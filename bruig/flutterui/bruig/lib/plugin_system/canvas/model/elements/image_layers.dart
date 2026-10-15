import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_adjustment.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_effects.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_strokes.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_mask.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart'
    show VectorCue;
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';

// image_layers.dart is a picture made of several: the layers an Image
// element is composited from, and the arithmetic of where each one sits.
//
// The element's own fields are still its picture. They are the *base* layer,
// which fills the frame exactly as a picture always has, so a background
// picture, a video's look and every canvas saved before there were layers are
// a stack of one and draw as they always did. Layers are what is added round
// it: more pictures, placed and turned within the frame, and flat or fading
// colour, each with its own blend, opacity and clipping.

/// layerUnits is how many units a picture layer's place is measured in,
/// across and down the frame.
///
/// Fractions of the frame rather than canvas units, so resizing the element
/// scales the whole composite with it -- the cannon stays under the players
/// whatever size the poster is drawn at. A thousand rather than one because
/// the place is kept in an ImageElement's own box, and everything that works
/// on that box (cropping trims it, and refuses to go below eight units) was
/// written for numbers of about that size.
const double layerUnits = 1000;

/// baseLayerId is the id the base layer always has. There is only ever one.
const String baseLayerId = "base";

/// LayerKind is what a layer draws.
enum LayerKind {
  /// base is the element's own picture, filling the frame.
  base("Picture"),

  /// picture is another picture, placed anywhere in the frame.
  picture("Picture"),

  /// fill is a colour or a fade over the whole frame.
  fill("Colour"),

  /// adjustment changes the layers under it: a grade, a curve, a colour
  /// kept. See image_adjustment.dart.
  adjustment("Adjustment"),

  /// texture draws grain, paper, grunge, a vignette over the frame. See
  /// image_effects.dart.
  texture("Texture"),

  /// paint is brushwork laid over the layers under it. See image_strokes.dart.
  paint("Paint");

  final String label;
  const LayerKind(this.label);

  static LayerKind fromName(String? name) =>
      values.firstWhere((k) => k.name == name, orElse: () => LayerKind.picture);
}

/// LayerBlend is how a layer is laid over the layers below it.
///
/// Every mode an image editor offers, in the order they are usually listed
/// in: normal, the darkening ones, the lightening ones, the contrast ones,
/// the comparing ones and the colour ones. Our own names, as with every other
/// enum a document saves.
enum LayerBlend {
  normal("Normal", BlendMode.srcOver),
  darken("Darken", BlendMode.darken),
  multiply("Multiply", BlendMode.multiply),
  colorBurn("Colour burn", BlendMode.colorBurn),
  lighten("Lighten", BlendMode.lighten),
  screen("Screen", BlendMode.screen),
  colorDodge("Colour dodge", BlendMode.colorDodge),
  add("Add", BlendMode.plus),
  overlay("Overlay", BlendMode.overlay),
  softLight("Soft light", BlendMode.softLight),
  hardLight("Hard light", BlendMode.hardLight),
  difference("Difference", BlendMode.difference),
  exclusion("Exclusion", BlendMode.exclusion),
  hue("Hue", BlendMode.hue),
  saturation("Saturation", BlendMode.saturation),
  colour("Colour", BlendMode.color),
  luminosity("Luminosity", BlendMode.luminosity);

  final String label;
  final BlendMode flutter;
  const LayerBlend(this.label, this.flutter);

  static LayerBlend fromName(String? name) =>
      values.firstWhere((b) => b.name == name, orElse: () => LayerBlend.normal);
}

/// ImageLayer is one layer of a composited picture.
class ImageLayer {
  final String id;
  final LayerKind kind;

  /// name is what the playlist calls it. Empty is named for what is in it.
  final String name;

  final bool visible;
  final double opacity;
  final LayerBlend blend;

  /// clip draws the layer only where the layer below it has something -- a
  /// texture laid over one player and not the sky round him. A run of clipped
  /// layers all clip to the first unclipped layer under them, as they do in
  /// every editor that has them.
  final bool clip;

