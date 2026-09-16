import 'package:bruig/components/paint_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// paint_spec_test.dart is "what something is coloured in": one colour, or two
// with a gradient between them.
//
// The point of the type is that a gradient is set where a colour is set, so
// the things worth pinning down are the ones that decide whether an existing
// swatch can become one without anything else changing: a plain colour still
// saves as the integer it always did, and a colour with no second colour
// still hands its caller nothing to paint with.

void main() {
  const from = Color(0xFF3D7EFF);
  const to = Color(0xFFFF3DAA);
  var area = const Rect.fromLTWH(0, 0, 100, 50);

  group("a plain colour", () {
    test("saves as the integer it always did", () {
      expect(const PaintSpec(from).toJson(), 0xFF3D7EFF);
    });

    test("reads back from one, so old documents still open", () {
      expect(PaintSpec.fromJson(0xFF3D7EFF), const PaintSpec(from));
      expect(PaintSpec.fromJson(0xFF3D7EFF).gradient, isNull);
    });

    test("has nothing to paint with, so the caller uses the colour", () {
      expect(const PaintSpec(from).shaderFor(area), isNull);
      expect(const PaintSpec(from).fades, isFalse);
    });

    test("falls back when the saved value is not a colour at all", () {
      expect(PaintSpec.fromJson(null, to).color, to);
      expect(PaintSpec.fromJson("blue", to).color, to);
    });
  });

  group("a colour that fades", () {
    const two = PaintSpec(from, gradient: GradientSpec(to: to, angle: 90));

    test("saves both ends and reads them back", () {
      var back = PaintSpec.fromJson(two.toJson());
      expect(back, two);
      expect(back.gradient!.to, to);
      expect(back.gradient!.angle, 90);
    });

    test("costs nothing extra when it is off", () {
      expect(const PaintSpec(from).toJson(), isA<int>());
      expect(two.toJson(), isA<Map>());
    });

    test("hands the caller something to paint with", () {
      expect(two.shaderFor(area), isNotNull);
      expect(two.fades, isTrue);
    });

    test("has nothing to paint an empty area with", () {
      // ui refuses to build a gradient with no distance to run over, and a
      // chart draws plenty of zero-height bars.
      expect(two.shaderFor(Rect.zero), isNull);
    });

    test("going plain forgets it", () {
      expect(two.copyWith(plain: true).gradient, isNull);
      expect(two.copyWith(color: to).gradient, isNotNull);
    });
  });

  group("where the colours stop being themselves", () {
    test("is the whole run by default", () {
      expect(const GradientSpec().positions, [0.0, 1.0]);
    });

    test("comes back in order however it was set", () {
      var places = const GradientSpec(start: 0.8, end: 0.2).positions;
      expect(places.first, lessThan(places.last));
    });

    test("is never the same place twice", () {
      // A hard edge is a fair thing to want; two stops at one number is a
      // gradient ui refuses to build.
      var places = const GradientSpec(start: 0.5, end: 0.5).positions;
      expect(places[1], greaterThan(places[0]));
      expect(places[1] - places[0], lessThan(0.01),
          reason: "still a hard edge, just a buildable one");
    });

    test("stays inside the run", () {
      var places = const GradientSpec(start: -3, end: 9).positions;
      expect(places.first, 0.0);
      expect(places.last, 1.0);
    });

    test("only what is not the default is written down", () {
      expect(const GradientSpec().toJson().containsKey("start"), isFalse);
      expect(const GradientSpec().toJson().containsKey("more"), isFalse);
      expect(const GradientSpec().toJson().containsKey("falloff"), isFalse);
      expect(const GradientSpec(start: 0.3).toJson()["start"], 0.3);
      expect(
          GradientSpec.fromJson(
              const GradientSpec(start: 0.3, end: 0.7).toJson()),
          const GradientSpec(start: 0.3, end: 0.7));
    });
  });

  group("a fade through more than two colours", () {
    const three = GradientSpec(
      to: Color(0xFFFF3DAA),
      end: 0.5,
      more: [GradientStop(Color(0xFF2FD3A0), 1)],
    );

    test("counts the colour it starts from", () {
      expect(const GradientSpec().count, 2);
      expect(three.count, 3);
      expect(three.ramp.length, 2);
    });

    test("adding one puts it in the gap rather than on top of another", () {
      var (four, where) = const GradientSpec().plus();
      expect(four.count, 3);
      expect(where, 0, reason: "and says where it landed, so it can be chosen");
      var places = four.positions;
      for (var i = 1; i < places.length; i++) {
        expect(places[i], greaterThan(places[i - 1]));
      }
    });

    test("and it starts as the colour that was already there", () {
      // Otherwise every added stop is a stripe that has to be undone.
      var (four, where) = three.plus();
      expect(four.ramp[where].color, isNot(const Color(0x00000000)));
    });

    test("taking one away leaves the rest", () {
      var back = three.minus(0)!;
      expect(back.count, 2);
      expect(back.to, const Color(0xFF2FD3A0));
    });

    test("and the last one cannot be taken away", () {
      // A fade with one colour is a flat colour, and the way to say that is
      // no gradient at all -- which is the caller's business, not this one's.
      expect(const GradientSpec().minus(0), isNull);
    });

    test("survives being saved", () {
      expect(GradientSpec.fromJson(three.toJson()), three);
    });

    test("and a two-colour one saved before there could be a third", () {
      var back = GradientSpec.fromJson({"to": 0xFFFF3DAA, "angle": 90});
      expect(back.count, 2);
      expect(back.to, const Color(0xFFFF3DAA));
      expect(back.more, isEmpty);
    });

    test("every colour reaches the shader", () {
      var (colours, places) =
          const PaintSpec(Color(0xFF3D7EFF), gradient: three).rampFor();
      expect(colours.length, 3);
      expect(colours[1], const Color(0xFFFF3DAA));
      expect(places, [0.0, 0.5, 1.0]);
    });
  });

  group("how sharp the change is", () {
    const even = PaintSpec(Color(0xFF000000),
        gradient: GradientSpec(to: Color(0xFFFFFFFF)));

    PaintSpec biased(double bias) => PaintSpec(const Color(0xFF000000),
        gradient: GradientSpec(
                to: const Color(0xFFFFFFFF), end: 1, more: const [], start: 0)
            .withStop(0, GradientStop(const Color(0xFFFFFFFF), 1, bias: bias)));

    /// _midway is the colour the ramp has reached halfway along.
    double midway(PaintSpec paint) {
      var (colours, places) = paint.rampFor();
      var at = 0;
      for (var i = 0; i < places.length; i++) {
        if (places[i] <= 0.5) at = i;
      }
      return colours[at].r;
    }

    test("is two stops when every change is even", () {
      var (colours, _) = even.rampFor();
      expect(colours.length, 2, reason: "a straight line needs no help");
    });

    test("is drawn as several when one is not", () {
      var (colours, places) = biased(0.8).rampFor();
      expect(colours.length, greaterThan(4),
          reason: "a shader only knows straight lines between stops");
      for (var i = 1; i < places.length; i++) {
        expect(places[i], greaterThanOrEqualTo(places[i - 1]));
      }
    });

    test("a handle pulled late leaves the first colour holding on", () {
      expect(midway(biased(0.8)), lessThan(0.4));
    });

    test("and pulled early lets the second one in", () {
      expect(midway(biased(0.2)), greaterThan(0.6));
    });

    test("halfway is halfway, whichever way it was set", () {
      // The whole meaning of the handle: at the place it sits, the two
      // colours are mixed evenly.
      var (colours, places) = biased(0.25).rampFor();
      var nearest = 0;
      for (var i = 0; i < places.length; i++) {
        if ((places[i] - 0.25).abs() < (places[nearest] - 0.25).abs()) {
          nearest = i;
        }
      }
      expect(colours[nearest].r, closeTo(0.5, 0.12));
    });

    test("the first span's handle survives a rewrite of the ramp", () {
      // The first colour after the base is held out in its own fields rather
      // than as ramp[0], so putting a ramp back is where its bias gets
      // dropped -- and a handle that springs back to the middle every time
      // another point moves is worse than no handle.
      var spec = const GradientSpec(to: Color(0xFFFF3DAA), toBias: 0.2);
      expect(spec.ramp.first.bias, 0.2);
      expect(spec.withRamp(spec.ramp).toBias, 0.2);
      expect(spec.withStop(0, spec.ramp.first.copyWith(at: 0.7)).toBias, 0.2,
          reason: "moving the point does not reset the handle beside it");
      expect(GradientSpec.fromJson(spec.toJson()).toBias, 0.2);
    });

    test("it belongs to one span, not to the whole fade", () {
      // The tightness of red into orange has nothing to do with the tightness
      // of orange into black.
      const three = GradientSpec(
        to: Color(0xFFFF3DAA),
        end: 0.5,
        more: [GradientStop(Color(0xFF2FD3A0), 1, bias: 0.9)],
      );
      expect(three.ramp[0].bias, 0.5);
      expect(three.ramp[1].bias, 0.9);
    });

    test("costs nothing on the spans that do not use it", () {
      expect(const GradientStop(Color(0xFF000000), 1).bias, 0.5);
      expect(
          const GradientStop(Color(0xFF000000), 1).toJson().containsKey("bias"),
          isFalse);
      expect(
          GradientStop.fromJson(
                  const GradientStop(Color(0xFF000000), 1, bias: 0.3).toJson())
              .bias,
          0.3);
    });
  });

  group("which way it runs", () {
    var square = const Rect.fromLTWH(0, 0, 100, 100);

    test("is read off a compass: 0 is up, 90 is right", () {
      var (up, _) = const GradientSpec(angle: 0).endsOf(square);
      expect(up.dy, greaterThan(square.center.dy),
          reason: "running up means starting below the middle");
      var (right, _) = const GradientSpec(angle: 90).endsOf(square);
      expect(right.dx, lessThan(square.center.dx));
    });

    test("a radial one ignores it", () {
      const a = PaintSpec(from,
          gradient: GradientSpec(to: to, radial: true, angle: 0));
      const b = PaintSpec(from,
          gradient: GradientSpec(to: to, radial: true, angle: 180));
      expect(a.gradient == b.gradient, isFalse,
          reason: "the angle is still kept, in case it goes back to straight");
      expect(a.shaderFor(square), isNotNull);
    });
  });
}
