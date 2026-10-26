import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/character_bvh.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_motion_files.dart';
import 'package:bruig/plugin_system/canvas/ui/body_capture.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_gltf.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_lipsync.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_motion.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_wardrobe.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_painter.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/orbit_pad.dart';
import 'package:bruig/plugin_system/canvas/ui/garment_shape_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/image_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/model_picking.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/character_appearance_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/storage/human_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/human_wear_assets.dart';
import 'package:bruig/plugin_system/canvas/model/elements/human_wear.dart';
import 'package:bruig/plugin_system/canvas/render/model/human_body.dart';
import 'package:bruig/plugin_system/canvas/ui/asset_elements.dart';
import 'package:bruig/plugin_system/canvas/ui/media_picking.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:provider/provider.dart';

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
  var style = e.style;
  void dnaNow(CharacterDna next) => now(e.copyWith(dna: next));
  // What every tile of this character is drawn from, so a tile changes
  // when the character does and not otherwise. See TileSnapshot.
  var drawn = "${dna.toJson()}|${style.name}";
  var pose = e.poseAtFrame(controller.frame);
  var animated = controller.document.isAnimated;
  var keyed = controller.hasCharacterPoseKey(e);
  var face = e.faceAtFrame(controller.frame);
  void faceNow(CharacterFace next) => now(controller.characterFaced(e, next));

  return [
    section(e, "character",
        icon: Icons.person_outline,
        title: "Type",
        summary: "${dna.kind.label} · ${shortNumber(dna.headsTall)} heads tall",
        initiallyOpen: true,
        children: [
          for (var family in TypeFamily.values)
            CanvasTiles<CharacterType>(
              label: family.label,
              help: family == TypeFamily.people
                  ? "What kind of character this is. A type sets the body, "
                      "the face and the proportions, and what the panel "
                      "offers below; everything about it is still yours to "
                      "change in Appearance. Between people, the colours "
                      "and the clothes are kept."
                  : "",
              columns: 6,
              previewHeight: 60,
              tiles: [
                for (var t in CharacterType.values)
                  if (t.family == family)
                    CanvasTile(t, t.label,
                        drawnFrom: "${t.name}|${style.name}",
                        paint: (canvas, size) =>
                            _typeTile(canvas, size, t, style)),
              ],
              selected: (t) => dna.kind == t,
              keyOf: (t) => "characterType-${t.name}",
              onPick: (t) {
                var next = e.copyWith(dna: t.becomes(dna));
                // Renamed with it, unless it has a name of its own.
                var named = e.base.name.isEmpty ||
                    characterCast.any((c) => c.name == e.base.name) ||
                    CharacterType.values.any((x) => x.label == e.base.name);
                now(named
                    ? next.withBase(name: t.label) as CharacterElement
                    : next);
              },
            ),
          if (characterCast.any((c) => c.dna.kind == dna.kind))
            CanvasTiles<int>(
              label: "Ready-made",
              help: "Someone of this type to start from. Their look is "
                  "copied onto this character, and from then on it is this "
                  "character's own to change.",
              columns: 5,
              previewHeight: 64,
              tiles: [
                for (var (i, who) in characterCast.indexed)
                  if (who.dna.kind == dna.kind)
                    CanvasTile(i, who.name,
                        drawnFrom: "${who.dna.toJson()}|${style.name}",
                        paint: (canvas, size) => _figureTile(canvas, size,
                            who.dna, CharacterElement.restPose, style)),
              ],
              selected: (i) =>
                  characterCast[i].dna.toJson().toString() ==
                  dna.toJson().toString(),
              keyOf: (i) => "characterCast-${characterCast[i].name}",
              onPick: (i) {
                var who = characterCast[i];
                var next = e.copyWith(dna: who.dna);
                var named = e.base.name.isEmpty ||
                    characterCast.any((c) => c.name == e.base.name) ||
                    CharacterType.values.any((x) => x.label == e.base.name);
                now(named
                    ? next.withBase(name: who.name) as CharacterElement
                    : next);
              },
            ),
        ]),
    section(e, "madeOf",
        icon: Icons.view_in_ar_outlined,
        title: "Made of",
        summary: e.body.kind == BodyKind.model && e.body.modelName.isNotEmpty
            ? e.body.modelName
            : e.body.kind.label,
        initiallyOpen: true,
        children: [
          CanvasTiles<BodyKind>(
            label: "Made of",
            help: "A flat sketch, as the style draws it, or a body sculpted "
                "in 3D from this character's type and Appearance -- lit, "
                "inked and given a face as its style draws them. Either way "
                "it is posed, animated and lip-synced the same.",
            columns: 3,
            previewHeight: 64,
            tiles: [
              // A model from a file is no longer offered: kept only for a
              // character already made of one, so it can be changed.
              for (var k in BodyKind.values)
                if (k != BodyKind.model || e.body.kind == BodyKind.model)
                  CanvasTile(k, k.label,
                      drawnFrom: "$drawn|${k.name}|${e.body.modelId}|"
                          "${controller.images.resolveModel(e.body.modelId) != null}",
                      paint: (canvas, size) => _figureTile(
                          canvas,
                          size,
                          dna,
                          CharacterElement.restPose,
                          style,
                          e.body.copyWith(kind: k),
                          controller.images)),
            ],
            selected: (k) => k == e.body.kind,
            keyOf: (k) => "characterBody-${k.name}",
            onPick: (k) => now(e.copyWith(body: e.body.copyWith(kind: k))),
          ),
          // A sculpted body is lit and inked as its style draws; a model
          // brought in is lit as chosen here.
          if (e.body.kind == BodyKind.model) ...[
            CanvasTiles<ModelShading>(
              label: "Shading",
              help: "How the body in 3D is lit: softly, in two flat bands as "
                  "a cel is, or face by face.",
              columns: 3,
              previewHeight: 64,
              tiles: [
                for (var sh in ModelShading.values)
                  CanvasTile(sh, sh.label,
                      drawnFrom: "$drawn|${e.body.kind.name}|${sh.name}|"
                          "${e.body.outline}|${e.body.modelId}|"
                          "${controller.images.resolveModel(e.body.modelId) != null}",
                      paint: (canvas, size) => _figureTile(
                          canvas,
                          size,
                          dna,
                          CharacterElement.restPose,
                          style,
                          e.body.copyWith(shading: sh),
                          controller.images)),
              ],
              selected: (sh) => sh == e.body.shading,
              keyOf: (sh) => "characterShading-${sh.name}",
              onPick: (sh) =>
                  now(e.copyWith(body: e.body.copyWith(shading: sh))),
            ),
            CanvasControlGroup(
                label: "Outline",
                help: "A line round the whole figure, as ink round a cel.",
                children: [
                  CanvasToggle(
                    key: const ValueKey("characterOutline"),
                    label: "Outline",
                    value: e.body.outline,
                    onChanged: (v) =>
                        now(e.copyWith(body: e.body.copyWith(outline: v))),
                  ),
                ]),
          ],
          if (e.body.kind == BodyKind.mannequin)
            SculptedBodyGroup(
                key: const ValueKey("characterSculpted"), character: e),
          if (e.body.kind == BodyKind.model)
            ModelImportGroup(
                key: ValueKey("characterModel-${e.id}"),
                controller: controller,
                character: e),
        ]),
    section(e, "style",
        icon: Icons.brush_outlined,
        title: "Style",
        summary: style.label,
        initiallyOpen: true,
        children: [
          CanvasTiles<StyleFamily>(
            label: "Family",
            help: "What kind of drawing: pick one, then the style within it "
                "nearest the look you want. A style changes the drawing and "
                "nothing else: the same person, clothes and moves, drawn "
                "another way.",
            columns: 5,
            previewHeight: 64,
            tiles: [
              for (var f in StyleFamily.values)
                CanvasTile(f, f.label,
                    drawnFrom: "${_styleTileKey(dna, e.body)}|${f.name}",
                    paint: (canvas, size) => _figureTile(
                        canvas,
                        size,
                        dna,
                        CharacterElement.restPose,
                        CharacterStyle.inFamily(f).first,
                        _styleTileBody(e.body),
                        controller.images,
                        style)),
            ],
            selected: (f) => style.family == f,
            keyOf: (f) => "characterStyleFamily-${f.name}",
            onPick: (f) =>
                now(e.copyWith(style: CharacterStyle.inFamily(f).first)),
          ),
          CanvasTiles<CharacterStyle>(
            label: style.family.label,
            help: [
              for (var st in CharacterStyle.inFamily(style.family))
                "${st.label}: ${st.about}",
            ].join(". "),
            columns: 4,
            previewHeight: 76,
            tiles: [
              for (var st in CharacterStyle.inFamily(style.family))
                CanvasTile(st, st.label,
                    drawnFrom: "${_styleTileKey(dna, e.body)}|${st.name}",
                    paint: (canvas, size) => _headTile(
                        canvas, size, dna, st, _styleTileBody(e.body), style)),
            ],
            selected: (st) => st == style,
            keyOf: (st) => "characterStyle-${st.name}",
            onPick: (st) => now(e.copyWith(style: st)),
          ),
        ]),
    section(e, "appearance",
        icon: Icons.face_retouching_natural_outlined,
        title: "Appearance",
        summary: dna.look.isRest
            ? "As the type is"
            : "${dna.look.values.length} change${dna.look.values.length == 1 ? "" : "s"}",
        changes: dna.look.values.length,
        onReset: () => dnaNow(dna.copyWith(look: dna.kind.dna.look)),
        initiallyOpen: true,
        children: [
          AppearanceEditor(
            key: ValueKey("characterAppearance-${e.id}"),
            controller: controller,
            character: e,
            write: write,
            commit: commit,
          ),
        ]),
    section(e, "creature",
        icon: Icons.pets_outlined,
        title: "Creature",
        summary: [
          dna.species.label,
          if (dna.fourLegs) "four legs",
          if (dna.tail != TailKind.none) "${dna.tail.label.toLowerCase()} tail",
          if (dna.wings != WingKind.none) "wings",
        ].join(" · "),
        children: [
          CanvasTiles<Species>(
            label: "Species",
            help: "What kind of creature: its ears, muzzle and nose. Skin is "
                "its fur, under Look; the second colour is the lighter fur "
                "of its muzzle and belly.",
            columns: 5,
            previewHeight: 48,
            tiles: [
              for (var sp in Species.values)
                CanvasTile(sp, sp.label,
                    drawnFrom: "$drawn|${sp.name}",
                    paint: (canvas, size) => _headTile(
                        canvas,
                        size,
                        dna.copyWith(
                            species: sp,
                            hairStyle: sp == Species.human
                                ? dna.hairStyle
                                : HairStyle.bald),
                        style)),
            ],
            selected: (sp) => dna.species == sp,
            keyOf: (sp) => "characterSpecies-${sp.name}",
            onPick: (sp) => dnaNow(dna.copyWith(
                species: sp,
                // An animal's fur is its hair: a head of hair on a fox is a
                // wig.
                hairStyle: sp.animal ? HairStyle.bald : dna.hairStyle)),
          ),
          CanvasControlGroup(
              label: "Body",
              help: "Four legs stands it like an animal: its body level, its "
                  "arms its front legs. Every motion and pin works the same "
                  "way -- a walk is a four-legged walk.",
              children: [
                CanvasToggle(
                  key: const ValueKey("characterFourLegs"),
                  label: "Four legs",
                  value: dna.fourLegs,
                  onChanged: (v) => dnaNow(dna.copyWith(fourLegs: v)),
                ),
                CanvasStepper(
                  key: const ValueKey("characterEyeCount"),
                  label: "Eyes",
                  value: dna.eyeCount.toDouble(),
                  min: 1,
                  max: 3,
                  defaultValue: 2,
                  onChanged: (v) =>
                      write(e.copyWith(dna: dna.copyWith(eyeCount: v.round()))),
                  onCommit: commit,
                ),
                CanvasToggle(
                  key: const ValueKey("characterFangs"),
                  label: "Fangs",
                  value: dna.fangs,
                  onChanged: (v) => dnaNow(dna.copyWith(fangs: v)),
                ),
                CanvasToggle(
                  key: const ValueKey("characterSpikes"),
                  label: "Spikes",
                  value: dna.spikes,
                  onChanged: (v) => dnaNow(dna.copyWith(spikes: v)),
                ),
                CanvasColorButton(
                  label: "Second fur",
                  color: dna.fur2,
                  onChanged: (c) => dnaNow(dna.copyWith(fur2: c)),
                ),
              ]),
          CanvasControlGroup(
              label: "Tail, wings and horns",
              help: "What grows from the back and the head. The horns and "
                  "spikes are in the second fur colour.",
              children: [
                CanvasDropdown<TailKind>(
                  key: const ValueKey("characterTail"),
                  label: "Tail",
                  value: dna.tail,
                  options: [for (var t in TailKind.values) (t, t.label)],
                  onChanged: (t) => dnaNow(dna.copyWith(tail: t)),
                ),
                CanvasDropdown<WingKind>(
                  key: const ValueKey("characterWings"),
                  label: "Wings",
                  value: dna.wings,
                  options: [for (var w in WingKind.values) (w, w.label)],
                  onChanged: (w) => dnaNow(dna.copyWith(wings: w)),
                ),
                CanvasDropdown<HornKind>(
                  key: const ValueKey("characterHorns"),
                  label: "Horns",
                  value: dna.horns,
                  options: [for (var h in HornKind.values) (h, h.label)],
                  onChanged: (h) => dnaNow(dna.copyWith(horns: h)),
                ),
              ]),
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
              // On a model brought in, in 3D: a pose is seen on what it
              // moves. A sculpted body's is the sketch's -- a dozen figures
              // in 3D are too many to draw again as it changes.
              for (var (i, p) in posePresets.indexed)
                CanvasTile(i, p.name,
                    drawnFrom:
                        "$drawn|${e.body.kind == BodyKind.model ? e.body.toJson() : ""}|"
                        "${controller.images.resolveModel(e.body.modelId) != null}",
                    paint: (canvas, size) => _figureTile(
                        canvas,
                        size,
                        dna,
                        p.pose,
                        style,
                        e.body.kind == BodyKind.model
                            ? e.body
                            : const CharacterBody(),
                        controller.images)),
            ],
            selected: (i) => _samePose(posePresets[i].pose, pose),
            keyOf: (i) => "characterPose-${posePresets[i].name}",
            onPick: (i) =>
                now(controller.characterPosed(e, posePresets[i].pose)),
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
                    onChanged: (v) => write(
                        controller.characterPosed(e, pose.withAngle(bone, v))),
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
                    paint: (canvas, size) =>
                        _motionTile(canvas, size, dna, k, style)),
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
                        _faceTile(canvas, size, dna, x.face, style)),
            ],
            selected: (i) => _sameFeeling(expressionPresets[i].face, face),
            keyOf: (i) => "characterFeeling-${expressionPresets[i].name}",
            onPick: (i) => faceNow(face.feeling(expressionPresets[i].face)),
          ),
          _MixGroup(face: face, onMix: (mixed) => faceNow(mixed)),
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
                    paint: (canvas, size) => _mouthTile(canvas, size, dna,
                        CharacterFace.rest.withMouth(m), style)),
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
    _stageSection(controller, e, write, commit, now),
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

