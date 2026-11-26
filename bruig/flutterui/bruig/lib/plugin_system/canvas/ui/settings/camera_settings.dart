import 'package:flutter/material.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart' show MotionKind;
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart'
    show presetsFor;
import 'package:bruig/plugin_system/canvas/render/camera_aim.dart'
    show aimChoices;
import 'package:bruig/plugin_system/canvas/render/motion_document.dart'
    show
        CameraLook,
        cameraFraming,
        cameraLookAt,
        isStageScene,
        poseAimAt,
        stageCameraOf;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/motion/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart';

// camera_settings.dart is a Camera's panel: looking through it, and on the
// page its framing and lens (zoom, roll, focus, depth of field, parallax, an
// aim at a chart, vignette, motion blur), or on a 3D stage where it stands;
// then the moves that can be put on the timeline. Focus, blur, vignette and
// how far it turns to its aim key with ◆ (KeyframeChannel), as every panel's
// values do; once keyed a change keys the playhead (a focus pull). Zoom and
// roll are the moving camera's pose, as a drag is.

/// cameraPanel is a Camera's settings in the frame every element's are in:
/// its own straight in Content, and its moves folded under them.
Widget cameraPanel(
        BuildContext context,
        CanvasController controller,
        CameraElement e,
        SettingsWrite write,
        VoidCallback begin,
        VoidCallback commit) =>
    elementPanel(context, controller, e, write, begin, commit,
        contentOpen: true,
        bits: [
          PanelBit(PanelSection.content,
              summary: controller.cameraView
                  ? "Looking through it"
                  : "Its frame is what is shown",
              children: [
                _lookGroup(controller),
                // On a 3D stage it stands in the scene: where, and its lens.
                // Its clips move it from here.
                if (isStageScene(controller.document))
                  _camera3dGroup(controller, e, write, begin, commit)
                else
                  // On the page: how close and turned, and its lens.
                  ..._lensGroups(_Lens(controller, e, write, begin, commit)),
              ]),
          PanelBit(PanelSection.content,
              children: [_movesSection(controller, e)]),
        ]);

/// _lookGroup is looking through the Camera rather than at the page.
Widget _lookGroup(CanvasController controller) => CanvasControlGroup(
        label: "Camera",
        help: "What plays and what is exported is this frame, filled out to "
            "the page. Draw it in or move it, or give it clips: push in, "
            "follow, pull back, shake.",
        children: [
          CanvasToggle(
            key: const ValueKey("cameraLook"),
            label: "Look through it",
            value: controller.cameraView,
            onChanged: (v) => controller.cameraView = v,
          ),
        ]);

/// _movesSection is the moves a Camera can be given: one put on the
/// timeline at the playhead and opened to be shaped, the quickest way to a
/// push in.
Widget _movesSection(CanvasController controller, CameraElement e) =>
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
        ]);

/// _Lens is what a Camera's framing and lens groups are built from: the
/// Camera as shown, the playhead, how it looks there, and how to write it.
class _Lens {
  final CanvasController controller;
  final CameraElement e;
  final SettingsWrite write;
  final VoidCallback begin;
  final VoidCallback commit;
  final CanvasDocument doc;
  final int frame;
  final CameraLook look;
  final ElementTrack track;

  _Lens(this.controller, this.e, this.write, this.begin, this.commit)
      : doc = controller.document,
        frame = controller.frame,
        look = cameraLookAt(e, controller.frame, controller.document),
        track = e.track ?? ElementTrack.empty;

  /// current is the Camera as the document has it now, which a change
  /// made earlier in the same drag has already written.
  CameraElement current() => switch (controller.document.elementById(e.id)) {
        CameraElement now => now,
        _ => e,
      };

  /// keyed is whether [channel] has any keyframes.
  bool keyed(String channel) =>
      track.keys.any((k) => k.values.containsKey(channel));

  /// keyedHere is [cam] with [channel] keyed to [v] at the playhead.
  CameraElement keyedHere(CameraElement cam, String channel, double v) =>
      cam.withBase(
          track: (cam.track ?? ElementTrack.empty)
              .withValueKey(channel, v, frame)) as CameraElement;
}

/// _lensGroups are a Camera's framing and lens on the page.
List<Widget> _lensGroups(_Lens l) => [
      _framingGroup(l),
      _depthGroup(l),
      _parallaxGroup(l),
      _aimGroup(l),
      _vignetteGroup(l),
    ];

