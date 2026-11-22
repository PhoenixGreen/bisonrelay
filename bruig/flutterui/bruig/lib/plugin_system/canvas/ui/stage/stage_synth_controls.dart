part of 'canvas_stage.dart';

// A synth module's controls on the stage: what a press does on its keys,
// knobs, screens, options, switches and jacks; the gestures it begins (a key
// held, a knob turned, a screen dragged, a cable carried) and what each does
// as it moves and ends, a carried cable plugged or dropped; and a synth task
// card's Hear and Check buttons. Part of CanvasStageState: its fields,
// lifecycle and build are in canvas_stage.dart.

extension StageSynthControls on CanvasStageState {
  /// _pressSynth answers a press on synth module [e]'s controls: a key
  /// sounds, a knob turns with a vertical drag (double-click: back to the
  /// teacher's start), an option is chosen, ↺ and the look switch act, and a
  /// jack starts a cable (from a used input, that cable is lifted). A locked
  /// module's knobs, options and ↺ do not change. False on the panel itself.
  bool _pressSynth(SynthModuleElement e, Offset doc) {
    var part = synthPartAt(e, doc);
    if (part == null) return false;
    controller.selectAlone(e.id);
    _mode = _DragMode.none;
    switch (part.kind) {
      case SynthPartKind.key:
        controller.synthKeyDown(e, part.index);
        _gesture = _SynthKeyHeld(e, part.index);
      case SynthPartKind.knob:
        if (e.fixed) break;
        var knob = synthKnobs[e.module]![part.index];
        var twice = clock.now().difference(_lastClickAt) <
            CanvasStageState._doubleClickWindow;
        _lastClickAt =
            twice ? DateTime.fromMillisecondsSinceEpoch(0) : clock.now();
        if (twice) {
          controller.setSynth(e.withValue(knob.key, e.startValue(knob.key)));
          break;
        }
        controller.beginInteraction();
        setState(() => _gesture = _SynthKnobTurn(
            moduleId: e.id,
            knob: knob,
            startTurn: knob.turn(e.value(knob.key)),
            pressedAt: doc));
      case SynthPartKind.screen:
        if (e.fixed) break;
        controller.beginInteraction();
        setState(() => _gesture = _SynthScreenDrag(e.id, part.port));
      case SynthPartKind.option:
        if (e.fixed) break;
        var name = synthChoiceOf(e.module)!;
        controller
            .setSynth(e.withChoice(name, synthChoices[name]![part.index]));
      case SynthPartKind.reset:
        if (!e.fixed) controller.resetSynth(e);
      case SynthPartKind.big:
        controller.bigSynth(e, !e.big);
      case SynthPartKind.look:
        controller.setSynth(e.copyWith(
            look: e.look == SynthLook.analogue
                ? SynthLook.digital
                : SynthLook.analogue));
      case SynthPartKind.jack:
        controller.beginInteraction();
        var plug = part.out ? null : e.inputs[part.port];
        var source = plug == null ? null : document.elementById(plug.module);
        setState(() => _gesture = source is SynthModuleElement
            ? _SynthCableCarry(
                from: source,
                port: plug!.port,
                out: true,
                lifted: (module: e, input: part.port),
                at: doc)
            : _SynthCableCarry(
                from: e,
                port: part.port,
                out: part.out,
                lifted: null,
                at: doc));
    }
    return true;
  }

  /// _pressSynthTask answers a task card's Hear and Check buttons.
  void _pressSynthTask(SynthTaskElement card, SynthTaskButton b) {
    controller.selectAlone(card.id);
    switch (b) {
      case SynthTaskButton.hear:
        controller.hearSynthTarget(card);
      case SynthTaskButton.check:
        if (card.checks.isEmpty) return;
        var (met, of) = controller.checkSynthTask(card);
        var snack = SnackBarModel.of(context);
        if (met == of) {
          snack.success("That's it: ${card.title.toLowerCase()}.");
        } else {
          snack.error("Not yet: ${of - met} of $of still to do. See the list.");
        }
    }
  }

  /// _turnSynthKnob turns the knob of [turn] for the pointer at [doc]: a
  /// whole turn per 150 pixels up, four times finer with Shift.
  void _turnSynthKnob(_SynthKnobTurn turn, Offset doc) {
    var e = document.elementById(turn.moduleId);
    if (e is! SynthModuleElement) return;
    var knob = turn.knob;
    var travel =
        (turn.pressedAt.dy - doc.dy) * _scale / (_shiftHeld ? 600 : 150);
    controller.setSynth(e.withValue(knob.key, knob.at(turn.startTurn + travel)),
        transient: true);
  }

  /// _dragSynthScreen drags what was [taken] of module [id]'s screen to
  /// [doc].
  void _dragSynthScreen(String id, String taken, Offset doc) {
    if (document.elementById(id) case SynthModuleElement e) {
      controller.setSynth(synthScreenDragged(e, taken, synthPanelPoint(e, doc)),
          transient: true);
    }
  }

  /// _carrySynthCable takes [cable]'s loose end to [doc].
  void _carrySynthCable(_SynthCableCarry cable, Offset doc) {
    setState(() => cable.at = doc);
  }

