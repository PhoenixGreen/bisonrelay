import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_adjustment.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_effects.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_strokes.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_mask.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart'
    show VectorCue;
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/layer_blend.dart';
import 'package:bruig/plugin_system/canvas/model/own_motion.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart' show BoxSpec;
import 'package:bruig/plugin_system/canvas/model/motion.dart' show MotionKind;

export 'package:bruig/plugin_system/canvas/model/layer_blend.dart'
    show LayerBlend;

// image_layers.dart is the layers an Image element is composited from, and
// where each one sits. The element's own fields are the base layer, which
// fills the frame, so a picture with no layers is a stack of one. Other
// layers (placed pictures, fills, adjustments, textures, paint) each have
// their own blend, opacity and clipping.

/// layerUnits is how many units a picture layer's place is measured in,
/// across and down the frame: fractions of the frame, so the composite
/// scales with the element; a thousand rather than one, since code working
/// on an ImageElement's box (cropping's eight-unit minimum) expects numbers
/// about that size.
const double layerUnits = 1000;

/// baseLayerId is the id the base layer always has. There is only ever one.
const String baseLayerId = "base";

enum LayerKind {
  /// base is the element's own picture, filling the frame.
  base("Picture"),

  /// picture is another picture, placed anywhere in the frame.
  picture("Picture"),

  /// fill is a colour or a fade over the whole frame.
  fill("Colour"),

  /// adjustment changes the layers under it. See image_adjustment.dart.
  adjustment("Adjustment"),

  /// texture draws grain, paper and the like (image_effects.dart).
  texture("Texture"),

  /// paint is brushwork laid over the layers under it. See image_strokes.dart.
  paint("Paint");

  final String label;
  const LayerKind(this.label);

  static LayerKind fromName(String? name) =>
      values.firstWhere((k) => k.name == name, orElse: () => LayerKind.picture);
}

class ImageLayer {
  final String id;
  final LayerKind kind;

  /// name is the layer's name in the panel; empty is named for its content.
  final String name;

  final bool visible;

  /// locked stops the layer being picked, moved, sized or painted on the
  /// canvas; it is still drawn and set from the panel.
  final bool locked;

  /// loop is the layer's own loop, on top of the whole picture's; a drift
  /// here moves the layer's box, not the picture inside it.
  final ElementLoop loop;
  final double opacity;
  final LayerBlend blend;

  /// clip draws the layer only where the layer below has something; a run of
  /// clipped layers all clip to the first unclipped layer under them.
  final bool clip;

  /// look is a picture layer's picture and place, null for other kinds: its
  /// box is where it sits in [layerUnits], its rotation its turn in the
  /// frame. An ImageElement, so a layer has every setting the base has, with
  /// the same panel and painter.
  final ImageElement? look;

  /// flipX and flipY mirror a picture (a layer's or the base) in place.
  final bool flipX;
  final bool flipY;

  final PaintSpec fill;

  final ImageAdjustment adjust;

  final TextureSpec texture;

  /// effects are done to the layer as it is drawn.
  final List<LayerEffect> effects;

  /// strokes are a paint layer's brushwork, in order.
  final List<StrokeMark> strokes;

  /// cue is when the layer comes in, relative to the one under it, while the
  /// picture arrives: with it, after it, or after [cueGap] frames (negative
  /// overlaps). [cueLength] is its frames, or null for the whole arrival.
  final VectorCue cue;
  final int cueGap;
  final int? cueLength;

  /// basePlace is where the base picture sits, in [layerUnits], once moved
  /// or kept in place on a resize; null fills the frame.
  final Rect? basePlace;

  /// mask is where over the frame a [framed] layer shows, its marks in
  /// fractions of the frame. A picture layer's mask is its look's.
  final ImageMask mask;

  /// retouchesUnder is whether this paint layer retouches everything under
  /// it in the frame, not one picture. See paintRetouchUnder.
  bool get retouchesUnder =>
      kind == LayerKind.paint && strokes.any((s) => s.kind.retouches);

  /// framed is whether this layer's mask is over the frame, not a picture.
  bool get framed =>
      kind == LayerKind.adjustment ||
      kind == LayerKind.texture ||
      kind == LayerKind.fill ||
      kind == LayerKind.paint;

  const ImageLayer({
    required this.id,
    required this.kind,
    this.name = "",
    this.visible = true,
    this.locked = false,
    this.loop = const ElementLoop(),
    this.opacity = 1,
    this.blend = LayerBlend.normal,
    this.clip = false,
    this.look,
    this.flipX = false,
    this.flipY = false,
    this.fill = const PaintSpec(Color(0xFF000000)),
    this.adjust = const ImageAdjustment(),
    this.texture = const TextureSpec(),
    this.effects = const [],
    this.strokes = const [],
    this.cue = VectorCue.together,
    this.cueGap = 0,
    this.cueLength,
    this.mask = const ImageMask(),
    this.basePlace,
  });

