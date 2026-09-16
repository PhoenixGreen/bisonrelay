import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_data.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_gradient_moved_test.dart is the second colour moving out of the
// element settings and into the colour picker.
//
// Two things had grown a gradient of their own: a chart series (Fade, To,
// Radial, Angle beside the swatch) and a procedural background (Gradient, To,
// Angle). Both now set it where the colour is set. What has to survive the
// move is every document already saved in the old shape -- including the
// procedural angle, which was measured clockwise from left-to-right and is
// now read off a compass like every other direction in a canvas.

void main() {
  group("a background saved before the move", () {
    test("still fades, and still points the way it did", () {
      // 90 the old way was top to bottom. 180 on a compass is the same.
      var back = ProceduralSpec.fromJson({
        "style": "rain",
        "bg": 0xFF0B0F14,
        "gradient": true,
        "gradientTo": 0xFF1B2530,
        "gradientAngle": 90,
      });
      expect(back.gradient, isNotNull);
      expect(back.gradient!.to, const Color(0xFF1B2530));
      expect(back.gradient!.angle, 180);
    });

    test("a flag saved switched off is no gradient at all", () {
      var back = ProceduralSpec.fromJson({
        "style": "rain",
        "gradient": false,
        "gradientTo": 0xFF1B2530,
      });
      expect(back.gradient, isNull,
          reason: "an off gradient is one nobody wanted, not a black fade");
    });

    test("and one saved with no gradient key has none", () {
      expect(ProceduralSpec.fromJson({"style": "rain"}).gradient, isNull);
    });
  });

  group("a background saved after it", () {
    test("round trips through the new shape", () {
      const spec = ProceduralSpec(
        style: ProceduralStyle.rain,
        gradient: GradientSpec(to: Color(0xFF1B2530), angle: 210, radial: true),
      );
      var back = ProceduralSpec.fromJson(spec.toJson());
      expect(back.gradient, spec.gradient);
    });

    test("costs nothing when it is flat", () {
      const flat = ProceduralSpec(style: ProceduralStyle.rain);
      expect(flat.toJson().containsKey("gradient"), isFalse);
    });

    test("going flat forgets it", () {
      const spec = ProceduralSpec(
        style: ProceduralStyle.rain,
        gradient: GradientSpec(to: Color(0xFF1B2530)),
      );
      expect(spec.copyWith(flatBackground: true).gradient, isNull);
      expect(spec.copyWith(seed: 4).gradient, isNotNull);
    });
  });

  group("a series saved before the move", () {
    test("keeps its second colour", () {
      var series = ChartSeries.fromJson({
        "name": "s",
        "color": 0xFF3D7EFF,
        "values": [1.0],
        "gradient": {"on": true, "to": 0xFFFF3DAA, "angle": 90},
      }, 0);
      expect(series.gradient!.to, const Color(0xFFFF3DAA));
      expect(series.gradient!.angle, 90,
          reason: "a series' angle was already read off a compass");
    });

    test("and one saved switched off comes back as one colour", () {
      var series = ChartSeries.fromJson({
        "name": "s",
        "color": 0xFF3D7EFF,
        "values": [1.0],
        "gradient": {"on": false, "to": 0xFFFF3DAA},
      }, 0);
      expect(series.gradient, isNull);
    });
  });

  group("a series' own thickness", () {
    test("is the chart's until it is given one", () {
      const series =
          ChartSeries(name: "s", color: Color(0xFF3D7EFF), values: []);
      expect(series.width, 0);
      expect(series.widthOn(3), 3);
      expect(series.copyWith(width: 8).widthOn(3), 8);
    });

    test("survives being saved, and costs nothing when unused", () {
      const series =
          ChartSeries(name: "s", color: Color(0xFF3D7EFF), values: []);
      expect(series.toJson().containsKey("width"), isFalse);
      var thick = series.copyWith(width: 6.5);
      expect(ChartSeries.fromJson(thick.toJson(), 0).width, 6.5);
    });
  });

  group("a shape that fades", () {
    const plain = ShapeElement(ElementBase(id: "s"));

    test("is flat until a second colour is chosen", () {
      expect(plain.fillFade, isNull);
      expect(plain.strokeFade, isNull);
      expect(plain.toJson().containsKey("fillFade"), isFalse);
    });

    test("keeps its two fades apart", () {
      // The fill and the outline are coloured separately, so they fade
      // separately -- a shape filled with a fade and outlined flat is the
      // common case, not an odd one.
      var e =
          plain.copyWith(fillFade: const GradientSpec(to: Color(0xFFFF3DAA)));
      expect(e.fillFade, isNotNull);
      expect(e.strokeFade, isNull);
    });

    test("survives being saved", () {
      var e = plain.copyWith(
        fillFade: const GradientSpec(to: Color(0xFFFF3DAA), radial: true),
        strokeFade: const GradientSpec(to: Color(0xFF2FD3A0), angle: 45),
      );
      var back = ShapeElement.fromJson(e.toJson(), e.base);
      expect(back.fillFade, e.fillFade);
      expect(back.strokeFade, e.strokeFade);
    });

    test("and going flat forgets it", () {
      var e = plain.copyWith(
        fillFade: const GradientSpec(to: Color(0xFFFF3DAA)),
        strokeFade: const GradientSpec(to: Color(0xFF2FD3A0)),
      );
      expect(e.copyWith(flatFill: true).fillFade, isNull);
      expect(e.copyWith(flatFill: true).strokeFade, isNotNull,
          reason: "clearing one does not clear the other");
      expect(e.copyWith(flatStroke: true).strokeFade, isNull);
    });
  });

  group("everything else that can fade", () {
    const fade = GradientSpec(to: Color(0xFFFF3DAA));

    test("a box: its fill and its border, separately", () {
      // One BoxSpec is a picture's background and border, a button's, and the
      // band behind a line of text -- so this is three settings groups, not
      // one.
      const box = BoxSpec(fill: Color(0xFF3D7EFF));
      var faded = box.copyWith(fillFade: fade);
      expect(faded.fillFade, fade);
      expect(faded.borderFade, isNull);
      expect(BoxSpec.fromJson(faded.toJson()).fillFade, fade);
      expect(faded.copyWith(flatFill: true).fillFade, isNull);
      expect(box.toJson().containsKey("fillFade"), isFalse);
    });

    test("and a box keeps them through the corner and padding rewrites", () {
      // withCorners and withRoom rebuild the whole box rather than copying
      // it, which is exactly where a newly added field gets dropped.
      var faded = const BoxSpec(fill: Color(0xFF3D7EFF))
          .copyWith(fillFade: fade, borderFade: fade);
      expect(faded.withEvenRadius(6).fillFade, fade);
      expect(faded.withEvenPad(4).borderFade, fade);
    });

    test("a line", () {
      const line = LineElement(ElementBase(id: "l"));
      var faded = line.copyWith(fade: fade);
      expect(faded.fade, fade);
      expect(LineElement.fromJson(faded.toJson(), faded.base).fade, fade);
      expect(faded.copyWith(flat: true).fade, isNull);
      expect(line.toJson().containsKey("fade"), isFalse);
    });

    test("a path", () {
      const path = PathElement(ElementBase(id: "p"));
      var faded = path.copyWith(fade: fade);
      expect(faded.fade, fade);
      expect(PathElement.fromJson(faded.toJson(), faded.base).fade, fade);
      expect(faded.copyWith(flat: true).fade, isNull);
    });

    test("a table's cells and its header, separately", () {
      const table = TableElement(ElementBase(id: "t"));
      var faded = table.copyWith(cellFade: fade);
      expect(faded.cellFade, fade);
      expect(faded.headerFade, isNull);
      var back = TableElement.fromJson(faded.toJson(), faded.base);
      expect(back.cellFade, fade);
      expect(faded.copyWith(flatCells: true).cellFade, isNull);
    });

    test("and a table keeps them when it is moved", () {
      // rebase builds a new element from every field by hand, which is the
      // other place a newly added field gets quietly dropped.
      var faded = const TableElement(ElementBase(id: "t"))
          .copyWith(cellFade: fade, headerFade: fade);
      var moved =
          faded.rebase(const ElementBase(id: "t", x: 40)) as TableElement;
      expect(moved.cellFade, fade);
      expect(moved.headerFade, fade);
    });

    test("and so do a line and a path", () {
      var line = const LineElement(ElementBase(id: "l")).copyWith(fade: fade);
      expect(
          (line.rebase(const ElementBase(id: "l", x: 9)) as LineElement).fade,
          fade);
      var path = const PathElement(ElementBase(id: "p")).copyWith(fade: fade);
      expect(
          (path.rebase(const ElementBase(id: "p", x: 9)) as PathElement).fade,
          fade);
    });
  });
}
