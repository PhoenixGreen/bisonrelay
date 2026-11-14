part of '../canvas_controller.dart';

// Part of CanvasController: synth modules on the canvas (see
// synth_module_element.dart) -- putting a rack down, turning a module's
// knobs, patching cables, the teacher's starting point and locks, and the
// keyboard module played on each speaker it reaches. What a speaker plays
// is kept made from the modules by apply() (see synth_channels.dart).

extension CanvasSynths on CanvasController {
  /// addSynthRack puts down the prototype's rack of modules (see
  /// synthRack), its speaker on a hidden instrument channel of its own
  /// that plays the patch. One change to undo; the speaker picked.
  void addSynthRack({Offset? center}) {
    var ch = newInstrument(_document);
    ch = ch
        .copyWith(
            instrument: ch.instrument!.copyWith(sound: InstrumentSound.patch))
        .rebase(
            ch.base.copyWith(name: "Synth", visible: false)) as AudioElement;
    var next = _document.addElement(ch);
    var rack = synthRack(next, center: center, channel: ch.id);
    for (var m in rack) {
      next = next.addElement(m);
    }
    apply(next);
    selectOnly(rack.firstWhere((m) => m.module == SynthModuleKind.out).id);
  }

  /// synthChannel is the instrument channel speaker [speaker] plays on.
  AudioElement? synthChannel(SynthModuleElement speaker) {
    var e = _document.elementById(speaker.channel);
    return e is AudioElement && e.instrument != null ? e : null;
  }

  /// _synthHearing are the channels module [id]'s keys play on: those of
  /// the speakers its cables reach.
  List<AudioElement> _synthHearing(String id) => [
        for (var s in synthSpeakersHearing(_document, id))
          if (synthChannel(s) case var ch?) ch,
      ];

  /// synthKeyDown and synthKeyUp press and let go [key] on keyboard module
  /// [keys]: played on every speaker it is patched through to.
  void synthKeyDown(SynthModuleElement keys, int key, {int velocity = 100}) {
    var on = _synthHearing(keys.id);
    _synthPressed[keys.id] = {...?_synthPressed[keys.id], key};
    for (var ch in on) {
      noteOn(ch, key, velocity: velocity);
    }
    keysHeld.value++;
  }

  void synthKeyUp(SynthModuleElement keys, int key) {
    _synthPressed[keys.id]?.remove(key);
    for (var ch in _document.elements.whereType<AudioElement>()) {
      if (ch.instrument?.sound == InstrumentSound.patch &&
          heldKeys(ch.id).contains(key)) {
        noteOff(ch, key);
      }
    }
    keysHeld.value++;
  }

  /// synthHeld are the keys held on keyboard module [id].
  Set<int> synthHeld(String id) => {...?_synthPressed[id]};

  /// setSynth writes module [e] over the one with its id: a knob turned, a
  /// choice made. [transient] for each step of a drag.
  void setSynth(SynthModuleElement e, {bool transient = false}) {
    replaceElement(e, transient: transient);
    _synthLive();
  }

  /// _synthLive sends each speaker's patch to its channel as it is now: a
  /// note held goes on in it, its knob heard turning.
  void _synthLive() {
    for (var e in _document.elements) {
      if (e is! SynthModuleElement || e.module != SynthModuleKind.out) continue;
      if (synthChannel(e)?.instrument?.patch case var patch?) {
        audio.livePatch(e.channel, patch);
      }
    }
  }

  /// plugSynth patches a cable from output [out] of module [from] into
  /// input [input] of module [into], in place of any cable there; false
  /// where the jacks don't fit (a control into a sound input).
  bool plugSynth(SynthModuleElement from, String out, SynthModuleElement into,
      String input) {
    var a = from.module.output(out), b = into.module.input(input);
    if (a == null || b == null || !synthPlugFits(a, b)) return false;
    replaceElement(into.plugged(input, (module: from.id, port: out)));
    _synthLive();
    return true;
  }

  /// unplugSynth takes the cable out of input [input] of [into].
  void unplugSynth(SynthModuleElement into, String input) {
    replaceElement(into.unplugged(input));
    _synthLive();
  }

  /// resetSynth puts [e]'s settings back to the starting point (↺).
  void resetSynth(SynthModuleElement e) => setSynth(e.reset());

  /// resetAllSynths puts every module back to the starting point, its
  /// cables too: the student's "Reset all".
  void resetAllSynths() {
    var next = _document;
    for (var e in _document.elements.whereType<SynthModuleElement>()) {
      next = next.withElement(e.reset(cables: true));
    }
    apply(next);
    _synthLive();
  }

  /// startSynthsHere makes every module as it is now the starting point:
  /// the teacher's "Set as start".
  void startSynthsHere() {
    var next = _document;
    for (var e in _document.elements.whereType<SynthModuleElement>()) {
      next = next.withElement(e.startHere());
    }
    apply(next);
  }

  /// lookAllSynths draws every module in [look].
  void lookAllSynths(SynthLook look) {
    var next = _document;
    for (var e in _document.elements.whereType<SynthModuleElement>()) {
      next = next.withElement(e.copyWith(look: look));
    }
    apply(next);
  }

  /// addSynthModule puts a module of [kind] down beside [near].
  void addSynthModule(SynthModuleKind kind, SynthModuleElement near) {
    var m = synthModule(
        _document, kind, Offset(near.bounds.right + near.width * 0.08, near.y));
    addElement(m.copyWith(look: near.look).startHere());
  }
}
