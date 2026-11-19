import 'package:bruig/models/menus.dart';
import 'package:bruig/plugin_system/canvas/canvas_nav.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/canvas_screen.dart';
import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/plugin_test_support.dart';

// menu_accent_icon_test.dart covers the menu icons drawn in two parts, the
// Canvas entry's and the Writing entry's: that each entry shows its own, that
// the files ship and draw, that the drawing takes the menu's colour while the
// accent keeps its orange, and that registering an entry again leaves the
// menu quiet.

const _canvas = SidebarAccentSvgIcon(canvasMenuDrawing, canvasMenuKey);
const _writing = SidebarAccentSvgIcon(writingMenuDrawing, writingMenuKey);

Widget? _iconOf(MainMenuModel menu, String route) =>
    menu.menus.firstWhere((e) => e.routeName == route).icon;

/// _filters are the tints of the icon's pictures, bottom to top.
List<ColorFilter?> _filters(WidgetTester tester) => tester
    .widgetList<SvgPicture>(find.byType(SvgPicture))
    .map((p) => p.colorFilter)
    .toList();

Widget _show(Widget icon, Color color, {double? box}) => MaterialApp(
      home: Center(
        child: IconTheme(
          data: IconThemeData(color: color),
          child:
              box == null ? icon : SizedBox.square(dimension: box, child: icon),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test("the Canvas entry shows its own icon, not the Pen tool's pencil", () {
    var menu = MainMenuModel();
    CanvasNavModel().update(CanvasPreferences()..enabled = true, menu);

    var icon = _iconOf(menu, CanvasScreen.routeName);
    expect(icon, isA<SidebarAccentSvgIcon>());
    expect((icon as SidebarAccentSvgIcon).drawingAsset, canvasMenuDrawing);
    expect(icon.accentAsset, canvasMenuKey);
  });

  test("the Writing entry shows its own icon, not the Drafts pencil", () {
    var menu = MainMenuModel();
    WritingNavModel()
        .update(FakePlugins({PluginCapability.spellcheckData}), menu);

    var icon = _iconOf(menu, WritingScreen.routeName);
    expect(icon, isA<SidebarAccentSvgIcon>());
    expect((icon as SidebarAccentSvgIcon).drawingAsset, writingMenuDrawing);
    expect(icon.accentAsset, writingMenuKey);
  });

  test("every half of both icons ships with the app, on the same box",
      () async {
    for (var asset in [
      canvasMenuDrawing,
      canvasMenuKey,
      writingMenuDrawing,
      writingMenuKey
    ]) {
      var svg = await rootBundle.loadString(asset);
      expect(svg, contains('viewBox="0 0 24 24"'),
          reason: "$asset: one box, or the accent would sit off the drawing");
    }
  });

  for (var (name, icon) in [("Canvas", _canvas), ("Writing", _writing)]) {
    testWidgets("$name: the drawing takes the menu's colour, the accent stays",
        (tester) async {
      const unselected = Color(0xFFE4E3E6);
      const selected = Color(0xFF00C2A8);

      await tester.pumpWidget(_show(icon, unselected));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_filters(tester), const [
        ColorFilter.mode(unselected, BlendMode.srcIn),
        ColorFilter.mode(menuAccentOrange, BlendMode.srcIn),
      ]);

      await tester.pumpWidget(_show(icon, selected));
      await tester.pumpAndSettle();
      expect(_filters(tester), const [
        ColorFilter.mode(selected, BlendMode.srcIn),
        ColorFilter.mode(menuAccentOrange, BlendMode.srcIn),
      ]);
    });
  }

  // The sidebar leaves the icon at its own size; the phone's bar hands it a
  // fixed box. The two pictures must come out the same size either way.
  testWidgets("both pictures are one size, free or boxed", (tester) async {
    for (var box in [null, 18.0, 40.0]) {
      await tester
          .pumpWidget(_show(_writing, const Color(0xFFE4E3E6), box: box));
      await tester.pumpAndSettle();
      var want = Size.square(box ?? 24);
      for (var e in find.byType(SvgPicture).evaluate()) {
        expect(e.size, want, reason: "box $box");
      }
    }
  });

  // Each nav model registers on every run while its feature is on, and the
  // menu is one of the things it listens to: an entry that looked changed
  // each time would notify, run the model again, and never stop.
  testWidgets("registering an entry again does not notify", (tester) async {
    var menu = MainMenuModel();
    var prefs = CanvasPreferences()..enabled = true;
    var plugins = FakePlugins({PluginCapability.spellcheckData});
    var canvas = CanvasNavModel();
    var writing = WritingNavModel();
    canvas.update(prefs, menu);
    writing.update(plugins, menu);
    await tester.pump();

    var notified = 0;
    menu.addListener(() => notified++);
    canvas.update(prefs, menu);
    writing.update(plugins, menu);
    await tester.pump();
    expect(notified, 0);
  });
}
