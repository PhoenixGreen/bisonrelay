import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/json_read.dart';
import 'package:bruig/plugin_system/canvas/model/colour_map.dart';

// scene_transition.dart is how one scene gives way to the next: the kinds
// of transition, the settings each reads, and a transition as saved on a
// scene (CanvasScene.transition). Drawing one is paintTransition, in
// render/scene_sequence.dart.

/// SceneTransitionFamily groups the kinds in the picker, so choosing is "what
/// sort of change" and then "which one".
enum SceneTransitionFamily {
  none("None"),
  fade("Fade"),
  move("Move"),
  wipe("Uncover"),
  overlay("Overlay"),
  drawn("Drawn"),

  /// paper is a leaf being turned, the transition a book uses.
  paper("Paper");

  final String label;
  const SceneTransitionFamily(this.label);
}

/// SceneTransitionWay is which way a transition with a direction goes: a
/// setting of its own, so the kinds need not spell out every direction.
enum SceneTransitionWay {
  /// inPlace grows where it is rather than crossing the page.
  inPlace("In place"),
  left("To the left"),
  right("To the right"),
  up("Upwards"),
  down("Downwards");

  final String label;
  const SceneTransitionWay(this.label);

  bool get horizontal => this == left || this == right || this == inPlace;

  /// waysFor is the directions worth offering for one kind. Barn doors take
  /// an axis rather than a side: left-and-right looks like right-and-left.
  static List<SceneTransitionWay> waysFor(SceneTransitionKind kind) {
    if (kind == SceneTransitionKind.barn) return const [left, up];
    if (kind == SceneTransitionKind.shapeWipe) return values;
    return const [left, right, up, down];
  }

  /// saysFor is what this way is called for [kind], which is not always the
  /// direction it points in.
  String saysFor(SceneTransitionKind kind) {
    if (kind != SceneTransitionKind.barn) return label;
    return this == up ? "Up and down" : "Side to side";
  }

  static SceneTransitionWay fromName(String? name) =>
      values.firstWhere((w) => w.name == name, orElse: () => right);
}

/// SceneTransitionSetting is a setting only some kinds of transition read.
/// Each kind lists its own (see [SceneTransitionKind.settings]), and the
/// panel offers those and no others.
enum SceneTransitionSetting {
  /// colour is the colour it goes through, or that passes over the join.
  colour,

  /// way is the direction it is pointed in.
  way,

  /// count is how many pieces it is made of.
  count,

  /// spacing is the room between those pieces.
  spacing,

  /// angle turns the whole arrangement.
  angle,

  /// radius is the size of each piece.
  radius,

  /// shape is the shape that opens.
  shape,

  /// centre is the point it grows from or shrinks to.
  centre,

  /// softness feathers its edge.
  softness,
}

const _colour = SceneTransitionSetting.colour;
const _way = SceneTransitionSetting.way;
const _count = SceneTransitionSetting.count;
const _spacing = SceneTransitionSetting.spacing;
const _angle = SceneTransitionSetting.angle;
const _radius = SceneTransitionSetting.radius;
const _shape = SceneTransitionSetting.shape;
const _centre = SceneTransitionSetting.centre;
const _softness = SceneTransitionSetting.softness;

const _fade = SceneTransitionFamily.fade;
const _move = SceneTransitionFamily.move;
const _wipe = SceneTransitionFamily.wipe;
const _overlay = SceneTransitionFamily.overlay;
const _drawn = SceneTransitionFamily.drawn;

/// SceneTransitionKind is each transition there is. A kind says here which
/// family the picker lists it under and which settings it reads; to add
/// one, add its line here, its starting values to
/// [SceneTransition.bestFor] where the usual ones do not suit, and its
/// drawing to paintTransition (render/scene_sequence.dart).
enum SceneTransitionKind {
  /// cut is no transition at all, and the default.
  cut("Cut", SceneTransitionFamily.none),

  /// fade crosses the two scenes over each other.
  fade("Cross fade", _fade),

  /// through goes out to a colour and back in from it: black, white, or
  /// whatever the design wants. See SceneTransition.color.
  through("Fade through a colour", _fade, {_colour}),

  slideLeft("Slide left", _move),
  slideRight("Slide right", _move),
  slideUp("Slide up", _move),
  slideDown("Slide down", _move),

  /// push shoves the old scene off with the new one, rather than sliding the
  /// new one over the top of it.
  pushLeft("Push left", _move),
  pushRight("Push right", _move),
  pushUp("Push up", _move),
  pushDown("Push down", _move),

