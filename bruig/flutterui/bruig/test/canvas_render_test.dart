import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/presets/builtin_presets.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_render_test.dart draws things and looks at the pixels.
//
// Everything under render/ is a painter, and a painter is the kind of code
// that fails by drawing nothing at all -- a clip in the wrong place, a colour
// with no alpha, a rectangle computed inside out. None of that throws, and a
// test that only checked it did not throw would pass on a blank canvas.
//
// So each test here renders and then reads a pixel it can name a reason for.

/// _pixelAt reads one pixel of a rendered document, in 0..255 RGBA.
Future<List<int>> _pixelAt(CanvasDocument document, int x, int y,
    {int frame = 0, double scale = 1}) async {
  var image = await renderFrame(document, frame: frame, scale: scale);
  try {
    var raw =
        await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    var pixels = raw!.buffer.asUint8List();
    var i = (y * image.width + x) * 4;
    return [pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]];
  } finally {
    image.dispose();
  }
}

void main() {
  group("a squad number", () {
    // Loaded from the app's own asset, because the question this group asks
    // cannot be asked of the test font. flutter_test draws everything in Ahem,
    // whose glyphs are solid rectangles filling the whole em -- it has no cap
    // height, no bearing and no difference between a digit and a descender, so
    // measuring where "7" sits in Ahem measures nothing about where "7" sits.
    setUpAll(() async {
      var loader = FontLoader("Inter");
      loader.addFont(
          File("assets/fonts/Inter-Bold.otf").readAsBytes().then(
              (bytes) => ByteData.view(Uint8List.fromList(bytes).buffer)));
      await loader.load();
    });

    /// inkBounds is the tightest box around the pixels [paint] actually drew.
    ///
    /// Rendering and then measuring is the only honest way to ask this: the
    /// question is where the glyph *looks* like it is, and a line box, a
    /// baseline and a font's own metrics all answer something slightly
    /// different from that.
    Future<Rect?> inkBounds(void Function(ui.Canvas) paint, Size size) async {
      var recorder = ui.PictureRecorder();
      paint(ui.Canvas(recorder));
      var image = await recorder
          .endRecording()
          .toImage(size.width.round(), size.height.round());
      var data = await image.toByteData();
      if (data == null) return null;

      double? top, bottom, left, right;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          // Alpha of the RGBA pixel.
          if (data.getUint8((y * image.width + x) * 4 + 3) < 8) continue;
          top ??= y.toDouble();
          bottom = y.toDouble();
          left = left == null ? x.toDouble() : math.min(left, x.toDouble());
          right = right == null ? x.toDouble() : math.max(right, x.toDouble());
        }
      }
      if (top == null) return null;
      return Rect.fromLTRB(left!, top, right! + 1, bottom! + 1);
    }

    test("sits dead centre in its dot, where its line box would not",
        () async {
      // Centred by its line box, a digit sits visibly high in the circle: the
      // box reserves room for a descender the digit does not have, and that
      // empty strip under the baseline is counted as part of the glyph. At a
      // 60px dot it is a couple of pixels out -- small enough to look like a
      // mistake rather than a bug, and on every dot of a pitch at once.
      const size = Size(120, 120);
      var centre = Offset(size.width / 2, size.height / 2);
      const spec = TextSpec(
          fontFamily: "Inter",
          fontSize: 40,
          weight: 700,
          color: Color(0xFFFFFFFF));

      var ink = await inkBounds(
          (canvas) => paintCentredGlyphs(canvas, "7", spec, centre), size);
      expect(ink, isNotNull, reason: "the number must actually be drawn");

      expect(ink!.center.dx, closeTo(centre.dx, 1.5));
      expect(ink.center.dy, closeTo(centre.dy, 1.5),
          reason: "the ink's middle, not the line box's, is on the centre");

    });

    test("stays centred when the line height changes", () async {
      // This is what centring on the ink buys, and why it is worth the
      // approximation. The number shares one TextSpec with the names -- see
      // TeamElement.labelSpec -- so the line height is set for a two-line
      // name and the number has to survive it. Centred by its line box, the
      // number slides straight out of its dot as the leading grows; centred by
      // its ink it does not move at all.
      const size = Size(160, 160);
      var centre = Offset(size.width / 2, size.height / 2);
      const base = TextSpec(
          fontFamily: "Inter",
          fontSize: 40,
          weight: 700,
          color: Color(0xFFFFFFFF));

      for (var lineHeight in [1.0, 1.6, 2.4]) {
        var spec = base.copyWith(lineHeight: lineHeight);

        var ink = await inkBounds(
            (canvas) => paintCentredGlyphs(canvas, "7", spec, centre), size);
        expect(ink!.center.dy, closeTo(centre.dy, 1.5),
            reason: "line height $lineHeight");

        var boxCentred = await inkBounds((canvas) {
          var painter = layoutText("7", spec, maxWidth: double.infinity);
          painter.paint(
              canvas,
              Offset(centre.dx - painter.width / 2,
                  centre.dy - painter.height / 2));
        }, size);
        if (lineHeight >= 2.4) {
          expect((boxCentred!.center.dy - centre.dy).abs(), greaterThan(4),
              reason: "the line box drifts where the ink does not");
        }
      }
    });

    test("stays centred whatever the digits", () async {
      // "1" is narrow, "10" is wide and "88" is wide and tall. All three have
      // to end up on the same centre, or a back four looks misaligned.
      const size = Size(160, 120);
      var centre = Offset(size.width / 2, size.height / 2);
      const spec = TextSpec(
          fontFamily: "Inter",
          fontSize: 36,
          weight: 700,
          color: Color(0xFFFFFFFF));

      for (var number in ["1", "7", "10", "88"]) {
        var ink = await inkBounds(
            (canvas) => paintCentredGlyphs(canvas, number, spec, centre), size);
        expect(ink, isNotNull, reason: number);
        expect(ink!.center.dx, closeTo(centre.dx, 1.5), reason: number);
        expect(ink.center.dy, closeTo(centre.dy, 1.5), reason: number);
      }
    });
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  test("an empty document renders at the size it says it is", () async {
    var document = const CanvasDocument(
        size: CanvasSize(ratio: CanvasRatio.wide, width: 320));
    var image = await renderFrame(document);
    expect(image.width, 320);
    expect(image.height, 180);
    image.dispose();
  });

  test("the export scale multiplies the pixels, not the design", () async {
    var document = const CanvasDocument(
        size: CanvasSize(ratio: CanvasRatio.square, width: 100));
    var image = await renderFrame(document, scale: 3);
    expect(image.width, 300);
    expect(image.height, 300);
    image.dispose();
  });

  test("the canvas background actually paints", () async {
    var document = const CanvasDocument(
      size: CanvasSize(ratio: CanvasRatio.square, width: 40),
      background: CanvasBackground(
        spec: ProceduralSpec(
          style: ProceduralStyle.plain,
          background: Color(0xFF203040),
          vignette: 0,
        ),
      ),
    );
    var pixel = await _pixelAt(document, 20, 20);
    expect(pixel[0], 0x20);
    expect(pixel[1], 0x30);
    expect(pixel[2], 0x40);
    expect(pixel[3], 255);
  });

  test("a shape lands where its bounds say", () async {
    // Drawn opaque red over an opaque black background, so a shape that failed
    // to paint, painted outside its bounds, or painted with no alpha all show
    // up as a different answer here.
    var document = CanvasDocument(
      size: const CanvasSize(ratio: CanvasRatio.square, width: 100),
      background: const CanvasBackground(
        spec: ProceduralSpec(
            style: ProceduralStyle.plain,
            background: Color(0xFF000000),
            vignette: 0),
      ),
      elements: [
        ShapeElement(
          const ElementBase(id: "s", x: 40, y: 40, width: 20, height: 20),
          shape: ShapeKind.rectangle,
          fill: const Color(0xFFFF0000),
        ),
      ],
    );

    expect((await _pixelAt(document, 50, 50)).sublist(0, 3), [255, 0, 0]);
    // Just outside it, on both axes.
    expect((await _pixelAt(document, 38, 50)).sublist(0, 3), [0, 0, 0]);
    expect((await _pixelAt(document, 50, 38)).sublist(0, 3), [0, 0, 0]);
  });

  test("a hidden element draws nothing", () async {
    var document = CanvasDocument(
      size: const CanvasSize(ratio: CanvasRatio.square, width: 40),
      background: const CanvasBackground(
        spec: ProceduralSpec(
            style: ProceduralStyle.plain,
            background: Color(0xFF000000),
            vignette: 0),
      ),
      elements: [
        ShapeElement(
          const ElementBase(
              id: "s", x: 0, y: 0, width: 40, height: 40, visible: false),
          fill: const Color(0xFFFF0000),
        ),
      ],
    );
    expect((await _pixelAt(document, 20, 20)).sublist(0, 3), [0, 0, 0]);
  });

  test("a keyframe moves the element it belongs to", () async {
    // The pose is a shift from the element's resting position, so this also
    // says the offsets are relative -- an absolute pose would put the shape
    // at 30,0 rather than at 30 past where it was drawn.
    var document = CanvasDocument(
      size: const CanvasSize(ratio: CanvasRatio.square, width: 100),
      frames: 11,
      background: const CanvasBackground(
        spec: ProceduralSpec(
            style: ProceduralStyle.plain,
            background: Color(0xFF000000),
            vignette: 0),
      ),
      elements: [
        ShapeElement(
          ElementBase(
            id: "s",
            x: 0,
            y: 40,
            width: 20,
            height: 20,
            track: ElementTrack(const [
              Keyframe(frame: 0),
              Keyframe(frame: 10, dx: 60),
            ]),
          ),
          fill: const Color(0xFFFF0000),
        ),
      ],
    );

    expect((await _pixelAt(document, 10, 50, frame: 0)).sublist(0, 3),
        [255, 0, 0]);
    expect((await _pixelAt(document, 10, 50, frame: 10)).sublist(0, 3),
        [0, 0, 0]);
    // Halfway along at the halfway frame, which is the interpolation itself.
    expect((await _pixelAt(document, 40, 50, frame: 5)).sublist(0, 3),
        [255, 0, 0]);
    expect((await _pixelAt(document, 70, 50, frame: 10)).sublist(0, 3),
        [255, 0, 0]);
  });

  test("opacity reaches the pixels", () async {
    var document = CanvasDocument(
      size: const CanvasSize(ratio: CanvasRatio.square, width: 40),
      background: const CanvasBackground(
        spec: ProceduralSpec(
            style: ProceduralStyle.plain,
            background: Color(0xFF000000),
            vignette: 0),
      ),
      elements: [
        ShapeElement(
          const ElementBase(
              id: "s", x: 0, y: 0, width: 40, height: 40, opacity: 0.5),
          fill: const Color(0xFFFFFFFF),
        ),
      ],
    );
    var pixel = await _pixelAt(document, 20, 20);
    expect(pixel[0], closeTo(128, 4));
  });

  test("every procedural style draws something and none throws", () async {
    // Fifteen generators, each with its own trigonometry. This is the cheapest
    // possible guard on all of them: a style that threw would fail the render,
    // and one that drew nothing would come back as the flat base colour.
    for (var style in ProceduralStyle.values) {
      var document = CanvasDocument(
        size: const CanvasSize(ratio: CanvasRatio.wide, width: 160),
        background: CanvasBackground(
          spec: ProceduralSpec(
            style: style,
            seed: 4,
            background: const Color(0xFF000000),
            foreground: const Color(0xFF00FF88),
            accent: const Color(0xFFFFFFFF),
            density: 0.9,
            intensity: 1,
            variation: 0.6,
            vignette: 0,
          ),
        ),
      );

      var image = await renderFrame(document);
      var raw =
          await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      var pixels = raw!.buffer.asUint8List();
      image.dispose();

      if (style == ProceduralStyle.plain) continue;
      var lit = 0;
      for (var i = 0; i < pixels.length; i += 4) {
        if (pixels[i] + pixels[i + 1] + pixels[i + 2] > 12) lit++;
      }
      expect(lit, greaterThan(20),
          reason: "${style.name} drew nothing on top of its base colour");
    }
  });

  test("the same seed gives the same picture twice", () async {
    // The whole reason the generators use a hash of the position rather than a
    // Random() walked in draw order. Without this, an exported frame would not
    // match the one on screen.
    const spec = ProceduralSpec(
      style: ProceduralStyle.ledGrid,
      seed: 99,
      density: 0.8,
      intensity: 1,
      vignette: 0,
    );
    var document = const CanvasDocument(
      size: CanvasSize(ratio: CanvasRatio.square, width: 80),
      background: CanvasBackground(spec: spec),
    );

    var a = await renderPng(document);
    var b = await renderPng(document);
    expect(a!.data, equals(b!.data));
  });

  test("a different seed gives a different picture", () async {
    var one = await renderPng(const CanvasDocument(
      size: CanvasSize(ratio: CanvasRatio.square, width: 80),
      background: CanvasBackground(
          spec: ProceduralSpec(
              style: ProceduralStyle.ledGrid,
              seed: 1,
              density: 0.8,
              vignette: 0)),
    ));
    var two = await renderPng(const CanvasDocument(
      size: CanvasSize(ratio: CanvasRatio.square, width: 80),
      background: CanvasBackground(
          spec: ProceduralSpec(
              style: ProceduralStyle.ledGrid,
              seed: 2,
              density: 0.8,
              vignette: 0)),
    ));
    expect(one!.data, isNot(equals(two!.data)));
  });

  test("the scale changes the pixels, not the composition", () async {
    // A canvas rendered at twice the size must be the same picture larger --
    // which is only true if every generator sizes itself to the frame rather
    // than to a number of pixels.
    var document = const CanvasDocument(
      size: CanvasSize(ratio: CanvasRatio.square, width: 60),
      background: CanvasBackground(
          spec: ProceduralSpec(
              style: ProceduralStyle.hexGrid,
              seed: 3,
              density: 0.7,
              vignette: 0)),
    );
    var small = await renderFrame(document);
    var large = await renderFrame(document, scale: 2);
    expect(large.width, small.width * 2);
    // Corresponding points, which land in the same cell of the pattern.
    var a = await _pixelAt(document, 30, 30);
    var b = await _pixelAt(document, 60, 60, scale: 2);
    for (var channel = 0; channel < 3; channel++) {
      expect(b[channel], closeTo(a[channel], 60), reason: "channel $channel");
    }
    small.dispose();
    large.dispose();
  });

  test("every preset renders to a PNG with something on it", () async {
    for (var preset in builtinPresets) {
      var export = await renderPng(preset.build(), scale: 0.25);
      expect(export, isNotNull, reason: preset.id);
      expect(export!.mime, "image/png");
      // A PNG of a blank canvas is tiny. Anything with a design on it is not.
      expect(export.bytes, greaterThan(400), reason: preset.id);
    }
  });

  test("an animation renders to a decodable GIF of the right length",
      () async {
    var document = footballCanvas().copyWith(frames: 4, frameRate: 8);
    var export = await renderGif(document, scale: 0.15);
    expect(export, isNotNull);
    expect(export!.mime, "image/gif");

    var codec = await ui.instantiateImageCodec(export.data);
    expect(codec.frameCount, 4);
    codec.dispose();
  });

  test("the size estimate is in the right order of magnitude", () async {
    // Only ever used to answer "will this fit in a message", so being within a
    // factor of five of the real thing is the whole requirement. What would be
    // a bug is being out by a hundred in either direction, which is what an
    // estimate that ignored the background would be.
    for (var preset in builtinPresets) {
      var document = preset.build();
      var real = (await renderPng(document))!.bytes;
      var guess = estimateStillBytes(document);
      expect(guess, greaterThan(real / 8),
          reason: "${preset.id}: guessed $guess against $real");
      expect(guess, lessThan(real * 8),
          reason: "${preset.id}: guessed $guess against $real");
    }
  });

  group("a line's arrowheads", () {
    LineElement line({double curvature = 0}) => LineElement(
          const ElementBase(id: "l", x: 0, y: 0, width: 200, height: 0),
          curvature: curvature,
          cap: LineCapStyle.arrowBoth,
          strokeWidth: 4,
        );

    test("a straight line's arrows follow the chord", () {
      var (atStart, atEnd) = lineTangents(line());
      // Left to right along the x axis.
      expect(atStart, closeTo(0, 0.0001));
      expect(atEnd, closeTo(0, 0.0001));
    });

    test("a bowed line's arrows follow the curve, not the chord", () {
      // The reported fault: the arrowheads took the chord's direction whatever
      // the bow, so on a curve they sat askew with the tail across the line
      // instead of flat against the end of it.
      var bowed = line(curvature: 0.4);
      var (atStart, atEnd) = lineTangents(bowed);
      var chord = math.atan2(
          bowed.end.dy - bowed.start.dy, bowed.end.dx - bowed.start.dx);

      expect((atStart - chord).abs(), greaterThan(0.5),
          reason: "the curve leaves the start at a very different angle");
      expect((atEnd - chord).abs(), greaterThan(0.5));
      // Symmetrical: it leaves as steeply as it arrives, the other way up.
      expect(atStart + atEnd, closeTo(2 * chord, 0.0001));
    });

    test("the tangent turns with the bow", () {
      var up = lineTangents(line(curvature: 0.3)).$1;
      var down = lineTangents(line(curvature: -0.3)).$1;
      expect(up, closeTo(-down, 0.0001),
          reason: "bowing the other way points the arrow the other way");
    });

    test("a zero-length line falls back to the chord rather than nothing", () {
      var degenerate = LineElement(
        const ElementBase(id: "l", x: 10, y: 10, width: 0, height: 0),
        curvature: 0.5,
      );
      var (atStart, atEnd) = lineTangents(degenerate);
      expect(atStart.isFinite, isTrue);
      expect(atEnd.isFinite, isTrue);
    });

    test("the painter, the hit test and the arrows share one control point",
        () {
      // They were written out twice and the arrowheads used neither, which is
      // how the arrows ended up pointing somewhere the curve does not go.
      var bowed = line(curvature: 0.35);
      var control = lineControlPoint(bowed);
      var curve = curveOfElement(bowed)!;

      // The apex of a quadratic is at t=0.5, half way between the chord's
      // midpoint and the control point.
      var mid = (bowed.start + bowed.end) / 2;
      var apex = Offset((mid.dx + control.dx) / 2, (mid.dy + control.dy) / 2);
      var nearest = curve.reduce(
          (a, b) => (a - apex).distance < (b - apex).distance ? a : b);
      expect((nearest - apex).distance, lessThan(1),
          reason: "the walked curve passes through the painter's own apex");
    });
  });
}
