import 'dart:io';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/character_bvh.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_lipsync.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_motion.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_wardrobe.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

// character_settings.dart is a Character element's settings.
//
// In the order a character is made: who they are (a cast member to start
// from, then how tall and how broad), what they look like, what they wear,
// and how they stand. Every choice is a tile drawn by the character's own
// painter, so what is picked is what arrives -- a pose tile shows this
// character in that pose, not a stick figure.

List<Widget> characterSettings(
  BuildContext context,
  CanvasController controller,
  CharacterElement e,
  SettingsWrite write,
  VoidCallback begin,
  VoidCallback commit,
) {
  void now(CharacterElement next) {
    begin();
    write(next);
    commit();
  }

  var dna = e.dna;
  void dnaNow(CharacterDna next) => now(e.copyWith(dna: next));
  // What every tile of this character is drawn from, so a tile changes
  // when the character does and not otherwise. See TileSnapshot.
  var drawn = dna.toJson().toString();
  var pose = e.poseAtFrame(controller.frame);
  var animated = controller.document.isAnimated;
  var keyed = controller.hasCharacterPoseKey(e);
  var face = e.faceAtFrame(controller.frame);
  void faceNow(CharacterFace next) => now(controller.characterFaced(e, next));

  return [
    section(e, "character",
        icon: Icons.person_outline,
        title: "Character",
        summary: "${e.style.label} · ${shortNumber(dna.headsTall)} heads tall",
        initiallyOpen: true,
        children: [
          CanvasTiles<int>(
            label: "Start from",
            help: "Someone from the cast to start from. Their look is copied "
                "onto this character, and from then on it is this "
                "character's own to change.",
            columns: 5,
            previewHeight: 64,
            tiles: [
              for (var (i, who) in characterCast.indexed)
                CanvasTile(i, who.name,
                    drawnFrom: who.dna.toJson().toString(),
                    paint: (canvas, size) => _figureTile(
                        canvas, size, who.dna, CharacterElement.restPose)),
            ],
            selected: (i) =>
                characterCast[i].dna.toJson().toString() == drawn,
            keyOf: (i) => "characterCast-${characterCast[i].name}",
            onPick: (i) {
              var who = characterCast[i];
              var next = e.copyWith(dna: who.dna);
              // Renamed with them, unless it has a name of its own.
              var named = e.base.name.isEmpty ||
                  characterCast.any((c) => c.name == e.base.name);
              now(named
                  ? next.withBase(name: who.name) as CharacterElement
                  : next);
            },
          ),
          CanvasControlGroup(
              label: "Body",
              help: "How tall the character is in head lengths -- about 2½ "
                  "for a chibi, 5½ for a cartoon, 7½ for a real adult -- "
                  "and how broad.",
              children: [
                CanvasStepper(
                  key: const ValueKey("characterHeads"),
                  label: "Heads tall",
                  value: dna.headsTall,
                  min: CharacterDna.minHeads,
                  max: CharacterDna.maxHeads,
                  step: 0.5,
                  decimals: 1,
                  defaultValue: 5.5,
                  onChanged: (v) =>
                      write(e.copyWith(dna: dna.copyWith(headsTall: v))),
                  onCommit: commit,
                ),
                CanvasStepper(
                  key: const ValueKey("characterBuild"),
                  label: "Build",
                  value: dna.build * 100,
                  min: 0,
                  max: 100,
                  step: 10,
                  suffix: "%",
                  defaultValue: 40,
                  onChanged: (v) =>
                      write(e.copyWith(dna: dna.copyWith(build: v / 100))),
                  onCommit: commit,
                ),
              ]),
        ]),
    section(e, "look",
        icon: Icons.face_outlined,
        title: "Look",
        summary: "${dna.hairStyle.label} hair",
        children: [
          CanvasControlGroup(
              label: "Colours",
              help: "Skin, hair and eyes.",
              children: [
                CanvasColorButton(
                  label: "Skin",
                  color: dna.skin,
                  onChanged: (c) => dnaNow(dna.copyWith(skin: c)),
                ),
                CanvasColorButton(
                  label: "Hair",
                  color: dna.hair,
                  onChanged: (c) => dnaNow(dna.copyWith(hair: c)),
                ),
                CanvasColorButton(
                  label: "Eyes",
                  color: dna.eyes,
                  onChanged: (c) => dnaNow(dna.copyWith(eyes: c)),
                ),
              ]),
          CanvasTiles<HairStyle>(
            label: "Hair",
            help: "How the hair is cut. Its colour is under Colours.",
            columns: 5,
            previewHeight: 48,
            tiles: [
              for (var h in HairStyle.values)
                CanvasTile(h, h.label,
                    drawnFrom: drawn,
                    paint: (canvas, size) => _headTile(
                        canvas, size, dna.copyWith(hairStyle: h))),
            ],
            selected: (h) => dna.hairStyle == h,
            keyOf: (h) => "characterHair-${h.name}",
            onPick: (h) => dnaNow(dna.copyWith(hairStyle: h)),
          ),
        ]),
    section(e, "wardrobe",
        icon: Icons.checkroom_outlined,
        title: "Wardrobe",
        summary: [
          if (e.bareView) "Bare view",
          for (var g in dna.wardrobe)
            if (g.kind.slot != GarmentSlot.base) g.kind.label,
        ].join(" · "),
        children: [
          _WardrobeGroup(
              controller: controller,
              character: e,
              write: write,
              commit: commit),
        ]),
    section(e, "pose",
        icon: Icons.accessibility_new,
        title: "Pose",
        summary: keyed
            ? "Keyed here"
            : e.posedOnTimeline
                ? "Animated"
                : _poseName(e.pose),
        children: [
          CanvasTiles<int>(
            label: "Stand like",
            help: "A ready-made pose. Drag the pins on the hands, feet, head "
                "and chest on the canvas to make your own.",
            columns: 4,
            previewHeight: 64,
            tiles: [
              for (var (i, p) in posePresets.indexed)
                CanvasTile(i, p.name,
                    drawnFrom: drawn,
                    paint: (canvas, size) =>
                        _figureTile(canvas, size, dna, p.pose)),
            ],
            selected: (i) => _samePose(posePresets[i].pose, pose),
            keyOf: (i) => "characterPose-${posePresets[i].name}",
            onPick: (i) => now(controller.characterPosed(e, posePresets[i].pose)),
          ),
          CanvasControlGroup(
              label: "Body and head",
              help: "How far the body leans and the head tilts, in degrees. "
                  "The arms and legs are posed by their pins on the canvas.",
              children: [
                for (var bone in [CharacterBone.spine, CharacterBone.head])
                  CanvasStepper(
                    key: ValueKey("characterBone-${bone.name}"),
                    label: bone == CharacterBone.spine ? "Lean" : "Head tilt",
                    value: pose[bone],
                    min: -60,
                    max: 60,
                    step: 5,
                    suffix: "°",
                    defaultValue: 0,
                    onChanged: (v) => write(controller.characterPosed(
                        e, pose.withAngle(bone, v))),
                    onCommit: commit,
                  ),
              ]),
          CanvasControlGroup(
              label: "On the timeline",
              help: "Keying makes the character move: it holds how it "
                  "stands until the first key, then goes from pose to pose "
                  "and face to face. Once anything is keyed, every change "
                  "of pose or face -- a tile, a pin, a number -- is made on "
                  "the frame being looked at.",
              children: [
                if (keyed)
                  CanvasTextButton(
                    key: const ValueKey("characterUnkey"),
                    icon: Icons.remove_circle_outline,
                    label: "Remove this key",
                    onPressed: () {
                      controller.beginInteraction();
                      controller.clearCharacterPoseKey(e);
                      controller.endInteraction();
                    },
                  )
                else
                  CanvasTextButton(
                    key: const ValueKey("characterKey"),
                    icon: Icons.add_circle_outline,
                    label: "Key pose and face here",
                    onPressed: animated
                        ? () {
                            controller.beginInteraction();
                            controller.keyCharacterPose(e, pose);
                            controller.endInteraction();
                          }
                        : null,
                  ),
                if (!animated)
                  const CanvasHint(
                      "Give the canvas more than one frame to animate a pose."),
                const CanvasLineBreak(),
                CanvasToggle(
                  key: const ValueKey("characterRecordPins"),
                  label: "Record with the pins while playing",
                  value: controller.recordPins,
                  onChanged: (v) => controller.recordPins = v,
                ),
              ]),
        ]),
    section(e, "motion",
        icon: Icons.directions_walk,
        title: "Motion",
        summary: e.motions.isEmpty
            ? "No motions"
            : [for (var m in e.motions) m.kind.label].join(", "),
        children: [
          CanvasTiles<MotionKind>(
            label: "Add a motion",
            help: "Lays the motion on the character from the frame being "
                "looked at. Whole-body motions take the pose over; upper-"
                "body ones only the arms, body and head, so a wave can go "
                "over a walk; added ones go on top of everything. Each is a "
                "clip below and a bar on the timeline's Motion lane.",
            columns: 4,
            previewHeight: 64,
            tiles: [
              for (var k in MotionKind.values)
                CanvasTile(k, k.label,
                    drawnFrom: drawn,
                    paint: (canvas, size) => _motionTile(canvas, size, dna, k)),
            ],
            selected: (_) => false,
            keyOf: (k) => "characterMotion-${k.name}",
            onPick: (k) {
              controller.beginInteraction();
              controller.addMotion(e, k);
              controller.endInteraction();
            },
          ),
          _WalkGroup(controller: controller, character: e),
          _ImportGroup(controller: controller, character: e),
          for (var clip in e.motions)
            _clipGroup(controller, e, clip, write, commit),
        ]),
    section(e, "face",
        icon: Icons.mood,
        title: "Face",
        summary: [
          _feelingName(face),
          if (face.mouth != MouthShape.rest) "mouth ${face.mouth.letter}",
        ].join(" · "),
        children: [
          CanvasTiles<int>(
            label: "Feeling",
            help: "A ready-made expression. It sets the brows, eyes and "
                "mouth, and leaves which way the head is turned alone.",
            columns: 4,
            previewHeight: 56,
            tiles: [
              for (var (i, x) in expressionPresets.indexed)
                CanvasTile(i, x.name,
                    drawnFrom: drawn,
                    paint: (canvas, size) =>
                        _faceTile(canvas, size, dna, x.face)),
            ],
            selected: (i) => _sameFeeling(expressionPresets[i].face, face),
            keyOf: (i) => "characterFeeling-${expressionPresets[i].name}",
            onPick: (i) =>
                faceNow(face.feeling(expressionPresets[i].face)),
          ),
          _MixGroup(
              face: face,
              onMix: (mixed) => faceNow(mixed)),
          CanvasTiles<MouthShape>(
            label: "Mouth",
            help: "The shapes speech is drawn with, named by the sounds that "
                "make them. Rest is no shape: the mouth the face's own "
                "smile and open settings make. Lip sync chooses from these.",
            columns: 5,
            previewHeight: 40,
            tiles: [
              for (var m in MouthShape.values)
                CanvasTile(m, "${m.letter} · ${m.sounds}",
                    drawnFrom: drawn,
                    paint: (canvas, size) => _mouthTile(
                        canvas, size, dna, CharacterFace.rest.withMouth(m))),
            ],
            selected: (m) => face.mouth == m,
            keyOf: (m) => "characterMouth-${m.name}",
            onPick: (m) => now(controller.characterMouthed(e, m)),
          ),
          for (var (label, help, controls) in _controlGroups)
            CanvasControlGroup(label: label, help: help, children: [
              for (var c in controls)
                CanvasStepper(
                  key: ValueKey("characterFace-${c.name}"),
                  label: c.label,
                  value: _shown(c, face[c]),
                  min: _shown(c, c.min),
                  max: _shown(c, c.max),
                  step: _degrees(c) ? 5 : 10,
                  suffix: _degrees(c) ? "°" : "%",
                  defaultValue: _shown(c, c.rest),
                  onChanged: (v) => write(controller.characterFaced(
                      e, face.withControl(c, _stored(c, v)))),
                  onCommit: commit,
                ),
            ]),
          CanvasControlGroup(
              label: "Stay alive",
              help: "Small movements the character makes by itself, the "
                  "same on every play and in every export: a blink every "
                  "few seconds, breathing, and the eyes wandering.",
              children: [
                CanvasToggle(
                  key: const ValueKey("characterBlink"),
                  label: "Blink",
                  value: e.life.blink,
                  onChanged: (v) =>
                      now(e.copyWith(life: e.life.copyWith(blink: v))),
                ),
                CanvasToggle(
                  key: const ValueKey("characterBreathe"),
                  label: "Breathe",
                  value: e.life.breathe,
                  onChanged: (v) =>
                      now(e.copyWith(life: e.life.copyWith(breathe: v))),
                ),
                CanvasToggle(
                  key: const ValueKey("characterGlance"),
                  label: "Glance about",
                  value: e.life.glance,
                  onChanged: (v) =>
                      now(e.copyWith(life: e.life.copyWith(glance: v))),
                ),
              ]),
        ]),
    section(e, "lipSync",
        icon: Icons.record_voice_over_outlined,
        title: "Lip sync",
        summary: e.mouthKeys.isEmpty
            ? "No mouths yet"
            : "${e.mouthKeys.length} mouths",
        children: [
          _LipSyncGroup(controller: controller, character: e),
        ]),
    animationPanelSection(controller, e, e.animation,
        (a) => write(e.copyWith(animation: a)), begin, commit),
  ];
}

