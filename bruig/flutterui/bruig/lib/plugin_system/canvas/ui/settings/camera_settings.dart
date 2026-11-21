import 'package:flutter/material.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart' show MotionKind;
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart'
    show presetsFor;
import 'package:bruig/plugin_system/canvas/render/camera_aim.dart'
    show aimChoices;
import 'package:bruig/plugin_system/canvas/render/motion_document.dart'
    show cameraFraming, cameraLookAt, isStageScene, poseAimAt;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/motion/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart';

// camera_settings.dart is a 2D Camera's framing and lens: zoom, roll,
// focus, depth of field, parallax, vignette, motion blur. Focus, blur and
// vignette key with ◆, and once keyed a change keys the playhead (a focus
// pull); zoom and roll are the moving camera's pose, as a drag is.

List<Widget> cameraLensGroups(
    CanvasController controller,
    CameraElement e,
    void Function(CanvasElement) write,
    VoidCallback begin,
    VoidCallback commit) {
  var doc = controller.document;
  var frame = controller.frame;
  CameraElement now() => doc.elementById(e.id) is CameraElement
      ? controller.document.elementById(e.id) as CameraElement
      : e;
  var (zoom, _) = cameraFraming(e, frame, doc);
  var look = cameraLookAt(e, frame, doc);
  var track = e.track ?? ElementTrack.empty;

  /// keyed is whether [channel] has any keyframes.
  bool keyed(String channel) =>
      track.keys.any((k) => k.values.containsKey(channel));

  /// keyHere is a key for [channel] at the playhead, holding [v].
  CameraElement keyHere(CameraElement cam, String channel, double v) {
    var t = (cam.track ?? ElementTrack.empty).seededFor(frame);
    return cam.withBase(
            track: t.withKey(
                t.at(frame).copyWith(frame: frame).withValue(channel, v)))
        as CameraElement;
  }

  /// set writes [channel]: keyed at the playhead where it is keyed, else
  /// the setting itself by [rest].
  void set(
      String channel, double v, CameraElement Function(CameraElement) rest) {
    begin();
    var cam = now();
    write(keyed(channel) ? keyHere(cam, channel, v) : rest(cam));
  }

  /// keyButton keys [channel] at the playhead, holding [v]; lit where a key
  /// already stands.
  Widget keyButton(String channel, double v) => CanvasIconButton(
        key: ValueKey("cameraKey-$channel"),
        icon: Icons.diamond_outlined,
        tooltip: "Key it here: changed at the playhead from then on",
        active: track.keyAt(frame)?.values.containsKey(channel) ?? false,
        onPressed: () {
          begin();
          write(keyHere(now(), channel, v));
          commit();
        },
      );

  // How far it is turned to its aim here: keyed, or all the way.
  var aimMix =
      (track.keyAt(frame)?.values["aim"] ?? poseAimAt(e, frame, doc)) ?? 1.0;

  var others = [
    for (var x in doc.elements)
      if (x is! CameraElement) x,
  ];

  return [
    CanvasControlGroup(
        label: "Framing",
        help: "How close it is and how far it is turned, at the playhead: on "
            "a camera that moves, a key there.",
        children: [
          panelRow([
            cell(CanvasStepper(
              key: const ValueKey("cameraZoom"),
              label: "Zoom",
              value: zoom,
              min: 1,
              max: 8,
              decimals: 2,
              step: 0.25,
              dragStep: 0.01,
              defaultValue: 1,
              suffix: "×",
              width: 104,
              onChanged: (v) {
                begin();
                var cam = now();
                var (z, _) = cameraFraming(cam, frame, controller.document);
                write(controller.cameraZoomed(cam, v / z));
              },
              onCommit: commit,
            )),
            cell(CanvasStepper(
              key: const ValueKey("cameraRoll"),
              label: "Roll",
              value: look.roll,
              min: -180,
              max: 180,
              step: 5,
              dragStep: 0.5,
              decimals: 1,
              defaultValue: 0,
              suffix: "°",
              width: 104,
              onChanged: (v) {
                begin();
                var cam = now();
                if (!controller.posesRatherThanMoves(cam)) {
                  write(cam.withBase(rotation: v));
                  return;
                }
                var t = (cam.track ?? ElementTrack.empty).seededFor(frame);
                write(cam.withBase(
                    track: t.withKey(t
                        .at(frame)
                        .copyWith(frame: frame, rotate: v - cam.rotation))));
              },
              onCommit: commit,
            )),
          ]),
        ]),
    CanvasControlGroup(
        label: "Depth of field",
        help: "What is sharp, and how soft the rest is by how far it is from "
            "it: each element's Depth (in its Layout) says how far. Key the "
            "focus at two moments for a focus pull.",
        children: [
          CanvasDropdown<String>(
            key: const ValueKey("cameraFocusOn"),
            label: "Focus on",
            value: others.any((x) => x.id == e.focusOn) ? e.focusOn : "",
            options: [
              ("", "A depth"),
              for (var x in others)
                (x.id, x.base.name.isEmpty ? x.kind.label : x.base.name),
            ],
            onChanged: (id) {
              begin();
              write(now().copyWith(focusOn: id));
              commit();
            },
          ),
          if (e.focusOn.isEmpty)
            panelRow([
              cell(CanvasStepper(
                key: const ValueKey("cameraFocus"),
                label: "Focus",
                value: look.focus * 100,
                min: -100,
                max: 100,
                step: 10,
                dragStep: 1,
                defaultValue: 0,
                width: 104,
                onChanged: (v) => set(
                    "focus", v / 100, (cam) => cam.copyWith(focus: v / 100)),
                onCommit: commit,
              )),
              cell(keyButton("focus", look.focus), width: 36),
            ]),
          panelRow([
            cell(CanvasStepper(
              key: const ValueKey("cameraBlur"),
              label: "Blur",
              value: look.blur,
              min: 0,
              max: 60,
              step: 2,
              dragStep: 0.5,
              decimals: 1,
              defaultValue: 0,
              width: 104,
              onChanged: (v) => set("blur", v, (cam) => cam.copyWith(blur: v)),
              onCommit: commit,
            )),
            cell(keyButton("blur", look.blur), width: 36),
          ]),
        ]),
    CanvasControlGroup(
        label: "Parallax",
        help: "As it pans and zooms, the far moves less and the near more, "
            "by each element's Depth: a flat page given room.",
        children: [
          CanvasStepper(
            key: const ValueKey("cameraParallax"),
            label: "Parallax",
            value: e.parallax * 100,
            min: 0,
            max: 100,
            step: 10,
            dragStep: 1,
            defaultValue: 0,
            suffix: "%",
            width: 104,
            onChanged: (v) {
              begin();
              write(now().copyWith(parallax: v / 100));
            },
            onCommit: commit,
          ),
        ]),
    // Part of a chart framed and followed through a race (camera_aim.dart).
    CanvasControlGroup(
        key: const ValueKey("cameraAim"),
        label: "Aim at a chart",
        help: "Frames part of a chart -- one club, the top three, whoever "
            "leads -- where it is drawn on each frame. Key \"How far\" to "
            "move in from its own framing and back out.",
        children: [
          CanvasDropdown<String>(
            key: const ValueKey("cameraAimChart"),
            label: "Chart",
            value: doc.elementById(e.aim) is ChartElement ? e.aim : "",
            options: [
              ("", "None"),
              for (var x in doc.elements)
                if (x is ChartElement)
                  (x.id, x.name.isEmpty ? "Chart" : x.name),
            ],
            onChanged: (id) {
              begin();
              write(now().copyWith(aim: id, aimAt: ""));
              commit();
            },
          ),
          if (doc.elementById(e.aim) case ChartElement chart) ...[
            CanvasDropdown<String>(
              key: const ValueKey("cameraAimAt"),
              label: "Frames",
              value:
                  aimChoices(chart).any((c) => c.$1 == e.aimAt) ? e.aimAt : "",
              options: aimChoices(chart),
              onChanged: (v) {
                begin();
                write(now().copyWith(aimAt: v));
                commit();
              },
            ),
            panelRow([
              cell(CanvasStepper(
                key: const ValueKey("cameraAimFill"),
                label: "Fills",
                value: e.aimFill * 100,
                min: 20,
                max: 95,
                step: 5,
                dragStep: 1,
                defaultValue: 60,
                suffix: "%",
                width: 104,
                onChanged: (v) {
                  begin();
                  write(now().copyWith(aimFill: v / 100));
                },
                onCommit: commit,
              )),
              cell(CanvasStepper(
                key: const ValueKey("cameraAimMix"),
                label: "How far",
                value: aimMix * 100,
                min: 0,
                max: 100,
                step: 10,
                dragStep: 1,
                defaultValue: 100,
                suffix: "%",
                width: 104,
                onChanged: (v) => set("aim", v / 100, (cam) {
                  // Unkeyed: all the way; keyed: at the playhead.
                  return keyHere(cam, "aim", v / 100);
                }),
                onCommit: commit,
              )),
              cell(keyButton("aim", aimMix), width: 36),
            ]),
          ],
        ]),
    CanvasControlGroup(
        label: "Lens",
        help: "Corners darkened, as a lens does, and the picture smeared "
            "along the camera's own fast moves.",
        children: [
          panelRow([
            cell(CanvasStepper(
              key: const ValueKey("cameraVignette"),
              label: "Vignette",
              value: look.vignette * 100,
              min: 0,
              max: 100,
              step: 10,
              dragStep: 1,
              defaultValue: 0,
              suffix: "%",
              width: 104,
              onChanged: (v) => set("vignette", v / 100,
                  (cam) => cam.copyWith(vignette: v / 100)),
              onCommit: commit,
            )),
            cell(keyButton("vignette", look.vignette), width: 36),
          ]),
          panelRow([
            cell(CanvasStepper(
              key: const ValueKey("cameraVignetteSoft"),
              label: "Softness",
              value: e.vignetteSoft * 100,
              min: 0,
              max: 100,
              step: 10,
              dragStep: 1,
              defaultValue: 50,
              suffix: "%",
              width: 104,
              onChanged: (v) {
                begin();
                write(now().copyWith(vignetteSoft: v / 100));
              },
              onCommit: commit,
            )),
            cell(CanvasStepper(
              key: const ValueKey("cameraMotionBlur"),
              label: "Motion blur",
              value: e.motionBlur * 100,
              min: 0,
              max: 100,
              step: 10,
              dragStep: 1,
              defaultValue: 0,
              suffix: "%",
              width: 104,
              onChanged: (v) {
                begin();
                write(now().copyWith(motionBlur: v / 100));
              },
              onCommit: commit,
            )),
          ]),
        ]),
  ];
}

