import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_snap.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_align_test.dart is putting things where you meant them: lining a
// dragged element up with the ones already there, and lining several up with
// each other on purpose.
//
// The two are not the same tool and neither replaces the other. Snapping
// catches one thing as it passes another and is about the drag; aligning
// moves everything chosen at once and exactly, and is about the result.

ShapeElement _at(String id, double x, double y, double w, double h) =>
    ShapeElement(ElementBase(id: id, x: x, y: y, width: w, height: h));

CanvasController _with(List<CanvasElement> elements) => CanvasController(
    CanvasDocument(elements: elements, guides: const CanvasGuides()));

void main() {
  group("snapping to the other elements", () {
    const guides = CanvasGuides(showGrid: false);
    const canvas = Size(1000, 1000);

    test("catches an element on another's left edge", () {
      // The line that matters most of the time, and the one that was missing:
      // a grid catches a design at regular intervals, and no spacing puts
      // this heading over that picture unless both were already on it.
      var landed = snapTopLeft(
        const Offset(203, 400),
        const Size(50, 50),
        guides,
        canvas,
        within: 8,
        others: [const Rect.fromLTWH(200, 100, 80, 80)],
      );
      expect(landed.at.dx, 200);
      expect(landed.onVertical, 200);
    });

    test("and on another's middle", () {
      var landed = snapTopLeft(
        const Offset(400, 236),
        const Size(40, 40),
        guides,
        canvas,
        within: 8,
        others: [const Rect.fromLTWH(0, 200, 100, 120)],
      );
      // Its own top on their middle: 200 + 120/2 = 260, which is out of
      // reach; its own middle on theirs is what catches.
      expect(landed.at.dy + 20, 260);
      expect(landed.onHorizontal, 260);
    });

    test("nothing at all when the switch is off", () {
      var landed = snapTopLeft(
        const Offset(203, 400),
        const Size(50, 50),
        const CanvasGuides(showGrid: false, snapTo: SnapTo(objects: false)),
        canvas,
        within: 8,
        others: [const Rect.fromLTWH(200, 100, 80, 80)],
      );
      expect(landed.at.dx, 203);
      expect(landed.caught, isFalse);
    });

    test("and a resized edge lands on one too", () {
      var line = snapEdgeTo(
        302,
        guides,
        canvas,
        vertical: true,
        within: 8,
        others: [const Rect.fromLTWH(100, 100, 200, 80)],
      );
      expect(line, 300, reason: "their right edge");
    });

    test("the lines an element offers follow the same switches", () {
      // Turn centres off and nothing lines up on a middle, theirs or its own.
      var (xs, ys) = objectLines([const Rect.fromLTWH(10, 20, 100, 40)],
          const CanvasGuides(snapTo: SnapTo(centres: false)));
      expect(xs, [10.0, 110.0]);
      expect(ys, [20.0, 60.0]);

      var (allX, _) = objectLines(
          [const Rect.fromLTWH(10, 20, 100, 40)], const CanvasGuides());
      expect(allX, containsAll([10.0, 110.0, 60.0]));
    });
  });

  group("lining several up", () {
    test("left puts them on the leftmost of themselves", () {
      var controller = _with([
        _at("a", 100, 0, 50, 50),
        _at("b", 40, 100, 50, 50),
        _at("c", 300, 200, 50, 50),
      ]);
      addTearDown(controller.dispose);
      controller.selectMany({"a", "b", "c"});
      controller.alignSelected(CanvasAlign.left);

      for (var element in controller.document.elements) {
        expect(element.bounds.left, 40, reason: element.base.id);
      }
    });

    test("right lines up their right edges, whatever their widths", () {
      var controller = _with([
        _at("a", 0, 0, 50, 50),
        _at("b", 0, 100, 120, 50),
      ]);
      addTearDown(controller.dispose);
      controller.selectMany({"a", "b"});
      controller.alignSelected(CanvasAlign.right);

      for (var element in controller.document.elements) {
        expect(element.bounds.right, 120, reason: element.base.id);
      }
    });

    test("centring is on the middle of the box they make", () {
      var controller = _with([
        _at("a", 0, 0, 100, 20),
        _at("b", 200, 50, 100, 20),
      ]);
      addTearDown(controller.dispose);
      controller.selectMany({"a", "b"});
      controller.alignSelected(CanvasAlign.centreX);

      for (var element in controller.document.elements) {
        expect(element.bounds.center.dx, 150, reason: element.base.id);
      }
    });

    test("one thing chosen is already aligned with itself", () {
      var controller = _with([_at("a", 33, 44, 50, 50)]);
      addTearDown(controller.dispose);
      controller.selectMany({"a"});
      controller.alignSelected(CanvasAlign.left);
      expect(controller.document.elements.single.bounds.left, 33,
          reason: "and must not jump to the canvas edge");
    });

    test("a locked element is left where it is", () {
      var controller = _with([
        _at("a", 100, 0, 50, 50),
        ShapeElement(const ElementBase(
            id: "b", x: 40, y: 100, width: 50, height: 50, locked: true)),
      ]);
      addTearDown(controller.dispose);
      controller.selectMany({"a", "b"});
      controller.alignSelected(CanvasAlign.left);
      expect(controller.document.elementById("b")!.bounds.left, 40);
      expect(controller.document.elementById("a")!.bounds.left, 100,
          reason: "the only movable one is already at its own left");
    });
  });

  group("spreading them out", () {
    test("leaves the two on the ends and evens the gaps between", () {
      var controller = _with([
        _at("a", 0, 0, 100, 10),
        _at("b", 120, 0, 20, 10),
        _at("c", 400, 0, 80, 10),
      ]);
      addTearDown(controller.dispose);
      controller.selectMany({"a", "b", "c"});
      controller.spreadSelected(true);

      var a = controller.document.elementById("a")!.bounds;
      var b = controller.document.elementById("b")!.bounds;
      var c = controller.document.elementById("c")!.bounds;
      expect(a.left, 0, reason: "the ends stay put");
      expect(c.right, 480);
      // Even white between them, not even centres: 480 - 200 of element is
      // 280 of gap over two gaps.
      expect(b.left - a.right, closeTo(c.left - b.right, 0.01));
    });

    test("two is nothing to spread", () {
      var controller = _with([_at("a", 0, 0, 10, 10), _at("b", 50, 0, 10, 10)]);
      addTearDown(controller.dispose);
      controller.selectMany({"a", "b"});
      controller.spreadSelected(true);
      expect(controller.document.elementById("b")!.bounds.left, 50);
    });
  });
}