/// _poseName is the preset [pose] is, or "Own pose".
String _poseName(CharacterPose pose) {
  for (var p in posePresets) {
    if (_samePose(p.pose, pose)) return p.name;
  }
  return "Own pose";
}

bool _samePose(CharacterPose a, CharacterPose b) {
  for (var bone in CharacterBone.values) {
    if ((a[bone] - b[bone]).abs() > 0.5) return false;
  }
  return true;
}

/// _figureTile draws the whole character, standing in the tile.
void _figureTile(
    ui.Canvas canvas, Size size, CharacterDna dna, CharacterPose pose) {
  var h = size.height * 0.92;
  paintCharacterFigure(
      canvas,
      Rect.fromCenter(
          center: size.center(Offset.zero), width: h * 0.45, height: h),
      dna,
      pose);
}

/// _headTile draws the character's head, filling the tile.
void _headTile(ui.Canvas canvas, Size size, CharacterDna dna) {
  // A head is one of headsTall lengths of the body: drawn at a height that
  // makes one head about the tile, with the top of the head near its top.
  var h = size.height * 0.8 * dna.headsTall;
  paintCharacterFigure(
      canvas,
      Rect.fromLTWH(size.width / 2 - h / 4, size.height * 0.18, h / 2, h),
      dna,
      CharacterElement.restPose);
}

