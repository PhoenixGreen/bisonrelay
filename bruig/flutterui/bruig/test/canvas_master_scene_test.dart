import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_master_scene_test.dart is the canvas every scene plays under.

Future<Map<int, int>> _ink(CanvasDocument document) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 200, 120),
      Paint()..color = const Color(0xFF000000));
  paintCanvasDocument(canvas, document, frame: 0);
  var picture = recorder.endRecording();
  var image = await picture.toImage(200, 120);
  var bytes = (await image.toByteData())!;
  var counts = <int, int>{};
  for (var i = 0; i < bytes.lengthInBytes; i += 4) {
    var pixel = bytes.getUint32(i);
    counts[pixel] = (counts[pixel] ?? 0) + 1;
  }
  image.dispose();
  picture.dispose();
  return counts;
}

CanvasDocument _document({bool masterOn = false}) => CanvasDocument(
      size: const CanvasSize(width: 200, ratio: CanvasRatio.wide),
      background: const CanvasBackground(),
      master: CanvasScene(id: "m", name: "Master", elements: [
        ShapeElement(
          const ElementBase(id: "logo", x: 0, y: 0, width: 40, height: 40),
          fill: const Color(0xFF00FF00),
        ),
      ]),
      masterOn: masterOn,
    ).withScenes([
      CanvasScene(id: "a", elements: [
        ShapeElement(
          const ElementBase(id: "s1", x: 100, y: 0, width: 40, height: 40),
          fill: const Color(0xFFFF0000),
        ),
      ]),
      const CanvasScene(id: "b"),
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const green = 0x00FF00FF;
  const red = 0xFF0000FF;

  testWidgets("what is on it appears on every scene", (tester) async {
    late Map<int, int> off;
    late Map<int, int> first;
    late Map<int, int> second;
    await tester.runAsync(() async {
      off = await _ink(_document());
      first = await _ink(_document(masterOn: true));
      second = await _ink(_document(masterOn: true).goToScene(1));
    });

    expect(off[green] ?? 0, 0, reason: "nothing until it is switched on");
    expect(first[green] ?? 0, greaterThan(1000));
    expect(first[red] ?? 0, greaterThan(1000), reason: "and the scene as well");
    expect(second[green] ?? 0, greaterThan(1000),
        reason: "on the next scene too, which has nothing of its own");
    expect(second[red] ?? 0, 0);
  });

  testWidgets("and is drawn once while it is the canvas being edited",
      (tester) async {
    // Drawn as itself and as the thing behind itself, an element on the
    // master would be painted twice -- which is invisible until something on
    // it is half transparent, and then it is a mystery.
    late Map<int, int> editing;
    await tester.runAsync(() async {
      editing = await _ink(_document(masterOn: true).copyWith(onMaster: true));
    });
    expect(editing[green] ?? 0, greaterThan(1000));
    expect(editing[red] ?? 0, 0,
        reason: "the scene it was covering is not drawn under it");
  });

  test("its length is the whole sequence, and follows the scenes", () {
    var it = _document(masterOn: true).withScenes([
      const CanvasScene(id: "a", frames: 24),
      const CanvasScene(id: "b", frames: 36),
    ]);
    expect(it.sequenceFrames, 60);

    // On the master, the timeline is that long rather than any scene's.
    expect(it.copyWith(onMaster: true).frames, 60);

    // A scene made longer, and a scene added, both change it.
    var longer = it.withScene(0, it.allScenes.first.copyWith(frames: 30));
    expect(longer.copyWith(onMaster: true).frames, 66);
    expect(longer.addScene().copyWith(onMaster: true).frames, greaterThan(66));
  });

  test("and a transition that overlaps shortens it", () {
    // Two scenes playing at once are one stretch of time, not two.
    var it = const CanvasDocument().withScenes([
      const CanvasScene(id: "a", frames: 24),
      const CanvasScene(id: "b", frames: 24),
    ]);
    expect(it.sequenceFrames, 48);

    var faded = it.withScene(
        0,
        it.allScenes.first.copyWith(
            transition: const SceneTransition(
                kind: SceneTransitionKind.fade, frames: 8, overlap: 8)));
    expect(faded.sequenceFrames, 40);
    expect(faded.startOfScene(1), 16,
        reason: "the second scene starts while the first is still going");
  });
}
