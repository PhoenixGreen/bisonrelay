import 'package:bruig/plugin_system/canvas/ui/settings/sheet_settings.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart' show MotionKind;
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart'
    show presetsFor;
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart'
    show isStageScene;
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/parallax_settings.dart';
import 'package:bruig/plugin_system/canvas/presets/parallax_looks.dart';
import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/backdrop_settings.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/character3d_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/stage_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/stage_spot_settings.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/vector_layers.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/vector_settings.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/procedural_settings.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sprite_element.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/sprite_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/tile_map_settings.dart';
import 'package:bruig/plugin_system/canvas/model/elements/tile_map_element.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/button_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/video_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/chart_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/counter_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/image_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/line_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/path_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/shape_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/table_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/team_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/text_layers.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/text_settings.dart';

// element_settings.dart is the controls for whichever element is selected.
//
// One function per element kind, each returning the groups that go into the
// settings bar. They are grouped by what somebody is thinking about rather
// than by which class the field is declared on -- so a text element's colour
// sits with its outline and its shadow under "Colour", not with its font size
// under "Type", even though all four are fields of the same TextSpec.
//
// Every control writes a transient edit and commits on release, so dragging a
// slider updates the canvas continuously and lands as one undo step. That
// pairing is why almost every control here passes both onChanged and
// onCommit; a control that only did the first would make an undo history
// forty steps long for one adjustment.

/// elementSettings is the groups for [element].
List<Widget> elementSettings(
  BuildContext context,
  CanvasController controller,
  CanvasElement element,
) {
  // Opening the undo step here rather than leaving it to each control.
  // beginInteraction is idempotent, and forgetting it is silent: a transient
  // edit made outside an interaction is never pushed onto the history, so the
  // control works and is simply not undoable. With forty controls in this
  // file, doing it once is the only way it stays true.
  void write(CanvasElement next) {
    controller.beginInteraction();
    controller.replaceElement(next, transient: true);
  }

  void commit() => controller.endInteraction();
  void begin() => controller.beginInteraction();

  // A sound on the timeline is not on the canvas: no place on it, no presets
  // for a speaker, no speaker. What it has is its files, how it plays, and
  // where on the timeline -- the same as a backdrop's sound.
  if (element is AudioElement && isTimelineSound(element)) {
    return audioSettings(context, controller, element, write, begin, commit,
        background: true);
  }

  // A picture is all sections, its place and its presets among them -- see
  // image_sections.dart.
  if (element is ImageElement) {
    return imageSettings(context, controller, element, write, begin, commit);
  }

  // Every other element in sections, as a picture is: where it is, its
  // own subjects, how it arrives, and the designs saved of its kind -- see
  // element_sections.dart.
  return [
    CanvasSections(
      key: const ValueKey("elementSections"),
      // A drawing's layers over its sections, as a picture's are -- once it
      // has been taken apart into shapes to have any.
      parts: element is TextElement
          // A text's layers -- its own words, and every piece of writing or
          // picture added to its box -- over its sections, as a picture's
          // are.
          ? TextLayersList(
              key: const ValueKey("textLayersList"),
              controller: controller,
              element: element,
              onChanged: (next) {
                begin();
                write(next);
                commit();
              })
          : element is VectorElement &&
                  element.edited &&
                  (element.shapes?.isNotEmpty ?? false)
              ? VectorLayersList(
                  key: const ValueKey("vectorLayersList"),
                  controller: controller,
                  element: element,
                  onChanged: (next) {
                    begin();
                    write(next);
                    commit();
                  })
              : null,
      children: [
        positionSection(controller, element, write, begin, commit,
            // An element with no arrival of its own still waits on a cue.
            extra: [
              if (controller.cues.isNotEmpty &&
                  (element is BackgroundElement || element is TeamElement))
                elementCueCard(controller, element),
              // A drawing's file and how it sits in its box, at the foot
              // of where the box is.
              if (element is VectorElement)
                vectorDrawingControls(
                    context, controller, element, write, begin, commit),
              if (element is VectorElement && element.hasDrawing)
                vectorCropControls(controller, element, write, begin, commit),
              // Where a text's words come from and how they sit in its box.
              if (element is TextElement)
                textWordsCard(
                    context, controller, element, write, begin, commit),
            ]),
        ...switch (element) {
          TextElement e =>
            textSettings(context, controller, e, write, begin, commit),
          ShapeElement e =>
            shapeSettings(context, controller, e, write, begin, commit),
          LineElement e =>
            lineSettings(context, controller, e, write, begin, commit),
          VectorElement e =>
            vectorSettings(context, controller, e, write, begin, commit),
          ChartElement e =>
            chartSettings(context, controller, e, write, begin, commit),
          TableElement e =>
            tableSettings(context, controller, e, write, begin, commit),
          ButtonElement e =>
            buttonSettings(context, controller, e, write, begin, commit),
          CounterElement e =>
            counterSettings(context, controller, e, write, begin, commit),
          AudioElement e =>
            audioSettings(context, controller, e, write, begin, commit),
          SheetElement e =>
            sheetSettings(context, controller, e, write, begin, commit),
          VideoElement e =>
            videoSettings(context, controller, e, write, begin, commit),
          BackgroundElement e => [
              ..._backgroundElementBackdrop(
                  context, controller, e, write, begin, commit),
              section(e, "panel",
                  icon: Icons.crop_square,
                  title: "Panel",
                  summary: e.cornerRadius > 0
                      ? "Corners ${e.cornerRadius.round()}"
                      : "Square corners",
                  children: [
                    CanvasControlGroup(
                        label: "Corners",
                        help: "How round the panel's corners are.",
                        children: [
                          CanvasNumberField(
                            label: "Radius",
                            value: e.cornerRadius,
                            min: 0,
                            max: 400,
                            onChanged: (v) =>
                                write(e.copyWith(cornerRadius: v)),
                            onCommit: commit,
                          ),
                        ]),
                  ]),
              edgeMaskSection(
                  e, e.mask, (m) => write(e.copyWith(mask: m)), begin, commit),
            ],
          TeamElement e =>
            teamSettings(context, controller, e, write, begin, commit),
          PathElement e =>
            pathSettings(context, controller, e, write, begin, commit),
          Character3dElement e =>
            character3dSettings(context, controller, e, write, begin, commit),
          StageElement e =>
            stageSettings(context, controller, e, write, begin, commit),
          SpriteElement e =>
            spriteSettings(context, controller, e, write, begin, commit),
          TileMapElement e =>
            tileMapSettings(context, controller, e, write, begin, commit),
          // A camera is its frame, moved by its clips: here only the way to
          // see what it sees while the scene stands still.
          CameraElement e => [
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
                      _camera3dGroup(controller, e, write, begin, commit),
                  ]),
              // A move put on the timeline at the playhead, opened to be
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
                          label: Text(p.name,
                              style: const TextStyle(fontSize: 11.5)),
                          onPressed: () {
                            var target = controller.document.elements
                                .where(
                                    (x) => x.id != e.id && x is! CameraElement)
                                .map((x) => x.id)
                                .lastOrNull;
                            controller.beginInteraction();
                            var clip = controller.newClip(e.id,
                                preset: p, target: p.aims ? target ?? "" : "");
                            var placed = controller.placeClip(e.id, clip,
                                seconds:
                                    controller.secondsAt(controller.frame));
                            controller.endInteraction();
                            controller.pickMotion(e.id, clip,
                                placement: placed);
                            controller.animationOpen = true;
                          },
                        ),
                    ]),
                  ]),
            ],
          _ => const <Widget>[],
        },
        // Where it stands on a 3D stage, for anything that can.
        ...stageSpotSettings(
            context, controller, element, write, begin, commit),
        presetsPanelSection(context, controller, element, extra: [
          // A text's named styles, under the designs kept of its kind: the
          // other way its look is kept to use again.
          if (element is TextElement) textStyleCard(controller, element),
        ]),
      ],
    ),
  ];
}

