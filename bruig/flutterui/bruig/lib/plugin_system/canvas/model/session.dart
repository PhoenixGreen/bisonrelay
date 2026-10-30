import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/automation.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart'
    show Quantise;
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';

// session.dart is the session view's clips: Ableton's grid of clip slots, a
// column for each channel and a row for each scene. A clip is launched live
// -- on the next bar -- and loops until another on its channel is launched
// or it is stopped; a scene launches its whole row at once. What is played
// can be written onto the timeline, which is how a song is put together
// from them. See CanvasController.launchClip.
//
// A clip is a sound -- part of a file -- on an audio channel, or notes on a
// MIDI channel, played by the channel's instrument. Its notes are counted in
// beats, not seconds, so a change of tempo plays them faster rather than
// moving them; they are rendered into a file to be played, as a part on the
// timeline is (see part_render.dart).

/// LaunchMode is what a press on a clip does.
enum LaunchMode {
  /// trigger plays it, from the next bar, until something stops it.
  trigger("Trigger", "Press to play it from the next bar"),

  /// gate plays it only while it is held down.
  gate("Gate", "Plays while it is held down"),

  /// toggle plays it, and stops it pressed again.
  toggle("Toggle", "Press to play it, and again to stop it"),

  /// repeat plays it from its start on every launch step -- the clip's
  /// quantise, or the song's -- while it is held, and stops let go: a
  /// stutter, a drum roll.
  repeat("Repeat", "Plays it again on every step while it is held");

  final String label;
  final String hint;
  const LaunchMode(this.label, this.hint);
}

/// FollowAction is what a clip does when it has played -- Ableton's follow
/// actions: another clip on its channel launched, itself again, or a stop.
enum FollowAction {
  none("Nothing"),
  next("Next clip"),
  previous("Previous clip"),
  first("First clip"),
  last("Last clip"),
  any("Any clip"),
  other("Another clip"),
  again("Play again"),
  stop("Stop");

  final String label;
  const FollowAction(this.label);
}

/// WarpMode is how a warped sound is stretched -- see warp.dart.
enum WarpMode {
  beats("Beats", "Drums and rhythm: cut at its hits, each kept sharp"),
  tones("Tones", "One voice or instrument at a time, with a clear pitch"),
  texture("Texture", "Pads, noise, washes: no clear hits or pitch"),
  repitch("Re-pitch", "Like a record sped up: faster is higher"),
  complex("Complex", "Whole mixes and vocals: the most even");

  final String label;
  final String hint;
  const WarpMode(this.label, this.hint);
}

/// WarpMarker pins a moment of a sound -- [seconds] into what it plays --
/// to a beat of the clip.
typedef WarpMarker = ({double seconds, double beat});

/// WarpMap is where each moment of a warped sound falls on the clip's
/// beats: through its start, at nought, and its markers, straight between
/// them; past the last, at its tempo.
class WarpMap {
  final double bpm;
  final List<WarpMarker> points;

  WarpMap(this.bpm, List<WarpMarker> markers) : points = _ordered(bpm, markers);

  static List<WarpMarker> _ordered(double bpm, List<WarpMarker> markers) {
    var out = <WarpMarker>[(seconds: 0, beat: 0)];
    for (var m in [...markers]
      ..sort((a, b) => a.seconds.compareTo(b.seconds))) {
      var last = out.last;
      // Only forward in both: a marker dragged past its neighbour is not
      // a sound played backwards.
      if (m.seconds > last.seconds + 1e-4 && m.beat > last.beat + 1e-4) {
        out.add(m);
      }
    }
    return out;
  }

  double get _perSecond => math.max(1e-3, bpm) / 60;

  /// beatAt is the beat [seconds] into the sound falls on.
  double beatAt(double seconds) {
    for (var i = 0; i + 1 < points.length; i++) {
      var a = points[i], b = points[i + 1];
      if (seconds <= b.seconds) {
        return a.beat +
            (seconds - a.seconds) * (b.beat - a.beat) / (b.seconds - a.seconds);
      }
    }
    var last = points.last;
    return last.beat + (seconds - last.seconds) * _perSecond;
  }

