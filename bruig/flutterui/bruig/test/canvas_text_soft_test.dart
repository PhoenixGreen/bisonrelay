import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_text_soft_test.dart is what falls behind the letters: the shadow and
// the glow.
//
// Both are drawn as a pass of their own rather than as shadows hung on the
// words, and the two things that pins are here: a shadow lands opposite the
// light wherever the light is put, and a glow keeps its own colour even when
// a pattern is showing through the type. Drawn with the letters, the glow was
// cut out of the same layer the pattern is cut to and came out in the
// pattern's colours instead of its own.

const _size = 400.0;

/// _where is the middle of everything drawn in [pick], as a point on the
/// canvas -- which is enough to say which way a shadow was thrown.
Future<Offset?> _where(
    TextSpec spec, bool Function(int r, int g, int b) pick) async {
  var element = TextElement(
    const ElementBase(id: "t", x: 0, y: 0, width: _size, height: _size),
    text: "Ii",
    textSpec: spec,
  );
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, _size, _size),
      Paint()..color = const Color(0xFF000000));
  paintElement(canvas, element, 0,
      document: CanvasDocument(elements: [element]));
  var picture = recorder.endRecording();
  var image = await picture.toImage(_size.toInt(), _size.toInt());
  var bytes = (await image.toByteData())!;
  double x = 0, y = 0;
  var found = 0;
  for (var i = 0; i < bytes.lengthInBytes; i += 4) {
    var p = bytes.getUint32(i);
    if (!pick((p >> 24) & 0xFF, (p >> 16) & 0xFF, (p >> 8) & 0xFF)) continue;
    var at = i ~/ 4;
    x += at % _size;
    y += at ~/ _size;
    found++;
  }
  image.dispose();
  picture.dispose();
  return found == 0 ? null : Offset(x / found, y / found);
}

bool _white(int r, int g, int b) => r > 0x80 && g > 0x80 && b > 0x80;
bool _red(int r, int g, int b) => r > 0x40 && g < 0x40 && b < 0x40;
bool _green(int r, int g, int b) => g > 0x40 && g > r + 0x20 && g > b + 0x20;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A hard shadow in a colour of its own, so what is the shadow and what is
  // the type can be told apart by looking.
  const lit = TextSpec(
      fontSize: 120,
      color: Color(0xFFFFFFFF),
      shadowBlur: 0,
      shadowDistance: 20,
      shadowColor: Color(0xFFFF0000));

  group("the shadow's direction", () {
    testWidgets("throws the shadow away from the light", (tester) async {
      // The setting is where the light is, read like a compass: 0 straight
      // up, 90 to the right. So a light overhead puts the shadow below the
      // words, and a light on the right puts it to their left.
      late Offset words;
      late Offset above;
      late Offset right;
      await tester.runAsync(() async {
        words = (await _where(lit, _white))!;
        above = (await _where(lit.copyWith(shadowAngle: 0), _red))!;
        right = (await _where(lit.copyWith(shadowAngle: 90), _red))!;
      });
      expect(above.dy, greaterThan(words.dy + 4),
          reason: "a light overhead throws the shadow downwards");
      expect((above.dx - words.dx).abs(), lessThan(4),
          reason: "and not to either side");
      expect(right.dx, lessThan(words.dx - 4),
          reason: "a light on the right throws it to the left");
    });

    testWidgets("and leaves it under the words at no distance", (tester) async {
      late Offset words;
      late Offset? under;
      await tester.runAsync(() async {
        words = (await _where(lit, _white))!;
        under =
            await _where(lit.copyWith(shadowDistance: 0, shadowBlur: 8), _red);
      });
      // A shadow with nowhere to go is a glow in the shadow's colour: it
      // spreads round the letters rather than to one side of them.
      expect(under, isNotNull, reason: "the blur is still drawn");
      // Near the words rather than exactly on them: the glow spreads round
      // the whole letterform and the letters' own middle is not the middle
      // of their blur. A distance of 20 moves it by fourteen in each
      // direction, so this tells the two apart with room to spare.
      var at = under!;
      expect((at.dx - words.dx).abs(), lessThan(8));
      expect((at.dy - words.dy).abs(), lessThan(8));
    });

    testWidgets("and an older document keeps the shadow it had",
        (tester) async {
      // Saved as a dx and a dy before the light had a direction. Read back as
      // the angle and the distance that put it in the same place.
      var old = TextSpec.fromJson(const {
        "font": "Inter",
        "size": 48.0,
        "sb": 6.0,
        "sx": 3.0,
        "sy": 4.0,
      });
      expect(old.shadowDistance, closeTo(5, 0.01));
      expect(old.shadowOffset.dx, closeTo(3, 0.01));
      expect(old.shadowOffset.dy, closeTo(4, 0.01));
      // And writes itself back out the new way, without the old keys.
      var written = old.toJson();
      expect(written["sd"], closeTo(5, 0.01));
      expect(written.containsKey("sx"), isFalse);
    });
  });

  group("the glow", () {
    testWidgets("keeps its own colour through a pattern fill", (tester) async {
      // The regression this pass exists for. A glow drawn as part of the
      // letters goes into the same layer the pattern is cut to, so srcIn
      // hands the glow the pattern's colours -- a green neon came out red.
      const glowing = TextSpec(
          fontSize: 120,
          color: Color(0xFFFFFFFF),
          glowBlur: 24,
          glowColor: Color(0xFF00FF40),
          fill: TextFill(
              kind: TextFillKind.pattern,
              pattern: ProceduralSpec(
                  style: ProceduralStyle.rings,
                  background: Color(0xFFFF2000),
                  foreground: Color(0xFFFF8000),
                  accent: Color(0xFFFFC000))));
      late Offset? glow;
      await tester.runAsync(() async {
        glow = await _where(glowing, _green);
      });
      expect(glow, isNotNull,
          reason: "the glow is drawn in its own green, not in the "
              "pattern's reds");
    });
  });
}
