import 'dart:convert';
import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/layer_blend.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/stage_spot.dart';

// canvas_element.dart is what everything on a canvas has in common, and
// nothing else.
//
// ElementBase holds the box, turn, opacity, name and motion every element
// has, so the stage can move, resize and animate any element without knowing
// its kind; only the painter and the settings switch on the kind. Elements
// are immutable, which is what makes undo a list of documents rather than of
// reversible operations.

/// ElementKind names the families. Serialised by name, so the order here is
/// free to change but the names are not.
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
  // A whole side, not one dot (TeamElement); the value keeps its old name so
  // saved documents load.
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
  // The part of the page shown, moved by clips.
  camera("Camera"),
  object3d("3D object");

  final String label;
  const ElementKind(this.label);
}

/// colorToJson and colorFromJson are the one encoding of a colour in a saved
/// document: 0xAARRGGBB as a plain integer, so a colour round-trips exactly
/// (float channels through JSON would not).
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

/// jsonStr and jsonNum are a field as a string or a finite number, or null
/// where it is missing or of another type.
String? jsonStr(Object? v) => v is String ? v : null;
num? jsonNum(Object? v) => v is num && v.isFinite ? v : null;

/// _far is the furthest out, and the biggest, a received element may be:
/// many times any page, but not a size that cannot be drawn.
const double _far = 1e6;

bool _b(dynamic v, bool fallback) => v is bool ? v : fallback;
String _s(dynamic v, String fallback) => v is String ? v : fallback;

/// jsonDouble, jsonInt, jsonBool and jsonString are the readers above,
/// exported for the element subclasses. A saved document may be from an
/// older build or another person, so every read survives a field being absent
/// or the wrong type: a cast that throws loses the whole document.
double jsonDouble(dynamic v, double fallback) => _d(v, fallback);
int jsonInt(dynamic v, int fallback) => _i(v, fallback);
bool jsonBool(dynamic v, bool fallback) => _b(v, fallback);
String jsonString(dynamic v, String fallback) => _s(v, fallback);

/// fractionsFromJson reads a flat [x, y, x, y, ...] list of points that are
/// fractions of a picture: within a picture's width either side of it, and
/// at most 100,000 of them, so a sent stroke cannot ask for billions of dabs.
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

/// ElementBase is every property that every element has.
///
/// Held by composition, so an element subclass implements one method
/// ([CanvasElement.rebase]) to be fully editable by the stage.
class ElementBase {
  /// id is stable for the life of the element and survives saving. Keyframes
  /// and button actions refer to elements by it.
  final String id;

  /// name is what the layer list calls this. Defaults to the kind's label.
  final String name;

  /// x, y, width and height are in the document's design space -- see
  /// canvas_geometry.dart. x and y are the top-left corner *before* rotation,
  /// and rotation happens about the centre.
  final double x;
  final double y;
  final double width;
  final double height;

  /// rotation is in degrees (a number the user types), clockwise, about the
  /// element's centre.
  final double rotation;

  /// skewX and skewY slant the element about its centre, in degrees, after
  /// its rotation: skewX leans its sides left and right -- the top edge one
  /// way, the bottom the other -- and skewY its top and bottom up and down.
  /// See BoxFrame.
  final double skewX;
  final double skewY;

  /// opacity multiplies the whole element, on top of whatever its own colours
  /// say.
  final double opacity;

  /// blend is how the element is laid over what is under it: its motion
  /// chain's Output.
  final LayerBlend blend;

  final bool visible;

  /// locked keeps an element out of the way of the pointer, so a pitch or a
  /// background is not selected by a click near what stands on it.
  final bool locked;

  /// lockAspect holds an element's proportions while it is resized: the
  /// width and the height move together.
  final bool lockAspect;

  /// anchorX and anchorY are the element's anchor point, as shares of its
  /// width and height from its top-left corner: what its animation turns and
  /// grows about, and what stays put when it is turned. The centre (0.5,
  /// 0.5) unless moved.
  final double anchorX;
  final double anchorY;

  /// anchorLocked keeps the anchor where it is, even while it is shown.
  final bool anchorLocked;

  /// track is the element's legacy keyframe track, or null. Tracks are
  /// converted to [motion] clips when a canvas opens (motion_convert.dart),
  /// except those a clip cannot say: backgrounds, stages, scenery, teams.
  final ElementTrack? track;

