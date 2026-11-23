import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/colour_map.dart';

// code_run_element.dart is a Run panel: it runs a Code panel's project and
// shows the page or app it makes, over what it printed. A run's result is
// kept in the element (CodeRunResult: output, and a preview picture as an
// asset), so a canvas opens showing its last run, an export plays that run
// without running anything, and a received canvas never runs code until
// Run is pressed.

enum CodeRunWhen {
  press("When Run is pressed"),
  typed("When the typing ends"),
  start("As the scene starts");

  final String label;
  const CodeRunWhen(this.label);
}

enum CodeRunShows {
  both("Preview and output"),
  preview("Preview"),
  output("Output");

  final String label;
  const CodeRunShows(this.label);
}

/// CodeLogKind is what a line of output is: printed, a warning, an error, or
/// a word from the runner itself (fetching Python, say).
enum CodeLogKind { log, warn, error, note }

/// maxCodeLogs and maxCodeLogLength cap the output kept, in lines and line
/// length: endless printing must not fill the screen or the canvas file.
const maxCodeLogs = 2000, maxCodeLogLength = 4000;

class CodeLog {
  final CodeLogKind kind;
  final String text;
  const CodeLog(this.text, {this.kind = CodeLogKind.log});

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = CodeLog("");

  /// capped is this, its text cut to [maxCodeLogLength].
  CodeLog get capped => text.length <= maxCodeLogLength
      ? this
      : CodeLog("${text.substring(0, maxCodeLogLength)}…", kind: kind);

  Map<String, dynamic> toJson() =>
      {"text": text, if (kind != _defaults.kind) "kind": kind.name};

  static CodeLog? fromJson(dynamic j) => j is Map<String, dynamic>
      ? CodeLog(jsonString(j["text"], ""),
          kind: CodeLogKind.values.asNameMap()[j["kind"]] ?? CodeLogKind.log)
      : null;
}

/// CodeRunResult is a run, kept: what ran it, when, what it printed, and a
/// picture of its preview (an asset id; empty for none).
class CodeRunResult {
  final String runner;
  final DateTime at;
  final List<CodeLog> logs;
  final String preview;
  const CodeRunResult(
      {required this.runner,
      required this.at,
      this.logs = const [],
      this.preview = ""});

  CodeRunResult copyWith({List<CodeLog>? logs, String? preview}) =>
      CodeRunResult(
          runner: runner,
          at: at,
          logs: logs ?? this.logs,
          preview: preview ?? this.preview);

  Map<String, dynamic> toJson() => {
        "runner": runner,
        "at": at.toUtc().toIso8601String(),
        "logs": [for (var l in logs) l.toJson()],
        if (preview.isNotEmpty) "preview": preview,
      };

  static CodeRunResult? fromJson(dynamic j) {
    if (j is! Map<String, dynamic>) return null;
    return CodeRunResult(
        runner: jsonString(j["runner"], ""),
        at: DateTime.tryParse(jsonString(j["at"], "")) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        logs: [
          for (var l
              in (j["logs"] is List ? j["logs"] as List : []).take(maxCodeLogs))
            if (CodeLog.fromJson(l) case var log?) log.capped
        ],
        preview: jsonString(j["preview"], ""));
  }
}

/// codeAppWidths are the widths a Run panel can lay its app out at, and
/// what each is called: 0 fits the panel.
const codeAppWidths = <(double, String)>[
  (0, "Fit the panel"),
  (360, "Phone (360)"),
  (768, "Tablet (768)"),
  (1280, "Desktop (1280)"),
];

class CodeRunElement extends CanvasElement {
  /// code is the Code panel it runs, by id.
  final String code;

  /// entry is the file it starts from, by id: the page, or the program's
  /// main file. Empty: the first it can run.
  final String entry;
  final CodeRunWhen when;
  final CodeRunShows shows;

  /// split is the preview's share of the height, when both show.
  final double split;

  /// outputSize is the output's text size on the page.
  final double outputSize;

