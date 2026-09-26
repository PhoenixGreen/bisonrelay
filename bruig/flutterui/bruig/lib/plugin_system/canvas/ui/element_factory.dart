import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

// element_factory.dart makes a new element of each kind.
//
// One place rather than at each of the two call sites -- the Design Elements
// panel's tap, and its drag onto the canvas -- because a new chart that came
// out with sample data one way and empty the other would be a difference
// nobody could explain.
//
// Every new element arrives with something in it. An empty chart, an empty
// table and a blank text box are all indistinguishable from a bug the first
// time somebody adds one, and having to type before you can see whether you
// wanted the thing is the wrong way round. What is put in is deliberately
// obviously placeholder -- "Text", "Week 1" -- so nobody publishes it by
// accident.

/// defaultSizeFor is how big a new element starts, as a fraction of the
/// document's shorter side.
///
/// Sized to the document rather than fixed, so an element dropped on a 400px
/// canvas is not larger than the canvas and one dropped on a 4000px canvas is
/// not a speck.
Size defaultSizeFor(ElementKind kind, CanvasDocument document) {
  var short = document.size.height.toDouble();
  var wide = document.size.width.toDouble();
  return switch (kind) {
    ElementKind.text => Size(wide * 0.5, short * 0.16),
    ElementKind.image => Size(short * 0.5, short * 0.5),
    ElementKind.shape => Size(short * 0.28, short * 0.28),
    ElementKind.line => Size(wide * 0.3, short * 0.001 + 4),
    ElementKind.chart => Size(wide * 0.6, short * 0.6),
    ElementKind.table => Size(wide * 0.55, short * 0.4),
    ElementKind.button => Size(short * 0.32, short * 0.11),
    // Wide enough for a figure with words either side of it, and tall enough
    // for the row of buttons a live one can carry.
    ElementKind.counter => Size(wide * 0.34, short * 0.22),
    ElementKind.background => Size(wide * 0.6, short * 0.5),
    // A team, not a player: the box is the half of the pitch the formation is
    // laid out in, so it wants most of the canvas rather than a dot's worth.
    ElementKind.player => Size(wide * 0.46, short * 0.86),
    // A path is a route across the design rather than an object on it, so it
    // arrives large enough to be worth curving.
    ElementKind.path => Size(wide * 0.5, short * 0.4),
  };
}