  /// sourceAt is the moment of the sound that falls on [beat].
  double sourceAt(double beat) {
    for (var i = 0; i + 1 < points.length; i++) {
      var a = points[i], b = points[i + 1];
      if (beat <= b.beat) {
        return a.seconds +
            (beat - a.beat) * (b.seconds - a.seconds) / (b.beat - a.beat);
      }
    }
    var last = points.last;
    return last.seconds + (beat - last.beat) / _perSecond;
  }
}

/// ClipEnvelope is what an audio clip's envelope changes as it plays: its
/// gain -- only ever down, from nought (silent) to one (its own gain) -- or
/// its pan, from nought (left) to one (right).
enum ClipEnvelope {
  gain("Gain", 1),
  pan("Pan", 0.5);

  final String label;

  /// rest is its value with no envelope: as the clip is.
  final double rest;
  const ClipEnvelope(this.label, this.rest);
}

/// curveAt is [points]' value at [beat]: straight between points, held
/// before the first and after the last -- or [rest] with none.
double curveAt(List<ControlPoint> points, double beat, double rest) {
  if (points.isEmpty) return rest;
  if (beat <= points.first.$1) return points.first.$2;
  for (var i = 0; i + 1 < points.length; i++) {
    var (a, va) = points[i];
    var (b, vb) = points[i + 1];
    if (beat <= b) return b <= a ? vb : va + (vb - va) * (beat - a) / (b - a);
  }
  return points.last.$2;
}

/// clipBarChoices are the lengths a clip is offered, in bars.
const clipBarChoices = [1, 2, 4, 8, 16, 32];

class SessionClip {
  /// id is the clip's own, kept through every change, for what is playing
  /// to be found by.
  final String id;
  final String name;

  /// color is its index in sectionColors.
  final int color;

  /// midi is whether it is notes, for the channel's instrument, rather than
  /// a sound.
  final bool midi;

  /// sound is what it plays: for an audio clip, the file and its range; for
  /// a MIDI clip, its notes rendered -- see [rendered] -- or null until
  /// they have been.
  final MediaSource? sound;

  /// notes are a MIDI clip's, their starts and lengths in beats from the
  /// clip's start.
  final List<MidiNote> notes;

  /// controls are a MIDI clip's controllers' curves, in beats from its
  /// start -- see MidiControl.
  final Map<MidiControl, List<ControlPoint>> controls;

  /// bars is how long its loop is: it goes round at the end, and a sound
  /// longer than it is cut there. Not looping, it plays from [start] to the
  /// loop's end and stops.
  final double bars;
  final bool loop;
  final LaunchMode launch;

  /// start is where it starts playing, and loopStart where its loop starts
  /// -- both in beats into what it plays. Started before its loop, it plays
  /// on into it, as Ableton's does.
  final double start;
  final double loopStart;

  /// gain is how much louder or quieter it is played, in decibels.
  final double gain;

  /// reversedOf is the sound it played before it was reversed -- its own
  /// file, kept, so Reverse undone gives it back.
  final MediaSource? reversedOf;

  /// quantise is what its launch waits for, or null for the song's.
  final Quantise? quantise;

  /// legato is whether it takes over from where the clip playing on its
  /// channel had got to, rather than from its start.
  final bool legato;

  /// velocity is how much the launching pad's velocity sets its volume,
  /// nought to one: nought, none -- as loud played softly as hard; one, a
  /// pad barely touched barely heard. A click is a full velocity.
  final double velocity;

  /// follow is what happens when it has played for [followBars] -- its
  /// loop's length, with none.
  final FollowAction follow;
  final double? followBars;

