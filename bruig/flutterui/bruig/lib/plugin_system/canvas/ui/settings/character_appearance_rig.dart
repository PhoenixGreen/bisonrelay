import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/character_face_rig_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/character_rig_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:flutter/material.dart';

// character_appearance_rig.dart is the Appearance editor's side of what a
// sketch is shaped with on the canvas: the face rig of the panel it is seen
// from -- each feature's place, size and turn, as numbers -- under the
// eyes, brows, nose and mouth; and under the body the puppet, the limbs'
// points, and the point picked. The sliders and the handles on the canvas
// are two ways to the same settings. See character_face_rig.dart and
// character_rig_points.dart.

/// appearanceFocus is the part of the Appearance editor what is picked on
/// the canvas belongs to -- a feature of the face, a point of a limb -- or
/// null with nothing picked.
AppearanceGroup? appearanceFocus(CanvasController controller) {
  if (controller.facePick case var p?) {
    return switch (p) {
      FacePoint.eyeL || FacePoint.eyeR => AppearanceGroup.eyes,
      FacePoint.browL || FacePoint.browR => AppearanceGroup.brows,
      FacePoint.nose => AppearanceGroup.nose,
      _ => AppearanceGroup.mouth,
    };
  }
  if (controller.rigPick != null) return AppearanceGroup.body;
  return null;
}

/// _features is the face rig's features each part of the face shapes.
List<FacePoint> _features(AppearanceGroup group) => switch (group) {
      AppearanceGroup.eyes => const [FacePoint.eyeL, FacePoint.eyeR],
      AppearanceGroup.brows => const [FacePoint.browL, FacePoint.browR],
      AppearanceGroup.nose => const [FacePoint.nose],
      AppearanceGroup.mouth => const [
          FacePoint.mouth,
          FacePoint.cornerL,
          FacePoint.cornerR
        ],
      _ => const [],
    };

