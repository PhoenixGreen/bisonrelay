import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/midi_effects.dart'
    show scaleSteps;

// pitch.dart detects a voice's pitch (YIN) and moves it (TD-PSOLA). The
// Tuner uses the first, Auto-tune both.
//
// YIN (de Cheveigné and Kawahara, 2002) takes the period as the first lag
// whose cumulative-mean-normalised difference falls under a threshold.
//
// TD-PSOLA shifts pitch without shifting formants, so a voice moved up is
// not a chipmunk: windowed two-period slices are laid down again closer
// together (higher) or further apart (lower).

/// PitchReading is what YIN heard: the pitch in Hz and its clarity, 0 to 1.
typedef PitchReading = ({double hz, double clarity});

/// _cmnd is detectPitch's row, each lag's cumulative mean normalised
/// difference: kept between calls rather than made at every one.
Float64List _cmnd = Float64List(0);

/// detectPitch finds [x]'s pitch at [rate] samples a second, between
/// [minHz] and [maxHz]; null where nothing repeats clearly enough.
PitchReading? detectPitch(Float32List x,
    {double rate = 48000,
    double minHz = 60,
    double maxHz = 1200,
    double threshold = 0.15}) {
  var maxLag = math.min((rate / minHz).floor(), x.length ~/ 2);
  var minLag = math.max(2, (rate / maxHz).floor());
  if (maxLag <= minLag + 2) return null;
  var w = x.length - maxLag;
  // Too quiet to say.
  var energy = 0.0;
  for (var i = 0; i < w; i++) {
    energy += x[i] * x[i];
  }
  if (energy / w < 1e-7) return null;
  // Worked out lag by lag, and no further than the dip it settles in: the
  // cumulative mean at a lag needs only the lags before it, so stopping
  // there gives what working out every lag gave, for a fraction of the
  // work at a voice's pitches (Ken's systems review, 2026-11-08: an
  // Auto-tune took a good share of a core). Its rows kept between calls.
  if (_cmnd.length < maxLag + 1) _cmnd = Float64List(maxLag + 1);
  var cmnd = _cmnd..[0] = 1;
  var running = 0.0;
  var tau = -1;
  var through = 0;
  void lag(int t) {
    var sum = 0.0;
    for (var i = 0; i < w; i++) {
      var diff = x[i] - x[i + t];
      sum += diff * diff;
    }
    running += sum;
    cmnd[t] = running == 0 ? 1 : sum * t / running;
    through = t;
  }

  for (var t = 1; t <= maxLag; t++) {
    lag(t);
    if (t < minLag || t >= maxLag || cmnd[t] >= threshold) continue;
    // Under the threshold: on to the bottom of the dip.
    lag(t + 1);
    while (t + 1 < maxLag && cmnd[t + 1] < cmnd[t]) {
      t++;
      if (t + 1 <= maxLag && through < t + 1) lag(t + 1);
    }
    tau = t;
    break;
  }
  if (tau < 0) return null;
  // Between samples: a parabola through the dip and its neighbours.
  var better = tau.toDouble();
  if (tau > 1 && tau < maxLag) {
    var a = cmnd[tau - 1], b = cmnd[tau], c = cmnd[tau + 1];
    var den = a + c - 2 * b;
    if (den.abs() > 1e-12) better = tau + 0.5 * (a - c) / den;
  }
  return (hz: rate / better, clarity: (1 - cmnd[tau]).clamp(0.0, 1.0));
}

/// midiOf is [hz] as a MIDI note, fractional: 69.0 is A440.
double midiOf(double hz) => 69 + 12 * math.log(hz / 440) / math.ln2;

/// snapNote is the note [midi] is pulled to: the nearest of [steps] above
/// [root], or of every semitone for an empty [steps].
double snapNote(double midi, int root, List<int> steps) {
  if (steps.isEmpty) return midi.roundToDouble();
  var best = midi.roundToDouble();
  var bestD = double.infinity;
  var octave = ((midi - root) / 12).floor();
  for (var o = octave - 1; o <= octave + 1; o++) {
    for (var s in steps) {
      var n = (root + 12 * o + s).toDouble();
      var d = (n - midi).abs();
      if (d < bestD) {
        bestD = d;
        best = n;
      }
    }
  }
  return best;
}

