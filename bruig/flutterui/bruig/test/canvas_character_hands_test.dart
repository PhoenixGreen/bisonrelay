import 'dart:ui' show Canvas, PictureRecorder, Rect;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_life.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_extremities.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_painter.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/character_puppet.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_character_hands_test.dart is a sketch's hands and feet: fingers
// that curl and spread, a wrist that bends and a palm that turns, picked
// from a hand chart; feet that point, toes that bend at the ball, and a
// body that rises on to its toes rather than push them through the floor.

CharacterElement _sketch([CharacterPose? pose, CharacterDna? dna]) => CharacterElement(
        const ElementBase(id: "c", x: 20, y: 20, width: 160, height: 340),
        dna: dna ?? characterCast.first.dna,
        views: CharacterView.all)
    .copyWith(pose: pose ?? CharacterElement.restPose);

const _box = Rect.fromLTWH(0, 0, 160, 340);

CharacterRig _rig(CharacterPose pose) =>
    CharacterRig.of(characterCast.first.dna, pose, _box);

/// _lowest is how far down the page the lowest of [rig]'s feet reaches.
double _lowest(CharacterRig rig) {
  var low = -double.infinity;
  for (var leg in [CharacterLimb.legL, CharacterLimb.legR]) {
    var s = footShape(rig, leg, rig.footSize());
    for (var p in [...s.heel, ...s.toes]) {
      low = low > rig.end(leg).dy + p.dy ? low : rig.end(leg).dy + p.dy;
    }
  }
  return low;
}

