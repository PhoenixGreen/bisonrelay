import 'package:flutter/material.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_run_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_task_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/metronome_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/object3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/play_task_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sprite_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/synth_module_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/synth_task_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/tile_map_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/background_element_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/button_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/camera_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/character3d_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/chart_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/code_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/counter_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/image_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/layout_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/line_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/metronome_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/object3d_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/path_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/play_task_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/shape_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/sheet_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/sprite_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/stage_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/synth_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/table_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/team_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/text_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/tile_map_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/vector_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/video_settings.dart';

// element_settings.dart is the way to an element's settings panel: which
// panel each kind has. The panels themselves are in settings/, one file a
// kind. Every control in them writes a transient edit and commits on
// release, so a drag is one undo step: hence the write, begin and commit
// every panel is handed.

/// elementSettings is the settings panel for [element], by its kind.
///
/// A new kind is added to the switch, which has no default so that the
/// compiler asks for it. A kind either builds its whole panel
/// (settings/element_panel.dart shows how) or hands its own sections to
/// [_inSharedPanel].
List<Widget> elementSettings(
  BuildContext context,
  CanvasController controller,
  CanvasElement element,
) {
  // The undo step is opened here, not by each control: beginInteraction is
  // idempotent, and a transient edit outside an interaction never reaches
  // the history.
  void write(CanvasElement next) {
    controller.beginInteraction();
    controller.replaceElement(next, transient: true);
  }

  void commit() => controller.endInteraction();
  void begin() => controller.beginInteraction();

  List<Widget> shared(List<Widget> own) =>
      _inSharedPanel(context, controller, element, write, begin, commit, own);

  return switch (element.kind) {
    // A picture is all sections (see image_sections.dart).
    ElementKind.image => imageSettings(
        context, controller, element as ImageElement, write, begin, commit),
    // A text: its layers, a quick strip, then Content, Look, Layout, Motion
    // and More (see textPanel).
    ElementKind.text => [
        textPanel(
            context, controller, element as TextElement, write, begin, commit)
      ],
    // Elements with a panel of their own, in the Text panel's shape.
    ElementKind.shape => [
        shapePanel(
            context, controller, element as ShapeElement, write, begin, commit)
      ],
    ElementKind.line => [
        linePanel(
            context, controller, element as LineElement, write, begin, commit)
      ],
    ElementKind.path => [
        pathPanel(
            context, controller, element as PathElement, write, begin, commit)
      ],
    ElementKind.button => [
        buttonPanel(
            context, controller, element as ButtonElement, write, begin, commit)
      ],
    ElementKind.counter => [
        counterPanel(context, controller, element as CounterElement, write,
            begin, commit)
      ],
    ElementKind.table => [
        tablePanel(
            context, controller, element as TableElement, write, begin, commit)
      ],
    ElementKind.chart => [
        chartPanel(
            context, controller, element as ChartElement, write, begin, commit)
      ],
    ElementKind.vector => [
        vectorPanel(
            context, controller, element as VectorElement, write, begin, commit)
      ],
    ElementKind.video => videoSettings(
        context, controller, element as VideoElement, write, begin, commit,
        panel: true),
    ElementKind.audio => switch (element as AudioElement) {
        // A sound on the timeline is not on the canvas: it has only its
        // files, how it plays and where on the timeline, as a backdrop's
        // sound does.
        var e when isTimelineSound(e) => audioSettings(
            context, controller, e, write, begin, commit,
            background: true),
        // An instrument keeps its keyboard and part, in the shared panel.
        var e when e.instrument != null =>
          shared(audioSettings(context, controller, e, write, begin, commit)),
        var e => audioSettings(context, controller, e, write, begin, commit,
            panel: true),
      },
    ElementKind.sheet => sheetSettings(
        context, controller, element as SheetElement, write, begin, commit,
        panel: true),
    ElementKind.code => codeSettings(
        context, controller, element as CodeElement, write, begin, commit),
    ElementKind.codeRun => codeRunSettings(
        context, controller, element as CodeRunElement, write, begin, commit),
    ElementKind.codeTask => codeTaskSettings(
        context, controller, element as CodeTaskElement, write, begin, commit),
    ElementKind.layout => layoutSettings(
        context, controller, element as LayoutElement, write, begin, commit),
    ElementKind.playTask => playTaskSettings(
        context, controller, element as PlayTaskElement, write, begin, commit),
    ElementKind.metronome => metronomeSettings(
        context, controller, element as MetronomeElement, write, begin, commit),
    ElementKind.synthTask => synthTaskSettings(
        context, controller, element as SynthTaskElement, write, begin, commit),
    ElementKind.synth => synthSettings(context, controller,
        element as SynthModuleElement, write, begin, commit),
    // The rest hand their own sections to the shared panel.
    ElementKind.background => shared(backgroundElementSettings(context,
        controller, element as BackgroundElement, write, begin, commit)),
    ElementKind.player => shared(teamSettings(
        context, controller, element as TeamElement, write, begin, commit)),
    ElementKind.character3d => shared(character3dSettings(context, controller,
        element as Character3dElement, write, begin, commit)),
    ElementKind.stage => shared(stageSettings(
        context, controller, element as StageElement, write, begin, commit)),
    ElementKind.sprite => shared(spriteSettings(
        context, controller, element as SpriteElement, write, begin, commit)),
    ElementKind.tileMap => shared(tileMapSettings(
        context, controller, element as TileMapElement, write, begin, commit)),
    ElementKind.object3d => shared(object3dSettings(
        context, controller, element as Object3dElement, write, begin, commit)),
    ElementKind.camera => shared(cameraSettings(
        context, controller, element as CameraElement, write, begin, commit)),
    // Scenery is never selected alone: it is set in its background's panel.
    ElementKind.parallax => shared(const []),
  };
}

/// _inSharedPanel is [element]'s [own] sections in the panel every such
/// element shares (elementPanel), each where [_placed] puts it.
List<Widget> _inSharedPanel(
  BuildContext context,
  CanvasController controller,
  CanvasElement element,
  void Function(CanvasElement) write,
  VoidCallback begin,
  VoidCallback commit,
  List<Widget> own,
) {
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

/// _placed is where each of an element's own sections goes in its panel, by
/// the name it is remembered by: which section, and whether its settings go
/// straight in (the element's main subject) rather than as a fold. One not
/// named is a fold in Content.
const _placed = <String, (PanelSection, bool)>{
  // An instrument.
  "instrument": (PanelSection.content, true),
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
