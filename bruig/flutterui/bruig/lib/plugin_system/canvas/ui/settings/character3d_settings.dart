import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/lip_sync.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_move.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_performance.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:flutter/material.dart';

// character3d_settings.dart is a 3D character's settings on the canvas: the
// character itself, changed in the Character Studio; what it does in this
// scene -- how it stands, the motions it plays and when, its face and what
// it says (character_performance.dart); and how the box shows it -- how
// much of it, from which side, how close.

/// character3dSettings are [e]'s settings. [inStudio] is for the Character
/// Studio's Test step, which tries a scene's settings on its own stage: no
/// way to the Studio, and no box to show it in.
List<Widget> character3dSettings(
  BuildContext context,
  CanvasController controller,
  Character3dElement e,
  SettingsWrite write,
  VoidCallback begin,
  VoidCallback commit, {
  bool inStudio = false,
}) {
  void now(Character3dElement next) {
    begin();
    write(next);
    commit();
  }

  final p = e.performance;
  void perf(CharacterPerformance n) => now(e.performing(n));
  void drag(CharacterPerformance n) {
    begin();
    write(e.performing(n));
  }

  // The playhead, in seconds of the scene; a key there is what the pose and
  // feeling settings change, rather than how it stands between keys.
  final fps = math.max(1, controller.document.frameRate);
  final at = controller.frame / fps;
  final keyIndex = p.keys.indexWhere((k) => (k.t - at).abs() < 0.5 / fps);
  final key = keyIndex < 0 ? null : p.keys[keyIndex];
  CharacterPerformance keyed(PoseKey k) =>
      p.copyWith(keys: [...p.keys]..[keyIndex] = k);
  String secs(double t) => "${t.toStringAsFixed(1)} s";

  var changes = (e.framing != Character3dFraming.body ? 1 : 0) +
      (e.turn != 0 ? 1 : 0) +
      (e.tilt != 0 ? 1 : 0) +
      (e.zoom != 1 ? 1 : 0) +
      (p.shadow != "Soft" ? 1 : 0);
  final poseChanges = (p.stance != null ? 1 : 0) +
      (p.lean != 0 ? 1 : 0) +
      (p.tilt != 0 ? 1 : 0) +
      p.keys.length;
  final faceChanges = (p.feeling != null ? 1 : 0) +
      (p.mixAmount != 0 ? 1 : 0) +
      (p.mouth != "rest" ? 1 : 0) +
      (p.line.isNotEmpty ? 1 : 0) +
      (!p.blink ? 1 : 0) +
      (!p.breathe ? 1 : 0) +
      (!p.glance ? 1 : 0);
  final feelings = [
    for (var n in e.design.face.expressions.keys) (n, n),
  ];
  // The motions to add: walks and runs on the spot or across the page.
  final adds = [
    for (final k in performanceMotions)
      if (k == "Walk" || k == "Run") ...[
        ("$k:0", k),
        ("$k:-1", "$k to the left"),
        ("$k:1", "$k to the right"),
      ] else
        ("$k:0", k),
  ];
  String clipName(MotionClip3d c) => switch (c.dir) {
        -1 => "${c.kind} to the left",
        1 => "${c.kind} to the right",
        _ => c.kind,
      };
  return [
    section(e, "character",
        icon: Icons.view_in_ar_outlined,
        title: "Character",
        summary: e.design.name,
        initiallyOpen: true,
        children: [
          if (!inStudio)
            CanvasControlGroup(
                label: "In the Character Studio",
                help: "Its body, hair, clothes, look and decals are changed in "
                    "the Character Studio. Done there changes every copy of "
                    "it, in every scene, and the one kept in Assets.",
                children: [
                  CanvasTextButton(
                    key: const ValueKey("character3dEdit"),
                    label: "Change in the Studio",
                    icon: Icons.edit_outlined,
                    primary: true,
                    onPressed: () => controller.openStudio3d(element: e.id),
                  ),
                ]),
          CanvasControlGroup(
              label: "Clothes",
              help: "What it wears in this scene: its clothes as designed, or "
                  "one of the Studio's quick changes.",
              children: [
                CanvasDropdown<String>(
                  key: const ValueKey("character3dWearing"),
                  label: "Wearing",
                  width: 200,
                  value: p.wearing,
                  options: [for (final w in performanceWearing) (w, w)],
                  onChanged: (v) => perf(p.copyWith(wearing: v)),
                ),
              ]),
        ]),
    section(e, "pose",
        icon: Icons.accessibility_new_outlined,
        title: "Pose",
        summary: [
          p.stance ?? e.design.move.stance,
          if (p.keys.isNotEmpty)
            "${p.keys.length} key${p.keys.length == 1 ? "" : "s"}",
        ].join(", "),
        changes: poseChanges,
        onReset: poseChanges == 0
            ? null
            : () => perf(p.copyWith(stance: null, lean: 0, tilt: 0, keys: [])),
        children: [
          CanvasControlGroup(
              label: key == null ? "Stands" : "Stands, at the key",
              help: key == null
                  ? "How it stands in this scene, between any keys: as "
                      "designed in the Studio, or another stance, leaning, "
                      "its head tilted."
                  : "The key at ${secs(key.t)}: it stands so from here "
                      "until the next key.",
              children: [
                CanvasDropdown<String>(
                  key: const ValueKey("character3dStance"),
                  label: "Stance",
                  width: 200,
                  value: key?.stance ?? p.stance ?? "",
                  options: [
                    if (key == null)
                      ("", "As designed (${e.design.move.stance})"),
                    for (final s in moveStances) (s, s),
                  ],
                  onChanged: (v) => perf(key != null
                      ? keyed(key.copyWith(stance: v))
                      : p.copyWith(stance: v.isEmpty ? null : v)),
                ),
                CanvasSlider(
                  key: const ValueKey("character3dLean"),
                  label: "Lean",
                  value: key?.lean ?? p.lean,
                  min: -1,
                  max: 1,
                  onChanged: (v) => drag(key != null
                      ? keyed(key.copyWith(lean: v))
                      : p.copyWith(lean: v)),
                  onCommit: commit,
                ),
                CanvasSlider(
                  key: const ValueKey("character3dPoseTilt"),
                  label: "Head tilt",
                  value: key?.tilt ?? p.tilt,
                  min: -1,
                  max: 1,
                  onChanged: (v) => drag(key != null
                      ? keyed(key.copyWith(tilt: v))
                      : p.copyWith(tilt: v)),
                  onCommit: commit,
                ),
              ]),
          CanvasControlGroup(
              label: "Keys",
              help: "A key changes its pose and feeling from its time until "
                  "the next. Move the playhead to a key to change it.",
              children: [
                if (key == null)
                  CanvasTextButton(
                    key: const ValueKey("character3dKeyAdd"),
                    label: "Key the pose at ${secs(at)}",
                    icon: Icons.add,
                    onPressed: () {
                      final held = p.keyAt(at);
                      perf(p.copyWith(
                          keys: [
                        ...p.keys,
                        PoseKey(
                            t: at,
                            stance: held?.stance ??
                                p.stance ??
                                e.design.move.stance,
                            lean: held?.lean ?? p.lean,
                            tilt: held?.tilt ?? p.tilt,
                            feeling: held?.feeling ??
                                p.feeling ??
                                e.design.face.name),
                      ]..sort((a, b) => a.t.compareTo(b.t))));
                    },
                  ),
                for (final (i, k) in p.keys.indexed) ...[
                  CanvasTextButton(
                    key: ValueKey("character3dKey-$i"),
                    label: "${secs(k.t)} · ${k.stance} · ${k.feeling}",
                    primary: i == keyIndex,
                    onPressed: () => controller.frame = (k.t * fps).round(),
                  ),
                  CanvasIconButton(
                    key: ValueKey("character3dKeyRemove-$i"),
                    icon: Icons.close,
                    tooltip: "Take the key out",
                    onPressed: () =>
                        perf(p.copyWith(keys: [...p.keys]..removeAt(i))),
                  ),
                  const CanvasLineBreak(),
                ],
              ]),
        ]),
    section(e, "motions",
        icon: Icons.directions_run_outlined,
        title: "Motions",
        summary: p.clips.isEmpty
            ? e.design.move.motion
            : "${p.clips.length} motion${p.clips.length == 1 ? "" : "s"}",
        changes: p.clips.length,
        onReset: p.clips.isEmpty ? null : () => perf(p.copyWith(clips: [])),
        children: [
          CanvasControlGroup(
              label: "Add a motion",
              help: "Played from the playhead for two seconds, faded in and "
                  "out, over the stance: it takes over the parts of the "
                  "body it moves. A walk or a run across the page carries "
                  "the character that way. Between motions it plays its own "
                  "(${e.design.move.motion}).",
              children: [
                CanvasDropdown<String>(
                  key: const ValueKey("character3dMotionAdd"),
                  label: "At ${secs(at)}",
                  width: 200,
                  value: "",
                  options: [("", "Choose…"), ...adds],
                  onChanged: (v) {
                    if (v.isEmpty) return;
                    final [kind, dir] = v.split(":");
                    perf(p.copyWith(
                        clips: [
                      ...p.clips,
                      MotionClip3d(kind: kind, start: at, dir: int.parse(dir)),
                    ]..sort((a, b) => a.start.compareTo(b.start))));
                  },
                ),
              ]),
          if (!inStudio && (p.startsAt != 0 || p.clips.any((c) => c.dir != 0)))
            CanvasControlGroup(
                label: "Walks start from",
                help: "Where in its box it stands until a walk carries it "
                    "off: a walk to the right from the left edge crosses "
                    "the whole box. It never walks past the box's edges.",
                children: [
                  CanvasSegmented<int>(
                    key: const ValueKey("character3dStartsAt"),
                    options: const [
                      (-1, "Left edge"),
                      (0, "Middle"),
                      (1, "Right edge")
                    ],
                    value: p.startsAt,
                    keyOf: (v) => "character3dStartsAt-$v",
                    onChanged: (v) => perf(p.copyWith(startsAt: v)),
                  ),
                ]),
          for (final (i, c) in p.clips.indexed)
            CanvasControlGroup(
                key: ValueKey("character3dClip-$i"),
                label: clipName(c),
                children: [
                  CanvasNumberField(
                    key: ValueKey("character3dClipStart-$i"),
                    label: "From",
                    value: c.start,
                    min: 0,
                    max: 3600,
                    decimals: 1,
                    suffix: " s",
                    onChanged: (v) => drag(p.copyWith(
                        clips: [...p.clips]..[i] = c.copyWith(start: v))),
                    onCommit: commit,
                  ),
                  CanvasNumberField(
                    key: ValueKey("character3dClipLength-$i"),
                    label: "For",
                    value: c.length,
                    min: 0.3,
                    max: 3600,
                    decimals: 1,
                    suffix: " s",
                    onChanged: (v) => drag(p.copyWith(
                        clips: [...p.clips]..[i] = c.copyWith(length: v))),
                    onCommit: commit,
                  ),
                  CanvasSlider(
                    key: ValueKey("character3dClipSpeed-$i"),
                    label: "Speed",
                    value: c.speed,
                    min: 0.25,
                    max: 3,
                    onChanged: (v) => drag(p.copyWith(
                        clips: [...p.clips]..[i] = c.copyWith(speed: v))),
                    onCommit: commit,
                  ),
                  CanvasSlider(
                    key: ValueKey("character3dClipStrength-$i"),
                    label: "How much",
                    value: c.strength,
                    min: 0,
                    max: 1.5,
                    onChanged: (v) => drag(p.copyWith(
                        clips: [...p.clips]..[i] = c.copyWith(strength: v))),
                    onCommit: commit,
                  ),
                  CanvasToggle(
                    key: ValueKey("character3dClipMirror-$i"),
                    label: "Mirrored, left for right",
                    value: c.mirror,
                    onChanged: (v) => perf(p.copyWith(
                        clips: [...p.clips]..[i] = c.copyWith(mirror: v))),
                  ),
                  CanvasTextButton(
                    key: ValueKey("character3dClipRemove-$i"),
                    label: "Take it out",
                    icon: Icons.close,
                    onPressed: () =>
                        perf(p.copyWith(clips: [...p.clips]..removeAt(i))),
                  ),
                ]),
        ]),
    section(e, "face",
        icon: Icons.face_outlined,
        title: "Face",
        summary: [
          key?.feeling ?? p.feeling ?? e.design.face.name,
          if (p.line.isNotEmpty) "says a line",
        ].join(", "),
        changes: faceChanges,
        onReset: faceChanges == 0
            ? null
            : () => perf(p.copyWith(
                feeling: null,
                mixAmount: 0,
                mouth: "rest",
                line: "",
                lineAt: 0,
                blink: true,
                breathe: true,
                glance: true)),
        children: [
          CanvasControlGroup(
              label: key == null ? "Expression" : "Expression, at the key",
              help: "The expression it wears in this scene: the one it was "
                  "made with, or any of its face's -- the ones to start from "
                  "and the ones kept in the Studio -- part of the way to "
                  "another if you like.",
              children: [
                CanvasDropdown<String>(
                  key: const ValueKey("character3dExpression"),
                  label: "Wears",
                  width: 200,
                  value: key?.feeling ?? e.expression ?? "",
                  options: [
                    if (key == null) ("", "As made (${e.design.face.name})"),
                    ...feelings,
                  ],
                  onChanged: (v) => key != null
                      ? perf(keyed(key.copyWith(feeling: v)))
                      : now(e.wearing(v.isEmpty ? null : v)),
                ),
                CanvasDropdown<String>(
                  key: const ValueKey("character3dMixTo"),
                  label: "Toward",
                  width: 160,
                  value: p.mixTo,
                  options: feelings,
                  onChanged: (v) => perf(p.copyWith(mixTo: v)),
                ),
                CanvasSlider(
                  key: const ValueKey("character3dMixAmount"),
                  label: "How far",
                  value: p.mixAmount,
                  onChanged: (v) => drag(p.copyWith(mixAmount: v)),
                  onCommit: commit,
                ),
              ]),
          CanvasControlGroup(
              label: "Mouth",
              help: "A mouth shape it holds, or a line it says from a time: "
                  "its mouth moves to the words.",
              children: [
                CanvasDropdown<String>(
                  key: const ValueKey("character3dMouth"),
                  label: "Holds",
                  width: 140,
                  value: p.mouth,
                  options: performanceMouths,
                  onChanged: (v) => perf(p.copyWith(mouth: v)),
                ),
                CanvasTextField(
                  key: const ValueKey("character3dLine"),
                  label: "Says",
                  value: p.line,
                  width: 200,
                  hint: "A line it says",
                  onChanged: (v) => drag(p.copyWith(line: v)),
                  onCommit: commit,
                ),
                CanvasNumberField(
                  key: const ValueKey("character3dLineAt"),
                  label: "From",
                  value: p.lineAt,
                  min: 0,
                  max: 3600,
                  decimals: 1,
                  suffix: " s",
                  onChanged: (v) => drag(p.copyWith(lineAt: v)),
                  onCommit: commit,
                ),
              ]),
          CanvasControlGroup(
              label: "By itself",
              help: "What it does without being told: blinks, breathes, and "
                  "glances about.",
              children: [
                CanvasToggle(
                  key: const ValueKey("character3dBlink"),
                  label: "Blinks",
                  value: p.blink,
                  onChanged: (v) => perf(p.copyWith(blink: v)),
                ),
                CanvasToggle(
                  key: const ValueKey("character3dBreathe"),
                  label: "Breathes",
                  value: p.breathe,
                  onChanged: (v) => perf(p.copyWith(breathe: v)),
                ),
                CanvasToggle(
                  key: const ValueKey("character3dGlance"),
                  label: "Glances about",
                  value: p.glance,
                  onChanged: (v) => perf(p.copyWith(glance: v)),
                ),
              ]),
        ]),
    section(e, "lipSync",
        icon: Icons.record_voice_over_outlined,
        title: "Lip sync",
        summary: [
          if (p.speaksFor.isNotEmpty) "speaks for a channel",
          p.mouths.isEmpty ? "no mouths yet" : "${p.mouths.length} mouths",
        ].join(", "),
        changes:
            (p.mouths.isNotEmpty ? 1 : 0) + (p.speaksFor.isNotEmpty ? 1 : 0),
        onReset: p.mouths.isEmpty && p.speaksFor.isEmpty
            ? null
            : () => perf(p.withMouths(const []).copyWith(speaksFor: "")),
        children: [
          if (channelsToSpeakFor(controller) case var channels
              when channels.isNotEmpty || p.speaksFor.isNotEmpty) ...[
            CanvasDropdown<String>(
              key: const ValueKey("character3dSpeaksFor"),
              label: "Speaks for",
              value: p.speaksFor,
              width: 200,
              options: [
                ("", "No channel"),
                ...channels,
                if (p.speaksFor.isNotEmpty &&
                    !channels.any((c) => c.$1 == p.speaksFor))
                  (p.speaksFor, "A channel since removed"),
              ],
              onChanged: (v) => perf(p.copyWith(speaksFor: v)),
            ),
            const CanvasHint(
                "A slot played on that channel -- a narrator's line -- moves "
                "the mouth by its sounds, and shows the character while it "
                "is heard."),
            const CanvasLineBreak(),
          ],
          if (!inStudio) _LipSyncGroup(controller: controller, character: e),
        ]),
    if (!inStudio)
      section(e, "view",
          icon: Icons.videocam_outlined,
          title: "View",
          summary: [
            e.framing.label,
            if (e.turn != 0) "turned ${(e.turn * 180).round()}°",
          ].join(", "),
          changes: changes,
          onReset: changes == 0
              ? null
              : () => now(e
                  .copyWith(
                      framing: Character3dFraming.body,
                      turn: 0,
                      tilt: 0,
                      zoom: 1)
                  .performing(p.copyWith(shadow: "Soft"))),
          initiallyOpen: true,
          children: [
            CanvasControlGroup(
                label: "Shows",
                help: "How much of the character the box shows. The box keeps "
                    "its size; the character is drawn closer.",
                children: [
                  CanvasSegmented<Character3dFraming>(
                    key: const ValueKey("character3dFraming"),
                    options: [
                      for (var f in Character3dFraming.values) (f, f.label)
                    ],
                    value: e.framing,
                    keyOf: (f) => "character3dFraming-${f.name}",
                    onChanged: (f) => now(e.copyWith(framing: f)),
                  ),
                ]),
            CanvasControlGroup(
                label: "Seen from",
                help: "Turn goes round the character, half a turn either way "
                    "from the front. Tilt looks from above, or below. Zoom "
                    "comes closer than the framing.",
                children: [
                  CanvasSlider(
                    key: const ValueKey("character3dTurn"),
                    label: "Turn",
                    value: e.turn,
                    min: -1,
                    max: 1,
                    onChanged: (v) {
                      begin();
                      write(e.copyWith(turn: v));
                    },
                    onCommit: commit,
                  ),
                  CanvasSlider(
                    key: const ValueKey("character3dTilt"),
                    label: "Tilt",
                    value: e.tilt,
                    min: -0.5,
                    max: 1,
                    onChanged: (v) {
                      begin();
                      write(e.copyWith(tilt: v));
                    },
                    onCommit: commit,
                  ),
                  CanvasSlider(
                    key: const ValueKey("character3dZoom"),
                    label: "Zoom",
                    value: e.zoom,
                    min: 0.5,
                    max: 3,
                    onChanged: (v) {
                      begin();
                      write(e.copyWith(zoom: v));
                    },
                    onCommit: commit,
                  ),
                ]),
            CanvasControlGroup(
                label: "Shadow",
                help: "The shadow under it on the ground, which shrinks as it "
                    "leaves the ground.",
                children: [
                  CanvasSegmented<String>(
                    key: const ValueKey("character3dShadow"),
                    options: [for (final s in performanceShadows) (s, s)],
                    value: p.shadow,
                    keyOf: (s) => "character3dShadow-$s",
                    onChanged: (s) => perf(p.copyWith(shadow: s)),
                  ),
                ]),
          ]),
  ];
}

