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
// the one answer to that question: the painter and the stage both ask it, so
// a click hits exactly what was drawn (as with chartLegendRects).

/// textItemRects is where each of [e]'s items is drawn, in the element's own
/// coordinates and in the element's own order. Items in the same slot stack
/// in the order they were added: down from the top for a top slot, up from
/// the bottom for a bottom one, and about the middle for a middle one.
List<Rect> textItemRects(TextElement e, Rect bounds) =>
    _blockRects(e, bounds).skip(1).toList();

/// textBodyRect is where the element's own words go when they have been given
/// a slot, or null when they fill the box as usual. See TextElement.slot.
Rect? textBodyRect(TextElement e, Rect bounds) {
  if (!bodyIsBlock(e)) return null;
  var rect = _blockRects(e, bounds).first;
  return rect.isEmpty ? null : rect;
}

/// bodyIsBlock is whether the element's own words are one of the blocks in a
/// slot rather than the paragraph filling the box. Not when they are set
/// along a line, in columns, or flowing on into another box.
bool bodyIsBlock(TextElement e) =>
    e.slot != null &&
    e.curve == null &&
    e.columns.isSingle &&
    e.flowTo.isEmpty &&
    e.text.isNotEmpty;

/// _blockRects is every block this element draws: the element's own words
/// first, whether or not they are in a slot, and then the pieces.
List<Rect> _blockRects(TextElement e, Rect bounds) {
  var body = bodyIsBlock(e);
  if (e.items.isEmpty && !body) {
    return [Rect.zero, for (var _ in e.items) Rect.zero];
  }
  var inner = e.box.inner(bounds);
  if (inner.width <= 0 || inner.height <= 0) {
    return [Rect.zero, for (var _ in e.items) Rect.zero];
  }

  // The blocks, by the slot each is in. Index 0 is the element's own words.
  TextSlot? slotOf(int i) =>
      i == 0 ? (body ? e.slot : null) : e.items[i - 1].slot;
  Size sizeOf(int i) => i == 0
      ? _sizeOfText(e.text, drawnTextSpec(e, bounds), inner.width)
      : _sizeOf(e.items[i - 1], inner.width);
  double gapOf(int i) => i == 0 ? 0 : e.items[i - 1].gap;
  double leadOf(int i) => i == 0 ? 0 : e.items[i - 1].gap;
  // Sideways, away from the edge the slot holds this piece to.
  double sideOf(int i) => i == 0 ? 0 : e.items[i - 1].side;

  var out = List<Rect>.filled(e.items.length + 1, Rect.zero);
  for (var slot in TextSlot.values) {
    var mine = [
      for (var i = 0; i < out.length; i++)
        if (slotOf(i) == slot) i,
    ];
    if (mine.isEmpty) continue;

    var sizes = [for (var i in mine) sizeOf(i)];

    // The stack's own height: every piece, and the room between each and the
    // one before. The first piece's room is the distance from the edge the
    // slot holds the stack to, applied to the stack rather than inside it,
    // so it works at the bottom of the box too. See TextItem.gap.
    var lead = leadOf(mine.first);
    var total = sizes.first.height;
    for (var (n, i) in mine.indexed) {
      if (n == 0) continue;
      total += sizes[n].height + gapOf(i);
    }
    var top = switch (slot.down) {
      VerticalAlignSpec.top => inner.top + lead,
      VerticalAlignSpec.middle => inner.center.dy - total / 2 + lead,
      VerticalAlignSpec.bottom => inner.bottom - total - lead,
    };

    for (var (n, i) in mine.indexed) {
      var size = sizes[n];
      if (n > 0) top += gapOf(i);
      var side = sideOf(i);
      var left = switch (slot.across) {
        TextAlignSpec.left => inner.left + side,
        TextAlignSpec.center => inner.center.dx - size.width / 2 + side,
        TextAlignSpec.right => inner.right - size.width - side,
        // Justified words fill their line, so there is no edge to hold to:
        // it reads as left.
        TextAlignSpec.justify => inner.left + side,
      };
      out[i] = Rect.fromLTWH(left, top, size.width, size.height);
      top += size.height;
    }
  }
  return out;
}

