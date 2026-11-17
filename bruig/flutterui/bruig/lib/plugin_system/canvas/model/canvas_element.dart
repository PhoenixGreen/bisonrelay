import 'dart:convert';
import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/layer_blend.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/stage_spot.dart';

// canvas_element.dart is what everything on a canvas has in common.
//
// ElementBase holds the box, turn, opacity, name and motion every element
// has, so the stage can move and animate any element without knowing its
// kind; only the painter and settings switch on kind. Elements are
// immutable, so undo is a list of documents.

/// ElementKind names the families. Serialised by name: the order may change,
/// the names may not.
enum ElementKind {
  text("Text"),
  image("Image"),
  shape("Shape"),
  line("Line"),
  chart("Chart"),
  table("Table"),
  button("Button"),
  background("Background"),
  path("Path"),
  // A whole side (TeamElement); keeps the name "player" so saved documents
  // load.
  player("Team"),
  counter("Counter"),
  audio("Audio"),
  video("Video"),
  vector("Vector"),
  character3d("3D character"),
  // The 3D set a background carries (BackdropKind.stage), not added by itself.
  stage("3D stage"),
  sprite("Sprite"),
  tileMap("Tile map"),
  // Scenery a background carries (BackdropKind.parallax), not added by itself.
  parallax("Parallax"),
  sheet("Sheet music"),
  camera("Camera"),
  object3d("3D object"),
  // One synth module, patched to others with cables.
  synth("Synth module"),
  // What to make on a synth rack, and checks of the patch.
  synthTask("Synth task"),
  metronome("Metronome"),
  // A small code project in tabbed panes (code_element.dart).
  code("Code"),
  // What a Code panel's project makes, run (code_run_element.dart).
  codeRun("Run panel"),
  // A task marked against a Code panel's code (code_task_element.dart).
  codeTask("Code task");

  final String label;
  const ElementKind(this.label);
}

/// colorToJson and colorFromJson save a colour as 0xAARRGGBB in a plain
/// integer, so it round-trips exactly (float channels through JSON would not).
int colorToJson(Color c) =>
    (_channel(c.a) << 24) |
    (_channel(c.r) << 16) |
    (_channel(c.g) << 8) |
    _channel(c.b);

int _channel(double v) => (v * 255).round().clamp(0, 255);

Color colorFromJson(dynamic v, [Color fallback = const Color(0xFFFFFFFF)]) =>
    v is num && v.isFinite ? Color(v.toInt() & 0xFFFFFFFF) : fallback;

// Non-finite numbers are refused: JSON reads 1e999 as infinity, which would
// throw on the first round() and lose the document.
double _d(dynamic v, double fallback) =>
    v is num && v.isFinite ? v.toDouble() : fallback;
int _i(dynamic v, int fallback) =>
    v is num && v.isFinite ? v.toInt() : fallback;

/// jsonStr and jsonNum are a field as a string or finite number, or null.
String? jsonStr(Object? v) => v is String ? v : null;
num? jsonNum(Object? v) => v is num && v.isFinite ? v : null;

/// _far is the furthest out and biggest a received element may be: many
/// pages, but never a size that cannot be drawn.
const double _far = 1e6;

bool _b(dynamic v, bool fallback) => v is bool ? v : fallback;
String _s(dynamic v, String fallback) => v is String ? v : fallback;

/// jsonDouble, jsonInt, jsonBool and jsonString are the readers above, for
/// the subclasses. A saved document may be old or from someone else, so
/// every read survives an absent or mistyped field: a throwing cast loses
/// the whole document.
double jsonDouble(dynamic v, double fallback) => _d(v, fallback);
int jsonInt(dynamic v, int fallback) => _i(v, fallback);
bool jsonBool(dynamic v, bool fallback) => _b(v, fallback);
String jsonString(dynamic v, String fallback) => _s(v, fallback);

