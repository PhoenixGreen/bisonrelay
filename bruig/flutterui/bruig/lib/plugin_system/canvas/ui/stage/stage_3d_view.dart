part of 'canvas_stage.dart';

// The 3D stage's gizmo, and steering the view: scrolling, pinching and zooming.
// The gestures that take a camera or the gizmo are here too: a 3D stage's
// camera orbited or panned, parallax scenery panned, a part of the gizmo
// dragged. Part of CanvasStageState: its fields, lifecycle and build are in
// canvas_stage.dart.

extension Stage3dView on CanvasStageState {
  /// _gizmoReach is how near a part, in page units, the pointer must be.
  double get _gizmoReach => 9 / _scaleOrOne;

  /// _gizmo is the gizmo on the lone selected staged element, or null.
  StageGizmo? _gizmo() {
    if (!controller.showHelpers || controller.canvasLive) {
      return null;
    }
    if (controller.selection.length != 1) return null;
    var e = document.elementById(controller.selection.first);
    if (e == null || e.locked || e.base.spot == null) return null;
    var at = stagedIn(document, e, controller.frame);
    if (at == null) return null;
    return StageGizmo.of(e, at, controller.stageTool, _scale);
  }

  /// _pressGizmo takes a press of the primary button on a part of the
  /// gizmo, to drag it. Another button goes on to what it does elsewhere:
  /// the middle one pans the view, or with the page locked the camera.
  bool _pressGizmo(PointerDownEvent event, Offset doc) {
    if (event.buttons != kPrimaryButton) return false;
    var g = _gizmo();
    if (g == null) return false;
    var part = g.hit(doc, _gizmoReach);
    if (part == null) return false;
    _gesture = _GizmoDrag(
        gizmo: g, part: part, from: doc, elementId: controller.selection.first);
    controller.beginInteraction();
    setState(() => _gizmoHot = part);
    return true;
  }

  /// _gizmoLetGo lights, once a part held is let go with the pointer at
  /// [at], what of the gizmo a mouse is over, as its hover would. A touch
  /// or a pen lifts away and has no hover to put it out, so nothing is lit.
  void _gizmoLetGo(Offset? at) {
    GizmoPart? hot;
    if (at != null && _pointer?.kind == PointerDeviceKind.mouse) {
      hot = _gizmo()?.hit(_toDocument(at), _gizmoReach);
    }
    setState(() => _gizmoHot = hot);
  }

  /// _pressLockedStage takes the stage's camera, with the page locked, for a
  /// press on the stage itself (not on anything standing on it) or the
  /// middle button anywhere: a drag orbits; shifted, or middle, it pans.
  bool _pressLockedStage(PointerDownEvent event, Offset doc) {
    if (!controller.pageLocked) return false;
    var s = controller.steeredStage;
    if (s == null || s.locked) return false;
    var middle = event.buttons == kMiddleMouseButton;
    if (!middle) {
      var hit = _hitElement(doc);
      var onStage = hit == null ||
          hit is StageElement ||
          (hit is BackgroundElement && hit.isStage);
      if (!onStage) return false;
    }
    var from = s.cameraAt(controller.frame);
    // Only the primary button's still press is a click on nothing.
    var primary = event.buttons == kPrimaryButton;
    _gesture = middle || HardwareKeyboard.instance.isShiftPressed
        ? _StagePan(s.id, from, event.localPosition, clickClears: primary)
        : _StageOrbit(s.id, from, event.localPosition, clickClears: primary);
    controller.beginInteraction();
    return true;
  }

  void _steering() {
    if (_steerTimer == null) controller.beginInteraction();
    _steerTimer?.cancel();
    _steerTimer = Timer(const Duration(milliseconds: 350), () {
      _steerTimer = null;
      controller.endInteraction();
    });
  }

  /// _steerByScroll is the wheel or two fingers with the page locked on a
  /// stage: orbit, Shift to pan, Command or Control (a pinch, to the wheel)
  /// to zoom.
  void _steerByScroll(PointerScrollEvent event) {
    if (!controller.onStage3d) return;
    var keys = HardwareKeyboard.instance;
    var d = event.scrollDelta;
    _steering();
    if (keys.isControlPressed || keys.isMetaPressed) {
      controller.dollyBy(math.exp(d.dy * 0.01), transient: true);
    } else if (keys.isShiftPressed) {
      controller.panCameraBy(-d / _scaleOrOne, transient: true);
    } else {
      controller.orbitBy(-d.dx * 0.4, -d.dy * 0.4, transient: true);
    }
  }

