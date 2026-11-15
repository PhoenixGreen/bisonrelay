part of '../canvas_controller.dart';

// Part of CanvasController: Run panels run (code_run_element.dart). A run
// is asked of [CanvasController.codeRunHost] -- the app's own browser and
// interpreters (media/code_run_host.dart), a fake in the tests -- and what
// it prints shows on the panel as it comes; when it is done its output and
// a picture of its preview are kept in the element, one change to undo.

/// CodeRunOutcome is what a run made: what it printed, and a picture of its
/// preview (PNG bytes; null for none).
class CodeRunOutcome {
  final List<CodeLog> logs;
  final List<int>? picture;
  const CodeRunOutcome({this.logs = const [], this.picture});
}

/// CodeRunHost runs code. [onLog] is told each line as it is printed;
/// [size] is the preview's size in the page's units, for a picture of it.
abstract class CodeRunHost {
  Future<CodeRunOutcome> run(CodeRunner runner, CodeElement code,
      CodeFile entry, Size size, void Function(CodeLog) onLog);
}

extension CanvasCodeRuns on CanvasController {
  /// codeRunning is whether Run panel [id] is running now.
  bool codeRunning(String id) => _codeRuns.containsKey(id);

  /// codeRunShowFor is how the stage shows Run panel [e]: running, and what
  /// it has printed so far; or open live, its run's output and what has
  /// been printed since.
  CodeRunShow codeRunShowFor(CodeRunElement e) {
    if (_codeLive?.$1 == e.id) {
      return CodeRunShow(
          live: true, logs: [...?e.result?.logs, ..._codeLive!.$2]);
    }
    var logs = _codeRuns[e.id];
    return logs == null
        ? const CodeRunShow()
        : CodeRunShow(running: true, logs: List.unmodifiable(logs));
  }

  /// codeLive is the Run panel whose preview is open to be used, by id.
  String? get codeLive => _codeLive?.$1;

  /// liveCode opens Run panel [e]'s preview to be used: its page live over
  /// it, or its Flutter app's own widgets. Only one that has run, and makes
  /// something to look at.
  void liveCode(CodeRunElement e) {
    if (_codeLive?.$1 == e.id || e.result == null) return;
    var code = _document.elementById(e.code);
    var runner = runnerOf(e, code is CodeElement ? code : null);
    if (runner != CodeRunner.web && runner != CodeRunner.flutter) return;
    _codeLive = (e.id, <CodeLog>[]);
    notifyListeners();
  }

  /// liveCodeLog is a line printed by the live preview.
  void liveCodeLog(CodeLog l) {
    _codeLive?.$2.add(l);
    notifyListeners();
  }

  /// endLiveCode shuts the live preview, keeping what it printed and a
  /// picture of it as it was left in place of its run's: one change.
  Future<void> endLiveCode() async {
    var live = _codeLive;
    if (live == null) return;
    var png = await codeLiveSnap?.call();
    _codeLive = null;
    var picture =
        png == null ? null : await CanvasController.saveCodePicture(png);
    if (_disposed) return;
    var e = _document.elementById(live.$1);
    if (e is CodeRunElement &&
        e.result != null &&
        (picture != null || live.$2.isNotEmpty)) {
      replaceElement(e.copyWith(
          result: e.result!.copyWith(
              logs: [...e.result!.logs, ...live.$2],
              preview: picture ?? e.result!.preview)));
    } else {
      notifyListeners();
    }
  }

  /// runCode runs Run panel [e]'s code now, and keeps what came of it.
  Future<void> runCode(CodeRunElement e) async {
    if (codeRunning(e.id)) return;
    var code = _document.elementById(e.code);
    if (code is! CodeElement) return;
    var entry = entryFile(e, code);
    var runner = runnerOf(e, code);
    if (entry == null || runner == CodeRunner.none) return;
    var logs = _codeRuns[e.id] = <CodeLog>[];
    notifyListeners();
    var host = CanvasController.codeRunHost;
    CodeRunOutcome outcome;
    try {
      var boxes = codeRunBoxes(e, e.bounds, runner: runner);
      var size = boxes.preview?.size ?? Size(e.width, e.width * 0.6);
      outcome = host == null
          ? const CodeRunOutcome(logs: [
              CodeLog("Code can't be run here.", kind: CodeLogKind.note)
            ])
          : await host.run(runner, code, entry, size, (l) {
              logs.add(l);
              notifyListeners();
            });
    } catch (err) {
      outcome = CodeRunOutcome(logs: [
        ...logs,
        CodeLog("The run stopped: $err", kind: CodeLogKind.error)
      ]);
    }
    _codeRuns.remove(e.id);
    if (_disposed) return;
    var picture = outcome.picture == null
        ? ""
        : (await CanvasController.saveCodePicture(outcome.picture!)) ?? "";
    if (_disposed) return;
    // The element as it is now: it may have been moved while it ran.
    var now = _document.elementById(e.id);
    if (now is! CodeRunElement) {
      notifyListeners();
      return;
    }
    replaceElement(now.copyWith(
        result: CodeRunResult(
            runner: runner.label,
            at: DateTime.now(),
            logs: outcome.logs,
            preview: picture)));
  }
}