  /// dartpad runs a Flutter app on DartPad (Google's servers, over the
  /// internet), not in the app with flutter_eval. Off unless turned on.
  final bool dartpad;

  /// appWidth is how wide, in logical pixels, an app it runs (a page or a
  /// Flutter app) is laid out before it is fitted to the preview: one of
  /// [codeAppWidths]; 0 fits the panel (at least a phone's width). The same
  /// for a run's picture and the live preview, at any zoom.
  final double appWidth;
  final CodeRunResult? result;

  const CodeRunElement(
    super.base, {
    this.code = "",
    this.entry = "",
    this.when = CodeRunWhen.typed,
    this.shows = CodeRunShows.both,
    this.split = 0.55,
    this.outputSize = 15,
    this.dartpad = false,
    this.appWidth = 0,
    this.result,
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = CodeRunElement(ElementBase(id: ""));

  @override
  ElementKind get kind => ElementKind.codeRun;

  /// mapOwnColours is this: it has no colour of its own.
  @override
  CanvasElement mapOwnColours(ColourMap f) => this;

  @override
  CanvasElement rebase(ElementBase base) => CodeRunElement(base,
      code: code,
      entry: entry,
      when: when,
      shows: shows,
      split: split,
      outputSize: outputSize,
      dartpad: dartpad,
      appWidth: appWidth,
      result: result);

  CodeRunElement copyWith({
    String? code,
    String? entry,
    CodeRunWhen? when,
    CodeRunShows? shows,
    double? split,
    double? outputSize,
    bool? dartpad,
    double? appWidth,
    CodeRunResult? result,
    bool clearResult = false,
  }) =>
      CodeRunElement(base,
          code: code ?? this.code,
          entry: entry ?? this.entry,
          when: when ?? this.when,
          shows: shows ?? this.shows,
          split: (split ?? this.split).clamp(0.15, 0.85),
          outputSize: (outputSize ?? this.outputSize).clamp(4.0, 1000.0),
          dartpad: dartpad ?? this.dartpad,
          appWidth: (appWidth ?? this.appWidth).clamp(0.0, 4000.0),
          result: clearResult ? null : result ?? this.result);

  /// appSize is the layout size for a [preview] that big: [appWidth] across
  /// (or the preview's, at least a phone's), in the preview's shape.
  Size appSize(Size preview) {
    var w = appWidth > 0 ? appWidth : math.max(360.0, preview.width);
    return Size(w, preview.height * w / math.max(1.0, preview.width));
  }

  @override
  Set<String> get assetIds => {
        if (result case var r? when r.preview.isNotEmpty) r.preview,
      };

  @override
  Map<String, dynamic> props() => {
        "code": code,
        if (entry.isNotEmpty) "entry": entry,
        "when": when.name,
        "shows": shows.name,
        "split": split,
        "outputSize": outputSize,
        if (dartpad) "dartpad": true,
        if (appWidth > 0) "appWidth": appWidth,
        if (result != null) "result": result!.toJson(),
      };

  factory CodeRunElement.fromJson(Map<String, dynamic> json, ElementBase b) =>
      CodeRunElement(b,
          code: jsonString(json["code"], _defaults.code),
          entry: jsonString(json["entry"], _defaults.entry),
          when:
              CodeRunWhen.values.asNameMap()[json["when"]] ?? CodeRunWhen.typed,
          shows: CodeRunShows.values.asNameMap()[json["shows"]] ??
              CodeRunShows.both,
          split: jsonDouble(json["split"], _defaults.split).clamp(0.15, 0.85),
          outputSize: jsonDouble(json["outputSize"], _defaults.outputSize)
              .clamp(4.0, 1000.0),
          dartpad: jsonBool(json["dartpad"], false),
          appWidth: jsonDouble(json["appWidth"], _defaults.appWidth)
              .clamp(0.0, 4000.0),
          result: CodeRunResult.fromJson(json["result"]));
}
