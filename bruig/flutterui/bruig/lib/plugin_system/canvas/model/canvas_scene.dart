import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_background.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_limits.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/element_reading.dart';
import 'package:bruig/plugin_system/canvas/model/scene_camera.dart';
import 'package:bruig/plugin_system/canvas/model/scene_transition.dart';
import 'package:bruig/plugin_system/canvas/model/colour_map.dart';

// A scene's transition and camera are part of it, so whatever imports a
// scene has them.
export 'package:bruig/plugin_system/canvas/model/scene_camera.dart';
export 'package:bruig/plugin_system/canvas/model/scene_transition.dart';

// canvas_scene.dart is one canvas of several in a document: a set of
// elements, their drawing order, a length in frames and the actions along
// it. A document plays its scenes one after another (CanvasDocument.scene);
// the page's size, guides and publishing settings are the document's.

/// maxPageValues is how many values a page may carry (CanvasScene.values).
const maxPageValues = 100;

/// CanvasScene is one canvas in a document: what is on it, how long it runs,
/// and what happens at the end of it.
class CanvasScene {
  /// id is how a button's action names this scene, so renaming a scene does
  /// not break the button that goes to it.
  final String id;

  final String name;

  /// elements are painted first to last, so the last one is on top.
  final List<CanvasElement> elements;

  /// frames is this scene's length. One means a still.
  final int frames;

  final List<TimelineAction> actions;

  /// holds is whether playback stops at the end of this scene instead of
  /// going on to the next one.
  final bool holds;

  /// background is this canvas's own backdrop, or null to use the
  /// document's. Only the master scene uses it, so turning the master off
  /// takes its background with it.
  final CanvasBackground? background;

  /// backgroundOff switches this canvas's backdrop off without forgetting it,
  /// so a master can stop covering the scenes' own backdrops.
  final bool backgroundOff;

  /// masterOff leaves the master canvas off this one: a game's title screen
  /// or menu without the score and the lives the master shows on every
  /// level.
  final bool masterOff;

  /// values are this page's own values, by name, which a text reads with
  /// `{value:Name}` (see text_fields.dart): a master's running head that
  /// says the chapter a page is in.
  final Map<String, String> values;

  /// gameSounds are what each mixer channel does as a game comes to this
  /// scene, by channel key: "stop" stops it, `slot:<clip id>` plays that
  /// slot; a channel not here keeps playing. See CanvasController.gameSound.
  final Map<String, String> gameSounds;

  /// gameSoundsAtEnd are what each mixer channel does as a game leaves this
  /// scene, for the next or ending on it, as [gameSounds] says for its start.
  final Map<String, String> gameSoundsAtEnd;

  /// cues are this scene's own cues, by name, a row each (its channels' and
  /// elements' slots, launched together), or null with none named. A game's
  /// master has the cues of the channels every scene shares (the document's,
  /// SessionGrid.scenes). See CanvasCues.
  final List<String>? cues;

  /// cover marks this canvas as the outside of a document rather than a
  /// leaf; see PageCover. Kept on the scene so it survives reordering. Read
  /// only when the document is pages.
  final PageCover cover;

  /// transition is how this scene gives way to the next, or null for the
  /// document's default (the master scene's). Null rather than a copy, so
  /// changing the default reaches every scene without its own.
  final SceneTransition? transition;

  /// camera is this scene's slow move, or null to hold still. Applied in
  /// playback and export only; the editor shows the page still so a press
  /// lands where it looks.
  final SceneCamera? camera;

  // No strip of its own: the scenes' sound is one strip for the whole
  // canvas (CanvasDocument.scenesBus). A "bus" an older file kept here is
  // read into that.

