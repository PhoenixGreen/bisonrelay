import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/element_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_panel_helpers.dart';

// canvas_camera_lens_test.dart is the 2D Camera's lens (Ken, 2026-11-14:
// "useful camera settings like depth of field"): roll, depth of field by
// each element's Depth, parallax, a vignette and motion blur -- each in the
// picture as it is drawn through the camera, as a video is.

ShapeElement square(String id, Rect r,
        {double depth = 0, Color colour = const Color(0xFFFF0000)}) =>
    ShapeElement(
        ElementBase(
            id: id,
            x: r.left,
            y: r.top,
            width: r.width,
            height: r.height,
            depth: depth),
        fill: colour,
        strokeWidth: 0);

CanvasDocument page(List<CanvasElement> elements, {int frames = 24}) =>
    CanvasDocument(
        frames: frames,
        frameRate: 24,
        size: const CanvasSize(width: 320, ratio: CanvasRatio.wide),
        background: const CanvasBackground(
            spec: ProceduralSpec(background: Color(0xFFFFFFFF))),
        elements: elements);

Future<(ByteData, int, int)> render(CanvasDocument doc, {int frame = 0}) async {
  var image = await renderFrame(doc, frame: frame);
  var raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  var out = (raw, image.width, image.height);
  image.dispose();
  return out;
}

/// soft counts the pixels part way between white and red: an edge that
/// is blurred has many, a sharp one few.
int soft(ByteData raw, int w, Rect within) {
  var n = 0;
  for (var y = within.top.toInt(); y < within.bottom; y++) {
    for (var x = within.left.toInt(); x < within.right; x++) {
      var g = raw.getUint8((y * w + x) * 4 + 1);
      if (g > 30 && g < 225) n++;
    }
  }
  return n;
}