  /// typeScale is how much the element's own measurements (type, spacing,
  /// padding) have been sized by for the shape being looked at.
  ///
  /// Kept because switching shape has to undo this shape's scaling before
  /// applying the next one's, and the scaled numbers cannot say what they
  /// were scaled by. See ElementLayout.typeScale.
  final double typeScale;

  /// ownText is whether the shape being looked at has words of its own --
  /// see ElementLayout.ownText.
  final bool ownText;

  /// ownDesign is whether the shape being looked at has its own copy of the
  /// whole element. Off, an element is one design laid out several ways and
  /// only its place, size and typeScale belong to the shape; on, nothing done
  /// to it on another shape reaches this one.
  final bool ownDesign;

  /// shared is the design the shapes share, kept aside while the shape being
  /// looked at shows one of its own (the element's fields then hold that
  /// shape's design). Null while nothing is detached. See ownDesign.
  final Map<String, dynamic>? shared;

  /// layouts is where this element sits on each of the *other* shapes the
  /// document is designed for, by ratio -- see ElementLayout and
  /// CanvasDocument.targets.
  ///
  /// The shape being looked at is not in here: its numbers are the live x, y,
  /// width and height, so every painter and handle reads them as usual.
  /// Changing shape swaps them. See CanvasDocument.forShape.
  final Map<String, ElementLayout> layouts;

  /// cue is the TimelineCue this element's timing is tied to, by id, or
  /// empty for none. Moving the cue moves the element's clip placements and
  /// keyframes with it -- see CanvasController.moveCue.
  final String cue;

  /// play is what it does when the canvas is played as a game. See play.dart.
  final PlaySpec play;

  /// spot is where it stands on a 3D stage, or null for on the page. See
  /// stage_spot.dart.
  final StageSpot? spot;

  /// motion is how it moves: its clips, its slots, where they are placed on
  /// the timeline. See motion.dart.
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
    this.lockAspect = false,
    this.anchorX = 0.5,
    this.anchorY = 0.5,
    this.anchorLocked = false,
    this.track,
    this.layouts = const {},
    this.typeScale = 1,
    this.ownText = false,
    this.ownDesign = false,
    this.shared,
    this.cue = "",
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
    bool? lockAspect,
    double? anchorX,
    double? anchorY,
    bool? anchorLocked,
    ElementTrack? track,
    bool clearTrack = false,
    Map<String, ElementLayout>? layouts,
    double? typeScale,
    bool? ownText,
    bool? ownDesign,
    Map<String, dynamic>? shared,
    bool clearShared = false,
    String? cue,
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
        lockAspect: lockAspect ?? this.lockAspect,
        anchorX: anchorX ?? this.anchorX,
        anchorY: anchorY ?? this.anchorY,
        anchorLocked: anchorLocked ?? this.anchorLocked,
        track: clearTrack ? null : (track ?? this.track),
        layouts: layouts ?? this.layouts,
        typeScale: typeScale ?? this.typeScale,
        ownText: ownText ?? this.ownText,
        ownDesign: ownDesign ?? this.ownDesign,
        shared: clearShared ? null : (shared ?? this.shared),
        cue: cue ?? this.cue,
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
      lockAspect: _b(json["aspect"], false),
      anchorX: _d(json["ax"], 0.5),
      anchorY: _d(json["ay"], 0.5),
      anchorLocked: _b(json["anchorLocked"], false),
      track: trackJson is Map<String, dynamic>
          ? ElementTrack.fromJson(trackJson)
          : null,
      typeScale: _d(json["typeScale"], 1),
      ownText: _b(json["ownText"], false),
      ownDesign: _b(json["ownDesign"], false),
      shared: json["shared"] is Map<String, dynamic>
          ? json["shared"] as Map<String, dynamic>
          : null,
      cue: _s(json["cue"], ""),
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
        "aspect": lockAspect,
        if (anchorX != 0.5) "ax": anchorX,
        if (anchorY != 0.5) "ay": anchorY,
        if (anchorLocked) "anchorLocked": true,
        if (track != null && !track!.isEmpty) "track": track!.toJson(),
        if (typeScale != 1) "typeScale": typeScale,
        if (ownText) "ownText": true,
        if (ownDesign) "ownDesign": true,
        if (shared != null) "shared": shared,
        if (cue.isNotEmpty) "cue": cue,
        if (!play.isNone) "play": play.toJson(),
        if (spot != null) "spot": spot!.toJson(),
        if (!motion.isBlank) "motion": motion.toJson(),
        if (layouts.isNotEmpty)
          "layouts": {
            for (var e in layouts.entries) e.key: e.value.toJson(),
          },
      };
}

