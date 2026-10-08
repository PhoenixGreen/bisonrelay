import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// tablet_input.dart is a drawing tablet's pen as the macOS runner reports it
// -- see TabletStream in macos/Runner/MainFlutterWindow.swift. Flutter's own
// pointer events on macOS carry the pen's position and its clicks but not
// its pressure, its tilt or which end of it is down, so the pencil reads
// those from here, and from Flutter's events where a platform gives them.

/// TabletInput is the pen's last reading. One for the app: there is one
/// pen, and the runner sends its readings whatever is listening.
class TabletInput {
  TabletInput._();
  static final TabletInput instance = TabletInput._();

  static const _channel = EventChannel("bruig/tablet");
  StreamSubscription<dynamic>? _listening;

  /// pressure is how hard the pen pressed, 0 to 1, at its last reading.
  double pressure = 0;

  /// tilt is how far over the pen leant, from 0 upright to a quarter turn
  /// flat; tiltX and tiltY are the tablet's own two readings of it, -1 to 1
  /// each way.
  double tiltX = 0, tiltY = 0;
  double get tilt =>
      math.min(1.0, math.sqrt(tiltX * tiltX + tiltY * tiltY)) * math.pi / 2;

  /// buttons is the pen's button mask at its last reading: 1 the tip, and
  /// 2, 4 and 8 its first, second and third button -- where the tablet
  /// passes them on at all, rather than acting on them itself.
  int buttons = 0;

  /// eraser is whether the end of the pen near the tablet is its eraser.
  bool eraser = false;

  /// near is whether the pen is near enough the tablet to be read.
  bool near = false;

  /// heard is whether any reading has come from the runner at all -- the
  /// way to tell a pen the app cannot hear from a pen not yet used.
  bool heard = false;

  /// readAt is when the last reading came, on this side -- what says
  /// whether it is about the press now being handled or one long gone.
  DateTime readAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// fresh is whether there is a reading recent enough to be the pen that
  /// is pressing now: a mouse used after the pen put down leaves the pen's
  /// last reading behind, and that is not the mouse's.
  bool get fresh =>
      DateTime.now().difference(readAt) < const Duration(milliseconds: 150);

  /// start listens to the runner, on macOS, once. Elsewhere -- and in the
  /// tests, which have no runner -- it does nothing, and the pencil goes by
  /// Flutter's own pointer events.
  void start() {
    if (!reading) return;
    if (_listening != null || kIsWeb || !Platform.isMacOS) return;
    if (Platform.environment.containsKey("FLUTTER_TEST")) return;
    _listening = _channel
        .receiveBroadcastStream()
        .listen(handle, onError: (Object e) => debugPrint("Tablet input: $e"));
  }

  /// reading is whether the runner is listened to at all. Off, it stops
  /// reading the tablet entirely -- the runner's watch on the window's events
  /// is taken down -- and the pencil goes by Flutter's own events.
  bool get reading => _reading;
  bool _reading = true;
  set reading(bool on) {
    if (_reading == on) return;
    _reading = on;
    if (on) {
      start();
    } else {
      _listening?.cancel();
      _listening = null;
      reset();
    }
  }

  /// handle takes one message from the runner.
  @visibleForTesting
  void handle(dynamic message) {
    if (message is! Map) return;
    heard = true;
    if (message["proximity"] is bool) {
      near = message["proximity"] as bool;
      eraser = near && message["eraser"] == true;
      return;
    }
    double n(String key) =>
        message[key] is num ? (message[key] as num).toDouble() : 0;
    pressure = n("pressure").clamp(0.0, 1.0);
    tiltX = n("tiltX").clamp(-1.0, 1.0);
    tiltY = n("tiltY").clamp(-1.0, 1.0);
    buttons = message["buttons"] is int ? message["buttons"] as int : 0;
    near = true;
    readAt = DateTime.now();
  }

  /// reset forgets every reading, for the tests.
  @visibleForTesting
  void reset() {
    pressure = tiltX = tiltY = 0;
    buttons = 0;
    eraser = near = heard = false;
    readAt = DateTime.fromMillisecondsSinceEpoch(0);
  }
}
