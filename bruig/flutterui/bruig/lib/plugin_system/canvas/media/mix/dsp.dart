import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';

// dsp.dart is the arithmetic a mix is made of: filters, a compressor, a
// limiter, a channel strip, the master, and a loudness meter.
//
// It is the one definition of how a mix sounds. The editor plays through it
// and an export is rendered by it, so the two cannot disagree -- before this
// a mix was played by SoLoud's filters and exported by ffmpeg's, which were
// each made to follow mix.dart and each got there their own way.
//
// Pure Dart with no Flutter in it, so a render can run in an isolate. Every
// processor works on blocks of stereo audio held as two Float32Lists, left and
// right, and keeps its state between blocks, so a sound processed in pieces
// is the same as one processed whole.

/// mixRate is the sample rate everything is mixed at.
const int mixRate = 48000;

/// Biquad is one second-order filter section, run on both sides.
class Biquad {
  final double b0, b1, b2, a1, a2;
  // Transposed direct form II: two state values a side.
  double _l1 = 0, _l2 = 0, _r1 = 0, _r2 = 0;

  Biquad(List<double> c)
      : b0 = c[0],
        b1 = c[1],
        b2 = c[2],
        a1 = c[3],
        a2 = c[4];

  void process(Float32List l, Float32List r, int n) {
    for (var i = 0; i < n; i++) {
      var x = l[i];
      var y = b0 * x + _l1;
      _l1 = b1 * x - a1 * y + _l2;
      _l2 = b2 * x - a2 * y;
      l[i] = y;
      x = r[i];
      y = b0 * x + _r1;
      _r1 = b1 * x - a1 * y + _r2;
      _r2 = b2 * x - a2 * y;
      r[i] = y;
    }
  }
}

/// EqProcessor is an Eq: its sections in turn, then its overall gain.
class EqProcessor {
  final List<Biquad> _sections;
  final double _gain;

  EqProcessor(Eq eq, {double sampleRate = 48000})
      : _sections = [for (var c in eqBiquads(eq, sampleRate)) Biquad(c)],
        _gain = eq.on ? dbToGain(eq.gainDb) : 1;

  void process(Float32List l, Float32List r, int n) {
    for (var s in _sections) {
      s.process(l, r, n);
    }
    if (_gain != 1) _scale(l, r, n, _gain, _gain);
  }
}

/// Compressor is a Dynamics: a peak detector across both sides (so the
/// stereo picture does not wander), the static curve of
/// [Dynamics.reducedDb], smoothed by the attack and release in decibels,
/// then the makeup and the dry/wet mix.
class Compressor {
  final Dynamics d;
  final double _attack, _release, _makeup;
  double _reduction = 0;

  Compressor(this.d, {double sampleRate = 48000})
      : _attack = _coefficient(d.attackMs, sampleRate),
        _release = _coefficient(d.releaseMs, sampleRate),
        _makeup = dbToGain(d.totalMakeupDb);

  /// reductionDb is how far it is turning down now, for a meter.
  double get reductionDb => _reduction;

  void process(Float32List l, Float32List r, int n) {
    var wet = d.mix.clamp(0.0, 1.0);
    for (var i = 0; i < n; i++) {
      var peak = math.max(l[i].abs(), r[i].abs());
      var level = peak <= 1e-9 ? -180.0 : 20 * math.log(peak) / math.ln10;
      var want = level - d.reducedDb(level);
      // Down quickly, back slowly: the attack when it has to turn down
      // more, the release when less.
      var k = want > _reduction ? _attack : _release;
      _reduction = want + k * (_reduction - want);
      var g = dbToGain(-_reduction) * _makeup;
      var gain = wet * g + (1 - wet);
      l[i] *= gain;
      r[i] *= gain;
    }
  }
}

/// Limiter holds every peak under its ceiling: it looks a few milliseconds
/// ahead, so the turn-down is under way before the peak arrives rather than
/// clipping its front, and lets go over the release.
class Limiter {
  final double ceiling;
  final int _ahead;
  final double _attack, _release;
  final Float32List _dl, _dr, _peaks;
  int _at = 0;
  double _gain = 1;

