import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/render/procedural_cache.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
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
    var last = i == scenes.length - 1;
    var (over, held, runs) = sceneStep(doc, i);
    var local = want - start;

    if (last) {
      return SequencePlace(
          scene: i, frame: math.min(math.max(0, local), scene.frames - 1));
    }

    // Inside the frames the two scenes share.
    if (held > 0 && local >= scene.frames - held && local < scene.frames) {
      var into = local - (scene.frames - held);
      return SequencePlace(
        scene: i,
        frame: local,
        next: i + 1,
        nextFrame: into,
        through: (into + 1) / held,
      );
    }

    // Or inside a transition that runs between them rather than across them:
    // the scene leaving is held on its last frame and the one arriving has
    // not started.
    if (held == 0 &&
        runs > 0 &&
        local >= scene.frames &&
        local < scene.frames + runs) {
      var into = local - scene.frames;
      return SequencePlace(
        scene: i,
        frame: scene.frames - 1,
        next: i + 1,
        nextFrame: 0,
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

/// sceneStep is how a scene fits into the run: how far the sequence moves on
/// before the next one starts, how many frames the two share, and how long a
/// transition between them runs for.
///
/// One answer, asked by the length of the document, by where each scene
/// starts and by what is drawn at a given moment -- three places that must
/// not be able to disagree.
(int, int, int) sceneStep(CanvasDocument doc, int index) {
  var scenes = doc.allScenes;
  if (index < 0 || index >= scenes.length) return (0, 0, 0);
  var scene = scenes[index];
  if (index == scenes.length - 1) return (scene.frames, 0, 0);

  var over = doc.transitionAfter(index);
  if (!over.on) return (scene.frames, 0, 0);

  var held =
      math.min(over.overlap, math.min(scene.frames, scenes[index + 1].frames));
  // Overlapping, the next scene starts before this one ends. Not
  // overlapping, the transition is its own stretch of time between them.
  return (
    scene.frames - held + (held == 0 ? over.frames : 0),
    held,
    over.frames
  );
}

/// paintSequenceFrame draws the whole document at one moment of its run.
void paintSequenceFrame(
  ui.Canvas canvas,
  CanvasDocument doc,
  int at, {
  CanvasImageSource? images,
  ProceduralCache? backgrounds,
}) {
  var place = placeInSequence(doc, at);
  var scenes = doc.allScenes;
  if (scenes.isEmpty) return;

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
        backgrounds: backgrounds);
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

    // The overlay family: the change happens under something rather than
    // between the two scenes. See SceneTransitionKind.band and the rest.
    case SceneTransitionKind.band:
      // The scenes swap behind the band, at the moment it covers the page.
      (t >= 0.5 ? to : from)();
      _paintBand(canvas, page, over, t);

    case SceneTransitionKind.blinds:
      from();
      _through(canvas, page, _blindsPath(page, over, t), over.softness, to);

    case SceneTransitionKind.barn:
      // The new scene is behind, and the old one is pulled apart to let it
      // through -- so what moves is the thing being left rather than the
      // thing arriving.
      to();
      _barnDoors(canvas, page, over, t, from);

    case SceneTransitionKind.shapeWipe:
      from();
      _through(canvas, page, _shapeOpening(page, over, t), over.softness, to);

    case SceneTransitionKind.clock:
      from();
      _through(canvas, page, _clockSweep(page, t), over.softness, to);

    case SceneTransitionKind.blurThrough:
      _blurThrough(canvas, page, over, t, from: from, to: to);

    // The drawn family. Each is a mask made of shapes, and the two that put
    // paint on the page draw the paint over the join as well -- what a
    // splatter looks like is paint landing, not a hole opening.
    case SceneTransitionKind.arrow:
      from();
      _through(canvas, page, _arrowPath(page, over, t), over.softness, to);

    case SceneTransitionKind.splatter:
      from();
      _paintOver(canvas, page, over, _splatterPath(page, over, t), t);
      _through(canvas, page, _splatterPath(page, over, t), over.softness, to);

    case SceneTransitionKind.brush:
      from();
      _paintOver(canvas, page, over, _brushPath(page, over, t), t);
      _through(canvas, page, _brushPath(page, over, t), over.softness, to);

    case SceneTransitionKind.tiles:
      from();
      _through(canvas, page, _tilesPath(page, over, t), over.softness, to);

    case SceneTransitionKind.halftone:
      from();
      _through(canvas, page, _halftonePath(page, over, t), over.softness, to);

    case SceneTransitionKind.burst:
      from();
      _through(canvas, page, _burstPath(page, over, t), over.softness, to);
  }
}

