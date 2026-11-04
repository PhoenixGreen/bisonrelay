import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';

// image_placement.dart answers where a picture's pixels land inside an
// element, and where a point on the element lands in the picture.
//
// The painter uses it to draw and the retouching brush uses it backwards, to
// map a stroke onto pixels; one implementation keeps them in agreement.

/// ImagePlacement is the source rectangle of the picture and the destination
/// rectangle on the canvas that it is drawn into.
class ImagePlacement {
  /// src is in the picture's own pixels, after the crop and after whatever
  /// [ImageFit.cover] trimmed off.
  final Rect src;

  /// dst is where those pixels go, in the element's coordinates.
  final Rect dst;

  /// whole is the picture the fit had to work with. [window] is the part of
  /// it the fit chose, and [src] is what is left of that after the crop.
  /// Reframing uses it to show what is outside the frame.
  final Rect whole;

  /// window is what the fit and the framing chose, before the crop: what
  /// reframing moves about.
  final Rect window;

  ImagePlacement(this.src, this.dst, [Rect? whole, Rect? window])
      : whole = whole ?? src,
        window = window ?? src;

  /// slack is how much of the picture, in its own pixels, the window is not
  /// showing: what framing spends. Measured against the window, so the crop
  /// is not slack and reframing cannot bring it back.
  Offset get slack => Offset(math.max(0, whole.width - window.width),
      math.max(0, whole.height - window.height));

  /// wholeDst is where the whole picture would be drawn: what reframing shows
  /// faintly round the frame. Measured from [src] and [dst] (not [window]),
  /// so it lines up with the drawn part whatever was cropped.
  Rect get wholeDst {
    if (src.width <= 0 || src.height <= 0) return dst;
    var sx = dst.width / src.width, sy = dst.height / src.height;
    return Rect.fromLTWH(
        dst.left - (src.left - whole.left) * sx,
        dst.top - (src.top - whole.top) * sy,
        whole.width * sx,
        whole.height * sy);
  }

  /// toImage turns a point on the canvas into one in the picture, as a
  /// fraction of its full size: how brush strokes are stored, so they survive
  /// resizing, refitting and recropping. Null outside the drawn picture.
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

  /// scaleToImage is how many picture pixels one canvas unit covers.
  double scaleToImage() => dst.width <= 0 ? 1 : src.width / dst.width;
}

/// placeImage works out where [imageSize] goes inside [rect].
///
/// [framing] is used only by [ImageFit.cover], the only fit with slack to
/// move. See [ImageFraming].
ImagePlacement placeImage(
  Size imageSize,
  Rect rect,
  ImageFit fit, {
  ImageCrop crop = const ImageCrop(),
  ImageFraming framing = const ImageFraming(),
}) {
  var whole = Rect.fromLTWH(0, 0, imageSize.width, imageSize.height);
  if (whole.width <= 0 || whole.height <= 0) {
    return ImagePlacement(whole, rect);
  }
  var src = whole;

  // The frame before cropping. Cropping trims the element's box (see
  // ImageElement.croppedTo), so [rect] is already smaller; fitting to it
  // would change the scale and make cropping zoom.
  var frame = rect;
  if (!crop.isWhole) {
    var w = rect.width / crop.width;
    var h = rect.height / crop.height;
    frame =
        Rect.fromLTWH(rect.left - w * crop.left, rect.top - h * crop.top, w, h);
  }

  Rect dst;
  switch (fit) {
    case ImageFit.stretch:
      dst = frame;
    case ImageFit.contain:
      var scale = math.min(frame.width / src.width, frame.height / src.height);
      dst = Rect.fromCenter(
          center: frame.center,
          width: src.width * scale,
          height: src.height * scale);
    case ImageFit.cover:
      // Cover crops the source rather than overflowing the destination, so
      // nothing needs clipping. Zoom shrinks the window.
      var scale = math.max(frame.width / src.width, frame.height / src.height) *
          framing.zoom;
      var window = Size(frame.width / scale, frame.height / scale);

      // The framing spends the slack; 0.5 is centred.
      var slack = Offset(math.max(0, src.width - window.width),
          math.max(0, src.height - window.height));
      src = Rect.fromLTWH(src.left + slack.dx * framing.x,
          src.top + slack.dy * framing.y, window.width, window.height);
      dst = frame;
  }

  // The crop last, off the window: a quarter cropped is a quarter of what is
  // visible, and the element's frame is trimmed by the same share (see
  // ImageElement.croppedTo), so what is left does not move.
  var window = src;
  if (!crop.isWhole && src.width > 0 && src.height > 0) {
    var kept = Rect.fromLTRB(
      src.left + src.width * crop.left,
      src.top + src.height * crop.top,
      src.left + src.width * crop.right,
      src.top + src.height * crop.bottom,
    );
    // The same share of where it is drawn.
    var into = Rect.fromLTRB(
      dst.left + dst.width * crop.left,
      dst.top + dst.height * crop.top,
      dst.left + dst.width * crop.right,
      dst.top + dst.height * crop.bottom,
    );
    if (kept.width > 0 && kept.height > 0) {
      src = kept;
      dst = into;
    }
  }
  return ImagePlacement(src, dst, whole, window);
}
