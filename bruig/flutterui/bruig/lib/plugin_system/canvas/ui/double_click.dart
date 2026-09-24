import 'package:flutter/foundation.dart';

// double_click.dart is the second click of a pair, counted by hand.
//
// Flutter has a double-tap recognizer and it cannot be used for this. A
// recognizer sits in the gesture arena, and everything else in the row --
// the press that chooses a scene, the button that opens its menu -- is held
// back until its window has passed. What these rows want is the opposite:
// every ordinary press at once, and a rename only when a second one follows.

/// DoubleClick remembers the last press and says whether the next one is the
/// second of a pair.
class DoubleClick {
  /// window is how long a pair may take. The system's own is about half a
  /// second; this is a little under it.
  ///
  /// Settable so that a test does not have to race the real clock: the count
  /// is against DateTime.now(), because a fake clock says nothing about how
  /// fast somebody's fingers are, and a loaded machine can put a second of
  /// real time between two taps a test made back to back.
  @visibleForTesting
  static Duration window = const Duration(milliseconds: 400);

  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  /// _on is what was pressed last, so two single clicks on two different
  /// rows are not read as a double click on the second.
  Object? _on;

  /// isSecond is whether this press completes a pair on [what].
  ///
  /// Answering true also clears the count, so three clicks are one pair and
  /// a single, rather than two overlapping pairs.
  bool isSecond(Object what) {
    var now = DateTime.now();
    var second = _on == what && now.difference(_last) < window;
    _last = now;
    _on = second ? null : what;
    return second;
  }
}