/// channelsToSpeakFor are the channels a character can speak for: those
/// with clips in their slots, by key and name.
List<(String, String)> channelsToSpeakFor(CanvasController c) {
  var names = {for (var ch in c.timelineChannels) ch.key: ch.name};
  return [
    for (var MapEntry(:key, value: slots) in c.session.slots.entries)
      if (slots.any((s) => s != null)) (key, names[key] ?? key),
  ];
}

/// _LipSyncGroup lays a voice-over's mouths on a 3D character: by its
/// words, heard or read from a Speech take, or by its loudness.
class _LipSyncGroup extends StatefulWidget {
  final CanvasController controller;
  final Character3dElement character;
  const _LipSyncGroup({required this.controller, required this.character});

  @override
  State<_LipSyncGroup> createState() => _LipSyncGroupState();
}

class _LipSyncGroupState extends State<_LipSyncGroup> {
  CanvasController get controller => widget.controller;

  /// _voice is the sound picked, by id; null is the longest.
  String? _voice;
  bool _words = true;
  double _shortest = 2;
  double _lead = 1;
  bool _busy = false;
  String _said = "";

  /// _voices are the timed sounds a voice-over could be, longest first --
  /// the voice is nearly always the longest thing on the timeline.
  List<AudioElement> get _voices {
    var d = controller.document;
    var all = <AudioElement>[
      for (var e in [
        ...?d.master?.elements,
        for (var s in d.allScenes) ...s.elements,
      ])
        if (e is AudioElement && e.clip.timed && !e.clip.isEmpty) e,
    ];
    all.sort((a, b) => b.clip.runLength.compareTo(a.clip.runLength));
    return all;
  }

