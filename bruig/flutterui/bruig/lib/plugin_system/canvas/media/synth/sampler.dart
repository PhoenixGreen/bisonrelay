import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/media/synth/soundfont.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart'
    show InstrumentLook, MidiControl;
import 'package:bruig/plugin_system/canvas/model/instrument_shape.dart';

// sampler.dart plays notes: a bank's samples where there is a bank (see
// soundfont.dart), otherwise built-in piano, drum and plucked voices, so an
// instrument sounds the moment it is added -- each shaped as the
// instrument's InstrumentShape has it (instrument_shape.dart): its own
// volume envelope, a filter with an envelope, an LFO, one voice or many,
// gliding from note to note.
//
// Generator meanings, and the 0.4 scale on initial attenuation, follow
// FluidSynth, which MuseScore's bank was voiced for.

/// Voice is one note sounding.
abstract class Voice {
  final int key;

  /// released is set when the key is let go; the voice is [done] once its
  /// release has died away.
  bool released = false;
  bool done = false;

  /// pitch is the bend from the voice's key as a ratio (pitch bend plus mod
  /// wheel vibrato). Plucked and drum voices ignore it.
  double pitch = 1;

  /// heldAs is the key it answers to: [key], or where a legato note moved
  /// it. offset is how far it plays from [key] there, in semitones, and
  /// slide how far it still has to glide.
  int heldAs;
  double offset = 0, slide = 0;

  /// note is which note it was started for: a bank's note may be two
  /// voices, a side each.
  int note = 0;

  /// The instrument's own envelopes, where it has them, and its filter's
  /// state, a side each.
  _Adsr? _envelope, _filterEnvelope;
  double _l1 = 0, _l2 = 0, _r1 = 0, _r2 = 0;

  Voice(this.key) : heldAs = key;

  /// ending is whether its key is let go: it is dying away.
  bool get ending => released || (_envelope?.letGo ?? false);

  void release() => released = true;

  /// render adds the next [n] frames of the voice to [l] and [r].
  void render(Float32List l, Float32List r, int n);
}

double _seconds(int timecents) => math.pow(2, timecents / 1200).toDouble();

/// _SfVoice is a voice of a SoundFont zone.
class _SfVoice extends Voice {
  final Int16List data;
  final int end, loopStart, loopEnd;
  final bool loops, loopsUntilRelease;
  final double step;
  final double gainL, gainR;
  double _pos;

  // The volume envelope, in samples. Decay and release are per-sample
  // factors (a fall in decibels), the decay stopping at the sustain level.
  final int _delay, _attack, _hold;
  final double _decayFactor, _sustain, _releaseFactor;
  int _t = 0;
  double _level = 0;

  // The zone's low-pass, if any: one mono biquad.
  final List<double>? _f;
  double _x1 = 0, _x2 = 0, _y1 = 0, _y2 = 0;

  /// _enveloped is whether it keeps its zone's envelope: not where the
  /// instrument has one of its own.
  final bool _enveloped;

  _SfVoice(super.key, int velocity, Zone z, this.data, {bool enveloped = true})
      : _enveloped = enveloped,
        end = math.min(data.length - 1,
            z.sample.end + z[Gen.endOffset] + z[Gen.endCoarse] * 32768),
        loopStart = z.sample.loopStart +
            z[Gen.loopStartOffset] +
            z[Gen.loopStartCoarse] * 32768,
        loopEnd = z.sample.loopEnd +
            z[Gen.loopEndOffset] +
            z[Gen.loopEndCoarse] * 32768,
        loops = z[Gen.sampleModes] & 3 == 1,
        loopsUntilRelease = z[Gen.sampleModes] & 3 == 3,
        step = _step(z, key),
        gainL = _gain(z, velocity) *
            math.cos((z[Gen.pan].clamp(-500, 500) + 500) / 1000 * math.pi / 2),
        gainR = _gain(z, velocity) *
            math.sin((z[Gen.pan].clamp(-500, 500) + 500) / 1000 * math.pi / 2),
        _pos =
            (z.sample.start + z[Gen.startOffset] + z[Gen.startCoarse] * 32768)
                .toDouble(),
        _delay = (_seconds(z[Gen.delayVolEnv]) * mixRate).round(),
        _attack = (_seconds(z[Gen.attackVolEnv]) * mixRate).round(),
        _hold =
            (_seconds(z[Gen.holdVolEnv] + z[Gen.keyToVolEnvHold] * (60 - key)) *
                    mixRate)
                .round(),
        // Decay and release times are times to fall 100dB.
        _decayFactor = _fall(_seconds(
            z[Gen.decayVolEnv] + z[Gen.keyToVolEnvDecay] * (60 - key))),
        _sustain =
            math.pow(10, -z[Gen.sustainVolEnv].clamp(0, 1440) / 200).toDouble(),
        _releaseFactor = _fall(_seconds(z[Gen.releaseVolEnv])),
        _f = _filter(z, velocity);