/// _keyed is a lens value a key can hold: its stepper, showing [shown] (the
/// value [per] times over), and the ◆ that keys it at the playhead, lit
/// where a key already stands. Where [channel] is keyed, a change keys the
/// playhead; else it is the Camera's own setting, by [setting]. Without a
/// [setting] a change is always a key.
List<(Widget, {int flex, double? width, double min})> _keyed(
  _Lens l, {
  required String key,
  required String label,
  required String channel,
  required double shown,
  required double min,
  required double max,
  required double step,
  required double dragStep,
  required double defaultValue,
  int decimals = 0,
  String suffix = "",
  double per = 1,
  CameraElement Function(CameraElement cam, double v)? setting,
}) =>
    [
      cell(CanvasStepper(
        key: ValueKey(key),
        label: label,
        value: shown * per,
        min: min,
        max: max,
        step: step,
        dragStep: dragStep,
        decimals: decimals,
        defaultValue: defaultValue,
        suffix: suffix,
        width: 104,
        onChanged: (v) {
          l.begin();
          var cam = l.current();
          l.write(setting == null || l.keyed(channel)
              ? l.keyedHere(cam, channel, v / per)
              : setting(cam, v / per));
        },
        onCommit: l.commit,
      )),
      cell(
          CanvasIconButton(
            key: ValueKey("cameraKey-$channel"),
            icon: Icons.diamond_outlined,
            tooltip: "Key it here: changed at the playhead from then on",
            active:
                l.track.keyAt(l.frame)?.values.containsKey(channel) ?? false,
            onPressed: () {
              l.begin();
              l.write(l.keyedHere(l.current(), channel, shown));
              l.commit();
            },
          ),
          width: 36),
    ];

/// _framingGroup is how close the Camera is and how far it is rolled.
Widget _framingGroup(_Lens l) {
  var (zoom, _) = cameraFraming(l.e, l.frame, l.doc);
  return CanvasControlGroup(
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
              l.begin();
              var cam = l.current();
              var (z, _) = cameraFraming(cam, l.frame, l.controller.document);
              l.write(l.controller.cameraZoomed(cam, v / z));
            },
            onCommit: l.commit,
          )),
          cell(CanvasStepper(
            key: const ValueKey("cameraRoll"),
            label: "Roll",
            value: l.look.roll,
            min: -180,
            max: 180,
            step: 5,
            dragStep: 0.5,
            decimals: 1,
            defaultValue: 0,
            suffix: "°",
            width: 104,
            onChanged: (v) {
              l.begin();
              var cam = l.current();
              if (!l.controller.posesRatherThanMoves(cam)) {
                l.write(cam.withBase(rotation: v));
                return;
              }
              var t = (cam.track ?? ElementTrack.empty).seededFor(l.frame);
              l.write(cam.withBase(
                  track: t.withKey(t
                      .at(l.frame)
                      .copyWith(frame: l.frame, rotate: v - cam.rotation))));
            },
            onCommit: l.commit,
          )),
        ]),
      ]);
}

/// _depthGroup is what is sharp, and how soft the rest is.
Widget _depthGroup(_Lens l) {
  var e = l.e;
  var others = [
    for (var x in l.doc.elements)
      if (x is! CameraElement) x,
  ];
  return CanvasControlGroup(
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
            l.begin();
            l.write(l.current().copyWith(focusOn: id));
            l.commit();
          },
        ),
        if (e.focusOn.isEmpty)
          panelRow(_keyed(l,
              key: "cameraFocus",
              label: "Focus",
              channel: KeyframeChannel.focus,
              shown: l.look.focus,
              per: 100,
              min: -100,
              max: 100,
              step: 10,
              dragStep: 1,
              defaultValue: 0,
              setting: (cam, v) => cam.copyWith(focus: v))),
        panelRow(_keyed(l,
            key: "cameraBlur",
            label: "Blur",
            channel: KeyframeChannel.blur,
            shown: l.look.blur,
            min: 0,
            max: 60,
            step: 2,
            dragStep: 0.5,
            decimals: 1,
            defaultValue: 0,
            setting: (cam, v) => cam.copyWith(blur: v))),
      ]);
}

/// _parallaxGroup is how much less the far moves than the near.
Widget _parallaxGroup(_Lens l) => CanvasControlGroup(
        label: "Parallax",
        help: "As it pans and zooms, the far moves less and the near more, "
            "by each element's Depth: a flat page given room.",
        children: [
          CanvasStepper(
            key: const ValueKey("cameraParallax"),
            label: "Parallax",
            value: l.e.parallax * 100,
            min: 0,
            max: 100,
            step: 10,
            dragStep: 1,
            defaultValue: 0,
            suffix: "%",
            width: 104,
            onChanged: (v) {
              l.begin();
              l.write(l.current().copyWith(parallax: v / 100));
            },
            onCommit: l.commit,
          ),
        ]);

