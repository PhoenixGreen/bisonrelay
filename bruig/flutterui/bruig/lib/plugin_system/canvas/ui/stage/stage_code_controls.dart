part of 'canvas_stage.dart';

// A Code panel's and a Run panel's controls on the stage: what a press and
// its release do on a Code panel's playbar, tabs, files, dividers and code,
// and on a Run panel's Run button and preview, and the gestures they begin
// (the playbar scrubbed, a divider dragged, a tab carried, a press left to a
// live preview); the widgets laid over them while they are worked (the code
// editor, the live preview, a carried tab); and a pane's hover and wheel
// scroll. Part of CanvasStageState: its fields, lifecycle and build are in
// canvas_stage.dart.

extension StageCodeControls on CanvasStageState {
  /// _pressCode answers [press] on Code panel [e]: a tab shown, or carried
  /// to move it; its cross closing it; a listed file opened in the pane last
  /// pressed; a pane divider dragged; a press on the code armed on [press]
  /// to open it for typing. False on the panel itself, to pick and move it.
  bool _pressCode(_Press press, CodeElement e) {
    var hit = codeHitAt(e, press.doc);
    if (hit == null) return false;
    switch (hit) {
      // Its playbar works picked or not; the track is dragged to scrub.
      case CodePlayHit(part: CodePlayPart.play):
        controller.playCode(e);
        _mode = _DragMode.none;
        return true;
      case CodePlayHit(part: CodePlayPart.full):
        controller.toggleCodeFull(e);
        _mode = _DragMode.none;
        return true;
      case CodePlayHit(part: CodePlayPart.restart):
        controller.restartCode(e);
        _mode = _DragMode.none;
        return true;
      case CodePlayHit(part: CodePlayPart.reset):
        controller.resetCode(e);
        _mode = _DragMode.none;
        return true;
      case CodePlayHit(:var at):
        controller.seekCode(at);
        setState(() => _gesture = _CodeScrub(e.id));
        return true;
      case CodeDividerHit(:var divider):
        controller.selectAlone(e.id);
        controller.beginInteraction();
        setState(() => _gesture = _CodeDividerDrag(e.id, divider));
        return true;
      case CodeTabHit(:var pane, :var file, close: true):
        controller.selectAlone(e.id);
        controller.closeCodeTab(e, pane, file);
        _mode = _DragMode.none;
        return true;
      case CodeTabHit(:var pane, :var file):
        controller.selectAlone(e.id);
        setState(() => _gesture = _CodeTabCarry(e.id, pane, file));
        return true;
      case CodeFileHit(:var file):
        controller.selectAlone(e.id);
        controller.openCodeFile(e, file);
        _mode = _DragMode.none;
        return true;
      case CodePaneHit(:var pane, :var inTabs):
        controller.pressCodePane(e, pane);
        // One click on the code opens it for typing; a press that becomes a
        // drag moves the panel instead. See _CodePaneClick.
        if (!inTabs && !_shiftHeld) press.click = _CodePaneClick(e.id, pane);
        return false;
    }
  }

  /// _pressCodeRun answers a Run panel's Run button, and opens a picked
  /// panel's preview live.
  bool _pressCodeRun(CodeRunElement e, Offset doc) {
    var code = document.elementById(e.code);
    var runner = runnerOf(e, code is CodeElement ? code : null);
    var boxes = codeRunBoxes(e, _hit.posed(e), runner: runner);
    var picked = controller.isOnlySelected(e.id);
    if (picked &&
        !_shiftHeld &&
        (boxes.preview?.contains(doc) ?? false) &&
        e.result != null &&
        (runner == CodeRunner.web || runner == CodeRunner.flutter)) {
      controller.liveCode(e);
      // The opening press is replayed into the app once it is there.
      if (runner == CodeRunner.flutter) _liveTapPending = true;
      _mode = _DragMode.none;
      return true;
    }
    if (!boxes.runButton.contains(doc)) {
      return false;
    }
    controller.selectAlone(e.id);
    // Run, then open live, so the next press goes to the app.
    controller.runCode(e).then((_) {
      if (!mounted || controller.codeLive != null) return;
      var now = document.elementById(e.id);
      if (now is CodeRunElement &&
          now.result?.preview.isNotEmpty == true &&
          controller.isOnlySelected(e.id) &&
          (runner == CodeRunner.web || runner == CodeRunner.flutter)) {
        controller.liveCode(now);
      }
    });
    _mode = _DragMode.none;
    return true;
  }

