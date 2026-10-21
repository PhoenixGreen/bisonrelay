import 'dart:io';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/render/raster_cache.dart';
import 'package:flutter/scheduler.dart';

// canvas_perf.dart is a log of what drawing the canvas costs, for finding
// where it is slow on a real machine -- where the graphics card does work a
// test cannot time. Off unless the app is built with
// --dart-define=CANVAS_PERF_LOG=<file>, and then a line a second: frames
// drawn and how long their building and their drawing took, and how often
// the costly things happened.

/// CanvasPerf counts and times the costly parts of drawing the canvas.
class CanvasPerf {
  static const _path = String.fromEnvironment("CANVAS_PERF_LOG");

  /// on is whether the log is being kept at all.
  static bool get on => _path.isNotEmpty;

  static final Map<String, int> _counts = {};
  static final Map<String, int> _micros = {};
  static final List<ui.FrameTiming> _frames = [];
  static DateTime _since = DateTime.now();
  static bool _started = false;

  /// count notes [what] happening [n] times.
  static void count(String what, [int n = 1]) {
    if (!on) return;
    _start();
    _counts[what] = (_counts[what] ?? 0) + n;
    _flush();
  }

  /// time is [run], timed as [what].
  static T time<T>(String what, T Function() run) {
    if (!on) return run();
    var watch = Stopwatch()..start();
    try {
      return run();
    } finally {
      _micros[what] = (_micros[what] ?? 0) + watch.elapsedMicroseconds;
      count(what);
    }
  }

  static void _start() {
    if (_started) return;
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(_frames.addAll);
    File(_path).writeAsStringSync(
        "canvas perf log, started ${DateTime.now()}\n",
        mode: FileMode.append);
  }

  static void _flush() {
    var now = DateTime.now();
    if (now.difference(_since).inMilliseconds < 1000) return;
    _since = now;
    String ms(int micros) => (micros / 1000).toStringAsFixed(1);
    var builds = [for (var f in _frames) f.buildDuration.inMicroseconds];
    var rasters = [for (var f in _frames) f.rasterDuration.inMicroseconds];
    int most(List<int> v) => v.isEmpty ? 0 : v.reduce((a, b) => a > b ? a : b);
    int mean(List<int> v) =>
        v.isEmpty ? 0 : v.reduce((a, b) => a + b) ~/ v.length;
    var line = [
      now.toIso8601String().substring(11, 19),
      "frames ${_frames.length}",
      "build avg ${ms(mean(builds))} max ${ms(most(builds))}",
      "raster avg ${ms(mean(rasters))} max ${ms(most(rasters))}",
      "cache ${RasterCache.instance.bytes >> 20}MB/${RasterCache.instance.length}",
      for (var e in _counts.entries)
        _micros.containsKey(e.key)
            ? "${e.key} ${e.value}x ${ms(_micros[e.key]!)}ms"
            : "${e.key} ${e.value}x",
    ].join(" | ");
    File(_path).writeAsStringSync("$line\n", mode: FileMode.append);
    _counts.clear();
    _micros.clear();
    _frames.clear();
  }
}
