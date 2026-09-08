import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/text_animator.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_text_animation_test.dart is a paragraph arriving.
//
// The thing worth pinning is that thirty names are not thirty animations: a
// preset is a scope -- the block, a line, a word, a letter -- and a motion,
// and the painter knows only the motions. So what is checked here is the
// pieces, the stagger, and that a few representative motions actually draw
// something different at half way than at the end.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const spec = TextSpec(fontSize: 20, color: Color(0xFFFFFFFF));
  const words = "One two three four";

  TextPainter laidOut(String text) =>
      layoutText(text, spec, maxWidth: 400, fillWidth: true);

  group("what moves", () {
    test("a block is one piece whatever is in it", () {
      var pieces = piecesFor(laidOut(words), words, TextAnimationScope.block);
      expect(pieces.length, 1);
    });

    test("words are the words, and letters the letters", () {
      expect(
          piecesFor(laidOut(words), words, TextAnimationScope.word).length, 4);
      // Spaces are not letters: an empty piece has nothing to animate and
      // would still take its turn in the stagger, so the words would arrive
      // with gaps in the rhythm.
      expect(piecesFor(laidOut(words), words, TextAnimationScope.letter).length,
          words.replaceAll(" ", "").length);
    });

    test("lines come from the paragraph's own line metrics", () {
      var text = List.filled(12, "wrapping words").join(" ");
      var painter = layoutText(text, spec, maxWidth: 200, fillWidth: true);
      var pieces = piecesFor(painter, text, TextAnimationScope.line);
      expect(pieces.length, painter.computeLineMetrics().length);
      expect(pieces.length, greaterThan(1));
    });

    test("a piece knows where it actually is", () {
      // Off the paragraph's boxes rather than counted out from the left,
      // which on a centred paragraph is wrong by half a line.
      var painter = layoutText(
          words, spec.copyWith(align: TextAlignSpec.center),
          maxWidth: 400, fillWidth: true);
      var pieces = piecesFor(painter, words, TextAnimationScope.word);
      expect(pieces.first.box.left, greaterThan(1),
          reason: "a centred line does not start at the left edge");
    });
  });

  group("the stagger", () {
    test("a block has nothing to stagger", () {
      expect(TextAnimationPreset.fadeIn.staggers, isFalse);
      expect(TextAnimationPreset.letters.staggers, isTrue);
      expect(TextAnimationPreset.words.staggers, isTrue);
    });

    test("the first piece arrives before the last", () {
      const animation = TextAnimation(
          preset: TextAnimationPreset.words, gap: 1, ease: ChartEase.linear);
      expect(animation.progressAt(0.2, 0, 4),
          greaterThan(animation.progressAt(0.2, 3, 4)));
    });

    test("and the way out unwinds unless it is told otherwise", () {
      const unwinds = TextAnimation(
          exit: TextAnimationPreset.words, gap: 1, ease: ChartEase.linear);
      const empties = TextAnimation(
          exit: TextAnimationPreset.words,
          exitInOrder: true,
          gap: 1,
          ease: ChartEase.linear);

      expect(unwinds.leaving.progressAt(0.9, 3, 4),
          lessThan(unwinds.leaving.progressAt(0.9, 0, 4)),
          reason: "unwinding: the last word goes first");
      expect(empties.leaving.progressAt(0.9, 0, 4),
          lessThan(empties.leaving.progressAt(0.9, 3, 4)),
          reason: "emptying: the first word goes first");
    });

    test("it is the same arithmetic a chart staggers with", () {
      // A headline and a chart arriving together have to line up, and two
      // staggers that meant slightly different things would not.
      const text = TextAnimation(
          preset: TextAnimationPreset.letters,
          gap: 0.7,
          ease: ChartEase.linear);
      const chart = ChartAnimation(
          preset: ChartAnimationPreset.fadeIn,
          gap: 0.7,
          ease: ChartEase.linear);
      for (var reveal in [0.1, 0.4, 0.9]) {
        expect(text.progressAt(reveal, 2, 6),
            closeTo(chart.progressAt(reveal, 2, 6), 0.0001));
      }
    });
  });

  group("drawn", () {
    /// ink is how many pixels the words put on the picture.
    Future<int> ink(TextElement element, {double reveal = 1}) async {
      const size = Size(400, 200);
      var recorder = ui.PictureRecorder();
      var canvas = ui.Canvas(recorder);
      canvas.drawRect(
          Offset.zero & size, Paint()..color = const Color(0xFF000000));
      paintElement(canvas, element, 0,
          document: CanvasDocument(elements: [element]));
      var picture = recorder.endRecording();
      var image = await picture.toImage(400, 200);
      var bytes = (await image.toByteData())!;
      var lit = 0;
      for (var i = 0; i < bytes.lengthInBytes; i += 4) {
        if (bytes.getUint32(i) != 0x000000FF) lit++;
      }
      image.dispose();
      picture.dispose();
      return lit;
    }

    /// at is the element posed part way through its animation, which is what
    /// a keyframe on the reveal channel does.
    TextElement at(TextAnimationPreset preset, double reveal) => TextElement(
          const ElementBase(id: "t", x: 0, y: 0, width: 400, height: 200),
          text: words,
          textSpec: spec,
          animation: TextAnimation(preset: preset, ease: ChartEase.linear),
        ).withBase(
          track: ElementTrack([
            Keyframe(frame: 0, values: {KeyframeChannel.reveal: reveal}),
          ]),
        ) as TextElement;

    testWidgets("nothing has arrived at the start", (tester) async {
      late int none;
      late int all;
      await tester.runAsync(() async {
        none = await ink(at(TextAnimationPreset.fadeIn, 0));
        all = await ink(at(TextAnimationPreset.fadeIn, 1));
      });
      expect(none, 0);
      expect(all, greaterThan(100));
    });

    testWidgets("and half of it is on the way", (tester) async {
      // Every motion has to do *something* different half way through, or it
      // is a name in a list that draws the finished thing.
      for (var preset in [
        TextAnimationPreset.fadeIn,
        TextAnimationPreset.slideLeft,
        TextAnimationPreset.scaleIn,
        TextAnimationPreset.wipe,
        TextAnimationPreset.split,
        TextAnimationPreset.letters,
        TextAnimationPreset.words,
        TextAnimationPreset.rotateIn,
        TextAnimationPreset.flipIn,
        TextAnimationPreset.underline,
        TextAnimationPreset.scramble,
        TextAnimationPreset.blurIn,
      ]) {
        late int half;
        late int whole;
        await tester.runAsync(() async {
          half = await ink(at(preset, 0.5));
          whole = await ink(at(preset, 1));
        });
        expect(half, isNot(whole),
            reason: "${preset.name} draws the finished "
                "thing half way through");
        expect(whole, greaterThan(100), reason: preset.name);
      }
    });
  });

  group("the keyframes it lays", () {
    CanvasController controllerWith(TextElement element) => CanvasController(
        CanvasDocument(frames: 48, frameRate: 12).addElement(element));

    TextElement textIn(CanvasController c) =>
        c.document.elements.single as TextElement;

    test("choosing one gives it a length on the timeline", () {
      var element = TextElement(
        const ElementBase(id: "t", x: 0, y: 0, width: 400, height: 200),
        text: words,
      );
      var controller = controllerWith(element);
      addTearDown(controller.dispose);

      controller.applyTextAnimation(
          textIn(controller), TextAnimationPreset.words);
      var band = bandsIn(textIn(controller).track).single;
      expect(band.channel, KeyframeChannel.reveal);
      expect(band.real, isTrue, reason: "two keyframes, not one");
      expect(textIn(controller).animation.preset, TextAnimationPreset.words);
    });

    test("and choosing None takes them away again", () {
      var element = TextElement(
        const ElementBase(id: "t", x: 0, y: 0, width: 400, height: 200),
        text: words,
      );
      var controller = controllerWith(element);
      addTearDown(controller.dispose);

      controller.applyTextAnimation(
          textIn(controller), TextAnimationPreset.fadeIn);
      controller.applyTextAnimation(
          textIn(controller), TextAnimationPreset.none);

      expect(textIn(controller).animation.on, isFalse);
      expect(textIn(controller).track, isNull,
          reason: "no animation left, so no empty track in the saved file");
    });

    test("the way out is a second pair, after the first", () {
      var element = TextElement(
        const ElementBase(id: "t", x: 0, y: 0, width: 400, height: 200),
        text: words,
      );
      var controller = controllerWith(element);
      addTearDown(controller.dispose);

      controller.frame = 0;
      controller.applyTextAnimation(
          textIn(controller), TextAnimationPreset.fadeIn);
      controller.applyTextExit(textIn(controller), TextAnimationPreset.fadeIn);

      var bands = bandsIn(textIn(controller).track);
      expect(bands.length, 2);
      expect(bands.last.channel, KeyframeChannel.close);
      expect(bands.last.from, greaterThan(bands.first.to));
    });
  });

  group("saved and read back", () {
    test("a preset, its way out and its timing survive", () {
      var element = TextElement(
        const ElementBase(id: "t", x: 0, y: 0, width: 400, height: 200),
        text: words,
        animation: const TextAnimation(
          preset: TextAnimationPreset.letterRise,
          exit: TextAnimationPreset.wipe,
          exitInOrder: true,
          gap: 0.8,
          ease: ChartEase.bounce,
        ),
      );
      var back = elementFromJson(element.toJson()) as TextElement;
      expect(back.animation.preset, TextAnimationPreset.letterRise);
      expect(back.animation.exit, TextAnimationPreset.wipe);
      expect(back.animation.exitInOrder, isTrue);
      expect(back.animation.gap, 0.8);
      expect(back.animation.ease, ChartEase.bounce);
    });

    test("and a text element saved before any of this has none", () {
      var element = TextElement(
        const ElementBase(id: "t", x: 0, y: 0, width: 400, height: 200),
        text: words,
      );
      expect(element.toJson().containsKey("animation"), isFalse);
      expect((elementFromJson(element.toJson()) as TextElement).animation.on,
          isFalse);
    });
  });

  group("what a piece drags with it", () {
    /// column is what is drawn down one vertical strip of the picture, which
    /// is how "did this letter bring its neighbours with it" is asked.
    Future<List<bool>> litColumns(TextElement element,
        {required double reveal}) async {
      const size = Size(400, 120);
      var posed = element.withBase(
        track: ElementTrack([
          Keyframe(frame: 0, values: {KeyframeChannel.reveal: reveal}),
        ]),
      );
      var recorder = ui.PictureRecorder();
      var canvas = ui.Canvas(recorder);
      canvas.drawRect(
          Offset.zero & size, Paint()..color = const Color(0xFF000000));
      paintElement(canvas, posed, 0,
          document: CanvasDocument(elements: [posed]));
      var picture = recorder.endRecording();
      var image = await picture.toImage(400, 120);
      var bytes = (await image.toByteData())!;

      var out = <bool>[];
      for (var x = 0; x < 400; x++) {
        var lit = false;
        for (var y = 0; y < 120 && !lit; y++) {
          if (bytes.getUint32(((y * 400) + x) * 4) != 0x000000FF) lit = true;
        }
        out.add(lit);
      }
      image.dispose();
      picture.dispose();
      return out;
    }

    TextElement rising() => TextElement(
          const ElementBase(id: "t", x: 0, y: 0, width: 400, height: 120),
          text: "ABCDEFGH",
          textSpec: const TextSpec(fontSize: 28, color: Color(0xFFFFFFFF)),
          animation: const TextAnimation(
            preset: TextAnimationPreset.letterRise,
            gap: 1,
            ease: ChartEase.linear,
          ),
        );

    testWidgets("a letter rising does not bring its neighbours",
        (tester) async {
      // The clip around a piece used to be the piece plus a line height in
      // every direction, so a letter dragged whatever was beside it into
      // view -- which is why letter by letter looked like whole words moving
      // and left a ghost of the next ones trailing behind.
      late List<bool> early;
      late List<bool> whole;
      await tester.runAsync(() async {
        early = await litColumns(rising(), reveal: 0.2);
        whole = await litColumns(rising(), reveal: 1);
      });

      int lit(List<bool> c) => c.where((on) => on).length;
      expect(lit(whole), greaterThan(50), reason: "all eight letters");
      expect(lit(early), lessThan(lit(whole) * 0.6),
          reason: "a fifth of the way in, most of the letters have not "
              "started: ${lit(early)} columns lit against ${lit(whole)}");
    });

    testWidgets("and the ones that have not started are not drawn at all",
        (tester) async {
      // The trailing ghost was the paragraph drawn again through a clip wide
      // enough to show the next few letters at whatever opacity the piece
      // being animated happened to have.
      late List<bool> early;
      await tester.runAsync(() async {
        early = await litColumns(rising(), reveal: 0.15);
      });
      // The right-hand third of a left-to-right stagger is empty this early.
      expect(early.sublist(280).where((on) => on), isEmpty,
          reason: "something is drawn where nothing has arrived yet");
    });
  });

  group("a drawn decoration", () {
    testWidgets("stays after it has been drawn", (tester) async {
      // An underline taken away the moment it finishes being drawn is not an
      // underline, it is a flicker.
      expect(TextMotion.underline.keeps, isTrue);
      expect(TextMotion.highlight.keeps, isTrue);
      expect(TextMotion.fade.keeps, isFalse,
          reason: "everything else ends exactly as a still element looks");

      const size = Size(400, 120);
      Future<int> ink(double reveal) async {
        var element = TextElement(
          const ElementBase(id: "t", x: 0, y: 0, width: 400, height: 120),
          text: "Underlined",
          textSpec: const TextSpec(fontSize: 28, color: Color(0xFFFFFFFF)),
          animation: const TextAnimation(
              preset: TextAnimationPreset.underline, ease: ChartEase.linear),
        ).withBase(
          track: ElementTrack([
            Keyframe(frame: 0, values: {KeyframeChannel.reveal: reveal}),
          ]),
        );
        var recorder = ui.PictureRecorder();
        var canvas = ui.Canvas(recorder);
        canvas.drawRect(
            Offset.zero & size, Paint()..color = const Color(0xFF000000));
        paintElement(canvas, element, 0,
            document: CanvasDocument(elements: [element]));
        var picture = recorder.endRecording();
        var image = await picture.toImage(400, 120);
        var bytes = (await image.toByteData())!;
        var lit = 0;
        for (var i = 0; i < bytes.lengthInBytes; i += 4) {
          if (bytes.getUint32(i) != 0x000000FF) lit++;
        }
        image.dispose();
        picture.dispose();
        return lit;
      }

      late int half;
      late int done;
      late int plain;
      await tester.runAsync(() async {
        half = await ink(0.5);
        done = await ink(1);
        plain = await ink(2);
      });

      expect(done, greaterThan(half), reason: "the line finishes drawing");
      expect(done, plain,
          reason: "and is still there afterwards: $done then $plain");
    });
  });

  group("None means none", () {
    test("a dropdown whose first entry is null can choose it", () {
      // The control refused a null selection, so "Kind — None" could be
      // chosen and nothing happened. The type says whether null is an answer.
      var chosen = <Object?>[];
      var nullable = CanvasDropdown<TextAnimationFamily?>(
        label: "Kind",
        value: TextAnimationFamily.fade,
        options: const [(null, "None"), (TextAnimationFamily.fade, "Fade")],
        onChanged: chosen.add,
      );
      expect(nullable.options.first.$1, isNull);

      // And the model half: choosing nothing is a preset like any other.
      expect(TextAnimationPreset.none.family, TextAnimationFamily.fade,
          reason: "it has to name one, and the first is as good as any");
      expect(const TextAnimation(preset: TextAnimationPreset.none).on, isFalse);
    });
  });

  group("an outlined headline", () {
    testWidgets("takes its outline with it", (tester) async {
      // The outline used to be drawn once, before the animation, so the words
      // slid out from under their own outline and left it behind.
      const size = Size(400, 120);
      Future<int> outlineInk(double reveal) async {
        var element = TextElement(
          const ElementBase(id: "t", x: 0, y: 0, width: 400, height: 120),
          text: "Outlined",
          textSpec: const TextSpec(
            fontSize: 40,
            color: Color(0xFF000000),
            outlineWidth: 3,
            outlineColor: Color(0xFF00FF00),
          ),
          animation: const TextAnimation(
              preset: TextAnimationPreset.slideRight, ease: ChartEase.linear),
        ).withBase(
          track: ElementTrack([
            Keyframe(frame: 0, values: {KeyframeChannel.reveal: reveal}),
          ]),
        );
        var recorder = ui.PictureRecorder();
        var canvas = ui.Canvas(recorder);
        canvas.drawRect(
            Offset.zero & size, Paint()..color = const Color(0xFF101010));
        paintElement(canvas, element, 0,
            document: CanvasDocument(elements: [element]));
        var picture = recorder.endRecording();
        var image = await picture.toImage(400, 120);
        var bytes = (await image.toByteData())!;
        // The outline's own colour, counted only in the left third -- where
        // the words have not arrived yet at a fifth of the way through.
        var left = 0;
        for (var y = 0; y < 120; y++) {
          for (var x = 0; x < 130; x++) {
            if (bytes.getUint32(((y * 400) + x) * 4) == 0x00FF00FF) left++;
          }
        }
        image.dispose();
        picture.dispose();
        return left;
      }

      late int early;
      await tester.runAsync(() async {
        early = await outlineInk(0.2);
      });
      expect(early, 0,
          reason: "the outline should have gone with the words, not stayed "
              "where they will be");
    });
  });
}
