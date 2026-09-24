import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/preset_scaling.dart';

// saved_preset.dart is a scene or a whole canvas somebody wants again.
//
// The same bargain an element preset makes -- see element_preset.dart -- of a
// whole thing saved as its own JSON with a name on it, so there is nothing
// here to keep in step as scenes and documents grow settings.
//
// A preset is a copy and not a link. What is saved is what was there at the
// moment of saving; editing the scene it came from afterwards changes
// nothing, which is the point of saving one at all.

/// SavedPresetKind is what a saved preset holds.
enum SavedPresetKind {
  /// scene is one canvas of a document, with everything on it.
  scene("scenes"),

  /// canvas is a whole document: its page, its backdrop and all its scenes.
  canvas("canvases");

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

  /// made is when it was saved, which is how the list is ordered where two
  /// presets share a name.
  final DateTime made;

  /// madeOn is the page it was designed on.
  ///
  /// Kept so that a scene saved on a banner and dropped on a square canvas
  /// arrives at the scale it was designed at rather than hanging off the
  /// side -- see presetScale. A canvas preset carries its page in its own
  /// JSON as well; this is what a *scene* has no other way of saying.
  final Size? madeOn;

  const SavedPreset({
    required this.id,
    required this.name,
    required this.kind,
    required this.data,
    required this.made,
    this.madeOn,
  });

  /// scene is a fresh scene from this preset, under new ids.
  ///
  /// New ids every time, and it matters for the same reason an element's
  /// does: two scenes sharing one are one scene as far as a button's Go to
  /// scene is concerned, and two elements sharing one cannot both be
  /// selected.
  CanvasScene? buildScene({Size? on}) {
    if (kind != SavedPresetKind.scene) return null;
    var scene = CanvasScene.fromJson(data);
    var fresh = scene.copyWith(
      id: newSceneId(),
      elements: [for (var e in scene.elements) e.withId(newElementId())],
    );
    // Sized to the page it is arriving on, where one was given and it is not
    // the page it was made on.
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
  /// A canvas preset can start a document of its own, and it can also be
  /// dropped into one -- and dropped in, what it is is its scenes. Its page
  /// size and backdrop stay with the document being worked on, which is the
  /// only thing that can be meant by adding one canvas to another.
  List<CanvasScene> buildScenes({Size? on}) => switch (kind) {
        SavedPresetKind.scene => [if (buildScene(on: on) case var s?) s],
        SavedPresetKind.canvas => _canvasScenes(on),
      };

  /// _canvasScenes is a saved canvas's scenes, sized to the page they are
  /// being added to.
  ///
  /// The page a canvas preset was made on is its own -- it is a whole
  /// document -- so that is what its scenes are scaled from.
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
