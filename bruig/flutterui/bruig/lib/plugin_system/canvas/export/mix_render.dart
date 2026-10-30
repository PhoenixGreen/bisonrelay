import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/export/export_media.dart';
import 'package:bruig/plugin_system/canvas/media/mix/decode.dart';
import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/media/mix/mix_graph.dart';
import 'package:bruig/plugin_system/canvas/model/automation.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/surround.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

// mix_render.dart renders the timeline's sound -- every stretch placed by
// ExportMedia.sounds -- through the mix, into a WAV file: each channel's
// stretches summed and played through its strip once, the channels summed
// into the master, the master brought to its loudness target where it is
// asked to be, and limited. ffmpeg only decodes the files going in and
// encodes the one coming out; the mixing is dsp.dart's, the same arithmetic
// the editor plays.
//
// Run in an isolate: it is a few seconds of arithmetic for a few minutes of
// sound, and the window should not stop while it happens.

/// renderMixWav writes [sounds] mixed through [master] to [out], [seconds]
/// long: a 48kHz float WAV of every one of [speakers] -- or, [fold], their
/// fold-down to two, for a file that can carry no more. False where nothing
/// could be decoded.
Future<bool> renderMixWav(List<ExportSound> sounds, MasterMix master,
        {required double seconds,
        required String ffmpeg,
        required String out,
        List<ReturnChannel> returns = const [],
        SpeakerLayout speakers = SpeakerLayout.stereo,
        bool fold = false}) =>
    Isolate.run(() => _render(
        sounds, master, returns, seconds, ffmpeg, out, speakers, fold));

const int _block = 4096;

/// _Stretch is one stretch decoded, with what it is played at.
class _Stretch {
  final ExportSound sound;
  final Float32List l, r;
  final int start;
  _Stretch(this.sound, this.l, this.r)
      : start = (sound.at * mixRate).round();
  int get end => start + l.length;
}

Future<bool> _render(
    List<ExportSound> sounds,
    MasterMix master,
    List<ReturnChannel> returns,
    double seconds,
    String ffmpeg,
    String out,
    SpeakerLayout speakers,
    bool fold) async {
  var total = math.max(0, (seconds * mixRate).round());
  // Each stretch decoded once, and grouped by the channel it plays through.
  var channels = <String, List<_Stretch>>{};
  var strips = <String, ChannelMix>{};
  var places = <String, List<(double, Heard)>>{};
  var clocks = <String, double>{};
  var decodedAny = false;
  // A muted channel a vocoder takes its carrier from is still decoded:
  // unheard itself, it is heard through the vocoder.
  var carriers = {
    for (var s in sounds)
      for (var d in s.mix.devices)
        if (d.sidechain case var c?) c,
    for (var r in returns)
      for (var d in r.devices)
        if (d.sidechain case var c?) c,
  };
  for (var (i, s) in sounds.indexed) {
    if (s.mix.mute && !carriers.contains(s.channel)) continue;
    var pcm = await _decode(ffmpeg, s);
    if (pcm == null) continue;
    decodedAny = true;
    var key = s.channel.isNotEmpty ? s.channel : "#$i";
    (channels[key] ??= []).add(_Stretch(s, pcm.$1, pcm.$2));
    strips.putIfAbsent(key, () => s.mix);
    clocks.putIfAbsent(key, () => s.clock);
    // Where a channel is heard from, from its first placed sound.
    if (s.place.isNotEmpty) places.putIfAbsent(key, () => s.place);
  }
  if (!decodedAny) return false;
  var written = fold ? 2 : speakers.channels;

  // A first pass to hear how loud it comes out, where a target is asked
  // for; then the pass that is kept, at the gain that reaches it.
  var normalise = 0.0;
  if (master.normalise) {
    // Measured as it will be written: every speaker, weighted as BS.1770
    // says, or the two it is folded down to.
    var weights = fold ? const [1.0, 1.0] : loudnessWeights(speakers);
    var meter = SpeakerLoudness(weights);
    _pass(channels, strips, places, clocks, master, returns, total, 0, speakers,
        fold, (out, n) => meter.add(out, n),
        limit: false);
    var heard = meter.integrated;
    if (heard.isFinite) normalise = (master.target - heard).clamp(-30.0, 30.0);
  }
  // Block by block onto the disk: a long mix held whole is hundreds of
  // megabytes nobody needs at once.
  var file = File(out).openSync(mode: FileMode.write);
  try {
    file.writeFromSync(wavHeader(total, written));
    var interleaved = Float32List(_block * written);
    _pass(channels, strips, places, clocks, master, returns, total, normalise,
        speakers, fold, (out, n) {
      for (var i = 0; i < n; i++) {
        for (var c = 0; c < written; c++) {
          interleaved[i * written + c] = out[c][i];
        }
      }
      file.writeFromSync(
          interleaved.buffer.asUint8List(), 0, n * 4 * written);
    });
  } finally {
    file.closeSync();
  }
  return true;
}

