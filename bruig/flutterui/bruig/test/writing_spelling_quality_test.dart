import 'dart:io';

import 'package:bruig/plugin_system/writing_tools/engine/checker.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/writing_real_data.dart';

// writing_spelling_quality_test.dart measures the corrections offered for a
// misspelled word, with the dictionary the plugin ships.
//
// Marking a misspelling is the easy half: the word is not in the list. The
// half a writer feels is whether the word they meant is the one on offer --
// first, so that one click fixes it, or at least in sight. The pairs are in
// the plugin's testdata/misspellings.tsv.
//
// The floors only move up.

void main() {
  var data = realWritingData();
  var skip = data == null ? realWritingDataFailure : null;

  test("the intended word is offered for a common misspelling", () {
    var checker = WritingChecker()..updateData(data!);
    var file = File("${writingToolsPlugin.path}/testdata/misspellings.tsv");
    var first = 0, three = 0, total = 0;
    var missed = <String>[];
    for (var line in file.readAsLinesSync()) {
      if (line.isEmpty || line.startsWith("#")) continue;
      var parts = line.split("\t");
      var wrong = parts[0], right = parts[1];
      total++;
      // In a sentence, so the rules that know a particular misspelling get
      // their say as well as the dictionary: what is measured is what the
      // writer is offered, wherever it came from.
      var text = "I think $wrong is the word.";
      var offered = <String>[
        for (var issue in checker.issuesAt(text, 8, 8 + wrong.length))
          if (issue.kind.isMistake) ...issue.suggestions,
      ];
      // A word already correct -- there is one in the list on purpose --
      // passes by not being marked at all.
      if (offered.isEmpty && wrong == right) {
        first++;
        three++;
        continue;
      }
      var at = offered.indexOf(right);
      if (at == 0) first++;
      if (at >= 0 && at < 3) three++;
      if (at != 0) {
        missed.add("$wrong -> $right: ${offered.take(4).join(", ")}");
      }
    }
    // ignore: avoid_print
    print("first $first/$total, in three $three/$total");
    var out = Platform.environment["WRITING_BENCHMARK_OUT"];
    if (out != null && out.isNotEmpty) {
      File(out).writeAsStringSync(missed.join("\n"));
    }
    expect(first, greaterThanOrEqualTo(_firstFloor));
    expect(three, greaterThanOrEqualTo(_threeFloor));
  }, skip: skip);
}

const _firstFloor = 144;
const _threeFloor = 150;
