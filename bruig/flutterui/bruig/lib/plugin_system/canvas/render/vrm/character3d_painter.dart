import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/render/image_store.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_character.dart';
import 'package:flutter/painting.dart';

// character3d_painter.dart draws a 3D character on the canvas: its scene,
// kept by the picture store (image_store.dart) as pictures are, drawn by
// Flutter GPU into the element's box. Until it is there -- and wherever 3D
// cannot be drawn, as in tests -- a figure stands in for it.

/// CanvasCharacterSource keeps the 3D characters drawn on a canvas, one
/// scene for each element, as CanvasImageSource keeps its pictures.
abstract interface class CanvasCharacterSource {
  /// resolveCharacter3d is [e]'s character, or null while it is loading, or
  /// where 3D cannot be drawn. Asking starts it loading; the source tells
  /// its listeners when there is more to draw.
  CharacterScene? resolveCharacter3d(Character3dElement e);

  /// noCharacters3d is whether this app cannot draw in 3D at all.
  bool get noCharacters3d;
}

/// paintCharacter3d draws [e] into [box] at [frame]: or, [staged] on a 3D
/// stage, where the stage's camera sees it, [box] being where that is.
void paintCharacter3d(
    ui.Canvas canvas, Rect box, Character3dElement e, int frame,
    {int frameRate = 12,
    CanvasImageSource? images,
    bool editing = false,
    Staged? staged}) {
  final source =
      images is CanvasCharacterSource ? images as CanvasCharacterSource : null;
  final scene = source?.resolveCharacter3d(e);
  if (scene == null || scene.avatar == null) {
    _standIn(canvas, box, e,
        editing: editing,
        says: source == null || source.noCharacters3d
            ? "3D characters are drawn in the app"
            : scene?.error ?? "Drawing ${e.design.name}…");
    return;
  }
  // As many pixels as the box covers: the canvas's own scale -- zoomed on
  // the stage, scaled up in an export -- and the screen's.
  final m = canvas.getTransform();
  final scale = math.sqrt(m[0] * m[0] + m[1] * m[1]);
  final screen = editing
      ? ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1
      : 1.0;
  final most = 4096 / math.max(box.width, box.height);
  scene
    ..expression = e.expression
    ..performance = e.performance;
  if (staged != null) {
    // The whole stage is drawn through, so the character lands where its
    // camera puts it.
    final view = staged.view, stage = view.box;
    final most = 4096 / math.max(stage.width, stage.height);
    scene.paintOnStage(canvas, stage,
        eye: view.eye,
        target: view.target,
        fovY: view.fovY,
        x: staged.spot.x,
        z: staged.spot.z,
        lift: staged.spot.lift,
        facing: staged.spot.facing,
        shadows: staged.stage.light.shadows,
        frame: frame,
        frameRate: frameRate,
        pixelRatio: (scale * screen).clamp(0.25, math.max(0.25, most)));
    return;
  }
  scene.paint(canvas, box,
      frame: frame,
      frameRate: frameRate,
      framing: e.framing,
      turn: e.turn,
      tilt: e.tilt,
      zoom: e.zoom,
      pixelRatio: (scale * screen).clamp(0.25, math.max(0.25, most)));
}

/// _standIn is a figure where the character will be, so it can be found and
/// picked: dashed round on the stage, with what is happening said under it.
void _standIn(ui.Canvas canvas, Rect box, Character3dElement e,
    {required bool editing, required String says}) {
  final ink = Paint()
    ..color = const Color(0x99888888)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  if (editing) {
    final r = RRect.fromRectAndRadius(box.deflate(1), const Radius.circular(6));
    for (final m in (Path()..addRRect(r)).computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 10) {
        canvas.drawPath(m.extractPath(d, d + 5), ink);
      }
    }
  }
  // A head and a body, as tall as the box allows.
  final fill = Paint()..color = const Color(0x33888888);
  final tall = math.min(box.height * 0.7, box.width * 1.6);
  final c = box.center;
  final head = tall * 0.13;
  final top = c.dy - tall / 2;
  canvas.drawCircle(Offset(c.dx, top + head), head, fill);
  canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(c.dx, top + head * 2.2 + tall * 0.36),
              width: tall * 0.3,
              height: tall * 0.72),
          Radius.circular(tall * 0.08)),
      fill);
  if (!editing) return;
  final p = (ui.ParagraphBuilder(ui.ParagraphStyle(
          textAlign: TextAlign.center, fontSize: 12, maxLines: 2))
        ..pushStyle(ui.TextStyle(color: const Color(0xCC888888)))
        ..addText(says))
      .build()
    ..layout(ui.ParagraphConstraints(width: math.max(40, box.width - 12)));
  canvas.drawParagraph(
      p,
      Offset(box.left + 6,
          math.min(box.bottom - p.height - 6, c.dy + tall / 2 + 6)));
}

/// loadDecalPicture reads a decal's picture or vector from the canvas
/// library as RGBA, no more than 1024 pixels across, with its width and
/// height; null where it cannot be read.
Future<(Uint8List, int, int)?> loadDecalPicture(String source) async {
  final id = source.substring(source.indexOf(':') + 1);
  final store = CanvasImageStore();
  try {
    var image = store.resolve(id, const BackgroundRemoval());
    // Waited for by looking, not by listening: the store says a picture has
    // come before it stops counting it as loading, and says nothing of one it
    // could not read.
    for (var waited = 0;
        image == null && store.loading && waited < 1000;
        waited++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      image = store.resolve(id, const BackgroundRemoval());
    }
    if (image == null) return null;
    // Large pictures drawn smaller first: a decal is never that big on
    // screen.
    final k = math.min(1.0, 1024 / math.max(image.width, image.height));
    var drawn = image;
    if (k < 1) {
      final w = (image.width * k).round(), h = (image.height * k).round();
      final rec = ui.PictureRecorder();
      ui.Canvas(rec).drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          Paint()..filterQuality = FilterQuality.medium);
      drawn = await rec.endRecording().toImage(w, h);
    }
    final (w, h) = (drawn.width, drawn.height);
    final bytes =
        await drawn.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    if (!identical(drawn, image)) drawn.dispose();
    if (bytes == null) return null;
    return (Uint8List.sublistView(bytes), w, h);
  } finally {
    // The pictures it read go with it.
    store.dispose();
  }
}
