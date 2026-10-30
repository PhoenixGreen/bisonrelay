import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/media/mix/pitch.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';

// vocoder.dart is the Vocoder: a channel vocoder of the classic kind. The
// voice -- the channel's own sound, the modulator -- is split into bands,
// and how loud each band is, moment to moment, is laid onto the same band of
// a second sound, the carrier: hiss, a buzz, or another channel. What comes
// out says what the voice said, in the carrier's tone.
//
// Each carrier band is first evened out by its own loudness, so a carrier
// with little in a band -- a chord with a gap in it -- still carries the
// voice there, up to a limit.

const double _rate = 48000;

/// _maxEven is how far a quiet carrier band is brought up: 18 dB.
const double _maxEven = 8;

/// _Band is one band of a bank: a fourth-order band-pass (two sections)
/// and a follower of how loud it is.
class _Band {
  final List<double> c;
  // Two sections' state, transposed direct form II.
  double _a1 = 0, _a2 = 0, _b1 = 0, _b2 = 0;
  double env = 0;

  _Band(double hz, double q) : c = _bandPass(hz, q);

  double filter(double x) {
    var y = c[0] * x + _a1;
    _a1 = c[1] * x - c[3] * y + _a2;
    _a2 = c[2] * x - c[4] * y;
    var z = c[0] * y + _b1;
    _b1 = c[1] * y - c[3] * z + _b2;
    _b2 = c[2] * y - c[4] * z;
    return z;
  }

  /// follow moves [env] toward [x]'s size: up at [up], down at [down].
  void follow(double x, double up, double down) {
    var a = x.abs();
    env = a > env ? a + (env - a) * up : a + (env - a) * down;
  }
}

/// _bandPass is an RBJ band-pass, 0 dB at its centre, normalised.
List<double> _bandPass(double hz, double q) {
  var w = 2 * math.pi * hz / _rate;
  var alpha = math.sin(w) / (2 * q);
  var a0 = 1 + alpha;
  return [
    alpha / a0,
    0,
    -alpha / a0,
    -2 * math.cos(w) / a0,
    (1 - alpha) / a0,
  ];
}

/// _coef is a follower's pull for a time of [ms]: e to the minus one over
/// it in samples.
double _coef(double ms) => math.exp(-1 / (ms / 1000 * _rate));

/// Sidechained is a device that hears a second channel beside its own:
/// [feed] is given that channel's sound, as it came in, before the block is
/// processed.
abstract class Sidechained implements DeviceProcessor {
  String? get source;
  void feed(Float32List l, Float32List r, int n);
}

class Vocoder implements Sidechained {
  @override
  final String? source;
  final int _carrier;
  final double _note, _up, _down, _unvoiced, _mix;
  final List<_Band> _voice, _carry;

  // The voice's highs, for the hiss of an s or a t the carrier lacks.
  final Biquad _hiss;
  Float32List _hl = Float32List(1024), _hr = Float32List(1024);

  // A channel carrier, fed for this block.
  Float32List _side = Float32List(1024);
  int _fed = 0;

  // The buzz: a phase and its step; following the voice, a step it eases to.
  double _phase = 0, _step, _toStep;
  int _seed = 22222;

  // Following the voice: what it has heard of it, to listen to.
  final Float32List _heard = Float32List(2048), _window = Float32List(2048);
  int _heardAt = 0, _sinceListen = 0;
  bool _voiced = false;

  Vocoder(MixDevice d)
      : source = d.sidechain,
        _carrier = d.value("carrier").round(),
        _note = d.value("note"),
        _up = _coef(d.value("attack")),
        _down = _coef(d.value("release")),
        _unvoiced = d.value("unvoiced"),
        _mix = d.value("mix"),
        _voice = [],
        _carry = [],
        _hiss = Biquad(_highPass(5000)),
        _step = 0,
        _toStep = 0 {
    var bands = d.value("bands").round();
    var low = d.value("low"), high = d.value("high");
    var ratio = math.pow(high / low, 1 / (bands - 1)).toDouble();
    // Each band as wide as the step to the next.
    var q = math.sqrt(ratio) / (ratio - 1);
    var shift = math.pow(2, d.value("formant") / 12).toDouble();
    for (var i = 0; i < bands; i++) {
      var hz = low * math.pow(ratio, i);
      _voice.add(_Band(hz, q));
      _carry.add(_Band(math.min(hz * shift, _rate * 0.45), q));
    }
    _step = _toStep = 440 * math.pow(2, (_note - 69) / 12) / _rate;
  }