/// elementCueGroup is which cue [element] arrives on.
Widget elementCueGroup(CanvasController controller, CanvasElement element) =>
    CanvasControlGroup(
        key: const ValueKey("elementCue"),
        label: "Word cue",
        hideCaption: true,
        rule: false,
        children: [
          CanvasDropdown<String>(
            label: "Arrives on word cue",
            value: controller.cues.any((c) => c.id == element.base.cue)
                ? element.base.cue
                : "",
            width: 150,
            options: [
              ("", "None"),
              for (var c in controller.cues) (c.id, c.name),
            ],
            onChanged: (v) =>
                controller.cueTo(element.id, v.isEmpty ? null : v),
          ),
        ]);

/// _backgroundElementBackdrop is a Background element's pattern, or its
/// stage, under the choice between them.
List<Widget> _backgroundElementBackdrop(
  BuildContext context,
  CanvasController controller,
  BackgroundElement e,
  void Function(CanvasElement) write,
  VoidCallback begin,
  VoidCallback commit,
) {
  var picker = backdropKindPicker(e.backdrop, (kind) {
    begin();
    write(e.copyWith(
        backdrop: kind,
        stage: e.stage ?? const StageElement(ElementBase(id: "")),
        parallax: kind == BackdropKind.parallax
            ? e.parallax ?? parallaxLooks.first.scenery
            : null));
    commit();
  });
  if (e.isParallax) {
    return [
      ParallaxSettings(
        key: ValueKey("parallaxSettings-${e.id}"),
        controller: controller,
        scenery: e.parallaxed,
        picker: picker,
        write: (p) => write(e.withParallax(p)),
        begin: begin,
        commit: commit,
        rememberAs: "backgroundElement",
      ),
    ];
  }
  if (e.isStage) {
    return stageBackdropSettings(context, controller, e.staged,
        picker: picker,
        write: (stage) => write(e.withStage(stage)),
        begin: begin,
        commit: commit,
        rememberAs: "backgroundElement");
  }
  return [
    ProceduralSettings(
      kindPicker: picker,
      sections: true,
      rememberAs: "backgroundElement",
      spec: e.spec,
      onChanged: (spec) => write(e.copyWith(spec: spec)),
      onBegin: begin,
      onCommit: commit,
    ),
  ];
}

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
