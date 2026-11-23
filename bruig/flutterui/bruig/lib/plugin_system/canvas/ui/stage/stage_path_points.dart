part of 'canvas_stage.dart';

// A selected path's points and handles: which is under the pointer, and
// one dragged. They are where the path is drawn, through its turn and slant
// (PathElement.gripOnPage), and a drag is turned and slanted back into the
// box, which is what a point keeps (PathElement.fractionAt). The gesture is
// _PathPointDrag (stage_gesture.dart); the marks are paintPathControls
// (stage_paint_elements.dart). Part of CanvasStageState: its fields,
// lifecycle and build are in canvas_stage.dart.

extension StagePathPoints on CanvasStageState {
  PathElement? _selectedPath() {
    var selected = controller.selected;
    return selected is PathElement ? selected : null;
  }

  /// _hitPathControl is the point or handle under [doc], by the point's
  /// place in the path and which of its grips. Handles first, so one on top
  /// of an unbent point can still be pulled out.
  ({int index, PathGrip grip})? _hitPathControl(PathElement path, Offset doc) {
    // In document units, so the grab area is one size on screen at any zoom.
    var reach = handleReach() / _scale;
    bool near(PathNode node, PathGrip grip) =>
        node.hasGrip(grip) &&
        (doc - path.gripOnPage(node, grip)).distance <= reach;
    for (var i = 0; i < path.nodes.length; i++) {
      for (var grip in const [PathGrip.outHandle, PathGrip.inHandle]) {
        if (near(path.nodes[i], grip)) return (index: i, grip: grip);
      }
    }
    for (var i = 0; i < path.nodes.length; i++) {
      if (near(path.nodes[i], PathGrip.point)) {
        return (index: i, grip: PathGrip.point);
      }
    }
    return null;
  }

  /// _applyNodeMove puts [grip] of the selected path's point [index] at
  /// [doc].
  void _applyNodeMove(Offset doc, int index, PathGrip grip) {
    var path = _selectedPath();
    if (path == null || index < 0 || index >= path.nodes.length) {
      return;
    }
    // Turned and slanted back into the box, which is what a node keeps.
    var to = path.fractionAt(doc);
    var node = path.nodes[index];
    var d = to - node.point;

    var next = switch (grip) {
      PathGrip.point => node.copyWith(x: to.dx, y: to.dy),
      // Alt breaks the handle pair, making a corner.
      PathGrip.outHandle when HardwareKeyboard.instance.isAltPressed =>
        node.copyWith(outDx: d.dx, outDy: d.dy),
      PathGrip.inHandle when HardwareKeyboard.instance.isAltPressed =>
        node.copyWith(inDx: d.dx, inDy: d.dy),
      PathGrip.outHandle ||
      PathGrip.inHandle =>
        node.withMirroredHandle(out: grip == PathGrip.outHandle, to: to),
    };

    controller.replaceElement(path.withNode(index, next), transient: true);
  }

  /// _bakePathFollow lays the selected path's follower along it again, once
  /// a drag of its points is done rather than every pixel: a route is
  /// dozens of keyframes.
  void _bakePathFollow() {
    var path = _selectedPath();
    if (path != null) controller.applyPathFollow(path);
  }
}