  /// _replayTap presses the live app at [global] once built, as a touch: a
  /// mouse's would need its pointer added first.
  void _replayTap(Offset global) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || controller.codeLive == null) return;
      var id = ++_replayPointer;
      GestureBinding.instance.handlePointerEvent(PointerDownEvent(
          pointer: id, position: global, kind: PointerDeviceKind.touch));
      GestureBinding.instance.handlePointerEvent(PointerUpEvent(
          pointer: id, position: global, kind: PointerDeviceKind.touch));
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// _scrubCode puts the playhead where on Code panel [id]'s playbar track
  /// [doc] is.
  void _scrubCode(String id, Offset doc) {
    if (document.elementById(id) case CodeElement e) {
      controller.seekCode(codeTrackSeconds(e, doc));
    }
  }

  /// _dragCodeDivider moves Code panel [id]'s pane [divider] to [doc].
  /// Transient: the drag is one undo step.
  void _dragCodeDivider(String id, CodeDividerBox divider, Offset doc) {
    if (document.elementById(id) case CodeElement e) {
      controller.replaceElement(codeDividerDragged(e, divider, doc),
          transient: true);
    }
  }

  /// _carryCodeTab takes [tab] to [doc], once it has gone past the click
  /// slop: short of that it is a click on the tab.
  void _carryCodeTab(_CodeTabCarry tab, Offset doc) {
    if (tab.carriedTo != null ||
        (_toStage(doc) - _pressedAt).distance >
            CanvasStageState._buttonClickSlop) {
      setState(() => tab.carriedTo = doc);
    }
  }

  /// _dropCodeTab ends [tab], let go at [at]: shown if it was never
  /// carried, else moved where it is dropped. With no [at], the press taken
  /// away, neither.
  void _dropCodeTab(_CodeTabCarry tab, {Offset? at}) {
    var carried = tab.carriedTo != null;
    setState(() {});
    var e = document.elementById(tab.codeId);
    if (e is! CodeElement || at == null) return;
    if (!carried) {
      controller.showCodeTab(e, tab.pane, tab.file);
      return;
    }
    if (codeTabDrop(e, at) case (var to, var index)?) {
      controller.moveCodeTab(e, tab.file, tab.pane, to, index);
    }
  }

  /// _codeTabCarried is a carried tab's name at the pointer and a drop mark.
  List<Widget> _codeTabCarried() {
    var (tab, at) = switch (_gesture) {
      _CodeTabCarry t => (t, t.carriedTo),
      _ => (null, null),
    };
    if (tab == null || at == null) return const [];
    var e = document.elementById(tab.codeId);
    if (e is! CodeElement) return const [];
    var f = e.file(tab.file);
    if (f == null) return const [];
    var theme = Theme.of(context);
    var out = <Widget>[];
    if (codeTabDrop(e, at) case (var pane, var index)?) {
      var b = codeBoxes(e, e.bounds).panes[pane];
      var x = b.tabs.isEmpty
          ? b.tabRow.left + e.fontSize * 0.3
          : index < b.tabs.length
              ? b.tabs[index].rect.left
              : b.tabs.last.rect.right;
      var top = _toStage(Offset(x, b.tabRow.top + e.fontSize * 0.3));
      out.add(Positioned(
          left: top.dx - 2,
          top: top.dy,
          width: 4,
          height: (b.tabRow.height - e.fontSize * 0.6) * _scale,
          child: IgnorePointer(
              child: ColoredBox(color: theme.colorScheme.primary))));
    }
    var p = _toStage(at);
    out.add(Positioned(
        left: p.dx + 12,
        top: p.dy + 10,
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: theme.colorScheme.primary),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, color: f.colour),
              const SizedBox(width: 6),
              Text(f.name, style: const TextStyle(fontSize: 12.5)),
            ]),
          ),
        )));
    return out;
  }

  /// _codeEditorFor is the code editor over the pane being edited, if open.
  Widget? _codeEditorFor() {
    var (id, pane) = controller.codeEditing ?? ("", -1);
    if (pane < 0) return null;
    var e = document.elementById(id);
    if (e is! CodeElement) return null;
    var file = controller.codeShownFile(e, pane);
    var rect = codeEditorRect(e, pane);
    if (file == null || rect == null) return null;
    return CodePaneEditor(
      key: ValueKey("codeEditing-$id-$pane-$file"),
      element: e,
      file: file,
      rect: _toStageRect(rect),
      scale: _scale,
      onChanged: (text) {
        var now = document.elementById(id);
        if (now is! CodeElement) return;
        if (!_codeEditBegun) {
          _codeEditBegun = true;
          controller.beginInteraction();
        }
        controller.replaceElement(now.typedInto(file, text), transient: true);
      },
      onDone: () {
        if (_codeEditBegun) {
          _codeEditBegun = false;
          controller.endInteraction();
        }
        if (controller.codeEditing != null) {
          var now = document.elementById(id);
          if (now is CodeElement) controller.editCodePane(now, -1);
        }
        _focus.requestFocus();
      },
    );
  }

  /// _codeLiveRect is the open live preview on the stage, if any.
  Rect? _codeLiveRect() {
    var e = document.elementById(controller.codeLive ?? "");
    if (e is! CodeRunElement) return null;
    var code = document.elementById(e.code);
    var runner = runnerOf(e, code is CodeElement ? code : null);
    var preview = codeRunBoxes(e, _hit.posed(e), runner: runner).preview;
    if (preview == null) return null;
    return _toStageRect(preview);
  }

  Widget? _codeLiveFor() {
    var id = controller.codeLive;
    if (id == null) return null;
    var e = document.elementById(id);
    if (e is! CodeRunElement) return null;
    var code = document.elementById(e.code);
    if (code is! CodeElement) return null;
    var entry = entryFile(e, code);
    var runner = runnerOf(e, code);
    var preview = codeRunBoxes(e, _hit.posed(e), runner: runner).preview;
    if (entry == null || preview == null) return null;
    return CodeLivePreview(
      key: ValueKey("codeLive-$id"),
      runner: runner,
      code: code,
      entry: entry,
      rect: _toStageRect(preview),
      appSize: e.appSize(preview.size),
      onLog: controller.liveCodeLog,
      onSnap: (snap) => controller.codeLiveSnap = snap,
    );
  }

  /// _hoverCode notes the code pane under the pointer, at document point
  /// [doc], which then scrolls instead of the page.
  void _hoverCode(Offset doc) {
    var over = _codePaneAt(doc);
    if (over != _codeOver) setState(() => _codeOver = over);
  }

  /// _scrollCodeBy scrolls pane [at] by [by] stage pixels, down positive.
  void _scrollCodeBy((String, int) at, double by) {
    var e = document.elementById(at.$1);
    if (e is! CodeElement) return;
    controller.scrollCode(e, at.$2, by / _scaleOrOne);
  }
}

