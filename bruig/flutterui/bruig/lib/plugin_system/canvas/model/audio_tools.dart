import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';

// audio_tools.dart is the arithmetic behind the timeline's sound tools,
// such as ducking music under a voice. Pure, so it tests without a sound
// card and the tools write ordinary clips and envelopes.

/// speechSpans is each stretch of sound in a recording shaped [peaks] over
/// [seconds], pauses shorter than [gap] bridged, as (from, to) in seconds.
List<(double, double)> speechSpans(Float32List peaks, double seconds,
    {double gap = 0.35, double floor = 0.08}) {
  if (peaks.isEmpty || seconds <= 0) return const [];
  var loudest = peaks.fold(0.0, (m, p) => p > m ? p : m);
  if (loudest <= 0) return const [];
  var quiet = loudest * floor;
  var step = seconds / peaks.length;
  var spans = <(double, double)>[];
  double? from;
  double to = 0;
  for (var i = 0; i < peaks.length; i++) {
    if (peaks[i] <= quiet) continue;
    var t = i * step;
    if (from != null && t - to < gap) {
      to = t + step;
      continue;
    }
    if (from != null) spans.add((from, to));
    from = t;
    to = t + step;
  }
  if (from != null) spans.add((from, to));
  return spans;
}

/// duckEnvelope sinks a clip to [gain] for every span (seconds from its
/// start), over [attack] before and [release] after. Dips that would meet
/// are one, so the music does not bob up for a breath between lines.
List<GainPoint> duckEnvelope(List<(double, double)> spans,
    {double gain = 0.25,
    double attack = 0.15,
    double release = 0.45,
    DuckCurve curve = DuckCurve.linear}) {
  // Hard is no fade: a step, as near as two points can make one.
  if (curve == DuckCurve.hard) {
    attack = 0.001;
    release = 0.001;
  }
  var merged = <(double, double)>[];
  for (var s in [...spans]..sort((a, b) => a.$1.compareTo(b.$1))) {
    if (merged.isNotEmpty && s.$1 - attack <= merged.last.$2 + release) {
      var last = merged.removeLast();
      merged.add((last.$1, math.max(last.$2, s.$2)));
    } else {
      merged.add(s);
    }
  }
  // A curve is laid down as several points, so playing and exporting (both
  // joining points with straight lines) follow the same shape.
  const steps = 8;
  double shaped(double t) => switch (curve) {
        DuckCurve.smooth => t * t * (3 - 2 * t),
        _ => t,
      };
  double level(double t) => curve == DuckCurve.natural
      // Even in decibels: a straight line in dB from 1 to [gain].
      ? math.pow(gain, t).toDouble()
      : 1 + (gain - 1) * shaped(t);
  var many = curve == DuckCurve.smooth || curve == DuckCurve.natural;
  return [
    for (var (from, to) in merged) ...[
      if (many)
        for (var i = 0; i <= steps; i++)
          GainPoint(from - attack + attack * i / steps, level(i / steps))
      else ...[
        GainPoint(from - attack, 1),
        GainPoint(from, gain),
      ],
      if (many)
        for (var i = 0; i <= steps; i++)
          GainPoint(to + release * i / steps, level(1 - i / steps))
      else ...[
        GainPoint(to, gain),
        GainPoint(to + release, 1),
      ],
    ],
  ];
}

/// multiplyEnvelopes is [a] then [b]: their product at every point of
/// either, joined by straight lines.
List<GainPoint> multiplyEnvelopes(List<GainPoint> a, List<GainPoint> b) {
  if (a.isEmpty) return b;
  if (b.isEmpty) return a;
  var times = <double>{for (var p in a) p.time, for (var p in b) p.time}
      .toList()
    ..sort();
  return [
    for (var t in times) GainPoint(t, envelopeAt(a, t) * envelopeAt(b, t)),
  ];
}

/// TimedSound is one sound on the run: its element, where its timeline
/// starts in the run, and its channel.
typedef TimedSound = ({
  CanvasElement element,
  MediaClip clip,
  int offset,
  String channel
});