/// maxTextLength is the most characters one element's words are read with:
/// far more than a page holds, and a received canvas's ten million would be
/// laid out every frame.
const maxTextLength = 200000;

String jsonText(dynamic v, String fallback) {
  var s = _s(v, fallback);
  return s.length <= maxTextLength ? s : s.substring(0, maxTextLength);
}

/// fractionsFromJson reads a flat [x, y, ...] list of points as fractions of
/// a picture: within a width either side, and at most 100,000, so a sent
/// stroke cannot ask for billions of dabs.
List<Offset> fractionsFromJson(Object? flat) {
  var points = <Offset>[];
  if (flat is! List) return points;
  for (var i = 0; i + 1 < flat.length && points.length < 100000; i += 2) {
    var x = flat[i], y = flat[i + 1];
    if (x is num && y is num && x.isFinite && y.isFinite) {
      points.add(
          Offset(x.toDouble().clamp(-1.0, 2.0), y.toDouble().clamp(-1.0, 2.0)));
    }
  }
  return points;
}

/// ElementBase is every property every element has. Held by composition, so
/// a subclass implements only [CanvasElement.rebase] to be fully editable.
class ElementBase {
  /// id is stable for the element's life and survives saving; keyframes and
  /// button actions refer to it.
  final String id;

  /// name is the layer list's name. Defaults to the kind's label.
  final String name;

  /// x, y, width and height are in design space (canvas_geometry.dart). x
  /// and y are the top-left before rotation, which is about the centre.
  final double x;
  final double y;
  final double width;
  final double height;

  /// rotation is in degrees, clockwise, about the centre.
  final double rotation;

  /// skewX and skewY slant the element about its centre, in degrees, after
  /// rotation: skewX leans the sides, skewY the top and bottom. See BoxFrame.
  final double skewX;
  final double skewY;

  /// opacity multiplies the whole element, on top of its own colours.
  final double opacity;

  /// blend is how the element is laid over what is under it: its motion
  /// chain's Output.
  final LayerBlend blend;

  final bool visible;

  /// locked keeps an element from the pointer, so a pitch or background is
  /// not selected by a click near what stands on it.
  final bool locked;

  /// rowColour is its row's ARGB colour on the timeline, mixer and slots;
  /// null for the given one (CanvasController.rowColour). A sound channel's
  /// is on its sounds.
  final int? rowColour;

  /// lockAspect holds width and height together while it is resized.
  final bool lockAspect;

  /// anchorX and anchorY are the anchor point as shares of width and height
  /// from the top-left: what animation turns and grows about. The centre
  /// (0.5, 0.5) unless moved.
  final double anchorX;
  final double anchorY;

  /// anchorLocked keeps the anchor in place, even while shown.
  final bool anchorLocked;

  /// track is the legacy keyframe track, or null. Converted to [motion]
  /// clips on open (motion_convert.dart), except what a clip cannot say:
  /// backgrounds, stages, scenery, teams.
  final ElementTrack? track;

  /// typeScale is what the element's own measurements (type, spacing,
  /// padding) are sized by on the current shape. Kept because a shape
  /// change must undo this scaling first, and scaled numbers cannot say what
  /// they were scaled by. See ElementLayout.typeScale.
  final double typeScale;

  /// depth is distance from the camera for a Camera's depth of field and
  /// parallax: nought on the page, up to one far behind, down to minus one
  /// near. Nothing else reads it.
  final double depth;

  /// ownText is whether the current shape has its own words
  /// (ElementLayout.ownText).
  final bool ownText;

  /// ownDesign is whether the current shape has its own copy of the whole
  /// element. Off, only place, size and typeScale are per shape; on, nothing
  /// done on another shape reaches this one.
  final bool ownDesign;

  /// shared is the shapes' shared design, kept aside while the current shape
  /// shows its own (held in the fields). Null while nothing is detached.
  final Map<String, dynamic>? shared;