  wipeLeft("Uncover left", _wipe),
  wipeRight("Uncover right", _wipe),
  wipeUp("Uncover up", _wipe),
  wipeDown("Uncover down", _wipe),

  /// zoom grows the new scene out of the middle of the old one.
  zoomIn("Zoom in", _move, {_centre}),
  zoomOut("Zoom out", _move, {_centre}),

  // The overlay family: the change happens under something passing over the
  // join: a band of colour, a shape opening, a set of bars.

  /// band sweeps a panel of colour across, the scenes changing behind it.
  band("A band sweeps over", _overlay, {_colour, _way, _softness}),

  /// blinds reveals the next scene through a set of bars.
  blinds("Blinds", _overlay, {_colour, _way, _count, _angle, _softness}),

  /// barn splits the old scene apart and lets the new one through.
  barn("Barn doors", _overlay, {_colour, _way}),

  /// shapeWipe opens a shape in the middle of the old scene.
  shapeWipe("Shapes", _overlay,
      {_colour, _way, _count, _spacing, _angle, _radius, _shape, _softness}),

  /// clock sweeps round like a hand.
  clock("Clock sweep", _overlay, {_colour, _softness}),

  /// blurThrough goes soft, changes, and comes back sharp.
  blurThrough("Blur through", _overlay, {_colour}),

  // The drawn family: shapes with a hand in them: paint, brush strokes, a
  // comic's dots and speed lines. Each is built from its kind's seed, so it
  // is the same every time it is played or exported.

  /// arrow drives an arrowhead across the page.
  arrow("Arrows", _drawn,
      {_colour, _way, _count, _spacing, _angle, _radius, _softness}),

  /// splatter throws paint at it.
  splatter("Paint splatter", _drawn,
      {_colour, _way, _count, _spacing, _radius, _softness}),

  /// brush drags strokes across it.
  brush("Brush strokes", _drawn,
      {_colour, _way, _count, _spacing, _angle, _softness}),

  /// tiles breaks it into squares that turn over in a wave.
  tiles(
      "Tiles turn over", _drawn, {_colour, _way, _count, _spacing, _softness}),

  /// halftone grows a comic's dots until they meet.
  halftone("Comic halftone", _drawn,
      {_colour, _count, _spacing, _radius, _softness}),

  /// burst throws speed lines out of the middle, and they carry on out of
  /// the picture rather than coming back.
  burst("Comic burst", _drawn, {_colour, _count, _softness}),

  /// rays swings the same lines shut like a fan and open again.
  rays("Comic rays", _drawn, {_colour, _count, _softness}),

  /// pageTurn turns the leaf over about its spine, the next page underneath.
  /// With facing pages the right-hand leaf turns and its back is the next
  /// left-hand page, a sheet printed on both sides. See paintPageTurn.
  pageTurn("Page turn", SceneTransitionFamily.paper);

  final String label;

  /// family is the group the picker lists it under.
  final SceneTransitionFamily family;

  /// settings is the settings it reads, besides its length and timing.
  final Set<SceneTransitionSetting> settings;

  const SceneTransitionKind(this.label, this.family,
      [this.settings = const {}]);

  /// covers is whether this kind works by putting something *over* the join
  /// rather than by showing one scene through the other: a shape in the
  /// transition's colour grows until it covers the page and the scenes
  /// change behind it. Not a mask, which would show the next scene's
  /// backdrop through the shape before the scene arrived.
  bool get covers =>
      family == SceneTransitionFamily.overlay && this != blurThrough ||
      family == SceneTransitionFamily.drawn;

  bool get takesColour => settings.contains(_colour);
  bool get takesWay => settings.contains(_way);
  bool get takesCount => settings.contains(_count);
  bool get takesSpacing => settings.contains(_spacing);
  bool get takesAngle => settings.contains(_angle);
  bool get takesRadius => settings.contains(_radius);
  bool get takesShape => settings.contains(_shape);
  bool get takesCentre => settings.contains(_centre);
  bool get takesSoftness => settings.contains(_softness);

  /// paints is whether this is a drawn kind that puts paint on the page.
  bool get paints => this == splatter || this == brush;

  /// inFamily is the kinds of one family, in the order they are listed.
  static List<SceneTransitionKind> inFamily(SceneTransitionFamily family) => [
        for (var kind in values)
          if (kind.family == family) kind,
      ];

  /// seed is a number of this kind's own, so two transitions of different
  /// kinds do not throw their paint in the same places.
  int get seed => index * 7919;

  bool get isCut => this == cut;

  static SceneTransitionKind fromName(String? name) =>
      values.firstWhere((k) => k.name == name, orElse: () => cut);
}