  Limiter(double ceilingDb,
      {double sampleRate = 48000, double aheadMs = 5, double releaseMs = 50})
      : ceiling = dbToGain(ceilingDb),
        _ahead = math.max(1, (aheadMs / 1000 * sampleRate).round()),
        // A quarter of the lookahead: all but settled by the time the peak
        // that asked for it is heard.
        _attack = _coefficient(aheadMs / 4, sampleRate),
        _release = _coefficient(releaseMs, sampleRate),
        _dl = Float32List(math.max(1, (aheadMs / 1000 * sampleRate).round())),
        _dr = Float32List(math.max(1, (aheadMs / 1000 * sampleRate).round())),
        _peaks = Float32List(math.max(1, (aheadMs / 1000 * sampleRate).round()));

  void process(Float32List l, Float32List r, int n) {
    for (var i = 0; i < n; i++) {
      // What comes in now is heard [_ahead] samples later; the gain is
      // worked out from the loudest of everything in that window.
      _peaks[_at] = math.max(l[i].abs(), r[i].abs());
      var loudest = 0.0;
      for (var p in _peaks) {
        if (p > loudest) loudest = p;
      }
      var want = loudest > ceiling ? ceiling / loudest : 1.0;
      _gain = want + (want < _gain ? _attack : _release) * (_gain - want);
      var outL = _dl[_at], outR = _dr[_at];
      _dl[_at] = l[i];
      _dr[_at] = r[i];
      _at = (_at + 1) % _ahead;
      // A last guard: nothing leaves above the ceiling.
      l[i] = (outL * _gain).clamp(-ceiling, ceiling);
      r[i] = (outR * _gain).clamp(-ceiling, ceiling);
    }
  }
}

/// StripProcessor is a channel strip: EQ and compressor in the order set,
/// then the fader and balance. A muted strip is silent.
class StripProcessor {
  final ChannelMix mix;
  final EqProcessor _eq;
  final Compressor? _comp;

  StripProcessor(this.mix)
      : _eq = EqProcessor(mix.eq),
        _comp = mix.comp.on ? Compressor(mix.comp) : null;

  Compressor? get compressor => _comp;

  void process(Float32List l, Float32List r, int n) {
    shape(l, r, n);
    level(l, r, n);
  }

  /// shape is the strip before its fader: the EQ and the compressor, in
  /// the order set -- where a pre-fader send is taken. A muted strip is
  /// silent from here on, sends included.
  void shape(Float32List l, Float32List r, int n) {
    if (mix.mute) {
      l.fillRange(0, n, 0);
      r.fillRange(0, n, 0);
      return;
    }
    if (mix.compFirst) {
      _comp?.process(l, r, n);
      _eq.process(l, r, n);
    } else {
      _eq.process(l, r, n);
      _comp?.process(l, r, n);
    }
  }

  /// level is the fader and the balance.
  void level(Float32List l, Float32List r, int n) {
    if (mix.mute) return;
    var (gl, gr) = mix.gains;
    if (gl != 1 || gr != 1) _scale(l, r, n, gl, gr);
  }
}

/// DeviceProcessor is a device of a chain, running.
abstract class DeviceProcessor {
  void process(Float32List l, Float32List r, int n);

  /// of is [device] as a processor, or null for one switched off.
  static DeviceProcessor? of(MixDevice device) {
    if (!device.on) return null;
    return switch (device.kind) {
      DeviceKind.reverb => Reverb(device),
      DeviceKind.delay => Delay(device),
    };
  }
}

