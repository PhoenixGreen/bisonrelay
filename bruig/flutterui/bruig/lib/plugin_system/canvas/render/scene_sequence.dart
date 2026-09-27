import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/render/audio_painter.dart';
import 'package:bruig/plugin_system/canvas/render/video_painter.dart';

import 'package:bruig/plugin_system/canvas/render/procedural_cache.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/transition_shapes.dart';
import 'package:flutter/painting.dart';

// scene_sequence.dart plays a document through: every scene in order, and
// whatever is drawn between them.
//
// One function that everything asking "what does this document look like at
// this moment" goes through -- the preview, the transport, the export. A
// second opinion about where scene four starts would be a canvas that
// exported differently from the one on screen.
//
// A transition is drawn as two scenes and an effect, never as a scene with an
// effect applied: both canvases are real for as long as the transition lasts,
// which is what lets a cross fade fade and a push push.

/// SequencePlace is where a moment in the whole document falls: which scene,
/// which frame of it, and whether a transition is running.
class SequencePlace {
  /// scene is the scene showing, and frame the frame of it.
  final int scene;
  final int frame;

  /// next is the scene coming in, or -1 when nothing is.
  final int next;

  /// nextFrame is the frame the incoming scene has reached.
  final int nextFrame;

  /// through is how far the transition has got, 0 to 1.
  final double through;

  const SequencePlace({
    required this.scene,
    required this.frame,
    this.next = -1,
    this.nextFrame = 0,
    this.through = 0,
  });

  bool get changing => next >= 0;
}

/// placeInSequence is where [at] falls in the document's whole run.
///
/// The frames a transition overlaps belong to both scenes at once -- see
/// CanvasDocument.sequenceFrames, which takes them off the total for exactly
/// that reason.
SequencePlace placeInSequence(CanvasDocument doc, int at) {
  var scenes = doc.allScenes;
  if (scenes.isEmpty) return const SequencePlace(scene: 0, frame: 0);

  var want = math.max(0, at);
  var start = 0;
  for (var i = 0; i < scenes.length; i++) {
    var scene = scenes[i];
    var (over, held, runs) = doc.sceneStep(i);
    var local = want - start;

    if (i == scenes.length - 1) {
      return SequencePlace(
          scene: i, frame: math.min(math.max(0, local), scene.frames - 1));
    }

    // The transition's own stretch of time. It begins where the two scenes
    // start sharing frames -- or at the end of this scene, when they share
    // none -- and lasts as long as the transition is set to.
    //
    // One branch for both. There were two, one for a transition that runs
    // across the join and one for a transition that runs between the scenes,
    // and between them was a case neither handled: a transition longer than
    // its overlap ran for the overlap and the rest of its length was thrown
    // away, so setting it to twenty frames over an overlap of five played a
    // five-frame transition.
    var begins = scene.frames - held;
    if (runs > 0 && local >= begins && local < begins + runs) {
      var into = local - begins;
      return SequencePlace(
        scene: i,
        // Both scenes play for the frames they share and are held either
        // side of them: the one leaving on its last frame, the one arriving
        // on the frame it has reached.
        frame: math.min(local, scene.frames - 1),
        next: i + 1,
        nextFrame: held == 0 ? 0 : math.min(into, held - 1),
        through: (into + 1) / runs,
      );
    }

    if (local < scene.frames) {
      return SequencePlace(scene: i, frame: math.max(0, local));
    }

    start += over;
  }

  var last = scenes.length - 1;
  return SequencePlace(scene: last, frame: scenes[last].frames - 1);
}