/// appearanceRigControls is what [group] of [e]'s Appearance has on the
/// canvas, for a sketch: nothing for a body in 3D, or a part with none.
List<Widget> appearanceRigControls(
    CanvasController controller,
    CharacterElement e,
    AppearanceGroup group,
    SettingsWrite write,
    VoidCallback commit) {
  if (e.body.inThreeD) return const [];
  void live(CharacterElement next) {
    controller.beginInteraction();
    write(next);
  }

  void now(CharacterElement next) {
    live(next);
    commit();
  }

  if (group == AppearanceGroup.body) {
    return _bodyControls(controller, e, live, now, commit);
  }
  var features = _features(group);
  if (features.isEmpty) return const [];

  var pose = e.poseAtFrame(controller.frame).inPanel;
  var turn = pose.panelTurn, tilt = pose.panelTilt;
  var (rig, mirrored) = e.faceRigFor(turn, tilt);
  void set(FacePoint p, FaceAdjust a) => live(e.withFaceRig(
      turn, tilt, withFacePoint(rig, p, a, mirror: controller.mirrorEdits)));

  return [
    CanvasControlGroup(
        key: ValueKey("appearanceFaceCanvas-${group.name}"),
        label: "On the canvas",
        help: "Set the ${group.label.toLowerCase()} on the canvas, by its "
            "handles, as it is seen from this panel -- "
            "${panelLabel(turn, tilt).toLowerCase()}. The sliders below are "
            "the same settings as numbers.",
        children: [
          CanvasToggle(
            key: const ValueKey("appearanceFaceShow"),
            label: "Set the face on the canvas",
            value: controller.editFace,
            onChanged: (v) => controller.editFace = v,
          ),
          CanvasToggle(
            key: const ValueKey("appearanceFaceMirror"),
            label: "Mirror left and right",
            value: controller.mirrorEdits,
            onChanged: (v) => controller.mirrorEdits = v,
          ),
          CanvasTextButton(
            key: const ValueKey("appearanceZoomHead"),
            label: "Zoom to the head",
            icon: Icons.zoom_in,
            onPressed: () =>
                controller.zoomToCharacter(e.id, CharacterZoom.head),
          ),
        ]),
    for (var p in features)
      CanvasControlGroup(
          key: ValueKey("appearanceFace-${p.name}"),
          label: "${p.label} on this panel${mirrored ? " (mirrored)" : ""}",
          help: "Where the ${p.label.toLowerCase()} is, seen from this panel: "
              "moved across and down the face${p.movesOnly ? "" : ", sized and turned"}. "
              "On top of every expression. The panel seen from the other "
              "side mirrors it until it is set itself.",
          children: [
            CanvasSlider(
              key: ValueKey("appearanceFace-${p.name}-across"),
              label: "Across",
              value: rig[p].dx * 100,
              min: -30,
              max: 30,
              decimals: 0,
              width: 150,
              onChanged: (v) => set(p, rig[p].copyWith(dx: v / 100)),
              onCommit: commit,
            ),
            CanvasSlider(
              key: ValueKey("appearanceFace-${p.name}-down"),
              label: "Down",
              value: rig[p].dy * 100,
              min: -30,
              max: 30,
              decimals: 0,
              width: 150,
              onChanged: (v) => set(p, rig[p].copyWith(dy: v / 100)),
              onCommit: commit,
            ),
            if (!p.movesOnly) ...[
              CanvasSlider(
                key: ValueKey("appearanceFace-${p.name}-size"),
                label: "Size",
                value: rig[p].scale * 100,
                min: 0,
                max: 300,
                decimals: 0,
                width: 150,
                onChanged: (v) => set(p, rig[p].copyWith(scale: v / 100)),
                onCommit: commit,
              ),
              CanvasSlider(
                key: ValueKey("appearanceFace-${p.name}-turn"),
                label: "Turn",
                value: rig[p].turn,
                min: -180,
                max: 180,
                decimals: 0,
                width: 150,
                onChanged: (v) => set(p, rig[p].copyWith(turn: v)),
                onCommit: commit,
              ),
            ],
            if (!rig[p].isRest && !mirrored)
              CanvasTextButton(
                key: ValueKey("appearanceFace-${p.name}-back"),
                label: "Put it back",
                icon: Icons.restart_alt,
                grow: false,
                onPressed: () => now(e.withFaceRig(
                    turn, tilt, rig.withPoint(p, FaceAdjust.rest))),
              ),
          ]),
  ];
}

/// _limbLabel is a limb's name in the Appearance editor.
String _limbLabel(CharacterLimb limb) => switch (limb) {
      CharacterLimb.armL => "Left arm",
      CharacterLimb.armR => "Right arm",
      CharacterLimb.legL => "Left leg",
      CharacterLimb.legR => "Right leg",
    };

/// _pointLabel is where on its limb a point is.
String _pointLabel(CharacterLimb limb, RigPoint p) {
  if (p.sameSpot(RigPoint.root)) {
    return limb.isArm ? "shoulder" : "hip";
  }
  if (p.sameSpot(RigPoint.middle)) return limb.isArm ? "elbow" : "knee";
  if (p.sameSpot(RigPoint.end)) return limb.isArm ? "wrist" : "ankle";
  var bone = p.bone == 0
      ? (limb.isArm ? "upper arm" : "thigh")
      : (limb.isArm ? "forearm" : "shin");
  return "$bone, ${(p.f * 100).round()}% down";
}

