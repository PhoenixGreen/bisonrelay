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
  player("Team"),
  // A number that counts -- across the timeline, or in real time when nobody
  // has keyframed it. See CounterElement.
  counter("Counter");

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

  /// lockAspect holds an element's proportions while it is resized.
  ///
  /// On the base rather than on the elements that want it, because every
  /// element can want it: a logo, a headline box, a chart drawn to a shape
  /// that suits it. It was a picture's own setting, and a picture is only the
  /// most obvious case of a general one.
  ///
  /// It does not stop a resize, which is the whole of what it is for. The
  /// width and the height move together, so dragging a corner or typing a
  /// width changes the size without changing the shape.
  final bool lockAspect;

  /// track is this element's animation, or null when it does not move.
  final ElementTrack? track;

  /// typeScale is how much the element's own measurements -- its type, its
  /// spacing, the room inside its box -- have been sized by for the shape
  /// being looked at.
  ///
  /// Bookkeeping for the shape switch rather than a setting in its own
  /// right, and the reason it has to be written down: moving to another
  /// shape has to *undo* this one's scaling before applying that one's, and
  /// the scaled numbers themselves cannot say what they were scaled by.
  ///
  /// It is also the knob a design needs on a narrow page, where the type that
  /// was right across a banner is a word a line. See ElementLayout.typeScale.
  final double typeScale;

  /// ownText is whether the shape being looked at has words of its own --
  /// see ElementLayout.ownText.
  final bool ownText;

  /// ownDesign is whether this element is its own on the shape being looked
  /// at rather than the one the shapes share.
  ///
  /// Off, an element is one thing laid out several ways: its colours, its
  /// type and its settings are the same everywhere and only its place, its
  /// size and how much that design has been scaled by belong to the shape.
  /// That is what keeps a typo fixed once and a colour changed once.
  ///
  /// On, this shape keeps a copy of the whole element and nothing done to it
  /// anywhere else reaches this one. For the case the shared design cannot
  /// carry: a headline that is a different size *and* a different weight on
  /// the narrow page, a chart that is a bar on one shape and a line on
  /// another.
  final bool ownDesign;

  /// shared is the design the shapes share, kept aside while a shape is
  /// showing one of its own.
  ///
  /// The element itself is whatever the shape being looked at shows, so
  /// without this the shared design is gone the moment a detached shape is
  /// opened: there is one set of settings and the detached shape is using
  /// it. Null while nothing is detached, which is nearly every element --
  /// then the element *is* the shared design. See ownDesign.
  final Map<String, dynamic>? shared;

  /// layouts is where this element sits on each of the *other* shapes the
  /// document is being designed for, by ratio -- see ElementLayout and
  /// CanvasDocument.targets.
  ///
  /// The shape being looked at is not in here: its numbers are x, y, width
  /// and height above, live, so that every painter, every handle and every
  /// settings field goes on reading the element the way it always has.
  /// Changing the document's shape puts the live numbers away under the
  /// shape being left and takes out the ones belonging to the shape being
  /// opened. See CanvasDocument.forShape.
  ///
  /// Only the place and the size. What the element *is* -- its words, its
  /// colours, its data, how it arrives -- is one thing across every shape,
  /// so that a headline fixed on the square is fixed on the banner too.
  final Map<String, ElementLayout> layouts;

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
    this.lockAspect = false,
    this.track,
    this.layouts = const {},
    this.typeScale = 1,
    this.ownText = false,
    this.ownDesign = false,
    this.shared,
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
    bool? lockAspect,
    ElementTrack? track,
    bool clearTrack = false,
    Map<String, ElementLayout>? layouts,
    double? typeScale,
    bool? ownText,
    bool? ownDesign,
    Map<String, dynamic>? shared,
    bool clearShared = false,
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
        lockAspect: lockAspect ?? this.lockAspect,
        track: clearTrack ? null : (track ?? this.track),
        layouts: layouts ?? this.layouts,
        typeScale: typeScale ?? this.typeScale,
        ownText: ownText ?? this.ownText,
        ownDesign: ownDesign ?? this.ownDesign,
        shared: clearShared ? null : (shared ?? this.shared),
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
      lockAspect: _b(json["aspect"], false),
      track: trackJson is Map<String, dynamic>
          ? ElementTrack.fromJson(trackJson)
          : null,
      typeScale: _d(json["typeScale"], 1),
      ownText: _b(json["ownText"], false),
      ownDesign: _b(json["ownDesign"], false),
      shared: json["shared"] is Map<String, dynamic>
          ? json["shared"] as Map<String, dynamic>
          : null,
      layouts: {
        if (json["layouts"] is Map)
          for (var e in (json["layouts"] as Map).entries)
            if (e.value is Map<String, dynamic>)
              "${e.key}": ElementLayout.fromJson(e.value as Map<String, dynamic>),
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
        if (opacity != 1) "opacity": opacity,
        if (!visible) "visible": false,
        if (locked) "locked": true,
        // Written even when false, unlike the other switches here. Its
        // absence has to mean "saved before elements had this", so that a
        // picture from an older document can be given back the locked
        // proportions every picture used to have -- see
        // ImageElement.fromJson. An absent key that could also mean "off"
        // would make that impossible to tell.
        "aspect": lockAspect,
        if (track != null && !track!.isEmpty) "track": track!.toJson(),
        if (typeScale != 1) "typeScale": typeScale,
        if (ownText) "ownText": true,
        if (ownDesign) "ownDesign": true,
        if (shared != null) "shared": shared,
        if (layouts.isNotEmpty)
          "layouts": {
            for (var e in layouts.entries) e.key: e.value.toJson(),
          },
      };
}

