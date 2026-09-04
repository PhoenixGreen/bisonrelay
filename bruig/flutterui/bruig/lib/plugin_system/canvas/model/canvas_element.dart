import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';

// canvas_element.dart is what everything on a canvas has in common, and
// nothing else.
//
// Every element is a rectangle with a rotation, an opacity and a name, plus
// its own properties. The base class owns the first list and knows nothing
// about the second, which is what lets the stage drag, resize, rotate,
// reorder and animate a chart without ever asking what a chart is. Only the
// painter and the settings bar switch on the kind.
//
// Elements are immutable. Every edit produces a new element and a new
// document, which is what makes undo a list of documents rather than a list
// of reversible operations -- and reversible operations are where an editor
// like this usually goes wrong.

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
  // "Team", because one of these is a whole side rather than one dot -- see
  // TeamElement. The enum value keeps its old name so that documents saved
  // before the change still load.
  path("Path"),
  player("Team");

  final String label;
  const ElementKind(this.label);
}

/// colorToJson and colorFromJson are the one encoding of a colour in a saved
/// document: 0xAARRGGBB as a plain integer.
///
/// Written by hand rather than through Color.value, which is deprecated in
/// favour of floating-point channels -- and a float channel round-tripped
/// through JSON is a colour that comes back very slightly different from the
/// one that was saved.
int colorToJson(Color c) =>
    (_channel(c.a) << 24) |
    (_channel(c.r) << 16) |
    (_channel(c.g) << 8) |
    _channel(c.b);

int _channel(double v) => (v * 255).round().clamp(0, 255);

Color colorFromJson(dynamic v, [Color fallback = const Color(0xFFFFFFFF)]) =>
    v is num ? Color(v.toInt()) : fallback;

double _d(dynamic v, double fallback) => v is num ? v.toDouble() : fallback;
int _i(dynamic v, int fallback) => v is num ? v.toInt() : fallback;
bool _b(dynamic v, bool fallback) => v is bool ? v : fallback;
String _s(dynamic v, String fallback) => v is String ? v : fallback;

/// jsonDouble, jsonInt, jsonBool and jsonString are the same readers, exported
/// for the element subclasses. A saved document is text from disk and may be
/// from an older build, so every read has to survive the field being absent or
/// being the wrong type -- never a cast that throws and loses the document.
double jsonDouble(dynamic v, double fallback) => _d(v, fallback);
int jsonInt(dynamic v, int fallback) => _i(v, fallback);
bool jsonBool(dynamic v, bool fallback) => _b(v, fallback);
String jsonString(dynamic v, String fallback) => _s(v, fallback);

/// ElementBase is every property that every element has.
///
/// Held by composition rather than spread across nine constructors. The stage
/// only ever changes these -- drag changes x and y, the handles change width
/// and height, the rotate ring changes rotation, the layer list changes the
/// order and the name -- so pulling them into one object means an element
/// subclass implements exactly one method to be fully editable, instead of
/// re-declaring nine fields and threading them through three constructors.
/// The first version of this file did it the other way and the boilerplate
/// was longer than every element's real content put together.
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

  /// rotation is in degrees, clockwise, about the element's centre. Degrees
  /// rather than radians because it is a number the user types.
  final double rotation;

  /// opacity multiplies the whole element, on top of whatever its own colours
  /// say.
  final double opacity;

  final bool visible;

  /// locked keeps an element out of the way of the pointer. A pitch or a
  /// background is something you place once and then want to stop selecting
  /// by accident every time you click near a player standing on it.
  final bool locked;

  /// track is this element's animation, or null when it does not move.
  final ElementTrack? track;

  const ElementBase({
    required this.id,
    this.name = "",
    this.x = 0,
    this.y = 0,
    this.width = 200,
    this.height = 100,
    this.rotation = 0,
    this.opacity = 1,
    this.visible = true,
    this.locked = false,
    this.track,
  });

  ElementBase copyWith({
    String? id,
    String? name,
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
    double? opacity,
    bool? visible,
    bool? locked,
    ElementTrack? track,
    bool clearTrack = false,
  }) =>
      ElementBase(
        id: id ?? this.id,
        name: name ?? this.name,
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
        rotation: rotation ?? this.rotation,
        opacity: opacity ?? this.opacity,
        visible: visible ?? this.visible,
        locked: locked ?? this.locked,
        track: clearTrack ? null : (track ?? this.track),
      );

  factory ElementBase.fromJson(Map<String, dynamic> json, String defaultName) {
    var trackJson = json["track"];
    return ElementBase(
      id: _s(json["id"], newElementId()),
      name: _s(json["name"], defaultName),
      x: _d(json["x"], 0),
      y: _d(json["y"], 0),
      width: _d(json["w"], 200),
      height: _d(json["h"], 100),
      rotation: _d(json["rot"], 0),
      opacity: _d(json["opacity"], 1).clamp(0.0, 1.0),
      visible: _b(json["visible"], true),
      locked: _b(json["locked"], false),
      track: trackJson is Map<String, dynamic>
          ? ElementTrack.fromJson(trackJson)
          : null,
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
        if (opacity != 1) "opacity": opacity,
        if (!visible) "visible": false,
        if (locked) "locked": true,
        if (track != null && !track!.isEmpty) "track": track!.toJson(),
      };
}