  /// layouts is where the element sits on each *other* target shape, by
  /// ratio (CanvasDocument.targets). The current shape's numbers are the live
  /// x, y, width and height, so painters read them as usual; changing shape
  /// swaps them (CanvasDocument.forShape).
  final Map<String, ElementLayout> layouts;

  /// cue is the id of the TimelineCue its timing is tied to, or empty.
  /// Moving the cue moves its clips and keyframes (CanvasController.moveCue).
  final String cue;

  /// cast is the id of the Cast member it is a linked copy of, or empty. Its
  /// design, game settings and motions are the member's; only its place,
  /// size and what it does in its scene are its own. See cast.dart.
  final String cast;

  /// play is what it does in a played game. See play.dart.
  final PlaySpec play;

  /// spot is where it stands on a 3D stage, or null for on the page.
  final StageSpot? spot;

  /// motion is its clips, slots and their timeline places. See motion.dart.
  final ElementMotion motion;

  const ElementBase({
    required this.id,
    this.name = "",
    this.x = 0,
    this.y = 0,
    this.width = 200,
    this.height = 100,
    this.rotation = 0,
    this.skewX = 0,
    this.skewY = 0,
    this.opacity = 1,
    this.blend = LayerBlend.normal,
    this.visible = true,
    this.locked = false,
    this.rowColour,
    this.lockAspect = false,
    this.anchorX = 0.5,
    this.anchorY = 0.5,
    this.anchorLocked = false,
    this.track,
    this.layouts = const {},
    this.typeScale = 1,
    this.depth = 0,
    this.ownText = false,
    this.ownDesign = false,
    this.shared,
    this.cue = "",
    this.cast = "",
    this.play = const PlaySpec(),
    this.spot,
    this.motion = ElementMotion.none,
  });

  ElementBase copyWith({
    String? id,
    String? name,
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
    double? skewX,
    double? skewY,
    double? opacity,
    LayerBlend? blend,
    bool? visible,
    bool? locked,
    int? rowColour,
    bool clearRowColour = false,
    bool? lockAspect,
    double? anchorX,
    double? anchorY,
    bool? anchorLocked,
    ElementTrack? track,
    bool clearTrack = false,
    Map<String, ElementLayout>? layouts,
    double? typeScale,
    double? depth,
    bool? ownText,
    bool? ownDesign,
    Map<String, dynamic>? shared,
    bool clearShared = false,
    String? cue,
    String? cast,
    PlaySpec? play,
    StageSpot? spot,
    bool clearSpot = false,
    ElementMotion? motion,
  }) =>
      ElementBase(
        play: play ?? this.play,
        spot: clearSpot ? null : (spot ?? this.spot),
        motion: motion ?? this.motion,
        id: id ?? this.id,
        name: name ?? this.name,
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
        rotation: rotation ?? this.rotation,
        skewX: (skewX ?? this.skewX).clamp(-maxSkew, maxSkew),
        skewY: (skewY ?? this.skewY).clamp(-maxSkew, maxSkew),
        opacity: opacity ?? this.opacity,
        blend: blend ?? this.blend,
        visible: visible ?? this.visible,
        locked: locked ?? this.locked,
        rowColour: clearRowColour ? null : rowColour ?? this.rowColour,
        lockAspect: lockAspect ?? this.lockAspect,
        anchorX: anchorX ?? this.anchorX,
        anchorY: anchorY ?? this.anchorY,
        anchorLocked: anchorLocked ?? this.anchorLocked,
        track: clearTrack ? null : (track ?? this.track),
        layouts: layouts ?? this.layouts,
        typeScale: typeScale ?? this.typeScale,
        depth: depth ?? this.depth,
        ownText: ownText ?? this.ownText,
        ownDesign: ownDesign ?? this.ownDesign,
        shared: clearShared ? null : (shared ?? this.shared),
        cue: cue ?? this.cue,
        cast: cast ?? this.cast,
      );