/// _CodeScrub is a Code panel's playbar track dragged along, the playhead
/// following. Not a change to the panel: no undo step.
class _CodeScrub extends StageGesture {
  _CodeScrub(this.codeId);

  /// codeId is the Code panel's.
  final String codeId;

  @override
  bool get opensUndoStep => false;

  @override
  bool get waitsToTravel => true;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) =>
      stage._scrubCode(codeId, doc);

  /// endsRelease is true: the playhead is where the drag left it, and the
  /// resets that follow are for the kinds still on _DragMode.
  @override
  bool get endsRelease => true;

  /// release rebuilds the stage, which no longer draws a scrub under way.
  @override
  void release(CanvasStageState stage, Offset at,
          {required bool travelled, required bool clicked}) =>
      stage.setState(() {});

  @override
  void cancel(CanvasStageState stage) => stage.setState(() {});
}

/// _CodeDividerDrag is the line between two of a Code panel's panes
/// dragged, sizing them. One undo step.
class _CodeDividerDrag extends StageGesture {
  _CodeDividerDrag(this.codeId, this.divider);

  /// codeId is the Code panel's, and divider the line taken.
  final String codeId;
  final CodeDividerBox divider;

  @override
  bool get opensUndoStep => true;

  @override
  bool get waitsToTravel => true;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) =>
      stage._dragCodeDivider(codeId, divider, doc);

  /// endsRelease is true, as for the playbar scrubbed.
  @override
  bool get endsRelease => true;

  /// release rebuilds the stage, which no longer draws a drag under way.
  @override
  void release(CanvasStageState stage, Offset at,
          {required bool travelled, required bool clicked}) =>
      stage.setState(() {});

  @override
  void cancel(CanvasStageState stage) => stage.setState(() {});
}

/// _CodeTabCarry is a Code panel's tab pressed: let go without being
/// carried, the tab is shown in its pane; carried, it is drawn at the
/// pointer and moved to the pane and place it is dropped on (see
/// codeTabDrop). Its change is the controller's to make: it opens no undo
/// step of its own.
class _CodeTabCarry extends StageGesture {
  _CodeTabCarry(this.codeId, this.pane, this.file);

  /// codeId is the Code panel's, pane the pane the tab is in, and file the
  /// file it shows.
  final String codeId;
  final int pane;
  final String file;

  /// carriedTo is where the tab has been carried, in the document; null
  /// until the press goes past the click slop.
  Offset? carriedTo;

  @override
  bool get opensUndoStep => false;

  @override
  bool get waitsToTravel => true;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) =>
      stage._carryCodeTab(this, doc);

  /// endsRelease is true: showing or moving the tab is the whole of its
  /// release.
  @override
  bool get endsRelease => true;

  @override
  void release(CanvasStageState stage, Offset at,
          {required bool travelled, required bool clicked}) =>
      stage._dropCodeTab(this, at: stage._toDocument(at));

  @override
  void cancel(CanvasStageState stage) => stage._dropCodeTab(this);
}

/// _LivePress is a press on a Code run's live preview that reached the
/// stage: one that lands before the preview is drawn over the page. It is
/// the preview's, so the stage does nothing with it, not even hover, and
/// takes every move and the release first.
class _LivePress extends StageGesture {
  @override
  bool get takesAll => true;

  @override
  bool get opensUndoStep => false;

  @override
  bool get waitsToTravel => false;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) {}

  @override
  void release(CanvasStageState stage, Offset at,
      {required bool travelled, required bool clicked}) {}

  @override
  void cancel(CanvasStageState stage) {}
}
