part of 'canvas_stage.dart';

// The 3D stage's gizmo, and steering the view: scrolling, pinching and zooming.
// Part of CanvasStageState: its fields, lifecycle and build are in
// canvas_stage.dart.

extension Stage3dView on CanvasStageState {
  /// _gizmoReach is how near a part, in page units, the pointer must be.
  double get _gizmoReach => 9 / (_scale == 0 ? 1 : _scale);

  /// _gizmo is the gizmo on the lone selected staged element, or null.
  StageGizmo? _gizmo() {
    if (!controller.showHelpers || controller.playing || controller.gaming) {
      return null;
    }
    if (controller.selection.length != 1) return null;
    var e = document.elementById(controller.selection.first);
    if (e == null || e.locked || e.base.spot == null) return null;
    var at = stagedIn(document, e, controller.frame);
    if (at == null) return null;
    return StageGizmo.of(e, at, controller.stageTool, _scale);
  }

  bool _pressGizmo(Offset doc) {
    var g = _gizmo();
    if (g == null) return false;
    var part = g.hit(doc, _gizmoReach);
    if (part == null) return false;
    _gizmoDrag = (g, part, doc, controller.selection.first);
    _mode = _DragMode.gizmo;
    controller.beginInteraction();
    setState(() => _gizmoHot = part);
    return true;
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
    _orbiting = s.id;
    _orbitFrom = s.cameraAt(controller.frame);
    _orbitAt = event.localPosition;
    _mode = middle || HardwareKeyboard.instance.isShiftPressed
        ? _DragMode.stagePan
        : _DragMode.stageOrbit;
    _lockedPress = true;
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
      controller.panCameraBy(-d / (_scale == 0 ? 1 : _scale),
          transient: true);
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
        _wheelRests = Timer(
            const Duration(milliseconds: 400), controller.endInteraction);
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
    var after = _fitScale * controller.zoom;
    var middle = Offset(document.size.width / 2, document.size.height / 2);
    var next = was + (under - middle) * (before - after);
    controller.pan = Offset2(next.dx, next.dy);
  }

  void _onPinchStart(PointerPanZoomStartEvent e) {
    _codePinch = _codePaneAt(e.localPosition);
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
        controller.panCameraBy(e.panDelta / (_scale == 0 ? 1 : _scale),
            transient: true);
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
