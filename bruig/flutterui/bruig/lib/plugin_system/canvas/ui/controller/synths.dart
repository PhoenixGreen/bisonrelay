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
    // Watched on each speaker it reaches, for the screens.
    for (var s in synthSpeakersHearing(_document, keys.id)) {
      if (synthChannel(s)?.instrument?.patch case var patch?) {
        _synthWatches[s.id] = PatchWatch(patch, key);
      }
    }
    _synthTicking();
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
    for (var w in _synthWatches.values) {
      if (w.key == key) w.release();
    }
    keysHeld.value++;
  }

  /// _synthTicking keeps the watched notes playing on, and the stage
  /// redrawing them, about thirty times a second until they have died away.
  void _synthTicking() {
    if (_synthTick != null) return;
    _synthClock
      ..reset()
      ..start();
    _synthTick = Timer.periodic(const Duration(milliseconds: 33), (_) {
      var samples = (_synthClock.elapsedMicroseconds * mixRate / 1e6)
          .round()
          .clamp(0, mixRate ~/ 10);
      _synthClock
        ..reset()
        ..start();
      for (var w in _synthWatches.values) {
        w.advance(samples);
      }
      _synthWatches.removeWhere((_, w) => w.done);
      keysHeld.value++;
      if (_synthWatches.isEmpty) {
        _synthTick?.cancel();
        _synthTick = null;
      }
    });
  }

  /// synthShowFor is what module [e] is doing on the stage: the keys held
  /// on a keyboard, and on the rest what the note watched on a speaker it
  /// reaches is making of it -- its sound, its level, where its envelope
  /// is.
  SynthShow synthShowFor(SynthModuleElement e, int frame) {
    var seconds = frame / math.max(1, _document.frameRate);
    if (e.module == SynthModuleKind.keys) {
      return SynthShow(seconds: seconds, held: synthHeld(e.id));
    }
    for (var w in _synthWatches.values) {
      if (!w.has(e.id)) continue;
      // The speaker's own is what is heard; an amp's, what it lets out.
      var id = e.id;
      return SynthShow(
          seconds: seconds,
          held: w.released ? const {} : {w.key},
          level: w.levelOf(id),
          env: e.module == SynthModuleKind.env ? w.valueOf(id) : null,
          wave: w.waveOf(id));
    }
    return SynthShow(seconds: seconds);
  }

  /// synthHeld are the keys held on keyboard module [id].
  Set<int> synthHeld(String id) => {...?_synthPressed[id]};

  /// setSynth writes module [e] over the one with its id: a knob turned, a
  /// choice made. [transient] for each step of a drag.
  void setSynth(SynthModuleElement e, {bool transient = false}) {
    replaceElement(e, transient: transient);
    _synthLive();
  }

  /// _synthLanesLive sends each speaker whose knobs are keyed its patch as
  /// they are on this frame, as the playhead moves: a key played over the
  /// timeline hears them turn, as the part's rendered notes do.
  void _synthLanesLive() {
    for (var e in _document.elements) {
      if (e is! SynthModuleElement || e.module != SynthModuleKind.out) continue;
      var ch = synthChannel(e);
      var patch = ch?.instrument?.patch;
      if (ch == null || patch == null || patch.lanes.isEmpty) continue;
      var t = (_frame - ch.clip.at) / math.max(1, _document.frameRate);
      var now = patch.at(t);
      audio.livePatch(e.channel, now);
      _synthWatches[e.id]?.patch = now;
    }
  }

  /// _synthLive sends each speaker's patch to its channel as it is now: a
  /// note held goes on in it, its knob heard turning.
  void _synthLive() {
    for (var e in _document.elements) {
      if (e is! SynthModuleElement || e.module != SynthModuleKind.out) continue;
      if (synthChannel(e)?.instrument?.patch case var patch?) {
        audio.livePatch(e.channel, patch);
        _synthWatches[e.id]?.patch = patch;
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

  // ----------------------------------------------------------- task cards

  /// synthSpeakerFor is the speaker task card [card] is about: its own, or
  /// the first there is.
  SynthModuleElement? synthSpeakerFor(SynthTaskElement card) {
    var speakers = [
      for (var e in _document.elements)
        if (e is SynthModuleElement && e.module == SynthModuleKind.out) e
    ];
    return speakers.where((s) => s.id == card.speaker).firstOrNull ??
        speakers.firstOrNull;
  }

  /// addSynthTask puts a task card down where it covers no module: at
  /// the rack's top left (above the keyboard, where the prototype's card
  /// was), else to the left of the rack, else beside [near].
  void addSynthTask(SynthModuleElement near) {
    var card = newElement(ElementKind.synthTask, _document) as SynthTaskElement;
    var mods = _document.elements.whereType<SynthModuleElement>().toList();
    var left = mods.map((m) => m.x).reduce(math.min);
    var top = mods.map((m) => m.y).reduce(math.min);
    var gap = near.width * 0.06;
    var size = card.bounds.size;
    var place = [
      Offset(left, top),
      Offset(left - size.width - gap, top),
      Offset(near.bounds.right + gap, near.y),
    ].firstWhere(
        (o) => o.dx >= 0 && !mods.any((m) => m.bounds.overlaps(o & size)),
        orElse: () => Offset(near.bounds.right + gap, near.y));
    addElement(card.rebase(card.base.copyWith(x: place.dx, y: place.dy)));
  }

  /// setSynthTarget makes the rack as it is now [card]'s target: the patch
  /// its speaker hears, to be heard, and a check of everything that
  /// differs from the rack's start (see synthChecksFor). The card grows to
  /// show them.
  void setSynthTarget(SynthTaskElement card) {
    var speaker = synthSpeakerFor(card);
    if (speaker == null) return;
    var target = synthPatchOf(_document.elements, speaker.id);
    var next = card.copyWith(
        target: target,
        speaker: speaker.id,
        checks: synthChecksFor(target,
            _document.elements.whereType<SynthModuleElement>().toList()));
    var h = synthTaskLayout(next, null).height * synthTaskScale(card.bounds);
    replaceElement(next.rebase(next.base.copyWith(height: h)));
  }

  /// fitSynthTask is [card] grown or shrunk to what it says.
  SynthTaskElement fitSynthTask(SynthTaskElement card) =>
      card.rebase(card.base.copyWith(
          height: synthTaskLayout(card, null).height *
              synthTaskScale(card.bounds))) as SynthTaskElement;

  /// hearSynthTarget plays [card]'s target: a chord of A, C and E held a
  /// few seconds, through its speaker's channel, as the prototype's did.
  void hearSynthTarget(SynthTaskElement card) {
    var target = card.target;
    var speaker = synthSpeakerFor(card);
    var ch = speaker == null ? null : synthChannel(speaker);
    if (target == null || ch == null) return;
    var part =
        ch.instrument!.copyWith(sound: InstrumentSound.patch, patch: target);
    const keys = [57, 60, 64];
    _synthTarget?.cancel();
    for (var k in keys) {
      unawaited(audio.noteOn(ch.id, part, k, 90));
    }
    _synthTarget = Timer(const Duration(milliseconds: 2600), () {
      for (var k in keys) {
        audio.noteOff(ch.id, k);
      }
    });
  }

  /// checkSynthTask is how many of [card]'s checks the patch meets, of how
  /// many.
  (int, int) checkSynthTask(SynthTaskElement card) =>
      (card.checks.where((c) => c.met(_document)).length, card.checks.length);
}
