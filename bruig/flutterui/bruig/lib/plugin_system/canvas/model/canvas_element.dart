import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data' show Float64List;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/colour_map.dart';
import 'package:bruig/plugin_system/canvas/model/element_reading.dart'
    show elementFromJson;
import 'package:bruig/plugin_system/canvas/model/json_read.dart';
import 'package:bruig/plugin_system/canvas/model/layer_blend.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'package:bruig/plugin_system/canvas/model/stage_spot.dart';

// Every element reads its saved fields with the readers in json_read.dart,
// so whatever imports an element has them.
export 'package:bruig/plugin_system/canvas/model/json_read.dart';

// canvas_element.dart is what everything on a canvas has in common.
//
// ElementBase holds the box, turn, opacity, name and motion every element
// has, so the stage can move and animate any element without knowing its
// kind; only the painter and settings switch on kind. Elements are
// immutable, so undo is a list of documents.

/// ElementKind names the families. Saved by name: the order may change, the
/// names may not.
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

  /// player is a whole side (TeamElement); it keeps the name "player" so
  /// saved documents load.
  player("Team"),
  counter("Counter"),
  audio("Audio"),
  video("Video"),
  vector("Vector"),
  character3d("3D character"),

  /// stage is the 3D set a background carries (BackdropKind.stage), never
  /// added by itself.
  stage("3D stage"),
  sprite("Sprite"),
  tileMap("Tile map"),

  /// parallax is scenery a background carries (BackdropKind.parallax), never
  /// added by itself.
  parallax("Parallax"),
  sheet("Sheet music"),
  camera("Camera"),
  object3d("3D object"),

  /// synth is one synth module, patched to others with cables.
  synth("Synth module"),

  /// synthTask is what to make on a synth rack, and checks of the patch.
  synthTask("Synth task"),
  metronome("Metronome"),

  /// code is a small code project in tabbed panes (code_element.dart).
  code("Code"),

  /// codeRun is what a Code panel's project makes, run
  /// (code_run_element.dart).
  codeRun("Run panel"),

  /// codeTask is a task marked against a Code panel's code
  /// (code_task_element.dart).
  codeTask("Code task"),

  /// layout is a box divided into cells: comic panels, a grid of cards, free
  /// shapes (layout_element.dart).
  layout("Layout"),

  /// playTask is steps ticked as an instrument's keys are played
  /// (play_task_element.dart).
  playTask("Play task");

  final String label;
  const ElementKind(this.label);

  /// fromName is the kind saved as [name], or null for one this build does
  /// not know (a newer build's, or nonsense).
  static ElementKind? fromName(Object? name) =>
      values.where((k) => k.name == name).firstOrNull;
}

