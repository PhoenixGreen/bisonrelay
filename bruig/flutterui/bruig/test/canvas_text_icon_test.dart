import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_text_icon_test.dart is the picture a text element carries.
//
// What matters is the room: an icon takes its space out of the box and the
// words are laid out in what is left. An icon drawn over the words, or words
// laid out as though the icon were not there, is the whole feature failing.

/// _Pictures hands the painter one flat square, which is enough to say where
/// an icon was drawn and in what colour.
///
/// [vector] is what resolveVector answers, for the tests about a drawing whose
/// own size is unusable.
class _Pictures implements CanvasImageSource {
  final ui.Image image;
  final CanvasVector? vector;
  _Pictures(this.image, {this.vector});

  @override
  ui.Image? resolve(String assetId, BackgroundRemoval removal) =>
      assetId.isEmpty ? null : image;

  @override
  CanvasVector? resolveVector(String assetId) =>
      assetId.isEmpty ? null : vector;
}

Future<ui.Image> _square(Color color) async {
  var recorder = ui.PictureRecorder();
  ui.Canvas(recorder)
      .drawRect(const Rect.fromLTWH(0, 0, 20, 20), Paint()..color = color);
  return recorder.endRecording().toImage(20, 20);
}

Future<Map<int, int>> _ink(TextElement element, CanvasImageSource? images,
    {Rect? within}) async {
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
    if (within != null) {
      var at = i ~/ 4;
      if (!within
          .contains(Offset((at % 400).toDouble(), (at ~/ 400).toDouble()))) {
        continue;
      }
    }
    var pixel = bytes.getUint32(i);
    counts[pixel] = (counts[pixel] ?? 0) + 1;
  }
  image.dispose();
  picture.dispose();
  return counts;
}

