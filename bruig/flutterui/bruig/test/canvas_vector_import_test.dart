import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/svg_import.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_vector_import_test.dart is an .svg taken apart into the shapes a
// Vector element edits, and the element itself saved and read back.

SvgImport read(String body, {String attrs = 'viewBox="0 0 100 100"'}) =>
    importSvg('<svg xmlns="http://www.w3.org/2000/svg" $attrs>$body</svg>')!;

void main() {
  group("paths", () {
    test("lines, closed", () {
      var s = read('<path d="M10 10 L90 10 L50 80 Z"/>');
      expect(s.shapes, hasLength(1));
      var run = s.shapes.single.paths.single;
      expect(run.closed, isTrue);
      expect([
        for (var n in run.nodes) n.point
      ], const [
        Offset(10, 10),
        Offset(90, 10),
        Offset(50, 80),
      ]);
      expect(s.shapes.single.fill, const Color(0xFF000000),
          reason: "black when nothing says otherwise, as SVG has it");
      expect(s.shapes.single.stroke, isNull);
    });

    test("relative, horizontal and vertical, and run together", () {
      var s = read('<path d="m10,10h20v20h-20z"/>');
      expect([
        for (var n in s.shapes.single.paths.single.nodes) n.point
      ], const [
        Offset(10, 10),
        Offset(30, 10),
        Offset(30, 30),
        Offset(10, 30)
      ]);
      var tight = read('<path d="M1-1L2.5.5-3e1,4"/>');
      expect([for (var n in tight.shapes.single.paths.single.nodes) n.point],
          const [Offset(1, -1), Offset(2.5, 0.5), Offset(-30, 4)]);
    });

    test("curves keep their handles, and a smooth join is smooth", () {
      var s = read('<path d="M0 50 C0 0 50 0 50 50 S100 100 100 50"/>');
      var nodes = s.shapes.single.paths.single.nodes;
      expect(nodes, hasLength(3));
      expect(nodes[0].outHandle, const Offset(0, 0));
      expect(nodes[1].inHandle, const Offset(50, 0));
      expect(nodes[1].outHandle, const Offset(50, 100),
          reason: "S reflects the last handle");
      expect(nodes[1].smooth, isTrue);
      expect(nodes[0].smooth, isFalse, reason: "an end has one handle");
    });

    test("quadratics become cubics through the same points", () {
      var s = read('<path d="M0 0 Q50 100 100 0"/>');
      var path = s.shapes.single.path;
      var mid = path.computeMetrics().single;
      var half = mid.getTangentForOffset(mid.length / 2)!.position;
      expect(half.dx, closeTo(50, 0.5));
      expect(half.dy, closeTo(50, 0.5), reason: "a quadratic peaks at half");
    });

    test("arcs are drawn as curves, ending where they should", () {
      var s = read('<path d="M10 50 A40 40 0 0 1 90 50"/>');
      var nodes = s.shapes.single.paths.single.nodes;
      expect(nodes.last.point.dx, closeTo(90, 1e-6));
      expect(nodes.last.point.dy, closeTo(50, 1e-6));
      var b = s.shapes.single.path.getBounds();
      expect(b.top, closeTo(10, 0.3), reason: "a half circle over the top");
    });
  });

  group("basic shapes", () {
    test("a rectangle, square and rounded", () {
      expect(
          read('<rect x="10" y="10" width="50" height="20"/>')
              .shapes
              .single
              .paths
              .single
              .nodes,
          hasLength(4));
      var round = read('<rect x="0" y="0" width="100" height="50" rx="10"/>');
      expect(round.shapes.single.paths.single.nodes, hasLength(8));
      var b = round.shapes.single.path.getBounds();
      expect(b.left, closeTo(0, 1e-6));
      expect(b.width, closeTo(100, 1e-6));
      expect(b.height, closeTo(50, 1e-6));
    });

    test("circles, ellipses, lines and polygons", () {
      var c = read('<circle cx="50" cy="50" r="40"/>').shapes.single;
      expect(c.paths.single.nodes, hasLength(4));
      var b = c.path.getBounds();
      expect(b.left, closeTo(10, 0.01));
      expect(b.bottom, closeTo(90, 0.01));
      expect(
          read('<ellipse cx="50" cy="50" rx="40" ry="20"/>')
              .shapes
              .single
              .path
              .getBounds()
              .height,
          closeTo(40, 0.01));
      var line = read('<line x1="0" y1="0" x2="10" y2="10" stroke="red"/>');
      expect(line.shapes.single.paths.single.closed, isFalse);
      expect(
          read('<polygon points="0,0 10,0 5,10"/>')
              .shapes
              .single
              .paths
              .single
              .closed,
          isTrue);
    });
  });

  group("style and placement", () {
    test("inherited from groups, from classes, and its own wins", () {
      var s = read('''
        <style>.blue { fill: #00f } .wide { stroke-width: 6 }</style>
        <g fill="red" stroke="#000">
          <rect width="10" height="10"/>
          <rect class="blue wide" width="10" height="10"/>
          <rect class="blue" style="fill: lime" width="10" height="10"/>
        </g>''');
      expect([
        for (var x in s.shapes) x.fill
      ], const [
        Color(0xFFFF0000),
        Color(0xFF0000FF),
        Color(0xFF00FF00),
      ]);
      expect(s.shapes[1].strokeWidth, 6);
      expect(s.shapes[0].stroke, const Color(0xFF000000));
    });

    test("transforms move the points and widen the strokes", () {
      var s = read('<g transform="translate(10 20) scale(2)">'
          '<rect width="10" height="5" stroke="black" stroke-width="1"/></g>');
      var b = s.shapes.single.path.getBounds();
      expect(b, const Rect.fromLTWH(10, 20, 20, 10));
      expect(s.shapes.single.strokeWidth, 2);
    });

    test("nothing to paint is nothing; hidden is left out", () {
      var s = read('<rect width="5" height="5" fill="none"/>'
          '<rect width="5" height="5" style="display:none"/>');
      expect(s.shapes, isEmpty);
    });

    test("what cannot be kept is said, and a gradient is made solid", () {
      var s = read('''
        <defs><linearGradient id="g"><stop offset="0" stop-color="#f00"/>
          <stop offset="1" stop-color="#00f"/></linearGradient></defs>
        <rect width="10" height="10" fill="url(#g)"/>
        <text x="0" y="0">Hello</text>''');
      expect(s.shapes.single.fill, const Color(0xFFFF0000));
      expect(s.dropped, containsAll(["gradients (made solid)", "text"]));
    });

    test("the viewBox, or the size where there is none", () {
      expect(
          read('<rect width="1" height="1"/>', attrs: 'viewBox="5 5 40 20"')
              .viewBox,
          const Rect.fromLTWH(5, 5, 40, 20));
      expect(
          read('<rect width="1" height="1"/>', attrs: 'width="64" height="32"')
              .viewBox,
          const Rect.fromLTWH(0, 0, 64, 32));
    });

    test("colours as SVG writes them", () {
      expect(parseSvgColor("#abc"), const Color(0xFFAABBCC));
      expect(parseSvgColor("#11223380"), const Color(0x80112233));
      expect(parseSvgColor("rgb(255, 0, 0)"), const Color(0xFFFF0000));
      expect(parseSvgColor("rgba(0,0,255,0.5)")!.a, closeTo(0.5, 0.01));
      expect(parseSvgColor("rebeccapurple-nonsense"), isNull);
      expect(parseSvgColor("navy"), const Color(0xFF000080));
    });
  });

  group("the element", () {
    test("reads back everything it wrote", () {
      var shapes = read('<path d="M0 0 C10 0 20 10 20 20 Z" stroke="red" '
              'stroke-width="3" stroke-linecap="round"/>')
          .shapes;
      var e = VectorElement(const ElementBase(id: "v", width: 50, height: 50),
          assetId: "0123456789abcdef.svg",
          viewBox: const Rect.fromLTWH(0, 0, 100, 100),
          shapes: shapes,
          fit: VectorFit.stretch,
          handleColor: const Color(0xFFFF00FF),
          handleSize: 12);
      var back = elementFromJson(e.toJson()) as VectorElement;
      expect(back.assetId, e.assetId);
      expect(back.viewBox, e.viewBox);
      expect(back.fit, VectorFit.stretch);
      expect(back.handleColor, const Color(0xFFFF00FF));
      expect(back.handleSize, 12);
      var shape = back.shapes!.single;
      expect(shape.stroke, const Color(0xFFFF0000));
      expect(shape.strokeWidth, 3);
      expect(shape.cap, StrokeCap.round);
      expect(shape.paths.single.closed, isTrue);
      expect(shape.paths.single.nodes[0].outHandle, const Offset(10, 0));
      expect(back.mediaIds, {"0123456789abcdef.svg"},
          reason: "a drawing is the Vectors store's");
    });

    test("not yet edited, it has no shapes", () {
      var e = elementFromJson(const VectorElement(ElementBase(id: "v"),
              assetId: "0123456789abcdef.svg")
          .toJson()) as VectorElement;
      expect(e.edited, isFalse);
    });

    test("a picture that was a drawing opens as a Vector element", () {
      var e = elementFromJson({
        "kind": "image",
        "id": "p",
        "x": 1,
        "y": 2,
        "w": 30,
        "h": 40,
        "asset": "0123456789abcdef.svg",
        "fit": "stretch",
      });
      expect(e, isA<VectorElement>());
      var v = e as VectorElement;
      expect(v.assetId, "0123456789abcdef.svg");
      expect(v.fit, VectorFit.stretch);
      expect(v.id, "p");
      var picture = elementFromJson(
          {"kind": "image", "id": "q", "asset": "0123456789abcdef.png"});
      expect(picture, isNot(isA<VectorElement>()),
          reason: "a photograph stays a picture");
    });

    test("fitted into its box, kept in proportion or stretched", () {
      var e = VectorElement(const ElementBase(id: "v"),
          viewBox: const Rect.fromLTWH(0, 0, 100, 50));
      var p = e.placement(const Rect.fromLTWH(0, 0, 100, 100), e.viewBox);
      expect([p.sx, p.sy, p.dy], [1, 1, 25], reason: "centred, not squashed");
      var s = e.copyWith(fit: VectorFit.stretch);
      var q = s.placement(const Rect.fromLTWH(0, 0, 100, 100), e.viewBox);
      expect([q.sx, q.sy], [1, 2]);
    });
  });

  test("a document keeps a drawing's file alive", () {
    var doc = const CanvasDocument().addElement(const VectorElement(
        ElementBase(id: "v"),
        assetId: "0123456789abcdef.svg"));
    expect(doc.mediaIds, contains("0123456789abcdef.svg"));
  });
}