/// paintSequenceFrame draws the whole document at one moment of its run.
void paintSequenceFrame(
  ui.Canvas canvas,
  CanvasDocument doc,
  int at, {
  CanvasImageSource? images,

  /// backgrounds holds a raster for each canvas on screen, which for the
  /// length of a transition is the scene leaving and the scene arriving both.
  /// A cache of one made a backdrop from scratch twice a frame, and a
  /// generated backdrop is the most expensive thing on a canvas -- which is
  /// what made a page turn crawl. See ProceduralCache.
  ProceduralCache? backgrounds,

  /// audioState and videoShow are what the media on screen are doing, so a
  /// document played through shows its videos moving rather than their
  /// posters. Null in an export. See paintCanvasDocument.
  AudioState Function(AudioElement)? audioState,
  VideoShow Function(VideoElement)? videoShow,
}) {
  var place = placeInSequence(doc, at);
  var scenes = doc.allScenes;
  if (scenes.isEmpty) return;

  // The scene after this one, ready before its transition asks for it.
  if (backgrounds != null) {
    var after = (place.changing ? place.next : place.scene) + 1;
    if (after < scenes.length) {
      warmBackdrop(doc, after, backgrounds, images);
    }
  }

  void drawScene(int index, int frame) {
    // Each scene with its own backdrop -- see CanvasDocument.backgroundOf.
    // Drawn from the document's own, every scene in the run wore whichever
    // one was edited last.
    paintCanvasDocument(
        canvas,
        doc
            .goToScene(index)
            .copyWith(onMaster: false, background: doc.backgroundOf(index)),
        frame: frame,
        images: images,
        backgrounds: backgrounds,
        audioState: audioState,
        videoShow: videoShow);
  }

  if (!place.changing) {
    drawScene(place.scene, place.frame);
    return;
  }

  var over = doc.transitionAfter(place.scene);
  var t = over.ease.apply(place.through.clamp(0.0, 1.0));
  var page = doc.size.rect;

  paintTransition(
    canvas,
    page,
    over,
    t,
    from: () => drawScene(place.scene, place.frame),
    to: () => drawScene(place.next, place.nextFrame),
  );
}

/// warmBackdrop has the generated backdrop of scene [index] made, if it is
/// one, so that it is ready by the time the scene is drawn.
void warmBackdrop(CanvasDocument doc, int index, ProceduralCache backgrounds,
    CanvasImageSource? images) {
  var bg = doc.backgroundOf(index);
  if (bg.isImage) return;
  backgrounds.warm(bg.spec, doc.size.size, images);
}

