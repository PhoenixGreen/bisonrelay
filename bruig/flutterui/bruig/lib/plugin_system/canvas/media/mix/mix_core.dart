import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/decode.dart';
import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/media/mix/mix_graph.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';

// mix_core.dart is the editor's mixer: the sounds playing, each on its
// channel, each channel through its strip, all of them through the master --
// rendered a block at a time for whatever is listening, which is the sound
// card in the editor and a test's own loop in the tests.
//
// It knows nothing of SoLoud or of time passing. It is asked for the next
// block and makes it; the engine around it (dart_audio_engine.dart) decides
// when to ask, and how far ahead of what is being heard to stay.

/// CoreVoice is one sound playing.
class CoreVoice {
  final TrackSource track;
  String? channel;

  /// frame is where the next block will be read from, in the file.
  int frame;

  /// since is where it was last started or moved to: no earlier than this
  /// has been heard since, whatever is still on its way to the speakers.
  int since;

  double _gain;
  double _target;
  double _step = 0;
  bool paused = false;
  bool alive = true;
  bool _stopAtSilence = false;

  /// wait is how many frames are still to be rendered before it starts: a
  /// clip launched on the next bar starts on it to the frame, not on
  /// whichever block the bar fell in.
  int wait = 0;

  /// loopFrom and loopTo are where it goes round, in the file: at loopTo
  /// back to loopFrom. Past the file's end, to loopTo, is silence -- a clip
  /// longer than its sound. Null for once through.
  int? loopFrom, loopTo;

  /// endIn is how many frames more it plays before it is stopped, with a
  /// short fade -- a clip stopped on the next bar. Null for no end set.
  int? endIn;

  CoreVoice._(this.track, this.channel, this.frame, double volume)
      : since = frame,
        _gain = volume,
        _target = volume;

  double get volume => _target;
}

class MixCore {
  final List<CoreVoice> _voices = [];

  /// graph is the routing: channels, sends, returns, master. See
  /// mix_graph.dart.
  final MixGraph graph = MixGraph();

  /// _recent are the last [spectrumSize] samples of each channel, each
  /// return and the master (under ""), mono, for a spectrum.
  final Map<String, Float32List> _recent = {};
  static const int spectrumSize = 512;

  Float32List _tl = Float32List(0), _tr = Float32List(0);

  List<CoreVoice> get voices => List.unmodifiable(_voices);

  CoreVoice play(TrackSource track,
      {required double volume,
      double at = 0,
      String? channel,
      double delay = 0,
      (double, double)? loop}) {
    var start = (at * mixRate).round().clamp(0, track.frames);
    if (start > 0) track.seek(start);
    var v = CoreVoice._(track, channel, start, volume);
    v.wait = math.max(0, (delay * mixRate).round());
    if (loop case (var from, var to) when to > from) {
      v.loopFrom = (from * mixRate).round();
      v.loopTo = math.max(v.loopFrom! + 1, (to * mixRate).round());
    }
    _voices.add(v);
    return v;
  }

  /// _endFade is how long a voice stopped at a time set fades for: long
  /// enough not to click, short enough to end on the bar.
  static const int _endFade = 220;

  /// stopIn stops [v] [delay] seconds from now, to the frame.
  void stopIn(CoreVoice v, double delay) {
    var frames = math.max(0, (delay * mixRate).round());
    // Still waiting to start, and stopped before it does: never heard.
    if (v.wait >= frames) {
      stop(v);
      return;
    }
    v.endIn = frames - v.wait;
  }

  /// volume moves [v] to [to] over [fade] seconds -- in a straight line,
  /// as SoLoud's faders do, so a fade sounds as it did.
  void volume(CoreVoice v, double to, {double fade = 0}) {
    v._target = to;
    var frames = (fade * mixRate).round();
    v._step = frames <= 0 ? 0 : (to - v._gain) / frames;
    if (frames <= 0) v._gain = to;
  }

  void pause(CoreVoice v, bool paused) => v.paused = paused;

  void seek(CoreVoice v, double at) {
    var frame = (at * mixRate).round().clamp(0, v.track.frames);
    v.track.seek(frame);
    v.frame = frame;
    v.since = frame;
  }

  void stop(CoreVoice v) {
    if (!v.alive) return;
    v.alive = false;
    v.track.close();
    _voices.remove(v);
  }

  /// stopSoftly fades [v] out over [fade] seconds, then stops it.
  void stopSoftly(CoreVoice v, double fade) {
    volume(v, 0, fade: fade);
    v._stopAtSilence = true;
    if (fade <= 0) stop(v);
  }

  void setChannel(String key, ChannelMix mix) => graph.setChannel(key, mix);

  void setReturns(List<ReturnChannel> returns) => graph.setReturns(returns);

  void setMaster(MasterMix mix) => graph.setMaster(mix);

  (double, double) levels([String? channel]) => graph.levels(channel);

