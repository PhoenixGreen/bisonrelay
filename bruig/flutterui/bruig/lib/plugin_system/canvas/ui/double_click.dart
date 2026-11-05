import 'package:clock/clock.dart';

// double_click.dart is the second click of a pair, counted by hand. Flutter's
// double-tap recognizer cannot be used: in the gesture arena it holds back
// every other press in the row (choosing a scene, opening its menu) until its
// window passes. These rows want every press at once, and a rename only when
// a second one follows.

/// DoubleClick remembers the last press and says whether the next one is the
/// second of a pair.
class DoubleClick {
  /// window is how long a pair may take, a little under the system's half
  /// second. Counted on package:clock's clock, which a widget test's own
  /// time drives: two taps a test makes back to back are a pair however
  /// busy the machine, and a pump of [window] sets them apart.
  static const Duration window = Duration(milliseconds: 400);

  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  /// _on is what was pressed last, so two single clicks on two different
  /// rows are not read as a double click on the second.
  Object? _on;

  /// isSecond is whether this press completes a pair on [what]. True also
  /// clears the count, so three clicks are a pair and a single.
  bool isSecond(Object what) {
    var now = clock.now();
    var second = _on == what && now.difference(_last) < window;
    _last = now;
    _on = second ? null : what;
    return second;
  }
}
