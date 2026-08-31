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

  group("a line's ends", () {
    LineElement line({
      double curvature = 0,
      LineEnd start = LineEnd.arrow,
      LineEnd end = LineEnd.arrow,
    }) =>
        LineElement(
          const ElementBase(id: "l", x: 0, y: 0, width: 200, height: 0),
          curvature: curvature,
          startEnd: start,
          endEnd: end,
          strokeWidth: 4,
        );

    test("the painter, the hit test and the ends share one control point", () {
      // The bow was written out twice and the arrowheads used neither, which
      // is how they ended up pointing somewhere the curve does not go.
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

    test("a straight line's control point is its own midpoint", () {
      var straight = line();
      expect(lineControlPoint(straight),
          (straight.start + straight.end) / 2);
    });

    test("the selection box leaves room for what is on the ends", () {
      // An arrowhead reaches three and a half stroke widths past the point the
      // line stops at, so a box sized for the stroke alone cut it in half.
      var plain = line(start: LineEnd.none, end: LineEnd.none);
      var arrowed = line();
      var withArrows = visualBoundsOf(arrowed, null, 0);
      var without = visualBoundsOf(plain, null, 0);
      expect(withArrows.width, greaterThan(without.width));
      expect(withArrows.height, greaterThan(without.height));
    });

    test("a bar reaches less far than an arrow", () {
      expect(LineEnd.bar.reach, lessThan(LineEnd.arrow.reach));
      expect(LineEnd.none.reach, 0);
    });

    test("only the pointed ends need the stroke cut back", () {
      // The trim exists so a thick stroke does not run on underneath a barb
      // and poke out of its sides. A dot or a bar sits on the end and needs
      // no room made for it.
      expect(LineEnd.arrow.isPointed, isTrue);
      expect(LineEnd.openArrow.isPointed, isTrue);
      expect(LineEnd.hollowArrow.isPointed, isTrue);
      expect(LineEnd.circle.isPointed, isFalse);
      expect(LineEnd.bar.isPointed, isFalse);
      expect(LineEnd.none.isPointed, isFalse);
    });

    test("each end is its own setting and survives a round trip", () {
      var element = line(start: LineEnd.circle, end: LineEnd.hollowDiamond)
          .copyWith(cap: LineStrokeCap.round);
      var back = CanvasDocument.decode(
              CanvasDocument(elements: [element]).encode())!.elements.single
          as LineElement;

      expect(back.startEnd, LineEnd.circle);
      expect(back.endEnd, LineEnd.hollowDiamond);
      expect(back.cap, LineStrokeCap.round);
    });

    test("a document saved before the split still opens", () {
      // One "cap" used to mean both the stroke's cap and its decoration. Each
      // old value maps onto the pair it actually meant.
      LineElement load(String cap) => LineElement.fromJson(
            {"cap": cap, "sw": 4.0},
            const ElementBase(id: "l"),
          );

      expect(load("arrow").endEnd, LineEnd.arrow);
      expect(load("arrow").startEnd, LineEnd.none);
      expect(load("arrow").cap, LineStrokeCap.flat);

      expect(load("arrowBoth").startEnd, LineEnd.arrow);
      expect(load("arrowBoth").endEnd, LineEnd.arrow);

      expect(load("dot").startEnd, LineEnd.circle);
      expect(load("dot").endEnd, LineEnd.circle);
      expect(load("dot").cap, LineStrokeCap.round);

      expect(load("round").cap, LineStrokeCap.round);
      expect(load("round").endEnd, LineEnd.none,
          reason: "a round cap was never a decoration");
    });

    test("a new document with no ends does not read as an old one", () {
      // The migration keys off the absence of the new fields, so a line that
      // deliberately has no decorations must still say so.
      var plain = line(start: LineEnd.none, end: LineEnd.none);
      var back = CanvasDocument.decode(
              CanvasDocument(elements: [plain]).encode())!.elements.single
          as LineElement;
      expect(back.startEnd, LineEnd.none);
      expect(back.endEnd, LineEnd.none);
    });

    testWidgets("an arrowhead sits behind the tip, along the line",
        (tester) async {
      // The one that kept getting away. Tangent.angle is *minus* atan2(dy, dx)
      // -- anticlockwise, the way a mathematician draws axes -- while the
      // canvas has y growing downwards, so using it flipped every decoration
      // about the horizontal. On a diagonal the arrowhead pointed into the
      // wrong quadrant and sat off the end of the line.
      //
      // Diagonal deliberately: the flip is invisible on a horizontal line,
      // which is exactly why it survived two attempts at this.
      const size = 240;
      var document = const CanvasDocument(
        size: CanvasSize(ratio: CanvasRatio.square, width: size),
        background: CanvasBackground(),
        elements: [
          LineElement(
            ElementBase(id: "l", x: 20, y: 20, width: 200, height: 200),
            strokeWidth: 5,
            endEnd: LineEnd.arrow,
          ),
        ],
      );

      late List<Offset> ink;
      await tester.runAsync(() async {
        var recorder = ui.PictureRecorder();
        paintCanvasDocument(ui.Canvas(recorder), document);
        var image = await recorder.endRecording().toImage(size, size);
        var data = await image.toByteData();
        ink = [
          for (var y = 0; y < size; y++)
            for (var x = 0; x < size; x++)
              if (data!.getUint8((y * size + x) * 4 + 3) > 60 &&
                  data.getUint8((y * size + x) * 4) > 150)
                Offset(x.toDouble(), y.toDouble()),
        ];
      });

      expect(ink, isNotEmpty);

      // The line runs from (20,20) to (220,220), so the tip is bottom-right
      // and the barbs must lie back up the line, towards the top-left.
      const tip = Offset(220, 220);
      var near = ink.where((p) => (p - tip).distance < 26).toList();
      expect(near.length, greaterThan(20), reason: "the head is drawn at all");

      var centroid = near.reduce((a, b) => a + b) / near.length.toDouble();
      var back = centroid - tip;
      expect(back.dx, lessThan(-2), reason: "the head lies back along the line");
      expect(back.dy, lessThan(-2));
      // And squarely on the line rather than off to one side: for a 45-degree
      // line the two components of the offset are equal.
      expect(back.dx, closeTo(back.dy, 4),
          reason: "it is seated on the line, not rotated off it");
    });

    testWidgets("a start arrow points the other way", (tester) async {
      const size = 240;
      var document = const CanvasDocument(
        size: CanvasSize(ratio: CanvasRatio.square, width: size),
        background: CanvasBackground(),
        elements: [
          LineElement(
            ElementBase(id: "l", x: 20, y: 20, width: 200, height: 200),
            strokeWidth: 5,
            startEnd: LineEnd.arrow,
          ),
        ],
      );

      late List<Offset> ink;
      await tester.runAsync(() async {
        var recorder = ui.PictureRecorder();
        paintCanvasDocument(ui.Canvas(recorder), document);
        var image = await recorder.endRecording().toImage(size, size);
        var data = await image.toByteData();
        ink = [
          for (var y = 0; y < size; y++)
            for (var x = 0; x < size; x++)
              if (data!.getUint8((y * size + x) * 4 + 3) > 60 &&
                  data.getUint8((y * size + x) * 4) > 150)
                Offset(x.toDouble(), y.toDouble()),
        ];
      });

      const tip = Offset(20, 20);
      var near = ink.where((p) => (p - tip).distance < 26).toList();
      expect(near.length, greaterThan(20));
      var back = (near.reduce((a, b) => a + b) / near.length.toDouble()) - tip;
      expect(back.dx, greaterThan(2),
          reason: "the head at the start lies back down the line");
      expect(back.dy, greaterThan(2));
    });

    /// inkNear is the drawn pixels within [radius] of [point].
    Future<List<Offset>> inkNear(WidgetTester tester, CanvasDocument document,
        Offset point, double radius) async {
      var size = document.size.width;
      late List<Offset> out;
      await tester.runAsync(() async {
        var recorder = ui.PictureRecorder();
        paintCanvasDocument(ui.Canvas(recorder), document);
        var image = await recorder.endRecording().toImage(size, size);
        var data = await image.toByteData();
        out = [
          for (var y = 0; y < size; y++)
            for (var x = 0; x < size; x++)
              if (data!.getUint8((y * size + x) * 4 + 3) > 60 &&
                  data.getUint8((y * size + x) * 4) > 150 &&
                  (Offset(x.toDouble(), y.toDouble()) - point).distance < radius)
                Offset(x.toDouble(), y.toDouble()),
        ];
      });
      return out;
    }

    CanvasDocument withEnd(LineEnd end, {double endSize = 1}) => CanvasDocument(
          size: const CanvasSize(ratio: CanvasRatio.square, width: 240),
          background: const CanvasBackground(),
          elements: [
            LineElement(
              // A height of its own: paintElement skips an element with an
              // empty box, so a line whose two corners share a row draws
              // nothing at all.
              const ElementBase(id: "l", x: 20, y: 116, width: 180, height: 8),
              strokeWidth: 6,
              endEnd: end,
              endSize: endSize,
            ),
          ],
        );

    testWidgets("a hollow end is not filled in by the line running through it",
        (tester) async {
      // The reported fault: a ring with the stroke visible through the middle
      // of it. The stroke is cut back to where every decoration begins now,
      // not only the pointed ones.
      const tip = Offset(200, 124);
      var hollow = await inkNear(tester, withEnd(LineEnd.hollowCircle), tip, 2);
      var solid = await inkNear(tester, withEnd(LineEnd.circle), tip, 2);

      expect(solid, isNotEmpty, reason: "a solid circle is filled");
      // Not quite empty: the ring's inner edge is anti-aliased and its blur
      // reaches a pixel or two inwards. What matters is that the middle is
      // nothing like as covered as a filled one.
      expect(hollow.length, lessThan(solid.length / 4),
          reason: "the middle of a hollow one shows the canvas, not the line");
    });

    testWidgets("a hollow diamond is hollow too", (tester) async {
      const tip = Offset(200, 124);
      var hollow = await inkNear(tester, withEnd(LineEnd.hollowDiamond), tip, 2);
      var solid = await inkNear(tester, withEnd(LineEnd.diamond), tip, 2);
      expect(hollow.length, lessThan(solid.length / 4));
    });

    testWidgets("a diamond sits centred on the end, not behind it",
        (tester) async {
      // Hung off the back, its forward point sat on the end and the whole
      // shape trailed down the line.
      const tip = Offset(200, 124);
      var plain = await inkNear(tester, withEnd(LineEnd.none), tip, 40);
      var ink = await inkNear(tester, withEnd(LineEnd.diamond), tip, 40);
      expect(ink, isNotEmpty);

      // Ahead of the end only the decoration can be drawing, so its forward
      // reach is measurable without the line confusing the count. Centred on
      // the end, it should reach forward about as far as it reaches back --
      // hung off the back, it reached forward not at all.
      var forward = ink.map((p) => p.dx).reduce(math.max) - tip.dx;
      var plainForward =
          plain.isEmpty ? 0.0 : plain.map((p) => p.dx).reduce(math.max) - tip.dx;
      expect(plainForward, lessThan(4),
          reason: "with no decoration nothing is drawn past the end");
      // long is strokeWidth * 1.7 = 10.2 at this weight.
      expect(forward, closeTo(10.2, 3),
          reason: "half the diamond stands past the line's end");
    });

    testWidgets("end size scales what is drawn", (tester) async {
      const tip = Offset(200, 124);
      var small = await inkNear(tester, withEnd(LineEnd.arrow), tip, 60);
      var large =
          await inkNear(tester, withEnd(LineEnd.arrow, endSize: 2), tip, 60);
      // Not four times, even though the area is: the bigger head also cuts
      // more of the stroke away behind it, and some of it falls outside the
      // window being counted.
      expect(large.length, greaterThan(small.length * 1.4),
          reason: "twice the size is visibly more ink");
    });

    test("end size survives a round trip and scales the selection box", () {
      var element = LineElement(
        const ElementBase(id: "l", x: 0, y: 0, width: 200, height: 0),
        strokeWidth: 4,
        endEnd: LineEnd.arrow,
        endSize: 3,
      );
      var back = CanvasDocument.decode(
              CanvasDocument(elements: [element]).encode())!.elements.single
          as LineElement;
      expect(back.endSize, 3);

      var big = visualBoundsOf(element, null, 0);
      var normal = visualBoundsOf(element.copyWith(endSize: 1), null, 0);
      expect(big.width, greaterThan(normal.width),
          reason: "a bigger arrow needs a bigger box");
    });

    test("a bar is the one end the line should reach", () {
      // It crosses the line rather than sitting on the end of it, so cutting
      // the stroke back would leave a gap before it.
      expect(LineEnd.bar.cover, 0);
      expect(LineEnd.none.cover, 0);
      for (var end in LineEnd.values) {
        if (end == LineEnd.bar || end == LineEnd.none) continue;
        expect(end.cover, greaterThan(0), reason: end.name);
      }
    });

    test("every end draws without throwing, bowed and straight", () {
      for (var end in LineEnd.values) {
        for (var bow in [0.0, 0.5, -0.5]) {
          var document = CanvasDocument(
            size: const CanvasSize(width: 200),
            elements: [line(curvature: bow, start: end, end: end)],
          );
          expect(
              () => paintCanvasDocument(
                  ui.Canvas(ui.PictureRecorder()), document),
              returnsNormally,
              reason: "${end.name} at bow $bow");
        }
      }
    });
  });
}
