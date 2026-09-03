import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/presets/builtin_presets.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
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

/// _Pictures is a CanvasImageSource holding one already-decoded picture,
/// which is what a renderer test needs and what the real store cannot be: the
/// store reads a file and decodes it asynchronously, and answers null until it
/// has, so a frame rendered through it would have no picture in it.
class _Pictures implements CanvasImageSource {
  final ui.Image image;
  _Pictures(this.image);

  @override
  ui.Image? resolve(String assetId, BackgroundRemoval removal) => image;
}

/// _cutOut is a picture shaped like a cut-out: a solid square of [colour] in
/// the middle of [size], transparent everywhere else. An outline traces the
/// alpha channel, so this is the smallest thing that has one worth tracing.
Future<ui.Image> _cutOut(int size, ui.Color colour) {
  var pixels = Uint8List(size * size * 4);
  var from = size ~/ 4, to = size - size ~/ 4;
  for (var y = from; y < to; y++) {
    for (var x = from; x < to; x++) {
      var i = (y * size + x) * 4;
      // Premultiplied is the same as straight at full alpha, which is all
      // this picture has.
      pixels[i] = (colour.r * 255).round();
      pixels[i + 1] = (colour.g * 255).round();
      pixels[i + 2] = (colour.b * 255).round();
      pixels[i + 3] = 255;
    }
  }
  var done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      pixels, size, size, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

/// _softBlob is a dark disc with a soft alpha ramp round it, which is what a
/// cut-out actually looks like: a background taken out of a photograph leaves
/// a rim of half-transparent pixels, and that rim is where an outline drawn in
/// two overlapping pieces gives itself away.
Future<ui.Image> _softBlob(int size) {
  var pixels = Uint8List(size * size * 4);
  var centre = size / 2;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      var away = math.sqrt(
          math.pow(x - centre, 2).toDouble() + math.pow(y - centre, 2));
      var alpha = ((size * 0.25 - away) / 4).clamp(0.0, 1.0);
      var i = (y * size + x) * 4;
      pixels[i] = (40 * alpha).round();
      pixels[i + 3] = (255 * alpha).round();
    }
  }
  var done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      pixels, size, size, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

/// _rowOf reads one channel straight across the middle of a rendered document.
Future<List<int>> _rowOf(CanvasDocument document, CanvasImageSource images,
    int channel, int y) async {
  var image = await renderFrame(document, images: images);
  try {
    var raw = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    var pixels = raw!.buffer.asUint8List();
    return [
      for (var x = 0; x < image.width; x++)
        pixels[(y * image.width + x) * 4 + channel]
    ];
  } finally {
    image.dispose();
  }
}

