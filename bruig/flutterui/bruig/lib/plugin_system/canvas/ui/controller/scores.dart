part of '../canvas_controller.dart';

// Part of CanvasController: the document's scores (see music_score.dart),
// each part playing on an instrument channel of its own whose notes are
// made from the score at every edit (see score_channels.dart).

extension CanvasScores on CanvasController {
  MusicScore? scoreById(String id) =>
      _document.scores.where((s) => s.id == id).firstOrNull;

  /// addScore puts [score] in the document, a hidden instrument channel
  /// made for each part that has none -- its sound the part's instrument's
  /// -- and every channel's notes made from it. One change to undo.
  void addScore(MusicScore score) {
    // Inside a gesture already (a drag, newScoreFor), part of its one step.
    var mine = _interaction == null;
    if (mine) beginInteraction();
    var parts = <ScorePart>[];
    for (var p in score.parts) {
      if (_document.elementById(p.channel) is AudioElement) {
        parts.add(p);
        continue;
      }
      var made = newInstrument(_document);
      var inst = p.kind;
      made = made
              .copyWith(
                  instrument: made.instrument!.copyWith(
                      look: inst.look, bank: inst.bank, program: inst.program))
              .rebase(made.base.copyWith(name: p.name, visible: false))
          as AudioElement;
      addElement(made, select: false);
      parts.add(p.copyWith(channel: made.id));
    }
    apply(scoreSynced(_document, score.copyWith(parts: parts)));
    if (mine) endInteraction();
  }

  /// setScore writes [score] over the one with its id, its channels made
  /// from it again.
  /// A part new to it (an instrument added) gets its channel as addScore
  /// gives one.
  void setScore(MusicScore score, {bool transient = false}) {
    if (score.parts
        .any((p) => _document.elementById(p.channel) is! AudioElement)) {
      addScore(score);
      return;
    }
    apply(scoreSynced(_document, score), transient: transient);
  }

  /// openScoreStudio gives the page to the Score Studio, on score [id].
  void openScoreStudio(String id) {
    if (playing) pause();
    scoreStudio.value = id;
  }

  void closeScoreStudio() {
    if (playing) pause();
    scoreStudio.value = null;
  }

  /// scoreChannel is the channel part [part] of score [score] plays on.
  AudioElement? scoreChannel(String score, String part) {
    var e =
        _document.elementById(scoreById(score)?.partById(part)?.channel ?? "");
    return e is AudioElement && e.instrument != null ? e : null;
  }

  /// newScoreFor makes [sheet] show a new score: the notes of the
  /// instrument it shows written out (or [score] given), each part on a
  /// channel of its own. One change to undo. Answers the score's id.
  String newScoreFor(SheetElement sheet, {MusicScore? score}) {
    var id = "score1";
    for (var i = 1; _document.scores.any((s) => s.id == id); i++) {
      id = "score$i";
    }
    var followed = _document.elementById(sheet.follows);
    var made = score != null
        ? MusicScore.fromJson({...score.toJson(), "id": id})
        : followed is AudioElement &&
                (followed.instrument?.notes ?? const []).isNotEmpty
            ? scoreFromNotes(id, followed.instrument!.notes,
                title: sheet.title.isEmpty ? followed.name : sheet.title,
                tempo: _document.audio.tempo,
                beats: _document.audio.beatsPerBar,
                beatUnit: _document.audio.beatUnit)
            : MusicScore.blank(id,
                title: sheet.title.isEmpty ? "Untitled score" : sheet.title,
                tempo: _document.audio.tempo);
    var mine = _interaction == null;
    if (mine) beginInteraction();
    addScore(made);
    var s = scoreById(id)!;
    var p = s.parts.first;
    apply(_document.withElement(sheet.copyWith(
        follows: p.channel,
        score: id,
        part: p.id,
        title: sheet.title.isEmpty ? s.title : null,
        key: s.fifths)));
    if (mine) endInteraction();
    return id;
  }

