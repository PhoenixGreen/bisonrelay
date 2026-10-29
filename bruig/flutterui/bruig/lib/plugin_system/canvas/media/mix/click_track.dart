import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/decode.dart';
import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';

// click_track.dart is the metronome: a click on every beat, the first of
// each bar higher, made as it is read rather than held -- so it is as long
// as anything it plays under, costs nothing to move about in, and is never
// a file.
//
// The editor's alone. An export renders the document's sounds, and this is
// not one of them.

class ClickTrack implements TrackSource {
  /// secondsPerBeat and beatsPerBar are the metre it counts.
  final double secondsPerBeat;
  final int beatsPerBar;
  final double level;

  int _at = 0;

  ClickTrack(this.secondsPerBeat, this.beatsPerBar, {this.level = 0.5});

  /// clickSeconds is how long one click rings.
  static const double clickSeconds = 0.03;

  /// frames is a day: longer than anything it will be played under.
  @override
  int get frames => 24 * 3600 * mixRate;

  @override
  int read(Float32List l, Float32List r, int n) {
    var beat = secondsPerBeat * mixRate;
    var ring = (clickSeconds * mixRate).round();
    for (var i = 0; i < n; i++) {
      var frame = _at + i;
      var index = (frame / beat).floor();
      var into = frame - (index * beat).round();
      var v = 0.0;
      if (into >= 0 && into < ring) {
        var hz = index % math.max(1, beatsPerBar) == 0 ? 1600.0 : 1000.0;
        var t = into / mixRate;
        v = level * math.sin(2 * math.pi * hz * t) * math.exp(-t * 160);
      }
      l[i] = v;
      r[i] = v;
    }
    _at += n;
    return n;
  }

  @override
  void seek(int frame) => _at = math.max(0, frame);

  @override
  void close() {}
}