/// _renderWith is _pixelAt for a document with a picture in it.
Future<List<int>> _renderWith(
    CanvasDocument document, CanvasImageSource images, int x, int y) async {
  var image = await renderFrame(document, images: images);
  try {
    var raw = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
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

  group("the speech bubble", () {
    const spec = SpeechBubbleSpec();
    const box = Rect.fromLTWH(0, 0, 200, 120);

    test("is one outline, not a body with a tail laid over it", () {
      // The reported fault. Filled, two sub-paths merge; *stroked*, each draws
      // its own boundary, so a line ran across the join and the tail read as a
      // separate shape stuck on the side.
      var path = bubblePath(box, spec, 0);
      expect(path.computeMetrics().length, 1,
          reason: "one closed contour means one boundary to stroke");
    });

    test("a thought tail is deliberately several contours", () {
      // It is a trail of separate circles; unioning them into the body would
      // weld the lot into a sausage.
      var path = bubblePath(
          box, spec.copyWith(tail: BubbleTail.thought), 0);
      expect(path.computeMetrics().length, greaterThan(1));
    });

    test("the tail goes all the way round", () {
      // It used to be nailed to the bottom-left corner.
      Rect tailBox(double angle) {
        var whole = bubblePath(box, spec.copyWith(tailAngle: angle), 0)
            .getBounds();
        return whole;
      }

      // Pointing right, the outline reaches further right than the body does;
      // pointing left, further left.
      var body = bubbleBodyRect(box, spec.copyWith(tailAngle: 0));
      expect(tailBox(0).right, greaterThan(body.right));
      expect(tailBox(180).left, lessThan(bubbleBodyRect(
              box, spec.copyWith(tailAngle: 180))
          .left));
      expect(tailBox(90).bottom,
          greaterThan(bubbleBodyRect(box, spec.copyWith(tailAngle: 90)).bottom));
      expect(tailBox(270).top,
          lessThan(bubbleBodyRect(box, spec.copyWith(tailAngle: 270)).top));
    });

    test("the body gives up room only on the side the tail points", () {
      // Insetting all four sides equally would shrink the bubble by the tail's
      // length however short a tail it had, and a bubble is mostly its body.
      var right = bubbleBodyRect(box, spec.copyWith(tailAngle: 0));
      expect(right.left, box.left, reason: "the far side is untouched");
      expect(right.right, lessThan(box.right));

      var down = bubbleBodyRect(box, spec.copyWith(tailAngle: 90));
      expect(down.top, box.top);
      expect(down.bottom, lessThan(box.bottom));
    });

    test("no tail leaves the whole box to the body", () {
      expect(bubbleBodyRect(box, spec.copyWith(tail: BubbleTail.none)), box);
    });

    test("a longer tail takes its room from the body, not from the box", () {
      // The whole bubble stays inside the element's rectangle whatever the
      // tail does, which is what keeps the selection box honest.
      var normal = spec.copyWith(tailAngle: 0);
      var longer = spec.copyWith(tailAngle: 0, tailLength: 1.0);

      expect(bubbleBodyRect(box, longer).width,
          lessThan(bubbleBodyRect(box, normal).width),
          reason: "the body gives way");
      expect(bubblePath(box, longer, 0).getBounds().right,
          closeTo(box.right, 1),
          reason: "and the tip still finishes at the edge of the box");
    });

    test("every body and tail builds a usable path", () {
      for (var body in BubbleBody.values) {
        for (var tail in BubbleTail.values) {
          var path = bubblePath(
              box, spec.copyWith(body: body, tail: tail), 0);
          expect(path.getBounds().isEmpty, isFalse,
              reason: "${body.name} with ${tail.name}");
        }
      }
    });

    test("the bubble's settings survive a round trip", () {
      var element = ShapeElement(
        const ElementBase(id: "s", width: 200, height: 120),
        shape: ShapeKind.speechBubble,
        bubble: const SpeechBubbleSpec(
          body: BubbleBody.cloud,
          tail: BubbleTail.curved,
          tailAngle: 240,
          tailLength: 0.8,
          tailWidth: 0.5,
          curl: -1.1,
        ),
      );
      var back = CanvasDocument.decode(
              CanvasDocument(elements: [element]).encode())!.elements.single
          as ShapeElement;

      expect(back.bubble.body, BubbleBody.cloud);
      expect(back.bubble.tail, BubbleTail.curved);
      expect(back.bubble.tailAngle, 240);
      expect(back.bubble.tailLength, 0.8);
      expect(back.bubble.curl, -1.1);
    });

    test("a shape that is not a bubble carries none of it into the file", () {
      var star = ShapeElement(
        const ElementBase(id: "s", width: 100, height: 100),
        shape: ShapeKind.star,
      );
      expect(CanvasDocument(elements: [star]).encode().contains("bubble"),
          isFalse);
    });
  });

  group("image looks", () {
    test("a filter and the sliders combine into one matrix", () {
      // One matrix rather than a layer per effect: layers are the expensive
      // part of drawing and a canvas may hold a dozen pictures.
      var element = const ImageElement(
        ElementBase(id: "i", width: 100, height: 100),
        assetId: "abcdefghij123456",
        filter: ImageFilterPreset.greyscale,
        saturation: 0.5,
      );
      expect(element.filter, ImageFilterPreset.greyscale);
      expect(element.saturation, 0.5);
    });

    test("crop, frame, filter and overlay survive a round trip", () {
      var element = const ImageElement(
        ElementBase(id: "i", width: 100, height: 100),
        assetId: "abcdefghij123456",
        crop: ImageCrop(left: 0.1, top: 0.2, right: 0.8, bottom: 0.9),
        frame: ShapeKind.circle,
        filter: ImageFilterPreset.sepia,
        overlay: Color(0x8812AAFF),
        blend: OverlayBlend.softLight,
      );
      var back = CanvasDocument.decode(
              CanvasDocument(elements: [element]).encode())!.elements.single
          as ImageElement;

      expect(back.crop.left, 0.1);
      expect(back.crop.bottom, 0.9);
      expect(back.frame, ShapeKind.circle);
      expect(back.filter, ImageFilterPreset.sepia);
      expect(back.blend, OverlayBlend.softLight);
      expect(back.overlay.toARGB32(), 0x8812AAFF);
    });

    test("an untouched picture carries none of it into the file", () {
      // The defaults are the common case and should cost a saved document
      // nothing at all.
      var plain = const ImageElement(
        ElementBase(id: "i", width: 100, height: 100),
        assetId: "abcdefghij123456",
      );
      // The element's own keys, not the whole document's -- a document has a
      // "frames" count in it, which contains the word this is looking for.
      var json = plain.toJson();
      expect(json.containsKey("crop"), isFalse);
      expect(json.containsKey("frame"), isFalse);
      expect(json.containsKey("filter"), isFalse);
      expect(json.containsKey("blend"), isFalse);
      expect(json.containsKey("overlay"), isFalse);
    });

    test("a crop is a fraction, and cannot be inside out", () {
      var back = ImageCrop.fromJson({"l": 2.0, "t": -3.0, "r": 9.0, "b": 0.5});
      expect(back.left, lessThanOrEqualTo(0.99));
      expect(back.top, greaterThanOrEqualTo(0.0));
      expect(back.right, lessThanOrEqualTo(1.0));
      expect(const ImageCrop().isWhole, isTrue);
    });

    test("every filter and blend draws without throwing", () {
      for (var filter in ImageFilterPreset.values) {
        for (var blend in OverlayBlend.values) {
          var document = CanvasDocument(
            size: const CanvasSize(width: 120),
            elements: [
              ImageElement(
                const ElementBase(id: "i", x: 10, y: 10, width: 80, height: 60),
                filter: filter,
                blend: blend,
                overlay: const Color(0x8800FF00),
              ),
            ],
          );
          expect(
              () => paintCanvasDocument(
                  ui.Canvas(ui.PictureRecorder()), document),
              returnsNormally,
              reason: "${filter.name} with ${blend.name}");
        }
      }
    });

    test("every frame shape is a usable mask", () {
      for (var shape in ShapeKind.values) {
        var document = CanvasDocument(
          size: const CanvasSize(width: 120),
          elements: [
            ImageElement(
              const ElementBase(id: "i", x: 10, y: 10, width: 80, height: 60),
              frame: shape,
            ),
          ],
        );
        expect(
            () => paintCanvasDocument(
                ui.Canvas(ui.PictureRecorder()), document),
            returnsNormally,
            reason: shape.name);
      }
    });
  });

  group("an image overlay", () {
    test("only the image is drawn into the blend's layer", () {
      // A blend mode blends against whatever is already on the canvas, and
      // that is every element painted before this one -- so an overlay set on
      // a photograph multiplied its way through the background and everything
      // sitting under it. The picture goes into a layer of its own first.
      var element = ImageElement(
        const ElementBase(id: "i", width: 100, height: 100),
        blend: OverlayBlend.multiply,
        overlay: const Color(0xFF3366FF),
      );
      expect(element.blend, OverlayBlend.multiply);
      // No image resolves in a test, so what this pins is the decision rather
      // than the pixels: with an overlay set, the painter must isolate.
      expect(element.overlay.a, greaterThan(0));
    });

    test("a picture keeps its proportions on resize by default", () {
      var element = ImageElement(
        const ElementBase(id: "i", width: 100, height: 100),
      );
      expect(element.keepsAspect, isTrue,
          reason: "a photograph dragged out of its own proportions is wrong");
      expect(element.copyWith(lockAspect: false).keepsAspect, isFalse);

      // Nothing else does: every other element is a shape that can be any
      // proportion it likes.
      expect(
          ShapeElement(const ElementBase(id: "s", width: 10, height: 10))
              .keepsAspect,
          isFalse);
    });

    test("the lock survives a round trip", () {
      var element = ImageElement(
        const ElementBase(id: "i", width: 100, height: 100),
      ).copyWith(lockAspect: false);
      var back = CanvasDocument.decode(
              CanvasDocument(elements: [element]).encode())!.elements.single
          as ImageElement;
      expect(back.lockAspect, isFalse);
    });
  });

  group("an outline round a cut-out", () {
    // The picture is 40x40 with a solid 20x20 middle, drawn into a 100x100
    // element at the top left of a square canvas -- so the middle lands on
    // canvas 25..75 and there are 25 units of transparent picture round it
    // for an outline to be drawn in.
    late ui.Image picture;
    setUp(() async {
      picture = await _cutOut(40, const ui.Color(0xFFFF0000));
    });
    tearDown(() => picture.dispose());

    CanvasDocument documentWith(ImageOutline outline) => CanvasDocument(
          size: const CanvasSize(width: 100, ratio: CanvasRatio.square),
          elements: [
            ImageElement(
              const ElementBase(id: "i", x: 0, y: 0, width: 100, height: 100),
              assetId: "abcdefghij123456",
              fit: ImageFit.contain,
              outline: outline,
            ),
          ],
        );

    test("with no width it draws nothing", () async {
      // The width is the off switch. There is no separate toggle to get out
      // of step with it.
      expect(const ImageOutline().on, isFalse);
      expect(const ImageOutline(width: 4, color: ui.Color(0x00FFFFFF)).on,
          isFalse,
          reason: "nor is an invisible colour an outline");

      // The canvas has a background of its own, so "nothing here" is read as
      // "not the outline's colour" rather than as no alpha.
      var pixel = await _renderWith(
          documentWith(const ImageOutline()), _Pictures(picture), 20, 50);
      expect(pixel[1], lessThan(60),
          reason: "beside the subject is still the background");
    });

    test("an outside band is drawn beside the subject, not over it",
        () async {
      var document = documentWith(const ImageOutline(
          width: 8, color: ui.Color(0xFF00FF00)));
      var images = _Pictures(picture);

      var beside = await _renderWith(document, images, 20, 50);
      expect(beside[1], greaterThan(200), reason: "green, four units out");
      expect(beside[0], lessThan(60), reason: "and not the subject's red");

      var within = await _renderWith(document, images, 50, 50);
      expect(within[0], greaterThan(200),
          reason: "the middle is still the picture");
      expect(within[1], lessThan(60));

      var further = await _renderWith(document, images, 5, 50);
      expect(further[1], lessThan(60),
          reason: "and the band stops, twenty units out");
    });

    test("an inside band eats into the subject instead", () async {
      var document = documentWith(const ImageOutline(
          width: 8, color: ui.Color(0xFF00FF00), style: OutlineStyle.inside));
      var images = _Pictures(picture);

      var beside = await _renderWith(document, images, 20, 50);
      expect(beside[1], lessThan(60),
          reason: "nothing outside the subject at all");

      var rim = await _renderWith(document, images, 28, 50);
      expect(rim[1], greaterThan(200), reason: "the rim is the outline");

      var middle = await _renderWith(document, images, 50, 50);
      expect(middle[0], greaterThan(200), reason: "the middle is untouched");
    });

    test("feathering fades the band out as it goes", () async {
      var images = _Pictures(picture);
      Future<int> greenAt(double feather, int x) async {
        var pixel = await _renderWith(
            documentWith(ImageOutline(
                width: 12, color: const ui.Color(0xFF00FF00),
                feather: feather)),
            images,
            x,
            50);
        return pixel[1];
      }

      // Read near the band's far edge -- 13 units out of a 12-wide band that
      // starts at 25 -- which is where the difference between a line and a
      // fade is the whole difference.
      expect(await greenAt(0, 15), greaterThan(240),
          reason: "unfeathered, the band is solid to its own edge");
      expect(await greenAt(1, 15), lessThan(150),
          reason: "feathered, it is nearly gone by there");
    });

    test("an outline survives a round trip, and costs nothing when off",
        () async {
      var element = const ImageElement(
        ElementBase(id: "i", width: 100, height: 100),
        assetId: "abcdefghij123456",
        outline: ImageOutline(
            width: 6,
            color: ui.Color(0xFF3366FF),
            style: OutlineStyle.glow,
            feather: 0.4),
      );
      var back = CanvasDocument.decode(
              CanvasDocument(elements: [element]).encode())!.elements.single
          as ImageElement;
      expect(back.outline.width, 6);
      expect(back.outline.style, OutlineStyle.glow);
      expect(back.outline.feather, 0.4);
      expect(back.outline.color.toARGB32(), 0xFF3366FF);

      expect(
          const ImageElement(ElementBase(id: "i", width: 10, height: 10))
              .toJson()
              .containsKey("outline"),
          isFalse);
    });

    test("every style draws without throwing", () {
      for (var style in OutlineStyle.values) {
        expect(
            () => paintCanvasDocument(
                ui.Canvas(ui.PictureRecorder()),
                documentWith(ImageOutline(width: 5, style: style)),
                images: _Pictures(picture)),
            returnsNormally,
            reason: style.name);
      }
    });
  });

  group("an outline is one line", () {
    // The reported fault, and the reason the band is not drawn as an outward
    // half behind the picture and an inward half in front of it. Two halves
    // meet at the subject's own soft rim, neither can be more than half
    // opaque where that rim is, and the join comes out dimmer than either
    // side -- which is a second line with a gap in front of it.
    late ui.Image picture;
    setUp(() async {
      picture = await _softBlob(200);
    });
    tearDown(() => picture.dispose());

    CanvasDocument documentWith(OutlineStyle style, double feather) =>
        CanvasDocument(
          size: const CanvasSize(width: 200, ratio: CanvasRatio.square),
          elements: [
            ImageElement(
              const ElementBase(id: "i", x: 0, y: 0, width: 200, height: 200),
              assetId: "abcdefghij123456",
              fit: ImageFit.contain,
              outline: ImageOutline(
                  width: 10,
                  color: const ui.Color(0xFFFFFFFF),
                  style: style,
                  feather: feather),
            ),
          ],
        );

    for (var style in OutlineStyle.values) {
      for (var feather in [0.0, 0.6]) {
        test("${style.name} at feather $feather rises once and does not dip",
            () async {
          // Green, because the outline is white on a dark canvas over a dark
          // subject, so green is the outline and nothing else.
          var row = await _rowOf(
              documentWith(style, feather), _Pictures(picture), 1, 100);

          // Walk in from the left edge as far as the band's brightest point.
          // Everything up to there is the band arriving, and it must arrive
          // once: any fall on the way in is a dim ring, which is the fault.
          // A glow never reaches full, so the peak is the brightest point
          // rather than a fixed level.
          var left = row.sublist(0, row.length ~/ 2);
          var brightest = left.reduce(math.max);
          expect(brightest, greaterThan(100), reason: "the band is drawn");
          var peak = left.indexOf(brightest);

          for (var x = 1; x <= peak; x++) {
            expect(row[x], greaterThanOrEqualTo(row[x - 1] - 2),
                reason: "dips at $x, from ${row[x - 1]} to ${row[x]}");
          }
        });
      }
    }

    test("feathering fades the outward side and leaves the traced edge alone",
        () async {
      // An outline that blurs the very line it is drawing is no longer
      // drawing it, so the feather goes on the side facing away from the
      // subject -- outwards here.
      var hard = await _rowOf(
          documentWith(OutlineStyle.outside, 0), _Pictures(picture), 1, 100);
      var soft = await _rowOf(
          documentWith(OutlineStyle.outside, 1), _Pictures(picture), 1, 100);

      // The subject's own edge is at 50. Just outside it the band is solid
      // either way; further out only the hard one still is.
      // The subject's own edge is at 50, and the band runs out to 40.
      expect(hard[49], greaterThan(240));
      expect(hard[42], greaterThan(100));

      var atTheSubject = hard[49] - soft[49];
      var atTheFarSide = hard[42] - soft[42];
      expect(atTheFarSide, greaterThan(atTheSubject * 2),
          reason: "the fade belongs to the outward side, not to both");
      expect(soft[49], greaterThan(150),
          reason: "and the band still meets the subject");
    });
  });

  group("a picture takes its own proportions", () {
    ImageElement squareBox() => const ImageElement(
        ElementBase(id: "i", x: 100, y: 100, width: 80, height: 80));

    test("a wide picture makes a wide box", () {
      var fitted = fitToPicture(squareBox(), const Size(200, 100));
      expect(fitted.base.width, 80, reason: "as wide as it was");
      expect(fitted.base.height, 40);
      expect(fitted.base.x, 100);
      expect(fitted.base.y, 120, reason: "and still centred where it was");
    });

    test("a tall picture shrinks the width rather than growing the height",
        () {
      // The tempting version keeps the width and works out the height, and it
      // puts a tall photograph's bottom half off the bottom of the canvas.
      var fitted = fitToPicture(squareBox(), const Size(100, 200));
      expect(fitted.base.height, 80);
      expect(fitted.base.width, 40);
      expect(fitted.base.x, 120);
      expect(fitted.base.y, 100);
    });

    test("nothing sensible to do means nothing done", () {
      var box = squareBox();
      expect(fitToPicture(box, const Size(0, 10)).base.width, 80);
      expect(fitToPicture(box, const Size(10, 0)).base.height, 80);
    });

    test("everything else about the picture is left alone", () {
      var element = squareBox().copyWith(
          assetId: "abcdefghij123456", filter: ImageFilterPreset.sepia);
      var fitted = fitToPicture(element, const Size(200, 100));
      expect(fitted.assetId, "abcdefghij123456");
      expect(fitted.filter, ImageFilterPreset.sepia);
      expect(fitted.base.id, "i");
    });
  });

  _chartTests();
}


/// _chartPixels is a chart rendered to raw bytes.
Future<Uint8List> _chartPixels(ChartElement e,
    {int width = 400, int height = 300}) async {
  var recorder = ui.PictureRecorder();
  paintChart(ui.Canvas(recorder),
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), e);
  var image = await recorder.endRecording().toImage(width, height);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!
        .buffer
        .asUint8List();
  } finally {
    image.dispose();
  }
}