/// ElementLayout is where an element sits on one shape of the canvas: its
/// place, size and visibility there, plus the few things that differ per
/// shape (type scale, own words, own design, a picture's framing and crop).
class ElementLayout {
  final double x;
  final double y;
  final double width;
  final double height;
  final bool visible;

  /// typeScale is how much the element's own measurements are sized by on
  /// this shape -- see ElementBase.typeScale.
  final double typeScale;

  /// text is the words this shape shows, or null for a non-text element.
  /// Kept on every shape, its own or not, so that visiting a shape with its
  /// own words and coming back restores the others'; [ownText] tells them
  /// apart.
  final String? text;

  /// own is this element's whole design on this shape, for one that has been
  /// detached here -- see ElementBase.ownDesign. Null means it follows the
  /// design the shapes share.
  final Map<String, dynamic>? own;

  /// framing and crop are a picture's own on this shape, always: the frame
  /// is a different shape on each, so the crop that suits one does not suit
  /// another.
  final Map<String, dynamic>? framing;
  final Map<String, dynamic>? crop;

  /// ownText is whether those words are this shape's own, for a narrow page
  /// that needs fewer words; the other shapes go on sharing one set.
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

  /// of is the layout an element is showing at the moment.
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
        // The design inside the box scales with the box, or the type
        // seeded onto a smaller page runs out of the frame.
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

  /// _sameJson is whether two saved designs are the same.
  static bool _sameJson(Map<String, dynamic>? a, Map<String, dynamic>? b) =>
      identical(a, b) ||
      (a != null && b != null && jsonEncode(a) == jsonEncode(b));
}

/// jsonSpec reads a nested value object -- a TextSpec, a BoxSpec, a
/// ProceduralSpec -- with [parse], falling back to [fallback] when the field
/// is missing or is not a map.
T jsonSpec<T>(dynamic v, T Function(Map<String, dynamic>) parse, T fallback) =>
    v is Map<String, dynamic> ? parse(v) : fallback;

/// CanvasElement is one thing on the canvas. Immutable: see the file header.
abstract class CanvasElement {
  final ElementBase base;

  const CanvasElement(this.base);

  ElementKind get kind;

  /// rebase is the one method a subclass owes the stage: the same element,
  /// with different base properties. Every move, resize, rename, lock and
  /// animation goes through it.
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

  /// frameAt is how this element's own box is laid on the page about its
  /// middle on [frame]: turned, then slanted. See BoxFrame.
  BoxFrame frameAt(int frame) =>
      BoxFrame(rotationAt(frame), base.skewX, base.skewY);
  double get opacity => base.opacity;
  bool get visible => base.visible;
  bool get locked => base.locked;
  ElementTrack? get track => base.track;

  Rect get bounds => Rect.fromLTWH(x, y, width, height);
  Offset get center => bounds.center;

  /// poseAt is where this element's keyframe track puts it on [frame], as an
  /// offset from where it rests; clips are not included (see poseWithMotion
  /// in render/motion_document.dart).
  Keyframe poseAt(int frame) => base.track?.at(frame) ?? Keyframe.rest;

  /// spotAt is where it stands on a stage on [frame], its own spot with
  /// whatever its track keys over it; null for on the page.
  StageSpot? spotAt(int frame) => base.spot?.over(poseAt(frame));

  /// boundsAt is where the element's keyframes put it on [frame]. Anything
  /// drawn beside a moving element must use a posed box, not [bounds]; with
  /// clips too, that is movedBoundsAt in render/motion_document.dart.
  Rect boundsAt(int frame) => boundsWith(poseAt(frame));

  /// boundsWith is the element's box posed as [pose], in the painter's order:
  /// the pose's shift, then its scale about the anchor.
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

  /// centred is whether the anchor is where it starts, in the middle.
  bool get anchorCentred => base.anchorX == 0.5 && base.anchorY == 0.5;

