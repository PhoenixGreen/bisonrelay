part of '../canvas_controller.dart';

// Part of CanvasController: the piano roll: what it edits and shows, step
// input, its cursor and playhead.

extension CanvasPianoRoll on CanvasController {
  /// clipPlayhead is where the open clip is playing, in beats into it --
  /// what its Set buttons take -- or null where it is not playing.
  double? get clipPlayhead {
    var t = clipEditing;
    if (t == null) return null;
    // A sound on the timeline: where the playhead is over it.
    if (t.row == timelineRow) {
      var e = timelineSoundOf(t.channel);
      var clip = editedClip;
      if (e == null || clip == null || !playing) return null;
      var spb = math.max(0.001, _document.audio.secondsPerBeat);
      var beat = (frame - e.clip.at) / _document.frameRate / spb + clip.start;
      return beat < clip.start ||
              beat > clip.loopEnd(_document.audio.beatsPerBar)
          ? null
          : beat;
    }
    var ch = _clipChannels[t.channel]?.now;
    if (ch == null || ch.row != t.row) return null;
    return clipAt(t.channel);
  }

  /// pianoRoll is what the piano roll edits: a MIDI clip in a slot, or a
  /// MIDI channel's part -- or null for nothing opened yet. It shares the
  /// effects panel with the chain: [pianoRollShown] says which shows.
  PianoRollTarget? get pianoRoll {
    var t = _pianoRoll;
    if (t == null || _instrumentOf(t.channel) == null) return null;
    if (t.row case var row? when session.at(t.channel, row) == null) {
      return null;
    }
    return t;
  }

  bool get pianoRollShown => _pianoRollShown && pianoRoll != null;

  set pianoRollShown(bool on) {
    if (on == _pianoRollShown) return;
    _pianoRollShown = on;
    notifyListeners();
  }

  /// openPianoRoll opens the piano roll on MIDI channel [channel]'s part,
  /// or on its clip in slot [row], in the effects panel.
  void openPianoRoll(String channel, {int? row}) {
    // A clip's notes are in its clip editor.
    if (row != null) {
      openClipEditor(channel, row);
      return;
    }
    if (_instrumentOf(channel) == null) return;
    _pianoRoll = PianoRollTarget(channel, row);
    _effectsOf = channel;
    _effectsOpen = true;
    // One detail panel: the Chain on its sound.
    _animationOpen = false;
    _chainMotion = false;
    _pianoRollShown = true;
    _speechShown = false;
    _pitchShown = false;
    _instrumentShown = false;
    _clipEditorShown = false;
    _effectsFocus = "roll";
    _effectsFocusCount++;
    rollSelected.clear();
    notifyListeners();
  }

  /// rollContent is what the piano roll shows, in beats: notes, controller
  /// curves and length -- a clip's, or a part's to the end of the bar after
  /// its last note, never under four bars.
  RollContent? get rollContent {
    var t = pianoRoll;
    if (t == null) return null;
    var a = _document.audio;
    if (t.row case var row?) {
      // To its loop's end: a loop moved on shows where it starts from.
      var clip = session.at(t.channel, row)!;
      return RollContent(clip.notes, clip.controls, clip.loopEnd(a.beatsPerBar),
          name: clip.name.isEmpty ? "Clip" : clip.name, clip: true);
    }
    var e = _instrumentOf(t.channel)!;
    var part = e.instrument!;
    var spb = math.max(0.001, a.secondsPerBeat);
    // A part made from a score: as written, each bar once, in quarters --
    // what is drawn here is written back into the score (score_roll.dart).
    var scored = scorePartOf(_document, part);
    var notes = scored != null && !scored.$2.strum
        ? [for (var n in writtenNotes(scored.$1, scored.$2.id)) n.note]
        : [
            for (var n in part.notes)
              n.copyWith(start: n.start / spb, length: n.length / spb),
          ];
    var end = notes.isEmpty ? 0.0 : notes.map((n) => n.end).reduce(math.max);
    var bars = math.max(4, (end / a.beatsPerBar).ceil() + 1);
    return RollContent(
        notes,
        {
          for (var c in part.controls.entries)
            c.key: [for (var (t, v) in c.value) (t / spb, v)],
        },
        bars * a.beatsPerBar.toDouble(),
        name: scored != null
            ? "${e.name} part, as written in the score"
            : "${e.name} part",
        clip: false);
  }