/// _bodyTile draws the character from the chin to the hips.
void _bodyTile(ui.Canvas canvas, Size size, CharacterDna dna) =>
    _cropTile(canvas, size, dna, 0.85, 0.42);

/// _legsTile draws the character from the hips down.
void _legsTile(ui.Canvas canvas, Size size, CharacterDna dna) =>
    _cropTile(canvas, size, dna, 0.47, 0.5);

/// _cropTile draws the part of the character [from] (a share of its height
/// above the bottom) for [span] of its height, filling the tile.
void _cropTile(ui.Canvas canvas, Size size, CharacterDna dna, double from,
    double span) {
  var h = size.height / span;
  var top = -(1 - from) * h;
  canvas.save();
  canvas.clipRect(Offset.zero & size);
  paintCharacterFigure(
      canvas,
      Rect.fromLTWH(size.width / 2 - h * 0.25, top, h * 0.5, h),
      dna,
      CharacterElement.restPose);
  canvas.restore();
}

/// _controlGroups is the face's controls, in the cards they are shown in.
const List<(String, String, List<FaceControl>)> _controlGroups = [
  (
    "Eyes",
    "Where the eyes look, as a share of as far as they go, and how open "
        "they are.",
    [
      FaceControl.lookX,
      FaceControl.lookY,
      FaceControl.eyesOpen,
      FaceControl.squint,
    ]
  ),
  (
    "Brows",
    "Brows up or down, drawn together and down in a frown, or lifted in the "
        "middle with worry.",
    [FaceControl.browRaise, FaceControl.browSqueeze, FaceControl.browWorry]
  ),
  (
    "Mouth",
    "A smile, or a frown below nought; how far the jaw is open; and the lips "
        "stretched wide, or pushed forward in a pucker below nought.",
    [FaceControl.smile, FaceControl.jaw, FaceControl.wide]
  ),
  (
    "Head",
    "The head turned away from the reader -- to the page's left as it goes "
        "up, round to the back at 180° -- and nodded down, or up below "
        "nought. Tilting is in Pose.",
    [FaceControl.turn, FaceControl.nod]
  ),
];

