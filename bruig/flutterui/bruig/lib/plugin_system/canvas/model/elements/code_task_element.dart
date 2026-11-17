import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_run_element.dart';
import 'package:bruig/plugin_system/canvas/model/pattern_counts.dart';

// code_task_element.dart is a task card beside a Code panel (Ken,
// 2026-11-15: "interactive tasks that tell the user if they passed the test
// and that they are ready to move onto the next lesson"), as a synth's task
// card is beside its rack: what to do, the checks it is marked by -- ticked
// as the code is typed -- and a button that checks it all, builds it too,
// and says whether it passed.

/// CodeCheckKind is what a check looks at.
enum CodeCheckKind {
  /// has: the code says [CodeCheck.text] (a pattern, where it is one).
  has("The code has"),

  /// lacks: the code no longer says it.
  lacks("The code no longer has"),

  /// changes: the code no longer says [CodeCheck.before], and says
  /// [CodeCheck.text] -- "coins++" made "coins += 2" (Ken: easier to set
  /// than a pattern).
  changes("The code changes"),

  /// builds: the project builds and runs without an error: looked at only
  /// when Check is pressed.
  builds("It builds and runs"),

  /// prints: its Run panel's last run printed it.
  prints("Its output has");

  final String label;
  const CodeCheckKind(this.label);
}

/// CodeCheck is one thing the student's code must do.
class CodeCheck {
  final CodeCheckKind kind;

  /// label is what the card says the check is.
  final String label;

  /// file is the file it looks in, by name; empty for every file.
  final String file;

  /// text is what it looks for -- any of its lines, each an answer it
  /// accepts (see [answers]) -- and [pattern] whether it is instead one
  /// regular expression.
  final String text;
  final bool pattern;

  /// before is what a [CodeCheckKind.changes] check must no longer find.
  final String before;

  /// count is how many times, at least, a [CodeCheckKind.has] check must
  /// find it: "three stars" without a pattern.
  final int count;

  const CodeCheck(this.kind, this.label,
      {this.file = "",
      this.text = "",
      this.pattern = false,
      this.before = "",
      this.count = 1});

  CodeCheck copyWith(
          {CodeCheckKind? kind,
          String? label,
          String? file,
          String? text,
          bool? pattern,
          String? before,
          int? count}) =>
      CodeCheck(kind ?? this.kind, label ?? this.label,
          file: file ?? this.file,
          text: text ?? this.text,
          pattern: pattern ?? this.pattern,
          before: before ?? this.before,
          count: (count ?? this.count).clamp(1, 999));

  /// answers are what it accepts: each line of [text], any of which does;
  /// a pattern is one.
  List<String> get answers => pattern
      ? [if (text.isNotEmpty) text]
      : [
          for (var l in text.split("\n"))
            if (l.trim().isNotEmpty) l.trim()
        ];

  /// _loose is [words] as a pattern: spaces anywhere in it, or none, match
  /// any run of spaces in the code or none (so `fontSize:40` and
  /// `fontSize: 40` both count), and it is found only as whole words
  /// (`fontSize: 48` is not in `fontSize: 480`).
  static RegExp _loose(String words) {
    var chars = words.replaceAll(RegExp(r"\s+"), "").split("");
    bool word(String c) => RegExp(r"\w").hasMatch(c);
    var b = StringBuffer();
    if (word(chars.first)) b.write(r"(?<!\w)");
    b.write(chars.map(RegExp.escape).join(r"\s*"));
    if (word(chars.last)) b.write(r"(?!\w)");
    return RegExp(b.toString());
  }

  /// timesIn is how many times [code] says any of [words]' answers: a
  /// pattern as written, or loosely (see [_loose]). Null while a pattern is
  /// being counted: one written with the card is counted off the UI
  /// isolate, as it may never finish (see PatternCounts).
  static int? timesIn(String code, List<String> words, {bool pattern = false}) {
    var n = 0;
    for (var w in words) {
      if (pattern) {
        var k = PatternCounts.count(w, code);
        if (k == null) return null;
        n += k;
        continue;
      }
      try {
        n += _loose(w).allMatches(code).length;
      } catch (_) {}
    }
    return n;
  }