  factory ElementBase.fromJson(Map<String, dynamic> json, String defaultName) {
    var trackJson = json["track"];
    return ElementBase(
      id: _s(json["id"], newElementId()),
      name: _s(json["name"], defaultName),
      x: _d(json["x"], 0).clamp(-_far, _far),
      y: _d(json["y"], 0).clamp(-_far, _far),
      width: _d(json["w"], 200).clamp(0.0, _far),
      height: _d(json["h"], 100).clamp(0.0, _far),
      rotation: _d(json["rot"], 0),
      skewX: _d(json["skx"], 0).clamp(-maxSkew, maxSkew),
      skewY: _d(json["sky"], 0).clamp(-maxSkew, maxSkew),
      opacity: _d(json["opacity"], 1).clamp(0.0, 1.0),
      blend: LayerBlend.fromName(
          json["blend"] is String ? json["blend"] as String : null),
      visible: _b(json["visible"], true),
      locked: _b(json["locked"], false),
      rowColour: json["rowColour"] is int ? json["rowColour"] as int : null,
      lockAspect: _b(json["aspect"], false),
      anchorX: _d(json["ax"], 0.5),
      anchorY: _d(json["ay"], 0.5),
      anchorLocked: _b(json["anchorLocked"], false),
      track: trackJson is Map<String, dynamic>
          ? ElementTrack.fromJson(trackJson)
          : null,
      typeScale: _d(json["typeScale"], 1),
      depth: _d(json["depth"], 0).clamp(-1.0, 1.0).toDouble(),
      ownText: _b(json["ownText"], false),
      ownDesign: _b(json["ownDesign"], false),
      shared: json["shared"] is Map<String, dynamic>
          ? json["shared"] as Map<String, dynamic>
          : null,
      cue: _s(json["cue"], ""),
      cast: _s(json["cast"], ""),
      play: PlaySpec.fromJson(json["play"]),
      spot: StageSpot.fromJson(json["spot"]),
      motion: ElementMotion.fromJson(json["motion"]),
      layouts: {
        if (json["layouts"] is Map)
          for (var e in (json["layouts"] as Map).entries)
            if (e.value is Map<String, dynamic>)
              "${e.key}":
                  ElementLayout.fromJson(e.value as Map<String, dynamic>),
      },
    );
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "x": x,
        "y": y,
        "w": width,
        "h": height,
        if (rotation != 0) "rot": rotation,
        if (skewX != 0) "skx": skewX,
        if (skewY != 0) "sky": skewY,
        if (opacity != 1) "opacity": opacity,
        if (blend != LayerBlend.normal) "blend": blend.name,
        if (!visible) "visible": false,
        if (locked) "locked": true,
        if (rowColour != null) "rowColour": rowColour,
        "aspect": lockAspect,
        if (anchorX != 0.5) "ax": anchorX,
        if (anchorY != 0.5) "ay": anchorY,
        if (anchorLocked) "anchorLocked": true,
        if (track != null && !track!.isEmpty) "track": track!.toJson(),
        if (typeScale != 1) "typeScale": typeScale,
        if (depth != 0) "depth": depth,
        if (ownText) "ownText": true,
        if (ownDesign) "ownDesign": true,
        if (shared != null) "shared": shared,
        if (cue.isNotEmpty) "cue": cue,
        if (cast.isNotEmpty) "cast": cast,
        if (!play.isNone) "play": play.toJson(),
        if (spot != null) "spot": spot!.toJson(),
        if (!motion.isBlank) "motion": motion.toJson(),
        if (layouts.isNotEmpty)
          "layouts": {
            for (var e in layouts.entries) e.key: e.value.toJson(),
          },
      };
}

/// ElementLayout is an element's place, size and visibility on one shape,
/// plus what else differs per shape (type scale, words, design, a picture's
/// framing and crop).
class ElementLayout {
  final double x;
  final double y;
  final double width;
  final double height;
  final bool visible;