  /// look is a picture layer's picture, with everything a picture can have
  /// done to it, and its place: the look's box is where it sits in the frame,
  /// in [layerUnits] across and down, and its rotation is its turn within
  /// the frame. Null for any other kind.
  ///
  /// An ImageElement rather than a copy of its fields, so a layer has every
  /// setting the base picture has, the same panel sets them, and the same
  /// painter draws them.
  final ImageElement? look;

  /// flipX and flipY mirror a picture layer within its place.
  final bool flipX;
  final bool flipY;

  /// fill is what a fill layer paints the frame with.
  final PaintSpec fill;

  /// adjust is what an adjustment layer does.
  final ImageAdjustment adjust;

  /// texture is what a texture layer draws.
  final TextureSpec texture;

  /// effects are done to the layer as it is drawn: shadows, glows, blurs.
  final List<LayerEffect> effects;

  /// strokes are a paint layer's brushwork, in order.
  final List<StrokeMark> strokes;

  /// cue is when the layer comes in, against the one under it, while the
  /// picture arrives: with it, after it, or after a gap of [cueGap] frames
  /// (less than nought overlapping it). [cueLength] is how many frames it
  /// takes, or null for as long as the picture's arrival. See layerTimes.
  final VectorCue cue;
  final int cueGap;
  final int? cueLength;

  /// mask is where over the frame an adjustment, texture, colour or paint
  /// layer shows -- marks in fractions of the frame, as a picture's mask's
  /// are of the picture. A picture layer's mask is its look's.
  final ImageMask mask;

  /// framed is whether this layer is masked over the frame rather than over
  /// a picture of its own.
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
  });

  /// base is the base layer as it is before anything has been done to it.
  static const ImageLayer base =
      ImageLayer(id: baseLayerId, kind: LayerKind.base);

  bool get isBase => kind == LayerKind.base;

  /// plain is whether this is the base layer with nothing done to it, which
  /// is the same as there being no layers at all.
  bool get plain =>
      isBase &&
      name.isEmpty &&
      cue == VectorCue.together &&
      cueGap == 0 &&
      cueLength == null &&
      visible &&
      opacity == 1 &&
      blend == LayerBlend.normal &&
      !clip &&
      effects.isEmpty;

  /// picture is a new picture layer showing [assetId] at [place].
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

  /// adjusting is a new adjustment layer of [kind].
  factory ImageLayer.adjusting(AdjustKind kind) => ImageLayer(
      id: newElementId(),
      kind: LayerKind.adjustment,
      adjust: ImageAdjustment(kind: kind));

  /// texturing is a new texture layer of [kind], blended as that texture
  /// usually is.
  factory ImageLayer.texturing(TextureKind kind) => ImageLayer(
      id: newElementId(),
      kind: LayerKind.texture,
      blend: LayerBlend.fromName(kind.blend),
      texture: TextureSpec(kind: kind));

  /// painting is a new, empty paint layer.
  factory ImageLayer.painting() =>
      ImageLayer(id: newElementId(), kind: LayerKind.paint);

  /// solid is a new fill layer.
  factory ImageLayer.solid(PaintSpec fill) =>
      ImageLayer(id: newElementId(), kind: LayerKind.fill, fill: fill);

  /// place is where a picture layer sits, in layer units.
  Rect get place => look == null
      ? const Rect.fromLTWH(0, 0, layerUnits, layerUnits)
      : Rect.fromLTWH(look!.x, look!.y, look!.width, look!.height);

  /// turn is a picture layer's rotation within the frame, in degrees.
  double get turn => look?.rotation ?? 0;

  ImageLayer copyWith({
    String? id,
    String? name,
    bool? visible,
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
  }) =>
      ImageLayer(
        id: id ?? this.id,
        kind: kind,
        name: name ?? this.name,
        visible: visible ?? this.visible,
        opacity: (opacity ?? this.opacity).clamp(0.0, 1.0),
        blend: blend ?? this.blend,
        clip: clip ?? this.clip,
        look: look ?? this.look,
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
        mask: mask ?? this.mask,
      );

  /// placed is this picture layer moved to [place] and turned to [turn].
  ImageLayer placed(Rect place, {double? turn}) => look == null
      ? this
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
        if (opacity != 1) "op": opacity,
        if (blend != LayerBlend.normal) "blend": blend.name,
        if (clip) "clip": true,
        if (look case var l?) "look": l.toJson(),
        if (flipX) "fx": true,
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
      };

  static ImageLayer? fromJson(Map<String, dynamic> json) {
    var kind = LayerKind.fromName(json["k"] as String?);
    ImageElement? look;
    if (kind == LayerKind.picture) {
      if (json["look"] is! Map<String, dynamic>) return null;
      var raw = json["look"] as Map<String, dynamic>;
      // A layer's look is written the way an element is, base and all, so
      // it is read the way one is.
      look = ImageElement.fromJson(raw, ElementBase.fromJson(raw, "Picture"));
    }
    return ImageLayer(
      id: kind == LayerKind.base
          ? baseLayerId
          : jsonString(json["id"], newElementId()),
      kind: kind,
      name: jsonString(json["name"], ""),
      visible: !jsonBool(json["hide"], false),
      opacity: jsonDouble(json["op"], 1).clamp(0.0, 1.0),
      blend: LayerBlend.fromName(json["blend"] as String?),
      clip: jsonBool(json["clip"], false),
      look: look,
      flipX: jsonBool(json["fx"], false),
      flipY: jsonBool(json["fy"], false),
      fill: PaintSpec.fromJson(json["fill"], const Color(0xFF000000)),
      adjust: jsonSpec(
          json["adjust"], ImageAdjustment.fromJson, const ImageAdjustment()),
      texture:
          jsonSpec(json["texture"], TextureSpec.fromJson, const TextureSpec()),
      effects: [
        if (json["fx"] case List raw)
          for (var f in raw)
            if (f is Map<String, dynamic>) LayerEffect.fromJson(f)
      ],
      strokes: strokesFromJson(json["strokes"]),
      cue: VectorCue.values.where((c) => c.name == json["cue"]).firstOrNull ??
          VectorCue.together,
      cueGap: jsonDouble(json["gap"], 0).round(),
      cueLength: json["len"] is num ? (json["len"] as num).round() : null,
      mask: jsonSpec(json["mask"], ImageMask.fromJson, const ImageMask()),
    );
  }
}

