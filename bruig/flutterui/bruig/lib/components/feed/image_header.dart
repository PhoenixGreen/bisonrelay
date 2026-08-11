import 'dart:typed_data';
import 'dart:ui';

// image_header.dart reads an image's dimensions out of its encoded bytes,
// without decoding it.
//
// It exists because of where the picture goes. An embedded image in the
// composer is drawn inside the text field, and a widget inside text has to
// declare how much room it needs while the line is being laid out. Image
// bytes are decoded on another thread and are not ready until afterwards, so
// an Image widget measures zero at exactly the moment the measurement is
// taken -- the line reserves nothing, and the picture then paints over the
// words above it. That was the reported fault, and it measured 0x0 with a
// position of NaN.
//
// Every format below states its size in the first few dozen bytes, so the
// answer is available immediately and the line can be built around it.

/// imageDimensions returns the pixel size declared in [bytes], or null when
/// the format is not one of the handful below or the header is truncated.
///
/// Null is a usable answer: the caller leaves the embed as readable text
/// rather than drawing a picture it cannot make room for.
Size? imageDimensions(Uint8List bytes) {
  if (bytes.length < 16) return null;
  var data = ByteData.sublistView(bytes);

  // PNG: an 8-byte signature, then the IHDR chunk, whose first two fields
  // are the dimensions.
  if (_startsWith(bytes, const [0x89, 0x50, 0x4E, 0x47])) {
    if (bytes.length < 24) return null;
    return Size(data.getUint32(16).toDouble(), data.getUint32(20).toDouble());
  }

  // GIF: "GIF87a" or "GIF89a", then width and height as little-endian
  // 16-bit values.
  if (_startsWith(bytes, const [0x47, 0x49, 0x46])) {
    return Size(data.getUint16(6, Endian.little).toDouble(),
        data.getUint16(8, Endian.little).toDouble());
  }

  // BMP: "BM", then a header whose width and height are signed 32-bit. A
  // negative height means the rows are stored top-down and is still that
  // many rows.
  if (_startsWith(bytes, const [0x42, 0x4D])) {
    if (bytes.length < 26) return null;
    return Size(data.getInt32(18, Endian.little).abs().toDouble(),
        data.getInt32(22, Endian.little).abs().toDouble());
  }

  if (_startsWith(bytes, const [0x52, 0x49, 0x46, 0x46])) {
    return _webp(bytes, data);
  }
  if (_startsWith(bytes, const [0xFF, 0xD8])) return _jpeg(bytes, data);
  return null;
}

/// _jpeg walks the marker segments looking for a start-of-frame, which is
/// the only one that carries the dimensions.
///
/// A JPEG has no fixed offset for them: the frame sits after however many
/// other segments the encoder chose to write, so the chain has to be walked.
Size? _jpeg(Uint8List bytes, ByteData data) {
  var at = 2;
  // Nine bytes, inclusive: the frame's height and width are read from
  // at+5 through at+8.
  while (at + 9 <= bytes.length) {
    if (bytes[at] != 0xFF) {
      at++; // Padding between segments is legal.
      continue;
    }
    var marker = bytes[at + 1];
    // C4, C8 and CC are numbered among the frame markers and are not
    // frames -- Huffman tables, an extension, and arithmetic coding.
    var isFrame = marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isFrame) {
      return Size(
          data.getUint16(at + 7).toDouble(), data.getUint16(at + 5).toDouble());
    }
    // Markers without a payload, which must not be treated as having a
    // length to skip over.
    if (marker == 0xD8 ||
        marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      at += 2;
      continue;
    }
    if (marker == 0xD9 || marker == 0xDA) return null; // End, or image data.
    if (at + 4 > bytes.length) return null;
    at += 2 + data.getUint16(at + 2);
  }
  return null;
}

/// _webp handles the three chunk layouts the format allows.
Size? _webp(Uint8List bytes, ByteData data) {
  if (bytes.length < 30 ||
      !_startsWith(bytes.sublist(8), const [0x57, 0x45, 0x42, 0x50])) {
    return null;
  }
  var chunk = String.fromCharCodes(bytes.sublist(12, 16));
  switch (chunk) {
    case "VP8X":
      // Canvas size, stored as 24-bit values one less than the real size.
      var w = bytes[24] | (bytes[25] << 8) | (bytes[26] << 16);
      var h = bytes[27] | (bytes[28] << 8) | (bytes[29] << 16);
      return Size((w + 1).toDouble(), (h + 1).toDouble());
    case "VP8 ":
      // A keyframe, whose dimensions are 14-bit and follow the start code.
      if (bytes.length < 30) return null;
      return Size((data.getUint16(26, Endian.little) & 0x3FFF).toDouble(),
          (data.getUint16(28, Endian.little) & 0x3FFF).toDouble());
    case "VP8L":
      // Lossless: 14 bits of width then 14 of height, packed together.
      var bits = data.getUint32(21, Endian.little);
      return Size(((bits & 0x3FFF) + 1).toDouble(),
          (((bits >> 14) & 0x3FFF) + 1).toDouble());
  }
  return null;
}

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

/// fitWithin scales [natural] down to sit inside [maxWidth] by [maxHeight],
/// keeping its shape. It never scales up: a small image drawn large is a
/// blurred one.
Size fitWithin(Size natural, double maxWidth, double maxHeight) {
  if (natural.width <= 0 || natural.height <= 0) {
    return Size(maxWidth, maxHeight);
  }
  var scale = 1.0;
  if (natural.width > maxWidth) scale = maxWidth / natural.width;
  if (natural.height * scale > maxHeight) scale = maxHeight / natural.height;
  return Size(natural.width * scale, natural.height * scale);
}