  /// _fall is the per-sample factor that falls 100dB in [seconds].
  static double _fall(double seconds) =>
      math.pow(10, -100 / 20 / math.max(1, seconds * mixRate)).toDouble();

  static double _step(Zone z, int key) {
    var root = z[Gen.rootKey] >= 0 ? z[Gen.rootKey] : z.sample.originalKey;
    var cents = (key - root) * z[Gen.scaleTuning] +
        z[Gen.coarseTune] * 100 +
        z[Gen.fineTune] +
        z.sample.correction;
    return math.pow(2, cents / 1200) * z.sample.rate / mixRate;
  }

  /// _gain is the zone's level at [velocity]: its initial attenuation (times
  /// FluidSynth's 0.4) and the spec's default velocity modulator, which
  /// comes to velocity squared.
  static double _gain(Zone z, int velocity) {
    var cb = z[Gen.attenuation].clamp(0, 1440) * 0.4;
    var v = velocity.clamp(1, 127) / 127;
    return math.pow(10, -cb / 200) * v * v;
  }

  /// _filter is the zone's low-pass as biquad coefficients, or null for
  /// none. The default modulator lowers it by up to two octaves for a soft
  /// note.
  static List<double>? _filter(Zone z, int velocity) {
    var cents = z[Gen.filterFc] - 2400 * (1 - velocity.clamp(1, 127) / 127);
    if (cents >= 13500) return null;
    var hz = (8.176 * math.pow(2, cents / 1200)).clamp(20.0, 20000.0);
    var qDb = z[Gen.filterQ].clamp(0, 960) / 10;
    var q = math.max(0.5, math.pow(10, qDb / 20).toDouble() * math.sqrt1_2);
    var w = 2 * math.pi * hz / mixRate;
    var alpha = math.sin(w) / (2 * q);
    var cos = math.cos(w), a0 = 1 + alpha;
    return [
      (1 - cos) / 2 / a0,
      (1 - cos) / a0,
      (1 - cos) / 2 / a0,
      -2 * cos / a0,
      (1 - alpha) / a0,
    ];
  }

  /// _next is the envelope's next value.
  double _next() {
    if (!_enveloped) return 1;
    if (released) {
      _level *= _releaseFactor;
      if (_level < 1e-5) done = true;
      return _level;
    }
    var t = _t++;
    if (t < _delay) return _level = 0;
    t -= _delay;
    if (t < _attack) return _level = t / math.max(1, _attack);
    t -= _attack;
    if (t < _hold) return _level = 1;
    if (_level > _sustain) {
      _level = math.max(_sustain, _level * _decayFactor);
    }
    if (_level < 1e-5) done = true;
    return _level;
  }

  @override
  void render(Float32List l, Float32List r, int n) {
    var f = _f;
    for (var i = 0; i < n; i++) {
      if (done) return;
      var at = _pos.floor();
      if (at >= end || at < 0) {
        done = true;
        return;
      }
      var frac = _pos - at;
      var a = data[at], b = data[math.min(at + 1, end)];
      var x = (a + (b - a) * frac) / 32768;
      if (f != null) {
        var y = f[0] * x + f[1] * _x1 + f[2] * _x2 - f[3] * _y1 - f[4] * _y2;
        _x2 = _x1;
        _x1 = x;
        _y2 = _y1;
        _y1 = y;
        x = y;
      }
      var v = x * _next();
      l[i] += v * gainL;
      r[i] += v * gainR;
      _pos += step * pitch;
      var looping = loops || (loopsUntilRelease && !released);
      if (looping && loopEnd > loopStart && _pos >= loopEnd) {
        _pos -= loopEnd - loopStart;
      }
    }
  }
}

/// _PianoVoice is the built-in piano: a handful of slightly inharmonic
/// partials, the higher ones dying faster.
class _PianoVoice extends Voice {
  final double _f0;
  final double _gain;
  final List<double> _phase = List.filled(8, 0);
  final List<double> _inc = List.filled(8, 0);
  final List<double> _amp = List.filled(8, 0);
  final List<double> _decay = List.filled(8, 0);
  double _release = 1;
  int _t = 0;

  _PianoVoice(super.key, int velocity)
      : _f0 = 440 * math.pow(2, (key - 69) / 12).toDouble(),
        _gain = 0.25 * math.pow(velocity.clamp(1, 127) / 127, 1.6).toDouble() {
    var bright = velocity.clamp(1, 127) / 127;
    for (var k = 0; k < 8; k++) {
      var h = k + 1;
      var f = _f0 * h * math.sqrt(1 + 0.0004 * h * h);
      if (f > mixRate / 2.2) continue;
      _inc[k] = 2 * math.pi * f / mixRate;
      _amp[k] = math.pow(h, -(1.6 - bright * 0.7)).toDouble();
      // Seconds for the partial to fall away: long for a low note's
      // fundamental, short for a high note's upper partials.
      var life = (7.0 * math.pow(2, -(key - 40) / 24)) / (1 + k * 0.6);
      _decay[k] = math.exp(-1 / (life.clamp(0.2, 12.0) * mixRate / 6.9));
    }
  }

