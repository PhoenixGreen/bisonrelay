import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';

// responsive_layout.dart is one design laid out for several shapes.
//
// The same canvas is wanted at 4:5 for a feed, 16:9 for a screen and 1:1 for
// everywhere else, and it is one design: the same words, the same colours,
// the same data and the same arrivals. What differs between the three is
// where things sit and how big they are.
//
// So the elements are one set, and each carries a place and a size *per
// shape* -- see ElementLayout. The shape being looked at is not held in that
// map: its numbers are the element's own x, y, width and height, live, which
// is what lets every painter, every handle and every settings field go on
// reading an element the way they always have. Changing shape puts the live
// numbers away under the shape being left and takes out the ones belonging to
// the shape being opened, which is the whole of the mechanism.
//
// A shape nobody has worked on yet is seeded by scaling from the one being
// left, so switching lands on something that already looks right rather than
// on a heap in the corner. See canvasScale.

/// shapeKey names a shape in an element's layouts and in a document's
/// targets.
///
/// The ratio's own name, and "custom" for a custom one whatever numbers it is
/// set to. Keyed by the numbers instead, typing a new aspect would leave the
/// document pointing at a shape nothing is laid out for -- and two different
/// custom shapes in one design is not a thing anybody has asked for. The
/// width is deliberately not in the key either: it is the document's
/// resolution rather than its shape.
String shapeKey(CanvasSize size) => size.ratio.name;

/// shapeLabel is what that key is called in a list.
String shapeLabel(String key) {
  for (var ratio in CanvasRatio.values) {
    if (ratio.name == key) return ratio.label;
  }
  return key;
}

/// shapeTag is a short name for a shape, safe in a filename.
///
/// What tells three files apart when a canvas is published at every shape it
/// is designed for: "card-16x9.png" beside "card-4x5.png". The ratio's label
/// without the words after it, and with the colon a filename cannot carry
/// turned into an x.
String shapeTag(String key) {
  var label = shapeLabel(key);
  var cut = label.indexOf(" ·");
  if (cut > 0) label = label.substring(0, cut);
  return label.replaceAll(":", "x").replaceAll(" ", "");
}

/// canvasScale is how much a design made for one page is sized by for
/// another -- the smaller of the two ratios, so it fits across and down.
///
/// The measure for a *thing being dropped on a page* -- a preset, an element
/// laid out for a shape it has not been seen on. Seeding a whole shape uses
/// [seedFor] instead, which measures the design rather than the page.
double canvasScale(CanvasSize from, CanvasSize to) {
  if (from.width <= 0 || from.height <= 0) return 1;
  var by = math.min(to.width / from.width, to.height / from.height);
  return (by - 1).abs() < 0.001 ? 1 : by;
}

/// ShapeSeed is how a design is placed on a shape nobody has laid it out on.
class ShapeSeed {
  /// by is how much everything is sized by.
  final double by;

  /// block is the design's own bounds on the page being left: everything
  /// except what covers the page.
  final Rect block;

  /// at is where the scaled block's top-left corner goes on the new page.
  final Offset at;

  /// page is the page being opened.
  final Size page;

  const ShapeSeed(
      {required this.by,
      required this.block,
      required this.at,
      required this.page});
}

/// coversPage is whether an element is the page rather than something on it:
/// a photograph behind everything, a colour wash, a frame.
///
/// They are seeded by covering the new page rather than by being scaled with
/// the design, which is the difference between a backdrop and a card.
bool coversPage(CanvasElement element, CanvasSize page) {
  var slack = math.max(page.width, page.height) * 0.02;
  return element.x <= slack &&
      element.y <= slack &&
      element.x + element.width >= page.width - slack &&
      element.y + element.height >= page.height - slack;
}

