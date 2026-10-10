import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/generators.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_background_glow_family_test.dart is the Gradient & light family
// after its rework: that each style's new settings reach the picture, and
// that the new kinds move when they are animated.

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
      (ProceduralStyle.gradientMesh, <String, double>{}, "meshKind", 1.0),
      (ProceduralStyle.gradientMesh, <String, double>{}, "meshKind", 2.0),
      (ProceduralStyle.gradientMesh, {"meshKind": 1.0}, "points", 8.0),
      (ProceduralStyle.gradientMesh, {"meshKind": 1.0}, "softness", 1.0),
      (ProceduralStyle.gradientMesh, {"meshKind": 1.0}, "warp", 0.0),
      (ProceduralStyle.flowWaves, <String, double>{}, "waveKind", 1.0),
      (ProceduralStyle.flowWaves, {"waveKind": 1.0}, "waves", 12.0),
      (ProceduralStyle.flowWaves, {"waveKind": 2.0}, "amplitude", 0.1),
      (ProceduralStyle.flowWaves, {"waveKind": 2.0}, "twist", 0.9),
      (ProceduralStyle.bokeh, <String, double>{}, "aperture", 1.0),
      (ProceduralStyle.bokeh, <String, double>{}, "rim", 1.0),
      (ProceduralStyle.bokeh, <String, double>{}, "depth", 1.0),
      (ProceduralStyle.starfield, <String, double>{}, "nebula", 1.0),
      (ProceduralStyle.starfield, <String, double>{}, "warp", 1.0),
      (ProceduralStyle.starfield, <String, double>{}, "spikes", 0.3),
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
      (ProceduralStyle.gradientMesh, {"meshKind": 1.0}),
      (ProceduralStyle.gradientMesh, {"meshKind": 2.0}),
      (ProceduralStyle.flowWaves, {"waveKind": 1.0}),
      (ProceduralStyle.flowWaves, {"waveKind": 2.0}),
      (ProceduralStyle.starfield, {"warp": 1.0}),
      (ProceduralStyle.starfield, {"shooting": 1.0}),
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
