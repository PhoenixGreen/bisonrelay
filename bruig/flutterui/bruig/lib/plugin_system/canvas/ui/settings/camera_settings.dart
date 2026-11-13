import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart'
    show cameraFraming, cameraLookAt;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart';
import 'package:flutter/material.dart';

// camera_settings.dart is a 2D Camera's framing and lens (Ken, 2026-11-14:
// "it would be nice if the camera had other useful camera settings like
// depth of field"): how close and how rolled, at the playhead; what is in
// focus and how soft the rest; parallax; a vignette and motion blur.
//
// Focus, blur and vignette can be keyed: the ◆ beside one puts a key at the
// playhead, and once keyed, changing it keys it at the playhead (a focus
// pull). Zoom and roll are keyed as dragging the camera is: on a frame of a
// camera that moves, they are its pose there.

/// cameraLensGroups are [e]'s framing and lens settings.
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

  /// keyed is whether [channel] is pinned by any of its keyframes.
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

  /// keyButton keys [channel] at the playhead, holding [v] -- lit where a
  /// key already stands there.
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
