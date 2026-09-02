import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';

// image_placement.dart answers where a picture's pixels land inside an
// element, and where a point on the element lands in the picture.
//
// One place, because two things need it and they must not disagree. The
// painter uses it to draw; the retouching brush uses it backwards, to turn a
// stroke drawn on the canvas into the pixels it is meant to touch. If the two
// worked it out separately then painting on the middle of a face would rub out
// something else, and the fault would look like the brush being inaccurate
// rather than like two functions having different opinions.

/// ImagePlacement is the source rectangle of the picture and the destination
/// rectangle on the canvas that it is drawn into.
class ImagePlacement {
  /// src is in the picture's own pixels, after the crop and after whatever
  /// [ImageFit.cover] trimmed off.
  final Rect src;

  /// dst is where those pixels go, in the element's coordinates.
  final Rect dst;

  const ImagePlacement(this.src, this.dst);

  /// toImage turns a point on the canvas into one in the picture, as a
  /// fraction of its full width and height -- which is how a brush stroke is
  /// stored, so that it survives the element being resized, refitted or
  /// recropped afterwards.
  ///
  /// Returns null for a point outside the drawn picture. A stroke that runs
  /// off the edge is not an error; the part that is on the picture still
  /// counts, and the part that is not has nothing to touch.
  Offset? toImage(Offset onCanvas, Size imageSize) {
    if (dst.width <= 0 || dst.height <= 0) return null;
    if (imageSize.width <= 0 || imageSize.height <= 0) return null;
    var fx = (onCanvas.dx - dst.left) / dst.width;
    var fy = (onCanvas.dy - dst.top) / dst.height;
    if (fx < 0 || fx > 1 || fy < 0 || fy > 1) return null;
    return Offset(
      (src.left + fx * src.width) / imageSize.width,
      (src.top + fy * src.height) / imageSize.height,
    );
  }

  /// scaleToImage is how many picture pixels one canvas unit covers, which is
  /// what turns a brush's size on screen into a radius in the picture.
  double scaleToImage() =>
      dst.width <= 0 ? 1 : src.width / dst.width;
}

/// placeImage works out where [imageSize] goes inside [rect].
ImagePlacement placeImage(
  Size imageSize,
  Rect rect,
  ImageFit fit, {
  ImageCrop crop = const ImageCrop(),
}) {
  var whole = Rect.fromLTWH(0, 0, imageSize.width, imageSize.height);
  // The crop is applied first and everything after it works on what is left,
  // so fitting, covering and framing all see the picture the reader chose
  // rather than the one on disk.
  var src = Rect.fromLTRB(
    whole.width * crop.left,
    whole.height * crop.top,
    whole.width * crop.right,
    whole.height * crop.bottom,
  );
  if (src.width <= 0 || src.height <= 0) return ImagePlacement(whole, rect);

  Rect dst;
  switch (fit) {
    case ImageFit.stretch:
      dst = rect;
    case ImageFit.contain:
      var scale = math.min(rect.width / src.width, rect.height / src.height);
      dst = Rect.fromCenter(
          center: rect.center,
          width: src.width * scale,
          height: src.height * scale);
    case ImageFit.cover:
      // Cover crops the source rather than overflowing the destination, so
      // the caller does not have to clip and an unclipped cover cannot spill
      // over its neighbours.
      var scale = math.max(rect.width / src.width, rect.height / src.height);
      src = Rect.fromCenter(
          center: src.center,
          width: rect.width / scale,
          height: rect.height / scale);
      dst = rect;
  }
  return ImagePlacement(src, dst);
}