  /// _scrollPhysics holds the page still while locked or over code.
  ScrollPhysics? get _scrollPhysics =>
      controller.pageLocked || _codeOver != null
          ? const NeverScrollableScrollPhysics()
          : null;

  void _onScroll(PointerScrollEvent event) {
    // While reframing, the wheel zooms the picture, not the view: drag to
    // choose what is in shot, scroll to choose how much.
    if (_framing != null) {
      var framed = document.elementById(_framing!);
      if (framed is ImageElement) {
        controller.beginInteraction();
        controller.replaceElement(
            framed.copyWith(
                framing: framed.framing.copyWith(
                    zoom: framed.framing.zoom *
                        (event.scrollDelta.dy > 0 ? 0.94 : 1.06))),
            transient: true);
        _wheelRests?.cancel();
        _wheelRests =
            Timer(const Duration(milliseconds: 400), controller.endInteraction);
        return;
      }
    }

    // About the pointer, so the corner scrolled in on stays put.
    _zoomAbout(event.localPosition,
        controller.zoom * (event.scrollDelta.dy > 0 ? 0.9 : 1.1));
  }

  /// _zoomAbout zooms to [zoom], keeping the page point under [stage] put.
  void _zoomAbout(Offset stage, double zoom,
      {Offset? doc, Offset? pan, double? scale}) {
    var under = doc ?? _toDocument(stage);
    var was = pan ?? _clampedPan;
    var before = scale ?? _scale;
    controller.zoom = zoom;
    var after = _view.fitScale * controller.zoom;
    var middle = Offset(document.size.width / 2, document.size.height / 2);
    var next = was + (under - middle) * (before - after);
    controller.pan = next;
  }

  void _onPinchStart(PointerPanZoomStartEvent e) {
    _codePinch = _codePaneAt(_toDocument(e.localPosition));
    // Locked, the page does not zoom: on a stage the fingers steer the camera
    // instead (see _onPinchUpdate).
    if (controller.pageLocked) {
      _pinchScale = 1;
      return;
    }
    _pinch = (
      zoom: controller.zoom,
      pan: _clampedPan,
      scale: _scale,
      doc: _toDocument(e.localPosition),
    );
  }

  /// _onPinchUpdate zooms as the fingers spread or close, about where they
  /// are. A two-finger slide alone is the scroll views' to handle.
  void _onPinchUpdate(PointerPanZoomUpdateEvent e) {
    if (_codePinch case var at? when (e.scale - 1).abs() < 0.01) {
      _scrollCodeBy(at, -e.panDelta.dy);
      return;
    }
    if (controller.pageLocked) {
      if (!controller.onStage3d) return;
      _steering();
      var spread = e.scale / (_pinchScale == 0 ? 1 : _pinchScale);
      _pinchScale = e.scale;
      if ((spread - 1).abs() > 0.002) {
        controller.dollyBy(1 / spread, transient: true);
      } else if (HardwareKeyboard.instance.isShiftPressed) {
        controller.panCameraBy(e.panDelta / _scaleOrOne, transient: true);
      } else {
        controller.orbitBy(e.panDelta.dx * 0.4, e.panDelta.dy * 0.4,
            transient: true);
      }
      return;
    }
    var p = _pinch;
    if (p == null || (e.scale - 1).abs() < 0.01) return;
    _zoomAbout(e.localPosition, p.zoom * e.scale,
        doc: p.doc, pan: p.pan, scale: p.scale);
  }

  void _onPinchEnd(PointerPanZoomEndEvent e) {
    _pinch = null;
    _codePinch = null;
  }
}

/// _StageCameraDrag is a 3D stage's camera taken by a drag: with Option
/// held anywhere on the stage, or, with the page locked, by a press on the
/// stage itself or the middle button anywhere. One undo step, opened as it
/// begins. Its travel is measured on the stage, in pixels.
sealed class _StageCameraDrag extends StageGesture {
  _StageCameraDrag(this.stageId, this.from, this.start,
      {required this.clickClears});

  /// stageId is the stage whose camera it is.
  final String stageId;

  /// from is the camera when the press began, which every step works from.
  final StageCamera from;

  /// start is where the press began, in stage pixels.
  final Offset start;

  /// clickClears is whether a click (the press let go without travelling)
  /// is a click on nothing, which clears the selection: for a press of the
  /// primary button that took the camera because the page is locked. The
  /// middle button pans, and Option takes the camera over what is there.
  final bool clickClears;

  @override
  bool get opensUndoStep => true;

  @override
  bool get waitsToTravel => true;

  @override
  MouseCursor get cursor => SystemMouseCursors.grabbing;