  static const ImageLayer base =
      ImageLayer(id: baseLayerId, kind: LayerKind.base);

  bool get isBase => kind == LayerKind.base;

  /// plain is whether this is an untouched base layer: as good as none.
  bool get plain =>
      isBase &&
      basePlace == null &&
      name.isEmpty &&
      cue == VectorCue.together &&
      cueGap == 0 &&
      cueLength == null &&
      visible &&
      !locked &&
      !loop.on &&
      opacity == 1 &&
      blend == LayerBlend.normal &&
      !clip &&
      !flipX &&
      !flipY &&
      effects.isEmpty;

  factory ImageLayer.picture(String assetId, Rect place) => ImageLayer(
        id: newElementId(),
        kind: LayerKind.picture,
        look: ImageElement(
            ElementBase(
                id: "",
                x: place.left,
                y: place.top,
                width: place.width,
                height: place.height,
                // A picture keeps its proportions unless told otherwise.
                lockAspect: true),
            assetId: assetId,
            fit: ImageFit.stretch),
      );

  factory ImageLayer.adjusting(AdjustKind kind) => ImageLayer(
      id: newElementId(),
      kind: LayerKind.adjustment,
      adjust: ImageAdjustment(kind: kind));

  /// texturing is a new texture layer of [kind], in its usual blend.
  factory ImageLayer.texturing(TextureKind kind) => ImageLayer(
      id: newElementId(),
      kind: LayerKind.texture,
      blend: LayerBlend.fromName(kind.blend),
      texture: TextureSpec(kind: kind));

  factory ImageLayer.painting() =>
      ImageLayer(id: newElementId(), kind: LayerKind.paint);

  factory ImageLayer.solid(PaintSpec fill) =>
      ImageLayer(id: newElementId(), kind: LayerKind.fill, fill: fill);

  /// place is where a picture layer sits, in layer units.
  Rect get place => look != null
      ? Rect.fromLTWH(look!.x, look!.y, look!.width, look!.height)
      : basePlace ?? const Rect.fromLTWH(0, 0, layerUnits, layerUnits);

  /// turn is a picture layer's rotation within the frame, in degrees.
  double get turn => look?.rotation ?? 0;

  ImageLayer copyWith({
    String? id,
    String? name,
    bool? visible,
    bool? locked,
    ElementLoop? loop,
    double? opacity,
    LayerBlend? blend,
    bool? clip,
    ImageElement? look,
    bool? flipX,
    bool? flipY,
    PaintSpec? fill,
    ImageAdjustment? adjust,
    TextureSpec? texture,
    List<LayerEffect>? effects,
    List<StrokeMark>? strokes,
    VectorCue? cue,
    int? cueGap,
    int? cueLength,
    bool clearCueLength = false,
    ImageMask? mask,
    Rect? basePlace,
    bool clearBasePlace = false,
  }) =>
      ImageLayer(
        id: id ?? this.id,
        kind: kind,
        name: name ?? this.name,
        visible: visible ?? this.visible,
        locked: locked ?? this.locked,
        loop: loop ?? this.loop,
        opacity: (opacity ?? this.opacity).clamp(0.0, 1.0),
        blend: blend ?? this.blend,
        clip: clip ?? this.clip,
        // A picture layer's mask goes onto its look.
        look: mask != null &&
                kind == LayerKind.picture &&
                (look ?? this.look) != null
            ? (look ?? this.look)!.copyWith(mask: mask)
            : look ?? this.look,
        flipX: flipX ?? this.flipX,
        flipY: flipY ?? this.flipY,
        fill: fill ?? this.fill,
        adjust: adjust ?? this.adjust,
        texture: texture ?? this.texture,
        effects: effects ?? this.effects,
        strokes: strokes ?? this.strokes,
        cue: cue ?? this.cue,
        cueGap: cueGap ?? this.cueGap,
        cueLength: clearCueLength ? null : cueLength ?? this.cueLength,
        mask: kind == LayerKind.picture ? this.mask : mask ?? this.mask,
        basePlace: clearBasePlace ? null : basePlace ?? this.basePlace,
      );

  /// placed is this picture layer or base layer moved to [place], and a
  /// picture layer turned to [turn].
  ImageLayer placed(Rect place, {double? turn}) => look == null
      ? (isBase ? copyWith(basePlace: place) : this)
      : copyWith(
          look: look!.withBase(
              x: place.left,
              y: place.top,
              width: place.width,
              height: place.height,
              rotation: turn) as ImageElement);

