import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_camera.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

// stage_scene.dart is a 3D stage's set drawn by Flutter GPU: its floor, laid
// with what it is made of, and its back wall with a skirting board, in a
// scene of their own seen through the stage's camera. The sky behind and
// the light's colour over everything are laid on the canvas, as they are
// over the flats and characters standing on the stage, so all of it is lit
// alike.
//
// The floor and the wall are drawn in the colours picked for them, as they
// are picked: unlit, rather than shaded by a light that would make the
// colour on the stage another colour than the one in its settings.

/// CanvasStageSource keeps the stages drawn on a canvas in 3D, one scene for
/// each, as CanvasCharacterSource keeps the characters.
abstract interface class CanvasStageSource {
  /// resolveStage is [stage]'s set, or null while 3D is being found out or
  /// where it cannot be drawn. The source tells its listeners when there
  /// is more to draw.
  StageScene? resolveStage(StageElement stage);
}

/// StageScene is one stage's set, in its own scene.
class StageScene {
  final Scene scene = Scene();

  bool _disposed = false;

  /// dispose lets go of the scene's GPU memory; it draws nothing after.
  void dispose() {
    _disposed = true;
    scene.dispose();
  }

  final PerspectiveCamera _camera =
      PerspectiveCamera(fovNear: 0.05, fovFar: 500);

  StageScene() {
    // Every frame drawn, rather than the last held while the GPU catches
    // up: an export draws each once, and must have it.
    scene.maxGpuFramesInFlight = 0;
  }

  /// _built is what the set was last built from; _set holds it.
  String? _built;
  Node? _set;

  /// show builds [stage]'s set, where it has changed.
  void show(StageElement stage) {
    final key = [
      stage.floor.toARGB32(),
      stage.pattern.name,
      stage.size,
      stage.wall,
      stage.wallColor.toARGB32(),
    ].join(";");
    if (key == _built) return;
    _built = key;
    if (_set case final old?) scene.remove(old);
    final s = stage.size;
    final set = Node(name: "set");
    // The floor, 2s across each way, its pattern a texture over the whole.
    final (floorPx, fw, fh) = floorTexture(stage);
    final floor =
        UnlitMaterial(colorTexture: Texture2D.fromPixels(floorPx, fw, fh))
          ..doubleSided = true;
    set.add(Node(
        name: "floor",
        mesh: Mesh(PlaneGeometry(width: 2 * s, depth: 2 * s), floor)));
    if (stage.wall) {
      // The back wall, three metres high at the far edge of the floor, stood
      // up from a plane lying flat, its skirting board in its texture.
      final (wallPx, ww, wh) = wallTexture(stage.wallColor.toARGB32());
      final wall =
          UnlitMaterial(colorTexture: Texture2D.fromPixels(wallPx, ww, wh))
            ..doubleSided = true;
      set.add(Node(
          name: "wall",
          localTransform: vm.Matrix4.translationValues(0, 1.5, -s) *
              vm.Matrix4.rotationX(math.pi / 2),
          mesh: Mesh(PlaneGeometry(width: 2 * s, depth: 3), wall)));
    }
    scene.add(set);
    _set = set;
  }

  /// paint draws [stage]'s set as its camera sees it on [frame], filling
  /// [box], with [pixelRatio] pixels to each of the canvas's points.
  void paint(ui.Canvas canvas, ui.Rect box, StageElement stage, int frame,
      {double pixelRatio = 1}) {
    // Let go of (see dispose), it draws nothing.
    if (_disposed) return;
    if (box.width < 1 || box.height < 1) return;
    show(stage);
    final view = StageView(box, stage.cameraAt(frame));
    // The stage's metres in the scene's: across mirrored, since the scene
    // sees its own left where the stage sees its right. See
    // CharacterScene.paintOnStage.
    vm.Vector3 toScene((double, double, double) v) =>
        vm.Vector3(-v.$1, v.$2, v.$3);
    _camera
      ..fovRadiansY = view.fovY
      ..position = toScene(view.eye)
      ..target = toScene(view.target);
    canvas
      ..save()
      ..clipRect(box)
      ..drawRect(box, ui.Paint()..color = stage.sky);
    scene.update(0);
    scene.render(_camera, canvas, viewport: box, pixelRatio: pixelRatio);
    canvas.restore();
  }
}