/// AutoTune pulls a voice towards the nearest note of a key and scale by
/// [_amount], easing the correction in over the retune time (zero gives the
/// robotic sound). Slices are taken [latency] behind the input and emitted
/// [_settle] behind where they are laid, a fixed delay of the two together.
class AutoTune implements DeviceProcessor, Tunable {
  static const int latency = 1024;

  /// _settle is how far behind the newest slice output is read: at least
  /// half a slice at the lowest pitch, so every slice touching a sample is
  /// laid before it goes out.
  static const int _settle = 1024;
  static const int _size = 8192;
  static const int _window = 2048;

  /// _hop is how often it listens for the pitch sung, in samples: every
  /// ninetieth of a second -- what pitch trackers step by, and quick enough
  /// to follow a note sung -- where every 256 (half that) was twice the work
  /// for nothing heard (Ken, 2026-11-08: "reduce this to a more optimal
  /// amount").
  static const int _hop = 512;

  int _root;
  List<int> _steps;
  double _amount;
  double _ease;

  /// _retuneMs, _humanise and _vibrato: see the device's knobs. _slow is
  /// the pitch heard, smoothed over about a tenth of a second -- the note
  /// being sung, without its vibrato -- and _held how long it has been on
  /// one note, in samples.
  double _retuneMs, _humanise, _vibrato;
  double? _slow;
  int _held = 0;
  double _easeNow = 0;

  final Float32List _inL = Float32List(_size), _inR = Float32List(_size);
  final Float32List _outL = Float32List(_size), _outR = Float32List(_size);
  final Float32List _scratch = Float32List(_window);

  /// _t is how many samples have gone in; _synth the next place a slice is
  /// laid down, in output time; _mark the last slice's place in the input.
  int _t = 0;
  double _synth = latency.toDouble();
  double _mark = 0;
  double _period = 240;
  double _ratio = 1, _target = 1;
  int _sinceHeard = 0;

  /// heard is the last pitch it heard, for a tuner beside it.
  PitchReading? heard;

  AutoTune(MixDevice d)
      : _root = _rootOf(d),
        _steps = _stepsOf(d),
        _amount = d.value("amount"),
        _retuneMs = d.value("retune"),
        _humanise = d.value("humanise"),
        _vibrato = d.value("vibrato"),
        // Retune time as a per-sample one-pole coefficient.
        _ease = _easeFor(d.value("retune")) {
    _easeNow = _ease;
  }

  static int _rootOf(MixDevice d) => d.value("key").round();
  static List<int> _stepsOf(MixDevice d) => d.value("scale").round() == 0
      ? const []
      : scaleSteps[
          (d.value("scale").round() - 1).clamp(0, scaleSteps.length - 1)];

  /// tune takes [d]'s settings as it plays: what it has heard and what it
  /// holds back are kept, so a knob turned -- or an LFO on it -- does not
  /// leave a gap while it listens again.
  @override
  void tune(MixDevice d) {
    _root = _rootOf(d);
    _steps = _stepsOf(d);
    _amount = d.value("amount");
    _retuneMs = d.value("retune");
    _humanise = d.value("humanise");
    _vibrato = d.value("vibrato");
    _ease = _easeFor(d.value("retune"));
  }

  /// _easeFor is the retune's per-sample coefficient for [ms].
  static double _easeFor(double ms) =>
      ms <= 0 ? 0 : math.exp(-1 / (ms / 1000 * 48000));

