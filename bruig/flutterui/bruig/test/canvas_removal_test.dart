import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/render/image_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_removal_test.dart is about taking a picture's background out.
//
// Worked on raw pixels rather than through a rendered image, because that is
// where the answers are and because a photograph is not a fixture anybody can
// check into a repository. Each case below is the smallest picture that has
// the property being tested.

void main() {
  /// picture builds RGBA pixels from a paint function.
  Uint8List picture(int width, int height, Color Function(int x, int y) at) {
    var out = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var c = at(x, y);
        var i = (y * width + x) * 4;
        out[i] = (c.r * 255).round();
        out[i + 1] = (c.g * 255).round();
        out[i + 2] = (c.b * 255).round();
        out[i + 3] = 255;
      }
    }
    return out;
  }

  int alphaAt(Uint8List pixels, int width, int x, int y) =>
      pixels[(y * width + x) * 4 + 3];

  group("flood from the edges", () {
    testWidgets("a background of two very different colours goes entirely",
        (tester) async {
      // The reported fault, in miniature: a stadium shot whose background runs
      // from bright on one side to near-black on the other. Judged against one
      // seed colour, no tolerance covers both -- raise it enough to reach the
      // dark and it eats the subject, leave it low and half the background
      // stays. Each edge pixel is its own seed now.
      const size = 40;
      var pixels = picture(size, size, (x, y) {
        // A subject in the middle, a bright left half and a dark right half.
        var inSubject = x > 14 && x < 26 && y > 14 && y < 26;
        if (inSubject) return const Color(0xFF20C040);
        return x < size ~/ 2 ? const Color(0xFFF0E0F0) : const Color(0xFF101014);
      });

      applyRemovalForTest(
        pixels,
        size,
        size,
        const BackgroundRemoval(
            mode: RemovalMode.cornerFlood, tolerance: 0.06, softness: 0),
      );

      expect(alphaAt(pixels, size, 2, 20), 0, reason: "the bright side went");
      expect(alphaAt(pixels, size, 37, 20), 0, reason: "the dark side too");
      expect(alphaAt(pixels, size, 20, 20), 255,
          reason: "and the subject stayed");
    });

    testWidgets("a gradient does not walk into the subject", (tester) async {
      // The guarantee the single seed was there to give, and which the new one
      // has to keep: the reference does not drift as the flood spreads, so a
      // background shading gently towards the subject's own colour cannot
      // creep across the boundary one small step at a time.
      const size = 60;
      var pixels = picture(size, size, (x, y) {
        var inSubject = x > 24 && x < 36 && y > 24 && y < 36;
        if (inSubject) return const Color(0xFF808080);
        // Runs from black to the subject's own grey across the frame.
        var v = (x / size * 128).round();
        return Color.fromARGB(255, v, v, v);
      });

      applyRemovalForTest(
        pixels,
        size,
        size,
        const BackgroundRemoval(
            mode: RemovalMode.cornerFlood, tolerance: 0.06, softness: 0),
      );

      expect(alphaAt(pixels, size, 30, 30), 255,
          reason: "the subject survived the gradient");
    });

    testWidgets("a colour inside the subject is left alone", (tester) async {
      // What a flood has over a colour key: the white of an eye stays white
      // even when the background is white too.
      const size = 40;
      var pixels = picture(size, size, (x, y) {
        var inSubject = x > 12 && x < 28 && y > 12 && y < 28;
        var inEye = x > 18 && x < 22 && y > 18 && y < 22;
        if (inEye) return const Color(0xFFFFFFFF);
        if (inSubject) return const Color(0xFF203040);
        return const Color(0xFFFFFFFF);
      });

      applyRemovalForTest(
        pixels,
        size,
        size,
        const BackgroundRemoval(
            mode: RemovalMode.cornerFlood, tolerance: 0.05, softness: 0),
      );

      expect(alphaAt(pixels, size, 1, 1), 0, reason: "the background went");
      expect(alphaAt(pixels, size, 20, 20), 255,
          reason: "the white inside the subject did not");
    });

    testWidgets("inverting keeps the background, and nothing it merely touched",
        (tester) async {
      // Inverted, a removal keeps what it would have taken and takes what it
      // would have kept. The old mask marked every pixel the flood *looked
      // at*, rejections included -- so inverting kept the background plus a
      // halo of subject pixels the flood had bumped into on its way round.
      const size = 30;
      var pixels = picture(size, size, (x, y) {
        var inSubject = x > 10 && x < 20 && y > 10 && y < 20;
        return inSubject ? const Color(0xFF20C040) : const Color(0xFF101010);
      });

      applyRemovalForTest(
        pixels,
        size,
        size,
        const BackgroundRemoval(
            mode: RemovalMode.cornerFlood,
            tolerance: 0.05,
            softness: 0,
            invert: true),
      );

      expect(alphaAt(pixels, size, 1, 1), 255, reason: "the background is kept");
      expect(alphaAt(pixels, size, 15, 15), 0, reason: "the subject is taken");
      // The subject's own edge, which the flood examined and rejected.
      expect(alphaAt(pixels, size, 11, 11), 0,
          reason: "with no halo of everything the flood examined");
    });
  });

  group("feathering", () {
    testWidgets("softens the edge without touching either side",
        (tester) async {
      const size = 40;
      Uint8List run(double softness) {
        var pixels = picture(size, size, (x, y) {
          var inSubject = x > 14 && x < 26 && y > 14 && y < 26;
          return inSubject
              ? const Color(0xFF20C040)
              : const Color(0xFF101010);
        });
        applyRemovalForTest(
          pixels,
          size,
          size,
          BackgroundRemoval(
              mode: RemovalMode.cornerFlood,
              tolerance: 0.05,
              softness: softness),
        );
        return pixels;
      }

      var hard = run(0);
      var soft = run(0.6);

      // Somewhere on the boundary there is now a partly transparent pixel,
      // which is what a soft edge is and what hair needs.
      var partial = 0;
      for (var i = 0; i < size * size; i++) {
        var a = soft[i * 4 + 3];
        if (a > 10 && a < 245) partial++;
      }
      expect(partial, greaterThan(0));

      var hardPartial = 0;
      for (var i = 0; i < size * size; i++) {
        var a = hard[i * 4 + 3];
        if (a > 10 && a < 245) hardPartial++;
      }
      expect(hardPartial, 0, reason: "with no softness it is all or nothing");

      // The middle of the subject and the far corner are untouched: a pixel
      // whose neighbours all agree with it is left exactly as it was.
      expect(alphaAt(soft, size, 20, 20), 255);
      expect(alphaAt(soft, size, 1, 1), 0);
    });
  });

  group("the other two modes still work", () {
    testWidgets("a colour key takes the colour it was given", (tester) async {
      const size = 20;
      var pixels = picture(size, size,
          (x, y) => x < 10 ? const Color(0xFF00FF00) : const Color(0xFF993322));

      applyRemovalForTest(
        pixels,
        size,
        size,
        const BackgroundRemoval(
            mode: RemovalMode.chromaKey,
            keyColor: Color(0xFF00FF00),
            tolerance: 0.1),
      );

      expect(alphaAt(pixels, size, 2, 2), 0);
      expect(alphaAt(pixels, size, 17, 2), 255);
    });

    testWidgets("brightness cuts where it is told", (tester) async {
      const size = 20;
      var pixels = picture(size, size, (x, y) {
        var v = x < 10 ? 240 : 20;
        return Color.fromARGB(255, v, v, v);
      });

      applyRemovalForTest(
        pixels,
        size,
        size,
        const BackgroundRemoval(
            mode: RemovalMode.luminance, threshold: 0.5),
      );

      expect(alphaAt(pixels, size, 2, 2), 0, reason: "the bright half went");
      expect(alphaAt(pixels, size, 17, 2), 255);
      expect(math.max(1, 1), 1);
    });
  });
}
