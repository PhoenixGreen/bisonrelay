import 'package:flutter/material.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// canvas_guides.dart is the scaffolding a canvas is laid out against: a grid,
// the lines the reader puts down themselves, and what an element snaps to.
//
// It is saved in the document, not in preferences, because the grid and
// guides are part of the design; whether they are shown is saved too.
// Nothing here is drawn on an export (see scene_renderer.dart).

/// GuideAxis is which way a guide runs: a vertical guide is a vertical line,
/// fixed at an x.
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

/// SnapTo is what part of an element is allowed to land on a line: its
/// corners, its edges or its centre, each switched separately.
class SnapTo {
  final bool vertices;
  final bool edges;
  final bool centres;

  /// objects is whether the other elements on the canvas count as lines too:
  /// their sides and their middles. See canvas_snap.dart.
  final bool objects;

  const SnapTo({
    this.vertices = true,
    this.edges = true,
    this.centres = true,
    this.objects = true,
  });

  bool get any => vertices || edges || centres;

  SnapTo copyWith(
          {bool? vertices, bool? edges, bool? centres, bool? objects}) =>
      SnapTo(
        vertices: vertices ?? this.vertices,
        edges: edges ?? this.edges,
        centres: centres ?? this.centres,
        objects: objects ?? this.objects,
      );

  Map<String, dynamic> toJson() =>
      {"v": vertices, "e": edges, "c": centres, if (!objects) "o": false};

  factory SnapTo.fromJson(Map<String, dynamic> json) => SnapTo(
        vertices: jsonBool(json["v"], true),
        edges: jsonBool(json["e"], true),
        centres: jsonBool(json["c"], true),
        objects: jsonBool(json["o"], true),
      );
}

/// CanvasAlign is one of the six ways a set of elements can be lined up.
/// "left" means all their left edges together, not "move them left".
enum CanvasAlign {
  left("Align left", Icons.align_horizontal_left),
  centreX("Centre across", Icons.align_horizontal_center),
  right("Align right", Icons.align_horizontal_right),
  top("Align top", Icons.align_vertical_top),
  middleY("Centre down", Icons.align_vertical_center),
  bottom("Align bottom", Icons.align_vertical_bottom);

  final String label;
  final IconData icon;
  const CanvasAlign(this.label, this.icon);

  /// across is whether this one moves things sideways.
  bool get across => this == left || this == centreX || this == right;
}

/// CanvasRulers is which edges of the window carry a ruler. All are off by
/// default.
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

  /// subdivisions are the faint lines between the strong ones: four means a
  /// lighter line every quarter of the grid. Snapping lands on them too.
  final int subdivisions;

  final List<CanvasGuide> guides;

  /// showGuides hides the lines without forgetting them. Hidden guides are
  /// not snapped to.
  final bool showGuides;

  /// lockGuides stops them being dragged.
  final bool lockGuides;

  final bool snap;
  final SnapTo snapTo;

  /// snapWithin is how near, in *screen* pixels, an element has to be before
  /// it jumps, since the reader's aim does not improve with zoom.
  final double snapWithin;

  /// stageSnap is snapping on a 3D stage, a separate switch that starts off:
  /// on a stage snapping puts everything moved on a step, rather than
  /// catching a line as it passes.
  final bool stageSnap;

  /// stageStep and stageTurn are the steps a thing moved on a 3D stage snaps
  /// to: metres across its floor, and degrees round.
  final double stageStep;
  final double stageTurn;

  final CanvasRulers rulers;

  /// showRulers hides the rulers without forgetting which edges they were
  /// on.
  final bool showRulers;

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
    this.stageSnap = false,
    this.stageStep = 0.25,
    this.stageTurn = 15,
    this.rulers = const CanvasRulers(),
    this.showRulers = true,
  });

  /// isDefault is whether every setting is at its default, so nothing need
  /// be saved.
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
      snapTo.objects &&
      snapWithin == 6 &&
      !stageSnap &&
      stageStep == 0.25 &&
      stageTurn == 15 &&
      showRulers &&
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
    bool? stageSnap,
    double? stageStep,
    double? stageTurn,
    CanvasRulers? rulers,
    bool? showRulers,
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
        stageSnap: stageSnap ?? this.stageSnap,
        stageStep: (stageStep ?? this.stageStep).clamp(0.01, 10.0),
        stageTurn: (stageTurn ?? this.stageTurn).clamp(1.0, 90.0),
        rulers: rulers ?? this.rulers,
        showRulers: showRulers ?? this.showRulers,
      );

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
        if (stageSnap) "stageSnap": true,
        if (stageStep != 0.25) "stageStep": stageStep,
        if (stageTurn != 15) "stageTurn": stageTurn,
        if (rulers.any) "rulers": rulers.toJson(),
        if (!showRulers) "showRulers": false,
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
        stageSnap: jsonBool(json["stageSnap"], false),
        stageStep: jsonDouble(json["stageStep"], 0.25).clamp(0.01, 10.0),
        stageTurn: jsonDouble(json["stageTurn"], 15).clamp(1.0, 90.0),
        rulers: jsonSpec(
            json["rulers"], CanvasRulers.fromJson, const CanvasRulers()),
        showRulers: jsonBool(json["showRulers"], true),
      );

  /// linesFor is every line an element could land on, in document units: the
  /// canvas's edges and middle, the grid, and the shown guides, as vertical
  /// and horizontal lists.
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
