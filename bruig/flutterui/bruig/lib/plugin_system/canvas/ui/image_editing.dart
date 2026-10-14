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
  result("As it will look"),

  /// overlay shows what is hidden in red over the whole picture, so what is
  /// about to be cut can be seen against what it is cut from.
  overlay("Red over hidden"),

  /// grey is the mask alone: white kept, black hidden.
  grey("Black and white");

  final String label;
  const MaskView(this.label);
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
