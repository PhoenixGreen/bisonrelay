part of '../canvas_controller.dart';

// Part of CanvasController: Run panels run (code_run_element.dart). A run
// is asked of [CanvasController.codeRunHost] (the app's browser and
// interpreters, a fake in tests); what it prints shows as it comes, and
// when done its output and a picture of its preview are kept in the
// element as one undo step.

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
  bool codeRunning(String id) => _codeRuns.containsKey(id);

  /// codeRunShowFor is how the stage shows Run panel [e]: running and what
  /// it has printed, or open live with its run's output and what has been
  /// printed since.
  CodeRunShow codeRunShowFor(CodeRunElement e) {
    var now = _codeRanNow.contains(e.id) || _codeFull.contains(e.code);
    if (_codeLive?.$1 == e.id) {
      return CodeRunShow(
          live: true, now: now, logs: [...?e.result?.logs, ..._codeLive!.$2]);
    }
    var logs = _codeRuns[e.id];
    if (logs != null) {
      return CodeRunShow(running: true, logs: List.unmodifiable(logs));
    }
    return CodeRunShow(now: now);
  }

  /// codeLive is the id of the Run panel whose preview is open to be used.
  String? get codeLive => _codeLive?.$1;

  /// liveCode opens Run panel [e]'s preview to be used: its page live over
  /// it, or its Flutter app's widgets. Only on the user's own action: a run
  /// that came with a received canvas is its sender's code, and nobody here
  /// runs it until Run is pressed.
  void liveCode(CodeRunElement e) {
    if (_codeLive?.$1 == e.id || e.result == null) return;
    if (!_codeRunHere.contains(e.id)) return;
    var code = _document.elementById(e.code);
    var runner = runnerOf(e, code is CodeElement ? code : null);
    if (runner != CodeRunner.web && runner != CodeRunner.flutter) return;
    _codeLive = (e.id, <CodeLog>[]);
    _codeViewChanged();
  }

  /// liveCodeLog is a line printed by the live preview, so long as it has
  /// not printed [maxCodeLogs] already.
  void liveCodeLog(CodeLog l) {
    var live = _codeLive;
    if (live == null || live.$2.length >= maxCodeLogs) return;
    live.$2.add(l.capped);
    _codeViewChanged();
  }

  /// endLiveCode shuts the live preview, keeping what it printed and a
  /// picture of it in place of its run's, as one change.
  Future<void> endLiveCode() async {
    var live = _codeLive;
    if (live == null) return;
    var loads = _loads;
    var png = await codeLiveSnap?.call();
    // Another canvas opened meanwhile: the preview was the last one's.
    if (_loads != loads) return;
    _codeLive = null;
    var picture =
        png == null ? null : await CanvasController.saveCodePicture(png);
    if (_disposed || _loads != loads) return;
    var e = _document.elementById(live.$1);
    if (e is CodeRunElement &&
        e.result != null &&
        (picture != null || live.$2.isNotEmpty)) {
      replaceElement(e.copyWith(
          result: e.result!.copyWith(
              logs: [...e.result!.logs, ...live.$2],
              preview: picture ?? e.result!.preview)));
    } else {
      _codeViewChanged();
    }
  }

  /// runCode runs Run panel [e]'s code now and keeps the outcome.
  Future<void> runCode(CodeRunElement e) async {
    if (codeRunning(e.id)) return;
    var code = _document.elementById(e.code);
    if (code is! CodeElement) return;
    var entry = entryFile(e, code);
    var runner = runnerOf(e, code);
    if (entry == null || runner == CodeRunner.none) return;
    // The canvas it was started on: one opened while it runs is not, and
    // nothing of the run reaches it, even a panel of the same id.
    var loads = _loads;
    var logs = _codeRuns[e.id] = <CodeLog>[];
    // Run by hand: shown now, not when the scene's clock comes to it.
    _codeRanNow.add(e.id);
    _codeRunHere.add(e.id);
    _codeViewChanged();
    var host = CanvasController.codeRunHost;
    CodeRunOutcome outcome;
    try {
      var boxes = codeRunBoxes(e, e.bounds, runner: runner);
      var size = e.appSize(boxes.preview?.size ?? Size(e.width, e.width * 0.6));
      outcome = host == null
          ? const CodeRunOutcome(logs: [
              CodeLog("Code can't be run here.", kind: CodeLogKind.note)
            ])
          : await host.run(runner, code, entry, size, (l) {
              // Only the first [maxCodeLogs] lines are kept, so a program
              // that prints for ever fills neither screen nor file.
              if (_loads != loads || logs.length >= maxCodeLogs) return;
              logs.add(l.capped);
              _codeViewChanged();
            });
    } catch (err) {
      outcome = CodeRunOutcome(logs: [
        ...logs,
        CodeLog("The run stopped: $err", kind: CodeLogKind.error)
      ]);
    }
    if (_loads != loads) return;
    _codeRuns.remove(e.id);
    if (_disposed) return;
    var picture = outcome.picture == null
        ? ""
        : (await CanvasController.saveCodePicture(outcome.picture!)) ?? "";
    if (_disposed || _loads != loads) return;
    // The element as it is now: it may have been moved while it ran.
    var now = _document.elementById(e.id);
    if (now is! CodeRunElement) {
      _codeViewChanged();
      return;
    }
    replaceElement(now.copyWith(
        result: CodeRunResult(
            runner: runner.label,
            at: DateTime.now(),
            logs: [for (var l in outcome.logs.take(maxCodeLogs)) l.capped],
            preview: picture)));
  }
}
