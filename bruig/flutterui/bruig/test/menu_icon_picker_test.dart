import 'package:bruig/models/menus.dart';
import 'support/canvas_app.dart';
import 'package:bruig/theming_system/theme_editor.dart';
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

Widget _app() => canvasApp(SingleChildScrollView(child: MenuSection()), extra: [
      ChangeNotifierProvider<MainMenuModel>(create: (c) => MainMenuModel())
    ]);

/// _resetButton is the picker's own "Default": the icon-set dropdown behind
/// the dialog says "Default" too, so the word alone finds two.
final _resetButton =
    find.ancestor(of: find.text('Default'), matching: find.byType(TextButton));

/// _setShown is what the icon-set dropdown currently reads.
String? _setShown(WidgetTester tester) => tester
    .widget<DropdownButton<String>>(find.byKey(const ValueKey("menuIconSet")))
    .value;

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
    expect(_resetButton, findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('the picker offers every bundled icon', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.byTooltip('Change icon').first);
    await tester.pumpAndSettle();

    // The grids are the bundled icons and then each set's; the row's own
    // icon is drawn by the same MenuIcon widget only once it has been
    // changed, so at this point there is exactly one tile per asset.
    var offered = [
      ...bundledMenuIcons,
      for (var set in menuIconSets) ...set.all,
    ];
    expect(find.byType(MenuIcon), findsNWidgets(offered.length));
    expect(offered.toSet().length, offered.length,
        reason: "an icon offered twice would show two tiles as chosen");
  });

  testWidgets('the picker offers each set under its name', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.byTooltip('Change icon').first);
    await tester.pumpAndSettle();

    var dialog = find.byType(AlertDialog);
    for (var set in menuIconSets) {
      expect(find.descendant(of: dialog, matching: find.text(set.name)),
          findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('one icon from a set can go on one area', (tester) async {
    await tester.pumpWidget(_app());
    var menu = Provider.of<MainMenuModel>(
        tester.element(find.byType(MenuSection)),
        listen: false);
    var route = menu.menus.where((e) => !e.hiddenFromSideBar).first.routeName;

    await tester.tap(find.byTooltip('Change icon').first);
    await tester.pumpAndSettle();
    // The last tile of the last set: nothing to do with this area.
    var stray = brSketchIcons.all.last;
    await tester.ensureVisible(find.byType(MenuIcon).last);
    await tester.tap(find.byType(MenuIcon).last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(menu.iconPathFor(route), stray);
    // One area out of step with the rest is neither set.
    expect(menu.iconSet, isNull);
    expect(_setShown(tester), "Mixed");
  });

  testWidgets('a set goes on every area from the dropdown, and comes off',
      (tester) async {
    await tester.pumpWidget(_app());
    var menu = Provider.of<MainMenuModel>(
        tester.element(find.byType(MenuSection)),
        listen: false);
    expect(_setShown(tester), "Default");

    await tester.tap(find.byKey(const ValueKey("menuIconSet")));
    await tester.pumpAndSettle();
    // "Mixed" is a state, not a choice.
    expect(find.text("Mixed"), findsNothing);
    await tester.tap(find.text(brSketchIcons.name).last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(menu.iconSet, same(brSketchIcons));
    expect(_setShown(tester), brSketchIcons.name);
    // Every row whose area the set covers now shows a two-part icon.
    expect(find.byType(SidebarAccentSvgIcon),
        findsNWidgets(brSketchIcons.icons.length));

    await tester.tap(find.byKey(const ValueKey("menuIconSet")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Default").last);
    await tester.pumpAndSettle();

    expect(menu.iconSet, isNull);
    expect(menu.currentIcons(), isEmpty);
    expect(find.byType(SidebarAccentSvgIcon), findsNothing);
  });

  testWidgets('Default is dead until the icon has actually been changed',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.byTooltip('Change icon').first);
    await tester.pumpAndSettle();

    // Nothing to undo yet -- an enabled button that does nothing reads as
    // broken.
    var reset = tester.widget<TextButton>(_resetButton);
    expect(reset.onPressed, isNull);
  });

  testWidgets('choosing an icon from the grid changes that row',
      (tester) async {
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
    await tester.tap(_resetButton);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(menu.iconPathFor(route), isNull);
  });
}
