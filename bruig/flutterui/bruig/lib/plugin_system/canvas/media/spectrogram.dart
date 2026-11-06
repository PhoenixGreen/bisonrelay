import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/mix_core.dart'
    show MixCore;

// spectrogram.dart is a sound as its spectrum over time: a picture, a
// column a moment, a row a band of pitch -- low at the bottom -- each as
// bright as that band is loud there. For the clip editor's Spectrum view.

/// Spectrogram is the picture: [columns] wide, [rows] high, as RGBA bytes,
/// the first column at the sound's start and the last at its end.
typedef Spectrogram = ({int columns, int rows, Uint8List rgba});

/// spectrogramOf is [mono] (at [rate]) as a picture [columns] wide and
/// [rows] high: rows on a log scale from 40Hz to 16kHz, levels from -90dB
/// (dark) to nought (bright).
Spectrogram spectrogramOf(Float32List mono,
    {int columns = 600, int rows = 128, double rate = 48000}) {
  const n = 2048;
  var rgba = Uint8List(columns * rows * 4);
  if (mono.isEmpty) return (columns: columns, rows: rows, rgba: rgba);
  // Each row's band of bins, low to high on a log scale.
  const lo = 40.0, hi = 16000.0;
  int binOf(double hz) => (hz / rate * n).round().clamp(1, n ~/ 2 - 1);
  var bands = [
    for (var r = 0; r <= rows; r++)
      binOf(lo * math.pow(hi / lo, r / rows).toDouble()),
  ];
  var window = Float32List(n);
  for (var c = 0; c < columns; c++) {
    var centre = ((c + 0.5) / columns * mono.length).round();
    for (var i = 0; i < n; i++) {
      var at = centre - n ~/ 2 + i;
      window[i] = at >= 0 && at < mono.length ? mono[at] : 0;
    }
    var mags = MixCore.magnitudes(window);
    for (var r = 0; r < rows; r++) {
      var a = bands[r], b = math.max(a + 1, bands[r + 1]);
      var peak = 0.0;
      for (var k = a; k < b && k < mags.length; k++) {
        if (mags[k] > peak) peak = mags[k];
      }
      // magnitudes has a full-scale sine at about one: nought dB.
      var db = 20 * math.log(peak + 1e-9) / math.ln10;
      var v = ((db + 90) / 90).clamp(0.0, 1.0);
      var (cr, cg, cb) = _heat(v);
      // Low pitches at the bottom.
      var o = ((rows - 1 - r) * columns + c) * 4;
      rgba[o] = cr;
      rgba[o + 1] = cg;
      rgba[o + 2] = cb;
      rgba[o + 3] = 255;
    }
  }
  return (columns: columns, rows: rows, rgba: rgba);
}

/// _heat is a loudness, nought to one, as a colour: dark blue through
/// purple and orange to pale yellow.
(int, int, int) _heat(double v) {
  const stops = [
    (0.0, (10, 10, 30)),
    (0.35, (60, 30, 110)),
    (0.6, (190, 60, 90)),
    (0.8, (240, 150, 50)),
    (1.0, (255, 245, 190)),
  ];
  for (var i = 1; i < stops.length; i++) {
    var (b, (br, bg, bb)) = stops[i];
    if (v <= b) {
      var (a, (ar, ag, ab)) = stops[i - 1];
      var u = (v - a) / (b - a);
      int mix(int x, int y) => (x + (y - x) * u).round();
      return (mix(ar, br), mix(ag, bg), mix(ab, bb));
    }
  }
  return stops.last.$2;
}
