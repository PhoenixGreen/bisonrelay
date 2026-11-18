import 'dart:io';

import 'package:bruig/plugin_system/writing_tools/engine/checker.dart';
import 'package:bruig/plugin_system/writing_tools/engine/writing_issue.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/writing_real_data.dart';

// writing_benchmark_test.dart measures the checker on the mistakes people
// make, with the rules the plugin ships, in the engine the app runs.
//
// Every other writing test here asks whether a rule that exists works. This
// one asks the question a writer asks: I made an ordinary mistake -- was it
// marked? The pairs are in the plugin's testdata/basic_errors.tsv, each a
// wrong sentence and its correction, and two numbers come out:
//
//   caught        the wrong sentence was marked at all
//   false alarms  the right sentence was marked as a mistake
//
// The floors below only ever move up. A change that lowers one has made the
// checker worse at something a person does, whatever else it improved.

void main() {
  var data = realWritingData();
  var skip = data == null ? realWritingDataFailure : null;

  test("basic mistakes are caught, and their corrections are left alone", () {
    var checker = WritingChecker()..updateData(data!);
    var pairs = readErrorPairs("basic_errors.tsv");
    expect(pairs.length, greaterThan(300));

    var total = <String, int>{};
    var caught = <String, int>{};
    var missed = <String>[];
    var falseAlarms = <String>[];

    for (var pair in pairs) {
      total[pair.category] = (total[pair.category] ?? 0) + 1;
      // Any mark counts, mistake or question: the writer's eye is drawn to
      // the sentence either way, which is the thing being measured.
      var found = checker.review(pair.wrong).where(_isAboutTheWords).toList();
      if (found.isNotEmpty) {
        caught[pair.category] = (caught[pair.category] ?? 0) + 1;
      } else {
        missed.add("${pair.category}\t${pair.wrong}");
      }
      // A correction is held to the stricter standard. A red underline under
      // right writing is the failure that teaches people to ignore them all.
      var wrongly = checker.review(pair.right).where((i) => i.kind.isMistake);
      for (var issue in wrongly) {
        falseAlarms.add("${pair.right}\t[${issue.text}] ${issue.message}");
      }
    }

    var report = StringBuffer();
    var allCaught = 0;
    for (var category in total.keys.toList()..sort()) {
      var n = caught[category] ?? 0;
      allCaught += n;
      report.writeln("${category.padRight(12)} $n/${total[category]}");
    }
    report.writeln("${"ALL".padRight(12)} $allCaught/${pairs.length}");
    report.writeln("false alarms ${falseAlarms.length}");
    // ignore: avoid_print
    print(report);

    var out = Platform.environment["WRITING_BENCHMARK_OUT"];
    if (out != null && out.isNotEmpty) {
      File(out).writeAsStringSync([
        report.toString(),
        "--- missed",
        ...missed,
        "--- false alarms",
        ...falseAlarms,
      ].join("\n"));
    }

    expect(falseAlarms, isEmpty,
        reason: "a correction must never be marked as a mistake");
    expect(allCaught, greaterThanOrEqualTo(_floor),
        reason: "the checker catches fewer basic mistakes than it did");
  }, skip: skip);
}

/// The fewest of the pairs the checker may catch. Raise it when it rises.
const _floor = 352;

/// A finding that says something about the sentence's words, rather than
/// about its length or rhythm -- a long-sentence note on a wrong sentence has
/// not caught the mistake in it.
bool _isAboutTheWords(WritingIssue issue) => !const {
      "analysis:long-sentence",
      "analysis:repeated-word-in-paragraph",
      "analysis:repeated-sentence-opener",
    }.contains(issue.checkId);
