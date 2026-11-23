part of '../canvas_controller.dart';

// Live counters, as the stage, the settings and the file player read and
// press them. Part of CanvasController. The counting is CounterClock's
// (controller/counter_clock.dart), which the controller holds as _counters;
// what is here is what only the controller knows: a game's counts, and the
// canvas the counters are on.

extension CanvasCounters on CanvasController {
  /// counterTicks counts the running counters' moves, for the stage's
  /// painter to see a change: counts are not in the document.
  int get counterTicks => _counters.ticks;

  /// counterValue is what [e] is showing now: a clock shows the time of day,
  /// anything else wherever its own count has got to.
  double counterValue(CounterElement e) {
    if (!e.live) return e.from;
    if (e.source == CounterSource.clock) return _counters.secondsOfDay();
    // A game's count: where the game has got it, else where it starts.
    if (e.source == CounterSource.game) {
      var count =
          _document.counts.where((c) => c.id == e.gameCount).firstOrNull;
      if (count == null) return e.from;
      return (_game?.countOf(_document, count.id) ?? count.start).toDouble();
    }
    return _counters.count(e);
  }

  /// counterRunning is whether [e] is counting now: its own `running` is
  /// where it starts. A clock is always running.
  bool counterRunning(CounterElement e) =>
      e.live && (e.source == CounterSource.clock || _counters.isRunning(e.id));

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
