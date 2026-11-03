import 'dart:math' as math;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_design.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/stage_spot.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_camera.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_settings_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/stage_gizmo.dart';
import 'package:bruig/plugin_system/canvas/ui/stage_nav_controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// The controls for a scene showing a 3D stage: the bar's 3D tools, Snap and
// the page lock; the stage camera's pan, framing and reset; the gizmo on an
// element standing on the stage; the view controls at its right; and the
// gestures and keys the page lock changes.

BackgroundElement stage({StageCamera camera = const StageCamera()}) =>
    BackgroundElement(
        const ElementBase(id: "st", x: 0, y: 0, width: 1280, height: 720),
        backdrop: BackdropKind.stage,
        stage: StageElement(const ElementBase(id: ""), camera: camera));

ShapeElement flat(String id, {StageSpot? spot}) => ShapeElement(ElementBase(
    id: id, name: id, x: 100, y: 50, width: 200, height: 400, spot: spot));

Character3dElement body(String id, {StageSpot? spot}) =>
    Character3dElement(ElementBase(id: id, width: 200, height: 400, spot: spot),
        design: CharacterDesign(
            id: "d", name: "Jess", body: "Vivi", updated: DateTime(2026)));

CanvasDocument onStage({StageSpot spot = const StageSpot("st")}) =>
    const CanvasDocument()
        .addElement(stage())
        .addElement(flat("a", spot: spot));

void near(Offset a, Offset b, [double within = 0.01]) =>
    expect((a - b).distance, lessThan(within), reason: "$a is not $b");

StageCamera cameraOf(CanvasController c) => c.steeredStage!.cameraAt(c.frame);

