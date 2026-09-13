import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart' as doc;
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/image_silhouette.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/image_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_box_spec_test.dart is the frame round an element: its background,
// its border, its corners and the room it keeps inside.
//
// The four sides and the four corners can each be set on their own, over a
// single number that answers for the rest. What is worth pinning is that the
// single number still means what it always meant -- every document ever saved
// has one of those in it and none of them have the four.

class _Pictures implements CanvasImageSource {
  final ui.Image image;
  _Pictures(this.image);
  @override
  ui.Image? resolve(String assetId, BackgroundRemoval removal) => image;
  @override
  CanvasVector? resolveVector(String assetId) => null;
  @override
  ImageSilhouette? resolveOutline(String assetId, BackgroundRemoval removal) =>
      null;
}

/// _picture is a flat orange square, so where it lands can be read off the
/// pixels and told apart from the background behind it.
Future<ui.Image> _picture() async {
  var recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 60, 60),
      Paint()..color = const Color(0xFFFF8000));
  return recorder.endRecording().toImage(60, 60);
}

const _size = 200;

/// _shot draws one picture element in [box] and hands back its pixels.
Future<(Set<int> orange, Set<int> blue)> _shot(BoxSpec box) async {
  var picture = await _picture();
  var element = ImageElement(
    const ElementBase(id: "i", x: 20, y: 20, width: 160, height: 160),
    assetId: "a",
    fit: ImageFit.cover,
    box: box,
  );
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 200, 200),
      Paint()..color = const Color(0xFF000000));
  paintElement(canvas, element, 0,
      document: CanvasDocument(elements: [element]),
      images: _Pictures(picture));
  var image = await recorder.endRecording().toImage(_size, _size);
  var bytes = (await image.toByteData())!;
  var orange = <int>{};
  var blue = <int>{};
  for (var i = 0; i < bytes.lengthInBytes; i += 4) {
    var p = bytes.getUint32(i);
    var r = (p >> 24) & 0xFF, g = (p >> 16) & 0xFF, b = (p >> 8) & 0xFF;
    if (r > 0x90 && g > 0x40 && b < 0x40) orange.add(i ~/ 4);
    if (b > 0x90 && r < 0x60) blue.add(i ~/ 4);
  }
  image.dispose();
  picture.dispose();
  return (orange, blue);
}

int _left(Set<int> ink) =>
    ink.map((at) => at % _size).reduce((a, b) => a < b ? a : b);
