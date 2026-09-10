import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// canvas_scene.dart is one canvas of several in a document.
//
// A scene is what the whole document used to be: a set of elements, an order
// to draw them in, a length in frames and the actions along it. A document is
// a list of them, played one after another, and a document with one scene in
// it is exactly the document there was before -- which is why nothing above
// this file had to learn a new word to keep working. See CanvasDocument.scene.
//
// What a scene is *not* is a copy of the whole document. The page's size, its
// background, its guides and what it will be published as belong to the
// document: they are what makes the scenes one piece of work rather than
// several. A scene that could change the page size would be a second
// document with extra steps.

/// SceneTransitionKind is how one scene becomes the next.
enum SceneTransitionKind {
  /// cut is no transition at all: the last frame of one scene, then the first
  /// frame of the next. The default, because it is what film does most of the
  /// time and the only one that costs nothing.
  cut("Cut"),

  /// fade crosses the two scenes over each other.
  fade("Cross fade"),

  /// through goes out to a colour and back in from it -- black, white, or
  /// whatever the design wants. See SceneTransition.color.
  through("Fade through a colour"),

  slideLeft("Slide left"),
  slideRight("Slide right"),
  slideUp("Slide up"),
  slideDown("Slide down"),

  /// push shoves the old scene off with the new one, rather than sliding the
  /// new one over the top of it.
  pushLeft("Push left"),
  pushRight("Push right"),
  pushUp("Push up"),
  pushDown("Push down"),

  wipeLeft("Wipe left"),
  wipeRight("Wipe right"),
  wipeUp("Wipe up"),
  wipeDown("Wipe down"),

  /// zoom grows the new scene out of the middle of the old one.
  zoomIn("Zoom in"),
  zoomOut("Zoom out");

  final String label;
  const SceneTransitionKind(this.label);

  /// takesColour is whether the colour setting means anything for this one.
  bool get takesColour => this == through;

  /// isCut is whether nothing is drawn between the two scenes.
  bool get isCut => this == cut;

  static SceneTransitionKind fromName(String? name) =>
      values.firstWhere((k) => k.name == name, orElse: () => cut);
}

/// SceneTransition is how a scene gives way to the one after it.
class SceneTransition {
  final SceneTransitionKind kind;

  /// frames is how long it takes.
  final int frames;

  /// overlap is how many of those frames the two scenes are both playing
  /// for.
  ///
  /// Its own number rather than the whole length, because the two are
  /// different questions: a cross fade of twelve frames where both scenes run
  /// for all twelve is one thing, and a fade to black where each scene has
  /// six frames to itself is another. Zero means the outgoing scene is frozen
  /// on its last frame while the incoming one has not started.
  final int overlap;

  /// color is what a transition through a colour goes through.
  final Color color;

  /// ease is how the movement is timed, for the ones that move.
  final SceneTransitionEase ease;

  const SceneTransition({
    this.kind = SceneTransitionKind.cut,
    this.frames = 12,
    this.overlap = 12,
    this.color = const Color(0xFF000000),
    this.ease = SceneTransitionEase.smooth,
  });

  /// cut is the default: nothing between one scene and the next.
  static const cut = SceneTransition();

  /// on is whether anything is drawn between the two scenes.
  bool get on => !kind.isCut && frames > 0;

  SceneTransition copyWith({
    SceneTransitionKind? kind,
    int? frames,
    int? overlap,
    Color? color,
    SceneTransitionEase? ease,
  }) =>
      SceneTransition(
        kind: kind ?? this.kind,
        frames: frames ?? this.frames,
        overlap: overlap ?? this.overlap,
        color: color ?? this.color,
        ease: ease ?? this.ease,
      );

  Map<String, dynamic> toJson() => {
        "kind": kind.name,
        if (frames != 12) "frames": frames,
        if (overlap != 12) "overlap": overlap,
        if (color != const Color(0xFF000000)) "color": colorToJson(color),
        if (ease != SceneTransitionEase.smooth) "ease": ease.name,
      };

  factory SceneTransition.fromJson(Map<String, dynamic> json) =>
      SceneTransition(
        kind: SceneTransitionKind.fromName(json["kind"] as String?),
        frames: jsonInt(json["frames"], 12).clamp(0, 600),
        overlap: jsonInt(json["overlap"], 12).clamp(0, 600),
        color: colorFromJson(json["color"], const Color(0xFF000000)),
        ease: SceneTransitionEase.fromName(json["ease"] as String?),
      );
}

/// SceneTransitionEase is how a moving transition is timed.
enum SceneTransitionEase {
  straight("Straight"),
  smooth("Smooth"),
  quick("Quick then slow"),
  slow("Slow then quick");

  final String label;
  const SceneTransitionEase(this.label);