  // ----------------------------------------------- a sheet's playhead

  /// playSheet plays [sheet]'s bars: a range of them from its first bar (if
  /// the playhead is not already in it), stopping at the end of its last
  /// (Ken, 2026-11-14: "pick a range of bars to display and playback").
  void playSheet(SheetElement sheet) {
    // Slower or faster than real time: its notes played live, at its speed
    // -- the parts' sounds are made at the speed they were written.
    _slowSheet = (sheet.tempo - 1).abs() > 1e-6 ? sheet.id : null;
    var span = sheetFrames(sheet, _document);
    var ranged = sheet.fromBar > 0 || sheet.toBar > 0;
    if (span == null || !ranged) {
      play();
      return;
    }
    if (_frame < span.$1 || _frame >= span.$2 - 1) frame = span.$1;
    play();
    _rangeEnd = span.$2;
  }

  /// setSheetSpeed plays [sheet] at [speed], a share of real time (1),
  /// to the nearest step, slower or faster for practice (Ken, 2026-11-15);
  /// playing, it goes on at the new speed from where it is.
  void setSheetSpeed(SheetElement sheet, double speed) {
    var v = ((speed / sheetSpeedStep).round() * sheetSpeedStep)
        .clamp(sheetSlowest, sheetFastest)
        .toDouble();
    var now = _document.elementById(sheet.id);
    if (now is! SheetElement || (now.tempo - v).abs() < 1e-9) return;
    var next = now.copyWith(tempo: v);
    var going = playing && (_slowSheet == sheet.id || _practice == null);
    if (going) pause();
    replaceElement(next);
    if (going) playSheet(next);
  }

  /// setSheetClick switches [sheet]'s metronome on or off.
  void setSheetClick(SheetElement sheet, bool on) {
    var now = _document.elementById(sheet.id);
    if (now is! SheetElement) return;
    replaceElement(now.copyWith(click: on));
    _syncMetronome();
  }

  /// _clicking is the sheet whose metronome sounds as the canvas plays --
  /// the one played slower or faster, or the first on the page with its
  /// click on -- with its score and the channel its part plays on.
  (SheetElement, MusicScore, AudioElement)? get _clicking {
    (SheetElement, MusicScore, AudioElement)? of(Object? e) {
      if (e is! SheetElement || !e.click || !e.visible) return null;
      var s = scoreById(e.score);
      var ch = _document.elementById(s?.partById(e.part)?.channel ?? "");
      return s != null && ch is AudioElement ? (e, s, ch) : null;
    }

    if (_slowSheet case var id?) {
      if (of(_document.elementById(id)) case var c?) return c;
    }
    for (var e in _document.elements) {
      if (of(e) case var c?) return c;
    }
    return null;
  }

  /// _slowStep plays the notes of the slowed sheet's score that start or
  /// end between frames [was] and [now], live, on their channels: every
  /// part of its score, as the timeline's sounds are quiet while it plays.
  void _slowStep(int was, int now) {
    var sheet = _document.elementById(_slowSheet ?? "");
    if (sheet is! SheetElement) return;
    var channels = <AudioElement>[
      for (var e in _document.elements)
        if (e is AudioElement &&
            e.instrument != null &&
            (sheet.score.isNotEmpty
                ? e.instrument!.score.startsWith("${sheet.score}/")
                : e.id == sheet.follows))
          e,
    ];
    if (now < was) _slowRelease();
    for (var ch in channels) {
      var key = CanvasController._channelOf(ch);
      var part = macroedPart(key, ch.instrument!);
      var held = _slowHeld.putIfAbsent(key, () => {});
      for (var n in ch.instrument!.notes) {
        var start = _noteFrame(ch, n), end = _noteEndFrame(ch, n);
        if (start >= was && start < now && held.add(n.key)) {
          unawaited(audio.noteOn(key, part, n.key, n.velocity));
        }
        if (end >= was && end < now && held.remove(n.key)) {
          audio.noteOff(key, n.key);
        }
      }
    }
  }