  final double typeScale;

  /// text is this shape's words, or null for a non-text element. Kept on
  /// every shape so visiting one with its own words and returning restores
  /// the others'; [ownText] tells them apart.
  final String? text;

  /// own is the element's whole design on a shape it is detached on. Null
  /// follows the shared design.
  final Map<String, dynamic>? own;

  /// framing and crop are always per shape: the frame differs on each, so
  /// one crop does not suit another.
  final Map<String, dynamic>? framing;
  final Map<String, dynamic>? crop;

  /// ownText is whether the words are this shape's own (a narrow page needing
  /// fewer); the other shapes share one set.
  final bool ownText;

  const ElementLayout({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.visible = true,
    this.typeScale = 1,
    this.text,
    this.ownText = false,
    this.own,
    this.framing,
    this.crop,
  });

  /// of is the layout an element is showing now.
  factory ElementLayout.of(
    ElementBase base, {
    String? text,
    Map<String, dynamic>? own,
    Map<String, dynamic>? framing,
    Map<String, dynamic>? crop,
  }) =>
      ElementLayout(
        x: base.x,
        y: base.y,
        width: base.width,
        height: base.height,
        visible: base.visible,
        typeScale: base.typeScale,
        text: text,
        ownText: base.ownText,
        own: own,
        framing: framing,
        crop: crop,
      );

  /// scaledBy is this layout on a page [by] times the size.
  ElementLayout scaledBy(double by) => ElementLayout(
        x: x * by,
        y: y * by,
        width: math.max(1, width * by),
        height: math.max(1, height * by),
        visible: visible,
        // The design scales with the box, or type seeded onto a smaller
        // page runs out of the frame.
        typeScale: typeScale * by,
        text: text,
        ownText: ownText,
        own: own,
        framing: framing,
        crop: crop,
      );

  ElementLayout copyWith({
    double? typeScale,
    String? text,
    bool? ownText,
    Map<String, dynamic>? own,
    Map<String, dynamic>? framing,
    Map<String, dynamic>? crop,
    bool clearOwn = false,
  }) =>
      ElementLayout(
        x: x,
        y: y,
        width: width,
        height: height,
        visible: visible,
        typeScale: typeScale ?? this.typeScale,
        text: text ?? this.text,
        ownText: ownText ?? this.ownText,
        own: clearOwn ? null : (own ?? this.own),
        framing: framing ?? this.framing,
        crop: crop ?? this.crop,
      );

  Map<String, dynamic> toJson() => {
        "x": x,
        "y": y,
        "w": width,
        "h": height,
        if (!visible) "visible": false,
        if (typeScale != 1) "typeScale": typeScale,
        if (text != null) "text": text,
        if (ownText) "ownText": true,
        if (own != null) "own": own,
        if (framing != null) "framing": framing,
        if (crop != null) "crop": crop,
      };