/// _rowsOf is which rows of a rendered chart carry a given colour.
///
/// Colour rather than "any text", because taking a label away rearranges
/// everything under it -- the plot grows into the space -- so a difference
/// between two renders is mostly the axis labels having moved. Giving the
/// label a colour of its own asks where *it* is and nothing else.
Future<List<int>> _rowsOf(ChartElement e, ui.Color colour,
    {int width = 400, int height = 300}) async {
  var pixels = await _chartPixels(e, width: width, height: height);
  var want = [
    (colour.r * 255).round(),
    (colour.g * 255).round(),
    (colour.b * 255).round(),
  ];
  var rows = <int>[];
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var i = (y * width + x) * 4;
      if (pixels[i + 3] > 200 &&
          (pixels[i] - want[0]).abs() < 24 &&
          (pixels[i + 1] - want[1]).abs() < 24 &&
          (pixels[i + 2] - want[2]).abs() < 24) {
        rows.add(y);
        break;
      }
    }
  }
  return rows;
}

/// _chartColours is every fully-opaque colour a chart draws, which is how a
/// painter test asks "is the second series there at all".
Future<Set<String>> _chartColours(ChartElement e,
    {int width = 400, int height = 300}) async {
  var recorder = ui.PictureRecorder();
  paintChart(ui.Canvas(recorder),
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), e);
  var image = await recorder.endRecording().toImage(width, height);
  try {
    var raw = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    var pixels = raw!.buffer.asUint8List();
    var out = <String>{};
    for (var i = 0; i < width * height; i++) {
      if (pixels[i * 4 + 3] > 240) {
        out.add("${pixels[i * 4]},${pixels[i * 4 + 1]},${pixels[i * 4 + 2]}");
      }
    }
    return out;
  } finally {
    image.dispose();
  }
}

