import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/sidebar_layout.dart';
import 'package:bruig/plugin_system/canvas/render/render_caches.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/canvas_screen.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/canvas_app.dart';
import 'support/canvas_sidebar_host.dart';
import 'support/canvas_audio_fake.dart';
import 'support/element_samples.dart';

// canvas_leaks_test.dart is the editor opened on every kind of element,
// used and shut, under Flutter's leak tracker: nothing it made may be left
// undisposed -- painters, notifiers, pictures. Ken, 2026-11-17: a check
// found 3,114 text painters a session dropped undisposed, three of the
// controller's notifiers never disposed, and caches that kept every sound
// the clip editor opened.
//
// Each workload runs once untracked first, so what lives as long as the app
// (the preset stores, a few module-level notifiers) is made then and not
// counted; the render caches, which keep painters on purpose, are emptied
// before a tracked test ends. Run alone (test_bundles/generate.dart): leak
// tracking, once on, is on for the whole process.

/// everything is a page with one of every kind of element, its sorts and
/// filled-in versions; not the 3D character, whose scene a test cannot make.
CanvasDocument everything() {
  var doc = const CanvasDocument(frames: 96, frameRate: 24);
  var k = 0;
  for (var (_, e) in [...elementSamples(), ...filledSamples()]) {
    if (e.kind == ElementKind.character3d) continue;
    doc = doc.addElement(e.rebase(e.base.copyWith(
        id: "e${k++}", x: 40.0 + (k % 8) * 150, y: 40.0 + (k ~/ 8) * 120)));
  }
  return doc;
}

/// editor opens the whole editor, picks each element in turn, plays a
/// second, undoes and redoes, and shuts it.
Future<void> editor(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  CanvasScreen.framedForTest = (page) => page;
  setTestScreen(tester, const Size(1600, 1000));
  var controller = CanvasController(everything(), audioEngine: FakeEngine({}));
  var prefs = CanvasPreferences()
    ..timeline = true
    ..sidebars = const SidebarLayout(mode: SidebarMode.hidden);
  await tester.pumpWidget(canvasApp(const CanvasScreen(), prefs: prefs, extra: [
    ChangeNotifierProvider<CanvasController>.value(value: controller),
  ]));
  await tester.pump(const Duration(milliseconds: 500));
  for (var e in controller.document.elements) {
    controller.selectOnly(e.id);
    await tester.pump(const Duration(milliseconds: 16));
  }
  controller.play();
  for (var i = 0; i < 24; i++) {
    await tester.pump(const Duration(milliseconds: 42));
  }
  controller.pause();
  controller.undo();
  controller.redo();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  controller.dispose();
  prefs.dispose();
  CanvasScreen.framedForTest = null;
  clearRenderCaches();
}

/// settings opens every element's settings, every section open, in turn.
Future<void> settings(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  CanvasSection.openAll = true;
  var controller = CanvasController(everything(), audioEngine: FakeEngine({}));
  await pumpCanvasApp(tester, designSidebar(controller),
      size: const Size(420, 1000));
  for (var e in controller.document.elements) {
    controller.selectOnly(e.id);
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  controller.dispose();
  CanvasSection.openAll = false;
  clearRenderCaches();
}

void main() {
  LeakTesting.enable();
  var tracked = LeakTesting.settings.withTrackedAll().withCreationStackTrace();

  testWidgets("first, untracked: what lasts the app's life is made",
      experimentalLeakTesting: LeakTesting.settings.withIgnoredAll(),
      (tester) async {
    await editor(tester);
    await settings(tester);
  });

  testWidgets("the editor opened, used and shut leaves nothing undisposed",
      experimentalLeakTesting: tracked, editor);

  testWidgets("every element's settings opened in turn leave nothing",
      experimentalLeakTesting: tracked, settings);
}
