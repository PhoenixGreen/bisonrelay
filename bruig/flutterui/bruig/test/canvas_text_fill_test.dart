import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/image_silhouette.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_text_fill_test.dart is a picture or a pattern showing through the
// letters.
//
// The thing worth pinning is where the fill is drawn: across the whole line
// and then cut to the shape of the type, rather than restarting inside every
// glyph. That is the whole effect, and it is invisible in the model -- both
// versions have the same settings and only the pixels tell them apart.

/// _Pictures hands the painter one picture, whatever is asked for.
class _Pictures implements CanvasImageSource {
  final ui.Image image;
  _Pictures(this.image);

  @override
  ui.Image? resolve(String assetId, BackgroundRemoval removal) =>
      assetId.isEmpty ? null : image;

  @override
  CanvasVector? resolveVector(String assetId) => null;

  @override
  ImageSilhouette? resolveOutline(String assetId, BackgroundRemoval removal) =>
      null;
}

/// _halves is a picture that is red down one side and blue down the other,
/// which is enough to say which part of a fill a letter is showing.
Future<ui.Image> _halves() async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 20, 40),
      Paint()..color = const Color(0xFFFF0000));
  canvas.drawRect(const Rect.fromLTWH(20, 0, 20, 40),
      Paint()..color = const Color(0xFF0000FF));
  return recorder.endRecording().toImage(40, 40);
}

/// [within] and [outside] count only part of the picture: what is drawn in
/// one rectangle, and not in another.
Future<Map<int, int>> _ink(TextElement element,
    {CanvasImageSource? images, Rect? within, Rect? outside}) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 400, 200),
      Paint()..color = const Color(0xFF000000));
  paintElement(canvas, element, 0,
      document: CanvasDocument(elements: [element]), images: images);
  var picture = recorder.endRecording();
  var image = await picture.toImage(400, 200);
  var bytes = (await image.toByteData())!;
  var counts = <int, int>{};
  for (var i = 0; i < bytes.lengthInBytes; i += 4) {
    if (within != null || outside != null) {
      var at = i ~/ 4;
      var point = Offset((at % 400).toDouble(), (at ~/ 400).toDouble());
      if (within != null && !within.contains(point)) continue;
      if (outside != null && outside.contains(point)) continue;
    }
    var pixel = bytes.getUint32(i);
    counts[pixel] = (counts[pixel] ?? 0) + 1;
  }
  image.dispose();
  picture.dispose();
  return counts;
}

/// _reddish counts pixels the pattern's ink has touched.
///
/// Not an exact colour: every generator draws through _fade, so its ink is
/// mixed with whatever it is over and comes out somewhere between the two.
int _reddish(Map<int, int> ink) {
  var total = 0;
  for (var e in ink.entries) {
    var r = (e.key >> 24) & 0xFF;
    var g = (e.key >> 16) & 0xFF;
    var b = (e.key >> 8) & 0xFF;
    if (r > 0x30 && r > g && r >= b) total += e.value;
  }
  return total;
}

