part of '../canvas_controller.dart';

// Part of CanvasController: play task cards (play_task_element.dart), kept
// the height of what they say, and marked as the keys are played: each key
// pressed on an instrument on the page (on the canvas, a computer keyboard
// or MIDI) is heard by every card listening to it, and a take on the music
// counts for a card's play-along steps. How far the student has got is this
// sitting's, not the document's: a lesson opened again starts fresh.

extension CanvasPlayTasks on CanvasController {
  /// setPlayTask writes card [e], never shorter than what it says: taller
  /// where it was made so (round a metronome laid over it, say).
  void setPlayTask(PlayTaskElement e, {bool transient = false}) =>
      replaceElement(
          e.withBase(height: math.max(e.height, playTaskFitHeight(e, e.width))),
          transient: transient);

  List<PlayCheckState> _playStates(PlayTaskElement e) {
    var states = _playTasks.states[e.id] ?? const [];
    return [
      for (var i = 0; i < e.checks.length; i++)
        i < states.length ? states[i] : PlayCheckState.fresh,
    ];
  }

  /// playTaskShowFor is how the stage shows card [e]: which steps are done.
  PlayTaskShow playTaskShowFor(PlayTaskElement e) =>
      PlayTaskShow([for (var s in _playStates(e)) s.done]);

  /// tickPlayStep ticks, or unticks, step [i] of card [e]: one the student
  /// marks, as no key can show it done.
  void tickPlayStep(PlayTaskElement e, int i) {
    if (i < 0 || i >= e.checks.length) return;
    if (e.checks[i].kind != PlayCheckKind.self) return;
    var states = _playStates(e);
    states[i] = PlayCheckState(done: !states[i].done);
    _playTasks.states[e.id] = states;
    notifyListeners();
  }

  /// startPlayTaskAgain clears every tick on card [e].
  void startPlayTaskAgain(PlayTaskElement e) {
    if (_playTasks.states.remove(e.id) != null) notifyListeners();
  }

  /// _playTasksHeard is [key] pressed on instrument [inst]: each card on the
  /// page listening to it moves on, and a take being played counts for its
  /// play-along steps.
  void _playTasksHeard(AudioElement inst, int key) {
    var cards = _document.elements.whereType<PlayTaskElement>();
    if (cards.isEmpty) return;
    var held = _instruments.held[inst.id] ?? {key};
    var take = _takeScore();
    var changed = false;
    for (var e in cards) {
      if (e.instrument.isNotEmpty && e.instrument != inst.id) continue;
      var states = _playStates(e);
      for (var (i, c) in e.checks.indexed) {
        var was = states[i];
        var now = c.kind == PlayCheckKind.along
            ? (take != null &&
                    take.$1 == _alongSheet(e)?.id &&
                    take.$2 * 100 >= c.percent * take.$3 &&
                    take.$3 > 0
                ? const PlayCheckState(done: true)
                : was)
            : heardBy(c, was, key, held);
        if (!identical(now, was)) {
          states[i] = now;
          changed = changed || now.done != was.done;
        }
      }
      _playTasks.states[e.id] = states;
    }
    if (changed) notifyListeners();
  }

  /// _alongSheet is the music card [e]'s play-along steps are played on: its
  /// own, or the first on the page.
  SheetElement? _alongSheet(PlayTaskElement e) {
    var own = _document.elementById(e.sheet);
    if (own is SheetElement) return own;
    return _document.elements.whereType<SheetElement>().firstOrNull;
  }

  /// _takeScore is the take being played: its sheet, the notes right so
  /// far, and how many of the music's notes are the player's. Null with none.
  (String, int, int)? _takeScore() {
    var p = _practised;
    if (p == null) return null;
    var (sheet, _, part) = p;
    var theirs = part.notes.where((n) => CanvasController._mine(sheet, n));
    return (sheet.id, practiceScore.$1, theirs.length);
  }
}

/// _PlayTaskState is how far each card on the canvas has got, by element id:
/// a state for each of its steps.
class _PlayTaskState {
  final Map<String, List<PlayCheckState>> states = {};
}