bool _degrees(FaceControl c) => c == FaceControl.turn || c == FaceControl.nod;

/// _shown is a control as the panel shows it: degrees as they are, the rest
/// as percentages.
double _shown(FaceControl c, double v) => _degrees(c) ? v : v * 100;

double _stored(FaceControl c, double v) => _degrees(c) ? v : v / 100;

/// _feelingName is the feeling [face] is, or "Own expression".
String _feelingName(CharacterFace face) {
  for (var x in expressionPresets) {
    if (_sameFeeling(x.face, face)) return x.name;
  }
  return "Own expression";
}

bool _sameFeeling(CharacterFace a, CharacterFace b) {
  for (var c in FaceControl.values) {
    if (c == FaceControl.turn || c == FaceControl.nod) continue;
    if ((a[c] - b[c]).abs() > 0.01) return false;
  }
  return true;
}

/// _faceTile draws the character's head with [face], filling the tile.
void _faceTile(ui.Canvas canvas, Size size, CharacterDna dna,
    CharacterFace face) {
  var h = size.height * 0.86 * dna.headsTall;
  canvas.save();
  canvas.clipRect(Offset.zero & size);
  paintCharacterFigure(
      canvas,
      Rect.fromLTWH(size.width / 2 - h / 4, size.height * 0.08, h / 2, h),
      dna,
      CharacterElement.restPose,
      face: face);
  canvas.restore();
}

/// _mouthTile draws the lower half of the character's face, close up.
void _mouthTile(ui.Canvas canvas, Size size, CharacterDna dna,
    CharacterFace face) {
  // A head's mouth is about three tenths of a head below its middle; drawn
  // at this size the mouth fills the middle of the tile.
  var head = size.height * 2.2;
  var h = head * dna.headsTall;
  canvas.save();
  canvas.clipRect(Offset.zero & size);
  paintCharacterFigure(
      canvas,
      Rect.fromLTWH(size.width / 2 - h / 4,
          size.height / 2 - head * 0.5 - head * 0.3, h / 2, h),
      dna,
      CharacterElement.restPose,
      face: face);
  canvas.restore();
}

/// _MixGroup mixes the face towards a second feeling, by as much as is
/// asked: 40% of the way from happy to surprised is delight.
class _MixGroup extends StatefulWidget {
  final CharacterFace face;
  final ValueChanged<CharacterFace> onMix;
  const _MixGroup({required this.face, required this.onMix});

  @override
  State<_MixGroup> createState() => _MixGroupState();
}

class _MixGroupState extends State<_MixGroup> {
  int _with = 6;
  double _amount = 40;

  @override
  Widget build(BuildContext context) => CanvasControlGroup(
          label: "Mix in",
          help: "Moves the face part of the way towards another feeling. "
              "Pick the feeling and how far, then Mix.",
          children: [
            CanvasDropdown<int>(
              key: const ValueKey("characterMixWith"),
              label: "Feeling",
              value: _with,
              options: [
                for (var (i, x) in expressionPresets.indexed) (i, x.name),
              ],
              onChanged: (i) => setState(() => _with = i),
            ),
            CanvasStepper(
              key: const ValueKey("characterMixAmount"),
              label: "How far",
              value: _amount,
              min: 0,
              max: 100,
              step: 10,
              suffix: "%",
              onChanged: (v) => setState(() => _amount = v),
            ),
            CanvasTextButton(
              key: const ValueKey("characterMix"),
              icon: Icons.blender_outlined,
              label: "Mix",
              onPressed: () => widget.onMix(widget.face.mixed(
                  widget.face.feeling(expressionPresets[_with].face),
                  _amount / 100)),
            ),
          ]);
}

/// _LipSyncGroup turns a voice-over into this character's mouths.
class _LipSyncGroup extends StatefulWidget {
  final CanvasController controller;
  final CharacterElement character;
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
  /// the voice is nearly always the longest thing on the timeline. The same
  /// list the Cues offer.
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
    var done = await controller.lipSync(widget.character, voice,
        words: _words,
        feel: LipSyncFeel(shortest: _shortest.round(), lead: _lead.round()));
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
    var voice = voices.where((v) => v.id == _voice).firstOrNull ??
        voices.firstOrNull;
    return CanvasControlGroup(
        label: "From the voice-over",
        help: "Hear the words uses the words heard for the Cues -- hearing "
            "them first if they have not been -- and spells each into the "
            "mouths it is said with. Sound only reads how loud the voice is "
            "frame by frame: rougher, but it works in any language with "
            "nothing installed. Either way the mouths are blocks on the "
            "Mouth lane of the timeline, to move or change by hand.",
        children: [
          if (voice == null)
            const CanvasStatus("Add a voice-over first: a timed Audio element, "
                "or a sound on the timeline's channels.")
          else ...[
            CanvasDropdown<String>(
              key: const ValueKey("characterLipVoice"),
              label: "Voice",
              value: voice.id,
              width: 200,
              options: [for (var v in voices) (v.id, v.name)],
              onChanged: (id) => setState(() => _voice = id),
            ),
            const CanvasLineBreak(),
            CanvasToggle(
              key: const ValueKey("characterLipWords"),
              label: "Hear the words",
              value: _words,
              onChanged: (v) => setState(() => _words = v),
            ),
            const CanvasLineBreak(),
            CanvasStepper(
              key: const ValueKey("characterLipShortest"),
              label: "Shortest mouth",
              value: _shortest,
              min: 1,
              max: 6,
              suffix: " fr",
              defaultValue: 2,
              onChanged: (v) => setState(() => _shortest = v),
            ),
            CanvasStepper(
              key: const ValueKey("characterLipLead"),
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
              key: const ValueKey("characterLipSync"),
              icon: Icons.graphic_eq,
              primary: true,
              label: _busy ? "Listening…" : "Lip sync",
              onPressed: _busy ? null : () => _sync(voice),
            ),
            if (widget.character.mouthKeys.isNotEmpty)
              CanvasTextButton(
                key: const ValueKey("characterLipClear"),
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
            CanvasStatus(_said, key: const ValueKey("characterLipSaid")),
          ],
        ]);
  }
}

