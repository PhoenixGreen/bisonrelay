import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// kept_lists.dart is how the panel tests keep what a panel shows and compare
// it with what was kept, line for line: the words' form of kept_pictures.dart.
// The environment variable a test names points at a folder: a list with
// nothing kept there yet is written (as <state>.<what>.txt); a list already
// kept is compared, and a difference fails showing the lines kept and the
// lines seen where the two part. With the variable unset nothing is kept, so
// a test that keeps lists is harmless in the whole suite.

/// keyText is [key] as a string that is the same from run to run: a key made
/// fresh each time (a GlobalKey, a UniqueKey) has a number of its own, which
/// is left out.
String keyText(Key key) =>
    key.toString().replaceAll(RegExp(r"#[0-9a-f]{5}"), "#");

/// shownUnder is every key under what [root] finds, in order, and every piece
/// of text shown there, in order (an icon is a glyph of text too).
(List<String> keys, List<String> words) shownUnder(
    WidgetTester tester, Finder root) {
  var keys = <String>[], words = <String>[];
  void visit(Element el) {
    var w = el.widget;
    if (w.key case var k?) keys.add(keyText(k));
    if (w is RichText) words.add(w.text.toPlainText());
    if (w is EditableText) words.add(w.controller.text);
    el.visitChildren(visit);
  }

  tester.element(root).visitChildren(visit);
  return (keys, words);
}

/// keepOrCompareLines keeps [lines] as [name]'s [what] in the folder
/// [variable] names, or compares them with what is kept there.
void keepOrCompareLines(
    String variable, String name, String what, List<String> lines) {
  var dir = Platform.environment[variable];
  if (dir == null || dir.isEmpty) return;
  Directory(dir).createSync(recursive: true);
  var file = File("$dir/${keptName(name)}.$what.txt");
  // As one text, since a piece of text shown may run over several lines.
  var now = lines.join("\n");
  if (!file.existsSync()) {
    file.writeAsStringSync(now);
    return;
  }
  var was = file.readAsStringSync();
  if (was == now) return;
  fail("$name: $what differ\n"
      "${linesDiffer(was.split("\n"), now.split("\n"))}");
}

/// keptName is [name] as a file name: a space as an underscore, and anything
/// a file name should not carry as one too.
String keptName(String name) =>
    name.replaceAll(RegExp(r"[^A-Za-z0-9._\-]"), "_");

/// linesDiffer is null where [was] and [now] are the same lines, or else the
/// part of each between what they start and end with in common, numbered by
/// line, at most [most] lines of each.
String? linesDiffer(List<String> was, List<String> now, {int most = 80}) {
  var head = 0;
  while (head < was.length && head < now.length && was[head] == now[head]) {
    head++;
  }
  if (head == was.length && head == now.length) return null;
  var tail = 0;
  while (tail < was.length - head &&
      tail < now.length - head &&
      was[was.length - 1 - tail] == now[now.length - 1 - tail]) {
    tail++;
  }
  String part(String said, List<String> lines) {
    var from = head, to = lines.length - tail;
    var out = StringBuffer("$said, lines ${from + 1} to $to of "
        "${lines.length}:\n");
    for (var i = from; i < to && i < from + most; i++) {
      out.writeln("  ${i + 1}: ${lines[i]}");
    }
    if (to - from > most) out.writeln("  ... and ${to - from - most} more");
    return out.toString();
  }

  return "${part("kept", was)}${part("seen", now)}";
}