  Map<String, dynamic> toJson() => {
        "id": id,
        "k": kind.name,
        if (name.isNotEmpty) "name": name,
        if (!visible) "hide": true,
        if (locked) "lock": true,
        if (loop.on) "loop": loop.toJson(),
        if (opacity != 1) "op": opacity,
        if (blend != LayerBlend.normal) "blend": blend.name,
        if (clip) "clip": true,
        if (look case var l?) "look": l.toJson(),
        // Not "fx": that key is the effects'.
        if (flipX) "flipX": true,
        if (flipY) "fy": true,
        if (kind == LayerKind.fill) "fill": fill.toJson(),
        if (kind == LayerKind.adjustment) "adjust": adjust.toJson(),
        if (kind == LayerKind.texture) "texture": texture.toJson(),
        if (effects.isNotEmpty) "fx": [for (var f in effects) f.toJson()],
        if (strokes.isNotEmpty) "strokes": [for (var s in strokes) s.toJson()],
        if (cue != VectorCue.together) "cue": cue.name,
        if (cueGap != 0) "gap": cueGap,
        if (cueLength != null) "len": cueLength,
        if (!mask.empty) "mask": mask.toJson(),
        if (basePlace case var p?) "place": [p.left, p.top, p.width, p.height],
      };

  static ImageLayer? fromJson(Map<String, dynamic> json) {
    var kind = LayerKind.fromName(jsonStr(json["k"]));
    ImageElement? look;
    if (kind == LayerKind.picture) {
      if (json["look"] is! Map<String, dynamic>) return null;
      var raw = json["look"] as Map<String, dynamic>;
      // A look is saved as a whole element, base and all.
      look = ImageElement.fromJson(raw, ElementBase.fromJson(raw, "Picture"));
    }
    return ImageLayer(
      id: kind == LayerKind.base
          ? baseLayerId
          : jsonString(json["id"], newElementId()),
      kind: kind,
      name: jsonString(json["name"], ""),
      visible: !jsonBool(json["hide"], false),
      locked: jsonBool(json["lock"], false),
      loop: jsonSpec(json["loop"], ElementLoop.fromJson, const ElementLoop()),
      opacity: jsonDouble(json["op"], 1).clamp(0.0, 1.0),
      blend: LayerBlend.fromName(jsonStr(json["blend"])),
      clip: jsonBool(json["clip"], false),
      look: look,
      flipX: jsonBool(json["flipX"], false),
      flipY: jsonBool(json["fy"], false),
      fill: PaintSpec.fromJson(json["fill"], const Color(0xFF000000)),
      adjust: jsonSpec(
          json["adjust"], ImageAdjustment.fromJson, const ImageAdjustment()),
      texture:
          jsonSpec(json["texture"], TextureSpec.fromJson, const TextureSpec()),
      effects: [
        // Each effect can draw the layer again, so a received file is capped.
        if (json["fx"] case List raw)
          for (var f in raw.take(16))
            if (f is Map<String, dynamic>) LayerEffect.fromJson(f)
      ],
      strokes: strokesFromJson(json["strokes"]),
      cue: VectorCue.values.where((c) => c.name == json["cue"]).firstOrNull ??
          VectorCue.together,
      cueGap: jsonDouble(json["gap"], 0).round(),
      cueLength: json["len"] is num ? (json["len"] as num).round() : null,
      mask: jsonSpec(json["mask"], ImageMask.fromJson, const ImageMask()),
      basePlace: switch (json["place"]) {
        [num l, num t, num w, num h] =>
          Rect.fromLTWH(l.toDouble(), t.toDouble(), w.toDouble(), h.toDouble()),
        _ => null,
      },
    );
  }
}

/// layerRect is where [place], in layer units, is in a frame drawn at
/// [inner], before any turn; layerPlace is the reverse.
Rect layerRect(Rect inner, Rect place) => Rect.fromLTWH(
      inner.left + place.left / layerUnits * inner.width,
      inner.top + place.top / layerUnits * inner.height,
      place.width / layerUnits * inner.width,
      place.height / layerUnits * inner.height,
    );

Rect layerPlace(Rect inner, Rect rect) {
  var w = inner.width == 0 ? 1 : inner.width;
  var h = inner.height == 0 ? 1 : inner.height;
  return Rect.fromLTWH(
    (rect.left - inner.left) / w * layerUnits,
    (rect.top - inner.top) / h * layerUnits,
    rect.width / w * layerUnits,
    rect.height / h * layerUnits,
  );
}