  const CanvasScene({
    required this.id,
    this.name = "",
    this.elements = const [],
    this.frames = defaultFrameCount,
    this.actions = const [],
    this.holds = false,
    this.background,
    this.backgroundOff = false,
    this.masterOff = false,
    this.values = const {},
    this.gameSounds = const {},
    this.gameSoundsAtEnd = const {},
    this.cues,
    this.transition,
    this.cover = PageCover.none,
    this.camera,
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = CanvasScene(id: "");

  /// saysAt is what the panel calls this canvas: its name, or its kind and
  /// number. A cover is called by its cover label rather than a number.
  String saysAt(int index, [CanvasKind kind = CanvasKind.scenes]) {
    if (name.isNotEmpty) return name;
    if (kind.isPages && cover.isCover) return cover.label;
    return "${kind.oneCap} ${index + 1}";
  }

  /// sharedBackground is the backdrop this canvas puts on everything under
  /// it, or null where it has none or has been told not to.
  CanvasBackground? get sharedBackground => backgroundOff ? null : background;

  bool get custom => transition != null;

  CanvasScene copyWith({
    String? id,
    String? name,
    List<CanvasElement>? elements,
    int? frames,
    List<TimelineAction>? actions,
    bool? holds,
    CanvasBackground? background,
    bool clearBackground = false,
    bool? backgroundOff,
    bool? masterOff,
    Map<String, String>? values,
    Map<String, String>? gameSounds,
    Map<String, String>? gameSoundsAtEnd,
    List<String>? cues,
    SceneTransition? transition,
    bool clearTransition = false,
    PageCover? cover,
    SceneCamera? camera,
    bool clearCamera = false,
  }) =>
      CanvasScene(
        id: id ?? this.id,
        name: name ?? this.name,
        elements: elements ?? this.elements,
        frames: (frames ?? this.frames).clamp(1, maxFrameCount),
        actions: actions ?? this.actions,
        holds: holds ?? this.holds,
        background: clearBackground ? null : (background ?? this.background),
        backgroundOff: backgroundOff ?? this.backgroundOff,
        masterOff: masterOff ?? this.masterOff,
        values: values ?? this.values,
        gameSounds: gameSounds ?? this.gameSounds,
        gameSoundsAtEnd: gameSoundsAtEnd ?? this.gameSoundsAtEnd,
        cues: cues ?? this.cues,
        transition: clearTransition ? null : (transition ?? this.transition),
        cover: cover ?? this.cover,
        camera: clearCamera ? null : (camera ?? this.camera),
      );

  /// mapColours maps the scene's elements, its own backdrop (hidden while
  /// switched off) and its transition.
  CanvasScene mapColours(ColourMap f) {
    var p = ColourPass(f);
    var elements = p.list(this.elements, (e) => e.mapColours(f));
    var background = p.partOrNone(
        this.background, (b) => b.mapColours(f.shownOnlyIf(!backgroundOff)));
    var transition = p.partOrNone(this.transition, (t) => t.mapColours(f));
    if (!p.changed) return this;
    return copyWith(
        elements: elements, background: background, transition: transition);
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        if (name.isNotEmpty) "name": name,
        "elements": [for (var e in elements) e.toJson()],
        "frames": frames,
        if (actions.isNotEmpty) "actions": [for (var a in actions) a.toJson()],
        if (holds) "holds": true,
        if (background != null) "background": background!.toJson(),
        if (backgroundOff) "backgroundOff": true,
        if (masterOff) "masterOff": true,
        if (values.isNotEmpty) "values": values,
        if (gameSounds.isNotEmpty) "gameSounds": gameSounds,
        if (gameSoundsAtEnd.isNotEmpty) "gameSoundsEnd": gameSoundsAtEnd,
        if (cues case var c?) "cues": c,
        if (transition != null) "transition": transition!.toJson(),
        if (cover.isCover) "cover": cover.name,
        if (camera != null) "camera": camera!.toJson(),
      };

  factory CanvasScene.fromJson(Map<String, dynamic> json) {
    return CanvasScene(
      id: jsonId(json["id"], newSceneId()),
      name: jsonLabel(json["name"], _defaults.name),
      elements: jsonObjects(json["elements"], elementFromJson,
          most: maxSceneElements),
      frames: jsonInt(json["frames"], _defaults.frames).clamp(1, maxFrameCount),
      actions: jsonObjects(json["actions"], TimelineAction.fromJson),
      holds: jsonBool(json["holds"], false),
      background: jsonSpec(json["background"], CanvasBackground.fromJson, null),
      backgroundOff: jsonBool(json["backgroundOff"], false),
      masterOff: jsonBool(json["masterOff"], false),
      values: {
        if (json["values"] case Map raw)
          for (var MapEntry(:key, :value) in raw.entries.take(maxPageValues))
            if (key is String && value is String)
              jsonLabel(key, ""): jsonString(value, ""),
      },
      gameSounds: {
        if (json["gameSounds"] case Map raw)
          for (var MapEntry(:key, :value) in raw.entries)
            if (key is String && value is String) key: value,
      },
      gameSoundsAtEnd: {
        if (json["gameSoundsEnd"] case Map raw)
          for (var MapEntry(:key, :value) in raw.entries)
            if (key is String && value is String) key: value,
      },
      cues: json["cues"] is List
          ? [for (var c in json["cues"] as List) c is String ? c : ""]
          : null,
      transition: jsonSpec(json["transition"], SceneTransition.fromJson, null),
      cover: PageCover.fromName(jsonStr(json["cover"])),
      camera: SceneCamera.fromJson(json["camera"]),
    );
  }
}

/// newSceneId makes an id unique within a session, in the same shape as an
/// element's id.
int _sceneCounter = 0;
String newSceneId() => "sc${DateTime.now().microsecondsSinceEpoch}_"
    "${_sceneCounter++}";
