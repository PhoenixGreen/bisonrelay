import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:flutter/material.dart';

// text_items.dart is where a text element's extra pieces are laid out, and
// the one answer to that question.
//
// Asked of the same function by the painter and by the stage, because the
// stage has to hit-test exactly what was drawn: an item is clicked to type
// into it, and a second opinion about where it is is a click that lands on
// the wrong words. The same arrangement chartLegendRects has.

/// textItemRects is where each of [e]'s items is drawn, in the element's own
/// coordinates and in the element's own order.
///
/// Items in the same slot stack in the order they were added: down from the
/// top for a top slot, up from the bottom for a bottom one, and about the
/// middle for a middle one. Nine slots is enough places for a card, and two
/// items in one slot drawn over each other would be a card with a mistake in
/// it that the panel could not explain.
List<Rect> textItemRects(TextElement e, Rect bounds) {
  if (e.items.isEmpty) return const [];
  var inner = e.box.inner(bounds);
  if (inner.width <= 0 || inner.height <= 0) {
    return [for (var _ in e.items) Rect.zero];
  }

  var out = List<Rect>.filled(e.items.length, Rect.zero);
  for (var slot in TextSlot.values) {
    var mine = [
      for (var (i, item) in e.items.indexed)
        if (item.slot == slot) i,
    ];
    if (mine.isEmpty) continue;

    var sizes = [
      for (var i in mine) _sizeOf(e.items[i], inner.width),
    ];
    var total = sizes.fold(0.0, (sum, s) => sum + s.height);
    var top = switch (slot.down) {
      VerticalAlignSpec.top => inner.top,
      VerticalAlignSpec.middle => inner.center.dy - total / 2,
      VerticalAlignSpec.bottom => inner.bottom - total,
    };

    for (var (n, i) in mine.indexed) {
      var size = sizes[n];
      var left = switch (slot.across) {
        TextAlignSpec.left => inner.left,
        TextAlignSpec.center => inner.center.dx - size.width / 2,
        TextAlignSpec.right => inner.right - size.width,
        // Justified words fill the line they are on, so there is nothing to
        // hold to an edge: it reads as left, which is what it looks like.
        TextAlignSpec.justify => inner.left,
      };
      out[i] = Rect.fromLTWH(left, top, size.width, size.height);
      top += size.height;
    }
  }
  return out;
}

/// _sizeOf is how much room one item's words take, given the width they have.
Size _sizeOf(TextItem item, double maxWidth) {
  if (item.text.isEmpty) return Size.zero;
  var painter =
      layoutText(item.text, item.spec, maxWidth: math.max(1, maxWidth));
  return Size(math.min(painter.width, maxWidth), painter.height);
}

/// paintTextItems draws them, after the element's own paragraph and inside
/// the same box.
///
/// They arrive with the element rather than each on its own account: a card
/// is one thing arriving, and four pieces of writing fading in one after
/// another out of the same pair of keyframes is a card that reads as four
/// elements again. A piece that wants a moment of its own can be given one
/// when there is a reason to.
void paintTextItems(
  ui.Canvas canvas,
  Rect bounds,
  TextElement e, {
  TextAnimation? animation,
  double reveal = 1,
  CanvasImageSource? images,

  /// skip is the piece with an editor open over it, whose words are being
  /// drawn by a real text field instead. See CanvasTextEditor.
  String? skip,
}) {
  if (e.items.isEmpty) return;
  var rects = textItemRects(e, bounds);
  for (var (i, item) in e.items.indexed) {
    var rect = rects[i];
    if (item.text.isEmpty || rect.isEmpty || item.id == skip) continue;
    // The slot decides how the words sit, so the item's own alignment is not
    // asked: a piece held to the right-hand edge is set ragged-left inside
    // its own rectangle, and its rectangle is only as wide as it is.
    paintTextInBox(
      canvas,
      item.text,
      item.spec.copyWith(
        align: item.slot.across,
        verticalAlign: VerticalAlignSpec.top,
      ),
      rect,
      animation: animation,
      reveal: reveal,
      images: images,
    );
  }
}