Widget host(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

Widget bar(CanvasController c, {VoidCallback? onGuides}) => host(Column(
      children: [
        CanvasSettingsBar(
          controller: c,
          onPublish: () {},
          canvasSettingsOpen: false,
          onToggleCanvasSettings: () {},
          guidesOpen: false,
          onToggleGuides: onGuides ?? () {},
          timelineOpen: false,
          onToggleTimeline: () {},
        ),
      ],
    ));

void main() {
  group("the stage camera's aim", () {
    test("pans what it looks at, and keeps it in the file", () {
      const cam = StageCamera(tx: 1.5, ty: -0.5, tz: 2);
      final back = StageCamera.fromJson(cam.toJson());
      expect((back.tx, back.ty, back.tz), (1.5, -0.5, 2));
      // An unpanned camera writes nothing new.
      expect(const StageCamera().toJson().containsKey("tx"), isFalse);
      final view = StageView(const Rect.fromLTWH(0, 0, 1280, 720), cam);
      expect(view.target, (1.5, 0.5, 2));
      // What it looks at is in the middle of the picture.
      near(view.see(1.5, 0.5, 2).page, const Offset(640, 360));
    });

    test("panned, the stage follows the pointer", () {
      final view =
          StageView(const Rect.fromLTWH(0, 0, 1280, 720), const StageCamera());
      final (x, y, z) = view.target;
      final was = view.see(x, y, z).page;
      final moved = StageView(view.box, view.panned(const Offset(60, -25)));
      near(moved.see(x, y, z).page, was + const Offset(60, -25), 0.5);
    });

    test("framing puts a thing in the middle, big enough to see", () {
      final view =
          StageView(const Rect.fromLTWH(0, 0, 1280, 720), const StageCamera());
      final framed = StageView(view.box, view.framing(2, 0.8, -1, 1.6));
      near(framed.see(2, 0.8, -1).page, const Offset(640, 360));
      // About 1.6 m fills most of the height, with room round it.
      final top = framed.see(2, 1.6, -1).page.dy;
      final bottom = framed.see(2, 0, -1).page.dy;
      expect(bottom - top, inInclusiveRange(720 * 0.6, 720 * 0.8));
    });

    test("a level above the floor is where a lifted thing slides", () {
      final view =
          StageView(const Rect.fromLTWH(0, 0, 1280, 720), const StageCamera());
      final p = view.see(1, 2, 0.5).page;
      final hit = view.toFloor(p, y: 2)!;
      near(hit, const Offset(1, 0.5), 0.001);
    });
  });

  group("the controller", () {
    test("steers the stage the selected element stands on", () {
      final c = CanvasController(onStage());
      addTearDown(c.dispose);
      expect(c.onStage3d, isTrue);
      expect(c.steeredStage!.id, "st");
      final yaw = cameraOf(c).yaw;
      c.orbitBy(30, 10);
      expect(cameraOf(c).yaw, closeTo(yaw + 30, 1e-9));
      expect(cameraOf(c).pitch, closeTo(22, 1e-9));
      final d = cameraOf(c).distance;
      c.dollyBy(0.5);
      expect(cameraOf(c).distance, closeTo(d * 0.5, 1e-9));
      c.panCameraBy(const Offset(100, 0));
      expect(cameraOf(c).tx, isNot(0));
      c.resetCamera();
      expect((cameraOf(c).tx, cameraOf(c).yaw, cameraOf(c).distance),
          (0, 0, const StageCamera().distance));
      // Each a step to undo.
      c.undo();
      expect(cameraOf(c).tx, isNot(0));
    });

    test("a page with no stage has no 3D", () {
      final c = CanvasController(const CanvasDocument().addElement(flat("a")));
      addTearDown(c.dispose);
      expect(c.onStage3d, isFalse);
      expect(c.steeredStage, isNull);
      c.orbitBy(30, 0); // and does nothing
    });

    test("frames the selected element", () {
      final c = CanvasController(
          onStage(spot: const StageSpot("st", x: 2, z: -1, height: 2)));
      addTearDown(c.dispose);
      c.frameSelected(); // nothing selected: nothing happens
      expect(cameraOf(c).tx, 0);
      c.selectOnly("a");
      c.frameSelected();
      final at = stagedIn(c.document, c.document.elementById("a")!, 0)!;
      // Its middle in the middle of the picture.
      final (x, z) = (2.0, -1.0);
      final tall = 2 * 400 / 400;
      near(at.view.see(x, tall / 2, z).page, const Offset(640, 360), 0.5);
    });

    test("the page lock, the 3D tool and the view controls are the view's", () {
      final c = CanvasController(onStage());
      addTearDown(c.dispose);
      final r = c.revision;
      c.pageLocked = true;
      c.stageTool = StageTool.rotate;
      c.stageNav = StageNav.orbit;
      expect((c.pageLocked, c.stageTool, c.stageNav),
          (true, StageTool.rotate, StageNav.orbit));
      expect(c.revision, r, reason: "none of it changes the document");
      expect(c.canUndo, isFalse);
    });

    test("snap on a stage is its own switch, and steps a drag", () {
      final c = CanvasController(onStage());
      addTearDown(c.dispose);
      // Off to begin with, whatever the page's snap: on a stage it puts
      // every move on a step.
      expect((c.canvasSnap, c.document.guides.snap), (false, true));
      // Unsnapped, it goes where it is put.
      final a0 = c.document.elementById("a")!;
      final box0 = stagedIn(c.document, a0, 0)!.box;
      final free0 =
          c.movedTo(a0, box0.topLeft + const Offset(37, 11)).base.spot!;
      expect(free0.x % 0.25, isNot(closeTo(0, 1e-6)));
      c.canvasSnap = true;
      expect(
          (c.document.guides.stageSnap, c.document.guides.snap), (true, true));
      c.apply(c.document
          .copyWith(guides: c.document.guides.copyWith(stageStep: 0.5)));
      final a = c.document.elementById("a")!;
      final box = stagedIn(c.document, a, 0)!.box;
      final moved = c.movedTo(a, box.topLeft + const Offset(37, 11));
      final spot = moved.base.spot!;
      expect(spot.x % 0.5, closeTo(0, 1e-9));
      expect(spot.z % 0.5, closeTo(0, 1e-9));
      // On a page the bar's Snap is the page's.
      final page =
          CanvasController(const CanvasDocument().addElement(flat("a")));
      addTearDown(page.dispose);
      page.canvasSnap = false;
      expect(page.document.guides.snap, isFalse);
    });

    test("the 3D steps are kept in the file", () {
      const g = CanvasGuides(stageSnap: true, stageStep: 0.1, stageTurn: 45);
      final back = CanvasGuides.fromJson(g.toJson());
      expect((back.stageSnap, back.stageStep, back.stageTurn), (true, 0.1, 45));
      expect(const CanvasGuides().isDefault, isTrue);
      expect(g.isDefault, isFalse);
    });
  });

  group("the gizmo", () {
    StageGizmo gizmoOf(CanvasElement e, CanvasDocument doc, StageTool tool) =>
        StageGizmo.of(e, stagedIn(doc, e, 0)!, tool, 1)!;

    test("has the parts its tool asks for", () {
      final doc = onStage();
      final a = doc.elementById("a")!;
      expect(gizmoOf(a, doc, StageTool.move).parts,
          [GizmoPart.floor, GizmoPart.x, GizmoPart.z, GizmoPart.y]);
      expect(gizmoOf(a, doc, StageTool.rotate).parts, [GizmoPart.turn]);
      expect(gizmoOf(a, doc, StageTool.scale).parts, [GizmoPart.scale]);
      // Facing the camera there is no way round to turn; on the wall, no
      // nearer; and a 3D character is as tall as it was made.
      final cam =
          flat("c", spot: const StageSpot("st", stand: SpotStand.camera));
      final wall = flat("w",
          spot: const StageSpot("st", stand: SpotStand.wall, lift: 1));
      final b = body("b", spot: const StageSpot("st"));
      final doc2 = doc.addElement(cam).addElement(wall).addElement(b);
      expect(gizmoOf(cam, doc2, StageTool.rotate).parts, isEmpty);
      expect(gizmoOf(wall, doc2, StageTool.move).parts,
          [GizmoPart.x, GizmoPart.y]);
      expect(gizmoOf(b, doc2, StageTool.scale).parts, isEmpty);
    });

    test("is the same size on screen however far off", () {
      final near0 = onStage(spot: const StageSpot("st", z: 2));
      final far = onStage(spot: const StageSpot("st", z: -4));
      double long(CanvasDocument d) {
        final g = gizmoOf(d.elementById("a")!, d, StageTool.move);
        return (g.tip(GizmoPart.y) - g.centre).distance;
      }

      // The up arrow, a little shorter than its length for the camera
      // looking down on it -- more so near, where it looks down further --
      // but about the same near and far.
      expect(long(near0), closeTo(StageGizmo.onScreen, 8));
      expect(long(far), closeTo(StageGizmo.onScreen, 8));
    });

    test("an arrow is taken hold of, and drags along its way", () {
      final doc = onStage();
      final g = gizmoOf(doc.elementById("a")!, doc, StageTool.move);
      final tip = g.tip(GizmoPart.x);
      expect(g.hit(tip, 6), GizmoPart.x);
      expect(g.hit(g.tip(GizmoPart.y), 6), GizmoPart.y);
      expect(g.hit(g.centre + const Offset(300, 300), 6), isNull);
      // Its own length along it is its length in metres.
      final moved = g.dragged(GizmoPart.x, g.centre, tip);
      expect(moved.x, closeTo(g.length, 1e-6));
      expect(moved.z, 0);
      // Lifted up the green, never under the floor.
      final up = g.dragged(GizmoPart.y, g.centre, g.tip(GizmoPart.y));
      expect(up.lift, closeTo(g.length, 1e-6));
      final down = g.dragged(GizmoPart.y, g.tip(GizmoPart.y), g.centre);
      expect(down.lift, 0);
      // And in steps, snapping.
      final stepped = g.dragged(GizmoPart.x, g.centre, tip, step: 0.25);
      expect(stepped.x % 0.25, closeTo(0, 1e-9));
    });

    test("the square slides it across the floor under the pointer", () {
      final doc = onStage();
      final g = gizmoOf(doc.elementById("a")!, doc, StageTool.move);
      final square = g.square;
      final middle = (square[0] + square[2]) / 2;
      expect(g.hit(middle, 6), GizmoPart.floor);
      final to = g.at.view.see(1.5, 0, 1).page;
      final from = g.centre;
      final moved = g.dragged(GizmoPart.floor, from, to);
      expect(moved.x, closeTo(1.5, 1e-6));
      expect(moved.z, closeTo(1, 1e-6));
    });

    test("the ring turns it, in steps when snapping", () {
      final doc = onStage();
      final g = gizmoOf(doc.elementById("a")!, doc, StageTool.rotate);
      final r = g.length * 0.7;
      final from = g.at.view.see(0, 0, r).page; // facing nought
      expect(g.hit(from, 6), GizmoPart.turn);
      final to = g.at.view.see(r, 0, 0).page; // a quarter turn round
      expect(g.dragged(GizmoPart.turn, from, to).facing, closeTo(90, 1e-6));
      final nearly =
          g.at.view.see(math.sin(1.4) * r, 0, math.cos(1.4) * r).page; // 80°
      expect(g.dragged(GizmoPart.turn, from, nearly, turn: 15).facing, 75);
    });

    test("the box grows it dragged up, shrinks it down", () {
      final doc = onStage();
      final g = gizmoOf(doc.elementById("a")!, doc, StageTool.scale);
      expect(g.hit(g.scaleBox, 6), GizmoPart.scale);
      final h = g.at.spot.height;
      expect(
          g
              .dragged(
                  GizmoPart.scale, g.scaleBox, g.scaleBox - const Offset(0, 50))
              .height,
          greaterThan(h));
      expect(
          g
              .dragged(
                  GizmoPart.scale, g.scaleBox, g.scaleBox + const Offset(0, 50))
              .height,
          lessThan(h));
    });
  });

  group("the bar", () {
    testWidgets("on a stage, the 3D tools stand in for Select and Pan",
        (tester) async {
      final c = CanvasController(onStage());
      addTearDown(c.dispose);
      await tester.pumpWidget(bar(c));
      expect(find.byKey(const ValueKey("canvasToolSelect")), findsNothing);
      await tester.tap(find.byKey(const ValueKey("stageTool-rotate")));
      await tester.pump();
      expect(c.stageTool, StageTool.rotate);
      // The view controls: all, the ball alone, none, and back.
      final nav = find.byKey(const ValueKey("stageNav"));
      for (final next in [StageNav.orbit, StageNav.none, StageNav.all]) {
        await tester.tap(nav);
        await tester.pump();
        expect(c.stageNav, next);
      }

      // On a page, Select and Pan, and no 3D.
      final page =
          CanvasController(const CanvasDocument().addElement(flat("a")));
      addTearDown(page.dispose);
      await tester.pumpWidget(bar(page));
      expect(find.byKey(const ValueKey("stageTool-move")), findsNothing);
      expect(find.byKey(const ValueKey("canvasToolSelect")), findsOneWidget);
      expect(find.byKey(const ValueKey("stageNav")), findsNothing);
    });

    testWidgets("Snap, its steps, and the page lock", (tester) async {
      final c = CanvasController(onStage());
      addTearDown(c.dispose);
      var opened = 0;
      await tester.pumpWidget(bar(c, onGuides: () => opened++));
      await tester.tap(find.byKey(const ValueKey("snapToggle")));
      await tester.pump();
      expect(c.document.guides.stageSnap, isTrue);
      await tester.tap(find.byKey(const ValueKey("snapMenu")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("snapStep-0.5")));
      await tester.pumpAndSettle();
      expect(c.document.guides.stageStep, 0.5);
      await tester.tap(find.byKey(const ValueKey("snapMenu")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("snapMore")));
      await tester.pumpAndSettle();
      expect(opened, 1, reason: "the menu opens the snapping settings");

      await tester.tap(find.byKey(const ValueKey("pageLock")));
      await tester.pump();
      expect(c.pageLocked, isTrue);
    });

    testWidgets("one button for the fit, and a zoom to drag", (tester) async {
      final c = CanvasController(const CanvasDocument());
      addTearDown(c.dispose);
      await tester.pumpWidget(bar(c));
      expect(c.fit, CanvasFit.whole);
      final fit = find.byKey(const ValueKey("canvasFit"));
      await tester.tap(fit);
      await tester.pump();
      expect(c.fit, CanvasFit.width);
      await tester.tap(fit);
      await tester.pump();
      expect(c.fit, CanvasFit.whole);

      // Dragged right it zooms in, left out.
      final zoom = find.byKey(const ValueKey("zoomScrub"));
      await tester.drag(zoom, const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(c.zoom, greaterThan(1.5));
      final zoomed = c.zoom;
      await tester.drag(zoom, const Offset(-60, 0));
      await tester.pumpAndSettle();
      expect(c.zoom, lessThan(zoomed));
      // Zoomed, the fit button puts the fit back rather than changing it.
      await tester.tap(fit);
      await tester.pump();
      expect((c.fit, c.zoom), (CanvasFit.whole, 1));
      // A double-click fits it too.
      await tester.drag(zoom, const Offset(80, 0));
      await tester.pumpAndSettle();
      await tester.tap(zoom);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(zoom);
      await tester.pumpAndSettle();
      expect(c.zoom, 1);

      // Locked, it holds.
      c.pageLocked = true;
      await tester.pump();
      await tester.drag(zoom, const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(c.zoom, 1);
      await tester.tap(fit);
      await tester.pump();
      expect(c.fit, CanvasFit.whole);
    });

    testWidgets("fits on one line at every text size", (tester) async {
      for (final scale in [0.65, 1.0, 1.5]) {
        final c = CanvasController(onStage());
        addTearDown(c.dispose);
        tester.view.physicalSize = const Size(1400, 400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: bar(c)));
        c.zoom = 8.88;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: "at $scale");
        // The reading whole inside its box, at the reader's text size.
        final box = tester.getRect(find.byKey(const ValueKey("zoomScrub")));
        final reading = tester.getRect(find.descendant(
            of: find.byKey(const ValueKey("zoomScrub")),
            matching: find.textContaining("%")));
        expect(reading.right, lessThanOrEqualTo(box.right + 0.5),
            reason: "at $scale the reading ends at ${reading.right}, its box "
                "at ${box.right}");
      }
    });
  });

  group("on the canvas", () {
    Future<CanvasStageState> pumpStage(
        WidgetTester tester, CanvasController c) async {
      final key = GlobalKey<CanvasStageState>();
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(SizedBox(
          width: 1280,
          height: 800,
          child: CanvasStage(key: key, controller: c))));
      await tester.pumpAndSettle();
      return key.currentState!;
    }

    testWidgets("the view controls float at the stage's right", (tester) async {
      final c = CanvasController(onStage());
      addTearDown(c.dispose);
      await pumpStage(tester, c);
      expect(find.byType(StageNavControls), findsOneWidget);
      expect(find.byKey(const ValueKey("stageNavZoom")), findsOneWidget);
      final yaw = cameraOf(c).yaw;
      await tester.drag(
          find.byKey(const ValueKey("stageNavOrbit")), const Offset(50, 0));
      await tester.pumpAndSettle();
      expect(cameraOf(c).yaw, greaterThan(yaw));
      final d = cameraOf(c).distance;
      await tester.drag(
          find.byKey(const ValueKey("stageNavZoom")), const Offset(0, -40));
      await tester.pumpAndSettle();
      expect(cameraOf(c).distance, lessThan(d));
      await tester.drag(
          find.byKey(const ValueKey("stageNavPan")), const Offset(40, 0));
      await tester.pumpAndSettle();
      expect(cameraOf(c).tx, isNot(0));
      await tester.tap(find.byKey(const ValueKey("stageNavReset")));
      await tester.pumpAndSettle();
      expect((cameraOf(c).tx, cameraOf(c).yaw), (0, 0));

      // Folded to the ball alone, then put away.
      c.stageNav = StageNav.orbit;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("stageNavZoom")), findsNothing);
      expect(find.byKey(const ValueKey("stageNavOrbit")), findsOneWidget);
      c.stageNav = StageNav.none;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("stageNavOrbit")), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets("none on a page", (tester) async {
      final c = CanvasController(const CanvasDocument().addElement(flat("a")));
      addTearDown(c.dispose);
      await pumpStage(tester, c);
      expect(find.byKey(const ValueKey("stageNavOrbit")), findsNothing);
    });

    testWidgets("the gizmo's arrow drags the element along it", (tester) async {
      final c = CanvasController(onStage());
      addTearDown(c.dispose);
      c.selectOnly("a");
      final s = await pumpStage(tester, c);
      final g = s.gizmo!;
      final from = s.toStagePoint(g.tip(GizmoPart.x));
      final to = s.toStagePoint(
          g.tip(GizmoPart.x) + (g.tip(GizmoPart.x) - g.centre) * 0.5);
      final gesture = await tester.startGesture(from);
      await gesture.moveTo(from + const Offset(10, 0));
      await gesture.moveTo(to);
      await gesture.up();
      await tester.pumpAndSettle();
      final spot = c.document.elementById("a")!.base.spot!;
      expect(spot.x, closeTo(g.length * 0.5, 0.05));
      expect(spot.z, closeTo(0, 0.05));
      // One step to undo.
      c.undo();
      expect(c.document.elementById("a")!.base.spot!.x, 0);
    });

    testWidgets("locked, a drag on the stage orbits its camera",
        (tester) async {
      final c = CanvasController(onStage());
      addTearDown(c.dispose);
      final s = await pumpStage(tester, c);
      c.pageLocked = true;
      await tester.pump();
      // A corner of the stage nothing stands on.
      final at = s.toStagePoint(const Offset(1200, 650));
      final yaw = cameraOf(c).yaw;
      final pan = c.pan;
      await tester.dragFrom(at, const Offset(-80, 0));
      await tester.pumpAndSettle();
      expect(cameraOf(c).yaw, isNot(closeTo(yaw, 0.1)));
      expect(c.pan, pan, reason: "the page stays where it is");

      // Shifted, it pans.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.dragFrom(at, const Offset(40, 0));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(cameraOf(c).tx, isNot(0));

      // The wheel orbits too, and the page does not zoom.
      final zoom = c.zoom;
      final before = cameraOf(c).pitch;
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(at));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 20)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(cameraOf(c).pitch, isNot(closeTo(before, 0.01)));
      expect(c.zoom, zoom);
    });

    testWidgets("unlocked, the stage's camera is left alone", (tester) async {
      final c = CanvasController(onStage());
      addTearDown(c.dispose);
      final s = await pumpStage(tester, c);
      final at = s.toStagePoint(const Offset(1200, 650));
      final yaw = cameraOf(c).yaw;
      await tester.dragFrom(at, const Offset(-80, 0));
      await tester.pumpAndSettle();
      expect(cameraOf(c).yaw, yaw);
    });

    testWidgets("the keys: G R S, L, Shift-S, F and Home", (tester) async {
      final c = CanvasController(
          onStage(spot: const StageSpot("st", x: 2, height: 2)));
      addTearDown(c.dispose);
      c.selectOnly("a");
      final s = await pumpStage(tester, c);
      // The canvas takes the keys once pressed.
      await tester.tapAt(s.toStagePoint(const Offset(40, 690)));
      await tester.pump();
      c.selectOnly("a");
      await tester.pump();
      for (final (key, tool) in [
        (LogicalKeyboardKey.keyR, StageTool.rotate),
        (LogicalKeyboardKey.keyS, StageTool.scale),
        (LogicalKeyboardKey.keyG, StageTool.move),
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pump();
        expect(c.stageTool, tool);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.pump();
      expect(c.pageLocked, isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(c.document.guides.stageSnap, isTrue);
      expect(c.stageTool, StageTool.move, reason: "Shift-S is not Scale");
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      expect(cameraOf(c).tx, closeTo(2, 1e-6));
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(cameraOf(c).tx, 0);
    });
  });
}
