part of '../canvas_controller.dart';

// Part of CanvasController: Code task cards (code_task_element.dart), put
// beside a Code panel, kept the height of their text, and checked against
// the code as it is, building it where a check asks.

extension CanvasCodeTasks on CanvasController {
  /// _codeNow is a fingerprint of [code]'s files as they are: a check
  /// holds only while they stay so.
  int _codeNow(CodeElement? code) =>
      code == null ? 0 : Object.hashAll([for (var f in code.files) f.text]);

  /// codeTaskShowFor is how the stage shows card [e]: checked (if against
  /// the code as it is now) and whether that built.
  CodeTaskShow codeTaskShowFor(CodeTaskElement e) {
    if (_codeTaskBusy.contains(e.id)) {
      return const CodeTaskShow(checking: true);
    }
    var done = _codeTaskChecks[e.id];
    var (code, _) = e.codeIn(_document);
    if (done == null || done.$1 != _codeNow(code)) return const CodeTaskShow();
    return CodeTaskShow(checked: true, built: done.$2);
  }

  /// checkCodeTask checks card [e] against its Code panel's code, building
  /// it first where a check asks.
  Future<void> checkCodeTask(CodeTaskElement e) async {
    if (_codeTaskBusy.contains(e.id)) return;
    var (code, run) = e.codeIn(_document);
    if (code == null) return;
    // A check still building as another canvas opens was the last one's,
    // and lands nowhere: not even on a card of the same id.
    var loads = _loads;
    bool? built;
    if (e.checks.any((c) => c.kind == CodeCheckKind.builds)) {
      _codeTaskBusy.add(e.id);
      _codeViewChanged();
      try {
        built = await _builds(code, run);
      } finally {
        if (_stillOn(loads)) _codeTaskBusy.remove(e.id);
      }
    }
    if (!_stillOn(loads)) return;
    _codeTaskChecks[e.id] = (_codeNow(code), built);
    _codeViewChanged();
  }

  /// _builds is whether [code] builds and runs without an error: a Flutter
  /// app compiled and its widget made, a Dart program run; anything else
  /// by its Run panel's last run.
  Future<bool> _builds(CodeElement code, CodeRunElement? run) async {
    var r = run ?? CodeRunElement(const ElementBase(id: ""), code: code.id);
    var entry = entryFile(r, code);
    if (entry == null) return false;
    switch (runnerOf(r, code)) {
      case CodeRunner.flutter || CodeRunner.dartpad:
        return buildFlutterApp(code, entry).widget != null;
      case CodeRunner.dart:
        var logs =
            await runDart(code, entry, limit: const Duration(seconds: 10));
        return !logs.any((l) => l.kind == CodeLogKind.error);
      default:
        var result = run?.result;
        return result != null &&
            !result.logs.any((l) => l.kind == CodeLogKind.error);
    }
  }

  /// addCodeTask puts a task card down for Code panel [code]: under its Run
  /// panel where there is room, else under the panel itself, and picks it.
  void addCodeTask(CodeElement code) {
    var page = _document.size.rect;
    var run = codeRunFor(code);
    var ts = math.max(8.0, code.fontSize * 0.95);
    var w = run?.width ?? math.min(code.width * 0.5, page.width * 0.4);
    var card = CodeTaskElement(
        ElementBase(id: newElementId(), name: "Code task", width: w),
        code: code.id,
        textSize: ts,
        checks: const [
          CodeCheck(CodeCheckKind.builds, "It builds and runs"),
        ]);
    var h = codeTaskFitHeight(card, w);
    var at = run != null && run.bounds.bottom + 20 + h <= page.bottom
        ? Offset(run.x, run.bounds.bottom + 20)
        : Offset(code.x, math.min(code.bounds.bottom + 20, page.bottom - h));
    apply(_document.addElement(
        card.withBase(x: at.dx, y: at.dy, height: h) as CodeTaskElement));
    selectOnly(card.id);
  }

  /// setCodeTask writes [e] over the card with its id, its height fitted to
  /// its text.
  void setCodeTask(CodeTaskElement e, {bool transient = false}) =>
      replaceElement(e.withBase(height: codeTaskFitHeight(e, e.width)),
          transient: transient);
}
