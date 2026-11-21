part of '../canvas_controller.dart';

// Part of CanvasController: the clip editor and the clip slots: what is open,
// what is picked, moving clips between slots, scales, tempo and warping.

extension CanvasClipEditing on CanvasController {
  /// clipEditing is the slot the clip editor is open on -- a channel and a
  /// row -- or null where none is, or its clip has gone. It shares the
  /// effects panel with the chain: [clipEditorShown] says which shows.
  PianoRollTarget? get clipEditing {
    var t = _clipEditing;
    if (t == null || t.row == null) return null;
    // A sound on the timeline, as a clip.
    if (t.row == timelineRow) {
      return timelineSoundOf(t.channel) == null ? null : t;
    }
    if (session.at(t.channel, t.row!) == null) return null;
    return t;
  }

  bool get clipEditorShown => _clipEditorShown && clipEditing != null;

  set clipEditorShown(bool on) {
    if (on == _clipEditorShown) return;
    _clipEditorShown = on;
    notifyListeners();
  }

  SessionClip? get editedClip {
    var t = clipEditing;
    if (t == null) return null;
    if (t.row == timelineRow) {
      var e = timelineSoundOf(t.channel);
      return e == null ? null : timelineClipOf(e);
    }
    return session.at(t.channel, t.row!);
  }

  /// openClipEditor opens the clip editor on [channel]'s slot [row], in the
  /// effects panel -- a MIDI clip's notes in the piano roll beside it.
  void openClipEditor(String channel, int row) {
    var timed = row == timelineRow ? timelineSoundOf(channel) : null;
    var clip = timed != null ? timelineClipOf(timed) : session.at(channel, row);
    if (clip == null) return;
    _clipEditing = PianoRollTarget(channel, row);
    if (clip.midi && _instrumentOf(channel) != null) {
      _pianoRoll = PianoRollTarget(channel, row);
    }
    rollSelected.clear();
    _clipCursor = 0;
    _effectsOf = channel;
    // One detail panel: the Chain on its sound, in place of whatever shared
    // its place.
    _showChain(ChainView.sound);
    _pianoRollShown = false;
    _speechShown = false;
    _pitchShown = false;
    _instrumentShown = false;
    _clipEditorShown = true;
    // First in the strip: scrolled to.
    _effectsFocus = "clip";
    _effectsFocusCount++;
    notifyListeners();
  }

  /// editClip changes the clip the editor is open on: one change to undo
  /// -- or, [transient], part of a drag that is.
  void editClip(SessionClip Function(SessionClip clip) change,
      {bool transient = false}) {
    var t = clipEditing;
    if (t == null) return;
    if (t.row == timelineRow) {
      var e = timelineSoundOf(t.channel);
      if (e == null) return;
      _setTimelineClip(e, change(timelineClipOf(e)), transient: transient);
      return;
    }
    var clip = session.at(t.channel, t.row!)!;
    apply(
        _document.copyWith(
            session: session.put(t.channel, t.row!, change(clip))),
        transient: transient);
    if (!transient) _warpSoon();
  }

  /// editSlotClip changes the clip in slot [row] of [channel] -- open in
  /// the editor or not, as the Clips card does -- as editClip does.
  void editSlotClip(
      String channel, int row, SessionClip Function(SessionClip clip) change,
      {bool transient = false}) {
    var clip = session.at(channel, row);
    if (clip == null) return;
    apply(_document.copyWith(session: session.put(channel, row, change(clip))),
        transient: transient);
    if (!transient) _warpSoon();
  }

