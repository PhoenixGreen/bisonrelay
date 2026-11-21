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
import 'package:bruig/plugin_system/canvas/model/elements/synth_module_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/synth_task_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/tile_map_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_looks.dart';

// element_reading.dart is the one place the model turns a saved element
// into its class, by kind. A new kind is added to the switch here (the
// compiler says so: the switch has no default).

/// elementFromJson reads a saved element as its kind's class. An unknown
/// kind (from a newer build) becomes a plain shape: a placeholder that can
/// be seen, where dropping it would lose it without a word.
CanvasElement elementFromJson(Map<String, dynamic> json) {
  var kind = ElementKind.fromName(json["kind"]) ?? ElementKind.shape;
  var base = ElementBase.fromJson(json, kind.label);
  switch (kind) {
    case ElementKind.text:
      // Its type's shadow, glow and outline read as layer looks
      // (text_looks.dart).
      return textLooksLifted(TextElement.fromJson(json, base));
    case ElementKind.image:
      return ImageElement.fromJson(json, base);
    case ElementKind.shape:
      return ShapeElement.fromJson(json, base);
    case ElementKind.line:
      return LineElement.fromJson(json, base);
    case ElementKind.chart:
      return ChartElement.fromJson(json, base);
    case ElementKind.table:
      return TableElement.fromJson(json, base);
    case ElementKind.button:
      return ButtonElement.fromJson(json, base);
    case ElementKind.background:
      return BackgroundElement.fromJson(json, base);
    case ElementKind.player:
      return TeamElement.fromJson(json, base);
    case ElementKind.path:
      return PathElement.fromJson(json, base);
    case ElementKind.counter:
      return CounterElement.fromJson(json, base);
    case ElementKind.audio:
      return AudioElement.fromJson(json, base);
    case ElementKind.video:
      return VideoElement.fromJson(json, base);
    case ElementKind.vector:
      return VectorElement.fromJson(json, base);
    case ElementKind.character3d:
      return Character3dElement.fromJson(json, base);
    case ElementKind.sheet:
      return SheetElement.fromJson(json, base);
    case ElementKind.camera:
      return CameraElement.fromJson(json, base);
    case ElementKind.object3d:
      return Object3dElement.fromJson(json, base);
    // Never saved alone (a background carries them), so read as an unknown
    // kind: a placeholder.
    case ElementKind.stage:
    case ElementKind.parallax:
      return ShapeElement.fromJson(json, base);
    case ElementKind.sprite:
      return SpriteElement.fromJson(json, base);
    case ElementKind.tileMap:
      return TileMapElement.fromJson(json, base);
    case ElementKind.synth:
      return SynthModuleElement.fromJson(json, base) ??
          ShapeElement.fromJson(json, base);
    case ElementKind.synthTask:
      return SynthTaskElement.fromJson(json, base);
    case ElementKind.metronome:
      return MetronomeElement.fromJson(json, base);
    case ElementKind.code:
      return CodeElement.fromJson(json, base);
    case ElementKind.codeRun:
      return CodeRunElement.fromJson(json, base);
    case ElementKind.codeTask:
      return CodeTaskElement.fromJson(json, base);
    case ElementKind.playTask:
      return PlayTaskElement.fromJson(json, base);
    case ElementKind.layout:
      return LayoutElement.fromJson(json, base);
  }
}