/// _motionTile draws the character part way through [kind]: side on for a
/// walk or a run, which only read from the side.
void _motionTile(ui.Canvas canvas, Size size, CharacterDna dna, MotionKind kind) {
  var side = kind == MotionKind.walk || kind == MotionKind.run;
  var base = CharacterElement.restPose.withTurn(side ? 90 : 0);
  var t = kind.seconds * (kind.loops ? 0.25 : 0.5);
  var (pose, face) = withMotions(
      base,
      CharacterFace.rest,
      [
        MotionClip(
            id: "", kind: kind, layer: kind.layer, start: 0, length: 1000,
            blend: 0)
      ],
      (t * 24).round(),
      24);
  var h = size.height * 0.86;
  paintCharacterFigure(
      canvas,
      Rect.fromCenter(
          center: size.center(Offset.zero) - Offset(0, h * 0.03),
          width: h * 0.45,
          height: h),
      dna,
      pose,
      face: face);
}

/// _clipGroup is one motion clip's settings: when, how fast, how much, on
/// which layer, mirrored or not, and a button to take it off.
Widget _clipGroup(CanvasController controller, CharacterElement e,
    MotionClip clip, SettingsWrite write, VoidCallback commit) {
  var rate = controller.document.frameRate <= 0 ? 12 : controller.document.frameRate;
  void set(MotionClip next) {
    controller.beginInteraction();
    write(e.copyWith(motions: [
      for (var m in e.motions) m.id == clip.id ? next : m,
    ]));
  }

  return CanvasControlGroup(
      key: ValueKey("characterClip-${clip.id}"),
      label: clip.kind.label,
      help: "When the clip starts and how long it lasts, in seconds; how "
          "fast it plays; how much of it is laid on; and the layer it is "
          "on. Mirror swaps left for right.",
      children: [
        CanvasNumberField(
          key: ValueKey("characterClipStart-${clip.id}"),
          label: "Start",
          value: clip.start / rate,
          min: 0,
          max: controller.document.frames / rate,
          decimals: 2,
          width: 64,
          onChanged: (v) => set(clip.copyWith(start: (v * rate).round())),
          onCommit: commit,
        ),
        CanvasNumberField(
          key: ValueKey("characterClipLength-${clip.id}"),
          label: "Length",
          value: clip.length / rate,
          min: 1 / rate,
          max: 600,
          decimals: 2,
          width: 64,
          onChanged: (v) => set(clip.copyWith(length: (v * rate).round())),
          onCommit: commit,
        ),
        CanvasStepper(
          key: ValueKey("characterClipSpeed-${clip.id}"),
          label: "Speed",
          value: clip.speed * 100,
          min: 10,
          max: 400,
          step: 10,
          suffix: "%",
          defaultValue: 100,
          onChanged: (v) => set(clip.copyWith(speed: v / 100)),
          onCommit: commit,
        ),
        CanvasStepper(
          key: ValueKey("characterClipStrength-${clip.id}"),
          label: "Strength",
          value: clip.strength * 100,
          min: 0,
          max: 100,
          step: 10,
          suffix: "%",
          defaultValue: 100,
          onChanged: (v) => set(clip.copyWith(strength: v / 100)),
          onCommit: commit,
        ),
        CanvasDropdown<MotionLayer>(
          key: ValueKey("characterClipLayer-${clip.id}"),
          label: "Layer",
          value: clip.layer,
          options: [for (var l in MotionLayer.values) (l, l.label)],
          onChanged: (l) {
            set(clip.copyWith(layer: l));
            commit();
          },
        ),
        CanvasToggle(
          key: ValueKey("characterClipMirror-${clip.id}"),
          label: "Mirror",
          value: clip.mirror,
          onChanged: (v) {
            set(clip.copyWith(mirror: v));
            commit();
          },
        ),
        CanvasIconButton(
          key: ValueKey("characterClipRemove-${clip.id}"),
          icon: Icons.delete_outline,
          tooltip: "Take this motion off",
          onPressed: () {
            controller.beginInteraction();
            controller.removeMotion(e, clip.id);
            controller.endInteraction();
          },
        ),
      ]);
}

/// _WalkGroup walks or runs the character across the page.
class _WalkGroup extends StatefulWidget {
  final CanvasController controller;
  final CharacterElement character;
  const _WalkGroup({required this.controller, required this.character});

  @override
  State<_WalkGroup> createState() => _WalkGroupState();
}