/// _styleTileBody is what a style's tile draws the character as: in 3D
/// when it is sculpted, as a sketch otherwise.
CharacterBody _styleTileBody(CharacterBody body) =>
    body.kind == BodyKind.mannequin ? body : const CharacterBody();

/// _styleTileKey is what a style's tile is drawn from: in 3D, not the fine
/// shaping of the face and body, which barely shows at a tile's size and
/// would draw every tile in 3D again for each step of a slider.
String _styleTileKey(CharacterDna dna, CharacterBody body) {
  if (body.kind != BodyKind.mannequin) return "${dna.toJson()}";
  return "${dna.toJson()..remove("look")}|3d";
}

/// _figureTile draws the whole character, standing in the tile.
void _figureTile(
    ui.Canvas canvas, Size size, CharacterDna dna, CharacterPose pose,
    [CharacterStyle style = CharacterStyle.featureCartoon,
    CharacterBody body = const CharacterBody(),
    CanvasImageSource? images,
    CharacterStyle? bodyStyle]) {
  var h = size.height * 0.92;
  paintCharacterFigure(
      canvas,
      Rect.fromCenter(
          center: size.center(Offset.zero), width: h * 0.45, height: h),
      dna,
      pose,
      style: style,
      body: body,
      images: images,
      bodyStyle: body.inThreeD ? bodyStyle : null);
}

