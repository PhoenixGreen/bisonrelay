part of 'canvas_stage.dart';

// The other elements' own controls on the stage: a metronome's buttons; a
// counter's buttons, its loose pieces dragged (_CounterPieceDrag), and the
// field on its Set button; a chart key's switches and the hold that takes
// the key instead; a video's and a speaker's controls; and a text's flow
// link dropped. Part of CanvasStageState: its fields, lifecycle and build
// are in canvas_stage.dart.

extension StageElementControls on CanvasStageState {
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
    var rects = counterButtonRects(element, _hit.posed(element));
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
      child: CounterInput(
        key: ValueKey("set-$id"),
        value: controller.counterValue(element),
        decimals: element.decimals,
        onDone: (typed) {
          if (typed != null) controller.setCounterValue(element, typed);
          close();
        },
      ),
    );
  }

  /// _applyCounterPart moves [piece] of counter [id] to [doc]: -2 its words
  /// before, -3 after, 0 and up a button.
  void _applyCounterPart(String id, int piece, Offset doc) {
    var element = document.elementById(id);
    if (element is! CounterElement) return;

    var inner = element.box.inner(_hit.posed(element));
    if (inner.width <= 0 || inner.height <= 0) return;
    // A fraction of the box from its middle, so it stays put on resize.
    var at = Offset(
      ((doc.dx - inner.center.dx) / inner.width).clamp(-1.0, 1.0),
      ((doc.dy - inner.center.dy) / inner.height).clamp(-1.0, 1.0),
    );

    controller.replaceElement(
        switch (piece) {
          -2 => element.copyWith(beforeAt: at),
          -3 => element.copyWith(afterAt: at),
          _ => element.copyWith(buttonAt: [
              for (var i = 0; i < element.buttons.length; i++)
                i == piece ? at : element.placedButton(i),
            ]),
        },
        transient: true);
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
    var bounds = _hit.posed(current);
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
    _handOver(_ChartLabelDrag(ChartLabelGrab(ChartLabelPart.legend, false,
        _toDocument(_pressedAt) - block.topLeft)));
  }

  void _pressVideo(VideoElement e, VideoPart part, Offset doc) {
    var parts = videoParts(e, _hit.posed(e));
    var along = switch (part) {
      VideoPart.track => alongBar(parts.track!, doc.dx),
      VideoPart.volume => alongBar(parts.volume!, doc.dx),
      _ => 0.0,
    };
    var url = controller.pressVideo(e, part, along: along);
    // Leaving the app is for whoever put the stage up, as a button's link is.
    if (url != null && url.isNotEmpty) widget.onButtonLink?.call(url);
  }

  void _pressAudio(AudioElement e, AudioControl part, Offset doc) {
    double? volume;
    if (part == AudioControl.volume) {
      var bar = audioParts(e, _hit.posed(e)).volume;
      if (bar != null) volume = volumeAt(bar, doc.dx);
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

    controller.beginInteraction();
    controller.replaceElement(from.copyWith(flowTo: onto?.id ?? ""));
    controller.endInteraction();
  }
}

/// _CounterPieceDrag is one of a selected counter's loosely placed pieces
/// moved inside it. One undo step.
class _CounterPieceDrag extends StageGesture with _CarriesClicks {
  _CounterPieceDrag(this.counterId, this.piece, {this.click});

  /// counterId is the counter's.
  final String counterId;

  /// piece is which: -2 the words before, -3 after, 0 and up a button.
  final int piece;

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
      stage._applyCounterPart(counterId, piece, doc);
}
