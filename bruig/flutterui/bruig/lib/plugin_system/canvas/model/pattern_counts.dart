import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

// pattern_counts.dart counts a task card's own patterns in its code off the
// UI isolate (security review, 2026-11-17).
//
// A pattern is a regular expression the card's author wrote, run against
// code that also came with the canvas. Dart's regular expressions backtrack
// and cannot be stopped: "(a+)+$" against forty a's and a "!" runs for
// ever. Counted in the painter, as they were, a received canvas's card froze
// the app as it was drawn. Each is counted here in an isolate of its own,
// killed when it runs over [limit], and the answer kept.

/// PatternCounts is the counts worked out so far, and the ones under way.
abstract final class PatternCounts {
  /// limit is how long one count may take: far longer than any honest
  /// pattern takes over a lesson's code.
  static const limit = Duration(seconds: 1);

  /// counted ticks each time a count comes in, so what drew a card without
  /// it draws it again.
  static final counted = ValueNotifier<int>(0);

  static final _known = <(String, String), int>{};
  static final _asking = <(String, String), Future<void>>{};

  /// count is how many times [pattern] matches [text]; null while it is
  /// being counted. One that is not a pattern, or that ran over [limit],
  /// counts nothing.
  static int? count(String pattern, String text) {
    var key = (pattern, text);
    if (_known[key] case var n?) return n;
    _asking.putIfAbsent(key, () => _count(key));
    return null;
  }

  /// settled is when every count asked for has come in: for tests.
  static Future<void> settled() async {
    while (_asking.isNotEmpty) {
      await Future.wait(_asking.values.toList());
    }
  }

  static Future<void> _count((String, String) key) async {
    var port = ReceivePort();
    var answer = Completer<int>();
    port.listen((m) {
      if (!answer.isCompleted) answer.complete(m is int ? m : 0);
    });
    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(_countIn, (port.sendPort, key.$1, key.$2),
          errorsAreFatal: true, onExit: port.sendPort);
    } catch (_) {
      if (!answer.isCompleted) answer.complete(0);
    }
    var n = await answer.future.timeout(limit, onTimeout: () => 0);
    isolate?.kill(priority: Isolate.immediate);
    port.close();
    if (_known.length > 2000) _known.clear();
    _known[key] = n;
    _asking.remove(key);
    counted.value++;
  }

  static void _countIn((SendPort, String, String) job) {
    var (reply, pattern, text) = job;
    try {
      reply.send(RegExp(pattern, multiLine: true).allMatches(text).length);
    } catch (_) {
      reply.send(0);
    }
  }
}