/// SceneTransitionEase is how a movement is timed from its start to its
/// end: a transition's, and a scene camera's.
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

/// SceneTransition is how a scene gives way to the one after it.
class SceneTransition {
  final SceneTransitionKind kind;

  final int frames;

  /// overlap is how many of those frames both scenes are playing for. Zero
  /// freezes the outgoing scene on its last frame while the incoming one has
  /// not started.
  final int overlap;

  /// color is what a transition through a colour goes through.
  final Color color;

  /// ease is how the movement is timed, for the kinds that move.
  final SceneTransitionEase ease;

  final SceneTransitionWay way;

  /// shape is what opens, for the shape wipe: any shape an element can be.
  final ShapeKind shape;

  /// count is how many pieces it is made of. See takesCount.
  final int count;

  /// spacing is the room between the pieces, as a fraction of a piece.
  final double spacing;

  /// angle turns the whole arrangement, in degrees.
  final double angle;

  /// radius is how large each piece is, as a fraction of the room it has.
  final double radius;

  /// softness feathers the edge, as a fraction of the page. Zero is a hard
  /// edge.
  final double softness;

  /// centreX and centreY are where a zoom grows from or shrinks to, as
  /// fractions of the page across and down: the middle by default.
  final double centreX, centreY;

  /// sound is the Audio store id heard as the transition plays, or empty for
  /// silence. It moves with the transition when a scene's length changes.
  /// See CanvasDocument.transitionSounds.
  final String sound;
  final String soundName;

  /// soundLength is the file's length in seconds, soundVolume how loud it
  /// plays, and soundLead how many frames before the transition it starts.
  final double soundLength;
  final double soundVolume;
  final int soundLead;

  /// label is what its slot is called, or "" for what it does: "→ the next
  /// scene · its kind".
  final String label;

  const SceneTransition({
    this.label = "",
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
    this.centreX = 0.5,
    this.centreY = 0.5,
    this.sound = "",
    this.soundName = "",
    this.soundLength = 0,
    this.soundVolume = 0.5,
    this.soundLead = 6,
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = SceneTransition();

  /// cut is the default: nothing between one scene and the next.
  static const cut = SceneTransition();

  /// bestFor is the starting settings for [kind], used when a kind is chosen
  /// or reset, so it never inherits what the last kind left behind.
  static SceneTransition bestFor(SceneTransitionKind kind) {
    var length = switch (kind) {
      SceneTransitionKind.cut => 0,
      SceneTransitionKind.splatter || SceneTransitionKind.brush => 22,
      SceneTransitionKind.burst || SceneTransitionKind.rays => 18,
      SceneTransitionKind.arrow || SceneTransitionKind.shapeWipe => 20,
      SceneTransitionKind.halftone || SceneTransitionKind.tiles => 20,
      SceneTransitionKind.blinds || SceneTransitionKind.barn => 16,
      SceneTransitionKind.clock || SceneTransitionKind.band => 18,
      // About as long as a hand takes over a page at film's rate.
      SceneTransitionKind.pageTurn => 16,
      _ => 14,
    };
    // Bars, splats, strokes, dots, rays or shapes, depending on the kind.
    var pieces = switch (kind) {
      SceneTransitionKind.blinds => 8,
      SceneTransitionKind.shapeWipe => 5,
      SceneTransitionKind.splatter => 16,
      SceneTransitionKind.brush => 5,
      SceneTransitionKind.tiles => 8,
      SceneTransitionKind.halftone => 16,
      SceneTransitionKind.burst || SceneTransitionKind.rays => 12,
      SceneTransitionKind.arrow => 4,
      _ => 6,
    };
    var apart = switch (kind) {
      SceneTransitionKind.arrow => 0.3,
      SceneTransitionKind.brush => 0.1,
      SceneTransitionKind.shapeWipe => 0.2,
      SceneTransitionKind.splatter => 0.25,
      _ => 0.15,
    };
    var size = switch (kind) {
      SceneTransitionKind.arrow => 0.6,
      SceneTransitionKind.splatter => 0.45,
      SceneTransitionKind.halftone => 0.55,
      _ => 0.5,
    };
    // Softness only where the edge is a straight line; ragged edges stay
    // sharp.
    var soft = switch (kind) {
      SceneTransitionKind.band ||
      SceneTransitionKind.blinds ||
      SceneTransitionKind.clock ||
      SceneTransitionKind.shapeWipe =>
        0.04,
      _ => 0.0,
    };
    return SceneTransition(
      kind: kind,
      frames: length,
      overlap: length,
      // A way this kind offers: barn doors have no "right", and the picker
      // would show nothing chosen.
      way: SceneTransitionWay.waysFor(kind).contains(SceneTransitionWay.right)
          ? SceneTransitionWay.right
          : SceneTransitionWay.waysFor(kind).first,
      ease: kind.family == SceneTransitionFamily.move ||
              kind == SceneTransitionKind.pageTurn
          ? SceneTransitionEase.smooth
          : SceneTransitionEase.straight,
      count: pieces,
      spacing: apart,
      radius: size,
      softness: soft,
    );
  }

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
    double? centreX,
    double? centreY,
    String? sound,
    String? soundName,
    double? soundLength,
    double? soundVolume,
    int? soundLead,
    String? label,
  }) =>
      SceneTransition(
        label: label ?? this.label,
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
        centreX: centreX ?? this.centreX,
        centreY: centreY ?? this.centreY,
        sound: sound ?? this.sound,
        soundName: soundName ?? this.soundName,
        soundLength: soundLength ?? this.soundLength,
        soundVolume: soundVolume ?? this.soundVolume,
        soundLead: soundLead ?? this.soundLead,
      );

