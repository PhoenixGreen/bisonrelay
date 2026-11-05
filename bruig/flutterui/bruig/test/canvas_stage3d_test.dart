import 'dart:ui';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_design.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/stage_spot.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_camera.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/elements_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_stage3d_test.dart is the 3D stage: its camera, characters standing
// on it -- placed, sorted, turned, dragged and posed as the camera sees
// them -- camera moves on the timeline, and a character on a flat page
// with its shadow and depth.
//
// A stage is a kind of background: a Background element showing one, or
// the canvas's own background. [stage] is the first, which is what a stage
// saved as an element of its own opens as.

const page = Rect.fromLTWH(0, 0, 1280, 720);

BackgroundElement stage(
        {StageCamera camera = const StageCamera(), ElementTrack? track}) =>
    BackgroundElement(
        ElementBase(
            id: "st", x: 0, y: 0, width: 1280, height: 720, track: track),
        backdrop: BackdropKind.stage,
        stage: StageElement(const ElementBase(id: ""), camera: camera));

/// stageIn is the stage "st" in [c]'s document, as it is drawn.
StageElement stageIn(CanvasController c) =>
    (c.document.elementById("st")! as BackgroundElement).staged;

Character3dElement who(String id,
        {double x = 0, double z = 0, double facing = 0, String on = "st"}) =>
    Character3dElement(
        ElementBase(
            id: id,
            name: id,
            width: 200,
            height: 420,
            spot: on.isEmpty
                ? null
                : StageSpot(on, x: x, z: z, facing: facing)),
        design: CharacterDesign(
            id: "d", name: id, body: "Vivi", updated: DateTime(2026)));

void near(Offset a, Offset b, [double within = 0.01]) =>
    expect((a - b).distance, lessThan(within), reason: "$a is not $b");