List<Widget> _bodyControls(
    CanvasController controller,
    CharacterElement e,
    void Function(CharacterElement) live,
    void Function(CharacterElement) now,
    VoidCallback commit) {
  var pick = controller.rigPick;
  // The point picked, as the character has it now.
  RigPoint? point;
  if (pick != null) {
    for (var p in e.dna.rigPoints.of(pick.$1.name)) {
      if (p.sameSpot(pick.$2)) point = p;
    }
  }
  void set(RigPoint next) =>
      live(withRigPoint(e, pick!.$1, next, mirror: controller.mirrorEdits));
  var reshaped = [
    for (var l in CharacterLimb.values)
      if (e.dna.rigPoints.edited(l.name)) _limbLabel(l).toLowerCase(),
  ];

  return [
    CanvasControlGroup(
        key: const ValueKey("appearanceBodyCanvas"),
        label: "On the canvas",
        help: "Shape the body on the canvas. The puppet's diamonds are the "
            "sliders below -- head size, shoulders, hips, how long the arms "
            "and legs are -- taken hold of on the figure. The limbs' points "
            "bend, thicken and turn an arm or a leg where they are. "
            "${reshaped.isEmpty ? "No limb is reshaped." : "Reshaped: ${reshaped.join(", ")}."}",
        children: [
          CanvasToggle(
            key: const ValueKey("appearancePuppetShow"),
            label: "Show the puppet",
            value: controller.showPuppet,
            onChanged: (v) => controller.showPuppet = v,
          ),
          CanvasToggle(
            key: const ValueKey("appearanceRigShow"),
            label: "Reshape the limbs",
            value: controller.editRig,
            onChanged: (v) => controller.editRig = v,
          ),
          CanvasToggle(
            key: const ValueKey("appearanceRigMirror"),
            label: "Mirror left and right",
            value: controller.mirrorEdits,
            onChanged: (v) => controller.mirrorEdits = v,
          ),
          if (!e.dna.rigPoints.isEmpty)
            CanvasTextButton(
              key: const ValueKey("appearanceRigReset"),
              label: "Put every limb back",
              icon: Icons.restart_alt,
              onPressed: () => now(
                  e.copyWith(dna: e.dna.copyWith(rigPoints: RigPoints.none))),
            ),
        ]),
    if (pick != null && point != null)
      CanvasControlGroup(
          key: const ValueKey("appearanceRigPoint"),
          label: "${_limbLabel(pick.$1)}: ${_pointLabel(pick.$1, point)}",
          help: "The point picked on the canvas: how thick the limb is "
              "there, how its cross-section is turned, and how far it is "
              "moved off the bone -- across it, which bends the limb, and "
              "along it. In head units, a hundredth at a time.",
          children: [
            CanvasSlider(
              key: const ValueKey("appearanceRigPoint-scale"),
              label: "Thickness",
              value: point.scale * 100,
              min: 0,
              max: 400,
              decimals: 0,
              width: 150,
              onChanged: (v) => set(point!.copyWith(scale: v / 100)),
              onCommit: commit,
            ),
            CanvasSlider(
              key: const ValueKey("appearanceRigPoint-turn"),
              label: "Turn",
              value: point.turn.clamp(-180.0, 180.0),
              min: -180,
              max: 180,
              decimals: 0,
              width: 150,
              onChanged: (v) => set(point!.copyWith(turn: v)),
              onCommit: commit,
            ),
            CanvasSlider(
              key: const ValueKey("appearanceRigPoint-across"),
              label: "Bend",
              value: (point.across * 100).clamp(-100.0, 100.0),
              min: -100,
              max: 100,
              decimals: 0,
              width: 150,
              onChanged: (v) => set(point!.copyWith(across: v / 100)),
              onCommit: commit,
            ),
            CanvasSlider(
              key: const ValueKey("appearanceRigPoint-along"),
              label: "Along",
              value: (point.along * 100).clamp(-100.0, 100.0),
              min: -100,
              max: 100,
              decimals: 0,
              width: 150,
              onChanged: (v) => set(point!.copyWith(along: v / 100)),
              onCommit: commit,
            ),
            CanvasTextButton(
              key: const ValueKey("appearanceRigPoint-delete"),
              label: point.isJoint ? "Put the joint back" : "Delete the point",
              icon: Icons.delete_outline,
              grow: false,
              onPressed: () {
                now(withoutRigPoint(e, pick.$1, point!,
                    mirror: controller.mirrorEdits));
                controller.pickRigPoint(null);
              },
            ),
          ]),
  ];
}