/// paintTransition draws one canvas giving way to another.
///
/// The two scenes are handed in as things to draw rather than as pictures,
/// so a transition that shows only part of one -- a wipe, a push -- pays for
/// the part it shows and nothing else.
void paintTransition(
  ui.Canvas canvas,
  Rect page,
  SceneTransition over,
  double t, {
  required void Function() from,
  required void Function() to,
}) {
  var kind = over.kind;

  switch (kind) {
    case SceneTransitionKind.cut:
      (t >= 0.5 ? to : from)();

    case SceneTransitionKind.fade:
      from();
      _faded(canvas, page, t, to);

    case SceneTransitionKind.through:
      // Out to the colour and back out of it: the first half belongs to the
      // scene leaving, the second to the one arriving, and the colour is at
      // its strongest exactly between them.
      if (t < 0.5) {
        from();
        canvas.drawRect(
            page,
            Paint()
              ..color = over.color.withValues(alpha: (t * 2).clamp(0.0, 1.0)));
      } else {
        to();
        canvas.drawRect(
            page,
            Paint()
              ..color =
                  over.color.withValues(alpha: ((1 - t) * 2).clamp(0.0, 1.0)));
      }

    case SceneTransitionKind.slideLeft:
    case SceneTransitionKind.slideRight:
    case SceneTransitionKind.slideUp:
    case SceneTransitionKind.slideDown:
      from();
      _shifted(canvas, page, _away(kind, page, 1 - t), to);

    case SceneTransitionKind.pushLeft:
    case SceneTransitionKind.pushRight:
    case SceneTransitionKind.pushUp:
    case SceneTransitionKind.pushDown:
      // The old one goes with the new one rather than being covered by it.
      _shifted(canvas, page, -_away(kind, page, t), from);
      _shifted(canvas, page, _away(kind, page, 1 - t), to);

    case SceneTransitionKind.wipeLeft:
    case SceneTransitionKind.wipeRight:
    case SceneTransitionKind.wipeUp:
    case SceneTransitionKind.wipeDown:
      from();
      canvas.save();
      canvas.clipRect(_wipe(kind, page, t));
      to();
      canvas.restore();

    case SceneTransitionKind.zoomIn:
      from();
      _scaled(canvas, page, 0.6 + 0.4 * t, t, to);

    case SceneTransitionKind.zoomOut:
      _scaled(canvas, page, 1 + 0.4 * t, 1 - t, from);
      _faded(canvas, page, t, to);

    // Everything that covers: a shape in the transition's own colour grows
    // until the page is behind it, the scenes change, and it goes away. See
    // transition_shapes.dart -- and SceneTransitionKind.covers for why these
    // are not masks.
    case SceneTransitionKind.band:
    case SceneTransitionKind.blinds:
    case SceneTransitionKind.barn:
    case SceneTransitionKind.shapeWipe:
    case SceneTransitionKind.clock:
    case SceneTransitionKind.arrow:
    case SceneTransitionKind.splatter:
    case SceneTransitionKind.brush:
    case SceneTransitionKind.tiles:
    case SceneTransitionKind.halftone:
    case SceneTransitionKind.burst:
    case SceneTransitionKind.rays:
      // Behind the cover, and swapped at the moment it is complete.
      (t >= 0.5 ? to : from)();
      _drawCover(canvas, page, over, t);

    case SceneTransitionKind.blurThrough:
      _blurThrough(canvas, page, over, t, from: from, to: to);

    case SceneTransitionKind.pageTurn:
      // One canvas on its own has no reverse to show, so the back of the
      // leaf is its own face seen through the paper -- which is what the
      // back of a printed page looks like held up to the light.
      paintPageTurn(canvas, page, t,
          front: from, under: to, back: () => _seenThrough(canvas, page, from));
  }
}

/// _seenThrough draws a page as it is seen from behind: mirrored about its
/// left edge, where a leaf turned to the left lies, and mostly paper.
void _seenThrough(ui.Canvas canvas, Rect page, void Function() draw) {
  canvas.save();
  canvas.translate(page.left * 2, 0);
  canvas.scale(-1, 1);
  canvas.save();
  canvas.clipRect(page);
  draw();
  canvas.restore();
  canvas.drawRect(page, Paint()..color = const Color(0xD8F7F5F0));
  canvas.restore();
}