  /// setRollContent writes what the piano roll changed: notes and curves in
  /// beats, and -- for a clip -- its length in beats.
  void setRollContent(
      {List<MidiNote>? notes,
      Map<MidiControl, List<ControlPoint>>? controls,
      double? beats,
      bool transient = false}) {
    var t = pianoRoll;
    if (t == null) return;
    var a = _document.audio;
    if (t.row case var row?) {
      var clip = session.at(t.channel, row)!;
      apply(
          _document.copyWith(
              session: session.put(
                  t.channel,
                  row,
                  clip.copyWith(
                      notes: notes,
                      controls: controls,
                      bars: beats == null
                          ? null
                          : (beats - clip.loopStart) / a.beatsPerBar))),
          transient: transient);
      return;
    }
    var e = _instrumentOf(t.channel)!;
    // A part made from a score: its notes are written into the score (as
    // notation, see score_roll.dart), and the channel made from it again.
    // A strum part's are the Studio's only.
    if (e.instrument!.fromScore) {
      var scored = scorePartOf(_document, e.instrument!);
      var drawn = notes;
      notes = null;
      if (scored != null && !scored.$2.strum && drawn != null) {
        if (controls != null) {
          setRollContent(controls: controls, transient: transient);
        }
        setScore(withRollNotes(scored.$1, scored.$2.id, drawn),
            transient: transient);
        return;
      }
    }
    var spb = math.max(0.001, a.secondsPerBeat);
    var part = e.instrument!.copyWith(
      notes: notes == null
          ? null
          : [
              for (var n in notes)
                n.copyWith(start: n.start * spb, length: n.length * spb),
            ],
      controls: controls == null
          ? null
          : {
              for (var c in controls.entries)
                c.key: [for (var (t, v) in c.value) (t * spb, v)],
            },
    );
    setInstrument(e, part, transient: transient);
  }

  /// rollStep is the piano roll's Step input: see _rollStep.
  bool get rollStep => _rollStep;

  /// setRollStep turns Step input on or off, its notes [grid] beats long.
  void setRollStep(bool on, {double? grid}) {
    _rollStep = on;
    if (grid != null) _rollStepGrid = grid;
    _stepAt = null;
    _stepHeld.clear();
    notifyListeners();
  }

  /// rollStepGrid is how long a step's notes are, and how far it moves on.
  set rollStepGrid(double beats) => _rollStepGrid = math.max(1 / 64, beats);

  /// stepNoteOn writes [key] at the step's place, if Step input is on and
  /// the piano roll shows [channel]'s notes. The first key of a chord sets
  /// the place; the rest join it.
  void stepNoteOn(String channel, int key, int velocity) {
    var t = pianoRoll;
    // The roll on screen: a part's, or a clip's in its clip editor.
    var shown = pianoRollShown || (clipEditorShown && t?.row != null);
    if (!_rollStep || !shown || t == null || t.channel != channel) return;
    var content = rollContent;
    if (content == null) return;
    var at = _stepAt ??= rollCursor;
    // A clip's notes stop at its end.
    if (t.row != null && at >= content.beats - 1e-6) return;
    _stepHeld.add(key);
    setRollContent(
        notes: [...content.notes, MidiNote(key, at, _rollStepGrid, velocity)]);
  }

  /// stepNoteOff lets [key] go: the last of a chord let go moves the
  /// cursor a step on.
  void stepNoteOff(int key) {
    if (!_stepHeld.remove(key) || _stepHeld.isNotEmpty) return;
    var at = _stepAt;
    _stepAt = null;
    if (at != null) rollCursor = at + _rollStepGrid;
  }

  /// stepRest moves Step input's cursor a step on without a note.
  void stepRest() {
    if (!_rollStep) return;
    rollCursor = rollCursor + _rollStepGrid;
  }

  /// rollCursor is where in what the piano roll shows a paste goes, in
  /// beats: for a part, the playhead's place in it -- set, it moves the
  /// playhead, and Play starts there; for a clip, a marker of its own, its
  /// loop playing on regardless.
  double get rollCursor {
    var t = pianoRoll;
    if (t == null) return 0;
    if (t.row != null) return _clipCursor;
    var e = _instrumentOf(t.channel)!;
    return _nowInPart(e) / math.max(0.001, _document.audio.secondsPerBeat);
  }