class _WalkGroupState extends State<_WalkGroup> {
  double _seconds = 3;

  void _go(MotionKind kind, int direction) {
    var c = widget.controller;
    c.beginInteraction();
    c.walkAcross(widget.character, kind, direction, _seconds);
    c.endInteraction();
  }

  @override
  Widget build(BuildContext context) => CanvasControlGroup(
          label: "Walk across",
          help: "Walks or runs the character across the page from the frame "
              "being looked at: it turns to face the way it is going, goes "
              "as far as its legs would take it, and turns back at the end. "
              "Move the end keyframe to send it somewhere else.",
          children: [
            CanvasStepper(
              key: const ValueKey("characterWalkSeconds"),
              label: "For",
              value: _seconds,
              min: 0.5,
              max: 30,
              step: 0.5,
              decimals: 1,
              suffix: " s",
              onChanged: (v) => setState(() => _seconds = v),
            ),
            const CanvasLineBreak(),
            for (var (kind, dir, label, icon, key) in const [
              (MotionKind.walk, -1, "Walk", Icons.west, "characterWalkLeft"),
              (MotionKind.walk, 1, "Walk", Icons.east, "characterWalkRight"),
              (MotionKind.run, -1, "Run", Icons.keyboard_double_arrow_left,
                  "characterRunLeft"),
              (MotionKind.run, 1, "Run", Icons.keyboard_double_arrow_right,
                  "characterRunRight"),
            ])
              CanvasTextButton(
                key: ValueKey(key),
                icon: icon,
                label: label,
                onPressed: () => _go(kind, dir),
              ),
          ]);
}

/// _ImportGroup lays motion capture from a BVH file on the character.
class _ImportGroup extends StatefulWidget {
  final CanvasController controller;
  final CharacterElement character;
  const _ImportGroup({required this.controller, required this.character});

  @override
  State<_ImportGroup> createState() => _ImportGroupState();
}

class _ImportGroupState extends State<_ImportGroup> {
  bool _faceReader = true;
  String _said = "";

  Future<void> _pick() async {
    var picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ["bvh"],
      withData: false,
    );
    var file = picked?.files.singleOrNull?.path;
    if (file == null) return;
    await importFrom(file);
  }

  /// importFrom reads the BVH at [file] and lays it on the character.
  Future<void> importFrom(String file) async {
    var c = widget.controller;
    String said;
    try {
      var bvh = parseBvh(await File(file).readAsString());
      var poses = bvhPoses(bvh,
          frameRate: c.document.frameRate <= 0 ? 12 : c.document.frameRate,
          headsTall: widget.character.dna.headsTall);
      var now = c.document.elementById(widget.character.id);
      if (now is! CharacterElement) return;
      c.beginInteraction();
      var laid = c.importMotion(now, poses, faceReader: _faceReader);
      c.endInteraction();
      said = laid < poses.length
          ? "$laid of ${poses.length} frames laid: the canvas ended first."
          : "$laid frames of motion laid, from the playhead on.";
    } on BvhError catch (error) {
      said = "That file could not be read: $error";
    } on FileSystemException {
      said = "That file could not be opened.";
    }
    if (mounted) setState(() => _said = said);
  }

  @override
  Widget build(BuildContext context) => CanvasControlGroup(
          label: "Motion capture",
          help: "Lays a BVH file -- motion capture, as the CMU library and "
              "most capture tools give it out -- on the character as "
              "keyframes from the frame being looked at. Any skeleton "
              "with the usual joints works, Mixamo's included; the "
              "character's own proportions are kept.",
          children: [
            CanvasTextButton(
              key: const ValueKey("characterImportBvh"),
              icon: Icons.file_open_outlined,
              label: "Import a BVH file",
              onPressed: _pick,
            ),
            CanvasToggle(
              key: const ValueKey("characterImportFace"),
              label: "Start facing the reader",
              value: _faceReader,
              onChanged: (v) => setState(() => _faceReader = v),
            ),
            if (_said.isNotEmpty) ...[
              const CanvasLineBreak(),
              CanvasStatus(_said, key: const ValueKey("characterImportSaid")),
            ],
          ]);
}

/// _garmentTile draws [dna] wearing what it wears, cropped to where a
/// garment of [slot] goes: the head for a hat, the feet for shoes.
void _garmentTile(
    ui.Canvas canvas, Size size, CharacterDna dna, GarmentSlot slot) {
  switch (slot) {
    case GarmentSlot.head || GarmentSlot.face:
      _headTile(canvas, size, dna);
    case GarmentSlot.neck || GarmentSlot.top || GarmentSlot.outer:
      _bodyTile(canvas, size, dna);
    case GarmentSlot.bottom:
      _legsTile(canvas, size, dna);
    case GarmentSlot.feet:
      _cropTile(canvas, size, dna, 0.2, 0.25);
    case GarmentSlot.base || GarmentSlot.full:
      _figureTile(canvas, size, dna, CharacterElement.restPose);
  }
}

/// _defaultColour is the colour a garment of [kind] is put on in, when it
/// replaces nothing it could take its colour from.
Color _defaultColour(GarmentKind kind) => switch (kind.slot) {
      GarmentSlot.base => const Color(0xFFF4F4F4),
      GarmentSlot.bottom => const Color(0xFF2F3E5C),
      GarmentSlot.top => const Color(0xFF5B9CFF),
      GarmentSlot.full => const Color(0xFFE05A47),
      GarmentSlot.outer => const Color(0xFF6A4A3A),
      GarmentSlot.feet => const Color(0xFF2A2A2A),
      GarmentSlot.neck => const Color(0xFFE05A47),
      GarmentSlot.face => const Color(0xFF1E1E1E),
      GarmentSlot.head => const Color(0xFF2F3E5C),
    };

