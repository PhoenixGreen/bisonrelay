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

  /// whole is the picture the fit had to work with. [window] is the part of
  /// it the fit chose, and [src] is what is left of that after the crop.
  ///
  /// Kept so that reframing can draw the part that is not being shown:
  /// dragging a picture about inside its frame is guesswork unless what is
  /// outside the frame can be seen, and working that rectangle out a second
  /// time somewhere else is exactly the disagreement this file exists to
  /// prevent.
  final Rect whole;

  /// window is what the fit and the framing chose, before the crop took a
  /// share of it.
  ///
  /// Held apart from [src] because the two answer different questions: what
  /// the frame *could* show is what reframing moves about, and what is
  /// actually drawn is that less the crop.
  final Rect window;

  ImagePlacement(this.src, this.dst, [Rect? whole, Rect? window])
      : whole = whole ?? src,
        window = window ?? src;

  /// slack is how much of the picture, in its own pixels, the frame is not
  /// showing -- which is what framing spends. Zero in a direction means the
  /// picture is exactly as wide (or tall) as the window, and there is nothing
  /// to move.
  ///
  /// Against the window rather than against what is drawn: the crop is not
  /// slack. It is a part of the picture the reader has taken off, and
  /// dragging the rest about must not bring it back.
  Offset get slack => Offset(math.max(0, whole.width - window.width),
      math.max(0, whole.height - window.height));

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
  if (whole.width <= 0 || whole.height <= 0) {
    return ImagePlacement(whole, rect);
  }
  var src = whole;

  // The frame this picture had before it was cropped.
  //
  // Cropping trims the element's own box -- see ImageElement.croppedTo -- so
  // the rectangle handed in here is already the smaller one. Fitting to that
  // would choose a different window and the picture left over would change
  // size, which is the "cropping zooms" of the report. Fitted to the frame it
  // was cropped from, the part that is left is drawn at exactly the scale it
  // was, and the crop takes the same share of the window that it took of the
  // frame.
  var frame = rect;
  if (!crop.isWhole) {
    var w = rect.width / crop.width;
    var h = rect.height / crop.height;
    frame = Rect.fromLTWH(
        rect.left - w * crop.left, rect.top - h * crop.top, w, h);
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
      // the caller does not have to clip and an unclipped cover cannot spill
      // over its neighbours.
      //
      // The zoom multiplies that scale, which takes less of the picture for
      // the same frame -- the whole of a zoom is that the window shrinks.
      var scale =
          math.max(frame.width / src.width, frame.height / src.height) *
              framing.zoom;
      var window = Size(frame.width / scale, frame.height / scale);

      // Whatever is left over in each direction is spent by the framing. At
      // 0.5 this lands exactly where centring did, so a picture nobody has
      // reframed is placed as it always was, to the pixel.
      var slack = Offset(math.max(0, src.width - window.width),
          math.max(0, src.height - window.height));
      src = Rect.fromLTWH(src.left + slack.dx * framing.x,
          src.top + slack.dy * framing.y, window.width, window.height);
      dst = frame;
  }

  // And the crop last, of what the frame is showing.
  //
  // The crop used to be taken off the picture *before* the fit, and covering
  // then re-filled the frame with whatever was left -- so cropping the top of
  // a picture that was already being trimmed top and bottom moved the picture
  // and changed nothing else, which reads as a zoom rather than as a crop.
  // Taken off the window, a quarter cropped is a quarter of what you can see,
  // every time; and the element's own frame is trimmed by the same quarter --
  // see ImageElement.croppedTo -- so what is left does not move at all.
  var window = src;
  if (!crop.isWhole && src.width > 0 && src.height > 0) {
    var kept = Rect.fromLTRB(
      src.left + src.width * crop.left,
      src.top + src.height * crop.top,
      src.left + src.width * crop.right,
      src.top + src.height * crop.bottom,
    );
    // And the same share of where it is drawn, which for a frame that was
    // trimmed with the crop is the frame itself.
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
