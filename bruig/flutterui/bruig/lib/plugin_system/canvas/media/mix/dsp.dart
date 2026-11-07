import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/analysers.dart';
import 'package:bruig/plugin_system/canvas/media/mix/device_dsp.dart';
import 'package:bruig/plugin_system/canvas/media/mix/device_scope.dart';
import 'package:bruig/plugin_system/canvas/media/mix/pitch.dart';
import 'package:bruig/plugin_system/canvas/media/mix/split_dsp.dart';
import 'package:bruig/plugin_system/canvas/media/mix/vocoder.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/modulation.dart';

// dsp.dart is the arithmetic a mix is made of: filters, a compressor, a
// limiter, a channel strip, the master, and a loudness meter.
//
// It is the one definition of how a mix sounds: the editor plays through it
// and exports render with it, so the two cannot disagree.
//
// Pure Dart with no Flutter, so a render can run in an isolate. Every
// processor works on blocks of stereo audio (two Float32Lists) and keeps its
// state between blocks, so a sound processed in pieces matches one
// processed whole.

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

  /// source is the channel it listens to rather than its own sound (see
  /// Dynamics.sidechain), fed into [key] before each block.
  final String? source;
  final SideKey key = SideKey();

  /// reductionDb is how many decibels it is taking off now: its meter.
  double get reductionDb => _reduction;

  Compressor(this.d, {double sampleRate = 48000})
      : _attack = _coefficient(d.attackMs, sampleRate),
        _release = _coefficient(d.releaseMs, sampleRate),
        _makeup = dbToGain(d.totalMakeupDb),
        source = d.sidechain;

  void process(Float32List l, Float32List r, int n) {
    var wet = d.mix.clamp(0.0, 1.0);
    for (var i = 0; i < n; i++) {
      var peak = key.level(i, math.max(l[i].abs(), r[i].abs()));
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
    key.done(n);
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

  /// least is the lowest gain of the last block: how far it turned the
  /// sound down, one for not at all.
  double least = 1;

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
        _peaks =
            Float32List(math.max(1, (aheadMs / 1000 * sampleRate).round()));

  void process(Float32List l, Float32List r, int n) {
    least = 1;
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
      if (_gain < least) least = _gain;
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

/// StripProcessor is a channel strip: its devices, EQ and compressor in the
/// order set, then the fader and balance. A muted strip is silent.
class StripProcessor {
  ChannelMix _mix;
  final EqProcessor _eq;
  final Compressor? _comp;

  /// _chain is a processor for each of the channel's devices, in order,
  /// null for one switched off.
  final List<DeviceProcessor?> _chain;

  /// _gl and _gr are the levels the last block ended on (see [level]).
  double _gl, _gr;

  /// _clock is how many seconds the strip has run, for its LFOs; carried
  /// on when the strip is rebuilt, so they do not jump.
  double _clock = 0;

  /// _moved are the devices, by place, an LFO moved on the last block: let
  /// go of, each goes back to where it is set. _movedInner likewise, for
  /// devices in a split's branches: (split's place, branch, place in it).
  Set<int> _moved = {};
  Set<(int, int, int)> _movedInner = {};

  /// tapping is whether shape notes [taps]: on while a chain's meters
  /// between devices are on screen, as measuring costs a pass per step.
  bool tapping = false;

  /// taps are the peaks, left and right, at each step of the last block's
  /// shape: coming in, after each device in order (an off or a listening
  /// device passes it on as it was), then after the EQ and the compressor
  /// in the order they ran. Empty when not [tapping], or muted.
  List<(double, double)> taps = const [];

  /// scopes are the devices of its chain, by step (a device's id, or the
  /// EQ's or compressor's), whose sound in and out is kept for their
  /// screens: see device_scope.dart. Set by its graph each block.
  Map<String, DeviceScope> scopes = const {};

  /// listenAt, set, is the step of its chain heard in place of its end: the
  /// sound coming in (nought), or after that many steps -- the prototype's
  /// "Listen from here". Set by its graph each block.
  int? listenAt;
  Float32List _heardL = Float32List(0), _heardR = Float32List(0);
  final SideRunner _sides = SideRunner();

  /// StripProcessor runs [mix]. With [carry], the strip it replaces, a
  /// device of the same id, kind and source keeps running -- so a chain put
  /// in another order keeps its delays' and reverbs' tails.
  StripProcessor(ChannelMix mix, {StripProcessor? carry})
      : _mix = mix,
        _eq = EqProcessor(mix.eq),
        _comp = mix.comp.on ? Compressor(mix.comp) : null,
        _chain = [
          for (var (i, d) in mix.devices.indexed)
            _carried(carry, deviceIdAt(mix.devices, i), d) ??
                DeviceProcessor.of(d)
        ],
        _gl = mix.gains.$1,
        _gr = mix.gains.$2 {
    tapping = carry?.tapping ?? false;
    _clock = carry?._clock ?? 0;
  }

  static DeviceProcessor? _carried(
      StripProcessor? was, String id, MixDevice now) {
    if (was == null || !now.on) return null;
    var j = deviceIndexOf(was._mix.devices, id);
    if (j < 0 || j >= was._chain.length) return null;
    var then = was._mix.devices[j], running = was._chain[j];
    if (running == null || !then.on || then.kind != now.kind) return null;
    if (then.source != now.source) return null;
    if (then == now) {
      // Set again as it is: an LFO may have left it somewhere else.
      if (running is Tunable) (running as Tunable).tune(now);
      return running;
    }
    if (running is Tunable) {
      (running as Tunable).tune(now);
      return running;
    }
    return null;
  }

  ChannelMix get mix => _mix;

  /// devices are the channel's running devices, for a tuner's reading.
  List<DeviceProcessor> get devices => [
        for (var d in _chain)
          if (d != null) d,
      ];

  Compressor? get compressor => _comp;

  /// retune takes [next], a channel differing only in levels, sends and
  /// device settings, without resetting state. A changed device is tuned in
  /// place where it is [Tunable], otherwise rebuilt.
  void retune(ChannelMix next) {
    for (var i = 0; i < _chain.length && i < next.devices.length; i++) {
      var was = _mix.devices[i], now = next.devices[i];
      if (was == now) continue;
      var running = _chain[i];
      if (running is Tunable && now.on && was.kind == now.kind) {
        (running as Tunable).tune(now);
      } else {
        _chain[i] = DeviceProcessor.of(now);
      }
    }
    _mix = next;
  }

  void process(Float32List l, Float32List r, int n) {
    shape(l, r, n);
    level(l, r, n);
  }

  /// shape is the strip before its fader, where a pre-fader send is taken.
  /// A muted strip still runs its chain -- its meters between devices show
  /// the sound going through, as Ken expects -- and is silenced at its
  /// fader (see level), its sends too (MixGraph._send).
  void shape(Float32List l, Float32List r, int n) {
    // Moved by its modulators every so often within the block, so a knob
    // they turn glides rather than steps; all at once with none.
    var every = _modulating ? modulationStep : n;
    List<(double, double)>? taps;
    for (var at = 0; at < n; at += every) {
      var m = math.min(every, n - at);
      var bl = m == n ? l : Float32List.sublistView(l, at, at + m);
      var br = m == n ? r : Float32List.sublistView(r, at, at + m);
      _modulate();
      _clock += m / mixRate;
      var part = _run(bl, br, m);
      taps = taps == null || part == null
          ? part
          : [
              for (var (i, (pl, pr)) in part.indexed)
                (math.max(pl, taps[i].$1), math.max(pr, taps[i].$2)),
            ];
    }
    this.taps = taps ?? const [];
  }

  /// _modulating is whether any of its modulators moves anything.
  bool get _modulating =>
      _mix.devices.any((d) => d.on && d.kind.modulates && d.mods.isNotEmpty);

  /// _run runs [l] and [r] through the chain, in the order it was arranged
  /// in: the EQ and the compressor among the devices wherever they were
  /// put (see ChannelMix.chain). The peaks between each step, when tapping.
  List<(double, double)>? _run(Float32List l, Float32List r, int n) {
    var taps = tapping ? <(double, double)>[blockPeaks(l, r, n)] : null;
    var listen = listenAt;
    var kept = false;
    void keep() {
      if (_heardL.length < n) {
        _heardL = Float32List(n);
        _heardR = Float32List(n);
      }
      _heardL.setRange(0, n, l);
      _heardR.setRange(0, n, r);
      kept = true;
    }

    if (listen == 0) keep();
    var at = 0;
    for (var step in _mix.chain) {
      var scope = scopes.isEmpty ? null : scopes[step];
      scope?.before(l, r, n);
      Object? ran;
      if (step == chainEq) {
        _eq.process(l, r, n);
      } else if (step == chainComp) {
        ran = _comp;
        _comp?.process(l, r, n);
      } else {
        var i = deviceIndexOf(_mix.devices, step);
        if (i >= 0 && i < _chain.length) {
          ran = _chain[i];
          if (_chain[i] case var p?) {
            _sides.run(p, _mix.devices[i], l, r, n);
          }
        }
      }
      scope?.after(l, r, n, ran);
      taps?.add(blockPeaks(l, r, n));
      if (listen == ++at) keep();
    }
    // Heard from where it was listened to: what the rest did is not.
    if (kept) {
      l.setRange(0, n, _heardL);
      r.setRange(0, n, _heardR);
    }
    return taps;
  }

  /// _modulate turns the knobs the strip's LFOs move, for this block: each
  /// moved device set to where it is plus what every LFO on it adds (see
  /// modulation.dart), in place, keeping its state. One no longer moved
  /// goes back to where it is set.
  void _modulate() {
    var adds = <int, Map<String, double>>{};
    var inner = <(int, int, int), Map<String, double>>{};
    for (var (at, d) in _mix.devices.indexed) {
      if (!d.on || d.mods.isEmpty) continue;
      double Function(ModTarget) v;
      if (d.kind == DeviceKind.lfo) {
        var now = lfoValue(d.value("shape").round(),
            d.value("rate") * _clock + d.value("phase"));
        v = (_) => now;
      } else if (d.kind == DeviceKind.follower &&
          at < _chain.length &&
          _chain[at] is Follower) {
        // As loud as it heard on the last block.
        var now = (_chain[at] as Follower).level;
        v = (_) => now;
      } else if (d.kind == DeviceKind.macro) {
        // Each its own knob's way, nought to all the way (twice the half
        // travel an LFO swings).
        v = (t) => macroValue(d.value, t.from) * 2;
      } else {
        continue;
      }
      for (var t in d.mods) {
        // A device in a split's branch.
        if (branchDevicePath(t.device) case (var split, var b, var id)) {
          var i = deviceIndexOf(_mix.devices, split);
          if (i < 0 || i >= _chain.length || _chain[i] is! SplitProcessor) {
            continue;
          }
          var branches = _mix.devices[i].branches;
          if (b < 0 || b >= branches.length) continue;
          var j = deviceIndexOf(branches[b].devices, id);
          if (j < 0) continue;
          if (!branches[b].devices[j].kind.params.any((p) => p.id == t.param)) {
            continue;
          }
          var add = inner[(i, b, j)] ??= {};
          add[t.param] = (add[t.param] ?? 0) + t.depth * v(t);
          continue;
        }
        var i = deviceIndexOf(_mix.devices, t.device);
        if (i < 0 || i >= _chain.length) continue;
        if (!_mix.devices[i].kind.params.any((p) => p.id == t.param)) continue;
        var add = adds[i] ??= {};
        add[t.param] = (add[t.param] ?? 0) + t.depth * v(t);
      }
    }
    // Those in branches: let go of, set back; moved, set where moved.
    for (var (i, b, j) in _movedInner.difference(inner.keys.toSet())) {
      if (i >= _chain.length) continue;
      if (_chain[i] case SplitProcessor split) {
        if (split.specOf(b, j) case var spec?) split.tuneInner(b, j, spec);
      }
    }
    for (var MapEntry(key: (i, b, j), value: add) in inner.entries) {
      var split = _chain[i] as SplitProcessor;
      var spec = split.specOf(b, j);
      if (spec == null || !spec.on) continue;
      var next = spec;
      for (var MapEntry(key: id, value: by) in add.entries) {
        next = next.withValue(
            id, modulated(spec.kind.param(id), spec.value(id), by));
      }
      split.tuneInner(b, j, next);
    }
    _movedInner = inner.keys.toSet();
    for (var i in _moved.difference(adds.keys.toSet())) {
      if (i >= _chain.length) continue;
      if (_chain[i] case Tunable running) running.tune(_mix.devices[i]);
    }
    for (var MapEntry(key: i, value: add) in adds.entries) {
      var target = _mix.devices[i];
      if (_chain[i] case Tunable running when target.on) {
        var next = target;
        for (var MapEntry(key: id, value: by) in add.entries) {
          next = next.withValue(
              id, modulated(target.kind.param(id), target.value(id), by));
        }
        running.tune(next);
      }
    }
    _moved = adds.keys.toSet();
  }

  /// level is the fader and balance, ramped from the last block's over this
  /// one so a level moved by automation does not click.
  void level(Float32List l, Float32List r, int n) {
    if (_mix.mute) {
      l.fillRange(0, n, 0);
      r.fillRange(0, n, 0);
      return;
    }
    var (gl, gr) = _mix.gains;
    if (gl == _gl && gr == _gr) {
      if (gl != 1 || gr != 1) _scale(l, r, n, gl, gr);
      return;
    }
    var dl = (gl - _gl) / n, dr = (gr - _gr) / n;
    for (var i = 0; i < n; i++) {
      l[i] *= _gl + dl * (i + 1);
      r[i] *= _gr + dr * (i + 1);
    }
    _gl = gl;
    _gr = gr;
  }
}

/// modulationStep is how many samples apart a strip's modulators move the
/// knobs they turn: a millisecond and a third, too fine to hear as steps.
const int modulationStep = 64;

/// blockPeaks is the loudest sample of each side of a block, nought to one.
(double, double) blockPeaks(Float32List l, Float32List r, int n) {
  var pl = 0.0, pr = 0.0;
  for (var i = 0; i < n; i++) {
    var a = l[i].abs(), b = r[i].abs();
    if (a > pl) pl = a;
    if (b > pr) pr = b;
  }
  return (math.min(pl, 1.0), math.min(pr, 1.0));
}

/// SideRunner runs a device on the whole sound, or -- its Works on set to
/// Mid or Side, as the prototype's -- on only its middle (what both sides
/// share) or only its sides (where they differ), the rest passing by.
class SideRunner {
  Float32List _a = Float32List(0), _b = Float32List(0), _rest = Float32List(0);

  void run(
      DeviceProcessor p, MixDevice d, Float32List l, Float32List r, int n) {
    var mode = d.kind.worksOnSides ? d.value("stereo").round() : 0;
    if (mode == 0) {
      p.process(l, r, n);
      return;
    }
    if (_a.length < n) {
      _a = Float32List(n);
      _b = Float32List(n);
      _rest = Float32List(n);
    }
    for (var i = 0; i < n; i++) {
      var mid = (l[i] + r[i]) * 0.5, side = (l[i] - r[i]) * 0.5;
      var worked = mode == 1 ? mid : side;
      _a[i] = worked;
      _b[i] = worked;
      _rest[i] = mode == 1 ? side : mid;
    }
    p.process(_a, _b, n);
    for (var i = 0; i < n; i++) {
      var worked = (_a[i] + _b[i]) * 0.5;
      var mid = mode == 1 ? worked : _rest[i];
      var side = mode == 1 ? _rest[i] : worked;
      l[i] = mid + side;
      r[i] = mid - side;
    }
  }
}

/// Tunable is a device that takes new settings without losing its state (a
/// delay line, a reverb's tail, an LFO's phase).
abstract class Tunable {
  void tune(MixDevice device);
}

/// Sidechained is a device that hears a second channel: [feed] is given
/// that channel's pre-strip input before each block is processed.
abstract class Sidechained implements DeviceProcessor {
  String? get source;
  void feed(Float32List l, Float32List r, int n);
}

/// SideKey is what a gate or compressor listens to in place of its own
/// sound: another channel's loudest side, sample by sample, for the block
/// about to be processed. Not fed -- the channel gone -- it is not [fed],
/// and the device listens to its own sound.
class SideKey {
  Float32List _peaks = Float32List(0);
  bool _fed = false;

  /// _at and _length are where in the block fed it is read from, and how
  /// long that block is: a strip whose modulators move its knobs runs its
  /// chain a short stretch at a time (see StripProcessor.shape), each
  /// stretch reading on from the last.
  int _at = 0, _length = 0;

  bool get fed => _fed;

  void feed(Float32List l, Float32List r, int n) {
    if (_peaks.length < n) _peaks = Float32List(n);
    for (var i = 0; i < n; i++) {
      _peaks[i] = math.max(l[i].abs(), r[i].abs());
    }
    _fed = true;
    _at = 0;
    _length = n;
  }

  /// silence is a channel that is there with nothing on it this block.
  void silence(int n) {
    if (_peaks.length < n) _peaks = Float32List(n);
    _peaks.fillRange(0, n, 0);
    _fed = true;
    _at = 0;
    _length = n;
  }

  /// level is the key's peak at sample [i] of the stretch being run, or
  /// [own] where it is not fed.
  double level(int i, double own) =>
      _fed && _at + i < _length ? _peaks[_at + i] : own;

  /// done is a stretch of [n] run: the next reads on from it, and with the
  /// block it was fed run out, the next block is listened to afresh.
  void done(int n) {
    _at += n;
    if (_at >= _length) _fed = false;
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
      DeviceKind.gate => Gate(device),
      DeviceKind.autoFilter => AutoFilter(device),
      DeviceKind.chorus => Chorus(device),
      DeviceKind.flanger => Flanger(device),
      DeviceKind.phaser => Phaser(device),
      DeviceKind.autoPan => AutoPan(device),
      DeviceKind.saturator => Saturator(device),
      DeviceKind.overdrive => Overdrive(device),
      DeviceKind.bitCrusher => BitCrusher(device),
      DeviceKind.utility => Utility(device),
      DeviceKind.autoTune => AutoTune(device),
      DeviceKind.vocoder => Vocoder(device),
      DeviceKind.tuner => PitchListener(pitch: true),
      DeviceKind.spectrum => PitchListener(),
      // The latest of the sound, for the Scope over its Time and the
      // Stereo Image over 20ms; a loudness meter.
      DeviceKind.scope =>
        WaveTap(DeviceKind.scope, frames: WaveTap.framesOf(device)),
      DeviceKind.stereoImage =>
        WaveTap(DeviceKind.stereoImage, frames: 1024, points: 1024),
      DeviceKind.loudness => LoudnessTap(),
      // It makes no sound: it moves other devices' knobs (see shape).
      DeviceKind.lfo => null,
      DeviceKind.follower => Follower(device),
      // Knobs only: what it turns, it turns (see shape).
      DeviceKind.macro => null,
      DeviceKind.split => SplitProcessor(device),
    };
  }
}

/// Reverb is Freeverb (Jezar's public-domain design: eight damped combs and
/// four allpasses a side, the right's delays a little longer for width),
/// scaled to 48kHz, with a pre-delay in front.
class Reverb implements DeviceProcessor, Tunable {
  static const _combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617];
  static const _allpasses = [556, 441, 341, 225];
  static const _spread = 23;

  final double _rate;
  late double _feedback, _damp, _wet1, _wet2, _dry, _wet;
  final List<_Comb> _cl, _cr;
  final List<_Allpass> _al, _ar;

  /// _preL and _preR are as long as the longest pre-delay and read [_pre]
  /// behind the write point, so changing the pre-delay reallocates nothing.
  final Float32List _preL, _preR;
  int _preAt = 0, _pre = 0;

  Reverb(MixDevice d, {double sampleRate = 48000})
      : _rate = sampleRate,
        _cl = [for (var c in _combs) _Comb(_scaled(c, sampleRate))],
        _cr = [for (var c in _combs) _Comb(_scaled(c + _spread, sampleRate))],
        _al = [for (var a in _allpasses) _Allpass(_scaled(a, sampleRate))],
        _ar = [
          for (var a in _allpasses) _Allpass(_scaled(a + _spread, sampleRate))
        ],
        _preL = Float32List(_longest(d, sampleRate)),
        _preR = Float32List(_longest(d, sampleRate)) {
    tune(d);
  }

  static int _longest(MixDevice d, double rate) =>
      (d.kind.param("predelay").max / 1000 * rate).ceil() + 1;

  @override
  void tune(MixDevice d) {
    _feedback = d.value("size") * 0.28 + 0.7;
    _damp = d.value("damping") * 0.4;
    _wet = d.value("mix");
    _dry = 1 - d.value("mix");
    _wet1 = d.value("width") / 2 + 0.5;
    _wet2 = (1 - d.value("width")) / 2;
    _pre =
        (d.value("predelay") / 1000 * _rate).round().clamp(0, _preL.length - 1);
  }

  static int _scaled(int samples, double rate) =>
      (samples * rate / 44100).round();

  @override
  void process(Float32List l, Float32List r, int n) {
    var size = _preL.length;
    for (var i = 0; i < n; i++) {
      _preL[_preAt] = l[i];
      _preR[_preAt] = r[i];
      var back = (_preAt - _pre + size) % size;
      var inL = _preL[back], inR = _preR[back];
      _preAt = (_preAt + 1) % size;
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

/// Delay is an echo fed back through a low-pass, so each repeat is quieter
/// and darker; with ping-pong, each repeat crosses to the other side.
class Delay implements DeviceProcessor, Tunable {
  /// _l and _r are as long as the longest time and read [_time] behind the
  /// write point. A changed time glides there, as a tape delay's does.
  final Float32List _l, _r;
  final double _rate;
  late double _feedback, _wet, _dry, _cross, _lp, _to;
  double _time = 0;
  double _fl = 0, _fr = 0;
  int _at = 0;

  Delay(MixDevice d, {double sampleRate = 48000})
      : _rate = sampleRate,
        _l = Float32List(_longest(d, sampleRate)),
        _r = Float32List(_longest(d, sampleRate)) {
    tune(d);
    _time = _to;
  }

  static int _longest(MixDevice d, double rate) =>
      (d.kind.param("time").max / 1000 * rate).ceil() + 2;

  @override
  void tune(MixDevice d) {
    _feedback = d.value("feedback");
    _wet = d.value("mix");
    _dry = 1 - d.value("mix");
    _cross = d.value("pingpong");
    _lp = 1 - math.exp(-2 * math.pi * d.value("tone") / _rate);
    _to = (d.value("time") / 1000 * _rate).clamp(1.0, _l.length - 2.0);
  }

  double _read(Float32List x, double back) {
    var size = x.length;
    var pos = _at - back;
    if (pos < 0) pos += size;
    var i = pos.floor(), f = pos - i;
    var a = x[i % size], b = x[(i + 1) % size];
    return a + (b - a) * f;
  }

  @override
  void process(Float32List l, Float32List r, int n) {
    for (var i = 0; i < n; i++) {
      if (_time != _to) {
        // A time constant of about 40ms.
        _time += (_to - _time) * 0.0005;
        if ((_to - _time).abs() < 0.01) _time = _to;
      }
      var dl = _read(_l, _time), dr = _read(_r, _time);
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

  /// _devices are the master's own, by place among its devices: null for
  /// one that is off or only listens.
  final List<DeviceProcessor?> _devices;
  List<DeviceProcessor> get devices => [
        for (var d in _devices)
          if (d != null) d,
      ];

  /// normaliseDb is the gain that brings the mix to its loudness target,
  /// measured on a first pass; 0 until then.
  double normaliseDb;

  /// tapping is whether process notes [taps]: on while the master's
  /// devices are on screen, as a channel strip's are (StripProcessor.taps).
  bool tapping = false;

  /// taps are the peaks coming in and after each step of its chain, in the
  /// order it ran, on the last block. Empty when not [tapping].
  List<(double, double)> taps = const [];

  /// scopes are as a strip's (StripProcessor.scopes).
  Map<String, DeviceScope> scopes = const {};
  final SideRunner _sides = SideRunner();

  MasterProcessor(this.mix, {this.normaliseDb = 0})
      : _eq = EqProcessor(mix.eq),
        _glue = mix.comp.on ? Compressor(mix.comp) : null,
        _limiter = mix.limiter
            ? Limiter(mix.ceilingDb,
                aheadMs: mix.limiterAheadMs, releaseMs: mix.limiterReleaseMs)
            : null,
        _devices = [for (var d in mix.devices) DeviceProcessor.of(d)];

  /// process runs the master on a block, the limiter only when [limit]. The
  /// measuring pass leaves it out, as a loudness normaliser measures.
  void process(Float32List l, Float32List r, int n, {bool limit = true}) {
    // In the order it was arranged in (see MasterMix.chain); the limiter
    // last, always.
    var taps = tapping ? <(double, double)>[blockPeaks(l, r, n)] : null;
    for (var step in mix.chain) {
      var scope = scopes.isEmpty ? null : scopes[step];
      scope?.before(l, r, n);
      Object? ran;
      if (step == chainEq) {
        _eq.process(l, r, n);
      } else if (step == chainComp) {
        ran = _glue;
        _glue?.process(l, r, n);
      } else {
        var i = deviceIndexOf(mix.devices, step);
        if (i >= 0 && i < _devices.length) {
          ran = _devices[i];
          if (_devices[i] case var p?) _sides.run(p, mix.devices[i], l, r, n);
        }
      }
      scope?.after(l, r, n, ran);
      taps?.add(blockPeaks(l, r, n));
    }
    this.taps = taps ?? const [];
    var g = dbToGain(mix.gainDb + normaliseDb);
    if (g != 1) _scale(l, r, n, g, g);
    if (limit) _limiter?.process(l, r, n);
  }

  /// limited is the least gain its limiter set on the last block: one for
  /// none, or no limiter.
  double get limited => _limiter?.least ?? 1;
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

  /// momentary and shortTerm are the loudness of the last 400ms and the
  /// last three seconds, ungated, as a meter shows them.
  double get momentary => _over(4);
  double get shortTerm => _over(30);

  double _over(int steps) {
    if (_steps.isEmpty) return -double.infinity;
    var from = math.max(0, _steps.length - steps);
    var sum = 0.0;
    for (var i = from; i < _steps.length; i++) {
      sum += _steps[i];
    }
    return _lufs(sum / (_steps.length - from));
  }

  /// reset starts it again: nothing measured.
  void reset() {
    _steps.clear();
    _sum = 0;
    _count = 0;
  }

  /// _gated is the gated loudness of [steps], 100ms powers.
  static double _gated(List<double> steps) {
    var blocks = <double>[
      for (var i = 0; i + 4 <= steps.length; i++)
        (steps[i] + steps[i + 1] + steps[i + 2] + steps[i + 3]) / 4,
    ];
    var loud = [
      for (var b in blocks)
        if (_lufs(b) > -70) b
    ];
    if (loud.isEmpty) return -double.infinity;
    var mean = loud.reduce((a, b) => a + b) / loud.length;
    var gate = _lufs(mean) - 10;
    var kept = [
      for (var b in loud)
        if (_lufs(b) > gate) b
    ];
    if (kept.isEmpty) return -double.infinity;
    return _lufs(kept.reduce((a, b) => a + b) / kept.length);
  }
}

/// SpeakerLoudness is LoudnessMeter over every speaker of a surround mix,
/// each weighted as BS.1770 says ([weights]: surrounds +1.5dB, LFE 0).
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
