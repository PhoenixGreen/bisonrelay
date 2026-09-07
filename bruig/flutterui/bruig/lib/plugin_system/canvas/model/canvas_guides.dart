import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// canvas_guides.dart is the scaffolding a canvas is laid out against: a grid,
// the lines the reader puts down themselves, and what an element snaps to.
//
// All of it belongs to the document rather than to the reader's preferences,
// and that is the one decision here worth defending. A grid of twelve columns
// with guides down the margins *is* the design -- it is the reason everything
// on the canvas lines up, and somebody opening the file on another machine
// needs it as much as the person who drew it. What is a preference is whether
// the scaffolding is *shown*, and that travels with it too, because a canvas
// sent with its guides hidden is a canvas that looks finished.
//
// Nothing here is drawn on an export. See scene_renderer: the grid, the guides
// and the rulers are all editing furniture, and a published picture with a
// grid over it is a mistake nobody would ask for.

/// GuideAxis is which way a guide runs.
///
/// A vertical guide is a vertical line, fixed at an x. The name describes the
/// line rather than the axis it is pinned to, because that is what somebody
/// dragging one out of a ruler sees.
enum GuideAxis {
  vertical("Vertical"),
  horizontal("Horizontal");

  final String label;
  const GuideAxis(this.label);
}

/// CanvasGuide is one line the reader has put down.
class CanvasGuide {
  final GuideAxis axis;

  /// at is where it sits, in document units -- an x for a vertical line, a y
  /// for a horizontal one.
  final double at;

  const CanvasGuide({required this.axis, required this.at});

  CanvasGuide copyWith({GuideAxis? axis, double? at}) =>
      CanvasGuide(axis: axis ?? this.axis, at: at ?? this.at);

  Map<String, dynamic> toJson() => {"axis": axis.name, "at": at};

  factory CanvasGuide.fromJson(Map<String, dynamic> json) => CanvasGuide(
        axis: GuideAxis.values.firstWhere((a) => a.name == json["axis"],
            orElse: () => GuideAxis.vertical),
        at: jsonDouble(json["at"], 0),
      );
}

/// SnapTo is what part of an element is allowed to land on a line.
///
/// Three, because they are three different intentions: lining up a row of
/// boxes by their edges, centring a title over a chart, and putting a corner
/// exactly where two guides cross. Anybody who has used one of these knows
/// which they want and is annoyed by the others.
class SnapTo {
  final bool vertices;
  final bool edges;
  final bool centres;

  const SnapTo({
    this.vertices = true,
    this.edges = true,
    this.centres = true,
  });

  bool get any => vertices || edges || centres;

  SnapTo copyWith({bool? vertices, bool? edges, bool? centres}) => SnapTo(
        vertices: vertices ?? this.vertices,
        edges: edges ?? this.edges,
        centres: centres ?? this.centres,
      );

  Map<String, dynamic> toJson() => {"v": vertices, "e": edges, "c": centres};

  factory SnapTo.fromJson(Map<String, dynamic> json) => SnapTo(
        vertices: jsonBool(json["v"], true),
        edges: jsonBool(json["e"], true),
        centres: jsonBool(json["c"], true),
      );
}

/// CanvasRulers is which edges carry a ruler.
///
/// Four switches rather than one, because a ruler eats a strip of the window
/// and which strip anybody can spare depends on their screen. Top and left is
/// the arrangement almost everything uses, so it is the one that is on.
class CanvasRulers {
  final bool top;
  final bool left;
  final bool right;
  final bool bottom;

  const CanvasRulers({
    this.top = false,
    this.left = false,
    this.right = false,
    this.bottom = false,
  });

  bool get any => top || left || right || bottom;

  CanvasRulers copyWith({bool? top, bool? left, bool? right, bool? bottom}) =>
      CanvasRulers(
        top: top ?? this.top,
        left: left ?? this.left,
        right: right ?? this.right,
        bottom: bottom ?? this.bottom,
      );

  Map<String, dynamic> toJson() => {
        if (top) "t": true,
        if (left) "l": true,
        if (right) "r": true,
        if (bottom) "b": true,
      };

  factory CanvasRulers.fromJson(Map<String, dynamic> json) => CanvasRulers(
        top: jsonBool(json["t"], false),
        left: jsonBool(json["l"], false),
        right: jsonBool(json["r"], false),
        bottom: jsonBool(json["b"], false),
      );
}

/// CanvasGuides is the whole arrangement: the grid, the lines, the rulers and
/// what snaps to what.
class CanvasGuides {
  /// showGrid and gridSize are the regular grid. The size is in document
  /// units, so a grid on a 1280-wide canvas is the same grid at any zoom.
  final bool showGrid;
  final double gridSize;

  /// subdivisions are the faint lines between the strong ones. Four means a
  /// line every quarter of the grid, drawn lighter -- what a ruler does, and
  /// for the same reason: the strong lines are for counting and the faint ones
  /// are for landing on.
  final int subdivisions;

  final List<CanvasGuide> guides;

  /// showGuides hides the lines without forgetting them, which is what
  /// somebody wants when they are checking how the design looks rather than
  /// building it.
  final bool showGuides;

  /// lockGuides stops them being dragged. A guide is a thing you put down once
  /// and then work against, so the commonest thing to do to one by accident is
  /// move it.
  final bool lockGuides;