  @override
  void render(Float32List l, Float32List r, int n) {
    var releaseStep = math.exp(-1 / (0.25 * mixRate / 6.9));
    for (var i = 0; i < n; i++) {
      var s = 0.0;
      for (var k = 0; k < 8; k++) {
        if (_amp[k] < 1e-5) continue;
        s += math.sin(_phase[k]) * _amp[k];
        _phase[k] += _inc[k] * pitch;
        _amp[k] *= _decay[k];
      }
      // A few milliseconds' attack, so the start is a strike, not a click.
      var attack = math.min(1.0, _t / (0.003 * mixRate));
      _t++;
      if (released) {
        _release *= releaseStep;
        if (_release < 1e-4) {
          done = true;
          return;
        }
      }
      var v = s * _gain * attack * _release;
      l[i] += v * 0.7;
      r[i] += v * 0.7;
    }
    if (_amp.every((a) => a < 1e-5)) done = true;
  }
}

/// _DrumVoice is the built-in drum kit, by General MIDI key: a falling sine
/// and/or filtered noise per drum.
class _DrumVoice extends Voice {
  final math.Random _noise = math.Random(1);
  final double _gain;
  double _phase = 0;
  int _t = 0;
  // Per drum: tone start and end Hz, tone and noise lifetimes in seconds,
  // tone and noise levels, and noise brightness.
  late final double _f0, _f1, _toneLife, _noiseLife, _tone, _hiss, _bright;
  double _lp = 0, _hp = 0;

  _DrumVoice(super.key, int velocity)
      : _gain = 0.5 * math.pow(velocity.clamp(1, 127) / 127, 1.4).toDouble() {
    (double, double, double, double, double, double, double) d = switch (key) {
      35 || 36 => (150, 45, 0.35, 0.01, 1, 0.15, 0.2),
      38 || 40 => (220, 180, 0.08, 0.18, 0.5, 0.8, 0.6),
      37 => (800, 700, 0.03, 0.03, 0.4, 0.6, 0.8),
      39 => (1200, 1000, 0.01, 0.15, 0.05, 1, 0.7),
      42 || 44 => (0, 0, 0, 0.05, 0, 0.7, 1),
      46 => (0, 0, 0, 0.35, 0, 0.7, 1),
      49 || 57 => (0, 0, 0, 1.4, 0, 0.6, 0.95),
      51 || 59 => (0, 0, 0, 1.0, 0, 0.35, 0.98),
      54 => (0, 0, 0, 0.2, 0, 0.6, 0.97),
      56 => (560, 540, 0.25, 0.01, 0.6, 0.1, 0.5),
      41 || 43 => (110, 80, 0.4, 0.05, 1, 0.2, 0.3),
      45 || 47 => (150, 110, 0.35, 0.05, 1, 0.2, 0.3),
      48 || 50 => (200, 150, 0.3, 0.05, 1, 0.2, 0.3),
      _ => (400, 300, 0.1, 0.1, 0.5, 0.5, 0.6),
    };
    var (f0, f1, toneLife, noiseLife, tone, hiss, bright) = d;
    _f0 = f0;
    _f1 = f1;
    _toneLife = toneLife;
    _noiseLife = noiseLife;
    _tone = tone;
    _hiss = hiss;
    _bright = bright;
  }

  // A drum is struck, not held: letting go does not stop it.
  @override
  void release() {}

  @override
  void render(Float32List l, Float32List r, int n) {
    for (var i = 0; i < n; i++) {
      var t = _t++ / mixRate;
      if (t > math.max(_toneLife, _noiseLife) * 4) {
        done = true;
        return;
      }
      var v = 0.0;
      if (_tone > 0) {
        var f = _f1 + (_f0 - _f1) * math.exp(-t * 30);
        _phase += 2 * math.pi * f / mixRate;
        v += math.sin(_phase) * math.exp(-t / _toneLife) * _tone;
      }
      if (_hiss > 0) {
        var x = _noise.nextDouble() * 2 - 1;
        // Brighter by taking away more of the low end.
        _lp += (x - _lp) * (1 - _bright);
        _hp = x - _lp;
        v += _hp * math.exp(-t / _noiseLife) * _hiss;
      }
      v *= _gain;
      l[i] += v;
      r[i] += v;
    }
  }
}

/// _PluckVoice is the built-in plucked string: Karplus-Strong, a burst of
/// noise round a delay one period long, averaged each time round.
class _PluckVoice extends Voice {
  final Float32List _line;
  final double _gain;
  final double _damp;
  int _at = 0;
  double _release = 1;

