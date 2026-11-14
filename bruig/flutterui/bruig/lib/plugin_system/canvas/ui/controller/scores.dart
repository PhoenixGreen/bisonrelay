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
    beginInteraction();
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
    endInteraction();
  }

  /// setScore writes [score] over the one with its id, its channels made
  /// from it again.
  void setScore(MusicScore score, {bool transient = false}) =>
      apply(scoreSynced(_document, score), transient: transient);

  /// removeScore takes score [id] out; its channels keep their notes.
  void removeScore(String id) => apply(scoreRemoved(_document, id));
}