  /// previewClip plays the open clip now -- not on the next bar -- to hear
  /// it while it is edited: with the transport stopped, on its own, the
  /// timeline silent (see sessionOnly). Pressed while it plays, it stops.
  void previewClip() {
    var t = clipEditing;
    var clip = editedClip;
    if (t == null || clip == null) return;
    // A sound on the timeline plays there: from where it starts.
    if (t.row == timelineRow) {
      if (playing) {
        pause();
        return;
      }
      if (timelineSoundOf(t.channel) case var e?) {
        frame = e.clip.at.clamp(0, math.max(0, _document.frames - 1));
      }
      play();
      return;
    }
    var state = clipState(t.channel, t.row!);
    if (state == ClipState.playing || state == ClipState.queued) {
      var ch = _clipChannels[t.channel];
      if (ch != null) {
        _cancelNext(ch);
        _stopChannelAt(t.channel, _sessionNow);
      }
      notifyListeners();
      return;
    }
    var at = playing ? _sessionNow : _sessionStart();
    unawaited(_startClip(t.channel, t.row!, clip, at));
  }

  /// clipPreviewing is whether the open clip plays, so Play shows Stop.
  bool get clipPreviewing {
    var t = clipEditing;
    if (t == null) return false;
    if (t.row == timelineRow) return playing;
    var state = clipState(t.channel, t.row!);
    return state == ClipState.playing || state == ClipState.queued;
  }

  /// selectedSlot is the clip slot last clicked: picked out in the mixer,
  /// and shown in the clip editor where that is open, as Ableton's is.
  (String, int)? get selectedSlot => _selectedSlot;

  void selectSlot(String channel, int row) {
    _selectedSlot = (channel, row);
    if (_clipEditorShown && session.at(channel, row) != null) {
      openClipEditor(channel, row);
      return;
    }
    notifyListeners();
  }

  /// canMoveClip is whether [channel]'s slots can take clip [clip]: a MIDI
  /// clip on a MIDI channel, a sound on an audio one.
  bool canMoveClip(SessionClip clip, String channel) =>
      clip.midi == instrumentChannel(channel);

  /// moveClip moves the clip in [fromChannel]'s slot [fromRow] to
  /// [toChannel]'s [toRow], replacing it, or copies it with [copy]. One undo.
  void moveClip(String fromChannel, int fromRow, String toChannel, int toRow,
      {bool copy = false}) {
    var clip = session.at(fromChannel, fromRow);
    if (clip == null || !canMoveClip(clip, toChannel)) return;
    if (fromChannel == toChannel && fromRow == toRow) return;
    var moved = copy ? clip.copyWith(id: newElementId()) : clip;
    // A clip playing from either slot stops: it is somewhere else now.
    for (var (ch, row) in [(fromChannel, fromRow), (toChannel, toRow)]) {
      var playing = _clipChannels[ch];
      if (playing != null &&
          (playing.now?.row == row || playing.next?.row == row) &&
          !(copy && ch == fromChannel && row == fromRow)) {
        _stopChannelAt(ch, _sessionNow);
      }
    }
    var grid = session.put(toChannel, toRow, moved);
    if (!copy) grid = grid.put(fromChannel, fromRow, null);
    apply(_document.copyWith(session: grid));
    // The editor follows the clip it was showing.
    if (!copy &&
        _clipEditing?.channel == fromChannel &&
        _clipEditing?.row == fromRow) {
      _clipEditing = PianoRollTarget(toChannel, toRow);
      if (moved.midi) _pianoRoll = PianoRollTarget(toChannel, toRow);
    }
    _selectedSlot = (toChannel, toRow);
    notifyListeners();
  }

  /// _editClipById changes clip [id], wherever it is now: for a change
  /// that took a while -- a sound reversed, cropped, its tempo heard --
  /// while the editor may have moved on to another clip.
  void _editClipById(String id, SessionClip Function(SessionClip clip) change) {
    if (session.find(id) case (var channel, var row)?) {
      setSessionClip(channel, row, change(session.at(channel, row)!));
      _warpSoon();
      return;
    }
    // A sound on the timeline, as a clip.
    if (_timelineOwner(id) case var e?) {
      _setTimelineClip(e, change(timelineClipOf(e)));
    }
  }

  /// scaleOf is the scale [channel] is in: its Scale effect's, or C major.
  (int, List<int>) scaleOf(String channel) {
    var scale = _instrumentOf(channel)
        ?.instrument
        ?.effects
        .where((m) => m.on && m.kind == MidiEffectKind.scale)
        .firstOrNull;
    if (scale == null) return (0, scaleSteps[0]);
    return (
      scale.choice("root"),
      scaleSteps[scale.choice("scale").clamp(0, scaleSteps.length - 1)]
    );
  }

