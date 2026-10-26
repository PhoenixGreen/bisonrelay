import 'dart:convert';
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/elements/character_bvh.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_fbx.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_gltf.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_motion_files.dart';
import 'package:bruig/plugin_system/canvas/ui/body_capture.dart';
import 'package:flutter_test/flutter_test.dart';

import 'canvas_model_fixture.dart';

// canvas_motion_import_test.dart is motion brought in from elsewhere: a
// Mixamo FBX, the animation in a glTF, a video read by Vision -- each turned
// into a skeleton moving and laid on a character as BVH is.

/// _armSwing is how far the arm on the page's right -- the skeleton's own
/// left -- is from hanging straight down, on the first and last poses.
(double, double) _armSwing(List<CharacterPose> poses) =>
    (poses.first[CharacterBone.upperArmR], poses.last[CharacterBone.upperArmR]);

void main() {
  group("Mixamo's FBX", () {
    test("its skeleton and its curves are read", () {
      var m = parseFbxMotion(mixamoFbx(), frameRate: 10);
      expect(m.names, contains("mixamorig:LeftArm"));
      expect(m.frameCount, 11, reason: "a second at ten frames a second");
      var hand = m.names.indexOf("mixamorig:LeftHand");
      var shoulder = m.names.indexOf("mixamorig:LeftArm");
      var first = m.positionsAt(0), last = m.positionsAt(10);
      // Out to the side, in centimetres, then hanging below the shoulder.
      expect(first[hand][0] - first[shoulder][0], closeTo(53, 1e-6));
      expect(last[hand][1] - last[shoulder][1], closeTo(-53, 1e-6));
      expect(last[hand][0] - last[shoulder][0], closeTo(0, 1e-6));
    });

    test("laid on a character, the arm comes down", () {
      var poses = motionPoses(parseFbxMotion(mixamoFbx(), frameRate: 12),
          frameRate: 12, headsTall: 5.5);
      var (first, last) = _armSwing(poses);
      expect(first.abs(), closeTo(90, 2), reason: "out to the side");
      expect(last.abs(), lessThan(3), reason: "hanging down");
    });

    test("what is not binary FBX is turned away", () {
      expect(() => parseFbxMotion(Uint8List.fromList(utf8.encode("nothing"))),
          throwsA(isA<MotionError>()));
      var text = Uint8List.fromList(
          utf8.encode("; FBX 7.4.0 project file\nFBXHeaderExtension: {\n}"));
      expect(
          () => readMotionFile(text, "a.fbx"),
          throwsA(isA<MotionError>()
              .having((e) => e.message, "message", contains("binary FBX"))));
    });
  });

  group("a glTF's own animation", () {
    test("is read, and laid on a character by its human bones", () {
      var g = parseGltf(humanoidGlb(animated: true));
      expect(g.animations.single.name, "Arm down");
      expect(g.animations.single.seconds, 1);
      var poses = motionPoses(gltfMotion(g, frameRate: 12),
          frameRate: 12, headsTall: 5.5);
      var (first, last) = _armSwing(poses);
      expect(first.abs(), closeTo(90, 2));
      expect(last.abs(), lessThan(3));
    });

    test("whatever the bones are called, when the file says which is which",
        () {
      var poses = motionPoses(
          gltfMotion(parseGltf(humanoidGlb(animated: true, vrm: true)),
              frameRate: 12),
          frameRate: 12,
          headsTall: 5.5);
      expect(_armSwing(poses).$2.abs(), lessThan(3));
    });

    test("a file with no motion says so", () {
      expect(() => gltfMotion(parseGltf(humanoidGlb())),
          throwsA(isA<MotionError>()));
    });
  });

  group("any motion file", () {
    test("a glTF names its motions; other files have one", () {
      expect(motionsIn(humanoidGlb(animated: true)), ["Arm down"]);
      expect(motionsIn(humanoidGlb()), isEmpty);
      expect(motionsIn(mixamoFbx()), isEmpty);
      // Asked for one past the last, the last.
      expect(readMotionFile(humanoidGlb(animated: true), "x", animation: 5).$2,
          "\"Arm down\"");
    });

    test("is told apart by what is in it", () {
      expect(readMotionFile(mixamoFbx(), "x.dat").$2, "the FBX");
      expect(readMotionFile(humanoidGlb(animated: true), "x.dat").$2,
          "\"Arm down\"");
      var bvh = Uint8List.fromList(utf8.encode("""HIERARCHY
ROOT Hips
{
  OFFSET 0 0 0
  CHANNELS 3 Xposition Yposition Zposition
  End Site
  {
    OFFSET 0 1 0
  }
}
MOTION
Frames: 1
Frame Time: 0.1
0 0 0
"""));
      expect(readMotionFile(bvh, "x.dat").$2, "the BVH");
      expect(() => readMotionFile(Uint8List.fromList([1, 2, 3]), "x"),
          throwsA(isA<MotionError>()));
    });
  });

  group("a video", () {
    // Vision's seventeen joints for someone standing facing the camera,
    // arms down, in metres from the hips -- their left on +x.
    List<double> standing() => [
          0, 0, 0, // hips
          0, 0.25, 0, // spine
          0, 0.5, 0, // neck
          0, 0.65, 0, // head
          0, 0.75, 0, // top of the head
          0.2, 0.5, 0, 0.22, 0.22, 0, 0.23, -0.02, 0, // left arm
          -0.2, 0.5, 0, -0.22, 0.22, 0, -0.23, -0.02, 0, // right arm
          0.1, 0, 0, 0.1, -0.45, 0, 0.1, -0.9, 0, // left leg
          -0.1, 0, 0, -0.1, -0.45, 0, -0.1, -0.9, 0, // right leg
        ];
    const names = [
      "hips", "spine", "neck", "head", "headtop_end", //
      "leftarm", "leftforearm", "lefthand",
      "rightarm", "rightforearm", "righthand",
      "leftupleg", "leftleg", "leftfoot",
      "rightupleg", "rightleg", "rightfoot",
    ];

    test("someone standing comes in standing, facing the reader", () {
      var m = motionFromCapture({
        "found": 2,
        "names": names,
        "frames": Float64List.fromList([...standing(), ...standing()]),
        "frameTime": 1 / 12,
      });
      expect(m.frameCount, 2);
      var poses = motionPoses(m, frameRate: 12, headsTall: 5.5);
      expect(poses.first.turn.abs(), lessThan(1));
      expect(poses.first[CharacterBone.upperArmR].abs(), lessThan(10));
      expect(poses.first[CharacterBone.thighL].abs(), lessThan(3));
    });

    test("no one found says so", () {
      expect(
          () => motionFromCapture({
                "found": 0,
                "names": names,
                "frames": Float64List(0),
                "frameTime": 1 / 12,
              }),
          throwsA(isA<MotionError>()
              .having((e) => e.message, "message", contains("No one"))));
    });
  });
}
