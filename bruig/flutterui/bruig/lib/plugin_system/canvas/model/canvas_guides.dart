import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_limits.dart';

// canvas_guides.dart is the scaffolding a canvas is laid out against: a grid,
// the lines the reader puts down themselves, and what an element snaps to.
//
// It is saved in the document, not in preferences, because the grid and
// guides are part of the design; whether they are shown is saved too. The
// rulers are not here: they are the person's, not the canvas's (see
// canvas_rulers.dart). Nothing here is drawn on an export: only the editor's
// stage draws it.

/// GuideAxis is which way a guide runs: a vertical one is fixed at an x.
enum GuideAxis { vertical, horizontal }

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
/// edges or its centre, each switched separately.
class SnapTo {
  /// edges is its sides, and so its corners: a corner lies on two sides,
  /// so on one axis the two offer the same points.
  final bool edges;
  final bool centres;

  /// objects is whether the other elements on the canvas count as lines too:
  /// their sides and their middles. See canvas_snap.dart.
  final bool objects;

  const SnapTo({
    this.edges = true,
    this.centres = true,
    this.objects = true,
  });

  /// _defaults is one as made: what a saved one means by leaving a field
  /// out.
  static const _defaults = SnapTo();

  bool get any => edges || centres;

  SnapTo copyWith({bool? edges, bool? centres, bool? objects}) => SnapTo(
        edges: edges ?? this.edges,
        centres: centres ?? this.centres,
        objects: objects ?? this.objects,
      );

  Map<String, dynamic> toJson() => {
        if (edges != _defaults.edges) "e": edges,
        if (centres != _defaults.centres) "c": centres,
        if (objects != _defaults.objects) "o": objects,
      };

  /// fromJson reads edges from a canvas saved with a switch for corners
  /// ("v") beside the one for sides ("e"), so it snaps as it did: on unless
  /// "e" was written off. A corners switch written on keeps it on, since
  /// corners snapped by the sides; one left out cannot, or the sides
  /// switched off and saved, which writes "e" alone, would read back on.
  factory SnapTo.fromJson(Map<String, dynamic> json) => SnapTo(
        edges:
            jsonBool(json["e"], _defaults.edges) || jsonBool(json["v"], false),
        centres: jsonBool(json["c"], _defaults.centres),
        objects: jsonBool(json["o"], _defaults.objects),
      );
}

/// SnapTarget is a switch for what snaps, as the guides panel and the
/// settings bar's snap menu both offer it, with the one label both show.
enum SnapTarget {
  edges("Edges"),
  centres("Centres"),
  objects("Other elements");

  final String label;
  const SnapTarget(this.label);

  /// of is whether this switch is on in [to].
  bool of(SnapTo to) => switch (this) {
        edges => to.edges,
        centres => to.centres,
        objects => to.objects,
      };

  /// set is [to] with this switch at [on].
  SnapTo set(SnapTo to, bool on) => switch (this) {
        edges => to.copyWith(edges: on),
        centres => to.copyWith(centres: on),
        objects => to.copyWith(objects: on),
      };
}

/// CanvasGuides is the grid, the guides and what snaps to what.
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
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = CanvasGuides();

  /// minGridSize and maxGridSize bound the grid's spacing, in document
  /// units; minSubdivisions and maxSubdivisions how finely it is divided;
  /// minSnapWithin and maxSnapWithin the snap distance, in screen pixels;
  /// minStageStep and maxStageStep a 3D stage's step, in metres; and
  /// minStageTurn and maxStageTurn its turn, in degrees. Held to as a value
  /// is set, as a saved one is read, and by the panel's fields.
  static const double minGridSize = 2, maxGridSize = 1000;
  static const int minSubdivisions = 1, maxSubdivisions = 10;
  static const double minSnapWithin = 1, maxSnapWithin = 40;
  static const double minStageStep = 0.01, maxStageStep = 10;
  static const double minStageTurn = 1, maxStageTurn = 90;

  /// isDefault is whether every setting is at its default: nothing to save.
  /// Asked of what is saved, so a setting is never missed here.
  bool get isDefault => toJson().isEmpty;

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
  }) =>
      CanvasGuides(
        showGrid: showGrid ?? this.showGrid,
        gridSize: (gridSize ?? this.gridSize).clamp(minGridSize, maxGridSize),
        subdivisions: (subdivisions ?? this.subdivisions)
            .clamp(minSubdivisions, maxSubdivisions),
        guides: guides ?? this.guides,
        showGuides: showGuides ?? this.showGuides,
        lockGuides: lockGuides ?? this.lockGuides,
        snap: snap ?? this.snap,
        snapTo: snapTo ?? this.snapTo,
        snapWithin:
            (snapWithin ?? this.snapWithin).clamp(minSnapWithin, maxSnapWithin),
        stageSnap: stageSnap ?? this.stageSnap,
        stageStep:
            (stageStep ?? this.stageStep).clamp(minStageStep, maxStageStep),
        stageTurn:
            (stageTurn ?? this.stageTurn).clamp(minStageTurn, maxStageTurn),
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

  /// toJson writes only what differs from a guides as made, so a canvas
  /// nobody has set up writes nothing (see isDefault).
  Map<String, dynamic> toJson() {
    const d = _defaults;
    return {
      if (showGrid != d.showGrid) "grid": showGrid,
      if (gridSize != d.gridSize) "gridSize": gridSize,
      if (subdivisions != d.subdivisions) "sub": subdivisions,
      if (guides.isNotEmpty) "guides": [for (var g in guides) g.toJson()],
      if (showGuides != d.showGuides) "hideGuides": !showGuides,
      if (lockGuides != d.lockGuides) "lockGuides": lockGuides,
      if (snap != d.snap) "noSnap": !snap,
      if (snapTo.toJson() case var to when to.isNotEmpty) "snapTo": to,
      if (snapWithin != d.snapWithin) "within": snapWithin,
      if (stageSnap != d.stageSnap) "stageSnap": stageSnap,
      if (stageStep != d.stageStep) "stageStep": stageStep,
      if (stageTurn != d.stageTurn) "stageTurn": stageTurn,
    };
  }

  /// fromJson passes over "rulers" and "showRulers" in a canvas that has
  /// them: the rulers are the reader's own (CanvasRulers), not the file's.
  factory CanvasGuides.fromJson(Map<String, dynamic> json) {
    const d = _defaults;
    return CanvasGuides(
      showGrid: jsonBool(json["grid"], d.showGrid),
      gridSize: jsonDouble(json["gridSize"], d.gridSize)
          .clamp(minGridSize, maxGridSize),
      subdivisions: jsonInt(json["sub"], d.subdivisions)
          .clamp(minSubdivisions, maxSubdivisions),
      guides:
          jsonObjects(json["guides"], CanvasGuide.fromJson, most: maxGuides),
      showGuides: !jsonBool(json["hideGuides"], !d.showGuides),
      lockGuides: jsonBool(json["lockGuides"], d.lockGuides),
      snap: !jsonBool(json["noSnap"], !d.snap),
      snapTo: jsonSpec(json["snapTo"], SnapTo.fromJson, d.snapTo),
      snapWithin: jsonDouble(json["within"], d.snapWithin)
          .clamp(minSnapWithin, maxSnapWithin),
      stageSnap: jsonBool(json["stageSnap"], d.stageSnap),
      stageStep: jsonDouble(json["stageStep"], d.stageStep)
          .clamp(minStageStep, maxStageStep),
      stageTurn: jsonDouble(json["stageTurn"], d.stageTurn)
          .clamp(minStageTurn, maxStageTurn),
    );
  }
}
