import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
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
/// The one step of a shape change, for one element. A shape nobody has worked
/// on yet is seeded by scaling what was just put away, so the first visit
/// lands on something that already looks like the design.
CanvasElement movedTo(CanvasElement element, String from, String to, double by) {
  var layouts = {...element.base.layouts};
  layouts[from] = ElementLayout.of(element.base);
  var next = layouts.remove(to) ?? layouts[from]!.scaledBy(by);
  return element.withBase(
    x: next.x,
    y: next.y,
    width: next.width,
    height: next.height,
    visible: next.visible,
    layouts: layouts,
  );
}