/// layerRect is where [place], in layer units, is in a frame drawn at
/// [inner], before any turn.
Rect layerRect(Rect inner, Rect place) => Rect.fromLTWH(
      inner.left + place.left / layerUnits * inner.width,
      inner.top + place.top / layerUnits * inner.height,
      place.width / layerUnits * inner.width,
      place.height / layerUnits * inner.height,
    );

/// layerPlace is the other way: where [rect], drawn in a frame at [inner],
/// is in layer units.
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

/// placeFor is where a picture of [picture]'s proportions goes when it is
/// added to a frame drawn at [inner]: fitted inside the frame's middle, at
/// two thirds of it, so it arrives whole and visibly on top of what is
/// there rather than covering it.
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
  final double _elementTurn;
  final double _layerTurn;

  LayerSpace(ImageElement e, ImageLayer layer)
      : inner = e.box.inner(e.bounds),
        rect = layerRect(e.box.inner(e.bounds), layer.place),
        _elementCentre = e.bounds.center,
        _elementTurn = e.rotation * math.pi / 180,
        _layerTurn = layer.turn * math.pi / 180;

  static Offset _turned(Offset p, Offset about, double a) {
    var d = p - about;
    var c = math.cos(a), s = math.sin(a);
    return about + Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c);
  }

  /// toFrame is a canvas point in the element's own unturned space -- where
  /// [inner] and [rect] are.
  Offset toFrame(Offset canvasPoint) =>
      _turned(canvasPoint, _elementCentre, -_elementTurn);

  /// fromFrame is a point of the element's unturned space on the canvas.
  Offset fromFrame(Offset p) => _turned(p, _elementCentre, _elementTurn);

  /// toLayer is a canvas point in the layer's own unturned space.
  Offset toLayer(Offset canvasPoint) =>
      _turned(toFrame(canvasPoint), rect.center, -_layerTurn);

  /// fromLayer is a point of the layer's unturned space on the canvas.
  Offset fromLayer(Offset p) => fromFrame(_turned(p, rect.center, _layerTurn));

  /// corners are the layer's four corners on the canvas, top-left first and
  /// on round.
  List<Offset> get corners => [
        rect.topLeft,
        rect.topRight,
        rect.bottomRight,
        rect.bottomLeft
      ].map(fromLayer).toList();

  bool contains(Offset canvasPoint) => rect.contains(toLayer(canvasPoint));

  /// resized is the layer's frame rectangle with handle [handle] (see
  /// boxHandles) dragged to [canvasPoint], the opposite side staying where it
  /// is on the canvas although the layer is turned.
  ///
  /// The new box is worked out in the layer's own space, where it is a plain
  /// rectangle; but that space turns about the old box's middle, and the new
  /// box will turn about its own. So the new middle is carried out to where
  /// the old turn puts it, and the box is set round that.
  Rect resized(
      Offset canvasPoint, int handle, Rect Function(Rect, int, Offset) resize) {
    var local = toLayer(canvasPoint);
    var next = resize(rect, handle, local);
    var centre = _turned(next.center, rect.center, _layerTurn);
    return Rect.fromCenter(
        center: centre, width: next.width, height: next.height);
  }

  /// turnTo is the layer's turn, in degrees, that points its top at
  /// [canvasPoint].
  double turnTo(Offset canvasPoint) {
    var p = toFrame(canvasPoint) - rect.center;
    return (math.atan2(p.dy, p.dx) + math.pi / 2) * 180 / math.pi;
  }
}