  factory ElementLayout.fromJson(Map<String, dynamic> json) => ElementLayout(
        x: _d(json["x"], 0).clamp(-_far, _far),
        y: _d(json["y"], 0).clamp(-_far, _far),
        width: _d(json["w"], 200).clamp(0.0, _far),
        height: _d(json["h"], 100).clamp(0.0, _far),
        visible: _b(json["visible"], true),
        typeScale: _d(json["typeScale"], 1),
        text: json["text"] is String ? json["text"] as String : null,
        ownText: _b(json["ownText"], false),
        own: json["own"] is Map<String, dynamic>
            ? json["own"] as Map<String, dynamic>
            : null,
        framing: json["framing"] is Map<String, dynamic>
            ? json["framing"] as Map<String, dynamic>
            : null,
        crop: json["crop"] is Map<String, dynamic>
            ? json["crop"] as Map<String, dynamic>
            : null,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ElementLayout &&
          other.x == x &&
          other.y == y &&
          other.width == width &&
          other.height == height &&
          other.visible == visible &&
          other.typeScale == typeScale &&
          other.text == text &&
          other.ownText == ownText &&
          _sameJson(other.own, own) &&
          _sameJson(other.framing, framing) &&
          _sameJson(other.crop, crop);

  @override
  int get hashCode =>
      Object.hash(x, y, width, height, visible, typeScale, text, ownText);

  static bool _sameJson(Map<String, dynamic>? a, Map<String, dynamic>? b) =>
      identical(a, b) ||
      (a != null && b != null && jsonEncode(a) == jsonEncode(b));
}

/// jsonSpec reads a nested value object (TextSpec, BoxSpec...) with [parse],
/// or [fallback] when the field is missing or not a map.
T jsonSpec<T>(dynamic v, T Function(Map<String, dynamic>) parse, T fallback) =>
    v is Map<String, dynamic> ? parse(v) : fallback;

/// CanvasElement is one thing on the canvas. Immutable: see the file header.
abstract class CanvasElement {
  final ElementBase base;

  const CanvasElement(this.base);

  ElementKind get kind;

  /// rebase is the one method a subclass owes the stage: the same element
  /// with a different base. Every move, resize, rename and animation uses it.
  CanvasElement rebase(ElementBase base);

  /// props is the element's own fields, and nothing [ElementBase] owns.
  Map<String, dynamic> props();

  String get id => base.id;
  String get name => base.name.isEmpty ? kind.label : base.name;
  double get x => base.x;
  double get y => base.y;
  double get width => base.width;
  double get height => base.height;
  double get rotation => base.rotation;

  /// frameAt is how the box is laid on the page about its middle on [frame]:
  /// turned, then slanted.
  BoxFrame frameAt(int frame) =>
      BoxFrame(rotationAt(frame), base.skewX, base.skewY);
  double get opacity => base.opacity;
  bool get visible => base.visible;
  bool get locked => base.locked;
  ElementTrack? get track => base.track;

  Rect get bounds => Rect.fromLTWH(x, y, width, height);
  Offset get center => bounds.center;

  /// poseAt is the keyframe track's offset from rest on [frame]; clips are
  /// not included (see poseWithMotion in render/motion_document.dart).
  Keyframe poseAt(int frame) => base.track?.at(frame) ?? Keyframe.rest;

  /// spotAt is its stage spot on [frame], with track keys over it; null for
  /// on the page.
  StageSpot? spotAt(int frame) => base.spot?.over(poseAt(frame));

  /// boundsAt is the keyframed box on [frame]. Anything drawn beside a
  /// moving element must use a posed box, not [bounds]; with clips, that is
  /// movedBoundsAt in render/motion_document.dart.
  Rect boundsAt(int frame) => boundsWith(poseAt(frame));

  /// boundsWith is the box posed as [pose], in the painter's order: shift,
  /// then scale about the anchor.
  Rect boundsWith(Keyframe pose) {
    var box = bounds.shift(Offset(pose.dx, pose.dy));
    if (pose.scale == 1) return box;
    // Grown about the anchor, which stays where it is.
    var a = anchorIn(box);
    return Rect.fromLTRB(
      a.dx + (box.left - a.dx) * pose.scale,
      a.dy + (box.top - a.dy) * pose.scale,
      a.dx + (box.right - a.dx) * pose.scale,
      a.dy + (box.bottom - a.dy) * pose.scale,
    );
  }

  /// anchorCentred is whether the anchor is in the middle.
  bool get anchorCentred => base.anchorX == 0.5 && base.anchorY == 0.5;

  /// anchorIn is the anchor's point in [box], before any turn.
  Offset anchorIn(Rect box) => Offset(
      box.left + box.width * base.anchorX, box.top + box.height * base.anchorY);

