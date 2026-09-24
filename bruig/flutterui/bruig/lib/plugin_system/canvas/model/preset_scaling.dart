import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';

// preset_scaling.dart is a saved design arriving on a canvas of another size.
//
// A preset carries the page it was made on. Dropped on a smaller one without
// this, a headline built for a 1920-wide banner arrives 1920 wide -- off the
// side of the page, in type nobody can use -- which is the "presets come in
// too big" of the report. Scaled by the ratio of the two pages, it arrives
// looking the way it looked where it was made, which is what saving it was
// for.
//
// The same rule the size setting follows: see CanvasSize.scalesDesign, where
// a bigger page is a resolution rather than more room.

/// presetScale is how much a design made on [from] is sized by to sit on
/// [to].
///
/// The smaller of the two ratios, so a design made for a wide page and
/// dropped on a tall one fits across rather than hanging off the side. One
/// where either page is unknown, which is what an older preset carries -- it
/// arrives as it was saved rather than being guessed at.
double presetScale(Size? from, Size to) {
  if (from == null || from.width <= 0 || from.height <= 0) return 1;
  if (to.width <= 0 || to.height <= 0) return 1;
  var by = math.min(to.width / from.width, to.height / from.height);
  // A hair either side of 1 is not worth the rounding it costs.
  return (by - 1).abs() < 0.001 ? 1 : by;
}

/// scaledElement is [element] at [by] times the size, place and all.
///
/// Both halves matter: the box is scaled here, and what is inside it --
/// the type, the spacing, the room in a chip -- by the element's own
/// scaledBy. Scaling the box alone is the stretch that holding the
/// proportions was written to avoid. See CanvasElement.scaledBy.
CanvasElement scaledElement(CanvasElement element, double by) {
  if (by == 1) return element;
  var inner = element.scaledBy(by);
  return inner.withBase(
    x: element.x * by,
    y: element.y * by,
    width: math.max(1, element.width * by),
    height: math.max(1, element.height * by),
  );
}

/// scaledScene is every element of [scene] at [by] times the size.
CanvasScene scaledScene(CanvasScene scene, double by) => by == 1
    ? scene
    : scene.copyWith(
        elements: [for (var e in scene.elements) scaledElement(e, by)]);

/// centredOn puts [element] in the middle of a page [on] big, keeping its
/// size.
///
/// What an element preset wants on arrival: the place it was saved at was
/// stripped when it was saved -- a preset is dropped where the canvas
/// decides, not where it happened to sit on somebody else's page.
CanvasElement centredOn(CanvasElement element, Size on) => element.withBase(
      x: (on.width - element.width) / 2,
      y: (on.height - element.height) / 2,
    );

/// sizeFromJson reads a page size written by [sizeToJson].
Size? sizeFromJson(dynamic json) {
  if (json is! Map) return null;
  var w = json["w"], h = json["h"];
  if (w is! num || h is! num || w <= 0 || h <= 0) return null;
  return Size(w.toDouble(), h.toDouble());
}

/// sizeToJson is the page a preset was made on, as it is saved.
Map<String, dynamic> sizeToJson(Size size) =>
    {"w": size.width, "h": size.height};
