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

  /// removeScore takes score [id] out; its channels keep their notes.
  void removeScore(String id) => apply(scoreRemoved(_document, id));

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
              play();
            }
          case SheetBarPart.track:
            var s = scoreById(sheet.score);
            var e = sheetKeyboard(sheet);
            if (s == null || e == null) return true;
            var total = s.secondsAt(s.playOrder(), s.lengthQuarters());
            var f = ((point.dx - r.left) / r.width).clamp(0.0, 1.0);
            _sheetGo(
                sheet,
                e.clip.at +
                    (total * f * math.max(1, _document.frameRate)).round(),
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
    var view = sheetViewOf(sheet, Rect.zero, _document, to);
    if (view == null) return;
    var e = view.channel;
    var keys = e.instrument!.sounding(view.seconds).toList();
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
