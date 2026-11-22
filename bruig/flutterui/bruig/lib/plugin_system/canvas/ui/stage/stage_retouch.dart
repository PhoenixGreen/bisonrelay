part of 'canvas_stage.dart';

// The retouching brush's stroke on a picture: the gesture that draws it
// (_RetouchStroke), the held stroke's preview, rebuilt when the stroke or its
// settings change, and the finished stroke handed to the controller as one
// undo step. Each point as it is drawn is _paintStrokeAt, in
// stage_picture_tools.dart. Part of CanvasStageState: its fields, lifecycle
// and build are in canvas_stage.dart.

extension StageRetouch on CanvasStageState {
  /// _previewPlacement is where the held stroke's preview is drawn.
  ImagePlacement? _previewPlacement() {
    var id = controller.pendingPicture;
    if (id == null || _preview == null) return null;
    var picture = document.elementById(id);
    if (picture is! ImageElement) return null;
    var inner = picture.box.inner(_hit.posed(picture));
    var size = Size(_preview!.width.toDouble(), _preview!.height.toDouble());
    return placeImage(size, inner, picture.fit,
        crop: picture.crop, framing: picture.framing);
  }

  /// _refreshPreview rebuilds the held stroke's preview when the stroke or
  /// its settings change, keyed on the settings rather than every notify.
  void _refreshPreview() {
    var stroke = controller.pendingAsStroke();
    var id = controller.pendingPicture;
    if (stroke == null || id == null) {
      if (_preview != null || _previewOf != null) {
        setState(() {
          _preview = null;
          _previewOf = null;
        });
      }
      return;
    }

    var picture = document.elementById(id);
    if (picture is! ImageElement) return;
    var source = controller.images.original(picture.assetId);
    if (source == null) return;

    var key = "$id|${stroke.points.length}|${stroke.radius}|"
        "${stroke.hardness}|${stroke.snap}|${stroke.keep}|"
        "${stroke.fill}|${stroke.fillInside}";
    if (key == _previewOf) return;
    _previewOf = key;

    // Once the settings stop moving. A last keystroke is only told by
    // waiting, so the stroke goes through the same delay.
    _previewDebounce?.cancel();
    _previewDebounce = Timer(CanvasStageState._previewDelay, () {
      if (!mounted || _previewOf != key) return;
      // Coloured by the brush's hardness at each pixel, which is judged.
      strokePreview(source, stroke).then((image) {
        if (!mounted || _previewOf != key) return;
        setState(() => _preview = image);
      });
    });
  }

  /// _commitStroke hands [stroke], finished, to the controller to hold on
  /// its picture: one pass over the pixels when it is applied. The
  /// gesture's end then closes its undo step.
  void _commitStroke(_RetouchStroke stroke) {
    var points = [...stroke.imagePoints];
    setState(() {
      stroke.imagePoints.clear();
      stroke.canvasPoints.clear();
    });

    var picture = document.elementById(stroke.pictureId);
    if (picture is! ImageElement || points.isEmpty) return;

    // A marking brush teaches the learning method; the other two rub out and
    // restore. Which is kept with the stroke, since another brush may be
    // picked before it is applied.
    var teaching = controller.retouch.teaches;

    // Held, not applied, so the brush can be adjusted while the same stroke
    // redraws: see CanvasController.holdStroke.
    controller.holdStroke(picture.id, points,
        keeps: controller.retouch.keeps,
        teaches: teaching,
        fills: controller.retouch.fills);
  }
}

/// _RetouchStroke is the retouching brush drawn over the selected picture.
/// What is drawn is kept here, and shown as it grows, until the stroke
/// ends: written to the picture point by point, each would rebuild the
/// treated picture. One undo step. A cancel ends it as a release does.
class _RetouchStroke extends StageGesture {
  _RetouchStroke(this.pictureId);

  /// pictureId is the picture's, by id: the element is replaced when the
  /// stroke lands.
  final String pictureId;

  /// imagePoints and canvasPoints are the stroke, in the picture's
  /// coordinates for storing and the page's for showing.
  final List<Offset> imagePoints = [];
  final List<Offset> canvasPoints = [];

  /// radius is the brush's radius on the page, set as the stroke begins.
  double radius = 0;

  @override
  bool get opensUndoStep => true;

  @override
  bool get waitsToTravel => false;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) =>
      stage._paintStrokeAt(this, doc);

  /// endsRelease is true: handing the stroke over is the whole of its
  /// release.
  @override
  bool get endsRelease => true;

  @override
  void release(CanvasStageState stage, Offset at,
          {required bool travelled, required bool clicked}) =>
      stage._commitStroke(this);

  @override
  void cancel(CanvasStageState stage) => stage._commitStroke(this);
}
