import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_support.dart';

// writing_field_test.dart covers the marks on the text: that they are there,
// that they are the right colour, and that they change the moment anything
// that could change them does.
//
// The last of those is the reason this path exists at all. Flutter's own
// spell check re-runs only when the *text* changes, so a word added to the
// dictionary kept its underline until the next keystroke, and switching
// checking off did nothing to a field that was already built. Working around
// that took a scope widget reaching into the element tree and a key forcing
// the field to be rebuilt. A controller that paints from the capability at
// build time has nothing to keep in sync.

const _dictionary = ["the", "payment", "cleared", "utilise", "colour", "color"];

Future<(SpellcheckCapability, WritingPreferences)> _capability({
  bool enabled = true,
  List<GrammarRule> rules = const [],
  List<AnalysisCheck> checks = const [],
}) async {
  var prefs = WritingPreferences();
  prefs.enabled = enabled;
  var capability = SpellcheckCapability(
      fetch: (_) async => SpellcheckData(_dictionary, const [], rules, checks),
      prefs: prefs);
  await capability.update(FakePlugins({PluginCapability.spellcheckData}));
  return (capability, prefs);
}

/// _spans renders the field and returns the styled runs the controller built.
Future<List<InlineSpan>> _spans(
  WidgetTester tester,
  SpellcheckCapability? capability,
  WritingPreferences prefs,
  TextEditingController controller,
) async {
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<WritingPreferences>.value(value: prefs),
      if (capability != null)
        ChangeNotifierProvider<SpellcheckCapability>.value(value: capability),
    ],
    child: MaterialApp(
      home: Scaffold(body: TextField(controller: controller)),
    ),
  ));
  await tester.pumpAndSettle();
  return _rendered(tester);
}

/// _rendered reads the styled text off the render object, which is what is
/// actually on screen.
///
/// Not by calling buildTextSpan directly: it reads the capability with
/// `watch`, which is only legal during a build, and calling it from a test
/// body throws. Going through the render object also means these tests cannot
/// pass while the real field shows something else.
List<InlineSpan> _rendered(WidgetTester tester) {
  var span = tester.allRenderObjects.whereType<RenderEditable>().first.text
      as TextSpan;
  return span.children ?? [span];
}

/// _marked is the text of every run that carries an underline, with the
/// colour it was underlined in.
List<(String, Color?)> _marked(List<InlineSpan> spans) => [
      for (var span in spans.whereType<TextSpan>())
        if (span.style?.decoration == TextDecoration.underline)
          (span.text ?? "", span.style?.decorationColor),
    ];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // A draft reopened, or a reply being edited: the text was there before the
  // field was. Flutter's own path never checked it until someone typed.
  testWidgets("text a field starts with is marked without typing",
      (tester) async {
    var (capability, prefs) = await _capability();
    var controller = WritingTextEditingController(text: "the paymnt cleared");
    var spans = await _spans(tester, capability, prefs, controller);

    expect(_marked(spans), [("paymnt", Colors.red)]);
  });

  // Reported before this path existed: switching checking on left the text
  // unmarked until the next keystroke, which made the switch look broken.
  testWidgets("switching checking on marks the text at once", (tester) async {
    var (capability, prefs) = await _capability(enabled: false);
    var controller = WritingTextEditingController(text: "the paymnt cleared");
    await _spans(tester, capability, prefs, controller);
    expect(_marked(_rendered(tester)), isEmpty);

    prefs.enabled = true;
    await tester.pumpAndSettle();

    expect(_marked(_rendered(tester)), isNotEmpty,
        reason: "nothing was marked until a key was pressed");
  });

  // Reported: choosing Ignore or Add to dictionary left the mark where it
  // was.
  testWidgets("an ignored word loses its mark without typing", (tester) async {
    var (capability, prefs) = await _capability();
    var controller = WritingTextEditingController(text: "the paymnt cleared");
    await _spans(tester, capability, prefs, controller);
    expect(_marked(_rendered(tester)), isNotEmpty);

    prefs.ignoreOnce("paymnt");
    await tester.pumpAndSettle();

    expect(_marked(_rendered(tester)), isEmpty);
  });

  testWidgets("a clean field is left alone", (tester) async {
    var (capability, prefs) = await _capability();
    var controller = WritingTextEditingController(text: "the payment cleared");
    var spans = await _spans(tester, capability, prefs, controller);
    expect(_marked(spans), isEmpty);
  });

  // The controller has to be safe in a field nothing provides for, because a
  // composer uses it whether or not a plugin is enabled.
  testWidgets("no capability means a plain field", (tester) async {
    var controller = WritingTextEditingController(text: "the paymnt cleared");
    var spans = await _spans(tester, null, WritingPreferences(), controller);
    expect(_marked(spans), isEmpty);
    expect(spans.whereType<TextSpan>().map((s) => s.text).join(),
        "the paymnt cleared");
  });

  // The reason for taking the painting over at all: one style cannot say both
  // "this is wrong" and "you might reconsider this".
  group("severity decides the colour", () {
    testWidgets("a suggestion is marked differently to a mistake",
        (tester) async {
      var (capability, prefs) = await _capability(rules: [
        GrammarRule(r"\butilise\b", "Wordy", "use", "Style", "", "suggestion"),
      ]);
      var controller = WritingTextEditingController(text: "the paymnt utilise");
      var spans = await _spans(tester, capability, prefs, controller);

      var marks = _marked(spans);
      expect(marks, hasLength(2));
      var mistake = marks.firstWhere((m) => m.$1 == "paymnt");
      var suggestion = marks.firstWhere((m) => m.$1 == "utilise");
      expect(mistake.$2, Colors.red);
      expect(suggestion.$2, isNot(Colors.red),
          reason: "a suggestion marked like a misspelling teaches people to "
              "ignore both");
    });

    // A rule that says nothing about severity is an error, so a provider
    // written before severity existed keeps the behaviour it had.
    testWidgets("a rule with no severity is a mistake", (tester) async {
      var (capability, prefs) = await _capability(rules: [
        GrammarRule(r"\butilise\b", "Wordy", "use"),
      ]);
      var controller = WritingTextEditingController(text: "the utilise");
      var spans = await _spans(tester, capability, prefs, controller);
      expect(_marked(spans), [("utilise", Colors.red)]);
    });

    // A long-sentence suggestion covers a whole sentence, misspellings and
    // all. Letting it win would repaint every mistake inside it as advice.
    testWidgets("a mistake keeps its colour inside a suggestion",
        (tester) async {
      var (capability, prefs) = await _capability(rules: [
        GrammarRule(
            r"the paymnt cleared", "Wordy", "", "Style", "", "suggestion"),
      ]);
      var controller = WritingTextEditingController(text: "the paymnt cleared");
      var spans = await _spans(tester, capability, prefs, controller);

      var marks = _marked(spans);
      expect(marks.firstWhere((m) => m.$1 == "paymnt").$2, Colors.red,
          reason: "the misspelling was repainted as a suggestion");
      expect(marks.any((m) => m.$2 != Colors.red), isTrue,
          reason: "the rest of the sentence should still carry the "
              "suggestion's mark");
    });
  });

  // The text has to survive being cut into runs exactly as it was.
  testWidgets("the text is unchanged by being marked", (tester) async {
    var (capability, prefs) = await _capability();
    const text = "the paymnt cleared, and the othr paymnt did not.";
    var controller = WritingTextEditingController(text: text);
    var spans = await _spans(tester, capability, prefs, controller);
    expect(spans.whereType<TextSpan>().map((s) => s.text).join(), text);
  });
}