  /// warp is whether an audio clip keeps the song's tempo: its sound laid
  /// on the beats at its own [bpm] -- or, where its [markers] say, moment
  /// by moment -- and stretched to fit, in [warpMode]. Unwarped, it plays
  /// at its own speed.
  final bool warp;
  final WarpMode warpMode;

  /// bpm is the tempo the sound was played at; nought, not yet known.
  final double bpm;
  final List<WarpMarker> markers;

  /// pitch is how far it is moved, in semitones, and cents in hundredths
  /// of one. Unwarped -- or in Re-pitch -- it is faster or slower with it.
  final int pitch;
  final int cents;

  /// warped is its sound warped, rendered at the song's tempo, and
  /// [warpedFor] what it was rendered from -- see warpSignature.
  final MediaSource? warped;
  final String warpedFor;

  /// envelopes are an audio clip's changes as it plays -- see ClipEnvelope
  /// -- each points of a beat into what it plays and a value, in order. They
  /// go round with its loop, and are part of what is rendered for it.
  final Map<ClipEnvelope, List<ControlPoint>> envelopes;

  /// automation is its envelopes of its channel's settings -- the volume,
  /// a send, a device's knob -- moved while it plays: see ClipAutomation.
  /// Not rendered into its sound, as gain and pan are; played on the
  /// channel as it goes.
  final List<ClipAutomation> automation;

  /// curveOf is the envelope [key] -- a ClipEnvelope's name, or a setting's
  /// id (see AutomationTarget) -- as its points, a beat and a height.
  List<ControlPoint> curveOf(String key) {
    for (var e in ClipEnvelope.values) {
      if (e.name == key) return envelopes[e] ?? const [];
    }
    return automation.where((a) => a.target == key).firstOrNull?.points ??
        const [];
  }

  /// withCurve is the clip with envelope [key]'s points [points]: one of
  /// a setting's made for its first point, and taken away with its last.
  SessionClip withCurve(String key, List<ControlPoint> points) {
    var sorted = [...points]..sort((a, b) => a.$1.compareTo(b.$1));
    for (var e in ClipEnvelope.values) {
      if (e.name == key) return copyWith(envelopes: {...envelopes, e: sorted});
    }
    var was = automation.where((a) => a.target == key).firstOrNull;
    return copyWith(automation: [
      for (var a in automation)
        if (a.target != key) a,
      if (sorted.isNotEmpty)
        (was ?? ClipAutomation(key)).copyWith(points: sorted),
    ]);
  }

  /// lengthOf is envelope [key]'s own length in beats, or null for one
  /// that goes with the clip's loop -- gain and pan always do.
  double? lengthOf(String key) =>
      automation.where((a) => a.target == key).firstOrNull?.length;

  /// withLength gives envelope [key] its own [length], or links it to the
  /// clip's loop with null. A setting's envelope with no points yet is
  /// made for it.
  SessionClip withLength(String key, double? length) {
    if (ClipEnvelope.values.any((e) => e.name == key)) return this;
    var was = automation.where((a) => a.target == key).firstOrNull ??
        ClipAutomation(key);
    return copyWith(automation: [
      for (var a in automation)
        if (a.target != key) a,
      was.copyWith(length: length, linked: length == null),
    ]);
  }

  /// mediaIds is every stored sound it uses: its own, what it was before
  /// it was reversed, and what was rendered for it -- warped, or a MIDI
  /// clip's notes played. Left out, the library's tidy after a save
  /// deleted them, and the clip came back with no sound.
  Set<String> get mediaIds => {
        for (var s in [sound, reversedOf, warped])
          if (s != null) ...[
            if (s.assetId.isNotEmpty) s.assetId,
            if (s.soundId.isNotEmpty) s.soundId,
          ],
      };

  /// warpMap is where its sound falls on its beats.
  WarpMap get warpMap => WarpMap(bpm, markers);

  /// needsRender is whether it plays a rendered sound -- warped, or moved
  /// in pitch -- rather than its own.
  bool get needsRender =>
      !midi &&
      (warp ||
          pitch != 0 ||
          cents != 0 ||
          envelopes.values.any((e) => e.isNotEmpty));

