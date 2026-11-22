part of 'canvas_stage.dart';

// The clicks that ride on a press: a press on a selected element's controls
// begins a drag of it and arms a click, made if the press is let go where it
// began. PendingClick and its cases. A gesture holds the ones its press
// armed and settles them as it ends (see _CarriesClicks). Part of
// CanvasStageState: its fields, lifecycle and build are in
// canvas_stage.dart.

/// PendingClick is a click a press has armed: made when the press ends as
/// a click (see [madeBy]) and dropped otherwise, so that a press that stays
/// put clicks a control and one that travels drags what it is on. Each case
/// holds what its click needs.
sealed class PendingClick {
  /// madeBy is whether a press ending this way makes the click: for most,
  /// a press that ended as a click ([clicked]: it never went the drag
  /// threshold, was let go within the click slop and was not taken away).
  /// [cancelled] is whether the system took it away.
  bool madeBy(CanvasStageState stage,
          {required bool clicked, required bool cancelled}) =>
      clicked;

  /// inStep is whether the click is made inside the undo step of the drag
  /// it rides on, before that step is closed. Most are not: the step is
  /// closed first, so what the click changes is a step of its own and is
  /// not taken back with the drag.
  bool get inStep => false;

  /// endsRelease is whether, once the click is made, nothing more of the
  /// release is done: the resets after it in _onPointerUp are not reached.
  bool get endsRelease => true;

  /// click is what the click does.
  void click(CanvasStageState stage);

  /// travelled is the press gone past the click slop, the button still
  /// down. It answers whether the click is still pending; most are, as a
  /// press may come back and be let go where it began.
  bool travelled(CanvasStageState stage) => true;

  /// dropped is the press ended without making the click: what the click
  /// holds is let go.
  void dropped(CanvasStageState stage) {}
}

/// _ButtonClick is a selected button pressed: clicked, it runs its action,
/// and a link is handed to whoever put the stage up.
class _ButtonClick extends PendingClick {
  _ButtonClick(this.button);

  /// button is the button pressed.
  final ButtonElement button;

  @override
  void click(CanvasStageState stage) {
    var url = stage.controller.runButtonAction(button.action);
    if (url != null && url.isNotEmpty) stage.widget.onButtonLink?.call(url);
  }
}

/// _VideoClick is a selected video's control pressed: clicked, it plays,
/// pauses, mutes, seeks or sets the volume.
class _VideoClick extends PendingClick {
  _VideoClick(this.video, this.part, this.at);

  /// video is the video pressed, and part which of its controls.
  final VideoElement video;
  final VideoPart part;

  /// at is where it was pressed, in the document: how far along a bar.
  final Offset at;

  @override
  void click(CanvasStageState stage) => stage._pressVideo(video, part, at);
}

/// _SheetClick is a selected sheet with a score pressed: clicked, its
/// playbar is pressed or the playhead goes to the note there (see
/// CanvasController.sheetPressed).
class _SheetClick extends PendingClick {
  _SheetClick(this.sheet, this.at);

  /// sheet is the sheet pressed.
  final SheetElement sheet;

  /// at is where it was pressed, in the document.
  final Offset at;

  @override
  void click(CanvasStageState stage) =>
      stage.controller.sheetPressed(sheet, stage._hit.posed(sheet), at);
}

/// _AudioClick is a selected speaker's control pressed: clicked, it plays,
/// pauses, mutes or sets the volume.
class _AudioClick extends PendingClick {
  _AudioClick(this.speaker, this.part, this.at);

  /// speaker is the speaker pressed, and part which of its controls.
  final AudioElement speaker;
  final AudioControl part;

  /// at is where it was pressed, in the document: how far along the bar.
  final Offset at;

  @override
  void click(CanvasStageState stage) => stage._pressAudio(speaker, part, at);
}

/// _CounterClick is a live counter's button pressed: clicked, it runs (see
/// _pressCounter).
class _CounterClick extends PendingClick {
  _CounterClick(this.counter, this.at);

  /// counter is the counter pressed, and at which of its buttons.
  final CounterElement counter;
  final int at;

  @override
  void click(CanvasStageState stage) => stage._pressCounter(counter, at);
}

/// _LegendClick is a chart key's entry pressed: clicked, it switches that
/// series off or on. Pressed on a key the chart lays out itself, it is also
/// timed: held still for _legendHoldDelay, the press takes the key to move
/// it instead (_holdLegend).
class _LegendClick extends PendingClick {
  _LegendClick(this.chart, this.at);

  /// chart is the chart pressed, and at which entry of its key.
  final ChartElement chart;
  final int at;

  /// hold is the timer for a held press, until it fires or is stopped.
  Timer? hold;

  /// _stopHold stops the hold's timer, if it has not fired.
  void _stopHold() {
    hold?.cancel();
    hold = null;
  }

  @override
  void click(CanvasStageState stage) {
    _stopHold();
    stage._toggleSeries(chart, at);
  }

  /// travelled stops the hold: a press on the move is not held. The switch
  /// stays armed, for a press brought back.
  @override
  bool travelled(CanvasStageState stage) {
    _stopHold();
    return true;
  }

  @override
  void dropped(CanvasStageState stage) => _stopHold();
}

/// _KeyHeld is a selected instrument's key pressed, its note sounding from
/// the press until it is let go. Unlike the others it is let go however the
/// press ends, and the note's end is part of the move's undo step, before
/// the step closes, as it always was.
class _KeyHeld extends PendingClick {
  _KeyHeld(this.instrument, this.key);

  /// instrument is the instrument played, and key the note held.
  final AudioElement instrument;
  final int key;

  @override
  bool madeBy(CanvasStageState stage,
          {required bool clicked, required bool cancelled}) =>
      true;

  @override
  bool get inStep => true;

  @override
  void click(CanvasStageState stage) =>
      stage.controller.noteOff(instrument, key);

  /// travelled lets the note go: a press on the move is moving the keys,
  /// not playing them.
  @override
  bool travelled(CanvasStageState stage) {
    stage.controller.noteOff(instrument, key);
    return false;
  }
}

/// _CodePaneClick is a Code panel's code pressed: clicked, the pane opens
/// for typing.
class _CodePaneClick extends PendingClick {
  _CodePaneClick(this.id, this.pane);

  /// id is the Code panel's, and pane which of its panes.
  final String id;
  final int pane;

  /// madeBy is a click on a panel still there.
  @override
  bool madeBy(CanvasStageState stage,
          {required bool clicked, required bool cancelled}) =>
      clicked && stage.document.elementById(id) is CodeElement;

  @override
  void click(CanvasStageState stage) {
    var e = stage.document.elementById(id) as CodeElement;
    if (stage.controller.playing) stage.controller.pause();
    stage._codeEditBegun = false;
    stage.controller.editCodePane(e, pane);
  }
}

/// _CopyPick is a copy of a reused element pressed: a click on it picks it
/// (see CanvasController.pickCopy). Picking is not a change to the
/// document, so it is made inside the move's step, and the release goes on
/// after it.
class _CopyPick extends PendingClick {
  _CopyPick(this.of, this.id);

  /// of is the reused element, and id the copy's.
  final String of, id;

  @override
  bool get inStep => true;

  @override
  bool get endsRelease => false;

  @override
  void click(CanvasStageState stage) => stage.controller.pickCopy(of, id);
}
