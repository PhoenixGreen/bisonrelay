import 'dart:ui';

import 'package:bruig/components/paint_spec.dart';

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

  /// mirrored is, for a smooth point, whether its handles are each other's
  /// mirror: dragged, one gives the other its length as well as its line.
  final bool mirrored;

  /// handles is how the two handles move together -- see VectorHandles.
  VectorHandles get handles => !smooth
      ? VectorHandles.free
      : mirrored
          ? VectorHandles.mirrored
          : VectorHandles.aligned;

  /// width is how thick the shape's line is at this point, as a share of the
  /// shape's own stroke width: 1 is as set, 2 twice as thick. It tapers from
  /// point to point along the line between.
  final double width;

  /// cap and join are this point's own line end -- where a run ends here --
  /// and line corner, or null for the shape's.
  final StrokeCap? cap;
  final StrokeJoin? join;

  const VectorNode(
    this.x,
    this.y, {
    this.inX = 0,
    this.inY = 0,
    this.outX = 0,
    this.outY = 0,
    this.smooth = false,
    this.mirrored = false,
    this.width = 1,
    this.cap,
    this.join,
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
    bool? mirrored,
    double? width,
    StrokeCap? cap,
    StrokeJoin? join,
    bool clearCap = false,
    bool clearJoin = false,
  }) =>
      VectorNode(
        x ?? this.x,
        y ?? this.y,
        inX: inX ?? this.inX,
        inY: inY ?? this.inY,
        outX: outX ?? this.outX,
        outY: outY ?? this.outY,
        smooth: smooth ?? this.smooth,
        mirrored: mirrored ?? this.mirrored,
        width: width ?? this.width,
        cap: clearCap ? null : cap ?? this.cap,
        join: clearJoin ? null : join ?? this.join,
      );

  /// reversed is this node on a run read the other way: its handles swap.
  VectorNode get reversed => VectorNode(x, y,
      inX: outX,
      inY: outY,
      outX: inX,
      outY: inY,
      smooth: smooth,
      mirrored: mirrored,
      width: width,
      cap: cap,
      join: join);

  /// moved is this node put at [to], its handles going with it.
  VectorNode moved(Offset to) => copyWith(x: to.dx, y: to.dy);

  /// toJson is a short list rather than a map: a drawing can have thousands
  /// of points, and the names of six numbers written out thousands of times
  /// is most of the file. Trailing noughts are left off.
  List<num> toJson() {
    num r(double v) => double.parse(v.toStringAsFixed(3));
    var out = <num>[r(x), r(y), r(inX), r(inY), r(outX), r(outY)];
    // A cap and a join are a ninth and tenth -- each its place in the list
    // of them, or -1 for the shape's -- after the width spelt out.
    if (cap != null || join != null) {
      return [
        ...out,
        _smoothFlag,
        r(width),
        cap?.index ?? -1,
        join?.index ?? -1,
      ];
    }
    // A width is an eighth number, after the smooth flag spelt out.
    if (width != 1) return [...out, _smoothFlag, r(width)];
    if (smooth) return [...out, _smoothFlag];
    while (out.length > 2 && out.last == 0) {
      out.removeLast();
    }
    return out;
  }

  /// _smoothFlag is the seventh number: 0 a corner, 1 smooth, 2 smooth and
  /// mirrored.
  int get _smoothFlag => !smooth ? 0 : (mirrored ? 2 : 1);

  static VectorNode? fromJson(Object? json) {
    if (json is! List || json.length < 2) return null;
    double at(int i) =>
        i < json.length && json[i] is num ? (json[i] as num).toDouble() : 0;
    return VectorNode(at(0), at(1),
        inX: at(2),
        inY: at(3),
        outX: at(4),
        outY: at(5),
        smooth: json.length > 6 && (json[6] == 1 || json[6] == 2),
        mirrored: json.length > 6 && json[6] == 2,
        width:
            json.length > 7 && json[7] is num ? (json[7] as num).toDouble() : 1,
        cap: _pick(StrokeCap.values, json.length > 8 ? json[8] : null),
        join: _pick(StrokeJoin.values, json.length > 9 ? json[9] : null));
  }
}

