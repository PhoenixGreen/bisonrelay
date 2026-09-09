import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

// image_silhouette.dart is where a picture actually is, as opposed to where its
// box is.
//
// A photograph fills its rectangle and the two are the same thing. A cut-out
// -- a badge, a player, anything with its background taken out -- does not,
// and the difference is most of the picture: text set around such a thing's
// box keeps a wide empty margin round nothing, which is exactly what wrapping
// is supposed to stop.
//
// The shape is kept as a profile rather than as a path: for each of a few
// hundred rows, how far in from the left the picture starts and how far in
// from the right it ends. That is all a line of text needs -- it asks "what
// room is there between these two heights" and nothing else -- and it is one
// pass over the pixels rather than an edge trace.

/// ImageOutline is the leftmost and rightmost ink on each of [rows] bands of a
/// picture, as fractions of its width.
class ImageSilhouette {
  /// left and right are 0..1 across the picture. A row with nothing on it has
  /// left greater than right, which is how "no ink here" is said without a
  /// second list of flags.
  final Float32List left;
  final Float32List right;
  final int rows;

  const ImageSilhouette(this.left, this.right, this.rows);

  /// spanIn is the ink between two heights, in the coordinates the picture is
  /// drawn in.
  ///
  /// [dst] is where the picture is on the canvas and [src] the part of it
  /// being shown -- a crop and a cover fit both mean the two are not the same
  /// picture -- so the rows this looks at are the rows actually on screen.
  (double, double)? spanIn(
      Rect dst, Rect src, Size image, double top, double bottom) {
    if (dst.width <= 0 || dst.height <= 0 || image.height <= 0) return null;
    if (bottom <= dst.top || top >= dst.bottom) return null;

    // The band, in the picture's own rows.
    var from = ((top - dst.top) / dst.height).clamp(0.0, 1.0);
    var to = ((bottom - dst.top) / dst.height).clamp(0.0, 1.0);
    var y0 = (src.top + src.height * from) / image.height;
    var y1 = (src.top + src.height * to) / image.height;

    var first = (y0 * rows).floor().clamp(0, rows - 1);
    var last = (y1 * rows).ceil().clamp(1, rows) - 1;

    var leftMost = 2.0;
    var rightMost = -1.0;
    for (var row = first; row <= last; row++) {
      if (left[row] > right[row]) continue;
      leftMost = math.min(leftMost, left[row]);
      rightMost = math.max(rightMost, right[row]);
    }
    if (rightMost < leftMost) return null;

    // Back out to the canvas, through the part of the picture being shown.
    double across(double at) {
      var x = at * image.width;
      if (src.width <= 0) return dst.left;
      return dst.left + (x - src.left) / src.width * dst.width;
    }

    var a = across(leftMost).clamp(dst.left, dst.right);
    var b = across(rightMost).clamp(dst.left, dst.right);
    if (b <= a) return null;
    return (a, b);
  }
}

/// silhouetteOf reads a decoded picture's alpha and builds its profile.
///
/// Rows rather than pixels: [rows] bands over the height, each keeping the
/// leftmost and rightmost pixel that is not see-through. A hundred and
/// twenty-eight of them is finer than any line of type can ask about and
/// costs one pass over the bytes.
Future<ImageSilhouette?> silhouetteOf(ui.Image image, {int rows = 128}) async {
  var data = await image.toByteData();
  if (data == null) return null;

  var width = image.width;
  var height = image.height;
  if (width <= 0 || height <= 0) return null;

  var left = Float32List(rows)..fillRange(0, rows, 2);
  var right = Float32List(rows)..fillRange(0, rows, -1);
  var bytes = data.buffer.asUint8List();

  for (var y = 0; y < height; y++) {
    var row = (y * rows ~/ height).clamp(0, rows - 1);
    var at = y * width * 4;
    // From each end inwards, stopping as soon as both have found ink: the
    // interesting rows are the ones with a little on them, and those are the
    // ones this leaves early on.
    var from = -1;
    for (var x = 0; x < width; x++) {
      if (bytes[at + x * 4 + 3] > 8) {
        from = x;
        break;
      }
    }
    if (from < 0) continue;
    var to = from;
    for (var x = width - 1; x > from; x--) {
      if (bytes[at + x * 4 + 3] > 8) {
        to = x;
        break;
      }
    }

    var a = from / width;
    var b = (to + 1) / width;
    if (a < left[row]) left[row] = a;
    if (b > right[row]) right[row] = b;
  }

  return ImageSilhouette(left, right, rows);
}
