part of 'scene_renderer.dart';

// The page's own background (colour, gradient, picture, pattern) and the
// Background element drawn the same way. Part of scene_renderer.dart.

void _paintDocumentBackground(
    ui.Canvas canvas,
    Rect rect,
    CanvasDocument doc,
    double time,
    CanvasImageSource? images,
    ProceduralCache? backgrounds,
    double frameRate,
    [ui.Image? backdrop,
    VideoShow Function(VideoElement)? videoShow]) {
  // A backdrop handed in is the background rasterised once (ExportBackdrop).
  if (backdrop != null) {
    // Drawn unfiltered at one pixel to one, matching the slow road; scaled
    // under a scene's camera, and filtered like any scaled picture.
    var m = canvas.getTransform();
    var across = rect.width * math.sqrt(m[0] * m[0] + m[1] * m[1]);
    var exact = (across - backdrop.width).abs() < 0.5;
    canvas.drawImageRect(
        backdrop,
        Rect.fromLTWH(
            0, 0, backdrop.width.toDouble(), backdrop.height.toDouble()),
        rect,
        Paint()
          ..filterQuality = exact ? FilterQuality.none : FilterQuality.medium);
    return;
  }
  // The master's own when the shared canvas is on and has one.
  var bg = doc.drawnBackground;

  // The picture, the drawing and the video are elements stretched to the
  // page, whatever box they were saved with.
  T onPage<T extends CanvasElement>(T e) => e.rebase(ElementBase(
      id: e.id,
      x: rect.left,
      y: rect.top,
      width: rect.width,
      height: rect.height)) as T;

  var picture = bg.shownPicture;
  var decoded = picture == null
      ? null
      : images?.resolve(picture.assetId, picture.removal);
  // A decoded picture covering the page uncut hides it: skip generating.
  var covered = decoded != null &&
      picture!.fit == ImageFit.cover &&
      !picture.removal.active &&
      picture.frame == null &&
      picture.box.padding == 0;
  if (bg.isStage) {
    // The stage in the pattern's place, seen through its camera; whatever
    // stands on it is drawn in front.
    paintStage(canvas, rect, bg.stageOn(rect), (time * frameRate).round(),
        images: images);
  } else if (bg.isParallax) {
    paintParallax(canvas, rect, bg.parallaxOn(rect), (time * frameRate).round(),
        frameRate: frameRate,
        images: images,
        loopFrames: parallaxLoopFrames(doc));
  } else if (!covered) {
    _paintPattern(canvas, rect, bg, time, images, backgrounds, frameRate);
  }
  if (picture != null && decoded != null) {
    _paintImage(canvas, rect, onPage(picture), images);
  }
  if (bg.drawing case var drawing? when drawing.hasDrawing) {
    paintVector(canvas, rect, onPage(drawing), images);
  }
  if (bg.video case var video? when !video.clip.isEmpty) {
    var page = onPage(video);
    _paintVideo(canvas, rect, page,
        videoShow?.call(page) ?? VideoShow.idle(page), images,
        placeholder: false);
  }
}

void _paintPattern(
    ui.Canvas canvas,
    Rect rect,
    CanvasBackground bg,
    double time,
    CanvasImageSource? images,
    ProceduralCache? backgrounds,
    double frameRate) {
  // The cached one, for the same background at the same size.
  var ready = backgrounds?.imageFor(bg.spec, rect.size, time, images);
  if (ready != null) {
    canvas.drawImageRect(
        ready,
        Rect.fromLTWH(0, 0, ready.width.toDouble(), ready.height.toDouble()),
        rect,
        Paint()..filterQuality = FilterQuality.low);
    return;
  }
  // The rate as well as the time: a movement that runs once is counted in
  // frames. See ProceduralSpec.passFrames.
  paintProcedural(canvas, rect, bg.spec,
      time: time, frameRate: frameRate, images: images);
}

/// paintDocumentBackdrop draws a document's background alone, for an export
/// to rasterise once and draw on every frame. See ExportBackdrop.
void paintDocumentBackdrop(ui.Canvas canvas, CanvasDocument doc,
        {CanvasImageSource? images}) =>
    _paintDocumentBackground(
        canvas, doc.size.rect, doc, 0, images, null, doc.frameRate.toDouble());

void _paintBackgroundElement(
    ui.Canvas canvas,
    Rect bounds,
    BackgroundElement e,
    double time,
    double frameRate,
    CanvasImageSource? images,
    ProceduralCache? backgrounds,
    {int? loopFrames}) {
  if (e.cornerRadius > 0) {
    canvas.save();
    canvas.clipRRect(
        RRect.fromRectAndRadius(bounds, Radius.circular(e.cornerRadius)));
  }
  if (e.isStage || e.isParallax) {
    var frame = (time * frameRate).round();
    if (e.isStage) {
      paintStage(canvas, bounds, e.staged, frame, images: images);
    } else {
      paintParallax(canvas, bounds, e.parallaxed, frame,
          frameRate: frameRate, images: images, loopFrames: loopFrames);
    }
    if (e.cornerRadius > 0) canvas.restore();
    return;
  }
  // From the editor's cache where it can be; during a gesture (a panel
  // resize) the last one is stretched and a new one made when it ends.
  var ready = backgrounds?.imageFor(
          e.spec, bounds.size, time, images, !RasterCache.drafting, false) ??
      (RasterCache.drafting ? backgrounds?.latestFor(e.spec) : null);
  if (ready != null) {
    canvas.drawImageRect(
        ready,
        Rect.fromLTWH(0, 0, ready.width.toDouble(), ready.height.toDouble()),
        bounds,
        Paint()..filterQuality = FilterQuality.low);
  } else {
    paintProcedural(canvas, bounds, e.spec,
        time: time, frameRate: frameRate, images: images);
  }
  if (e.cornerRadius > 0) canvas.restore();
}
