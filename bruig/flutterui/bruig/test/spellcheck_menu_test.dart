import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';

import 'plugin_test_support.dart';

// spellcheck_menu_test.dart covers what a right-click on a flagged word
// actually offers. The gap it was written for: the composer showed the wavy
// underline but no corrections, because Flutter only surfaces those through
// a toolbar builder that was never set -- so the underline pointed at a
// problem the menu could not fix.

const _dictionary = ["the", "three", "there", "they", "payment", "happy"];

/// _menuFor builds a composer wired the way the real ones are, puts the
/// caret inside [word], and returns the labels its context menu offers.
Future<List<String>> _menuFor(
  WidgetTester tester,
  String text,
  int caretOffset, {
  bool thesaurus = false,
}) async {
  var capability = SpellcheckCapability(
      fetch: () async => SpellcheckData(_dictionary, const [], const []));
  await capability.update(FakePlugins({PluginCapability.spellcheckData}));

  var labels = <String>[];
  var controller = TextEditingController(text: text);
  var focusNode = FocusNode();

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<SpellcheckCapability>.value(value: capability),
      Provider<ThesaurusCapability?>.value(
        value: thesaurus
            ? ThesaurusCapability(
                FakePlugins({PluginCapability.thesaurus}),
                fetch: (w) async => ThesaurusEntry(w, [
                  ThesaurusSense("adj", ["glad"], [])
                ]),
              )
            : null,
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: TextField(
          controller: controller,
          focusNode: focusNode,
          spellCheckConfiguration: capability.configuration,
          contextMenuBuilder: (context, editableTextState) {
            labels = [
              ...spellingContextMenuItems(context, editableTextState),
              ...thesaurusContextMenuItems(context, editableTextState),
            ].map((item) => item.label ?? "<${item.type.name}>").toList();
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  ));

  focusNode.requestFocus();
  await tester.pump();

  // Drive the spell check the way the framework does, then place the caret
  // and open the menu.
  var state = tester.state<EditableTextState>(find.byType(EditableText));
  var spans = await capability.configuration!.spellCheckService!
      .fetchSpellCheckSuggestions(const Locale("en", "US"), text);
  state.spellCheckResults = SpellCheckResults(text, spans ?? []);
  controller.selection = TextSelection.collapsed(offset: caretOffset);
  await tester.pump();

  state.showToolbar();
  await tester.pump();
  return labels;
}

void main() {
  // The regression. "thh" is flagged, and the corrections the service
  // already computed for the underline must reach the menu.
  testWidgets("a misspelled word offers its corrections", (tester) async {
    var labels = await _menuFor(tester, "thh", 1);
    expect(labels, isNotEmpty,
        reason: "the menu offered nothing for a flagged word");
    expect(labels, contains("the"));
    expect(labels.length, lessThanOrEqualTo(maxCorrections),
        reason: "the menu should not list every near miss");
  });

  testWidgets("corrections come first", (tester) async {
    var labels = await _menuFor(tester, "thh", 1, thesaurus: true);
    expect(labels.first, isNot("Synonyms"),
        reason: "corrections are why the menu was opened on a flagged word");
  });

  // The second half of the reported problem: asking a thesaurus about a
  // misspelling can only ever return nothing, so it must not be offered.
  testWidgets("a misspelled word is not offered synonyms", (tester) async {
    var labels = await _menuFor(tester, "thh", 1, thesaurus: true);
    expect(labels, isNot(contains("Synonyms")));
  });

  testWidgets("a correctly spelled word offers no corrections", (tester) async {
    var labels = await _menuFor(tester, "payment", 3);
    expect(labels.where((l) => _dictionary.contains(l)), isEmpty,
        reason: "a word that is spelled fine has nothing to correct");
  });
}