  /// _slowRelease lets go of every note the slowed sheet is sounding.
  void _slowRelease() {
    for (var MapEntry(:key, :value) in _slowHeld.entries) {
      for (var k in value) {
        audio.noteOff(key, k);
      }
    }
    _slowHeld.clear();
  }

  /// sheetToStart puts the playhead at the start of [sheet]'s part.
  void sheetToStart(SheetElement sheet) {
    var on = sheetOnsets(sheet, _document);
    if (on.isNotEmpty) _sheetGo(sheet, on.first, sound: false);
  }

  /// stepSheet moves the playhead to the next note start of [sheet]'s
  /// part ([by] 1) or the one before (-1), sounding what is there; while
  /// playing, play goes on from there.
  void stepSheet(SheetElement sheet, int by) {
    var on = sheetOnsets(sheet, _document);
    if (on.isEmpty) return;
    var now = _frame;
    var to = by > 0
        ? on.where((f) => f > now).firstOrNull ?? on.last
        : on.lastWhere((f) => f < now, orElse: () => on.first);
    _sheetGo(sheet, to);
  }

  /// sheetPressed is a press at [point] (canvas space) on [sheet] drawn in
  /// [bounds]: the playhead goes to the nearest note start there, in the
  /// time round nearest where it is now. Answers whether it went.
  bool sheetPressed(SheetElement sheet, Rect bounds, Offset point) {
    // Its playbar: the buttons, and the track to put the playhead along.
    if (sheetBarRect(sheet, bounds) case var bar? when bar.contains(point)) {
      for (var MapEntry(key: part, value: r) in sheetBarParts(bar).entries) {
        if (!r.contains(point)) continue;
        switch (part) {
          case SheetBarPart.start:
            sheetToStart(sheet);
          case SheetBarPart.back:
            stepSheet(sheet, -1);
          case SheetBarPart.on:
            stepSheet(sheet, 1);
          case SheetBarPart.play:
            if (playing) {
              pause();
            } else {
              playSheet(sheet);
            }
          case SheetBarPart.click:
            setSheetClick(sheet, !sheet.click);
          case SheetBarPart.slower:
            setSheetSpeed(sheet, sheet.tempo - sheetSpeedStep);
          case SheetBarPart.faster:
            setSheetSpeed(sheet, sheet.tempo + sheetSpeedStep);
          case SheetBarPart.speed || SheetBarPart.reset:
            // Back to real time.
            setSheetSpeed(sheet, 1);
          case SheetBarPart.track:
            // Along its bars as they play: all of them, or its range.
            var span = sheetFrames(sheet, _document);
            if (span == null) return true;
            var f = ((point.dx - r.left) / r.width).clamp(0.0, 1.0);
            _sheetGo(sheet, span.$1 + ((span.$2 - span.$1) * f).round(),
                sound: false);
        }
        return true;
      }
      return true;
    }
    var view = sheetViewOf(sheet, bounds, _document, _frame);
    if (view == null) return false;
    var p = view.toScore(point);
    var area = view.engraved.staffAt(p);
    if (area == null) return false;
    var s = view.score;
    var at = area.timeAt(p.dx, s.barQuarters(area.bar), grid: 1 / 48);
    var order = s.playOrder();
    var rate = math.max(1, _document.frameRate);
    var clip = view.channel.clip.at;
    // Each time the bar is played, the frame of that time in it.
    var candidates = <int>[
      for (var pb in order)
        if (pb.bar == area.bar)
          clip + (s.secondsAt(order, pb.start + at) * rate - 1e-6).ceil()
    ];
    if (candidates.isEmpty) return false;
    var want = candidates
        .reduce((a, b) => (a - _frame).abs() <= (b - _frame).abs() ? a : b);
    var on = sheetOnsets(sheet, _document);
    if (on.isEmpty) return false;
    // Onto the nearest note start in that bar.
    var near =
        on.reduce((a, b) => (a - want).abs() <= (b - want).abs() ? a : b);
    _sheetGo(sheet, near);
    return true;
  }

