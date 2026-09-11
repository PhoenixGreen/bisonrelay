import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
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
      // Behind the cover, and swapped at the moment it is complete.
      (t >= 0.5 ? to : from)();
      _drawCover(canvas, page, over, t);

    case SceneTransitionKind.blurThrough:
      _blurThrough(canvas, page, over, t, from: from, to: to);
  }
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
