import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/object3d_element.dart';
import 'package:bruig/plugin_system/canvas/render/model3d/model_scene.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_painter.dart';
import 'package:flutter/material.dart';

// model3d_painter.dart draws a 3D object: its model, from the store that
// keeps a scene for each, posed by what its clips play -- or, where 3D
// cannot be drawn here or it is still being read, a box saying so.

/// CanvasModelSource keeps the 3D objects' scenes.
abstract class CanvasModelSource {
  /// resolveModel is [e]'s model, or null while it is being read, where
  /// there is none, or where 3D cannot be drawn.
  ModelScene? resolveModel(Object3dElement e);

  /// noModels3d is whether this app cannot draw in 3D at all.
  bool get noModels3d;
}

/// paintObject3d draws [e] in [box], or on its stage where [staged] says
/// it stands, its animations where [plays] has them.
void paintObject3d(ui.Canvas canvas, Rect box, Object3dElement e, Object? images,
    {List<ModelPlay> plays = const [],
    bool editing = false,
    Staged? staged}) {
  var source = images is CanvasModelSource ? images : null;
  var scene = source?.resolveModel(e);
  if (scene == null || !scene.ready) {
    _standIn(canvas, box, e,
        says: e.assetId.isEmpty
            ? "Drag a model here from the 3D objects"
            : source == null || source.noModels3d
                ? "3D objects are drawn in the app"
                : scene?.error ?? "Reading ${e.name}…");
    return;
  }
  var m = canvas.getTransform();
  var scale = math.sqrt(m[0] * m[0] + m[1] * m[1]);
  var screen = editing
      ? ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1
      : 1.0;
  if (staged != null) {
    var view = staged.view, stage = view.box;
    var most = 4096 / math.max(stage.width, stage.height);
    scene.paintOnStage(canvas, stage,
        eye: view.eye,
        target: view.target,
        fovY: view.fovY,
        x: staged.spot.x,
        z: staged.spot.z,
        lift: staged.spot.lift,
        facing: staged.spot.facing,
        height: staged.spot.height,
        plays: plays,
        pixelRatio: (scale * screen).clamp(0.25, math.max(0.25, most)));
    return;
  }
  var most = 4096 / math.max(box.width, box.height);
  scene.paint(canvas, box,
      turn: e.turn,
      tilt: e.tilt,
      zoom: e.zoom,
      plays: plays,
      pixelRatio: (scale * screen).clamp(0.25, math.max(0.25, most)));
}

/// _standIn is a box drawn as a cube where the model will be, with what
/// is happening said under it: something to find and pick meanwhile.
void _standIn(ui.Canvas canvas, Rect box, Object3dElement e,
    {required String says}) {
  var ink = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1, box.shortestSide / 120)
    ..color = const Color(0x998A93A6);
  var s = box.shortestSide * 0.5;
  var c = box.center;
  var front = Rect.fromCenter(center: c + Offset(-s * 0.12, s * 0.12), width: s, height: s);
  var back = front.shift(Offset(s * 0.24, -s * 0.24));
  canvas.drawRect(front, ink);
  canvas.drawRect(back, ink);
  for (var (a, b) in [
    (front.topLeft, back.topLeft),
    (front.topRight, back.topRight),
    (front.bottomLeft, back.bottomLeft),
    (front.bottomRight, back.bottomRight),
  ]) {
    canvas.drawLine(a, b, ink);
  }
  var text = TextPainter(
    text: TextSpan(
        text: says,
        style: TextStyle(
            fontSize: math.max(9, box.shortestSide / 16),
            color: const Color(0xCC8A93A6))),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: box.width);
  text.paint(canvas,
      Offset(box.center.dx - text.width / 2, front.bottom + s * 0.08));
}
