part of '../canvas_controller.dart';

// Part of CanvasController: Code and Run panels (code_element.dart,
// code_run_element.dart): put down together, tabs picked, opened, closed
// and moved, panes resized, and which tab each pane shows while paused.

extension CanvasCodes on CanvasController {
  /// addCodeLesson puts down a Code panel (an empty web page, or started
  /// from [starter]) and a Run panel beside it running it, filling most of
  /// the page, and picks the Code panel.
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
    // A scene too short for the lesson is lengthened to hold its typing,
    // its lit lines and a moment after.
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

  CodeRunElement? codeRunFor(CodeElement e) => _document.elements
      .whereType<CodeRunElement>()
      .where((r) => r.code == e.id)
      .firstOrNull;

  /// codeShowFor is how the stage shows Code panel [e]: the tabs picked by
  /// hand while paused, the pane being edited, and whether it plays.
  CodeShow codeShowFor(CodeElement e) => CodeShow(
      onStage: true,
      picked: _codePicked[e.id] ?? const {},
      editing: _codeEditing?.$1 == e.id ? _codeEditing!.$2 : -1,
      playing: playing,
      full: _codeFull.contains(e.id),
      scroll: _codeScroll[e.id] ?? const {});

  /// codeFull is whether Code panel [id] shows the whole of its code.
  bool codeFull(String id) => _codeFull.contains(id);

  /// toggleCodeFull shows the whole of [e]'s code and every lit step at
  /// once, paused for reading, or the scene's moment again.
  void toggleCodeFull(CodeElement e) {
    if (playing) pause();
    if (!_codeFull.remove(e.id)) _codeFull.add(e.id);
    _codeScroll.remove(e.id);
    // Only the stage redrawn: nothing round it shows this, and its painter
    // does not see a view's change by itself.
    keysHeld.value++;
  }

  /// scrollCode scrolls pane [pane] of [e] by [by] page units (positive is
  /// down), as far as its last line.
  void scrollCode(CodeElement e, int pane, double by) {
    var seconds = frame / _document.frameRate;
    var show = codeShowFor(e);
    var file = show.full
        ? (show.picked[pane] ?? e.shownPanes[pane].shows)
        : shownFile(e, pane, seconds, codePlan(e), picked: show.picked[pane]);
    if (file == null) return;
    var now = codeShownScroll(e, pane, seconds, show);
    var next = (now + by / codeLineHeight(e.fontSize))
        .clamp(0.0, codeScrollRoom(e, pane, file))
        .toDouble();
    if ((next - now).abs() < 1e-6) return;
    (_codeScroll[e.id] ??= {})[pane] = next;
    // Only the stage redrawn, not the editor round it: a trackpad sends
    // many of these a second.
    keysHeld.value++;
  }

  /// resetCode puts [e]'s code back as it began, as one undo step.
  void resetCode(CodeElement e) {
    if (!e.changedFromStart) return;
    _codeScroll.remove(e.id);
    replaceElement(e.reset);
  }

  /// keepCodeAsStart makes [e]'s code as it is now what Reset goes back to.
  void keepCodeAsStart(CodeElement e) =>
      replaceElement(e.copyWith(start: e.files));

  /// playCode is Code panel [e]'s play button: a pause while playing, else
  /// the canvas played to its lesson's end (from the start if the playhead
  /// is past it).
  void playCode(CodeElement e) {
    if (playing) {
      pause();
      return;
    }
    _codeFull.remove(e.id);
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

  void seekCode(double seconds) {
    if (playing) pause();
    frame = (seconds * _document.frameRate).round();
  }

  /// codePane is the pane of [e] last pressed: where a file picked from its
  /// list opens.
  int codePane(CodeElement e) =>
      (_codePane[e.id] ?? 0).clamp(0, e.layout.panes - 1).toInt();

  /// showCodeTab shows [file] in pane [pane] of [e]: the pane's own pick
  /// from now on, whatever the scene is showing.
  void showCodeTab(CodeElement e, int pane, String file) {
    _codePane[e.id] = pane;
    (_codePicked[e.id] ??= {})[pane] = file;
    var next = e.openTab(pane, file);
    if (next.shownPanes[pane].active != e.shownPanes[pane].active) {
      replaceElement(next);
    } else {
      _codeViewChanged();
    }
  }

  /// openCodeFile opens [file] of [e] as a tab in the pane last pressed.
  void openCodeFile(CodeElement e, String file) =>
      showCodeTab(e, codePane(e), file);

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

  void pressCodePane(CodeElement e, int pane) => _codePane[e.id] = pane;

  /// editCodePane opens the stage's editor on pane [pane] of [e], or shuts
  /// it (-1). Opened while its code is still typing in, the playhead goes
  /// to where it is all typed: the whole file is what is edited and shown.
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
    _codeViewChanged();
  }

  /// codeEditing is the pane being edited: its element's id and its index.
  (String, int)? get codeEditing => _codeEditing;

  /// codeShownFile is the file the editor on pane [pane] of [e] edits: the
  /// one the pane shows now.
  String? codeShownFile(CodeElement e, int pane) =>
      shownFile(e, pane, frame / _document.frameRate, codePlan(e),
          picked: _codePicked[e.id]?[pane]);

  /// _codeViewChanged is how a Code, Run or task panel's view (not the
  /// document) changes: the stage redrawn, since its painter compares only
  /// what it is given and a view's state is not in that.
  void _codeViewChanged() {
    keysHeld.value++;
    notifyListeners();
  }

  /// _forgetCodePicks lets each pane show what its scene shows again:
  /// when it plays, or the playhead is moved by hand.
  void _forgetCodePicks() {
    _codePicked.clear();
    _codeScroll.clear();
    _codeRanNow.clear();
  }
}