/// _typeTile draws a new character of type [t] standing in the tile --
/// side on when it stands on four legs, which face on is all chest.
void _typeTile(
    ui.Canvas canvas, Size size, CharacterType t, CharacterStyle style) {
  var dna = t.dna;
  var pose = dna.fourLegs
      ? CharacterElement.restPose.withTurn(65)
      : CharacterElement.restPose;
  var h = size.height * 0.92;
  var w = dna.fourLegs ? h * 0.9 : h * 0.45;
  paintCharacterFigure(
      canvas,
      Rect.fromCenter(center: size.center(Offset.zero), width: w, height: h),
      dna,
      pose,
      style: style);
}

/// _headTile draws the character's head, filling the tile.
void _headTile(ui.Canvas canvas, Size size, CharacterDna dna,
    [CharacterStyle style = CharacterStyle.featureCartoon,
    CharacterBody body = const CharacterBody(),
    CharacterStyle? bodyStyle]) {
  // A head is one of headsTall lengths of the body: drawn at a height that
  // makes one head about the tile, with the top of the head near its top --
  // in 3D, the body as made, whatever the style's proportions.
  var threeD = body.inThreeD && bodyStyle != null;
  var h = size.height *
      0.8 *
      (threeD ? bodyStyle.dnaOf(dna).headsTall : style.dnaOf(dna).headsTall);
  paintCharacterFigure(
      canvas,
      Rect.fromLTWH(size.width / 2 - h / 4, size.height * 0.18, h / 2, h),
      dna,
      CharacterElement.restPose,
      style: style,
      body: body,
      bodyStyle: threeD ? bodyStyle : null);
}

/// _bodyTile draws the character from the chin to the hips.
void _bodyTile(ui.Canvas canvas, Size size, CharacterDna dna,
        [CharacterStyle style = CharacterStyle.featureCartoon]) =>
    _cropTile(canvas, size, dna, 0.85, 0.42, style);

/// _legsTile draws the character from the hips down.
void _legsTile(ui.Canvas canvas, Size size, CharacterDna dna,
        [CharacterStyle style = CharacterStyle.featureCartoon]) =>
    _cropTile(canvas, size, dna, 0.47, 0.5, style);