/// placeFor is where a [picture]-shaped picture added to a frame at
/// [inner] goes: the middle two thirds, whole, covering little.
Rect placeFor(Rect inner, Size picture) {
  var room = Size(inner.width * 2 / 3, inner.height * 2 / 3);
  var aspect = picture.height <= 0 ? 1.0 : picture.width / picture.height;
  var w = room.width, h = w / aspect;
  if (h > room.height) {
    h = room.height;
    w = h * aspect;
  }
  return layerPlace(
      inner, Rect.fromCenter(center: inner.center, width: w, height: h));
}

/// LayerSpace maps between the canvas and a picture layer of an element:
/// the element's turn about its own centre, then the layer's about its own.
class LayerSpace {
  final Rect inner;
  final Rect rect;
  final Offset _elementCentre;

  /// _elementFrame is the element's turn and slant (see BoxFrame), so a
  /// press on a slanted picture lands where it is drawn.
  final BoxFrame _elementFrame;
  final double _layerTurn;

  LayerSpace(ImageElement e, ImageLayer layer)
      : inner = e.box.inner(e.bounds),
        rect = layerRect(e.box.inner(e.bounds), layer.place),
        _elementCentre = e.bounds.center,
        _elementFrame = BoxFrame(e.rotation, e.base.skewX, e.base.skewY),
        _layerTurn = layer.turn * math.pi / 180;

  static Offset _turned(Offset p, Offset about, double a) {
    var d = p - about;
    var c = math.cos(a), s = math.sin(a);
    return about + Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c);
  }

  /// toFrame and fromFrame map canvas points to and from the element's
  /// unturned space ([inner], [rect]); toLayer and fromLayer the layer's.
  Offset toFrame(Offset canvasPoint) =>
      _elementCentre + _elementFrame.invert(canvasPoint - _elementCentre);

  Offset fromFrame(Offset p) =>
      _elementCentre + _elementFrame.apply(p - _elementCentre);

  Offset toLayer(Offset canvasPoint) =>
      _turned(toFrame(canvasPoint), rect.center, -_layerTurn);

  Offset fromLayer(Offset p) => fromFrame(_turned(p, rect.center, _layerTurn));

  /// corners are its four corners on the canvas, clockwise from top-left.
  List<Offset> get corners => [
        rect.topLeft,
        rect.topRight,
        rect.bottomRight,
        rect.bottomLeft
      ].map(fromLayer).toList();

  bool contains(Offset canvasPoint) => rect.contains(toLayer(canvasPoint));

  /// resized is the layer's frame rectangle with [handle] (see boxHandles)
  /// dragged to [canvasPoint], the opposite side staying put on the canvas
  /// though the layer is turned: resized in the layer's space, then its new
  /// middle carried to where the old turn puts it.
  Rect resized(
      Offset canvasPoint, int handle, Rect Function(Rect, int, Offset) resize) {
    var local = toLayer(canvasPoint);
    var next = resize(rect, handle, local);
    var centre = _turned(next.center, rect.center, _layerTurn);
    return Rect.fromCenter(
        center: centre, width: next.width, height: next.height);
  }

  /// turnTo is the turn, in degrees, pointing its top at [canvasPoint].
  double turnTo(Offset canvasPoint) {
    var p = toFrame(canvasPoint) - rect.center;
    return (math.atan2(p.dy, p.dx) + math.pi / 2) * 180 / math.pi;
  }
}

/// layerAt is [e]'s topmost shown picture layer under [canvasPoint], or
/// the base; layers [locked] marks are pressed through.
ImageLayer layerAt(ImageElement e, Offset canvasPoint,
    {bool Function(ImageLayer)? locked}) {
  for (var layer in e.stack.reversed) {
    if (!layer.visible || layer.kind != LayerKind.picture) continue;
    if (locked?.call(layer) ?? layer.locked) continue;
    if (LayerSpace(e, layer).contains(canvasPoint)) return layer;
  }
  return e.stack.firstWhere((l) => l.isBase);
}

/// layerName is what a layer is called in the layers list.
String layerName(ImageLayer layer, int index) {
  if (layer.name.isNotEmpty) return layer.name;
  return switch (layer.kind) {
    LayerKind.base => "Base picture",
    LayerKind.picture => "Picture ${index + 1}",
    LayerKind.fill => layer.fill.fades ? "Fade" : "Colour",
    LayerKind.adjustment => layer.adjust.kind.label,
    LayerKind.texture => layer.texture.kind.label,
    LayerKind.paint => "Paint",
  };
}

/// withPictureProportions is a picture layer's look with its place given
/// [picture]'s proportions in a frame at [inner], keeping width and middle.
ImageElement withPictureProportions(
    ImageElement look, Rect inner, Size picture) {
  if (picture.width <= 0 || picture.height <= 0) return look;
  var rect =
      layerRect(inner, Rect.fromLTWH(look.x, look.y, look.width, look.height));
  var height = rect.width * picture.height / picture.width;
  var place = layerPlace(inner,
      Rect.fromCenter(center: rect.center, width: rect.width, height: height));
  return look.withBase(
      x: place.left,
      y: place.top,
      width: place.width,
      height: place.height) as ImageElement;
}