  final bool snap;
  final SnapTo snapTo;

  /// snapWithin is how near, in *screen* pixels, an element has to be before
  /// it jumps. Screen rather than document units on purpose: what it allows
  /// for is the reader's aim, which does not get better when they zoom in.
  final double snapWithin;

  final CanvasRulers rulers;

  const CanvasGuides({
    this.showGrid = false,
    this.gridSize = 40,
    this.subdivisions = 1,
    this.guides = const [],
    this.showGuides = true,
    this.lockGuides = false,
    this.snap = true,
    this.snapTo = const SnapTo(),
    this.snapWithin = 6,
    this.rulers = const CanvasRulers(),
  });

  /// isDefault is whether any of this is worth writing down. A canvas nobody
  /// has set up keeps its file free of a block that says "no grid, no guides".
  bool get isDefault =>
      !showGrid &&
      gridSize == 40 &&
      subdivisions == 1 &&
      guides.isEmpty &&
      showGuides &&
      !lockGuides &&
      snap &&
      snapTo.vertices &&
      snapTo.edges &&
      snapTo.centres &&
      snapWithin == 6 &&
      !rulers.any;

  CanvasGuides copyWith({
    bool? showGrid,
    double? gridSize,
    int? subdivisions,
    List<CanvasGuide>? guides,
    bool? showGuides,
    bool? lockGuides,
    bool? snap,
    SnapTo? snapTo,
    double? snapWithin,
    CanvasRulers? rulers,
  }) =>
      CanvasGuides(
        showGrid: showGrid ?? this.showGrid,
        gridSize: (gridSize ?? this.gridSize).clamp(2.0, 1000.0),
        subdivisions: (subdivisions ?? this.subdivisions).clamp(1, 10),
        guides: guides ?? this.guides,
        showGuides: showGuides ?? this.showGuides,
        lockGuides: lockGuides ?? this.lockGuides,
        snap: snap ?? this.snap,
        snapTo: snapTo ?? this.snapTo,
        snapWithin: (snapWithin ?? this.snapWithin).clamp(1.0, 40.0),
        rulers: rulers ?? this.rulers,
      );

  /// withGuide adds one, and moved replaces one, because those are the two
  /// things the stage does to this list and doing them by hand at the call
  /// site is how a list ends up sorted in one place and not another.
  CanvasGuides withGuide(CanvasGuide guide) =>
      copyWith(guides: [...guides, guide]);

  CanvasGuides movedGuide(int index, double to) => copyWith(guides: [
        for (var (i, g) in guides.indexed) i == index ? g.copyWith(at: to) : g,
      ]);

  CanvasGuides withoutGuide(int index) => copyWith(guides: [
        for (var (i, g) in guides.indexed)
          if (i != index) g,
      ]);

  Map<String, dynamic> toJson() => {
        if (showGrid) "grid": true,
        "gridSize": gridSize,
        if (subdivisions != 1) "sub": subdivisions,
        if (guides.isNotEmpty) "guides": [for (var g in guides) g.toJson()],
        if (!showGuides) "hideGuides": true,
        if (lockGuides) "lockGuides": true,
        if (!snap) "noSnap": true,
        "snapTo": snapTo.toJson(),
        if (snapWithin != 6) "within": snapWithin,
        if (rulers.any) "rulers": rulers.toJson(),
      };

  factory CanvasGuides.fromJson(Map<String, dynamic> json) => CanvasGuides(
        showGrid: jsonBool(json["grid"], false),
        gridSize: jsonDouble(json["gridSize"], 40).clamp(2.0, 1000.0),
        subdivisions: jsonInt(json["sub"], 1).clamp(1, 10),
        guides: [
          if (json["guides"] case List raw)
            for (var g in raw)
              if (g is Map<String, dynamic>) CanvasGuide.fromJson(g),
        ],
        showGuides: !jsonBool(json["hideGuides"], false),
        lockGuides: jsonBool(json["lockGuides"], false),
        snap: !jsonBool(json["noSnap"], false),
        snapTo: jsonSpec(json["snapTo"], SnapTo.fromJson, const SnapTo()),
        snapWithin: jsonDouble(json["within"], 6).clamp(1.0, 40.0),
        rulers: jsonSpec(
            json["rulers"], CanvasRulers.fromJson, const CanvasRulers()),
      );

  /// linesFor is every line an element could land on, in document units.
  ///
  /// The grid and the guides together, because an element does not care which
  /// it is snapping to -- and the canvas's own edges and middle, which are the
  /// lines people reach for most and which nobody should have to draw first.
  (List<double>, List<double>) linesFor(Size canvas) {
    var vertical = <double>[0, canvas.width / 2, canvas.width];
    var horizontal = <double>[0, canvas.height / 2, canvas.height];

    if (showGrid && gridSize > 0) {
      var step = gridSize / subdivisions;
      for (var x = 0.0; x <= canvas.width; x += step) {
        vertical.add(x);
      }
      for (var y = 0.0; y <= canvas.height; y += step) {
        horizontal.add(y);
      }
    }
    if (showGuides) {
      for (var guide in guides) {
        (guide.axis == GuideAxis.vertical ? vertical : horizontal)
            .add(guide.at);
      }
    }
    return (vertical, horizontal);
  }
}
