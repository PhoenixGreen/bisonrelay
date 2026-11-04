import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/media/synth/soundfont.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart'
    show InstrumentLook, MidiControl;

// sampler.dart plays notes: a bank's samples where there is a bank (see
// soundfont.dart), otherwise built-in piano, drum and plucked voices, so an
// instrument sounds the moment it is added.
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
  Voice(this.key);

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

  _SfVoice(super.key, int velocity, Zone z, this.data)
      : end = math.min(data.length - 1,
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

/// Sampler is an instrument: a bank's preset, or a built-in voice.
class Sampler {
  final SoundFont? font;
  final SfPreset? preset;

  /// look picks the built-in voice used with no bank.
  final InstrumentLook look;
  final List<Voice> _voices = [];

  /// maxVoices is how many sound at once: past it the oldest let-go note
  /// is cut, then the oldest of all.
  static const int maxVoices = 64;

  Sampler(
      {this.font,
      int bank = 0,
      int program = 0,
      this.look = InstrumentLook.keyboard})
      : preset = font?.preset(bank, program);

  int get sounding => _voices.length;

  /// _controls are the channel's controllers as last set, 0 to 1.
  final Map<MidiControl, double> _controls = {
    for (var c in MidiControl.values) c: c.rest,
  };

  /// _pedalled are keys let go while the sustain pedal was down, sounding
  /// until it is let up.
  final Set<int> _pedalled = {};

  /// _time is how long it has played, for the vibrato's swing.
  double _time = 0;
  double _gainL = 1, _gainR = 1;
  bool _rendered = false;
  Float32List _l = Float32List(0), _r = Float32List(0);

  /// control sets one of the channel's controllers, 0 to 1.
  void control(MidiControl c, double value) {
    _controls[c] = value.clamp(0.0, 1.0);
    if (c == MidiControl.sustain && value < 0.5) {
      for (var key in _pedalled) {
        for (var v in _voices) {
          if (v.key == key) v.release();
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
    var f = font, p = preset;
    if (f != null && p != null) {
      for (var z in f.zones(p, key, velocity)) {
        _voices.add(_SfVoice(key, velocity, z, f.samples));
      }
    } else {
      _voices.add(switch (look) {
        InstrumentLook.keyboard => _PianoVoice(key, velocity),
        InstrumentLook.drums => _DrumVoice(key, velocity),
        InstrumentLook.guitar => _PluckVoice(key, velocity),
        InstrumentLook.bass => _PluckVoice(key, velocity, bass: true),
      });
    }
    while (_voices.length > maxVoices) {
      var old = _voices.indexWhere((v) => v.released);
      _voices.removeAt(old < 0 ? 0 : old);
    }
  }

  void noteOff(int key) {
    if (_controls[MidiControl.sustain]! >= 0.5) {
      _pedalled.add(key);
      return;
    }
    for (var v in _voices) {
      if (v.key == key) v.release();
    }
  }

  void allOff() {
    for (var v in _voices) {
      v.release();
    }
  }

  /// render adds the next [n] frames of everything sounding to [l] and [r],
  /// through the controllers.
  void render(Float32List l, Float32List r, int n) {
    // Bend range is two semitones; the mod wheel gives up to half a
    // semitone of vibrato at 5.5Hz.
    var bend = (_controls[MidiControl.pitchBend]! - 0.5) * 4;
    var vibrato = _controls[MidiControl.modulation]! *
        0.5 *
        math.sin(2 * math.pi * 5.5 * _time);
    var pitch = math.pow(2, (bend + vibrato) / 12).toDouble();
    _time += n / mixRate;
    if (_l.length < n) {
      _l = Float32List(n);
      _r = Float32List(n);
    }
    _l.fillRange(0, n, 0);
    _r.fillRange(0, n, 0);
    for (var v in [..._voices]) {
      v.pitch = pitch;
      v.render(_l, _r, n);
      if (v.done) _voices.remove(v);
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
}