/// _through draws [what] through [mask], softly where softness has been asked
/// for.
///
/// A clip where the edge is meant to be hard, and a blurred stencil where it
/// is not: a clip path cannot be feathered, so a soft edge is the scene drawn
/// into a layer and then cut back with a blurred copy of the same shape.
void _through(ui.Canvas canvas, Rect page, ui.Path mask, double softness,
    void Function() what) {
  if (softness <= 0) {
    canvas.save();
    canvas.clipPath(mask);
    what();
    canvas.restore();
    return;
  }

  // The stencil first, then the scene kept only where the stencil is: drawn
  // the other way round -- scene first, then the mask with dstIn -- the parts
  // of the layer the mask never touched were left alone rather than cut away,
  // so an empty mask kept the whole scene and the arriving canvas was there
  // from the first frame.
  canvas.saveLayer(page, Paint());
  canvas.drawPath(
      mask,
      Paint()
        ..color = const Color(0xFF000000)
        // Solid rather than normal: the shape stays as it is and the blur
        // spreads outwards from it. Blurred both ways, the mask ate into its
        // own edges -- so a mask that had grown to cover the page still lost
        // a soft band all round it, and the scene arriving never quite
        // arrived.
        ..maskFilter = ui.MaskFilter.blur(
            ui.BlurStyle.solid, page.shortestSide * softness * 0.08));
  canvas.saveLayer(page, Paint()..blendMode = ui.BlendMode.srcIn);
  what();
  canvas.restore();
  canvas.restore();
}

/// _paintOver draws the mask itself in the transition's colour, so a splatter
/// looks like paint landing rather than like a hole opening.
///
/// Strongest as it lands and gone by the end, which is what leaves the scene
/// arriving clean.
void _paintOver(
    ui.Canvas canvas, Rect page, SceneTransition over, ui.Path mask, double t) {
  var strength = (1 - t) * 0.85;
  if (strength <= 0.01 || over.color.a <= 0) return;
  canvas.drawPath(
      mask,
      Paint()
        ..color = over.color.withValues(alpha: over.color.a * strength)
        ..maskFilter =
            ui.MaskFilter.blur(ui.BlurStyle.normal, page.shortestSide * 0.01));
}

/// _arrowPath is an arrowhead driving across the page.
ui.Path _arrowPath(Rect page, SceneTransition over, double t) {
  var across = over.way.horizontal ? page.width : page.height;
  // The head starts off one edge and leaves by the other, and the tail fills
  // in behind it -- so what is revealed is everything the arrow has passed.
  var deep = (over.way.horizontal ? page.height : page.width) * 0.55;
  // Off the page to begin with: the head has to arrive from outside, or the
  // arrow is already through the edge of the picture on the first frame.
  var reach = across * (t * 1.7) - deep;

  var path = ui.Path();
  switch (over.way) {
    case SceneTransitionWay.right:
      path.moveTo(page.left - deep, page.top);
      path.lineTo(page.left + reach, page.top);
      path.lineTo(page.left + reach + deep, page.center.dy);
      path.lineTo(page.left + reach, page.bottom);
      path.lineTo(page.left - deep, page.bottom);
    case SceneTransitionWay.left:
      path.moveTo(page.right + deep, page.top);
      path.lineTo(page.right - reach, page.top);
      path.lineTo(page.right - reach - deep, page.center.dy);
      path.lineTo(page.right - reach, page.bottom);
      path.lineTo(page.right + deep, page.bottom);
    case SceneTransitionWay.down:
      path.moveTo(page.left, page.top - deep);
      path.lineTo(page.left, page.top + reach);
      path.lineTo(page.center.dx, page.top + reach + deep);
      path.lineTo(page.right, page.top + reach);
      path.lineTo(page.right, page.top - deep);
    case SceneTransitionWay.up:
      path.moveTo(page.left, page.bottom + deep);
      path.lineTo(page.left, page.bottom - reach);
      path.lineTo(page.center.dx, page.bottom - reach - deep);
      path.lineTo(page.right, page.bottom - reach);
      path.lineTo(page.right, page.bottom + deep);
  }
  return path..close();
}