  set rollCursor(double beats) {
    var t = pianoRoll;
    if (t == null) return;
    beats = math.max(0, beats);
    if (t.row != null) {
      if (beats == _clipCursor) return;
      _clipCursor = beats;
      notifyListeners();
      return;
    }
    var e = _instrumentOf(t.channel)!;
    frame = e.clip.at +
        (beats * _document.audio.secondsPerBeat * _document.frameRate).round();
  }

  /// movePart moves the piano roll's part by [bars], never before the start.
  void movePart(int bars) {
    var t = pianoRoll;
    if (t == null || t.row != null) return;
    var e = _instrumentOf(t.channel)!;
    var a = _document.audio;
    var by =
        (bars * a.beatsPerBar * a.secondsPerBeat * _document.frameRate).round();
    setTimedClip(e, e.clip.copyWith(at: math.max(0, e.clip.at + by)));
  }

  /// rollPlayhead is where playing is in the piano roll, in beats, or null.
  double? get rollPlayhead {
    var t = pianoRoll;
    if (t == null || !playing) return null;
    if (t.row case var row?) {
      var ch = _clipChannels[t.channel];
      if (ch?.now?.row != row) return null;
      var p = clipProgress(t.channel);
      var c = rollContent;
      return p == null || c == null ? null : p * c.beats;
    }
    var e = _instrumentOf(t.channel)!;
    return _nowInPart(e) / math.max(0.001, _document.audio.secondsPerBeat);
  }

  /// pickStrip picks channel [key] -- or the master, mixerMasterKey -- from
  /// the mixer: picked on the timeline too, its chain the one the effects
  /// panel shows. One thing is picked in the mixer at a time: the strip
  /// alone, or an element's own sound with its element, the two being one
  /// thing. With the Chain out, its chain comes up.
  void pickStrip(String key) {
    // A transition's slot was pressed, in this same press: it has picked
    // itself (pickJoin), and the strip's pick -- the scene shown -- would
    // take its place.
    if (_joinPress && key == sceneBusKey) return;
    var owner = key.startsWith("snd-") ? key.substring(4) : null;
    var element = owner != null && _document.elementById(owner) != null;
    var picked = element
        ? _selection.length == 1 && _selection.first == owner
        : _selection.isEmpty;
    var chainOut = _animationOpen || _effectsOpen;
    // Pressed again -- every press on a strip picks it, a fader grab too --
    // with nothing to change, nothing is told: each press would rebuild the
    // editor. The scene's strip with the Chain on its motion opens the
    // scene's own chain (clips, transition, camera), as a click on the
    // scene on the timeline does; on its sound, its bus.
    var sceneMotion = key == sceneBusKey && _animationOpen;
    if (picked &&
        selectedChannel == key &&
        _effectsOf == key &&
        (!chainOut ||
            (sceneMotion
                ? pickedScene == _document.at
                : _effectsOpen && !_animationOpen && !_chainMotion))) {
      return;
    }
    if (!picked) element ? selectOnly(owner) : clearSelection();
    _effectsOf = key;
    selectedChannel = key;
    // Told once: by opening the chain where it is out, or here.
    if (sceneMotion) {
      pickScene(_document.at);
    } else if (chainOut) {
      openEffects(key);
    } else {
      notifyListeners();
    }
  }

  /// pickJoin picks the transition after scene [join] from its slot on the
  /// Scenes strip -- the strip, and the Chain on that transition -- on the
  /// press itself, as a slot rebuilt under the pointer may see nothing
  /// later. The strip's own pick in the same press is passed by, or it would
  /// open the scene shown in its place.
  void pickJoin(int join) {
    // Picked already in this same press: by its launch strip, then the card
    // the strip is on.
    if (_joinPress && _joinPicked && _pickedScene == join) return;
    _joinPress = true;
    scheduleMicrotask(() => _joinPress = false);
    if (_selection.isNotEmpty) clearSelection();
    _effectsOf = sceneBusKey;
    selectedChannel = sceneBusKey;
    pickScene(join);
    _joinPicked = true;
  }
}
