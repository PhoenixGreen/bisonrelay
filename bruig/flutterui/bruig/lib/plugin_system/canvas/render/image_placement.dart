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

  /// whole is the picture the fit had to work with -- the crop, before the fit
  /// took anything else off. [src] is the part of it that is actually drawn.
  ///
  /// Kept so that reframing can draw the part that is not: dragging a picture
  /// about inside its frame is guesswork unless what is outside the frame can
  /// be seen, and working that rectangle out a second time somewhere else is
  /// exactly the disagreement this file exists to prevent.
  final Rect whole;

  const ImagePlacement(this.src, this.dst, [Rect? whole])
      : whole = whole ?? src;

  /// slack is how much of the picture, in its own pixels, is not being shown
  /// -- which is what framing spends. Zero in a direction means the picture is
  /// exactly as wide (or tall) as the window, and there is nothing to move.
  Offset get slack => Offset(math.max(0, whole.width - src.width),
      math.max(0, whole.height - src.height));

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
  double scaleToImage() => dst.width <= 0 ? 1 : src.width / dst.width;
}

/// placeImage works out where [imageSize] goes inside [rect].
///
/// [framing] is spent only by [ImageFit.cover], because it is the only fit
/// with anything to spend: containing shows the whole picture and stretching
/// distorts it to the frame, and in both cases there is no slack to move
/// about. See [ImageFraming].
ImagePlacement placeImage(
  Size imageSize,
  Rect rect,
  ImageFit fit, {
  ImageCrop crop = const ImageCrop(),
  ImageFraming framing = const ImageFraming(),
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
  var cropped = src;

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
      //
      // The zoom multiplies that scale, which takes less of the picture for
      // the same frame -- the whole of a zoom is that the window shrinks.
      var scale = math.max(rect.width / src.width, rect.height / src.height) *
          framing.zoom;
      var window = Size(rect.width / scale, rect.height / scale);

      // Whatever is left over in each direction is spent by the framing. At
      // 0.5 this lands exactly where centring did, so a picture nobody has
      // reframed is placed as it always was, to the pixel.
      var slack = Offset(math.max(0, src.width - window.width),
          math.max(0, src.height - window.height));
      src = Rect.fromLTWH(src.left + slack.dx * framing.x,
          src.top + slack.dy * framing.y, window.width, window.height);
      dst = rect;
  }
  return ImagePlacement(src, dst, cropped);
}
