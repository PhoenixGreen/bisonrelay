import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_support.dart';

// spellcheck_field_test.dart covers the gap Flutter leaves: it runs a spell
// check only when the *text* changes, so a field created with text already
// in it is never checked until someone touches it, and turning checking on
// leaves the text unmarked until the next keystroke.

const _dictionary = ["the", "payment", "cleared"];

Future<(SpellcheckCapability, WritingPreferences)> _capability(
    {bool enabled = true}) async {
  var prefs = WritingPreferences();
  prefs.enabled = enabled;
  var capability = SpellcheckCapability(
      fetch: () async => SpellcheckData(_dictionary, const [], const []),
      prefs: prefs);
  await capability.update(FakePlugins({PluginCapability.spellcheckData}));
  return (capability, prefs);
}

Future<EditableTextState> _pumpField(
  WidgetTester tester,
  SpellcheckCapability capability,
  WritingPreferences prefs,
  TextEditingController controller,
) async {
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<SpellcheckCapability>.value(value: capability),
      ChangeNotifierProvider<WritingPreferences>.value(value: prefs),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SpellcheckedFieldScope(
          child: TextField(
            key: capability.fieldKey,
            controller: controller,
            spellCheckConfiguration: capability.configuration,
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return tester.state<EditableTextState>(find.byType(EditableText));
}

void main() {
  _recoveryTests();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // A draft reopened, or a reply being edited: the text was there before the
  // field was, and Flutter will never check it on its own.
  testWidgets("text a field starts with is checked without typing",
      (tester) async {
    var (capability, prefs) = await _capability();
    var controller = TextEditingController(text: "the paymnt cleared");
    var state = await _pumpField(tester, capability, prefs, controller);

    expect(state.spellCheckResults, isNotNull,
        reason: "the field was never checked at all");
    expect(state.spellCheckResults!.suggestionSpans, hasLength(1));
    var span = state.spellCheckResults!.suggestionSpans.single;
    expect(
        controller.text.substring(span.range.start, span.range.end), "paymnt");
  });

  // Reported: switching checking on left the text unmarked until the next
  // keystroke, which made the switch look like it had not worked.
  testWidgets("switching checking on marks the text at once", (tester) async {
    var (capability, prefs) = await _capability(enabled: false);
    var controller = TextEditingController(text: "the paymnt cleared");
    await _pumpField(tester, capability, prefs, controller);

    prefs.enabled = true;
    await tester.pumpAndSettle();

    var state = tester.state<EditableTextState>(find.byType(EditableText));
    expect(state.spellCheckResults?.suggestionSpans ?? const [], isNotEmpty,
        reason: "nothing was marked until a key was pressed");
  });

  testWidgets("an ignored word loses its mark without typing", (tester) async {
    var (capability, prefs) = await _capability();
    var controller = TextEditingController(text: "the paymnt cleared");
    var state = await _pumpField(tester, capability, prefs, controller);
    expect(state.spellCheckResults!.suggestionSpans, isNotEmpty);

    prefs.ignoreOnce("paymnt");
    await tester.pumpAndSettle();

    state = tester.state<EditableTextState>(find.byType(EditableText));
    expect(state.spellCheckResults!.suggestionSpans, isEmpty);
  });

  testWidgets("a clean field is left alone", (tester) async {
    var (capability, prefs) = await _capability();
    var controller = TextEditingController(text: "the payment cleared");
    var state = await _pumpField(tester, capability, prefs, controller);
    expect(state.spellCheckResults?.suggestionSpans ?? const [], isEmpty);
  });

  // The scope has to be safe to wrap around anything, including a field the
  // checker has nothing to say about.
  testWidgets("no provider means the scope does nothing", (tester) async {
    var prefs = WritingPreferences();
    var capability = SpellcheckCapability(
        fetch: () async => throw "no provider", prefs: prefs);
    await capability.update(FakePlugins({}));

    var controller = TextEditingController(text: "the paymnt cleared");
    var state = await _pumpField(tester, capability, prefs, controller);
    expect(state.spellCheckResults?.suggestionSpans ?? const [], isEmpty);
  });
}

// Reported: clicking a flagged word made its underline vanish. A field can
// lose its results without this scope doing anything -- clicking into one is
// enough for its EditableText to be rebuilt -- and a scope that trusted its
// own memory of the last hand-off concluded there was nothing to do.
void _recoveryTests() {
  testWidgets("results lost by the field are put back", (tester) async {
    var (capability, prefs) = await _capability();
    var controller = TextEditingController(text: "the paymnt cleared");
    var state = await _pumpField(tester, capability, prefs, controller);
    expect(state.spellCheckResults!.suggestionSpans, isNotEmpty);

    // What a rebuilt EditableText looks like from outside, followed by the
    // kind of interaction that caused it -- a click, which moves the caret.
    state.spellCheckResults = null;
    controller.selection = const TextSelection.collapsed(offset: 5);
    await tester.pumpAndSettle();

    expect(state.spellCheckResults?.suggestionSpans ?? const [], isNotEmpty,
        reason: "the underline did not come back");
  });

  testWidgets("results for stale text are replaced", (tester) async {
    var (capability, prefs) = await _capability();
    var controller = TextEditingController(text: "the paymnt cleared");
    var state = await _pumpField(tester, capability, prefs, controller);

    // Results describing text the field no longer holds address the wrong
    // offsets, so they must not be left in place.
    state.spellCheckResults = const SpellCheckResults("something else", []);
    controller.selection = const TextSelection.collapsed(offset: 5);
    await tester.pumpAndSettle();

    expect(state.spellCheckResults!.spellCheckedText, controller.text);
    expect(state.spellCheckResults!.suggestionSpans, isNotEmpty);
  });
}