  void _sheetGo(SheetElement sheet, int to, {bool sound = true}) {
    if (playing) {
      pause();
      frame = to;
      play();
      return;
    }
    frame = to;
    if (!sound) return;
    // What sounds there on its part's own channel.
    var e = sheetKeyboard(sheet);
    if (e == null) return;
    var keys = e.instrument!
        .sounding((to - e.clip.at) / math.max(1, _document.frameRate))
        .toList();
    // The last step's notes let go first, however soon this one comes.
    _releaseStepped();
    for (var k in keys) {
      noteOn(e, k, velocity: 90);
    }
    _stepped[this] =
        (Timer(const Duration(milliseconds: 450), _releaseStepped), e.id, keys);
  }

  void _releaseStepped() {
    var held = _stepped[this];
    if (held == null) return;
    _stepped[this] = null;
    var (timer, id, keys) = held;
    timer.cancel();
    var now = _document.elementById(id);
    if (now is AudioElement) {
      for (var k in keys) {
        noteOff(now, k);
      }
    }
  }

  /// sheetKeyboard is the channel [sheet]'s score part plays on, if it is
  /// one.
  AudioElement? sheetKeyboard(SheetElement sheet) =>
      sheet.score.isEmpty ? null : scoreChannel(sheet.score, sheet.part);

  /// setSheetLook draws [sheet]'s part's instrument as [look] -- keys, a
  /// neck, pads -- and shows it under the sheet, where it was hidden: what
  /// is chosen is seen (Ken, 2026-11-15: "you change the "Instrument"
  /// setting it doesn't work"). One change to undo.
  void setSheetLook(SheetElement sheet, InstrumentLook look) {
    var keys = sheetKeyboard(sheet);
    if (keys == null) return;
    var mine = _interaction == null;
    if (mine) beginInteraction();
    setInstrument(keys, keys.instrument!.copyWith(look: look));
    if (!keys.base.visible) showSheetKeyboard(sheet, true);
    if (mine) endInteraction();
  }

  /// showSheetKeyboard shows (or hides) the keyboard of [sheet]'s part on
  /// the canvas, under the sheet and as wide: the Instrument that follows
  /// it, lighting what is under the playhead.
  void showSheetKeyboard(SheetElement sheet, bool show) {
    var e = sheetKeyboard(sheet);
    if (e == null) return;
    var b = e.base;
    if (!show) {
      apply(_document.withElement(e.rebase(b.copyWith(visible: false))));
      return;
    }
    // Its keys: from the C at or below the part's lowest note, whole
    // octaves up past its highest.
    var notes = e.instrument!.notes;
    var part = e.instrument!;
    if (notes.isNotEmpty) {
      var lo = notes.map((n) => n.key).reduce(math.min);
      var hi = notes.map((n) => n.key).reduce(math.max);
      var low = lo - lo % 12;
      part = part.copyWith(lowKey: low, keys: ((hi - low) ~/ 12 + 1) * 12 + 1);
      e = e.copyWith(instrument: part);
    }
    var w = sheet.base.width;
    var h = w * 0.16;
    var under = sheet.base.y + sheet.base.height + w * 0.02;
    var room = _document.size.rect.bottom;
    var y = under + h <= room ? under : math.max(0.0, room - h);
    apply(_document.withElement(e.rebase(b.copyWith(
        visible: true, x: sheet.base.x, y: y, width: w, height: h))));
  }
}

/// _stepped is each controller's notes sounded by a step, and the timer
/// that lets them go.
final _stepped = Expando<(Timer, String, List<int>)>();