/// newElement makes one of [kind], centred on [center] in document space.
CanvasElement newElement(
  ElementKind kind,
  CanvasDocument document, {
  Offset? center,
}) {
  var size = defaultSizeFor(kind, document);
  var at = center ?? document.size.rect.center;
  var base = ElementBase(
    id: newElementId(),
    x: at.dx - size.width / 2,
    y: at.dy - size.height / 2,
    width: size.width,
    height: size.height,
  );

  // The type sizes are worked from the document's height so that text on a
  // small canvas is not enormous and text on a large one is not unreadable.
  var unit = document.size.height / 24;

  switch (kind) {
    case ElementKind.text:
      // Proportions held to begin with, like a picture's -- and for a nearer
      // reason: holding them scales the type, the spacing and the pieces with
      // the box, which is what dragging a corner of a card is meant to do.
      // Let go of, the box changes and what is in it stays the size it was.
      return TextElement(base.copyWith(lockAspect: true),
          text: "Text",
          textSpec: TextSpec(
            fontSize: unit * 1.6,
            weight: 700,
            align: TextAlignSpec.center,
          ),
          autoSize: true);

    case ElementKind.image:
      // Proportions locked to begin with. Every element can hold them now, but
      // a picture is the one that starts wanting to: a photograph dragged out
      // of its own shape is a photograph that looks wrong, and putting it back
      // by hand means finding the original numbers.
      return ImageElement(base.copyWith(lockAspect: true));

    case ElementKind.shape:
      return ShapeElement(base,
          shape: ShapeKind.rectangle,
          cornerRadius: unit * 0.4,
          textSpec: TextSpec(fontSize: unit, weight: 700));

    case ElementKind.line:
      return LineElement(base, strokeWidth: unit * 0.18, endEnd: LineEnd.arrow);

    case ElementKind.chart:
      return ChartElement(base,
          title: "Chart title",
          xAxisLabel: "Category",
          yAxisLabel: "Value",
          titleSpec: TextSpec(fontSize: unit * 0.9, weight: 700),
          labelSpec: TextSpec(fontSize: unit * 0.52),
          valueSpec: TextSpec(fontSize: unit * 0.45, weight: 600),
          data: const ChartData(
            categories: ["One", "Two", "Three", "Four", "Five"],
            series: [
              ChartSeries(
                name: "Series 1",
                color: Color(0xFF3D7EFF),
                values: [8, 14, 11, 19, 15],
              ),
            ],
          ));

    case ElementKind.counter:
      // On a document of pages this is a page number, because that is what a
      // number on a page is. It was a setting three controls into the
      // counter's panel and nobody found it: an element that has to be
      // hunted for is an element nobody knows exists. The dropdown is still
      // there for the counter that is meant to be a clock.
      if (document.isPages) {
        return CounterElement(base,
            source: CounterSource.page,
            from: 1,
            to: 1,
            numberSpec:
                TextSpec(fontSize: unit * 1.1, align: TextAlignSpec.center),
            box: const BoxSpec());
      }
      // A hundred, counting up from nothing, written plainly. Every other
      // element arrives with something obviously placeholder in it; the
      // placeholder here is the count itself, which is the one thing that
      // shows what this is the moment it lands.
      return CounterElement(base,
          from: 0,
          to: 100,
          numberSpec: TextSpec(
              fontSize: unit * 2.4, weight: 700, align: TextAlignSpec.center),
          affixSpec:
              TextSpec(fontSize: unit * 0.9, align: TextAlignSpec.center),
          buttonSpec: TextSpec(
              fontSize: unit * 0.5, weight: 600, align: TextAlignSpec.center),
          box: BoxSpec(padding: unit * 0.6));

    case ElementKind.table:
      return TableElement(base,
          cellSpec: TextSpec(fontSize: unit * 0.55, align: TextAlignSpec.left),
          headerSpec: TextSpec(
              fontSize: unit * 0.55, weight: 700, align: TextAlignSpec.left),
          cellPadding: unit * 0.35,
          rows: const [
            ["Name", "Value", "Change"],
            ["First", "120", "+4%"],
            ["Second", "185", "+11%"],
            ["Third", "143", "-2%"],
          ]);

    case ElementKind.button:
      return ButtonElement(base,
          label: "Next",
          textSpec: TextSpec(fontSize: unit * 0.7, weight: 600),
          box: BoxSpec(
            fill: const Color(0xFF3D7EFF),
            borderRadius: unit * 0.4,
            padding: unit * 0.35,
          ),
          hoverFill: const Color(0xFF5C95FF));

    case ElementKind.background:
      return BackgroundElement(base,
          spec: const ProceduralSpec(
            style: ProceduralStyle.rain,
            seed: 5,
            background: Color(0xFF00120A),
            foreground: Color(0xFF19C46B),
            accent: Color(0xFFD8FFEA),
            density: 0.6,
            scale: 0.045,
            intensity: 0.9,
            variation: 0.5,
            vignette: 0.35,
          ),
          cornerRadius: unit * 0.4);

    case ElementKind.path:
      return PathElement(
        base.copyWith(name: "Path"),
        nodes: PathElement.defaultNodes(frames: document.frames),
        strokeWidth: math.max(2, size.shortestSide * 0.012),
        dash: size.shortestSide * 0.04,
      );

    case ElementKind.player:
      // A team is dropped in at a size that would cover half a pitch, because
      // that is what a formation is laid out against -- one dropped at the
      // size of every other element would put eleven players inside a
      // 200-pixel square, on top of each other.
      var dot = size.height * 0.16;
      return TeamElement(
        base.copyWith(name: "Team"),
        dotWidth: dot,
        dotHeight: dot,
        ringWidth: dot * 0.09,
        labelSpec: TextSpec(
          fontSize: dot * 0.5,
          weight: 700,
          outlineWidth: dot * 0.04,
          outlineColor: const Color(0xCC0A1A0A),
        ),
        nameGap: dot * 0.2,
      ).withFormation(TeamFormation.f442);
  }
}
