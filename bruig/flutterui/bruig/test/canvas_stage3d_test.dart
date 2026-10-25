import 'dart:ui';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_painter.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_camera.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/character_puppet.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_stage3d_test.dart is the 3D stage: its camera, characters standing
// on it -- placed, sorted, turned, dragged and posed as the camera sees
// them -- camera moves on the timeline, and a character on a flat page
// with its shadow and depth.

const page = Rect.fromLTWH(0, 0, 1280, 720);

StageElement stage({StageCamera camera = const StageCamera(), ElementTrack? track}) =>
    StageElement(
        ElementBase(id: "st", x: 0, y: 0, width: 1280, height: 720, track: track),
        camera: camera);

CharacterElement who(String id,
        {double x = 0, double z = 0, double facing = 0, String on = "st"}) =>
    CharacterElement(ElementBase(id: id, name: id, width: 200, height: 420),
        dna: characterCast.first.dna,
        onStage: on.isEmpty ? null : OnStage(on, x: x, z: z, facing: facing));

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
      var s = stage(camera: cameraShots[2].camera)
          .copyWith(pattern: FloorPattern.grass, light: StageLight.night, wall: false);
      var back = elementFromJson(s.toJson()) as StageElement;
      expect(back.toJson(), s.toJson());
      var c = CanvasController(const CanvasDocument().addElement(who("a", on: "")));
      addTearDown(c.dispose);
      c.addElement(newElement(ElementKind.stage, c.document));
      expect(c.document.elements.first, isA<StageElement>());
    });
  });

  group("standing on a stage", () {
    test("it stands where the camera sees its spot, sized by distance", () {
      var els = [stage(), who("near", z: 2), who("far", z: -3)];
      var n = staging(els[1] as CharacterElement, els, 0)!;
      var f = staging(els[2] as CharacterElement, els, 0)!;
      var view = StageView(page, const StageCamera());
      near(n.box.bottomCenter, view.see(0, 0, 2).page);
      expect(f.box.height, lessThan(n.box.height));
      expect(inStageOrder(els, 0).map((e) => e.id), ["st", "far", "near"],
          reason: "the far one first, so the near one is in front");
      expect(staging(who("lost", on: "gone"), els, 0), isNull);
    });

    test("the camera's swing turns it, with its own facing", () {
      var els = [stage(camera: const StageCamera(yaw: 40)), who("a", facing: 10)];
      expect(staging(els[1] as CharacterElement, els, 0)!.turn, 50);
    });

    test("a camera move is keyed and eased, the rule a pose follows", () {
      var c = CanvasController(CanvasDocument(frames: 48).addElement(stage()));
      addTearDown(c.dispose);
      StageElement get() => c.document.elementById("st")! as StageElement;
      c.replaceElement(c.stageFilmed(get(), const StageCamera(distance: 5)));
      expect(get().camera.distance, 5, reason: "not keyed yet: the setting");
      c.frame = 24;
      c.keyCamera(get());
      c.replaceElement(c.stageFilmed(get(), const StageCamera(distance: 15)));
      expect(get().track!.keys.map((k) => k.frame), [0, 24]);
      expect(get().cameraAt(0).distance, 5);
      expect(get().cameraAt(24).distance, 15);
      expect(get().cameraAt(12).distance, closeTo(10, 1e-9));
      expect(c.hasCameraKey(get()), isTrue);
    });

    test("dragged, it moves across the floor", () {
      var c = CanvasController(const CanvasDocument().addElement(stage()).addElement(who("a")));
      addTearDown(c.dispose);
      var e = c.document.elementById("a")! as CharacterElement;
      var box = staging(e, c.document.elements, 0)!.box;
      var moved = c.movedTo(e, box.topLeft + const Offset(80, 30)) as CharacterElement;
      expect(moved.onStage!.x, greaterThan(0), reason: "to the right");
      expect(moved.onStage!.z, greaterThan(0), reason: "down the page is nearer");
      var after = staging(moved, [c.document.elementById("st")!, moved], 0)!;
      near(after.box.bottomCenter, box.bottomCenter + const Offset(80, 30), 0.5);
      expect(visualBoundsOf(moved, c.document.withElement(moved), 0), after.box);
      expect(hasOwnGeometry(moved, c.document.withElement(moved), 0), isFalse);
    });

    test("its pins are where it is drawn, and land the hand there", () {
      var doc = const CanvasDocument()
          .addElement(stage(camera: const StageCamera(yaw: 30)))
          .addElement(who("a", x: 1));
      var e = doc.elementById("a")! as CharacterElement;
      var at = CharacterPlacement.of(e, 0, document: doc);
      var to = at.pin(CharacterPin.handR) + const Offset(-10, -40);
      var posed = e.copyWith(pose: at.posedBy(CharacterPin.handR, to));
      var again = CharacterPlacement.of(posed, 0, document: doc.withElement(posed));
      near(again.pin(CharacterPin.handR), to, 1);
      expect(posed.pose.turn, e.pose.turn, reason: "the camera's turn is not kept");
    });

    test("a new character stands on the stage, a step from the last", () {
      var doc = const CanvasDocument().addElement(stage());
      var first = newElement(ElementKind.character, doc) as CharacterElement;
      expect(first.onStage?.stage, "st");
      var second = newElement(ElementKind.character, doc.addElement(first))
          as CharacterElement;
      expect(second.onStage!.x, isNot(first.onStage!.x));
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

  group("on a flat page", () {
    test("depth shrinks it going up the page, about its feet", () {
      var e = who("a", on: "").copyWith(depth: 1).withBase(
          track: ElementTrack(const [Keyframe(frame: 0, dy: -210)])) as CharacterElement;
      var box = characterBox(e, 0, e.bounds);
      expect(box.height, closeTo(210, 1e-6));
      expect(box.bottom, e.bounds.bottom);
      var flat = who("b", on: "");
      expect(characterBox(flat, 0, flat.bounds), flat.bounds);
    });

    test("a shadow is drawn, or not", () async {
      Future<List<int>> draw(CharacterShadow s) async {
        var rec = PictureRecorder();
        paintElement(Canvas(rec), who("a", on: "").copyWith(shadow: s), 0);
        var img = await rec.endRecording().toImage(300, 460);
        return (await img.toByteData())!.buffer.asUint8List();
      }

      expect(await draw(CharacterShadow.soft), isNot(await draw(CharacterShadow.none)));
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
      StageElement get() => c.document.elementById("st")! as StageElement;
      await tap(tester, "stageShot-Close-up");
      expect(get().camera.lens, cameraShots[2].camera.lens);
      await tap(tester, "stageYaw-more");
      expect(get().camera.yaw, 15);
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

    testWidgets("a character is put on a stage and moved on its floor",
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(const CanvasDocument()
          .addElement(stage())
          .addElement(who("a", on: "")));
      addTearDown(c.dispose);
      c.selectOnly("a");
      tester.view.physicalSize = const Size(900, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(c));
      await tester.pumpAndSettle();
      CharacterElement get() => c.document.elementById("a")! as CharacterElement;
      var pick = find.byKey(const ValueKey("characterStage"));
      await tester.ensureVisible(pick);
      tester.widget<CanvasDropdown<String>>(pick).onChanged("st");
      await tester.pumpAndSettle();
      expect(get().onStage?.stage, "st");
      await tap(tester, "characterStageX-more");
      expect(get().onStage!.x, 0.5);
      tester.widget<CanvasDropdown<String>>(pick).onChanged("");
      await tester.pumpAndSettle();
      expect(get().onStage, isNull);
      await tap(tester, "characterDepth-more");
      expect(get().depth, closeTo(0.1, 1e-9));
      expect(tester.takeException(), isNull);
    });
  });
}
