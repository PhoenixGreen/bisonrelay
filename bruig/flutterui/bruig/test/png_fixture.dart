import 'dart:io';
import 'dart:typed_data';

// png_fixture.dart builds a real PNG of a given size, for tests that need
// one to be scaled or compressed.
//
// Built rather than checked in. The pictures these tests need are large
// enough to be worth measuring -- a 2000 pixel wide photograph -- and a
// base64 string of one in a source file is most of a megabyte that nobody
// can read or adjust.

/// pngOf returns a [width] by [height] PNG with a pattern in it.
///
/// A pattern rather than one flat colour, because a flat colour compresses
/// to almost nothing in either format and a test that a picture got smaller
/// would then be measuring noise.
Uint8List pngOf(int width, int height) {
  var raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0); // No per-row filter.
    for (var x = 0; x < width; x++) {
      raw.add([(x * 7) % 256, (y * 5) % 256, (x * y) % 256]);
    }
  }

  var out = BytesBuilder();
  out.add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  var ihdr = BytesBuilder();
  ihdr.add(_uint32(width));
  ihdr.add(_uint32(height));
  ihdr.add([8, 2, 0, 0, 0]); // 8 bits per channel, truecolour.
  out.add(_chunk("IHDR", ihdr.takeBytes()));
  out.add(_chunk("IDAT", Uint8List.fromList(zlib.encode(raw.takeBytes()))));
  out.add(_chunk("IEND", Uint8List(0)));
  return out.takeBytes();
}

Uint8List _uint32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v);

Uint8List _chunk(String type, Uint8List data) {
  var body = BytesBuilder()
    ..add(type.codeUnits)
    ..add(data);
  var bytes = body.takeBytes();
  return Uint8List.fromList(
      [..._uint32(data.length), ...bytes, ..._uint32(_crc32(bytes))]);
}

/// _crc32 is the checksum every PNG chunk carries. Written out rather than
/// reached for, because the one package that has it is not a dependency and
/// a checksum is twelve lines.
int _crc32(Uint8List bytes) {
  var crc = 0xFFFFFFFF;
  for (var byte in bytes) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
