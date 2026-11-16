import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:flutter/painting.dart';

// label_placer.dart is one rule for keeping a chart's words apart, shared by
// every kind (Ken, 2026-11-17, the improvements report's first item): the
// Charts canvas found names crowding under twenty columns, scatter names on
// top of one another, a key reading "20242025", words broken mid-word on
// small tiles -- each kind with its own partial fix, or none.
//
// A label asks for a few places in order of preference; it gets the first
// that is inside the chart and clear of every label already placed (and of
// anything kept clear), else none -- dropped, or for the caller to shrink.

/// LabelPlacer hands out room for labels, first come first served.
class LabelPlacer {
  /// bounds is where labels may go: the chart's own box.
  final Rect bounds;

  /// gap is the least room left between two labels.
  final double gap;

  final List<Rect> _taken = [];

  LabelPlacer(this.bounds,
      {this.gap = 2, Iterable<Rect> keepClear = const []}) {
    _taken.addAll(keepClear);
  }

  /// taken is the room handed out so far, and what was kept clear.
  List<Rect> get taken => List.unmodifiable(_taken);

  /// keepClear marks [r] as not for labels: a mark, a title.
  void keepClear(Rect r) => _taken.add(r);

  /// fits is whether [r] is inside the chart and clear of every label.
  bool fits(Rect r) {
    if (r.left < bounds.left - 0.5 ||
        r.right > bounds.right + 0.5 ||
        r.top < bounds.top - 0.5 ||
        r.bottom > bounds.bottom + 0.5) {
      return false;
    }
    var padded = r.inflate(gap / 2);
    return !_taken.any((t) => t.overlaps(padded));
  }

  /// place is the first of [candidates] that fits, taken; null if none does.
  Rect? place(Iterable<Rect> candidates) {
    for (var r in candidates) {
      if (fits(r)) {
        _taken.add(r);
        return r;
      }
    }
    return null;
  }

  /// around is the places for a label of [size] beside a point [at] of
  /// radius [r], in the usual order: above, right, below, left, then the
  /// four corners.
  static List<Rect> around(Offset at, Size size, double r, {double gap = 3}) {
    var w = size.width, h = size.height, d = r + gap;
    return [
      Rect.fromLTWH(at.dx - w / 2, at.dy - d - h, w, h),
      Rect.fromLTWH(at.dx + d, at.dy - h / 2, w, h),
      Rect.fromLTWH(at.dx - w / 2, at.dy + d, w, h),
      Rect.fromLTWH(at.dx - d - w, at.dy - h / 2, w, h),
      Rect.fromLTWH(at.dx + d * 0.7, at.dy - d * 0.7 - h, w, h),
      Rect.fromLTWH(at.dx - d * 0.7 - w, at.dy - d * 0.7 - h, w, h),
      Rect.fromLTWH(at.dx + d * 0.7, at.dy + d * 0.7, w, h),
      Rect.fromLTWH(at.dx - d * 0.7 - w, at.dy + d * 0.7, w, h),
    ];
  }
}

/// sizeOf is how big [text] is written in [spec] on one line.
Size labelSize(String text, TextSpec spec) {
  var p = layoutText(text, spec, maxWidth: double.infinity);
  return Size(p.width, p.height);
}

/// AxisNames is how a row of names under (or beside) slots is written when
/// they don't all fit: smaller, down to [minScale], and then only every
/// [every]th of them, so none is cut to a few letters.
class AxisNames {
  final double scale;
  final int every;
  const AxisNames(this.scale, this.every);

  bool shows(int i, int n) =>
      every <= 1 || i % every == 0 || (i == n - 1 && (n - 1) % every == 0);

  /// of is how [names] fit slots [slot] wide written in [spec]: their full
  /// size where the widest fits, else as small as [minScale], else every
  /// second, third... name at that size.
  static AxisNames of(List<String> names, TextSpec spec, double slot,
      {double minScale = 0.75}) {
    if (names.isEmpty || slot <= 0) return const AxisNames(1, 1);
    var widest = 0.0;
    for (var n in names) {
      widest = math.max(widest, labelSize(n, spec).width);
    }
    // A little room either side, so neighbours don't touch.
    var need = widest + spec.fontSize * 0.6;
    if (need <= slot) return const AxisNames(1, 1);
    var scale = slot / need;
    if (scale >= minScale) return AxisNames(scale, 1);
    var every = (need * minScale / slot).ceil();
    // Shown every [every] slots, a name has that much room.
    return AxisNames(minScale, math.max(2, every));
  }
}
