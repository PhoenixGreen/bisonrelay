import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/own_motion.dart';

// canvas_arrival_fixture.dart gives a test's element an arrival and a way
// out as the editor does: its own clips (see own_motion.dart), timed in
// frames at the document's rate.

/// arrivingOver is [e] arriving from frame [from] to [to], and leaving over
/// [leaves] (from, to) if it is given, at [rate] frames a second.
T arrivingOver<T extends CanvasElement>(T e,
    {required int from,
    required int to,
    (int, int)? leaves,
    int rate = defaultFrameRate}) {
  var out = withOwnSpan(e, MotionKind.arrive, from, to, rate);
  if (leaves case (var a, var b)) {
    out = withOwnSpan(out, MotionKind.leave, a, b, rate);
  }
  return out as T;
}