/// jsonSpec reads a nested value object -- a TextSpec, a BoxSpec, a
/// ProceduralSpec -- falling back to [fallback] when the field is missing or
/// is not a map.
///
/// One function rather than the same three-line conditional at every nested
/// field, and the reason it takes the parser as an argument is that these
/// specs have nothing in common beyond being maps.
T jsonSpec<T>(
        dynamic v, T Function(Map<String, dynamic>) parse, T fallback) =>
    v is Map<String, dynamic> ? parse(v) : fallback;

/// CanvasElement is one thing on the canvas.
///
/// Immutable. Every edit produces a new element and a new document, which is
/// what makes undo a list of documents rather than a list of reversible
/// operations -- and reversible operations are where an editor like this
/// usually goes wrong.
abstract class CanvasElement {
  final ElementBase base;

  const CanvasElement(this.base);

  ElementKind get kind;

  /// rebase is the one method a subclass owes the stage: the same element,
  /// with different base properties. Everything the stage does -- move,
  /// resize, rotate, rename, lock, hide, duplicate, animate -- goes through
  /// it, and none of it needs to know what the element is.
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
  double get opacity => base.opacity;
  bool get visible => base.visible;
  bool get locked => base.locked;
  ElementTrack? get track => base.track;

  Rect get bounds => Rect.fromLTWH(x, y, width, height);
  Offset get center => bounds.center;

  /// poseAt is where this element is on [frame], as an offset from where it
  /// rests. See canvas_animation.dart.
  Keyframe poseAt(int frame) => base.track?.at(frame) ?? Keyframe.rest;

  /// boundsAt is where the element actually *is* on [frame].
  ///
  /// Everything that puts something on screen beside an element has to use
  /// this rather than [bounds], and forgetting is the sort of bug that looks
  /// like the animation itself is wrong. The selection box and the handles
  /// used [bounds], so scrubbing an animated text element moved the words and
  /// left the blue rectangle behind at the resting position -- which reads
  /// exactly as though the text were being animated *inside* a box that was
  /// standing still.
  ///
  /// The transform matches the painter's, in the painter's order: the pose's
  /// shift in document space, then the scale about the centre it has moved to.
  Rect boundsAt(int frame) {
    var pose = poseAt(frame);
    var box = bounds.shift(Offset(pose.dx, pose.dy));
    if (pose.scale == 1) return box;
    return Rect.fromCenter(
      center: box.center,
      width: box.width * pose.scale,
      height: box.height * pose.scale,
    );
  }

  /// rotationAt and opacityAt are the same question for the other two things a
  /// pose carries.
  double rotationAt(int frame) => rotation + poseAt(frame).rotate;

  double opacityAt(int frame) =>
      (opacity * poseAt(frame).opacity).clamp(0.0, 1.0);

  /// keepsAspect is whether a resize should hold this element's proportions
  /// even without Shift. False for everything except a picture that has asked
  /// for it -- see ImageElement.lockAspect.
  bool get keepsAspect => false;

  /// rotationRadians is what the painter and the hit test both want.
  double get rotationRadians => rotation * math.pi / 180;

  /// assetIds is every stored picture this element refers to.
  ///
  /// Asked of the element rather than worked out by the document, and that is
  /// the whole point: the document used to know that a picture element has an
  /// asset and that nothing else does, so when a table learnt to hold one in
  /// a cell the sweep did not hear about it and deleted every badge on the
  /// next restart. An element that refers to a picture says so here, and
  /// there is nowhere else to forget.
  Set<String> get assetIds => const {};

  /// withBase is [ElementBase.copyWith] plumbed through [rebase], so a caller
  /// changing one property writes one line rather than three.
  CanvasElement withBase({
    String? name,
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
    double? opacity,
    bool? visible,
    bool? locked,
    ElementTrack? track,
    bool clearTrack = false,
  }) =>
      rebase(base.copyWith(
        name: name,
        x: x,
        y: y,
        width: width,
        height: height,
        rotation: rotation,
        opacity: opacity,
        visible: visible,
        locked: locked,
        track: track,
        clearTrack: clearTrack,
      ));

  /// withId returns a copy under a new id, for duplicating an element.
  CanvasElement withId(String newId) => rebase(base.copyWith(id: newId));

  Map<String, dynamic> toJson() => {
        "kind": kind.name,
        ...base.toJson(),
        ...props(),
      };
}

/// _idCounter and newElementId make ids that are unique within a session and
/// unlikely to collide across them.
///
/// Not a UUID and not a hash of the contents: two identical stars added one
/// after another must be two elements, and a content hash would make them one.
int _idCounter = 0;
final math.Random _idRandom = math.Random();

String newElementId() {
  var n = _idCounter++;
  var salt = _idRandom.nextInt(1 << 20);
  return "e${n.toRadixString(36)}_${salt.toRadixString(36)}";
}