  /// warpSignature is what its rendered sound is made from, at
  /// [secondsPerBeat]: when it changes, it is rendered again.
  String warpSignature(double secondsPerBeat) => [
        sound?.assetId,
        sound?.start,
        sound?.end,
        warp,
        warpMode.name,
        bpm,
        for (var m in markers) "${m.seconds}@${m.beat}",
        pitch,
        cents,
        for (var e in envelopes.entries)
          if (e.value.isNotEmpty)
            "${e.key.name}=${e.value.map((p) => "${p.$1},${p.$2}").join(";")}",
        if (warp || envelopes.values.any((e) => e.isNotEmpty)) secondsPerBeat,
      ].join(":");

  /// rendered is what [sound] was played from, for a MIDI clip: its
  /// signature, so it is played again only when that changes.
  final String rendered;

  const SessionClip({
    required this.id,
    this.name = "",
    this.color = 0,
    this.midi = false,
    this.sound,
    this.notes = const [],
    this.controls = const {},
    this.bars = 1,
    this.loop = true,
    this.launch = LaunchMode.trigger,
    this.rendered = "",
    this.start = 0,
    this.loopStart = 0,
    this.gain = 0,
    this.reversedOf,
    this.quantise,
    this.legato = false,
    this.velocity = 0,
    this.follow = FollowAction.none,
    this.followBars,
    this.warp = false,
    this.warpMode = WarpMode.complex,
    this.bpm = 0,
    this.markers = const [],
    this.pitch = 0,
    this.cents = 0,
    this.warped,
    this.warpedFor = "",
    this.envelopes = const {},
    this.automation = const [],
  });

  /// loopEnd is where its loop ends, in beats, at [beatsPerBar].
  double loopEnd(int beatsPerBar) => loopStart + bars * beatsPerBar;

  SessionClip copyWith({
    String? id,
    String? name,
    int? color,
    MediaSource? sound,
    bool clearSound = false,
    List<MidiNote>? notes,
    Map<MidiControl, List<ControlPoint>>? controls,
    double? bars,
    bool? loop,
    LaunchMode? launch,
    String? rendered,
    double? start,
    double? loopStart,
    double? gain,
    MediaSource? reversedOf,
    bool clearReversed = false,
    Quantise? quantise,
    bool clearQuantise = false,
    bool? legato,
    double? velocity,
    FollowAction? follow,
    double? followBars,
    bool clearFollowBars = false,
    bool? warp,
    WarpMode? warpMode,
    double? bpm,
    List<WarpMarker>? markers,
    int? pitch,
    int? cents,
    MediaSource? warped,
    String? warpedFor,
    Map<ClipEnvelope, List<ControlPoint>>? envelopes,
    List<ClipAutomation>? automation,
  }) =>
      SessionClip(
        id: id ?? this.id,
        name: name ?? this.name,
        color: color ?? this.color,
        midi: midi,
        sound: clearSound ? null : sound ?? this.sound,
        notes: notes ?? this.notes,
        controls: controls ?? this.controls,
        bars: math.max(0.25, bars ?? this.bars),
        loop: loop ?? this.loop,
        launch: launch ?? this.launch,
        rendered: rendered ?? this.rendered,
        start: math.max(0, start ?? this.start),
        loopStart: math.max(0, loopStart ?? this.loopStart),
        gain: (gain ?? this.gain).clamp(-70.0, 24.0),
        reversedOf: clearReversed ? null : reversedOf ?? this.reversedOf,
        quantise: clearQuantise ? null : quantise ?? this.quantise,
        legato: legato ?? this.legato,
        velocity: (velocity ?? this.velocity).clamp(0.0, 1.0),
        follow: follow ?? this.follow,
        followBars: clearFollowBars
            ? null
            : (followBars ?? this.followBars) == null
                ? null
                : math.max(0.25, (followBars ?? this.followBars)!),
        warp: warp ?? this.warp,
        warpMode: warpMode ?? this.warpMode,
        bpm: (bpm ?? this.bpm).clamp(0.0, 999.0),
        markers: markers ?? this.markers,
        pitch: (pitch ?? this.pitch).clamp(-48, 48),
        cents: (cents ?? this.cents).clamp(-50, 50),
        warped: warped ?? this.warped,
        warpedFor: warpedFor ?? this.warpedFor,
        envelopes: envelopes ?? this.envelopes,
        automation: automation ?? this.automation,
      );

