import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart'
    show elementFromJson;
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';

// responsive_layout.dart is one design laid out for several page shapes
// (4:5, 16:9...): each element has a place and size per shape (see
// ElementLayout). The shape on screen keeps its numbers in the element's
// live x, y, width and height, so everything reads an element as usual;
// changing shape swaps them with the stored ones, seeding a shape not yet
// worked on from the one left (see seedFor).

/// shapeKey names a shape in an element's layouts and a document's targets:
/// the ratio's name, and "custom" for any custom ratio, so typing a new
/// aspect keeps its layout. The width is the resolution, not the shape.
String shapeKey(CanvasSize size) => size.ratio.name;

String shapeLabel(String key) {
  for (var ratio in CanvasRatio.values) {
    if (ratio.name == key) return ratio.label;
  }
  return key;
}

/// shapeTag is a filename-safe short name for a shape ("16x9").
String shapeTag(String key) =>
    shapeShort(key).replaceAll(":", "x").replaceAll(" ", "");

/// shapeShort is a shape's name alone ("4:5", not "4:5 · Feed ad").
String shapeShort(String key) {
  var label = shapeLabel(key);
  var cut = label.indexOf(" ·");
  return cut > 0 ? label.substring(0, cut) : label;
}

/// canvasScale is how much a design made for one page is sized by for
/// another: the smaller of the two ratios. For one thing dropped on a page;
/// seeding a whole shape uses [seedFor], which measures the design.
double canvasScale(CanvasSize from, CanvasSize to) {
  if (from.width <= 0 || from.height <= 0) return 1;
  var by = math.min(to.width / from.width, to.height / from.height);
  return (by - 1).abs() < 0.001 ? 1 : by;
}

/// ShapeSeed is how a design is placed on a shape nobody has laid it out on.
class ShapeSeed {
  final double by;

  /// block is the design's bounds on the page left, minus what covers it.
  final Rect block;

  /// at is where the scaled block's top-left corner goes on the new page.
  final Offset at;

  final Size page;

  const ShapeSeed(
      {required this.by,
      required this.block,
      required this.at,
      required this.page});
}

/// coversPage is whether an element covers the page (a photograph behind
/// everything, a wash, a frame): such elements cover the new page too.
bool coversPage(CanvasElement element, CanvasSize page) {
  var slack = math.max(page.width, page.height) * 0.02;
  return element.x <= slack &&
      element.y <= slack &&
      element.x + element.width >= page.width - slack &&
      element.y + element.height >= page.height - slack;
}

/// seedFor works out how a scene's design moves onto another page shape.
/// What covers the page goes on covering it; the rest is one block, scaled
/// by how much the page changed and placed where it sat as a fraction of the
/// page. Measuring the design matters: by page ratio alone a 4:5 card taken
/// to 16:9 shrinks to 45% in a corner. Never enlarged; smaller still where
/// the block would not fit, and nudged back on where it would hang off.
ShapeSeed seedFor(
    List<CanvasElement> elements, CanvasSize from, CanvasSize to) {
  var page = Size(to.width.toDouble(), to.height.toDouble());

  Rect? block;
  for (var e in elements) {
    if (coversPage(e, from)) continue;
    var box = Rect.fromLTWH(e.x, e.y, e.width, e.height);
    block = block == null ? box : block.expandToInclude(box);
  }
  if (block == null || block.width <= 0 || block.height <= 0) {
    return ShapeSeed(by: 1, block: Rect.zero, at: Offset.zero, page: page);
  }

  // How much the page changed, capped at one, smaller still if the block
  // would not fit.
  var by = math.min(
    math.min(1.0, math.min(page.width / from.width, page.height / from.height)),
    math.min(page.width / block.width, page.height / block.height),
  );
  var sized = Size(block.width * by, block.height * by);

  // Where it sat, as a fraction of the page.
  var centre = Offset(
    block.center.dx / math.max(1, from.width) * page.width,
    block.center.dy / math.max(1, from.height) * page.height,
  );
  var at = Offset(centre.dx - sized.width / 2, centre.dy - sized.height / 2);

  // Nudged back on where it would hang off an edge.
  at = Offset(
    at.dx.clamp(math.min(0, page.width - sized.width),
        math.max(0, page.width - sized.width)),
    at.dy.clamp(math.min(0, page.height - sized.height),
        math.max(0, page.height - sized.height)),
  );
  return ShapeSeed(by: by, block: block, at: at, page: page);
}

/// seeded is [layout] placed on the new page by [seed].
ElementLayout seeded(ElementLayout layout, ShapeSeed seed, bool covers) {
  if (covers) {
    // The backdrop is the page, whatever shape the page is.
    return ElementLayout(
      x: 0,
      y: 0,
      width: seed.page.width,
      height: seed.page.height,
      visible: layout.visible,
      typeScale: layout.typeScale,
      text: layout.text,
      ownText: layout.ownText,
    );
  }
  return ElementLayout(
    x: seed.at.dx + (layout.x - seed.block.left) * seed.by,
    y: seed.at.dy + (layout.y - seed.block.top) * seed.by,
    width: math.max(1, layout.width * seed.by),
    height: math.max(1, layout.height * seed.by),
    visible: layout.visible,
    typeScale: layout.typeScale * seed.by,
    text: layout.text,
    ownText: layout.ownText,
  );
}

/// withLayoutsFor gives [element] a layout for every shape in [targets],
/// scaled from the one showing.
CanvasElement withLayoutsFor(
    CanvasElement element, CanvasSize size, List<String> targets,
    {required CanvasSize Function(String) sizeOf}) {
  if (targets.isEmpty) return element;
  var here = shapeKey(size);
  var layouts = {...element.base.layouts};
  var showing = ElementLayout.of(element.base);
  for (var key in targets) {
    if (key == here || layouts.containsKey(key)) continue;
    layouts[key] = showing.scaledBy(canvasScale(size, sizeOf(key)));
  }
  return element.withBase(layouts: layouts);
}

