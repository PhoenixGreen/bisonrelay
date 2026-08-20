import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/components/feed/image_header.dart';
import 'package:bruig/components/md_elements.dart';
import 'package:image_compression_flutter/image_compression_flutter.dart';

// embed_options.dart shrinks a picture before it goes into a post.
//
// Two separate things, applied in that order, because the order is most of
// the point. Scaling a 2000-pixel-wide photograph down to 1000 throws away
// three quarters of the pixels; compressing what is left is then working on
// a quarter as much data, and the quality setting means what it says about
// the picture that will actually be seen. Compressing first and scaling
// afterwards spends effort on detail that is about to be discarded, and
// leaves the quality figure describing an image nobody will look at.

/// EmbedOptions is how much of a picture to keep.
class EmbedOptions {
  /// maxWidth is the widest the picture may be, or null to leave it alone.
  ///
  /// A bound rather than a size: a picture already narrower than this is
  /// untouched, because scaling one up produces a larger file that looks
  /// worse than the original.
  final int? maxWidth;

  /// quality runs from 1 to 100. 100 means leave the encoding alone.
  final int quality;

  const EmbedOptions({this.maxWidth, this.quality = 100});

  /// none is the original bytes, unchanged.
  static const none = EmbedOptions();

  bool get changesAnything => maxWidth != null || quality < 100;

  EmbedOptions copyWith(
          {int? maxWidth, bool clearMaxWidth = false, int? quality}) =>
      EmbedOptions(
        maxWidth: clearMaxWidth ? null : (maxWidth ?? this.maxWidth),
        quality: quality ?? this.quality,
      );
}

/// PreparedEmbed is what came back, with what it took to get there.
class PreparedEmbed {
  final Uint8List data;
  final String mime;

  /// width and height of the result, or null when it could not be read.
  final int? width;
  final int? height;

  const PreparedEmbed(this.data, this.mime, {this.width, this.height});
}

/// prepareEmbed applies [options] to [original].
///
/// Anything that is not an image is returned untouched: there is no sense in
/// which a text attachment has a width.
///
/// Every failure returns the original rather than throwing. A picture that
/// cannot be scaled is still a picture the writer asked to include, and
/// refusing the whole embed because it could not be made smaller would be
/// answering a question nobody asked.
Future<PreparedEmbed> prepareEmbed(
  Uint8List original,
  String mime,
  EmbedOptions options,
) async {
  if (!mime.startsWith("image/")) return PreparedEmbed(original, mime);

  // A vector has no pixels to scale or quality to trade away, and putting
  // one through the decoder would only turn a few kilobytes of markup into
  // a bitmap of whatever size it happened to be drawn at.
  if (isSvgMime(mime)) return PreparedEmbed(original, mime);

  var natural = imageDimensions(original);
  var data = original;
  var out = mime;

  var target = options.maxWidth;
  if (target != null && natural != null && natural.width > target) {
    var scaled = await _scaleToWidth(data, target);
    if (scaled != null) {
      data = scaled;
      // Scaling goes through the decoder and comes back as PNG, which is
      // lossless and usually larger than what went in. That is fine only
      // because compression follows; on its own it would make some files
      // bigger, which is why quality below 100 is the sensible default.
      out = "image/png";
    }
  }

  // Compression encodes to JPEG, which has no alpha channel: a picture with
  // anything see-through in it comes back with the transparency filled in,
  // usually black. That is right for a photograph and wrong for a logo, and
  // the writer is not told -- so a picture that uses transparency keeps the
  // format it arrived in, whatever the quality setting says.
  //
  // Checked rather than assumed from the format. Most PNGs are opaque
  // screenshots, which are exactly what the quality setting is for, and
  // refusing to compress every PNG would give that up for the few that
  // need it.
  var transparent = await hasTransparency(data);
  if (options.quality < 100 && !transparent) {
    var compressed = await _compress(data, options.quality);
    if (compressed != null) {
      data = compressed;
      out = "image/jpeg";
    }
  }

  var size = imageDimensions(data);
  return PreparedEmbed(data, out,
      width: size?.width.round(), height: size?.height.round());
}

/// hasTransparency is whether any pixel is less than fully opaque.
///
/// Decoded and scanned rather than read out of the file's header: the header
/// says whether a format *can* carry transparency, not whether this picture
/// uses any, and most PNGs are opaque. Stops at the first see-through pixel,
/// so a logo with a clear corner costs almost nothing to detect.
///
/// A picture that cannot be decoded is treated as transparent, which is the
/// safe way to be wrong: the worst case is a file that could have been
/// smaller, rather than one that comes back with black behind it.
Future<bool> hasTransparency(Uint8List bytes) async {
  ui.Codec? codec;
  try {
    codec = await ui.instantiateImageCodec(bytes);
    var frame = await codec.getNextFrame();
    var raw = await frame.image
        .toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    frame.image.dispose();
    if (raw == null) return true;

    var data = raw.buffer.asUint8List();
    for (var i = 3; i < data.length; i += 4) {
      if (data[i] != 255) return true;
    }
    return false;
  } catch (_) {
    return true;
  } finally {
    codec?.dispose();
  }
}

/// _scaleToWidth decodes at the requested width and re-encodes.
///
/// Only the width is given to the decoder, which is what keeps the shape:
/// naming one dimension leaves the other to follow from the original's
/// proportions. A 2000x1000 picture asked for 1000 comes back 1000x500.
Future<Uint8List?> _scaleToWidth(Uint8List bytes, int width) async {
  ui.Codec? codec;
  try {
    codec = await ui.instantiateImageCodec(bytes, targetWidth: width);
    var frame = await codec.getNextFrame();
    var png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    return png?.buffer.asUint8List();
  } catch (_) {
    return null;
  } finally {
    codec?.dispose();
  }
}

Future<Uint8List?> _compress(Uint8List bytes, int quality) async {
  try {
    var output = await compressor.compress(ImageFileConfiguration(
      // The name is only what the compressor calls the thing; nothing is
      // read from or written to disk here.
      input: ImageFile(filePath: "embed", rawBytes: bytes),
      config: Configuration(
        useJpgPngNativeCompressor: false,
        outputType: ImageOutputType.jpg,
        quality: quality,
      ),
    ));
    return output.rawBytes;
  } catch (_) {
    return null;
  }
}
