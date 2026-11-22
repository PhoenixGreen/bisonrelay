// view_types.dart is the view's kinds and bounds: the zoom's limits, the
// tools a drag on the canvas or the 3D stage takes, and how the frame is
// fitted. Plain values that know nothing of the
// controller, which exports them.

/// minZoom and maxZoom bound the view, as multiples of the fitted size (see
/// [CanvasController.zoom]): 1 is the whole canvas filling the area.
const double minZoom = 0.25;
const double maxZoom = 16;

/// RetouchBrush is what the brush does to a picture's background.
enum RetouchBrush {
  off("Off"),

  /// erase takes the picture away, for a patch the automatic pass missed.
  erase("Rub out"),

  /// cutAround draws a boundary: all outside it goes. See RemovalStroke.fill.
  cutAround("Cut around"),

  /// restore puts it back, for a hand or a shoulder the automatic pass ate.
  restore("Put back"),

  /// markBackground and markSubject leave the picture as it is: they are
  /// hints for RemovalMode.learn (see BackgroundRemoval.hints).
  markBackground("Mark background"),
  markSubject("Mark subject");

  final String label;
  const RetouchBrush(this.label);

  bool get on => this != RetouchBrush.off;

  /// teaches is whether the brush leaves a hint rather than rubbing out.
  bool get teaches =>
      this == RetouchBrush.markBackground || this == RetouchBrush.markSubject;

  /// keeps is whether the mark is about the subject, not the background.
  bool get keeps =>
      this == RetouchBrush.restore || this == RetouchBrush.markSubject;

  /// fills is whether the stroke is a boundary rather than a mark.
  bool get fills => this == RetouchBrush.cutAround;
}

/// CanvasTool is what dragging on the canvas does. An explicit tool rather
/// than a gesture that guesses, so the view can be made to stay still.
enum CanvasTool {
  /// select moves and selects elements. The view does not move in this tool,
  /// by dragging or scrolling, so nothing shifts under a careful adjustment.
  select("Select", "Move and select elements; the view stays put"),

  /// pan moves the view. Dragging slides the canvas about and the wheel zooms.
  pan("Pan", "Drag to move around the canvas, scroll to zoom");

  final String label;
  final String description;
  const CanvasTool(this.label, this.description);
}

/// StageTool is what the gizmo does to an element on a 3D stage: the bar's
/// 3D tools (keys G, R and S), in place of Select and Pan on a stage.
enum StageTool {
  move("Move", "G",
      "arrows along the stage, the square across the floor"),
  rotate("Rotate", "R", "turn it round on the floor"),
  scale("Scale", "S", "drag the box up to grow it, down to shrink it");

  final String label;
  final String key;
  final String description;
  const StageTool(this.label, this.key, this.description);
}

/// StageNav is how much of the 3D view controls float at the stage's
/// right: all of them, the orbit ball alone, or none.
enum StageNav { all, orbit, none }

/// CanvasFit is how large the canvas's frame is drawn. Two modes because a
/// tall document fitted whole is a narrow strip down the middle of the window.
enum CanvasFit {
  /// whole shows all of the canvas at once; nothing scrolls.
  whole("Show the whole canvas"),

  /// width fills the area's width, scrolling if the canvas is taller.
  width("Fit to width");

  final String label;
  const CanvasFit(this.label);
}
