import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/text_items.dart';
import 'package:bruig/plugin_system/canvas/ui/own_style.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_text_pieces_in_turn_test.dart is a text's pieces arriving one after
// another rather than with its words (Ken, 2026-11-11): a kicker or a badge
// coming in just after its headline, set on the text's own arrival rather
// than given arrivals of their own, which would crowd the timeline.

const w = 300, h = 160;

TextElement card(TextAnimation a) => TextElement(
      const ElementBase(id: "t", width: 300, height: 160),
      text: "HEADLINE",
      animation: a,
      items: const [
        TextItem(
            id: "k",
            text: "KICKER",
            slot: TextSlot.bottomRight,
            spec: TextSpec(fontSize: 16, color: Color(0xFFFFFFFF))),
      ],
    );

Future<int> pieceInk(TextAnimation a, double reveal) async {
  var recorder = ui.PictureRecorder();
  var e = card(a);
  paintTextItems(ui.Canvas(recorder), const Rect.fromLTWH(0, 0, 300, 160), e,
      animation: a, reveal: reveal);
  var image = await recorder.endRecording().toImage(w, h);
  var bytes = (await image.toByteData())!;
  image.dispose();
  var n = 0;
  for (var i = 0; i < w * h; i++) {
    n += bytes.getUint8(i * 4 + 3);
  }
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("each layer's share of the arrival", () {
    const inTurn = TextAnimation(
        preset: TextAnimationPreset.fadeIn, piecesInTurn: true, piecesGap: 1);

    test("together, every layer is as far as the whole", () {
      const a = TextAnimation(preset: TextAnimationPreset.fadeIn);
      for (var i = 0; i < 3; i++) {
        expect(a.pieceReveal(0.4, i, 3), 0.4);
      }
    });

    test("in turn, the words first and the last piece as it ends", () {
      // Three layers, each starting as the one before ends.
      expect(inTurn.pieceReveal(1 / 3, 0, 3), closeTo(1, 1e-9));
      expect(inTurn.pieceReveal(1 / 3, 1, 3), closeTo(0, 1e-9));
      expect(inTurn.pieceReveal(0.5, 1, 3), closeTo(0.5, 1e-9));
      expect(inTurn.pieceReveal(1, 2, 3), 1, reason: "all in by the end");
      expect(inTurn.pieceReveal(0.6, 2, 3), 0);
    });

    test("a gap of half: each starts halfway through the one before", () {
      const half = TextAnimation(
          preset: TextAnimationPreset.fadeIn,
          piecesInTurn: true,
          piecesGap: 0.5);
      // Two layers over 1.5 of one layer's time.
      expect(half.pieceReveal(1 / 3, 1, 2), closeTo(0, 1e-9));
      expect(half.pieceReveal(2 / 3, 0, 2), closeTo(1, 1e-9));
      expect(half.pieceReveal(1, 1, 2), closeTo(1, 1e-9));
    });

    test("kept with the text", () {
      var back = TextAnimation.fromJson(inTurn.toJson());
      expect(back.piecesInTurn, isTrue);
      expect(back.piecesGap, 1);
      expect(const TextAnimation().toJson(), isNot(contains("piecesInTurn")));
    });
  });

  test("a piece waiting its turn is not drawn, box and all", () async {
    const together = TextAnimation(preset: TextAnimationPreset.fadeIn);
    const inTurn = TextAnimation(
        preset: TextAnimationPreset.fadeIn, piecesInTurn: true, piecesGap: 1);
    expect(await pieceInk(together, 0.4), greaterThan(0),
        reason: "with the words, it is part-way in");
    expect(await pieceInk(inTurn, 0.4), 0,
        reason: "after the words, it has not started");
    expect(await pieceInk(inTurn, 1), await pieceInk(together, 1),
        reason: "and in the end the same");
  });

  test("offered on the text's own style only where it has pieces", () {
    var withPieces = OwnStyle(card(const TextAnimation()));
    expect(withPieces.piecesInTurn, isFalse);
    expect(withPieces.piecesGap, isNull, reason: "no gap while together");
    var turned = OwnStyle(withPieces.withPiecesInTurn(true));
    expect(turned.piecesInTurn, isTrue);
    expect(turned.piecesGap, 0.5);
    var plain = OwnStyle(TextElement(const ElementBase(id: "p")));
    expect(plain.piecesInTurn, isNull, reason: "nothing to bring in turn");
  });
}
