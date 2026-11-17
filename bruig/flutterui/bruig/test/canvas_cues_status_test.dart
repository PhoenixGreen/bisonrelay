import 'dart:typed_data';

import 'support/canvas_app.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/cues_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_cues_status_test.dart is what finding cues says back: shown as
// words on the panel, not tucked behind a "?" that has to be clicked to be
// read -- which is where it was.

void main() {
  testWidgets("finding cues says how many, where it can be read",
      (tester) async {
    // Two lines of voice with a pause between them, as the waveform reads.
    var peaks = Float32List(400);
    for (var i = 20; i < 150; i++) {
      peaks[i] = 0.8;
    }
    for (var i = 250; i < 380; i++) {
      peaks[i] = 0.8;
    }
    CanvasController.seedWaveform("voice1", peaks);
    var voice = AudioElement(const ElementBase(id: "v", name: "Voice"),
        clip: const MediaClip(
            timed: true,
            playlist: [MediaSource(assetId: "voice1", length: 8)]));
    var c = CanvasController(
        CanvasDocument(frames: 200).addElement(voice));
    addTearDown(c.dispose);
    await tester.pumpWidget(canvasApp(SingleChildScrollView(child: CanvasCuesSection(controller: c))));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey("cueFind")));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(c.cues.length, 2);
    expect(find.text("2 word cues, one at each line."), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