  /// metBy is whether [code]'s files (and its Run panel's last run, [run])
  /// do it; null for one that is only known by checking ([builds]).
  bool? metBy(CodeElement? code, CodeRunElement? run) {
    switch (kind) {
      case CodeCheckKind.builds:
        return null;
      case CodeCheckKind.prints:
        var logs = run?.result?.logs ?? const <CodeLog>[];
        var a = answers;
        if (pattern) {
          var waiting = false;
          for (var l in logs) {
            if (l.kind == CodeLogKind.error) continue;
            var n = timesIn(l.text, a, pattern: true);
            if (n == null) {
              waiting = true;
            } else if (n > 0) {
              return true;
            }
          }
          return waiting ? null : false;
        }
        return logs.any((l) =>
            l.kind != CodeLogKind.error &&
            (a.isEmpty || a.any(l.text.contains)));
      case CodeCheckKind.has || CodeCheckKind.lacks || CodeCheckKind.changes:
        if (code == null) return false;
        var all = [
          for (var f in code.files)
            if (file.isEmpty || f.name == file) f.text
        ].join("\n");
        var a = answers;
        var times = a.isEmpty ? count : timesIn(all, a, pattern: pattern);
        if (times == null) return null;
        if (kind == CodeCheckKind.changes && before.trim().isNotEmpty) {
          var was = timesIn(all, [before.trim()], pattern: pattern);
          if (was == null) return null;
          if (was != 0) return false;
        }
        return switch (kind) {
          CodeCheckKind.has => times >= count,
          CodeCheckKind.lacks => times == 0,
          _ => times > 0,
        };
    }
  }

  Map<String, dynamic> toJson() => {
        "kind": kind.name,
        "label": label,
        if (file.isNotEmpty) "file": file,
        if (text.isNotEmpty) "text": text,
        if (pattern) "pattern": true,
        if (before.isNotEmpty) "before": before,
        if (count != 1) "count": count,
      };

  static CodeCheck? fromJson(Object? j) {
    if (j is! Map) return null;
    var kind = CodeCheckKind.values.asNameMap()[j["kind"]];
    if (kind == null) return null;
    return CodeCheck(kind, jsonString(j["label"], ""),
        file: jsonString(j["file"], ""),
        text: jsonString(j["text"], ""),
        pattern: jsonBool(j["pattern"], false),
        before: jsonString(j["before"], ""),
        count: jsonInt(j["count"], 1).clamp(1, 999));
  }
}

/// CodeTaskElement is the card itself.
class CodeTaskElement extends CanvasElement {
  /// code is the Code panel it marks, by id.
  final String code;
  final String title;
  final String text;
  final List<CodeCheck> checks;

  /// passed is what it says when every check is met; notYet what it says
  /// when they are not (with how many are).
  final String passed;
  final String notYet;

  /// accent is its colour: the title's rule and the button.
  final Color accent;

  /// textSize is its words' size on the page; the rest is sized from it.
  final double textSize;

  const CodeTaskElement(
    super.base, {
    this.code = "",
    this.title = "Your turn",
    this.text = "Change the code, run it, then check your work.",
    this.checks = const [],
    this.passed = "Passed! You're ready for the next lesson.",
    this.notYet = "Not yet: fix the checks without a tick and try again.",
    this.accent = const Color(0xFF2ED6A1),
    this.textSize = 16,
  });

  @override
  ElementKind get kind => ElementKind.codeTask;

  @override
  CanvasElement rebase(ElementBase base) => CodeTaskElement(base,
      code: code,
      title: title,
      text: text,
      checks: checks,
      passed: passed,
      notYet: notYet,
      accent: accent,
      textSize: textSize);

  CodeTaskElement copyWith({
    String? code,
    String? title,
    String? text,
    List<CodeCheck>? checks,
    String? passed,
    String? notYet,
    Color? accent,
    double? textSize,
  }) =>
      CodeTaskElement(base,
          code: code ?? this.code,
          title: title ?? this.title,
          text: text ?? this.text,
          checks: checks ?? this.checks,
          passed: passed ?? this.passed,
          notYet: notYet ?? this.notYet,
          accent: accent ?? this.accent,
          textSize: (textSize ?? this.textSize).clamp(4.0, 1000.0));

  /// codeIn is the Code panel it marks in [doc], and the Run panel that
  /// runs that.
  (CodeElement?, CodeRunElement?) codeIn(CanvasDocument? doc) {
    var c = doc?.elementById(code);
    if (c is! CodeElement) return (null, null);
    var run = doc!.elements
        .whereType<CodeRunElement>()
        .where((r) => r.code == c.id)
        .firstOrNull;
    return (c, run);
  }

  @override
  Map<String, dynamic> props() => {
        "code": code,
        "title": title,
        "text": text,
        if (checks.isNotEmpty) "checks": [for (var c in checks) c.toJson()],
        "passed": passed,
        "notYet": notYet,
        "accent": colorToJson(accent),
        "textSize": textSize,
      };

  factory CodeTaskElement.fromJson(Map<String, dynamic> json, ElementBase b) {
    const plain = CodeTaskElement(ElementBase(id: ""));
    return CodeTaskElement(b,
        code: jsonString(json["code"], ""),
        title: jsonString(json["title"], plain.title),
        text: jsonString(json["text"], plain.text),
        checks: [
          for (var c in (json["checks"] is List ? json["checks"] as List : []))
            if (CodeCheck.fromJson(c) case var check?) check
        ],
        passed: jsonString(json["passed"], plain.passed),
        notYet: jsonString(json["notYet"], plain.notYet),
        accent: colorFromJson(json["accent"], plain.accent),
        textSize: jsonDouble(json["textSize"], 16).clamp(4.0, 1000.0));
  }
}
