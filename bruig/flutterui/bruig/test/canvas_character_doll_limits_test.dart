import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_gltf.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_limits.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/render/model/model_figure.dart';
import 'package:bruig/plugin_system/canvas/ui/character_doll_pose.dart';
import 'package:bruig/plugin_system/canvas/ui/character_puppet.dart';
import 'package:flutter_test/flutter_test.dart';

import 'canvas_model_fixture.dart';

// canvas_character_doll_limits_test.dart is a body kept to what a body can
// do: each joint within how far it goes, and nothing of an arm inside the
// trunk or the thighs. See character_limits.dart and LoadedModel._clear.

void main() {
  test("a knee bends back, an elbow forward, and no further", () {
    var knee = limitOf(CharacterBone.shinL);
    expect(knee.swingMax, lessThanOrEqualTo(5), reason: "a knee does not bend forward");
    expect(limitOf(CharacterBone.foreArmR).swingMin, greaterThanOrEqualTo(-5));
    // The right side's turn in the picture mirrors the left's.
    expect(limitOf(CharacterBone.upperArmR).angleMax, -limitOf(CharacterBone.upperArmL).angleMin);
    var bent = const CharacterPose({}, {CharacterBone.shinL: 60, CharacterBone.thighR: 200}).limited();
    expect(bent.swing(CharacterBone.shinL), knee.swingMax);
    expect(bent.swing(CharacterBone.thighR), limitOf(CharacterBone.thighR).swingMax);
  });

  test("every pose offered is one a body can make", () {
    for (var p in [...posePresets, ...actionPoses]) {
      var held = p.pose.limited();
      for (var b in CharacterBone.values) {
        expect(held[b], p.pose[b], reason: "${p.name}: ${b.name}");
        expect(held.swing(b), p.pose.swing(b), reason: "${p.name}: ${b.name} swing");
      }
    }
  });

  test("the doll's knee swung forward stays where a knee goes", () {
    var e = CharacterElement(const ElementBase(id: "c", x: 0, y: 0, width: 200, height: 420),
        dna: CharacterType.empty.dna);
    var placed = CharacterPlacement.of(e, 0);
    var swung = placed.swungBy(DollJoint.kneeL, e.pose, 90);
    expect(swung.swing(CharacterBone.shinL), lessThanOrEqualTo(limitOf(CharacterBone.shinL).swingMax));
  });

  group("a model's arms kept out of its body", () {
    late LoadedModel model;
    setUpAll(() async => model = await loadModel(humanoidGlb()));

    test("an arm sent across the body comes to rest outside it", () {
      // Both arms bent in, across the middle of the body.
      var pose = const CharacterPose({
        CharacterBone.upperArmL: -35,
        CharacterBone.foreArmL: -110,
        CharacterBone.upperArmR: 35,
        CharacterBone.foreArmR: 110,
      });
      var rig = CharacterRig.of(CharacterType.man.dna, pose, const Rect.fromLTWH(0, 0, 200, 420));
      for (var bone in [HumanBone.leftHand, HumanBone.rightHand, HumanBone.leftLowerArm, HumanBone.rightLowerArm]) {
        var p = model.boneAt(rig, CharacterFace.rest, bone)!;
        // The trunk is a box 0.05 either side of the middle, from the hips
        // up to the neck.
        var inTrunk = p[1] > 0.95 && p[1] < 1.6 && p[0].abs() < 0.05 && p[2].abs() < 0.05;
        expect(inTrunk, isFalse, reason: "${bone.name} at $p");
      }
    });

    test("the lines a figure is drawn by, on the model as it is posed", () {
      var rig = CharacterRig.of(CharacterType.man.dna, posePresets[1].pose,
          const Rect.fromLTWH(0, 0, 200, 420));
      var lines = model.guidePieces(rig, CharacterFace.rest, const Rect.fromLTWH(0, 0, 200, 420),
          centre: const Color(0xFFE8742A), ring: const Color(0xFF8C8F98));
      expect(lines, hasLength(2), reason: "the middle, and the rings");
      expect(lines.first.color, const Color(0xFFE8742A));
      expect(lines.every((p) => p.indices.isNotEmpty), isTrue);
    });
  });
}
