import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';

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

/// SceneTransitionFamily groups the kinds in the picker.
///
/// The list is long enough that a flat one is a wall of names: asked in two
/// steps the question is "what sort of change" and then "which one", which is
/// how somebody actually chooses. The same shape the text animations use.
enum SceneTransitionFamily {
  none("None"),
  fade("Fade"),
  move("Move"),
  wipe("Uncover"),
  overlay("Overlay"),
  drawn("Drawn");

  final String label;
  const SceneTransitionFamily(this.label);
}

/// SceneTransitionWay is which way a transition that has a direction goes.
///
/// Its own setting rather than four kinds with the direction in their names.
/// The overlay ones each take a direction and two of them take a count as
/// well, and a list with every combination spelled out would be sixty names
/// for six ideas.
enum SceneTransitionWay {
  left("To the left"),
  right("To the right"),
  up("Upwards"),
  down("Downwards");

  final String label;
  const SceneTransitionWay(this.label);

  bool get horizontal => this == left || this == right;

  static SceneTransitionWay fromName(String? name) =>
      values.firstWhere((w) => w.name == name, orElse: () => right);
}

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

  slideLeft("The new one slides in, to the left"),
  slideRight("The new one slides in, to the right"),
  slideUp("The new one slides in, upwards"),
  slideDown("The new one slides in, downwards"),

  /// push shoves the old scene off with the new one, rather than sliding the
  /// new one over the top of it.
  pushLeft("Push left"),
  pushRight("Push right"),
  pushUp("Push up"),
  pushDown("Push down"),

  wipeLeft("The new one is uncovered, to the left"),
  wipeRight("The new one is uncovered, to the right"),
  wipeUp("The new one is uncovered, upwards"),
  wipeDown("The new one is uncovered, downwards"),

  /// zoom grows the new scene out of the middle of the old one.
  zoomIn("Zoom in"),
  zoomOut("Zoom out"),

  // The overlay family: something passes over the join rather than the two
  // scenes simply crossing. What they have in common is that the change
  // happens *under* something -- a band of colour, a shape opening, a set of
  // bars -- which is what makes a cut look deliberate rather than abrupt.
  /// band sweeps a panel of colour across, the scenes changing behind it.
  band("A band sweeps over", SceneTransitionFamily.overlay),

  /// blinds reveals the next scene through a set of bars.
  blinds("Blinds", SceneTransitionFamily.overlay),

  /// barn splits the old scene apart and lets the new one through.
  barn("Barn doors", SceneTransitionFamily.overlay),

  /// shapeWipe opens a shape in the middle of the old scene.
  shapeWipe("Shapes", SceneTransitionFamily.overlay),

  /// clock sweeps round like a hand.
  clock("Clock sweep", SceneTransitionFamily.overlay),

  /// blurThrough goes soft, changes, and comes back sharp.
  blurThrough("Blur through", SceneTransitionFamily.overlay),

  // The drawn family: transitions with a hand in them. Each is a mask made of
  // shapes rather than of rectangles -- paint thrown at the page, a brush
  // dragged across it, a comic's dots and speed lines -- and each is built
  // from its own seed, so the same transition is the same every time it is
  // played and every time it is exported.
  /// arrow drives an arrowhead across the page.
  arrow("Arrows", SceneTransitionFamily.drawn),

  /// splatter throws paint at it.
  splatter("Paint splatter", SceneTransitionFamily.drawn),

  /// brush drags strokes across it.
  brush("Brush strokes", SceneTransitionFamily.drawn),

  /// tiles breaks it into squares that turn over in a wave.
  tiles("Tiles turn over", SceneTransitionFamily.drawn),

  /// halftone grows a comic's dots until they meet.
  halftone("Comic halftone", SceneTransitionFamily.drawn),

  /// burst throws speed lines out of the middle.
  burst("Comic burst", SceneTransitionFamily.drawn);

  final String label;
  final SceneTransitionFamily family;
  const SceneTransitionKind(this.label,
      [this.family = SceneTransitionFamily.none]);

  /// covers is whether this kind works by putting something *over* the join
  /// rather than by showing one scene through the other.
  ///
  /// The whole overlay and drawn families do. What they draw is a shape in
  /// the transition's own colour that grows until it covers the page, and the
  /// scenes change behind it -- which is what an overlay is, and what these
  /// were not: built as masks, they were windows onto the next scene, so the
  /// next scene's backdrop arrived through a shape before the scene did.
  bool get covers =>
      familyOf == SceneTransitionFamily.overlay && this != blurThrough ||
      familyOf == SceneTransitionFamily.drawn;

  /// takesColour is whether the colour setting means anything for this one.
  bool get takesColour => this == through || this == blurThrough || covers;

  /// takesWay is whether it has a direction to be pointed in.
  bool get takesWay =>
      this == band ||
      this == blinds ||
      this == barn ||
      this == arrow ||
      this == brush ||
      this == tiles ||
      this == shapeWipe ||
      this == splatter;

  /// takesCount is whether it is made of a number of pieces.
  bool get takesCount =>
      this == blinds ||
      this == shapeWipe ||
      this == splatter ||
      this == brush ||
      this == tiles ||
      this == halftone ||
      this == burst ||
      this == arrow;

  /// takesSpacing is whether the room between those pieces means anything.
  bool get takesSpacing =>
      this == shapeWipe ||
      this == arrow ||
      this == splatter ||
      this == brush ||
      this == tiles ||
      this == halftone;

  /// takesAngle is whether the arrangement can be turned.
  bool get takesAngle =>
      this == arrow || this == brush || this == blinds || this == shapeWipe;

  /// takesRadius is whether each piece has a size of its own.
  bool get takesRadius =>
      this == shapeWipe ||
      this == splatter ||
      this == halftone ||
      this == arrow;

  /// takesShape is whether a shape decides what opens.
  bool get takesShape => this == shapeWipe;

  /// takesSoftness is whether its edge can be feathered.
  ///
  /// Everything that works by masking, which is most of the two later
  /// families: the edge of the mask is the edge of the transition, and a
  /// little softness is the difference between a shape being dragged over the
  /// page and something happening to it.
  bool get takesSoftness =>
      this == band ||
      this == blinds ||
      this == shapeWipe ||
      this == clock ||
      familyOf == SceneTransitionFamily.drawn;

  /// takesColour is also true of the drawn ones that put paint on the page.
  bool get paints => this == splatter || this == brush;

  /// inFamily is the kinds of one family, in the order they are listed.
  static List<SceneTransitionKind> inFamily(SceneTransitionFamily family) => [
        for (var kind in values)
          if (kind.familyOf == family) kind,
      ];

  /// familyOf is which group this kind belongs to, worked out from its own
  /// name for the ones that were here before families were.
  SceneTransitionFamily get familyOf {
    if (family != SceneTransitionFamily.none) return family;
    return switch (this) {
      cut => SceneTransitionFamily.none,
      fade || through => SceneTransitionFamily.fade,
      slideLeft ||
      slideRight ||
      slideUp ||
      slideDown ||
      pushLeft ||
      pushRight ||
      pushUp ||
      pushDown ||
      zoomIn ||
      zoomOut =>
        SceneTransitionFamily.move,
      _ => SceneTransitionFamily.wipe,
    };
  }

  /// seed is a number of this kind's own, so two transitions of different
  /// kinds do not throw their paint in the same places.
  int get seed => index * 7919;

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

  /// way is which direction the ones with a direction go.
  final SceneTransitionWay way;

  /// shape is what opens, for the shape wipe. Any of the shapes an element
  /// can be, drawn by the same code -- a transition that could only be a
  /// circle would be a second, smaller list of shapes to keep in step.
  final ShapeKind shape;

  /// count is how many pieces it is made of, for the blinds.
  final int count;

  /// spacing is the room between the pieces, as a fraction of a piece.
  final double spacing;

  /// angle turns the whole arrangement, in degrees. What lets a set of
  /// strokes or arrows run across a corner rather than along an edge.
  final double angle;

  /// radius is how large each piece is, as a fraction of the room it has.
  final double radius;

  /// softness feathers the edge, as a fraction of the page. Nothing is a hard
  /// edge; a little makes a wipe read as a light sweeping across rather than
  /// as a rectangle being dragged.
  final double softness;

  const SceneTransition({
    this.kind = SceneTransitionKind.cut,
    this.frames = 12,
    this.overlap = 12,
    this.color = const Color(0xFF000000),
    this.ease = SceneTransitionEase.smooth,
    this.way = SceneTransitionWay.right,
    this.shape = ShapeKind.circle,
    this.count = 6,
    this.spacing = 0.15,
    this.angle = 0,
    this.radius = 0.5,
    this.softness = 0,
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
    SceneTransitionWay? way,
    ShapeKind? shape,
    int? count,
    double? spacing,
    double? angle,
    double? radius,
    double? softness,
  }) =>
      SceneTransition(
        kind: kind ?? this.kind,
        frames: frames ?? this.frames,
        overlap: overlap ?? this.overlap,
        color: color ?? this.color,
        ease: ease ?? this.ease,
        way: way ?? this.way,
        shape: shape ?? this.shape,
        count: count ?? this.count,
        spacing: spacing ?? this.spacing,
        angle: angle ?? this.angle,
        radius: radius ?? this.radius,
        softness: softness ?? this.softness,
      );

  Map<String, dynamic> toJson() => {
        "kind": kind.name,
        if (frames != 12) "frames": frames,
        if (overlap != 12) "overlap": overlap,
        if (color != const Color(0xFF000000)) "color": colorToJson(color),
        if (ease != SceneTransitionEase.smooth) "ease": ease.name,
        if (way != SceneTransitionWay.right) "way": way.name,
        if (shape != ShapeKind.circle) "shape": shape.name,
        if (count != 6) "count": count,
        if (spacing != 0.15) "spacing": spacing,
        if (angle != 0) "angle": angle,
        if (radius != 0.5) "radius": radius,
        if (softness != 0) "softness": softness,
      };

  factory SceneTransition.fromJson(Map<String, dynamic> json) =>
      SceneTransition(
        kind: SceneTransitionKind.fromName(json["kind"] as String?),
        frames: jsonInt(json["frames"], 12).clamp(0, 600),
        overlap: jsonInt(json["overlap"], 12).clamp(0, 600),
        color: colorFromJson(json["color"], const Color(0xFF000000)),
        ease: SceneTransitionEase.fromName(json["ease"] as String?),
        way: SceneTransitionWay.fromName(json["way"] as String?),
        shape: ShapeKind.fromName(json["shape"] as String?),
        count: jsonInt(json["count"], 6).clamp(1, 40),
        spacing: jsonDouble(json["spacing"], 0.15).clamp(0.0, 2.0),
        angle: jsonDouble(json["angle"], 0).clamp(-180.0, 180.0),
        radius: jsonDouble(json["radius"], 0.5).clamp(0.05, 1.0),
        softness: jsonDouble(json["softness"], 0).clamp(0.0, 1.0),
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

  /// backgroundOff switches this canvas's backdrop off without forgetting it.
  ///
  /// For the shared canvas above all: a master worth having is often one that
  /// carries a logo and a transition and nothing else, and the scenes under
  /// it want their own backdrops. Without this the only way to stop the
  /// master covering them would be to throw its background away.
  final bool backgroundOff;

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
    this.backgroundOff = false,
    this.transition,
  });

  /// says is what the panel calls this scene: its name, or its place in the
  /// order when it has not been given one.
  String saysAt(int index) => name.isEmpty ? "Scene ${index + 1}" : name;

  /// sharedBackground is the backdrop this canvas puts on everything under
  /// it, or null where it has none or has been told not to.
  CanvasBackground? get sharedBackground => backgroundOff ? null : background;

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
    bool? backgroundOff,
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
        backgroundOff: backgroundOff ?? this.backgroundOff,
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
        if (backgroundOff) "backgroundOff": true,
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
      backgroundOff: jsonBool(json["backgroundOff"], false),
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
