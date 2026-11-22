part of 'canvas_stage.dart';

// A picture reframed inside its frame: where the whole picture is drawn
// while it is moved in its box, and the drag that moves it. "Framing" here is
// the picture in its frame, not the camera's view of the scene. Part of
// CanvasStageState: its fields, lifecycle and build are in canvas_stage.dart.

extension StagePictureFraming on CanvasStageState {
  /// _framingPlacement is where the picture is drawn, from what draws it.
  ImagePlacement? _framingPlacement(ImageElement e, ui.Image image) {
    var inner = _framingRect(e);
    if (inner.width <= 0 || inner.height <= 0) return null;
    return placeImage(
        Size(image.width.toDouble(), image.height.toDouble()), inner, e.fit,
        crop: e.crop, framing: e.framing);
  }

  /// _framingRect is where the reframed picture is drawn: its frame, or,
  /// layered, its own place in the frame, which is less than the whole once
  /// the frame grows round a layer or stroke.
  Rect _framingRect(ImageElement e) {
    var inner = e.box.inner(_hit.posed(e));
    if (!e.layered) return inner;
    var base =
        e.stack.firstWhere((l) => l.isBase, orElse: () => ImageLayer.base);
    return layerRect(inner, base.place);
  }

  /// _framingView is the whole reframed picture, placed where its visible
  /// part is, for the painter.
  StageFraming? _framingView() {
    if (_framedPicture() case (var e, var image)) {
      var placement = _framingPlacement(e, image);
      if (placement == null || placement.src.width <= 0) return null;

      var base =
          e.stack.firstWhere((l) => l.isBase, orElse: () => ImageLayer.base);
      return StageFraming(
          image,
          placement.whole,
          placement.wholeDst,
          _framingRect(e),
          e.movedRotationAt(controller.frame, controller.document,
                  live: controller.liveMotion) *
              math.pi /
              180,
          pivot: _hit.posed(e).center,
          flipX: base.flipX,
          flipY: base.flipY);
    }
    return null;
  }

  /// _applyFraming moves the picture inside its frame by the pointer's travel
  /// since the press. Travel is in canvas units and framing in fractions of
  /// the slack, so it converts through the placement and follows the pointer
  /// at any zoom. Dragging right moves the picture right.
  void _applyFraming(Offset doc) {
    if (_framedPicture() case (var e, var image)) {
      var placement = _framingPlacement(e, image);
      if (placement == null) return;
      // Canvas units per picture pixel.
      var perPixel = placement.src.width <= 0
          ? 0.0
          : placement.dst.width / placement.src.width;
      if (perPixel <= 0) return;
      var slack = placement.slack;

      // Undo the element's rotation and mirror, so the picture moves with
      // the pointer.
      var travel = doc - _dragStart;
      var turn = -e.movedRotationAt(controller.frame, controller.document,
          live: controller.liveMotion);
      if (turn != 0) travel = BoxFrame(turn, 0, 0).apply(travel);
      var base =
          e.stack.firstWhere((l) => l.isBase, orElse: () => ImageLayer.base);
      travel = Offset(base.flipX ? -travel.dx : travel.dx,
          base.flipY ? -travel.dy : travel.dy);

      controller.replaceElement(
          e.copyWith(
              framing: e.framing.copyWith(
            x: slack.dx <= 0
                ? _framingStart.x
                : _framingStart.x - travel.dx / perPixel / slack.dx,
            y: slack.dy <= 0
                ? _framingStart.y
                : _framingStart.y - travel.dy / perPixel / slack.dy,
          )),
          transient: true);
    }
  }
}