/// _cropTile draws the part of the character [from] (a share of its height
/// above the bottom) for [span] of its height, filling the tile.
void _cropTile(
    ui.Canvas canvas, Size size, CharacterDna dna, double from, double span,
    [CharacterStyle style = CharacterStyle.featureCartoon]) {
  var h = size.height / span;
  var top = -(1 - from) * h;
  canvas.save();
  canvas.clipRect(Offset.zero & size);
  paintCharacterFigure(
      canvas,
      Rect.fromLTWH(size.width / 2 - h * 0.25, top, h * 0.5, h),
      dna,
      CharacterElement.restPose,
      style: style);
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
void _faceTile(
    ui.Canvas canvas, Size size, CharacterDna dna, CharacterFace face,
    [CharacterStyle style = CharacterStyle.featureCartoon]) {
  var h = size.height * 0.86 * dna.headsTall;
  canvas.save();
  canvas.clipRect(Offset.zero & size);
  paintCharacterFigure(
      canvas,
      Rect.fromLTWH(size.width / 2 - h / 4, size.height * 0.08, h / 2, h),
      dna,
      CharacterElement.restPose,
      face: face,
      style: style);
  canvas.restore();
}

/// _mouthTile draws the lower half of the character's face, close up.
void _mouthTile(
    ui.Canvas canvas, Size size, CharacterDna dna, CharacterFace face,
    [CharacterStyle style = CharacterStyle.featureCartoon]) {
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
      face: face,
      style: style);
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

  /// _record starts the microphone, or -- recording -- stops it and puts
  /// what it heard on the timeline from where the recording began, on a
  /// channel of its own, as the voice to lip sync to.
  Future<void> _record() async {
    if (LiveCapture.recording.value == CaptureKind.microphone) {
      String said;
      try {
        var file = await LiveCapture.stop();
        if (file == null || !mounted) {
          said = "Nothing was recorded.";
        } else {
          var source = await addCanvasAudio(context, controller, file);
          if (source == null || !mounted) {
            said = "The recording could not be kept.";
          } else {
            var clip = channelClip(controller.document, _recordFrom,
                source: source,
                channel: controller.newChannelId(),
                channelName: "Voice");
            controller.addElement(clip);
            _voice = clip.id;
            said = "Recorded, from frame ${_recordFrom + 1}. Lip sync to it "
                "below.";
          }
          try {
            await File(file).delete();
          } catch (_) {}
        }
      } catch (error) {
        said = "$error";
      }
      if (mounted) setState(() => _said = said);
      return;
    }
    try {
      _recordFrom = controller.frame;
      await LiveCapture.start(CaptureKind.microphone);
      if (mounted) setState(() => _said = "Recording. Press Stop when done.");
    } catch (error) {
      if (mounted) setState(() => _said = "$error");
    }
  }

  /// _recordFrom is the frame a voice-over being recorded starts on.
  int _recordFrom = 0;

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
    var voice =
        voices.where((v) => v.id == _voice).firstOrNull ?? voices.firstOrNull;
    return CanvasControlGroup(
        label: "From the voice-over",
        help: "Hear the words uses the words heard for the Cues -- hearing "
            "them first if they have not been -- and spells each into the "
            "mouths it is said with. Sound only reads how loud the voice is "
            "frame by frame: rougher, but it works in any language with "
            "nothing installed. Either way the mouths are blocks on the "
            "Mouth lane of the timeline, to move or change by hand.",
        children: [
          if (LiveCapture.available &&
              context.watch<CanvasPreferences>().allowCapture)
            ValueListenableBuilder<CaptureKind?>(
              valueListenable: LiveCapture.recording,
              builder: (context, now, _) => CanvasTextButton(
                key: const ValueKey("characterRecordVoice"),
                icon: now == CaptureKind.microphone
                    ? Icons.stop_circle_outlined
                    : Icons.mic_none_outlined,
                label: now == CaptureKind.microphone
                    ? "Stop, and use it"
                    : "Record a voice-over",
                primary: now == CaptureKind.microphone,
                onPressed: now != null && now != CaptureKind.microphone
                    ? null
                    : _record,
              ),
            ),
          if (LiveCapture.available) captureSwitch(context),
          const CanvasLineBreak(),
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
void _motionTile(ui.Canvas canvas, Size size, CharacterDna dna, MotionKind kind,
    [CharacterStyle style = CharacterStyle.featureCartoon]) {
  var side = kind == MotionKind.walk || kind == MotionKind.run;
  var base = CharacterElement.restPose.withTurn(side ? 90 : 0);
  var t = kind.seconds * (kind.loops ? 0.25 : 0.5);
  var (pose, face) = withMotions(
      base,
      CharacterFace.rest,
      [
        MotionClip(
            id: "",
            kind: kind,
            layer: kind.layer,
            start: 0,
            length: 1000,
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
      face: face,
      style: style);
}

/// _clipGroup is one motion clip's settings: when, how fast, how much, on
/// which layer, mirrored or not, and a button to take it off.
Widget _clipGroup(CanvasController controller, CharacterElement e,
    MotionClip clip, SettingsWrite write, VoidCallback commit) {
  var rate =
      controller.document.frameRate <= 0 ? 12 : controller.document.frameRate;
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
              (
                MotionKind.run,
                -1,
                "Run",
                Icons.keyboard_double_arrow_left,
                "characterRunLeft"
              ),
              (
                MotionKind.run,
                1,
                "Run",
                Icons.keyboard_double_arrow_right,
                "characterRunRight"
              ),
            ])
              CanvasTextButton(
                key: ValueKey(key),
                icon: icon,
                label: label,
                onPressed: () => _go(kind, dir),
              ),
          ]);
}

/// characterOrbitGroup orbits the character in its own box -- round it and
/// over it -- and nothing else: not its stage's camera, not the page. The
/// orbit is the character's turn and tilt, so it is keyed on the timeline
/// as a pose is, and can move.
Widget characterOrbitGroup(CanvasController controller, CharacterElement e,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  var pose = e.poseAtFrame(controller.frame);
  void orbit(double turn, double tilt, {bool live = true}) {
    write(controller.characterPosed(e, pose.withTurn(turn).withTilt(tilt)));
    if (!live) commit();
  }

  return CanvasControlGroup(
      key: const ValueKey("characterOrbit"),
      label: "Orbit",
      help: "Drag the globe to go round the character -- across to turn "
          "it, up and down to see it from below or above. Only this "
          "character moves: on a stage, the camera stays where it is. A "
          "body in 3D is seen from there whole; a drawn one has its arms "
          "and legs foreshortened. Double click the globe to face it "
          "again.",
      children: [
        CanvasOrbitPad(
          key: const ValueKey("characterOrbitPad"),
          turn: pose.turn,
          tilt: pose.tilt,
          onStart: begin,
          onChanged: (t, k) => orbit(t, k),
          onEnd: commit,
        ),
        CanvasStepper(
          key: const ValueKey("characterOrbitTurn"),
          label: "Turn",
          value: pose.turn,
          min: -180,
          max: 180,
          step: 15,
          suffix: "°",
          defaultValue: 0,
          onChanged: (v) {
            begin();
            orbit(v, pose.tilt);
          },
          onCommit: commit,
        ),
        CanvasStepper(
          key: const ValueKey("characterOrbitTilt"),
          label: "Tilt",
          value: pose.tilt,
          min: -85,
          max: 85,
          step: 5,
          suffix: "°",
          defaultValue: 0,
          onChanged: (v) {
            begin();
            orbit(pose.turn, v);
          },
          onCommit: commit,
        ),
      ]);
}

/// SculptedBodyGroup fetches the sculpted body, once, when it is wanted:
/// what it is, how big, where from, and how far along.
class SculptedBodyGroup extends StatefulWidget {
  final CharacterElement character;
  const SculptedBodyGroup({required this.character, super.key});

  @override
  State<SculptedBodyGroup> createState() => SculptedBodyGroupState();
}

class SculptedBodyGroupState extends State<SculptedBodyGroup> {
  double? _progress;
  String _said = "";

  HumanBody get _body => HumanBody.instance;

  @override
  void initState() {
    super.initState();
    _body.addListener(_changed);
    _body.load();
  }

  @override
  void dispose() {
    _body.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _download() async {
    setState(() {
      _progress = 0;
      _said = "";
    });
    try {
      await HumanAssets.install(
          progress: (p) => mounted ? setState(() => _progress = p) : null);
      await _body.installed();
      _said = "";
    } catch (e) {
      _said = "$e";
    }
    if (mounted) setState(() => _progress = null);
  }

  /// _wearProgress is how far along hair and shoes are, while they come.
  double? _wearProgress;

  Future<void> _downloadWear() async {
    setState(() {
      _wearProgress = 0;
      _said = "";
    });
    try {
      await HumanWearAssets.install(
          progress: (p) => mounted ? setState(() => _wearProgress = p) : null);
      await _body.wearInstalled();
      _said = "";
    } catch (e) {
      _said = "$e";
    }
    if (mounted) setState(() => _wearProgress = null);
  }

  @override
  Widget build(BuildContext context) {
    var person = widget.character.dna.kind.person;
    var status = _wearProgress != null
        ? "Downloading hair and shoes… ${(_wearProgress! * 100).round()}%"
        : _progress != null
            ? "Downloading the body… ${(_progress! * 100).round()}%"
            : _said.isNotEmpty
                ? _said
                : _body.ready
                    ? person
                        ? "Sculpted from MakeHuman's body, free to use for "
                            "anything. Shape every part in Appearance."
                        : "Animals and creatures are a smooth mannequin for "
                            "now; people are sculpted."
                    : _body.missing
                        ? "The detailed body is downloaded once: about "
                            "${humanDownloadBytes >> 20} MB from MakeHuman on "
                            "GitHub, free to use for anything. It connects "
                            "directly, not through this app's proxy. Until "
                            "then, a smooth mannequin stands in."
                        : "Looking for the body…";
    return CanvasControlGroup(
        label: "Sculpted body",
        help: "A real body in 3D, sculpted into this character from its "
            "type and its Appearance: age, build and every part of the "
            "face. Made from MakeHuman's open body, which is fetched the "
            "first time it is used.",
        children: [
          if (_body.missing && _progress == null)
            CanvasTextButton(
              key: const ValueKey("characterSculptedDownload"),
              icon: Icons.download_outlined,
              label: "Download the body",
              primary: true,
              onPressed: _download,
            ),
          CanvasStatus(status),
          if (_body.ready && _body.wearMissing && _wearProgress == null) ...[
            CanvasTextButton(
              key: const ValueKey("characterWearDownload"),
              icon: Icons.download_outlined,
              label: "Download hair and shoes",
              onPressed: _downloadWear,
            ),
            CanvasStatus("${wearOfKind(WearKind.hair).length} hairstyles, "
                "brows, shoes and teeth fitted to the body: about "
                "${humanWearBytes >> 20} MB from MakeHuman's collections, "
                "free to use for anything. Until then the hair is grown "
                "from the scalp."),
          ],
        ]);
  }
}

/// ModelImportGroup brings a 3D model in from a file and makes it the
/// character's body.
class ModelImportGroup extends StatefulWidget {
  final CanvasController controller;
  final CharacterElement character;
  const ModelImportGroup(
      {required this.controller, required this.character, super.key});

  @override
  State<ModelImportGroup> createState() => ModelImportGroupState();
}

class ModelImportGroupState extends State<ModelImportGroup> {
  String _said = "";

  /// _loaded is whether the model had been read when this was last drawn:
  /// when it arrives, the tiles that show it are drawn again.
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loaded = _model() != null;
    widget.controller.images.addListener(_onImages);
    _loadLibrary();
  }

  @override
  void dispose() {
    widget.controller.images.removeListener(_onImages);
    super.dispose();
  }

  Object? _model() =>
      widget.controller.images.resolveModel(widget.character.body.modelId);

  void _onImages() {
    var now = _model() != null;
    if (now == _loaded || !mounted) return;
    _loaded = now;
    widget.controller.arrived();
  }

  /// _library is the models already brought in, to pick one from.
  List<LibraryAsset> _library = const [];

  Future<void> _loadLibrary() async {
    var all = await CanvasLibrary.list(kind: AssetKind.model);
    if (mounted) setState(() => _library = all);
  }

  Future<void> _pick() async {
    var picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: modelExtensions,
      withData: false,
    );
    var file = picked?.files.singleOrNull?.path;
    if (file == null) return;
    await importFrom(file);
  }

  /// _use makes the model [id], called [name], the character's body.
  void _use(String id, String name) {
    var c = widget.controller;
    var now = c.document.elementById(widget.character.id);
    if (now is! CharacterElement) return;
    c.beginInteraction();
    c.replaceElement(now.copyWith(
        body: now.body
            .copyWith(kind: BodyKind.model, modelId: id, modelName: name)));
    c.endInteraction();
  }

  /// importFrom stores the model at [file] and makes it the character's
  /// body -- once it has been read, so a file that is not a model is
  /// turned away rather than drawn as nothing.
  Future<void> importFrom(String file) async {
    String said;
    try {
      var stored = await storeModel(file);
      _use(stored.id, stored.name);
      said = _about(stored.gltf);
      unawaited(_loadLibrary());
    } on GltfError catch (error) {
      said = "That file could not be read: $error";
    }
    if (mounted) setState(() => _said = said);
  }

  /// _about is what was found in [gltf], in a sentence.
  static String _about(Gltf gltf) {
    var bones = gltf.humanoid.length;
    var faces = gltf.expressions.length;
    var kind = gltf.vrm == null ? "glTF" : "VRM ${gltf.vrm}";
    if (bones < 8) {
      return "A $kind model, with no human skeleton found in it: it stands "
          "as it was made, and turns with the character.";
    }
    return "A $kind model with a human skeleton: posed by the character's "
        "pose, motions and pins"
        "${faces > 0 ? ", with $faces face shapes for its expressions and lip sync" : ""}.";
  }

  @override
  Widget build(BuildContext context) {
    var body = widget.character.body;
    var loaded = widget.controller.images.resolveModel(body.modelId);
    var status = _said.isNotEmpty
        ? _said
        : body.modelId.isEmpty
            ? "No model yet: a mannequin stands in until one is brought in."
            : loaded == null
                ? "${body.modelName.isEmpty ? "The model" : body.modelName} -- "
                    "being read; a mannequin stands in meanwhile."
                : "${body.modelName.isEmpty ? "The model" : body.modelName}. "
                    "${_about(loaded.gltf)}";
    return CanvasControlGroup(
        label: "Model",
        help: "A 3D character from a file: .glb, .gltf with everything in "
            "it, or .vrm -- what VRoid Studio, Ready Player Me, Mixamo "
            "(through Blender), Blender and most 3D tools export. A human "
            "skeleton in it is found by its names and posed as this "
            "character is; VRM and ARKit face shapes give it its "
            "expressions and lip sync.",
        children: [
          CanvasTextButton(
            key: const ValueKey("characterModelPick"),
            icon: Icons.view_in_ar_outlined,
            label: body.modelId.isEmpty
                ? "Bring in a model…"
                : "Bring in another model…",
            onPressed: _pick,
          ),
          if (_library.isNotEmpty)
            CanvasDropdown<String>(
              key: const ValueKey("characterModelLibrary"),
              label: "From the library",
              value:
                  _library.any((a) => a.id == body.modelId) ? body.modelId : "",
              width: 170,
              options: [
                if (!_library.any((a) => a.id == body.modelId))
                  ("", "Choose a model"),
                for (var a in _library) (a.id, a.name),
              ],
              onChanged: (id) {
                if (id.isEmpty) return;
                var a = _library.firstWhere((a) => a.id == id);
                _use(a.id, a.name);
                setState(() => _said = "");
              },
            ),
          CanvasStatus(status),
        ]);
  }
}

