import 'package:bruig/models/menus.dart';
import 'package:bruig/theming_system/theme_editor.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// menu_icon_picker_test.dart drives the icon control in Settings >
// Appearance > Menu as a user does: it taps it.
//
// The model tests next door (menu_icons_test.dart) covered what happens once
// a choice comes back, and passed while the control was in fact dead on
// arrival -- the tap handler read the theme through the listening form of
// Provider.of, which asserts outright when called from anything but a build,
// so the picker never opened at all. Nothing that only calls setItemIcon can
// catch that; it takes a tap.

Widget _app() => MultiProvider(
      providers: [
        ChangeNotifierProvider<MainMenuModel>(create: (c) => MainMenuModel()),
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: MenuSection())),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('every menu row offers its icon as a control', (tester) async {
    await tester.pumpWidget(_app());
    // One per destination the navigation carries.
    expect(find.byTooltip('Change icon'), findsWidgets);
  });

  testWidgets('tapping an icon opens the picker', (tester) async {
    await tester.pumpWidget(_app());

    await tester.tap(find.byTooltip('Change icon').first);
    await tester.pumpAndSettle();

    // No exception, and the picker is really up.
    expect(tester.takeException(), isNull);
    expect(find.text('Choose SVG...'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('the picker offers every bundled icon', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.byTooltip('Change icon').first);
    await tester.pumpAndSettle();

    // The grid is the bundled set; the row's own icon is drawn by the same
    // MenuIcon widget only once it has been changed, so at this point there
    // is exactly one tile per bundled asset.
    expect(find.byType(MenuIcon), findsNWidgets(bundledMenuIcons.length));
  });

  testWidgets('Default is dead until the icon has actually been changed',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.byTooltip('Change icon').first);
    await tester.pumpAndSettle();

    // Nothing to undo yet -- an enabled button that does nothing reads as
    // broken.
    var reset = tester.widget<TextButton>(
        find.ancestor(of: find.text('Default'), matching: find.byType(TextButton)));
    expect(reset.onPressed, isNull);
  });

  testWidgets('choosing an icon from the grid changes that row', (tester) async {
    await tester.pumpWidget(_app());
    var menu = Provider.of<MainMenuModel>(
        tester.element(find.byType(MenuSection)),
        listen: false);
    var route = menu.menus.where((e) => !e.hiddenFromSideBar).first.routeName;
    expect(menu.iconPathFor(route), isNull);

    await tester.tap(find.byTooltip('Change icon').first);
    await tester.pumpAndSettle();
    // The tiles are in bundledMenuIcons order, so the second one is a
    // different icon from whatever the first row started with.
    await tester.tap(find.byType(MenuIcon).at(1));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(menu.iconPathFor(route), bundledMenuIcons[1]);
    // And the picker closed behind the choice.
    expect(find.text('Choose SVG...'), findsNothing);
  });

  testWidgets('the reset comes alive once there is something to reset',
      (tester) async {
    await tester.pumpWidget(_app());
    var menu = Provider.of<MainMenuModel>(
        tester.element(find.byType(MenuSection)),
        listen: false);
    var route = menu.menus.where((e) => !e.hiddenFromSideBar).first.routeName;

    await tester.tap(find.byTooltip('Change icon').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MenuIcon).at(1));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Change icon').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Default'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(menu.iconPathFor(route), isNull);
  });
}
