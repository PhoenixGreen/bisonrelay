import 'dart:io';

import 'package:bruig/plugin_system/writing_tools/engine/checker.dart';
import 'package:bruig/plugin_system/writing_tools/engine/writing_issue.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/writing_real_data.dart';

// writing_corpus_scan.dart runs the shipped rules over a large body of
// edited English and reports what fired.
//
// Not part of the suite -- it is named so `flutter test` does not pick it up
// and needs a corpus that is not in the repository. It is the tool behind the
// standard an error rule is held to: text that has been through an editor is
// overwhelmingly correct, so a rule that marks it often is marking correct
// writing. Run it after adding rules, and read the top of the report.
//
//   WRITING_CORPUS=/path/to/sentences.txt  one sentence per line
//   WRITING_SCAN_OUT=/path/to/report.txt
//   WRITING_SCAN_KINDS=grammar,check       which kinds to count (default all
//                                          but spelling)
//
//   flutter test test/tools/writing_corpus_scan.dart

void main() {
  test("scan a corpus", () {
    var data = realWritingData();
    if (data == null) fail(realWritingDataFailure);
    var corpus = Platform.environment["WRITING_CORPUS"];
    if (corpus == null) fail("set WRITING_CORPUS");
    var kinds =
        (Platform.environment["WRITING_SCAN_KINDS"] ?? "grammar,phrasing,check")
            .split(",")
            .toSet();

    var checker = WritingChecker()..updateData(data);
    var hits = <String, int>{};
    var samples = <String, List<String>>{};
    var spelling = <String, int>{};
    var lines = File(corpus).readAsLinesSync();
    var watch = Stopwatch()..start();
    for (var line in lines) {
      for (var issue in checker.issuesAt(line, 0, line.length)) {
        if (issue.kind == WritingIssueKind.spelling) {
          spelling[issue.text] = (spelling[issue.text] ?? 0) + 1;
          continue;
        }
        if (!kinds.contains(issue.kind.name)) continue;
        var key = "${issue.kind.name}\t${issue.ruleMessage}\t"
            "${issue.checkId ?? ""}";
        hits[key] = (hits[key] ?? 0) + 1;
        var list = samples[key] ??= [];
        if (list.length <
            int.parse(Platform.environment["WRITING_SCAN_SAMPLES"] ?? "6")) {
          var from = (issue.range.start - 40).clamp(0, line.length);
          var to = (issue.range.end + 30).clamp(0, line.length);
          list.add("${line.substring(from, issue.range.start)}"
              "[[${issue.text}]]${line.substring(issue.range.end, to)}"
              "  -> ${issue.suggestions.take(2).join(" | ")}");
        }
      }
    }
    watch.stop();

    var out = StringBuffer();
    out.writeln("${lines.length} sentences in ${watch.elapsedMilliseconds}ms");
    var byKind = <String, int>{};
    for (var e in hits.entries) {
      var kind = e.key.split("\t").first;
      byKind[kind] = (byKind[kind] ?? 0) + e.value;
    }
    out.writeln("totals: $byKind");
    var ordered = hits.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (var e in ordered) {
      out.writeln("${e.value}\t${e.key}");
      for (var s in samples[e.key]!) {
        out.writeln("\t\t$s");
      }
    }
    out.writeln("=== spelling (top 400)");
    var words = spelling.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (var e in words.take(400)) {
      out.writeln("${e.value}\t${e.key}");
    }
    var path = Platform.environment["WRITING_SCAN_OUT"];
    if (path != null) {
      File(path).writeAsStringSync(out.toString());
    } else {
      // ignore: avoid_print
      print(out);
    }
  }, timeout: const Timeout(Duration(minutes: 30)));
}