  _PluckVoice(super.key, int velocity, {bool bass = false})
      : _line = Float32List(math.max(
            2, (mixRate / (440 * math.pow(2, (key - 69) / 12))).round())),
        _gain = (bass ? 0.55 : 0.4) *
            math.pow(velocity.clamp(1, 127) / 127, 1.3).toDouble(),
        _damp = bass ? 0.996 : 0.998 {
    var random = math.Random(key);
    // A softer pluck for a softer touch: the burst smoothed.
    var soft = 1 - velocity.clamp(1, 127) / 127 * 0.7;
    var last = 0.0;
    for (var i = 0; i < _line.length; i++) {
      var x = random.nextDouble() * 2 - 1;
      last = last * soft + x * (1 - soft);
      _line[i] = last;
    }
  }

  @override
  void render(Float32List l, Float32List r, int n) {
    var releaseStep = math.exp(-1 / (0.08 * mixRate / 6.9));
    for (var i = 0; i < n; i++) {
      var a = _line[_at], b = _line[(_at + 1) % _line.length];
      var y = (a + b) / 2 * _damp;
      _line[_at] = y;
      _at = (_at + 1) % _line.length;
      if (released) {
        _release *= releaseStep;
        if (_release < 1e-4) {
          done = true;
          return;
        }
      }
      var v = a * _gain * _release;
      l[i] += v * 0.7;
      r[i] += v * 0.7;
    }
  }
}

/// _Patch is a built-in sound for a General MIDI family, played by a
/// _SynthVoice: its wave, a second one detuned beside it, breath, its
/// envelope, how open its filter is (times the note), how far the filter
/// opens with the envelope, a vibrato, and -- for bells -- a frequency
/// modulator's ratio and how much it bites, dying away.
class _Patch {
  final int wave; // 0 sine, 1 saw, 2 square, 3 triangle, 4 organ
  final double detune, noise;
  final double attack, decay, sustain, release;
  final double cutoff, sweep, vibrato;
  final double fmRatio, fmIndex;
  final double level;
  const _Patch(
      {this.wave = 1,
      this.detune = 0,
      this.noise = 0,
      this.attack = 0.01,
      this.decay = 0.3,
      this.sustain = 0.8,
      this.release = 0.2,
      this.cutoff = 8,
      this.sweep = 0,
      this.vibrato = 0,
      this.fmRatio = 0,
      this.fmIndex = 0,
      this.level = 0.22});
}

/// _patches are the built-in sounds, by General MIDI family (program ~/ 8).
/// Null for a family played by a voice of its own: pianos, guitars, basses
/// and plucked ethnic instruments.
const Map<int, _Patch> _patches = {
  // Chromatic percussion: bells, a struck bar's inharmonic ring.
  1: _Patch(
      wave: 0,
      attack: 0.002,
      decay: 1.4,
      sustain: 0,
      release: 0.5,
      fmRatio: 3.5,
      fmIndex: 2.2,
      cutoff: 30,
      level: 0.28),
  // Organs: drawbars, held as long as the key.
  2: _Patch(
      wave: 4,
      attack: 0.006,
      decay: 0.1,
      sustain: 1,
      release: 0.06,
      cutoff: 30,
      level: 0.16),
  // Strings: bowed, swelling in, with a late vibrato.
  5: _Patch(
      wave: 1,
      detune: 6,
      attack: 0.18,
      decay: 0.4,
      sustain: 0.9,
      release: 0.45,
      cutoff: 6,
      vibrato: 0.12,
      level: 0.18),
  // Ensembles and choirs: wide and slow.
  6: _Patch(
      wave: 1,
      detune: 11,
      attack: 0.3,
      decay: 0.6,
      sustain: 0.9,
      release: 0.9,
      cutoff: 4,
      vibrato: 0.06,
      level: 0.16),
  // Brass: a bright blat as the filter opens.
  7: _Patch(
      wave: 1,
      attack: 0.04,
      decay: 0.3,
      sustain: 0.8,
      release: 0.15,
      cutoff: 2.5,
      sweep: 6,
      vibrato: 0.05,
      level: 0.2),
  // Reeds: hollow and buzzy.
  8: _Patch(
      wave: 2,
      attack: 0.03,
      decay: 0.2,
      sustain: 0.85,
      release: 0.1,
      cutoff: 5,
      vibrato: 0.06,
      level: 0.16),
  // Pipes and flutes: soft, with breath.
  9: _Patch(
      wave: 3,
      noise: 0.06,
      attack: 0.06,
      decay: 0.2,
      sustain: 0.9,
      release: 0.12,
      cutoff: 3,
      vibrato: 0.08,
      level: 0.3),
  // Synth leads: bright and immediate.
  10: _Patch(
      wave: 1,
      detune: 4,
      attack: 0.004,
      decay: 0.2,
      sustain: 0.9,
      release: 0.1,
      cutoff: 10,
      level: 0.17),
  // Synth pads: slow, wide and dark.
  11: _Patch(
      wave: 1,
      detune: 12,
      attack: 0.6,
      decay: 1,
      sustain: 0.9,
      release: 1.5,
      cutoff: 3,
      level: 0.15),
  // Synth effects: a shimmer with air in it.
  12: _Patch(
      wave: 3,
      detune: 15,
      noise: 0.05,
      attack: 0.4,
      decay: 1,
      sustain: 0.8,
      release: 2,
      cutoff: 6,
      vibrato: 0.15,
      level: 0.22),
  // Percussive: woodblocks, steel drums -- short and struck.
  14: _Patch(
      wave: 0,
      attack: 0.001,
      decay: 0.35,
      sustain: 0,
      release: 0.15,
      fmRatio: 1.4,
      fmIndex: 1.6,
      cutoff: 30,
      level: 0.3),
  // Sound effects: noise, filtered by the note.
  15: _Patch(
      wave: 3,
      noise: 0.5,
      attack: 0.1,
      decay: 0.5,
      sustain: 0.7,
      release: 0.5,
      cutoff: 4,
      level: 0.22),
};

