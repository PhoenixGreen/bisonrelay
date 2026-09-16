import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/theming_system/model/area_gradient.dart';
import 'package:bruig/theming_system/model/area_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// area_gradient_test.dart is a theme area's gradient going to the app's
// colour picker and back.
//
// The two are not the same shape and neither is wrong. An area keeps a list
// of colours, a list of stops and a begin/end Alignment, because that is what
// a BoxDecoration wants; the picker keeps a first colour, a ramp and a
// compass angle, because that is what one picker can edit. So the thing worth
// pinning down is that a round trip changes nothing -- every theme already
// saved was written in the first shape.

void main() {
  const red = Color(0xFFFF0000);
  const blue = Color(0xFF0000FF);
  const green = Color(0xFF00FF00);

  group("which way it runs", () {
    test("reads the four the dropdown used to offer", () {
      // The named directions it replaced, as compass angles: the same
      // gradients, so a theme saved before this points the way it did.
      expect(areaAngleOf(Alignment.topLeft, Alignment.bottomRight),
          closeTo(135, 0.5));
      expect(areaAngleOf(Alignment.topRight, Alignment.bottomLeft),
          closeTo(225, 0.5));
      expect(areaAngleOf(Alignment.centerLeft, Alignment.centerRight),
          closeTo(90, 0.5));
      expect(areaAngleOf(Alignment.topCenter, Alignment.bottomCenter),
          closeTo(180, 0.5));
    });

    test("and writes them back unchanged", () {
      for (var pair in [
        (Alignment.topLeft, Alignment.bottomRight),
        (Alignment.topRight, Alignment.bottomLeft),
        (Alignment.centerLeft, Alignment.centerRight),
        (Alignment.topCenter, Alignment.bottomCenter),
      ]) {
        var (begin, end) = areaEndsOf(areaAngleOf(pair.$1, pair.$2));
        expect(begin, pair.$1);
        expect(end, pair.$2);
      }
    });

    test("an angle between them still reaches both edges", () {
      // An Alignment runs -1 to 1. A gradient at 30 degrees whose end only
      // reached 0.5 across would fade out inside the area instead of at its
      // edge.
      // 30 degrees runs up and to the right, so it starts at the bottom.
      var (begin, end) = areaEndsOf(30);
      expect(begin.y, 1.0);
      expect(end.y, -1.0);
      expect(end.x, greaterThan(0));
      expect(end.x, lessThan(1));
    });
  });

  group("a gradient going to the picker and back", () {
    test("keeps its colours, in order", () {
      var paint = areaPaintOf(
          [red, blue, green], null, Alignment.topLeft, Alignment.bottomRight);
      expect(paint.color, red);
      expect(paint.gradient!.to, blue);
      expect(paint.gradient!.more.single.color, green);
      expect(areaGradientOf(paint).colours, [red, blue, green]);
    });

    test("spreads them evenly where it had no stops", () {
      // What a BoxDecoration does with none, said out loud so the picker's
      // handles land where the gradient actually changes.
      var paint = areaPaintOf(
          [red, blue, green], null, Alignment.topLeft, Alignment.bottomRight);
      expect(paint.gradient!.positions, [0.0, 0.5, 1.0]);
    });

    test("and keeps the stops it had", () {
      var paint = areaPaintOf([red, blue, green], const [0.0, 0.2, 1.0],
          Alignment.topLeft, Alignment.bottomRight);
      expect(paint.gradient!.positions, [0.0, 0.2, 1.0]);
      expect(areaGradientOf(paint).stops, [0.0, 0.2, 1.0]);
    });

    test("keeps which way it runs, and whether it runs outwards", () {
      var paint = areaPaintOf(
          [red, blue], null, Alignment.centerLeft, Alignment.centerRight,
          radial: true);
      expect(paint.gradient!.angle, closeTo(90, 0.5));
      expect(paint.gradient!.radial, isTrue);
      var back = areaGradientOf(paint);
      expect(back.begin, Alignment.centerLeft);
      expect(back.end, Alignment.centerRight);
      expect(back.radial, isTrue);
    });

    test("a fill with one colour has nothing to fade", () {
      expect(
          areaPaintOf([red], null, Alignment.topLeft, Alignment.bottomRight)
              .gradient,
          isNull);
      expect(
          areaPaintOf([], null, Alignment.topLeft, Alignment.bottomRight)
              .gradient,
          isNull);
    });

    test("and a flat colour comes back as two, never one", () {
      // An area in gradient mode builds a LinearGradient out of what it is
      // given, and a LinearGradient of one colour is one Flutter refuses to
      // build.
      var back = areaGradientOf(const PaintSpec(red));
      expect(back.colours, [red, red]);
      expect(back.stops.length, 2);
    });
  });

  group("running outwards", () {
    test("is off by default and costs nothing when it is", () {
      const flat = AreaStyle();
      expect(flat.gradientRadial, isFalse);
      expect(flat.borderGradientRadial, isFalse);
      expect(flat.toJson().containsKey("gradientRadial"), isFalse);
    });

    test("survives being saved, and the border's is its own", () {
      var style = const AreaStyle().copyWith(gradientRadial: true);
      var back = AreaStyle.fromJson(style.toJson());
      expect(back.gradientRadial, isTrue);
      expect(back.borderGradientRadial, isFalse,
          reason: "a background that runs outwards does not make the border "
              "run outwards too");
    });
  });
}