/// _two is a chart of two series, which is what most of these need.
ChartElement _two(ChartType type, {ChartType? secondAs}) {
  var data = ChartData.parse("Cat\tA\tB\nx\t10\t5\ny\t6\t9");
  if (secondAs != null) {
    data = ChartData(
      categories: data.categories,
      series: [data.series.first, data.series[1].copyWith(type: secondAs)],
    );
  }
  return ChartElement(
    const ElementBase(id: "c", width: 400, height: 300),
    type: type,
    data: data,
  );
}

void _chartTests() {
  group("a chart", () {
    test("the legend draws for one series as well as for several", () async {
      // It was "showLegend && series.length > 1", so a one-series chart with
      // the legend switched on drew nothing at all -- which reads as the
      // switch being broken rather than as the legend being unnecessary.
      var one = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        data: ChartData.parse("Cat\tMessages\nx\t10\ny\t6"),
        showLegend: true,
        labelSpec: const TextSpec(fontSize: 14),
      );

      var recorder = ui.PictureRecorder();
      paintChart(ui.Canvas(recorder), const Rect.fromLTWH(0, 0, 400, 300), one);
      var withLegend = await recorder.endRecording().toImage(400, 300);

      recorder = ui.PictureRecorder();
      paintChart(ui.Canvas(recorder), const Rect.fromLTWH(0, 0, 400, 300),
          one.copyWith(showLegend: false));
      var without = await recorder.endRecording().toImage(400, 300);

      try {
        var a = (await withLegend.toByteData(
                format: ui.ImageByteFormat.rawStraightRgba))!
            .buffer
            .asUint8List();
        var b = (await without.toByteData(
                format: ui.ImageByteFormat.rawStraightRgba))!
            .buffer
            .asUint8List();
        expect(a, isNot(orderedEquals(b)),
            reason: "turning the legend on changes the picture");
      } finally {
        withLegend.dispose();
        without.dispose();
      }
    });

    test("grouped bars put two series side by side", () async {
      // They draw exactly what plain bars draw until there is a second series
      // to group, which is why choosing one on a one-series chart looks like
      // the setting doing nothing.
      var grouped = await _chartColours(_two(ChartType.groupedBar));
      expect(grouped, contains("61,126,255"), reason: "the first series");
      expect(grouped, contains("255,176,32"), reason: "and the second");

      var one = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        type: ChartType.groupedBar,
        data: ChartData.parse("Cat\tA\nx\t10\ny\t6"),
      );
      expect(ChartType.groupedBar.needsMultipleSeries, isTrue);
      expect((await _chartColours(one)), isNot(contains("255,176,32")));
    });

    test("stacked bars stack the second series on the first", () async {
      var stacked = await _chartColours(_two(ChartType.stackedBar));
      expect(stacked, contains("61,126,255"));
      expect(stacked, contains("255,176,32"));
    });

    test("a series can be drawn as something else over the rest", () async {
      // The point of the override: a set of bars with a line across it.
      var overlaid = _two(ChartType.bar, secondAs: ChartType.line);
      expect(overlaid.data.series[1].typeIn(ChartType.bar), ChartType.line);
      expect(overlaid.data.series.first.typeIn(ChartType.bar), ChartType.bar);

      var colours = await _chartColours(overlaid);
      expect(colours, contains("255,176,32"),
          reason: "the line series is drawn");

      // Plain bars ignore every series but the first, so the second showing at
      // all is the override doing its work.
      var plain = await _chartColours(_two(ChartType.bar));
      expect(plain, isNot(contains("255,176,32")));
    });

    test("smooth is only offered where there is a line to curve", () {
      expect(ChartType.line.usesSmooth, isTrue);
      expect(ChartType.area.usesSmooth, isTrue);
      expect(ChartType.bar.usesSmooth, isFalse);
      expect(ChartType.scatter.usesSmooth, isFalse,
          reason: "a scatter is unconnected by definition");
    });

    test("a label can be switched off", () async {
      var titled = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        title: "Messages",
        data: ChartData.parse("Cat\tA\nx\t10\ny\t6"),
        titleSpec: const TextSpec(fontSize: 24, weight: 700),
      );
      var shown = await _chartPixels(titled);
      var hidden = await _chartPixels(
          titled.copyWith(titleBox: const ChartLabel(show: false)));
      expect(shown, isNot(orderedEquals(hidden)));
    });

    test("a title the chart places sits at the top, not down the middle",
        () async {
      // The box handed to the text painter is the whole remaining area, and a
      // TextSpec is vertically centred unless it says otherwise -- so the
      // title was drawn across the middle of the plot, over the bars, while
      // the description sat at the top above it.
      const red = ui.Color(0xFFFF0000);
      var e = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        title: "Messages",
        showGrid: false,
        showAxes: false,
        data: ChartData.parse("Cat\tA\nx\t10\ny\t6"),
        titleSpec: const TextSpec(fontSize: 24, weight: 700, color: red),
        labelSpec: const TextSpec(fontSize: 11),
      );

      var rows = await _rowsOf(e, red);
      expect(rows, isNotEmpty, reason: "the title is drawn at all");
      expect(rows.last, lessThan(60),
          reason: "every row of it is in the top fifth, not over the bars");
    });

    test("a description sits under the title, not above it", () async {
      const red = ui.Color(0xFFFF0000);
      const green = ui.Color(0xFF00FF00);
      var e = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        title: "Messages",
        description: "By week",
        showGrid: false,
        showAxes: false,
        data: ChartData.parse("Cat\tA\nx\t10\ny\t6"),
        titleSpec: const TextSpec(fontSize: 24, weight: 700, color: red),
        labelSpec: const TextSpec(fontSize: 11, color: green),
      );

      var titleRows = await _rowsOf(e, red);
      var descriptionRows = await _rowsOf(e, green);
      expect(titleRows, isNotEmpty);
      expect(descriptionRows, isNotEmpty);
      expect(titleRows.last, lessThan(descriptionRows.first),
          reason: "the title finishes before the description begins");
    });

    test("the body is the whole box until a label leaves it", () {
      expect(const ChartBody().isWhole, isTrue);

      // What the stage does when the box grows: the chart keeps the rectangle
      // it already had, so a drag about the words does not resize the plot.
      const was = Rect.fromLTWH(100, 100, 400, 300);
      const grown = Rect.fromLTWH(60, 80, 460, 340);
      var body = ChartBody.fitting(was, grown);

      expect(body.rectIn(grown).left, closeTo(was.left, 0.001));
      expect(body.rectIn(grown).top, closeTo(was.top, 0.001));
      expect(body.rectIn(grown).width, closeTo(was.width, 0.001));
      expect(body.rectIn(grown).height, closeTo(was.height, 0.001));
    });

    test("a placed label sits where it was put and takes no room", () {
      // Placed, it stops being part of the chart's own arrangement: it is
      // drawn over the plot at its own box, and the plot gets the height the
      // title used to take.
      const box = ChartLabel(x: 0.5, y: 0.6, width: 0.4, height: 0.2);
      expect(box.placed, isTrue);
      expect(const ChartLabel().placed, isFalse);

      var rect = box.rectIn(const Rect.fromLTWH(100, 200, 400, 300));
      expect(rect.left, 300);
      expect(rect.top, 380);
      expect(rect.width, 160);
      expect(rect.height, 60);
    });

    test("a placed description goes under the title, not over it", () {
      // Both used to land on the same corner, so placing the second put it
      // exactly over the first -- and since the description is drawn last,
      // that looked like a description sitting above a title.
      expect(defaultTitlePlacement.y, lessThan(0.05));

      var under = defaultDescriptionPlacement(defaultTitlePlacement, true);
      expect(under.y,
          greaterThanOrEqualTo(
              defaultTitlePlacement.y + defaultTitlePlacement.height),
          reason: "below the bottom of the title");
      expect(under.x, defaultTitlePlacement.x,
          reason: "and lined up with it, so the two read as a pair");
    });

    test("it follows a title that has already been moved", () {
      const title = ChartLabel(x: 0.4, y: 0.5, width: 0.3, height: 0.1);
      var under = defaultDescriptionPlacement(title, true);
      expect(under.x, 0.4);
      expect(under.y, greaterThanOrEqualTo(0.6));
      expect(under.width, 0.3);
    });

    test("with no title it takes the top itself", () {
      // Rather than leaving a band of nothing where a title would have been.
      var alone = defaultDescriptionPlacement(const ChartLabel(), false);
      expect(alone.y, lessThan(0.05));
    });

    test("a chart's labels and series types survive a round trip", () {
      var element = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        title: "T",
        description: "D",
        titleBox: const ChartLabel(x: 0.1, y: 0.2, width: 0.5, height: 0.15),
        descriptionBox: const ChartLabel(show: false),
        data: ChartData(
          categories: const ["x"],
          series: [
            const ChartSeries(
                name: "A", color: Color(0xFF3D7EFF), values: [1]),
            const ChartSeries(
                name: "B",
                color: Color(0xFFFFB020),
                values: [2],
                type: ChartType.line),
          ],
        ),
      );
      var back = CanvasDocument.decode(
              CanvasDocument(elements: [element]).encode())!.elements.single
          as ChartElement;

      expect(back.titleBox.x, 0.1);
      expect(back.titleBox.height, 0.15);
      expect(back.descriptionBox.show, isFalse);
      expect(back.data.series[1].type, ChartType.line);
      expect(back.data.series.first.type, isNull,
          reason: "a series following the chart carries nothing");
    });

    test("editing the numbers keeps a series' colour and its type", () {
      // The text form has no room for either, so parsing it back would throw
      // them away -- and changing one number would silently turn the line
      // over the bars back into bars.
      var before = _two(ChartType.bar, secondAs: ChartType.line).data;
      var after = ChartData.parse(
          "Cat\tA\tB\nx\t11\t5\ny\t6\t9", keep: before.series);

      expect(after.valueAt(0, 0), 11);
      expect(after.series[1].type, ChartType.line);
      expect(after.series[1].color, before.series[1].color);
    });
  });
}