  @override
  void release(CanvasStageState stage, Offset at,
      {required bool travelled, required bool clicked}) {
    if (!clickClears || !clicked) return;
    // The camera's step is closed first: letting go of the selection can
    // finish editing a drawing, which changes the document, and that is
    // not the camera's to take back.
    stage.controller.endInteraction();
    stage.controller.clearSelection();
  }

  @override
  void cancel(CanvasStageState stage) {}
}

/// _StageOrbit is a 3D stage's camera swung round it: across turns it,
/// down looks from higher.
class _StageOrbit extends _StageCameraDrag {
  _StageOrbit(super.stageId, super.from, super.start,
      {required super.clickClears});

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) {
    var c = stage.controller;
    if (c.stageOf(stageId) case var s?) {
      var d = at - start;
      var yaw = from.yaw + d.dx * CanvasOrbitPad.degreesPerPixel * 0.5;
      var pitch = (from.pitch + d.dy * CanvasOrbitPad.degreesPerPixel * 0.5)
          .clamp(-10.0, 89.0);
      c.putStage(
          c.stageFilmed(
              s, from.copyWith(yaw: (yaw * 10).round() / 10, pitch: pitch)),
          transient: true);
    }
  }
}

/// _StagePan is a 3D stage's camera slid sideways and up, by a shifted or
/// middle-button drag. Only the page locked begins one.
class _StagePan extends _StageCameraDrag {
  _StagePan(super.stageId, super.from, super.start,
      {required super.clickClears});

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) {
    var c = stage.controller;
    if (c.stageOf(stageId) case var s?) {
      var d = (at - start) / stage._scaleOrOne;
      c.putStage(c.stageFilmed(s, StageView(s.bounds, from).panned(d)),
          transient: true);
    }
  }
}

/// _ParallaxPan is parallax scenery's camera moved by an Option-drag on it.
/// One undo step, opened as it begins.
class _ParallaxPan extends StageGesture {
  _ParallaxPan(this.sceneryId, this.from, this.start);

  /// sceneryId is the scenery whose camera it is.
  final String sceneryId;

  /// from is the camera when the press began, which every step works from.
  final ParallaxCamera from;

  /// start is where the press began, in stage pixels.
  final Offset start;

  @override
  bool get opensUndoStep => true;

  @override
  bool get waitsToTravel => true;

  @override
  MouseCursor get cursor => SystemMouseCursors.grabbing;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) {
    var c = stage.controller;
    if (c.parallaxOf(sceneryId) case var p?) {
      // Against the drag, in design units: dragging the scenery left moves
      // the camera right.
      var d = (at - start) / stage._scaleOrOne;
      c.putBackdrop(
          c.parallaxFilmed(
              p,
              from.copyWith(
                  x: (from.x - d.dx).roundToDouble(),
                  y: (from.y - d.dy).roundToDouble())),
          transient: true);
    }
  }

  @override
  void release(CanvasStageState stage, Offset at,
      {required bool travelled, required bool clicked}) {}

  @override
  void cancel(CanvasStageState stage) {}
}

/// _GizmoDrag is a part of the stage gizmo dragged, moving, turning or
/// sizing the element it is on (see StageGizmo.dragged), worked out from
/// where it stood when pressed. One undo step, opened as it begins. The
/// part held is drawn lit while it runs.
class _GizmoDrag extends StageGesture {
  _GizmoDrag(
      {required this.gizmo,
      required this.part,
      required this.from,
      required this.elementId});

  /// gizmo is the gizmo when it was pressed.
  final StageGizmo gizmo;

  /// part is the part held.
  final GizmoPart part;

  /// from is the page point taken.
  final Offset from;

  /// elementId is the element the gizmo is on.
  final String elementId;

  @override
  bool get opensUndoStep => true;

  @override
  bool get waitsToTravel => true;

  @override
  MouseCursor get cursor => SystemMouseCursors.grabbing;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) {
    var document = stage.document;
    if (document.elementById(elementId) case var e?) {
      var guides = document.guides;
      var snap = guides.stageSnap && stage._snapReach != null;
      var spot = gizmo.dragged(part, from, doc,
          pageScale: stage._scale,
          step: snap ? guides.stageStep : 0,
          turn: snap ? guides.stageTurn : 0);
      stage.controller
          .replaceElement(stage.controller.spotted(e, spot), transient: true);
    }
  }

  /// release lights what the pointer is over now, not the part it held:
  /// see _gizmoLetGo.
  @override
  void release(CanvasStageState stage, Offset at,
          {required bool travelled, required bool clicked}) =>
      stage._gizmoLetGo(at);

  @override
  void cancel(CanvasStageState stage) =>
      stage._gizmoLetGo(stage._pointer?.localPosition);
}