void main() {
  test("kept: an element's depth and a camera's lens", () {
    const cam = CameraElement(ElementBase(id: "c", width: 320, height: 180),
        focus: 0.5,
        focusOn: "a",
        blur: 8,
        parallax: 0.4,
        vignette: 0.3,
        vignetteSoft: 0.7,
        motionBlur: 0.5);
    var back = elementFromJson(cam.toJson()) as CameraElement;
    expect([
      back.focus,
      back.focusOn,
      back.blur,
      back.parallax,
      back.vignette,
      back.vignetteSoft,
      back.motionBlur
    ], [
      0.5,
      "a",
      8,
      0.4,
      0.3,
      0.7,
      0.5
    ]);
    var s = square("s", const Rect.fromLTWH(0, 0, 10, 10), depth: -0.6);
    expect(elementFromJson(s.toJson()).base.depth, -0.6);
  });

  test("rolled, it comes in close enough to keep the page filled", () {
    var doc = page([
      const CameraElement(ElementBase(id: "c", width: 320, height: 180)),
    ]);
    var rolled = doc.withElement(const CameraElement(
        ElementBase(id: "c", width: 320, height: 180, rotation: 90)));
    expect(cameraFraming(doc.elementById("c") as CameraElement, 0, doc).$1, 1);
    expect(
        cameraFraming(rolled.elementById("c") as CameraElement, 0, rolled).$1,
        closeTo(320 / 180, 1e-9));
  });

  test("rolled, the picture turns the other way, and never shows past it",
      () async {
    // A red band across the top of the page: rolled a quarter turn, it is
    // along a side.
    var flat = page([
      square("band", const Rect.fromLTWH(0, 0, 320, 40)),
      const CameraElement(ElementBase(id: "c", width: 320, height: 180)),
    ]);
    var (r0, w, h) = await render(flat);
    bool redAt(ByteData raw, int x, int y) =>
        raw.getUint8((y * w + x) * 4 + 1) < 60;
    expect(redAt(r0, w ~/ 2, 5), isTrue);
    var rolled = flat.withElement(const CameraElement(
        ElementBase(id: "c", width: 320, height: 180, rotation: 30)));
    var (r1, _, _) = await render(rolled);
    // Top middle no longer red all the way: the band is tilted.
    var reds = 0;
    for (var x = 0; x < w; x++) {
      if (redAt(r1, x, 5)) reds++;
    }
    expect(reds, lessThan(w * 0.9));
    // The corners are page, not nothing.
    expect(r1.getUint8(3), 255, reason: "opaque at the corner");
  });

  test("depth of field: the far is soft, what is in focus sharp", () async {
    CanvasDocument with_(double blur) => page([
          square("near", const Rect.fromLTWH(30, 50, 80, 80)),
          square("far", const Rect.fromLTWH(200, 50, 80, 80), depth: 1),
          CameraElement(const ElementBase(id: "c", width: 320, height: 180),
              blur: blur),
        ]);
    var (sharp, w, _) = await render(with_(0));
    var (dof, _, _) = await render(with_(6));
    var near = const Rect.fromLTWH(20, 40, 100, 100);
    var far = const Rect.fromLTWH(190, 40, 100, 100);
    expect(soft(dof, w, far), greaterThan(soft(sharp, w, far) + 200),
        reason: "the far square's edges spread");
    expect(soft(dof, w, near), lessThan(soft(sharp, w, near) + 20),
        reason: "the near one, on the focus, stays as it was");
  });

  test("focus pulled: keyed, the soft one changes over the move", () async {
    var doc = page([
      square("near", const Rect.fromLTWH(30, 50, 80, 80)),
      square("far", const Rect.fromLTWH(200, 50, 80, 80), depth: 1),
      CameraElement(
          ElementBase(
              id: "c",
              width: 320,
              height: 180,
              track: ElementTrack(const [
                Keyframe(frame: 0, values: {"focus": 0}),
                Keyframe(frame: 20, values: {"focus": 1}),
              ])),
          blur: 6),
    ]);
    var cam = doc.elementById("c") as CameraElement;
    expect(cameraLookAt(cam, 0, doc).focus, 0);
    expect(cameraLookAt(cam, 20, doc).focus, 1);
    var (end, w, _) = await render(doc, frame: 20);
    expect(
        soft(end, w, const Rect.fromLTWH(20, 40, 100, 100)), greaterThan(200),
        reason: "at the end the near is the soft one");
  });

  test("parallax: panned, the far moves less than the near", () async {
    // Twice as close, looking right of the middle.
    CanvasDocument with_(double parallax) => page([
          square("far", const Rect.fromLTWH(150, 80, 20, 20), depth: 1),
          CameraElement(
              const ElementBase(id: "c", x: 120, y: 45, width: 160, height: 90),
              parallax: parallax),
        ]);
    Future<double> farX(CanvasDocument d) async {
      var (raw, w, h) = await render(d);
      var sum = 0.0, n = 0;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          if (raw.getUint8((y * w + x) * 4 + 1) < 60) {
            sum += x;
            n++;
          }
        }
      }
      return n == 0 ? double.nan : sum / n;
    }

    var flat = await farX(with_(0));
    var deep = await farX(with_(0.5));
    // The camera looks right of the page's middle: the far square, which
    // is left of where it looks, sits further right -- moved less.
    expect(deep, greaterThan(flat + 5));
  });

  test("vignette: the corners darker than the middle", () async {
    var (raw, w, h) = await render(page([
      const CameraElement(ElementBase(id: "c", width: 320, height: 180),
          vignette: 0.8),
    ]));
    int grey(int x, int y) => raw.getUint8((y * w + x) * 4);
    expect(grey(w ~/ 2, h ~/ 2), greaterThan(240));
    expect(grey(2, 2), lessThan(150));
  });

  test("motion blur: a fast move is smeared, a still one is not", () async {
    CanvasDocument with_(double blur) => page([
          square("s", const Rect.fromLTWH(140, 70, 40, 40)),
          CameraElement(
              ElementBase(
                  id: "c",
                  x: 80,
                  y: 45,
                  width: 160,
                  height: 90,
                  track: ElementTrack(const [
                    Keyframe(frame: 0, dx: -60),
                    Keyframe(frame: 2, dx: 60),
                  ])),
              motionBlur: blur),
        ], frames: 4);
    var (sharp, w, _) = await render(with_(0), frame: 1);
    var (smeared, _, _) = await render(with_(1), frame: 1);
    var all = Rect.fromLTWH(0, 0, w.toDouble(), 180);
    expect(soft(smeared, w, all), greaterThan(soft(sharp, w, all) + 300));
  });

  // The settings: a key for the focus, and once keyed, the focus changed
  // later keys it there -- a focus pull, made in the panel.
  testWidgets("the focus keyed from its settings, and pulled", (tester) async {
    var c = CanvasController(page([
      square("a", const Rect.fromLTWH(30, 50, 80, 80)),
      const CameraElement(ElementBase(id: "c", width: 320, height: 180),
          blur: 6),
    ]));
    addTearDown(c.dispose);
    c.selectOnly("c");
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
      create: (_) => ThemeNotifier(doLoad: false),
      child: MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 340,
                  child: SingleChildScrollView(
                      child: ListenableBuilder(
                          listenable: c,
                          builder: (context, _) => Column(
                              children: elementSettings(context, c,
                                  c.document.elementById("c")!))))))),
    ));
    await tester.pumpAndSettle();
    // Its settings are there: framing, depth of field, parallax, lens.
    for (var k in [
      "cameraZoom",
      "cameraRoll",
      "cameraFocusOn",
      "cameraBlur",
      "cameraParallax",
      "cameraVignette",
      "cameraMotionBlur",
    ]) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
    await tester.ensureVisible(find.byKey(const ValueKey("cameraKey-focus")));
    await tester.tap(find.byKey(const ValueKey("cameraKey-focus")));
    await tester.pumpAndSettle();
    var cam = c.document.elementById("c") as CameraElement;
    expect(cam.track!.keyAt(0)!.values["focus"], 0);
    // Later on, a new focus is a key there.
    c.frame = 20;
    await tester.pumpAndSettle();
    await typeNumber(tester, "cameraFocus", "100");
    cam = c.document.elementById("c") as CameraElement;
    expect(cam.track!.keyAt(20)!.values["focus"], closeTo(1, 1e-9));
    expect(cam.focus, 0, reason: "the setting itself left as it was");
    expect(cameraLookAt(cam, 10, c.document).focus, closeTo(0.5, 0.01));
  });
}