/// floorTexture is [stage]'s floor, its colour and what it is made of, as
/// RGBA pixels and their width and height: the whole floor, from its far
/// left corner.
(Uint8List, int, int) floorTexture(StageElement stage) {
  final s = stage.size;
  // As many pixels to a metre as keep it under 1024 across: quick enough
  // to make again as its colour is dragged.
  final perMetre = (1024 / (2 * s)).clamp(8.0, 64.0);
  final n = (2 * s * perMetre).round().clamp(16, 1024);
  final px = Uint8List(n * n * 4);
  final c = stage.floor.toARGB32();
  final (r, g, b) = ((c >> 16) & 0xff, (c >> 8) & 0xff, c & 0xff);
  // A shade 14% darker, for the lines and the darker tiles.
  int dark(int v) => (v * 0.86).round();
  void put(int x, int y, bool shaded) {
    if (x < 0 || y < 0 || x >= n || y >= n) return;
    final i = (y * n + x) * 4;
    px[i] = shaded ? dark(r) : r;
    px[i + 1] = shaded ? dark(g) : g;
    px[i + 2] = shaded ? dark(b) : b;
    px[i + 3] = 255;
  }

  // Metres from the floor's corner, for each pixel.
  double m(int p) => p / perMetre;
  final line = math.max(1, (perMetre * 0.02).round());
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final mx = m(x), my = m(y);
      final shaded = switch (stage.pattern) {
        FloorPattern.plain || FloorPattern.grass => false,
        FloorPattern.grid =>
          (x % perMetre.round()) < line || (y % perMetre.round()) < line,
        FloorPattern.tiles => (mx.floor() + my.floor()).isOdd,
        // Boards 0.3 m wide running away from the camera's start, their
        // ends staggered.
        FloorPattern.boards => () {
            final board = (mx / 0.3).floor();
            final across = (mx - board * 0.3) * perMetre;
            final along = ((my + (board % 3) * 0.7) % 2.1) * perMetre;
            return across < line || along < line;
          }(),
      };
      put(x, y, shaded);
    }
  }
  if (stage.pattern == FloorPattern.grass) {
    // Blades scattered by a fixed rule, so the same stage has the same
    // grass in every frame and every export.
    final count = (s * s * 400).round().clamp(500, 60000);
    for (var k = 0; k < count; k++) {
      final x = (_unit(k * 2) * n).floor(), y = (_unit(k * 2 + 1) * n).floor();
      for (var d = 0; d < math.max(2, perMetre ~/ 12); d++) {
        put(x, y - d, true);
      }
    }
  }
  return (px, n, n);
}

/// wallTexture is a wall of colour [argb], three metres high, with its
/// skirting board along the bottom twelve centimetres: as RGBA pixels and
/// their width and height, top first -- as the wall's plane is stood up.
(Uint8List, int, int) wallTexture(int argb) {
  const w = 4, h = 300;
  final px = Uint8List(w * h * 4);
  final (r, g, b) = ((argb >> 16) & 0xff, (argb >> 8) & 0xff, argb & 0xff);
  for (var y = 0; y < h; y++) {
    // Darker towards the floor, and darker still on the skirting board.
    final skirt = y >= h - 12;
    final k = skirt ? 0.78 : 1 - 0.08 * (y / h);
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      px[i] = (r * k).round();
      px[i + 1] = (g * k).round();
      px[i + 2] = (b * k).round();
      px[i + 3] = 255;
    }
  }
  return (px, w, h);
}

double _unit(int n) {
  var h = (n * 0x9E3779B1) & 0xFFFFFFFF;
  h = ((h ^ (h >> 16)) * 0x85EBCA6B) & 0xFFFFFFFF;
  h = ((h ^ (h >> 13)) * 0xC2B2AE35) & 0xFFFFFFFF;
  return (h ^ (h >> 16)) / 0xFFFFFFFF;
}
