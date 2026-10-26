import 'dart:io';

import 'package:bruig/plugin_system/canvas/model/elements/character_bvh.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// body_capture.dart reads how a person in a video moves, in 3D, with the
// operating system's own model -- see BodyPoseReader in
// macos/Runner/MainFlutterWindow.swift. On this computer, from a file: no
// camera, nothing uploaded.

/// BodyCapture is motion from a video.
class BodyCapture {
  static const _channel = MethodChannel("bruig/vision");
  static bool? _available;

  /// known is the answer [available] has already had, if any.
  static bool? get known => _available;

  /// available is whether this computer can: macOS 14 or later.
  static Future<bool> available() async {
    var known = _available;
    if (known != null) return known;
    if (kIsWeb || !Platform.isMacOS) return _available = false;
    try {
      return _available =
          await _channel.invokeMethod<bool>("available") ?? false;
    } catch (_) {
      return _available = false;
    }
  }

  /// fromVideo is the person in the video at [path] moving, read at [fps]
  /// frames a second for up to [seconds]. Throws a MotionError when no one
  /// is found or the video cannot be read.
  static Future<JointMotion> fromVideo(String path, double fps,
      {double seconds = 120}) async {
    Map<String, dynamic>? found;
    try {
      found = await _channel.invokeMapMethod<String, dynamic>("bodyPose3D",
          {"path": path, "fps": fps, "seconds": seconds});
    } on PlatformException catch (e) {
      throw MotionError(e.message ?? "The video could not be read.");
    } on MissingPluginException {
      throw const MotionError("Motion from a video needs macOS 14 or later.");
    }
    return motionFromCapture(found ?? const {});
  }
}

/// motionFromCapture is BodyPoseReader's answer as a skeleton moving.
@visibleForTesting
JointMotion motionFromCapture(Map<String, dynamic> found) {
  var names = [for (var n in (found["names"] as List?) ?? const []) "$n"];
  var raw = found["frames"];
  var frames = raw is Float64List
      ? raw
      : Float64List.fromList([for (var v in (raw as List?) ?? const []) (v as num).toDouble()]);
  var count = names.isEmpty ? 0 : frames.length ~/ (names.length * 3);
  if ((found["found"] as num? ?? 0) <= 0 || count == 0) {
    throw const MotionError("No one could be found in the video. A whole "
        "body, head to feet, in good light, works best.");
  }
  var frameTime = (found["frameTime"] as num?)?.toDouble() ?? 1 / 24;
  return JointMotion(names, count, frameTime, (f) {
    var at = f * names.length * 3;
    return [
      for (var j = 0; j < names.length; j++)
        [frames[at + j * 3], frames[at + j * 3 + 1], frames[at + j * 3 + 2]],
    ];
  });
}


/// CaptureKind is what a live recording is from.
enum CaptureKind { camera, microphone }

/// LiveCapture records from the camera or the microphone to a file -- see
/// CaptureRecorder in macos/Runner/MainFlutterWindow.swift. One at a time.
class LiveCapture {
  static const _channel = MethodChannel("bruig/capture");

  /// recording is what is being recorded now, or null.
  static final ValueNotifier<CaptureKind?> recording = ValueNotifier(null);

  /// available is whether this computer can: macOS only, for now.
  static bool get available => !kIsWeb && Platform.isMacOS;

  /// start begins recording from [kind]. Throws a message fit to show when
  /// it is not allowed or cannot.
  static Future<void> start(CaptureKind kind) async {
    if (recording.value != null) return;
    try {
      await _channel.invokeMethod("start", {"kind": kind.name});
      recording.value = kind;
    } on PlatformException catch (e) {
      throw e.message ?? "Recording could not start.";
    } on MissingPluginException {
      throw "Recording is not available on this computer.";
    }
  }

  /// stop ends the recording and gives the file it made, or null.
  static Future<String?> stop() async {
    if (recording.value == null) return null;
    try {
      var got = await _channel.invokeMapMethod<String, dynamic>("stop");
      var path = got?["path"] as String? ?? "";
      return path.isEmpty ? null : path;
    } on PlatformException catch (e) {
      throw e.message ?? "The recording could not be kept.";
    } finally {
      recording.value = null;
    }
  }
}
