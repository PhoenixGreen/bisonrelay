import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/document_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'canvas_audio_fake.dart';

// A book or a PDF is drawn with the looks' shaders as a video is (Ken,
// 2026-11-13: the Decred infographic's book had none of the worn print its
// video had). Its own file: the shaders, once loaded, stay loaded for the
// rest of the process, so a test before this one that drew a video frame
// would hide the bug.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("a page's Wear is drawn, with nothing drawn before it",
      (tester) async {
    var doc = CanvasDocument(
      size: const CanvasSize(ratio: CanvasRatio.wide, width: 320),
      scenes: [
        CanvasScene(id: "one", elements: [
          ShapeElement(
              const ElementBase(id: "s", x: 0, y: 0, width: 320, height: 180),
              fill: const Color(0xFFFFFFFF)),
        ]),
      ],
    );
    var c = CanvasController(doc, audioEngine: FakeEngine({}));
    var made = c.addMotionDevice("s", MotionDeviceKind.wear);
    c.setMotionDevices("s", [
      for (var d in c.motionDevicesOf("s"))
        d.id == made ? d.withValue("amount", 0.6) : d,
    ]);
    var worn = c.document;
    c.dispose();

    Future<int> holes(CanvasDocument d) async {
      var n = 0;
      await tester.runAsync(() async {
        var image = await renderDocumentPage(d, 0, scale: 0.5);
        var bytes =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        image.dispose();
        // White shape on the page: a pixel worn through is not white.
        for (var i = 0; i < bytes.lengthInBytes; i += 4) {
          if (bytes.getUint8(i) < 200) n++;
        }
      });
      return n;
    }

    expect(await holes(worn), greaterThan(200), reason: "worn through");
  });
}