  /// useNoteTool uses [tool] on the open MIDI clip's picked notes, or all,
  /// stepping [grid] beats (the piano roll's grid; a sixteenth otherwise).
  void useNoteTool(NoteTool tool, {double grid = 0.25}) {
    var t = clipEditing;
    var clip = editedClip;
    // A part's notes, in its piano roll.
    var roll = pianoRoll;
    if (pianoRollShown && roll != null && roll.row == null) {
      var content = rollContent!;
      setRollContent(
          notes: applyNoteTool(tool, content.notes, rollSelected,
              scale: scaleOf(roll.channel),
              grid: grid,
              loopEnd: content.beats,
              seed: _noteToolPresses++));
      return;
    }
    if (t == null || clip == null || !clip.midi) return;
    var bpb = _document.audio.beatsPerBar;
    var notes = applyNoteTool(tool, clip.notes, rollSelected,
        scale: scaleOf(t.channel),
        grid: grid,
        loopEnd: clip.loopEnd(bpb),
        seed: _noteToolPresses++);
    editClip((c) => c.copyWith(notes: notes));
  }

  /// _keepSound stores WAV bytes [wav] as a library sound: its id, or null.
  Future<String?> _keepSound(Uint8List wav) async {
    var dir = await Directory.systemTemp.createTemp("canvas-clip");
    try {
      var file = File(path.join(dir.path, "clip.wav"));
      await file.writeAsBytes(wav, flush: true);
      return await CanvasController.speechStore(file.path);
    } finally {
      await dir.delete(recursive: true).catchError((_) => dir);
    }
  }

  /// reverseClip plays the open audio clip backwards from a reversed copy
  /// kept beside the original, so pressed again it is undone. Says why not.
  Future<String?> reverseClip() async {
    var clip = editedClip;
    var sound = clip?.sound;
    if (clip == null || clip.midi || sound == null) return null;
    if (clip.reversedOf case var original?) {
      _editClipById(
          clip.id,
          (c) => _markersMirrored(
              c.copyWith(sound: original, clearReversed: true),
              _spanOf(original)));
      return null;
    }
    var audio = await CanvasController.clipAudio(sound.assetId);
    if (audio == null) return "Its sound could not be read.";
    var (l, r) = audio;
    var n = l.length;
    // Reversed and written out off the UI isolate, as it was read.
    var id = await _keepSound(await _reversedWavAway(l, r));
    if (id == null || _disposed) return "The reversed sound could not be kept.";
    var length = n / mixRate;
    var end = sound.end > 0 ? sound.end : length;
    var reversed = MediaSource(
        assetId: id,
        name: "${sound.name.isEmpty ? "Clip" : sound.name} (reversed)",
        start: math.max(0, length - end),
        end: math.max(0, length - sound.start),
        length: length);
    _editClipById(
        clip.id,
        (c) => _markersMirrored(
            c.copyWith(sound: reversed, reversedOf: sound), end - sound.start));
    return null;
  }

  /// _spanOf is how long [sound] plays, in seconds.
  double _spanOf(MediaSource sound) => sound.end > 0
      ? sound.end - sound.start
      : math.max(0, sound.length - sound.start);

  /// _markersMirrored is [clip] with its warp markers reversed with its
  /// sound ([seconds] of it played): a moment from its start becomes that
  /// moment from its end. Its end is pinned where its start was, since past
  /// the last marker a sound goes at its tempo: reversed twice, it matches.
  SessionClip _markersMirrored(SessionClip clip, double seconds) {
    if (clip.markers.isEmpty || seconds <= 0) return clip;
    var last = clip.warpMap.beatAt(seconds);
    return clip.copyWith(markers: [
      for (var m in clip.markers)
        if (m.seconds > 0 && m.seconds < seconds - 1e-6)
          (seconds: seconds - m.seconds, beat: last - m.beat),
      (seconds: seconds, beat: last),
    ]);
  }

