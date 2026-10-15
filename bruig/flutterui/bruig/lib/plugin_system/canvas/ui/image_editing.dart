import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';

// image_editing.dart is the editing of a picture made of layers: the tools,
// and the changes to the stack they make. The stack's own model is in
// model/elements/image_layers.dart; this is what a press or a button does
// to it.

/// ImageTool is what a press on a picture being edited does.
enum ImageTool {
  /// move picks the layer under the press and moves, resizes or turns it --
  /// or, on the base picture, moves it about inside its frame.
  move("Move", "V"),

  /// subject finds the subject of the picked layer's picture: a click picks
  /// the one there, Shift adds it, Option takes it away.
  subject("Select subject", "W"),

  /// quick grows what is brushed over out to the edges near it: a stroke
  /// over a shirt takes in the shirt.
  quick("Quick select", "Q"),

  /// refine is brushed along a soft edge -- hair, fur -- and works out how
  /// much of each pixel there is the subject from its colours.
  refine("Refine edge", "R"),

  /// brush paints the mask: away, or back.
  brush("Mask brush", "B"),

  /// lasso takes away, or puts back, whatever a line drawn round it holds.
  lasso("Lasso", "L"),

  /// fade fades the picture out across a line dragged over it, or away from
  /// a middle.
  fade("Gradient", "G"),

  /// paint lays colour on a paint layer -- making one, where the layer
  /// picked is not one -- and erase takes it off.
  paint("Paint brush", "P"),
  erase("Eraser", "E"),

  /// clone copies the picture from where Option-click chose; heal fills a
  /// spot with what is round it; dodge lightens (Option: burn darkens); blur
  /// softens. On the picture picked.
  clone("Clone", "S"),
  heal("Spot heal", "J"),
  dodge("Dodge and burn", "O"),
  soften("Blur brush", "U"),
  sharpen("Sharpen", "Y"),
  smudge("Smudge", "M");

  final String label;

  /// key is the letter that takes it up.
  final String key;
  const ImageTool(this.label, this.key);

  /// masks is whether the tool works on the picked layer's mask.
  bool get masks =>
      this == subject ||
      this == quick ||
      this == refine ||
      this == brush ||
      this == lasso ||
      this == fade;

  /// paints is whether the tool lays strokes: paint on a paint layer, or
  /// retouching on a picture.
  bool get paints => !masks && this != move;

  /// retouches is whether the tool works on a picture rather than a paint
  /// layer.
  bool get retouches =>
      this == clone ||
      this == heal ||
      this == dodge ||
      this == soften ||
      this == sharpen ||
      this == smudge;
}

/// MaskView is how a mask being worked on is shown on the canvas.
enum MaskView {
  /// result is the picture as it will be.
  result("As it will look", "Picture"),

  /// overlay shows what is hidden in red over the whole picture, so what is
  /// about to be cut can be seen against what it is cut from.
  overlay("Red over hidden", "Red overlay"),

  /// grey is the mask alone: white kept, black hidden.
  grey("Black and white", "Black and white");

  final String label;

  /// short is its name side by side with the others.
  final String short;
  const MaskView(this.label, this.short);
}

/// withLayerAdded is [e] with [layer] put in just above the layer [above],
/// or at the top where there is no such layer.
ImageElement withLayerAdded(ImageElement e, ImageLayer layer, {String? above}) {
  var stack = [...e.stack];
  var at = above == null ? -1 : stack.indexWhere((l) => l.id == above);
  stack.insert(at < 0 ? stack.length : at + 1, layer);
  return e.withLayers(_clipFixed(stack));
}

/// withoutLayer is [e] without the layer [id]. The base layer cannot go: it
/// is the element's own picture -- taking that out is "Take the picture
/// out", which leaves the layer and empties it.
ImageElement withoutLayer(ImageElement e, String id) {
  if (id == baseLayerId) return e;
  return e.withLayers(_clipFixed([
    for (var l in e.stack)
      if (l.id != id) l
  ]));
}

/// withLayerCopied is [e] with a copy of the layer [id] just above it, and
/// the copy's id. A picture layer's copy is nudged so it is seen to be two.
(ImageElement, String)? withLayerCopied(ImageElement e, String id) {
  var layer = e.layerById(id);
  if (layer == null || layer.isBase) return null;
  var copy = ImageLayer.fromJson(layer.toJson())!;
  copy = copy.copyWith(id: _freshId(e));
  if (copy.kind == LayerKind.picture) {
    copy = copy.placed(copy.place.translate(20, 20), turn: copy.turn);
  }
  return (withLayerAdded(e, copy, above: id), copy.id);
}

