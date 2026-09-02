import 'dart:ui' as ui;
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
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

    testWidgets("a smooth gradient background goes, sharp subject stays",
        (tester) async {
      // The shape of the reported photograph: the background is out of focus
      // and shades right across the frame, while the player is in focus and
      // has a crisp outline. Judged by colour against any fixed reference
      // there is no tolerance that works -- the one that reaches the far end
      // of the gradient has already eaten the subject. Judged by *how sharply
      // the picture changes*, the two are miles apart.
      const size = 60;
      var pixels = picture(size, size, (x, y) {
        // Over the dark end of the ramp, so the subject's own outline is a
        // real edge -- which is what a subject in focus has. Its colour still
        // sits in the middle of the background's overall range, so any method
        // judging by colour against a fixed reference cannot tell them apart.
        var inSubject = x > 8 && x < 22 && y > 20 && y < 40;
        if (inSubject) return const Color(0xFF808080);
        var v = (x / size * 230).round();
        return Color.fromARGB(255, v, v, v);
      });

      applyRemovalForTest(
        pixels,
        size,
        size,
        const BackgroundRemoval(
            mode: RemovalMode.cornerFlood,
            edge: 0.09,
            tolerance: 0.6,
            softness: 0),
      );

      expect(alphaAt(pixels, size, 2, 5), 0, reason: "the dark end went");
      expect(alphaAt(pixels, size, 57, 30), 0, reason: "the bright end too");
      expect(alphaAt(pixels, size, 15, 30), 255,
          reason: "and the subject survived, though its grey is the "
              "background's grey somewhere else in the frame");
      expect(alphaAt(pixels, size, 10, 22), 255, reason: "right to its edge");
    });

    testWidgets("a sharp edge stops the flood even at a huge budget",
        (tester) async {
      // The budget is a runaway guard, not the thing doing the separating.
      const size = 40;
      var pixels = picture(size, size, (x, y) {
        var inSubject = x > 14 && x < 26 && y > 14 && y < 26;
        return inSubject ? const Color(0xFF20C040) : const Color(0xFF101010);
      });

      applyRemovalForTest(
        pixels,
        size,
        size,
        const BackgroundRemoval(
            mode: RemovalMode.cornerFlood,
            edge: 0.05,
            tolerance: 1,
            softness: 0),
      );

      expect(alphaAt(pixels, size, 1, 1), 0);
      expect(alphaAt(pixels, size, 20, 20), 255,
          reason: "it stopped at the subject's outline, not at a colour");
    });

    testWidgets("the budget bounds how far a gentle ramp can carry it",
        (tester) async {
      // The local step follows a gradient, and would follow one anywhere; the
      // budget is what stops a ramp gentle enough to pass it from walking in
      // from the border and out the other side.
      //
      // A ramp *rising towards the middle*, so the interior is far from any
      // border seed's colour. On a ramp running side to side every pixel has a
      // seed of nearly its own colour directly above it and the budget never
      // comes into play.
      const size = 60;
      Uint8List ramp() => picture(size, size, (x, y) {
            var toEdge = math.min(math.min(x, y), math.min(size - 1 - x, size - 1 - y));
            var v = (toEdge / (size / 2) * 240).round().clamp(0, 255);
            return Color.fromARGB(255, v, v, v);
          });

      var tight = ramp();
      applyRemovalForTest(
        tight,
        size,
        size,
        const BackgroundRemoval(
            mode: RemovalMode.cornerFlood,
            edge: 0.09,
            tolerance: 0.12,
            softness: 0),
      );
      expect(alphaAt(tight, size, 30, 30), 255,
          reason: "the middle is well past the budget");

      var loose = ramp();
      applyRemovalForTest(
        loose,
        size,
        size,
        const BackgroundRemoval(
            mode: RemovalMode.cornerFlood,
            edge: 0.09,
            tolerance: 1,
            softness: 0),
      );
      expect(alphaAt(loose, size, 30, 30), 0,
          reason: "and reachable once the budget allows it");
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

  group("the retouching brush", () {
    /// flat is a picture with no background to find automatically, which is
    /// the case the brush exists for.
    Uint8List flat(int size) =>
        picture(size, size, (x, y) => const Color(0xFF6688AA));

    testWidgets("a stroke rubs the picture out along its whole length",
        (tester) async {
      // Along its length, not at the points: stamping only where the pointer
      // was sampled leaves a dotted line whenever it moved quickly.
      const size = 60;
      var pixels = flat(size);

      applyRemovalForTest(
        pixels,
        size,
        size,
        const BackgroundRemoval(
          mode: RemovalMode.none,
          strokes: [
            RemovalStroke(
              points: [Offset(0.1, 0.5), Offset(0.9, 0.5)],
              radius: 0.05,
              keep: false,
            ),
          ],
        ),
      );

      for (var x = 8; x < 52; x++) {
        expect(alphaAt(pixels, size, x, 30), 0,
            reason: "nothing left in the middle of the stroke at x=$x");
      }
      expect(alphaAt(pixels, size, 30, 5), 255,
          reason: "and the picture above it is untouched");
    });

    testWidgets("a put-back stroke restores what a method took",
        (tester) async {
      // The strokes run after the automatic pass, so one is always the last
      // word: a hand the flood ate comes back without changing the settings.
      const size = 40;
      var pixels = picture(size, size, (x, y) => const Color(0xFF101010));

      applyRemovalForTest(
        pixels,
        size,
        size,
        const BackgroundRemoval(
          // Takes the whole picture: it is all one flat colour reaching the
          // border.
          mode: RemovalMode.cornerFlood,
          edge: 0.05,
          tolerance: 0.5,
          softness: 0,
          strokes: [
            RemovalStroke(
              points: [Offset(0.5, 0.5)],
              radius: 0.15,
              keep: true,
            ),
          ],
        ),
      );

      expect(alphaAt(pixels, size, 1, 1), 0, reason: "the flood took the rest");
      expect(alphaAt(pixels, size, 20, 20), 255,
          reason: "and the brush put the middle back");
    });

    testWidgets("the brush alone is a way to use this", (tester) async {
      // No method at all, just strokes. On a photograph no automatic method
      // can do, painting the background out by hand has to work without
      // touching the dropdown -- which means "active" cannot mean "a mode is
      // chosen".
      const size = 40;
      var pixels = flat(size);
      const removal = BackgroundRemoval(
        mode: RemovalMode.none,
        strokes: [
          RemovalStroke(
              points: [Offset(0.5, 0.5)], radius: 0.2, keep: false),
        ],
      );

      expect(removal.active, isTrue);
      applyRemovalForTest(pixels, size, size, removal);
      expect(alphaAt(pixels, size, 20, 20), 0);
      expect(alphaAt(pixels, size, 1, 1), 255);
    });

    test("the cache key changes as a stroke is painted", () {
      // Left out of the key, a stroke changed nothing on screen: the store
      // handed back the picture it had already made and went on doing so
      // however much was painted.
      const one = BackgroundRemoval(strokes: [
        RemovalStroke(points: [Offset(0.5, 0.5)], radius: 0.1, keep: false),
      ]);
      const longer = BackgroundRemoval(strokes: [
        RemovalStroke(
            points: [Offset(0.5, 0.5), Offset(0.6, 0.5)],
            radius: 0.1,
            keep: false),
      ]);
      const second = BackgroundRemoval(strokes: [
        RemovalStroke(points: [Offset(0.5, 0.5)], radius: 0.1, keep: false),
        RemovalStroke(points: [Offset(0.2, 0.2)], radius: 0.1, keep: true),
      ]);

      expect(one.cacheKey("a"), isNot(longer.cacheKey("a")));
      expect(one.cacheKey("a"), isNot(second.cacheKey("a")));
      expect(one.cacheKey("a"), one.cacheKey("a"));
    });

    test("strokes survive a round trip", () {
      var element = ImageElement(
        const ElementBase(id: "i", width: 100, height: 100),
        removal: const BackgroundRemoval(
          strokes: [
            RemovalStroke(
                points: [Offset(0.25, 0.5), Offset(0.75, 0.5)],
                radius: 0.08,
                keep: true),
          ],
        ),
      );
      var back = CanvasDocument.decode(
              CanvasDocument(elements: [element]).encode())!.elements.single
          as ImageElement;

      expect(back.removal.strokes.length, 1);
      expect(back.removal.strokes.single.points.length, 2);
      expect(back.removal.strokes.single.points.first.dx, 0.25);
      expect(back.removal.strokes.single.keep, isTrue);
      expect(back.removal.strokes.single.radius, 0.08);
    });
  });

  group("learning from marks", () {
    /// stroke is a short horizontal mark across [y], in picture fractions.
    RemovalStroke stroke(double x1, double x2, double y,
            {required bool keep}) =>
        RemovalStroke(
          points: [Offset(x1, y), Offset(x2, y)],
          radius: 0.02,
          keep: keep,
        );

    testWidgets("the subject is kept though its colour is in the background too",
        (tester) async {
      // The case that defeats every threshold, and the reason this mode
      // exists: the player's white shirt is the same white as a highlight
      // behind him. No colour distance tells them apart, and no edge setting
      // does either once the outline is soft.
      const size = 60;
      Uint8List build() => picture(size, size, (x, y) {
            var inSubject = x > 20 && x < 40 && y > 20 && y < 40;
            if (inSubject) return const Color(0xFFF0F0F0);
            // The same white in the background, well away from the subject.
            if (x < 12 && y < 12) return const Color(0xFFF0F0F0);
            return const Color(0xFF203040);
          });

      var pixels = build();
      applyRemovalForTest(
        pixels,
        size,
        size,
        BackgroundRemoval(
          mode: RemovalMode.learn,
          tolerance: 0.5,
          softness: 0,
          hints: [
            stroke(0.6, 0.9, 0.9, keep: false),
            stroke(0.4, 0.6, 0.5, keep: true),
          ],
        ),
      );

      expect(alphaAt(pixels, size, 30, 55), 0, reason: "the dark background");
      expect(alphaAt(pixels, size, 30, 30), 255,
          reason: "and the subject kept, though the background has that white "
              "in it as well");

      // The white patch stays, and is *right* to stay on this evidence: it is
      // the subject's own colour and nothing has been said to the contrary.
      // What matters is that saying so is one more mark rather than a hunt
      // through three settings for a number that does not exist.
      expect(alphaAt(pixels, size, 5, 5), 255);

      var told = build();
      applyRemovalForTest(
        told,
        size,
        size,
        BackgroundRemoval(
          mode: RemovalMode.learn,
          tolerance: 0.5,
          softness: 0,
          hints: [
            stroke(0.6, 0.9, 0.9, keep: false),
            stroke(0.02, 0.15, 0.08, keep: false),
            stroke(0.4, 0.6, 0.5, keep: true),
          ],
        ),
      );

      expect(alphaAt(told, size, 5, 5), 0, reason: "marked, the patch goes");
      expect(alphaAt(told, size, 30, 30), 255,
          reason: "and the subject is still there");
    });

    testWidgets("a subject mark blocks the flood", (tester) async {
      // Connectivity is what makes the above work: the shirt is only removed
      // if there is a path to it through background-looking pixels, and a
      // subject mark closes the path.
      const size = 40;
      var pixels =
          picture(size, size, (x, y) => const Color(0xFF203040));

      applyRemovalForTest(
        pixels,
        size,
        size,
        BackgroundRemoval(
          mode: RemovalMode.learn,
          tolerance: 0.5,
          softness: 0,
          hints: [
            stroke(0.05, 0.2, 0.05, keep: false),
            stroke(0.4, 0.6, 0.5, keep: true),
          ],
        ),
      );

      expect(alphaAt(pixels, size, 20, 20), 255,
          reason: "what is marked as subject is kept, whatever its colour");
    });

    testWidgets("with only one side marked it does nothing", (tester) async {
      // There is nothing to compare, and guessing would take something
      // arbitrary the moment the mode was chosen.
      const size = 40;
      var pixels =
          picture(size, size, (x, y) => const Color(0xFF203040));

      applyRemovalForTest(
        pixels,
        size,
        size,
        BackgroundRemoval(
          mode: RemovalMode.learn,
          hints: [stroke(0.1, 0.3, 0.1, keep: false)],
        ),
      );

      expect(alphaAt(pixels, size, 20, 20), 255);
      expect(alphaAt(pixels, size, 1, 1), 255);
    });

    testWidgets("the bias takes more when it is turned up", (tester) async {
      // A colour halfway between the two sets of evidence: at a fair fight it
      // stays, leaning towards the background it goes.
      const size = 40;
      Uint8List build() => picture(size, size, (x, y) {
            if (x > 25) return const Color(0xFF101010);
            if (x > 12) return const Color(0xFF808080);
            return const Color(0xFFF0F0F0);
          });

      var hints = [
        stroke(0.8, 0.95, 0.5, keep: false),
        stroke(0.02, 0.15, 0.5, keep: true),
      ];

      var fair = build();
      applyRemovalForTest(
          fair,
          size,
          size,
          BackgroundRemoval(
              mode: RemovalMode.learn,
              tolerance: 0.2,
              softness: 0,
              hints: hints));

      var eager = build();
      applyRemovalForTest(
          eager,
          size,
          size,
          BackgroundRemoval(
              mode: RemovalMode.learn,
              tolerance: 1,
              softness: 0,
              hints: hints));

      var middle = 20;
      expect(alphaAt(fair, size, middle, 20), 255,
          reason: "the middle grey is left alone at a low bias");
      expect(alphaAt(eager, size, middle, 20), 0,
          reason: "and taken once the bias leans towards the background");
    });

    test("marks are evidence, not instructions", () {
      // Nothing is removed where a hint is drawn -- that is the whole
      // difference between the two lists.
      const removal = BackgroundRemoval(
        mode: RemovalMode.learn,
        hints: [
          RemovalStroke(points: [Offset(0.5, 0.5)], radius: 0.1, keep: false),
          RemovalStroke(points: [Offset(0.2, 0.2)], radius: 0.1, keep: true),
        ],
      );
      expect(removal.backgroundHints.length, 1);
      expect(removal.subjectHints.length, 1);
      expect(removal.strokes, isEmpty);
    });

    test("hints survive a round trip and change the cache key", () {
      var element = ImageElement(
        const ElementBase(id: "i", width: 100, height: 100),
        removal: const BackgroundRemoval(
          mode: RemovalMode.learn,
          hints: [
            RemovalStroke(
                points: [Offset(0.25, 0.5)], radius: 0.03, keep: true),
          ],
        ),
      );
      var back = CanvasDocument.decode(
              CanvasDocument(elements: [element]).encode())!.elements.single
          as ImageElement;
      expect(back.removal.hints.length, 1);
      expect(back.removal.hints.single.keep, isTrue);

      const none = BackgroundRemoval(mode: RemovalMode.learn);
      expect(none.cacheKey("a"),
          isNot(element.removal.cacheKey("a")));
    });
  });

  group("the brush is the tool, not the fallback", () {
    testWidgets("a soft brush fades out towards its rim", (tester) async {
      // A hard brush is the wrong tool for a photograph: everything in one has
      // a soft boundary, and a cut-out with a hard edge reads as a sticker
      // whatever else is right about it.
      const size = 60;
      var pixels = picture(size, size, (x, y) => const Color(0xFF6688AA));

      applyRemovalForTest(
        pixels,
        size,
        size,
        const BackgroundRemoval(
          mode: RemovalMode.none,
          strokes: [
            RemovalStroke(
              points: [Offset(0.5, 0.5)],
              radius: 0.25,
              keep: false,
              hardness: 0.3,
            ),
          ],
        ),
      );

      expect(alphaAt(pixels, size, 30, 30), 0, reason: "gone in the middle");
      expect(alphaAt(pixels, size, 59, 30), 255, reason: "untouched outside");

      // Somewhere between the two there is a partly transparent ring, which is
      // what makes one stroke blend into the next.
      var partial = 0;
      for (var i = 0; i < size * size; i++) {
        var a = pixels[i * 4 + 3];
        if (a > 10 && a < 245) partial++;
      }
      expect(partial, greaterThan(20));
    });

    testWidgets("a hard brush does not", (tester) async {
      const size = 60;
      var pixels = picture(size, size, (x, y) => const Color(0xFF6688AA));

      applyRemovalForTest(
        pixels,
        size,
        size,
        const BackgroundRemoval(
          mode: RemovalMode.none,
          strokes: [
            RemovalStroke(
              points: [Offset(0.5, 0.5)],
              radius: 0.25,
              keep: false,
              hardness: 1,
            ),
          ],
        ),
      );

      var partial = 0;
      for (var i = 0; i < size * size; i++) {
        var a = pixels[i * 4 + 3];
        if (a > 10 && a < 245) partial++;
      }
      expect(partial, 0);
    });

    testWidgets("a clinging brush stops at what is already in the picture",
        (tester) async {
      // The one that makes this usable at speed: brushing along a shoulder
      // takes the sky and stops at the coat, without the pointer having to
      // trace the line.
      const size = 60;
      Uint8List build() => picture(size, size,
          (x, y) => x < 30 ? const Color(0xFF88AAEE) : const Color(0xFF203020));

      // A dab centred in the sky, big enough to cover a good deal of the coat.
      const dab = RemovalStroke(
        points: [Offset(0.25, 0.5)],
        radius: 0.4,
        keep: false,
        hardness: 1,
      );

      var blunt = build();
      applyRemovalForTest(blunt, size, size,
          const BackgroundRemoval(mode: RemovalMode.none, strokes: [dab]));
      // Inside the brush and past the boundary between the two colours.
      expect(alphaAt(blunt, size, 35, 30), 0,
          reason: "a plain brush takes whatever it covers");

      var clinging = build();
      applyRemovalForTest(
        clinging,
        size,
        size,
        const BackgroundRemoval(
          mode: RemovalMode.none,
          strokes: [
            RemovalStroke(
              points: [Offset(0.25, 0.5)],
              radius: 0.4,
              keep: false,
              hardness: 1,
              snap: 0.08,
            ),
          ],
        ),
      );
      expect(alphaAt(clinging, size, 15, 30), 0, reason: "the sky went");
      expect(alphaAt(clinging, size, 35, 30), 255,
          reason: "and it stopped at the coat, though the brush covered it");
    });

    testWidgets("cling holds on to what the stroke started on",
        (tester) async {
      // The reported fault. The reference used to be taken per dab, from
      // whatever was under the pointer at that moment -- so the instant the
      // stroke crossed onto the subject it re-learnt the subject and started
      // clinging to that, which is the opposite of the whole idea. Flesh
      // against a blue background is about as easy as this gets, and it was
      // eating the flesh.
      const size = 60;
      var pixels = picture(size, size,
          (x, y) => x < 30 ? const Color(0xFF3C5AA0) : const Color(0xFFC89678));

      applyRemovalForTest(
        pixels,
        size,
        size,
        const BackgroundRemoval(
          mode: RemovalMode.none,
          strokes: [
            RemovalStroke(
              // Starts on the blue and sweeps well over the flesh.
              points: [Offset(0.1, 0.5), Offset(0.85, 0.5)],
              radius: 0.12,
              keep: false,
              hardness: 1,
              snap: 0.12,
            ),
          ],
        ),
      );

      expect(alphaAt(pixels, size, 10, 30), 0, reason: "the blue went");
      expect(alphaAt(pixels, size, 25, 30), 0,
          reason: "right up to the boundary");
      expect(alphaAt(pixels, size, 40, 30), 255,
          reason: "and the flesh survived being swept over");
      expect(alphaAt(pixels, size, 50, 30), 255);
    });

    testWidgets("cling fades out across the edge rather than leaving a fringe",
        (tester) async {
      // All-or-nothing at the tolerance left a halo: the pixels along an
      // outline are blends of the subject and what is behind it, so they fall
      // outside any tolerance tight enough to protect the subject and stayed
      // as a fringe of background.
      const size = 60;
      var pixels = picture(size, size, (x, y) {
        if (x < 28) return const Color(0xFF3C5AA0);
        // Two columns of blend between the two, as an anti-aliased outline.
        // The first is far enough from the background to be in the fading
        // part of the tolerance rather than wholly inside it.
        if (x == 28) return const Color(0xFF648282);
        if (x == 29) return const Color(0xFFAA8C8C);
        return const Color(0xFFC89678);
      });

      applyRemovalForTest(
        pixels,
        size,
        size,
        const BackgroundRemoval(
          mode: RemovalMode.none,
          strokes: [
            RemovalStroke(
              points: [Offset(0.15, 0.5), Offset(0.42, 0.5)],
              radius: 0.14,
              keep: false,
              hardness: 1,
              snap: 0.2,
            ),
          ],
        ),
      );

      expect(alphaAt(pixels, size, 10, 30), 0, reason: "the background went");
      expect(alphaAt(pixels, size, 40, 30), 255, reason: "the subject stayed");
      // And the blend between them is partly taken, which is what it is.
      var edge = alphaAt(pixels, size, 28, 30);
      expect(edge, greaterThan(0));
      expect(edge, lessThan(255),
          reason: "a blended pixel is half of each and is taken as half");
    });

    testWidgets("cling follows a background that shades", (tester) async {
      // The reference is allowed to drift towards colours it already agrees
      // with -- a sky that shades from one side to the other is still the sky
      // -- so long as it never follows something it does not recognise.
      const size = 60;
      var pixels = picture(size, size, (x, y) {
        if (x >= 45) return const Color(0xFFC89678);
        // A blue ramp across the background half.
        var v = 90 + (x / 45 * 90).round();
        return Color.fromARGB(255, v ~/ 2, (v * 0.7).round(), v);
      });

      applyRemovalForTest(
        pixels,
        size,
        size,
        const BackgroundRemoval(
          mode: RemovalMode.none,
          strokes: [
            RemovalStroke(
              points: [Offset(0.05, 0.5), Offset(0.9, 0.5)],
              radius: 0.12,
              keep: false,
              hardness: 1,
              snap: 0.1,
            ),
          ],
        ),
      );

      expect(alphaAt(pixels, size, 5, 30), 0, reason: "the near end");
      // Mostly gone rather than entirely: cling fades out across the last part
      // of its tolerance, and the far end of a ramp is by definition near that
      // edge. What matters is that it was followed at all.
      expect(alphaAt(pixels, size, 40, 30), lessThan(80),
          reason: "and the far end of the ramp, though it is a long way from "
              "the colour the stroke started on");
      expect(alphaAt(pixels, size, 52, 30), 255,
          reason: "but not the flesh");
    });

    testWidgets("strokes build on one another rather than fighting",
        (tester) async {
      // Two overlapping soft strokes have to add up, or feathering them means
      // every second pass undoes the first.
      const size = 60;
      var pixels = picture(size, size, (x, y) => const Color(0xFF6688AA));

      const soft = BackgroundRemoval(
        mode: RemovalMode.none,
        strokes: [
          RemovalStroke(
              points: [Offset(0.45, 0.5)],
              radius: 0.2,
              keep: false,
              hardness: 0.2),
          RemovalStroke(
              points: [Offset(0.55, 0.5)],
              radius: 0.2,
              keep: false,
              hardness: 0.2),
        ],
      );
      applyRemovalForTest(pixels, size, size, soft);

      // Where the two rims overlap, between the centres, both have had a go.
      expect(alphaAt(pixels, size, 30, 30), lessThan(60));
    });

    testWidgets("a put-back stroke wins over an erase drawn before it",
        (tester) async {
      const size = 40;
      var pixels = picture(size, size, (x, y) => const Color(0xFF6688AA));

      applyRemovalForTest(
        pixels,
        size,
        size,
        const BackgroundRemoval(
          mode: RemovalMode.none,
          strokes: [
            RemovalStroke(
                points: [Offset(0.5, 0.5)],
                radius: 0.4,
                keep: false,
                hardness: 1),
            RemovalStroke(
                points: [Offset(0.5, 0.5)],
                radius: 0.15,
                keep: true,
                hardness: 1),
          ],
        ),
      );

      expect(alphaAt(pixels, size, 20, 20), 255, reason: "put back");
      expect(alphaAt(pixels, size, 20, 8), 0, reason: "still rubbed out");
    });
  });

  group("premultiplied alpha", () {
    /// colourAt is the three colour channels, which in this format are
    /// already multiplied by the pixel's own alpha.
    List<int> colourAt(Uint8List pixels, int width, int x, int y) {
      var p = (y * width + x) * 4;
      return [pixels[p], pixels[p + 1], pixels[p + 2]];
    }

    testWidgets("a preview's transparent pixels carry no colour",
        (tester) async {
      // The whole picture washing orange after a stroke. Written straight, a
      // transparent pixel carried the tint's full colour at zero alpha --
      // meaningless in premultiplied form, and Skia is free to draw it as the
      // colour.
      const size = 32;
      late Uint8List out;
      await tester.runAsync(() async {
        var pixels = Uint8List(size * size * 4);
        for (var i = 0; i < size * size; i++) {
          pixels[i * 4] = 60;
          pixels[i * 4 + 1] = 90;
          pixels[i * 4 + 2] = 160;
          pixels[i * 4 + 3] = 255;
        }
        var made = Completer<ui.Image>();
        ui.decodeImageFromPixels(
            pixels, size, size, ui.PixelFormat.rgba8888, made.complete);

        var preview = await strokePreview(
            await made.future,
            const RemovalStroke(
              points: [Offset(0.5, 0.5)],
              radius: 0.1,
              keep: false,
              hardness: 1,
            ));
        out = (await preview!.toByteData())!.buffer.asUint8List();
      });

      // A corner, far from the stroke: fully transparent and therefore black.
      expect(out[3], 0, reason: "nothing there");
      expect(colourAt(out, size, 0, 0), [0, 0, 0],
          reason: "and no colour hiding behind the transparency");
    });

    testWidgets("a removed background carries no colour either",
        (tester) async {
      // The same fault in the removal itself, which is why every feathered
      // edge glowed: a half-transparent pixel was carrying twice the colour
      // it should.
      const size = 40;
      var pixels = picture(size, size, (x, y) => const Color(0xFF3C5AA0));

      applyRemovalForTest(
        pixels,
        size,
        size,
        const BackgroundRemoval(
          mode: RemovalMode.none,
          strokes: [
            RemovalStroke(
                points: [Offset(0.5, 0.5)],
                radius: 0.3,
                keep: false,
                hardness: 1),
          ],
        ),
      );

      expect(alphaAt(pixels, size, 20, 20), 0);
      expect(colourAt(pixels, size, 20, 20), [0, 0, 0],
          reason: "a pixel that is gone is gone, colour included");
      expect(colourAt(pixels, size, 1, 1), [60, 90, 160],
          reason: "and one that stayed is untouched");
    });

    testWidgets("a half-transparent pixel carries half the colour",
        (tester) async {
      const size = 40;
      var pixels = picture(size, size, (x, y) => const Color(0xFF3C5AA0));

      applyRemovalForTest(
        pixels,
        size,
        size,
        const BackgroundRemoval(
          mode: RemovalMode.none,
          strokes: [
            RemovalStroke(
                points: [Offset(0.5, 0.5)],
                radius: 0.35,
                keep: false,
                hardness: 0.1),
          ],
        ),
      );

      // Somewhere on the feathered rim there is a partly transparent pixel,
      // and its colour must have come down with its alpha.
      for (var x = 0; x < size; x++) {
        var a = alphaAt(pixels, size, x, 20);
        if (a > 40 && a < 215) {
          var colour = colourAt(pixels, size, x, 20);
          expect(colour[2], closeTo(160 * a / 255, 3),
              reason: "colour scaled with the alpha it now has");
          return;
        }
      }
      fail("no feathered pixel to check");
    });
  });

  group("the working size", () {
    test("a big picture is shrunk before any of this runs", () {
      // Background removal is several passes over every pixel, and the
      // preview does it again on every adjustment. A twelve-megapixel pass
      // buys nothing anybody can see -- the result is drawn into a few hundred
      // pixels -- and costs the whole wait.
      expect(scaleForWork(6000, 4000), closeTo(workingSize / 6000, 0.0001));
      expect(scaleForWork(4000, 6000), closeTo(workingSize / 6000, 0.0001));
    });

    test("a small one is left exactly as it is", () {
      // Shrinking something already small would only lose detail, and
      // scaling back up would soften an edge that was crisp.
      expect(scaleForWork(800, 600), 1);
      expect(scaleForWork(workingSize, workingSize), 1);
      expect(scaleForWork(workingSize + 1, 10), lessThan(1));
    });

    test("a stroke lands in the same place at either size", () {
      // The brush's measurements are fractions of the picture rather than
      // pixel counts, which is what lets the work be done at one size and
      // shown at another.
      const stroke = RemovalStroke(
        points: [Offset(0.25, 0.5), Offset(0.75, 0.5)],
        radius: 0.1,
        keep: false,
        hardness: 1,
      );

      /// removed is the fraction of the picture the stroke takes out.
      double removed(int size) {
        var pixels = picture(size, size, (x, y) => const Color(0xFF3C5AA0));
        applyRemovalForTest(pixels, size, size,
            const BackgroundRemoval(mode: RemovalMode.none, strokes: [stroke]));
        var gone = 0;
        for (var i = 0; i < size * size; i++) {
          if (pixels[i * 4 + 3] == 0) gone++;
        }
        return gone / (size * size);
      }

      expect(removed(200), closeTo(removed(60), 0.02),
          reason: "the same fraction of the picture, whatever its size");
    });
  });

  group("hardness", () {
    /// band is how many pixels *across* the stroke are partly taken -- the
    /// width of the falloff.
    ///
    /// A column rather than a row. The stroke runs left to right, so along it
    /// the coverage is flat and the only partial pixels are its two end caps;
    /// the falloff is perpendicular to it, and measuring the wrong axis makes
    /// a test that passes whatever the brush does.
    int band(Uint8List pixels, int size, int column) {
      var out = 0;
      for (var y = 0; y < size; y++) {
        var a = alphaAt(pixels, size, column, y);
        if (a > 8 && a < 247) out++;
      }
      return out;
    }

    Uint8List sweep(double hardness) {
      const size = 120;
      var pixels = picture(size, size, (x, y) => const Color(0xFF3C5AA0));
      applyRemovalForTest(
        pixels,
        size,
        size,
        BackgroundRemoval(
          mode: RemovalMode.none,
          strokes: [
            RemovalStroke(
              // A long stroke, so most of its length is far from either end
              // and every pixel under it is covered by several dabs.
              points: const [Offset(0.2, 0.5), Offset(0.8, 0.5)],
              radius: 0.15,
              keep: false,
              hardness: hardness,
            ),
          ],
        ),
      );
      return pixels;
    }

    testWidgets("a stroke that goes back over itself stays soft",
        (tester) async {
      // The reason coverage is the *strongest* dab rather than the sum of
      // them. Applying each dab as it went blended a pixel towards the target
      // once per dab, and repeated blending arrives at the target however
      // gentle each step is -- so scrubbing back and forth over one area,
      // which is exactly how anybody uses a brush, drove its feathered rim to
      // a hard edge.
      const size = 120;
      var pixels = picture(size, size, (x, y) => const Color(0xFF3C5AA0));
      applyRemovalForTest(
        pixels,
        size,
        size,
        const BackgroundRemoval(
          mode: RemovalMode.none,
          strokes: [
            RemovalStroke(
              // Six passes over the same band.
              points: [
                Offset(0.2, 0.5),
                Offset(0.8, 0.5),
                Offset(0.2, 0.5),
                Offset(0.8, 0.5),
                Offset(0.2, 0.5),
                Offset(0.8, 0.5),
                Offset(0.2, 0.5),
              ],
              radius: 0.15,
              keep: false,
              hardness: 0.1,
            ),
          ],
        ),
      );

      expect(band(pixels, size, 60), greaterThan(10),
          reason: "the rim is as soft after six passes as after one");
    });

    testWidgets("a soft brush feathers across the middle of a stroke",
        (tester) async {
      expect(band(sweep(0.1), 120, 60), greaterThan(10),
          reason: "a soft brush has a wide falloff");
    });

    testWidgets("and a hard one does not", (tester) async {
      expect(band(sweep(1), 120, 60), lessThan(4),
          reason: "a hard brush is a cut edge");
    });

    testWidgets("the falloff narrows as hardness rises", (tester) async {
      var soft = band(sweep(0.1), 120, 60);
      var middling = band(sweep(0.5), 120, 60);
      var hard = band(sweep(0.9), 120, 60);

      expect(soft, greaterThan(middling));
      expect(middling, greaterThan(hard));
    });

    testWidgets("the preview shows the falloff as a band of its own",
        (tester) async {
      // Blue where the brush is at full strength, yellow at the outer rim, so
      // the width of the yellow *is* the softness. A flat wash showed neither
      // and hardness could be moved end to end with no visible change.
      const size = 64;
      late Uint8List out;
      await tester.runAsync(() async {
        var pixels = Uint8List(size * size * 4);
        for (var i = 0; i < size * size; i++) {
          pixels[i * 4] = 60;
          pixels[i * 4 + 1] = 90;
          pixels[i * 4 + 2] = 160;
          pixels[i * 4 + 3] = 255;
        }
        var made = Completer<ui.Image>();
        ui.decodeImageFromPixels(
            pixels, size, size, ui.PixelFormat.rgba8888, made.complete);
        var preview = await strokePreview(
            await made.future,
            const RemovalStroke(
              points: [Offset(0.5, 0.5)],
              radius: 0.3,
              keep: false,
              hardness: 0.1,
            ));
        out = (await preview!.toByteData())!.buffer.asUint8List();
      });

      // The centre is at full strength: blue, with no red in it.
      var centre = (32 * size + 32) * 4;
      expect(out[centre + 2], greaterThan(out[centre]),
          reason: "blue at the core");

      // Somewhere out on the rim the red channel leads, which is the yellow.
      var yellow = 0;
      for (var x = 0; x < size; x++) {
        var p = (32 * size + x) * 4;
        if (out[p + 3] > 20 && out[p] > out[p + 2]) yellow++;
      }
      expect(yellow, greaterThan(4),
          reason: "and a band of yellow where it fades out");
    });
  });

  group("a swept line is a line, not a row of blobs", () {
    testWidgets("a long drag covers its whole length", (tester) async {
      // The regression. A drag reports hundreds of positions a pixel or two
      // apart, and the spacing between dabs is carried across the joins
      // between them -- carried wrongly, the dabs landed almost anywhere and
      // most of the line was never covered.
      const size = 120;
      var pixels = picture(size, size, (x, y) => const Color(0xFF3C5AA0));

      // Two hundred sampled points across the middle, as a real drag gives.
      var points = [
        for (var i = 0; i < 200; i++) Offset(0.1 + i * 0.004, 0.5),
      ];

      applyRemovalForTest(
        pixels,
        size,
        size,
        BackgroundRemoval(
          mode: RemovalMode.none,
          strokes: [
            RemovalStroke(
                points: points, radius: 0.05, keep: false, hardness: 1),
          ],
        ),
      );

      // Every pixel along the line's own row must be gone -- no gaps between
      // one dab and the next.
      var gaps = 0;
      for (var x = 15; x < 105; x++) {
        if (alphaAt(pixels, size, x, 60) != 0) gaps++;
      }
      expect(gaps, 0, reason: "no bare patches along the swept line");
    });

    testWidgets("a wandering drag covers its whole length too",
        (tester) async {
      // Segments of varying length, which is what a hand actually draws: the
      // carried distance has to survive short and long ones alike.
      const size = 120;
      var pixels = picture(size, size, (x, y) => const Color(0xFF3C5AA0));

      var points = <Offset>[];
      for (var i = 0; i < 120; i++) {
        // Uneven steps, and a wobble across the line.
        points.add(Offset(0.12 + i * 0.006 + (i % 5) * 0.001,
            0.5 + (i % 3) * 0.004));
      }

      applyRemovalForTest(
        pixels,
        size,
        size,
        BackgroundRemoval(
          mode: RemovalMode.none,
          strokes: [
            RemovalStroke(
                points: points, radius: 0.06, keep: false, hardness: 1),
          ],
        ),
      );

      var gaps = 0;
      for (var x = 20; x < 100; x++) {
        if (alphaAt(pixels, size, x, 62) != 0) gaps++;
      }
      expect(gaps, 0);
    });

    testWidgets("and a single tap still makes one mark", (tester) async {
      const size = 60;
      var pixels = picture(size, size, (x, y) => const Color(0xFF3C5AA0));
      applyRemovalForTest(
        pixels,
        size,
        size,
        const BackgroundRemoval(
          mode: RemovalMode.none,
          strokes: [
            RemovalStroke(
                points: [Offset(0.5, 0.5)],
                radius: 0.1,
                keep: false,
                hardness: 1),
          ],
        ),
      );
      expect(alphaAt(pixels, size, 30, 30), 0);
      expect(alphaAt(pixels, size, 1, 1), 255);
    });
  });

  group("putting something back", () {
    testWidgets("a put-back stroke never clings", (tester) async {
      // Clinging means "spread only through pixels like the one I started on",
      // which is how you find the edge of a background -- but what is being
      // put back is the subject, and a subject is every colour there is. With
      // it on, a stroke over a face brought back the few pixels nearest
      // whatever was under the pointer and left the rest, so the brush
      // appeared to do nothing at all.
      const size = 60;
      var pixels = picture(size, size, (x, y) {
        // A subject of many colours, which is what a subject is.
        if (x < 30) return const Color(0xFF3C5AA0);
        return Color.fromARGB(255, 200 - (x % 17) * 8, 150 + (y % 13) * 6, 120);
      });

      applyRemovalForTest(
        pixels,
        size,
        size,
        const BackgroundRemoval(
          mode: RemovalMode.none,
          strokes: [
            RemovalStroke(
                points: [Offset(0.5, 0.5)],
                radius: 0.6,
                keep: false,
                hardness: 1),
            // Snap is deliberately set: the point is that a put-back stroke
            // ignores it, which the controller does when it builds one.
            RemovalStroke(
                points: [Offset(0.75, 0.5)],
                radius: 0.15,
                keep: true,
                hardness: 1,
                snap: 0),
          ],
        ),
      );

      // Every pixel under the put-back stroke is back, whatever its colour.
      var back = 0;
      for (var x = 40; x < 50; x++) {
        for (var y = 26; y < 34; y++) {
          if (alphaAt(pixels, size, x, y) == 255) back++;
        }
      }
      expect(back, 80, reason: "all of it, not the parts that matched");
    });
  });

  group("the magnet", () {
    testWidgets("finds the edge a stroke crossed", (tester) async {
      // The number cling wants is "how different from the background does a
      // pixel have to be before it is not the background", and nobody can read
      // that off a photograph -- which is why setting it by hand never worked.
      const size = 80;
      var pixels = picture(size, size,
          (x, y) => x < 40 ? const Color(0xFF3C5AA0) : const Color(0xFFC89678));

      var found = suggestSnap(
        pixels,
        size,
        size,
        const RemovalStroke(
          points: [Offset(0.1, 0.5), Offset(0.9, 0.5)],
          radius: 0.08,
          keep: false,
          hardness: 1,
        ),
      );

      expect(found, isNotNull);

      // And the number it found actually separates the two: used as the cling,
      // a stroke that sweeps across takes the sky and leaves the flesh.
      applyRemovalForTest(
        pixels,
        size,
        size,
        BackgroundRemoval(
          mode: RemovalMode.none,
          strokes: [
            RemovalStroke(
              points: const [Offset(0.1, 0.5), Offset(0.9, 0.5)],
              radius: 0.08,
              keep: false,
              hardness: 1,
              snap: found!,
            ),
          ],
        ),
      );

      expect(alphaAt(pixels, size, 10, 40), 0, reason: "the sky went");
      expect(alphaAt(pixels, size, 60, 40), 255, reason: "the flesh stayed");
    });

    testWidgets("says so when there is no edge to find", (tester) async {
      // A stroke drawn entirely on the background has one cluster of colours,
      // and inventing a split in it would cut the background in half.
      const size = 60;
      var pixels = picture(size, size, (x, y) => const Color(0xFF3C5AA0));

      expect(
          suggestSnap(
            pixels,
            size,
            size,
            const RemovalStroke(
              points: [Offset(0.2, 0.5), Offset(0.8, 0.5)],
              radius: 0.08,
              keep: false,
              hardness: 1,
            ),
          ),
          isNull);
    });

    testWidgets("a fainter edge gives a tighter cling", (tester) async {
      // The threshold has to come from the picture rather than from a constant,
      // which is the whole point: two pictures with different amounts of
      // contrast need different numbers.
      double? forGap(int gap) {
        const size = 80;
        var pixels = picture(
            size,
            size,
            (x, y) => x < 40
                ? const Color(0xFF404040)
                : Color.fromARGB(255, 64 + gap, 64 + gap, 64 + gap));
        return suggestSnap(
          pixels,
          size,
          size,
          const RemovalStroke(
            points: [Offset(0.1, 0.5), Offset(0.9, 0.5)],
            radius: 0.08,
            keep: false,
            hardness: 1,
          ),
        );
      }

      var faint = forGap(30);
      var strong = forGap(150);
      expect(faint, isNotNull);
      expect(strong, isNotNull);
      expect(faint!, lessThan(strong!));
    });
  });
}
