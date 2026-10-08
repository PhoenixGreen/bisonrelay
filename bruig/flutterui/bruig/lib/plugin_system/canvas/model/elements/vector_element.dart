import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';

// vector_element.dart is a drawing: an .svg, placed on the canvas and kept a
// drawing all the way to the screen and the export, so it is sharp at any
// size -- and, unlike a picture, edited point by point.
//
// It starts as the file it came from, drawn exactly as the file says. The
// first time it is opened for editing it is taken apart into shapes -- each a
// run of points with handles, a fill and a stroke -- and from then on it is
// those shapes that are drawn and saved, so what is seen is what is edited.
// Anything in the file that is not a shape (a gradient, words, a filter) is
// simplified or left out at that moment, and the reader is told before it is.

/// VectorNode is one point of a shape's outline, and the handles that bend
/// the segments either side of it.
///
/// In the drawing's own units -- its viewBox -- rather than as fractions of
/// the element's box, because that is what the file is written in and the
/// box can be any shape: a drawing stretched to fit is the same drawing.
/// The handles are offsets from the point, so moving a point takes its
/// handles with it. Both nought is a corner with straight segments.
class VectorNode {
  final double x;
  final double y;
  final double inX;
  final double inY;
  final double outX;
  final double outY;

  /// smooth is whether the two handles stay in line with each other: dragged,
  /// one swings the other round with it. Off is a corner, whose handles move
  /// apart.
  final bool smooth;

  const VectorNode(
    this.x,
    this.y, {
    this.inX = 0,
    this.inY = 0,
    this.outX = 0,
    this.outY = 0,
    this.smooth = false,
  });

  Offset get point => Offset(x, y);
  Offset get inHandle => Offset(x + inX, y + inY);
  Offset get outHandle => Offset(x + outX, y + outY);
  bool get hasIn => inX != 0 || inY != 0;
  bool get hasOut => outX != 0 || outY != 0;

  VectorNode copyWith({
    double? x,
    double? y,
    double? inX,
    double? inY,
    double? outX,
    double? outY,
    bool? smooth,
  }) =>
      VectorNode(
        x ?? this.x,
        y ?? this.y,
        inX: inX ?? this.inX,
        inY: inY ?? this.inY,
        outX: outX ?? this.outX,
        outY: outY ?? this.outY,
        smooth: smooth ?? this.smooth,
      );

  /// moved is this node put at [to], its handles going with it.
  VectorNode moved(Offset to) => copyWith(x: to.dx, y: to.dy);

  /// toJson is a short list rather than a map: a drawing can have thousands
  /// of points, and the names of six numbers written out thousands of times
  /// is most of the file. Trailing noughts are left off.
  List<num> toJson() {
    num r(double v) => double.parse(v.toStringAsFixed(3));
    var out = <num>[r(x), r(y), r(inX), r(inY), r(outX), r(outY)];
    if (smooth) return [...out, 1];
    while (out.length > 2 && out.last == 0) {
      out.removeLast();
    }
    return out;
  }

  static VectorNode? fromJson(Object? json) {
    if (json is! List || json.length < 2) return null;
    double at(int i) =>
        i < json.length && json[i] is num ? (json[i] as num).toDouble() : 0;
    return VectorNode(at(0), at(1),
        inX: at(2),
        inY: at(3),
        outX: at(4),
        outY: at(5),
        smooth: json.length > 6 && json[6] == 1);
  }
}

/// VectorPath is one unbroken run of points: a shape's outline, or one of
/// them -- a ring is two runs, the outside and the hole.
class VectorPath {
  final List<VectorNode> nodes;
  final bool closed;

  const VectorPath(this.nodes, {this.closed = false});

  VectorPath copyWith({List<VectorNode>? nodes, bool? closed}) =>
      VectorPath(nodes ?? this.nodes, closed: closed ?? this.closed);

  Map<String, dynamic> toJson() => {
        "n": [for (var n in nodes) n.toJson()],
        if (closed) "c": true,
      };

  static VectorPath? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    var raw = json["n"];
    return VectorPath([
      if (raw is List)
        for (var n in raw)
          if (VectorNode.fromJson(n) case var node?) node,
    ], closed: json["c"] == true);
  }
}

/// VectorShape is one shape of the drawing: its outline -- one or more runs
/// of points -- and how it is painted.
class VectorShape {
  final List<VectorPath> paths;

  /// fill and stroke are its colours, or null for none.
  final Color? fill;
  final Color? stroke;

  /// strokeWidth is in the drawing's own units, so it scales with the
  /// drawing as the file's own lines do.
  final double strokeWidth;
  final StrokeCap cap;
  final StrokeJoin join;

