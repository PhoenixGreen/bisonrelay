import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/canvas_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_studio_colors_test.dart is the palette the mixer and effects are
// drawn in: Studio, or the app's theme, with any role changed by hand -- and
// remembered.

void main() {
  test("Studio, the theme, and a role changed by hand", () {
    var light = ColorScheme.fromSeed(seedColor: Colors.indigo);
    var studio = StudioColors.resolve(StudioLook.studio, const {}, light);
    expect(studio.on, const Color(0xFFF2B33D));
    var themed = StudioColors.resolve(StudioLook.theme, const {}, light);
    expect(themed.on, light.primary);
    expect(themed.strip, light.surfaceContainer);
    expect(themed.arm, light.error);
    var mine = StudioColors.resolve(
        StudioLook.studio, {StudioRole.on: Colors.pink}, light);
    expect(mine.on, Colors.pink);
    expect(mine.solo, studio.solo, reason: "only the role changed");
    expect(studio.onOn.computeLuminance(), lessThan(0.2),
        reason: "dark writing on the amber lamp");
  });

  test("the choice and the colours are remembered", () async {
    SharedPreferences.setMockInitialValues({});
    var prefs = CanvasPreferences();
    prefs.studioLook = StudioLook.theme;
    prefs.setStudioColour(StudioRole.solo, const Color(0xFF123456));
    await Future<void>.delayed(Duration.zero);
    var again = CanvasPreferences();
    await again.load();
    expect(again.studioLook, StudioLook.theme);
    expect(again.studioOverrides[StudioRole.solo], const Color(0xFF123456));
    again.setStudioColour(StudioRole.solo, null);
    expect(again.studioOverrides, isEmpty);
  });

  testWidgets("chosen in Settings > Plugins > Canvas", (tester) async {
    SharedPreferences.setMockInitialValues({});
    var prefs = CanvasPreferences()..enabled = true;
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>.value(value: prefs),
      ],
      child: const MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(child: CanvasSettingsSection()))),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("studioColour-on")), findsOneWidget);
    await tester.tap(find.text("Follow my theme"));
    await tester.pumpAndSettle();
    expect(prefs.studioLook, StudioLook.theme);
    prefs.setStudioColour(StudioRole.on, Colors.pink);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("studioColourReset-on")));
    await tester.pumpAndSettle();
    expect(prefs.studioOverrides, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