/// _withLegacyStrokes hands the tints and rub-outs a drawing kept for the
/// whole of itself, before they were each shape's own, to the shapes each
/// lay over -- what they showed on when they were saved.
List<VectorShape> _withLegacyStrokes(
    List<VectorShape> shapes, List<VectorTint> tints, List<VectorTint> rubs) {
  if (tints.isEmpty && rubs.isEmpty) return shapes;
  return [
    for (var s in shapes)
      (() {
        var b = s.path.getBounds().inflate(s.strokeWidth / 2);
        bool over(VectorTint t) => t.bounds.overlaps(b);
        return s.copyWith(
          tints: [...s.tints, ...tints.where(over)],
          erasures: [...s.erasures, ...rubs.where(over)],
        );
      })(),
  ];
}

/// _strokes reads a list of tint strokes or rub-outs.
List<VectorTint> _strokes(Object? raw, {bool erase = false}) => [
      if (raw is List)
        for (var t in raw)
          if (VectorTint.fromJson(t) case var tint?) erase ? tint.erased : tint,
    ];

/// _pick is [values] at the place [i] names, or null for -1, or anything
/// that is not a place in it.
T? _pick<T>(List<T> values, Object? i) =>
    i is int && i >= 0 && i < values.length ? values[i] : null;

/// VectorHandles is how a point's two handles move together.
enum VectorHandles {
  /// free: each on its own -- a corner.
  free("Free"),

  /// aligned: in line with each other, each its own length.
  aligned("Aligned"),

  /// mirrored: each the other's mirror, the same length.
  mirrored("Mirrored");

  final String label;
  const VectorHandles(this.label);
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

  /// combine is how this shape is combined into the shape before it -- see
  /// VectorCombine -- or null for a shape of its own. The shape a run of
  /// combining shapes starts from gives the result its fill and stroke; the
  /// others only give it their outlines, and keep their own colours for the
  /// day they are separated again.
  final VectorCombine? combine;

  /// tints and erasures are the tint brush's strokes and the eraser's
  /// rub-outs laid on this shape -- those it was under when they were
  /// painted. Its own, so a shape drawn later over the same place comes out
  /// in its own colours, whole; and a shape that goes takes them with it.
  /// In the drawing's units, where they were painted. See VectorTint.
  final List<VectorTint> tints;
  final List<VectorTint> erasures;

  const VectorShape({
    required this.paths,
    this.fill,
    this.stroke,
    this.strokeWidth = 1,
    this.cap = StrokeCap.butt,
    this.join = StrokeJoin.miter,
    this.evenOdd = false,
    this.combine,
    this.tints = const [],
    this.erasures = const [],
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
    VectorCombine? combine,
    bool clearCombine = false,
    List<VectorTint>? tints,
    List<VectorTint>? erasures,
  }) =>
      VectorShape(
        paths: paths ?? this.paths,
        fill: clearFill ? null : fill ?? this.fill,
        stroke: clearStroke ? null : stroke ?? this.stroke,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        cap: cap ?? this.cap,
        join: join ?? this.join,
        evenOdd: evenOdd ?? this.evenOdd,
        combine: clearCombine ? null : combine ?? this.combine,
        tints: tints ?? this.tints,
        erasures: erasures ?? this.erasures,
      );

  /// tapered is whether its line is thicker or thinner at some points than
  /// its stroke width says -- see VectorNode.width.
  bool get tapered => paths.any((p) => p.nodes.any((n) => n.width != 1));

  /// ownLine is whether its line is drawn point by point: tapered, or with
  /// points that end or turn their own way -- what one stroke of the whole
  /// path, with one end and one corner for all of it, cannot draw.
  bool get ownLine =>
      tapered ||
      paths.any((p) => p.nodes.any((n) => n.cap != null || n.join != null));

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
        if (combine != null) "op": combine!.name,
        if (tints.isNotEmpty) "tints": [for (var t in tints) t.toJson()],
        if (erasures.isNotEmpty) "rub": [for (var t in erasures) t.toJson()],
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
      combine:
          VectorCombine.values.where((c) => c.name == json["op"]).firstOrNull,
      tints: _strokes(json["tints"]),
      erasures: _strokes(json["rub"], erase: true),
    );
  }
}

/// VectorCombine is how a shape is combined with the shapes before it --
/// the Boolean tool's operators. Kept rather than worked out once, so every
/// shape in the result keeps its own points and can still be edited.
enum VectorCombine {
  /// unite joins it on: the outline round both.
  unite("Unite", PathOperation.union),