TextElement _headline(TextSpec spec) => TextElement(
      const ElementBase(id: "t", x: 0, y: 20, width: 400, height: 90),
      text: "PATTERN",
      textSpec: spec,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const white = 0xFFFFFFFF;
  const plain = TextSpec(fontSize: 40, color: Color(0xFFFFFFFF));

  group("a pattern inside the letters", () {
    testWidgets("is drawn through them and nowhere else", (tester) async {
      // Cut to the type: nothing of the pattern is outside the words, and
      // the words are no longer the flat colour they were.
      late Map<int, int> flat;
      late Map<int, int> filled;
      await tester.runAsync(() async {
        flat = await _ink(_headline(plain));
        filled = await _ink(_headline(plain.copyWith(
            fill: const TextFill(
          kind: TextFillKind.pattern,
          pattern: ProceduralSpec(
            style: ProceduralStyle.halftone,
            background: Color(0xFF00FF00),
            foreground: Color(0xFFFF0000),
            accent: Color(0xFFFF0000),
          ),
        ))));
      });

      expect(flat[white]!, greaterThan(500), reason: "white letters");
      expect(filled[white] ?? 0, 0,
          reason: "none of the type is the flat colour any more");
      expect(filled[0x00FF00FF] ?? 0, greaterThan(200),
          reason: "the pattern's ground shows through the letters");
      expect(_reddish(filled), greaterThan(20), reason: "and so do its dots");

      // And the letters are still letters: the same pixels are covered as
      // before, give or take the antialiasing.
      var covered = 0;
      for (var e in filled.entries) {
        if (e.key != 0x000000FF) covered += e.value;
      }
      var was = 0;
      for (var e in flat.entries) {
        if (e.key != 0x000000FF) was += e.value;
      }
      expect(covered, closeTo(was, was * 0.25),
          reason: "the fill is the shape of the type: $was then $covered");
    });

    testWidgets("runs through the whole word rather than each letter",
        (tester) async {
      // A pattern restarted inside every glyph is a row of little patterns.
      // Zoomed right in, one letter's worth of the fill is one flat area --
      // so the number of colours in the word says whether the fill is one
      // picture across it or seven copies of the same small one.
      late int across;
      await tester.runAsync(() async {
        across = (await _ink(_headline(plain.copyWith(
                fill: const TextFill(
          kind: TextFillKind.pattern,
          zoom: 1,
          pattern: ProceduralSpec(
            style: ProceduralStyle.speedLines,
            background: Color(0xFF000080),
            foreground: Color(0xFFFFFF00),
            accent: Color(0xFFFFFF00),
          ),
        )))))
            .length;
      });
      // A burst drawn once across the line puts its rays at a different angle
      // in every letter, which is many colours; drawn per letter it would be
      // the same few.
      expect(across, greaterThan(8), reason: "$across colours");
    });

    test("and it survives being saved", () {
      var spec = plain.copyWith(
          fill: const TextFill(
        kind: TextFillKind.pattern,
        zoom: 2.5,
        pattern: ProceduralSpec(style: ProceduralStyle.flames),
      ));
      var back = TextSpec.fromJson(spec.toJson());
      expect(back.fill.kind, TextFillKind.pattern);
      expect(back.fill.pattern.style, ProceduralStyle.flames);
      expect(back.fill.zoom, 2.5);
      expect(back.fill.on, isTrue);

      // A plain colour writes nothing at all.
      expect(plain.toJson().containsKey("fill"), isFalse);
      expect(const TextFill().on, isFalse);
      expect(const TextFill(kind: TextFillKind.image).on, isFalse,
          reason: "a picture fill with no picture is still the colour");
    });
  });

  group("a fill locked to the words", () {
    /// _sliding is the words a picture shows through, half way in from the
    /// right. A picture that is red down one side and blue down the other
    /// says which part of the fill the letters are actually showing.
    Future<Map<int, int>> sliding(bool locked, ui.Image picture,
            {double reveal = 0.6}) =>
        _ink(
            TextElement(
              // Narrow, and well inside the picture: slid, the words have to
              // stay on the canvas or the count is of what was left rather
              // than of what the letters are showing.
              const ElementBase(id: "t", x: 40, y: 20, width: 260, height: 90),
              text: "PATTERN",
              textSpec: plain.copyWith(
                  fill: TextFill(
                      kind: TextFillKind.image, assetId: "a", locked: locked)),
              animation: const TextAnimation(
                  preset: TextAnimationPreset.slideRight,
                  ease: ChartEase.linear),
            ).withBase(
              track: ElementTrack([
                Keyframe(frame: 0, values: {KeyframeChannel.reveal: reveal}),
              ]),
            ) as TextElement,
            images: _Pictures(picture));

    /// _sides is how much of each half of the picture is showing.
    (int, int) sides(Map<int, int> ink) {
      var red = 0, blue = 0;
      for (var e in ink.entries) {
        var r = (e.key >> 24) & 0xFF, b = (e.key >> 8) & 0xFF;
        if (r < 0x20 && b < 0x20) continue;
        if (r > b) red += e.value;
        if (b > r) blue += e.value;
      }
      return (red, blue);
    }

    testWidgets("shows the same bit of it through the same letter",
        (tester) async {
      // Unlocked, the fill is pinned to the box and the words sweep across
      // it while they arrive: a word that ends up over the red half of the
      // picture spends the animation over the blue half, so what shows
      // through the letters changes every frame -- which is not what
      // somebody who chose a picture for the word asked for.
      late (int, int) rest;
      late (int, int) locked;
      late (int, int) loose;
      await tester.runAsync(() async {
        var picture = await _halves();
        rest = sides(await sliding(false, picture, reveal: 1));
        locked = sides(await sliding(true, picture));
        loose = sides(await sliding(false, picture));
      });

      double share((int, int) s) => s.$1 / math.max(1, s.$1 + s.$2).toDouble();

      expect(share(rest), greaterThan(0.2));
      expect(share(rest), lessThan(0.8),
          reason: "at rest the words straddle the two halves");
      expect((share(locked) - share(rest)).abs(), lessThan(0.1),
          reason: "locked, the picture travels with the words: the same "
              "halves show through the same letters. Rest ${share(rest)}, "
              "locked ${share(locked)}");
      expect((share(loose) - share(rest)).abs(), greaterThan(0.2),
          reason: "unlocked, the words have slid across it. Rest "
              "${share(rest)}, loose ${share(loose)}");
    });

    testWidgets("and the words are filled wherever the arrival takes them",
        (tester) async {
      // The layer the fill is cut to was the size of the box, so a paragraph
      // that spends its arrival outside the box -- a slide, a slam, a
      // rotate -- was cut off at the edge of it. The outline is drawn outside
      // that layer, so what arrived was an empty outline that filled itself
      // in as it crossed the box edge.
      // A strip well clear of the box, where the words are a quarter of the
      // way through a slide in from the right.
      const strip = Rect.fromLTRB(360, 0, 400, 200);
      late int filled;
      late int outlined;
      await tester.runAsync(() async {
        var ink = await _ink(
            TextElement(
              const ElementBase(id: "t", x: 40, y: 20, width: 260, height: 90),
              text: "PATTERN",
              textSpec: plain.copyWith(
                  outlineWidth: 4,
                  outlineColor: const Color(0xFF00FF00),
                  fill: const TextFill(
                      kind: TextFillKind.pattern,
                      pattern: ProceduralSpec(
                        style: ProceduralStyle.halftone,
                        background: Color(0xFF0000FF),
                        foreground: Color(0xFF0000FF),
                        accent: Color(0xFF0000FF),
                      ))),
              animation: const TextAnimation(
                  preset: TextAnimationPreset.slideRight,
                  ease: ChartEase.linear),
            ).withBase(
              track: ElementTrack([
                const Keyframe(
                    frame: 0, values: {KeyframeChannel.reveal: 0.25}),
              ]),
            ) as TextElement,
            within: strip);
        filled = 0;
        outlined = 0;
        for (var e in ink.entries) {
          var r = (e.key >> 24) & 0xFF, g = (e.key >> 16) & 0xFF;
          var b = (e.key >> 8) & 0xFF;
          if (b > 0x20 && b > r && b > g) filled += e.value;
          if (g > 0x20 && g > r && g > b) outlined += e.value;
        }
      });
      expect(outlined, greaterThan(20),
          reason: "the words are out here at all: the outline says so");
      expect(filled, greaterThan(100),
          reason: "and they are filled out here too, rather than hollow "
              "outlines waiting to cross into the box");
    });

    test("and it survives being saved", () {
      var spec = plain.copyWith(
          fill: const TextFill(
              kind: TextFillKind.pattern,
              pattern: ProceduralSpec(style: ProceduralStyle.flames),
              locked: true));
      expect(TextSpec.fromJson(spec.toJson()).fill.locked, isTrue);
      // Off is the default and writes nothing.
      expect(const TextFill().toJson().containsKey("locked"), isFalse);
    });
  });

  group("what stays outside the fill", () {
    testWidgets("a highlighter band keeps its own colour", (tester) async {
      // The band is drawn behind the words, not through them, so it belongs
      // outside the layer the fill is cut to. Drawn inside it, it became part
      // of what the pattern was cut to and came out in the pattern's colours
      // -- and it was drawn on both passes, so a translucent one was laid
      // down twice.
      late int band;
      await tester.runAsync(() async {
        var ink = await _ink(TextElement(
          const ElementBase(id: "t", x: 0, y: 20, width: 400, height: 90),
          text: "PATTERN",
          textSpec: plain.copyWith(
              fill: const TextFill(
            kind: TextFillKind.pattern,
            pattern: ProceduralSpec(
              style: ProceduralStyle.halftone,
              background: Color(0xFFFF0000),
              foreground: Color(0xFFFF0000),
              accent: Color(0xFFFF0000),
            ),
          )),
          animation: const TextAnimation(
            preset: TextAnimationPreset.highlight,
            ease: ChartEase.linear,
            draw: TextDrawSpec(color: Color(0xFF00FF00), padTop: 20),
          ),
        ).withBase(
          track: ElementTrack([
            const Keyframe(frame: 0, values: {KeyframeChannel.reveal: 1}),
          ]),
        ) as TextElement);
        band = 0;
        for (var e in ink.entries) {
          var r = (e.key >> 24) & 0xFF, g = (e.key >> 16) & 0xFF;
          var b = (e.key >> 8) & 0xFF;
          if (g > 0x40 && g > r && g > b) band += e.value;
        }
      });
      expect(band, greaterThan(1000),
          reason: "the band is drawn in the colour it was given");
    });
  });

  group("the drawn patterns", () {
    test("are offered alongside the generated backgrounds", () {
      var labels = [for (var s in ProceduralStyle.values) s.label];
      for (var wanted in [
        "Halftone",
        "Speed lines",
        "Crosshatch",
        "Paint splatter",
        "Flames",
      ]) {
        expect(labels, contains(wanted));
      }
    });

    testWidgets("and each of them draws something", (tester) async {
      // A style in the list that draws nothing is a style somebody chooses
      // once and never again.
      await tester.runAsync(() async {
        for (var style in [
          ProceduralStyle.halftone,
          ProceduralStyle.speedLines,
          ProceduralStyle.crosshatch,
          ProceduralStyle.splatter,
          ProceduralStyle.flames,
        ]) {
          var ink = await _ink(_headline(plain.copyWith(
              fill: TextFill(
            kind: TextFillKind.pattern,
            pattern: ProceduralSpec(
              style: style,
              background: const Color(0xFF00FF00),
              foreground: const Color(0xFFFF0000),
              accent: const Color(0xFFFF00FF),
              density: 0.8,
              intensity: 1,
            ),
          ))));
          expect(_reddish(ink), greaterThan(10),
              reason: "${style.name} drew nothing inside the letters");
        }
      });
    });
  });
}
