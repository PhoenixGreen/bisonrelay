import 'dart:async';

import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';

// counter_clock.dart is the live counters' clock: where each counter's own
// count has got to, which are counting, and the timer that moves them on.
// It knows nothing of the controller, which holds one and hands it what it
// reads (the document's counters) and what to tell (a count changed).
//
// Counts are not on the elements: writing each tick into the document would
// make a clock an unsaved change every second and flood the undo history.

/// CounterClock counts the open canvas's live counters in real time.
class CounterClock {
  /// [counters] are the counters on the canvas showing, [counterById] the
  /// counter of an id anywhere in the document (null for none); [changed]
  /// is called when a press or a typed value moves a count, and [ticked]
  /// when the timer does; [now] is the clock, the computer's unless a test
  /// stands in for it.
  CounterClock({
    required Iterable<CounterElement> Function() counters,
    required CounterElement? Function(String id) counterById,
    required void Function() changed,
    required void Function() ticked,
    DateTime Function()? now,
  })  : _counters = counters,
        _counterById = counterById,
        _changed = changed,
        _ticked = ticked,
        _now = now ?? DateTime.now;

  final Iterable<CounterElement> Function() _counters;
  final CounterElement? Function(String id) _counterById;
  final void Function() _changed;
  final void Function() _ticked;
  final DateTime Function() _now;

  /// _counts is what each live counter shows, by element id.
  final Map<String, double> _counts = {};

  /// _running is which of them are counting, and _since when each was last
  /// read, so a tick advances by the time actually passed.
  final Set<String> _running = {};
  final Map<String, DateTime> _since = {};

  Timer? _timer;

  /// ticks counts the counters' moves, for the stage's painter to see a
  /// change: counts are not in the document.
  int get ticks => _ticks;
  int _ticks = 0;

  /// count is where [e]'s own count has got to: where it starts, until it
  /// has been run or set.
  double count(CounterElement e) => _counts[e.id] ?? e.from;

  /// isRunning is whether the counter of [id] is counting now.
  bool isRunning(String id) => _running.contains(id);

  /// secondsOfDay is the reader's own clock, as a number of seconds.
  double secondsOfDay() {
    var now = _now();
    return now.hour * 3600 +
        now.minute * 60 +
        now.second +
        now.millisecond / 1000;
  }

  /// start starts every counter set to start running, as opening a canvas
  /// with a clock on it should, and sets going again those left running
  /// when the timer was stopped (see stopTimer).
  void start() {
    // From where each was, not on by the time the timer was stopped.
    var now = _now();
    for (var id in _running) {
      _since[id] = now;
    }
    if (_running.isNotEmpty) _startTimer();
    for (var e in _counters()) {
      if (e.live && e.running) run(e, true);
    }
  }

  /// press is what one of a counter's own buttons does. Returns true where
  /// the press was handled here; Input returns false, and the caller asks
  /// for a number (see set).
  bool press(CounterElement e, CounterButton button) {
    if (!e.live) return true;
    switch (button) {
      case CounterButton.startStop:
        run(e, !_running.contains(e.id));
        return true;
      case CounterButton.reset:
        set(e, e.from);
        return true;
      case CounterButton.input:
        return false;
    }
  }

  /// set is the number [e] counts on from. It does not start or stop
  /// anything.
  void set(CounterElement e, double value) {
    _counts[e.id] = value;
    _since[e.id] = _now();
    _ticks++;
    _changed();
  }

  /// run starts [e] counting, from where it was, or stops it there.
  void run(CounterElement e, bool on) {
    if (on) {
      _counts.putIfAbsent(e.id, () => e.from);
      _since[e.id] = _now();
      _running.add(e.id);
      _ticks++;
      _startTimer();
    } else {
      _running.remove(e.id);
      if (_running.isEmpty) stopTimer();
    }
    _changed();
  }

  void _startTimer() {
    if (_timer != null) return;
    // Twenty times a second, so a count to two decimal places is seen
    // changing; the cost is a repaint of a number.
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) => tick());
  }

  /// stopTimer stops the counting without stopping any counter: those
  /// running are still running, and start sets them going again from where
  /// they were. For the page left, with nothing to show them.
  void stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// tick moves every running counter on by the time that has passed: by
  /// the clock rather than a fixed step per tick, since the timer loses time
  /// whenever the window is busy.
  void tick({DateTime? now}) {
    if (_running.isEmpty) return;
    var at = now ?? _now();
    var moved = false;
    for (var id in _running.toList()) {
      var e = _counterById(id);
      if (e == null || !e.live) {
        _running.remove(id);
        continue;
      }
      var since = _since[id] ?? at;
      var seconds = at.difference(since).inMicroseconds / 1000000;
      if (seconds <= 0) continue;
      _since[id] = at;

      var value = _counts[id] ?? e.from;
      // Towards the far end, whichever way round the two ends are: the rate
      // is how fast, not which way.
      var step = e.rate.abs() * seconds * (e.span < 0 ? -1 : 1);
      value += step;

      // Stopped at the end, or back round to the start.
      var done = e.span < 0 ? value <= e.to : value >= e.to;
      if (done && e.span != 0) {
        if (e.loop) {
          var over = (value - e.to).abs();
          var span = e.span.abs();
          value = span <= 0 ? e.from : e.from + (over % span) * (e.span.sign);
        } else {
          value = e.to;
          _running.remove(id);
        }
      }
      _counts[id] = value;
      moved = true;
    }
    if (_running.isEmpty) stopTimer();
    if (moved) {
      _ticks++;
      _ticked();
    }
  }

  /// forget lets go of every count, for another canvas: they are by its
  /// elements' ids.
  void forget() {
    _counts.clear();
    _running.clear();
    _since.clear();
    stopTimer();
  }

  /// dispose stops the timer for good.
  void dispose() => stopTimer();
}