  static SceneTransitionEase fromName(String? name) =>
      values.firstWhere((e) => e.name == name, orElse: () => smooth);

  /// apply maps 0..1 onto the eased value.
  double apply(double t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    switch (this) {
      case SceneTransitionEase.straight:
        return t;
      case SceneTransitionEase.smooth:
        return t * t * (3 - 2 * t);
      case SceneTransitionEase.quick:
        return 1 - (1 - t) * (1 - t);
      case SceneTransitionEase.slow:
        return t * t;
    }
  }
}

/// CanvasScene is one canvas in a document: what is on it, how long it runs,
/// and what happens at the end of it.
class CanvasScene {
  /// id is how a button's action names this scene, so renaming a scene does
  /// not break the button that goes to it.
  final String id;

  final String name;

  /// elements are painted first to last, so the last one is on top -- the
  /// same order the document's own list had, because it is that list.
  final List<CanvasElement> elements;

  /// frames is this scene's length. One means a still.
  final int frames;

  final List<TimelineAction> actions;

  /// holds is whether playback stops at the end of this scene instead of
  /// going on to the next one.
  ///
  /// For the two moments it is wanted: a scene being worked on, where running
  /// into the next one is a distraction, and the end of a sequence that is
  /// meant to sit on its last frame rather than loop away from it.
  final bool holds;

  /// background is this canvas's own backdrop, or null to use the
  /// document's.
  ///
  /// Only the master scene uses it, and that is the point: a background put
  /// on the shared canvas belongs to the shared canvas. Written to the
  /// document's own background instead, as it was, turning the master off
  /// left every scene wearing it with nothing to say where it came from.
  final CanvasBackground? background;

  /// transition is how this scene gives way to the next, or null for whatever
  /// the document's default is -- see CanvasDocument.defaultTransition, which
  /// is the master scene's.
  ///
  /// Null rather than a copy of the default, so changing the default changes
  /// every scene that has not been given one of its own. A scene with its own
  /// is what the panel marks as custom.
  final SceneTransition? transition;

  const CanvasScene({
    required this.id,
    this.name = "",
    this.elements = const [],
    this.frames = defaultFrameCount,
    this.actions = const [],
    this.holds = false,
    this.background,
    this.transition,
  });

  /// says is what the panel calls this scene: its name, or its place in the
  /// order when it has not been given one.
  String saysAt(int index) => name.isEmpty ? "Scene ${index + 1}" : name;

  /// custom is whether this scene has a transition of its own rather than the
  /// document's.
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
    SceneTransition? transition,
    bool clearTransition = false,
  }) =>
      CanvasScene(
        id: id ?? this.id,
        name: name ?? this.name,
        elements: elements ?? this.elements,
        frames: (frames ?? this.frames).clamp(1, maxFrameCount),
        actions: actions ?? this.actions,
        holds: holds ?? this.holds,
        background: clearBackground ? null : (background ?? this.background),
        transition: clearTransition ? null : (transition ?? this.transition),
      );

  Map<String, dynamic> toJson() => {
        "id": id,
        if (name.isNotEmpty) "name": name,
        "elements": [for (var e in elements) e.toJson()],
        "frames": frames,
        if (actions.isNotEmpty) "actions": [for (var a in actions) a.toJson()],
        if (holds) "holds": true,
        if (background != null) "background": background!.toJson(),
        if (transition != null) "transition": transition!.toJson(),
      };

  factory CanvasScene.fromJson(Map<String, dynamic> json) {
    var elements = json["elements"];
    var actions = json["actions"];
    return CanvasScene(
      id: jsonString(json["id"], newSceneId()),
      name: jsonString(json["name"], ""),
      elements: elements is List
          ? [
              for (var e in elements)
                if (e is Map<String, dynamic>) elementFromJson(e),
            ]
          : const [],
      frames:
          jsonInt(json["frames"], defaultFrameCount).clamp(1, maxFrameCount),
      actions: actions is List
          ? [
              for (var a in actions)
                if (a is Map<String, dynamic>) TimelineAction.fromJson(a),
            ]
          : const [],
      holds: jsonBool(json["holds"], false),
      background: json["background"] is Map<String, dynamic>
          ? CanvasBackground.fromJson(
              json["background"] as Map<String, dynamic>)
          : null,
      transition: json["transition"] is Map<String, dynamic>
          ? SceneTransition.fromJson(json["transition"] as Map<String, dynamic>)
          : null,
    );
  }
}

/// _sceneCounter and newSceneId make ids that are unique within a session.
///
/// The same shape as an element's id and for the same reason: a button's
/// action names a scene by id, so a scene has to keep its name across a
/// rename, a reorder and a save.
int _sceneCounter = 0;
String newSceneId() => "sc${DateTime.now().microsecondsSinceEpoch}_"
    "${_sceneCounter++}";