String _freshId(ImageElement e) {
  var n = e.stack.length;
  while (e.layerById("l$n") != null) {
    n++;
  }
  return "l$n";
}

/// withLayerMoved is [e] with the layer at [from] moved to [to], both
/// counted back to front.
ImageElement withLayerMoved(ImageElement e, int from, int to) {
  var stack = [...e.stack];
  if (from < 0 || from >= stack.length) return e;
  to = to.clamp(0, stack.length - 1);
  if (from == to) return e;
  var layer = stack.removeAt(from);
  stack.insert(to, layer);
  return e.withLayers(_clipFixed(stack));
}

/// _clipFixed takes the clip off whatever layer is now at the bottom, which
/// has nothing under it to be clipped to and would otherwise show a clip it
/// does not have.
List<ImageLayer> _clipFixed(List<ImageLayer> stack) {
  if (stack.isEmpty || !stack.first.clip) return stack;
  return [stack.first.copyWith(clip: false), ...stack.skip(1)];
}

/// _seen is where [layer] shows in a frame [inner]: its rectangle, or the
/// box round it once it is turned, which is what an eye lines up.
Rect _seen(ImageLayer layer, Rect inner) {
  var r = layerRect(inner, layer.place);
  if (layer.turn == 0) return r;
  var a = layer.turn * math.pi / 180;
  var c = math.cos(a).abs(), s = math.sin(a).abs();
  return Rect.fromCenter(
      center: r.center,
      width: r.width * c + r.height * s,
      height: r.width * s + r.height * c);
}

/// _shifted is [e] with the layer [id] moved by [by], in the frame's units.
ImageElement _shifted(ImageElement e, Rect inner, String id, Offset by) =>
    e.withLayer(
        id,
        (l) => l.placed(layerPlace(inner, layerRect(inner, l.place).shift(by)),
            turn: l.turn));

/// withLayersAligned lines the layers [ids] of [e] up on one edge or middle,
/// against the box they make between them -- as CanvasController
/// .alignSelected does elements, so the outermost stay put.
ImageElement withLayersAligned(
    ImageElement e, List<String> ids, CanvasAlign align) {
  var inner = e.box.inner(e.bounds);
  var layers = [
    for (var id in ids)
      if (e.layerById(id) case var l?) l
  ];
  if (layers.length < 2 || inner.isEmpty) return e;
  var box =
      layers.map((l) => _seen(l, inner)).reduce((a, b) => a.expandToInclude(b));
  var next = e;
  for (var l in layers) {
    var at = _seen(l, inner);
    var by = Offset(
      switch (align) {
        CanvasAlign.left => box.left - at.left,
        CanvasAlign.centreX => box.center.dx - at.center.dx,
        CanvasAlign.right => box.right - at.right,
        _ => 0.0,
      },
      switch (align) {
        CanvasAlign.top => box.top - at.top,
        CanvasAlign.middleY => box.center.dy - at.center.dy,
        CanvasAlign.bottom => box.bottom - at.bottom,
        _ => 0.0,
      },
    );
    if (by != Offset.zero) next = _shifted(next, inner, l.id, by);
  }
  return next;
}

/// withLayersSpread puts an even gap between the layers [ids] of [e], the
/// two on the ends staying where they are -- even gaps, not even middles,
/// as for elements.
ImageElement withLayersSpread(ImageElement e, List<String> ids, bool across) {
  var inner = e.box.inner(e.bounds);
  var layers = [
    for (var id in ids)
      if (e.layerById(id) case var l?) l
  ];
  if (layers.length < 3 || inner.isEmpty) return e;
  double start(Rect r) => across ? r.left : r.top;
  double size(Rect r) => across ? r.width : r.height;
  layers
      .sort((a, b) => start(_seen(a, inner)).compareTo(start(_seen(b, inner))));
  var first = _seen(layers.first, inner), last = _seen(layers.last, inner);
  var span = (across ? last.right : last.bottom) - start(first);
  var filled = layers.fold<double>(0, (sum, l) => sum + size(_seen(l, inner)));
  var gap = (span - filled) / (layers.length - 1);
  var next = e;
  var at = start(first);
  for (var l in layers) {
    var r = _seen(l, inner);
    var shift = at - start(r);
    if (shift != 0) {
      next = _shifted(
          next, inner, l.id, across ? Offset(shift, 0) : Offset(0, shift));
    }
    at += size(r) + gap;
  }
  return next;
}