  Future<void> _sync(AudioElement voice) async {
    setState(() {
      _busy = true;
      _said = "";
    });
    controller.beginInteraction();
    var done = await controller.lipSync(widget.character, voice,
        words: _words,
        feel: LipSyncFeel(shortest: _shortest.round(), lead: _lead.round()));
    controller.endInteraction();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _said = done.problem ??
          (done.mouths == 0
              ? "No speech was found in that recording."
              : "${done.mouths} mouths laid down.");
    });
  }

  @override
  Widget build(BuildContext context) {
    var voices = _voices;
    var voice =
        voices.where((v) => v.id == _voice).firstOrNull ?? voices.firstOrNull;
    return CanvasControlGroup(
        label: "From the voice-over",
        help: "Hear the words uses the words heard for the Cues -- hearing "
            "them first if they have not been -- and spells each into the "
            "mouths it is said with. Sound only reads how loud the voice is "
            "frame by frame: rougher, but it works in any language with "
            "nothing installed. A take the Speech device spoke needs no "
            "hearing: its words are read from it, each to the moment.",
        children: [
          const CanvasLineBreak(),
          if (voice == null)
            const CanvasStatus("Add a voice-over first: a timed Audio element, "
                "or a sound on the timeline's channels.")
          else ...[
            CanvasDropdown<String>(
              key: const ValueKey("character3dLipVoice"),
              label: "Voice",
              value: voice.id,
              width: 200,
              options: [for (var v in voices) (v.id, v.name)],
              onChanged: (id) => setState(() => _voice = id),
            ),
            const CanvasLineBreak(),
            CanvasToggle(
              key: const ValueKey("character3dLipWords"),
              label: "Hear the words",
              value: _words,
              onChanged: (v) => setState(() => _words = v),
            ),
            const CanvasLineBreak(),
            CanvasStepper(
              key: const ValueKey("character3dLipShortest"),
              label: "Shortest mouth",
              value: _shortest,
              min: 1,
              max: 6,
              suffix: " fr",
              defaultValue: 2,
              onChanged: (v) => setState(() => _shortest = v),
            ),
            CanvasStepper(
              key: const ValueKey("character3dLipLead"),
              label: "Ahead of the voice",
              value: _lead,
              min: 0,
              max: 4,
              suffix: " fr",
              defaultValue: 1,
              onChanged: (v) => setState(() => _lead = v),
            ),
            const CanvasLineBreak(),
            CanvasTextButton(
              key: const ValueKey("character3dLipSync"),
              icon: Icons.graphic_eq,
              primary: true,
              label: _busy ? "Listening…" : "Lip sync",
              onPressed: _busy ? null : () => _sync(voice),
            ),
            if (widget.character.performance.mouths.isNotEmpty)
              CanvasTextButton(
                key: const ValueKey("character3dLipClear"),
                icon: Icons.backspace_outlined,
                label: "Clear mouths",
                onPressed: () {
                  controller.beginInteraction();
                  controller.clearLipSync(widget.character);
                  controller.endInteraction();
                },
              ),
          ],
          if (_said.isNotEmpty) ...[
            const CanvasLineBreak(),
            CanvasStatus(_said, key: const ValueKey("character3dLipSaid")),
          ],
        ]);
  }
}
