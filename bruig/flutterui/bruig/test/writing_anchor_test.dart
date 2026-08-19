import 'package:bruig/plugin_system/writing_tools/engine/checker.dart';
import 'package:flutter_test/flutter_test.dart';

// writing_anchor_test.dart guards the prefilter that decides which rules run.
//
// requiredLiteral exists to make the checker cheap: nearly every rule is about
// one word, and text without that word cannot match it. The saving is real --
// it is most of the cost of a keystroke in a long post -- and so is the
// failure mode. An anchor the pattern does not actually require makes the
// rule silently stop firing, which looks exactly like a rule nobody wrote.
//
// So the property under test is one-directional and always the same: whatever
// this returns must appear in every string the pattern matches.

/// _mustHold checks the contract on one pattern against text it matches.
void _mustHold(String pattern, List<String> matching) {
  var anchor = requiredLiteral(pattern);
  if (anchor == null) return; // Always running a rule is never wrong.
  for (var text in matching) {
    expect(RegExp(pattern).hasMatch(text), isTrue,
        reason: "the test's own example does not match $pattern");
    expect(text.toLowerCase().contains(anchor), isTrue,
        reason: "$pattern anchored on \"$anchor\", which is not in \"$text\" "
            "-- the rule would never fire on it");
  }
}

void main() {
  test("an anchor is in everything its pattern matches", () {
    // The shapes the plugin's own rules are written in.
    _mustHold(r"\butilise\b", ["please utilise it"]);
    _mustHold(r"\b([wW]ould|[cC]ould|[tT]o)\s+brake\b",
        ["it would brake the system", "To brake now", "could brake it"]);
    _mustHold(r"\b([tT]he|[aA])\s+tail\s+of\b", ["the tail of two cities"]);
    _mustHold(r"\b[wW]ere\s+(am|is)\s+(I|you)\b", ["Were am I going"]);
    // Optional characters cannot be anchored on.
    _mustHold(r"\bcolou?r\b", ["the colour", "the color"]);
    _mustHold(r"\breforms?\b", ["reform now", "the reforms"]);
    // Groups, classes and escapes are not literals.
    _mustHold(r"\b(\w+)([ \t]+)\1\b", ["the the"]);
    _mustHold(r"[ \t]+([,.!?;:])", ["hello ,"]);
    _mustHold(r"(?:in|on)\s+principal\b", ["in principal"]);
    // A class inside an alternation is as optional as the branch holding it.
    _mustHold(r"\b(a|[tT]he)\s+cat\b", ["a cat", "the cat"]);
    _mustHold(r"(?<=^|[.!?]\s|\n)(Yes|No)\s+([Ii]|[Ww]e|[Tt]hey)\b",
        ["No i do not", "Yes we can"]);
    _mustHold(r"(?<=\w\w)([.!?])(?!com)", ["end."]);
    _mustHold(r"\ba\s+(hour|honest)\b", ["a hour"]);
    _mustHold(r"\bi\.e\.\s", ["i.e. this"]);
  });

  test("nothing mandatory means no anchor", () {
    expect(requiredLiteral(r"\b(\w+)\s+\1\b"), isNull);
    expect(requiredLiteral(r"[ ]{2,}"), isNull);
    expect(requiredLiteral(r"\s+\)"), isNull);
    // A top-level alternation: neither branch is required, so neither can be
    // an anchor. The one shape that would otherwise pass a wrong answer.
    expect(requiredLiteral(r"\bcolour\b|\bflavour\b"), isNull);
  });

  test("an anchor is worth having", () {
    // Not merely correct: the point is that it is usually found, since a
    // filter that never fires costs a scan and saves nothing.
    expect(requiredLiteral(r"\b([wW]ould|[cC]ould)\s+brake\b"), "brake");
    expect(requiredLiteral(r"\butilise\b"), "utilise");
    expect(requiredLiteral(r"\b[wW]ere\s+(am|is)\s+(I|you)\b"), "were");
  });
}
