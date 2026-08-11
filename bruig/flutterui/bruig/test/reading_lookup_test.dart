import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_support.dart';

// reading_lookup_test.dart covers the word lookup on text being read rather
// than written.
//
// A composer reaches it through its EditableTextState, which knows what is
// selected and can replace the word with what the sheet offers. A post has
// neither: the words are somebody else's. What is checked here is that the
// sheet still answers the question, and that nothing in it pretends the
// answer can be applied.

ThesaurusEntry _entry() => ThesaurusEntry("happy", [
      ThesaurusSense("adj", ["glad", "cheerful"], ["unhappy"]),
    ]);

Future<void> _openSheet(WidgetTester tester,
    {required ValueChanged<String>? onReplace}) async {
  var capability = ThesaurusCapability(
      FakePlugins({PluginCapability.thesaurus}),
      fetch: (w) async => _entry());

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showThesaurusSheet(context,
                capability: capability, word: "happy", onReplace: onReplace),
            child: const Text("open"),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text("open"));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group("looking a word up while reading", () {
    // What the reader gets: the meaning and the alternatives, as a list.
    testWidgets("the sheet answers for the word", (tester) async {
      await _openSheet(tester, onReplace: null);
      expect(find.text("glad"), findsOneWidget);
      expect(find.text("unhappy"), findsOneWidget);
    });

    // Nothing to replace, so nothing that looks like it could be pressed.
    // Alternatives dressed as buttons that quietly did nothing would be
    // worse than alternatives dressed as the list they are.
    testWidgets("the alternatives are not offered as actions", (tester) async {
      await _openSheet(tester, onReplace: null);
      expect(find.byType(ActionChip), findsNothing);
      expect(find.byType(Chip), findsWidgets);
    });

    testWidgets("while writing they still are", (tester) async {
      await _openSheet(tester, onReplace: (_) {});
      expect(find.byType(ActionChip), findsWidgets);
    });

    testWidgets("choosing one replaces the word", (tester) async {
      String? chosen;
      await _openSheet(tester, onReplace: (w) => chosen = w);
      await tester.tap(find.text("glad"));
      await tester.pumpAndSettle();
      expect(chosen, "glad");
    });
  });

  // The entry only appears for something a thesaurus can answer for, which
  // is one word. A selection of three is a sentence.
  group("what is worth offering the lookup for", () {
    test("a single word", () {
      expect(ThesaurusCapability.normalizeWord("happy"), "happy");
      expect(ThesaurusCapability.normalizeWord("  Happy.  "), "happy");
    });

    test("not a phrase, and not nothing", () {
      expect(ThesaurusCapability.normalizeWord("happy little"), isNull);
      expect(ThesaurusCapability.normalizeWord(""), isNull);
    });
  });
}
