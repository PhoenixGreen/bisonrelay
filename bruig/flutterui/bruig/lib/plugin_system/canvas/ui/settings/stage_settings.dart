import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/orbit_pad.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:flutter/material.dart';

// stage_settings.dart is a 3D stage's settings: its camera, its set and its
// light. Every choice that can be seen is a tile drawn from this stage --
// a shot is this stage through that camera, a floor this stage's floor
// made of that.

List<Widget> stageSettings(
  BuildContext context,
  CanvasController controller,
  StageElement e,
  SettingsWrite write,
  VoidCallback begin,
  VoidCallback commit,
) {
  void now(StageElement next) {
    begin();
    write(next);
    commit();
  }

  var camera = e.cameraAt(controller.frame);
  var animated = controller.document.isAnimated;
  var keyed = controller.hasCameraKey(e);
  var drawn = e.toJson().toString();
  void film(StageCamera next, {bool live = false}) {
    var filmed = controller.stageFilmed(e, next);
    if (live) {
      write(filmed);
    } else {
      now(filmed);
    }
  }

  return [
    section(e, "camera",
        icon: Icons.videocam_outlined,
        title: "Camera",
        summary: "${camera.lens.round()} mm · ${camera.distance.toStringAsFixed(1)} m"
            "${keyed ? " · keyed here" : ""}",
        initiallyOpen: true,
        children: [
          CanvasTiles<int>(
            label: "Shot",
            help: "A ready-made camera. Characters on the stage are seen "
                "through it -- placed, sized and turned by it.",
            columns: 4,
            previewHeight: 44,
            tiles: [
              for (var (i, shot) in cameraShots.indexed)
                CanvasTile(i, shot.name,
                    drawnFrom: "$drawn|$i",
                    paint: (canvas, size) => _stageTile(
                        canvas, size, e.copyWith(camera: shot.camera))),
            ],
            selected: (i) => _sameCamera(cameraShots[i].camera, camera),
            keyOf: (i) => "stageShot-${cameraShots[i].name}",
            onPick: (i) => film(cameraShots[i].camera),
          ),
          CanvasControlGroup(
              label: "Where it is",
              help: "Drag the globe to orbit the camera round the stage -- "
                  "across to go round, down to look from higher -- or hold "
                  "Option and drag on the stage itself. Orbit swings the "
                  "camera round the stage; Height raises it to look down; "
                  "Distance moves it nearer or further; Lens is wide at "
                  "24 mm and close at 85.",
              children: [
                CanvasOrbitPad(
                  key: const ValueKey("stageOrbitPad"),
                  turn: camera.yaw,
                  tilt: camera.pitch,
                  minTilt: -10,
                  maxTilt: 89,
                  rest: (0, 12),
                  tooltip: "Drag to orbit the camera: across to go round "
                      "the stage, down to look from higher. Double click "
                      "for the camera's start.",
                  onStart: begin,
                  onChanged: (t, k) =>
                      film(camera.copyWith(yaw: t, pitch: k), live: true),
                  onEnd: commit,
                ),
                CanvasStepper(
                  key: const ValueKey("stageYaw"),
                  label: "Orbit",
                  value: camera.yaw,
                  min: -360,
                  max: 360,
                  step: 15,
                  suffix: "°",
                  defaultValue: 0,
                  onChanged: (v) => film(camera.copyWith(yaw: v), live: true),
                  onCommit: commit,
                ),
                CanvasStepper(
                  key: const ValueKey("stagePitch"),
                  label: "Height",
                  value: camera.pitch,
                  min: -10,
                  max: 89,
                  step: 5,
                  suffix: "°",
                  defaultValue: 12,
                  onChanged: (v) => film(camera.copyWith(pitch: v), live: true),
                  onCommit: commit,
                ),
                CanvasStepper(
                  key: const ValueKey("stageDistance"),
                  label: "Distance",
                  value: camera.distance,
                  min: StageCamera.minDistance,
                  max: StageCamera.maxDistance,
                  step: 0.5,
                  decimals: 1,
                  suffix: " m",
                  defaultValue: 7,
                  onChanged: (v) =>
                      film(camera.copyWith(distance: v), live: true),
                  onCommit: commit,
                ),
                CanvasStepper(
                  key: const ValueKey("stageLens"),
                  label: "Lens",
                  value: camera.lens,
                  min: 12,
                  max: 200,
                  step: 5,
                  suffix: " mm",
                  defaultValue: 35,
                  onChanged: (v) => film(camera.copyWith(lens: v), live: true),
                  onCommit: commit,
                ),
              ]),
          CanvasControlGroup(
              label: "Camera moves",
              help: "Key the camera on one frame, change it on a later one, "
                  "and it moves between them -- a dolly in, a crane up, an "
                  "orbit round. Once it is keyed, every change of camera is "
                  "made on the frame being looked at.",
              children: [
                if (keyed)
                  CanvasTextButton(
                    key: const ValueKey("stageUnkey"),
                    icon: Icons.remove_circle_outline,
                    label: "Remove this key",
                    onPressed: () {
                      controller.beginInteraction();
                      controller.clearCameraKey(e);
                      controller.endInteraction();
                    },
                  )
                else
                  CanvasTextButton(
                    key: const ValueKey("stageKey"),
                    icon: Icons.add_circle_outline,
                    label: "Key the camera here",
                    onPressed: animated
                        ? () {
                            controller.beginInteraction();
                            controller.keyCamera(e);
                            controller.endInteraction();
                          }
                        : null,
                  ),
              ]),
        ]),
    section(e, "set",
        icon: Icons.foundation_outlined,
        title: "Set",
        summary: "${e.pattern.label} floor${e.wall ? " · back wall" : ""}",
        children: [
          CanvasTiles<FloorPattern>(
            label: "Floor",
            help: "What the floor is made of. Its colour is below.",
            columns: 5,
            previewHeight: 40,
            tiles: [
              for (var p in FloorPattern.values)
                CanvasTile(p, p.label,
                    drawnFrom: "$drawn|${p.name}",
                    paint: (canvas, size) =>
                        _stageTile(canvas, size, e.copyWith(pattern: p))),
            ],
            selected: (p) => e.pattern == p,
            keyOf: (p) => "stageFloor-${p.name}",
            onPick: (p) => now(e.copyWith(pattern: p)),
          ),
          CanvasControlGroup(
              label: "Colours and size",
              help: "The floor, the back wall and the sky behind; how far "
                  "the floor runs each way from the middle, in metres.",
              children: [
                CanvasColorButton(
                  label: "Floor",
                  color: e.floor,
                  onChanged: (c) => now(e.copyWith(floor: c)),
                ),
                CanvasColorButton(
                  label: "Wall",
                  color: e.wallColor,
                  onChanged: (c) => now(e.copyWith(wallColor: c)),
                ),
                CanvasColorButton(
                  label: "Sky",
                  color: e.sky,
                  onChanged: (c) => now(e.copyWith(sky: c)),
                ),
                CanvasToggle(
                  key: const ValueKey("stageWall"),
                  label: "Back wall",
                  value: e.wall,
                  onChanged: (v) => now(e.copyWith(wall: v)),
                ),
                CanvasStepper(
                  key: const ValueKey("stageSize"),
                  label: "Floor size",
                  value: e.size,
                  min: 1,
                  max: 50,
                  suffix: " m",
                  defaultValue: 6,
                  onChanged: (v) => write(e.copyWith(size: v)),
                  onCommit: commit,
                ),
              ]),
        ]),
    section(e, "light",
        icon: Icons.wb_sunny_outlined,
        title: "Light",
        summary: e.light.label,
        children: [
          CanvasTiles<StageLight>(
            label: "Light",
            help: "How the stage is lit: a colour laid over it and everyone "
                "on it, and which way their shadows fall.",
            columns: 3,
            previewHeight: 40,
            tiles: [
              for (var l in StageLight.values)
                CanvasTile(l, l.label,
                    drawnFrom: "$drawn|${l.name}",
                    paint: (canvas, size) =>
                        _stageTile(canvas, size, e.copyWith(light: l))),
            ],
            selected: (l) => e.light == l,
            keyOf: (l) => "stageLight-${l.name}",
            onPick: (l) => now(e.copyWith(light: l)),
          ),
        ]),
  ];
}

bool _sameCamera(StageCamera a, StageCamera b) =>
    (a.yaw - b.yaw).abs() < 0.5 &&
    (a.pitch - b.pitch).abs() < 0.5 &&
    (a.distance - b.distance).abs() < 0.05 &&
    (a.lens - b.lens).abs() < 0.5;

/// _stageTile draws [stage] filling the tile, at its first frame.
void _stageTile(ui.Canvas canvas, Size size, StageElement stage) {
  paintStage(canvas, Offset.zero & size, stage, 0);
}
