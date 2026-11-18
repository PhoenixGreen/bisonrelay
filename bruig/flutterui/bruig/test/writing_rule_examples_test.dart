import 'package:bruig/plugin_system/writing_tools/engine/checker.dart';
import 'package:bruig/plugin_system/writing_tools/engine/language/grammar.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/writing_real_data.dart';

// writing_rule_examples_test.dart runs every shipped rule's own examples
// through the engine that ships.
//
// Each rule in the plugin carries text it must mark and text it must leave
// alone, written beside it by whoever wrote the rule. The plugin's tests run
// those through Go's regular expressions, which is the wrong engine for all
// of them and no engine at all for the rules stated over words. This is the
// right one.

void main() {
  var data = realWritingData();
  var examples = data == null ? null : realRuleExamples();
  var skip = examples == null ? realWritingDataFailure : null;

  test("every rule over words compiles", () {
    expect(LanguageEngine.uncompilable(data!.grammar!), isEmpty,
        reason: "a rule that does not compile is skipped, and a skipped rule "
            "looks exactly like a rule nobody wrote");
  }, skip: skip);

  test("every rule marks its own examples and leaves its counter-examples", () {
    var checker = WritingChecker()..updateData(data!);
    var failures = <String>[];
    var ran = 0;
    for (var example in examples!) {
      bool fires(String text) => checker
          .issuesAt(text, 0, text.length)
          .any((i) => i.checkId == example.rule);
      var name = example.rule.length > 70
          ? "${example.rule.substring(0, 70)}..."
          : example.rule;
      for (var text in example.flags) {
        ran++;
        if (!fires(text)) failures.add("$name\n    does not mark: $text");
      }
      for (var text in example.leaves) {
        ran++;
        if (fires(text)) failures.add("$name\n    should leave: $text");
      }
    }
    expect(ran, greaterThan(500));
    expect(failures, isEmpty, reason: failures.join("\n"));
  }, skip: skip);
}