/// paintPageTurn draws [leaf] turning over about its left edge, the spine.
///
/// The leaf is a sheet printed on both sides. [front] is its face and
/// [under] what lies beneath it, both drawn where the leaf lies now; [back]
/// is its reverse, drawn where it will lie once turned -- the leaf's own
/// size, to the left of the spine. The four attempts before this one each
/// had one page moving over another with blank paper or nothing on its
/// back, and every one of them read as something going wrong with the page.
///
/// The bottom outer corner is carried over the spine along a low arc, and
/// the fold is wherever it has to be for that corner to be where it is: the
/// line halfway between where the corner started and where it has got to.
/// Everything past the fold is reflected across it, which is how a sheet
/// folds. Because the corner leads, the fold leans -- a page turned by a hand
/// goes over bottom corner first.
void paintPageTurn(
  ui.Canvas canvas,
  Rect leaf,
  double t, {
  required void Function() front,
  void Function()? under,
  required void Function() back,
}) {
  if (t <= 0) {
    front();
    return;
  }
  var width = leaf.width, height = leaf.height;
  var spineTop = leaf.topLeft, spineFoot = leaf.bottomLeft;
  if (t >= 1) {
    under?.call();
    canvas.save();
    canvas.clipRect(leaf.shift(Offset(-width, 0)));
    back();
    canvas.restore();
    return;
  }

  var corner = leaf.bottomRight;
  var angle = math.pi * t;
  var lift = math.min(width, height) * 0.22;
  var held = Offset(leaf.left + width * math.cos(angle),
      leaf.bottom - lift * math.sin(angle));
  // The sheet is bound at the spine and cannot stretch: the corner can get
  // no further from the foot of the spine than the page is wide, nor from
  // its head than the diagonal.
  held = _within(held, spineFoot, width);
  held = _within(held, spineTop, math.sqrt(width * width + height * height));

  var travel = held - corner;
  if (travel.distance < 0.5) {
    front();
    return;
  }
  var fold = (corner + held) / 2;
  var normal = travel / travel.distance;
  double side(Offset q) =>
      (q.dx - fold.dx) * normal.dx + (q.dy - fold.dy) * normal.dy;
  Offset reflect(Offset q) => q - normal * (2 * side(q));

  var sheet = [leaf.topLeft, leaf.topRight, leaf.bottomRight, leaf.bottomLeft];
  var staying = _clipPolygon(sheet, side, keep: true);
  var lifted = _clipPolygon(sheet, side, keep: false);
  var over = [for (var q in lifted) reflect(q)];

  // How far open the sheet is, which is how much shadow it throws: none
  // lying flat at either end, most standing up in the middle.
  var open = math.sin(angle);
  var reach = width * (0.04 + 0.12 * open);

  // What the turn uncovers, and the shadow of the sheet on it. The shadow
  // runs back from the fold, darkest against it.
  if (under != null && lifted.length > 2) {
    canvas.save();
    canvas.clipPath(_polygon(lifted));
    under();
    canvas.drawPaint(Paint()
      ..shader = ui.Gradient.linear(fold, fold - normal * reach, [
        Color.fromRGBO(0, 0, 0, 0.35 * open + 0.1),
        const Color(0x00000000),
      ]));
    canvas.restore();
  }

  // The face still lying flat.
  if (staying.length > 2) {
    canvas.save();
    canvas.clipPath(_polygon(staying));
    front();
    canvas.restore();
  }

  if (over.length < 3) return;
  var flap = _polygon(over);

  // The turned part stands off the page, so it throws a shadow round its
  // edges onto whatever is under it.
  canvas.drawPath(
      flap.shift(Offset(-reach * 0.15, reach * 0.1)),
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, 0.3 * open)
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, reach * 0.35));

  // The reverse of the sheet. [back] draws it where it lies once turned;
  // mirroring that about the spine puts it on the sheet the way the sheet
  // lies flat, and reflecting across the fold carries it to where the
  // turned part is. Two reflections are a rotation, so its words read the
  // right way round.
  var nx = normal.dx, ny = normal.dy;
  var a = 1 - 2 * nx * nx, b = -2 * nx * ny, d = 1 - 2 * ny * ny;
  var along = fold.dx * nx + fold.dy * ny;
  var x0 = leaf.left;
  var matrix = Float64List.fromList([
    -a, -b, 0, 0, //
    b, d, 0, 0, //
    0, 0, 1, 0, //
    2 * x0 * a + 2 * along * nx, 2 * x0 * b + 2 * along * ny, 0, 1,
  ]);
  canvas.save();
  canvas.clipPath(flap);
  canvas.save();
  canvas.transform(matrix);
  canvas.clipRect(leaf.shift(Offset(-width, 0)));
  back();
  canvas.restore();
  // Paper curving up off the fold is in its own shadow there, and catches
  // the light further out.
  canvas.drawPaint(Paint()
    ..shader = ui.Gradient.linear(fold, fold + normal * reach * 2.2, [
      Color.fromRGBO(0, 0, 0, 0.28 * open + 0.06),
      const Color(0x00000000),
      Color.fromRGBO(255, 255, 255, 0.10 * open),
    ], [
      0,
      0.45,
      1
    ]));
  canvas.restore();
}