  void _listen() {
    // The last window of what came in, both sides as one.
    for (var i = 0; i < _window; i++) {
      var k = (_t - _window + i) & (_size - 1);
      _scratch[i] = (_inL[k] + _inR[k]) * 0.5;
    }
    var p = detectPitch(_scratch);
    heard = p;
    if (p == null || p.clarity < 0.5) {
      _target = 1;
      _slow = null;
      return;
    }
    _period = 48000 / p.hz;
    var midi = midiOf(p.hz);
    // The note sung, under its vibrato: a jump of more than half a
    // semitone is a new note, taken at once.
    var slow = _slow;
    if (slow == null || (midi - slow).abs() > 0.7) {
      slow = midi;
      _held = 0;
    } else {
      // Heard every [_hop] samples: a tenth of a second's smoothing.
      const k = _hop / (0.1 * 48000);
      slow += (midi - slow) * k;
      _held += _hop;
    }
    _slow = slow;
    // The note sung goes onto the scale; its vibrato is kept, by Vibrato.
    var to = snapNote(slow, _root, _steps) + _vibrato * (midi - slow);
    _target = math.pow(2, (to - midi) * _amount / 12).toDouble();
    // Held a while, eased on more slowly, by Humanise: up to three tenths
    // of a second more once it has been held for a sixth of one.
    var settled = (_held / (48000 / 6)).clamp(0.0, 1.0);
    _easeNow = _easeFor(_retuneMs + _humanise * 300 * settled);
  }

  @override
  void process(Float32List l, Float32List r, int n) {
    for (var i = 0; i < n; i++) {
      var k = _t & (_size - 1);
      _inL[k] = l[i];
      _inR[k] = r[i];
      _t++;
      if (++_sinceHeard >= _hop && _t > _window) {
        _sinceHeard = 0;
        _listen();
      }
      _ratio =
          _easeNow == 0 ? _target : _target + (_ratio - _target) * _easeNow;
      // Lay down every slice due by now: two periods of the input [latency]
      // behind, spaced the period over the ratio, each scaled by 1/ratio
      // as that many more overlap.
      while (_synth <= _t) {
        var at = _synth - latency;
        // The input's own marks a period apart: the one nearest.
        while (_mark + _period < at) {
          _mark += _period;
        }
        if (_mark > at + _period) _mark = at;
        var span = _period.round();
        var centre = _mark.round();
        var out = _synth.round();
        var gain = 1 / _ratio;
        for (var j = -span; j < span; j++) {
          var w = (0.5 + 0.5 * math.cos(math.pi * j / span)) * gain;
          var src = (centre + j) & (_size - 1);
          var dst = (out + j) & (_size - 1);
          _outL[dst] += _inL[src] * w;
          _outR[dst] += _inR[src] * w;
        }
        _synth += _period / _ratio;
      }
      // Take what is due out now and clear it for the next time round.
      var o = (_t - 1 - _settle) & (_size - 1);
      l[i] = _outL[o];
      r[i] = _outR[o];
      _outL[o] = 0;
      _outR[o] = 0;
    }
  }
}

/// PitchListener is a device that only listens (a tuner or a spectrum),
/// keeping the [heard] pitch for the panel to read when [pitch].
class PitchListener implements DeviceProcessor {
  final Float32List _buffer = Float32List(2048);
  final Float32List _ordered = Float32List(2048);
  int _at = 0, _since = 0;
  PitchReading? heard;
  final bool pitch;
  PitchListener({this.pitch = false});

  /// _askedAt is when its reading was last asked for (see asked), on
  /// [_clock]. Not asked for in a second -- nothing showing it -- it stops
  /// listening, and starts again when it is (Ken, 2026-11-08).
  int _askedAt = -1 << 40;
  static final Stopwatch _clock = Stopwatch()..start();

  /// asked notes its reading being read: by a tuner's screen, through
  /// MixGraph.pitchOf.
  void asked() => _askedAt = _clock.elapsedMilliseconds;

  /// listening is whether it is worth working out: shown somewhere lately.
  bool get listening => pitch && _clock.elapsedMilliseconds - _askedAt < 1000;

  @override
  void process(Float32List l, Float32List r, int n) {
    if (!listening) return;
    for (var i = 0; i < n; i++) {
      _buffer[_at] = (l[i] + r[i]) * 0.5;
      _at = (_at + 1) % _buffer.length;
    }
    _since += n;
    if (_since < 1024) return;
    _since = 0;
    for (var i = 0; i < _buffer.length; i++) {
      _ordered[i] = _buffer[(_at + i) % _buffer.length];
    }
    heard = detectPitch(_ordered);
  }
}