/// captureSwitch lets the canvas use the camera and the microphone -- off
/// until it is switched on. One switch for both, wherever either is used.
Widget captureSwitch(BuildContext context) {
  var prefs = context.watch<CanvasPreferences>();
  return CanvasToggle(
    key: const ValueKey("canvasAllowCapture"),
    label: "Allow the camera and microphone",
    value: prefs.allowCapture,
    onChanged: (v) => prefs.allowCapture = v,
  );
}

/// _ImportGroup lays motion from a file -- BVH, Mixamo's FBX, a glTF's
/// own animation -- or from a video on the character.
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
  bool _busy = false;
  bool _video = BodyCapture.known ?? false;

  /// _file and _motions are a file holding several motions, waiting for
  /// one to be picked; _motion is the one picked.
  String? _file;
  Uint8List? _bytes;
  List<String> _motions = const [];
  int _motion = 0;

  @override
  void initState() {
    super.initState();
    BodyCapture.available().then((v) {
      if (mounted && v != _video) setState(() => _video = v);
    });
  }

  Future<void> _pick() async {
    var picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: motionExtensions,
      withData: false,
    );
    var file = picked?.files.singleOrNull?.path;
    if (file == null) return;
    await importFrom(file);
  }

  Future<void> _pickVideo() async {
    var picked = await FilePicker.platform.pickFiles(
      type: FileType.video,
      withData: false,
    );
    var file = picked?.files.singleOrNull?.path;
    if (file == null) return;
    setState(() {
      _busy = true;
      _said = "Finding the person in the video, frame by frame…";
    });
    String said;
    try {
      var rate = widget.controller.document.frameRate <= 0
          ? 12
          : widget.controller.document.frameRate;
      var motion = await BodyCapture.fromVideo(file, rate.toDouble());
      said = _lay(motion, "the video");
    } on MotionError catch (error) {
      said = "$error";
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _said = said;
      });
    }
  }

  /// _record starts the camera, or -- recording -- stops it and reads the
  /// movement off what it saw.
  Future<void> _record() async {
    if (LiveCapture.recording.value == CaptureKind.camera) {
      setState(() {
        _busy = true;
        _said = "Finding you in the recording, frame by frame…";
      });
      String said;
      try {
        var file = await LiveCapture.stop();
        if (file == null) {
          said = "Nothing was recorded.";
        } else {
          var rate = widget.controller.document.frameRate <= 0
              ? 12
              : widget.controller.document.frameRate;
          var motion = await BodyCapture.fromVideo(file, rate.toDouble());
          said = _lay(motion, "the camera");
          try {
            await File(file).delete();
          } catch (_) {}
        }
      } on MotionError catch (error) {
        said = "$error";
      } catch (error) {
        said = "$error";
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _said = said;
        });
      }
      return;
    }
    try {
      await LiveCapture.start(CaptureKind.camera);
      if (mounted) {
        setState(() => _said = "Recording. Step back so all of you is "
            "seen, move, then press Stop.");
      }
    } catch (error) {
      if (mounted) setState(() => _said = "$error");
    }
  }

  /// importFrom reads the motion file at [file] and lays it on the
  /// character.
  Future<void> importFrom(String file, {int? animation}) async {
    var c = widget.controller;
    String said;
    try {
      var rate = c.document.frameRate <= 0 ? 12 : c.document.frameRate;
      var bytes = _file == file && _bytes != null
          ? _bytes!
          : await File(file).readAsBytes();
      // A file with several motions waits for one to be picked.
      if (animation == null) {
        var names = motionsIn(bytes);
        if (names.length > 1) {
          if (mounted) {
            setState(() {
              _file = file;
              _bytes = bytes;
              _motions = names;
              _motion = 0;
              _said = "The file has ${names.length} motions: pick one, "
                  "and lay it.";
            });
          }
          return;
        }
      }
      var (motion, from) = readMotionFile(bytes, file,
          frameRate: rate.toDouble(), animation: animation ?? 0);
      said = _lay(motion, from);
    } on MotionError catch (error) {
      said = "That file could not be read: $error";
    } on GltfError catch (error) {
      said = "That file could not be read: $error";
    } on FormatException {
      said = "That file could not be read.";
    } on FileSystemException {
      said = "That file could not be opened.";
    }
    if (mounted) setState(() => _said = said);
  }

  /// _lay retargets [motion] on to the character as keyframes from the
  /// playhead, and says how it went.
  String _lay(JointMotion motion, String from) {
    var c = widget.controller;
    var rate = c.document.frameRate <= 0 ? 12 : c.document.frameRate;
    var poses = motionPoses(motion,
        frameRate: rate, headsTall: widget.character.dna.headsTall);
    var now = c.document.elementById(widget.character.id);
    if (now is! CharacterElement) return "";
    c.beginInteraction();
    var laid = c.importMotion(now, poses, faceReader: _faceReader);
    c.endInteraction();
    return laid < poses.length
        ? "$laid of ${poses.length} frames laid from $from: the canvas ended "
            "first."
        : "$laid frames of motion laid from $from, from the playhead on.";
  }

  @override
  Widget build(BuildContext context) => CanvasControlGroup(
          label: "Motion capture",
          help: "Lays motion on the character as keyframes from the frame "
              "being looked at: a BVH file (the CMU library, most capture "
              "tools), an FBX from Mixamo, or the animation in a .glb, "
              ".gltf or .vrm. Any skeleton with the usual joints works; "
              "the character's own proportions are kept. On macOS 14 and "
              "later, a video of someone moving can be read for their "
              "motion too -- on this computer, with nothing uploaded.",
          children: [
            CanvasTextButton(
              key: const ValueKey("characterImportBvh"),
              icon: Icons.file_open_outlined,
              label: "Import motion…",
              onPressed: _busy ? null : _pick,
            ),
            if (_video)
              CanvasTextButton(
                key: const ValueKey("characterImportVideo"),
                icon: Icons.accessibility_new_outlined,
                label: "From a video…",
                onPressed: _busy ? null : _pickVideo,
              ),
            if (_video &&
                LiveCapture.available &&
                context.watch<CanvasPreferences>().allowCapture)
              ValueListenableBuilder<CaptureKind?>(
                valueListenable: LiveCapture.recording,
                builder: (context, now, _) => CanvasTextButton(
                  key: const ValueKey("characterRecordCamera"),
                  icon: now == CaptureKind.camera
                      ? Icons.stop_circle_outlined
                      : Icons.videocam_outlined,
                  label: now == CaptureKind.camera
                      ? "Stop, and use it"
                      : "Record with the camera",
                  primary: now == CaptureKind.camera,
                  onPressed: _busy || (now != null && now != CaptureKind.camera)
                      ? null
                      : _record,
                ),
              ),
            if (_motions.length > 1 && _file != null) ...[
              CanvasDropdown<int>(
                key: const ValueKey("characterImportWhich"),
                label: "Motion",
                value: _motion,
                options: [
                  for (var (i, n) in _motions.indexed)
                    (i, n.isEmpty ? "Motion ${i + 1}" : n),
                ],
                onChanged: (i) => setState(() => _motion = i),
              ),
              CanvasTextButton(
                key: const ValueKey("characterImportLay"),
                icon: Icons.download_done_outlined,
                label: "Lay this motion",
                onPressed: () => importFrom(_file!, animation: _motion),
              ),
            ],
            CanvasToggle(
              key: const ValueKey("characterImportFace"),
              label: "Start facing the reader",
              value: _faceReader,
              onChanged: (v) => setState(() => _faceReader = v),
            ),
            if (LiveCapture.available) captureSwitch(context),
            if (_said.isNotEmpty) ...[
              const CanvasLineBreak(),
              CanvasStatus(_said, key: const ValueKey("characterImportSaid")),
            ],
          ]);
}

