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
}
