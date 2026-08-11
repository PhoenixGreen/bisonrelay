import 'package:bruig/theming_system/model/area_options.dart';
import 'package:bruig/theming_system/model/area_sides.dart';
import 'package:flutter/material.dart';

// bubble_shape.dart turns a chat bubble's corner settings -- a radius per
// corner plus a BubbleCornerStyle -- into the ShapeBorder the bubble is
// painted with. See AreaStyle.bubbleCorners for the settings themselves.

// bubbleShape is the border for one message bubble. `radii` are its four
// corner radii in SideValues' clockwise-from-top-left order; `isOwn` says
// which side the message is on, which only the speech style consults (it
// squares off the bottom corner nearest the speaker).
ShapeBorder bubbleShape(BubbleCornerStyle style, SideValues radii, bool isOwn) {
  var r = BorderRadius.only(
    topLeft: Radius.circular(radii.topLeft),
    topRight: Radius.circular(radii.topRight),
    bottomRight: Radius.circular(radii.bottomRight),
    bottomLeft: Radius.circular(radii.bottomLeft),
  );

  switch (style) {
    case BubbleCornerStyle.rounded:
      return RoundedRectangleBorder(borderRadius: r);
    case BubbleCornerStyle.beveled:
      return BeveledRectangleBorder(borderRadius: r);
    case BubbleCornerStyle.speech:
      return RoundedRectangleBorder(
          borderRadius: isOwn
              ? r.copyWith(bottomRight: Radius.zero)
              : r.copyWith(bottomLeft: Radius.zero));
    case BubbleCornerStyle.inverted:
      return _InvertedCornerBorder(borderRadius: r);
  }
}

// _InvertedCornerBorder scoops each corner inward instead of rounding it
// out: the same quarter-circle arc as a rounded rectangle, swept the other
// way, so the corner reads as bitten out of the box rather than filed off.
//
// Flutter has no built-in for this (RoundedRectangleBorder and
// BeveledRectangleBorder cover the two convex cases), so the path is drawn
// by hand -- clockwise from just after the top-left corner, with each
// corner's arc curving back toward the box's interior.
class _InvertedCornerBorder extends OutlinedBorder {
  final BorderRadius borderRadius;

  const _InvertedCornerBorder({required this.borderRadius, super.side});

  // Each corner is capped at half the shorter side so opposing scoops on a
  // small bubble can't overlap into a self-crossing path.
  double _cap(Rect rect, double radius) =>
      radius.clamp(0, rect.shortestSide / 2);

  Path _path(Rect rect) {
    var tl = _cap(rect, borderRadius.topLeft.x);
    var tr = _cap(rect, borderRadius.topRight.x);
    var br = _cap(rect, borderRadius.bottomRight.x);
    var bl = _cap(rect, borderRadius.bottomLeft.x);

    return Path()
      ..moveTo(rect.left + tl, rect.top)
      ..lineTo(rect.right - tr, rect.top)
      // Sweeping counter-clockwise (clockwise: false) around a centre placed
      // *outside* the box is what turns each convex corner concave.
      ..arcToPoint(Offset(rect.right, rect.top + tr),
          radius: Radius.circular(tr), clockwise: false)
      ..lineTo(rect.right, rect.bottom - br)
      ..arcToPoint(Offset(rect.right - br, rect.bottom),
          radius: Radius.circular(br), clockwise: false)
      ..lineTo(rect.left + bl, rect.bottom)
      ..arcToPoint(Offset(rect.left, rect.bottom - bl),
          radius: Radius.circular(bl), clockwise: false)
      ..lineTo(rect.left, rect.top + tl)
      ..arcToPoint(Offset(rect.left + tl, rect.top),
          radius: Radius.circular(tl), clockwise: false)
      ..close();
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.strokeInset));

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.strokeInset);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(_path(rect), side.toPaint());
  }

  @override
  _InvertedCornerBorder copyWith(
          {BorderSide? side, BorderRadius? borderRadius}) =>
      _InvertedCornerBorder(
          borderRadius: borderRadius ?? this.borderRadius,
          side: side ?? this.side);

  @override
  ShapeBorder scale(double t) => _InvertedCornerBorder(
      borderRadius: borderRadius * t, side: side.scale(t));

  @override
  bool operator ==(Object other) =>
      other is _InvertedCornerBorder &&
      other.borderRadius == borderRadius &&
      other.side == side;

  @override
  int get hashCode => Object.hash(borderRadius, side);
}