/// _SynthVoice plays a _Patch: band-limited waves (PolyBLEP), two of them
/// detuned, through two one-pole low-passes that open with the touch and
/// the envelope.
class _SynthVoice extends Voice {
  final _Patch p;
  final double _f0, _gain, _bright;
  final _Adsr _env;
  double _ph1 = 0, _ph2 = 0, _fm = 0, _lp1 = 0, _lp2 = 0, _t = 0;
  final math.Random _noise;

  _SynthVoice(super.key, int velocity, this.p)
      : _f0 = 440 * math.pow(2, (key - 69) / 12).toDouble(),
        _gain =
            p.level * math.pow(velocity.clamp(1, 127) / 127, 1.4).toDouble(),
        _bright = 0.55 + 0.45 * velocity.clamp(1, 127) / 127,
        _env = _Adsr(p.attack, p.decay, p.sustain, p.release),
        _noise = math.Random(key);

  @override
  void release() {
    super.release();
    _env.letGo = true;
  }

  static double _blep(double t, double dt) {
    if (t < dt) {
      t /= dt;
      return t + t - t * t - 1;
    }
    if (t > 1 - dt) {
      t = (t - 1) / dt;
      return t * t + t + t + 1;
    }
    return 0;
  }

  double _wave(double ph, double dt) => switch (p.wave) {
        0 => math.sin(2 * math.pi * ph),
        1 => 2 * ph - 1 - _blep(ph, dt),
        2 =>
          (ph < 0.5 ? 1.0 : -1.0) + _blep(ph, dt) - _blep((ph + 0.5) % 1, dt),
        3 => 1 - 4 * (ph - 0.5).abs(),
        // Drawbars: the note, its octave, its twelfth and two octaves up.
        _ => (math.sin(2 * math.pi * ph) +
                0.7 * math.sin(4 * math.pi * ph) +
                0.45 * math.sin(6 * math.pi * ph) +
                0.3 * math.sin(8 * math.pi * ph)) /
            1.6,
      };

  @override
  void render(Float32List l, Float32List r, int n) {
    var spread = math.pow(2, p.detune / 1200).toDouble();
    for (var i = 0; i < n; i++) {
      var e = _env.next();
      if (_env.done) {
        done = true;
        return;
      }
      _t += 1 / mixRate;
      // A vibrato that comes in after a third of a second.
      var vib = p.vibrato == 0
          ? 1.0
          : math
              .pow(
                  2,
                  p.vibrato *
                      math.min(1.0, _t / 0.35) *
                      math.sin(2 * math.pi * 5.5 * _t) /
                      12)
              .toDouble();
      var f = _f0 * pitch * vib;
      var dt1 = (f / mixRate).clamp(0.0, 0.45);
      double s;
      if (p.fmRatio > 0) {
        // A bell: the modulator's bite dying with the note.
        _fm = (_fm + dt1 * p.fmRatio) % 1;
        var index = p.fmIndex * e;
        s = math.sin(2 * math.pi * _ph1 + index * math.sin(2 * math.pi * _fm));
      } else {
        s = _wave(_ph1, dt1);
        if (p.detune > 0) s = 0.5 * (s + _wave(_ph2, dt1 * spread));
      }
      if (p.noise > 0) s += p.noise * (_noise.nextDouble() * 2 - 1);
      _ph1 = (_ph1 + dt1) % 1;
      _ph2 = (_ph2 + dt1 * spread) % 1;
      // The filter opens with the touch, and with the envelope by sweep.
      var cut = math.min(16000.0, f * p.cutoff * _bright * (1 + p.sweep * e));
      var a = 1 - math.exp(-2 * math.pi * cut / mixRate);
      _lp1 += (s - _lp1) * a;
      _lp2 += (_lp1 - _lp2) * a;
      var v = _lp2 * _gain * e;
      l[i] += v * 0.7;
      r[i] += v * 0.7;
    }
  }
}