  /// _cutsOf is where [clip] is cut into slices [by], in seconds into its
  /// file, its start and its loop's end included -- or why it cannot be.
  Future<(List<double>, String?)> _cutsOf(SessionClip clip, SliceBy by) async {
    var sound = clip.sound;
    if (sound == null) return (const <double>[], "It has no sound.");
    var bpb = _document.audio.beatsPerBar;
    var spb = math.max(0.001, _document.audio.secondsPerBeat);
    var speed = math.pow(2, (clip.pitch + clip.cents / 100) / 12).toDouble();
    // Where in the file each beat of it is.
    double sourceOf(double beat) => clip.warp
        ? sound.start + clip.warpMap.sourceAt(beat)
        : sound.start + beat * spb * speed;
    var from = clip.start, to = clip.loopEnd(bpb);
    if (to <= from) return (const <double>[], "It plays nothing.");
    switch (by) {
      case SliceBy.hits:
        var audio = await CanvasController.clipAudio(sound.assetId);
        if (audio == null) {
          return (const <double>[], "Its sound could not be read.");
        }
        var (l, r) = audio;
        var hits = await Isolate.run(() => onsets(l, r));
        var a = sourceOf(from), b = sourceOf(to);
        // No slice shorter than 50ms: a hit read a little late, at its
        // very start, would otherwise leave a sliver.
        const least = 0.05;
        var cuts = [a];
        for (var h in hits) {
          if (h - cuts.last >= least && h <= b - least) cuts.add(h);
        }
        cuts.add(b);
        return (cuts, null);
      case SliceBy.sixteenth || SliceBy.eighth || SliceBy.beat || SliceBy.bar:
        var step = switch (by) {
          SliceBy.bar => bpb.toDouble(),
          SliceBy.beat => 1.0,
          SliceBy.eighth => 0.5,
          _ => 0.25,
        };
        return (
          [
            for (var b = from; b < to - 1e-6; b += step) sourceOf(b),
            sourceOf(to),
          ],
          null
        );
    }
  }

  /// normaliseClip sets the open audio clip's gain so its loudest moment,
  /// of what it plays, reaches 0 dB. Says what it did.
  Future<String?> normaliseClip() async {
    var clip = editedClip;
    var sound = clip?.sound;
    if (clip == null || clip.midi || sound == null) return null;
    var audio = await CanvasController.clipAudio(sound.assetId);
    if (audio == null) return "Its sound could not be read.";
    var (l, r) = audio;
    var a = (sound.start * mixRate).round().clamp(0, l.length);
    var end = sound.end > 0 ? sound.end : l.length / mixRate;
    var b = (end * mixRate).round().clamp(a, l.length);
    var peak = 0.0;
    for (var i = a; i < b; i++) {
      peak = math.max(peak, math.max(l[i].abs(), r[i].abs()));
    }
    if (peak <= 1e-6) return "It is silent.";
    var gain = (-20 * math.log(peak) / math.ln10 * 10).round() / 10;
    _editClipById(clip.id, (x) => x.copyWith(gain: gain));
    return "Normalised: ${gain >= 0 ? "+" : ""}${gain.toStringAsFixed(1)} dB "
        "to reach 0 dB";
  }

