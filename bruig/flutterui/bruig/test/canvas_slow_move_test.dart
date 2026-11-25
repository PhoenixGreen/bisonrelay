import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/generators.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart'
    show sceneFraming;
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart'
    show paintCanvasDocument, slowMoveMost, smoothMove;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_slow_move_test.dart is two things Ken saw in an exported video
// (2026-11-25, "Decred in a bear market"):
//
// - Words under a scene's slow move (SceneCamera) moved in steps: drawn
//   through a zoom that changes a little each frame, the words were put on
//   fractions of a pixel only so fine, so they held for frames then jumped,
//   while everything else drifted. The scene is now drawn unzoomed and the
//   whole picture zoomed, which moves by any fraction of a pixel.
// - The Metal background came out blotchy and grainy: worked out at most
//   448 points a side, a 1920-wide export blew each point up four times.
//   An export now works it out at its own pixels.

const _words = TextElement(
  ElementBase(id: "t", x: 40, y: 280, width: 320, height: 40),
  // One line: two would give the rows measured two left edges.
  text: "VERIFIABLE",
  textSpec: TextSpec(fontSize: 17, weight: 600, color: Color(0xFFFFFFFF)),
);

// On a flat grey, so only the words change from frame to frame, and a dark
// ring round them would show.
const _grey = 0x40;

CanvasDocument _slowMove() => const CanvasDocument(
      size: CanvasSize(width: 400, ratio: CanvasRatio.square),
      frameRate: 24,
      background: CanvasBackground(
          spec: ProceduralSpec(
              style: ProceduralStyle.plain,
              background: Color(0xFF404040),
              vignette: 0)),
      scenes: [
        CanvasScene(
            id: "s",
            name: "Slow move",
            elements: [_words],
            frames: 100,
            camera: SceneCamera(fromZoom: 1, toZoom: 1.04)),
      ],
    );

/// _leftEdge is where the words' left edge is drawn in [image], to a
/// fraction of a pixel: on each of [rows], where the brightness first
/// passes half way, averaged. The same rows every frame, or a letter's
/// corner coming into one would look like a jump.
Future<double> _leftEdge(ui.Image image, Iterable<int> rows) async {
  var bytes = (await image.toByteData())!;
  var w = image.width;
  int red(int x, int y) => bytes.getUint8((y * w + x) * 4);
  var at = <double>[];
  for (var y in rows) {
    for (var x = 1; x < w ~/ 2; x++) {
      var a = red(x - 1, y), b = red(x, y);
      if (a < 128 && b >= 128) {
        at.add(x - 1 + (128 - a) / (b - a));
        break;
      }
    }
  }
  expect(at, isNotEmpty, reason: "the words are drawn");
  return at.reduce((p, q) => p + q) / at.length;
}

/// _middleRows are the middle third of the rows the words are drawn on in
/// [image]: measured on the same rows every frame.
Future<List<int>> _middleRows(ui.Image image) async {
  var bytes = (await image.toByteData())!;
  var lit = [
    for (var y = 0; y < image.height; y++)
      if (Iterable<int>.generate(image.width ~/ 2)
          .any((x) => bytes.getUint8((y * image.width + x) * 4) > 200))
        y
  ];
  var third = (lit.last - lit.first) ~/ 3;
  return [for (var y = lit.first + third; y <= lit.last - third; y++) y];
}

void main() {
  testWidgets("words under a slow move move every frame, not in steps",
      (tester) async {
    var edges = <double>[];
    await tester.runAsync(() async {
      var document = _slowMove();
      var first = await renderFrame(document, frame: 40);
      var rows = await _middleRows(first);
      first.dispose();
      for (var f = 40; f < 48; f++) {
        var image = await renderFrame(document, frame: f);
        edges.add(await _leftEdge(image, rows));
        image.dispose();
      }
    });
    // Zooming in, the edge moves out to the left a few hundredths of a
    // pixel a frame. Drawn through the zoom, it sat still for frames at a
    // time, then jumped.
    for (var i = 1; i < edges.length; i++) {
      expect(edges[i], lessThan(edges[i - 1] - 0.005),
          reason: "frame ${40 + i} moved on from the one before: $edges");
    }
  });

  testWidgets("and as it plays in the app, drawn as the stage draws it",
      (tester) async {
    // The stage draws the scene's slow move only while it plays, at the
    // screen's pixels: the words must glide there too, not only in a file.
    var document = _slowMove().goToScene(0);
    Future<ui.Image> frame(int f) {
      var recorder = ui.PictureRecorder();
      paintCanvasDocument(ui.Canvas(recorder), document,
          frame: f, camera: sceneFraming(document, f));
      var picture = recorder.endRecording();
      return picture.toImage(400, 400).whenComplete(picture.dispose);
    }

    var edges = <double>[];
    await tester.runAsync(() async {
      var first = await frame(40);
      var rows = await _middleRows(first);
      first.dispose();
      for (var f = 40; f < 48; f++) {
        var image = await frame(f);
        edges.add(await _leftEdge(image, rows));
        image.dispose();
      }
    });
    for (var i = 1; i < edges.length; i++) {
      expect(edges[i], lessThan(edges[i - 1] - 0.005),
          reason: "frame ${40 + i} moved on from the one before: $edges");
    }
  });

  testWidgets("the words stay sharp: no dark ring, edges still hard",
      (tester) async {
    // Zoomed as a layer by the renderer, the words came out soft and ringed
    // in dark (Ken: "the text on the intro screen now looks worse"). Drawn
    // at the move's closest and only shrunk, they keep their edges.
    late List<int> reds;
    late int width;
    await tester.runAsync(() async {
      var image = await renderFrame(_slowMove(), frame: 60);
      var bytes = (await image.toByteData())!;
      width = image.width;
      reds = [
        for (var i = 0; i < bytes.lengthInBytes; i += 4) bytes.getUint8(i)
      ];
      image.dispose();
    });
    expect(reds.reduce(math.min), greaterThanOrEqualTo(_grey - 2),
        reason: "nothing darker than the grey the words are on");
    // Across an edge, from the grey to the white, in at most two pixels.
    var row = reds.indexWhere((r) => r > 250) ~/ width;
    var line = reds.sublist(row * width, row * width + width);
    var hard = 0;
    for (var x = 2; x < width; x++) {
      if (line[x - 2] < _grey + 20 && line[x] > 230) hard++;
    }
    expect(hard, greaterThan(0), reason: "a letter's edge is still crisp");
  });

  test("a slow move is a picture only near the page's own size", () {
    expect(smoothMove(1.04), isTrue);
    expect(smoothMove(1.2), isTrue);
    expect(smoothMove(2), isFalse, reason: "too big a picture every frame");
    // Drawn as big as the move's closest, so never magnified.
    const move = SceneCamera(fromZoom: 1, toZoom: 1.04);
    expect(slowMoveMost(move, 1.01), 1.04);
    expect(
        slowMoveMost(const SceneCamera(fromZoom: 0.9, toZoom: 0.95), 0.9), 1.0);
  });

  test("an export works the metal out at its own pixels", () {
    const page = Rect.fromLTWH(0, 0, 1280, 720);
    expect(latticeSize(page), (448, 448), reason: "the editor's, for speed");
    var exported = atExportDetail(1.5, () => latticeSize(page));
    expect(exported, (1920, 1080), reason: "a point an output pixel");
    expect(latticeSize(page), (448, 448), reason: "and the editor's after");
    expect(atExportDetail(10, () => latticeSize(page)).$1, 4096,
        reason: "within reason");
  });
}
