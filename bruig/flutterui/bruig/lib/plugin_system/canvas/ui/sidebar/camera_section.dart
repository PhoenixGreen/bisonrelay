import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';

// camera_section.dart is a scene's slow move: still, or a push in, a pull
// out, a drift across. See SceneCamera.

/// CameraMove is a named slow move, at a strength.
enum CameraMove {
  still("Still"),
  pushIn("Push in"),
  pullOut("Pull out"),
  driftLeft("Drift left"),
  driftRight("Drift right"),
  driftUp("Drift up");

  final String label;
  const CameraMove(this.label);

  /// camera is this move at [strength]: how far it zooms in, as a fraction
  /// -- 0.12 is twelve per cent closer.
  SceneCamera? camera(double strength) {
    var z = 1 + strength;
    var d = strength / 2;
    return switch (this) {
      still => null,
      pushIn => SceneCamera(fromZoom: 1, toZoom: z),
      pullOut => SceneCamera(fromZoom: z, toZoom: 1),
      driftLeft => SceneCamera(
          fromZoom: z, toZoom: z, fromX: 0.5 + d, toX: 0.5 - d),
      driftRight => SceneCamera(
          fromZoom: z, toZoom: z, fromX: 0.5 - d, toX: 0.5 + d),
      driftUp => SceneCamera(
          fromZoom: z, toZoom: z, fromY: 0.5 + d, toY: 0.5 - d),
    };
  }

  /// of is which move [c] is, as near as can be said.
  static CameraMove of(SceneCamera? c) {
    if (c == null) return still;
    if (c.toZoom > c.fromZoom + 0.001) return pushIn;
    if (c.fromZoom > c.toZoom + 0.001) return pullOut;
    if (c.toX < c.fromX) return driftLeft;
    if (c.toX > c.fromX) return driftRight;
    if (c.toY < c.fromY) return driftUp;
    return still;
  }

  /// strengthOf is how strong [c] is: how far it is zoomed beyond the page.
  static double strengthOf(SceneCamera? c) {
    if (c == null) return 0.12;
    var most = c.fromZoom > c.toZoom ? c.fromZoom : c.toZoom;
    return (most - 1).clamp(0.02, 1.0);
  }
}

/// CanvasCameraSection sets the slow move of the scene being edited.
class CanvasCameraSection extends StatelessWidget {
  final CanvasController controller;
  const CanvasCameraSection({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    var document = controller.document;
    var index = document.at;
    var camera = document.allScenes[index].camera;
    var move = CameraMove.of(camera);
    var strength = CameraMove.strengthOf(camera);
    return CanvasControlGroup(
      key: const ValueKey("camera"),
      label: "Camera",
      children: [
        CanvasDropdown<CameraMove>(
          key: const ValueKey("cameraMove"),
          label: "Over the ${document.kind.one}",
          value: move,
          width: 110,
          options: [for (var m in CameraMove.values) (m, m.label)],
          onChanged: (m) =>
              controller.setSceneCamera(index, m.camera(strength)),
        ),
        if (camera != null)
          CanvasNumberField(
            key: const ValueKey("cameraStrength"),
            label: "Closer by",
            value: strength * 100,
            min: 2,
            max: 100,
            suffix: "%",
            width: 58,
            onChanged: (v) =>
                controller.setSceneCamera(index, move.camera(v / 100)),
          ),
        const CanvasHint(
            "Seen as the scenes play and in the export. The page stays still "
            "while it is being edited."),
      ],
    );
  }
}
