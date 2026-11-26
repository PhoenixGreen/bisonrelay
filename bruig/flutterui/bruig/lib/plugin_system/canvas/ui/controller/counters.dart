part of '../canvas_controller.dart';

// Counters' numbers as the controller knows them, as the stage, the
// settings and the file player read and press them. Part of
// CanvasController. The counting is CounterClock's
// (controller/counter_clock.dart), which the controller holds as _counters;
// what is here is what only the controller knows: a game's counts, and the
// canvas the counters are on.

extension CanvasCounters on CanvasController {
  /// counterTicks counts the running counters' moves, for the stage's
  /// painter to see a change: counts are not in the document.
  int get counterTicks => _counters.ticks;

  /// counterValue is what [e]'s own source says now: a clock the time of
  /// day, a game's count where the game has got it, a run wherever its own
  /// count has got to. A keyed counter and a page number take theirs from
  /// the timeline and the page (CounterElement.shownValue), so this is
  /// their start.
  double counterValue(CounterElement e) => switch (e.mode) {
        CounterMode.run => _counters.count(e),
        CounterMode.clock => _counters.secondsOfDay(),
        CounterMode.game => _gameCountOf(e),
        CounterMode.keyed || CounterMode.page => e.from,
      };

  /// _gameCountOf is where the game has got [e]'s count, else where it
  /// starts.
  double _gameCountOf(CounterElement e) {
    var count = _document.counts.where((c) => c.id == e.gameCount).firstOrNull;
    if (count == null) return e.from;
    return (_game?.countOf(_document, count.id) ?? count.start).toDouble();
  }

  /// counterRunning is whether [e] is counting now: its own `running` is
  /// where it starts. A clock is always running.
  bool counterRunning(CounterElement e) => switch (e.mode) {
        CounterMode.clock => true,
        CounterMode.run || CounterMode.game => _counters.isRunning(e.id),
        CounterMode.keyed || CounterMode.page => false,
      };

  /// startCounters starts every counter set to start running, as opening a
  /// canvas with a clock on it should, and sets going again those left
  /// running when the page was left (see leavePage).
  void startCounters() => _counters.start();

  /// pressCounterButton is what one of a counter's own buttons does. Returns
  /// true where the press was handled here; Input returns false, and the
  /// caller asks for a number (see setCounterValue).
  bool pressCounterButton(CounterElement e, CounterButton button) =>
      _counters.press(e, button);

  /// setCounterValue answers the Set button: the number to count on from.
  /// It does not start or stop anything.
  void setCounterValue(CounterElement e, double value) =>
      _counters.set(e, value);

  /// tickCounters moves every running counter on by the time that has passed:
  /// by the clock rather than a fixed step per tick, since the timer loses
  /// time whenever the window is busy.
  @visibleForTesting
  void tickCounters({DateTime? now}) => _counters.tick(now: now);
}