// Arriving a layer at a time

/// layerNaturalTimes is each layer's (start, length) in its own frames
/// before fitting: starts by cue from the bottom's, lengths or [span].
List<(double, double)> layerNaturalTimes(List<ImageLayer> stack, int span) {
  var natural = <(double, double)>[];
  for (var (i, l) in stack.indexed) {
    var length = math.max(1, l.cueLength ?? span).toDouble();
    var start = 0.0;
    if (i > 0) {
      var (before, took) = natural[i - 1];
      start = switch (l.cue) {
        VectorCue.together => before,
        VectorCue.after => before + took,
        VectorCue.gap => math.max(before, before + took + l.cueGap),
      };
    }
    natural.add((start, length));
  }
  return natural;
}

/// layerNaturalLength is how many of their own frames [stack]'s layers
/// take, first start to last finish.
double layerNaturalLength(List<ImageLayer> stack, int span) {
  var times = layerNaturalTimes(stack, span);
  if (times.isEmpty) return span.toDouble();
  return times.map((t) => t.$1 + t.$2).reduce(math.max);
}

/// layerTimes is each layer's (start, length) in frames from the arrival's
/// start, the whole scaled to fit the arrival's [span].
List<(double, double)> layerTimes(List<ImageLayer> stack, int span) {
  var natural = layerNaturalTimes(stack, span);
  if (natural.isEmpty) return natural;
  var whole = layerNaturalLength(stack, span);
  var k = whole <= 0 ? 1.0 : span / whole;
  return [for (var (s, l) in natural) (s * k, l * k)];
}

/// imageArrivalSpan is where [e]'s arrival starts on the timeline and how
/// many frames it takes at [rate], or null with none. See own_motion.dart.
(int, int)? imageArrivalSpan(ImageElement e, int rate) =>
    ownSpan(e, MotionKind.arrive, rate);

/// withLayerTimingBaked is [e] with its layers' timing written out in
/// timeline frames as it plays (lengths set, gaps scaled by the arrival's
/// stretch), so an edit to one layer is in frames that can be seen.
ImageElement withLayerTimingBaked(ImageElement e, int rate) {
  var span = imageArrivalSpan(e, rate)?.$2;
  if (span == null) return e;
  var stack = e.stack;
  var whole = layerNaturalLength(stack, span);
  var k = whole <= 0 ? 1.0 : span / whole;
  return e.withLayers([
    for (var l in stack)
      l.copyWith(
          cueLength: math.max(1, ((l.cueLength ?? span) * k).round()),
          cueGap: (l.cueGap * k).round())
  ]);
}

/// withLayerSpanFitted is [e] with its arrival covering every layer's.
ImageElement withLayerSpanFitted(ImageElement e, int rate) {
  var arrival = imageArrivalSpan(e, rate);
  if (arrival == null) return e;
  var (at, span) = arrival;
  var whole = layerNaturalLength(e.stack, span).round();
  if (whole == span || whole < 1) return e;
  return withOwnSpan(e, MotionKind.arrive, at, at + whole, rate)
      as ImageElement;
}

/// withLayerStartAt is [e] with layer [index] (not the first) cued to start
/// [start] layer frames into the arrival, never before the layer under it.
ImageElement withLayerStartAt(ImageElement e, int index, int start, int span) {
  var stack = e.stack;
  if (index <= 0 || index >= stack.length) return e;
  var (before, took) = layerNaturalTimes(stack, span)[index - 1];
  var end = (before + took).round();
  var id = stack[index].id;
  if (start <= before.round()) {
    return e.withLayer(
        id, (l) => l.copyWith(cue: VectorCue.together, cueGap: 0));
  }
  if (start == end) {
    return e.withLayer(id, (l) => l.copyWith(cue: VectorCue.after, cueGap: 0));
  }
  return e.withLayer(
      id, (l) => l.copyWith(cue: VectorCue.gap, cueGap: start - end));
}

ImageElement withLayerLength(ImageElement e, int index, int length) {
  var stack = e.stack;
  if (index < 0 || index >= stack.length) return e;
  return e.withLayer(
      stack[index].id, (l) => l.copyWith(cueLength: math.max(1, length)));
}

/// layersSequenced is whether [stack] comes in a layer at a time.
bool layersSequenced(List<ImageLayer> stack) =>
    stack.skip(1).any((l) => l.cue != VectorCue.together) ||
    stack.any((l) => l.cueLength != null);