/// Reverb is Freeverb -- Jezar's public-domain design: eight parallel
/// damped comb filters and four allpasses a side, the right side's delays a
/// little longer than the left's for width -- tuned for 48kHz, with a
/// pre-delay in front.
class Reverb implements DeviceProcessor {
  static const _combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617];
  static const _allpasses = [556, 441, 341, 225];
  static const _spread = 23;

  final double _feedback, _damp, _wet1, _wet2, _dry, _wet;
  final List<_Comb> _cl, _cr;
  final List<_Allpass> _al, _ar;
  final Float32List _preL, _preR;
  int _preAt = 0;

  Reverb(MixDevice d, {double sampleRate = 48000})
      : _feedback = d.value("size") * 0.28 + 0.7,
        _damp = d.value("damping") * 0.4,
        _wet = d.value("mix"),
        _dry = 1 - d.value("mix"),
        _wet1 = d.value("width") / 2 + 0.5,
        _wet2 = (1 - d.value("width")) / 2,
        _cl = [for (var c in _combs) _Comb(_scaled(c, sampleRate))],
        _cr = [for (var c in _combs) _Comb(_scaled(c + _spread, sampleRate))],
        _al = [for (var a in _allpasses) _Allpass(_scaled(a, sampleRate))],
        _ar = [
          for (var a in _allpasses) _Allpass(_scaled(a + _spread, sampleRate))
        ],
        _preL = Float32List(
            math.max(1, (d.value("predelay") / 1000 * sampleRate).round())),
        _preR = Float32List(
            math.max(1, (d.value("predelay") / 1000 * sampleRate).round()));

  static int _scaled(int samples, double rate) =>
      (samples * rate / 44100).round();

  @override
  void process(Float32List l, Float32List r, int n) {
    for (var i = 0; i < n; i++) {
      var inL = _preL[_preAt], inR = _preR[_preAt];
      _preL[_preAt] = l[i];
      _preR[_preAt] = r[i];
      _preAt = (_preAt + 1) % _preL.length;
      // Freeverb's fixed input gain, so the tail sits near the level fed in.
      var input = (inL + inR) * 0.015;
      var outL = 0.0, outR = 0.0;
      for (var c in _cl) {
        outL += c.run(input, _feedback, _damp);
      }
      for (var c in _cr) {
        outR += c.run(input, _feedback, _damp);
      }
      for (var a in _al) {
        outL = a.run(outL);
      }
      for (var a in _ar) {
        outR = a.run(outR);
      }
      var wl = outL * _wet1 + outR * _wet2, wr = outR * _wet1 + outL * _wet2;
      // Freeverb's wet scale, three.
      l[i] = l[i] * _dry + wl * 3 * _wet;
      r[i] = r[i] * _dry + wr * 3 * _wet;
    }
  }
}

class _Comb {
  final Float32List _buffer;
  int _at = 0;
  double _store = 0;
  _Comb(int size) : _buffer = Float32List(size);

  double run(double input, double feedback, double damp) {
    var out = _buffer[_at];
    _store = out * (1 - damp) + _store * damp;
    _buffer[_at] = input + _store * feedback;
    if (++_at >= _buffer.length) _at = 0;
    return out;
  }
}

class _Allpass {
  final Float32List _buffer;
  int _at = 0;
  _Allpass(int size) : _buffer = Float32List(size);

  double run(double input) {
    var held = _buffer[_at];
    var out = -input + held;
    _buffer[_at] = input + held * 0.5;
    if (++_at >= _buffer.length) _at = 0;
    return out;
  }
}

/// Delay is an echo: each side delayed by the time, fed back by the
/// feedback through a low-pass, so each repeat is quieter and darker -- and
/// with ping-pong, each repeat crosses to the other side.
class Delay implements DeviceProcessor {
  final Float32List _l, _r;
  final double _feedback, _wet, _dry, _cross;
  final double _lp;
  double _fl = 0, _fr = 0;
  int _at = 0;

  Delay(MixDevice d, {double sampleRate = 48000})
      : _l = Float32List(
            math.max(1, (d.value("time") / 1000 * sampleRate).round())),
        _r = Float32List(
            math.max(1, (d.value("time") / 1000 * sampleRate).round())),
        _feedback = d.value("feedback"),
        _wet = d.value("mix"),
        _dry = 1 - d.value("mix"),
        _cross = d.value("pingpong"),
        _lp = 1 - math.exp(-2 * math.pi * d.value("tone") / sampleRate);