/// _aimGroup is part of a chart framed and followed through a race
/// (camera_aim.dart): which chart, what of it, how much of the frame it
/// fills and how far the Camera turns to it.
Widget _aimGroup(_Lens l) {
  var e = l.e;
  // How far it is turned to its aim here: keyed, or all the way.
  var aimMix = (l.track.keyAt(l.frame)?.values[KeyframeChannel.aimMix] ??
          poseAimAt(e, l.frame, l.doc)) ??
      1.0;
  return CanvasControlGroup(
      key: const ValueKey("cameraAim"),
      label: "Aim at a chart",
      help: "Frames part of a chart -- one club, the top three, whoever "
          "leads -- where it is drawn on each frame. Key \"How far\" to "
          "move in from its own framing and back out.",
      children: [
        CanvasDropdown<String>(
          key: const ValueKey("cameraAimChart"),
          label: "Chart",
          value: l.doc.elementById(e.aim) is ChartElement ? e.aim : "",
          options: [
            ("", "None"),
            for (var x in l.doc.elements)
              if (x is ChartElement) (x.id, x.name.isEmpty ? "Chart" : x.name),
          ],
          onChanged: (id) {
            l.begin();
            l.write(l.current().copyWith(aim: id, aimAt: ""));
            l.commit();
          },
        ),
        if (l.doc.elementById(e.aim) case ChartElement chart) ...[
          CanvasDropdown<String>(
            key: const ValueKey("cameraAimAt"),
            label: "Frames",
            value: aimChoices(chart).any((c) => c.$1 == e.aimAt) ? e.aimAt : "",
            options: aimChoices(chart),
            onChanged: (v) {
              l.begin();
              l.write(l.current().copyWith(aimAt: v));
              l.commit();
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
                l.begin();
                l.write(l.current().copyWith(aimFill: v / 100));
              },
              onCommit: l.commit,
            )),
            // How far has no setting of its own: unkeyed the Camera turns
            // all the way, so any change to it is a key at the playhead.
            ..._keyed(l,
                key: "cameraAimMix",
                label: "How far",
                channel: KeyframeChannel.aimMix,
                shown: aimMix,
                per: 100,
                min: 0,
                max: 100,
                step: 10,
                dragStep: 1,
                defaultValue: 100,
                suffix: "%"),
          ]),
        ],
      ]);
}

/// _vignetteGroup is the lens's own marks: its corners darkened, and the
/// picture smeared along the Camera's fast moves.
Widget _vignetteGroup(_Lens l) => CanvasControlGroup(
        label: "Lens",
        help: "Corners darkened, as a lens does, and the picture smeared "
            "along the camera's own fast moves.",
        children: [
          panelRow(_keyed(l,
              key: "cameraVignette",
              label: "Vignette",
              channel: KeyframeChannel.vignette,
              shown: l.look.vignette,
              per: 100,
              min: 0,
              max: 100,
              step: 10,
              dragStep: 1,
              defaultValue: 0,
              suffix: "%",
              setting: (cam, v) => cam.copyWith(vignette: v))),
          panelRow([
            cell(CanvasStepper(
              key: const ValueKey("cameraVignetteSoft"),
              label: "Softness",
              value: l.e.vignetteSoft * 100,
              min: 0,
              max: 100,
              step: 10,
              dragStep: 1,
              defaultValue: 50,
              suffix: "%",
              width: 104,
              onChanged: (v) {
                l.begin();
                l.write(l.current().copyWith(vignetteSoft: v / 100));
              },
              onCommit: l.commit,
            )),
            cell(CanvasStepper(
              key: const ValueKey("cameraMotionBlur"),
              label: "Motion blur",
              value: l.e.motionBlur * 100,
              min: 0,
              max: 100,
              step: 10,
              dragStep: 1,
              defaultValue: 0,
              suffix: "%",
              width: 104,
              onChanged: (v) {
                l.begin();
                l.write(l.current().copyWith(motionBlur: v / 100));
              },
              onCommit: l.commit,
            )),
          ]),
        ]);

/// _camera3dGroup is where a Camera stands on a 3D stage, and its lens.
Widget _camera3dGroup(CanvasController controller, CameraElement e,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  var view =
      e.view ?? stageCameraOf(controller.document) ?? const StageCamera();
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
