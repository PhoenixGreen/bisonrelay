part of 'canvas_stage.dart';

// A synth module's controls on the stage: what a press does on its keys,
// knobs, screens, options, switches and jacks, a knob turned by a drag, and
// the release that ends each, a carried cable plugged or dropped; and a synth
// task card's Hear and Check buttons. Part of CanvasStageState: its fields,
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
        _synthKey = (e, part.index);
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
        _synthKnob = (e.id, knob, knob.turn(e.value(knob.key)), doc);
        setState(() => _mode = _DragMode.synthKnob);
      case SynthPartKind.screen:
        if (e.fixed) break;
        controller.beginInteraction();
        _synthScreen = (e.id, part.port);
        setState(() => _mode = _DragMode.synthScreen);
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
        _synthCable = source is SynthModuleElement
            ? (
                from: source,
                port: plug!.port,
                out: true,
                lifted: (e, part.port),
                at: doc
              )
            : (from: e, port: part.port, out: part.out, lifted: null, at: doc);
        setState(() => _mode = _DragMode.synthCable);
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

  /// _turnSynthKnob turns the dragged knob a whole turn per 150 pixels up,
  /// four times finer with Shift.
  void _turnSynthKnob(Offset doc) {
    var (id, knob, from, start) = _synthKnob ?? (null, null, 0.0, Offset.zero);
    var e = id == null ? null : document.elementById(id);
    if (e is! SynthModuleElement || knob == null) return;
    var travel = (start.dy - doc.dy) * _scale / (_shiftHeld ? 600 : 150);
    controller.setSynth(e.withValue(knob.key, knob.at(from + travel)),
        transient: true);
  }

  /// _releaseSynth ends a press on a synth module: the key released, the
  /// knob's turn one undo step, the cable plugged into the jack it is dropped
  /// on, or, lifted and dropped on nothing, removed. True if there was one.
  /// When [cancelled] a cable is neither plugged nor removed.
  bool _releaseSynth(Offset doc, {bool cancelled = false}) {
    if (_synthKey case (var e, var key)?) {
      _synthKey = null;
      controller.synthKeyUp(e, key);
      return true;
    }
    if (_synthKnob != null || _synthScreen != null) {
      _synthKnob = null;
      _synthScreen = null;
      controller.endInteraction();
      setState(() => _mode = _DragMode.none);
      return true;
    }
    var cable = _synthCable;
    if (cable == null) return false;
    _synthCable = null;
    var onto = cancelled ? null : synthJackUnder(document.elements, doc);
    var plugged = false;
    if (onto case (var into, var port, var out)? when out != cable.out) {
      var (src, srcPort) = cable.out ? (cable.from, cable.port) : (into, port);
      var (dst, dstPort) = cable.out ? (into, port) : (cable.from, cable.port);
      if (cable.lifted case (var was, var input)?
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
    } else if (cable.lifted case (var was, var input)? when !cancelled) {
      controller.unplugSynth(
          document.elementById(was.id) as SynthModuleElement, input);
    }
    controller.endInteraction();
    setState(() => _mode = _DragMode.none);
    return true;
  }
}