/// ElementLayout is where an element sits on one shape of the canvas.
///
/// The place and the size and nothing else. A document designed for several
/// shapes -- a 4:5 for a feed, a 16:9 for a screen -- is one set of elements
/// laid out several ways, not several documents to keep in step.
///
/// [visible] is part of the layout because "not on this one" is a layout
/// decision: a wide strip across the top of a banner has no business on a
/// tall canvas, and squeezing it is not the answer.
class ElementLayout {
  final double x;
  final double y;
  final double width;
  final double height;
  final bool visible;

  /// typeScale is how much the element's own measurements are sized by on
  /// this shape -- see ElementBase.typeScale.
  ///
  /// Part of the layout because it is a layout decision: a headline that
  /// carries a banner is a word a line on a tall page, and the answer is
  /// smaller type there rather than different words.
  final double typeScale;

  /// text is the words this shape shows. Null for everything that is not a
  /// text element.
  ///
  /// Kept on every shape, its own or not, so that going to a shape with its
  /// own words and back again gives the others theirs. [ownText] is what
  /// tells the two apart.
  final String? text;

  /// own is this element's whole design on this shape, for one that has been
  /// detached here -- see ElementBase.ownDesign. Null means it follows the
  /// design the shapes share.
  final Map<String, dynamic>? own;

  /// framing and crop are a picture's own on this shape, always.
  ///
  /// Not part of the shared design and not something anybody has to ask for:
  /// which part of a photograph is showing, and how much of it, is a decision
  /// about a frame -- and the frame is a different shape on every one of
  /// these. A portrait cropped to sit beside a headline on a feed card is the
  /// wrong crop for the same headline across a screen.
  final Map<String, dynamic>? framing;
  final Map<String, dynamic>? crop;

  /// ownText is whether those words are this shape's own.
  ///
  /// The one thing scaling cannot fix: type half the size still wraps where
  /// the page is narrow, and a headline that takes two lines across a banner
  /// takes four down a feed. Somewhere there has to be a place to say "on
  /// this one, fewer words" -- and everywhere else goes on sharing one set,
  /// so a typo is still fixed once.
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
        // The design inside the box comes down with the box, or a headline
        // seeded onto a smaller page keeps the type it had on the larger one
        // and runs out of the frame.
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
        x: _d(json["x"], 0),
        y: _d(json["y"], 0),
        width: _d(json["w"], 200),
        height: _d(json["h"], 100),
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
          other.ownText == ownText;

  @override
  int get hashCode =>
      Object.hash(x, y, width, height, visible, typeScale, text, ownText);
}

/// jsonSpec reads a nested value object -- a TextSpec, a BoxSpec, a
/// ProceduralSpec -- falling back to [fallback] when the field is missing or
/// is not a map.
///
/// One function rather than the same three-line conditional at every nested
/// field, and the reason it takes the parser as an argument is that these
/// specs have nothing in common beyond being maps.
T jsonSpec<T>(dynamic v, T Function(Map<String, dynamic>) parse, T fallback) =>
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
  /// even without Shift. See [ElementBase.lockAspect].
  bool get keepsAspect => base.lockAspect;

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

  /// scaledBy is this element with everything inside it sized by [by].
  ///
  /// The type, the spacing, the room inside a box: the things that are in
  /// design units and would otherwise stay the size they were while the box
  /// round them changed. Only asked while the proportions are being held --
  /// see ElementBase.lockAspect -- because it is only then that one number
  /// can stand for what happened to both sides.
  ///
  /// The default is to change nothing, which is right for every element whose
  /// contents are already fractions of its box: a chart, a picture. The ones
  /// that carry measurements say so -- see TextElement.scaledBy and
  /// TableElement.scaledBy.
  CanvasElement scaledBy(double by) => this;

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
    bool? lockAspect,
    ElementTrack? track,
    bool clearTrack = false,
    Map<String, ElementLayout>? layouts,
    double? typeScale,
    bool? ownText,
    bool? ownDesign,
    Map<String, dynamic>? shared,
    bool clearShared = false,
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
        lockAspect: lockAspect,
        track: track,
        clearTrack: clearTrack,
        layouts: layouts,
        typeScale: typeScale,
        ownText: ownText,
        ownDesign: ownDesign,
        shared: shared,
        clearShared: clearShared,
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
