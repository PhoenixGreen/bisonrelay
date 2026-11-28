part of 'canvas_stage.dart';

// The other elements' own controls on the stage: a metronome's buttons; a
// counter's buttons, its loose pieces dragged (_CounterPieceDrag), and the
// field on its Set button; a chart key's switches and the hold that takes
// the key instead; a chart's placed labels and a table's column rules, as
// drawn and as taken; a video's and a speaker's controls; a play task's
// steps ticked; and a text's flow link dropped. Part of CanvasStageState: its fields, lifecycle and build
// are in canvas_stage.dart.

extension StageElementControls on CanvasStageState {
  /// _labelledChart is the lone selected chart whose placed labels are
  /// drawn and can be taken: not a locked one, and not with helpers hidden.
  /// Drawing and pressing both ask this, so they agree.
  ChartElement? get _labelledChart {
    var element = controller.selected;
    if (element is! ChartElement || element.locked) return null;
    return controller.showHelpers ? element : null;
  }

  /// _selectedChartLabels are the placed labels of the chart whose labels
  /// are shown (see _labelledChart), each with whether it has a resize grip:
  /// in its box, which the painter lays on the page by _partsPlace.
  List<({Rect rect, bool grip})> _selectedChartLabels() {
    var element = _labelledChart;
    if (element == null) return const [];
    return [
      for (var MapEntry(key: part, value: rect)
          in chartLabelPlaces(element, _hit.placed(element).box).entries)
        if (!rect.isEmpty) (rect: rect, grip: chartLabelResizes(part)),
    ];
  }

  /// _partsPlace is where the painter lays out the chart whose labels, or
  /// the table whose column rules, are shown (see _labelledChart and
  /// _columnedTable): their marks are drawn on the page by it, so they sit
  /// on the parts as drawn. Null when neither is.
  ElementPlace? get _partsPlace => switch (_labelledChart ?? _columnedTable) {
        var e? => _hit.placed(e).place,
        null => null,
      };

  /// _chartLabelAt is the placed label of the labelled chart at [doc], and
  /// how it is taken, or null.
  ChartLabelGrab? _chartLabelAt(Offset doc) {
    var chart = _labelledChart;
    if (chart == null) return null;
    var inside = _hit.inBox(chart, doc);
    if (inside == null) return null;
    return chartLabelGrabAt(chart, inside.on.box, inside.point, _docSlop);
  }

  /// _columnedTable is the lone selected table whose column rules have
  /// grips and can be taken: not a locked one, and not with helpers hidden.
  /// Drawing and pressing both ask this, so they agree.
  TableElement? get _columnedTable {
    var element = controller.selected;
    if (element is! TableElement || element.locked) return null;
    return controller.showHelpers ? element : null;
  }

  /// _selectedTableColumns are the inner column rules of the table whose
  /// rules can be taken (see _columnedTable), as (x, top, bottom), for
  /// grips: in its box, which the painter lays on the page by _partsPlace.
  List<(double, double, double)> _selectedTableColumns() {
    var element = _columnedTable;
    if (element == null) return const [];
    var bounds = _hit.placed(element).box;
    return [
      for (var x in tableColumnDividers(element, bounds))
        (x, bounds.top, bounds.bottom),
    ];
  }

  /// _tableColumnAt is the column rule of that table at [doc], or null.
  int? _tableColumnAt(Offset doc) {
    var table = _columnedTable;
    if (table == null) return null;
    var inside = _hit.inBox(table, doc);
    if (inside == null) return null;
    return tableColumnAt(table, inside.on.box, inside.point, _docSlop);
  }

  /// _onTableColumnGrip is whether a press at [stage] is on one of the grips
  /// drawn at the ends of a column rule, and takes the rule.
  bool _onTableColumnGrip(Offset stage, Offset doc) {
    if (_tableColumnAt(doc) == null) return false;
    var place = _partsPlace;
    if (place == null) return false;
    for (var (x, top, bottom) in _selectedTableColumns()) {
      for (var grip in tableColumnGrips(_toStage(place.place(Offset(x, top))),
          _toStage(place.place(Offset(x, bottom))))) {
        if (grip.inflate(handleHitSlop).contains(stage)) return true;
      }
    }
    return false;
  }

