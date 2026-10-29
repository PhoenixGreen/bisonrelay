import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_mix_dsp_test.dart is the mix's arithmetic against what it is meant
// to be: the EQ's curve as drawn, the compressor's static curve, a ceiling
// nothing passes, and the loudness standard's own reference figure.

(Float32List, Float32List) sine(double freq, double amp,
    {double seconds = 0.5, double right = -1}) {
  var n = (seconds * mixRate).round();
  var l = Float32List(n), r = Float32List(n);
  for (var i = 0; i < n; i++) {
    var v = amp * math.sin(2 * math.pi * freq * i / mixRate);
    l[i] = v;
    r[i] = right < 0 ? v : right * math.sin(2 * math.pi * freq * i / mixRate);
  }
  return (l, r);
}

double rmsDb(Float32List x, {double from = 0.6}) {
  var start = (x.length * from).round();
  var sum = 0.0;
  for (var i = start; i < x.length; i++) {
    sum += x[i] * x[i];
  }
  return 10 * math.log(sum / (x.length - start)) / math.ln10;
}

double peakDb(Float32List x, {double from = 0.6}) {
  var start = (x.length * from).round();
  var p = 0.0;
  for (var i = start; i < x.length; i++) {
    p = math.max(p, x[i].abs());
  }
  return 20 * math.log(p) / math.ln10;
}

void main() {
  test("the EQ does what its curve says", () {
    var eq = const Eq(on: true)
        .withBand(EqSlot.low, const EqBand(120, gainDb: 6))
        .withBand(EqSlot.mid, const EqBand(1000, gainDb: -8, q: 1.4))
        .withBand(EqSlot.highCut, const EqBand(6000, on: true, slope: 24))
        .copyWith(gainDb: 2);
    for (var f in [60.0, 300.0, 1000.0, 3000.0, 9000.0]) {
      var (l, r) = sine(f, 0.25);
      var before = rmsDb(l);
      EqProcessor(eq).process(l, r, l.length);
      expect(rmsDb(l) - before, closeTo(eq.responseDb(f), 0.15),
          reason: "at $f Hz");
      expect(rmsDb(r), closeTo(rmsDb(l), 1e-3), reason: "both sides alike");
    }
  });

  test("the compressor settles on its curve, with its makeup", () {
    const d = Dynamics(
        on: true,
        threshold: -18,
        ratio: 4,
        kneeDb: 0,
        attackMs: 1,
        releaseMs: 400,
        makeupDb: 3);
    var (l, r) = sine(100, dbToGain(-6), seconds: 1);
    Compressor(d).process(l, r, l.length);
    expect(peakDb(l), closeTo(d.reducedDb(-6) + 3, 0.5));
    // Under the threshold it is left alone.
    var (ql, qr) = sine(100, dbToGain(-30), seconds: 1);
    Compressor(d.copyWith(makeupDb: 0)).process(ql, qr, ql.length);
    expect(peakDb(ql), closeTo(-30, 0.05));
  });

  test("nothing passes the limiter's ceiling", () {
    var (l, r) = sine(440, 2.5, seconds: 1);
    // A sudden spike as well, which the lookahead has to catch.
    l[30000] = 6;
    Limiter(-1).process(l, r, l.length);
    var ceiling = dbToGain(-1);
    for (var i = 0; i < l.length; i++) {
      expect(l[i].abs(), lessThanOrEqualTo(ceiling + 1e-6));
    }
    expect(peakDb(l), closeTo(-1, 0.3), reason: "held at it, not far below");
  });

  test("a strip's balance turns down the other side, and mute is silence", () {
    var (l, r) = sine(440, 0.5);
    var before = rmsDb(l);
    StripProcessor(const ChannelMix(gainDb: -6, balance: 0.5))
        .process(l, r, l.length);
    expect(rmsDb(r) - before, closeTo(-6, 0.01));
    expect(rmsDb(l) - before, closeTo(-6 + 20 * math.log(0.5) / math.ln10, 0.01));
    StripProcessor(const ChannelMix(mute: true)).process(l, r, l.length);
    expect(l.every((v) => v == 0), isTrue);
  });

  test("loudness: the standard's own check, and twice as loud is +6", () {
    // BS.1770: a full-scale 1kHz sine in one channel reads -3.01 LUFS.
    var (l, r) = sine(1000, 1, seconds: 5, right: 0);
    var m = LoudnessMeter()..add(l, r, l.length);
    expect(m.integrated, closeTo(-3.01, 0.1));
    var (ql, qr) = sine(1000, 0.5, seconds: 5, right: 0);
    var half = LoudnessMeter()..add(ql, qr, ql.length);
    expect(m.integrated - half.integrated, closeTo(6.02, 0.05));
    expect(LoudnessMeter().integrated, -double.infinity);
  });
}