  /// anchorIn is where the anchor is in [box], before any turn: the point
  /// of [box] at the anchor's shares of it.
  Offset anchorIn(Rect box) => Offset(
      box.left + box.width * base.anchorX, box.top + box.height * base.anchorY);

  /// anchorAt is where the anchor is on the page at [frame]: in the box
  /// moved as the pose moves it, and turned with it about its centre. A
  /// keyframe's own turn and size are about the anchor, so they leave it
  /// where it is.
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

  /// withAnchorAt is this element with its anchor moved to [page], a point
  /// on the page at [frame], turned back into the element's own box. The
  /// element does not move: it turns about its centre at rest, and the
  /// anchor is only what its animation turns and grows about.
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

  /// turnedTo is this element turned to [degrees] about its anchor rather
  /// than its centre: moved as well as turned, so that the anchor stays
  /// where it is on the page. The same as a plain turn while the anchor is
  /// in the middle.
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

  /// keepsAspect is whether a resize should hold this element's proportions
  /// even without Shift. See [ElementBase.lockAspect].
  bool get keepsAspect => base.lockAspect;

  /// rotationRadians is what the painter and the hit test both want.
  double get rotationRadians => rotation * math.pi / 180;

  /// assetIds is every stored picture this element refers to. The asset
  /// sweep deletes any picture no saved canvas names, so an element that
  /// refers to one must list it here.
  Set<String> get assetIds => const {};

  /// mediaIds is every stored sound or video this element refers to, in the
  /// media store (see CanvasMedia). Swept as [assetIds] are.
  Set<String> get mediaIds => const {};

  /// scaledBy is this element with its inside measurements (type, spacing,
  /// padding, in design units) sized by [by]. Asked only while proportions
  /// are held, when one number stands for both sides. The default changes
  /// nothing, right for elements whose contents are fractions of their box;
  /// see TextElement.scaledBy and TableElement.scaledBy.
  CanvasElement scaledBy(double by) => this;

  /// scalesInside is whether [scaledBy] does anything to this element, so
  /// the settings offer a typeScale field only where it has an effect.
  bool get scalesInside => false;

  /// withBase is [ElementBase.copyWith] plumbed through [rebase], so a caller
  /// changing one property writes one line rather than three.
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
        ownText: ownText,
        ownDesign: ownDesign,
        shared: shared,
        clearShared: clearShared,
        cue: cue,
      ));

  /// withId returns a copy under a new id, for duplicating an element.
  CanvasElement withId(String newId) => newId == id
      ? this
      : rebase(base.copyWith(id: newId, motion: base.motion.renamedFor(newId)));

  Map<String, dynamic> toJson() => {
        "kind": kind.name,
        ...base.toJson(),
        ...props(),
      };
}

/// _idCounter and newElementId make ids that are unique within a session and
/// unlikely to collide across them.
int _idCounter = 0;
final math.Random _idRandom = math.Random();

String newElementId() {
  var n = _idCounter++;
  var salt = _idRandom.nextInt(1 << 20);
  return "e${n.toRadixString(36)}_${salt.toRadixString(36)}";
}

/// maxSkew is the most an element is slanted, in degrees: past it, the box
/// is a line.
const double maxSkew = 80;

/// BoxFrame is how an element's own box is laid on the page about its
/// middle: turned by [rotation], then slanted by [skewX] and [skewY], all in
/// degrees. [apply] maps an offset from the middle in the box's own space to
/// one on the page, and [invert] goes back. It is the mapping the renderer
/// draws with (Canvas.rotate, then Canvas.skew), so clicks, handles and
/// outlines land where the element is drawn.
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

  /// upright is whether it neither turns nor slants.
  bool get upright => rotation == 0 && skewX == 0 && skewY == 0;

  /// slanted is whether it slants at all.
  bool get slanted => skewX != 0 || skewY != 0;

  Offset apply(Offset p) => Offset(a * p.dx + b * p.dy, c * p.dx + d * p.dy);

  Offset invert(Offset p) {
    var det = a * d - b * c;
    if (det.abs() < 1e-12) return p;
    return Offset((d * p.dx - b * p.dy) / det, (-c * p.dx + a * p.dy) / det);
  }

  /// applyTo lays [canvas] out the box's way about [centre]: what is drawn
  /// next in the box's own space lands where the element is.
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

  /// corners is [box] laid out this way about its own middle.
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