  /// anchorAt is the anchor on the page at [frame]: moved with the pose and
  /// turned with the box about its centre. A keyframe's turn and size are
  /// about the anchor, so they leave it put.
  Offset anchorAt(int frame) {
    var pose = poseAt(frame);
    var box = bounds.shift(Offset(pose.dx, pose.dy));
    return turnedAboutCentre(anchorIn(box), box.center);
  }

  /// turnedAboutCentre is [p] turned as the element is, about [centre].
  Offset turnedAboutCentre(Offset p, Offset centre) {
    var r = rotationRadians;
    if (r == 0) return p;
    var d = p - centre;
    var c = math.cos(r), s = math.sin(r);
    return centre + Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c);
  }

  /// withAnchorAt moves the anchor to [page] at [frame], turned back into
  /// the box. The element does not move: it rests turned about its centre,
  /// and the anchor is only what animation turns and grows about.
  CanvasElement withAnchorAt(Offset page, int frame) {
    var pose = poseAt(frame);
    var box = bounds.shift(Offset(pose.dx, pose.dy));
    var r = -rotationRadians;
    var d = page - box.center;
    var c = math.cos(r), s = math.sin(r);
    var local = box.center + Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c);
    return withBase(
      anchorX: box.width <= 0 ? 0.5 : (local.dx - box.left) / box.width,
      anchorY: box.height <= 0 ? 0.5 : (local.dy - box.top) / box.height,
    );
  }

  /// turnedTo turns to [degrees] about the anchor rather than the centre,
  /// moving as well so the anchor stays put on the page.
  CanvasElement turnedTo(double degrees) {
    if (anchorCentred) return withBase(rotation: degrees);
    var box = bounds;
    var before = turnedAboutCentre(anchorIn(box), box.center);
    var turned = withBase(rotation: degrees);
    var after = turned.turnedAboutCentre(anchorIn(box), box.center);
    var shift = before - after;
    return turned.withBase(x: base.x + shift.dx, y: base.y + shift.dy);
  }

  /// rotationAt and opacityAt are the keyframed turn and opacity on [frame].
  double rotationAt(int frame) => rotation + poseAt(frame).rotate;

  double opacityAt(int frame) =>
      (opacity * poseAt(frame).opacity).clamp(0.0, 1.0);

  /// keepsAspect is whether a resize holds proportions without Shift.
  bool get keepsAspect => base.lockAspect;

  double get rotationRadians => rotation * math.pi / 180;

  /// assetIds is every stored picture it refers to. The sweep deletes any
  /// picture no saved canvas names, so each must be listed here.
  Set<String> get assetIds => const {};

  /// mediaIds is every stored sound or video it refers to (CanvasMedia),
  /// swept as [assetIds] are.
  Set<String> get mediaIds => const {};

  /// scaledBy sizes the inside measurements (type, spacing, padding) by
  /// [by]. Asked only while proportions are held. The default changes
  /// nothing, right for contents that are fractions of the box.
  CanvasElement scaledBy(double by) => this;

  /// scalesInside is whether [scaledBy] does anything, so typeScale is only
  /// offered where it has an effect.
  bool get scalesInside => false;

  /// withBase is [ElementBase.copyWith] through [rebase], for one-line
  /// property changes.
  CanvasElement withBase({
    String? name,
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
    double? skewX,
    double? skewY,
    double? opacity,
    LayerBlend? blend,
    bool? visible,
    bool? locked,
    bool? lockAspect,
    double? anchorX,
    double? anchorY,
    bool? anchorLocked,
    ElementTrack? track,
    bool clearTrack = false,
    Map<String, ElementLayout>? layouts,
    double? typeScale,
    double? depth,
    bool? ownText,
    bool? ownDesign,
    Map<String, dynamic>? shared,
    bool clearShared = false,
    String? cue,
    StageSpot? spot,
    bool clearSpot = false,
    ElementMotion? motion,
  }) =>
      rebase(base.copyWith(
        spot: spot,
        clearSpot: clearSpot,
        motion: motion,
        name: name,
        x: x,
        y: y,
        width: width,
        height: height,
        rotation: rotation,
        skewX: skewX,
        skewY: skewY,
        opacity: opacity,
        blend: blend,
        visible: visible,
        locked: locked,
        lockAspect: lockAspect,
        anchorX: anchorX,
        anchorY: anchorY,
        anchorLocked: anchorLocked,
        track: track,
        clearTrack: clearTrack,
        layouts: layouts,
        typeScale: typeScale,
        depth: depth,
        ownText: ownText,
        ownDesign: ownDesign,
        shared: shared,
        clearShared: clearShared,
        cue: cue,
      ));

  /// withId is a copy under a new id, for duplicating.
  CanvasElement withId(String newId) => newId == id
      ? this
      : rebase(base.copyWith(id: newId, motion: base.motion.renamedFor(newId)));

  Map<String, dynamic> toJson() => {
        "kind": kind.name,
        ...base.toJson(),
        ...props(),
      };
}

