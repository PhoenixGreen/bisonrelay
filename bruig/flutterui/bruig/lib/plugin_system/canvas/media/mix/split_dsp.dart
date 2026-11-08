import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart' show dbToGain;

// split_dsp.dart is a Split running: its sound into branches side by side,
// each through its own devices, and back together -- all of it into each
// (in parallel), its middle and its sides, its left and its right, or its
// lows and its highs (a Linkwitz-Riley crossover, which sums back flat).

/// highPass is a Butterworth high-pass at [hz], as a Biquad's coefficients.
List<double> highPass(double hz, {double sampleRate = 48000}) {
  var w = 2 * math.pi * hz / sampleRate;
  var alpha = math.sin(w) / (2 * math.sqrt1_2);
  var cos = math.cos(w);
  var a0 = 1 + alpha;
  return [
    (1 + cos) / 2 / a0,
    -(1 + cos) / a0,
    (1 + cos) / 2 / a0,
    -2 * cos / a0,
    (1 - alpha) / a0,
  ];
}

/// _Branch is one branch running: its devices, its level, its buffers.
class _Branch {
  SplitBranch spec;
  List<DeviceProcessor?> chain;
  Float32List l = Float32List(1024), r = Float32List(1024);

  /// _sides runs each device on what it works on, and its Out after it, as
  /// a chain's own devices are (SideRunner.run).
  final SideRunner _sides = SideRunner();

  _Branch(this.spec)
      : chain = [for (var d in spec.devices) DeviceProcessor.of(d)];

  void grow(int n) {
    if (l.length >= n) return;
    l = Float32List(n);
    r = Float32List(n);
  }

  void run(int n) {
    if (spec.mute) {
      l.fillRange(0, n, 0);
      r.fillRange(0, n, 0);
      return;
    }
    for (var (i, p) in chain.indexed) {
      if (p != null) _sides.run(p, spec.devices[i], l, r, n);
    }
    var g = dbToGain(spec.gainDb);
    if (g != 1) {
      for (var i = 0; i < n; i++) {
        l[i] *= g;
        r[i] *= g;
      }
    }
  }

  /// retune takes [next], of the same structure, without losing state.
  void retune(SplitBranch next) {
    for (var i = 0; i < chain.length && i < next.devices.length; i++) {
      var was = spec.devices[i], now = next.devices[i];
      if (was == now) continue;
      var running = chain[i];
      if (running is Tunable && now.on && was.kind == now.kind) {
        (running as Tunable).tune(now);
      } else {
        chain[i] = DeviceProcessor.of(now);
      }
    }
    spec = next;
  }
}

class SplitProcessor implements DeviceProcessor, Tunable {
  int? _mode;
  double? _crossover;
  List<_Branch> _branches = [];
  String _structure = "";

  /// The crossover: two Butterworth sections each way, for the lows and
  /// for the highs.
  List<Biquad> _lows = [], _highs = [];

  SplitProcessor(MixDevice d) {
    tune(d);
  }

  /// _count is how many branches it runs: two, but in parallel as many as
  /// it has (none passes the sound through as it was).
  int _count(MixDevice d) => _modeOf(d) == 0 ? d.branches.length : 2;

  static int _modeOf(MixDevice d) => d.value("mode").round();

  @override
  void tune(MixDevice d) {
    var mode = _modeOf(d);
    var specs = [
      for (var i = 0; i < _count(d); i++)
        i < d.branches.length ? d.branches[i] : const SplitBranch(),
    ];
    var structure = "$mode|${[for (var b in specs) b.structure].join("|")}";
    if (structure == _structure) {
      for (var (i, b) in _branches.indexed) {
        b.retune(specs[i]);
      }
    } else {
      _structure = structure;
      _branches = [for (var s in specs) _Branch(s)];
    }
    var crossover = d.value("crossover");
    if (mode != _mode || crossover != _crossover) {
      _lows = [Biquad(lowPass(crossover)), Biquad(lowPass(crossover))];
      _highs = [Biquad(highPass(crossover)), Biquad(highPass(crossover))];
    }
    _mode = mode;
    _crossover = crossover;
  }

  /// inner are its branches' running devices, for a sidechain to be fed:
  /// see MixGraph.finish.
  Iterable<DeviceProcessor> get inner => [
        for (var b in _branches)
          for (var p in b.chain)
            if (p != null) p,
      ];

  /// specOf is device [j] of branch [b] as it is set, or null.
  MixDevice? specOf(int b, int j) =>
      b < _branches.length && j < _branches[b].spec.devices.length
          ? _branches[b].spec.devices[j]
          : null;

  /// tuneInner sets device [j] of branch [b] to [d] in place, keeping its
  /// state: a modulator moving one of its knobs (see StripProcessor).
  void tuneInner(int b, int j, MixDevice d) {
    if (b >= _branches.length || j >= _branches[b].chain.length) return;
    if (_branches[b].chain[j] case Tunable running) running.tune(d);
  }

  @override
  void process(Float32List l, Float32List r, int n) {
    if (_branches.isEmpty) return;
    for (var b in _branches) {
      b.grow(n);
    }
    switch (_mode ?? 0) {
      case 1:
        // Its middle into the first, its sides into the second, each as a
        // mono pair; put back as left and right.
        var mid = _branches[0], side = _branches[1];
        for (var i = 0; i < n; i++) {
          var m = (l[i] + r[i]) / 2, s = (l[i] - r[i]) / 2;
          mid.l[i] = mid.r[i] = m;
          side.l[i] = side.r[i] = s;
        }
        mid.run(n);
        side.run(n);
        for (var i = 0; i < n; i++) {
          var m = (mid.l[i] + mid.r[i]) / 2, s = (side.l[i] + side.r[i]) / 2;
          l[i] = m + s;
          r[i] = m - s;
        }
      case 2:
        // Its left into the first, its right into the second.
        var left = _branches[0], right = _branches[1];
        for (var i = 0; i < n; i++) {
          left.l[i] = left.r[i] = l[i];
          right.l[i] = right.r[i] = r[i];
        }
        left.run(n);
        right.run(n);
        for (var i = 0; i < n; i++) {
          l[i] = (left.l[i] + left.r[i]) / 2;
          r[i] = (right.l[i] + right.r[i]) / 2;
        }
      case 3:
        // Its lows into the first, its highs into the second.
        var low = _branches[0], high = _branches[1];
        low.l.setRange(0, n, l);
        low.r.setRange(0, n, r);
        high.l.setRange(0, n, l);
        high.r.setRange(0, n, r);
        for (var f in _lows) {
          f.process(low.l, low.r, n);
        }
        for (var f in _highs) {
          f.process(high.l, high.r, n);
        }
        low.run(n);
        high.run(n);
        for (var i = 0; i < n; i++) {
          l[i] = low.l[i] + high.l[i];
          r[i] = low.r[i] + high.r[i];
        }
      default:
        // All of it into each, and the branches summed.
        for (var b in _branches) {
          b.l.setRange(0, n, l);
          b.r.setRange(0, n, r);
          b.run(n);
        }
        for (var i = 0; i < n; i++) {
          var sl = 0.0, sr = 0.0;
          for (var b in _branches) {
            sl += b.l[i];
            sr += b.r[i];
          }
          l[i] = sl;
          r[i] = sr;
        }
    }
  }
}
