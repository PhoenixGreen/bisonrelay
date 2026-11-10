import 'dart:math' as math;
import 'dart:ui' show Color, Offset, Rect;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart' show ChannelMix;

// canvas_scene.dart is one canvas of several in a document.
//
// A scene is a set of elements, the order they are drawn in, a length in
// frames and the actions along it. A document plays its scenes one after
// another; see CanvasDocument.scene. The page's size, guides and publishing
// settings belong to the document, not to a scene.

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

/// SceneTransitionWay is which way a transition that has a direction goes.
/// A setting of its own, so the kinds list does not spell out every
/// direction.
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
  /// an axis rather than a side, since left-and-right looks the same as
  /// right-and-left.
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

/// SceneTransitionKind is how one scene becomes the next.
enum SceneTransitionKind {
  /// cut is no transition at all, and the default.
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

  wipeLeft("Uncover left"),
  wipeRight("Uncover right"),
  wipeUp("Uncover up"),
  wipeDown("Uncover down"),

  /// zoom grows the new scene out of the middle of the old one.
  zoomIn("Zoom in"),
  zoomOut("Zoom out"),

  // The overlay family: the change happens under something passing over the
  // join -- a band of colour, a shape opening, a set of bars.

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

  // The drawn family: shapes with a hand in them -- paint, brush strokes, a
  // comic's dots and speed lines. Each is built from its kind's seed, so it
  // is the same every time it is played or exported.

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

  /// burst throws speed lines out of the middle, and they carry on out of
  /// the picture rather than coming back.
  burst("Comic burst", SceneTransitionFamily.drawn),

  /// rays swings the same lines shut like a fan and open again.
  rays("Comic rays", SceneTransitionFamily.drawn),

  /// pageTurn turns the leaf over about its spine, the next page underneath.
  /// With facing pages the right-hand leaf turns and its back is the next
  /// left-hand page, a sheet printed on both sides. See paintPageTurn.
  pageTurn("Page turn", SceneTransitionFamily.paper);

  final String label;
  final SceneTransitionFamily family;
  const SceneTransitionKind(this.label,
      [this.family = SceneTransitionFamily.none]);

  /// covers is whether this kind works by putting something *over* the join
  /// rather than by showing one scene through the other: a shape in the
  /// transition's colour grows until it covers the page and the scenes
  /// change behind it. Not a mask, which would show the next scene's
  /// backdrop through the shape before the scene arrived.
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
      this == rays ||
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

  /// takesCentre is whether it grows from, or shrinks to, a point that can
  /// be moved from the middle: a zoom.
  bool get takesCentre => this == zoomIn || this == zoomOut;

  /// takesSoftness is whether its edge can be feathered.
  bool get takesSoftness =>
      this == band ||
      this == blinds ||
      this == shapeWipe ||
      this == clock ||
      familyOf == SceneTransitionFamily.drawn;

  /// paints is whether this is a drawn kind that puts paint on the page.
  bool get paints => this == splatter || this == brush;

  /// inFamily is the kinds of one family, in the order they are listed.
  static List<SceneTransitionKind> inFamily(SceneTransitionFamily family) => [
        for (var kind in values)
          if (kind.familyOf == family) kind,
      ];

  /// familyOf is which group this kind belongs to; kinds constructed without
  /// a family are placed by name.
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

  /// overlap is how many of those frames both scenes are playing for. Zero
  /// freezes the outgoing scene on its last frame while the incoming one has
  /// not started.
  final int overlap;

  /// color is what a transition through a colour goes through.
  final Color color;

  /// ease is how the movement is timed, for the ones that move.
  final SceneTransitionEase ease;

  /// way is which direction the ones with a direction go.
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