  /// evenOdd is the file's fill-rule: whether a run inside another is a
  /// hole even when it goes the same way round.
  final bool evenOdd;

  const VectorShape({
    required this.paths,
    this.fill,
    this.stroke,
    this.strokeWidth = 1,
    this.cap = StrokeCap.butt,
    this.join = StrokeJoin.miter,
    this.evenOdd = false,
  });

  VectorShape copyWith({
    List<VectorPath>? paths,
    Color? fill,
    Color? stroke,
    bool clearFill = false,
    bool clearStroke = false,
    double? strokeWidth,
    StrokeCap? cap,
    StrokeJoin? join,
    bool? evenOdd,
  }) =>
      VectorShape(
        paths: paths ?? this.paths,
        fill: clearFill ? null : fill ?? this.fill,
        stroke: clearStroke ? null : stroke ?? this.stroke,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        cap: cap ?? this.cap,
        join: join ?? this.join,
        evenOdd: evenOdd ?? this.evenOdd,
      );

  /// path is the outline as one drawable path, in the drawing's units.
  Path get path {
    var out = Path()
      ..fillType = evenOdd ? PathFillType.evenOdd : PathFillType.nonZero;
    for (var run in paths) {
      var nodes = run.nodes;
      if (nodes.isEmpty) continue;
      out.moveTo(nodes.first.x, nodes.first.y);
      void segment(VectorNode a, VectorNode b) {
        if (!a.hasOut && !b.hasIn) {
          out.lineTo(b.x, b.y);
        } else {
          var c1 = a.outHandle, c2 = b.inHandle;
          out.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, b.x, b.y);
        }
      }

      for (var i = 1; i < nodes.length; i++) {
        segment(nodes[i - 1], nodes[i]);
      }
      if (run.closed && nodes.length > 1) {
        segment(nodes.last, nodes.first);
        out.close();
      }
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
        "p": [for (var p in paths) p.toJson()],
        if (fill != null) "f": colorToJson(fill!),
        if (stroke != null) "s": colorToJson(stroke!),
        if (strokeWidth != 1) "w": strokeWidth,
        if (cap != StrokeCap.butt) "cap": cap.name,
        if (join != StrokeJoin.miter) "join": join.name,
        if (evenOdd) "eo": true,
      };

  static VectorShape? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    var raw = json["p"];
    return VectorShape(
      paths: [
        if (raw is List)
          for (var p in raw)
            if (VectorPath.fromJson(p) case var path?) path,
      ],
      fill: json["f"] == null ? null : colorFromJson(json["f"]),
      stroke: json["s"] == null ? null : colorFromJson(json["s"]),
      strokeWidth: jsonDouble(json["w"], 1),
      cap: StrokeCap.values.firstWhere((c) => c.name == json["cap"],
          orElse: () => StrokeCap.butt),
      join: StrokeJoin.values.firstWhere((j) => j.name == json["join"],
          orElse: () => StrokeJoin.miter),
      evenOdd: json["eo"] == true,
    );
  }
}

/// VectorFit is how a drawing sits in its box.
enum VectorFit {
  /// contain is the whole drawing, as large as fits, never squashed.
  contain("Fit"),

  /// cover fills the box, never squashed, cut off where it does not fit --
  /// what a drawing behind a whole page wants.
  cover("Fill"),

  /// stretch fills the box, the drawing taking its shape.
  stretch("Stretch");

  final String label;
  const VectorFit(this.label);

  static VectorFit fromName(String? name) =>
      values.firstWhere((f) => f.name == name, orElse: () => VectorFit.contain);
}

/// defaultHandleColor is the colour the edit handles are drawn in until one
/// is chosen: a blue that reads on light and dark drawings alike.
const Color defaultHandleColor = Color(0xFF2F80ED);

class VectorElement extends CanvasElement {
  /// assetId is the file the drawing came from, in the Vectors store.
  final String assetId;

  /// viewBox is the drawing's own coordinate space -- what its points are
  /// written in, and what is fitted to the element's box. Empty until it is
  /// first taken apart, and read from the file to draw it before that.
  final Rect viewBox;

  /// shapes is the drawing taken apart, or null while it is still drawn as
  /// the file it came from. See the note at the top of the file.
  final List<VectorShape>? shapes;

  final VectorFit fit;

  /// handleColor and handleSize are how the edit points and handles are
  /// drawn while it is being edited: so they can be told from the drawing
  /// whatever colour the drawing is.
  final Color handleColor;
  final double handleSize;

  final ElementAnimation animation;