  void _pressMetronome(MetronomeElement e, MetronomePart part) {
    controller.selectAlone(e.id);
    switch (part) {
      case MetronomePart.play:
        controller.toggleMetronome(e);
      case MetronomePart.slower:
        controller.metronomeStep(e, _shiftHeld ? -1.0 : -4.0);
      case MetronomePart.faster:
        controller.metronomeStep(e, _shiftHeld ? 1.0 : 4.0);
      case MetronomePart.tap:
        controller.tapMetronome(e);
      case MetronomePart.beats:
        controller.cycleMetronomeBeats(e);
    }
  }

  /// _pressCounter runs a counter's button. Set is typed on the button here,
  /// as the controller has no window.
  void _pressCounter(CounterElement e, int at) {
    if (at < 0 || at >= e.buttons.length) return;
    var button = e.buttons[at];
    if (controller.pressCounterButton(e, button)) return;
    setState(() {
      _editing = CounterSet(e.id, at: at);
    });
  }

  /// _counterInputFor is the field on a counter's Set button: Enter takes
  /// it; closing it otherwise changes nothing.
  Widget? _counterInputFor() {
    var setting = _editing;
    if (setting is! CounterSet) return null;
    var id = setting.elementId;
    var element = document.elementById(id);
    if (element is! CounterElement) return null;
    var on = _hit.placed(element);
    var rects = counterButtonRects(element, on.box);
    if (setting.at < 0 || setting.at >= rects.length) return null;

    var box = rects[setting.at];
    var topLeft = _toStage(box.topLeft);
    void close() {
      if (mounted) {
        // Only a Set field: its last word can come after a press has
        // opened something else (see _pressOverlays, which lets it close
        // by taking the focus).
        setState(() {
          if (_editing is CounterSet) _editing = null;
        });
      }
    }

    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      width: box.width * _scale,
      height: box.height * _scale,
      // On the button as it is drawn on this frame.
      child: Transform(
        transform: _onStage(on.place),
        origin: -topLeft,
        child: CounterInput(
          key: ValueKey("set-$id"),
          value: controller.counterValue(element),
          decimals: element.decimals,
          onDone: (typed) {
            if (typed != null) controller.setCounterValue(element, typed);
            close();
          },
        ),
      ),
    );
  }

  /// _applyCounterPiece moves [piece] of counter [id] to [doc].
  void _applyCounterPiece(String id, CounterPiece piece, Offset doc) {
    var element = document.elementById(id);
    if (element is! CounterElement) return;

    // Where the pointer is in the box as it is drawn on this frame.
    var inside = _hit.inBox(element, doc);
    if (inside == null) return;
    var (:on, :point) = inside;
    var inner = element.box.inner(on.box);
    if (inner.width <= 0 || inner.height <= 0) return;
    // A fraction of the box from its middle, so it stays put on resize.
    var at = Offset(
      ((point.dx - inner.center.dx) / inner.width).clamp(-1.0, 1.0),
      ((point.dy - inner.center.dy) / inner.height).clamp(-1.0, 1.0),
    );
    controller.replaceElement(element.withPieceAt(piece, at), transient: true);
  }

  void _toggleSeries(ChartElement e, int at) {
    var current = document.elementById(e.id);
    if (current is! ChartElement) return;
    if (at < 0 || at >= current.data.series.length) return;
    var series = [...current.data.series];
    series[at] = series[at].copyWith(hidden: !series[at].hidden);
    controller.beginInteraction();
    controller.replaceElement(
        current.copyWith(data: current.data.copyWith(series: series)));
    controller.endInteraction();
  }

  /// _holdLegend takes hold of a chart's key after a held press, to move it
  /// rather than press a switch. The key keeps its drawn place and becomes a
  /// placed label like the title, reset from the Legend settings.
  void _holdLegend(ChartElement e) {
    var current = document.elementById(e.id);
    if (current is! ChartElement || current.locked) return;
    // Where the press is in the chart's box as it is drawn on this frame.
    var inside = _hit.inBox(current, _toDocument(_pressedAt));
    if (inside == null) return;
    var (:on, :point) = inside;
    var bounds = on.box;
    if (bounds.width <= 0 || bounds.height <= 0) return;
    var block = chartLegendBlock(current, bounds);
    if (block.isEmpty) return;

    if (!current.legend.hasPlace) {
      controller.replaceElement(
          current.copyWith(
            legend: current.legend.copyWith(
              x: (block.left - bounds.left) / bounds.width,
              y: (block.top - bounds.top) / bounds.height,
            ),
          ),
          transient: true);
    }
    // The press is the key's now: the move it began, and the switch it
    // armed, give way to a drag of the key, in the move's undo step.
    _handOver(_ChartLabelDrag(ChartLabelGrab(
        ChartLabelPart.legend, point - block.topLeft,
        resizing: false)));
  }

  void _pressVideo(VideoElement e, VideoPart part, Offset doc) {
    // How far along a bar is measured along it as it is drawn.
    var inside = _hit.inBox(e, doc);
    if (inside == null) return;
    var parts = videoParts(e, inside.on.box);
    var x = inside.point.dx;
    var along = switch (part) {
      VideoPart.track => alongBar(parts.track!, x),
      VideoPart.volume => alongBar(parts.volume!, x),
      _ => 0.0,
    };
    var url = controller.pressVideo(e, part, along: along);
    // Leaving the app is for whoever put the stage up, as a button's link is.
    if (url != null && url.isNotEmpty) widget.onButtonLink?.call(url);
  }

  void _pressAudio(AudioElement e, AudioControl part, Offset doc) {
    double? volume;
    if (part == AudioControl.volume) {
      // Along the bar as it is drawn.
      if (_hit.inBox(e, doc) case (:var on, :var point)?) {
        var bar = audioParts(e, on.box).volume;
        if (bar != null) volume = volumeAt(bar, point.dx);
      }
    }
    controller.pressAudio(e, part, volume: volume);
  }

  /// _dropFlow finishes a link drag from box [fromId], let go at [stage]:
  /// onto another text box it links there; elsewhere it unlinks, so the
  /// gesture that made a chain undoes it.
  void _dropFlow(String fromId, Offset stage) {
    var from = document.elementById(fromId) as TextElement?;
    if (from == null || controller.lockJoins) return;

    var doc = _toDocument(stage);
    var onto = _hit.topmost(doc,
        where: (e) => e is TextElement && e.id != from.id) as TextElement?;

    if (onto != null && wouldLoop(from, onto.id, document)) {
      // A ring of boxes has no first box to read from: refused.
      return;
    }
    // A box shows one box's overflow, and a second's would be drawn
    // nowhere; text on a line has no box to show it in: both refused.
    var taking = onto == null ? null : flowSourceOf(onto, document);
    if (onto != null &&
        (onto.wordsSetIn(document) == WordsSet.onLine ||
            (taking != null && taking.id != from.id))) {
      return;
    }

    controller.beginInteraction();
    controller.replaceElement(from.copyWith(flowTo: onto?.id ?? ""));
    controller.endInteraction();
  }

  /// _pressPlayTask ticks a play task's step the student marks, or starts it
  /// again, if the press is on one. Answers whether it was taken.
  bool _pressPlayTask(PlayTaskElement e, Offset doc) {
    // From where it is drawn now, which its motion may have moved.
    var inside = _hit.inBox(e, doc);
    if (inside == null) return false;
    var at = inside.point - inside.on.box.topLeft;
    var show = controller.playTaskShowFor(e);
    if (playTaskAgainAt(e, at, show)) {
      controller.startPlayTaskAgain(e);
    } else if (playTaskMarkAt(e, at, show) case var i?) {
      controller.tickPlayStep(e, i);
    } else {
      return false;
    }
    _mode = _DragMode.none;
    return true;
  }
}

/// _CounterPieceDrag is one of a selected counter's loosely placed pieces
/// moved inside it. One undo step.
class _CounterPieceDrag extends StageGesture with _CarriesClicks {
  _CounterPieceDrag(this.counterId, this.piece, {this.click});

  /// counterId is the counter's.
  final String counterId;

  /// piece is which of its pieces.
  final CounterPiece piece;

  /// click is the press of the live button the piece is, if it is one:
  /// made if the press is let go where it began.
  final _CounterClick? click;

  @override
  Iterable<PendingClick> get carried => [click].nonNulls;

  @override
  bool get opensUndoStep => true;

  @override
  bool get waitsToTravel => true;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) =>
      stage._applyCounterPiece(counterId, piece, doc);
}