/// _splatterPath is paint thrown at the page: blobs that land in an order of
/// their own and grow until they meet.
ui.Path _splatterPath(Rect page, SceneTransition over, double t) {
  var path = ui.Path();
  var blobs = over.count.clamp(2, 40);
  var random = math.Random(over.kind.seed + blobs);
  var reach = page.longestSide;

  for (var i = 0; i < blobs; i++) {
    // Where it lands and when, both decided once from a seed of the
    // transition's own -- a splatter that consulted a fresh random number
    // would land somewhere else on every frame of an export.
    var at = Offset(page.left + random.nextDouble() * page.width,
        page.top + random.nextDouble() * page.height);
    var lands = random.nextDouble() * 0.6;
    var grown = ((t - lands) / (1 - lands)).clamp(0.0, 1.0);
    if (grown <= 0) continue;

    // Ragged rather than round: a blob with a few arms reads as paint, and a
    // circle reads as a hole.
    var size = reach * 0.16 * grown * (0.6 + random.nextDouble() * 0.8);
    var arms = 7 + random.nextInt(4);
    for (var a = 0; a < arms; a++) {
      var angle = a / arms * 2 * math.pi;
      var out = size * (0.55 + random.nextDouble() * 0.7);
      var spot = at + Offset(math.cos(angle) * out, math.sin(angle) * out);
      path.addOval(Rect.fromCircle(center: spot, radius: size * 0.42));
    }
    path.addOval(Rect.fromCircle(center: at, radius: size * 0.8));
  }
  // And the whole page at the end, so nothing of the old scene is left in the
  // gaps between the blobs.
  if (t > 0.92) {
    var over92 = (t - 0.92) / 0.08;
    path.addRect(Rect.fromCenter(
        center: page.center,
        width: page.width * over92 * 1.2,
        height: page.height * over92 * 1.2));
  }
  return path;
}

/// _brushPath is strokes dragged across the page, one after another.
ui.Path _brushPath(Rect page, SceneTransition over, double t) {
  var path = ui.Path();
  var strokes = over.count.clamp(2, 40);
  var horizontal = over.way.horizontal;
  var thick = (horizontal ? page.height : page.width) / strokes;
  var random = math.Random(over.kind.seed + strokes);

  for (var i = 0; i < strokes; i++) {
    // Each stroke starts a little after the one before it, so the page is
    // painted rather than covered all at once.
    var starts = i / strokes * 0.45;
    var run = ((t - starts) / (1 - starts)).clamp(0.0, 1.0);
    if (run <= 0) continue;

    var along = (horizontal ? page.width : page.height) * run * 1.15;
    var at = (horizontal ? page.top : page.left) + thick * i;
    // A stroke is not a rectangle: it is thickest in the middle and its ends
    // are rounded, which is what the extra ovals are for.
    var body = horizontal
        ? Rect.fromLTWH(
            over.way == SceneTransitionWay.right
                ? page.left
                : page.right - along,
            at + thick * 0.08,
            along,
            thick * 0.84)
        : Rect.fromLTWH(
            at + thick * 0.08,
            over.way == SceneTransitionWay.down
                ? page.top
                : page.bottom - along,
            thick * 0.84,
            along);
    path.addRRect(RRect.fromRectAndRadius(body, Radius.circular(thick * 0.42)));

    // A little wander at the leading end, so no two strokes end level.
    var wobble = thick * (random.nextDouble() * 0.5 - 0.25);
    path.addOval(Rect.fromCircle(
        center: horizontal
            ? Offset(
                over.way == SceneTransitionWay.right ? body.right : body.left,
                body.center.dy + wobble)
            : Offset(body.center.dx + wobble,
                over.way == SceneTransitionWay.down ? body.bottom : body.top),
        radius: thick * 0.5));
  }

  // And the page itself at the very end. Strokes leave gaps at their edges by
  // construction -- that is what makes them strokes -- and a transition that
  // ended with a few of them showing would be a transition that never
  // finished.
  if (t > 0.9) {
    var last = (t - 0.9) / 0.1;
    path.addRect(Rect.fromCenter(
        center: page.center,
        width: page.width * last * 1.2,
        height: page.height * last * 1.2));
  }
  return path;
}

