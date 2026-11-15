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
  /// it has printed so far.
  CodeRunShow codeRunShowFor(CodeRunElement e) {
    var logs = _codeRuns[e.id];
    return logs == null
        ? const CodeRunShow()
        : CodeRunShow(running: true, logs: List.unmodifiable(logs));
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
