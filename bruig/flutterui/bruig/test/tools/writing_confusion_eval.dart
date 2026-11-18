import 'dart:io';

import 'package:bruig/plugin_system/writing_tools/engine/checker.dart';
import 'package:bruig/plugin_system/writing_tools/engine/writing_issue.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/writing_real_data.dart';

// writing_confusion_eval.dart measures the confused-word check both ways at
// once, on sentences the provider's counts were not made from.
//
// For every confusable word in a sentence of edited English there are two
// questions. Left as written, is it marked? It should not be: that is a false
// alarm. Swapped for the word it is confused with, is the swap marked and the
// original offered back? It should be: that is the mistake being caught.
//
//   WRITING_CORPUS=/path/to/held-out-sentences.txt
//   WRITING_SCAN_OUT=/path/to/report.txt
//
//   flutter test test/tools/writing_confusion_eval.dart

final _word = RegExp(r"[A-Za-z][A-Za-z'’]*");

class _Tally {
  int seen = 0, alarms = 0, certainAlarms = 0;
  int swaps = 0, caught = 0, certain = 0;
  final samples = <String>[];
}

void main() {
  test("confusion eval", () {
    var data = realWritingData();
    if (data == null) fail(realWritingDataFailure);
    var rivals = <String, Set<String>>{};
    for (var line in data.grammar!.confusionSets) {
      var set = line.split(" ");
      for (var w in set) {
        (rivals[w] ??= {}).addAll(set.where((x) => x != w));
      }
    }
    var checker = WritingChecker()..updateData(data);
    bool isConfusion(WritingIssue i) =>
        (i.checkId ?? "").startsWith("analysis:confused-word");
    var tallies = <String, _Tally>{};
    var lines = File(Platform.environment["WRITING_CORPUS"]!).readAsLinesSync();
    var limit =
        int.parse(Platform.environment["WRITING_EVAL_LINES"] ?? "20000");
    for (var line in lines.take(limit)) {
      var matches = _word.allMatches(line).toList();
      var hasMember = matches.any((m) => rivals.containsKey(m.group(0)));
      if (!hasMember) continue;
      var clean = checker.issuesAt(line, 0, line.length).where(isConfusion);
      for (var m in matches) {
        var w = m.group(0)!;
        var set = rivals[w];
        if (set == null) continue;
        for (var rival in set) {
          // Filed under the mistake: "rival written where w belongs".
          var t = tallies["$rival for $w"] ??= _Tally();
          t.seen++;
          var swapped = line.replaceRange(m.start, m.end, rival);
          var found = checker
              .issuesAt(swapped, m.start, m.start + rival.length)
              .where(isConfusion)
              .where((i) => i.suggestions.contains(w));
          t.swaps++;
          if (found.isNotEmpty) {
            t.caught++;
            if (found.any((i) => i.kind.isMistake)) t.certain++;
          }
        }
        for (var issue in clean) {
          if (issue.range.start != m.start) continue;
          // An alarm on w proposing some rival: "w for rival" misfired.
          var t = tallies["$w for ${issue.suggestions.first}"] ??= _Tally();
          t.alarms++;
          if (issue.kind.isMistake) t.certainAlarms++;
          if (t.samples.length < 4) {
            var from = (m.start - 35).clamp(0, line.length);
            var to = (m.end + 25).clamp(0, line.length);
            t.samples.add("${line.substring(from, m.start)}[[$w]]"
                "${line.substring(m.end, to)}");
          }
        }
      }
    }
    var out = StringBuffer();
    var alarms = 0, certainAlarms = 0, swaps = 0, caught = 0, certain = 0;
    for (var t in tallies.values) {
      alarms += t.alarms;
      certainAlarms += t.certainAlarms;
      swaps += t.swaps;
      caught += t.caught;
      certain += t.certain;
    }
    out.writeln(
        "alarms $alarms (certain $certainAlarms) on ${lines.take(limit).length} sentences; "
        "caught $caught of $swaps swaps (${(100 * caught / swaps).toStringAsFixed(1)}%), "
        "certain $certain");
    var ordered = tallies.entries.toList()
      ..sort((a, b) => b.value.alarms.compareTo(a.value.alarms));
    for (var e in ordered) {
      var t = e.value;
      if (t.alarms == 0 && t.swaps < 20) continue;
      out.writeln("${e.key.padRight(26)} alarms ${t.alarms}/${t.certainAlarms}"
          "  caught ${t.caught}/${t.swaps} certain ${t.certain}");
      for (var s in t.samples) {
        out.writeln("      $s");
      }
    }
    File(Platform.environment["WRITING_SCAN_OUT"]!)
        .writeAsStringSync(out.toString());
  }, timeout: const Timeout(Duration(minutes: 30)));
}
