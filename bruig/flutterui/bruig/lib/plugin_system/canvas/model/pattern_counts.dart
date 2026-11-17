import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

// pattern_counts.dart counts a task card's own patterns in its code off the
// UI isolate. A pattern is a regular expression from a received canvas, run
// on code that came with it. Dart's regular expressions backtrack and cannot
// be stopped ("(a+)+$" on forty a's and a "!" runs for ever), so counting in
// the painter would freeze the app. Each runs in an isolate of its own,
// killed past [limit], and the answer kept.

/// PatternCounts is the counts worked out so far, and the ones under way.
abstract final class PatternCounts {
  /// limit is how long one count may take: far longer than any honest
  /// pattern needs.
  static const limit = Duration(seconds: 1);

  /// counted ticks each time a count comes in, so cards drawn without it
  /// redraw.
  static final counted = ValueNotifier<int>(0);

  static final _known = <(String, String), int>{};
  static final _asking = <(String, String), Future<void>>{};

  /// count is how many times [pattern] matches [text]; null while counting.
  /// An invalid pattern, or one past [limit], counts nothing.
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
    unawaited(_asking.remove(key));
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
