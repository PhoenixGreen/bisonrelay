import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/gif_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_gif_test.dart checks the GIF encoder by decoding what it writes.
//
// The encoder is written out by hand -- palette, dithering and LZW -- because
// there is no Flutter-native one. Hand-written LZW is exactly the kind of code
// that produces a file which looks plausible, passes a header check, and is
// rejected or drawn as garbage by every real decoder. So these tests do not
// inspect bytes beyond the header: they hand the result to Flutter's own image
// codec and look at the pixels that come back.

/// _solid is one frame of a single colour.
GifFrame _solid(int width, int height, int r, int g, int b,
    {int delayMs = 100}) {
  var rgba = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    rgba[i * 4] = r;
    rgba[i * 4 + 1] = g;
    rgba[i * 4 + 2] = b;
    rgba[i * 4 + 3] = 255;
  }
  return GifFrame(rgba: rgba, width: width, height: height, delayMs: delayMs);
}

/// _gradient is a frame that a 256-colour palette cannot hold exactly, which
/// is what exercises the quantiser and the dither.
GifFrame _gradient(int width, int height) {
  var rgba = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var i = (y * width + x) * 4;
      rgba[i] = (x * 255 ~/ (width - 1));
      rgba[i + 1] = (y * 255 ~/ (height - 1));
      rgba[i + 2] = 128;
      rgba[i + 3] = 255;
    }
  }
  return GifFrame(rgba: rgba, width: width, height: height, delayMs: 80);
}