  /// signature is what a MIDI clip's sound is played from, with [part]'s
  /// instrument: when it changes, the sound is played again.
  String signature(InstrumentPart part, double secondsPerBeat) =>
      "${part.sound.name}:${part.look.name}:${part.bank}:${part.program}:"
      "${part.effects.where((e) => e.on).join(";")}:"
      "$secondsPerBeat:$bars:"
      "${notes.map((n) => n.toJson().join(",")).join(";")}:"
      "${controls.isEmpty ? "" : controlsToJson(controls)}";

  /// partOf is the clip as a part for [part]'s instrument to play: its notes
  /// in seconds, at [secondsPerBeat], for the clip's whole length.
  InstrumentPart partOf(InstrumentPart part, double secondsPerBeat) =>
      part.copyWith(notes: [
        for (var n in notes)
          MidiNote(n.key, n.start * secondsPerBeat, n.length * secondsPerBeat,
              n.velocity),
      ], controls: {
        for (var e in controls.entries)
          e.key: [for (var (t, v) in e.value) (t * secondsPerBeat, v)],
      });

  Map<String, dynamic> toJson() => {
        "id": id,
        if (name.isNotEmpty) "name": name,
        if (color != 0) "color": color,
        if (midi) "midi": true,
        if (sound case var s?) "sound": s.toJson(),
        if (notes.isNotEmpty) "notes": [for (var n in notes) n.toJson()],
        if (controls.isNotEmpty) "controls": controlsToJson(controls),
        "bars": bars,
        if (!loop) "loop": false,
        if (launch != LaunchMode.trigger) "launch": launch.name,
        if (rendered.isNotEmpty) "rendered": rendered,
        if (start != 0) "start": start,
        if (loopStart != 0) "loopStart": loopStart,
        if (gain != 0) "gain": gain,
        if (reversedOf case var r?) "reversedOf": r.toJson(),
        if (quantise case var q?) "quantise": q.name,
        if (legato) "legato": true,
        if (velocity != 0) "velocity": velocity,
        if (follow != FollowAction.none) "follow": follow.name,
        if (followBars case var f?) "followBars": f,
        if (warp) "warp": true,
        if (warpMode != WarpMode.complex) "warpMode": warpMode.name,
        if (bpm != 0) "bpm": bpm,
        if (markers.isNotEmpty)
          "markers": [
            for (var m in markers) [m.seconds, m.beat]
          ],
        if (pitch != 0) "pitch": pitch,
        if (cents != 0) "cents": cents,
        if (warped case var w?) "warped": w.toJson(),
        if (warpedFor.isNotEmpty) "warpedFor": warpedFor,
        if (envelopes.values.any((e) => e.isNotEmpty))
          "envelopes": {
            for (var e in envelopes.entries)
              if (e.value.isNotEmpty)
                e.key.name: [
                  for (var (b, v) in e.value) [b, v]
                ],
          },
        if (automation.isNotEmpty)
          "automation": [for (var a in automation) a.toJson()],
      };