/// _far is the furthest out and biggest a received element may be: many
/// pages, but never a size that cannot be drawn.
const double _far = 1e6;

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
  /// is on its sounds. Not put through mapColours: it is the editor's colour
  /// for the row, not the design's.
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

  /// track is its keyframes, or null: those made on the Chain's Keyframes
  /// card, and everything a clip cannot say (a background's, a stage's,
  /// scenery's, a team's runs). Played under its [motion] clips, whose moves
  /// are added on top (poseWithMotion in render/motion_document.dart).
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

  /// dock is the Layout cell it is docked in, "layout id:cell id", or empty:
  /// drawn clipped to the cell, and moved when the whole layout is moved;
  /// editing the layout's cells leaves it as it is (layout_sync.dart).
  /// [dockOut] lets it break out of the
  /// cell's edge, as a figure does over a comic panel's line.
  final String dock;
  final bool dockOut;

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
    this.dock = "",
    this.dockOut = false,
    this.play = const PlaySpec(),
    this.spot,
    this.motion = ElementMotion.none,
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = ElementBase(id: "");

  /// asDesign is this base as a design kept to be used again (a preset):
  /// without what ties the element to its place in one document. Those are
  /// its place and keyframes, and whatever names something else there: its
  /// cue, its Cast member, the Layout cell it is docked in, and its layouts
  /// and shared design on the document's other page shapes. Its clips, its
  /// game part and its stage spot stay: they are what it does.
  ///
  /// [withTiesOf] is the other half. A field added to the class belongs in
  /// one of the two, or in neither where it is design:
  /// test/canvas_element_presets_test.dart asks which.
  ElementBase asDesign() => copyWith(
        x: 0,
        y: 0,
        clearTrack: true,
        cue: "",
        cast: "",
        dock: "",
        dockOut: false,
        layouts: const {},
        clearShared: true,
        ownDesign: false,
        ownText: false,
      );

  /// withTiesOf is this base, a design's, on the element [own] was: the
  /// design's size, turn and look with the element's own identity, place
  /// and everything that ties it to its document or says what it does
  /// there. For putting a preset on an element that is already in use.
  ElementBase withTiesOf(ElementBase own) => copyWith(
        id: own.id,
        name: own.name,
        x: own.x,
        y: own.y,
        opacity: own.opacity,
        visible: own.visible,
        locked: own.locked,
        rowColour: own.rowColour,
        clearRowColour: own.rowColour == null,
        track: own.track,
        clearTrack: own.track == null,
        layouts: own.layouts,
        depth: own.depth,
        ownText: own.ownText,
        ownDesign: own.ownDesign,
        shared: own.shared,
        clearShared: own.shared == null,
        cue: own.cue,
        cast: own.cast,
        dock: own.dock,
        dockOut: own.dockOut,
        play: own.play,
        spot: own.spot,
        clearSpot: own.spot == null,
        motion: own.motion,
      );

  /// copyWith's parameters are in the fields' order. A field added here is
  /// added to [CanvasElement.withBase] too.
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
    String? dock,
    bool? dockOut,
    PlaySpec? play,
    StageSpot? spot,
    bool clearSpot = false,
    ElementMotion? motion,
  }) =>
      ElementBase(
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
        dock: dock ?? this.dock,
        dockOut: dockOut ?? this.dockOut,
        play: play ?? this.play,
        spot: clearSpot ? null : (spot ?? this.spot),
        motion: motion ?? this.motion,
      );

  /// mapColours maps what of the base is design: its motion's colours, and
  /// the copies of the whole design it keeps for other page shapes ([shared]
  /// and each layout's own), each read as an element of its kind, mapped and
  /// written back in the same form. Only a copy whose colours changed is
  /// written again. The copies are for other shapes of page, so none of
  /// their colours shows on this one. [rowColour] is the editor's, and is
  /// left alone.
  ElementBase mapColours(ColourMap f) {
    var p = ColourPass(f);
    var motion = p.part(this.motion, (m) => m.mapColours(f));
    var elsewhere = f.shownOnlyIf(false);
    var shared = p.partOrNone(this.shared, (s) => _mappedDesign(s, elsewhere));
    var layouts = p.values(this.layouts, (_, l) {
      var own = l.own;
      if (own == null) return l;
      var next = _mappedDesign(own, elsewhere);
      return identical(next, own) ? l : l.copyWith(own: next);
    });
    if (!p.changed) return this;
    return copyWith(motion: motion, shared: shared, layouts: layouts);
  }

  /// _mappedDesign is [design], a copy of a whole element as kept for a page
  /// shape (its toJson less its layouts and shared copy: see _snapshot in
  /// responsive_layout.dart), with its colours mapped; the very same map
  /// where none changed.
  static Map<String, dynamic> _mappedDesign(
      Map<String, dynamic> design, ColourMap f) {
    var element = elementFromJson(design);
    var mapped = element.mapColours(f);
    if (identical(mapped, element)) return design;
    var out = mapped.toJson()
      ..remove("layouts")
      ..remove("shared");
    // Read without an id, it was given one; it is written as it came.
    if (!design.containsKey("id")) out.remove("id");
    return out;
  }

  factory ElementBase.fromJson(Map<String, dynamic> json, String defaultName) {
    var trackJson = json["track"];
    return ElementBase(
      id: jsonId(json["id"], newElementId()),
      name: jsonLabel(json["name"], defaultName),
      x: jsonDouble(json["x"], _defaults.x).clamp(-_far, _far),
      y: jsonDouble(json["y"], _defaults.y).clamp(-_far, _far),
      width: jsonDouble(json["w"], _defaults.width).clamp(0.0, _far),
      height: jsonDouble(json["h"], _defaults.height).clamp(0.0, _far),
      rotation: jsonDouble(json["rot"], _defaults.rotation),
      skewX: jsonDouble(json["skx"], _defaults.skewX).clamp(-maxSkew, maxSkew),
      skewY: jsonDouble(json["sky"], _defaults.skewY).clamp(-maxSkew, maxSkew),
      opacity: jsonDouble(json["opacity"], _defaults.opacity).clamp(0.0, 1.0),
      blend: LayerBlend.fromName(jsonStr(json["blend"])),
      visible: jsonBool(json["visible"], true),
      locked: jsonBool(json["locked"], false),
      rowColour: json["rowColour"] is int ? json["rowColour"] as int : null,
      lockAspect: jsonBool(json["aspect"], false),
      anchorX: jsonDouble(json["ax"], _defaults.anchorX),
      anchorY: jsonDouble(json["ay"], _defaults.anchorY),
      anchorLocked: jsonBool(json["anchorLocked"], false),
      track: trackJson is Map<String, dynamic>
          ? ElementTrack.fromJson(trackJson)
          : null,
      typeScale: jsonDouble(json["typeScale"], _defaults.typeScale),
      depth: jsonDouble(json["depth"], _defaults.depth)
          .clamp(-1.0, 1.0)
          .toDouble(),
      ownText: jsonBool(json["ownText"], false),
      ownDesign: jsonBool(json["ownDesign"], false),
      shared: jsonMap(json["shared"]),
      cue: jsonId(json["cue"], _defaults.cue),
      cast: jsonId(json["cast"], _defaults.cast),
      // Two ids and the colon between them.
      dock: jsonString(json["dock"], "", most: maxIdLength * 2 + 1),
      dockOut: jsonBool(json["dockOut"], false),
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
        if (rotation != _defaults.rotation) "rot": rotation,
        if (skewX != _defaults.skewX) "skx": skewX,
        if (skewY != _defaults.skewY) "sky": skewY,
        if (opacity != _defaults.opacity) "opacity": opacity,
        if (blend != _defaults.blend) "blend": blend.name,
        if (!visible) "visible": false,
        if (locked) "locked": true,
        if (rowColour != null) "rowColour": rowColour,
        "aspect": lockAspect,
        if (anchorX != _defaults.anchorX) "ax": anchorX,
        if (anchorY != _defaults.anchorY) "ay": anchorY,
        if (anchorLocked) "anchorLocked": true,
        if (track != null && !track!.isEmpty) "track": track!.toJson(),
        if (typeScale != _defaults.typeScale) "typeScale": typeScale,
        if (depth != _defaults.depth) "depth": depth,
        if (ownText) "ownText": true,
        if (ownDesign) "ownDesign": true,
        if (shared != null) "shared": shared,
        if (cue.isNotEmpty) "cue": cue,
        if (cast.isNotEmpty) "cast": cast,
        if (dock.isNotEmpty) "dock": dock,
        if (dockOut) "dockOut": true,
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

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = ElementLayout(x: 0, y: 0, width: 0, height: 0);

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
        if (typeScale != _defaults.typeScale) "typeScale": typeScale,
        if (text != null) "text": text,
        if (ownText) "ownText": true,
        if (own != null) "own": own,
        if (framing != null) "framing": framing,
        if (crop != null) "crop": crop,
      };

  factory ElementLayout.fromJson(Map<String, dynamic> json) => ElementLayout(
        x: jsonDouble(json["x"], 0).clamp(-_far, _far),
        y: jsonDouble(json["y"], 0).clamp(-_far, _far),
        width: jsonDouble(json["w"], 200).clamp(0.0, _far),
        height: jsonDouble(json["h"], 100).clamp(0.0, _far),
        visible: jsonBool(json["visible"], true),
        typeScale: jsonDouble(json["typeScale"], _defaults.typeScale),
        text: jsonStr(json["text"]),
        ownText: jsonBool(json["ownText"], false),
        own: jsonMap(json["own"]),
        framing: jsonMap(json["framing"]),
        crop: jsonMap(json["crop"]),
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

  /// mapOwnColours is the element with every colour of its own fields (and
  /// of what they hold) put through [f], and nothing [ElementBase] owns; the
  /// very same element where none changed (see colour_map.dart). Each kind
  /// states its own, so a kind cannot be added without saying what colours
  /// it holds; one with none answers itself.
  CanvasElement mapOwnColours(ColourMap f);

  /// mapColours is the element with every colour of its design put through
  /// [f]: its own ([mapOwnColours]) and its base's (ElementBase.mapColours).
  /// The very same element where none changed.
  CanvasElement mapColours(ColourMap f) {
    var own = mapOwnColours(f);
    var base = own.base.mapColours(f);
    return identical(base, own.base) ? own : own.rebase(base);
  }

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

  /// boxFrame is how the box is laid on the page about its middle as it
  /// rests: its own turn and slant, which paintElement lays the canvas out
  /// by before a pose turns or sizes it about the anchor.
  BoxFrame get boxFrame => BoxFrame(rotation, base.skewX, base.skewY);

  /// onPage is [p], a point of the box as it is drawn before its turn and
  /// slant, where it lands on the page ([boxFrame] about the box's
  /// middle); fromPage is the way back, for a press or a drag on the page.
  Offset onPage(Offset p) => boxFrame.place(p, center);
  Offset fromPage(Offset p) => boxFrame.unplace(p, center);

  /// placedBy is where paintElement lays this element's box on the page in
  /// [pose]: see ElementPlace. With Keyframe.rest it places as [onPage]
  /// does.
  ElementPlace placedBy(Keyframe pose) => placedIn(bounds, pose);

  /// placedIn is [placedBy] for the box [box], where the painter draws the
  /// element somewhere other than its bounds (a page number mirrored onto a
  /// left-hand page). Its moving loop's turn and size are read from [loop]
  /// where that is given, as the painter does when the rest of the pose is
  /// laid on outside it.
  ElementPlace placedIn(Rect box, Keyframe pose, {Keyframe? loop}) {
    var squash = pose.values[KeyframeChannel.squash];
    var squashed = squash != null && (squash - 1).abs() > 1e-3 && squash > 0;
    var looping = (loop ?? pose).values;
    var loopTurn = looping[KeyframeChannel.loopTurn];
    // About the element's anchor where it has been moved; otherwise where
    // the loop itself turns: a swing hangs from its top.
    var pivot = loopTurn == null
        ? Offset.zero
        : anchorCentred
            ? Offset(looping[KeyframeChannel.loopPivotX] ?? 0.5,
                looping[KeyframeChannel.loopPivotY] ?? 0.5)
            : Offset(base.anchorX, base.anchorY);
    return ElementPlace(
      centre: box.center,
      shift: Offset(pose.dx, pose.dy),
      squash: squashed ? squash : 1,
      squashAngle: squashed ? pose.values[KeyframeChannel.squashAngle] ?? 0 : 0,
      frame: boxFrame,
      anchor: pose.rotate != 0 || pose.scale != 1 ? anchorIn(box) : Offset.zero,
      turn: pose.rotate,
      size: pose.scale,
      loopPivot: Offset(
          box.left + box.width * pivot.dx, box.top + box.height * pivot.dy),
      loopTurn: loopTurn ?? 0,
      loopSx: loopTurn == null ? 1 : looping[KeyframeChannel.loopSx] ?? 1,
      loopSy: loopTurn == null ? 1 : looping[KeyframeChannel.loopSy] ?? 1,
    );
  }

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

  /// withProportionsKept is this element with its width and height held
  /// together as it is resized, or let go (ElementBase.lockAspect). A kind
  /// whose contents change with it says so (a picture squashes).
  CanvasElement withProportionsKept(bool keep) => withBase(lockAspect: keep);

  /// withBase is [ElementBase.copyWith] through [rebase], for one-line
  /// property changes. It takes everything copyWith does but the id, which
  /// [withId] changes.
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
    String? dock,
    bool? dockOut,
    PlaySpec? play,
    StageSpot? spot,
    bool clearSpot = false,
    ElementMotion? motion,
  }) =>
      rebase(base.copyWith(
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
        rowColour: rowColour,
        clearRowColour: clearRowColour,
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
        cast: cast,
        dock: dock,
        dockOut: dockOut,
        play: play,
        spot: spot,
        clearSpot: clearSpot,
        motion: motion,
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

  // Equal when turned and slanted alike: a, b, c and d follow from those.
  @override
  bool operator ==(Object other) =>
      other is BoxFrame &&
      other.rotation == rotation &&
      other.skewX == skewX &&
      other.skewY == skewY;

  @override
  int get hashCode => Object.hash(rotation, skewX, skewY);

  bool get upright => rotation == 0 && skewX == 0 && skewY == 0;

  bool get slanted => skewX != 0 || skewY != 0;

  Offset apply(Offset p) => Offset(a * p.dx + b * p.dy, c * p.dx + d * p.dy);

  Offset invert(Offset p) {
    var det = a * d - b * c;
    if (det.abs() < 1e-12) return p;
    return Offset((d * p.dx - b * p.dy) / det, (-c * p.dx + a * p.dy) / det);
  }

  /// place is [p], a point in box space, laid out this way about [centre],
  /// as [placePath] lays a path; unplace is the way back.
  Offset place(Offset p, Offset centre) {
    if (upright) return p;
    var x = p.dx - centre.dx, y = p.dy - centre.dy;
    return Offset(centre.dx + x * a + y * b, centre.dy + x * c + y * d);
  }

  Offset unplace(Offset p, Offset centre) =>
      upright ? p : centre + invert(p - centre);

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

  /// placePath is [path], drawn in box space, laid out this way about
  /// [centre] as [applyTo] lays out the canvas: an outline that must land
  /// where the element is drawn, for words to go round or a press to find.
  Path placePath(Path path, Offset centre) {
    if (upright) return path;
    return path.transform(Float64List.fromList([
      a, c, 0, 0, //
      b, d, 0, 0, //
      0, 0, 1, 0, //
      centre.dx - a * centre.dx - b * centre.dy,
      centre.dy - c * centre.dx - d * centre.dy,
      0,
      1,
    ]));
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

/// ElementPlace is where paintElement lays an element's box on the page on
/// one frame, in the painter's order: moved by its pose, squashed along its
/// travel about its middle, turned and slanted as it rests about its middle
/// ([frame]), turned and sized by its pose about its anchor, and turned and
/// sized by a moving loop about the loop's pivot. [applyTo] lays a canvas out
/// so, and is what the painter calls; [place] takes a point of the box to
/// the page by the same steps in the same order and [unplace] brings one
/// back, so whatever asks where a part of an element is drawn (a stroke's
/// curve, a path's points, a line's ends) is answered where the painter put
/// it. Made by CanvasElement.placedIn. A step that does nothing is skipped,
/// so an element at rest is placed exactly as [frame] alone places it.
class ElementPlace {
  /// centre is the middle of the box, which the turn, slant and squash are
  /// about.
  final Offset centre;

  /// shift is the pose's move.
  final Offset shift;

  /// squash stretches by this along [squashAngle] (radians) and squeezes
  /// across; one is none.
  final double squash;
  final double squashAngle;

  /// frame is the element's own turn and slant.
  final BoxFrame frame;

  /// turn (degrees) and size are the pose's, about [anchor].
  final Offset anchor;
  final double turn;
  final double size;

  /// loopTurn (degrees), loopSx and loopSy are a moving loop's, about
  /// [loopPivot].
  final Offset loopPivot;
  final double loopTurn;
  final double loopSx;
  final double loopSy;

  // The turns' cosines and sines, worked out once: a stroke's every point
  // is placed by them.
  final (double, double) _squashTurn, _poseTurn, _loopTurn;

  ElementPlace({
    required this.centre,
    this.shift = Offset.zero,
    this.squash = 1,
    this.squashAngle = 0,
    required this.frame,
    this.anchor = Offset.zero,
    this.turn = 0,
    this.size = 1,
    this.loopPivot = Offset.zero,
    this.loopTurn = 0,
    this.loopSx = 1,
    this.loopSy = 1,
  })  : _squashTurn = _cosSin(squashAngle),
        _poseTurn = _cosSin(turn * math.pi / 180),
        _loopTurn = _cosSin(loopTurn * math.pi / 180);

  static (double, double) _cosSin(double radians) =>
      radians == 0 ? (1, 0) : (math.cos(radians), math.sin(radians));

  bool get _squashed => squash != 1;
  bool get _posed => turn != 0 || size != 1;
  bool get _looped => loopTurn != 0 || loopSx != 1 || loopSy != 1;

  /// leavesAlone is whether every point lands where it is in the box: an
  /// upright element at rest.
  bool get leavesAlone =>
      shift == Offset.zero &&
      !_squashed &&
      !_posed &&
      !_looped &&
      frame.upright;

  /// stretch is the most the pose and the loop lengthen anything drawn,
  /// before the turn and slant the element rests in: what a stroke's width is
  /// drawn at, so its bounds and its press grow with it.
  double get stretch =>
      size.abs() *
      (_looped ? math.max(loopSx.abs(), loopSy.abs()) : 1) *
      (_squashed ? math.max(squash, 1 / squash) : 1);

  /// applyTo lays [canvas] out so what is drawn next in box space lands
  /// where the element is on this frame.
  void applyTo(Canvas canvas) {
    if (shift != Offset.zero) canvas.translate(shift.dx, shift.dy);
    if (_squashed) {
      canvas.translate(centre.dx, centre.dy);
      canvas.rotate(squashAngle);
      canvas.scale(squash, 1 / squash);
      canvas.rotate(-squashAngle);
      canvas.translate(-centre.dx, -centre.dy);
    }
    frame.applyTo(canvas, centre);
    if (_posed) {
      canvas.translate(anchor.dx, anchor.dy);
      if (turn != 0) canvas.rotate(turn * math.pi / 180);
      if (size != 1) canvas.scale(size);
      canvas.translate(-anchor.dx, -anchor.dy);
    }
    if (_looped) {
      canvas.translate(loopPivot.dx, loopPivot.dy);
      if (loopTurn != 0) canvas.rotate(loopTurn * math.pi / 180);
      if (loopSx != 1 || loopSy != 1) canvas.scale(loopSx, loopSy);
      canvas.translate(-loopPivot.dx, -loopPivot.dy);
    }
  }

  /// place is [p], a point of the box as drawn before any of this, where it
  /// lands on the page; unplace is the way back, for a press or a drag.
  Offset place(Offset p) {
    var q = p;
    if (_looped) {
      q = loopPivot +
          _turned(
              Offset((q.dx - loopPivot.dx) * loopSx,
                  (q.dy - loopPivot.dy) * loopSy),
              _loopTurn);
    }
    if (_posed) q = anchor + _turned((q - anchor) * size, _poseTurn);
    q = frame.place(q, centre);
    if (_squashed) {
      var d = _turned(q - centre, _back(_squashTurn));
      q = centre + _turned(Offset(d.dx * squash, d.dy / squash), _squashTurn);
    }
    return q + shift;
  }

  Offset unplace(Offset p) {
    var q = p - shift;
    if (_squashed) {
      var d = _turned(q - centre, _back(_squashTurn));
      q = centre + _turned(Offset(d.dx / squash, d.dy * squash), _squashTurn);
    }
    q = frame.unplace(q, centre);
    if (_posed && size != 0) {
      q = anchor + _turned(q - anchor, _back(_poseTurn)) / size;
    }
    if (_looped && loopSx != 0 && loopSy != 0) {
      var d = _turned(q - loopPivot, _back(_loopTurn));
      q = loopPivot + Offset(d.dx / loopSx, d.dy / loopSy);
    }
    return q;
  }

  /// _turned is [v] turned by the angle whose cosine and sine are [by].
  static Offset _turned(Offset v, (double, double) by) {
    var (c, s) = by;
    if (s == 0 && c == 1) return v;
    return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
  }

  /// _back is the turn the other way.
  static (double, double) _back((double, double) by) => (by.$1, -by.$2);

  @override
  bool operator ==(Object other) =>
      other is ElementPlace &&
      other.centre == centre &&
      other.shift == shift &&
      other.squash == squash &&
      other.squashAngle == squashAngle &&
      other.frame == frame &&
      other.anchor == anchor &&
      other.turn == turn &&
      other.size == size &&
      other.loopPivot == loopPivot &&
      other.loopTurn == loopTurn &&
      other.loopSx == loopSx &&
      other.loopSy == loopSy;

  @override
  int get hashCode => Object.hash(centre, shift, squash, squashAngle, frame,
      anchor, turn, size, loopPivot, loopTurn, loopSx, loopSy);
}
