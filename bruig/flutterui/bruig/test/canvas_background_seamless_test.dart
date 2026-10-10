import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/generators.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/procedural_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_background_seamless_test.dart is a moving background made to loop:
// the same picture every loop, and the last frame running into the first
// without a jump, whatever the style is doing.

const int _w = 120, _h = 68;
const Rect _page = Rect.fromLTWH(0, 0, 120, 68);
const double _fps = 30;

Future<List<int>> _pixels(ProceduralSpec spec, double time) async {
  var recorder = ui.PictureRecorder();
  paintProcedural(ui.Canvas(recorder), _page, spec,
      time: time, frameRate: _fps);
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

/// _distance is how different two frames are: the mean difference of their
/// channels.
double _distance(List<int> a, List<int> b) {
  var sum = 0;
  for (var i = 0; i < a.length; i++) {
    for (var s in [24, 16, 8]) {
      sum += (((a[i] >> s) & 0xFF) - ((b[i] >> s) & 0xFF)).abs();
    }
  }
  return sum / (a.length * 3);
}

const _moving = ProceduralSpec(
  style: ProceduralStyle.flowWaves,
  params: {"waveKind": 2},
  background: Color(0xFF101020),
  foreground: Color(0xFF40E0A0),
  accent: Color(0xFFFF4080),
  vignette: 0,
  animated: true,
  speed: 3,
);

void main() {
  test("is saved only while it moves", () {
    var spec = _moving.copyWith(loopFrames: 90, loopBlend: 0.5);
    var back = ProceduralSpec.fromJson(spec.toJson());
    expect(back.loopFrames, 90);
    expect(back.loopBlend, 0.5);
    expect(back.seamless, isTrue);
    expect(spec.copyWith(animated: false).toJson().containsKey("loopFrames"),
        isFalse);
    expect(spec.copyWith(loopTimes: 2).seamless, isFalse,
        reason: "a movement counted in runs is timed by its runs");
  });

  testWidgets("draws the same picture every loop", (tester) async {
    var spec = _moving.copyWith(loopFrames: 60);
    late List<int> first, second, third;
    await tester.runAsync(() async {
      first = await _pixels(spec, 0.5);
      second = await _pixels(spec, 0.5 + 2);
      third = await _pixels(spec, 1.9);
    });
    expect(second, first);
    expect(third, isNot(first));
  });

  testWidgets("runs its last frame into its first without a jump",
      (tester) async {
    const frames = 60;
    var looped = _moving.copyWith(loopFrames: frames);
    late double step, jump, wrap;
    await tester.runAsync(() async {
      // How far the picture moves in one frame, anywhere in the middle.
      step = _distance(
          await _pixels(looped, 0.5), await _pixels(looped, 0.5 + 1 / _fps));
      // How far it moves from the last frame to the first, unlooped -- the
      // jump a GIF would show -- and looped.
      jump = _distance(await _pixels(_moving, (frames - 1) / _fps),
          await _pixels(_moving, 0));
      wrap = _distance(await _pixels(looped, (frames - 1) / _fps),
          await _pixels(looped, frames / _fps));
    });
    expect(jump, greaterThan(step * 3), reason: "unlooped, it jumps");
    expect(wrap, lessThan(step * 2), reason: "looped, it is one more frame");
  });

  testWidgets("is set from the movement, and fits the canvas in one press",
      (tester) async {
    var current = _moving;
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider(
        create: (_) => ThemeNotifier(doLoad: false),
        child: Scaffold(
          body: SingleChildScrollView(
            child: CanvasControlScope(
              maxWidth: 300,
              child: SizedBox(
                width: 300,
                child: StatefulBuilder(
                  builder: (context, setState) => ProceduralSettings(
                    spec: current,
                    canvasFrames: 150,
                    onChanged: (s) => setState(() => current = s),
                    onBegin: () {},
                    onCommit: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("seamlessBlend")), findsNothing);
    await tester.tap(find.byKey(const ValueKey("seamlessFit")));
    await tester.pumpAndSettle();
    expect(current.loopFrames, 150);
    expect(find.byKey(const ValueKey("seamlessBlend")), findsOneWidget);
  });
}