/// _WardrobeGroup is what the character wears: costumes to start from,
/// garments to put on, what is worn and in what order, and the one picked,
/// to change.
class _WardrobeGroup extends StatefulWidget {
  final CanvasController controller;
  final CharacterElement character;
  final SettingsWrite write;
  final VoidCallback commit;
  const _WardrobeGroup(
      {required this.controller,
      required this.character,
      required this.write,
      required this.commit});

  @override
  State<_WardrobeGroup> createState() => _WardrobeGroupState();
}

class _WardrobeGroupState extends State<_WardrobeGroup> {
  GarmentSlot _slot = GarmentSlot.top;
  int _picked = -1;

  CharacterElement get e => widget.character;
  CharacterDna get dna => e.dna;

  void _now(CharacterElement next) {
    widget.controller.beginInteraction();
    widget.write(next);
    widget.commit();
  }

  void _wear(List<Garment> wardrobe) =>
      _now(e.copyWith(dna: dna.copyWith(wardrobe: wardrobe)));

  /// _change writes the picked garment as [g]: [live] while a number is
  /// being dragged, committed when it is let go.
  void _change(Garment g, {bool live = false}) {
    var wardrobe = [...dna.wardrobe];
    wardrobe[_picked] = g;
    var next = e.copyWith(dna: dna.copyWith(wardrobe: wardrobe));
    if (live) {
      widget.controller.beginInteraction();
      widget.write(next);
    } else {
      _now(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    var drawn = dna.toJson().toString();
    var wardrobe = dna.wardrobe;
    if (_picked >= wardrobe.length) _picked = -1;
    var picked = _picked >= 0 ? wardrobe[_picked] : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CanvasControlGroup(
          label: "Showing",
          help: "Bare view shows the body without its clothes while you "
              "design it -- on the stage only: everything made from the "
              "canvas is dressed. Base layer is the underwear and swimwear: "
              "off, nothing is drawn under the clothes.",
          children: [
            CanvasToggle(
              key: const ValueKey("characterBareView"),
              label: "Bare view",
              value: e.bareView,
              onChanged: (v) => _now(e.copyWith(bareView: v)),
            ),
            CanvasToggle(
              key: const ValueKey("characterBaseLayer"),
              label: "Base layer",
              value: dna.baseLayer,
              onChanged: (v) => _now(e.copyWith(dna: dna.copyWith(baseLayer: v))),
            ),
          ]),
      CanvasTiles<int>(
        label: "Costumes",
        help: "A whole outfit at once, in place of what is worn now.",
        columns: 5,
        previewHeight: 64,
        tiles: [
          for (var (i, c) in costumes.indexed)
            CanvasTile(i, c.name,
                drawnFrom: drawn,
                paint: (canvas, size) => _figureTile(canvas, size,
                    dna.copyWith(wardrobe: c.wardrobe), CharacterElement.restPose)),
        ],
        selected: (_) => false,
        keyOf: (i) => "characterCostume-${costumes[i].name}",
        onPick: (i) {
          _picked = -1;
          _wear(seeded(costumes[i].wardrobe));
        },
      ),
      CanvasControlGroup(
          label: "Put on",
          help: "Pick where it goes, then what. It goes on in its place -- "
              "over what is worn under it, under what is worn over it -- "
              "and takes off whatever it replaces.",
          children: [
            CanvasDropdown<GarmentSlot>(
              key: const ValueKey("characterSlot"),
              label: "Where",
              value: _slot,
              width: 170,
              options: [for (var s in GarmentSlot.values) (s, s.label)],
              onChanged: (v) => setState(() => _slot = v),
            ),
          ]),
      CanvasTiles<GarmentKind>(
        columns: 4,
        previewHeight: 56,
        tiles: [
          for (var k in GarmentKind.values)
            if (k.slot == _slot)
              CanvasTile(k, k.label,
                  drawnFrom: drawn,
                  paint: (canvas, size) => _garmentTile(
                      canvas,
                      size,
                      dna.copyWith(
                          wardrobe: putOn(dna.wardrobe,
                              Garment(k, color: _defaultColour(k)))),
                      _slot)),
        ],
        selected: (k) => wardrobe.any((g) => g.kind == k),
        keyOf: (k) => "characterGarment-${k.name}",
        onPick: (k) {
          // A garment put on in place of another keeps its colour.
          var old = wardrobe.where((g) => g.kind.slot == k.slot).firstOrNull;
          var g = Garment(k,
              color: old?.color ?? _defaultColour(k),
              color2: old?.color2 ?? const Color(0xFFFFFFFF),
              seed: newSeed(wardrobe.length, k));
          var next = putOn(wardrobe, g);
          _picked = next.indexOf(g);
          _wear(next);
        },
      ),
      CanvasControlGroup(
          label: "Worn, inside to outside",
          help: "Everything worn, the innermost first. Click one to change "
              "it below. The arrows move it in or out -- which is worn over "
              "which is the order.",
          children: [
            for (var (i, g) in wardrobe.indexed) ...[
              const CanvasLineBreak(),
              CanvasTextButton(
                key: ValueKey("characterWorn-$i"),
                label: g.kind.label,
                primary: i == _picked,
                onPressed: () => setState(() => _picked = i),
              ),
              CanvasIconButton(
                key: ValueKey("characterWornIn-$i"),
                icon: Icons.arrow_upward,
                tooltip: "Wear it further in",
                onPressed: i == 0
                    ? null
                    : () {
                        if (_picked == i) _picked = i - 1;
                        _wear(moved(wardrobe, i, -1));
                      },
              ),
              CanvasIconButton(
                key: ValueKey("characterWornOut-$i"),
                icon: Icons.arrow_downward,
                tooltip: "Wear it further out",
                onPressed: i == wardrobe.length - 1
                    ? null
                    : () {
                        if (_picked == i) _picked = i + 1;
                        _wear(moved(wardrobe, i, 1));
                      },
              ),
              CanvasIconButton(
                key: ValueKey("characterWornOff-$i"),
                icon: Icons.close,
                tooltip: "Take it off",
                onPressed: () {
                  _picked = -1;
                  _wear([...wardrobe]..removeAt(i));
                },
              ),
            ],
          ]),
      if (picked != null) ..._garmentEditor(picked),
    ]);
  }

