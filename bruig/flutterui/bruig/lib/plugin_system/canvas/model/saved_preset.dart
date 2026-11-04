import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/preset_scaling.dart';

// saved_preset.dart is a saved scene, canvas, brush, look or similar: the
// thing's own JSON with a name on it (as element_preset.dart does), so
// nothing here changes as they grow settings. A preset is a copy, not a link.

/// SavedPresetKind is what a saved preset holds.
enum SavedPresetKind {
  /// scene is one canvas of a document, with everything on it.
  scene("scenes"),

  /// canvas is a whole document: its page, its backdrop and all its scenes.
  canvas("canvases"),

  /// brush is a pencil brush somebody made. See VectorBrush.
  brush("brushes"),

  /// pitchView is a sports pitch's camera somebody liked.
  pitchView("pitch-views"),

  /// look is a picture's grade (adjustments, textures and colour layers) to
  /// put on another picture. See lookData.
  look("looks"),

  /// paintBrush is a brush for a picture's paint layers. See BrushPreset.
  paintBrush("paint-brushes");

  /// folder is where these are kept on disk, under the presets folder.
  final String folder;
  const SavedPresetKind(this.folder);
}

/// SavedPreset is one of them.
class SavedPreset {
  /// id names the file this is kept in.
  final String id;

  final String name;
  final SavedPresetKind kind;

  /// data is the scene's or the document's own JSON.
  final Map<String, dynamic> data;

  /// made is when it was saved; it orders presets that share a name.
  final DateTime made;

  /// madeOn is the page it was designed on, so a scene dropped on another
  /// page shape arrives scaled to fit (see presetScale). A canvas preset also
  /// carries its page in its own JSON.
  final Size? madeOn;

  const SavedPreset({
    required this.id,
    required this.name,
    required this.kind,
    required this.data,
    required this.made,
    this.madeOn,
  });

  /// buildScene is a fresh scene from this preset, under new ids: scenes or
  /// elements sharing an id are one as far as Go to scene and selection are
  /// concerned.
  CanvasScene? buildScene({Size? on}) {
    if (kind != SavedPresetKind.scene) return null;
    var scene = CanvasScene.fromJson(data);
    var fresh = scene.copyWith(
      id: newSceneId(),
      elements: [for (var e in scene.elements) e.withId(newElementId())],
    );
    // Sized to the page it arrives on, where one is given.
    return on == null ? fresh : scaledScene(fresh, presetScale(madeOn, on));
  }

  /// buildDocument is a fresh document from this preset, ids and all.
  CanvasDocument? buildDocument() {
    if (kind != SavedPresetKind.canvas) return null;
    var document = CanvasDocument.fromJson(data);
    return document.withScenes([
      for (var scene in document.allScenes)
        scene.copyWith(
          id: newSceneId(),
          elements: [for (var e in scene.elements) e.withId(newElementId())],
        ),
    ], at: 0);
  }

  /// buildScenes is what this preset adds to a document that is already
  /// open: one scene, or every scene of a saved canvas.
  ///
  /// A canvas preset dropped into a document adds only its scenes; the page
  /// size and backdrop stay the open document's.
  List<CanvasScene> buildScenes({Size? on}) => switch (kind) {
        SavedPresetKind.scene => [if (buildScene(on: on) case var s?) s],
        SavedPresetKind.canvas => _canvasScenes(on),
        SavedPresetKind.brush ||
        SavedPresetKind.pitchView ||
        SavedPresetKind.look ||
        SavedPresetKind.paintBrush =>
          const [],
      };

  /// _canvasScenes is a saved canvas's scenes, scaled from its own page to
  /// the page they are added to.
  List<CanvasScene> _canvasScenes(Size? on) {
    var document = buildDocument();
    if (document == null) return const [];
    var by = on == null ? 1.0 : presetScale(document.size.size, on);
    return [for (var scene in document.allScenes) scaledScene(scene, by)];
  }

  SavedPreset copyWith({String? name}) => SavedPreset(
        id: id,
        name: name ?? this.name,
        kind: kind,
        data: data,
        made: made,
        madeOn: madeOn,
      );

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "kind": kind.name,
        "made": made.toIso8601String(),
        if (madeOn case var made?) "madeOn": sizeToJson(made),
        "data": data,
      };

  factory SavedPreset.fromJson(Map<String, dynamic> json) => SavedPreset(
        id: jsonString(json["id"], ""),
        name: jsonString(json["name"], "Preset"),
        kind: SavedPresetKind.values.firstWhere(
          (k) => k.name == json["kind"],
          orElse: () => SavedPresetKind.scene,
        ),
        data: json["data"] is Map<String, dynamic>
            ? json["data"] as Map<String, dynamic>
            : const {},
        made: DateTime.tryParse(jsonString(json["made"], "")) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        madeOn: sizeFromJson(json["madeOn"]),
      );
}
