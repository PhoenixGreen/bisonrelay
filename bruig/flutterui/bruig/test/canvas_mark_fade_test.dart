import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_mark_fade_test.dart is the smaller colours that learned to fade with
// the text: the band behind some words, the line under them, and the figures
// and titles round a chart.
//
// The chart's two label types had a size and a gap and no colour at all, so a
// chart on a pale background wrote its figures in whatever the default was
// with nowhere to say otherwise. That was a gap rather than a gradient
// question, and it is filled here as well.

void main() {
  const fade = GradientSpec(to: Color(0xFFFF3DAA));

  group("the band behind some words", () {
    const plain = PartHighlight();

    test("is flat until a second colour is chosen", () {
      expect(plain.fade, isNull);
      expect(plain.toJson().containsKey("fade"), isFalse);
    });

    test("keeps it, and gives it up when asked", () {
      var two = plain.copyWith(fade: fade);
      expect(two.fade, fade);
      expect(two.copyWith(flat: true).fade, isNull);
      expect(two.copyWith(radius: 4).fade, fade,
          reason: "changing something else does not clear it");
    });

    test("and survives being saved", () {
      expect(PartHighlight.fromJson(plain.copyWith(fade: fade).toJson()).fade,
          fade);
    });
  });

  group("the line under them", () {
    const plain = PartUnderline();

    test("is flat until a second colour is chosen", () {
      expect(plain.fade, isNull);
      expect(plain.toJson().containsKey("fade"), isFalse);
    });

    test("keeps its own colour and its fade apart", () {
      // The line's colour may be null, meaning "the words'". A fade on top of
      // that is still a fade, from whatever the words are.
      var two = plain.copyWith(fade: fade);
      expect(two.color, isNull);
      expect(two.fade, fade);
      expect(two.copyWith(flat: true).fade, isNull);
    });

    test("and survives being saved", () {
      expect(PartUnderline.fromJson(plain.copyWith(fade: fade).toJson()).fade,
          fade);
    });
  });

  group("a chart's writing", () {
    const chart = ChartElement(ElementBase(id: "c"));

    test("the figures and the axis titles are coloured separately", () {
      // Two kinds of writing with two jobs: the numbers up the side and the
      // word naming the axis.
      var painted = chart.copyWith(
        labelSpec: chart.labelSpec.copyWith(color: const Color(0xFF112233)),
        axisSpec: chart.axisText.copyWith(color: const Color(0xFF445566)),
      );
      expect(painted.labelSpec.color, const Color(0xFF112233));
      expect(painted.axisText.color, const Color(0xFF445566));
    });

    test("and the writing can fade", () {
      var painted =
          chart.copyWith(labelSpec: chart.labelSpec.copyWith(fade: fade));
      expect(painted.labelSpec.fade, fade);
      var back = ChartElement.fromJson(painted.toJson(), painted.base);
      expect(back.labelSpec.fade, fade);
    });

    test("an axis title given its own settings keeps them", () {
      // The titles take the figures' settings until they are given their own,
      // which is why the two swatches are separate controls rather than one.
      const other = GradientSpec(to: Color(0xFF2FD3A0));
      var painted = chart.copyWith(
        labelSpec: chart.labelSpec.copyWith(fade: fade),
        axisSpec: chart.axisText.copyWith(fade: other),
      );
      expect(painted.axisText.fade, other);
      expect(painted.labelSpec.fade, fade);
    });
  });
}
