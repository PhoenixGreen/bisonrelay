import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/sidebar_layout.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/canvas_screen.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/canvas_settings_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/guides_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_stage.dart';

import 'support/canvas_app.dart';
import 'support/canvas_audio_fake.dart';

// canvas_second_line_test.dart is the line that opens under the band on the
// Canvas page: the canvas settings, or the grid and guides (BandLine).
//
// It opens above the canvas and pushes it down. Drawn over the canvas, it
// would cover the top edge of the design, the part most likely to be worked
// on while the settings that do the work are open. The two lines share the
// one place, so opening one shuts the other.

void main() {
  /// open puts the Canvas page up, with nothing under its band.
  Future<void> open(WidgetTester tester) async {
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
    await tester
        .pumpWidget(canvasApp(const CanvasScreen(), prefs: prefs, extra: [
      ChangeNotifierProvider<CanvasController>.value(value: controller),
    ]));
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// press presses the band's button with [tip], and waits for the page to
  /// be laid out round what opened (the band's height is known a frame late).
  Future<void> press(WidgetTester tester, String tip) async {
    await tester.tap(find.byTooltip(tip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  const settings = "Canvas settings";
  const guides = "Grid, guides, rulers and snapping";

  Rect rectOf(WidgetTester tester, Type type) =>
      tester.getRect(find.byType(type));

  testWidgets("with nothing open the canvas starts under the band",
      (tester) async {
    await open(tester);
    expect(find.byType(CanvasSettingsPanel), findsNothing);
    expect(find.byType(CanvasGuidesPanel), findsNothing);
    expect(rectOf(tester, CanvasStage).top,
        rectOf(tester, CanvasSettingsBar).bottom);
  });

  testWidgets("the canvas settings push the canvas down", (tester) async {
    await open(tester);
    var whole = rectOf(tester, CanvasStage);

    await press(tester, settings);
    var line = rectOf(tester, CanvasSettingsPanel);
    var stage = rectOf(tester, CanvasStage);
    expect(line.top, rectOf(tester, CanvasSettingsBar).bottom,
        reason: "under the band");
    expect(stage.top, line.bottom,
        reason: "and the canvas starts below it, not behind it");
    expect(whole.height - stage.height, line.height,
        reason: "shorter by exactly the line");

    await press(tester, settings);
    expect(find.byType(CanvasSettingsPanel), findsNothing,
        reason: "pressed again, it shuts");
    expect(rectOf(tester, CanvasStage), whole);
  });

  testWidgets("and so do the grid and guides", (tester) async {
    await open(tester);
    await press(tester, guides);
    var line = rectOf(tester, CanvasGuidesPanel);
    expect(line.top, rectOf(tester, CanvasSettingsBar).bottom);
    expect(rectOf(tester, CanvasStage).top, line.bottom);
  });

  testWidgets("opening one shuts the other", (tester) async {
    await open(tester);
    await press(tester, settings);
    await press(tester, guides);
    expect(find.byType(CanvasGuidesPanel), findsOneWidget);
    expect(find.byType(CanvasSettingsPanel), findsNothing);

    await press(tester, settings);
    expect(find.byType(CanvasSettingsPanel), findsOneWidget);
    expect(find.byType(CanvasGuidesPanel), findsNothing);
  });
}