/// withLayersStaggered is [e] with its layers coming in bottom first, each
/// starting a third of [span] before the one under it finishes.
ImageElement withLayersStaggered(ImageElement e, int span) {
  var overlap = -(span / 3).round();
  return e.withLayers([
    for (var (i, l) in e.stack.indexed)
      i == 0
          ? l.copyWith(cue: VectorCue.together, cueGap: 0, clearCueLength: true)
          : l.copyWith(
              cue: VectorCue.gap, cueGap: overlap, clearCueLength: true)
  ]);
}

ImageElement withLayersTogether(ImageElement e) => e.withLayers([
      for (var l in e.stack)
        l.copyWith(cue: VectorCue.together, cueGap: 0, clearCueLength: true)
    ]);

// Looks and actions

/// lookKinds are a look's layer kinds: what is done to a picture.
const lookKinds = {LayerKind.adjustment, LayerKind.texture, LayerKind.fill};

/// isPictureCopy is whether [l] is a copy of [e]'s own picture laid over or
/// under it -- what an action keeps as "a copy of the picture", since a
/// glow, a double exposure or a split of the colours is drawn from one.
bool isPictureCopy(ImageElement e, ImageLayer l) =>
    l.kind == LayerKind.picture && e.hasImage && l.look?.assetId == e.assetId;

/// inLook is whether layer [l] of [e] is part of its look: what a look or
/// an action keeps and what wearing another takes off.
bool inLook(ImageElement e, ImageLayer l) =>
    lookKinds.contains(l.kind) || isPictureCopy(e, l);

/// pictureCopy is a layer drawing [e]'s own picture over the frame, as the
/// base draws it -- its crop, cut-out and colours -- moved by [shift]:
/// across and down by fractions of the base's place, then sized by the
/// last two.
ImageLayer pictureCopy(ImageElement e,
    {List<double> shift = const [0, 0, 1, 1]}) {
  var base = e.stack.firstWhere((l) => l.isBase, orElse: () => ImageLayer.base);
  var at = base.place;
  var place = Rect.fromLTWH(at.left + shift[0] * at.width,
      at.top + shift[1] * at.height, at.width * shift[2], at.height * shift[3]);
  var look = e.copyWith(
    layers: const [],
    animation: const ElementAnimation(),
    outline: const ImageOutline(),
    clearFrame: true,
    box: const BoxSpec(padding: 0),
  );
  return ImageLayer(
    id: newElementId(),
    kind: LayerKind.picture,
    name: "Copy of the picture",
    flipX: base.flipX,
    flipY: base.flipY,
    // Its own base, as a placed picture's: never the element's id, which
    // names the element's drawings in the caches.
    look: look.rebase(ElementBase(
        id: "",
        x: place.left,
        y: place.top,
        width: place.width,
        height: place.height,
        lockAspect: true)) as ImageElement,
  );
}

/// _copyKeys are a copy's own picture settings an action keeps: how it is
/// coloured, never which picture.
const _copyKeys = {"filter", "sat", "bri", "tint", "overlay", "blend"};

/// lookData is [e]'s look for other pictures: its [inLook] layers, each
/// under or over the base, and the base's blend, opacity, effects. [only]
/// keeps just the layers with those ids (the base's settings count as the
/// base's id); null keeps them all.
Map<String, dynamic> lookData(ImageElement e, {Set<String>? only}) {
  var stack = e.stack;
  var baseAt = stack.indexWhere((l) => l.isBase);
  var base = stack[baseAt];
  var withBase = only == null || only.contains(base.id);
  var at = base.place;
  return {
    "base": {
      if (withBase && base.blend != LayerBlend.normal) "blend": base.blend.name,
      if (withBase && base.opacity != 1) "op": base.opacity,
      if (withBase && base.effects.isNotEmpty)
        "fx": [for (var f in base.effects) f.toJson()],
    },
    "layers": [
      for (var (i, l) in stack.indexed)
        if (inLook(e, l) && (only == null || only.contains(l.id)))
          if (isPictureCopy(e, l))
            {
              ...{
                for (var entry in l.toJson().entries)
                  if (entry.key != "look" && entry.key != "id")
                    entry.key: entry.value
              },
              "copy": {
                for (var entry in l.look!.props().entries)
                  if (_copyKeys.contains(entry.key)) entry.key: entry.value
              },
              "shift": [
                if (at.width == 0 || at.height == 0) ...[
                  0,
                  0,
                  1,
                  1
                ] else ...[
                  (l.place.left - at.left) / at.width,
                  (l.place.top - at.top) / at.height,
                  l.place.width / at.width,
                  l.place.height / at.height,
                ]
              ],
              "under": i < baseAt,
            }
          else
            {...l.toJson(), "under": i < baseAt}
    ],
  };
}

