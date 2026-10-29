import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/decode.dart';
import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/media/mix/mix_core.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_mix_core_test.dart is the editor's mixer without a sound card:
// sounds through their channels' strips and the master, fades, soft stops,
// seeking, pausing, solo, levels and the spectrum -- block by block, as the
// engine asks for them.

MemoryTrack tone(double freq, double amp, {double seconds = 1}) {
  var n = (seconds * mixRate).round();
  var l = Float32List(n), r = Float32List(n);
  for (var i = 0; i < n; i++) {
    l[i] = r[i] = amp * math.sin(2 * math.pi * freq * i / mixRate);
  }
  return MemoryTrack(l, r);
}

MemoryTrack level(double v, {double seconds = 1}) {
  var n = (seconds * mixRate).round();
  return MemoryTrack(Float32List(n)..fillRange(0, n, v),
      Float32List(n)..fillRange(0, n, v));
}

/// run renders [frames] in blocks of 512, as the engine does, and returns
/// the left side.
Float32List run(MixCore core, int frames) {
  var out = Float32List(frames);
  var l = Float32List(512), r = Float32List(512);
  for (var at = 0; at < frames; at += 512) {
    var n = math.min(512, frames - at);
    core.render(l, r, n);
    out.setRange(at, at + n, l);
  }
  return out;
}

void main() {
  test("a sound on a channel goes through its strip, then the master", () {
    var core = MixCore()
      ..setChannel("a", const ChannelMix(gainDb: -6))
      ..setMaster(const MasterMix(limiter: false, gainDb: -6));
    core.play(level(0.5), volume: 1, channel: "a");
    var out = run(core, 1024);
    expect(out[600], closeTo(0.5 * dbToGain(-12), 1e-6));
  });

  test("a channel is the same strip an export runs", () {
    const strip = ChannelMix(
        eq: Eq(on: true, mid: EqBand(1000, gainDb: 6)),
        comp: Dynamics(on: true, threshold: -20),
        balance: 0.2);
    var core = MixCore()
      ..setChannel("a", strip)
      ..setMaster(const MasterMix(limiter: false));
    core.play(tone(800, 0.4), volume: 1, channel: "a");
    var live = run(core, 4096);
    var t = tone(800, 0.4);
    var l = Float32List(4096), r = Float32List(4096);
    t.read(l, r, 4096);
    var export = StripProcessor(strip);
    for (var at = 0; at < 4096; at += 512) {
      var bl = Float32List.sublistView(l, at, at + 512),
          br = Float32List.sublistView(r, at, at + 512);
      export.process(bl, br, 512);
    }
    for (var i = 0; i < 4096; i += 97) {
      expect(live[i], closeTo(l[i], 1e-6), reason: "frame $i");
    }
  });

  test("two sounds on one channel are summed, not halved", () {
    var core = MixCore()
      ..setChannel("a", const ChannelMix())
      ..setMaster(const MasterMix(limiter: false));
    core.play(level(0.2), volume: 1, channel: "a");
    core.play(level(0.3), volume: 1, channel: "a");
    expect(run(core, 512)[100], closeTo(0.5, 1e-6));
  });

  test("a fade is a straight line, and a soft stop ends the sound", () {
    var core = MixCore()..setMaster(const MasterMix(limiter: false));
    var v = core.play(level(1), volume: 1);
    core.volume(v, 0, fade: 1024 / mixRate);
    var out = run(core, 2048);
    expect(out[511], closeTo(0.5, 0.01));
    expect(out[1500], 0);
    var w = core.play(level(1), volume: 1);
    core.stopSoftly(w, 512 / mixRate);
    run(core, 1024);
    expect(w.alive, isFalse);
    expect(core.voices, isNot(contains(w)));
  });

  test("seek, pause, and the end of the file", () {
    var core = MixCore()..setMaster(const MasterMix(limiter: false));
    var n = mixRate ~/ 2;
    var ramp = Float32List(n);
    for (var i = 0; i < n; i++) {
      ramp[i] = i / n;
    }
    var v = core.play(MemoryTrack(ramp, Float32List.fromList(ramp)),
        volume: 1, at: 0.25);
    expect(v.since, n ~/ 2);
    var out = run(core, 512);
    expect(out[0], closeTo(0.5, 1e-6), reason: "from a quarter second in");
    core.pause(v, true);
    var frame = v.frame;
    expect(run(core, 512)[10], 0);
    expect(v.frame, frame, reason: "paused, it does not move on");
    core.pause(v, false);
    core.seek(v, 0.49);
    run(core, 2048);
    expect(v.alive, isFalse, reason: "it ran off the end");
  });

  test("a sound with no channel goes straight to the master", () {
    var core = MixCore()..setMaster(const MasterMix(limiter: false));
    core.play(level(0.25), volume: 1, channel: "nowhere");
    expect(run(core, 512)[10], closeTo(0.25, 1e-6));
  });

  test("soloed out is silent, and the meters read the levels", () {
    var core = MixCore()
      ..setChannel("a", const ChannelMix(mute: true))
      ..setChannel("b", const ChannelMix())
      ..setMaster(const MasterMix(limiter: false));
    core.play(level(0.5), volume: 1, channel: "a");
    core.play(level(0.1), volume: 1, channel: "b");
    expect(run(core, 512)[10], closeTo(0.1, 1e-6));
    expect(core.levels("a"), (0.0, 0.0));
    expect(core.levels("b").$1, closeTo(0.1, 1e-6));
    expect(core.levels().$1, closeTo(0.1, 1e-6));
  });

  test("the spectrum peaks where the sound is", () {
    var core = MixCore()
      ..setChannel("a", const ChannelMix())
      ..setMaster(const MasterMix(limiter: false));
    // 3000 Hz is bin 32 of 512 at 48kHz.
    core.play(tone(3000, 0.5), volume: 1, channel: "a");
    run(core, 2048);
    var s = core.spectrum("a")!;
    expect(s.length, 256);
    var top = 0;
    for (var i = 1; i < s.length; i++) {
      if (s[i] > s[top]) top = i;
    }
    expect(top, 32);
    expect(core.spectrum("nobody"), isNull);
  });

  test("a strip set again unchanged keeps what is in it", () {
    var core = MixCore()
      ..setChannel("a", const ChannelMix(comp: Dynamics(on: true)))
      ..setMaster(const MasterMix(limiter: false));
    core.play(tone(200, 0.9), volume: 1, channel: "a");
    var steady = run(core, 8192);
    core.setChannel("a", const ChannelMix(comp: Dynamics(on: true)));
    var next = run(core, 512);
    // No jump back to an uncompressed level: the compressor carried on.
    var peakBefore = steady.sublist(7000).map((v) => v.abs()).reduce(math.max);
    var peakAfter = next.map((v) => v.abs()).reduce(math.max);
    expect(peakAfter, closeTo(peakBefore, 0.05));
  });
}
