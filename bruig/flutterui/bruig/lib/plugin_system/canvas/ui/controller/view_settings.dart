part of '../canvas_controller.dart';

// How the canvas is looked at and worked on: its framing, the band's switches
// (overspill, helpers, bounds, joins, page lock), the 3D stage's tool and view
// controls, snapping, steering the stage's camera, and the tool in hand. Part
// of CanvasController: its fields and lifecycle are in canvas_controller.dart.

extension CanvasViewSettings on CanvasController {
  /// fit is how large the frame is drawn. See [CanvasFit].
  CanvasFit get fit => _fit;

  set fit(CanvasFit value) {
    if (_fit == value) return;
    _fit = value;
    // A zoom chosen against the old frame means something else in the new.
    _zoom = 1;
    _pan = Offset.zero;
    _notifyView();
  }

  /// rulers is which edges of the stage carry a ruler and whether they show:
  /// the person's own (CanvasPreferences.rulers), not the canvas's, so
  /// another canvas opens with them as they are. Setting them redraws the
  /// stage without changing the canvas: no undo step, nothing to save.
  CanvasRulers get rulers => _rulers;

  set rulers(CanvasRulers value) {
    if (_rulers == value) return;
    _rulers = value;
    _notifyView();
  }

  /// restoreRulers puts back the rulers as the preferences hold them,
  /// without notifying: it runs while the page is being built.
  void restoreRulers(CanvasRulers value) => _rulers = value;

  /// autoKeyframe makes dragging anything on frame N write a keyframe at N
  /// instead of moving it. Off by default, so tidying is not recorded.
  bool get autoKeyframe => _autoKeyframe;

  set autoKeyframe(bool value) {
    if (_autoKeyframe == value) return;
    _autoKeyframe = value;
    notifyListeners();
  }

  /// showOverspill draws a margin of the world outside the canvas, so an
  /// element entering from off the page can be seen and dragged there.
  bool get showOverspill => _showOverspill;

  set showOverspill(bool value) {
    if (_showOverspill == value) return;
    _showOverspill = value;
    notifyListeners();
  }

  /// showHelpers draws the selection box, resize handles and rotation ring.
  /// Off, the handles stop answering too, so nothing unseen can be grabbed.
  bool get showHelpers => _showHelpers;

  set showHelpers(bool value) {
    if (_showHelpers == value) return;
    _showHelpers = value;
    _notifyView();
  }

  /// showAllBounds outlines every element, not only the selected one, for
  /// elements that relate to each other, such as a chain of text boxes.
  bool get showAllBounds => _showAllBounds;

  set showAllBounds(bool value) {
    if (_showAllBounds == value) return;
    _showAllBounds = value;
    _notifyView();
  }

  /// lockJoins stops a drag changing the connectors between text boxes,
  /// whose grips sit on the resize handles' outline; locked, they ignore
  /// the pointer.
  bool get lockJoins => _lockJoins;

  set lockJoins(bool value) {
    if (_lockJoins == value) return;
    _lockJoins = value;
    _notifyView();
  }

  /// hideJoins leaves the lines between linked text boxes undrawn. The grips
  /// stay, still saying there is a chain and whether the words all fit.
  bool get hideJoins => _hideJoins;

  set hideJoins(bool value) {
    if (_hideJoins == value) return;
    _hideJoins = value;
    _notifyView();
  }

  /// pageLocked stops the page scrolling or zooming. On a 3D stage those
  /// gestures steer the stage's camera instead: drag orbits, shift-drag
  /// pans, pinch zooms.
  bool get pageLocked => _pageLocked;

  set pageLocked(bool value) {
    if (_pageLocked == value) return;
    _pageLocked = value;
    _notifyView();
  }

  /// stageTool is what the gizmo does on an element standing on a stage.
  StageTool get stageTool => _stageTool;

  set stageTool(StageTool value) {
    if (_stageTool == value) return;
    _stageTool = value;
    _notifyView();
  }

