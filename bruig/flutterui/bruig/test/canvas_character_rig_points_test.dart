import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/character_rig_editor.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_character_rig_points_test.dart is a sketch's limbs reshaped point
// by point: a point moved bends the limb, its ring thickens or thins it to
// nothing, its knob turns it, a line taken hold of has a point put on it,
// and Delete takes a point away -- or puts a joint back.

CharacterElement _sketch() => CharacterElement(
    const ElementBase(id: "c", x: 100, y: 40, width: 160, height: 340),
    dna: characterCast.first.dna);

const _scale = 2.0;

Future<List<int>> _pixels(CharacterElement e) async {
  var rec = PictureRecorder();
  paintElement(Canvas(rec), e, 0);
  var img = await rec.endRecording().toImage(400, 420);
  return (await img.toByteData())!.buffer.asUint8List();
}

void main() {
  RigPoint pointOf(CharacterElement e, CharacterLimb limb, RigPoint spot) =>
      e.dna.rigPoints.of(limb.name).firstWhere((p) => p.sameSpot(spot));

  test("the middle of the elbow moved moves the elbow, in the bone's measure",
      () {
    var e = _sketch();
    var view = RigView.of(e, 0);
    var elbow = view.limbs[CharacterLimb.armR]![1];
    var at = view.placed.toPage(elbow.at);
    var hold = view.under(at, _scale, 4)!;
    expect(hold.grab, RigGrab.centre);
    expect(hold.point.sameSpot(RigPoint.middle), isTrue);
    var to = at + elbow.across * 10;
    var next = rigDragged(e, hold, at, to, 0, _scale);
    var moved = RigView.of(next, 0).limbs[CharacterLimb.armR]![1];
    expect((view.placed.toPage(moved.at) - to).distance, lessThan(0.01));
    expect(pointOf(next, CharacterLimb.armR, RigPoint.middle).across,
        greaterThan(0));
    // And it goes with the arm when the arm is posed.
    var raised =
        next.copyWith(pose: next.pose.withAngle(CharacterBone.upperArmR, -100));
    var r = RigView.of(raised, 0).limbs[CharacterLimb.armR]![1];
    expect(
        (r.at - r.on).distance, closeTo((moved.at - moved.on).distance, 0.01));
  });

  test("the ring pulled in thins the limb to nothing; out, thickens it",
      () async {
    var e = _sketch();
    var view = RigView.of(e, 0);
    var knee = view.limbs[CharacterLimb.legL]![1];
    var r = view.ring(CharacterLimb.legL, knee, _scale);
    var edge = view.placed.toPage(knee.at + knee.dir * r);
    var hold = view.under(edge, _scale, 3)!;
    expect(hold.grab, RigGrab.ring);
    var centre = view.placed.toPage(knee.at);
    var thin =
        rigDragged(e, hold, edge, centre + (edge - centre) * 0.01, 0, _scale);
    expect(pointOf(thin, CharacterLimb.legL, RigPoint.middle).scale, 0);
    var thick =
        rigDragged(e, hold, edge, centre + (edge - centre) * 1.5, 0, _scale);
    expect(pointOf(thick, CharacterLimb.legL, RigPoint.middle).scale,
        closeTo(1.5, 0.01));
    expect(await _pixels(thick), isNot(await _pixels(e)),
        reason: "drawn thicker");
  });

  test("the knob turned turns it", () {
    var e = _sketch();
    var view = RigView.of(e, 0);
    var wrist = view.limbs[CharacterLimb.armL]!.last;
    var k = view.placed.toPage(view.knob(CharacterLimb.armL, wrist, _scale));
    var hold = view.under(k, _scale, 3)!;
    expect(hold.grab, RigGrab.knob);
    var c = view.placed.toPage(wrist.at);
    var d = k - c;
    // A quarter turn round the point.
    var next = rigDragged(e, hold, k, c + Offset(-d.dy, d.dx), 0, _scale);
    expect(
        pointOf(next, CharacterLimb.armL, RigPoint.end).turn, closeTo(90, 0.5));
  });

  test("a line taken hold of has a point put on it, and is bent by it",
      () async {
    var e = _sketch();
    var view = RigView.of(e, 0);
    var pts = view.limbs[CharacterLimb.legR]!;
    var mid = view.placed.toPage(Offset.lerp(pts[1].at, pts[2].at, 0.5)!);
    var hold = view.under(mid, _scale, 3)!;
    expect(hold.added, isTrue);
    expect(hold.point.bone, 1);
    expect(hold.point.f, closeTo(0.5, 0.05));
    var next = rigDragged(e, hold, mid, mid + const Offset(12, 0), 0, _scale);
    var after = next.dna.rigPoints.of(CharacterLimb.legR.name);
    expect(after.length, 4, reason: "three joints and the point put on");
    expect(await _pixels(next), isNot(await _pixels(e)),
        reason: "the shin is bent");
    // Taken away, the leg is as it was.
    var back = withoutRigPoint(next, CharacterLimb.legR, hold.point);
    expect(back.dna.rigPoints.of(CharacterLimb.legR.name).length, 3);
    expect(await _pixels(back), await _pixels(e));
  });

  test("mirrored: the other arm's elbow goes the mirror of the way", () {
    var e = _sketch();
    var view = RigView.of(e, 0);
    var elbow = view.limbs[CharacterLimb.armR]![1];
    var at = view.placed.toPage(elbow.at);
    var hold = view.under(at, _scale, 4)!;
    var next = rigDragged(e, hold, at, at + const Offset(7, -3), 0, _scale, mirror: true);
    var after = RigView.of(next, 0);
    Offset moved(CharacterLimb l) {
      var before = view.limbs[l]![1], now = after.limbs[l]![1];
      return after.placed.toPage(now.at) - view.placed.toPage(before.at);
    }

    var r = moved(CharacterLimb.armR), l = moved(CharacterLimb.armL);
    expect(r.dx, closeTo(7, 0.01));
    expect(l.dx, closeTo(-7, 0.05), reason: "across the other way");
    expect(l.dy, closeTo(-3, 0.05), reason: "up the same");
    // Taken away, from both.
    var back = withoutRigPoint(next, CharacterLimb.armR, RigPoint.middle, mirror: true);
    expect(back.dna.rigPoints.isEmpty, isTrue);
    // Unmirrored, the other arm is left alone.
    var one = rigDragged(e, hold, at, at + const Offset(7, -3), 0, _scale);
    expect(one.dna.rigPoints.edited("armL"), isFalse);
  });

  test("a joint is put back, not taken away", () {
    var e = withRigPoint(
        _sketch(), CharacterLimb.armL, RigPoint.middle.copyWith(scale: 0.5));
    var back = withoutRigPoint(e, CharacterLimb.armL, RigPoint.middle);
    expect(back.dna.rigPoints.isEmpty, isTrue);
    expect(back.dna.rigPoints.of(CharacterLimb.armL.name).length, 3);
  });

  test("kept in the saved canvas, and the same on every panel", () {
    var e = withRigPoint(
        withRigPoint(
            _sketch(), CharacterLimb.armR, const RigPoint(1, 0.4, across: 0.3)),
        CharacterLimb.legL,
        RigPoint.end.copyWith(turn: 20, scale: 0.7));
    var back = elementFromJson(e.toJson()) as CharacterElement;
    expect(back.dna.rigPoints, e.dna.rigPoints);
    var turned = back.copyWith(pose: back.pose.withTurn(90));
    expect(turned.dna.rigPoints, e.dna.rigPoints);
  });

  group("on the stage", () {
    Future<(CanvasController, Offset Function(Offset), double)> stage(
        WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(const CanvasDocument().addElement(_sketch()));
      addTearDown(c.dispose);
      c.selectOnly("c");
      c.editRig = true;
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(
              create: (c) => CanvasPreferences()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: CanvasStage(key: const ValueKey("stage"), controller: c))),
      ));
      await tester.pumpAndSettle();
      var view = tester.state<CanvasStageState>(find.byKey(const ValueKey("stage")));
      var page = view.pageRect;
      var scale = page.width / c.document.size.size.width;
      return (
        c,
        (Offset doc) =>
            tester.getTopLeft(find.byKey(const ValueKey("stage"))) +
            page.topLeft +
            doc * scale,
        scale
      );
    }

    CharacterElement get(CanvasController c) =>
        c.document.elementById("c")! as CharacterElement;

    testWidgets("an elbow dragged bends the arm, in one undo, and stays selected",
        (tester) async {
      var (c, onScreen, _) = await stage(tester);
      var view = RigView.of(get(c), 0);
      var elbow = view.placed.toPage(view.limbs[CharacterLimb.armR]![1].at);
      await tester.dragFrom(onScreen(elbow), const Offset(16, 0));
      await tester.pumpAndSettle();
      var p = pointOf(get(c), CharacterLimb.armR, RigPoint.middle);
      expect(p.isRest, isFalse);
      expect(get(c).bounds, _sketch().bounds, reason: "reshaped, not moved");
      expect(c.selection, {"c"});
      expect(c.rigPick?.$2.sameSpot(RigPoint.middle), isTrue);
      c.undo();
      expect(get(c).dna.rigPoints.isEmpty, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets("a click on a line puts a point there; Delete takes it away",
        (tester) async {
      var (c, onScreen, _) = await stage(tester);
      var view = RigView.of(get(c), 0);
      var pts = view.limbs[CharacterLimb.legL]!;
      var mid = view.placed.toPage(Offset.lerp(pts[0].at, pts[1].at, 0.5)!);
      await tester.tapAt(onScreen(mid));
      await tester.pumpAndSettle();
      expect(get(c).dna.rigPoints.of("legL").length, 4);
      c.deleteSelected();
      await tester.pump();
      expect(get(c).dna.rigPoints.of("legL").length, 3);
      expect(c.document.elementById("c"), isNotNull, reason: "the point, not the character");
    });

    testWidgets("put away, the points are not taken hold of", (tester) async {
      var (c, onScreen, _) = await stage(tester);
      c.editRig = false;
      await tester.pump();
      var view = RigView.of(get(c), 0);
      var knee = view.placed.toPage(view.limbs[CharacterLimb.legR]![1].at);
      await tester.dragFrom(onScreen(knee), const Offset(0, 1));
      await tester.pumpAndSettle();
      expect(get(c).dna.rigPoints.isEmpty, isTrue);
    });
  });
}