  const VectorElement(
    super.base, {
    this.assetId = "",
    this.viewBox = Rect.zero,
    this.shapes,
    this.fit = VectorFit.contain,
    this.handleColor = defaultHandleColor,
    this.handleSize = 8,
    this.animation = const ElementAnimation(),
  });

  @override
  ElementKind get kind => ElementKind.vector;

  /// edited is whether the drawing has been taken apart into shapes.
  bool get edited => shapes != null;

  bool get hasDrawing => assetId.isNotEmpty || (shapes?.isNotEmpty ?? false);

  /// placement is where the viewBox lands in [box]: the matrix that takes
  /// the drawing's units to the canvas.
  ///
  /// Returned as a scale for each axis and an offset, which is all a fitted
  /// drawing ever needs.
  ({double sx, double sy, double dx, double dy}) placement(
      Rect box, Rect view) {
    if (view.width <= 0 || view.height <= 0) {
      return (sx: 1, sy: 1, dx: box.left, dy: box.top);
    }
    var sx = box.width / view.width, sy = box.height / view.height;
    if (fit == VectorFit.contain) {
      var s = sx < sy ? sx : sy;
      sx = sy = s;
    } else if (fit == VectorFit.cover) {
      var s = sx > sy ? sx : sy;
      sx = sy = s;
    }
    var dx = box.left + (box.width - view.width * sx) / 2 - view.left * sx;
    var dy = box.top + (box.height - view.height * sy) / 2 - view.top * sy;
    return (sx: sx, sy: sy, dx: dx, dy: dy);
  }

  @override
  VectorElement rebase(ElementBase base) => VectorElement(base,
      assetId: assetId,
      viewBox: viewBox,
      shapes: shapes,
      fit: fit,
      handleColor: handleColor,
      handleSize: handleSize,
      animation: animation);

  VectorElement copyWith({
    String? assetId,
    Rect? viewBox,
    List<VectorShape>? shapes,
    bool clearShapes = false,
    VectorFit? fit,
    Color? handleColor,
    double? handleSize,
    ElementAnimation? animation,
  }) =>
      VectorElement(base,
          assetId: assetId ?? this.assetId,
          viewBox: viewBox ?? this.viewBox,
          shapes: clearShapes ? null : shapes ?? this.shapes,
          fit: fit ?? this.fit,
          handleColor: handleColor ?? this.handleColor,
          handleSize: handleSize ?? this.handleSize,
          animation: animation ?? this.animation);

  /// withShape is this drawing with shape [index] replaced.
  VectorElement withShape(int index, VectorShape shape) {
    var list = [...?shapes];
    if (index < 0 || index >= list.length) return this;
    list[index] = shape;
    return copyWith(shapes: list);
  }

  /// A drawing named by an extensionless id is still in the picture store
  /// -- see CanvasMedia.migrateVectors -- and is a picture's to keep; one
  /// that says it is a drawing is the Vectors store's.
  @override
  Set<String> get assetIds =>
      assetId.isNotEmpty && !assetId.endsWith(".svg") ? {assetId} : const {};

  @override
  Set<String> get mediaIds => assetId.endsWith(".svg") ? {assetId} : const {};

  @override
  Map<String, dynamic> props() => {
        if (assetId.isNotEmpty) "asset": assetId,
        if (viewBox != Rect.zero)
          "vb": [viewBox.left, viewBox.top, viewBox.width, viewBox.height],
        if (shapes != null) "shapes": [for (var s in shapes!) s.toJson()],
        if (fit != VectorFit.contain) "fit": fit.name,
        if (handleColor != defaultHandleColor)
          "handle": colorToJson(handleColor),
        if (handleSize != 8) "handleSize": handleSize,
        if (animation.on || animation.closes) "anim": animation.toJson(),
      };

  factory VectorElement.fromJson(Map<String, dynamic> json, ElementBase b) {
    var vb = json["vb"];
    var raw = json["shapes"];
    return VectorElement(b,
        assetId: json["asset"] is String ? json["asset"] as String : "",
        viewBox: vb is List && vb.length == 4 && vb.every((v) => v is num)
            ? Rect.fromLTWH(
                (vb[0] as num).toDouble(),
                (vb[1] as num).toDouble(),
                (vb[2] as num).toDouble(),
                (vb[3] as num).toDouble())
            : Rect.zero,
        shapes: raw is List
            ? [
                for (var s in raw)
                  if (VectorShape.fromJson(s) case var shape?) shape,
              ]
            : null,
        fit: VectorFit.fromName(json["fit"] as String?),
        handleColor: colorFromJson(json["handle"], defaultHandleColor),
        handleSize: jsonDouble(json["handleSize"], 8),
        animation: jsonSpec(
            json["anim"], ElementAnimation.fromJson, const ElementAnimation()));
  }
}