/// timedSounds is every sound on the document's timeline (master, scenes,
/// transitions), placed in the run.
List<TimedSound> timedSounds(CanvasDocument doc) {
  TimedSound? of(CanvasElement e, int offset) {
    var clip = switch (e) {
      AudioElement a => a.clip,
      VideoElement v when !v.isLink => v.clip,
      _ => null,
    };
    if (clip == null || !clip.timed || clip.isEmpty) return null;
    return (
      element: e,
      clip: clip,
      offset: offset,
      channel: clip.channel.isNotEmpty ? clip.channel : e.id,
    );
  }

  var scenes = doc.allScenes;
  return [
    for (var (i, scene) in scenes.indexed)
      for (var e in scene.elements)
        if (of(e, doc.hasScenes ? doc.startOfScene(i) : 0) case var t?) t,
    if (doc.masterScene case var m?)
      for (var e in m.elements)
        if (of(e, 0) case var t?) t,
    for (var e in doc.transitionSounds)
      if (of(e, 0) case var t?) t,
  ];
}

/// _timedOf caches each document's timed sounds: a followed channel is
/// asked about every frame.
final Expando<List<TimedSound>> _timedOf = Expando("timedSounds");

/// channelLevelAt is how loud [channel] is [seconds] into the run, 0 to 1,
/// from its recordings' [peaksOf] (unread is silent), averaged over the
/// [window] before, as a smoothed meter. The same played and exported.
double channelLevelAt(CanvasDocument doc, String channel, double seconds,
    Float32List? Function(String assetId) peaksOf,
    {double window = 0}) {
  var sounds = _timedOf[doc] ??= timedSounds(doc);
  var rate = math.max(1, doc.frameRate).toDouble();
  var loudest = 0.0;
  for (var s in sounds) {
    if (s.channel != channel || s.clip.muted) continue;
    var source = s.clip.playlist.firstOrNull;
    if (source == null || source.length <= 0) continue;
    var begins = (s.offset + s.clip.at) / rate;
    var end = source.end > 0 ? source.end : source.length;
    var local = seconds - begins + source.start;
    if (local < source.start || local > end) continue;
    var peaks = peaksOf(source.assetId);
    if (peaks == null || peaks.isEmpty) continue;
    int index(double t) =>
        (t / source.length * peaks.length).floor().clamp(0, peaks.length - 1);
    var from = index(math.max(source.start, local - window)), to = index(local);
    var sum = 0.0;
    for (var i = from; i <= to; i++) {
      sum += peaks[i];
    }
    var level = sum / (to - from + 1) * s.clip.volume;
    if (level > loudest) loudest = level;
  }
  return loudest.clamp(0.0, 1.0);
}

/// duckEnvelopes is how far each channel is turned down over the run by the
/// ducking channels (see Ducking), by channel, in run seconds; a channel
/// nothing ducks is absent. [peaksOf] is null for an unread recording,
/// which ducks nothing until read.
Map<String, List<GainPoint>> duckEnvelopes(
    CanvasDocument doc, Float32List? Function(String assetId) peaksOf) {
  var rate = math.max(1, doc.frameRate).toDouble();
  var sounds = timedSounds(doc);
  // The ducking channels, each with when it speaks.
  var ducking = <String, Ducking>{};
  var speech = <String, List<(double, double)>>{};
  for (var s in sounds) {
    if (!s.clip.mix.duck.on) continue;
    ducking[s.channel] = s.clip.mix.duck;
    var source = s.clip.playlist.firstOrNull;
    if (source == null || source.length <= 0) continue;
    var peaks = peaksOf(source.assetId);
    if (peaks == null) continue;
    var begins = (s.offset + s.clip.at) / rate;
    var end = source.end > 0 ? source.end : source.length;
    for (var (a, b) in speechSpans(peaks, source.length)) {
      if (b <= source.start || a >= end) continue;
      (speech[s.channel] ??= []).add((
        begins + math.max(a, source.start) - source.start,
        begins + math.min(b, end) - source.start,
      ));
    }
  }
  if (ducking.isEmpty) return const {};
  var dips = {
    for (var e in ducking.entries)
      e.key: duckEnvelope(speech[e.key] ?? const [],
          gain: dbToGain(e.value.depthDb),
          attack: e.value.attack,
          release: e.value.release,
          curve: e.value.curve),
  };
  var out = <String, List<GainPoint>>{};
  for (var channel in {for (var s in sounds) s.channel}) {
    var env = <GainPoint>[];
    for (var e in ducking.entries) {
      if (e.key == channel || e.value.except.contains(channel)) continue;
      env = multiplyEnvelopes(env, dips[e.key]!);
    }
    if (env.isNotEmpty) out[channel] = env;
  }
  return out;
}