/// sizeForShape is the page a shape key names, at [like]'s width: the width
/// is the document's resolution, not its shape.
CanvasSize sizeForShape(String key, CanvasSize like) {
  for (var ratio in CanvasRatio.values) {
    if (ratio.name == key) return like.copyWith(ratio: ratio);
  }
  return like;
}

/// detachedHere gives [element] its own design on the shape on screen,
/// keeping the shared one aside (see ElementBase.shared).
CanvasElement detachedHere(CanvasElement element) => element.withBase(
      ownDesign: true,
      shared: element.base.shared ?? _snapshot(element),
    );

/// _snapshot is [element]'s design as JSON without its layouts and shared
/// design, which are kept once, on the element.
Map<String, dynamic> _snapshot(CanvasElement element) => element.toJson()
  ..remove("layouts")
  ..remove("shared");

/// sharedAgain puts [element] back on the shared design at once: otherwise
/// this shape's copy would become the shared design when the shape is left.
CanvasElement sharedAgain(CanvasElement element) {
  var shared = element.base.shared;
  if (shared == null) return element.withBase(ownDesign: false);
  // The shared copy is kept: another shape may still be detached, and
  // movedTo drops it once none is.
  return elementFromJson({...shared, "id": element.id}).withBase(
    layouts: element.base.layouts,
    ownDesign: false,
    shared: shared,
  );
}

/// showing is [element] wearing [layout]: its place, size, and design at
/// that layout's scale. The one place a layout is put on an element. The
/// design is scaled by the ratio of the two type scales, because its
/// measurements are at the left shape's scale (see ElementBase.typeScale).
CanvasElement showing(CanvasElement element, ElementLayout layout,
    {Map<String, dynamic>? shared}) {
  var base = element.base;

  // A design this shape keeps for itself is taken back whole, under the
  // element's own id. See ElementBase.ownDesign.
  if (layout.own case var own?) {
    element = elementFromJson({...own, "id": element.id}).withBase(
      layouts: base.layouts,
      ownDesign: true,
      shared: shared,
    );
  } else if (base.ownDesign && shared != null) {
    // A sharing shape takes the shared design back: while a detached shape
    // was on screen, [shared] was its only copy.
    element = elementFromJson({...shared, "id": element.id}).withBase(
      layouts: base.layouts,
      ownDesign: false,
      shared: shared,
    );
  }

  // A picture's framing and crop always belong to the shape.
  if (element is ImageElement) {
    element = element.copyWith(
      framing: layout.framing == null
          ? null
          : ImageFraming.fromJson(layout.framing!),
      crop: layout.crop == null ? null : ImageCrop.fromJson(layout.crop!),
    );
  }

  var was = element.base.typeScale;
  var moved = element.withBase(
    x: layout.x,
    y: layout.y,
    width: layout.width,
    height: layout.height,
    visible: layout.visible,
    typeScale: layout.typeScale,
    ownText: layout.ownText,
  );
  if (layout.typeScale == was || was <= 0) return moved;
  return moved.scaledBy(layout.typeScale / was).withBase(
        x: layout.x,
        y: layout.y,
        width: layout.width,
        height: layout.height,
        typeScale: layout.typeScale,
      );
}

/// movedTo is [element] showing its layout for [to], with what it showed
/// stored under [from]: place and size, measurement scale, and for words
/// which text this shape shows. A new shape is seeded from what was stored.
CanvasElement movedTo(CanvasElement element, String from, String to,
    {required ShapeSeed seed, required bool covers}) {
  var layouts = {...element.base.layouts};
  var words = element is TextElement ? element.text : null;
  var ownHere = element.base.ownText;
  var picture = element is ImageElement ? element : null;

  // What is on screen is stored under the shape being left: place and size,
  // the design if this shape keeps its own, and a picture's framing and crop.
  var detached = element.base.ownDesign;
  layouts[from] = ElementLayout.of(
    element.base,
    text: words,
    own: detached ? _snapshot(element) : null,
    framing: picture?.framing.toJson(),
    crop: picture?.crop.toJson(),
  );

  // The shared design: refreshed when leaving a sharing shape (that element
  // is the shared design), kept when leaving a detached one.
  var sharedDesign = detached ? element.base.shared : _snapshot(element);
  // With nothing detached anywhere no shared copy is kept.
  var anyOwn = layouts.values.any((l) => l.own != null);

  // If this shape followed the others' words, every following shape takes
  // what was typed: done on leaving, not on every keystroke.
  if (!ownHere && words != null) {
    for (var key in layouts.keys.toList()) {
      if (!layouts[key]!.ownText) {
        layouts[key] = layouts[key]!.copyWith(text: words);
      }
    }
  }

  var shared = _shared(layouts) ?? words;

  var next = layouts.remove(to) ??
      // A new shape follows the shared words, not a shape's own.
      seeded(layouts[from]!, seed, covers)
          .copyWith(text: shared, ownText: false);

  var keepsShared = anyOwn || next.own != null;
  var moved = showing(element, next, shared: sharedDesign).withBase(
    layouts: layouts,
    shared: keepsShared ? sharedDesign : null,
    clearShared: !keepsShared,
  );

  if (moved is TextElement) {
    var say = next.ownText ? next.text : shared;
    if (say != null && say != moved.text) moved = moved.copyWith(text: say);
  }
  return moved;
}

/// _shared is the words on the shapes without their own, or null.
String? _shared(Map<String, ElementLayout> layouts) {
  for (var layout in layouts.values) {
    if (!layout.ownText && layout.text != null) return layout.text;
  }
  return null;
}