/// lookLayers are the layers [data] (see lookData) puts on [e], fresh,
/// under the base and over it.
(List<ImageLayer>, List<ImageLayer>) lookLayers(
    ImageElement e, Map<String, dynamic> data) {
  var under = <ImageLayer>[], over = <ImageLayer>[];
  if (data["layers"] case List raw) {
    // Each layer is drawn again for every one over it: a received action
    // is kept to as many as a person would make.
    for (var item in raw.take(48)) {
      if (item is! Map<String, dynamic>) continue;
      ImageLayer? layer;
      if (item["copy"] is Map) {
        if (!e.hasImage) continue;
        layer = _copyFrom(e, item);
      } else {
        layer = ImageLayer.fromJson(item);
        if (layer != null && !lookKinds.contains(layer.kind)) layer = null;
      }
      if (layer == null) continue;
      // Fresh ids: a look worn by two pictures is two sets of layers.
      layer = layer.copyWith(id: newElementId());
      (item["under"] == true ? under : over).add(layer);
    }
  }
  return (under, over);
}

/// _copyFrom is the copy of [e]'s picture an action's [item] describes.
ImageLayer _copyFrom(ImageElement e, Map<String, dynamic> item) {
  var shift = switch (item["shift"]) {
    [num x, num y, num w, num h] when w > 0 && h > 0 => [
        x.toDouble().clamp(-4.0, 4.0),
        y.toDouble().clamp(-4.0, 4.0),
        w.toDouble().clamp(0.05, 8.0),
        h.toDouble().clamp(0.05, 8.0),
      ],
    _ => const [0.0, 0.0, 1.0, 1.0],
  };
  var copy = pictureCopy(e, shift: shift);
  // Its layer settings read as a colour layer's, which has the same ones.
  var settings =
      ImageLayer.fromJson({...item, "k": LayerKind.fill.name}) ?? copy;
  var colours = item["copy"] as Map;
  var look = copy.look!;
  var plain = ImageElement.fromJson(
      {for (var e in colours.entries) "${e.key}": e.value}, look.base);
  look = look.copyWith(
    filter: plain.filter,
    saturation: plain.saturation,
    brightness: plain.brightness,
    tint: plain.tint,
    overlay: plain.overlay,
    blend: plain.blend,
  );
  return ImageLayer(
    id: copy.id,
    kind: LayerKind.picture,
    name: settings.name.isEmpty ? copy.name : settings.name,
    visible: settings.visible,
    opacity: settings.opacity,
    blend: settings.blend,
    clip: settings.clip,
    flipX: item.containsKey("flipX") ? settings.flipX : copy.flipX,
    flipY: item.containsKey("fy") ? settings.flipY : copy.flipY,
    effects: settings.effects,
    look: look,
  );
}

/// withLookApplied is [e] wearing the look [data] (see lookData). Replacing,
/// it takes the place of [e]'s own: pictures and paint kept, [inLook]
/// layers swapped, the base's settings as the look has them. Not replacing,
/// the look is added to what is there, as an action is: its layers over
/// (and under) those already there, its effects after the base's own.
ImageElement withLookApplied(ImageElement e, Map<String, dynamic> data,
    {bool replace = true}) {
  var kept = [
    for (var l in e.stack)
      if (!replace || !inLook(e, l)) l
  ];
  var (under, over) = lookLayers(e, data);
  var base = data["base"] is Map<String, dynamic>
      ? data["base"] as Map<String, dynamic>
      : const <String, dynamic>{};
  var effects = [
    if (base["fx"] case List fx)
      for (var f in fx.take(16))
        if (f is Map<String, dynamic>) LayerEffect.fromJson(f)
  ];
  var stack = <ImageLayer>[];
  for (var l in kept) {
    if (l.isBase) {
      stack.addAll(under);
      stack.add(replace
          ? l.copyWith(
              blend: LayerBlend.fromName(jsonStr(base["blend"])),
              opacity: jsonDouble(base["op"], 1),
              effects: effects,
            )
          : l.copyWith(
              blend: base["blend"] == null
                  ? null
                  : LayerBlend.fromName(jsonStr(base["blend"])),
              opacity: base["op"] == null ? null : jsonDouble(base["op"], 1),
              effects: [...l.effects, ...effects].take(16).toList(),
            ));
    } else {
      stack.add(l);
    }
  }
  stack.addAll(over);
  return e.withLayers(stack);
}

/// lookSteps is how many steps [data] (see lookData) takes: its layers and
/// the base's effects.
int lookSteps(Map<String, dynamic> data) {
  var n = data["layers"] is List ? (data["layers"] as List).length : 0;
  if (data["base"] case {"fx": List fx}) n += fx.length;
  return n;
}

