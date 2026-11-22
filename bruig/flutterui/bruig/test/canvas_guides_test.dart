import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_snap.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_rulers.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_guides_test.dart is about where a dragged element actually lands.
//
// What makes snapping feel right or wrong is entirely in a handful of rules,
// and they are far easier to be sure of against numbers than against a
// pointer -- which is why the arithmetic is its own file with nothing in it
// that knows about a mouse.

void main() {
  const canvas = Size(1000, 600);

  /// moved is a box of [size] moved to [topLeft] and snapped against
  /// [guides] on the canvas: where its top-left lands, and the lines caught.
  (Offset, SnapLines) moved(CanvasGuides guides, Offset topLeft, Size size,
      {double reach = 8}) {
    var snap = Snapper(guides, canvas).move(topLeft & size, reach: reach);
    return (topLeft + snap.nudge, snap.lines);
  }

  group("snapping a move", () {
    // A grid every 100, and nothing else.
    const grid = CanvasGuides(showGrid: true, gridSize: 100);

    test("a corner lands on the nearest line", () {
      var (at, lines) = moved(grid, const Offset(97, 203), const Size(50, 50));
      expect(at, const Offset(100, 200));
      expect(lines.vertical, 100);
      expect(lines.horizontal, 200);
    });

    test("nothing moves when nothing is near enough", () {
      var (at, lines) = moved(grid, const Offset(140, 260), const Size(50, 50));
      expect(at, const Offset(140, 260));
      expect(lines.caught, isFalse);
    });

    test("the far edge can be what catches", () {
      // The element's right-hand side is on 300; its left is nowhere near a
      // line. Snapping only the top-left corner would miss this.
      var (at, lines) = moved(grid, const Offset(147, 10), const Size(150, 50));
      expect(at.dx, 150, reason: "moved so the right edge is on 300");
      expect(lines.vertical, 300);
    });

    test("the centre can be what catches", () {
      var (at, lines) = moved(grid.copyWith(snapTo: const SnapTo(edges: false)),
          const Offset(72, 10), const Size(50, 50));
      expect(at.dx, 75, reason: "its middle is now on 100");
      expect(lines.vertical, 100);
    });

    test("nearest wins, not first", () {
      // On a fine grid an element is always within reach of several lines.
      // Taking the first would jump it backwards past the one it was nearly
      // touching.
      var fine = grid.copyWith(gridSize: 10);
      var (at, _) =
          moved(fine, const Offset(28, 5), const Size(10, 10), reach: 6);
      expect(at.dx, 30);
    });

    test("the canvas's own edges and middle are always there", () {
      // Nobody should have to draw a guide down the middle of the page.
      const plain = CanvasGuides();
      expect(plain.showGrid, isFalse);
      var (_, lines) = moved(plain, const Offset(497, 3), const Size(20, 20));
      expect(lines.vertical, 500);
      expect(lines.horizontal, 0);
    });

    test("a guide is snapped to like anything else", () {
      var withGuide = const CanvasGuides()
          .withGuide(const CanvasGuide(axis: GuideAxis.vertical, at: 321));
      var (at, _) =
          moved(withGuide, const Offset(318, 400), const Size(20, 20));
      expect(at.dx, 321);
    });

    test("a hidden guide catches nothing", () {
      // What is not shown cannot be aimed at, so it must not act at a
      // distance either.
      var hidden = const CanvasGuides(showGuides: false)
          .withGuide(const CanvasGuide(axis: GuideAxis.vertical, at: 321));
      var (_, lines) =
          moved(hidden, const Offset(318, 400), const Size(20, 20));
      expect(lines.vertical, isNot(321));
    });

    test("snapping off leaves everything exactly where it was put", () {
      var off = grid.copyWith(snap: false);
      var (at, lines) = moved(off, const Offset(97, 203), const Size(50, 50));
      expect(at, const Offset(97, 203));
      expect(lines.caught, isFalse);
    });

    test("so does turning every target off", () {
      var none =
          grid.copyWith(snapTo: const SnapTo(edges: false, centres: false));
      var (_, lines) = moved(none, const Offset(97, 203), const Size(50, 50));
      expect(lines.caught, isFalse);
    });

    test("Edges off, a side lands on nothing", () {
      // The bar's snap menu offers Edges, Centres and Other elements. With
      // Edges and Centres off, nothing on the box is left to snap.
      var noSides =
          grid.copyWith(snapTo: const SnapTo(edges: false, centres: false));
      var (at, lines) =
          moved(noSides, const Offset(97, 203), const Size(50, 50));
      expect(lines.caught, isFalse);
      expect(at, const Offset(97, 203));
    });
  });

  group("snapping a dragged edge or a guide", () {
    const grid = CanvasGuides(showGrid: true, gridSize: 100);

    test("only the sides dragged are snapped", () {
      // The left side at 97 is in reach of 100, but only the right is
      // dragged, and it is nowhere near a line.
      const box = Rect.fromLTRB(97, 140, 240, 260);
      var right = Snapper(grid, canvas).edges(box, right: true, reach: 8);
      expect(right.nudge, Offset.zero);
      expect(right.lines.caught, isFalse);

      var left =
          Snapper(grid, canvas).edges(box, left: true, bottom: true, reach: 8);
      expect(left.nudge, const Offset(3, 0));
      expect(left.lines, const SnapLines(vertical: 100));
    });

    test("a guide lands on the grid, and not on its own last place", () {
      var guides =
          grid.withGuide(const CanvasGuide(axis: GuideAxis.vertical, at: 333));
      var snapper = Snapper(guides, canvas, leaving: 0);
      expect(snapper.line(GuideAxis.vertical, 397, reach: 8), 400);
      expect(snapper.line(GuideAxis.vertical, 335, reach: 8), 335,
          reason: "its own place is left out");
      expect(
          Snapper(guides, canvas).line(GuideAxis.vertical, 335, reach: 8), 333,
          reason: "which another drag would land on");
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

    test("a grid too fine to draw is not snapped to either", () {
      // What a drag lands on is what is drawn: a grid the painter leaves
      // out must not be felt.
      const page = Size(1280, 720);
      const fine = CanvasGuides(showGrid: true, gridSize: 2, subdivisions: 10);
      expect(gridLines(page.width, 2, 10).$1, isEmpty);
      var snap = Snapper(fine, page)
          .move(const Rect.fromLTWH(100.13, 50.05, 20, 20), reach: 0.1);
      expect(snap.lines.caught, isFalse);
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
          snapTo: SnapTo(edges: false, centres: false),
          snapWithin: 12,
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
      expect(back.snapTo.edges, isFalse);
      expect(back.snapTo.centres, isFalse);
      expect(back.snapWithin, 12);
      expect(back.guides.length, 2);
      expect(back.guides.first.axis, GuideAxis.vertical);
      expect(back.guides.first.at, 120);
      expect(back.guides.last.at, 340);
    });

    test("each setting changed alone is saved, and reads back", () {
      // Nothing to save is asked of what is saved, so a setting is never
      // left out of either.
      const d = CanvasGuides();
      expect(d.isDefault, isTrue);
      expect(d.toJson(), isEmpty);
      var alone = <String, CanvasGuides>{
        "showGrid": d.copyWith(showGrid: true),
        "gridSize": d.copyWith(gridSize: 24),
        "subdivisions": d.copyWith(subdivisions: 3),
        "guides":
            d.withGuide(const CanvasGuide(axis: GuideAxis.horizontal, at: 120)),
        "showGuides": d.copyWith(showGuides: false),
        "lockGuides": d.copyWith(lockGuides: true),
        "snap": d.copyWith(snap: false),
        "snapTo.edges": d.copyWith(snapTo: const SnapTo(edges: false)),
        "snapTo.centres": d.copyWith(snapTo: const SnapTo(centres: false)),
        "snapTo.objects": d.copyWith(snapTo: const SnapTo(objects: false)),
        "snapWithin": d.copyWith(snapWithin: 12),
        "stageSnap": d.copyWith(stageSnap: true),
        "stageStep": d.copyWith(stageStep: 0.5),
        "stageTurn": d.copyWith(stageTurn: 45),
      };
      for (var MapEntry(key: field, value: guides) in alone.entries) {
        expect(guides.isDefault, isFalse, reason: field);
        var saved = jsonEncode(guides.toJson());
        var back =
            CanvasGuides.fromJson(jsonDecode(saved) as Map<String, dynamic>);
        expect(back.isDefault, isFalse, reason: field);
        expect(jsonEncode(back.toJson()), saved, reason: field);
      }
    });

    test("every setting changed is written as it always was", () {
      const every = CanvasGuides(
        showGrid: true,
        gridSize: 24,
        subdivisions: 3,
        guides: [CanvasGuide(axis: GuideAxis.vertical, at: 120)],
        showGuides: false,
        lockGuides: true,
        snap: false,
        snapTo: SnapTo(edges: false, centres: false, objects: false),
        snapWithin: 12,
        stageSnap: true,
        stageStep: 0.5,
        stageTurn: 45,
      );
      expect(
          jsonEncode(every.toJson()),
          '{"grid":true,"gridSize":24.0,"sub":3,'
          '"guides":[{"axis":"vertical","at":120.0}],"hideGuides":true,'
          '"lockGuides":true,"noSnap":true,'
          '"snapTo":{"e":false,"c":false,"o":false},'
          '"within":12.0,"stageSnap":true,"stageStep":0.5,"stageTurn":45.0}');
    });

    test("a canvas saved with a corners switch snaps as it did", () {
      // Corners ("v") and sides ("e") were two switches for one thing: the
      // sides are on unless "e" was written off, and stay on when "v" was
      // written on. "e" off alone is what the sides switched off now
      // saves, so it must read back off.
      for (var (v, e, edges) in [
        (null, null, true),
        (true, true, true),
        (false, true, true),
        (true, false, true),
        (false, false, false),
        (false, null, true),
        (true, null, true),
        (null, false, false),
      ]) {
        var read = CanvasGuides.fromJson({
          "snapTo": {if (v != null) "v": v, if (e != null) "e": e},
        });
        expect(read.snapTo.edges, edges, reason: "v: $v, e: $e");
        var saved = jsonEncode(read.toJson());
        expect(saved, isNot(contains('"v"')), reason: "v: $v, e: $e");
        expect(saved.contains('"e":false'), !edges, reason: "v: $v, e: $e");
      }
    });

    test("rulers a canvas was saved with are passed over", () {
      // They are the person's who is editing (CanvasPreferences.rulers), so
      // a canvas sent to somebody does not turn them on for them.
      var read = CanvasGuides.fromJson({
        "rulers": {"t": true, "l": true, "r": true, "b": true},
        "showRulers": false,
      });
      expect(read.isDefault, isTrue);
      expect(read.toJson(), isEmpty);

      var withGrid = CanvasGuides.fromJson({
        "grid": true,
        "rulers": {"t": true},
        "showRulers": true,
      });
      expect(withGrid.showGrid, isTrue, reason: "the rest is read as ever");
      expect(withGrid.toJson().keys, ["grid"]);
    });

    test("the scaffolding travels with the canvas", () {
      // It is the reason everything lines up, so somebody opening the file
      // elsewhere needs it as much as the person who drew it.
      var document = const CanvasDocument()
          .copyWith(guides: const CanvasGuides(showGrid: true, gridSize: 12));
      expect(document.encode(), contains("gridSize"));
    });

    test("a received canvas brings a bounded number of guides", () {
      // Every guide is drawn on each repaint and snapped to on each step of
      // a drag, so a sent file cannot ask for any number of them.
      var json = const CanvasDocument().toJson();
      json["guides"] = {
        "guides": [
          for (var i = 0; i < 400000; i++) {"axis": "vertical", "at": i % 1000},
        ],
      };
      var back = CanvasDocument.fromJson(json).guides;
      expect(back.guides.length, maxGuides);
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