/// _idCounter and newElementId make ids unique within a session and unlikely
/// to collide across them.
int _idCounter = 0;
final math.Random _idRandom = math.Random();

String newElementId() {
  var n = _idCounter++;
  var salt = _idRandom.nextInt(1 << 20);
  return "e${n.toRadixString(36)}_${salt.toRadixString(36)}";
}

/// maxSkew is the most slant, in degrees: past it the box is a line.
const double maxSkew = 80;

/// BoxFrame lays an element's box on the page about its middle: turned by
/// [rotation], then slanted by [skewX] and [skewY], in degrees. [apply] maps
/// box space to page, [invert] back. It matches the renderer (Canvas.rotate,
/// then Canvas.skew), so clicks, handles and outlines land on the drawing.
class BoxFrame {
  final double rotation;
  final double skewX;
  final double skewY;

  // x' = a x + b y, y' = c x + d y.
  final double a, b, c, d;

  factory BoxFrame(double rotation, double skewX, double skewY) {
    var r = rotation * math.pi / 180;
    var cos = math.cos(r), sin = math.sin(r);
    var sx = math.tan(skewX * math.pi / 180);
    var sy = math.tan(skewY * math.pi / 180);
    // Rotation after skew: R * S, S = [[1, sx], [sy, 1]].
    return BoxFrame._(rotation, skewX, skewY, cos - sin * sy, cos * sx - sin,
        sin + cos * sy, sin * sx + cos);
  }

  const BoxFrame._(
      this.rotation, this.skewX, this.skewY, this.a, this.b, this.c, this.d);

  bool get upright => rotation == 0 && skewX == 0 && skewY == 0;

  bool get slanted => skewX != 0 || skewY != 0;

  Offset apply(Offset p) => Offset(a * p.dx + b * p.dy, c * p.dx + d * p.dy);

  Offset invert(Offset p) {
    var det = a * d - b * c;
    if (det.abs() < 1e-12) return p;
    return Offset((d * p.dx - b * p.dy) / det, (-c * p.dx + a * p.dy) / det);
  }

  /// applyTo transforms [canvas] about [centre] so what is drawn next in box
  /// space lands where the element is.
  void applyTo(Canvas canvas, Offset centre) {
    if (upright) return;
    canvas.translate(centre.dx, centre.dy);
    if (rotation != 0) canvas.rotate(rotation * math.pi / 180);
    if (slanted) {
      canvas.skew(
          math.tan(skewX * math.pi / 180), math.tan(skewY * math.pi / 180));
    }
    canvas.translate(-centre.dx, -centre.dy);
  }

  /// corners is [box] laid out this way about its middle.
  List<Offset> corners(Rect box) {
    var c0 = box.center;
    return [
      for (var p in [
        box.topLeft,
        box.topRight,
        box.bottomRight,
        box.bottomLeft
      ])
        c0 + apply(p - c0)
    ];
  }
}