  /// sliceToInstrument cuts the open audio clip at its hits into a new MIDI
  /// channel that plays them: with [pads], each slice on a drum pad, struck
  /// to its end; else each on a key from C2, with a note clip in its first
  /// slot playing them where they were. One undo step. Says what it did.
  Future<String?> sliceToInstrument({required bool pads}) async {
    var t = clipEditing;
    var clip = editedClip;
    var sound = clip?.sound;
    if (t == null || clip == null || clip.midi || sound == null) return null;
    var (cuts, why) = await _cutsOf(clip, SliceBy.hits);
    if (why != null) return why;
    if (cuts.length < 3) return "There is only one slice there.";
    // A pad a slice, the bottom row first, as a drum kit is played.
    var padKeys = [
      for (var row = drumPads.length ~/ 4 - 1; row >= 0; row--)
        for (var k = 0; k < 4; k++) drumPads[row * 4 + k].$1,
    ];
    var count = math.min(cuts.length - 1, pads ? padKeys.length : 128 - 36);
    var keys = pads
        ? padKeys.take(count).toList()
        : [for (var i = 0; i < count; i++) 36 + i];
    var kit = SliceKit(sound.assetId, cuts.take(count + 1).toList(), keys,
        oneShot: pads);
    var name = clip.name.isEmpty ? "Clip" : clip.name;
    var made = newInstrument(_document);
    var octaves = math.max(1, (count / 12).ceil());
    made = made
        .copyWith(
            instrument: InstrumentPart(
                look: pads ? InstrumentLook.drums : InstrumentLook.keyboard,
                sound: InstrumentSound.slices,
                slices: kit,
                lowKey: 36,
                keys: (12 * octaves + 1).clamp(13, 88)))
        .rebase(made.base.copyWith(
            name: "$name ${pads ? "pads" : "slices"}",
            visible: false)) as AudioElement;
    beginInteraction();
    addElement(made, select: false);
    if (!pads) {
      // Where each slice falls in the clip, in beats from its start.
      var bpb = _document.audio.beatsPerBar;
      var spb = math.max(0.001, _document.audio.secondsPerBeat);
      var speed = math.pow(2, (clip.pitch + clip.cents / 100) / 12).toDouble();
      double beatOf(double seconds) => clip.warp
          ? clip.warpMap.beatAt(seconds - sound.start)
          : (seconds - sound.start) / speed / spb;
      var notes = [
        for (var i = 0; i < count; i++)
          MidiNote(keys[i], math.max(0.0, beatOf(cuts[i]) - clip.start),
              math.max(1 / 64, beatOf(cuts[i + 1]) - beatOf(cuts[i])), 100),
      ];
      var channel = CanvasController._channelOf(made);
      setSessionClip(
          channel,
          0,
          SessionClip(
            id: newElementId(),
            name: "$name slices",
            color: clip.color,
            midi: true,
            notes: notes,
            bars: math.max(1 / bpb, (clip.loopEnd(bpb) - clip.start) / bpb),
          ));
    }
    endInteraction();
    return pads
        ? "Put $count slices on drum pads, on the channel “${made.name}”"
        : "Made a note clip of $count slices, on the channel “${made.name}”";
  }

  /// sliceClip cuts the open audio clip into slices -- at its hits, or each
  /// beat or bar -- each a clip in the channel's empty slots under it,
  /// playing that stretch: one undo step. Why not, or null.
  Future<String?> sliceClip(SliceBy by) async {
    var t = clipEditing;
    var clip = editedClip;
    if (t == null || clip == null || clip.midi) return null;
    var sound = clip.sound;
    if (sound == null) return null;
    var bpb = _document.audio.beatsPerBar;
    var spb = math.max(0.001, _document.audio.secondsPerBeat);
    var speed = math.pow(2, (clip.pitch + clip.cents / 100) / 12).toDouble();
    var (cuts, why) = await _cutsOf(clip, by);
    if (why != null) return why;
    if (cuts.length < 3) return "There is only one slice there.";
    var slices = <SessionClip>[];
    for (var i = 0; i + 1 < cuts.length; i++) {
      var a = cuts[i], b = cuts[i + 1];
      // At its own speed, its length in the song's bars.
      var bars = (b - a) / speed / spb / bpb;
      slices.add(SessionClip(
        id: newElementId(),
        name: "${clip.name.isEmpty ? "Slice" : clip.name} ${i + 1}",
        color: clip.color,
        sound: sound.copyWith(start: a, end: b),
        bars: bars,
        loop: false,
        launch: clip.launch,
        gain: clip.gain,
        pitch: clip.pitch,
        cents: clip.cents,
        // No click where each is cut.
        fade: true,
      ));
    }
    // Each in the next empty slot under it.
    var grid = session;
    var row = t.row!;
    for (var s in slices) {
      do {
        row++;
      } while (grid.at(t.channel, row) != null);
      grid = grid.put(t.channel, row, s);
    }
    apply(_document.copyWith(session: grid));
    return null;
  }

