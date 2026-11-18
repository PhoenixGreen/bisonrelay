import 'dart:io';

import 'package:bruig/plugin_system/writing_tools/engine/analysis.dart';
import 'package:bruig/plugin_system/writing_tools/engine/checker.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/writing_real_data.dart';

// writing_timing.dart times the checker with the shipped data: taking the
// data in, the first look at a document, and a keystroke in one.
//
//   WRITING_CORPUS=/path/to/sentences.txt flutter test test/tools/writing_timing.dart

void main() {
  test("timing", () {
    var data = realWritingData();
    if (data == null) fail(realWritingDataFailure);
    var lines = File(Platform.environment["WRITING_CORPUS"]!).readAsLinesSync();
    // A post of forty paragraphs, five sentences each.
    var paragraphs = [
      for (var p = 0; p < 40; p++) lines.skip(p * 5).take(5).join(" "),
    ];
    var document = paragraphs.join("\n\n");

    var watch = Stopwatch()..start();
    var checker = WritingChecker()..updateData(data);
    var load = watch.elapsedMilliseconds;

    watch.reset();
    var found = checker.review(document).length;
    var first = watch.elapsedMicroseconds;

    // Typing: one character more at the end of the last paragraph, each a
    // text the checker has not seen.
    var typed = " and then we";
    watch.reset();
    for (var i = 1; i <= typed.length; i++) {
      checker.review(document + typed.substring(0, i));
    }
    var perKey = watch.elapsedMicroseconds / typed.length;

    watch.reset();
    for (var i = 0; i < 10; i++) {
      runAnalysisChecks("$document $i", data.analysisChecks,
          isIgnoredCheck: (_) => false);
    }
    var counting = watch.elapsedMicroseconds / 10;
    for (var check in data.analysisChecks) {
      watch.reset();
      for (var i = 0; i < 10; i++) {
        runAnalysisChecks("$document $i", [check],
            isIgnoredCheck: (_) => false);
      }
      // ignore: avoid_print
      print("  ${check.id}: "
          "${(watch.elapsedMicroseconds / 10000).toStringAsFixed(2)}ms");
    }
    // ignore: avoid_print
    print("counting checks ${(counting / 1000).toStringAsFixed(2)}ms");

    // ignore: avoid_print
    print("load ${load}ms; first review of ${document.length} chars "
        "${(first / 1000).toStringAsFixed(1)}ms ($found findings); "
        "a keystroke ${(perKey / 1000).toStringAsFixed(2)}ms");
  });
}
