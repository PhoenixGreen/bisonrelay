import 'package:bruig/components/containers.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// sidebar_border_test.dart covers how the Sidebar area's Border setting is
// actually painted.
//
// A gradient is not a BorderSide and cannot go in a BoxDecoration's border
// at all, so it has to be painted as a box behind the sidebar rather than as
// part of it. Picking Border > Gradient used to resolve to no flat colour,
// which left the sidebar falling through to its own built-in divider -- the
// setting appeared to do nothing at all.

const _marker = Key('sidebar-child');

/// _decorations is every box decoration painted around the sidebar's child,
/// outermost first.
List<BoxDecoration> _decorations(WidgetTester tester) => tester
    .widgetList<Container>(find.ancestor(
        of: find.byKey(_marker), matching: find.byType(Container)))
    .map((c) => c.decoration)
    .whereType<BoxDecoration>()
    .toList();

Future<ThemeNotifier> _pump(WidgetTester tester, AreaStyle sidebar) async {
  var theme = ThemeNotifier(doLoad: false);
  theme.previewPreset(ThemePreset.seedFromDark()
      .copyWith(areas: {ThemeArea.subMenuTabBar: sidebar}));
  await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>.value(
    value: theme,
    child: const MaterialApp(
      home: Scaffold(
        body: SecondarySideMenu(width: 200, child: SizedBox(key: _marker)),
      ),
    ),
  ));
  return theme;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('left alone, the sidebar keeps its built-in right divider',
      (tester) async {
    await _pump(tester, const AreaStyle());
    var borders =
        _decorations(tester).map((d) => d.border).whereType<Border>().toList();
    expect(borders, isNotEmpty);
    var border = borders.first;
    expect(border.right.width, greaterThan(0));
    // Only the right edge -- this is a divider, not a frame.
    expect(border.left, BorderSide.none);
  });

  testWidgets('a solid border is drawn as the sidebar\'s own border sides',
      (tester) async {
    await _pump(
        tester,
        const AreaStyle(
          borderMode: AreaBackgroundMode.solid,
          borderColor: Color(0xFFFF0000),
          borderWidth: 3,
        ));
    var border = _decorations(tester)
        .map((d) => d.border)
        .whereType<Border>()
        .firstWhere((b) => b.right.width == 3);
    expect(border.right.color, const Color(0xFFFF0000));
  });

  testWidgets('a gradient border is painted as a box behind the sidebar',
      (tester) async {
    await _pump(
        tester,
        const AreaStyle(
          borderMode: AreaBackgroundMode.gradient,
          borderGradientColors: [Color(0xFFFF0000), Color(0xFF0000FF)],
          borderWidth: 4,
        ));

    var decorations = _decorations(tester);
    var gradients =
        decorations.map((d) => d.gradient).whereType<LinearGradient>();
    expect(gradients, isNotEmpty,
        reason: 'Border > Gradient painted no gradient at all');
    expect(gradients.first.colors,
        containsAll(const [Color(0xFFFF0000), Color(0xFF0000FF)]));

    // And the built-in divider is gone: leaving it would draw a flat line
    // down the middle of the gradient that just replaced it.
    for (var d in decorations) {
      expect(d.border, isNull,
          reason: 'a flat border was drawn alongside the gradient');
    }
  });

  testWidgets('a gradient border needs a width to show at all', (tester) async {
    // Consistent with the solid border, which also only appears once a
    // width is set -- a zero-width edge is no edge.
    await _pump(
        tester,
        const AreaStyle(
          borderMode: AreaBackgroundMode.gradient,
          borderGradientColors: [Color(0xFFFF0000), Color(0xFF0000FF)],
        ));
    expect(
        _decorations(tester).map((d) => d.gradient).whereType<LinearGradient>(),
        isEmpty);
  });
}