void main() {
  var rest = CharacterElement.restPose;
  HandShape shape(String name) => handShapes.firstWhere((s) => s.name == name);
  FootStance stance(String name) => footStances.firstWhere((s) => s.name == name);

  test("hands and feet are bones of the pose: saved, eased and mirrored", () {
    var fist = shape("Fist").on(rest, true);
    expect(handShapeName(fist, true), "Fist");
    expect(handShapeName(fist, false), "At rest");
    var back = CharacterPose.fromJson(fist.toJson());
    expect(handShapeName(back, true), "Fist");
    // Half way from open to a fist: every finger half curled.
    var half = rest.lerp(fist, 0.5);
    expect(half[CharacterBone.middleL], closeTo(fist[CharacterBone.middleL] / 2, 1e-9));
    // Fingers do not make two poses different poses -- see views of a pose.
    expect(rest.near(fist), isTrue);
    // A bone's partner, and what mirroring turns the other way.
    expect(CharacterBone.thumbL.partner, CharacterBone.thumbR);
    expect(CharacterBone.toesR.partner, CharacterBone.toesL);
    expect(CharacterBone.spine.partner, CharacterBone.spine);
    expect(CharacterBone.wristL.mirrors, isTrue);
    expect(CharacterBone.indexL.mirrors, isFalse);
    expect(CharacterBone.ankleL.mirrors, isFalse, reason: "turned out either side");
    var tiptoe = stance("Tiptoe").on(rest, true);
    expect(footStanceName(tiptoe, true), "Tiptoe");
    expect(footStanceName(tiptoe, false), "Flat");
  });

  test("a fist is shorter than an open hand; a palm turned shows another side", () {
    var open = _rig(rest);
    var fist = _rig(shape("Fist").on(rest, true));
    var r = open.handRadius;
    expect(handTip(fist, CharacterLimb.armL, r).distance,
        lessThan(handTip(open, CharacterLimb.armL, r).distance * 0.75));
    expect(handTip(fist, CharacterLimb.armR, r), handTip(open, CharacterLimb.armR, r),
        reason: "the other hand is left as it was");
    // A hand is a palm and every bone of every finger once they curl.
    expect(handPieces(fist, CharacterLimb.armL, r).length, 1 + 4 * 3 + 1 + 2);
    expect(handPieces(open, CharacterLimb.armL, r).length, 1 + 4 + 1 + 1,
        reason: "straight fingers are one piece each");
    // The palm turned to the reader: the thumb on the other side of it.
    var palm = _rig(rest.withAngle(CharacterBone.palmL, 135));
    double width(CharacterRig rig) {
      var xs = [for (var p in handPieces(rig, CharacterLimb.armL, r)) for (var q in p.outline) q.dx];
      return xs.reduce((a, b) => a > b ? a : b) - xs.reduce((a, b) => a < b ? a : b);
    }

    expect(width(palm), isNot(closeTo(width(open), 0.01)));
    // Spread wider than together.
    expect(width(_rig(shape("Open").on(rest, true))), greaterThan(width(open)));
  });

  test("a foot stays on the ground: on its toes the body rises", () {
    var flat = _rig(rest);
    expect(flat.planted, 0);
    var floor = _lowest(flat);
    for (var turn in [0.0, 90.0]) {
      var tiptoe = _rig(stance("Tiptoe").on(stance("Tiptoe").on(rest, true), false).withTurn(turn));
      expect(tiptoe.planted, greaterThan(0), reason: "turned $turn");
      expect(tiptoe.hips.dy, lessThan(_rig(rest.withTurn(turn)).hips.dy));
      expect(_lowest(tiptoe), closeTo(floor, 1), reason: "on the floor, not through it");
    }
    // Off the ground already, a pointed foot lifts nothing.
    var jump = rest.withLift(1);
    expect(_rig(stance("Pointed").on(jump, true)).planted, 0);
    // On the heel, the toes come up off the floor.
    var heel = _rig(stance("On the heel").on(rest, true).withTurn(90));
    var s = footShape(heel, CharacterLimb.legL, heel.footSize());
    var f = footShape(flat, CharacterLimb.legL, flat.footSize());
    expect(s.tip.dy, lessThan(f.tip.dy), reason: "toes raised");
    // Toes bent up at the ball.
    var toes = _rig(rest.withSwing(CharacterBone.toesL, 40).withTurn(90));
    expect(footShape(toes, CharacterLimb.legL, toes.footSize()).tip.dy,
        lessThan(footShape(_rig(rest.withTurn(90)), CharacterLimb.legL, flat.footSize()).tip.dy));
  });

  test("drawn: every hand shape, every stance, in every view, on its layers", () async {
    Future<List<int>> pixels(CharacterElement e) async {
      var rec = PictureRecorder();
      paintElement(Canvas(rec), e, 0);
      var img = await rec.endRecording().toImage(200, 380);
      return (await img.toByteData())!.buffer.asUint8List();
    }

    var plain = await pixels(_sketch());
    expect(await pixels(_sketch(shape("Fist").on(rest, true))), isNot(plain));
    expect(await pixels(_sketch(stance("Tiptoe").on(rest, true))), isNot(plain));
    for (var turn in [0.0, 45.0, 90.0, 135.0, 180.0]) {
      for (var s in handShapes) {
        await pixels(_sketch(s.on(rest, true).withTurn(turn)));
      }
      for (var s in footStances) {
        await pixels(_sketch(s.on(rest, false).withTurn(turn)));
      }
    }
    // Taken apart, the fingers are the hand's layer.
    var rig = _rig(shape("Peace").on(rest, true));
    var shapes = captureFigure(rig, characterCast.first.dna, const CharacterFace(),
        LifeAt.none, CharacterStyle.featureCartoon);
    expect(shapes.where((s) => s.layer == BodyLayer.handL.name), isNotEmpty);
    expect(shapes.where((s) => s.layer == BodyLayer.footL.name || s.layer == garmentLayer(0)),
        isNotEmpty);
  });

  test("the toes' pin points the foot", () {
    var e = _sketch(rest.withTurn(90));
    var placed = CharacterPlacement.of(e, 0);
    expect(placed.pins, contains(CharacterPin.toeL));
    var toe = placed.pin(CharacterPin.toeL);
    var ankle = placed.pin(CharacterPin.footL);
    // Dragged down and round below the ankle: pointed.
    var arm = toe - ankle;
    var down = ankle + Offset(arm.dx * 0.3, arm.distance);
    var posed = placed.posedBy(CharacterPin.toeL, down);
    expect(posed.swing(CharacterBone.ankleL), greaterThan(30));
    expect(posed.swing(CharacterBone.ankleR), 0, reason: "the other foot as it was");
    var after = CharacterPlacement.of(e.copyWith(pose: posed), 0);
    expect(after.rig.planted, greaterThan(0), reason: "up on its toes");
    // Seen from the front -- toes on -- dragged across, the foot turns;
    // pointed right down, dragged back up, it comes back up.
    var front = _sketch(rest);
    var fp = CharacterPlacement.of(front, 0);
    var t0 = fp.pin(CharacterPin.toeL), a0 = fp.pin(CharacterPin.footL);
    var aside = t0 + Offset(-(t0 - a0).distance * 1.5, 0);
    var across = fp.posedBy(CharacterPin.toeL, aside);
    expect(across[CharacterBone.ankleL].abs(), greaterThan(15), reason: "turned");
    expect(across.swing(CharacterBone.ankleL).abs(), lessThan(15), reason: "not pointed");
    var turned = CharacterPlacement.of(front.copyWith(pose: across), 0);
    expect((turned.pin(CharacterPin.toeL) - turned.pin(CharacterPin.footL) - (aside - a0)).distance,
        lessThan(0.3), reason: "the toes where they were dropped");
    var pointed = front.copyWith(pose: rest.withSwing(CharacterBone.ankleL, 85));
    var pp = CharacterPlacement.of(pointed, 0);
    var up = pp.posedBy(CharacterPin.toeL, pp.pin(CharacterPin.footL) + (t0 - a0));
    expect(up.swing(CharacterBone.ankleL), lessThan(20), reason: "not stuck pointing down");
    // No toes to point on four legs.
    var dog = characterCast.firstWhere((c) => c.dna.fourLegs);
    expect(CharacterPlacement.of(_sketch(rest, dog.dna), 0).pins, isNot(contains(CharacterPin.toeL)));
  });

  test("a hand goes where it is dragged, however the body is turned; the "
      "fingers' pin bends it at the wrist", () {
    for (var turn in [0.0, 30.0, 45.0, 60.0, 90.0]) {
      var e = _sketch(rest.withTurn(turn));
      var placed = CharacterPlacement.of(e, 0);
      var hand = placed.pin(CharacterPin.handL);
      var shoulder = placed.toPage(placed.rig.shoulderL);
      // Out from the body and up, within reach.
      var to = shoulder + (hand - shoulder) * 0.5 + const Offset(-25, -10);
      var posed = placed.posedBy(CharacterPin.handL, to);
      var after = CharacterPlacement.of(e.copyWith(pose: posed), 0);
      expect((after.pin(CharacterPin.handL) - to).distance, lessThan(1.5),
          reason: "turned $turn");
    }
    var e = _sketch(rest);
    var placed = CharacterPlacement.of(e, 0);
    expect(placed.pins, contains(CharacterPin.fingersL));
    var wrist = placed.pin(CharacterPin.handL), tips = placed.pin(CharacterPin.fingersL);
    var arm = tips - wrist;
    var to = wrist + Offset(arm.dx * 0.5 - arm.distance * 0.8, arm.dy * 0.6);
    var bent = placed.posedBy(CharacterPin.fingersL, to);
    expect(bent[CharacterBone.wristL].abs(), greaterThan(10));
    var after = CharacterPlacement.of(e.copyWith(pose: bent), 0);
    expect(after.pin(CharacterPin.handL), wrist, reason: "the arm where it was");
    var dog = characterCast.firstWhere((c) => c.dna.fourLegs);
    expect(CharacterPlacement.of(_sketch(rest, dog.dna), 0).pins,
        isNot(contains(CharacterPin.fingersL)), reason: "a paw has no fingers to bend");
  });

  group("in the hand and foot layers' settings", () {
    setUpAll(() => CanvasSection.openAll = true);
    tearDownAll(() => CanvasSection.openAll = false);

    Future<CanvasController> open(WidgetTester tester, BodyLayer layer) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(CanvasDocument(frames: 24).addElement(_sketch()));
      addTearDown(c.dispose);
      c.selectOnly("c");
      c.pickCharacterLayer(layer.name);
      tester.view.physicalSize = const Size(900, 14000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(create: (c) => CanvasPreferences()),
        ],
        child: MaterialApp(
            home: Scaffold(body: SizedBox(width: 420, child: CanvasDesignPanel(controller: c)))),
      ));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets("a hand picked from the chart, a finger curled, both hands or one",
        (tester) async {
      var c = await open(tester, BodyLayer.handR);
      CharacterPose pose() => (c.document.elementById("c") as CharacterElement).pose;
      expect(c.mirrorEdits, isTrue);
      tester.widget<CanvasDropdown<String>>(find.byKey(const ValueKey("characterHandShapePick")))
          .onChanged("Point");
      await tester.pumpAndSettle();
      expect(handShapeName(pose(), false), "Point");
      expect(handShapeName(pose(), true), "Point", reason: "both hands, mirrored");
      var curl = tester.widget<CanvasSlider>(find.byKey(const ValueKey("characterFinger-pointerR")));
      curl.onChanged(40);
      curl.onCommit!();
      await tester.pumpAndSettle();
      expect(pose()[CharacterBone.indexR], 40);
      expect(pose()[CharacterBone.indexL], 40);
      expect(handShapeName(pose(), false), isNull);
      // A wrist bent one way bends the other the other way.
      var bend = tester.widget<CanvasSlider>(find.byKey(const ValueKey("characterWristBendR")));
      bend.onChanged(20);
      bend.onCommit!();
      await tester.pumpAndSettle();
      expect(pose()[CharacterBone.wristR], 20);
      expect(pose()[CharacterBone.wristL], -20);
      // One hand only.
      c.mirrorEdits = false;
      await tester.pumpAndSettle();
      tester.widget<CanvasDropdown<String>>(find.byKey(const ValueKey("characterHandShapePick")))
          .onChanged("Fist");
      await tester.pumpAndSettle();
      expect(handShapeName(pose(), false), "Fist");
      expect(handShapeName(pose(), true), isNot("Fist"));
      c.undo();
      expect(handShapeName(pose(), false), isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets("a foot's stance, its toes, and keyed once it is animated", (tester) async {
      var c = await open(tester, BodyLayer.footL);
      CharacterElement get() => c.document.elementById("c") as CharacterElement;
      tester.widget<CanvasDropdown<String>>(find.byKey(const ValueKey("characterFootStancePick")))
          .onChanged("Tiptoe");
      await tester.pumpAndSettle();
      expect(footStanceName(get().pose, true), "Tiptoe");
      expect(footStanceName(get().pose, false), "Tiptoe");
      var toes = tester.widget<CanvasSlider>(find.byKey(const ValueKey("characterToesL")));
      toes.onChanged(20);
      toes.onCommit!();
      await tester.pumpAndSettle();
      expect(get().pose.swing(CharacterBone.toesL), 20);
      // Animated: on the frame looked at.
      c.keyCharacterPose(get());
      c.frame = 12;
      await tester.pumpAndSettle();
      tester.widget<CanvasDropdown<String>>(find.byKey(const ValueKey("characterFootStancePick")))
          .onChanged("Flat");
      await tester.pumpAndSettle();
      expect(footStanceName(get().poseAtFrame(12), true), "Flat");
      expect(get().poseAtFrame(0).swing(CharacterBone.ankleL), stance("Tiptoe").point);
      expect(tester.takeException(), isNull);
    });
  });
}
