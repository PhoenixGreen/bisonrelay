import 'dart:math' as math;

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

/// canvasScale is how much a design made for one page is sized by for
/// another -- the smaller of the two ratios, so it fits across and down.
double canvasScale(CanvasSize from, CanvasSize to) {
  if (from.width <= 0 || from.height <= 0) return 1;
  var by = math.min(to.width / from.width, to.height / from.height);
  return (by - 1).abs() < 0.001 ? 1 : by;
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
CanvasElement movedTo(CanvasElement element, String from, String to, double by) {
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
      layouts[from]!
          .scaledBy(by)
          .copyWith(text: shared, ownText: false);

  var moved = element.withBase(
    x: next.x,
    y: next.y,
    width: next.width,
    height: next.height,
    visible: next.visible,
    layouts: layouts,
    typeScale: next.typeScale,
    ownText: next.ownText,
  );

  // The design inside the box, brought to this shape's scale. Undoing this
  // shape's scaling before applying that one's is the reason the number is
  // written down at all: scaled numbers cannot say what they were scaled by.
  var was = element.base.typeScale;
  if (next.typeScale != was && was > 0) {
    moved = moved.scaledBy(next.typeScale / was).withBase(
          x: next.x,
          y: next.y,
          width: next.width,
          height: next.height,
          typeScale: next.typeScale,
        );
  }

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
