import 'package:bruig/plugin_system/writing_tools/engine/checks/brackets.dart';
import 'package:bruig/plugin_system/writing_tools/engine/checks/consistency.dart';
import 'package:bruig/plugin_system/writing_tools/engine/checks/dates.dart';
import 'package:bruig/plugin_system/writing_tools/engine/checks/readability.dart';
import 'package:bruig/plugin_system/writing_tools/engine/checks/repetition.dart';
import 'package:bruig/plugin_system/writing_tools/engine/text_segments.dart';
import 'package:bruig/plugin_system/writing_tools/engine/writing_issue.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';

// analysis.dart runs the checks a regular expression cannot express, because
// they have to count.
//
// "This word appears four times in this paragraph" is not a property of any
// stretch of text on its own -- it is a property of the paragraph around it,
// and a pattern has no way to look there. The same goes for a sentence's
// length, a run of sentences opening the same way, and two spellings of one
// word being mixed.
//
// A provider does not supply the logic for these, because there is no pattern
// to supply. It names one of the checks implemented under checks/ and gives
// the threshold, the wording and the explanation; the mechanics live here, as
// they already do for the regex engine and the edit-distance ranking a
// provider also relies on without owning.
//
// A check id nothing here implements is ignored rather than reported, so a
// provider can ship a check ahead of the app that runs it.
//
// To add a check: write the routine in the checks/ file its family belongs to
// (or a new one), name it in that file's map, and spread the map into
// [_runners] below. Nothing else in the app changes, and a provider that
// never declares the id never pays for it.

/// AnalysisRunner is one counting check: it reads [context]'s text and
/// reports what it finds back into the same context.
typedef AnalysisRunner = void Function(
    AnalysisContext context, AnalysisCheck check);

/// _runners maps a declared check id to the routine that runs it.
///
/// Composed from the checks/ files rather than written out here, so a family
/// of related checks is added, read and reviewed in one place instead of
/// being split between its implementation and a central switch that has to be
/// kept in step with it.
final Map<String, AnalysisRunner> _runners = {
  ...repetitionChecks,
  ...readabilityChecks,
  ...consistencyChecks,
  ...bracketChecks,
  ...dateChecks,
};

/// analysisCheckId is how one of these is identified when the user turns it
/// off. It has to be distinguishable from a grammar rule's pattern, which is
/// what that same preference set otherwise holds.
String analysisCheckId(AnalysisCheck check) => "analysis:${check.id}";

/// runAnalysisChecks applies every check [checks] names that this app knows
/// how to run, over the whole of [text].
List<WritingIssue> runAnalysisChecks(
  String text,
  List<AnalysisCheck> checks, {
  required bool Function(String) isIgnoredCheck,
  DateTime? now,
}) {
  if (text.trim().isEmpty) return const [];
  var context = AnalysisContext(text, now ?? DateTime.now());
  for (var check in checks) {
    if (isIgnoredCheck(analysisCheckId(check))) continue;
    // A check this app does not implement. Deliberately silent: it is how a
    // provider ships a check before the app that runs it.
    _runners[check.id]?.call(context, check);
  }
  return context.issues;
}

/// AnalysisContext is the text under review, the segmentations of it, and
/// somewhere to put what is found.
///
/// The segmentations are computed on first use and kept, which is the reason
/// this exists as an object rather than as a bag of arguments. Several checks
/// want the sentences and several want the paragraphs; passed the bare text
/// they each split it again, so a message was walked once per check instead of
/// once per shape -- on every keystroke.
class AnalysisContext {
  /// text is the message exactly as the writer has it. Every offset reported
  /// is an offset into this, so a correction can be spliced straight back.
  final String text;

  /// now is injected rather than read, so the date checks can be tested
  /// against a fixed calendar.
  final DateTime now;

  final List<WritingIssue> issues = [];

  AnalysisContext(this.text, this.now);

  List<TextSegment>? _paragraphs;
  List<TextSegment> get paragraphs =>
      _paragraphs ??= splitKeepingOffsets(text, paragraphBreak);

  List<TextSegment>? _sentences;
  List<TextSegment> get sentences =>
      _sentences ??= splitKeepingOffsets(text, sentenceEnd);

  /// report records one finding, expanding [check]'s message and explanation.
  ///
  /// `$1` is what the check is about -- the repeated word, the spelling that
  /// clashes -- and `$2` is whatever second thing the check counts or names: a
  /// number for the counting checks, the other spelling for the variant one.
  /// Both are passed as strings so one substitution serves all of them.
  void report(
    AnalysisCheck check,
    int start,
    int end, {
    String subject = "",
    String detail = "",
    List<String> suggestions = const [],
  }) {
    String expand(String s) =>
        s.replaceAll(r"$1", subject).replaceAll(r"$2", detail);
    issues.add(WritingIssue(
      range: TextRange(start: start, end: end),
      text: text.substring(start, end),
      message: expand(check.message),
      suggestions: suggestions,
      kind: WritingIssueKind.fromSeverity(check.severity),
      checkId: analysisCheckId(check),
      category: check.category,
      explanation: expand(check.explanation),
    ));
  }
}