  static List<double> _highPass(double hz) {
    var w = 2 * math.pi * hz / _rate;
    var alpha = math.sin(w) / (2 * math.sqrt1_2);
    var cw = math.cos(w), a0 = 1 + alpha;
    return [
      (1 + cw) / 2 / a0,
      -(1 + cw) / a0,
      (1 + cw) / 2 / a0,
      -2 * cw / a0,
      (1 - alpha) / a0,
    ];
  }

  @override
  void feed(Float32List l, Float32List r, int n) {
    if (_side.length < n) _side = Float32List(n);
    for (var i = 0; i < n; i++) {
      _side[i] = (l[i] + r[i]) * 0.5;
    }
    _fed = n;
  }

  double _noise() {
    _seed ^= _seed << 13;
    _seed ^= _seed >> 17;
    _seed ^= _seed << 5;
    _seed &= 0xffffffff;
    return _seed / 0x7fffffff - 1;
  }

  /// _saw is a band-limited saw: the polyBLEP correction rounds off the
  /// jump that would otherwise alias.
  double _saw() {
    _step += (_toStep - _step) * 0.002;
    var t = _phase, dt = _step;
    var v = 2 * t - 1;
    if (t < dt) {
      var x = t / dt;
      v -= x + x - x * x - 1;
    } else if (t > 1 - dt) {
      var x = (t - 1) / dt;
      v -= x * x + x + x + 1;
    }
    _phase += dt;
    if (_phase >= 1) _phase -= 1;
    return v;
  }

  /// _listen hears the voice's pitch, for a buzz to follow it.
  void _listen() {
    for (var i = 0; i < _window.length; i++) {
      _window[i] = _heard[(_heardAt + i) % _heard.length];
    }
    var p = detectPitch(_window);
    _voiced = p != null && p.clarity >= 0.5;
    if (_voiced) _toStep = p!.hz / _rate;
  }

  double _carrierAt(int i) => switch (_carrier) {
        0 => _noise() * 0.5,
        1 => _saw() * 0.5,
        2 => _voiced ? _saw() * 0.5 : _noise() * 0.5,
        _ => i < _fed ? _side[i] : 0,
      };

  @override
  void process(Float32List l, Float32List r, int n) {
    if (_hl.length < n) {
      _hl = Float32List(n);
      _hr = Float32List(n);
    }
    _hl.setRange(0, n, l);
    _hr.setRange(0, n, r);
    _hiss.process(_hl, _hr, n);
    for (var i = 0; i < n; i++) {
      var voice = (l[i] + r[i]) * 0.5;
      if (_carrier == 2) {
        _heard[_heardAt] = voice;
        _heardAt = (_heardAt + 1) % _heard.length;
        if (++_sinceListen >= 1024) {
          _sinceListen = 0;
          _listen();
        }
      }
      var carrier = _carrierAt(i);
      var wet = 0.0;
      for (var b = 0; b < _voice.length; b++) {
        var vb = _voice[b], cb = _carry[b];
        vb.follow(vb.filter(voice), _up, _down);
        var c = cb.filter(carrier);
        cb.follow(c, _up, _down);
        var even = cb.env > 1e-6 ? math.min(vb.env / cb.env, _maxEven) : 0;
        wet += c * even;
      }
      wet += (_hl[i] + _hr[i]) * 0.5 * _unvoiced;
      l[i] = l[i] * (1 - _mix) + wet * _mix;
      r[i] = r[i] * (1 - _mix) + wet * _mix;
    }
    _fed = 0;
  }
}
