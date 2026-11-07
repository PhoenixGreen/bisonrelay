import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';

// latency_log.dart measures a key's way from the keyboard to the mix, for
// Ken's 200-300ms: when the keyboard stamped it (CoreMIDI's host time),
// when the editor had it, when it was handed to the mix, and how much sound
// was already waiting ahead of it there. Lines go to ~/bruig-latency.log,
// in debug and profile builds only, on macOS.

final bool _on = !kReleaseMode && Platform.isMacOS;

final DynamicLibrary? _lib = _on ? DynamicLibrary.process() : null;

final int Function()? _ticks = _lib
    ?.lookupFunction<Uint64 Function(), int Function()>("mach_absolute_time");

final int Function(int)? _nanos =
    _lib?.lookupFunction<Uint64 Function(Int32), int Function(int)>(
        "clock_gettime_nsec_np");

/// _nsPerTick is the host clock's nanoseconds a tick: CLOCK_UPTIME_RAW
/// (8) is mach_absolute_time in nanoseconds.
final double _nsPerTick = () {
  var t = _ticks?.call() ?? 0, n = _nanos?.call(8) ?? 0;
  return t == 0 ? 1.0 : n / t;
}();

/// hostTicks is the host clock now, as CoreMIDI stamps its packets.
int hostTicks() => _ticks?.call() ?? 0;

/// sinceMs is the milliseconds from host tick [from] to now.
double sinceMs(int from) =>
    from <= 0 ? -1 : (hostTicks() - from) * _nsPerTick / 1e6;

/// latencyLog writes [line] to the log, stamped, where it is on.
void latencyLog(String line) {
  if (!_on) return;
  try {
    var home = Platform.environment["HOME"];
    if (home == null) return;
    File("$home/bruig-latency.log").writeAsStringSync(
        "${DateTime.now().toIso8601String().substring(11, 23)} $line\n",
        mode: FileMode.append);
  } catch (_) {}
}
