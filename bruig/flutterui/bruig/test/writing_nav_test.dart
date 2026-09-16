import 'package:bruig/plugin_system/writing_tools/ui/sidebar/document_page.dart';
import 'package:bruig/plugin_system/writing_tools/ui/sidebar/thesaurus_page.dart';
import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_support.dart';

// writing_nav_test.dart covers how the sidebar's four parts are arranged.
//
// They were four tabs in a row. Reported at the time: that row and the icon
// row above it looked like the same control twice, because both drew the
// selected item as a filled rectangle and neither read as subordinate to the
// other. They are now four panels in a column that opens, shuts, resizes and
// changes places -- the same PanelStack the canvas's design sidebar is -- so
// the question the tab row could not answer is gone with it: two of the four
// are wanted at the same moment, and a tab is a place you have to leave to
// reach another.
//
// What is tested here is the writing tools' own wiring into that column. How
// the column itself behaves -- dragging, tabbing two panels together,
// remembering it all -- is canvas_editor_test's, and is not worth a second
// copy.

Future<void> _mount(
  WidgetTester tester, {
  double width = 900,
  String text = "the paymnt",
  WritingPreferences? prefs,
}) async {
  var settings = prefs ?? WritingPreferences();
  var spellcheck = SpellcheckCapability(
      fetch: (_) async =>
          SpellcheckData(const ["the", "payment"], const [], []),
      prefs: settings);
  await spellcheck.update(FakePlugins({PluginCapability.spellcheckData}));

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
            controller: TextEditingController(text: text),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// _tabDecoration is the box drawn behind one tab.

/// _header finds a panel's heading. The stack sets its headings in capitals.
Finder _header(WritingSidebarPage page) => find.text(page.short.toUpperCase());

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets("all four are headed, in one column", (tester) async {
    await _mount(tester);
    for (var page in WritingSidebarPage.values) {
      expect(_header(page), findsOneWidget, reason: page.short);
    }

    // A column, not a row: each heading is below the one before it. That is
    // the whole difference from the tab row this replaced.
    var tops = [
      for (var page in WritingSidebarPage.values)
        tester.getRect(_header(page)).top,
    ];
    for (var i = 1; i < tops.length; i++) {
      expect(tops[i], greaterThan(tops[i - 1]));
    }
  });

  testWidgets("the two that count say how many on their heading",
      (tester) async {
    // The reason to look at a panel is usually to find out whether there is
    // anything to look at, and a shut panel should say so before it is opened.
    await _mount(tester);
    expect(find.text("1"), findsWidgets,
        reason: "the misspelled word in the fixture is counted on the heading");
  });

  testWidgets("and say nothing rather than nought", (tester) async {
    // A panel headed 0 invites a look at a list with nothing in it.
    await _mount(tester, text: "the payment");
    expect(find.text("0"), findsNothing);
  });

  testWidgets("the thesaurus and the counts start shut", (tester) async {
    // Two holes in a column the issue lists want the room from: the
    // thesaurus has nothing to say until a word is selected, and the counts
    // are read once, at the end.
    await _mount(tester);
    expect(find.byType(ThesaurusPage), findsNothing);
    expect(find.byType(DocumentPage), findsNothing);

    await tester.tap(_header(WritingSidebarPage.thesaurus));
    await tester.pumpAndSettle();
    expect(find.byType(ThesaurusPage), findsOneWidget);
  });

  testWidgets("the on/off switch is above them all, and works", (tester) async {
    // It governs all four, so it is not on any one of them.
    var prefs = WritingPreferences();
    await _mount(tester, prefs: prefs);
    expect(find.byType(Switch), findsOneWidget);
    expect(tester.getRect(find.byType(Switch)).top,
        lessThan(tester.getRect(_header(WritingSidebarPage.mistakes)).top));

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(prefs.enabled, isFalse);
  });

  testWidgets("switched off, the panels say so -- except the counts",
      (tester) async {
    var prefs = WritingPreferences()..enabled = false;
    await _mount(tester, prefs: prefs);
    expect(find.text("Writing tools are off for this session."), findsWidgets);

    // Counting words needs no provider and no rules, so it keeps working.
    await tester.tap(_header(WritingSidebarPage.document));
    await tester.pumpAndSettle();
    expect(find.byType(DocumentPage), findsOneWidget);
  });
}