  /// cropClip keeps only what the open clip plays -- from its start, or its
  /// loop's start where that is earlier, to its loop's end -- as a new file
  /// for an audio clip, or the notes there for a MIDI one, and moves its
  /// start and loop to match. Answers why not.
  Future<String?> cropClip() async {
    var clip = editedClip;
    if (clip == null) return null;
    var bpb = _document.audio.beatsPerBar;
    var spb = math.max(0.001, _document.audio.secondsPerBeat);
    var from = clip.loop ? math.min(clip.start, clip.loopStart) : clip.start;
    var to = clip.loopEnd(bpb);
    if (to <= from) return null;
    SessionClip moved(SessionClip c) =>
        c.copyWith(start: c.start - from, loopStart: c.loopStart - from);
    if (clip.midi) {
      _editClipById(
          clip.id,
          (c) => moved(c).copyWith(notes: [
                for (var n in c.notes)
                  if (n.end > from && n.start < to)
                    n.copyWith(
                        start: math.max(0, n.start - from),
                        length: math.min(n.end, to) - math.max(n.start, from)),
              ]));
      return null;
    }
    var sound = clip.sound;
    if (sound == null) return null;
    var audio = await CanvasController.clipAudio(sound.assetId);
    if (audio == null) return "Its sound could not be read.";
    var (l, r) = audio;
    // Where its beats are in its sound: by its warp map, warped; at the
    // song's tempo -- faster with its pitch -- not.
    var speed = math.pow(2, (clip.pitch + clip.cents / 100) / 12).toDouble();
    double sourceOf(double beat) =>
        clip.warp ? clip.warpMap.sourceAt(beat) : beat * spb * speed;
    var s0 = sourceOf(from), s1 = sourceOf(to);
    var a = ((sound.start + s0) * mixRate).round().clamp(0, l.length);
    var b = ((sound.start + s1) * mixRate).round().clamp(a, l.length);
    if (b - a < 1) return "There is no sound there to keep.";
    var id = await _keepSound(await _wavAway(
        Float32List.sublistView(l, a, b), Float32List.sublistView(r, a, b)));
    if (id == null || _disposed) return "The cropped sound could not be kept.";
    var cropped = MediaSource(
        assetId: id,
        name: "${sound.name.isEmpty ? "Clip" : sound.name} (cropped)",
        length: (b - a) / mixRate);
    // Its warp markers moved with it, and its end pinned where it was.
    var markers = [
      for (var m in clip.markers)
        if (m.seconds > s0 + 1e-6 && m.seconds < s1 - 1e-6)
          (seconds: m.seconds - s0, beat: m.beat - from),
      if (clip.warp && clip.markers.isNotEmpty)
        (seconds: s1 - s0, beat: to - from),
    ];
    _editClipById(
        clip.id,
        (c) => moved(c)
            .copyWith(sound: cropped, clearReversed: true, markers: markers));
    return null;
  }

  /// _playedSound is what audio [clip] plays: its own sound, or -- warped,
  /// or moved in pitch -- that rendered at the song's tempo, made now where
  /// it has not been. See warp.dart.
  Future<MediaSource?> _playedSound(SessionClip clip) async {
    if (!clip.needsRender || clip.sound == null) return clip.sound;
    var spb = _document.audio.secondsPerBeat;
    var signature = clip.warpSignature(spb);
    // Rendered already -- and still there: a file the library swept away
    // is rendered again, not played as silence.
    if (clip.warpedFor == signature && clip.warped != null) {
      if (await CanvasMedia.existingPath(
              MediaKind.audio, clip.warped!.assetId) !=
          null) {
        return clip.warped;
      }
    }
    return _warpingNow[signature] ??= _warp(clip, signature).whenComplete(() {
      _warpingNow.remove(signature);
    });
  }

