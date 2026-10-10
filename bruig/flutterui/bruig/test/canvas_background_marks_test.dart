import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/generators.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_background_marks_test.dart is the Organic and Graphic & comic
// families after their rework: that each style's new settings reach the
// picture, and that the new kinds move when they are animated.

const int _w = 160, _h = 90;
const Rect _page = Rect.fromLTWH(0, 0, 160, 90);

Future<List<int>> _pixels(ProceduralSpec spec, {double time = 0}) async {
  var recorder = ui.PictureRecorder();
  paintProcedural(ui.Canvas(recorder), _page, spec, time: time, frameRate: 30);
  var picture = recorder.endRecording();
  var image = await picture.toImage(_w, _h);
  var bytes = (await image.toByteData())!;
  var out = [
    for (var i = 0; i < bytes.lengthInBytes; i += 4) bytes.getUint32(i),
  ];
  image.dispose();
  picture.dispose();
  return out;
}

const _dark = ProceduralSpec(
  background: Color(0xFF101020),
  foreground: Color(0xFF40E0A0),
  accent: Color(0xFFFF4080),
  vignette: 0,
  seed: 4,
);

void main() {
  group("settings reach the picture", () {
    for (var (style, base, id, value) in [
      (ProceduralStyle.contours, <String, double>{}, "contourKind", 1.0),
      (ProceduralStyle.contours, <String, double>{}, "weight", 3.0),
      (ProceduralStyle.contours, <String, double>{}, "major", 3.0),
      (ProceduralStyle.flames, <String, double>{}, "flameKind", 1.0),
      (ProceduralStyle.flames, <String, double>{}, "height", 0.5),
      (ProceduralStyle.flames, <String, double>{}, "embers", 1.0),
      (ProceduralStyle.halftone, <String, double>{}, "dotShape", 1.0),
      (ProceduralStyle.halftone, <String, double>{}, "dotShape", 3.0),
      (ProceduralStyle.halftone, <String, double>{}, "ink", 1.0),
      (ProceduralStyle.halftone, <String, double>{}, "ink", 2.0),
      (ProceduralStyle.speedLines, <String, double>{}, "burstKind", 1.0),
      (ProceduralStyle.speedLines, <String, double>{}, "aim", 1.0),
      (ProceduralStyle.speedLines, {"aim": 2.0}, "aimX", 0.1),
      (ProceduralStyle.crosshatch, <String, double>{}, "tone", 1.0),
      (ProceduralStyle.crosshatch, <String, double>{}, "wobble", 0.8),
      (ProceduralStyle.splatter, <String, double>{}, "splatKind", 1.0),
      (ProceduralStyle.splatter, <String, double>{}, "splatKind", 2.0),
    ]) {
      testWidgets("${style.label} $base: $id", (tester) async {
        var plain = _dark.copyWith(style: style, params: base);
        late List<int> a, b;
        await tester.runAsync(() async {
          a = await _pixels(plain);
          b = await _pixels(plain.withParam(id, value));
        });
        expect(a, isNot(b));
      });
    }
  });

  group("the new kinds move when animated", () {
    for (var (style, params) in [
      (ProceduralStyle.flames, {"flameKind": 1.0}),
      (ProceduralStyle.flames, {"embers": 1.0}),
      (ProceduralStyle.speedLines, {"burstKind": 1.0}),
      (ProceduralStyle.splatter, {"splatKind": 1.0}),
    ]) {
      testWidgets("${style.label} $params", (tester) async {
        var spec = _dark.copyWith(style: style, params: params, animated: true);
        late List<int> a, b;
        await tester.runAsync(() async {
          a = await _pixels(spec, time: 0.5);
          b = await _pixels(spec, time: 2.5);
        });
        expect(a, isNot(b));
      });
    }
  });
}
