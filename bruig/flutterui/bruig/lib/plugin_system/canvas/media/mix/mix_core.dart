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
      {required double volume, double at = 0, String? channel}) {
    var start = (at * mixRate).round().clamp(0, track.frames);
    if (start > 0) track.seek(start);
    var v = CoreVoice._(track, channel, start, volume);
    _voices.add(v);
    return v;
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
      var got = v.track.read(_tl, _tr, n);
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
        il[i] += _tl[i] * v._gain;
        ir[i] += _tr[i] * v._gain;
      }
      v.frame += got;
      if (got < n || (v._stopAtSilence && v._gain <= 0)) stop(v);
    }
    graph.finish(l, r, n);
    for (var e in graph.heard.entries) {
      _remember(e.key, e.value.$1, e.value.$2, n);
    }
    _remember("", l, r, n);
  }

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
      out[i] = (math.sqrt(re[i] * re[i] + im[i] * im[i]) / (n / 4))
          .clamp(0.0, 1.0);
    }
    return out;
  }
}
