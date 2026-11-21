import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/media/midi_input.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/sidebar_layout.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/canvas_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/canvas_app.dart';
import 'support/canvas_audio_fake.dart';

// canvas_screen_leaving_test.dart holds the Canvas page to taking down what
// it put up. The editing session outlives the page, so anything the page
// hands to the rest of the app (a MIDI keyboard's keys, its play button)
// would go on working the canvas after it has left the screen.

void main() {
  testWidgets("leaving the page gives the MIDI keyboard back", (tester) async {
    SharedPreferences.setMockInitialValues({});
    CanvasScreen.framedForTest = (page) => page;
    addTearDown(() => CanvasScreen.framedForTest = null);
    setTestScreen(tester, const Size(1600, 1000));
    var controller = CanvasController(
        const CanvasDocument(frames: 48, frameRate: 24),
        audioEngine: FakeEngine({}));
    addTearDown(controller.dispose);
    // The sidebar put away: it sits in the app's side menu, which needs the
    // chat client.
    var prefs = CanvasPreferences()
      ..sidebars = const SidebarLayout(mode: SidebarMode.hidden);
    var midi = MidiInput.shared;

    await tester
        .pumpWidget(canvasApp(const CanvasScreen(), prefs: prefs, extra: [
      ChangeNotifierProvider<CanvasController>.value(value: controller),
    ]));
    await tester.pump(const Duration(milliseconds: 500));
    expect(midi.onNote, isNotNull, reason: "the keyboard plays this canvas");
    expect(midi.onPlay, isNotNull);

    // Another page in its place.
    await tester.pumpWidget(canvasApp(const SizedBox(), prefs: prefs, extra: [
      ChangeNotifierProvider<CanvasController>.value(value: controller),
    ]));
    await tester.pump(const Duration(milliseconds: 500));
    expect(midi.onNote, isNull, reason: "a key no longer plays it");
    expect(midi.onControl, isNull);
    expect(midi.onCc, isNull);
    expect(midi.onPlay, isNull, reason: "nor does its play button start it");
    expect(midi.onRecord, isNull);
    expect(midi.onClip, isNull);
    expect(midi.clipAt, isNull);
  });
}