Future<ui.Codec> _decode(Uint8List bytes) => ui.instantiateImageCodec(bytes);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("an empty list produces nothing rather than a broken file", () {
    expect(encodeGif(const []), isEmpty);
  });

  test("a single frame decodes to the right size and colour", () async {
    var bytes = encodeGif([_solid(8, 6, 200, 30, 40)]);

    expect(String.fromCharCodes(bytes.sublist(0, 6)), "GIF89a");
    expect(bytes.last, 0x3B, reason: "the file must end with the trailer");

    var codec = await _decode(bytes);
    expect(codec.frameCount, 1);

    var frame = await codec.getNextFrame();
    expect(frame.image.width, 8);
    expect(frame.image.height, 6);

    var raw = await frame.image
        .toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    var pixels = raw!.buffer.asUint8List();
    // Every pixel is the one colour that went in. Exact, because a palette of
    // 256 has ample room for one.
    for (var i = 0; i < 8 * 6; i++) {
      expect(pixels[i * 4], 200, reason: "red at $i");
      expect(pixels[i * 4 + 1], 30, reason: "green at $i");
      expect(pixels[i * 4 + 2], 40, reason: "blue at $i");
    }
    frame.image.dispose();
    codec.dispose();
  });

  test("several frames decode, in order, with their colours", () async {
    var bytes = encodeGif([
      _solid(4, 4, 255, 0, 0),
      _solid(4, 4, 0, 255, 0),
      _solid(4, 4, 0, 0, 255),
    ], dither: false);

    var codec = await _decode(bytes);
    expect(codec.frameCount, 3);

    for (var expected in [
      [255, 0, 0],
      [0, 255, 0],
      [0, 0, 255],
    ]) {
      var frame = await codec.getNextFrame();
      var raw = await frame.image
          .toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      var pixels = raw!.buffer.asUint8List();
      expect([pixels[0], pixels[1], pixels[2]], expected);
      frame.image.dispose();
    }
    codec.dispose();
  });

  test("a gradient survives quantisation closely enough", () async {
    // 256 colours cannot hold a 64x64 two-axis gradient exactly. What is
    // checked is that it is close -- a broken LZW or a broken palette gives
    // noise, not a slightly-off gradient.
    var bytes = encodeGif([_gradient(64, 64)]);
    var codec = await _decode(bytes);
    var frame = await codec.getNextFrame();
    var raw = await frame.image
        .toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    var pixels = raw!.buffer.asUint8List();

    for (var (x, y) in [(0, 0), (63, 0), (0, 63), (63, 63), (32, 32)]) {
      var i = (y * 64 + x) * 4;
      expect(pixels[i], closeTo(x * 255 / 63, 24), reason: "red at $x,$y");
      expect(pixels[i + 1], closeTo(y * 255 / 63, 24),
          reason: "green at $x,$y");
    }
    frame.image.dispose();
    codec.dispose();
  });

  test("transparency comes back as transparency", () async {
    var frame = _solid(4, 4, 10, 200, 90);
    // Make the top-left pixel see-through. GIF has one bit of alpha, so this
    // has to come back fully clear rather than dimmed.
    frame.rgba[3] = 0;

    var bytes = encodeGif([frame], dither: false);
    var codec = await _decode(bytes);
    var decoded = await codec.getNextFrame();
    var raw = await decoded.image
        .toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    var pixels = raw!.buffer.asUint8List();

    expect(pixels[3], 0, reason: "the cut-out pixel should be clear");
    expect(pixels[7], 255, reason: "its neighbour should not be");
    decoded.image.dispose();
    codec.dispose();
  });

  test("a reduced palette still decodes", () async {
    // The smallest palette the encoder offers is where an off-by-one in the
    // code width would show up: fewer colours means a narrower minimum code
    // size, which is the LZW parameter most easily got wrong.
    for (var colors in [2, 4, 16, 64, 128, 256]) {
      var bytes = encodeGif([_gradient(32, 32)], maxColors: colors);
      var codec = await _decode(bytes);
      expect(codec.frameCount, 1, reason: "at $colors colours");
      var frame = await codec.getNextFrame();
      expect(frame.image.width, 32, reason: "at $colors colours");
      frame.image.dispose();
      codec.dispose();
    }
  });

  test("dithering changes the pixels but not the size or the shape", () async {
    var plain = encodeGif([_gradient(48, 48)], dither: false);
    var dithered = encodeGif([_gradient(48, 48)], dither: true);
    expect(plain, isNot(equals(dithered)));

    for (var bytes in [plain, dithered]) {
      var codec = await _decode(bytes);
      var frame = await codec.getNextFrame();
      expect(frame.image.width, 48);
      expect(frame.image.height, 48);
      frame.image.dispose();
      codec.dispose();
    }
  });

  test("an animation carries the loop extension and a still does not", () {
    var one = encodeGif([_solid(2, 2, 1, 2, 3)]);
    var many = encodeGif([_solid(2, 2, 1, 2, 3), _solid(2, 2, 3, 2, 1)]);

    bool hasNetscape(Uint8List bytes) {
      var needle = "NETSCAPE2.0".codeUnits;
      for (var i = 0; i + needle.length <= bytes.length; i++) {
        var match = true;
        for (var j = 0; j < needle.length; j++) {
          if (bytes[i + j] != needle[j]) {
            match = false;
            break;
          }
        }
        if (match) return true;
      }
      return false;
    }

    expect(hasNetscape(many), isTrue);
    // A still needs no loop block, and putting one in a single-frame GIF makes
    // some viewers treat it as an animation of one frame.
    expect(hasNetscape(one), isFalse);
  });

  test("a large frame does not run the dictionary off the end", () async {
    // The LZW dictionary fills at 4096 codes and has to be cleared. A frame
    // large and varied enough to reach that is the only way to exercise the
    // branch, and getting it wrong produces a file that decodes correctly for
    // the first few thousand pixels and then turns to noise.
    var frame = _gradient(200, 200);
    var codec = await _decode(encodeGif([frame]));
    var decoded = await codec.getNextFrame();
    var raw = await decoded.image
        .toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    var pixels = raw!.buffer.asUint8List();

    // The very last pixel, which is only right if the whole stream decoded.
    var last = (199 * 200 + 199) * 4;
    expect(pixels[last], closeTo(255, 24));
    expect(pixels[last + 1], closeTo(255, 24));
    decoded.image.dispose();
    codec.dispose();
  });
}