  List<Widget> _garmentEditor(Garment g) {
    var k = g.kind;
    return [
      CanvasControlGroup(
          key: const ValueKey("characterGarmentEditor"),
          label: k.label,
          help: "Its colours -- the second is its pattern's, and its trim's "
              "-- and how it is cut: how loose, how long, how far down "
              "the arm.",
          children: [
            CanvasColorButton(
              label: "Colour",
              color: g.color,
              onChanged: (c) => _change(g.copyWith(color: c)),
            ),
            CanvasColorButton(
              label: "Second",
              color: g.color2,
              onChanged: (c) => _change(g.copyWith(color2: c)),
            ),
            CanvasDropdown<GarmentPattern>(
              key: const ValueKey("characterGarmentPattern"),
              label: "Pattern",
              value: g.pattern,
              options: [for (var p in GarmentPattern.values) (p, p.label)],
              onChanged: (p) => _change(g.copyWith(pattern: p)),
            ),
            const CanvasLineBreak(),
            CanvasStepper(
              key: const ValueKey("characterGarmentFit"),
              label: "Fit",
              value: g.fitOr * 100,
              min: 80,
              max: 140,
              step: 5,
              suffix: "%",
              defaultValue: k.fit * 100,
              onChanged: (v) => _change(g.copyWith(fit: v / 100), live: true),
              onCommit: widget.commit,
            ),
            if (k.hasLength)
              CanvasStepper(
                key: const ValueKey("characterGarmentLength"),
                label: "Length",
                value: g.lengthOr * 100,
                min: 5,
                max: 200,
                step: 5,
                suffix: "%",
                defaultValue: k.length * 100,
                onChanged: (v) =>
                    _change(g.copyWith(length: v / 100), live: true),
                onCommit: widget.commit,
              ),
            if (k.hasSleeves)
              CanvasStepper(
                key: const ValueKey("characterGarmentSleeve"),
                label: "Sleeves",
                value: g.sleeveOr * 100,
                min: 0,
                max: 100,
                step: 5,
                suffix: "%",
                defaultValue: k.sleeve * 100,
                onChanged: (v) =>
                    _change(g.copyWith(sleeve: v / 100), live: true),
                onCommit: widget.commit,
              ),
          ]),
      CanvasTiles<int>(
        label: "Condition",
        help: "How worn it is. Pick a starting point, then change any of "
            "it. Rips go right through, so whatever is underneath shows. "
            "The wear is laid out the same way every time.",
        columns: 3,
        previewHeight: 56,
        tiles: [
          for (var (i, p) in conditionPresets.indexed)
            CanvasTile(i, p.$1,
                drawnFrom: "${dna.toJson()}|$_picked",
                paint: (canvas, size) {
                  var worn = [...dna.wardrobe];
                  worn[_picked] = g.copyWith(condition: p.$2);
                  _garmentTile(canvas, size, dna.copyWith(wardrobe: worn),
                      g.kind.slot);
                }),
        ],
        selected: (i) => _sameCondition(conditionPresets[i].$2, g.condition),
        keyOf: (i) => "characterCondition-${conditionPresets[i].$1}",
        onPick: (i) => _change(g.copyWith(condition: conditionPresets[i].$2)),
      ),
      CanvasControlGroup(
          label: "Wear",
          help: "Each from as new to as bad as it gets.",
          children: [
            for (var (name, value, set) in <(String, double,
                GarmentCondition Function(double))>[
              ("Faded", g.condition.fade, (v) => g.condition.copyWith(fade: v)),
              ("Dirt", g.condition.dirt, (v) => g.condition.copyWith(dirt: v)),
              ("Rips", g.condition.rips, (v) => g.condition.copyWith(rips: v)),
              ("Frayed", g.condition.frays,
                  (v) => g.condition.copyWith(frays: v)),
              ("Patched", g.condition.patches,
                  (v) => g.condition.copyWith(patches: v)),
            ])
              CanvasStepper(
                key: ValueKey("characterWear-$name"),
                label: name,
                value: value * 100,
                min: 0,
                max: 100,
                step: 10,
                suffix: "%",
                defaultValue: 0,
                onChanged: (v) =>
                    _change(g.copyWith(condition: set(v / 100)), live: true),
                onCommit: widget.commit,
              ),
          ]),
    ];
  }
}

bool _sameCondition(GarmentCondition a, GarmentCondition b) =>
    a.fade == b.fade &&
    a.dirt == b.dirt &&
    a.rips == b.rips &&
    a.frays == b.frays &&
    a.patches == b.patches;