/// _within pulls [point] back onto a circle round [centre] when it is
/// further out than [radius].
Offset _within(Offset point, Offset centre, double radius) {
  var away = point - centre;
  if (away.distance <= radius) return point;
  return centre + away / away.distance * radius;
}

/// _clipPolygon is the part of a convex polygon on one side of a line, where
/// [side] is positive on the side [keep] asks for.
List<Offset> _clipPolygon(List<Offset> points, double Function(Offset) side,
    {required bool keep}) {
  double at(Offset q) => keep ? side(q) : -side(q);
  var out = <Offset>[];
  for (var i = 0; i < points.length; i++) {
    var p = points[i], q = points[(i + 1) % points.length];
    var sp = at(p), sq = at(q);
    if (sp >= 0) out.add(p);
    if ((sp >= 0) != (sq >= 0)) {
      out.add(p + (q - p) * (sp / (sp - sq)));
    }
  }
  return out;
}

Path _polygon(List<Offset> points) => Path()..addPolygon(points, true);

/// paintLeaf draws one page of a document as it is printed: its own paper,
/// the neighbour's overhang, then its own contents, clipped to the page.
///
/// The same order the editor and the PDF use, so a picture laid across the
/// gutter is whole in a spread whichever of the two it was placed on. Drawn
/// as a whole canvas with the neighbour beside it, the second page's paper
/// went over the first page's overhang, and a picture across the spread was
/// cut off at the spine the moment the second page played.
///
/// [frameOf] is which frame each leaf is showing -- see paintBookFrame.
void paintLeaf(
  ui.Canvas canvas,
  CanvasDocument doc,
  int index, {
  required int Function(int index) frameOf,
  CanvasImageSource? images,
  ProceduralCache? backgrounds,

  /// audioState and videoShow are what the media on screen are doing, so a
  /// document played through shows its videos moving rather than their
  /// posters. Null in an export. See paintCanvasDocument.
  AudioState Function(AudioElement)? audioState,
  VideoShow Function(VideoElement)? videoShow,
}) {
  var size = doc.size.size;
  var page = doc
      .goToScene(index)
      .copyWith(onMaster: false, background: doc.backgroundOf(index));
  canvas.save();
  canvas.clipRect(Offset.zero & size);
  paintCanvasDocument(canvas, page,
      part: CanvasPaintPart.backdrop, images: images, backgrounds: backgrounds);
  if (doc.facingAt(index) case var beside?) {
    canvas.save();
    canvas.translate(beside > index ? size.width : -size.width, 0);
    paintCanvasDocument(canvas, doc.goToScene(beside).copyWith(onMaster: false),
        frame: frameOf(beside), part: CanvasPaintPart.contents, images: images);
    canvas.restore();
  }
  paintCanvasDocument(canvas, page,
      frame: frameOf(index),
      part: CanvasPaintPart.contents,
      images: images,
      audioState: audioState,
      videoShow: videoShow);
  canvas.restore();
}

/// bookSides is which sides of the book have a leaf on them at [at]: the
/// spread showing, and the one arriving while a transition runs.
(bool, bool) bookSides(CanvasDocument doc, int at) {
  var place = placeInSequence(doc, at);
  var here = doc.spreadOf(place.scene);
  var next = place.changing ? doc.spreadOf(place.next) : null;
  return (
    here?.$1 != null || next?.$1 != null,
    here?.$2 != null || next?.$2 != null,
  );
}