  @override
  void process(Float32List l, Float32List r, int n) {
    for (var i = 0; i < n; i++) {
      var dl = _l[_at], dr = _r[_at];
      _fl += _lp * (dl - _fl);
      _fr += _lp * (dr - _fr);
      // Ping-pong: each side's repeat fed into the other.
      var backL = _fl * (1 - _cross) + _fr * _cross;
      var backR = _fr * (1 - _cross) + _fl * _cross;
      _l[_at] = l[i] + backL * _feedback;
      _r[_at] = r[i] + backR * _feedback;
      if (++_at >= _l.length) _at = 0;
      l[i] = l[i] * _dry + dl * _wet;
      r[i] = r[i] * _dry + dr * _wet;
    }
  }
}

/// MasterProcessor is the master strip: EQ and glue in the order set, the
/// fader, a gain to bring the whole to its loudness target where one is
/// asked for, and the limiter last.
class MasterProcessor {
  final MasterMix mix;
  final EqProcessor _eq;
  final Compressor? _glue;
  final Limiter? _limiter;

  /// normaliseDb is the gain that brings the mix to its target: measured
  /// on a first pass, so it is not known until then. Nought until it is.
  double normaliseDb;

  MasterProcessor(this.mix, {this.normaliseDb = 0})
      : _eq = EqProcessor(mix.eq),
        _glue = mix.comp.on ? Compressor(mix.comp) : null,
        _limiter = mix.limiter ? Limiter(mix.ceilingDb) : null;

  /// process runs the master on a block, the limiter only when [limit].
  /// The first of two passes leaves it out: what is measured there is the
  /// mix before the limiter, as a loudness normaliser measures it.
  void process(Float32List l, Float32List r, int n, {bool limit = true}) {
    if (mix.compFirst) {
      _glue?.process(l, r, n);
      _eq.process(l, r, n);
    } else {
      _eq.process(l, r, n);
      _glue?.process(l, r, n);
    }
    var g = dbToGain(mix.gainDb + normaliseDb);
    if (g != 1) _scale(l, r, n, g, g);
    if (limit) _limiter?.process(l, r, n);
  }
}

/// LoudnessMeter is ITU-R BS.1770-4 integrated loudness, in LUFS: the sound
/// K-weighted, its power taken over 400ms blocks overlapping by three
/// quarters, and gated -- absolutely at −70 LUFS, then relatively at 10 LU
/// under the mean of what passed. The filter coefficients are the standard's
/// own, which are given for 48kHz: the rate everything is mixed at.
class LoudnessMeter {
  final _pre = Biquad(const [
    1.53512485958697,
    -2.69169618940638,
    1.19839281085285,
    -1.69065929318241,
    0.73248077421585,
  ]);
  final _rlb = Biquad(const [1, -2, 1, -1.99004745483398, 0.99007225036621]);

  static const int _step = mixRate ~/ 10; // 100ms: a quarter block
  final List<double> _steps = [];
  double _sum = 0;
  int _count = 0;
  Float32List _l = Float32List(0), _r = Float32List(0);

  void add(Float32List l, Float32List r, int n) {
    if (_l.length < n) {
      _l = Float32List(n);
      _r = Float32List(n);
    }
    _l.setRange(0, n, l);
    _r.setRange(0, n, r);
    _pre.process(_l, _r, n);
    _rlb.process(_l, _r, n);
    for (var i = 0; i < n; i++) {
      _sum += _l[i] * _l[i] + _r[i] * _r[i];
      if (++_count == _step) {
        _steps.add(_sum / _step);
        _sum = 0;
        _count = 0;
      }
    }
  }

  static double _lufs(double power) =>
      power <= 0 ? -double.infinity : -0.691 + 10 * math.log(power) / math.ln10;

