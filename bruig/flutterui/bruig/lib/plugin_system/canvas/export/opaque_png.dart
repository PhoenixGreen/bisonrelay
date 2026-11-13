import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;

/// opaquePng is [rgba] (straight, width by height) as a PNG with no alpha
/// channel: a book's cover. Flutter's own PNGs always carry alpha, and an
/// e-reader's library makes its thumbnail from the cover; one without
/// transparency leaves it nothing to guess about.
Uint8List opaquePng(Uint8List rgba, int width, int height) {
  // Each row: filter 0 (none), then its pixels' red, green and blue, laid
  // over black where they are not wholly opaque.
  var rows = Uint8List((width * 3 + 1) * height);
  var o = 0, i = 0;
  for (var y = 0; y < height; y++) {
    rows[o++] = 0;
    for (var x = 0; x < width; x++, i += 4) {
      var a = rgba[i + 3];
      rows[o++] = rgba[i] * a ~/ 255;
      rows[o++] = rgba[i + 1] * a ~/ 255;
      rows[o++] = rgba[i + 2] * a ~/ 255;
    }
  }
  var out = BytesBuilder(copy: false)
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    var body = BytesBuilder(copy: false)
      ..add(type.codeUnits)
      ..add(data);
    var bytes = body.takeBytes();
    out
      ..add(_be32(data.length))
      ..add(bytes)
      ..add(_be32(getCrc32(bytes)));
  }

  chunk("IHDR", [
    ..._be32(width), ..._be32(height),
    8, // bits per sample
    2, // truecolour, no alpha
    0, 0, 0, // deflate, adaptive filtering, not interlaced
  ]);
  chunk("IDAT", ZLibCodec(level: 6).encode(rows));
  chunk("IEND", const []);
  return out.takeBytes();
}

List<int> _be32(int v) =>
    [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