/// paintBookFrame draws a document of facing pages at one moment of its run,
/// a spread at a time.
///
/// The book's left-hand leaf is at [left] and its right-hand leaf a page
/// further on, whichever leaf is playing -- so the book stays where it is
/// for the whole run, and a leaf standing alone stands on its own side.
///
/// A transition between two spreads moves the whole spread, both leaves,
/// and a page turn turns the right-hand leaf over onto the left. Between
/// the two leaves of one spread nothing moves at all: both are already on
/// screen, and any transition there would move a page the reader can see is
/// not going anywhere.
void paintBookFrame(
  ui.Canvas canvas,
  CanvasDocument doc,
  int at, {
  required double left,
  CanvasImageSource? images,
  ProceduralCache? backgrounds,

  /// audioState and videoShow are what the media on screen are doing, so a
  /// document played through shows its videos moving rather than their
  /// posters. Null in an export. See paintCanvasDocument.
  AudioState Function(AudioElement)? audioState,
  VideoShow Function(VideoElement)? videoShow,
}) {
  var scenes = doc.allScenes;
  if (scenes.isEmpty) return;
  var place = placeInSequence(doc, at);
  var size = doc.size.size;

  // What each leaf is showing. The one playing is at its own frame; a leaf
  // already played stays on its last, and one still to come waits on its
  // first, so a page that arrives is seen arriving.
  int frameOf(int index) {
    if (index == place.scene) return place.frame;
    if (place.changing && index == place.next) return place.nextFrame;
    if (index < place.scene) return math.max(0, scenes[index].frames - 1);
    return 0;
  }

  Rect slot(bool onLeft) => Offset(onLeft ? left : left + size.width, 0) & size;

  void leaf(int index, bool onLeft) {
    canvas.save();
    canvas.translate(slot(onLeft).left, 0);
    paintLeaf(canvas, doc, index,
        frameOf: frameOf,
        images: images,
        backgrounds: backgrounds,
        audioState: audioState,
        videoShow: videoShow);
    canvas.restore();
  }

  void spine() {
    var join = left + size.width;
    canvas.drawRect(
      Rect.fromLTWH(
          join - size.width * 0.003, 0, size.width * 0.006, size.height),
      Paint()..color = const Color(0x22000000),
    );
  }

  void spread((int?, int?)? pair) {
    if (pair == null) return;
    if (pair.$1 case var l?) leaf(l, true);
    if (pair.$2 case var r?) leaf(r, false);
    if (pair.$1 != null && pair.$2 != null) spine();
  }

  var here = doc.spreadOf(place.scene);
  var next = place.changing ? doc.spreadOf(place.next) : null;

  // The spread after whatever is on screen, made ready before it is
  // needed -- see ProceduralCache.warm. The leaves on screen are asked for
  // as they are drawn, which keeps them the most recently used.
  if (backgrounds != null) {
    var last = [here?.$1, here?.$2, next?.$1, next?.$2]
        .whereType<int>()
        .fold(place.scene, math.max);
    for (var i = last + 1; i <= last + 2 && i < scenes.length; i++) {
      warmBackdrop(doc, i, backgrounds, images);
    }
  }

  if (!place.changing) {
    spread(here);
    return;
  }
  if (here == next) {
    spread(here);
    return;
  }

  var over = doc.transitionAfter(place.scene);
  var t = over.ease.apply(place.through.clamp(0.0, 1.0));

  if (over.kind == SceneTransitionKind.pageTurn && place.next > place.scene) {
    var turning = here?.$2;
    if (turning == null) {
      // Nothing on the right to turn: a left-hand leaf standing alone, which
      // only a cover in the middle of the book gives. The pages change as a
      // cut would rather than as a leaf that is not there.
      spread(t >= 0.5 ? next : here);
      return;
    }
    // The leaf on the left lies still until the turned one comes down on it.
    if (here?.$1 case var l?) leaf(l, true);
    var arrivingLeft = next?.$1;
    var arrivingRight = next?.$2;
    paintPageTurn(
      canvas,
      slot(false),
      t,
      front: () => leaf(turning, false),
      under: arrivingRight == null ? null : () => leaf(arrivingRight, false),
      back: arrivingLeft != null
          ? () => leaf(arrivingLeft, true)
          : () => _seenThrough(canvas, slot(false), () => leaf(turning, false)),
    );
    // No spine while it turns: drawn over the sheet, it is a line across a
    // page in the air.
    return;
  }

  // Everything else moves a spread as the one picture it is.
  paintTransition(
    canvas,
    Rect.fromLTWH(left, 0, size.width * 2, size.height),
    over,
    t,
    from: () => spread(here),
    to: () => spread(next),
  );
}