/// _garmentTile draws [dna] wearing what it wears, cropped to where a
/// garment of [slot] goes: the head for a hat, the feet for shoes.
void _garmentTile(
    ui.Canvas canvas, Size size, CharacterDna dna, GarmentSlot slot,
    [CharacterStyle style = CharacterStyle.featureCartoon]) {
  switch (slot) {
    case GarmentSlot.head || GarmentSlot.face:
      _headTile(canvas, size, dna, style);
    case GarmentSlot.neck || GarmentSlot.top || GarmentSlot.outer:
      _bodyTile(canvas, size, dna, style);
    case GarmentSlot.bottom:
      _legsTile(canvas, size, dna, style);
    case GarmentSlot.feet:
      _cropTile(canvas, size, dna, 0.2, 0.25, style);
    case GarmentSlot.base || GarmentSlot.full:
      _figureTile(canvas, size, dna, CharacterElement.restPose, style);
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
  CharacterStyle get style => e.style;

  void _now(CharacterElement next) {
    widget.controller.beginInteraction();
    widget.write(next);
    widget.commit();
  }

  void _wear(List<Garment> wardrobe) =>
      _now(e.copyWith(dna: dna.copyWith(wardrobe: wardrobe)));

  /// _change writes the picked garment as [g]: [live] while a number is
  /// being dragged, committed when it is let go.
  /// _pickedGarment is the garment being edited, as it is now.
  Garment? get _pickedGarment => _picked >= 0 && _picked < dna.wardrobe.length
      ? dna.wardrobe[_picked]
      : null;

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
    var drawn = "${dna.toJson()}|${style.name}";
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
              onChanged: (v) =>
                  _now(e.copyWith(dna: dna.copyWith(baseLayer: v))),
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
                paint: (canvas, size) => _figureTile(
                    canvas,
                    size,
                    dna.copyWith(wardrobe: c.wardrobe),
                    CharacterElement.restPose,
                    style)),
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
      if (g.pattern == GarmentPattern.print)
        CanvasControlGroup(
            key: const ValueKey("characterGarmentPrint"),
            label: "Picture print",
            help: "A picture on the front of it -- a band's logo, a slogan, "
                "a face -- as big as a share of the front's width. A "
                "picture with a clear background shows the cloth round "
                "it.",
            children: [
              CanvasTextButton(
                key: const ValueKey("characterGarmentPrintPick"),
                icon: Icons.image_outlined,
                label: g.printId.isEmpty
                    ? "Choose a picture…"
                    : "Another picture…",
                onPressed: () async {
                  var id = await pickCanvasImage(context, vectors: false);
                  if (id == null || !mounted) return;
                  _change(_pickedGarment!.copyWith(printId: id));
                },
              ),
              CanvasStepper(
                key: const ValueKey("characterGarmentPrintSize"),
                label: "Size",
                value: g.printSize * 100,
                min: 10,
                max: 150,
                step: 10,
                suffix: "%",
                defaultValue: 60,
                onChanged: (v) =>
                    _change(g.copyWith(printSize: v / 100), live: true),
                onCommit: widget.commit,
              ),
            ]),
      CanvasControlGroup(
          key: const ValueKey("characterGarmentShape"),
          label: "Shape",
          help: "A shape of its own, laid on over it and going with the body "
              "-- a collar, a peplum, a flared hem. Start from one, then "
              "drag its points; click an edge to put a point in it, double "
              "click a point to take it out.",
          children: [
            for (var (name, points) in outlineShapes)
              CanvasTextButton(
                key: ValueKey("characterGarmentShape-$name"),
                label: name,
                grow: false,
                onPressed: () => _change(g.copyWith(outline: points)),
              ),
            if (g.outline.isNotEmpty)
              CanvasTextButton(
                key: const ValueKey("characterGarmentShapeClear"),
                icon: Icons.close,
                label: "No shape",
                grow: false,
                onPressed: () => _change(g.copyWith(outline: const [])),
              ),
            const CanvasLineBreak(),
            GarmentShapeEditor(
              key: const ValueKey("characterGarmentShapeEditor"),
              dna: dna,
              style: style,
              outline: g.outline,
              images: widget.controller.images,
              onStart: widget.controller.beginInteraction,
              onChanged: (pts) =>
                  _change(_pickedGarment!.copyWith(outline: pts), live: true),
              onEnd: widget.commit,
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
            CanvasTile(i, p.$1, drawnFrom: "${dna.toJson()}|$_picked",
                paint: (canvas, size) {
              var worn = [...dna.wardrobe];
              worn[_picked] = g.copyWith(condition: p.$2);
              _garmentTile(canvas, size, dna.copyWith(wardrobe: worn),
                  g.kind.slot, style);
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
            for (var (name, value, set)
                in <(String, double, GarmentCondition Function(double))>[
              ("Faded", g.condition.fade, (v) => g.condition.copyWith(fade: v)),
              ("Dirt", g.condition.dirt, (v) => g.condition.copyWith(dirt: v)),
              ("Rips", g.condition.rips, (v) => g.condition.copyWith(rips: v)),
              (
                "Frayed",
                g.condition.frays,
                (v) => g.condition.copyWith(frays: v)
              ),
              (
                "Patched",
                g.condition.patches,
                (v) => g.condition.copyWith(patches: v)
              ),
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

/// _stageSection is where the character stands: on a 3D stage -- which
/// one, the spot on its floor, how tall, which way round -- or on the page,
/// with its shadow and how much it shrinks going up the page.
Widget _stageSection(
    CanvasController controller,
    CharacterElement e,
    SettingsWrite write,
    VoidCallback commit,
    void Function(CharacterElement) now) {
  var stages = controller.document.elements.whereType<StageElement>().toList();
  var on = e.onStage;
  void place(OnStage next, {bool live = false}) {
    controller.beginInteraction();
    write(e.copyWith(onStage: next));
    if (!live) commit();
  }

  return section(e, "stage",
      icon: Icons.view_in_ar_outlined,
      title: "Where it stands",
      summary: on == null
          ? "On the page"
          : "On ${stages.where((s) => s.id == on.stage).firstOrNull?.name ?? "a stage"}",
      children: [
        CanvasControlGroup(
            label: "Stands on",
            help: "On a 3D stage the character stands at a spot on its "
                "floor, and the stage's camera decides where on the page "
                "that is, how big it looks and which way round. Drag it to "
                "move it across the floor. Add a 3D stage from Add to have "
                "one to stand on.",
            children: [
              CanvasDropdown<String>(
                  key: const ValueKey("characterStage"),
                  label: "Stage",
                  value: on?.stage ?? "",
                  width: 170,
                  options: [
                    ("", "The page"),
                    for (var s in stages) (s.id, s.name),
                  ],
                  onChanged: (id) => now(id.isEmpty
                      ? e.copyWith(offStage: true)
                      : e.copyWith(
                          onStage: OnStage(id,
                              height: e.dna.fourLegs ? 0.9 : 1.7)))),
            ]),
        if (on != null)
          CanvasControlGroup(
              label: "On the floor",
              help: "Where it stands, in metres across the floor and towards "
                  "the camera's start; how tall it is; and which way round "
                  "it faces, before the camera is taken into account.",
              children: [
                for (var (key, label, value, min, max, step, suffix, set) in <(
                  String,
                  String,
                  double,
                  double,
                  double,
                  double,
                  String,
                  OnStage Function(double)
                )>[
                  (
                    "characterStageX",
                    "Across",
                    on.x,
                    -50,
                    50,
                    0.5,
                    " m",
                    (v) => on.copyWith(x: v)
                  ),
                  (
                    "characterStageZ",
                    "Forward",
                    on.z,
                    -50,
                    50,
                    0.5,
                    " m",
                    (v) => on.copyWith(z: v)
                  ),
                  (
                    "characterStageHeight",
                    "Height",
                    on.height,
                    0.1,
                    30,
                    0.1,
                    " m",
                    (v) => on.copyWith(height: v)
                  ),
                  (
                    "characterStageFacing",
                    "Facing",
                    on.facing,
                    -180,
                    180,
                    15,
                    "°",
                    (v) => on.copyWith(facing: v)
                  ),
                ])
                  CanvasStepper(
                    key: ValueKey(key),
                    label: label,
                    value: value,
                    min: min,
                    max: max,
                    step: step,
                    decimals: step < 1 ? 1 : 0,
                    suffix: suffix,
                    onChanged: (v) => place(set(v), live: true),
                    onCommit: commit,
                  ),
              ]),
        CanvasControlGroup(
            label: "Ground",
            help: "The shadow under the character. On the page, Depth makes "
                "it smaller as it moves up the page and bigger as it comes "
                "down, as though walking into the picture and out of it.",
            children: [
              CanvasDropdown<CharacterShadow>(
                key: const ValueKey("characterShadow"),
                label: "Shadow",
                value: e.shadow,
                options: [for (var s in CharacterShadow.values) (s, s.label)],
                onChanged: (s) => now(e.copyWith(shadow: s)),
              ),
              if (on == null)
                CanvasStepper(
                  key: const ValueKey("characterDepth"),
                  label: "Depth",
                  value: e.depth * 100,
                  min: 0,
                  max: 200,
                  step: 10,
                  suffix: "%",
                  defaultValue: 0,
                  onChanged: (v) {
                    controller.beginInteraction();
                    write(e.copyWith(depth: v / 100));
                  },
                  onCommit: commit,
                ),
            ]),
      ]);
}
