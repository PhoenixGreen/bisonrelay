import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_snap.dart';
import 'package:bruig/plugin_system/canvas/ui/stage_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_guides_test.dart is about where a dragged element actually lands.
//
// What makes snapping feel right or wrong is entirely in a handful of rules,
// and they are far easier to be sure of against numbers than against a
// pointer -- which is why the arithmetic is its own file with nothing in it
// that knows about a mouse.

void main() {
  const canvas = Size(1000, 600);

  group("snapping a move", () {
    // A grid every 100, and nothing else.
    const grid = CanvasGuides(showGrid: true, gridSize: 100);

    test("a corner lands on the nearest line", () {
      var result = snapTopLeft(
          const Offset(97, 203), const Size(50, 50), grid, canvas,
          within: 8);
      expect(result.at, const Offset(100, 200));
      expect(result.onVertical, 100);
      expect(result.onHorizontal, 200);
    });

    test("nothing moves when nothing is near enough", () {
      var result = snapTopLeft(
          const Offset(140, 260), const Size(50, 50), grid, canvas,
          within: 8);
      expect(result.at, const Offset(140, 260));
      expect(result.caught, isFalse);
    });

    test("the far edge can be what catches", () {
      // The element's right-hand side is on 300; its left is nowhere near a
      // line. Snapping only the top-left corner would miss this.
      var result = snapTopLeft(
          const Offset(147, 10), const Size(150, 50), grid, canvas,
          within: 8);
      expect(result.at.dx, 150, reason: "moved so the right edge is on 300");
      expect(result.onVertical, 300);
    });

    test("the centre can be what catches", () {
      var result = snapTopLeft(
          const Offset(72, 10),
          const Size(50, 50),
          grid.copyWith(snapTo: const SnapTo(vertices: false, edges: false)),
          canvas,
          within: 8);
      expect(result.at.dx, 75, reason: "its middle is now on 100");
      expect(result.onVertical, 100);
    });

    test("nearest wins, not first", () {
      // On a fine grid an element is always within reach of several lines.
      // Taking the first would jump it backwards past the one it was nearly
      // touching.
      var fine = grid.copyWith(gridSize: 10);
      var result = snapTopLeft(
          const Offset(28, 5), const Size(10, 10), fine, canvas,
          within: 6);
      expect(result.at.dx, 30);
    });

    test("the canvas's own edges and middle are always there", () {
      // Nobody should have to draw a guide down the middle of the page.
      const plain = CanvasGuides();
      expect(plain.showGrid, isFalse);
      var result = snapTopLeft(
          const Offset(497, 3), const Size(20, 20), plain, canvas,
          within: 8);
      expect(result.onVertical, 500);
      expect(result.onHorizontal, 0);
    });

    test("a guide is snapped to like anything else", () {
      var withGuide = const CanvasGuides()
          .withGuide(const CanvasGuide(axis: GuideAxis.vertical, at: 321));
      var result = snapTopLeft(
          const Offset(318, 400), const Size(20, 20), withGuide, canvas,
          within: 8);
      expect(result.at.dx, 321);
    });

    test("a hidden guide catches nothing", () {
      // What is not shown cannot be aimed at, so it must not act at a
      // distance either.
      var hidden = const CanvasGuides(showGuides: false)
          .withGuide(const CanvasGuide(axis: GuideAxis.vertical, at: 321));
      expect(
          snapTopLeft(
                  const Offset(318, 400), const Size(20, 20), hidden, canvas,
                  within: 8)
              .onVertical,
          isNot(321));
    });

    test("snapping off leaves everything exactly where it was put", () {
      var off = grid.copyWith(snap: false);
      var result = snapTopLeft(
          const Offset(97, 203), const Size(50, 50), off, canvas,
          within: 8);
      expect(result.at, const Offset(97, 203));
      expect(result.caught, isFalse);
    });

    test("so does turning every target off", () {
      var none = grid.copyWith(
          snapTo: const SnapTo(vertices: false, edges: false, centres: false));
      expect(
          snapTopLeft(const Offset(97, 203), const Size(50, 50), none, canvas,
                  within: 8)
              .caught,
          isFalse);
    });
  });

  group("the grid it draws", () {
    test("the strong lines and the faint ones are told apart", () {
      var (majors, minors) = gridLines(400, 100, 4);
      expect(majors, [0, 100, 200, 300, 400]);
      expect(minors, contains(25));
      expect(minors, isNot(contains(100)),
          reason: "a line is one or the other, never both");
    });

    test("undivided, there are no faint ones", () {
      var (majors, minors) = gridLines(300, 100, 1);
      expect(majors, [0, 100, 200, 300]);
      expect(minors, isEmpty);
    });

    test("a grid too fine to draw is not drawn", () {
      // One unit on a four-thousand-pixel canvas is four thousand lines, and
      // the frame that tried would be the last one for a while.
      var (majors, minors) = gridLines(4000, 0.5, 1);
      expect(majors, isEmpty);
      expect(minors, isEmpty);
    });
  });

  group("what is saved", () {
    test("a canvas nobody has set up writes nothing down", () {
      var encoded = const CanvasDocument().encode();
      expect(encoded, isNot(contains("guides")));
    });

    test("the whole arrangement survives a round trip", () {
      var document = const CanvasDocument().copyWith(
        guides: const CanvasGuides(
          showGrid: true,
          gridSize: 24,
          subdivisions: 3,
          showGuides: false,
          lockGuides: true,
          snap: false,
          snapTo: SnapTo(vertices: false, edges: true, centres: false),
          snapWithin: 12,
          rulers: CanvasRulers(top: true, left: true),
          guides: [
            CanvasGuide(axis: GuideAxis.vertical, at: 120),
            CanvasGuide(axis: GuideAxis.horizontal, at: 340),
          ],
        ),
      );

      var back = CanvasDocument.decode(document.encode())!.guides;
      expect(back.showGrid, isTrue);
      expect(back.gridSize, 24);
      expect(back.subdivisions, 3);
      expect(back.showGuides, isFalse);
      expect(back.lockGuides, isTrue);
      expect(back.snap, isFalse);
      expect(back.snapTo.vertices, isFalse);
      expect(back.snapTo.edges, isTrue);
      expect(back.snapWithin, 12);
      expect(back.rulers.top, isTrue);
      expect(back.rulers.bottom, isFalse);
      expect(back.guides.length, 2);
      expect(back.guides.first.axis, GuideAxis.vertical);
      expect(back.guides.first.at, 120);
      expect(back.guides.last.at, 340);
    });

    test("the scaffolding travels with the canvas", () {
      // It is the reason everything lines up, so somebody opening the file
      // elsewhere needs it as much as the person who drew it.
      var document = const CanvasDocument()
          .copyWith(guides: const CanvasGuides(showGrid: true, gridSize: 12));
      expect(document.encode(), contains("gridSize"));
    });
  });

  group("adding and moving guides", () {
    test("one goes down, moves, and comes back up", () {
      var guides = const CanvasGuides()
          .withGuide(const CanvasGuide(axis: GuideAxis.vertical, at: 100))
          .withGuide(const CanvasGuide(axis: GuideAxis.horizontal, at: 200));
      expect(guides.guides.length, 2);

      guides = guides.movedGuide(0, 150);
      expect(guides.guides.first.at, 150);
      expect(guides.guides.last.at, 200, reason: "the other one stayed");

      guides = guides.withoutGuide(0);
      expect(guides.guides.single.axis, GuideAxis.horizontal);
    });
  });

  group("ruler ticks", () {
    // A ruler is only worth drawing if a position can be read off it, and
    // that means the numbers on it have to be round.

    test("every number on the ruler has a grid line under it", () {
      // The two are one measurement of the page shown twice. A ruler that
      // picked its own round numbers put its figures between the lines, and
      // reading a position off it meant counting squares to find it.
      for (var every in [25.0, 40.0, 100.0, 120.0, 250.0]) {
        for (var scale in [0.05, 0.31, 0.5, 1.0, 1.7, 4.0, 13.0]) {
          var step = rulerStep(scale, every);
          expect(step / every, closeTo((step / every).round(), 0.0001),
              reason: "$step is not a whole number of ${every}s");
        }
      }
    });

    test("and it is a countable number of them", () {
      // One, two, five or ten squares to a number. Seven squares to a number
      // is a ruler nobody can read a position off.
      for (var scale in [0.05, 0.31, 0.5, 1.0, 1.7, 4.0, 13.0]) {
        var multiple = rulerStep(scale, 40) / 40;
        var digits =
            multiple / math.pow(10, (math.log(multiple) / math.ln10).floor());
        expect([1.0, 2.0, 5.0, 10.0], contains(closeTo(digits, 0.0001)),
            reason: "$multiple squares to a number, at scale $scale");
      }
    });

    test("zooming out numbers every few lines rather than every line", () {
      // The step is in canvas units, so it has to grow as the view shrinks,
      // or a grid of 40 on a canvas at a tenth would want a number every four
      // pixels. It cannot fall below the grid, though: the finest a ruler is
      // numbered is once per square.
      for (var scale in [0.1, 0.25, 1.0, 3.0]) {
        var gap = rulerStep(scale, 40) * scale;
        expect(gap, greaterThanOrEqualTo(math.min(40 * scale, 40.0)));
        expect(gap, lessThan(200));
      }
      // Zoomed right in, one square is already further apart than the numbers
      // want to be, and there is nothing finer to fall back to.
      expect(rulerStep(8, 40), 40);
    });

    test("a nonsense scale still gives a usable step", () {
      // Fit runs before the first layout, so a zero or a NaN reaches here.
      for (var scale in [0.0, -1.0, double.nan, double.infinity]) {
        expect(rulerStep(scale, 40), greaterThan(0));
        expect(rulerStep(1, scale), greaterThan(0));
      }
    });
  });
}