/// _drawCover paints the overlay's own shape over the join.
void _drawCover(ui.Canvas canvas, Rect page, SceneTransition over, double t) {
  var shape = overlayPath(over, page, t);
  var paint = Paint()..color = over.color;
  if (over.softness > 0) {
    // Outwards only, so a cover that has grown to the page stays solid: blur
    // it both ways and it eats its own edges, and the scene behind shows
    // through the very moment it is meant to be hidden.
    paint.maskFilter = ui.MaskFilter.blur(
        ui.BlurStyle.solid, page.shortestSide * over.softness * 0.06);
  }
  canvas.drawPath(shape, paint);
}

/// _blurThrough goes soft, changes, and comes back sharp.
void _blurThrough(ui.Canvas canvas, Rect page, SceneTransition over, double t,
    {required void Function() from, required void Function() to}) {
  // How far from sharp: nothing at either end, most in the middle, where the
  // change happens and is not seen.
  var away = (1 - (t * 2 - 1).abs()).clamp(0.0, 1.0);
  var sigma = math.max(0.1, page.shortestSide * 0.05 * away);

  canvas.saveLayer(
      page,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma, sigmaY: sigma, tileMode: ui.TileMode.decal));
  (t >= 0.5 ? to : from)();
  canvas.restore();

  // And a veil of the colour at its strongest in the middle, where the
  // colour has been given one to show.
  if (over.color.a > 0) {
    canvas.drawRect(page,
        Paint()..color = over.color.withValues(alpha: over.color.a * away));
  }
}

/// _away is how far a moving scene has left to travel.
Offset _away(SceneTransitionKind kind, Rect page, double left) =>
    switch (kind) {
      SceneTransitionKind.slideLeft ||
      SceneTransitionKind.pushLeft =>
        Offset(page.width * left, 0),
      SceneTransitionKind.slideRight ||
      SceneTransitionKind.pushRight =>
        Offset(-page.width * left, 0),
      SceneTransitionKind.slideUp ||
      SceneTransitionKind.pushUp =>
        Offset(0, page.height * left),
      _ => Offset(0, -page.height * left),
    };

/// _wipe is the part of the page the arriving scene has taken.
Rect _wipe(SceneTransitionKind kind, Rect page, double t) => switch (kind) {
      SceneTransitionKind.wipeLeft => Rect.fromLTWH(
          page.right - page.width * t, page.top, page.width * t, page.height),
      SceneTransitionKind.wipeRight =>
        Rect.fromLTWH(page.left, page.top, page.width * t, page.height),
      SceneTransitionKind.wipeUp => Rect.fromLTWH(page.left,
          page.bottom - page.height * t, page.width, page.height * t),
      _ => Rect.fromLTWH(page.left, page.top, page.width, page.height * t),
    };

void _faded(ui.Canvas canvas, Rect page, double alpha, void Function() draw) {
  if (alpha <= 0) return;
  if (alpha >= 1) {
    draw();
    return;
  }
  canvas.saveLayer(
      page, Paint()..color = Color.fromRGBO(0, 0, 0, alpha.clamp(0.0, 1.0)));
  draw();
  canvas.restore();
}

void _shifted(ui.Canvas canvas, Rect page, Offset by, void Function() draw) {
  canvas.save();
  canvas.translate(by.dx, by.dy);
  draw();
  canvas.restore();
}

void _scaled(ui.Canvas canvas, Rect page, double scale, double alpha,
    void Function() draw) {
  canvas.save();
  var centre = page.center;
  canvas.translate(centre.dx, centre.dy);
  canvas.scale(scale, scale);
  canvas.translate(-centre.dx, -centre.dy);
  _faded(canvas, page, alpha, draw);
  canvas.restore();
}