  /// subtract cuts it out: a hole, or a bite.
  subtract("Subtract", PathOperation.difference),

  /// intersect keeps only where it overlaps.
  intersect("Intersect", PathOperation.intersect),

  /// exclude keeps where one or the other is, but not both.
  exclude("Exclude", PathOperation.xor);

  final String label;
  final PathOperation operation;
  const VectorCombine(this.label, this.operation);
}

/// VectorTint is one stroke of the tint brush: colour painted over the
/// drawing, and seen only where the drawing is -- on its lines, its fills,
/// or both, as the stroke was painted.
///
/// A tint belongs to the drawing rather than to a shape: what is painted is
/// what was seen under the brush, whichever shape that was. In the drawing's
/// own units, so it moves and scales with the drawing.
class VectorTint {
  /// points is the brush's path. One point is a dab.
  final List<Offset> points;

  /// paint is the tint: one colour, or a gradient laid across the stroke as
  /// the colour picker set it.
  final PaintSpec paint;

  /// width is the brush's width, in the drawing's units.
  final double width;

  /// soft is how far the brush's edge fades, from 0 (a hard edge) to 1 (a
  /// fade from the middle out).
  final double soft;

  /// line and fill are where it shows: on the drawing's lines, in its fills.
  final bool line;
  final bool fill;

  /// erase is a stroke that takes tint off rather than putting it on.
  final bool erase;

  const VectorTint({
    required this.points,
    required this.paint,
    this.width = 10,
    this.soft = 0.5,
    this.line = true,
    this.fill = true,
    this.erase = false,
  });

  /// erased is this stroke as a rub-out.
  VectorTint get erased => erase
      ? this
      : VectorTint(
          points: points,
          paint: paint,
          width: width,
          soft: soft,
          line: line,
          fill: fill,
          erase: true);

  /// bounds is the stroke's reach: round its points, out by half its width.
  Rect get bounds {
    var r = Rect.fromPoints(points.first, points.first);
    for (var p in points) {
      r = r.expandToInclude(Rect.fromPoints(p, p));
    }
    return r.inflate(width / 2);
  }

  VectorTint withPoint(Offset p) => VectorTint(
      points: [...points, p],
      paint: paint,
      width: width,
      soft: soft,
      line: line,
      fill: fill,
      erase: erase);

  /// mapped is this stroke with every point put through [f]: what moving or
  /// scaling the drawing's points does to the tint laid on them.
  VectorTint mapped(Offset Function(Offset) f, {double scale = 1}) =>
      VectorTint(
          points: [for (var p in points) f(p)],
          paint: paint,
          width: width * scale,
          soft: soft,
          line: line,
          fill: fill,
          erase: erase);

  Map<String, dynamic> toJson() {
    num r(double v) => double.parse(v.toStringAsFixed(2));
    return {
      "p": [
        for (var p in points) ...[r(p.dx), r(p.dy)]
      ],
      "c": paint.toJson(),
      "w": r(width),
      if (soft != 0.5) "soft": soft,
      if (!line) "line": false,
      if (!fill) "fill": false,
      if (erase) "erase": true,
    };
  }

  static VectorTint? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    var raw = json["p"];
    if (raw is! List || raw.length < 2) return null;
    var points = <Offset>[
      for (var i = 0; i + 1 < raw.length; i += 2)
        if (raw[i] is num && raw[i + 1] is num)
          Offset((raw[i] as num).toDouble(), (raw[i + 1] as num).toDouble()),
    ];
    if (points.isEmpty) return null;
    return VectorTint(
      points: points,
      paint: PaintSpec.fromJson(json["c"], const Color(0xFFE5484D)),
      width: jsonDouble(json["w"], 10),
      soft: jsonDouble(json["soft"], 0.5),
      line: json["line"] != false,
      fill: json["fill"] != false,
      erase: json["erase"] == true,
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
            ? _withLegacyStrokes([
                for (var s in raw)
                  if (VectorShape.fromJson(s) case var shape?) shape,
              ], _strokes(json["tints"]),
                _strokes(json["erasures"], erase: true))
            : null,
        fit: VectorFit.fromName(json["fit"] as String?),
        handleColor: colorFromJson(json["handle"], defaultHandleColor),
        handleSize: jsonDouble(json["handleSize"], 8),
        animation: jsonSpec(
            json["anim"], ElementAnimation.fromJson, const ElementAnimation()));
  }
}
