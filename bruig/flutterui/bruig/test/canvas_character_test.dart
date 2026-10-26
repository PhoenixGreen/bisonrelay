import 'dart:typed_data';
import 'dart:ui';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_cues.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_bvh.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_motion.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_wardrobe.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_lipsync.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_life.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/character_puppet.dart';
import 'package:bruig/plugin_system/canvas/ui/character_timeline.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline_view.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/render/character/painted_light.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_character_test.dart is the Character element: what is saved, the
// skeleton and how a pin bends it, where the pins are on the page, posing on
// the timeline, the drawing, and the settings and stage that pose it.

CharacterElement juno({ElementTrack? track, double rotation = 0}) =>
    CharacterElement(
        ElementBase(
            id: "c",
            name: "Juno",
            x: 200,
            y: 50,
            width: 160,
            height: 340,
            rotation: rotation,
            track: track),
        dna: characterCast.first.dna);

CharacterElement get(CanvasController c) =>
    c.document.elementById("c")! as CharacterElement;

void expectNear(Offset a, Offset b, [double within = 0.01]) {
  expect((a - b).distance, lessThan(within), reason: "$a is not $b");
}

Future<List<int>> _draw(CanvasElement e) async {
  var rec = PictureRecorder();
  paintElement(Canvas(rec), e, 6, frameRate: 24);
  var img = await rec.endRecording().toImage(600, 420);
  return (await img.toByteData())!.buffer.asUint8List();
}

Future<List<int>> _draw0(CanvasElement e) async {
  var rec = PictureRecorder();
  paintElement(Canvas(rec), e, 0);
  var img = await rec.endRecording().toImage(600, 420);
  return (await img.toByteData())!.buffer.asUint8List();
}