  /// label is what its slot is called (Ken, 2026-11-10), or "" for what it
  /// does: "→ the next scene · its kind".
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
      ease: kind.familyOf == SceneTransitionFamily.move ||
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
        if (centreX != 0.5) "centreX": centreX,
        if (centreY != 0.5) "centreY": centreY,
        if (label.isNotEmpty) "label": label,
        if (sound.isNotEmpty) ...{
          "sound": sound,
          if (soundName.isNotEmpty) "soundName": soundName,
          "soundLength": soundLength,
          if (soundVolume != 0.5) "soundVolume": soundVolume,
          if (soundLead != 6) "soundLead": soundLead,
        },
      };

  factory SceneTransition.fromJson(Map<String, dynamic> json) =>
      SceneTransition(
        kind: SceneTransitionKind.fromName(jsonStr(json["kind"])),
        frames: jsonInt(json["frames"], 12).clamp(0, 600),
        overlap: jsonInt(json["overlap"], 12).clamp(0, 600),
        color: colorFromJson(json["color"], const Color(0xFF000000)),
        ease: SceneTransitionEase.fromName(jsonStr(json["ease"])),
        way: SceneTransitionWay.fromName(jsonStr(json["way"])),
        // Absent means a circle, which toJson leaves out. ShapeKind.fromName
        // falls back to a rectangle.
        shape: json["shape"] == null
            ? ShapeKind.circle
            : ShapeKind.fromName(jsonStr(json["shape"])),
        count: jsonInt(json["count"], 6).clamp(1, 40),
        spacing: jsonDouble(json["spacing"], 0.15).clamp(0.0, 2.0),
        angle: jsonDouble(json["angle"], 0).clamp(-180.0, 180.0),
        radius: jsonDouble(json["radius"], 0.5).clamp(0.05, 1.0),
        softness: jsonDouble(json["softness"], 0).clamp(0.0, 1.0),
        centreX: jsonDouble(json["centreX"], 0.5).clamp(0.0, 1.0),
        centreY: jsonDouble(json["centreY"], 0.5).clamp(0.0, 1.0),
        sound: jsonString(json["sound"], ""),
        soundName: jsonString(json["soundName"], ""),
        soundLength: jsonDouble(json["soundLength"], 0).clamp(0.0, 3600.0),
        soundVolume: jsonDouble(json["soundVolume"], 0.5).clamp(0.0, 2.0),
        soundLead: jsonInt(json["soundLead"], 6).clamp(-240, 240),
        label: jsonString(json["label"], ""),
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

/// SceneCamera is a slow move over a whole scene, from one framing to
/// another across its length: a push in, a pull out, a drift across.
///
/// A framing is a zoom, never less than one so the page is always filled,
/// and the point it is centred on, as fractions of the page.
class SceneCamera {
  final double fromZoom;
  final double fromX;
  final double fromY;
  final double toZoom;
  final double toX;
  final double toY;
  final SceneTransitionEase ease;

  /// orbit goes once round the point it looks at over the scene, as far
  /// out as [fromX] is from the middle, instead of from one framing to the
  /// other.
  final bool orbit;

  /// shake is how much it shakes (0 to 1): a few pixels' jitter, as a hand
  /// held camera's -- or a hit's, all the way up.
  final double shake;

  const SceneCamera({
    this.fromZoom = 1,
    this.fromX = 0.5,
    this.fromY = 0.5,
    this.toZoom = 1.12,
    this.toX = 0.5,
    this.toY = 0.5,
    this.ease = SceneTransitionEase.smooth,
    this.orbit = false,
    this.shake = 0,
  });

  /// at is the framing [t] of the way through the scene: a zoom, and the
  /// point of [page] at the middle of the picture -- held far enough in from
  /// the edges that the picture never runs off the page.
  ///
  /// [seconds] into the scene times its shake; without it, [t] does.
  (double, Offset) at(double t, Rect page, {double? seconds}) {
    var e = ease.apply(t.clamp(0.0, 1.0));
    var zoom = math.max(1.0, fromZoom + (toZoom - fromZoom) * e);
    var fx = fromX + (toX - fromX) * e, fy = fromY + (toY - fromY) * e;
    if (orbit) {
      // Round the middle, as far out as it starts, once over the scene.
      var r = math.max((fromX - 0.5).abs(), 0.04);
      var a = 2 * math.pi * e;
      fx = 0.5 + r * math.cos(a);
      fy = 0.5 + r * math.sin(a) * page.width / math.max(1, page.height);
    }
    if (shake > 0) {
      // Room to shake in: closer by as much, so the page never shows its
      // edge; then a quick jitter, a few sines out of step.
      zoom = math.max(zoom, 1 + shake * 0.06);
      var s = (seconds ?? t * 10) * 9;
      double jitter(double k) =>
          math.sin(s * 1.7 + k) * 0.5 +
          math.sin(s * 3.1 + k * 2) * 0.3 +
          math.sin(s * 5.3 + k * 3) * 0.2;
      fx += jitter(0) * shake * 0.012;
      fy += jitter(4) * shake * 0.012 * page.width / math.max(1, page.height);
    }
    var x = fx * page.width;
    var y = fy * page.height;
    var hx = page.width / 2 / zoom, hy = page.height / 2 / zoom;
    return (
      zoom,
      Offset(page.left + x.clamp(hx, page.width - hx),
          page.top + y.clamp(hy, page.height - hy)),
    );
  }

  SceneCamera copyWith({
    double? fromZoom,
    double? fromX,
    double? fromY,
    double? toZoom,
    double? toX,
    double? toY,
    SceneTransitionEase? ease,
    bool? orbit,
    double? shake,
  }) =>
      SceneCamera(
        fromZoom: fromZoom ?? this.fromZoom,
        fromX: fromX ?? this.fromX,
        fromY: fromY ?? this.fromY,
        toZoom: toZoom ?? this.toZoom,
        toX: toX ?? this.toX,
        toY: toY ?? this.toY,
        ease: ease ?? this.ease,
        orbit: orbit ?? this.orbit,
        shake: (shake ?? this.shake).clamp(0.0, 1.0),
      );

  Map<String, dynamic> toJson() => {
        "from": [fromZoom, fromX, fromY],
        "to": [toZoom, toX, toY],
        if (ease != SceneTransitionEase.smooth) "ease": ease.name,
        if (orbit) "orbit": true,
        if (shake > 0) "shake": shake,
      };

  static SceneCamera? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    List<double> three(Object? v, List<double> or) =>
        v is List && v.length == 3 && v.every((x) => x is num)
            ? [for (var x in v) (x as num).toDouble()]
            : or;
    var from = three(json["from"], const [1, 0.5, 0.5]);
    var to = three(json["to"], const [1.12, 0.5, 0.5]);
    return SceneCamera(
      fromZoom: from[0].clamp(1.0, 8.0),
      fromX: from[1].clamp(0.0, 1.0),
      fromY: from[2].clamp(0.0, 1.0),
      toZoom: to[0].clamp(1.0, 8.0),
      toX: to[1].clamp(0.0, 1.0),
      toY: to[2].clamp(0.0, 1.0),
      ease: SceneTransitionEase.fromName(jsonStr(json["ease"])),
      orbit: json["orbit"] == true,
      shake: json["shake"] is num
          ? (json["shake"] as num).toDouble().clamp(0.0, 1.0)
          : 0,
    );
  }
}

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

  /// gameSounds are what each mixer channel does as a game comes to this
  /// scene, by channel key: "stop" stops it, `slot:<clip id>` plays that
  /// slot; a channel not here keeps playing. See CanvasController.gameSound.
  final Map<String, String> gameSounds;

  /// gameSoundsAtEnd are what each mixer channel does as a game leaves
  /// this scene -- for the next, or ending on it -- as [gameSounds] says
  /// for its start (Ken: the meadow's music stopped as it ends).
  final Map<String, String> gameSoundsAtEnd;

  /// cues are this scene's own cues, by name, a row each -- its own
  /// channels' and elements' rows of slots, launched together -- or null,
  /// none named yet. A game's master has the cues of the channels every
  /// scene shares (the document's, SessionGrid.scenes); a scene's are its
  /// own (Ken, 2026-11-10: per-canvas cues). See CanvasCues.
  final List<String>? cues;

  /// cover marks this canvas as the outside of a document rather than one of
  /// its leaves; see PageCover. Kept on the scene, not as a position on the
  /// document, so it survives reordering. Read only when the document is
  /// pages.
  final PageCover cover;

  /// transition is how this scene gives way to the next, or null for the
  /// document's default (CanvasDocument.defaultTransition, the master
  /// scene's). Null rather than a copy, so changing the default reaches
  /// every scene without its own.
  final SceneTransition? transition;

  /// camera is this scene's slow move, or null to hold still. Applied in
  /// playback and export only; the editor shows the page still so a press
  /// lands where it looks.
  final SceneCamera? camera;

  /// bus is the scene's own strip: everything heard in the scene -- its
  /// channels, its elements' sounds, its transition's -- sums into it, through
  /// its devices, EQ, compressor and fader, on its way to the master. The
  /// master's own sounds go straight to the master. As it is made, it changes
  /// nothing.
  final ChannelMix bus;

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
    this.gameSounds = const {},
    this.gameSoundsAtEnd = const {},
    this.cues,
    this.transition,
    this.cover = PageCover.none,
    this.camera,
    this.bus = const ChannelMix(),
  });

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

  /// custom is whether this scene has a transition of its own.
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
    Map<String, String>? gameSounds,
    Map<String, String>? gameSoundsAtEnd,
    List<String>? cues,
    SceneTransition? transition,
    bool clearTransition = false,
    PageCover? cover,
    SceneCamera? camera,
    bool clearCamera = false,
    ChannelMix? bus,
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
        gameSounds: gameSounds ?? this.gameSounds,
        gameSoundsAtEnd: gameSoundsAtEnd ?? this.gameSoundsAtEnd,
        cues: cues ?? this.cues,
        transition: clearTransition ? null : (transition ?? this.transition),
        cover: cover ?? this.cover,
        camera: clearCamera ? null : (camera ?? this.camera),
        bus: bus ?? this.bus,
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
        if (masterOff) "masterOff": true,
        if (gameSounds.isNotEmpty) "gameSounds": gameSounds,
        if (gameSoundsAtEnd.isNotEmpty) "gameSoundsEnd": gameSoundsAtEnd,
        if (cues case var c?) "cues": c,
        if (transition != null) "transition": transition!.toJson(),
        if (cover.isCover) "cover": cover.name,
        if (camera != null) "camera": camera!.toJson(),
        if (!bus.isDefault) "bus": bus.toJson(),
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
      masterOff: jsonBool(json["masterOff"], false),
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
      transition: json["transition"] is Map<String, dynamic>
          ? SceneTransition.fromJson(json["transition"] as Map<String, dynamic>)
          : null,
      cover: PageCover.fromName(jsonStr(json["cover"])),
      camera: SceneCamera.fromJson(json["camera"]),
      bus: json["bus"] is Map<String, dynamic>
          ? ChannelMix.fromJson(json["bus"] as Map<String, dynamic>)
          : const ChannelMix(),
    );
  }
}

/// newSceneId makes an id unique within a session, in the same shape as an
/// element's id.
int _sceneCounter = 0;
String newSceneId() => "sc${DateTime.now().microsecondsSinceEpoch}_"
    "${_sceneCounter++}";