/// cameraSettings is a Camera's own sections: looking through it, where it
/// stands (on a 3D stage) or how close and turned it is (on the page), and
/// the moves that can be put on the timeline.
///
/// A camera is its frame, moved by its clips: here is only the way to see
/// what it sees while the scene stands still.
List<Widget> cameraSettings(
  BuildContext context,
  CanvasController controller,
  CameraElement e,
  void Function(CanvasElement) write,
  VoidCallback begin,
  VoidCallback commit,
) =>
    [
      section(e, "camera",
          icon: Icons.videocam_outlined,
          title: "Camera",
          summary: controller.cameraView
              ? "Looking through it"
              : "Its frame is what is shown",
          children: [
            CanvasControlGroup(
                label: "Camera",
                help: "What plays and what is exported is this frame, "
                    "filled out to the page. Draw it in or move it, or "
                    "give it clips: push in, follow, pull back, shake.",
                children: [
                  CanvasToggle(
                    key: const ValueKey("cameraLook"),
                    label: "Look through it",
                    value: controller.cameraView,
                    onChanged: (v) => controller.cameraView = v,
                  ),
                ]),
            // On a 3D stage it stands in the scene: where, and its
            // lens. Its clips move it from here.
            if (isStageScene(controller.document))
              _camera3dGroup(controller, e, write, begin, commit)
            else
              // On the page: how close and turned, and its lens.
              ...cameraLensGroups(controller, e, write, begin, commit),
          ]),
      // A move put on the timeline at the playhead and opened to be
      // shaped: the quickest way to a push in.
      section(e, "cameraMoves",
          icon: Icons.movie_filter_outlined,
          title: "Moves",
          summary: "${e.base.motion.placed.length} on the timeline",
          children: [
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (var p in presetsFor(MotionKind.camera))
                ActionChip(
                  key: ValueKey("cameraMove-${p.name}"),
                  visualDensity: VisualDensity.compact,
                  label: Text(p.name, style: const TextStyle(fontSize: 11.5)),
                  onPressed: () {
                    var target = controller.document.elements
                        .where((x) => x.id != e.id && x is! CameraElement)
                        .map((x) => x.id)
                        .lastOrNull;
                    controller.beginInteraction();
                    var clip = controller.newClip(e.id,
                        preset: p, target: p.aims ? target ?? "" : "");
                    var placed = controller.placeClip(e.id, clip,
                        seconds: controller.secondsAt(controller.frame));
                    controller.endInteraction();
                    controller.pickMotion(e.id, clip, placement: placed);
                    controller.animationOpen = true;
                  },
                ),
            ]),
          ]),
    ];

