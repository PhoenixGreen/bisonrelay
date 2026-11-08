import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/render/motion_pose.dart';
import 'package:bruig/plugin_system/canvas/ui/animation_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart'
    show DeviceKnob;
import 'package:bruig/plugin_system/canvas/ui/motion_cards.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_motion_place_test.dart is the prototype's Place card: where a clip
// comes from (or, leaving, goes to) -- an edge of the page, beside another
// element, on its ground -- worked out as it plays, and an Offset from it.

const _self = Rect.fromLTWH(100, 100, 50, 50);
const _other = Rect.fromLTWH(400, 300, 80, 40);
final _scene = MotionScene(
    page: const Size(800, 600), boundsOf: (id) => id == "o" ? _other : null);

double? _x(MotionClip c, double t) =>
    sampleProp(c, MotionProp.x, t, _self, _scene);
double? _y(MotionClip c, double t) =>
    sampleProp(c, MotionProp.y, t, _self, _scene);

void main() {
  group("the places", () {
    test("from off the left edge, to where it is", () {
      var c = withPlace(
          MotionClip.ofKind("a", MotionKind.arrive).copyWith(length: 1),
          MotionPlaceKind.offLeft,
          _self);
      expect(_x(c, 0), -_self.right - 14, reason: "wholly out of sight");
      expect(_x(c, 1), 0, reason: "and where it is set");
      expect(c.keys[MotionProp.y], isNull, reason: "an edge moves one way");
      expect(placeOf(c)?.kind, MotionPlaceKind.offLeft);
    });

    test("leaving, the place is where it goes", () {
      var c = withPlace(
          MotionClip.ofKind("l", MotionKind.leave).copyWith(length: 1),
          MotionPlaceKind.offBottom,
          _self);
      expect(_y(c, 0), 0);
      expect(_y(c, 1), 600 - _self.top + 14);
    });

    test("on another's ground, and some way on from it", () {
      var c = withPlace(
          MotionClip.ofKind("a", MotionKind.arrive).copyWith(length: 1),
          MotionPlaceKind.ground,
          _self,
          target: "o",
          by: 30);
      expect(_x(c, 0), _other.center.dx - _self.center.dx + 30,
          reason: "the Offset, across");
      expect(_y(c, 0), _other.bottom - _self.bottom, reason: "bottoms level");
    });

    test("an Offset above the page is up and down", () {
      var c = withPlace(
          MotionClip.ofKind("a", MotionKind.arrive).copyWith(length: 1),
          MotionPlaceKind.offTop,
          _self,
          by: -20);
      expect(_y(c, 0), -_self.bottom - 14 - 20);
    });

    test("put back where it is, and kept with its offset", () {
      var c = withPlace(
          MotionClip.ofKind("a", MotionKind.arrive).copyWith(length: 1),
          MotionPlaceKind.offRight,
          _self,
          by: 12);
      var back = MotionClip.fromJson(c.toJson())!;
      expect(
          placeOf(back), const MotionPlace(MotionPlaceKind.offRight, by: 12));
      var still = withPlace(c, null, _self);
      expect(placeOf(still), isNull);
      expect(_x(still, 0), 0);
    });
  });

  for (var scale in [1.0, 1.5]) {
    testWidgets("the Place card sets From, Of and Offset, at $scale",
        (tester) async {
      tester.view.physicalSize = const Size(3000, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var c =
          CanvasController(CanvasDocument(frames: 96, frameRate: 24, elements: [
        ShapeElement(
            const ElementBase(id: "s", x: 100, y: 100, width: 50, height: 50)),
        ShapeElement(const ElementBase(
            id: "o", name: "Rock", x: 400, y: 300, width: 80, height: 40)),
      ]));
      addTearDown(c.dispose);
      var id = c.newClip("s", kind: MotionKind.arrive, slot: 0);
      c.pickMotion("s", id);
      c.selectOnly("s");
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ],
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: Scaffold(
                body: ListenableBuilder(
                    listenable: c,
                    builder: (context, _) =>
                        AnimationPanel(controller: c, height: 400)))),
      ));
      await tester.pumpAndSettle();
      MotionClip clip() => c.motionOf("s").clip(id)!;
      tester
          .widget<StudioDrop<String>>(
              find.byKey(const ValueKey("animPlaceFrom")))
          .onChanged(MotionPlaceKind.beside.name);
      await tester.pumpAndSettle();
      expect(placeOf(clip()),
          const MotionPlace(MotionPlaceKind.beside, target: "o"),
          reason: "beside the only other one, to start with");
      var of = tester.widget<StudioDrop<String>>(
          find.byKey(const ValueKey("animPlaceOf")));
      expect(of.options.map((o) => o.$2), contains("Rock"));
      tester
          .widget<DeviceKnob>(find.byKey(const ValueKey("animPlaceOffset")))
          .onChanged(40);
      await tester.pumpAndSettle();
      expect(placeOf(clip())?.by, 40);
      tester
          .widget<StudioDrop<String>>(
              find.byKey(const ValueKey("animPlaceFrom")))
          .onChanged("");
      await tester.pumpAndSettle();
      expect(placeOf(clip()), isNull, reason: "where it is again");
      expect(find.byKey(const ValueKey("animPlaceOffset")), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
