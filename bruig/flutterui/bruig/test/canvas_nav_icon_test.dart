import 'package:bruig/models/menus.dart';
import 'package:bruig/plugin_system/canvas/canvas_nav.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/canvas_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_nav_icon_test.dart covers the Canvas entry's own menu icon: that
// the entry shows it, that its two files ship and draw, that the drawing
// takes the menu's colour while the keyframe keeps its own, and that
// registering the entry again leaves the menu quiet.

MainMenuItem _canvasItem(MainMenuModel menu) =>
    menu.menus.firstWhere((e) => e.routeName == CanvasScreen.routeName);

/// _filters are the tints of the icon's pictures, bottom to top.
List<ColorFilter?> _filters(WidgetTester tester) => tester
    .widgetList<SvgPicture>(find.byType(SvgPicture))
    .map((p) => p.colorFilter)
    .toList();

Widget _icon(Color color, {double? box}) => MaterialApp(
      home: Center(
        child: IconTheme(
          data: IconThemeData(color: color),
          child: box == null
              ? const CanvasMenuIcon()
              : SizedBox.square(dimension: box, child: const CanvasMenuIcon()),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test("the Canvas entry shows its own icon, not the Pen tool's pencil", () {
    var menu = MainMenuModel();
    var prefs = CanvasPreferences()..enabled = true;
    CanvasNavModel().update(prefs, menu);

    expect(_canvasItem(menu).icon, isA<CanvasMenuIcon>());
  });

  test("both halves of the icon ship with the app, on the same box", () async {
    for (var asset in [canvasMenuDrawing, canvasMenuKey]) {
      var svg = await rootBundle.loadString(asset);
      expect(svg, contains('viewBox="0 0 24 24"'),
          reason: "$asset: one box, or the keyframe would sit off the path");
    }
  });

  testWidgets("the drawing takes the menu's colour, the keyframe stays orange",
      (tester) async {
    const unselected = Color(0xFFE4E3E6);
    const selected = Color(0xFF00C2A8);

    await tester.pumpWidget(_icon(unselected));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_filters(tester), const [
      ColorFilter.mode(unselected, BlendMode.srcIn),
      ColorFilter.mode(canvasKeyColor, BlendMode.srcIn),
    ]);

    await tester.pumpWidget(_icon(selected));
    await tester.pumpAndSettle();
    expect(_filters(tester), const [
      ColorFilter.mode(selected, BlendMode.srcIn),
      ColorFilter.mode(canvasKeyColor, BlendMode.srcIn),
    ]);
  });

  // The sidebar leaves the icon at its own size; the phone's bar hands it a
  // fixed box. The two pictures must come out the same size either way.
  testWidgets("both pictures are one size, free or boxed", (tester) async {
    for (var box in [null, 18.0, 40.0]) {
      await tester.pumpWidget(_icon(const Color(0xFFE4E3E6), box: box));
      await tester.pumpAndSettle();
      var want = Size.square(box ?? 24);
      for (var e in find.byType(SvgPicture).evaluate()) {
        expect(e.size, want, reason: "box $box");
      }
    }
  });

  // The nav model registers on every run while Canvas is on, and the menu
  // is one of the things it listens to: an entry that looked changed each
  // time would notify, run the model again, and never stop.
  testWidgets("registering it again does not notify", (tester) async {
    var menu = MainMenuModel();
    var prefs = CanvasPreferences()..enabled = true;
    var nav = CanvasNavModel();
    nav.update(prefs, menu);
    await tester.pump();

    var notified = 0;
    menu.addListener(() => notified++);
    nav.update(prefs, menu);
    await tester.pump();
    expect(notified, 0);
  });
}
