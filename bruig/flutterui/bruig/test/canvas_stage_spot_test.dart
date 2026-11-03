import 'dart:typed_data';
import 'dart:ui';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_design.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/stage_spot.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/surround.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/sound_placement.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_camera.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Any element standing on a 3D stage: kept with it, seen where the stage's
// camera puts it -- a flat set into the stage in perspective, a 3D
// character through the camera -- sorted far to near, dragged across the
// floor, and put on a stage from its settings.

const page = Rect.fromLTWH(0, 0, 1280, 720);

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

void near(Offset a, Offset b, [double within = 0.01]) =>
    expect((a - b).distance, lessThan(within), reason: "$a is not $b");

/// through is [p] through [m], as Canvas.transform takes it.
Offset through(Float64List m, Offset p) {
  final x = m[0] * p.dx + m[4] * p.dy + m[12];
  final y = m[1] * p.dx + m[5] * p.dy + m[13];
  final w = m[3] * p.dx + m[7] * p.dy + m[15];
  return Offset(x / w, y / w);
}

void main() {
  test("kept with the element, and read back the same", () {
    const spot = StageSpot("st",
        x: 1.5,
        z: -2,
        lift: 0.3,
        height: 2.2,
        facing: 30,
        stand: SpotStand.floor);
    final e = flat("a", spot: spot);
    final back = ElementBase.fromJson(e.base.toJson(), "Shape");
    expect(back.spot, spot);
    expect(flat("b").base.toJson().containsKey("spot"), isFalse);
    expect(
        ElementBase.fromJson({
          "spot": {"stage": ""}
        }, "x")
            .spot,
        isNull);
    expect(
        StageSpot.fromJson({"stage": "st", "height": -4, "stand": "sideways"}),
        const StageSpot("st", height: 0.05));
    expect(e.withBase(clearSpot: true).base.spot, isNull);
  });

  test("its spot is keyed like anything else", () {
    final e = flat("a", spot: const StageSpot("st")).withBase(
        track: ElementTrack.empty.withKey(Keyframe.rest
            .copyWith(frame: 10, values: {spotChannel("x"): 2.0})));
    expect(e.spotAt(10)!.x, 2);
    expect(e.spotAt(10)!.stage, "st");
  });

  test("keyed, it moves between its keys, and moving it keys it", () {
    final c = CanvasController(CanvasDocument(frames: 48)
        .addElement(stage())
        .addElement(flat("a", spot: const StageSpot("st", x: -2))));
    addTearDown(c.dispose);
    CanvasElement get() => c.document.elementById("a")!;
    // Unkeyed, moving it moves it on every frame.
    c.frame = 20;
    c.replaceElement(c.spotted(get(), get().spotAt(20)!.copyWith(x: -1)));
    expect(get().base.spot!.x, -1);
    expect(c.spotKeyed(get()), isFalse);
    // Keyed here, it is keyed on the first frame too, where it stood.
    c.keySpot(get());
    expect(c.hasSpotKey(get()), isTrue);
    c.frame = 40;
    c.replaceElement(c.spotted(get(), get().spotAt(40)!.copyWith(x: 3)));
    expect(get().spotAt(40)!.x, 3);
    expect(get().spotAt(20)!.x, -1);
    expect(get().spotAt(30)!.x, closeTo(1, 0.6), reason: "on its way");
    expect(get().base.spot!.x, -1, reason: "its own spot left alone");
    // Dragged on a keyed frame, the drag keys it.
    final box = stagedIn(c.document, get(), 40)!.box;
    final moved = c.movedTo(get(), box.topLeft + const Offset(40, 0));
    expect(moved.spotAt(40)!.x, greaterThan(3));
    expect(moved.base.spot!.x, -1);
    c.clearSpotKey(get());
    expect(c.hasSpotKey(get()), isFalse);
  });

  test("a flat is set into the stage: its corners where the camera sees them",
      () {
    for (final cam in [
      const StageCamera(),
      const StageCamera(yaw: 40, pitch: 25, lens: 50),
    ]) {
      final doc = const CanvasDocument()
          .addElement(stage(camera: cam))
          .addElement(flat("a", spot: const StageSpot("st", x: 1, z: 0.5)));
      final at = stagedIn(doc, doc.elementById("a")!, 0)!;
      final view = StageView(page, cam);
      // The middle of its bottom edge on the spot, and the matrix takes its
      // own box's corners to where the camera sees them.
      final r = const Rect.fromLTWH(100, 50, 200, 400);
      near(through(at.matrix!, r.bottomCenter), view.see(1, 0, 0.5).page, 0.01);
      for (final (corner, seen) in [
        (r.topLeft, at.quad[0]),
        (r.topRight, at.quad[1]),
        (r.bottomRight, at.quad[2]),
        (r.bottomLeft, at.quad[3]),
      ]) {
        near(through(at.matrix!, corner), seen, 0.01);
      }
      // As tall as the spot says: 1.6 m.
      near(through(at.matrix!, r.topCenter), view.see(1, 1.6, 0.5).page, 0.01);
      expect(visualBoundsOf(doc.elementById("a")!, doc, 0), at.box);
      expect(hasOwnGeometry(doc.elementById("a")!, doc, 0), isFalse);
    }
  });

  test("turned to the camera, laid on the floor, hung on the wall", () {
    final cam = const StageCamera(yaw: 50);
    final view = StageView(page, cam);
    Staged on(SpotStand s) {
      final doc = const CanvasDocument()
          .addElement(stage(camera: cam))
          .addElement(flat("a", spot: StageSpot("st", stand: s, lift: 1)));
      return stagedIn(doc, doc.elementById("a")!, 0)!;
    }

    // Turned to the camera, its top edge is level across the picture.
    final facing = on(SpotStand.camera);
    expect((facing.quad[0].dy - facing.quad[1].dy).abs(), lessThan(1e-6));
    // Upright and not turned, the swung camera sees it slanted, and
    // narrower.
    final upright = on(SpotStand.upright);
    expect((upright.quad[0].dy - upright.quad[1].dy).abs(), greaterThan(1));
    expect(upright.box.width, lessThan(facing.box.width));
    // Laid on the floor, its corners are on the floor's plane.
    for (final p in on(SpotStand.floor).quad) {
      final spot = view.toFloor(p);
      expect(spot, isNotNull);
    }
    // On the wall, its bottom edge is a metre up the back wall.
    final wall = on(SpotStand.wall);
    final foot = view.toWall((wall.quad[2] + wall.quad[3]) / 2, -6 + 0.01)!;
    expect(foot.dy, closeTo(1, 1e-6));
  });

  test("a line stands as long as its size, on a plane round its stroke", () {
    final doc = const CanvasDocument().addElement(stage()).addElement(
        const LineElement(
            ElementBase(id: "l", x: 100, y: 300, width: 400, height: 0)));
    final line =
        doc.elementById("l")!.withBase(spot: const StageSpot("st", height: 2));
    final at = stagedIn(doc.withElement(line), line, 0)!;
    final view = StageView(page, const StageCamera());
    // Two metres from end to end: its ends where the camera sees them.
    near((at.quad[2] + at.quad[3]) / 2, view.see(0, 0, 0).page, 0.5);
    expect(at.box.width, closeTo(view.scaleAt(at.depth) * 2, 3));
  });

  test("behind the camera it is not drawn; off a stage, on the page", () {
    final doc = const CanvasDocument()
        .addElement(stage(camera: const StageCamera(distance: 2)))
        .addElement(flat("a", spot: const StageSpot("st", z: 6)))
        .addElement(flat("b", spot: const StageSpot("gone")));
    expect(stagedIn(doc, doc.elementById("a")!, 0), isNull);
    expect(stagedIn(doc, doc.elementById("b")!, 0), isNull);
    expect(visualBoundsOf(doc.elementById("b")!, doc, 0),
        const Rect.fromLTWH(100, 50, 200, 400));
    // A speaker or an instrument on the canvas can stand on a stage, and a
    // Background element showing a picture; a sound on the timeline, and a
    // stage itself, cannot.
    expect(canStand(AudioElement(const ElementBase(id: "s"))), isTrue);
    expect(
        canStand(AudioElement(const ElementBase(id: "t", visible: false),
            clip: const MediaClip(timed: true))),
        isFalse);
    expect(canStand(const BackgroundElement(ElementBase(id: "b"))), isTrue);
    expect(canStand(stage()), isFalse);
  });

  test("drawn after their stage, the furthest first", () {
    final doc = const CanvasDocument()
        .addElement(flat("near", spot: const StageSpot("st", z: 2)))
        .addElement(stage())
        .addElement(flat("far", spot: const StageSpot("st", z: -3)))
        .addElement(body("who", spot: const StageSpot("st", z: 0)))
        .addElement(flat("page"));
    final order = [
      for (final e in inStageOrder(doc.elements, 0, page: page)) e.id
    ];
    expect(order, ["st", "far", "who", "near", "page"]);
  });

  test("a 3D character stands on its spot, picked by a body-sized box", () {
    final doc = const CanvasDocument()
        .addElement(stage())
        .addElement(body("who", spot: const StageSpot("st", x: -1)));
    final at = stagedIn(doc, doc.elementById("who")!, 0)!;
    final view = StageView(page, const StageCamera());
    expect(at.matrix, isNull);
    expect(at.box.contains(view.see(-1, 0.9, 0).page), isTrue);
    expect(at.box.height, greaterThan(view.scaleAt(at.depth) * 1.6));
  });

  test("dragged, it moves across the floor -- or along the wall", () {
    final c = CanvasController(const CanvasDocument()
        .addElement(stage())
        .addElement(flat("a", spot: const StageSpot("st")))
        .addElement(flat("w",
            spot: const StageSpot("st", stand: SpotStand.wall, lift: 1))));
    addTearDown(c.dispose);
    final a = c.document.elementById("a")!;
    final box = stagedIn(c.document, a, 0)!.box;
    final moved = c.movedTo(a, box.topLeft + const Offset(80, 30));
    expect(moved.base.spot!.x, greaterThan(0), reason: "to the right");
    expect(moved.base.spot!.z, greaterThan(0), reason: "down is nearer");
    final w = c.document.elementById("w")!;
    final wbox = stagedIn(c.document, w, 0)!.box;
    final slid = c.movedTo(w, wbox.topLeft + const Offset(-60, -40));
    expect(slid.base.spot!.x, lessThan(0));
    expect(slid.base.spot!.lift, greaterThan(1), reason: "up the wall");
    expect(slid.base.spot!.z, 0, reason: "still on the wall");
  });

  test("drawn in perspective, and the camera moves it", () async {
    Future<List<int>> draw(StageCamera cam) async {
      final rec = PictureRecorder();
      paintCanvasDocument(
          Canvas(rec),
          CanvasDocument()
              .addElement(stage(camera: cam))
              .addElement(flat("a", spot: const StageSpot("st", x: 1)))
              .addElement(body("who", spot: const StageSpot("st"))));
      final img = await rec.endRecording().toImage(320, 180);
      return (await img.toByteData())!.buffer.asUint8List();
    }

    final a = await draw(const StageCamera());
    expect(await draw(const StageCamera()), a);
    expect(await draw(const StageCamera(yaw: 60)), isNot(a));
  });

  test("a sound following something on a stage is heard from where it is", () {
    const place = SoundPlacement(by: PlaceBy.follow, follow: "who");
    final sound = AudioElement(const ElementBase(id: "s"),
        clip: MediaClip(
            playlist: const [MediaSource(assetId: "t", length: 2)],
            timed: true,
            place: place));
    Heard heard(double x, double z) {
      final doc = const CanvasDocument()
          .addElement(stage())
          .addElement(body("who", spot: StageSpot("st", x: x, z: z)))
          .addElement(sound);
      return heardAt(doc, sound, place, 0)!;
    }

    expect(heard(0, 0).angle, closeTo(0, 0.5), reason: "straight ahead");
    expect(heard(3, 0).angle, greaterThan(15), reason: "to the right");
    expect(heard(-3, 0).angle, lessThan(-15), reason: "to the left");
    expect(heard(0, -5).gain, lessThan(heard(0, 0).gain),
        reason: "quieter further off");
  });

  group("the panel", () {
    setUpAll(() => CanvasSection.openAll = true);
    tearDownAll(() => CanvasSection.openAll = false);

    Widget host(CanvasController c) => MultiProvider(
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
                  body: SizedBox(
                      width: 420, child: CanvasDesignPanel(controller: c)))),
        );

    testWidgets("put on a stage, moved and turned, and taken off it",
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final c = CanvasController(
          const CanvasDocument().addElement(stage()).addElement(flat("a")));
      addTearDown(c.dispose);
      c.selectOnly("a");
      tester.view.physicalSize = const Size(900, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(c));
      await tester.pumpAndSettle();
      StageSpot? spot() => c.document.elementById("a")!.base.spot;
      final on = find.byKey(const ValueKey("stageSpotOn"));
      await tester.ensureVisible(on);
      tester.widget<CanvasDropdown<String>>(on).onChanged("st");
      await tester.pumpAndSettle();
      expect(spot()?.stage, "st");
      tester
          .widget<CanvasDropdown<SpotStand>>(
              find.byKey(const ValueKey("stageSpotStand")))
          .onChanged(SpotStand.floor);
      await tester.pumpAndSettle();
      expect(spot()?.stand, SpotStand.floor);
      tester
          .widget<CanvasSlider>(find.byKey(const ValueKey("stageSpotFacing")))
          .onChanged(45);
      await tester.pumpAndSettle();
      tester
          .widget<CanvasSlider>(find.byKey(const ValueKey("stageSpotHeight")))
          .onChanged(3);
      await tester.pumpAndSettle();
      expect((spot()?.facing, spot()?.height), (45, 3));
      tester.widget<CanvasDropdown<String>>(on).onChanged("");
      await tester.pumpAndSettle();
      expect(spot(), isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets("a picture has it too, among its sections", (tester) async {
      SharedPreferences.setMockInitialValues({});
      final c = CanvasController(const CanvasDocument()
          .addElement(stage())
          .addElement(ImageElement(
              const ElementBase(id: "p", width: 200, height: 100))));
      addTearDown(c.dispose);
      c.selectOnly("p");
      tester.view.physicalSize = const Size(900, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(c));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("stageSpotOn")), findsOneWidget);
    });

    testWidgets("with no stage, nothing is offered", (tester) async {
      SharedPreferences.setMockInitialValues({});
      final c = CanvasController(const CanvasDocument().addElement(flat("a")));
      addTearDown(c.dispose);
      c.selectOnly("a");
      await tester.pumpWidget(host(c));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("stageSpotOn")), findsNothing);
    });
  });
}