  /// stageNav is how much of the 3D view controls are shown. See StageNav.
  StageNav get stageNav => _stageNav;

  set stageNav(StageNav value) {
    if (_stageNav == value) return;
    _stageNav = value;
    _notifyView();
  }

  /// canvasSnap is the bar's Snap: the page's snap, or on a 3D stage the
  /// stage's own, which starts off. Not [snapping], which is the timeline's.
  bool get canvasSnap =>
      onStage3d ? _document.guides.stageSnap : _document.guides.snap;

  set canvasSnap(bool value) {
    if (canvasSnap == value) return;
    var g = _document.guides;
    apply(_document.copyWith(
        guides: onStage3d
            ? g.copyWith(stageSnap: value)
            : g.copyWith(snap: value)));
  }

  /// steeredStage is the 3D stage the view controls steer: the selected
  /// element's, else the scene's first (background, then a Background
  /// element). Null where there is none, and the bar shows the page tools.
  StageElement? get steeredStage {
    if (_selection.length == 1) {
      var spot = _document.elementById(_selection.first)?.base.spot;
      if (spot != null) {
        if (stageOf(spot.stage) case var s?) return s;
      }
    }
    for (var (id, _)
        in stagesIn(_document.elements, backdrop: _document.drawnBackground)) {
      if (stageOf(id) case var s?) return s;
    }
    return null;
  }

  bool get onStage3d => steeredStage != null;

  /// steer moves the steered stage's camera to [to] of its setting on this
  /// frame (its key where keyed). Nothing without a stage, or if locked.
  void steer(StageCamera Function(StageCamera) to, {bool transient = false}) {
    var s = steeredStage;
    if (s == null || s.locked) return;
    putStage(stageFilmed(s, to(s.cameraAt(_frame))), transient: transient);
  }

  /// orbitBy swings the steered stage's camera round by [dx], [dy]
  /// degrees: across goes round the stage, down looks from higher.
  void orbitBy(double dx, double dy, {bool transient = false}) =>
      steer(
          (c) => c.copyWith(
              yaw: (c.yaw + dx + 540) % 360 - 180, pitch: c.pitch + dy),
          transient: transient);

  /// panCameraBy slides the steered camera by [by] page units, with the
  /// pointer.
  void panCameraBy(Offset by, {bool transient = false}) {
    var s = steeredStage;
    if (s == null) return;
    var view = stageView(s, _frame);
    steer((c) => view.panned(by), transient: transient);
  }

  /// dollyBy scales the steered camera's distance by [factor]: below 1 nearer.
  void dollyBy(double factor, {bool transient = false}) =>
      steer((c) => c.copyWith(distance: c.distance * factor),
          transient: transient);

  /// frameSelected turns the steered camera to fill the view with the one
  /// selected element, if it stands on a stage.
  void frameSelected() {
    if (_selection.length != 1) return;
    var e = _document.elementById(_selection.first);
    if (e == null) return;
    var at = stagedIn(_document, e, _frame);
    if (at == null) return;
    var spot = at.spot;
    var tall = e is Character3dElement
        ? 1.75
        : spot.height * e.height / math.max(1.0, math.max(e.width, e.height));
    var size = math.max(tall, spot.height);
    var middle = spot.stand == SpotStand.wall
        ? (spot.x, spot.lift + tall / 2, -at.stage.size)
        : (spot.x, spot.lift + tall / 2, spot.z);
    steer((c) => at.view.framing(middle.$1, middle.$2, middle.$3, size));
  }

  /// resetCamera puts the steered camera back to its start, keeping its lens.
  void resetCamera() => steer((c) => StageCamera(lens: c.lens));

  /// tool is what dragging on the canvas does. Select to begin with.
  CanvasTool get tool => _tool;

  set tool(CanvasTool value) {
    if (_tool == value) return;
    _tool = value;
    _notifyView();
  }
}