void main() {
  group("the camera", () {
    test("it looks at the middle, and further is smaller", () {
      var view = StageView(page, const StageCamera());
      near(view.see(0, 1, 0).page, page.center);
      var close = view.see(0, 0, 2), far = view.see(0, 0, -2);
      expect(far.depth, greaterThan(close.depth));
      expect(view.scaleAt(far.depth), lessThan(view.scaleAt(close.depth)));
      expect(far.page.dy, lessThan(close.page.dy), reason: "the far floor is higher");
    });

    test("a spot on the floor goes to the page and back", () {
      for (var cam in [for (var s in cameraShots) s.camera]) {
        var view = StageView(page, cam);
        for (var (x, z) in [(0.0, 0.0), (1.5, -2.0), (-2.0, 1.0)]) {
          var seen = view.see(x, 0, z);
          if (seen.depth <= StageView.nearest) continue;
          var back = view.toFloor(seen.page)!;
          near(back, Offset(x, z), 1e-6);
        }
      }
      expect(StageView(page, const StageCamera()).toFloor(const Offset(640, 10)),
          isNull, reason: "above the horizon there is no floor");
    });

    test("what is behind the lens is cut off", () {
      var view = StageView(page, const StageCamera(distance: 2));
      var floor = view.polygon([(-6, 0, -6), (6, 0, -6), (6, 0, 6), (-6, 0, 6)]);
      expect(floor.length, greaterThanOrEqualTo(3));
      for (var p in floor) {
        expect(p.dy.isFinite, isTrue);
      }
    });

    test("a stage is saved whole and goes in at the back", () {
      var s = stage().withStage(stage(camera: cameraShots[2].camera).staged.copyWith(
          pattern: FloorPattern.grass, light: StageLight.night, wall: false));
      var back = elementFromJson(s.toJson()) as BackgroundElement;
      expect(back.toJson(), s.toJson());
      expect(back.isStage, isTrue);
      var c = CanvasController(const CanvasDocument().addElement(who("a", on: "")));
      addTearDown(c.dispose);
      c.addElement(newElement(ElementKind.stage, c.document));
      expect(c.document.elements.first,
          isA<BackgroundElement>().having((b) => b.isStage, "isStage", true));
    });
  });

  group("standing on a stage", () {
    test("it stands where the camera sees its spot, sized by distance", () {
      var els = [stage(), who("near", z: 2), who("far", z: -3)];
      var n = staged(els[1], els, 0)!;
      var f = staged(els[2], els, 0)!;
      var view = StageView(page, const StageCamera());
      near(n.foot, view.see(0, 0, 2).page);
      expect(f.box.height, lessThan(n.box.height));
      expect(inStageOrder(els, 0).map((e) => e.id), ["st", "far", "near"],
          reason: "the far one first, so the near one is in front");
      expect(staged(who("lost", on: "gone"), els, 0), isNull);
    });

    test("a camera move is keyed and eased, the rule a pose follows", () {
      var c = CanvasController(CanvasDocument(frames: 48).addElement(stage()));
      addTearDown(c.dispose);
      StageElement get() => stageIn(c);
      c.putStage(c.stageFilmed(get(), const StageCamera(distance: 5)));
      expect(get().camera.distance, 5, reason: "not keyed yet: the setting");
      c.frame = 24;
      c.keyCamera(get());
      expect(c.document.elementById("st"), isA<BackgroundElement>(),
          reason: "keyed where it lives, not swapped for a bare stage");
      c.putStage(c.stageFilmed(get(), const StageCamera(distance: 15)));
      expect(get().track!.keys.map((k) => k.frame), [0, 24]);
      expect(get().cameraAt(0).distance, 5);
      expect(get().cameraAt(24).distance, 15);
      expect(get().cameraAt(12).distance, closeTo(10, 1e-9));
      expect(c.hasCameraKey(get()), isTrue);
    });

    test("dragged, it moves across the floor", () {
      var c = CanvasController(const CanvasDocument().addElement(stage()).addElement(who("a")));
      addTearDown(c.dispose);
      var e = c.document.elementById("a")!;
      var box = staged(e, c.document.elements, 0)!.box;
      var moved = c.movedTo(e, box.topLeft + const Offset(80, 30));
      expect(moved.base.spot!.x, greaterThan(0), reason: "to the right");
      expect(moved.base.spot!.z, greaterThan(0), reason: "down the page is nearer");
      var after = staged(moved, [c.document.elementById("st")!, moved], 0)!;
      expect(c.document.elementById("st"), isA<BackgroundElement>());
      var before = staged(e, c.document.elements, 0)!.foot;
      near(after.foot, before + const Offset(80, 30), 0.5);
      expect(visualBoundsOf(moved, c.document.withElement(moved), 0), after.box);
      expect(hasOwnGeometry(moved, c.document.withElement(moved), 0), isFalse);
    });

    test("a new character stands on the stage, a step from the last", () {
      var doc = const CanvasDocument().addElement(stage());
      var first = newElement(ElementKind.character3d, doc);
      expect(first.base.spot?.stage, "st");
      var second = newElement(ElementKind.character3d, doc.addElement(first));
      expect(second.base.spot!.x, isNot(first.base.spot!.x));
    });

    test("the camera changes the picture", () async {
      Future<List<int>> draw(StageCamera cam) async {
        var rec = PictureRecorder();
        paintCanvasDocument(Canvas(rec),
            const CanvasDocument().addElement(stage(camera: cam)).addElement(who("a")));
        var img = await rec.endRecording().toImage(320, 180);
        return (await img.toByteData())!.buffer.asUint8List();
      }

      var a = await draw(const StageCamera());
      expect(await draw(const StageCamera()), a);
      expect(await draw(const StageCamera(yaw: 60)), isNot(a));
    });
  });

  group("the panels", () {
    setUpAll(() => CanvasSection.openAll = true);
    tearDownAll(() => CanvasSection.openAll = false);

    Widget host(CanvasController c) => MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeNotifier>(
                create: (c) => ThemeNotifier(doLoad: false)),
            ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
            ChangeNotifierProvider<CanvasPreferences>(
                create: (c) => CanvasPreferences()),
          ],
          child: MaterialApp(
              home: Scaffold(
                  body: SizedBox(width: 420, child: CanvasDesignPanel(controller: c)))),
        );

    Future<void> tap(WidgetTester tester, String key) async {
      var f = find.byKey(ValueKey(key));
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    testWidgets("the stage's camera, set and light", (tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(CanvasDocument(frames: 48).addElement(stage()));
      addTearDown(c.dispose);
      c.selectOnly("st");
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(c));
      await tester.pumpAndSettle();
      StageElement get() => stageIn(c);
      await tap(tester, "stageShot-Close-up");
      expect(get().camera.lens, cameraShots[2].camera.lens);
      await tap(tester, "stageYaw-more");
      expect(get().camera.yaw, 15);
      // What it looks at, moved across: and the shot is no longer the
      // shot it was.
      await tap(tester, "stageAimX-more");
      expect(get().camera.tx, 0.25);
      await tap(tester, "stageFloor-tiles");
      expect(get().pattern, FloorPattern.tiles);
      await tap(tester, "stageLight-goldenHour");
      expect(get().light, StageLight.goldenHour);
      c.frame = 10;
      await tester.pumpAndSettle();
      await tap(tester, "stageKey");
      expect(c.hasCameraKey(get()), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets("a stage's globe orbits its camera", (tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(CanvasDocument(frames: 48).addElement(stage()));
      addTearDown(c.dispose);
      c.selectOnly("st");
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(c));
      await tester.pumpAndSettle();
      var pad = find.byKey(const ValueKey("stageOrbitPad"));
      await tester.ensureVisible(pad);
      await tester.pumpAndSettle();
      await tester.drag(pad, const Offset(60, 20));
      await tester.pumpAndSettle();
      expect(stageIn(c).camera.yaw, greaterThan(10));
      expect(stageIn(c).camera.pitch, greaterThan(const StageCamera().pitch));
    });

  });

  group("the canvas background as a stage", () {
    CanvasDocument staged({StageCamera camera = const StageCamera()}) =>
        CanvasDocument(
            frames: 48,
            background: CanvasBackground(
                backdrop: BackdropKind.stage,
                stage: defaultBackgroundStage.copyWith(camera: camera)));

    test("it is saved, and what stands on it is drawn first", () {
      var doc = staged(camera: const StageCamera(yaw: 20))
          .addElement(const BackgroundElement(ElementBase(id: "panel")))
          .addElement(who("far", z: -3, on: backgroundStageId))
          .addElement(who("near", z: 2, on: backgroundStageId));
      var back = CanvasDocument.fromJson(doc.toJson());
      expect(back.background.isStage, isTrue);
      expect(back.background.toJson(), doc.background.toJson());
      var near = back.elementById("near")!;
      var at = stagedIn(back, near, 0)!;
      var view = StageView(page, const StageCamera(yaw: 20));
      expect((at.foot - view.see(0, 0, 2).page).distance, lessThan(0.01));
      expect(
          inStageOrder(back.elements, 0,
                  backdrop: back.drawnBackground, page: back.size.rect)
              .map((e) => e.id),
          ["far", "near", "panel"],
          reason: "behind everything, as the background is");
    });

    test("shown flat, it keeps its stage and nobody stands on it", () {
      var doc = staged(camera: const StageCamera(lens: 85));
      var flat = doc.copyWith(
          background: doc.background.copyWith(backdrop: BackdropKind.flat));
      expect(flat.background.stage!.camera.lens, 85);
      var a = who("a", on: backgroundStageId);
      expect(stagedIn(flat.addElement(a), a, 0), isNull);
      expect(stagedIn(doc.addElement(a), a, 0), isNotNull);
    });

    test("its camera is keyed on the background, and a drag walks", () {
      var c = CanvasController(
          staged().addElement(who("a", on: backgroundStageId)));
      addTearDown(c.dispose);
      StageElement get() => c.stageOf(backgroundStageId)!;
      c.putStage(c.stageFilmed(get(), const StageCamera(distance: 5)));
      c.frame = 24;
      c.keyCamera(get());
      c.putStage(c.stageFilmed(get(), const StageCamera(distance: 15)));
      expect(c.document.background.stage!.track!.keys.map((k) => k.frame),
          [0, 24]);
      expect(get().cameraAt(12).distance, closeTo(10, 1e-9));
      c.frame = 0;
      var e = c.document.elementById("a")!;
      var box = stagedIn(c.document, e, 0)!.box;
      var moved = c.movedTo(e, box.topLeft + const Offset(60, 0));
      expect(moved.base.spot!.x, greaterThan(0));
    });

    test("a new character stands on it", () {
      var first = newElement(ElementKind.character3d, staged());
      expect(first.base.spot?.stage, backgroundStageId);
    });

    test("it is drawn in the pattern's place", () async {
      Future<List<int>> draw(CanvasDocument doc) async {
        var rec = PictureRecorder();
        paintCanvasDocument(Canvas(rec), doc);
        var img = await rec.endRecording().toImage(320, 180);
        return (await img.toByteData())!.buffer.asUint8List();
      }

      var doc = staged();
      var flat = doc.copyWith(
          background: doc.background.copyWith(backdrop: BackdropKind.flat));
      expect(await draw(doc), isNot(await draw(flat)));
      expect(await draw(flat), await draw(const CanvasDocument(frames: 48)),
          reason: "a stage kept but not shown changes nothing");
      expect(await draw(staged(camera: const StageCamera(yaw: 60))),
          isNot(await draw(doc)));
    });
  });

  group("choosing a stage", () {
    setUpAll(() => CanvasSection.openAll = true);
    tearDownAll(() => CanvasSection.openAll = false);

    Widget host(Widget child) => MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeNotifier>(
                create: (c) => ThemeNotifier(doLoad: false)),
            ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
            ChangeNotifierProvider<CanvasPreferences>(
                create: (c) => CanvasPreferences()),
          ],
          child: MaterialApp(
              home: Scaffold(body: SizedBox(width: 420, child: child))),
        );

    Future<void> tap(WidgetTester tester, String key) async {
      var f = find.byKey(ValueKey(key));
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    void tall(WidgetTester tester) {
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets("the canvas background turns into a stage and back",
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(const CanvasDocument(frames: 48));
      addTearDown(c.dispose);
      tall(tester);
      await tester.pumpWidget(host(CanvasDesignPanel(controller: c)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("addLayer")), findsOneWidget,
          reason: "a 2D background has its pattern layers");
      await tap(tester, "backdropKind-stage");
      expect(c.document.background.isStage, isTrue);
      expect(find.byKey(const ValueKey("addLayer")), findsNothing);
      await tap(tester, "stageShot-Close-up");
      expect(c.document.background.stage!.camera.lens,
          cameraShots[2].camera.lens);
      await tap(tester, "stageFloor-tiles");
      expect(c.document.background.stage!.pattern, FloorPattern.tiles);
      c.frame = 10;
      await tester.pumpAndSettle();
      await tap(tester, "stageKey");
      expect(c.hasCameraKey(c.stageOf(backgroundStageId)!), isTrue);
      await tap(tester, "backdropKind-flat");
      expect(c.document.background.isStage, isFalse);
      expect(c.document.background.stage!.pattern, FloorPattern.tiles,
          reason: "kept for coming back to");
      expect(find.byKey(const ValueKey("addLayer")), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets("a Background element turns into a stage", (tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(const CanvasDocument(frames: 48).addElement(
          const BackgroundElement(
              ElementBase(id: "bg", width: 640, height: 360))));
      addTearDown(c.dispose);
      c.selectOnly("bg");
      tall(tester);
      await tester.pumpWidget(host(CanvasDesignPanel(controller: c)));
      await tester.pumpAndSettle();
      BackgroundElement get() => c.document.elementById("bg")! as BackgroundElement;
      await tap(tester, "backdropKind-stage");
      expect(get().isStage, isTrue);
      await tap(tester, "stageLight-night");
      expect(get(), isA<BackgroundElement>());
      expect(get().stage!.light, StageLight.night);
      c.frame = 10;
      await tester.pumpAndSettle();
      await tap(tester, "stageKey");
      expect(get().track!.keys.map((k) => k.frame), [0, 10],
          reason: "the camera's keys are on the element's own track");
      expect(tester.takeException(), isNull);
    });

    testWidgets("Add no longer offers a 3D stage", (tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(const CanvasDocument());
      addTearDown(c.dispose);
      tall(tester);
      await tester.pumpWidget(host(CanvasElementsPanel(controller: c)));
      await tester.pumpAndSettle();
      expect(find.text(ElementKind.tileMap.label), findsWidgets);
      expect(find.text(ElementKind.stage.label), findsNothing);
    });
  });
}