  /// render makes the next [n] frames of everything into [l] and [r].
  void render(Float32List l, Float32List r, int n) {
    if (_tl.length < n) {
      _tl = Float32List(n);
      _tr = Float32List(n);
    }
    graph.begin(n);
    for (var v in [..._voices]) {
      if (!v.alive || v.paused) continue;
      // Not started yet, or starting part way into this block.
      var offset = 0;
      if (v.wait > 0) {
        if (v.wait >= n) {
          v.wait -= n;
          continue;
        }
        offset = v.wait;
        v.wait = 0;
      }
      var want = n - offset;
      var ending = v.endIn != null;
      if (v.endIn case var left?) want = math.min(want, left);
      var got = _read(v, want);
      var (il, ir) = graph.input(v.channel, n);
      for (var i = 0; i < got; i++) {
        if (v._step != 0) {
          v._gain += v._step;
          if ((v._step > 0 && v._gain >= v._target) ||
              (v._step < 0 && v._gain <= v._target)) {
            v._gain = v._target;
            v._step = 0;
          }
        }
        var g = v._gain;
        if (v.endIn case var left?) {
          var remaining = left - i;
          if (remaining < _endFade) g *= remaining / _endFade;
        }
        il[offset + i] += _tl[i] * g;
        ir[offset + i] += _tr[i] * g;
      }
      if (v.endIn case var left?) v.endIn = left - got;
      if ((ending && v.endIn! <= 0) ||
          got < want ||
          (v._stopAtSilence && v._gain <= 0)) {
        stop(v);
      }
    }
    graph.finish(l, r, n);
    for (var e in graph.heard.entries) {
      _remember(e.key, e.value.$1, e.value.$2, n);
    }
    _remember("", l, r, n);
  }

  /// _read reads [want] frames of [v] into the start of _tl and _tr, going
  /// round its loop -- and through the silence past its file's end, to the
  /// loop's end -- returning how many it read: fewer at the end of a voice
  /// that does not loop.
  int _read(CoreVoice v, int want) {
    var to = v.loopTo, from = v.loopFrom;
    if (to == null || from == null) {
      var got = v.track.read(_tl, _tr, want);
      v.frame += got;
      return got;
    }
    if (_rl.length < want) {
      _rl = Float32List(want);
      _rr = Float32List(want);
    }
    var done = 0;
    while (done < want) {
      var chunk = math.min(want - done, to - v.frame);
      if (chunk <= 0) {
        v.track.seek(from);
        v.frame = from;
        v.since = from;
        continue;
      }
      var got = v.frame < v.track.frames ? v.track.read(_rl, _rr, chunk) : 0;
      for (var i = 0; i < got; i++) {
        _tl[done + i] = _rl[i];
        _tr[done + i] = _rr[i];
      }
      // Past the end of the file, to the loop's end: silence.
      for (var i = got; i < chunk; i++) {
        _tl[done + i] = 0;
        _tr[done + i] = 0;
      }
      v.frame += chunk;
      done += chunk;
    }
    return done;
  }

  Float32List _rl = Float32List(0), _rr = Float32List(0);

  void _remember(String key, Float32List l, Float32List r, int n) {
    var keep = _recent[key] ??= Float32List(spectrumSize);
    if (n >= spectrumSize) {
      for (var i = 0; i < spectrumSize; i++) {
        var k = n - spectrumSize + i;
        keep[i] = (l[k] + r[k]) / 2;
      }
      return;
    }
    keep.setRange(0, spectrumSize - n, keep, n);
    for (var i = 0; i < n; i++) {
      keep[spectrumSize - n + i] = (l[i] + r[i]) / 2;
    }
  }

  /// spectrum is [channel]'s -- or the master's -- last moment of sound as
  /// [spectrumSize] / 2 magnitudes from nothing to half the rate, nought to
  /// about one.
  Float32List? spectrum([String? channel]) {
    var x = _recent[channel ?? ""];
    if (x == null) return null;
    return magnitudes(x);
  }

  /// magnitudes is the spectrum of [x] (a power of two long), Hann-windowed.
  static Float32List magnitudes(Float32List x) {
    var n = x.length;
    var re = Float64List(n), im = Float64List(n);
    for (var i = 0; i < n; i++) {
      re[i] = x[i] * (0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1)));
    }
    // Iterative radix-2, in place.
    for (var i = 1, j = 0; i < n; i++) {
      var bit = n >> 1;
      for (; j & bit != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        var t = re[i];
        re[i] = re[j];
        re[j] = t;
      }
    }
    for (var len = 2; len <= n; len <<= 1) {
      var ang = -2 * math.pi / len;
      for (var i = 0; i < n; i += len) {
        for (var k = 0; k < len ~/ 2; k++) {
          var c = math.cos(ang * k), s = math.sin(ang * k);
          var a = i + k, b = i + k + len ~/ 2;
          var tr = re[b] * c - im[b] * s, ti = re[b] * s + im[b] * c;
          re[b] = re[a] - tr;
          im[b] = im[a] - ti;
          re[a] += tr;
          im[a] += ti;
        }
      }
    }
    var out = Float32List(n ~/ 2);
    for (var i = 0; i < n ~/ 2; i++) {
      out[i] =
          (math.sqrt(re[i] * re[i] + im[i] * im[i]) / (n / 4)).clamp(0.0, 1.0);
    }
    return out;
  }
}