void main() {
  group("the model", () {
    test("a character is saved and loaded whole", () {
      var e = juno().copyWith(
          dna: characterCast[3].dna,
          pose: posePresets[1].pose);
      var back = elementFromJson(e.toJson()) as CharacterElement;
      expect(back.dna.toJson(), e.dna.toJson());
      expect(back.pose.toJson(), e.pose.toJson());
      expect(back.dna.hairStyle, HairStyle.bun);
      expect(back.dna.wardrobe.map((g) => g.kind), contains(GarmentKind.dress));
    });

    test("standing straight is kept apart from never having stood", () {
      var straight = juno().copyWith(pose: CharacterPose.rest);
      var back = elementFromJson(straight.toJson()) as CharacterElement;
      expect(back.pose[CharacterBone.upperArmL], 0,
          reason: "an empty stance is a stance");
      var json = juno().toJson()..remove("pose");
      var old = elementFromJson(json) as CharacterElement;
      expect(old.pose[CharacterBone.upperArmL],
          CharacterElement.restPose[CharacterBone.upperArmL]);
    });

    test("odd values from disk are survived", () {
      var json = juno().toJson();
      json["dna"] = {"heads": 99, "build": "wide", "hairStyle": "mohawk"};
      json["pose"] = {"upperArmL": "up", "nobody": 4, "head": 12};
      var back = elementFromJson(json) as CharacterElement;
      expect(back.dna.headsTall, CharacterDna.maxHeads);
      expect(back.dna.build, const CharacterDna().build);
      expect(back.dna.hairStyle, HairStyle.short);
      expect(back.pose[CharacterBone.head], 12);
      expect(back.pose[CharacterBone.upperArmL], 0);
    });

    test("a new one is the first of the cast, named for them", () {
      var e = newElement(ElementKind.character, const CanvasDocument())
          as CharacterElement;
      expect(e.name, characterCast.first.name);
      expect(e.dna.toJson(), characterCast.first.dna.toJson());
      expect(e.keepsAspect, isTrue);
    });
  });

  group("the rig", () {
    const box = Rect.fromLTWH(0, 0, 200, 400);

    test("stands in its box: crown at the top, soles at the bottom", () {
      // On two legs: a four-legged creature's head is carried lower.
      for (var who in characterCast
          .where((c) => !c.dna.fourLegs && !c.dna.species.legless)) {
        var rig = CharacterRig.of(who.dna, CharacterPose.rest, box);
        expect(rig.headCentre.dy - rig.headRadii.height, closeTo(0, 0.001),
            reason: who.name);
        var sole = rig.ankleL.dy + rig.below * CharacterRig.footDrop;
        expect(sole, closeTo(400, 0.001), reason: who.name);
      }
    });

    test("left is the page's left", () {
      var rig = CharacterRig.of(const CharacterDna(), CharacterPose.rest, box);
      expect(rig.shoulderL.dx, lessThan(100));
      expect(rig.hipL.dx, lessThan(100));
      var raised = CharacterRig.of(const CharacterDna(),
          const CharacterPose({CharacterBone.upperArmL: 90}), box);
      expect(raised.wristL.dx, lessThan(rig.shoulderL.dx - rig.upperArm),
          reason: "turning a hanging arm clockwise lifts it out to the left");
    });

    test("a pin bends the limb to reach it, its joint pointing outwards",
        () {
      var rig = CharacterRig.of(const CharacterDna(), CharacterPose.rest, box);
      for (var limb in CharacterLimb.values) {
        var root = rig.root(limb);
        var (a, b) = rig.lengths(limb);
        // Somewhere it can reach, a little in front and up.
        var target = root + Offset(limb.onLeft ? -0.3 : 0.3, 0.8) * (a + b) * 0.8;
        var pose = rig.solveLimb(CharacterPose.rest, limb, target);
        var solved = CharacterRig.of(const CharacterDna(), pose, box);
        expectNear(solved.end(limb), target);
        var mid = solved.middle(limb);
        // Outward of the straight line from the root to the end.
        var along = target - root;
        var side = along.dx * (mid.dy - root.dy) - along.dy * (mid.dx - root.dx);
        expect(limb.onLeft ? side > 0 : side < 0, isTrue,
            reason: "${limb.name}'s middle joint points out");
      }
    });

    test("out of reach, it stretches straight towards the pin", () {
      var rig = CharacterRig.of(const CharacterDna(), CharacterPose.rest, box);
      var far = rig.shoulderR + const Offset(1000, 0);
      var pose = rig.solveLimb(CharacterPose.rest, CharacterLimb.armR, far);
      var solved = CharacterRig.of(const CharacterDna(), pose, box);
      expect(solved.wristR.dy, closeTo(solved.shoulderR.dy, 0.5));
      expect(solved.wristR.dx,
          closeTo(solved.shoulderR.dx + rig.upperArm + rig.foreArm, 0.5));
    });

    test("the arms go with the body when it leans, and the legs do not", () {
      var lean = CharacterRig.of(const CharacterDna(),
          const CharacterPose({CharacterBone.spine: 30}), box);
      var straight =
          CharacterRig.of(const CharacterDna(), CharacterPose.rest, box);
      expect(lean.chest.dx, greaterThan(straight.chest.dx),
          reason: "clockwise, like every other turn on the page");
      expect(lean.wristL, isNot(straight.wristL));
      expectNear(lean.ankleL, straight.ankleL);
    });
  });

  group("the pins on the page", () {
    test("page and drawing map back and forth, turned and keyed", () {
      var track = ElementTrack(const [
        Keyframe(frame: 0, dx: 30, dy: -12, scale: 1.3, rotate: 20),
      ]);
      var e = juno(track: track, rotation: 15).withBase(skewX: 10)
          as CharacterElement;
      var at = CharacterPlacement.of(e, 0);
      for (var p in const [Offset(210, 70), Offset(300, 380), Offset(0, 0)]) {
        expectNear(at.toLocal(at.toPage(p)), p, 1e-6);
      }
    });

    test("a pin dragged on the page lands the hand there", () {
      var e = juno(rotation: 25);
      var at = CharacterPlacement.of(e, 0);
      var to = at.pin(CharacterPin.handR) + const Offset(-30, -60);
      var posed = e.copyWith(pose: at.posedBy(CharacterPin.handR, to));
      expectNear(CharacterPlacement.of(posed, 0).pin(CharacterPin.handR), to);
      expect(posed.pose[CharacterBone.upperArmL],
          e.pose[CharacterBone.upperArmL],
          reason: "the other arm stays");
    });
  });

  group("posing on the timeline", () {
    CanvasController animated() => CanvasController(
        CanvasDocument(frames: 48).addElement(juno()));

    test("until a pose is keyed, a change of pose is the stance", () {
      var c = animated();
      addTearDown(c.dispose);
      c.frame = 20;
      c.setCharacterPose(get(c), posePresets[3].pose);
      expect(get(c).track, isNull);
      expect(get(c).pose[CharacterBone.upperArmL],
          posePresets[3].pose[CharacterBone.upperArmL]);
    });

    test("keyed, it is arrived at from the stance and then held", () {
      var c = animated();
      addTearDown(c.dispose);
      var stance = get(c).pose;
      c.frame = 20;
      c.keyCharacterPose(get(c), posePresets[3].pose);
      var e = get(c);
      expect(e.posedOnTimeline, isTrue);
      expect(e.track!.keys.map((k) => k.frame), [0, 20]);
      expect(e.poseAtFrame(0)[CharacterBone.upperArmL],
          stance[CharacterBone.upperArmL]);
      var cheer = posePresets[3].pose[CharacterBone.upperArmL];
      var mid = e.poseAtFrame(10)[CharacterBone.upperArmL];
      expect(mid, greaterThan(stance[CharacterBone.upperArmL]));
      expect(mid, lessThan(cheer));
      expect(e.poseAtFrame(40)[CharacterBone.upperArmL], cheer);
      expect(e.track!.posesAnything, isFalse,
          reason: "a pose is not a move: dragging it still moves it");
    });

    test("once keyed, a change of pose is a keyframe where it is made", () {
      var c = animated();
      addTearDown(c.dispose);
      c.frame = 10;
      c.keyCharacterPose(get(c), posePresets[1].pose);
      c.frame = 30;
      c.setCharacterPose(get(c), posePresets[4].pose);
      var e = get(c);
      expect(e.track!.keys.map((k) => k.frame), [0, 10, 30]);
      expect(c.hasCharacterPoseKey(e), isTrue);
      c.clearCharacterPoseKey(e);
      expect(get(c).track!.keys.map((k) => k.frame), [0, 10]);
    });
  });

  group("the face", () {
    test("a face is saved and loaded, and odd values are survived", () {
      var e = juno().copyWith(
          face: expressionPresets[6].face.withMouth(MouthShape.wide),
          life: const CharacterLife(blink: false, glance: true));
      var back = elementFromJson(e.toJson()) as CharacterElement;
      expect(back.face.toJson(), e.face.toJson());
      expect(back.face.mouth, MouthShape.wide);
      expect(back.life.blink, isFalse);
      expect(back.life.glance, isTrue);
      var json = e.toJson();
      json["face"] = {"smile": 9, "eyesOpen": "wide", "mouth": "whistle"};
      var odd = elementFromJson(json) as CharacterElement;
      expect(odd.face[FaceControl.smile], 1, reason: "kept in range");
      expect(odd.face[FaceControl.eyesOpen], 1);
      expect(odd.face.mouth, MouthShape.rest);
    });

    test("a feeling leaves the head where it is turned", () {
      var turned = CharacterFace.rest.withControl(FaceControl.turn, 60);
      var happy = turned.feeling(expressionPresets[1].face);
      expect(happy[FaceControl.turn], 60);
      expect(happy[FaceControl.smile], 0.8);
      var half = CharacterFace.rest.mixed(expressionPresets[6].face, 0.5);
      expect(half[FaceControl.browRaise], closeTo(0.5, 1e-9));
    });

    test("the face eases between keys, and the mouth is held", () {
      var track = ElementTrack([
        Keyframe(frame: 10, values: {
          faceChannel(FaceControl.smile): 0,
          mouthChannel: MouthShape.wide.index.toDouble(),
        }),
        Keyframe(frame: 20, values: {
          faceChannel(FaceControl.smile): 1,
          mouthChannel: MouthShape.pucker.index.toDouble(),
        }),
      ]);
      var e = juno(track: track);
      expect(e.faceAtFrame(15)[FaceControl.smile], closeTo(0.5, 1e-9));
      expect(e.faceAtFrame(15).mouth, MouthShape.wide,
          reason: "no shape half way between two mouths");
      expect(e.faceAtFrame(20).mouth, MouthShape.pucker);
      expect(e.faceAtFrame(3).mouth, MouthShape.wide,
          reason: "the first key holds before it");
      expect(e.posedOnTimeline, isTrue);
    });

    test("keying keys the face with the pose", () {
      var c = CanvasController(CanvasDocument(frames: 48).addElement(juno()));
      addTearDown(c.dispose);
      c.frame = 12;
      c.replaceElement(c.characterFaced(get(c), expressionPresets[5].face));
      c.keyCharacterPose(get(c));
      var e = get(c);
      expect(e.track!.keys.map((k) => k.frame), [0, 12]);
      expect(e.faceAtFrame(12)[FaceControl.browSqueeze], 1);
      c.frame = 30;
      c.replaceElement(
          c.characterFaced(get(c), expressionPresets[1].face));
      expect(get(c).track!.keys.map((k) => k.frame), [0, 12, 30],
          reason: "once keyed, a change of face is a keyframe");
    });
  });

  group("staying alive", () {
    test("blinks are the same every time, and differ between characters", () {
      var a = juno();
      var b = juno().withId("other") as CharacterElement;
      List<double> blinks(CharacterElement e) =>
          [for (var f = 0; f < 24 * 12; f++) lifeAt(e, f, 24).blink];
      var once = blinks(a);
      expect(blinks(a), once);
      expect(once.first, 0, reason: "never caught blinking at the start");
      expect(once.where((v) => v > 0.9).length, greaterThan(1),
          reason: "blinks in twelve seconds");
      expect(blinks(b), isNot(once));
      var still = a.copyWith(life: CharacterLife.still);
      expect(blinks(still).every((v) => v == 0), isTrue);
    });

    test("breathing lifts the chest and nothing below it", () {
      const box = Rect.fromLTWH(0, 0, 200, 400);
      var out = CharacterRig.of(const CharacterDna(), CharacterPose.rest, box);
      var inn = CharacterRig.of(const CharacterDna(), CharacterPose.rest, box,
          breath: 1);
      expect(inn.chest.dy, lessThan(out.chest.dy));
      expect(inn.headCentre.dy, lessThan(out.headCentre.dy));
      expectNear(inn.ankleL, out.ankleL);
    });
  });

  group("lip sync", () {
    const a = MouthShape.closed,
        b = MouthShape.teeth,
        c = MouthShape.open,
        e = MouthShape.round,
        f = MouthShape.pucker,
        g = MouthShape.lip,
        h = MouthShape.tongue;

    test("words are spelt into the mouths they are said with", () {
      expect(mouthsOfWord("Mom!"), [a, e, a]);
      expect(mouthsOfWord("hello"), [c, h, e]);
      expect(mouthsOfWord("food"), [g, f, b]);
      expect(mouthsOfWord("make"), [a, c, b], reason: "the e is silent");
      expect(mouthsOfWord("the"), [b, c]);
      expect(mouthsOfWord("phone"), [g, e, b]);
      expect(mouthsOfWord("8,640"), isEmpty);
    });

    test("a word's time is shared out, and the mouth rests in a pause", () {
      var words = const [
        SpokenWord(text: "hello", frame: 10, end: 22),
        SpokenWord(text: "mom", frame: 40, end: 48),
      ];
      var keys = mouthsFromWords(words,
          frameRate: 24, feel: const LipSyncFeel(lead: 0));
      expect(keys.first, (frame: 10, shape: c));
      expect(keys.map((k) => k.shape),
          [c, h, e, MouthShape.rest, a, e, a, MouthShape.rest]);
      expect(keys.where((k) => k.shape == MouthShape.rest).first.frame, 22);
      for (var i = 1; i < keys.length; i++) {
        expect(keys[i].frame - keys[i - 1].frame, greaterThanOrEqualTo(2),
            reason: "nothing shorter than the shortest mouth");
      }
      var led = mouthsFromWords(words, frameRate: 24);
      expect(led.first.frame, 9, reason: "a frame ahead of the voice");
    });

    test("a short word keeps its closures and its vowels", () {
      var keys = mouthsFromWords(
          const [SpokenWord(text: "bumps", frame: 0, end: 4)],
          frameRate: 24,
          feel: const LipSyncFeel(lead: 0));
      expect(keys.map((k) => k.shape), contains(a));
      expect(keys.where((k) => k.shape != MouthShape.rest).length,
          lessThanOrEqualTo(2));
    });

    test("with only the sound, louder is more open", () {
      // Half a second quiet, a second loud with a dip, half a second quiet,
      // at a hundred readings a second.
      var peaks = Float32List(200);
      for (var i = 50; i < 150; i++) {
        peaks[i] = 0.9;
      }
      peaks[100] = peaks[101] = peaks[102] = peaks[103] = 0.1;
      var keys = mouthsFromLoudness(peaks, 2,
          startFrame: 100, frameRate: 24, feel: const LipSyncFeel(lead: 0));
      expect(keys.first, (frame: 100, shape: MouthShape.rest));
      expect(keys[1].frame, 112);
      expect(keys[1].shape, MouthShape.wide);
      expect(keys.map((k) => k.shape), contains(a), reason: "the dip");
      expect(keys.last.shape, MouthShape.rest);
      expect(keys.last.frame, 136);
    });

    test("mouths go on the track, and leave the pose alone", () {
      var c0 = juno().copyWith(pose: posePresets[1].pose);
      var synced = c0.withMouths(const [
        (frame: 5, shape: MouthShape.wide),
        (frame: 9, shape: MouthShape.rest),
      ]);
      expect(synced.posedOnTimeline, isFalse,
          reason: "lip sync is not posing");
      expect(synced.faceAtFrame(6).mouth, MouthShape.wide);
      expect(synced.faceAtFrame(12).mouth, MouthShape.rest);
      expect(synced.poseAtFrame(6)[CharacterBone.upperArmR],
          posePresets[1].pose[CharacterBone.upperArmR]);
      var again = synced.withMouths(const [
        (frame: 30, shape: MouthShape.pucker),
      ], from: 20);
      expect(again.mouthKeys.length, 3, reason: "only from 20 on replaced");
      expect(synced.withMouths(const []).track, isNull,
          reason: "cleared, nothing is left behind");
    });

    test("the controller syncs from the words heard on a voice", () async {
      var voice = AudioElement(const ElementBase(id: "v"),
          clip: const MediaClip(
              timed: true,
              at: 12,
              playlist: [MediaSource(assetId: "a1", length: 4)]));
      var doc = CanvasDocument(frames: 120, words: const [
        SpokenWord(text: "hello", frame: 20, end: 32, from: "voice:v"),
        SpokenWord(text: "there", frame: 60, end: 70, from: "voice:other"),
      ]).addElement(voice).addElement(juno());
      var c = CanvasController(doc);
      addTearDown(c.dispose);
      var done = await c.lipSync(get(c), voice);
      expect(done.problem, isNull);
      expect(done.mouths, greaterThan(2));
      var keys = get(c).mouthKeys;
      expect(keys.first.frame, 19);
      expect(keys.every((k) => k.frame < 60), isTrue,
          reason: "only this voice's words");
      c.undo();
      expect(get(c).mouthKeys, isEmpty, reason: "one undo step");

      await c.lipSync(get(c), voice);
      c.frame = 22;
      c.replaceElement(c.characterMouthed(get(c), MouthShape.pucker));
      expect(get(c).faceAtFrame(23).mouth, MouthShape.pucker,
          reason: "a mouth picked by hand is keyed where it is picked");
      c.clearLipSync(get(c));
      expect(get(c).mouthKeys, isEmpty);
    });
  });

  group("turning and swinging", () {
    const box = Rect.fromLTWH(0, 0, 200, 400);

    test("a pose's swings, turn and lift are saved and keyed", () {
      var p = CharacterPose.rest
          .withSwing(CharacterBone.thighL, 30)
          .withTurn(90)
          .withLift(0.2);
      var back = CharacterPose.fromJson(p.toJson());
      expect(back.swing(CharacterBone.thighL), 30);
      expect(back.turn, 90);
      expect(back.lift, 0.2);
      var keyed = CharacterPose.rest.over(Keyframe(frame: 0, values: p.channels));
      expect(keyed.swing(CharacterBone.thighL), 30);
      expect(keyed.turn, 90);
    });

    test("side on, the shoulders line up and the far arm is behind", () {
      var rig = CharacterRig.of(
          const CharacterDna(), CharacterPose.rest.withTurn(90), box);
      expect(rig.shoulderL.dx, closeTo(rig.shoulderR.dx, 0.001));
      expect(rig.depths[CharacterLimb.armL]!,
          lessThan(rig.depths[CharacterLimb.armR]!));
      var stride = CharacterRig.of(const CharacterDna(),
          CharacterPose.rest.withTurn(90).withSwing(CharacterBone.thighL, 30),
          box);
      expect(stride.ankleL.dx, lessThan(rig.ankleL.dx - 10),
          reason: "turned to the left, a leg swung forward goes left");
      var front = CharacterRig.of(const CharacterDna(),
          CharacterPose.rest.withSwing(CharacterBone.thighL, 30), box);
      expect(front.ankleL.dy, lessThan(rig.ankleL.dy),
          reason: "facing the reader, a swung leg is foreshortened");
    });

    test("side on, a pin swings a leg rather than spreading it", () {
      var pose = CharacterPose.rest.withTurn(90);
      var rig = CharacterRig.of(const CharacterDna(), pose, box);
      var target = rig.hipL + Offset(-rig.thigh * 0.6, rig.thigh * 1.4);
      var solved = rig.solveLimb(pose, CharacterLimb.legL, target);
      expect(solved[CharacterBone.thighL], 0);
      expect(solved.swing(CharacterBone.thighL), greaterThan(0));
      var after = CharacterRig.of(const CharacterDna(), solved, box);
      expectNear(after.ankleL, target, 0.5);
    });

    test("lift raises the whole figure", () {
      var up = CharacterRig.of(
          const CharacterDna(), CharacterPose.rest.withLift(1), box);
      var down = CharacterRig.of(const CharacterDna(), CharacterPose.rest, box);
      expect(down.ankleL.dy - up.ankleL.dy, closeTo(up.unit, 0.001));
    });
  });

  group("motion", () {
    MotionClip clip(MotionKind k, {int start = 0, int length = 48}) =>
        MotionClip(
            id: "m", kind: k, layer: k.layer, start: start, length: length);

    test("a clip is saved and comes in and goes out", () {
      var m = clip(MotionKind.wave, start: 10, length: 20)
          .copyWith(speed: 1.5, mirror: true, blend: 4);
      var back = MotionClip.fromJson(m.toJson())!;
      expect(back.kind, MotionKind.wave);
      expect(back.speed, 1.5);
      expect(back.mirror, isTrue);
      expect(m.weightAt(9), 0);
      expect(m.weightAt(10), closeTo(1 / 5, 1e-9));
      expect(m.weightAt(20), 1);
      expect(m.weightAt(29), closeTo(1 / 5, 1e-9));
      expect(m.weightAt(30), 0);
      var e = juno().copyWith(motions: [m]);
      var loaded = elementFromJson(e.toJson()) as CharacterElement;
      expect(loaded.motions.single.kind, MotionKind.wave);
    });

    test("a walk swings the legs and leaves the way it faces", () {
      var base = CharacterPose.rest.withTurn(90);
      var (a, _) = withMotions(base, CharacterFace.rest,
          [clip(MotionKind.walk).copyWith(blend: 0)], 6, 24);
      expect(a.turn, 90);
      expect(a.swing(CharacterBone.thighL), isNot(0));
      expect(a.swing(CharacterBone.thighL),
          closeTo(-a.swing(CharacterBone.thighR), 1e-9));
    });

    test("an upper-body clip leaves the legs to what is under it", () {
      var (p, f) = withMotions(
          CharacterPose.rest,
          CharacterFace.rest,
          [
            clip(MotionKind.walk).copyWith(blend: 0),
            MotionClip(
                id: "w",
                kind: MotionKind.wave,
                layer: MotionLayer.upper,
                start: 0,
                length: 48,
                blend: 0),
          ],
          6,
          24);
      expect(p[CharacterBone.upperArmR], -130, reason: "the wave's arm");
      expect(p.swing(CharacterBone.thighL), isNot(0), reason: "the walk's legs");
      expect(f[FaceControl.smile], 0.6);
    });

    test("mirrored, the wave is the other arm", () {
      var m = motionAt(MotionKind.wave, 0.2, mirror: true);
      expect(m.pose[CharacterBone.upperArmL], 130);
    });

    test("motions are drawn: the character moves with them", () async {
      var still = await _draw(juno());
      var waving = await _draw(
          juno().copyWith(motions: [clip(MotionKind.cheer).copyWith(blend: 0)]));
      expect(waving, isNot(still));
    });
  });

  group("motion on the timeline", () {
    test("a motion is added at the playhead, long enough to see", () {
      var c = CanvasController(CanvasDocument(frames: 120).addElement(juno()));
      addTearDown(c.dispose);
      c.frame = 10;
      var m = c.addMotion(get(c), MotionKind.walk);
      expect(m.start, 10);
      expect(m.length, 48, reason: "two seconds at 24");
      var jump = c.addMotion(get(c), MotionKind.jump);
      expect(jump.length, 24, reason: "once, its own length");
      c.removeMotion(get(c), m.id);
      expect(get(c).motions.single.kind, MotionKind.jump);
    });

    test("walking across turns, travels and turns back, in one undo", () {
      var c = CanvasController(CanvasDocument(frames: 120).addElement(juno()));
      addTearDown(c.dispose);
      c.frame = 12;
      c.walkAcross(get(c), MotionKind.walk, 1, 2);
      var e = get(c);
      expect(e.motions.single.start, 12);
      expect(e.motions.single.length, 48);
      expect(e.poseAt(60).dx, closeTo(0.6 * e.height * 2, 1e-6));
      expect(e.poseAt(12).dx, 0);
      expect(e.poseAtFrame(36).turn, -90, reason: "facing right to go right");
      expect(e.poseAtFrame(60).turn, 0, reason: "back to the reader");
      c.undo();
      expect(get(c).motions, isEmpty);
      expect(get(c).track, isNull);
    });

    test("recording keys a pose on each frame it is given", () {
      var c = CanvasController(CanvasDocument(frames: 120).addElement(juno()));
      addTearDown(c.dispose);
      for (var f = 10; f < 14; f++) {
        c.frame = f;
        c.recordCharacterPose(get(c),
            get(c).pose.withAngle(CharacterBone.upperArmR, -20.0 - f));
      }
      var e = get(c);
      expect(e.track!.keys.map((k) => k.frame), [0, 10, 11, 12, 13]);
      expect(e.poseAtFrame(13)[CharacterBone.upperArmR], -33);
      expect(e.poseAtFrame(0)[CharacterBone.upperArmR],
          CharacterElement.restPose[CharacterBone.upperArmR],
          reason: "it stood as it did before the recording");
    });
  });

  group("motion capture", () {
    String bvh(List<String> rows) => """
HIERARCHY
ROOT Hips
{
  OFFSET 0 0 0
  CHANNELS 6 Xposition Yposition Zposition Zrotation Xrotation Yrotation
  JOINT Spine
  {
    OFFSET 0 10 0
    CHANNELS 3 Zrotation Xrotation Yrotation
    JOINT Neck
    {
      OFFSET 0 10 0
      CHANNELS 3 Zrotation Xrotation Yrotation
      JOINT Head
      {
        OFFSET 0 5 0
        CHANNELS 3 Zrotation Xrotation Yrotation
        End Site
        {
          OFFSET 0 5 0
        }
      }
    }
    JOINT LeftArm
    {
      OFFSET 5 8 0
      CHANNELS 3 Zrotation Xrotation Yrotation
      JOINT LeftForeArm
      {
        OFFSET 6 0 0
        CHANNELS 3 Zrotation Xrotation Yrotation
        JOINT LeftHand
        {
          OFFSET 6 0 0
          CHANNELS 3 Zrotation Xrotation Yrotation
        }
      }
    }
    JOINT RightArm
    {
      OFFSET -5 8 0
      CHANNELS 3 Zrotation Xrotation Yrotation
      JOINT RightForeArm
      {
        OFFSET -6 0 0
        CHANNELS 3 Zrotation Xrotation Yrotation
        JOINT RightHand
        {
          OFFSET -6 0 0
          CHANNELS 3 Zrotation Xrotation Yrotation
        }
      }
    }
  }
  JOINT LeftUpLeg
  {
    OFFSET 3 0 0
    CHANNELS 3 Zrotation Xrotation Yrotation
    JOINT LeftLeg
    {
      OFFSET 0 -12 0
      CHANNELS 3 Zrotation Xrotation Yrotation
      JOINT LeftFoot
      {
        OFFSET 0 -12 0
        CHANNELS 3 Zrotation Xrotation Yrotation
      }
    }
  }
  JOINT RightUpLeg
  {
    OFFSET -3 0 0
    CHANNELS 3 Zrotation Xrotation Yrotation
    JOINT RightLeg
    {
      OFFSET 0 -12 0
      CHANNELS 3 Zrotation Xrotation Yrotation
      JOINT RightFoot
      {
        OFFSET 0 -12 0
        CHANNELS 3 Zrotation Xrotation Yrotation
      }
    }
  }
}
MOTION
Frames: ${rows.length}
Frame Time: 0.0416667
${rows.join("\n")}
""";

    // 6 for the hips, then 3 for each of the other 15 joints.
    String row({double leftThighX = 0, double hipsY = 24}) {
      var v = List<double>.filled(6 + 3 * 15, 0);
      v[1] = hipsY;
      // LeftUpLeg is joint 10 counting the hips as 0: its numbers start at
      // 6 + 3 * 9, and its X rotation is the second of them.
      v[6 + 3 * 9 + 1] = leftThighX;
      return v.join(" ");
    }

    test("a skeleton and its frames are read", () {
      var b = parseBvh(bvh([row(), row()]));
      expect(b.joints.length, 16);
      expect(b.frames.length, 2);
      expect(b.joints.map((j) => j.name), contains("LeftForeArm"));
      expect(() => parseBvh("not a bvh"), throwsA(isA<BvhError>()));
    });

    test("it becomes poses of our bones, sides and all", () {
      var b = parseBvh(bvh([row(), row(leftThighX: -30, hipsY: 30)]));
      var poses = bvhPoses(b, frameRate: 24, headsTall: 5.5);
      expect(poses.length, 2);
      var rest = poses.first;
      expect(rest.turn, closeTo(0, 1e-6), reason: "it faces the reader");
      expect(rest[CharacterBone.thighL], closeTo(0, 1e-6));
      // A T-pose: the BVH's left arm out to the side, which is the page's
      // right -- our right arm, spread the whole way.
      expect(rest[CharacterBone.upperArmR], closeTo(-90, 1e-6));
      expect(rest[CharacterBone.upperArmL], closeTo(90, 1e-6));
      var step = poses[1];
      expect(step.swing(CharacterBone.thighR), closeTo(30, 1e-6),
          reason: "the BVH's left thigh forwards, our right");
      expect(step.lift, greaterThan(0), reason: "the hips went up");
    });

    test("a skeleton without the joints we need is said so", () {
      var broken = bvh([row()]).replaceAll("LeftFoot", "LeftToe");
      expect(
          () => bvhPoses(parseBvh(broken), frameRate: 24, headsTall: 5),
          throwsA(isA<BvhError>().having(
              (e) => e.message, "message", contains("left foot"))));
    });

    test("imported, it is a key a frame from the playhead, in one undo", () {
      var c = CanvasController(CanvasDocument(frames: 30).addElement(juno()));
      addTearDown(c.dispose);
      c.frame = 25;
      var poses = [
        for (var i = 0; i < 10; i++)
          CharacterPose.rest.withTurn(40).withAngle(CharacterBone.head, i * 1.0)
      ];
      var laid = c.importMotion(get(c), poses);
      expect(laid, 5, reason: "the canvas ends at 30");
      expect(get(c).poseAtFrame(26).turn, 0,
          reason: "turned to start facing the reader");
      expect(get(c).poseAtFrame(27)[CharacterBone.head], 2);
      c.undo();
      expect(get(c).track, isNull);
    });
  });

  group("wardrobe", () {
    test("a garment is saved whole, and odd values are survived", () {
      var g = const Garment(GarmentKind.hoodie,
          color: Color(0xFF112233),
          color2: Color(0xFF445566),
          pattern: GarmentPattern.check,
          length: 1.3,
          sleeve: 0.5,
          fit: 1.2,
          condition: GarmentCondition(rips: 0.5, dirt: 0.2),
          seed: 42);
      var back = Garment.fromJson(g.toJson())!;
      expect(back.toJson(), g.toJson());
      expect(Garment.fromJson({"kind": "spacesuit"}), isNull);
      var odd = Garment.fromJson({
        "kind": "tee",
        "fit": 9,
        "condition": {"rips": 4}
      })!;
      expect(odd.fitOr, 1.4);
      expect(odd.condition.rips, 1);
      expect(odd.sleeveOr, GarmentKind.tee.sleeve, reason: "the kind's own");
    });

    test("putting on goes in its place and takes off what it replaces", () {
      var w = CharacterDna.defaultWardrobe;
      var coat = putOn(w, const Garment(GarmentKind.coat, color: Color(0xFF000000)));
      expect(coat.last.kind, GarmentKind.trainers,
          reason: "shoes go on after the coat");
      expect(coat[coat.length - 2].kind, GarmentKind.coat);
      expect(coat.indexWhere((g) => g.kind == GarmentKind.coat),
          greaterThan(coat.indexWhere((g) => g.kind == GarmentKind.hoodie)));
      var tee = putOn(w, const Garment(GarmentKind.tee, color: Color(0xFF000000)));
      expect(tee.map((g) => g.kind), isNot(contains(GarmentKind.hoodie)));
      expect(tee.map((g) => g.kind), contains(GarmentKind.trousers));
      var dress = putOn(w, const Garment(GarmentKind.dress, color: Color(0xFF000000)));
      expect(dress.map((g) => g.kind),
          isNot(anyOf(contains(GarmentKind.hoodie), contains(GarmentKind.trousers))));
      expect(dress.map((g) => g.kind), contains(GarmentKind.briefs),
          reason: "the base layer stays");
      var socks = putOn(w, const Garment(GarmentKind.socks, color: Color(0xFF000000)));
      expect(socks.map((g) => g.kind), contains(GarmentKind.briefs),
          reason: "socks do not replace pants");
      var m = moved(w, 2, 1);
      expect(m[3].kind, w[2].kind);
    });

    test("a character saved before the wardrobe keeps its clothes", () {
      var old = {
        "heads": 5.5,
        "top": "shirt",
        "topColor": 0xFF102030,
        "bottom": "skirt",
        "bottomColor": 0xFF405060,
        "shoes": 0xFF708090,
      };
      var dna = CharacterDna.fromJson(old);
      var kinds = dna.wardrobe.map((g) => g.kind).toList();
      expect(kinds, containsAll([GarmentKind.shirt, GarmentKind.skirt, GarmentKind.trainers]));
      expect(dna.wardrobe.firstWhere((g) => g.kind == GarmentKind.shirt).color,
          const Color(0xFF102030));
    });

    test("the base layer can be left off, and bare is the editor's only",
        () async {
      var dna = const CharacterDna();
      expect(dna.copyWith(baseLayer: false).worn.any(
          (g) => g.kind.slot == GarmentSlot.base), isFalse);
      var e = juno().copyWith(bareView: true);
      Future<List<int>> draw(bool editing) async {
        var rec = PictureRecorder();
        paintElement(Canvas(rec), e, 0, editing: editing);
        var img = await rec.endRecording().toImage(600, 420);
        return (await img.toByteData())!.buffer.asUint8List();
      }

      var exported = await draw(false);
      expect(await draw(true), isNot(exported));
      expect(exported, await _draw0(juno()),
          reason: "an export is dressed, bare view or not");
    });

    test("wear is drawn, and is the same every time", () async {
      var worn = juno().copyWith(
          dna: juno().dna.copyWith(wardrobe: [
        for (var g in juno().dna.wardrobe)
          g.copyWith(condition: conditionPresets[2].$2)
      ]));
      var a = await _draw0(worn), b = await _draw0(worn);
      expect(a, b);
      expect(a, isNot(await _draw0(juno())));
    });
  });

  group("styles", () {
    test("every style draws, each its own way, the same every time",
        () async {
      // Painted light draws flat until its shader is loaded, as the 3D
      // body's toon light does: loaded first, it is the same every time.
      await PaintShader.load();
      var drawn = <String, List<int>>{};
      for (var st in CharacterStyle.values) {
        var e = juno().copyWith(style: st);
        var a = await _draw0(e);
        expect(a, await _draw0(e), reason: "${st.name} is the same twice");
        drawn[st.name] = a;
      }
      expect(drawn.values.map((d) => d.toString().hashCode).toSet().length,
          CharacterStyle.values.length,
          reason: "no two styles draw alike");
      var back = elementFromJson(juno().copyWith(style: CharacterStyle.comic).toJson())
          as CharacterElement;
      expect(back.style, CharacterStyle.comic);
    });

    test("chibi shortens the body, clay moves on twos", () {
      expect(CharacterStyle.chibi.dnaOf(const CharacterDna()).headsTall, 2.6);
      expect(CharacterStyle.anime.dnaOf(const CharacterDna()).headsTall, 5.5);
      expect(CharacterStyle.clay.frameOf(7), 6);
      expect(CharacterStyle.clay.frameOf(8), 8);
      expect(CharacterStyle.anime.frameOf(7), 7);
    });

    test("on a chibi the pins are where it is drawn", () {
      var e = juno().copyWith(style: CharacterStyle.chibi);
      var at = CharacterPlacement.of(e, 0);
      var styled = CharacterRig.of(
          CharacterStyle.chibi.dnaOf(e.dna), e.pose, e.bounds);
      expectNear(at.pin(CharacterPin.handR), styled.wristR);
    });
  });

  group("the spine and four legs", () {
    const box = Rect.fromLTWH(0, 0, 200, 400);

    test("a forward lean goes the way the body faces", () {
      var lean = CharacterRig.of(const CharacterDna(),
          CharacterPose.rest.withTurn(90).withSwing(CharacterBone.spine, 30), box);
      expect(lean.chest.dx, lessThan(lean.hips.dx - 10),
          reason: "turned to the left, forwards is to the left");
      var rig = CharacterRig.of(
          const CharacterDna(), CharacterPose.rest.withTurn(90), box);
      var leaned = rig.solveLean(CharacterPose.rest.withTurn(90),
          rig.hips + const Offset(-60, -100));
      expect(leaned.swing(CharacterBone.spine), greaterThan(0),
          reason: "the lean pin drawn forwards leans forwards");
    });

    test("on four legs the body is level and stands on all four", () {
      var dna = const CharacterDna(fourLegs: true, species: Species.dog);
      var rig = CharacterRig.of(dna, CharacterPose.rest.withTurn(90), box);
      expect((rig.chest.dy - rig.hips.dy).abs(), lessThan(rig.torsoLength * 0.3),
          reason: "level");
      expect(rig.chest.dx, lessThan(rig.hips.dx - rig.torsoLength * 0.8),
          reason: "the shoulders ahead of the hips");
      for (var front in [rig.wristL, rig.wristR]) {
        expect(front.dy, closeTo(rig.ankleL.dy, rig.unit * 0.6),
            reason: "front feet on the ground with the back ones");
      }
      expect(rig.headScale, lessThan(1));
    });

    test("on four legs a pin still lands the foot where it is dragged", () {
      var e = juno().copyWith(
          dna: const CharacterDna(fourLegs: true, species: Species.dog),
          pose: CharacterPose.rest.withTurn(90));
      var at = CharacterPlacement.of(e, 0);
      var to = at.pin(CharacterPin.handL) + const Offset(-20, -15);
      var posed = e.copyWith(pose: at.posedBy(CharacterPin.handL, to));
      expectNear(CharacterPlacement.of(posed, 0).pin(CharacterPin.handL), to, 1);
    });

    test("a creature is saved whole", () {
      var dna = characterCast.firstWhere((c) => c.name == "Ember").dna;
      var back = CharacterDna.fromJson(dna.toJson());
      expect(back.toJson(), dna.toJson());
      expect(back.wings, WingKind.bat);
      expect(back.fourLegs, isTrue);
      expect(back.eyeCount, 2);
      var grub = characterCast.firstWhere((c) => c.name == "Grub").dna;
      expect(CharacterDna.fromJson(grub.toJson()).eyeCount, 1);
    });
  });

  group("birds, fish and flying", () {
    const box = Rect.fromLTWH(0, 0, 200, 400);
    CharacterDna who(String name) =>
        characterCast.firstWhere((c) => c.name == name).dna;

    test("a bird's arms are its wings, and rise as they flap", () {
      var folded = CharacterRig.of(who("Ollie"), CharacterPose.rest, box);
      var raised = CharacterRig.of(who("Ollie"),
          CharacterPose.rest.withAngle(CharacterBone.wings, 60), box);
      expect(raised.wristL.dy, lessThan(folded.wristL.dy - 10));
      expect(raised.wristR.dy, lessThan(folded.wristR.dy - 10));
      expect(raised.wingFlap, 60);
    });

    test("flying lifts and flaps; swimming floats", () {
      var (fly, _) = withMotions(
          CharacterPose.rest,
          CharacterFace.rest,
          const [
            MotionClip(
                id: "f",
                kind: MotionKind.fly,
                layer: MotionLayer.added,
                start: 0,
                length: 99,
                blend: 0)
          ],
          3,
          24);
      expect(fly.lift, greaterThan(0.4));
      expect(fly[CharacterBone.wings], greaterThan(0));
      var rig = CharacterRig.of(who("Finn"), CharacterPose.rest, box);
      expect(rig.hips.dy, lessThan(box.height * 0.75), reason: "a fish floats");
    });

    test("a fish has no feet to take hold of", () {
      var e = juno().copyWith(dna: who("Finn"));
      var pins = CharacterPlacement.of(e, 0).pins;
      expect(pins, isNot(contains(CharacterPin.footL)));
      expect(pins, contains(CharacterPin.handL));
    });

    test("every creature draws, dressed on four legs too", () async {
      for (var c in characterCast.skip(1)) {
        var e = juno().copyWith(dna: c.dna);
        expect(await _draw0(e), isNot(await _draw0(juno())), reason: c.name);
      }
      var dog = juno().copyWith(
          dna: who("Biscuit").copyWith(wardrobe: [
        const Garment(GarmentKind.hoodie, color: Color(0xFFE05A47)),
        const Garment(GarmentKind.trousers, color: Color(0xFF2F3E5C)),
      ]));
      expect(await _draw0(dog),
          isNot(await _draw0(juno().copyWith(dna: who("Biscuit")))));
    });
  });

  group("the drawing", () {
    Future<List<int>> draw(CanvasElement e) async {
      var rec = PictureRecorder();
      paintElement(Canvas(rec), e, 0);
      var img = await rec.endRecording().toImage(600, 420);
      return (await img.toByteData())!.buffer.asUint8List();
    }

    test("the same character draws the same, and a pose changes it",
        () async {
      var e = juno();
      var a = await draw(e), b = await draw(e);
      expect(a, b);
      var waving = await draw(e.copyWith(pose: posePresets[1].pose));
      expect(waving, isNot(a));
      var talking = await draw(
          e.copyWith(face: CharacterFace.rest.withMouth(MouthShape.wide)));
      expect(talking, isNot(a));
      var away = await draw(e.copyWith(
          face: CharacterFace.rest.withControl(FaceControl.turn, 180)));
      expect(away, isNot(a));
      var inked = a.indexed.where((p) => p.$1 % 4 == 3 && p.$2 > 0).length;
      expect(inked, greaterThan(160 * 340 * 0.2),
          reason: "a figure, not a speck");
    });
  });

  group("the controls", () {
    Widget host(CanvasController c, {bool stage = false}) => MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeNotifier>(
                create: (c) => ThemeNotifier(doLoad: false)),
            ChangeNotifierProvider<SnackBarModel>(
                create: (c) => SnackBarModel()),
            ChangeNotifierProvider<CanvasPreferences>(
                create: (c) => CanvasPreferences()),
          ],
          child: MaterialApp(
              home: Scaffold(
                  body: Row(children: [
            SizedBox(width: 420, child: CanvasDesignPanel(controller: c)),
            if (stage)
              Expanded(
                  child:
                      CanvasStage(key: const ValueKey("stage"), controller: c)),
          ]))),
        );

    setUpAll(() => CanvasSection.openAll = true);
    tearDownAll(() => CanvasSection.openAll = false);

    Future<void> tap(WidgetTester tester, String key) async {
      var f = find.byKey(ValueKey(key));
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    testWidgets("the panel picks a cast member, a pose and a size",
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(
          CanvasDocument(frames: 24).addElement(juno()));
      addTearDown(c.dispose);
      c.selectOnly("c");
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(c));
      await tester.pumpAndSettle();

      // A type, and someone ready-made of that type.
      await tap(tester, "characterType-girl");
      expect(get(c).dna.kind, CharacterType.girl);
      expect(get(c).dna.headsTall, CharacterType.girl.dna.headsTall);
      await tap(tester, "characterCast-Mae");
      expect(get(c).dna.hairStyle, HairStyle.bun);
      expect(get(c).name, "Mae", reason: "renamed with them");
      c.undo();
      expect(get(c).name, "Girl", reason: "one undo step");
      c.undo();
      expect(get(c).name, "Juno");

      await tap(tester, "characterPose-Cheer");
      expect(get(c).pose[CharacterBone.upperArmL],
          posePresets[3].pose[CharacterBone.upperArmL]);

      await tap(tester, "appearanceTab-hair");
      await tap(tester, "characterHair-long");
      expect(get(c).dna.hairStyle, HairStyle.long);
      // Wardrobe: a dress put on in place of the top and the trousers.
      var slot = find.byKey(const ValueKey("characterSlot"));
      await tester.ensureVisible(slot);
      tester.widget<CanvasDropdown<GarmentSlot>>(slot).onChanged(GarmentSlot.full);
      await tester.pumpAndSettle();
      await tap(tester, "characterGarment-dress");
      var kinds = get(c).dna.wardrobe.map((g) => g.kind).toList();
      expect(kinds, contains(GarmentKind.dress));
      expect(kinds, isNot(contains(GarmentKind.hoodie)));
      expect(kinds, isNot(contains(GarmentKind.trousers)));
      expect(find.byKey(const ValueKey("characterGarmentEditor")), findsOneWidget,
          reason: "what was put on is picked");
      await tap(tester, "characterCondition-Worn out");
      var dress = get(c).dna.wardrobe.firstWhere((g) => g.kind == GarmentKind.dress);
      expect(dress.condition.rips, greaterThan(0));
      await tap(tester, "characterGarmentLength-more");
      expect(get(c).dna.wardrobe.firstWhere((g) => g.kind == GarmentKind.dress).length,
          closeTo(0.6, 1e-9));
      await tap(tester, "characterCostume-Pirate");
      expect(get(c).dna.wardrobe.map((g) => g.kind), contains(GarmentKind.scarf));
      await tap(tester, "characterBareView");
      expect(get(c).bareView, isTrue);
      await tap(tester, "characterWornOff-0");
      expect(get(c).dna.wardrobe.first.kind, isNot(GarmentKind.briefs));

      // Appearance: a body type, the size, and a slider.
      await tap(tester, "appearanceTab-body");
      await tap(tester, "appearancePreset-body-Curvy");
      expect(get(c).dna.look[Look.hips], 0.8);
      var heads = find.byKey(const ValueKey("characterHeads"));
      await tester.ensureVisible(heads);
      tester.widget<CanvasSlider>(heads).onChanged(6);
      tester.widget<CanvasSlider>(heads).onCommit?.call();
      await tester.pumpAndSettle();
      expect(get(c).dna.headsTall, 6);
      await tap(tester, "appearanceTab-eyes");
      var eyes = find.byKey(const ValueKey("appearance-eyeSize"));
      await tester.ensureVisible(eyes);
      tester.widget<CanvasSlider>(eyes).onChanged(40);
      tester.widget<CanvasSlider>(eyes).onCommit?.call();
      await tester.pumpAndSettle();
      expect(get(c).dna.look[Look.eyeSize], closeTo(0.4, 1e-9));

      // A family, then a style within it.
      await tap(tester, "characterStyleFamily-anime");
      expect(get(c).style.family, StyleFamily.anime);
      await tap(tester, "characterStyle-shojo");
      expect(get(c).style, CharacterStyle.shojo);
      await tap(tester, "characterStyle-anime");
      expect(get(c).style, CharacterStyle.anime);
      await tap(tester, "characterSpecies-cat");
      expect(get(c).dna.species, Species.cat);
      expect(get(c).dna.hairStyle, HairStyle.bald, reason: "fur, not hair");
      await tap(tester, "characterFourLegs");
      expect(get(c).dna.fourLegs, isTrue);
      await tap(tester, "characterFourLegs");

      await tap(tester, "characterFeeling-Angry");
      expect(get(c).face[FaceControl.browSqueeze], 1);
      await tap(tester, "characterMouth-pucker");
      expect(get(c).face.mouth, MouthShape.pucker);
      await tap(tester, "characterFace-turn-more");
      expect(get(c).face[FaceControl.turn], 5);
      await tap(tester, "characterBlink");
      expect(get(c).life.blink, isFalse);
      var mixWith = find.byKey(const ValueKey("characterMixWith"));
      await tester.ensureVisible(mixWith);
      tester.widget<CanvasDropdown<int>>(mixWith).onChanged(1);
      await tester.pumpAndSettle();
      await tap(tester, "characterMix");
      expect(get(c).face[FaceControl.smile], closeTo(-0.6 + 1.4 * 0.4, 1e-9),
          reason: "40% of the way from angry to happy");

      c.frame = 12;
      await tester.pumpAndSettle();
      await tap(tester, "characterKey");
      expect(get(c).posedOnTimeline, isTrue);
      expect(find.byKey(const ValueKey("characterUnkey")), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    CanvasController voiced() {
      var voice = AudioElement(const ElementBase(id: "v", name: "Voice"),
          clip: const MediaClip(
              timed: true,
              playlist: [MediaSource(assetId: "a1", length: 4)]));
      return CanvasController(CanvasDocument(frames: 96, words: const [
        SpokenWord(text: "hello", frame: 10, end: 22, from: "voice:v"),
        SpokenWord(text: "mom", frame: 40, end: 48, from: "voice:v"),
      ]).addElement(voice).addElement(juno()));
    }

    testWidgets("the panel adds a motion and walks across",
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(CanvasDocument(frames: 200).addElement(juno()));
      addTearDown(c.dispose);
      c.selectOnly("c");
      tester.view.physicalSize = const Size(900, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(c));
      await tester.pumpAndSettle();
      await tap(tester, "characterMotion-wave");
      expect(get(c).motions.single.kind, MotionKind.wave);
      var id = get(c).motions.single.id;
      await tap(tester, "characterClipSpeed-$id-more");
      expect(get(c).motions.single.speed, closeTo(1.1, 1e-9));
      await tap(tester, "characterClipRemove-$id");
      expect(get(c).motions, isEmpty);
      await tap(tester, "characterWalkRight");
      expect(get(c).motions.single.kind, MotionKind.walk);
      c.undo();
      expect(get(c).motions, isEmpty, reason: "one undo step");

      expect(find.byKey(const ValueKey("characterImportBvh")), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets("the panel lip syncs from the voice and clears again",
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = voiced();
      addTearDown(c.dispose);
      c.selectOnly("c");
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(c));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("characterLipVoice")), findsOneWidget);
      await tester.runAsync(() => tap(tester, "characterLipSync"));
      await tester.pumpAndSettle();
      expect(get(c).mouthKeys, isNotEmpty);
      expect(find.textContaining("mouths laid down"), findsOneWidget);
      await tap(tester, "characterLipClear");
      expect(get(c).mouthKeys, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets("the mouth lane goes to a mouth, and moves one",
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = voiced();
      addTearDown(c.dispose);
      await c.lipSync(get(c), c.document.elementById("v") as AudioElement,
          feel: const LipSyncFeel(lead: 0));
      c.selectOnly("c");
      const width = 760.0;
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                        width: width,
                        child: ListenableBuilder(
                            listenable: c,
                            builder: (context, _) => CharacterMouthLane(
                                controller: c,
                                view: const TimelineView(0, 96))))))),
      ));
      await tester.pumpAndSettle();
      var lane = find.byKey(const ValueKey("characterMouthLane"));
      expect(lane, findsOneWidget);
      var left = tester.getTopLeft(lane) + Offset(c.headerWidth, 11);
      var across = width - c.headerWidth;
      Offset at(num frame) => left + Offset(across * frame / 96, 0);

      await tester.tapAt(at(40.4));
      await tester.pumpAndSettle();
      expect(c.frame, 40, reason: "the block's start");

      var before = get(c).mouthKeys.map((k) => k.frame).toList();
      // The last mouth, which has room after it.
      var start = before.last;
      await tester.dragFrom(at(start), Offset(across * 4.0 / 96, 0));
      await tester.pumpAndSettle();
      var after = get(c).mouthKeys.map((k) => k.frame).toList();
      expect(after.last, start + 4);
      expect(after.sublist(0, after.length - 1),
          before.sublist(0, before.length - 1));
      c.undo();
      expect(get(c).mouthKeys.map((k) => k.frame).toList(), before);
    });

    testWidgets("a pin dragged on the stage bends the arm, in one undo",
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(const CanvasDocument().addElement(juno()));
      addTearDown(c.dispose);
      c.selectOnly("c");
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(c, stage: true));
      await tester.pumpAndSettle();
      var view =
          tester.state<CanvasStageState>(find.byKey(const ValueKey("stage")));
      var page = view.pageRect;
      var scale = page.width / c.document.size.size.width;
      Offset onScreen(Offset doc) =>
          tester.getTopLeft(find.byKey(const ValueKey("stage"))) +
          page.topLeft +
          doc * scale;

      var before = get(c);
      var hand = CharacterPlacement.of(before, 0).pin(CharacterPin.handR);
      var to = hand + const Offset(20, -120);
      await tester.dragFrom(onScreen(hand), onScreen(to) - onScreen(hand));
      await tester.pumpAndSettle();

      var after = get(c);
      expect(after.bounds, before.bounds, reason: "posed, not moved");
      expectNear(CharacterPlacement.of(after, 0).pin(CharacterPin.handR), to,
          2 / scale);
      c.undo();
      expect(get(c).pose[CharacterBone.upperArmR],
          before.pose[CharacterBone.upperArmR]);
      expect(tester.takeException(), isNull);
    });
  });
}