/// _maskInPlace is a [ImageLayer.framed] layer with its mask's marks
/// (fractions of the frame) moved back to where they were on the page.
ImageLayer _maskInPlace(
    ImageLayer l, Offset Function(Offset) at, double shorter) {
  if (!l.framed || l.mask.marks.isEmpty) return l;
  return l.copyWith(
      mask: l.mask.copyWith(marks: [
    for (var m in l.mask.marks)
      m.copyWith(
          points: [for (var p in m.points) at(p)], radius: m.radius * shorter),
  ]));
}

/// contentRectOf is the box round everything drawn in [e]'s layers, in a
/// frame at [inner]: the base picture, picture layers (turned) and paint
/// strokes to their brush's reach; not whole-frame layers or effects. Null
/// for nothing.
Rect? contentRectOf(ImageElement e, Rect inner) {
  Rect? all;
  void add(Rect r) => all = all == null ? r : all!.expandToInclude(r);
  var short = math.min(inner.width, inner.height);
  for (var l in e.stack) {
    switch (l.kind) {
      case LayerKind.base:
        // As far as its warp bends it.
        if (e.hasImage) add(warpBounds(e.warp, layerRect(inner, l.place)));
      case LayerKind.picture:
        if (!(l.look?.hasImage ?? false)) continue;
        var place = layerRect(inner, l.place);
        var r = warpBounds(l.look!.warp, place);
        if (l.turn == 0) {
          add(r);
          continue;
        }
        // Turned about its place's middle, as it is drawn.
        var t = l.turn * math.pi / 180;
        var c = place.center;
        Offset turned(Offset p) {
          var d = p - c;
          return c +
              Offset(d.dx * math.cos(t) - d.dy * math.sin(t),
                  d.dx * math.sin(t) + d.dy * math.cos(t));
        }

        var corners = [
          turned(r.topLeft),
          turned(r.topRight),
          turned(r.bottomLeft),
          turned(r.bottomRight)
        ];
        add(Rect.fromLTRB(
            corners.map((p) => p.dx).reduce(math.min),
            corners.map((p) => p.dy).reduce(math.min),
            corners.map((p) => p.dx).reduce(math.max),
            corners.map((p) => p.dy).reduce(math.max)));
      case LayerKind.paint:
        for (var s in l.strokes) {
          // Rubbing out and retouching lay nothing down of their own.
          if (s.kind != StrokeKind.paint || s.points.isEmpty) continue;
          var reach = s.radius * short;
          for (var p in s.points) {
            add(Rect.fromCircle(
                center: Offset(inner.left + p.dx * inner.width,
                    inner.top + p.dy * inner.height),
                radius: reach));
          }
        }
      case LayerKind.fill || LayerKind.texture || LayerKind.adjustment:
        break;
    }
  }
  return all;
}

/// keptInPlace is [now] ([was] with its frame moved or resized) with every
/// placed layer and paint stroke kept where it was on the page. A pure move
/// carries the layers; an unlayered picture fills its frame.
ImageElement keptInPlace(ImageElement was, ImageElement now) {
  if (!now.layered) return now;
  var a = was.box.inner(was.bounds), b = now.box.inner(now.bounds);
  // Compared within rounding: a moved frame's size, worked out from its
  // edges, comes out a hair different and must not count as a resize.
  bool same(double p, double q) => (p - q).abs() <= 1e-6 * math.max(1, p.abs());
  if (same(a.width, b.width) && same(a.height, b.height) ||
      a.isEmpty ||
      b.isEmpty) {
    return now;
  }
  Rect to(Rect place) => layerPlace(b, layerRect(a, place));
  Offset at(Offset f) => Offset((a.left + f.dx * a.width - b.left) / b.width,
      (a.top + f.dy * a.height - b.top) / b.height);
  var shorter = math.min(a.width, a.height) / math.min(b.width, b.height);
  return now.withLayers([
    for (var l in now.stack)
      switch (l.kind) {
        LayerKind.picture => l.placed(to(l.place), turn: l.turn),
        LayerKind.base => l.copyWith(basePlace: to(l.place)),
        LayerKind.paint => _maskInPlace(
            l.copyWith(strokes: [
              for (var s in l.strokes)
                s.copyWith(
                    points: [for (var p in s.points) at(p)],
                    radius: s.radius * shorter,
                    // A clone's source is a distance in frame fractions.
                    source: Offset(s.source.dx * a.width / b.width,
                        s.source.dy * a.height / b.height)),
            ]),
            at,
            shorter),
        _ => _maskInPlace(l, at, shorter),
      },
  ]);
}
