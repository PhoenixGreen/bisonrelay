import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';

// preset_scaling.dart is a saved design arriving on a canvas of another size.
// A preset carries the page it was made on and is scaled by the ratio of the
// two pages, so it looks as it did where it was made. The same rule as
// CanvasSize.scalesDesign: a bigger page is a resolution, not more room.

/// presetScale is how much a design made on [from] is sized by to sit on
/// [to].
///
/// The smaller of the two ratios, so it fits across and down. One where the
/// source page is unknown (older presets).
double presetScale(Size? from, Size to) {
  if (from == null || from.width <= 0 || from.height <= 0) return 1;
  if (to.width <= 0 || to.height <= 0) return 1;
  var by = math.min(to.width / from.width, to.height / from.height);
  // Near 1 is treated as 1, to avoid rounding drift.
  return (by - 1).abs() < 0.001 ? 1 : by;
}

/// scaledElement is [element] at [by] times the size, place and all.
///
/// The box is scaled here and its contents (type, spacing, padding) by
/// [CanvasElement.scaledBy]; scaling the box alone would stretch it.
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
/// size: element presets are saved without a place.
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