TextElement _headline({TextIcon icon = const TextIcon(), bool fit = false}) =>
    TextElement(
      const ElementBase(id: "t", x: 0, y: 20, width: 400, height: 120),
      text: "Headline",
      autoSize: fit,
      textSpec: const TextSpec(fontSize: 30, color: Color(0xFFFFFFFF)),
      icon: icon,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const white = 0xFFFFFFFF;
  const red = 0xFF0000FF;
  const green = 0x00FF00FF;

  group("an icon beside the words", () {
    testWidgets("is drawn, and takes its room out of the box", (tester) async {
      late Map<int, int> plain;
      late Map<int, int> withIcon;
      await tester.runAsync(() async {
        var pictures = _Pictures(await _square(const Color(0xFFFF0000)));
        plain = await _ink(_headline(), pictures);
        withIcon = await _ink(
            _headline(icon: const TextIcon(assetId: "a", size: 60)), pictures);
      });

      expect(plain[red] ?? 0, 0, reason: "no icon, no icon pixels");
      expect(withIcon[red] ?? 0, greaterThan(2000),
          reason: "a sixty pixel square");
      // The words are still there, and in less room than they had.
      expect(withIcon[white] ?? 0, greaterThan(100));
      expect(withIcon[white]!, lessThanOrEqualTo(plain[white]!),
          reason: "the words were pushed into what was left");
    });

    testWidgets("on whichever side it was put", (tester) async {
      const leftEdge = Rect.fromLTWH(0, 0, 120, 200);
      const rightEdge = Rect.fromLTWH(280, 0, 120, 200);
      late int leftWhenFirst;
      late int rightWhenLast;
      await tester.runAsync(() async {
        var pictures = _Pictures(await _square(const Color(0xFFFF0000)));
        leftWhenFirst = (await _ink(
                _headline(icon: const TextIcon(assetId: "a", size: 60)),
                pictures,
                within: leftEdge))[red] ??
            0;
        rightWhenLast = (await _ink(
                _headline(
                    icon: const TextIcon(
                        assetId: "a", size: 60, place: IconPlace.end)),
                pictures,
                within: rightEdge))[red] ??
            0;
      });
      expect(leftWhenFirst, greaterThan(2000));
      expect(rightWhenLast, greaterThan(2000));
    });

    testWidgets("a tint repaints it in one colour", (tester) async {
      late Map<int, int> tinted;
      await tester.runAsync(() async {
        var pictures = _Pictures(await _square(const Color(0xFFFF0000)));
        tinted = await _ink(
            _headline(
                icon: const TextIcon(
                    assetId: "a", size: 60, color: Color(0xFF00FF00))),
            pictures);
      });
      expect(tinted[red] ?? 0, 0, reason: "not the colour it was drawn in");
      expect(tinted[green] ?? 0, greaterThan(2000));
    });

    testWidgets("a drawing with no size of its own still shows",
        (tester) async {
      // An .svg with no width, height or viewBox has a size of nothing, and
      // nothing cannot be scaled to fit anything. Drawn from the rasterised
      // copy instead of not drawn at all.
      late Map<int, int> ink;
      await tester.runAsync(() async {
        var picture = ui.PictureRecorder();
        ui.Canvas(picture).drawRect(const Rect.fromLTWH(0, 0, 1, 1),
            Paint()..color = const Color(0xFF0000FF));
        var pictures = _Pictures(await _square(const Color(0xFFFF0000)),
            vector: CanvasVector(picture.endRecording(), Size.zero));
        ink = await _ink(
            _headline(icon: const TextIcon(assetId: "a", size: 60)), pictures);
      });
      expect(ink[red] ?? 0, greaterThan(2000),
          reason: "the rasterised copy is drawn");
    });

    test("and Fit to box measures against the room that is left", () {
      // Fitted against the whole box, the type would be set to a size it does
      // not fit at once the icon has taken a third of the width.
      var inner = const Rect.fromLTWH(0, 0, 400, 100);
      var (icon, room) =
          iconRoom(inner, const TextIcon(assetId: "a", size: 60, gap: 20));
      expect(icon.width, 60);
      expect(room.left, 80, reason: "the icon and the gap");
      expect(room.width, 320);

      // Nothing at all when there is no icon.
      expect(iconRoom(inner, const TextIcon()).$2, inner);

      var over = iconRoom(
          inner, const TextIcon(assetId: "a", size: 40, place: IconPlace.over));
      expect(over.$2.top, greaterThan(inner.top));
      expect(over.$2.width, inner.width,
          reason: "above takes height, not width");
    });

    test("and it follows the words' own alignment", () {
      // The room is the right width and the wrong place for anything but
      // left-aligned words: centred text centres itself in what is left over,
      // so the icon sat against the far edge of the box with a hole between
      // it and the sentence it belongs to.
      const inner = Rect.fromLTWH(0, 0, 400, 100);
      const icon = TextIcon(assetId: "a", size: 60, gap: 20);
      const words = "Headline";

      var left = iconLayout(inner, icon, words,
          const TextSpec(fontSize: 20, align: TextAlignSpec.left));
      expect(left.$1.left, 0, reason: "left-aligned words start at the edge");
      expect(left.$2.left, 80, reason: "the icon and the gap");

      var centre = iconLayout(inner, icon, words,
          const TextSpec(fontSize: 20, align: TextAlignSpec.center));
      expect(centre.$2.left, closeTo(centre.$1.right + 20, 0.5),
          reason: "the gap is the gap, wherever the group is");
      expect((centre.$1.left + centre.$2.right) / 2, closeTo(200, 1),
          reason: "and the icon and the words are centred together");
      expect(centre.$1.left, greaterThan(0),
          reason: "not against the edge of the box any more");

      var right = iconLayout(inner, icon, words,
          const TextSpec(fontSize: 20, align: TextAlignSpec.right));
      expect(right.$2.right, closeTo(400, 1), reason: "against the right edge");
      expect(right.$2.left, closeTo(right.$1.right + 20, 0.5));

      // An icon after the words follows them the same way.
      var after = iconLayout(
          inner,
          const TextIcon(assetId: "a", size: 60, gap: 20, place: IconPlace.end),
          words,
          const TextSpec(fontSize: 20, align: TextAlignSpec.center));
      expect(after.$1.left, closeTo(after.$2.right + 20, 0.5));
      expect((after.$2.left + after.$1.right) / 2, closeTo(200, 1));
    });

    test("except where there is no group to place", () {
      // Justified text and columns both fill the width they are given.
      const inner = Rect.fromLTWH(0, 0, 400, 100);
      const icon = TextIcon(assetId: "a", size: 60, gap: 20);
      var justified = iconLayout(inner, icon, "Headline",
          const TextSpec(fontSize: 20, align: TextAlignSpec.justify));
      expect(justified.$2.width, 320);

      var columned = iconLayout(inner, icon, "Headline",
          const TextSpec(fontSize: 20, align: TextAlignSpec.center),
          columns: 3);
      expect(columned.$2.width, 320);
    });

    test("it survives being saved", () {
      var element = _headline(
          icon: const TextIcon(
        assetId: "badge",
        place: IconPlace.under,
        size: 80,
        color: Color(0xFF00FF00),
        gap: 4,
        align: TextIconAlign.end,
        outlineWidth: 3,
        underline: PartUnderline(style: PartLineStyle.marker),
      ));
      var back = elementFromJson(element.toJson()) as TextElement;
      expect(back.icon.assetId, "badge");
      expect(back.icon.place, IconPlace.under);
      expect(back.icon.size, 80);
      expect(back.icon.color, const Color(0xFF00FF00));
      expect(back.icon.align, TextIconAlign.end);
      expect(back.icon.outlineWidth, 3);
      expect(back.icon.underline!.style, PartLineStyle.marker);

      // And an element with no icon writes none.
      expect(_headline().toJson().containsKey("icon"), isFalse);
    });
  });
}
