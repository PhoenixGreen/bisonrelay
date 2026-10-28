import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/character_doll_pose.dart';
import 'package:bruig/plugin_system/canvas/ui/character_puppet.dart';
import 'package:bruig/plugin_system/canvas/ui/stage_painter.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_character_doll_pose_test.dart is the doll posed joint by joint:
// a joint dragged by the bone above it, the rings round a picked joint --
// bend in the picture, swing towards the reader -- and fingers curled by
// their tips. See character_doll_pose.dart.

CharacterElement _empty() => CharacterElement(
    const ElementBase(id: "c", x: 300, y: 60, width: 200, height: 420),
    dna: CharacterType.empty.dna);

double _gap(double a, double b) => math.atan2(math.sin(a - b), math.cos(a - b)).abs();

void main() {
  test("bent: the bone points where it is asked", () {
    var e = _empty();
    var placed = CharacterPlacement.of(e, 0);
    for (var j in [DollJoint.shoulderL, DollJoint.elbowR, DollJoint.hipL, DollJoint.waist]) {
      var from = placed.dollJoint(j);
      // A quarter turn round from where it points now.
      var now = (placed.dollTip(j) - from).direction;
      var want = from + Offset.fromDirection(now + math.pi / 2 * 0.6, 60);
      var bent = e.copyWith(pose: placed.bentTo(j, want));
      var after = CharacterPlacement.of(bent, 0);
      var got = (after.dollTip(j) - after.dollJoint(j)).direction;
      expect(_gap(got, (want - from).direction), lessThan(0.06), reason: j.label);
    }
  });

  test("a joint dragged is brought there by the bone above it", () {
    var e = _empty();
    var placed = CharacterPlacement.of(e, 0);
    var elbow = placed.dollJoint(DollJoint.elbowL);
    var shoulder = placed.dollJoint(DollJoint.shoulderL);
    var want = shoulder + Offset.fromDirection((elbow - shoulder).direction - 0.8, 50);
    var moved = e.copyWith(pose: placed.movedTo(DollJoint.elbowL, want)!);
    var after = CharacterPlacement.of(moved, 0);
    expect(
        _gap((after.dollJoint(DollJoint.elbowL) - shoulder).direction, (want - shoulder).direction),
        lessThan(0.06));
    expect(placed.movedTo(DollJoint.waist, want), isNull, reason: "nothing above the waist turns it");
  });

  test("swung towards the reader, and a finger curled to its tip", () {
    var e = _empty();
    var placed = CharacterPlacement.of(e, 0);
    var swung = placed.swungBy(DollJoint.shoulderR, e.pose, 40);
    expect(swung.swing(CharacterBone.upperArmR), closeTo(e.pose.swing(CharacterBone.upperArmR) + 40, 1e-9));
    var tips = placed.fingerTips(CharacterLimb.armL);
    expect(tips, hasLength(5), reason: "four fingers and a thumb");
    var wrist = placed.dollJoint(DollJoint.wristL);
    var want = Offset.lerp(tips[1], wrist, 0.6)!;
    var curled = e.copyWith(pose: placed.curledTo(CharacterLimb.armL, 1, want));
    var after = CharacterPlacement.of(curled, 0).fingerTips(CharacterLimb.armL);
    expect((after[1] - want).distance, lessThan((tips[1] - want).distance),
        reason: "the middle finger's tip nearer");
    expect(curled.pose[CharacterBone.middleL], isNot(e.pose[CharacterBone.middleL]));
  });

  test("the rings round a joint", () {
    const c = Offset(100, 100);
    expect(dollRingUnder(c, 40, c + const Offset(40, 0), 5), DollRing.bend);
    expect(dollRingUnder(c, 40, c + const Offset(0, 40), 5), isNotNull);
    expect(dollRingUnder(c, 40, c + const Offset(18, 0), 5), DollRing.swing);
    expect(dollRingUnder(c, 40, c + const Offset(10, 10), 5), isNull);
  });

  group("on the stage", () {
    Future<(CanvasController, Offset Function(Offset))> stage(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(const CanvasDocument().addElement(_empty()));
      addTearDown(c.dispose);
      c.selectOnly("c");
      c.showPuppet = true;
      c.puppet3D = true;
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(create: (c) => CanvasPreferences()),
        ],
        child: MaterialApp(
            home: Scaffold(body: CanvasStage(key: const ValueKey("stage"), controller: c))),
      ));
      await tester.pumpAndSettle();
      var view = tester.state<CanvasStageState>(find.byKey(const ValueKey("stage")));
      var page = view.pageRect;
      var scale = page.width / c.document.size.size.width;
      return (
        c,
        (Offset doc) =>
            tester.getTopLeft(find.byKey(const ValueKey("stage"))) + page.topLeft + doc * scale
      );
    }

    CharacterElement get(CanvasController c) => c.document.elementById("c")! as CharacterElement;

    testWidgets("a joint clicked is picked; its ring bends it, in one undo", (tester) async {
      var (c, onScreen) = await stage(tester);
      var placed = CharacterPlacement.of(get(c), 0);
      var elbow = placed.dollJoint(DollJoint.elbowR);
      await tester.tapAt(onScreen(elbow));
      await tester.pumpAndSettle();
      expect(c.dollJoint, DollJoint.elbowR);
      var before = get(c).pose[CharacterBone.foreArmR];
      // Round the bend ring, a quarter of the way.
      var view = tester.state<CanvasStageState>(find.byKey(const ValueKey("stage")));
      var scale = view.pageRect.width / c.document.size.size.width;
      var r = dollRingRadius / scale;
      var g = await tester.startGesture(onScreen(elbow + Offset(r, 0)));
      for (var k = 1; k <= 8; k++) {
        var a = k / 8 * math.pi / 2;
        await g.moveTo(onScreen(elbow + Offset(r * math.cos(a), r * math.sin(a))));
        await tester.pump();
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(get(c).pose[CharacterBone.foreArmR], isNot(before));
      c.undo();
      expect(get(c).pose[CharacterBone.foreArmR], before, reason: "one undo");
      expect(tester.takeException(), isNull);
    });

    testWidgets("a joint dragged moves it", (tester) async {
      var (c, onScreen) = await stage(tester);
      var placed = CharacterPlacement.of(get(c), 0);
      var knee = placed.dollJoint(DollJoint.kneeL);
      var thigh = get(c).pose[CharacterBone.thighL];
      await tester.dragFrom(onScreen(knee), const Offset(-40, -30));
      await tester.pumpAndSettle();
      expect(get(c).pose[CharacterBone.thighL], isNot(thigh));
      expect(c.dollJoint, DollJoint.kneeL);
    });
  });
}