/// _tilesPath breaks the page into squares that arrive in a wave.
ui.Path _tilesPath(Rect page, SceneTransition over, double t) {
  var path = ui.Path();
  var across = over.count.clamp(2, 40);
  var wide = page.width / across;
  var down = math.max(1, (page.height / math.max(1.0, wide)).round());
  var tall = page.height / down;

  for (var x = 0; x < across; x++) {
    for (var y = 0; y < down; y++) {
      // The wave runs the way the transition points, with a little of the
      // other axis mixed in so the edge is a diagonal rather than a line.
      var along = switch (over.way) {
        SceneTransitionWay.right => x / across,
        SceneTransitionWay.left => 1 - x / across,
        SceneTransitionWay.down => y / down,
        SceneTransitionWay.up => 1 - y / down,
      };
      var lean = (over.way.horizontal ? y / down : x / across) * 0.25;
      var starts = (along * 0.7 + lean).clamp(0.0, 0.95);
      var grown = ((t - starts) / (1 - starts)).clamp(0.0, 1.0);
      if (grown <= 0) continue;

      // Each tile grows from its own middle, which is what makes it read as
      // turning over rather than as a square being uncovered.
      var box =
          Rect.fromLTWH(page.left + wide * x, page.top + tall * y, wide, tall);
      path.addRect(Rect.fromCenter(
          center: box.center,
          width: box.width * grown,
          height: box.height * grown));
    }
  }
  return path;
}

/// _halftonePath grows a comic's dots until they meet and the page is full.
ui.Path _halftonePath(Rect page, SceneTransition over, double t) {
  var path = ui.Path();
  var across = over.count.clamp(2, 40);
  var step = page.width / across;
  var rows = math.max(1, (page.height / step).ceil()) + 1;

  // Big enough at the end to close every gap between the dots, which is what
  // takes a halftone from a pattern to a full page.
  var reach = step * 0.72 * (t * 1.45);
  for (var y = 0; y < rows; y++) {
    for (var x = -1; x <= across; x++) {
      // Every other row half a step over, the way a printed halftone is.
      var at = Offset(
          page.left + step * (x + (y.isEven ? 0 : 0.5)), page.top + step * y);
      // Later towards the far corner, so the dots come in as a wave rather
      // than all at once.
      var away = (at - page.topLeft).distance / page.longestSide;
      var grown = reach * (1.35 - away * 0.7);
      if (grown <= 0) continue;
      path.addOval(Rect.fromCircle(center: at, radius: grown));
    }
  }
  return path;
}

/// _burstPath throws speed lines out of the middle.
ui.Path _burstPath(Rect page, SceneTransition over, double t) {
  var path = ui.Path();
  var rays = over.count.clamp(2, 40);
  var reach = page.longestSide * t * 1.2;
  if (reach <= 0) return path;
  var random = math.Random(over.kind.seed + rays);

  for (var i = 0; i < rays; i++) {
    var angle = i / rays * 2 * math.pi;
    // Each ray a different width, so it reads as drawn rather than as a pie
    // chart -- and the widths are fixed by the seed, not by the frame.
    var spread = (math.pi / rays) * (0.55 + random.nextDouble() * 0.9);
    path.moveTo(page.center.dx, page.center.dy);
    path.lineTo(page.center.dx + math.cos(angle - spread) * reach,
        page.center.dy + math.sin(angle - spread) * reach);
    path.lineTo(page.center.dx + math.cos(angle + spread) * reach,
        page.center.dy + math.sin(angle + spread) * reach);
    path.close();
  }
  // And the middle fills in behind them.
  path.addOval(Rect.fromCircle(center: page.center, radius: reach * 0.55));
  return path;
}

