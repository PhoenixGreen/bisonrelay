import 'dart:typed_data';
import 'dart:ui';

import 'package:bruig/components/feed/image_header.dart';
import 'package:flutter_test/flutter_test.dart';

// image_header_test.dart covers reading an image's size out of its bytes.
//
// This exists for one reason: a picture drawn inside the composer's text has
// to say how much room it needs while the line is being measured, and an
// Image widget cannot -- its bytes are decoded afterwards, so it measures
// zero at exactly the wrong moment. Reported as the image sitting over the
// text at the top of the page; measured as a size of 0x0 at a position of
// NaN.
//
// The headers below are built by hand rather than loaded, so each test says
// exactly which bytes the answer comes from.

Uint8List _bytes(List<int> b) => Uint8List.fromList(b);

void main() {
  test("PNG", () {
    var png = _bytes([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
      0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, // length, "IHDR"
      0, 0, 1, 0x90, // width 400
      0, 0, 0, 0xC8, // height 200
    ]);
    expect(imageDimensions(png), const Size(400, 200));
  });

  test("GIF, whose dimensions are little-endian", () {
    var gif = _bytes([
      0x47, 0x49, 0x46, 0x38, 0x39, 0x61, // "GIF89a"
      0x90, 0x01, // width 400
      0xC8, 0x00, // height 200
      0, 0, 0, 0, 0, 0,
    ]);
    expect(imageDimensions(gif), const Size(400, 200));
  });

  group("BMP", () {
    Uint8List bmp(int height) {
      var b = List<int>.filled(30, 0);
      b[0] = 0x42;
      b[1] = 0x4D;
      var d = ByteData.sublistView(Uint8List.fromList(b));
      d.setInt32(18, 400, Endian.little);
      d.setInt32(22, height, Endian.little);
      return d.buffer.asUint8List();
    }

    test("top-up rows", () => expect(imageDimensions(bmp(200)), const Size(400, 200)));

    // A negative height means the rows are stored the other way up. It is
    // still that many rows, and a picture cannot be -200 pixels tall.
    test("a negative height is still a height",
        () => expect(imageDimensions(bmp(-200)), const Size(400, 200)));
  });

  group("JPEG", () {
    // A JPEG states its size in a start-of-frame segment, which sits after
    // however many other segments the encoder chose to write -- so the chain
    // has to be walked rather than indexed into.
    test("a frame after another segment", () {
      var jpeg = _bytes([
        0xFF, 0xD8, // start of image
        0xFF, 0xE0, 0x00, 0x06, 1, 2, 3, 4, // an APP0 of length 6, skipped
        0xFF, 0xC0, 0x00, 0x11, 0x08, // start of frame
        0x00, 0xC8, // height 200
        0x01, 0x90, // width 400
      ]);
      expect(imageDimensions(jpeg), const Size(400, 200));
    });

    // C4 is numbered among the frame markers and is a Huffman table. Reading
    // it as a frame returns whatever two numbers happen to follow.
    test("a Huffman table is not a frame", () {
      var jpeg = _bytes([
        0xFF, 0xD8,
        0xFF, 0xC4, 0x00, 0x06, 9, 9, 9, 9, // DHT, must be skipped
        0xFF, 0xC0, 0x00, 0x11, 0x08,
        0x00, 0x64, // height 100
        0x00, 0xC8, // width 200
      ]);
      expect(imageDimensions(jpeg), const Size(200, 100));
    });

    test("no frame at all is no answer", () {
      expect(imageDimensions(_bytes([0xFF, 0xD8, ...List.filled(30, 0)])), isNull);
    });
  });

  test("WebP in its extended form", () {
    var b = List<int>.filled(32, 0);
    b.setRange(0, 4, [0x52, 0x49, 0x46, 0x46]); // "RIFF"
    b.setRange(8, 12, [0x57, 0x45, 0x42, 0x50]); // "WEBP"
    b.setRange(12, 16, [0x56, 0x50, 0x38, 0x58]); // "VP8X"
    // Canvas size is stored one less than the real size, 24 bits each.
    b.setRange(24, 27, [399 & 0xFF, (399 >> 8) & 0xFF, 0]);
    b.setRange(27, 30, [199 & 0xFF, (199 >> 8) & 0xFF, 0]);
    expect(imageDimensions(_bytes(b)), const Size(400, 200));
  });

  group("nothing to answer with", () {
    test("an unknown format", () {
      expect(imageDimensions(_bytes(List.filled(40, 0x7F))), isNull);
    });
    test("a truncated header", () {
      expect(imageDimensions(_bytes([0x89, 0x50, 0x4E, 0x47])), isNull);
    });
    test("nothing at all", () => expect(imageDimensions(_bytes([])), isNull));
  });

  group("fitting it on the page", () {
    test("something too wide is scaled down, keeping its shape", () {
      var got = fitWithin(const Size(800, 400), 420, 260);
      expect(got.width, 420);
      expect(got.height, 210);
    });

    test("something too tall is bounded by its height", () {
      var got = fitWithin(const Size(400, 800), 420, 260);
      expect(got.height, 260);
      expect(got.width, closeTo(130, 0.01));
    });

    // A small picture blown up to fill the space is a blurred one.
    test("something small is left alone", () {
      expect(fitWithin(const Size(40, 20), 420, 260), const Size(40, 20));
    });
  });
}
