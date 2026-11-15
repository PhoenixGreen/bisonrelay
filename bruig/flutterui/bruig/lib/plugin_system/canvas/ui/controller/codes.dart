part of '../canvas_controller.dart';

// Part of CanvasController: Code and Run panels (code_element.dart,
// code_run_element.dart) -- put down together from an example, their tabs
// picked, opened, closed and moved, the lines between their panes dragged,
// and which tab each pane shows while paused.

extension CanvasCodes on CanvasController {
  /// addCodeLesson puts down a Code panel -- an empty web page, or started
  /// from [starter] -- and a Run panel beside it running it, the two
  /// filling most of the page side by side, and picks the Code panel.
  void addCodeLesson({CodeStarter? starter, Offset? center}) {
    var page = _document.size.rect;
    var fs = codeFontFor(_document);
    var gap = page.width * 0.02;
    var h = page.height * 0.78;
    var codeW = page.width * 0.6, runW = page.width * 0.3;
    var mid = center ?? page.center;
    var left = mid.dx - (codeW + gap + runW) / 2;
    var top = mid.dy - h / 2;
    var blank = CodeElement(
        ElementBase(
            id: newElementId(),
            name: "Code",
            x: left,
            y: top,
            width: codeW,
            height: h),
        fontSize: fs);
    var code = starter == null
        ? blank.startedAs(CodeKind.web)
        : startedFrom(starter, blank);
    var run = CodeRunElement(
        ElementBase(
            id: newElementId(),
            name: "Run",
            x: left + codeW + gap,
            y: top,
            width: runW,
            height: h),
        code: code.id,
        entry: starter == null ? "" : code.files[starter.entry].id,
        outputSize: fs * 0.9);
    // A scene too short for the lesson is made long enough for it: its
    // typing, its lit lines and a moment after them.
    var doc = _document.addElement(code).addElement(run);
    var need = ((lessonLength(code) + 2) * doc.frameRate)
        .ceil()
        .clamp(1, maxFrameCount)
        .toInt();
    if (need > doc.frames) doc = doc.copyWith(frames: need);
    apply(doc);
    selectOnly(code.id);
  }

  /// openCodeStudio gives the page to the Code Studio, on Code panel [id].
  void openCodeStudio(String id) {
    if (playing) pause();
    _codeEditing = null;
    codeStudio.value = id;
  }

  void closeCodeStudio() => codeStudio.value = null;

  /// codeRunFor is the Run panel that runs Code panel [e], if it has one.
  CodeRunElement? codeRunFor(CodeElement e) => _document.elements
      .whereType<CodeRunElement>()
      .where((r) => r.code == e.id)
      .firstOrNull;

  /// codeShowFor is how the stage shows Code panel [e]: the tabs picked by
  /// hand while paused, the pane being edited, and whether it plays.
  CodeShow codeShowFor(CodeElement e) => CodeShow(
      picked: _codePicked[e.id] ?? const {},
      editing: _codeEditing?.$1 == e.id ? _codeEditing!.$2 : -1,
      playing: playing);

  /// playCode is Code panel [e]'s play button: playing, a pause; else the
  /// canvas played to its lesson's end -- from the start, where the
  /// playhead is past it.
  void playCode(CodeElement e) {
    if (playing) {
      pause();
      return;
    }
    var span = lessonSpan(e);
    if (span == null) return;
    var rate = _document.frameRate;
    var end = (span.$2 * rate).ceil();
    if (end > _document.frames) setSceneLength(end + rate);
    if (frame >= end - 1) frame = 0;
    play();
    _rangeEnd = end;
  }

  /// restartCode puts the playhead back at the scene's start, where Code
  /// panel [e]'s lesson begins; playing, it plays on from there.
  void restartCode(CodeElement e) {
    var going = playing;
    if (going) pause();
    frame = 0;
    if (going) playCode(e);
  }

  /// seekCode puts the playhead at [seconds] into the scene.
  void seekCode(double seconds) {
    if (playing) pause();
    frame = (seconds * _document.frameRate).round();
  }

  /// codePane is the pane of [e] last pressed: where a file picked from its
  /// list opens.
  int codePane(CodeElement e) =>
      (_codePane[e.id] ?? 0).clamp(0, e.layout.panes - 1).toInt();

  /// showCodeTab shows file [file] in pane [pane] of [e]: its pane's own
  /// pick from now on, and shown now whatever the scene is showing.
  void showCodeTab(CodeElement e, int pane, String file) {
    _codePane[e.id] = pane;
    (_codePicked[e.id] ??= {})[pane] = file;
    var next = e.openTab(pane, file);
    if (next.shownPanes[pane].active != e.shownPanes[pane].active) {
      replaceElement(next);
    } else {
      notifyListeners();
    }
  }

  /// openCodeFile opens [file] of [e] as a tab in the pane last pressed.
  void openCodeFile(CodeElement e, String file) =>
      showCodeTab(e, codePane(e), file);

  /// closeCodeTab closes [file]'s tab in pane [pane] of [e].
  void closeCodeTab(CodeElement e, int pane, String file) {
    if (_codePicked[e.id]?[pane] == file) _codePicked[e.id]!.remove(pane);
    replaceElement(e.closeTab(pane, file));
  }

  /// moveCodeTab moves [file]'s tab from pane [from] to pane [to] of [e],
  /// before its tab [index].
  void moveCodeTab(CodeElement e, String file, int from, int to, int index) {
    var picks = _codePicked[e.id] ??= {};
    if (picks[from] == file) picks.remove(from);
    picks[to] = file;
    _codePane[e.id] = to;
    replaceElement(e.moveTab(file, from, to, index));
  }

  /// pressCodePane notes pane [pane] of [e] as the one last pressed.
  void pressCodePane(CodeElement e, int pane) => _codePane[e.id] = pane;

  /// editCodePane opens the stage's editor on pane [pane] of [e], or shuts
  /// it (-1).
  ///
  /// Opened while its code is still typing in, the playhead goes to where
  /// it is all typed: the whole file is what is edited, and what is shown.
  void editCodePane(CodeElement e, int pane) {
    if (pane >= 0) {
      var file = codeShownFile(e, pane);
      var end = codePlan(e).end;
      if (frame / _document.frameRate < end) {
        frame = (end * _document.frameRate).ceil();
      }
      if (file != null) (_codePicked[e.id] ??= {})[pane] = file;
      _codePane[e.id] = pane;
    }
    _codeEditing = pane < 0 ? null : (e.id, pane);
    notifyListeners();
  }

  /// codeEditing is the pane being edited: its element's id and its index.
  (String, int)? get codeEditing => _codeEditing;

  /// codeEditedFile is the file the editor on pane [pane] of [e] is
  /// editing: the one the pane shows now.
  String? codeShownFile(CodeElement e, int pane) =>
      shownFile(e, pane, frame / _document.frameRate, codePlan(e),
          picked: _codePicked[e.id]?[pane]);

  /// _forgetCodePicks lets each pane show what its scene shows again:
  /// when it plays, or the playhead is moved by hand.
  void _forgetCodePicks() => _codePicked.clear();
}
