import 'dart:convert';
import 'dart:ui';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_anchor_test.dart is an element's anchor point: what its animation
// turns and grows about, what stays put when it is turned, how it is kept,
// and its three buttons and its handle on the stage.

/// square is a 40-wide black square at (100, 100), its anchor at [ax], [ay].
ShapeElement square(
        {double ax = 0.5,
        double ay = 0.5,
        double rotation = 0,
        ElementTrack? track}) =>
    ShapeElement(
      ElementBase(
          id: "s",
          x: 100,
          y: 100,
          width: 40,
          height: 40,
          rotation: rotation,
          anchorX: ax,
          anchorY: ay,
          track: track),
      fill: const Color(0xFF000000),
    );

Future<List<int>> draw(CanvasElement e, int frame) async {
  var rec = PictureRecorder();
  paintElement(Canvas(rec), e, frame);
  var img = await rec.endRecording().toImage(300, 300);
  return (await img.toByteData())!.buffer.asUint8List();
}

/// inked is the box of everything drawn in [px].
Rect inked(List<int> px) {
  var l = 300, t = 300, r = -1, b = -1;
  for (var y = 0; y < 300; y++) {
    for (var x = 0; x < 300; x++) {
      if (px[(y * 300 + x) * 4 + 3] > 128) {
        if (x < l) l = x;
        if (x > r) r = x;
        if (y < t) t = y;
        if (y > b) b = y;
      }
    }
  }
  return Rect.fromLTRB(l.toDouble(), t.toDouble(), r + 1.0, b + 1.0);
}

void main() {
  group("what the anchor does", () {
    test("kept with the element, and centred unless moved", () {
      var e = square(ax: 0, ay: 1).withBase(anchorLocked: true);
      var back = elementFromJson(
          jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>);
      expect(back.base.anchorX, 0);
      expect(back.base.anchorY, 1);
      expect(back.base.anchorLocked, isTrue);
      expect(square().anchorCentred, isTrue);
      expect(square().toJson().containsKey("ax"), isFalse);
    });

    test("a keyframe grows it about its anchor", () async {
      var track = ElementTrack(const [
        Keyframe(frame: 0, scale: 2),
      ]);
      var centred = inked(await draw(square(track: track), 0));
      expect(centred, const Rect.fromLTRB(80, 80, 160, 160));
      var cornered = inked(await draw(square(ax: 0, ay: 0, track: track), 0));
      expect(cornered, const Rect.fromLTRB(100, 100, 180, 180),
          reason: "the top-left corner stays where it is");
      expect(square(ax: 0, ay: 0, track: track).boundsAt(0),
          const Rect.fromLTRB(100, 100, 180, 180));
    });

    test("a keyframe turns it about its anchor", () async {
      var track = ElementTrack(const [Keyframe(frame: 0, rotate: 180)]);
      // Half a turn about its top-left corner: up and to the left of it.
      var turned = inked(await draw(square(ax: 0, ay: 0, track: track), 0));
      expect(turned.left, closeTo(60, 1));
      expect(turned.top, closeTo(60, 1));
      expect(turned.right, closeTo(100, 1));
    });

    test("turning it leaves the anchor where it is on the page", () {
      var e = square(ax: 0, ay: 0);
      var before = e.anchorAt(0);
      var turned = e.turnedTo(90);
      expect(turned.rotation, 90);
      expect((turned.anchorAt(0) - before).distance, lessThan(1e-9));
      expect(turned.bounds, isNot(e.bounds), reason: "moved to keep it");
      expect(square().turnedTo(90).bounds, square().bounds,
          reason: "centred: a plain turn");
    });

    test("moved to a point on the page, through its turn", () {
      var e = square(rotation: 90);
      var moved = e.withAnchorAt(const Offset(140, 140), 0);
      expect((moved.anchorAt(0) - const Offset(140, 140)).distance,
          lessThan(1e-9));
      expect(moved.bounds, e.bounds, reason: "the element stays put");
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

    testWidgets("shown, it can be locked and put back in the middle",
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(
          const CanvasDocument().addElement(square(ax: 0.1, ay: 0.2)));
      addTearDown(c.dispose);
      c.selectOnly("s");
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(c));
      await tester.pumpAndSettle();
      CanvasElement now() => c.document.elementById("s")!;
      var show = find.byKey(const ValueKey("elementAnchorShow"));
      var lock = find.byKey(const ValueKey("elementAnchorLock"));
      var reset = find.byKey(const ValueKey("elementAnchorReset"));

      expect(show, findsOneWidget);
      expect(lock, findsNothing, reason: "hidden: nothing to lock");
      expect(reset, findsNothing);
      await tester.tap(show);
      await tester.pumpAndSettle();
      expect(c.anchorShown("s"), isTrue);
      expect(lock, findsOneWidget);
      expect(reset, findsOneWidget);

      await tester.tap(lock);
      await tester.pumpAndSettle();
      expect(now().base.anchorLocked, isTrue);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(now().anchorCentred, isTrue);
      c.undo();
      expect(now().base.anchorX, 0.1, reason: "undoable");

      await tester.tap(show);
      await tester.pumpAndSettle();
      expect(c.anchorShown("s"), isFalse);
      expect(lock, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets("shown and unlocked, it is dragged on the stage",
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(const CanvasDocument().addElement(square()));
      addTearDown(c.dispose);
      c.selectOnly("s");
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(c, stage: true));
      await tester.pumpAndSettle();
      CanvasElement now() => c.document.elementById("s")!;
      var view =
          tester.state<CanvasStageState>(find.byKey(const ValueKey("stage")));
      Offset onScreen(Offset doc) {
        var page = view.pageRect;
        var scale = page.width / c.document.size.size.width;
        return tester.getTopLeft(find.byKey(const ValueKey("stage"))) +
            page.topLeft +
            doc * scale;
      }

      var from = onScreen(now().anchorAt(0));
      var to = onScreen(const Offset(100, 100));

      // Hidden: a drag there moves the element.
      await tester.dragFrom(from, to - from);
      await tester.pumpAndSettle();
      expect(now().anchorCentred, isTrue);
      expect(now().bounds.topLeft, isNot(const Offset(100, 100)));
      c.undo();
      await tester.pumpAndSettle();

      // Shown: it moves the anchor, and not the element.
      c.showAnchor("s", true);
      await tester.pumpAndSettle();
      await tester.dragFrom(from, to - from);
      await tester.pumpAndSettle();
      expect(now().base.anchorX, closeTo(0, 0.1));
      expect(now().base.anchorY, closeTo(0, 0.1));
      expect(now().bounds.topLeft, const Offset(100, 100));
      c.undo();
      expect(now().anchorCentred, isTrue, reason: "one undo step");

      // Locked: it stays.
      c.replaceElement(now().withBase(anchorLocked: true));
      await tester.pumpAndSettle();
      await tester.dragFrom(from, to - from);
      await tester.pumpAndSettle();
      expect(now().anchorCentred, isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}