/// layerAt is the topmost shown picture layer of [e] under [canvasPoint], or
/// the base layer where there is none.
ImageLayer layerAt(ImageElement e, Offset canvasPoint) {
  for (var layer in e.stack.reversed) {
    if (!layer.visible || layer.kind != LayerKind.picture) continue;
    if (LayerSpace(e, layer).contains(canvasPoint)) return layer;
  }
  return e.stack.firstWhere((l) => l.isBase);
}

/// layerName is what a layer is called in the playlist.
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
/// [picture]'s proportions, in a frame drawn at [inner]: as wide as it was,
/// about the same middle, so the new picture is neither squashed nor moved.
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

// ---- arriving a layer at a time --------------------------------------------

/// layerNaturalTimes is when each layer of [stack] comes in, in its own
/// frames, before the arrival is fitted round them: the frame it starts on,
/// counted from the bottom layer's, and how many it takes -- its own length
/// or [span]. Back to front, each after the one under it as its cue says.
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

/// layerTimes is when each layer of [stack] comes in, in frames from the
/// arrival's start, the whole fitted into the arrival's [span] -- the last
/// to finish finishing as the arrival does, and stretching the arrival
/// stretching them all alike.
List<(double, double)> layerTimes(List<ImageLayer> stack, int span) {
  var natural = layerNaturalTimes(stack, span);
  if (natural.isEmpty) return natural;
  var whole = layerNaturalLength(stack, span);
  var k = whole <= 0 ? 1.0 : span / whole;
  return [for (var (s, l) in natural) (s * k, l * k)];
}

/// imageArrivalSpan is where [e]'s arrival starts on the timeline and how
/// many frames it takes, by its reveal keyframes, or null with none.
(int, int)? imageArrivalSpan(ImageElement e) {
  int? from, to;
  for (var key in e.track?.keys ?? const []) {
    if (!key.values.containsKey("reveal")) continue;
    from = from == null ? key.frame : math.min(from, key.frame);
    to = to == null ? key.frame : math.max(to, key.frame);
  }
  if (from == null || to == null || to <= from) return null;
  return (from, to - from);
}