/// _paintBand draws a panel of colour crossing the page.
///
/// Sized to the page and travelling two page widths, so it covers everything
/// exactly at the half way point -- which is where the scenes change behind
/// it, and why the change is not seen.
void _paintBand(ui.Canvas canvas, Rect page, SceneTransition over, double t) {
  var along = over.way.horizontal ? page.width : page.height;
  var travel = (t * 2 - 1) * along;

  var band = over.way.horizontal
      ? Rect.fromLTWH(
          page.left + (over.way == SceneTransitionWay.right ? travel : -travel),
          page.top,
          page.width,
          page.height)
      : Rect.fromLTWH(
          page.left,
          page.top + (over.way == SceneTransitionWay.down ? travel : -travel),
          page.width,
          page.height);

  var paint = Paint()..color = over.color;
  // A feathered leading edge, where one has been asked for: a band with a
  // little softness reads as a light sweeping across rather than as a
  // rectangle being dragged over the page.
  if (over.softness > 0) {
    var soft = (over.softness * 0.5).clamp(0.0, 0.5);
    paint.shader = ui.Gradient.linear(
      over.way.horizontal ? band.centerLeft : band.topCenter,
      over.way.horizontal ? band.centerRight : band.bottomCenter,
      [
        over.color.withValues(alpha: 0),
        over.color,
        over.color,
        over.color.withValues(alpha: 0),
      ],
      [0, soft, 1 - soft, 1],
    );
  }
  canvas.drawRect(band, paint);
}

/// _blindsPath is the part of the page the arriving scene has taken, as a set
/// of bars growing from one side.
ui.Path _blindsPath(Rect page, SceneTransition over, double t) {
  var path = ui.Path();
  var bars = over.count.clamp(2, 40);
  var horizontal = over.way.horizontal;
  var span = (horizontal ? page.height : page.width) / bars;

  for (var i = 0; i < bars; i++) {
    var at = (horizontal ? page.top : page.left) + span * i;
    var grown = (horizontal ? page.width : page.height) * t;
    path.addRect(horizontal
        ? Rect.fromLTWH(
            over.way == SceneTransitionWay.right
                ? page.left
                : page.right - grown,
            at,
            grown,
            span)
        : Rect.fromLTWH(
            at,
            over.way == SceneTransitionWay.down
                ? page.top
                : page.bottom - grown,
            span,
            grown));
  }
  return path;
}

/// _barnDoors draws the scene being left, split apart.
void _barnDoors(ui.Canvas canvas, Rect page, SceneTransition over, double t,
    void Function() draw) {
  var horizontal = over.way.horizontal;
  var half = horizontal ? page.width / 2 : page.height / 2;
  var open = half * t;

  for (var side in const [-1.0, 1.0]) {
    canvas.save();
    // Moved first and clipped after, so the clip travels with the door.
    // Clipped to a fixed half and then moved, the picture slid *inside* its
    // own clip and never left it -- the doors stayed shut however far they
    // had opened.
    canvas.translate(
        horizontal ? side * open : 0, horizontal ? 0 : side * open);
    canvas.clipRect(horizontal
        ? Rect.fromLTRB(side < 0 ? page.left : page.center.dx, page.top,
            side < 0 ? page.center.dx : page.right, page.bottom)
        : Rect.fromLTRB(page.left, side < 0 ? page.top : page.center.dy,
            page.right, side < 0 ? page.center.dy : page.bottom));
    draw();
    canvas.restore();
  }
}

/// _shapeOpening is the shape the arriving scene comes through.
///
/// Drawn by the same code an element's shape is -- see shapePath -- so a
/// transition cannot drift away from what the shapes on the canvas look like.
ui.Path _shapeOpening(Rect page, SceneTransition over, double t) {
  // Large enough at the end to cover the corners of the page, whatever shape
  // it is: a circle that stopped at the edges would leave the corners of the
  // scene it is replacing showing.
  var reach = math.sqrt(page.width * page.width + page.height * page.height);
  var size = reach * t * 1.05;
  var centre = page.center;
  return shapePath(
      over.shape, Rect.fromCenter(center: centre, width: size, height: size),
      points: 5);
}

/// _clockSweep is a sector of the page, swept from the top like a hand.
ui.Path _clockSweep(Rect page, double t) {
  if (t >= 1) return ui.Path()..addRect(page);
  var reach = math.sqrt(page.width * page.width + page.height * page.height);
  var box =
      Rect.fromCenter(center: page.center, width: reach * 2, height: reach * 2);
  return ui.Path()
    ..moveTo(page.center.dx, page.center.dy)
    ..arcTo(box, -math.pi / 2, 2 * math.pi * t, false)
    ..close();
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