  static SessionClip? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    var id = jsonString(json["id"], "");
    if (id.isEmpty) return null;
    var sound = json["sound"];
    return SessionClip(
      id: id,
      name: jsonString(json["name"], ""),
      color: jsonInt(json["color"], 0),
      midi: jsonBool(json["midi"], false),
      sound: sound is Map<String, dynamic> ? MediaSource.fromJson(sound) : null,
      notes: [
        if (json["notes"] case List notes)
          for (var n in notes)
            if (MidiNote.fromJson(n) case var note?) note,
      ],
      controls: controlsFromJson(json["controls"]),
      bars: math.max(0.25, jsonDouble(json["bars"], 1)),
      loop: jsonBool(json["loop"], true),
      launch: LaunchMode.values
              .where((m) => m.name == json["launch"])
              .firstOrNull ??
          LaunchMode.trigger,
      rendered: jsonString(json["rendered"], ""),
      start: math.max(0, jsonDouble(json["start"], 0)),
      loopStart: math.max(0, jsonDouble(json["loopStart"], 0)),
      gain: jsonDouble(json["gain"], 0).clamp(-70.0, 24.0),
      reversedOf: json["reversedOf"] is Map<String, dynamic>
          ? MediaSource.fromJson(json["reversedOf"])
          : null,
      quantise:
          Quantise.values.where((q) => q.name == json["quantise"]).firstOrNull,
      legato: jsonBool(json["legato"], false),
      velocity: jsonDouble(json["velocity"], 0).clamp(0.0, 1.0),
      follow: FollowAction.values
              .where((f) => f.name == json["follow"])
              .firstOrNull ??
          FollowAction.none,
      followBars: json["followBars"] is num
          ? math.max(0.25, (json["followBars"] as num).toDouble())
          : null,
      warp: jsonBool(json["warp"], false),
      warpMode: WarpMode.values
              .where((m) => m.name == json["warpMode"])
              .firstOrNull ??
          WarpMode.complex,
      bpm: jsonDouble(json["bpm"], 0).clamp(0.0, 999.0),
      markers: [
        if (json["markers"] case List list)
          for (var m in list)
            if (m case [num s, num b])
              (seconds: s.toDouble(), beat: b.toDouble()),
      ],
      pitch: jsonInt(json["pitch"], 0).clamp(-48, 48),
      cents: jsonInt(json["cents"], 0).clamp(-50, 50),
      warped: json["warped"] is Map<String, dynamic>
          ? MediaSource.fromJson(json["warped"])
          : null,
      warpedFor: jsonString(json["warpedFor"], ""),
      automation: [
        if (json["automation"] case List list)
          for (var raw in list)
            if (ClipAutomation.fromJson(raw) case var a?) a,
      ],
      envelopes: {
        if (json["envelopes"] case Map<String, dynamic> all)
          for (var e in ClipEnvelope.values)
            if (all[e.name] case List points)
              e: [
                for (var p in points)
                  if (p case [num b, num v])
                    (b.toDouble(), v.toDouble().clamp(0.0, 1.0)),
              ]..sort((a, b) => a.$1.compareTo(b.$1)),
      },
    );
  }
}

/// defaultSceneCount is how many scenes a grid starts with, unnamed.
const int defaultSceneCount = 8;

/// SessionGrid is every channel's clip slots, and the scenes -- its rows.
class SessionGrid {
  /// scenes are the rows' names, top to bottom; "" is unnamed, shown by its
  /// number.
  final List<String> scenes;

  /// slots are each channel's clips by row, by channel key; a list shorter
  /// than the scenes, or a null in it, is empty slots.
  final Map<String, List<SessionClip?>> slots;

  const SessionGrid({
    this.scenes = const ["", "", "", "", "", "", "", ""],
    this.slots = const {},
  });

  int get rows => scenes.length;

  bool get isEmpty =>
      slots.values.every((l) => l.every((c) => c == null)) &&
      scenes.length == defaultSceneCount &&
      scenes.every((s) => s.isEmpty);

  /// sceneName is row [row]'s name, or its number.
  String sceneName(int row) => row < scenes.length && scenes[row].isNotEmpty
      ? scenes[row]
      : "${row + 1}";

  SessionClip? at(String channel, int row) {
    var list = slots[channel];
    if (list == null || row < 0 || row >= list.length) return null;
    return list[row];
  }

