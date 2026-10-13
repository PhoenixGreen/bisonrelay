import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';

// audio_tools.dart is the arithmetic behind the timeline's sound tools:
// ducking music under a voice.
// Pure, so it can be tested without a sound card, and so the tools write
// ordinary clips and envelopes that play and export as anything else does.

/// speechSpans is when somebody is speaking in a recording whose shape is
/// [peaks] across [seconds]: each stretch of sound, with pauses shorter than
/// [gap] bridged, as (from, to) in seconds.
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

/// duckEnvelope is the volume envelope that sinks a clip to [gain] for
/// every span of [spans] -- each in seconds from the clip's start --
/// sinking over [attack] before a span and rising over [release] after it.
///
/// Spans whose dips would meet are one dip: the music does not bob up for a
/// breath between two lines.
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
  // A straight line is two points; a curve is laid down as several, so
  // playing it and exporting it -- both of which join points with straight
  // lines -- follow the same shape.
  const steps = 8;
  double shaped(double t) => switch (curve) {
        DuckCurve.smooth => t * t * (3 - 2 * t),
        _ => t,
      };
  double level(double t) => curve == DuckCurve.natural
      // Even in decibels: from 1 to [gain] along a straight line in dB.
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

/// multiplyEnvelopes is [a] and [b] applied one after the other: their
/// product at every point either has, joined by straight lines between.
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

/// TimedSound is one sound on the run's timeline: its element, where its
/// own timeline starts in the run, and the channel it is on.
typedef TimedSound = ({
  CanvasElement element,
  MediaClip clip,
  int offset,
  String channel
});

/// timedSounds is every sound on the document's timeline, wherever it is --
/// the master, each scene, the transitions -- placed in the run.
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

/// duckEnvelopes is how far each channel is turned down, over the whole
/// run, by the channels that duck the others -- see Ducking. Keyed by
/// channel, in seconds of the run; a channel nothing ducks is not in it.
///
/// [peaksOf] is a recording's shape, or null where it has not been read; a
/// sound not yet read ducks nothing until it has been.
Map<String, List<GainPoint>> duckEnvelopes(
    CanvasDocument doc, Float32List? Function(String assetId) peaksOf) {
  var rate = math.max(1, doc.frameRate).toDouble();
  var sounds = timedSounds(doc);
  // The channels that duck, each with when it is speaking.
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