/// _Adsr is an envelope: up in a straight line over its attack, down to its
/// sustain over its decay, held there, then to silence over its release
/// once let go -- each fall within a thousandth (60dB) of its end in the
/// time it is given.
class _Adsr {
  final int _attack;
  final double _decay, _sustain, _release;
  int _t = 0;
  double level = 0;
  bool letGo = false, done = false;

  _Adsr(double attack, double decay, this._sustain, double release)
      : _attack = math.max(1, (attack * mixRate).round()),
        _decay = _factor(decay),
        _release = _factor(release);

  static double _factor(double seconds) =>
      math.exp(-6.9 / (math.max(0.001, seconds) * mixRate));

  double next() {
    if (letGo) {
      level *= _release;
      if (level < 1e-4) done = true;
      return level;
    }
    if (_t < _attack) return level = ++_t / _attack;
    return level = _sustain + (level - _sustain) * _decay;
  }
}

/// Sampler is an instrument: a bank's preset, or a built-in voice.
class Sampler {
  final SoundFont? font;
  final SfPreset? preset;

  /// bank and program are the General MIDI sound: with no bank of
  /// samples, the program's family picks the built-in voice, and bank 128
  /// is the drum kit.
  final int bank, program;

  /// look picks the built-in voice used with no bank.
  final InstrumentLook look;

  /// shape is how it plays: see instrument_shape.dart. Changed as it plays,
  /// the next note has it, and the filter, LFO and bend at once.
  InstrumentShape shape;
  final List<Voice> _voices = [];

  /// maxVoices is how many sound at once: past it the oldest let-go note
  /// is cut, then the oldest of all.
  static const int maxVoices = InstrumentShape.maxVoices;

  Sampler(
      {this.font,
      this.bank = 0,
      this.program = 0,
      this.look = InstrumentLook.keyboard,
      this.shape = const InstrumentShape()})
      : preset = font?.preset(bank, program);

  int get sounding => _voices.length;

  /// _controls are the channel's controllers as last set, 0 to 1.
  final Map<MidiControl, double> _controls = {
    for (var c in MidiControl.values) c: c.rest,
  };

  /// _pedalled are keys let go while the sustain pedal was down, sounding
  /// until it is let up.
  final Set<int> _pedalled = {};

  /// _held are the keys down, the last pressed last, with how hard each was
  /// struck: where one voice plays, letting go of a note goes back to the
  /// one held before it.
  final List<int> _held = [];
  final Map<int, int> _struck = {};

  /// _notes counts the notes started, to tell one from another.
  int _notes = 0;

  /// _time is how long it has played, for the vibrato's swing, and
  /// _lfoPhase where the LFO is in its cycle.
  double _time = 0, _lfoPhase = 0;
  double _gainL = 1, _gainR = 1;
  bool _rendered = false;
  Float32List _l = Float32List(0), _r = Float32List(0);

  /// _step is how many frames are rendered together: the LFO, the filter's
  /// envelope and a glide move between them.
  static const int _step = 64;
  final Float32List _vl = Float32List(_step), _vr = Float32List(_step);

  /// control sets one of the channel's controllers, 0 to 1.
  void control(MidiControl c, double value) {
    _controls[c] = value.clamp(0.0, 1.0);
    if (c == MidiControl.sustain && value < 0.5) {
      for (var key in _pedalled) {
        for (var v in _voices) {
          if (v.heldAs == key) _end(v);
        }
      }
      _pedalled.clear();
    }
  }

  void noteOn(int key, int velocity) {
    if (velocity <= 0) {
      noteOff(key);
      return;
    }
    velocity = shape.velocity(velocity);
    _held
      ..remove(key)
      ..add(key);
    _struck[key] = velocity;
    _pedalled.remove(key);
    if (shape.mode == VoiceMode.poly) {
      _start(key, velocity);
      return;
    }
    // One at a time: legato moves what is sounding to the new key; mono
    // starts it afresh, gliding from where the last was.
    var sounding = [
      for (var v in _voices)
        if (!v.ending) v
    ];
    if (shape.mode == VoiceMode.legato && sounding.isNotEmpty) {
      for (var v in sounding) {
        _moveTo(v, key);
      }
      return;
    }
    var from = sounding.isEmpty
        ? null
        : sounding.last.key + sounding.last.offset + sounding.last.slide;
    for (var v in sounding) {
      _end(v);
    }
    _start(key, velocity, from: from);
  }