  /// mapColours maps the colour it goes through, shown only while it is on
  /// and of a kind that takes a colour.
  SceneTransition mapColours(ColourMap f) {
    var next = f(color, shown: on && kind.takesColour);
    return next == color ? this : copyWith(color: next);
  }

  Map<String, dynamic> toJson() => {
        "kind": kind.name,
        if (frames != _defaults.frames) "frames": frames,
        if (overlap != _defaults.overlap) "overlap": overlap,
        if (color != _defaults.color) "color": colorToJson(color),
        if (ease != _defaults.ease) "ease": ease.name,
        if (way != _defaults.way) "way": way.name,
        if (shape != _defaults.shape) "shape": shape.name,
        if (count != _defaults.count) "count": count,
        if (spacing != _defaults.spacing) "spacing": spacing,
        if (angle != _defaults.angle) "angle": angle,
        if (radius != _defaults.radius) "radius": radius,
        if (softness != _defaults.softness) "softness": softness,
        if (centreX != _defaults.centreX) "centreX": centreX,
        if (centreY != _defaults.centreY) "centreY": centreY,
        if (label.isNotEmpty) "label": label,
        if (sound.isNotEmpty) ...{
          "sound": sound,
          if (soundName.isNotEmpty) "soundName": soundName,
          "soundLength": soundLength,
          if (soundVolume != _defaults.soundVolume) "soundVolume": soundVolume,
          if (soundLead != _defaults.soundLead) "soundLead": soundLead,
        },
      };

  factory SceneTransition.fromJson(Map<String, dynamic> json) =>
      SceneTransition(
        kind: SceneTransitionKind.fromName(jsonStr(json["kind"])),
        frames: jsonInt(json["frames"], _defaults.frames).clamp(0, 600),
        overlap: jsonInt(json["overlap"], _defaults.overlap).clamp(0, 600),
        color: colorFromJson(json["color"], _defaults.color),
        ease: SceneTransitionEase.fromName(jsonStr(json["ease"])),
        way: SceneTransitionWay.fromName(jsonStr(json["way"])),
        // Absent means a circle, which toJson leaves out. ShapeKind.fromName
        // falls back to a rectangle.
        shape: json["shape"] == null
            ? ShapeKind.circle
            : ShapeKind.fromName(jsonStr(json["shape"])),
        count: jsonInt(json["count"], _defaults.count).clamp(1, 40),
        spacing: jsonDouble(json["spacing"], _defaults.spacing).clamp(0.0, 2.0),
        angle: jsonDouble(json["angle"], _defaults.angle).clamp(-180.0, 180.0),
        radius: jsonDouble(json["radius"], _defaults.radius).clamp(0.05, 1.0),
        softness:
            jsonDouble(json["softness"], _defaults.softness).clamp(0.0, 1.0),
        centreX: jsonDouble(json["centreX"], _defaults.centreX).clamp(0.0, 1.0),
        centreY: jsonDouble(json["centreY"], _defaults.centreY).clamp(0.0, 1.0),
        sound: jsonString(json["sound"], _defaults.sound),
        soundName: jsonString(json["soundName"], _defaults.soundName),
        soundLength: jsonDouble(json["soundLength"], _defaults.soundLength)
            .clamp(0.0, 3600.0),
        soundVolume: jsonDouble(json["soundVolume"], _defaults.soundVolume)
            .clamp(0.0, 2.0),
        soundLead:
            jsonInt(json["soundLead"], _defaults.soundLead).clamp(-240, 240),
        label: jsonString(json["label"], _defaults.label),
      );
}