  Future<MediaSource?> _warp(SessionClip clip, String signature) async {
    var sound = clip.sound!;
    warping.add(clip.id);
    notifyListeners();
    try {
      var audio = await CanvasController.clipAudio(sound.assetId);
      if (audio == null || _disposed) return null;
      var (l, r) = audio;
      var length = l.length / mixRate;
      var from = sound.start, to = sound.end > 0 ? sound.end : length;
      var spb = _document.audio.secondsPerBeat;
      var map = clip.warpMap;
      var (warp, mode) = (clip.warp, clip.warpMode);
      var semitones = clip.pitch + clip.cents / 100;
      // Faded where it is played from and round: as _startClip has them.
      var loopAt = clip.loopStart * spb;
      // Each edge as long as its own fade, or Fade's few milliseconds (as
      // warp.dart's declick has them).
      const declick = 0.004;
      var inFor = clip.fadeIn > 0 ? clip.fadeIn : (clip.fade ? declick : 0.0);
      var outFor =
          clip.fadeOut > 0 ? clip.fadeOut : (clip.fade ? declick : 0.0);
      var fades = inFor > 0 || outFor > 0
          ? (
              ins: [
                if (inFor > 0) ...[
                  (clip.start * spb, inFor),
                  if (clip.loop) (loopAt, inFor),
                ],
              ],
              outs: [
                if (outFor > 0)
                  (loopAt + math.max(0.05, clip.bars * _barSeconds), outFor),
              ],
              curve: clip.fadeCurve,
            )
          : null;
      var (wav, frames) = await _warpedWavAway(l, r, from, to, warp, mode, map,
          spb, semitones, clip.envelopes, fades);
      var id = await CanvasController.partStore(wav);
      if (id == null || _disposed) return null;
      var warped = MediaSource(
          assetId: id,
          name: "${sound.name.isEmpty ? "Clip" : sound.name} (warped)",
          length: frames / mixRate);
      // Written onto the clip as it now is, if still there and still wanting
      // this: not an undo step of its own, as the file follows the clip.
      if (session.find(clip.id) case (var ch, var row)?) {
        var now = session.at(ch, row)!;
        // (A timeline sound's clip is written by renderTimelineClip.)
        if (now.warpSignature(spb) == signature) {
          apply(
              _document.copyWith(
                  session: session.put(ch, row,
                      now.copyWith(warped: warped, warpedFor: signature))),
              transient: true);
        }
      }
      return warped;
    } catch (exception) {
      debugPrint("Unable to warp the clip: $exception");
      return null;
    } finally {
      warping.remove(clip.id);
      if (!_disposed) notifyListeners();
    }
  }

  /// _warpSoon warps every clip that needs it, a moment after the last
  /// change -- so a clip is ready before it is launched.
  void _warpSoon() {
    _warpTimer?.cancel();
    _warpTimer = Timer(const Duration(milliseconds: 400), () async {
      for (var (_, _, clip) in session.clips) {
        if (_disposed) return;
        if (clip.needsRender) await _playedSound(clip);
      }
    });
  }

  /// setWarp switches the open audio clip's warping on or off. On for the
  /// first time, its tempo is heard first -- see estimateTempo.
  Future<String?> setWarp(bool on) async {
    var clip = editedClip;
    var sound = clip?.sound;
    if (clip == null || clip.midi || sound == null) return null;
    var bpm = clip.bpm;
    if (on && bpm == 0) {
      var audio = await CanvasController.clipAudio(sound.assetId);
      if (audio == null) return "Its sound could not be read.";
      var (l, r) = audio;
      var from = (sound.start * mixRate).round().clamp(0, l.length);
      var to = sound.end > 0
          ? (sound.end * mixRate).round().clamp(from, l.length)
          : l.length;
      var near = _document.audio.tempo;
      var bpb = _document.audio.beatsPerBar;
      var sl = Float32List.sublistView(l, from, to);
      var sr = Float32List.sublistView(r, from, to);
      bpm = await _tempoAway(sl, sr, near, bpb);
      if (_disposed) return null;
    }
    _editClipById(clip.id, (c) => c.copyWith(warp: on, bpm: bpm));
    return null;
  }
}