  /// _start sounds [key], gliding from [from] (a key, in semitones) where it
  /// is given and the instrument glides.
  void _start(int key, int velocity, {double? from}) {
    var started = <Voice>[];
    var f = font, p = preset;
    var own = shape.envelope;
    if (f != null && p != null) {
      for (var z in f.zones(p, key, velocity)) {
        started.add(_SfVoice(key, velocity, z, f.samples, enveloped: !own));
      }
    } else {
      // Built in: the drum kit, or the program's family -- a piano, a
      // plucked string, or one of the synth's patches.
      var family = program.clamp(0, 127) ~/ 8;
      started.add(look == InstrumentLook.drums || bank == 128
          ? _DrumVoice(key, velocity)
          : switch (_patches[family]) {
              var patch? => _SynthVoice(key, velocity, patch),
              null => switch (family) {
                  3 || 13 => _PluckVoice(key, velocity),
                  4 => _PluckVoice(key, velocity, bass: true),
                  _ => _PianoVoice(key, velocity),
                },
            });
    }
    var note = ++_notes;
    for (var v in started) {
      v.note = note;
      if (own) {
        v._envelope =
            _Adsr(shape.attack, shape.decay, shape.sustain, shape.release);
      }
      if (shape.filter != SynthFilter.off && shape.filterEnvelope != 0) {
        v._filterEnvelope =
            _Adsr(0.002, shape.filterDecay, 0, shape.filterDecay);
      }
      if (from != null && shape.glides) v.slide = from - key;
    }
    _voices.addAll(started);
    _trim();
  }

  /// _moveTo moves [v] to [key] -- a legato note -- gliding there where the
  /// instrument glides, else at once.
  void _moveTo(Voice v, int key) {
    var now = v.offset + v.slide;
    v.offset = (key - v.key).toDouble();
    v.slide = shape.glides ? now - v.offset : 0;
    v.heldAs = key;
  }

  /// _end lets [v] go: its own release, or the instrument's.
  void _end(Voice v) {
    var amp = v._envelope;
    if (amp == null) {
      v.release();
    } else {
      amp.letGo = true;
    }
    v._filterEnvelope?.letGo = true;
  }

  /// _trim cuts voices past the most there may be -- the oldest let-go note
  /// first, then the oldest of all -- and notes past the instrument's
  /// [InstrumentShape.voices].
  void _trim() {
    while (_voices.length > maxVoices) {
      var old = _voices.indexWhere((v) => v.ending);
      _voices.removeAt(old < 0 ? 0 : old);
    }
    if (shape.voices >= maxVoices) return;
    while (true) {
      var notes = {for (var v in _voices) v.note};
      if (notes.length <= shape.voices) return;
      var ending = _voices.where((v) => v.ending);
      var cut = ending.isNotEmpty ? ending.first.note : _voices.first.note;
      _voices.removeWhere((v) => v.note == cut);
    }
  }

  void noteOff(int key) {
    _held.remove(key);
    if (_controls[MidiControl.sustain]! >= 0.5) {
      _pedalled.add(key);
      return;
    }
    var sounding = [
      for (var v in _voices)
        if (v.heldAs == key && !v.ending) v
    ];
    // One at a time: back to the key still held, if any.
    if (shape.mode != VoiceMode.poly &&
        sounding.isNotEmpty &&
        _held.isNotEmpty) {
      var back = _held.last;
      if (shape.mode == VoiceMode.legato) {
        for (var v in sounding) {
          _moveTo(v, back);
        }
        return;
      }
      var from = sounding.last.key + sounding.last.offset + sounding.last.slide;
      for (var v in sounding) {
        _end(v);
      }
      _start(back, _struck[back] ?? 100, from: from);
      return;
    }
    for (var v in sounding) {
      _end(v);
    }
  }

  void allOff() {
    _held.clear();
    for (var v in _voices) {
      _end(v);
    }
  }

