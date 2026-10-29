import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';

// transport.dart is the arithmetic behind the timeline's control bar: where
// the playhead is, said three ways and read back from any of them, and the
// tempo worked out from presses in time.
//
// A frame is the timeline's step; [rate] of them make a second. Bars and
// beats are the AudioSettings' metre laid over the same seconds, counted
// from the start of the timeline.

/// PositionFormat is how the position reads.
enum PositionFormat {
  bars("Bars and beats"),
  time("Minutes and seconds"),
  frames("Frames");

  final String label;
  const PositionFormat(this.label);

  static PositionFormat fromName(String? name) =>
      values.firstWhere((f) => f.name == name, orElse: () => bars);
}

/// sixteenthsPerBeat is how many sixteenth notes a beat of [audio] holds:
/// four in 4/4, two in 6/8 -- never fewer than one.
int sixteenthsPerBeat(AudioSettings audio) => math.max(1, 16 ~/ audio.beatUnit);

/// barsText is [frame] as bar, beat and sixteenth, each counted from one, as
/// "5. 2. 3".
String barsText(AudioSettings audio, int frame, int rate) {
  var seconds = frame / math.max(1, rate);
  var sixteenth = audio.secondsPerBeat / sixteenthsPerBeat(audio);
  // A hair over, so a frame that is a beat to within rounding reads as it.
  var count = (seconds / sixteenth + 1e-6).floor();
  var perBar = sixteenthsPerBeat(audio) * audio.beatsPerBar;
  var bar = count ~/ perBar;
  var beat = (count % perBar) ~/ sixteenthsPerBeat(audio);
  var six = count % sixteenthsPerBeat(audio);
  return "${bar + 1}. ${beat + 1}. ${six + 1}";
}

/// lengthText is a span of [frames] as bars, beats and sixteenths, each
/// counted from nought -- "4. 0. 0" is four bars long -- as a loop's length
/// is shown.
String lengthText(AudioSettings audio, int frames, int rate) {
  var seconds = frames / math.max(1, rate);
  var sixteenth = audio.secondsPerBeat / sixteenthsPerBeat(audio);
  var count = (seconds / sixteenth + 1e-6).round();
  var perBar = sixteenthsPerBeat(audio) * audio.beatsPerBar;
  return "${count ~/ perBar}. "
      "${(count % perBar) ~/ sixteenthsPerBeat(audio)}. "
      "${count % sixteenthsPerBeat(audio)}";
}

/// timeText is [frame] as minutes and seconds, to the thousandth where the
/// rate is fine enough to need it.
String timeText(int frame, int rate) {
  var seconds = frame / math.max(1, rate);
  var minutes = seconds ~/ 60;
  var rest = seconds - minutes * 60;
  var digits = rate > 50 ? 3 : 1;
  var s = rest.toStringAsFixed(digits);
  if (rest < 10) s = "0$s";
  return "$minutes:$s";
}

/// positionText is [frame] read as [format]. Frames are counted from one, as
/// the frame field always has.
String positionText(PositionFormat format, AudioSettings audio, int frame,
        int rate, int frames) =>
    switch (format) {
      PositionFormat.bars => barsText(audio, frame, rate),
      PositionFormat.time => timeText(frame, rate),
      PositionFormat.frames => "${frame + 1} / $frames",
    };

/// parsePosition is the frame a typed position names, or null where it
/// names none. Read by its shape rather than by the format showing: "5.2.3"
/// (or "5 2 3", or "5") is a bar, "1:04.5" minutes and seconds, "#288" or
/// "f288" a frame. A plain number is a bar in [bars] and a frame otherwise.
int? parsePosition(String typed, AudioSettings audio, int rate,
    {required bool bars}) {
  var text = typed.trim().toLowerCase();
  if (text.isEmpty) return null;
  rate = math.max(1, rate);
  if (text.startsWith("#") || text.startsWith("f")) {
    var n = int.tryParse(text.substring(1).trim());
    return n == null || n < 1 ? null : n - 1;
  }
  if (text.contains(":")) {
    var parts = text.split(":");
    if (parts.length != 2) return null;
    var m = int.tryParse(parts[0].trim());
    var s = double.tryParse(parts[1].trim());
    if (m == null || s == null || m < 0 || s < 0) return null;
    return ((m * 60 + s) * rate).round();
  }
  var pieces = text
      .split(RegExp(r"[.\s]+"))
      .where((p) => p.isNotEmpty)
      .map(int.tryParse)
      .toList();
  if (pieces.isEmpty || pieces.any((p) => p == null || p < 1)) return null;
  if (pieces.length == 1 && !bars) return pieces.first! - 1;
  if (pieces.length > 3) return null;
  var bar = pieces[0]! - 1;
  var beat = (pieces.length > 1 ? pieces[1]! : 1) - 1;
  var six = (pieces.length > 2 ? pieces[2]! : 1) - 1;
  if (beat >= audio.beatsPerBar || six >= sixteenthsPerBeat(audio)) {
    return null;
  }
  var seconds = bar * audio.secondsPerBar +
      beat * audio.secondsPerBeat +
      six * audio.secondsPerBeat / sixteenthsPerBeat(audio);
  return (seconds * rate).round();
}

/// tapTempo is the tempo that presses at [taps] (in seconds, oldest first)
/// keep, or null until there are enough to say. The last few intervals are
/// averaged; a gap of more than two seconds starts the count again, as a
/// pause before tapping again would mean.
double? tapTempo(List<double> taps) {
  var run = <double>[];
  for (var t in taps) {
    if (run.isNotEmpty && t - run.last > 2) run.clear();
    run.add(t);
  }
  if (run.length < 4) return null;
  var recent = run.sublist(math.max(0, run.length - 8));
  var gap = (recent.last - recent.first) / (recent.length - 1);
  if (gap <= 0) return null;
  var bpm = 60 / gap;
  return (bpm * 100).round() / 100;
}

/// parseLength is the span a typed length names, in frames, or null. In
/// [bars], counted from nought as lengthText writes them: "4" is four bars,
/// "4.2" four bars and two beats. Otherwise a number of frames.
int? parseLength(String typed, AudioSettings audio, int rate,
    {required bool bars}) {
  var text = typed.trim();
  rate = math.max(1, rate);
  if (!bars) {
    var n = int.tryParse(text);
    return n == null || n < 1 ? null : n;
  }
  var pieces = text
      .split(RegExp(r"[.\s]+"))
      .where((p) => p.isNotEmpty)
      .map(int.tryParse)
      .toList();
  if (pieces.isEmpty ||
      pieces.length > 3 ||
      pieces.any((p) => p == null || p < 0)) {
    return null;
  }
  var seconds = pieces[0]! * audio.secondsPerBar +
      (pieces.length > 1 ? pieces[1]! : 0) * audio.secondsPerBeat +
      (pieces.length > 2 ? pieces[2]! : 0) *
          audio.secondsPerBeat /
          sixteenthsPerBeat(audio);
  var frames = (seconds * rate).round();
  return frames < 1 ? null : frames;
}
