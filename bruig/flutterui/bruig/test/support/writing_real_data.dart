import 'dart:convert';
import 'dart:io';

import 'package:golib_plugin/definitions.dart';

// writing_real_data.dart hands a test the Writing Tools plugin's own data:
// the dictionary and every rule it ships, as the running app receives them.
//
// The rules are written in Go, in plugins/writingtools, and executed in Dart,
// by the engine under lib/plugin_system/writing_tools. For a long time nothing
// checked the two halves together -- the plugin's tests run its patterns
// through Go's regex engine, which cannot read all of them, and the app's
// tests ran its engine over a few rules written out by hand. A rule could
// pass both and do nothing in the app.
//
// The data is produced by the plugin's own `tools/dumpdata`, so this needs
// the Go toolchain. A machine without it gets null and the tests that depend
// on this skip, saying why.

/// The plugin module, found from the bruig package root the tests run in.
final Directory writingToolsPlugin =
    Directory("../../../plugins/writingtools").absolute;

SpellcheckData? _loaded;
String? _failure;

/// Why [realWritingData] returned null, for a skip message.
String get realWritingDataFailure => _failure ?? "";

/// The shipped en-US data, or null where it cannot be produced here.
///
/// Dumped once per test process. `WRITING_TOOLS_DATA` names a dump made
/// earlier, which saves the `go run` when iterating on the engine alone.
SpellcheckData? realWritingData() {
  if (_loaded != null) return _loaded;
  if (_failure != null) return null;

  String json;
  var prepared = Platform.environment["WRITING_TOOLS_DATA"];
  if (prepared != null && prepared.isNotEmpty) {
    json = File(prepared).readAsStringSync();
  } else {
    if (!writingToolsPlugin.existsSync()) {
      _failure = "plugins/writingtools is not beside this package";
      return null;
    }
    ProcessResult result;
    try {
      result = Process.runSync(
          "go", ["run", "./tools/dumpdata", "-locale", "en-US"],
          workingDirectory: writingToolsPlugin.path,
          stdoutEncoding: utf8,
          stderrEncoding: utf8);
    } on ProcessException catch (e) {
      _failure = "the Go toolchain is needed to dump the plugin's data: $e";
      return null;
    }
    if (result.exitCode != 0) {
      _failure = "tools/dumpdata failed: ${result.stderr}";
      return null;
    }
    json = result.stdout as String;
  }
  _loaded = SpellcheckData.fromJson(jsonDecode(json) as Map<String, dynamic>);
  return _loaded;
}

/// RuleExample is one rule's own proof, as its author wrote it beside the
/// rule: text it must mark, and text it must leave alone.
class RuleExample {
  /// What the app reports the rule as: "token:" and its id, or a regular
  /// expression's source.
  final String rule;
  final List<String> flags;
  final List<String> leaves;
  const RuleExample(this.rule, this.flags, this.leaves);
}

/// Every shipped rule's examples, or null where they cannot be produced
/// here -- see [realWritingData].
///
/// The plugin's own tests cannot run these for the rules stated over words:
/// the engine that reads those is the app's. So they are run here.
List<RuleExample>? realRuleExamples() {
  if (!writingToolsPlugin.existsSync()) return null;
  ProcessResult result;
  try {
    result = Process.runSync("go", ["run", "./tools/dumpdata", "-examples"],
        workingDirectory: writingToolsPlugin.path,
        stdoutEncoding: utf8,
        stderrEncoding: utf8);
  } on ProcessException {
    return null;
  }
  if (result.exitCode != 0) return null;
  List<String> strings(dynamic v) =>
      [for (var s in (v as List<dynamic>? ?? const [])) s as String];
  return [
    for (var e in jsonDecode(result.stdout as String) as List<dynamic>)
      RuleExample(
          e["rule"] as String, strings(e["flags"]), strings(e["leaves"])),
  ];
}

/// One line of the plugin's testdata/basic_errors.tsv.
class ErrorPair {
  final String category;
  final String wrong;
  final String right;
  const ErrorPair(this.category, this.wrong, this.right);
}

/// The minimal pairs in the plugin's testdata/[name].
List<ErrorPair> readErrorPairs(String name) {
  var file = File("${writingToolsPlugin.path}/testdata/$name");
  return [
    for (var line in file.readAsLinesSync())
      if (line.trim().isNotEmpty && !line.startsWith("#"))
        if (line.split("\t") case [var category, var wrong, var right])
          ErrorPair(category, wrong, right),
  ];
}
