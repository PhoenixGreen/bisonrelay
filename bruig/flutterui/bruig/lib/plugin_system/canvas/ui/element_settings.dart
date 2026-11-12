import 'package:bruig/plugin_system/canvas/ui/settings/sheet_settings.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart' show MotionKind;
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart'
    show presetsFor;
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart'
    show isStageScene;
import 'package:bruig/plugin_system/canvas/ui/asset_elements.dart'
    show modelClipsOnto;
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart'
    show AssetKind, CanvasLibrary, LibraryAsset;
import 'package:bruig/plugin_system/canvas/model/elements/object3d_element.dart';
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
import 'package:bruig/plugin_system/canvas/ui/settings/element_panel.dart';
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
import 'package:bruig/plugin_system/canvas/ui/settings/text_settings.dart';

// element_settings.dart is the controls for whichever element is selected,
// grouped by what somebody is thinking about rather than by which class holds
// the field: a text's colour sits with its outline and shadow under Colour,
// not with its font size under Type. Every control writes a transient edit
// and commits on release, so a drag is one undo step: hence onChanged and
// onCommit on almost every control.

/// elementSettings is the groups for [element].
List<Widget> elementSettings(
  BuildContext context,
  CanvasController controller,
  CanvasElement element,
) {
  // The undo step is opened here, not by each control: beginInteraction is
  // idempotent, and a transient edit made outside an interaction is silently
  // never put on the history.
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

  // A text, rebuilt round tasks: its layers, a quick strip, then Content,
  // Look, Layout, Motion and More -- see textPanel.
  if (element is TextElement) {
    return [textPanel(context, controller, element, write, begin, commit)];
  }

  // Batch 2 of the rebuild (Ken, 2026-11-11): the Text panel's shape.
  if (element is ShapeElement) {
    return [shapePanel(context, controller, element, write, begin, commit)];
  }
  if (element is LineElement) {
    return [linePanel(context, controller, element, write, begin, commit)];
  }
  if (element is PathElement) {
    return [pathPanel(context, controller, element, write, begin, commit)];
  }
  if (element is ButtonElement) {
    return [buttonPanel(context, controller, element, write, begin, commit)];
  }
  if (element is CounterElement) {
    return [counterPanel(context, controller, element, write, begin, commit)];
  }
  // Batch 3.
  if (element is TableElement) {
    return [tablePanel(context, controller, element, write, begin, commit)];
  }
  if (element is ChartElement) {
    return [chartPanel(context, controller, element, write, begin, commit)];
  }
  // Batch 4.
  if (element is VectorElement) {
    return [vectorPanel(context, controller, element, write, begin, commit)];
  }
  // Batch 5. An instrument keeps its own (its keyboard and part).
  if (element is VideoElement) {
    return videoSettings(context, controller, element, write, begin, commit,
        panel: true);
  }
  if (element is AudioElement && element.instrument == null) {
    return audioSettings(context, controller, element, write, begin, commit,
        panel: true);
  }
  if (element is SheetElement) {
    return sheetSettings(context, controller, element, write, begin, commit,
        panel: true);
  }

  // Every other element in sections, as a picture is: where it is, its
  // own subjects, how it arrives, and the designs saved of its kind -- see
  // element_sections.dart.
  var own = <Widget>[
        ...switch (element) {
          // An instrument: its keyboard and part.
          AudioElement e =>
            audioSettings(context, controller, e, write, begin, commit),
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
          Character3dElement e =>
            character3dSettings(context, controller, e, write, begin, commit),
          StageElement e =>
            stageSettings(context, controller, e, write, begin, commit),
          SpriteElement e =>
            spriteSettings(context, controller, e, write, begin, commit),
          TileMapElement e =>
            tileMapSettings(context, controller, e, write, begin, commit),
          // A 3D object: how it is seen in its box, and its animations.
          Object3dElement e => [
              section(e, "object3d",
                  icon: Icons.view_in_ar,
                  title: "3D object",
                  summary: e.assetId.isEmpty
                      ? "No model yet"
                      : "${e.animations.length} animations of its own",
                  children: [
                    _ModelChoice(
                      element: e,
                      onPick: (a) {
                        begin();
                        var next =
                            e.copyWith(assetId: a.id, animations: a.animations);
                        write(next.withBase(
                            // Named after its model, unless renamed.
                            name: e.base.name == "3D object" ? a.name : null,
                            motion: modelClipsOnto(
                                e.base.motion, e.id, a.animations)));
                        commit();
                      },
                    ),
                    CanvasControlGroup(
                        label: "Seen",
                        help: "How it is seen in its box. On a 3D stage, "
                            "the stage's camera sees it instead.",
                        children: [
                          for (var (key, label, value, min, max, set) in [
                            (
                              "turn",
                              "Turn",
                              e.turn,
                              -360.0,
                              360.0,
                              (double v) => e.copyWith(turn: v)
                            ),
                            (
                              "tilt",
                              "Tilt",
                              e.tilt,
                              -89.0,
                              89.0,
                              (double v) => e.copyWith(tilt: v)
                            ),
                            (
                              "zoom",
                              "Closer",
                              e.zoom,
                              0.2,
                              8.0,
                              (double v) => e.copyWith(zoom: v)
                            ),
                          ])
                            CanvasNumberField(
                              key: ValueKey("object3d-$key"),
                              label: label,
                              value: value,
                              min: min,
                              max: max,
                              decimals: key == "zoom" ? 2 : 0,
                              width: 64,
                              onChanged: (v) {
                                begin();
                                write(set(v));
                              },
                              onCommit: commit,
                            ),
                        ]),
                  ]),
              // Its own animations, read from its file: its clips.
              section(e, "object3dAnimations",
                  icon: Icons.animation,
                  title: "Its animations",
                  summary: e.animations.isEmpty
                      ? "None in its file"
                      : [for (var (n, _) in e.animations) n].join(", "),
                  children: [
                    if (e.animations.isEmpty)
                      const CanvasHint("This model has no animations of its "
                          "own: it moves as any element does, by clips.")
                    else
                      CanvasControlGroup(
                          label: "Its animations",
                          help: "Read from its file, and in its slots as "
                              "clips From the model: played, placed on the "
                              "timeline and layered as any clip is.",
                          children: [
                            CanvasTextButton(
                              key: const ValueKey("object3dSlots"),
                              label: "Put them in its slots again",
                              onPressed: () {
                                begin();
                                write(e.withBase(
                                    motion: modelClipsOnto(
                                        e.base.motion, e.id, e.animations)));
                                commit();
                              },
                            ),
                          ]),
                  ]),
            ],
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
  ];

  // Batch 6 (Ken, 2026-11-11): the rest in the shared panel, each of their
  // sections where _placed puts it. An instrument keeps the older panel
  // (its keyboard and part).
  if (element is! AudioElement) {
    var bits = <PanelBit>[];
    for (var w in own) {
      var name = w is CanvasSection ? w.remember.split(".").last : "";
      var (into, straight) = _placed[name] ?? (PanelSection.content, false);
      bits.add(PanelBit(into,
          summary: straight && w is CanvasSection ? w.summary : "",
          children: straight ? sectionContents(w) : [w]));
    }
    return [
      elementPanel(context, controller, element, write, begin, commit,
          contentOpen: true, bits: bits),
    ];
  }
  return [
    CanvasSections(
      key: const ValueKey("elementSections"),
      children: [
        positionSection(controller, element, write, begin, commit),
        ...own,
        // Where it stands on a 3D stage, for anything that can.
        ...stageSpotSettings(
            context, controller, element, write, begin, commit),
        presetsPanelSection(context, controller, element),
      ],
    ),
  ];
}

/// _placed is where each of an element's own sections goes in its rebuilt
/// panel, by the name it is remembered by: which section, and whether its
/// settings go straight in (the element's main subject, open from the
/// start) rather than as a fold. One not named is a fold in Content.
const _placed = <String, (PanelSection, bool)>{
  // A team.
  "team": (PanelSection.content, true),
  "players": (PanelSection.content, false),
  "look": (PanelSection.look, true),
  "labels": (PanelSection.look, false),
  // A 3D character.
  "character": (PanelSection.content, true),
  "face": (PanelSection.look, false),
  "view": (PanelSection.layout, false),
  // A 3D object.
  "object3d": (PanelSection.content, true),
  // A camera, and a stage's camera.
  "camera": (PanelSection.content, true),
  "light": (PanelSection.look, false),
  // A sprite.
  "spriteSheet": (PanelSection.content, true),
  "spriteCues": (PanelSection.motion, false),
  "spriteExport": (PanelSection.more, false),
  // A tile map.
  "tileMapScene": (PanelSection.look, false),
  // A background: its pattern's colour, its corners and its edges.
  "colour": (PanelSection.look, false),
  "panel": (PanelSection.look, false),
  "mask": (PanelSection.look, false),
};

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

/// _ModelChoice is which of the library's 3D objects a 3D object shows. One
/// added from the Add panel starts with none, and is given one here.
class _ModelChoice extends StatefulWidget {
  final Object3dElement element;
  final ValueChanged<LibraryAsset> onPick;
  const _ModelChoice({required this.element, required this.onPick});

  @override
  State<_ModelChoice> createState() => _ModelChoiceState();
}

class _ModelChoiceState extends State<_ModelChoice> {
  late final Future<List<LibraryAsset>> _models =
      CanvasLibrary.list(kind: AssetKind.model);

  @override
  Widget build(BuildContext context) => FutureBuilder<List<LibraryAsset>>(
        future: _models,
        builder: (context, got) {
          if (got.connectionState != ConnectionState.done) {
            return const SizedBox(height: 32);
          }
          var models = got.data ?? const <LibraryAsset>[];
          var now = widget.element.assetId;
          if (models.isEmpty && now.isEmpty) {
            return const CanvasHint(
                "No 3D objects in the library yet. Add a .glb file under "
                "Assets › 3D objects, then choose it here.",
                key: ValueKey("object3dNoModels"));
          }
          return CanvasControlGroup(
              label: "Model",
              help: "Which of the library's 3D objects it shows. Its own "
                  "animations come with it, as clips in its slots.",
              children: [
                CanvasDropdown<String>(
                  key: const ValueKey("object3dModel"),
                  label: "Model",
                  value: now,
                  width: 200,
                  options: [
                    if (now.isEmpty) ("", "None yet"),
                    if (now.isNotEmpty && !models.any((m) => m.id == now))
                      (now, "Not in the library"),
                    for (var m in models) (m.id, m.name),
                  ],
                  onChanged: (id) {
                    var picked = models.where((m) => m.id == id).firstOrNull;
                    if (picked != null && id != now) widget.onPick(picked);
                  },
                ),
              ]);
        },
      );
}