/// _sizeOfText is how tall and wide a run of words comes out at a width.
Size _sizeOfText(String text, TextSpec spec, double maxWidth) {
  if (text.isEmpty) return Size.zero;
  var painter = layoutText(text, spec, maxWidth: math.max(1, maxWidth));
  return Size(math.min(painter.width, maxWidth), painter.height);
}

/// _sizeOf is how much room one piece takes, given the width it has: a
/// picture is a square of its own size; words are as tall as they come out.
Size _sizeOf(TextItem item, double maxWidth) {
  // The room the background takes is the piece's too: the words are drawn
  // inside it, padding and all.
  var pad = item.box.pad;
  var inside = math.max(1.0, maxWidth - pad.left - pad.right);

  var icon = item.icon;
  if (icon != null) {
    if (!icon.on) return Size.zero;
    var side = math.min(icon.size, inside);
    return Size(side + pad.left + pad.right, icon.size + pad.top + pad.bottom);
  }
  var words = _sizeOfText(item.text, item.spec, inside);
  if (words.isEmpty) return Size.zero;
  return Size(
      words.width + pad.left + pad.right, words.height + pad.top + pad.bottom);
}

/// paintTextItems draws them, after the element's own paragraph and inside
/// the same box. They arrive with the element rather than each on its own,
/// since a card is one thing arriving.
/// LayerPainter draws one layer of a text -- [draw], its letters or its
/// picture, in [box] -- with the looks laid on that layer alone (see
/// MotionDevice.layer): [layer] is MotionDevice.bodyLayer for the text's own
/// words, or a piece's id. The box behind them is not the layer's: a look on
/// all of the text covers that.
typedef LayerPainter = void Function(
    ui.Canvas canvas, Rect box, String layer, void Function(ui.Canvas on) draw);

void paintTextItems(
  ui.Canvas canvas,
  Rect bounds,
  TextElement e, {
  TextAnimation? animation,
  double reveal = 1,
  CanvasImageSource? images,

  /// onLayer draws each piece with its own looks; none, without.
  LayerPainter? onLayer,

  /// skip is the piece with an editor open over it, whose words are being
  /// drawn by a real text field instead. See CanvasTextEditor.
  String? skip,
}) {
  if (e.items.isEmpty) return;
  var rects = textItemRects(e, bounds);
  for (var (i, item) in e.items.indexed) {
    var rect = rects[i];
    if (rect.isEmpty || item.id == skip || item.hidden) continue;

    // What is behind it, if anything, and then the piece inside that.
    paintBox(canvas, rect, item.box, images);
    var inner = item.box.inner(rect);
    if (inner.width <= 0 || inner.height <= 0) continue;

    var icon = item.icon;
    if (icon == null && item.text.isEmpty) continue;
    void drawn(ui.Canvas canvas) {
      if (icon != null) {
        // Drawn by the same function the element's own icon is drawn by, so
        // a picture in a box looks the same however it got there.
        paintTextIcon(canvas, inner, icon, images, item.spec);
        return;
      }
      // The slot decides how the words sit, so the item's own alignment is
      // not asked: a piece held to the right-hand edge is set ragged-left
      // inside a rectangle only as wide as it is.
      paintTextInBox(
        canvas,
        item.text,
        item.spec.copyWith(
          align: item.slot.across,
          verticalAlign: VerticalAlignSpec.top,
        ),
        inner,
        animation: animation,
        reveal: reveal,
        images: images,
      );
    }

    if (onLayer == null) {
      drawn(canvas);
    } else {
      onLayer(canvas, inner, item.id, drawn);
    }
  }
}
