import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// canvas_cues.dart is the named moments of a whole run -- "OR DIE", "the
// flip side" -- that what is on the scenes is timed against.
//
// A video cut to a voice-over is timed to the voice, and the voice is on the
// master: the one timeline every scene plays under. A cue is a point on that
// timeline with a name. An element tied to one keeps its timing *relative* to
// it, so when the voice is re-recorded and a line lands half a second later,
// moving the cue moves everything that arrives on it -- in whichever scene it
// is -- rather than somebody finding and dragging forty keyframes.

/// TimelineCue is one named moment, in frames of the whole run.
class TimelineCue {
  final String id;
  final String name;
  final int frame;

  const TimelineCue({required this.id, this.name = "", required this.frame});

  TimelineCue copyWith({String? name, int? frame}) =>
      TimelineCue(id: id, name: name ?? this.name, frame: frame ?? this.frame);

  Map<String, dynamic> toJson() => {
        "id": id,
        if (name.isNotEmpty) "name": name,
        "frame": frame,
      };

  static TimelineCue? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    var id = jsonString(json["id"], "");
    if (id.isEmpty) return null;
    return TimelineCue(
        id: id,
        name: jsonString(json["name"], ""),
        frame: math.max(0, jsonInt(json["frame"], 0)));
  }
}

int _cueCounter = 0;

/// newCueId is an id unique within a session, and in practice across them.
String newCueId() =>
    "cue${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}"
    "_${_cueCounter++}";

/// speechStarts is where somebody starts speaking after a pause, in seconds
/// from the start of a recording whose shape is [peaks] -- evenly spaced
/// loudness from nought to one across [seconds].
///
/// A pause is at least [gap] seconds quieter than [floor] of the recording's
/// loudest; the first sound in the file counts too. Not transcription -- it
/// cannot say what is said -- but on a voice-over the pauses are where the
/// lines change, which is what a scene wants cutting on.
List<double> speechStarts(Float32List peaks, double seconds,
    {double gap = 0.35, double floor = 0.08}) {
  if (peaks.isEmpty || seconds <= 0) return const [];
  var loudest = 0.0;
  for (var p in peaks) {
    if (p > loudest) loudest = p;
  }
  if (loudest <= 0) return const [];
  var quiet = loudest * floor;
  var step = seconds / peaks.length;
  var starts = <double>[];
  var silent = 0;
  var first = true;
  for (var i = 0; i < peaks.length; i++) {
    if (peaks[i] <= quiet) {
      silent++;
      continue;
    }
    if (first || silent * step >= gap) starts.add(i * step);
    first = false;
    silent = 0;
  }
  return starts;
}