  /// find is where the clip [id] is: its channel and row.
  (String, int)? find(String id) {
    for (var e in slots.entries) {
      for (var (i, c) in e.value.indexed) {
        if (c?.id == id) return (e.key, i);
      }
    }
    return null;
  }

  /// put is the grid with [clip] in [channel]'s slot [row] -- or that slot
  /// emptied, for null.
  SessionGrid put(String channel, int row, SessionClip? clip) {
    if (row < 0) return this;
    var list = [...?slots[channel]];
    while (list.length <= row) {
      list.add(null);
    }
    list[row] = clip;
    while (list.isNotEmpty && list.last == null) {
      list.removeLast();
    }
    var next = {...slots};
    if (list.isEmpty) {
      next.remove(channel);
    } else {
      next[channel] = list;
    }
    return SessionGrid(
        scenes: row >= scenes.length
            ? [...scenes, for (var i = scenes.length; i <= row; i++) ""]
            : scenes,
        slots: next);
  }

  /// withScene is the grid with a scene added after [after] -- at the end
  /// for null -- and the clips below it moved down.
  SessionGrid withScene({int? after}) {
    var at = after == null ? scenes.length : after + 1;
    return SessionGrid(
      scenes: [...scenes]..insert(at.clamp(0, scenes.length), ""),
      slots: {
        for (var e in slots.entries)
          e.key:
              e.value.length <= at ? e.value : ([...e.value]..insert(at, null)),
      },
    );
  }

  /// withoutScene is the grid with row [row] and its clips gone. Never the
  /// last row.
  SessionGrid withoutScene(int row) {
    if (scenes.length <= 1 || row < 0 || row >= scenes.length) return this;
    return SessionGrid(
      scenes: [...scenes]..removeAt(row),
      slots: {
        for (var e in slots.entries)
          e.key:
              e.value.length <= row ? e.value : ([...e.value]..removeAt(row)),
      }..removeWhere((_, l) => l.every((c) => c == null)),
    );
  }

  SessionGrid renameScene(int row, String name) {
    if (row < 0 || row >= scenes.length) return this;
    return SessionGrid(scenes: [...scenes]..[row] = name.trim(), slots: slots);
  }

  /// withoutChannel is the grid with [channel]'s clips gone: the channel is.
  SessionGrid withoutChannel(String channel) => !slots.containsKey(channel)
      ? this
      : SessionGrid(scenes: scenes, slots: {...slots}..remove(channel));

  /// clips is every clip, with its channel and row.
  /// mediaIds is every stored sound the slots use -- see
  /// SessionClip.mediaIds -- for the library to keep.
  Set<String> get mediaIds => {
        for (var (_, _, c) in clips) ...c.mediaIds,
      };

  Iterable<(String, int, SessionClip)> get clips sync* {
    for (var e in slots.entries) {
      for (var (i, c) in e.value.indexed) {
        if (c != null) yield (e.key, i, c);
      }
    }
  }

  Map<String, dynamic> toJson() => {
        "scenes": scenes,
        "slots": {
          for (var e in slots.entries)
            e.key: [for (var c in e.value) c?.toJson()],
        },
      };

  static SessionGrid fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const SessionGrid();
    var scenes = [
      if (json["scenes"] case List names)
        for (var n in names) jsonString(n, ""),
    ];
    if (scenes.isEmpty) scenes = List.filled(defaultSceneCount, "");
    var slots = <String, List<SessionClip?>>{};
    if (json["slots"] case Map<String, dynamic> m) {
      for (var e in m.entries) {
        if (e.value is! List) continue;
        var list = [for (var c in e.value as List) SessionClip.fromJson(c)];
        while (list.isNotEmpty && list.last == null) {
          list.removeLast();
        }
        if (list.isEmpty) continue;
        slots[e.key] = list;
        while (scenes.length < list.length) {
          scenes.add("");
        }
      }
    }
    return SessionGrid(scenes: scenes, slots: slots);
  }
}