  /// _dropSynthCable ends [cable]: plugged into the jack it is let go on at
  /// [at], or, lifted and let go on nothing, taken out. With no [at], the
  /// press taken away, it is neither plugged nor taken out.
  void _dropSynthCable(_SynthCableCarry cable, {Offset? at}) {
    var cancelled = at == null;
    var onto = at == null ? null : synthJackUnder(document.elements, at);
    var plugged = false;
    if (onto case (var into, var port, var out)? when out != cable.out) {
      var (src, srcPort) = cable.out ? (cable.from, cable.port) : (into, port);
      var (dst, dstPort) = cable.out ? (into, port) : (cable.from, cable.port);
      if (cable.lifted case (module: var was, :var input)?
          when was.id != dst.id || input != dstPort) {
        controller.unplugSynth(
            document.elementById(was.id) as SynthModuleElement, input);
      }
      plugged = controller.plugSynth(src, srcPort,
          document.elementById(dst.id) as SynthModuleElement, dstPort);
      if (!plugged) {
        var a = (cable.out ? cable.from : into)
            .module
            .output(cable.out ? cable.port : port);
        var b = dst.module.input(dstPort);
        SnackBarModel.of(context).error(a == null || b == null
            ? "Patch from an output to an input."
            : "That doesn't fit: a ${a.signal.name} jack goes to a "
                "${a.signal.name} jack.");
      }
    } else if (cable.lifted case (module: var was, :var input)?
        when !cancelled) {
      controller.unplugSynth(
          document.elementById(was.id) as SynthModuleElement, input);
    }
    setState(() {});
  }
}

/// _SynthKeyHeld is a key of a synth keyboard module held, sounding until
/// the press ends, however it ends. Not a change: no undo step. The pointer
/// moving meanwhile is hover, as it is with nothing pressed.
class _SynthKeyHeld extends StageGesture {
  _SynthKeyHeld(this.module, this.key);

  /// module is the keyboard module, and key the key held.
  final SynthModuleElement module;
  final int key;

  @override
  bool get opensUndoStep => false;

  @override
  bool get waitsToTravel => false;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) =>
      stage._updateHover(at);

  /// endsRelease is true: letting the key go is the whole of its release.
  @override
  bool get endsRelease => true;

  @override
  void release(CanvasStageState stage, Offset at,
          {required bool travelled, required bool clicked}) =>
      stage.controller.synthKeyUp(module, key);

  @override
  void cancel(CanvasStageState stage) =>
      stage.controller.synthKeyUp(module, key);
}

/// _SynthKnobTurn is a synth module's knob turned by a drag up or down. One
/// undo step.
class _SynthKnobTurn extends StageGesture {
  _SynthKnobTurn(
      {required this.moduleId,
      required this.knob,
      required this.startTurn,
      required this.pressedAt});

  /// moduleId is the module's, and knob the knob turned.
  final String moduleId;
  final SynthKnob knob;

  /// startTurn is how far round the knob was at the press (see
  /// SynthKnob.turn).
  final double startTurn;

  /// pressedAt is where the press was, in the document.
  final Offset pressedAt;

  @override
  bool get opensUndoStep => true;

  @override
  bool get waitsToTravel => true;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) =>
      stage._turnSynthKnob(this, doc);

  /// endsRelease is true: the turn is done, and the resets that follow are
  /// for the kinds still on _DragMode.
  @override
  bool get endsRelease => true;

  /// release rebuilds the stage, which no longer draws a turn under way.
  @override
  void release(CanvasStageState stage, Offset at,
          {required bool travelled, required bool clicked}) =>
      stage.setState(() {});

  @override
  void cancel(CanvasStageState stage) => stage.setState(() {});
}

/// _SynthScreenDrag is a digital synth module's screen dragged on: an
/// envelope's corner, a filter's curve. One undo step.
class _SynthScreenDrag extends StageGesture {
  _SynthScreenDrag(this.moduleId, this.taken);

  /// moduleId is the module's, and taken what of its screen was taken (see
  /// synthScreenGrab).
  final String moduleId;
  final String taken;

  @override
  bool get opensUndoStep => true;

  @override
  bool get waitsToTravel => true;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) =>
      stage._dragSynthScreen(moduleId, taken, doc);

  /// endsRelease is true, as for a knob turned.
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

/// _SynthCableCarry is a cable carried from a synth module's jack, drawn
/// from it to the pointer (see CarriedSynthCable) until it is let go. One
/// undo step.
class _SynthCableCarry extends StageGesture {
  _SynthCableCarry(
      {required this.from,
      required this.port,
      required this.out,
      required this.lifted,
      required this.at});

  /// from is the module the cable comes from, port its jack, and out
  /// whether that jack is an output.
  final SynthModuleElement from;
  final String port;
  final bool out;

  /// lifted is the input the cable was lifted out of, when the press was on
  /// one in use: it is then carried from its other end.
  final ({SynthModuleElement module, String input})? lifted;

  /// at is the cable's loose end, the pointer, in the document.
  Offset at;

  @override
  bool get opensUndoStep => true;

  @override
  bool get waitsToTravel => true;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) =>
      stage._carrySynthCable(this, doc);

  /// endsRelease is true: plugging or dropping the cable is the whole of
  /// its release.
  @override
  bool get endsRelease => true;

  @override
  void release(CanvasStageState stage, Offset at,
          {required bool travelled, required bool clicked}) =>
      stage._dropSynthCable(this, at: stage._toDocument(at));

  @override
  void cancel(CanvasStageState stage) => stage._dropSynthCable(this);
}
