import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/image_silhouette.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_text_icon_test.dart is a picture inside a text element.
//
// It was a feature of its own -- one icon per element, with a place, an
// alignment and a gap that were nobody else's, and a section of the panel to
// set them in. It is a piece now, like a piece of writing: the same list, the
// same nine slots, the same row and button. See TextItem.

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

  @override
  ImageSilhouette? resolveOutline(String assetId, BackgroundRemoval removal) =>
      null;
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

TextElement _headline({TextIcon? icon, TextSlot slot = TextSlot.middleLeft}) =>
    TextElement(
      const ElementBase(id: "t", x: 0, y: 20, width: 400, height: 120),
      text: "Headline",
      textSpec: const TextSpec(fontSize: 30, color: Color(0xFFFFFFFF)),
      items: [
        if (icon != null) TextItem(id: "p", slot: slot, icon: icon),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const red = 0xFF0000FF;
  const green = 0x00FF00FF;

  group("a picture in a text element", () {
    testWidgets("is drawn where its slot puts it", (tester) async {
      late Map<int, int> plain;
      late Map<int, int> left;
      late Map<int, int> right;
      await tester.runAsync(() async {
        var pictures = _Pictures(await _square(const Color(0xFFFF0000)));
        plain = await _ink(_headline(), pictures);
        left = await _ink(
            _headline(icon: const TextIcon(assetId: "a", size: 60)), pictures);
        right = await _ink(
            _headline(
                icon: const TextIcon(assetId: "a", size: 60),
                slot: TextSlot.middleRight),
            pictures);
      });

      expect(plain[red] ?? 0, 0, reason: "no picture, no picture pixels");
      expect(left[red] ?? 0, greaterThan(2000));
      expect(right[red] ?? 0, left[red],
          reason: "the same picture, the same ink, in another corner");
    });

    testWidgets("on the side its slot names", (tester) async {
      late Map<int, int> onLeft;
      late Map<int, int> onRight;
      await tester.runAsync(() async {
        var pictures = _Pictures(await _square(const Color(0xFFFF0000)));
        // The left-hand third of the element, and the right-hand third.
        onLeft = await _ink(
            _headline(icon: const TextIcon(assetId: "a", size: 60)), pictures,
            within: const Rect.fromLTWH(0, 20, 133, 120));
        onRight = await _ink(
            _headline(
                icon: const TextIcon(assetId: "a", size: 60),
                slot: TextSlot.middleRight),
            pictures,
            within: const Rect.fromLTWH(267, 20, 133, 120));
      });
      expect(onLeft[red] ?? 0, greaterThan(2000));
      expect(onRight[red] ?? 0, greaterThan(2000));
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
      expect(tinted[green] ?? 0, greaterThan(2000));
      expect(tinted[red] ?? 0, 0, reason: "cut to its own shape and filled");
    });

    testWidgets("a drawing with no size of its own still shows",
        (tester) async {
      // An .svg with no width, height or viewBox cannot be scaled to fit
      // anything, so the rasterised copy is drawn instead of nothing.
      late Map<int, int> drawn;
      await tester.runAsync(() async {
        var picture = ui.PictureRecorder();
        ui.Canvas(picture).drawRect(const Rect.fromLTWH(0, 0, 1, 1),
            Paint()..color = const Color(0xFF0000FF));
        var pictures = _Pictures(await _square(const Color(0xFFFF0000)),
            vector: CanvasVector(picture.endRecording(), Size.zero));
        drawn = await _ink(
            _headline(icon: const TextIcon(assetId: "a", size: 60)), pictures);
      });
      expect(drawn[red] ?? 0, greaterThan(2000));
    });

    test("it survives being saved", () {
      var element = _headline(
        icon: const TextIcon(
          assetId: "badge",
          size: 80,
          color: Color(0xFF00FF00),
          outlineWidth: 3,
          underline: PartUnderline(style: PartLineStyle.marker),
        ),
        slot: TextSlot.bottomRight,
      );
      var back = elementFromJson(element.toJson()) as TextElement;
      var piece = back.items.single;
      expect(piece.icon!.assetId, "badge");
      expect(piece.icon!.size, 80);
      expect(piece.icon!.color, const Color(0xFF00FF00));
      expect(piece.icon!.outlineWidth, 3);
      expect(piece.icon!.underline!.style, PartLineStyle.marker);
      expect(piece.slot, TextSlot.bottomRight);

      // And an element with no picture writes none.
      expect(_headline().toJson().containsKey("items"), isFalse);
    });

    test("an older document's icon opens as a piece", () {
      // An icon was a feature of its own, with a place and an alignment that
      // were nobody else's. The two of them add up to one of the nine slots.
      TextElement opened(Map<String, dynamic> icon) => elementFromJson({
            "kind": "text",
            "id": "t",
            "w": 400.0,
            "h": 120.0,
            "text": "Headline",
            "icon": icon,
          }) as TextElement;

      var start = opened({"assetId": "a", "size": 40.0});
      expect(start.items.single.icon!.assetId, "a");
      expect(start.items.single.icon!.size, 40);
      expect(start.items.single.slot, TextSlot.middleLeft,
          reason: "before the words, lined up with the middle of them");

      expect(
          opened({"assetId": "a", "place": "end", "align": "end"})
              .items
              .single
              .slot,
          TextSlot.bottomRight);
      expect(opened({"assetId": "a", "place": "over"}).items.single.slot,
          TextSlot.topCentre);
      expect(
          opened({"assetId": "a", "place": "under", "align": "start"})
              .items
              .single
              .slot,
          TextSlot.bottomLeft);

      // An icon that was never given a picture is not a piece at all.
      expect(opened({"size": 40.0}).items, isEmpty);
    });
  });
}