/// _camera3dGroup is where a Camera stands on a 3D stage, and its lens.
Widget _camera3dGroup(
    CanvasController controller,
    CameraElement e,
    void Function(CanvasElement) write,
    VoidCallback begin,
    VoidCallback commit) {
  var doc = controller.document;
  var view = e.view ??
      (doc.drawnBackground.isStage
              ? doc.drawnBackground.stageOn(doc.size.rect)
              : doc.elements
                  .whereType<BackgroundElement>()
                  .where((b) => b.isStage)
                  .first
                  .staged)
          .ownCameraAt(0);
  Widget field(String key, String label, double value, double min, double max,
          StageCamera Function(double v) set,
          {String suffix = "", int decimals = 1}) =>
      CanvasNumberField(
        key: ValueKey("camera3d-$key"),
        label: label,
        value: value,
        min: min,
        max: max,
        decimals: decimals,
        suffix: suffix,
        width: 70,
        onChanged: (v) {
          begin();
          write(e.withView(set(v)));
        },
        onCommit: commit,
      );
  return CanvasControlGroup(
      key: const ValueKey("camera3d"),
      label: "In 3D",
      help: "Where it stands on the stage. Its clips turn it round what it "
          "looks at, bring it closer, and aim it at whoever it is on.",
      children: [
        field("lens", "Lens", view.lens, 12, 200, (v) => view.copyWith(lens: v),
            suffix: " mm", decimals: 0),
        field("distance", "Distance", view.distance, StageCamera.minDistance,
            StageCamera.maxDistance, (v) => view.copyWith(distance: v),
            suffix: " m"),
        field("height", "Height", view.ty, -10, 30, (v) => view.copyWith(ty: v),
            suffix: " m"),
        field("turn", "Turn", view.yaw, -360, 360, (v) => view.copyWith(yaw: v),
            suffix: "°", decimals: 0),
        field(
            "tilt", "Tilt", view.pitch, -10, 89, (v) => view.copyWith(pitch: v),
            suffix: "°", decimals: 0),
      ]);
}
