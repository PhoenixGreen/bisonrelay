import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_export_backdrop_test.dart is the background being drawn once for a
// whole run of frames rather than once per frame.
//
// Generating a background is the most expensive thing on a canvas, and an
// export of a thirty-second animation generated the same still picture seven
// hundred and fifty times. What has to stay true is that the picture is the
// same one: an export that is fast and wrong is worse than a slow one.

CanvasDocument _document({
  ProceduralStyle style = ProceduralStyle.metal,
  bool animated = false,
  int frames = 6,
}) =>
    CanvasDocument(
      size: const CanvasSize(width: 200, ratio: CanvasRatio.square),
      frames: frames,
      background: CanvasBackground(
          spec: ProceduralSpec(
        style: style,
        animated: animated,
        background: const Color(0xFF101820),
        foreground: const Color(0xFFDDE6F0),
      )),
    );

Future<List<int>> _pixels(ui.Image image) async {
  var bytes = (await image.toByteData())!;
  return [for (var i = 0; i < bytes.lengthInBytes; i += 4) bytes.getUint32(i)];
}

void main() {
  testWidgets("a still background is kept and drawn again", (tester) async {
    late List<int> slow, quick;
    await tester.runAsync(() async {
      var document = _document();
      var backdrop = await ExportBackdrop.prepare(document);
      expect(backdrop, isNotNull, reason: "there is something to keep");

      var a = await renderFrame(document, frame: 2);
      var b = await renderFrame(document, frame: 2, backdrop: backdrop);
      slow = await _pixels(a);
      quick = await _pixels(b);
      a.dispose();
      b.dispose();
      backdrop!.dispose();
    });
    expect(quick, slow, reason: "the same picture, drawn the quick way");
  });

  testWidgets("a background that moves is not kept at all", (tester) async {
    // It is a different picture every frame, so there is nothing to keep --
    // and keeping the first one would freeze a background that is supposed to
    // be running.
    await tester.runAsync(() async {
      var backdrop = await ExportBackdrop.prepare(
          _document(style: ProceduralStyle.rain, animated: true));
      expect(backdrop, isNull);
    });
  });

  testWidgets("and neither is a document of several scenes", (tester) async {
    // Each scene brings its own background, so one picture cannot stand in
    // for the run.
    await tester.runAsync(() async {
      var document = _document().copyWith(scenes: [
        const CanvasScene(id: "a", name: "One", elements: []),
        const CanvasScene(id: "b", name: "Two", elements: []),
      ]);
      expect(await ExportBackdrop.prepare(document), isNull);
    });
  });

  testWidgets("it is rasterised at the size the export is written at",
      (tester) async {
    // At the document's own size and then blown up, a background exported at
    // four times the width would be a blurred background -- and the whole
    // reason an export names a width is that somebody wants the pixels.
    await tester.runAsync(() async {
      var document = _document();
      var one = await ExportBackdrop.prepare(document);
      var four = await ExportBackdrop.prepare(document, scale: 4);
      expect(four!.image.width, one!.image.width * 4);
      one.dispose();
      four.dispose();
    });
  });
}
