import 'package:flutter/material.dart';

// canvas_align.dart is lining several things up with each other: elements
// on the page, or a picture's layers inside it. An operation on what is
// chosen, not part of the design, so it is kept out of the document's model.

/// CanvasAlign is one of the six ways a set of elements can be lined up.
/// "left" means all their left edges together, not "move them left".
enum CanvasAlign {
  left("Align left", Icons.align_horizontal_left),
  centreX("Centre across", Icons.align_horizontal_center),
  right("Align right", Icons.align_horizontal_right),
  top("Align top", Icons.align_vertical_top),
  middleY("Centre down", Icons.align_vertical_center),
  bottom("Align bottom", Icons.align_vertical_bottom);

  final String label;
  final IconData icon;
  const CanvasAlign(this.label, this.icon);

  /// offset is how far [at] moves to line up with [box] this way: across
  /// for left, centre and right, down for top, middle and bottom.
  Offset offset(Rect box, Rect at) => Offset(
        switch (this) {
          left => box.left - at.left,
          centreX => box.center.dx - at.center.dx,
          right => box.right - at.right,
          _ => 0.0,
        },
        switch (this) {
          top => box.top - at.top,
          middleY => box.center.dy - at.center.dy,
          bottom => box.bottom - at.bottom,
          _ => 0.0,
        },
      );
}
