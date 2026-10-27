import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:flutter/material.dart';

// character_hands_settings.dart is a sketch's hands and feet, in their
// layers' settings: a hand's shape picked from the hand chart, each finger
// curled after, the wrist bent and the palm turned; a foot's stance, how
// far it points and its toes bend, and how far it turns out. Both are the
// pose -- keyed on the frame looked at once the character is animated --
// and both hands, or both feet, together while edits are mirrored. See
// character_hands.dart.

/// _Posing is what the hand and foot editors share: the pose on the frame
/// looked at, and a bone set on one side, or on both.
class _Posing {
  final CanvasController controller;
  final CharacterElement e;
  final SettingsWrite write;
  final bool left;
  _Posing(this.controller, this.e, this.write, this.left);

  CharacterPose get pose => e.poseAtFrame(controller.frame);
  bool get both => controller.mirrorEdits;

  void put(CharacterPose pose) {
    controller.beginInteraction();
    write(controller.characterPosed(e, pose));
  }

  /// angle and swing set [bone] to [v] -- and its partner too, turned the
  /// other way where a turn on the page is mirrored.
  void angle(CharacterBone bone, double v) {
    var p = pose.withAngle(bone, v);
    if (both) p = p.withAngle(bone.partner, bone.mirrors ? -v : v);
    put(p);
  }

  void swing(CharacterBone bone, double v) {
    var p = pose.withSwing(bone, v);
    if (both) p = p.withSwing(bone.partner, v);
    put(p);
  }
}

Widget _slider(String key, String label, double value, double min, double max,
        ValueChanged<double> set, VoidCallback commit) =>
    CanvasSlider(
      key: ValueKey(key),
      label: label,
      value: value.clamp(min, max),
      min: min,
      max: max,
      decimals: 0,
      width: 150,
      onChanged: set,
      onCommit: commit,
    );

Widget _both(CanvasController controller, String label) => CanvasToggle(
      key: const ValueKey("characterExtremityBoth"),
      label: label,
      value: controller.mirrorEdits,
      onChanged: (v) => controller.mirrorEdits = v,
    );

/// handEditor is the hand on the page's left, or right, of [e].
Widget handEditor(CanvasController controller, CharacterElement e,
    SettingsWrite write, VoidCallback commit, bool left) {
  var at = _Posing(controller, e, write, left);
  var pose = at.pose;
  var name = handShapeName(pose, left);
  var side = left ? "L" : "R";
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    CanvasControlGroup(
        key: const ValueKey("characterHandShape"),
        label: "Hand shape",
        help: "Pick a shape from the hand chart, then curl each finger and "
            "spread them to make it the character's own. A hand is part of "
            "the pose: once the character is animated, it is keyed on the "
            "frame you are on.",
        children: [
          CanvasDropdown<String>(
            key: const ValueKey("characterHandShapePick"),
            label: "Shape",
            stepped: true,
            value: name ?? "",
            options: [
              for (var s in handShapes) (s.name, s.name),
              if (name == null) ("", "Own shape"),
            ],
            onChanged: (n) {
              if (n.isEmpty) return;
              var s = handShapes.firstWhere((s) => s.name == n);
              var p = s.on(pose, left);
              if (at.both) p = s.on(p, !left);
              at.put(p);
              commit();
            },
          ),
          for (var f in Finger.values)
            _slider("characterFinger-${f.name}$side", f.label, pose[f.bone(left)],
                0, 110, (v) => at.angle(f.bone(left), v), commit),
          _slider("characterFingerSpread$side", "Spread",
              pose[spreadBone(left)], -5, 25,
              (v) => at.angle(spreadBone(left), v), commit),
          _both(controller, "Both hands"),
        ]),
    CanvasControlGroup(
        key: const ValueKey("characterWrist"),
        label: "Wrist",
        help: "The hand bent at the wrist -- across, and forward or back -- "
            "and the palm turned: the back of the hand towards you below "
            "nought, the palm above it.",
        children: [
          _slider("characterWristBend$side", "Bend", pose[wristBone(left)],
              -80, 80, (v) => at.angle(wristBone(left), v), commit),
          _slider("characterWristForward$side", "Forward",
              pose.swing(wristBone(left)), -80, 80,
              (v) => at.swing(wristBone(left), v), commit),
          _slider("characterPalmTurn$side", "Palm turn", pose[palmBone(left)],
              -180, 180, (v) => at.angle(palmBone(left), v), commit),
        ]),
  ]);
}

/// footEditor is the foot on the page's left, or right, of [e].
Widget footEditor(CanvasController controller, CharacterElement e,
    SettingsWrite write, VoidCallback commit, bool left) {
  var at = _Posing(controller, e, write, left);
  var pose = at.pose;
  var name = footStanceName(pose, left);
  var side = left ? "L" : "R";
  return CanvasControlGroup(
      key: const ValueKey("characterFootStance"),
      label: "Foot",
      help: "How the foot stands: pointed, its toes bent at the ball, and "
          "turned out. It stays on the ground -- pointing it lifts the body "
          "on to its toes -- unless the character is off the ground already. "
          "Drag the dot on the toes on the canvas: up and down to point it, "
          "across to turn it in or out.",
      children: [
        CanvasDropdown<String>(
          key: const ValueKey("characterFootStancePick"),
          label: "Stance",
          stepped: true,
          value: name ?? "",
          options: [
            for (var s in footStances) (s.name, s.name),
            if (name == null) ("", "Own stance"),
          ],
          onChanged: (n) {
            if (n.isEmpty) return;
            var s = footStances.firstWhere((s) => s.name == n);
            var p = s.on(pose, left);
            if (at.both) p = s.on(p, !left);
            at.put(p);
            commit();
          },
        ),
        _slider("characterFootPoint$side", "Point", pose.swing(ankleBone(left)),
            -40, 85, (v) => at.swing(ankleBone(left), v), commit),
        _slider("characterToes$side", "Toes", pose.swing(toesBone(left)), -30,
            60, (v) => at.swing(toesBone(left), v), commit),
        _slider("characterFootTurn$side", "Turn out", pose[ankleBone(left)],
            -60, 60, (v) => at.angle(ankleBone(left), v), commit),
        _both(controller, "Both feet"),
      ]);
}