int _right(Set<int> ink) =>
    ink.map((at) => at % _size).reduce((a, b) => a > b ? a : b);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const framed = BoxSpec(fill: Color(0xFF2060FF), padding: 10);

  group("the room inside", () {
    test("is the one number until a side is given its own", () {
      const even = BoxSpec(padding: 12);
      expect(even.padLeft, 12);
      expect(even.padBottom, 12);
      expect(even.evenPad, 12);

      var uneven = even.copyWith(padL: 40);
      expect(uneven.padLeft, 40);
      expect(uneven.padTop, 12, reason: "the others still follow the one");
      expect(uneven.evenPad, isNull, reason: "so the all-sides field is blank");
    });

    test("and setting all four again forgets what they had", () {
      const uneven = BoxSpec(padding: 4, padL: 40, padB: 26);
      expect(uneven.withEvenPad(6).padLeft, 6);
      expect(uneven.withEvenPad(6).padBottom, 6);
    });

    testWidgets("puts the picture where the sides say", (tester) async {
      late (Set<int>, Set<int>) even;
      late (Set<int>, Set<int>) shifted;
      await tester.runAsync(() async {
        even = await _shot(framed);
        shifted = await _shot(framed.copyWith(padL: 50));
      });
      expect(_left(shifted.$1), greaterThan(_left(even.$1) + 30),
          reason: "a wider left side pushes the picture right");
      expect(_right(shifted.$1), _right(even.$1),
          reason: "and leaves the other side where it was");
    });

    testWidgets("and the background shows in the room it leaves",
        (tester) async {
      // What a background colour is *for*: the part of the box the picture
      // does not reach.
      late (Set<int>, Set<int>) tight;
      late (Set<int>, Set<int>) roomy;
      await tester.runAsync(() async {
        tight = await _shot(framed.copyWith(padding: 0));
        roomy = await _shot(framed.copyWith(padL: 50));
      });
      expect(tight.$2, isEmpty,
          reason: "a picture that covers its box hides the background");
      expect(roomy.$2.length, greaterThan(1000),
          reason: "and one held off the edge lets it show");
    });
  });

  group("padding a picture", () {
    // A box with room round the type is what padding means for words, and the
    // words reflow into what is left. A picture cannot reflow: told to cover
    // a box that has become shorter it keeps its proportions and crops, so
    // asking for a little room along the bottom cut the top and bottom off
    // the photograph. On a picture the room goes *around* it.
    ImageElement picture(BoxSpec box) => ImageElement(
          const ElementBase(id: "i", x: 30, y: 20, width: 100, height: 100),
          assetId: "a",
          box: box,
        );

    test("grows the box instead of shrinking the picture", () {
      var was = picture(const BoxSpec(padding: 0));
      var now = grownForPadding(was, was.box.copyWith(padB: 30));

      expect(was.box.inner(was.bounds), now.box.inner(now.bounds),
          reason: "the picture is drawn in exactly the same place");
      expect(now.bounds.bottom, was.bounds.bottom + 30,
          reason: "and the box has grown downwards to hold the room");
      expect(now.bounds.top, was.bounds.top,
          reason: "with the sides that were not asked for left alone");
    });

    test("and grows every side that is asked for", () {
      var was = picture(const BoxSpec(padding: 0));
      var now = grownForPadding(was, was.box.withEvenPad(16));
      expect(now.bounds, was.bounds.inflate(16));
      expect(now.box.inner(now.bounds), was.bounds);
    });

    test("however many times it is asked while a field is dragged", () {
      // Worked out from where the picture is drawn rather than from the
      // change in the numbers, so dragging a field -- which writes on every
      // pixel of the drag -- does not add the room up again and again.
      var was = picture(const BoxSpec(padding: 0));
      var once = grownForPadding(was, was.box.withEvenPad(20));
      var twice = grownForPadding(once, once.box.withEvenPad(20));
      expect(twice.bounds, once.bounds);
    });
  });

  group("the corners", () {
    test("are the one number until a corner is given its own", () {
      const even = BoxSpec(borderRadius: 8);
      expect(even.topLeft, 8);
      expect(even.evenRadius, 8);

      var cut = even.copyWith(radBR: 40);
      expect(cut.bottomRight, 40);
      expect(cut.topLeft, 8);
      expect(cut.evenRadius, isNull);
      expect(cut.isRounded, isTrue);
    });

    testWidgets("round only the corner they belong to", (tester) async {
      // Read off the picture itself: a rounded corner takes a bite out of
      // it, so the corner pixel is background where it is rounded and
      // picture where it is not.
      late (Set<int>, Set<int>) square;
      late (Set<int>, Set<int>) cut;
      await tester.runAsync(() async {
        square = await _shot(const BoxSpec(padding: 0));
        cut = await _shot(const BoxSpec(padding: 0, radTL: 40));
      });
      const topLeft = (22 * _size) + 22;
      const topRight = (22 * _size) + 177;
      expect(square.$1.contains(topLeft), isTrue);
      expect(cut.$1.contains(topLeft), isFalse,
          reason: "the corner that was given a radius is rounded");
      expect(cut.$1.contains(topRight), isTrue,
          reason: "and the ones that were not are square");
    });
  });

  group("a shape's own corners and room", () {
    // The same two questions a frame answers, on the element that is itself
    // the frame. A shape paints its own fill and stroke, so it cannot simply
    // be given a BoxSpec -- but it rounds and insets through the same Corners
    // and Room, so the two cannot drift apart.
    Future<Set<int>> lit(ShapeElement element) async {
      var recorder = ui.PictureRecorder();
      var canvas = ui.Canvas(recorder);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 200, 200),
          Paint()..color = const Color(0xFF000000));
      paintElement(canvas, element, 0,
          document: doc.CanvasDocument(elements: [element]));
      var image = await recorder.endRecording().toImage(_size, _size);
      var bytes = (await image.toByteData())!;
      var on = <int>{};
      for (var i = 0; i < bytes.lengthInBytes; i += 4) {
        if (bytes.getUint32(i) != 0x000000FF) on.add(i ~/ 4);
      }
      image.dispose();
      return on;
    }

    ShapeElement rect({double? radTL, double? radBR, double all = 0}) =>
        ShapeElement(
          const ElementBase(id: "s", x: 20, y: 20, width: 160, height: 160),
          fill: const Color(0xFFFFFFFF),
          cornerRadius: all,
          radTL: radTL,
          radBR: radBR,
        );

    testWidgets("round the corner they are given and no other", (tester) async {
      late Set<int> square;
      late Set<int> cut;
      await tester.runAsync(() async {
        square = await lit(rect());
        cut = await lit(rect(radTL: 50));
      });
      const topLeft = (23 * _size) + 23;
      const topRight = (23 * _size) + 176;
      expect(square.contains(topLeft), isTrue);
      expect(cut.contains(topLeft), isFalse,
          reason: "the corner that was given a radius is rounded");
      expect(cut.contains(topRight), isTrue,
          reason: "and the ones that were not are square");
    });

    test("and only the shapes with corners are offered them", () {
      // A field that does nothing is worse than no field.
      expect(ShapeKind.rectangle.hasCorners, isTrue);
      expect(ShapeKind.speechBubble.hasCorners, isTrue);
      expect(ShapeKind.circle.hasCorners, isFalse);
      expect(ShapeKind.star.hasCorners, isFalse);
    });

    test("the label's room is the shape's own until it is set", () {
      // Zero means "you decide": a circle needs more inset than a rectangle
      // and a triangle more again, and those are the numbers nobody should
      // have to set. Anything asked for replaces them.
      var plain = ShapeElement(
          const ElementBase(id: "s", x: 0, y: 0, width: 100, height: 100),
          text: "Hi");
      expect(plain.padded, isFalse);
      var box = labelRoom(plain, plain.bounds);
      expect(box.width, lessThan(100),
          reason: "a rectangle still keeps the label off its edge");

      var asked = plain.copyWith(padding: 5, padT: 40);
      expect(asked.padded, isTrue);
      expect(
          labelRoom(asked, asked.bounds), const Rect.fromLTRB(5, 40, 95, 95));
    });

    test("and setting all four forgets the ones that had their own", () {
      var uneven = ShapeElement(const ElementBase(id: "s"),
          cornerRadius: 4, radTL: 40, padding: 2, padB: 30);
      var even =
          uneven.copyWith(cornerRadius: 9, radTL: null, clearCorners: true);
      expect(even.corners.even, 9);
      expect(even.pad.bottom, 30, reason: "and leaves the other one alone");
    });

    test("which all survives being saved", () {
      var shape = ShapeElement(const ElementBase(id: "s"),
          cornerRadius: 6,
          radTL: 30,
          radBR: 12,
          padding: 3,
          padT: 40,
          text: "Hi");
      var back = doc.elementFromJson(shape.toJson()) as ShapeElement;
      expect(back.corners, shape.corners);
      expect(back.pad, shape.pad);
    });
  });

  group("a saved box", () {
    test("keeps its sides and corners", () {
      const box = BoxSpec(
          fill: Color(0xFF112233),
          borderWidth: 2,
          borderRadius: 6,
          padding: 4,
          padL: 30,
          padB: 26,
          radTL: 40,
          radBR: 12);
      expect(BoxSpec.fromJson(box.toJson()), box);
    });

    test("and one saved before they existed reads as an even box", () {
      // Every document written until now has a single number for each. Read
      // back, the four follow it -- so nothing that was saved moves.
      var old = BoxSpec.fromJson(const {"pad": 14.0, "br": 9.0});
      expect(old.padLeft, 14);
      expect(old.padBottom, 14);
      expect(old.bottomRight, 9);
      expect(old.evenPad, 14);
      expect(old.toJson().containsKey("padL"), isFalse,
          reason: "and it is written back out the way it came in");
    });
  });
}