/// _pass runs the whole mix once, block by block, through the one routing
/// there is -- see mix_graph.dart -- handing each finished block of the
/// master to [take].
void _pass(
    Map<String, List<_Stretch>> channels,
    Map<String, ChannelMix> strips,
    Map<String, List<(double, Heard)>> places,
    Map<String, double> clocks,
    MasterMix master,
    List<ReturnChannel> returns,
    int total,
    double normaliseDb,
    SpeakerLayout speakers,
    bool fold,
    void Function(List<Float32List> out, int n) take,
    {bool limit = true}) {
  var graph = MixGraph()
    ..setSpeakers(speakers)
    ..setReturns(returns)
    ..setMaster(master, normaliseDb: normaliseDb);
  // Each from where its lanes start it, not glided to there from its own
  // settings over the first block.
  for (var key in channels.keys) {
    graph.setChannel(key, automatedAt(strips[key]!, -(clocks[key] ?? 0)));
  }
  var ml = Float32List(_block), mr = Float32List(_block);
  for (var at = 0; at < total; at += _block) {
    var n = math.min(_block, total - at);
    // Where each placed channel is heard from, at the middle of the block:
    // the graph glides to it over the block.
    var middle = (at + n / 2) / mixRate;
    for (var e in places.entries) {
      graph.setPlacement(e.key, heardOn(e.value, middle));
    }
    // Each automated channel as its lanes have it there: retuned, not made
    // again -- see MixGraph.setChannel.
    for (var e in strips.entries) {
      if (e.value.automation.isEmpty) continue;
      graph.setChannel(
          e.key, automatedAt(e.value, middle - (clocks[e.key] ?? 0)));
    }
    graph.begin(n);
    for (var entry in channels.entries) {
      var (cl, cr) = graph.input(entry.key, n);
      for (var s in entry.value) {
        if (s.end <= at || s.start >= at + n) continue;
        _addStretch(s, at, n, cl, cr);
      }
    }
    graph.finish(ml, mr, n, limit: limit);
    take(fold || !speakers.isSurround ? [ml, mr] : graph.speakers, n);
  }
}

/// heardOn is where a placed sound is heard from at [seconds], from its
/// [points] -- each (seconds, where), in order: the last at or before it,
/// or the first.
Heard? heardOn(List<(double, Heard)> points, double seconds) {
  if (points.isEmpty) return null;
  var lo = 0, hi = points.length - 1;
  if (seconds <= points[0].$1) return points[0].$2;
  while (lo < hi) {
    var mid = (lo + hi + 1) ~/ 2;
    if (points[mid].$1 <= seconds) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return points[lo].$2;
}

/// _addStretch adds the part of [s] inside the block at [at] to [l] and
/// [r], at its volume, through its fades and its envelope.
void _addStretch(_Stretch s, int at, int n, Float32List l, Float32List r) {
  var sound = s.sound;
  var from = math.max(at, s.start), to = math.min(at + n, s.end);
  var length = sound.length;
  for (var i = from; i < to; i++) {
    var k = i - s.start;
    var t = k / mixRate;
    var g = sound.volume;
    if (sound.fadeIn > 0 && t < sound.fadeIn) g *= t / sound.fadeIn;
    if (sound.fadeOut > 0 && t > length - sound.fadeOut) {
      g *= math.max(0, (length - t) / sound.fadeOut);
    }
    if (sound.envelope.isNotEmpty) g *= envelopeAt(sound.envelope, t);
    l[i - at] += s.l[k] * g;
    r[i - at] += s.r[k] * g;
  }
}

/// _decode is [s]'s part of its file as 48kHz stereo -- see ffmpegDecode.
Future<(Float32List, Float32List)?> _decode(String ffmpeg, ExportSound s) =>
    ffmpegDecode(ffmpeg, s.path, from: s.from, length: s.length);

/// wavHeader is the header of a 32-bit float WAV of [frames] in
/// [channels]. More than two is WAVE_FORMAT_EXTENSIBLE, with the speakers
/// named in its channel mask -- ffmpeg's 5.1 (FL FR FC LFE BL BR) and 7.1
/// (and SL SR) -- so whatever reads it knows which is which.
@visibleForTesting
Uint8List wavHeader(int frames, [int channels = 2]) {
  var extensible = channels > 2;
  var fmt = extensible ? 40 : 16;
  var data = frames * 4 * channels;
  var b = ByteData(28 + fmt);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, "RIFF");
  b.setUint32(4, 20 + fmt + data, Endian.little);
  tag(8, "WAVE");
  tag(12, "fmt ");
  b.setUint32(16, fmt, Endian.little);
  b.setUint16(20, extensible ? 0xFFFE : 3, Endian.little); // IEEE float
  b.setUint16(22, channels, Endian.little);
  b.setUint32(24, mixRate, Endian.little);
  b.setUint32(28, mixRate * 4 * channels, Endian.little);
  b.setUint16(32, 4 * channels, Endian.little);
  b.setUint16(34, 32, Endian.little);
  if (extensible) {
    b.setUint16(36, 22, Endian.little);
    b.setUint16(38, 32, Endian.little);
    b.setUint32(40, channels == 8 ? 0x63F : 0x3F, Endian.little);
    // KSDATAFORMAT_SUBTYPE_IEEE_FLOAT
    const guid = [3, 0, 0, 0, 0, 0, 0x10, 0, 0x80, 0, 0, 0xAA, 0, 0x38, 0x9B, 0x71];
    for (var i = 0; i < 16; i++) {
      b.setUint8(44 + i, guid[i]);
    }
  }
  tag(20 + fmt, "data");
  b.setUint32(24 + fmt, data, Endian.little);
  return b.buffer.asUint8List();
}
