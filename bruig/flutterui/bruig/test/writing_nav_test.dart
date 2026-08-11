import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_support.dart';

// writing_nav_test.dart covers how the sidebar's four tabs are drawn.
//
// Reported: the tab row and the icon row above it looked like the same
// control twice. They were -- both drew the selected item as a filled
// secondaryContainer rectangle, so neither read as subordinate to the other.
// The tabs now carry a line instead of a block, and the tests below are
// mostly about that difference surviving, because it is the kind of thing a
// later tidy-up reintroduces without noticing.

WritingSidebarPage? _lastRequested;

Future<void> _mount(
  WidgetTester tester, {
  double width = 900,
  WritingSidebarPage page = WritingSidebarPage.mistakes,
  WritingPreferences? prefs,
}) async {
  var settings = prefs ?? WritingPreferences();
  var spellcheck = SpellcheckCapability(
      fetch: (_) async =>
          SpellcheckData(const ["the", "payment"], const [], []),
      prefs: settings);
  await spellcheck.update(FakePlugins({PluginCapability.spellcheckData}));

  _lastRequested = null;
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<SpellcheckCapability>.value(value: spellcheck),
      ChangeNotifierProvider<WritingPreferences>.value(value: settings),
      Provider<ThesaurusCapability?>.value(value: null),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: WritingSidebar(
            controller: TextEditingController(text: "the payment"),
            page: page,
            onPageChanged: (p) => _lastRequested = p,
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// _tabDecoration is the box drawn behind one tab.
BoxDecoration _tabDecoration(WidgetTester tester, WritingSidebarPage page) {
  var container = tester.widget<Container>(find
      .ancestor(of: find.byIcon(page.icon), matching: find.byType(Container))
      .first);
  return container.decoration as BoxDecoration;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // The complaint, stated as a test. A filled selected tab is what made the
  // two rows indistinguishable.
  testWidgets("the selected tab is not filled", (tester) async {
    await _mount(tester);
    expect(_tabDecoration(tester, WritingSidebarPage.mistakes).color, isNull,
        reason: "a filled tab is the icon row's way of showing selection, and "
            "using it here is what made the two look like one control");
  });

  testWidgets("the selected tab carries an underline", (tester) async {
    await _mount(tester);
    var accent = _tabDecoration(tester, WritingSidebarPage.mistakes)
        .border!
        .bottom
        .color;
    expect(accent, isNot(Colors.transparent));
    expect(
        _tabDecoration(tester, WritingSidebarPage.mistakes)
            .border!
            .bottom
            .width,
        2);
  });

  // Present but invisible on the others: a border that appears only on the
  // active tab changes the height of the rest, and the row twitches as the
  // selection moves.
  testWidgets("an unselected tab reserves the same underline", (tester) async {
    await _mount(tester);
    var other =
        _tabDecoration(tester, WritingSidebarPage.thesaurus).border!.bottom;
    expect(other.color, Colors.transparent);
    expect(other.width, 2);
  });

  testWidgets("the underline moves with the selection", (tester) async {
    await _mount(tester, page: WritingSidebarPage.document);
    expect(
        _tabDecoration(tester, WritingSidebarPage.document)
            .border!
            .bottom
            .color,
        isNot(Colors.transparent));
    expect(
        _tabDecoration(tester, WritingSidebarPage.mistakes)
            .border!
            .bottom
            .color,
        Colors.transparent);
  });

  group("labels", () {
    testWidgets("a wide panel names every tab", (tester) async {
      await _mount(tester, width: 900);
      for (var page in WritingSidebarPage.values) {
        expect(find.text(page.short), findsOneWidget, reason: page.short);
      }
    });

    // The panel is 260 wide by default, where four names and the switch do
    // not fit. The icons carry it, and the underline still separates this
    // row from the one above.
    testWidgets("the default width falls back to icons", (tester) async {
      await _mount(tester, width: 260);
      expect(find.text(WritingSidebarPage.thesaurus.short), findsNothing);
      for (var page in WritingSidebarPage.values) {
        expect(find.byIcon(page.icon), findsOneWidget, reason: page.title);
      }
      expect(
          _tabDecoration(tester, WritingSidebarPage.mistakes)
              .border!
              .bottom
              .width,
          2,
          reason: "narrow is exactly where the two rows are easiest to "
              "confuse, so the underline has to survive it");
    });
  });

  testWidgets("tapping a tab asks for that page", (tester) async {
    await _mount(tester);
    await tester.tap(find.byIcon(WritingSidebarPage.thesaurus.icon));
    await tester.pumpAndSettle();
    expect(_lastRequested, WritingSidebarPage.thesaurus);
  });

  // The switch stays in the row, so it has to stay working there.
  testWidgets("the on/off switch is in the row and works", (tester) async {
    var prefs = WritingPreferences();
    await _mount(tester, prefs: prefs);
    expect(find.byType(Switch), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(prefs.enabled, isFalse);
  });
}