/// seedFor works out how a scene's design moves onto another shape of page.
///
/// Measured against the *design* rather than against the page, which is the
/// whole difference between this and scaling everything by the ratio of the
/// two pages. A 4:5 feed card taken to 16:9 has the same width and less than
/// half the height, so by the page it would be shrunk to 45% -- a table and a
/// score bug that filled the card left as postage stamps in a corner of the
/// new one, which is what was reported.
///
/// What it does instead: what covers the page goes on covering it, and the
/// rest is one block, scaled by how much the page changed and placed where it
/// sat as a fraction of the page -- so a block across the bottom of a feed
/// card is across the bottom of the screen, at the same share of it.
///
/// Never made larger: type grown to fill a bigger page is type nobody chose.
/// Made smaller than the page asked for where even that does not fit, because
/// a block hanging off two edges is worse than a small one. And nudged back
/// on where it would hang off one.
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
    return ShapeSeed(
        by: 1, block: Rect.zero, at: Offset.zero, page: page);
  }

  // How much the page itself changed, which is what keeps a design looking
  // like itself: a page that lost half its height carries a design at half
  // the size. Never larger -- type grown to fill a bigger page is type
  // nobody chose -- and smaller still where even that does not fit.
  var by = math.min(
    math.min(1.0, math.min(page.width / from.width, page.height / from.height)),
    math.min(page.width / block.width, page.height / block.height),
  );
  var sized = Size(block.width * by, block.height * by);

  // Where it sat, as a fraction of the page it sat on: a block across the
  // bottom of a feed card is across the bottom of the screen too.
  var centre = Offset(
    block.center.dx / math.max(1, from.width) * page.width,
    block.center.dy / math.max(1, from.height) * page.height,
  );
  var at = Offset(centre.dx - sized.width / 2, centre.dy - sized.height / 2);

  // And nudged back on where that would hang it off an edge. A design that
  // fits the page should be on the page.
  at = Offset(
    at.dx.clamp(
        math.min(0, page.width - sized.width), math.max(0, page.width - sized.width)),
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

/// withLayoutsFor is [element] given a layout for every shape in [targets],
/// seeded from the one it is showing.
///
/// What a new element needs on a document that is being designed for several
/// shapes: added while the 16:9 is open, it should be on the 4:5 as well,
/// scaled to it -- otherwise the same card has to be built once per shape,
/// which is the whole thing this was written to avoid.
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

/// sizeForShape is the page a shape key names, at the width [like] is drawn
/// at.
///
/// The width is kept because it is the document's own resolution rather than
/// part of its shape: designing the same canvas at 4:5 and at 16:9 should not
/// change how many pixels it publishes at.
CanvasSize sizeForShape(String key, CanvasSize like) {
  for (var ratio in CanvasRatio.values) {
    if (ratio.name == key) return like.copyWith(ratio: ratio);
  }
  return like;
}

/// movedTo is [element] showing the layout it has for [to], with what it was
/// showing put away under [from].
///
/// The one step of a shape change, for one element, and it moves three
/// things: where the element sits, how much its own measurements have been
/// scaled by, and -- for words -- which set this shape shows.
///
/// A shape nobody has worked on yet is seeded by scaling what was just put
/// away, so the first visit lands on something that already looks like the
/// design. The type comes down with the box: seeded without that, a headline
/// keeps the size it had on the larger page and runs out of the frame.
/// showing is [element] wearing [layout]: its place, its size, and its own
/// design brought to that layout's scale.
///
/// The one place a layout is put on an element. The design has to be scaled
/// by the *difference* between the two, because the element carries one set
/// of measurements for every shape and they are currently at the scale of the
/// shape being left -- see ElementBase.typeScale.
CanvasElement showing(CanvasElement element, ElementLayout layout) {
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

CanvasElement movedTo(CanvasElement element, String from, String to,
    {required ShapeSeed seed, required bool covers}) {
  var layouts = {...element.base.layouts};
  var words = element is TextElement ? element.text : null;
  var ownHere = element.base.ownText;

  // What is on screen belongs to the shape being left.
  layouts[from] = ElementLayout.of(element.base, text: words);

  // Where this shape was following the others, they are all showing the same
  // words, so they all take what has been typed. Done on the way out rather
  // than on every keystroke: one place, and nothing to keep in step while
  // somebody is typing.
  if (!ownHere && words != null) {
    for (var key in layouts.keys.toList()) {
      if (!layouts[key]!.ownText) {
        layouts[key] = layouts[key]!.copyWith(text: words);
      }
    }
  }

  // The words every shape that has not been given its own is showing.
  var shared = _shared(layouts) ?? words;

  var next = layouts.remove(to) ??
      // A new shape follows the others' words: a headline shortened for the
      // narrow page is that page's business, not the next one's.
      seeded(layouts[from]!, seed, covers)
          .copyWith(text: shared, ownText: false);

  var moved = showing(element, next).withBase(layouts: layouts);

  if (moved is TextElement) {
    var say = next.ownText ? next.text : shared;
    if (say != null && say != moved.text) moved = moved.copyWith(text: say);
  }
  return moved;
}

/// _shared is the words the shapes that have not been given their own are
/// showing, or null where none of them has any.
String? _shared(Map<String, ElementLayout> layouts) {
  for (var layout in layouts.values) {
    if (!layout.ownText && layout.text != null) return layout.text;
  }
  return null;
}
