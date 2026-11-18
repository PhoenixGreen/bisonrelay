import 'dart:io';

import 'package:bruig/plugin_system/writing_tools/engine/checker.dart';
import 'package:bruig/plugin_system/writing_tools/engine/language/grammar.dart';
import 'package:bruig/plugin_system/writing_tools/engine/language/usage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/writing_real_data.dart';

// writing_debug.dart shows what the checker makes of some text: each
// sentence's words and what they were taken to be, and everything found.
//
//   WRITING_DEBUG="He go to school." flutter test test/tools/writing_debug.dart
//
// WRITING_DEBUG_COUNTS="M|wants|reconsider|to" also prints one stored count.

void main() {
  test("debug", () {
    var data = realWritingData();
    if (data == null) fail(realWritingDataFailure);
    var engine = LanguageEngine.from(data)!;
    var checker = WritingChecker()..updateData(data);
    var out = StringBuffer();
    for (var text in (Platform.environment["WRITING_DEBUG"] ?? "").split("|")) {
      if (text.isEmpty) continue;
      out.writeln("> $text");
      for (var s in engine.tokenizer.sentences(text)) {
        out.writeln("  ${s.tokens.join(" ")}");
        out.writeln("  units: ${unitsOf(s).map((u) => u.text).join(" ")}");
      }
      for (var i in checker.issuesAt(text, 0, text.length)) {
        out.writeln("  ${i.kind.name} [${i.text}] ${i.message} "
            "-> ${i.suggestions.take(3).join(" | ")}  (${i.checkId})");
      }
    }
    for (var spec
        in (Platform.environment["WRITING_DEBUG_COUNTS"] ?? "").split(";")) {
      var p = spec.split("|");
      if (p.length < 2) continue;
      out.writeln("count $spec = "
          "${engine.usage.count(p[0], p.sublist(1, p.length - 1), p.last)}");
    }
    // ignore: avoid_print
    print(out);
  });
}