  /// render adds the next [n] frames of everything sounding to [l] and [r],
  /// through the controllers.
  void render(Float32List l, Float32List r, int n) {
    if (_l.length < n) {
      _l = Float32List(n);
      _r = Float32List(n);
    }
    _l.fillRange(0, n, 0);
    _r.fillRange(0, n, 0);
    var shape = this.shape;
    var lfoStep = 2 * math.pi * shape.lfoRate / mixRate;
    for (var at = 0; at < n; at += _step) {
      var m = math.min(_step, n - at);
      var lfo = shape.lfoDepth > 0 ? math.sin(_lfoPhase) * shape.lfoDepth : 0.0;
      // The bend wheel bends as far as the instrument says; the mod wheel
      // gives up to half a semitone of vibrato at 5.5Hz; the LFO, a
      // semitone either way.
      var bend =
          (_controls[MidiControl.pitchBend]! - 0.5) * 2 * shape.bendRange;
      var vibrato = _controls[MidiControl.modulation]! *
          0.5 *
          math.sin(2 * math.pi * 5.5 * _time);
      var semitones = bend +
          vibrato +
          shape.tune / 100 +
          (shape.lfoTarget == LfoTarget.pitch ? lfo : 0);
      var outL = Float32List.sublistView(_l, at, at + m);
      var outR = Float32List.sublistView(_r, at, at + m);
      var glideFall =
          shape.glide > 0 ? math.exp(-4.6 * m / (shape.glide * mixRate)) : 0.0;
      for (var v in [..._voices]) {
        v.pitch = math.pow(2, (semitones + v.offset + v.slide) / 12).toDouble();
        if (v._envelope == null && shape.filter == SynthFilter.off) {
          v.render(outL, outR, m);
        } else {
          _vl.fillRange(0, m, 0);
          _vr.fillRange(0, m, 0);
          v.render(_vl, _vr, m);
          _shaped(v, m, lfo);
          for (var i = 0; i < m; i++) {
            outL[i] += _vl[i];
            outR[i] += _vr[i];
          }
        }
        if (v.slide != 0) {
          v.slide *= glideFall;
          if (v.slide.abs() < 1e-3) v.slide = 0;
        }
        if (v.done) _voices.remove(v);
      }
      // The LFO on the volume: down from full as far as its depth.
      if (shape.lfoTarget == LfoTarget.volume && shape.lfoDepth > 0) {
        for (var i = 0; i < m; i++) {
          var g = 1 -
              shape.lfoDepth * (0.5 - 0.5 * math.sin(_lfoPhase + lfoStep * i));
          outL[i] *= g;
          outR[i] *= g;
        }
      }
      _time += m / mixRate;
      _lfoPhase = (_lfoPhase + lfoStep * m) % (2 * math.pi);
    }
    // Volume and expression are squared, as MIDI has them; unity at
    // volume's rest value and full expression.
    var volume = _controls[MidiControl.volume]! / MidiControl.volume.rest;
    var expression = _controls[MidiControl.expression]!;
    var gain = volume * volume * expression * expression;
    var pan = _controls[MidiControl.pan]!;
    var toL = gain * (pan <= 0.5 ? 1 : (1 - pan) * 2);
    var toR = gain * (pan >= 0.5 ? 1 : pan * 2);
    // Ramped across the block so a moving curve never steps, except the
    // first block, which starts at the set level.
    if (!_rendered) {
      _rendered = true;
      _gainL = toL;
      _gainR = toR;
    }
    var stepL = (toL - _gainL) / n, stepR = (toR - _gainR) / n;
    for (var i = 0; i < n; i++) {
      _gainL += stepL;
      _gainR += stepR;
      l[i] += _l[i] * _gainL;
      r[i] += _r[i] * _gainR;
    }
    _gainL = toL;
    _gainR = toR;
  }

  /// _shaped puts [v]'s [m] frames, in _vl and _vr, through the instrument's
  /// filter and its own volume envelope. [lfo] is the LFO's swing now,
  /// minus to plus its depth.
  void _shaped(Voice v, int m, double lfo) {
    var shape = this.shape;
    if (shape.filter != SynthFilter.off) {
      // Its corner: up (or down) as far as the filter's envelope is open,
      // and two octaves either way of the LFO.
      var octaves = (v._filterEnvelope?.level ?? 0) * shape.filterEnvelope * 4 +
          (shape.lfoTarget == LfoTarget.filter ? lfo * 2 : 0);
      var hz = (shape.cutoff * math.pow(2, octaves))
          .clamp(20.0, mixRate * 0.45)
          .toDouble();
      // A state-variable filter (Simper's), stable however it is moved.
      var g = math.tan(math.pi * hz / mixRate);
      var k = 1 / (math.sqrt1_2 * math.pow(28, shape.resonance));
      var a1 = 1 / (1 + g * (g + k)), a2 = g * a1, a3 = g * a2;
      var kind = shape.filter;
      // A side at a time: its two states in, the filtered frames out.
      (double, double) side(Float32List x, double c1, double c2) {
        for (var i = 0; i < m; i++) {
          var input = x[i];
          var v3 = input - c2;
          var v1 = a1 * c1 + a2 * v3;
          var v2 = c2 + a2 * c1 + a3 * v3;
          c1 = 2 * v1 - c1;
          c2 = 2 * v2 - c2;
          x[i] = switch (kind) {
            SynthFilter.lowPass => v2,
            SynthFilter.highPass => input - k * v1 - v2,
            SynthFilter.bandPass => v1,
            SynthFilter.off => input,
          };
        }
        return (c1, c2);
      }

      var (l1, l2) = side(_vl, v._l1, v._l2);
      var (r1, r2) = side(_vr, v._r1, v._r2);
      v
        .._l1 = l1
        .._l2 = l2
        .._r1 = r1
        .._r2 = r2;
      var fe = v._filterEnvelope;
      if (fe != null) {
        for (var i = 0; i < m; i++) {
          fe.next();
        }
      }
    }
    var amp = v._envelope;
    if (amp != null) {
      for (var i = 0; i < m; i++) {
        var a = amp.next();
        _vl[i] *= a;
        _vr[i] *= a;
      }
      if (amp.done) v.done = true;
    }
  }
}