/// withLayerTimingBaked is [e] with its layers' timing written out in the
/// timeline's frames as it plays now -- each length set, each gap scaled by
/// however the arrival has been stretched -- before one layer's timing is
/// changed, so the change is in frames that can be seen.
ImageElement withLayerTimingBaked(ImageElement e) {
  var span = imageArrivalSpan(e)?.$2;
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

/// withLayerSpanFitted is [e] with its arrival's last keyframe moved so the
/// arrival covers every layer's coming in, exactly.
ImageElement withLayerSpanFitted(ImageElement e) {
  var arrival = imageArrivalSpan(e);
  var track = e.track;
  if (arrival == null || track == null) return e;
  var (at, span) = arrival;
  var whole = layerNaturalLength(e.stack, span).round();
  if (whole == span || whole < 1) return e;
  var last = track.keyAt(at + span);
  if (last == null) return e;
  return e.withBase(
      track: track
          .withoutFrame(at + span)
          .withKey(last.copyWith(frame: at + whole))) as ImageElement;
}

/// withLayerStartAt is [e] with layer [index] -- not the first -- starting
/// [start] frames into the arrival, in the layers' own frames, said as the
/// cue that puts it there. Never before the layer under it starts.
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

/// withLayerLength is [e] with layer [index] taking [length] frames.
ImageElement withLayerLength(ImageElement e, int index, int length) {
  var stack = e.stack;
  if (index < 0 || index >= stack.length) return e;
  return e.withLayer(
      stack[index].id, (l) => l.copyWith(cueLength: math.max(1, length)));
}

/// layersSequenced is whether [stack] comes in a layer at a time rather
/// than as one picture.
bool layersSequenced(List<ImageLayer> stack) =>
    stack.skip(1).any((l) => l.cue != VectorCue.together) ||
    stack.any((l) => l.cueLength != null);

/// withLayersStaggered is [e] with its layers coming in one after another,
/// bottom first, each starting a third of the way before the one under it
/// has finished -- the drawing's Stagger, for layers.
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

/// withLayersTogether is [e] with every layer coming in at once again.
ImageElement withLayersTogether(ImageElement e) => e.withLayers([
      for (var l in e.stack)
        l.copyWith(cue: VectorCue.together, cueGap: 0, clearCueLength: true)
    ]);

// ---- looks -----------------------------------------------------------------

/// lookKinds are the layers a look is made of: what a picture is done to,
/// never what it is a picture of.
const lookKinds = {LayerKind.adjustment, LayerKind.texture, LayerKind.fill};

/// lookData is [e]'s look, to be kept and put on other pictures: its
/// adjustments, textures and colour layers -- each said to be under the base
/// picture or over it -- and the base picture's own blend, opacity and
/// effects. Nothing that is a picture: a look is the grade, not the photo.
Map<String, dynamic> lookData(ImageElement e) {
  var stack = e.stack;
  var baseAt = stack.indexWhere((l) => l.isBase);
  var base = stack[baseAt];
  return {
    "base": {
      if (base.blend != LayerBlend.normal) "blend": base.blend.name,
      if (base.opacity != 1) "op": base.opacity,
      if (base.effects.isNotEmpty)
        "fx": [for (var f in base.effects) f.toJson()],
    },
    "layers": [
      for (var (i, l) in stack.indexed)
        if (lookKinds.contains(l.kind)) {...l.toJson(), "under": i < baseAt}
    ],
  };
}

/// withLookApplied is [e] wearing the look [data] -- see lookData -- in place
/// of its own: its pictures and paint kept where they are, its adjustments,
/// textures and colour layers swapped for the look's.
ImageElement withLookApplied(ImageElement e, Map<String, dynamic> data) {
  var kept = [
    for (var l in e.stack)
      if (!lookKinds.contains(l.kind)) l
  ];
  var under = <ImageLayer>[], over = <ImageLayer>[];
  if (data["layers"] case List raw) {
    for (var item in raw) {
      if (item is! Map<String, dynamic>) continue;
      var layer = ImageLayer.fromJson(item);
      if (layer == null || !lookKinds.contains(layer.kind)) continue;
      // Fresh ids: a look worn by two pictures is two sets of layers.
      layer = layer.copyWith(id: newElementId());
      (item["under"] == true ? under : over).add(layer);
    }
  }
  var base = data["base"] is Map<String, dynamic>
      ? data["base"] as Map<String, dynamic>
      : const <String, dynamic>{};
  var stack = <ImageLayer>[];
  for (var l in kept) {
    if (l.isBase) {
      stack.addAll(under);
      stack.add(l.copyWith(
        blend: LayerBlend.fromName(base["blend"] as String?),
        opacity: jsonDouble(base["op"], 1),
        effects: [
          if (base["fx"] case List fx)
            for (var f in fx)
              if (f is Map<String, dynamic>) LayerEffect.fromJson(f)
        ],
      ));
    } else {
      stack.add(l);
    }
  }
  stack.addAll(over);
  return e.withLayers(stack);
}