  /// integrated is the loudness of everything added, or minus infinity for
  /// silence.
  double get integrated => _gated(_steps);

  /// _gated is the gated loudness of [steps], 100ms powers.
  static double _gated(List<double> steps) {
    var blocks = <double>[
      for (var i = 0; i + 4 <= steps.length; i++)
        (steps[i] + steps[i + 1] + steps[i + 2] + steps[i + 3]) / 4,
    ];
    var loud = [for (var b in blocks) if (_lufs(b) > -70) b];
    if (loud.isEmpty) return -double.infinity;
    var mean = loud.reduce((a, b) => a + b) / loud.length;
    var gate = _lufs(mean) - 10;
    var kept = [for (var b in loud) if (_lufs(b) > gate) b];
    if (kept.isEmpty) return -double.infinity;
    return _lufs(kept.reduce((a, b) => a + b) / kept.length);
  }
}

/// SpeakerLoudness is LoudnessMeter over every speaker of a surround mix:
/// each K-weighted, its power weighted as BS.1770 says -- the side and
/// rear speakers a decibel and a half more, the LFE not at all -- and the
/// whole gated in the same way.
class SpeakerLoudness {
  final List<double> weights;
  final List<(Biquad, Biquad)> _filters;
  final List<double> _steps = [];
  double _sum = 0;
  int _count = 0;
  List<Float32List> _work = const [];

  SpeakerLoudness(this.weights)
      : _filters = [
          for (var i = 0; i < (weights.length + 1) ~/ 2; i++)
            (
              Biquad(const [
                1.53512485958697,
                -2.69169618940638,
                1.19839281085285,
                -1.69065929318241,
                0.73248077421585,
              ]),
              Biquad(const [1, -2, 1, -1.99004745483398, 0.99007225036621]),
            ),
        ];

  /// add measures a block of every speaker, in the layout's order.
  void add(List<Float32List> speakers, int n) {
    var count = weights.length;
    if (_work.length < count + 1 || _work[0].length < n) {
      _work = [for (var i = 0; i <= count; i++) Float32List(n)];
    }
    for (var c = 0; c < count; c++) {
      _work[c].setRange(0, n, speakers[c]);
    }
    // An odd speaker out is filtered beside a silent one.
    if (count.isOdd) _work[count].fillRange(0, n, 0);
    for (var k = 0; k < _filters.length; k++) {
      var (pre, rlb) = _filters[k];
      pre.process(_work[2 * k], _work[2 * k + 1], n);
      rlb.process(_work[2 * k], _work[2 * k + 1], n);
    }
    for (var i = 0; i < n; i++) {
      for (var c = 0; c < count; c++) {
        var w = weights[c];
        if (w == 0) continue;
        _sum += w * _work[c][i] * _work[c][i];
      }
      if (++_count == LoudnessMeter._step) {
        _steps.add(_sum / LoudnessMeter._step);
        _sum = 0;
        _count = 0;
      }
    }
  }

  double get integrated => LoudnessMeter._gated(_steps);
}

/// lowPass is a Butterworth low-pass at [hz], as a Biquad's coefficients.
List<double> lowPass(double hz, {double sampleRate = 48000}) {
  var w = 2 * math.pi * hz / sampleRate;
  var alpha = math.sin(w) / (2 * math.sqrt1_2);
  var cos = math.cos(w);
  var a0 = 1 + alpha;
  return [
    (1 - cos) / 2 / a0,
    (1 - cos) / a0,
    (1 - cos) / 2 / a0,
    -2 * cos / a0,
    (1 - alpha) / a0,
  ];
}

void _scale(Float32List l, Float32List r, int n, double gl, double gr) {
  for (var i = 0; i < n; i++) {
    l[i] *= gl;
    r[i] *= gr;
  }
}

/// _coefficient is a one-pole smoother's that moves most of the way in [ms].
double _coefficient(double ms, double sampleRate) =>
    ms <= 0 ? 0 : math.exp(-1 / (ms / 1000 * sampleRate));
