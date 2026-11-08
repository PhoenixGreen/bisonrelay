import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/mix_graph.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/surround.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_engine_carry_test.dart is the mix going on through a change as it
// plays (Ken's systems review, 2026-11-08): a mute ramps rather than cuts,
// the master changed keeps its limiter's lookahead and its fader ramps, a
// strip rebuilt keeps its EQ's state, and a channel taken away is gone for
// whatever listened to it.

const _n = 480;

/// _block plays one block of [level] on channel "a" (and [key] on "k"),
/// and gives the master's left side.
Float32List _block(MixGraph g, double level, {double? key}) {
  var l = Float32List(_n), r = Float32List(_n);
  g.begin(_n);
  var (il, ir) = g.input("a", _n);
  il.fillRange(0, _n, level);
  ir.fillRange(0, _n, level);
  if (key != null) {
    var (kl, kr) = g.input("k", _n);
    kl.fillRange(0, _n, key);
    kr.fillRange(0, _n, key);
  }
  g.finish(l, r, _n);
  return l;
}

void main() {
  test("a mute ramps down over a block, and back up", () {
    var g = MixGraph()
      ..setMaster(const MasterMix(limiter: false))
      ..setChannel("a", const ChannelMix());
    _block(g, 0.5);
    g.setChannel("a", const ChannelMix(mute: true));
    var down = _block(g, 0.5);
    expect(down.first, greaterThan(0.45), reason: "no cut at its start");
    expect(down.last, closeTo(0, 1e-6));
    expect(_block(g, 0.5).every((v) => v == 0), isTrue, reason: "then silent");
    g.setChannel("a", const ChannelMix());
    var up = _block(g, 0.5);
    expect(up.first, lessThan(0.05));
    expect(up.last, closeTo(0.5, 1e-6));
  });

  test("the master changed as it plays: no gap, its fader ramps", () {
    var g = MixGraph()
      ..setMaster(const MasterMix(ceilingDb: -1))
      ..setChannel("a", const ChannelMix());
    for (var i = 0; i < 5; i++) {
      _block(g, 0.3);
    }
    g.setMaster(const MasterMix(ceilingDb: -1, gainDb: -6.0206));
    var after = _block(g, 0.3);
    // A new limiter would give its five milliseconds of lookahead as
    // silence; carried on, what it held back comes out.
    expect(after.first, closeTo(0.3, 0.01), reason: "no gap");
    expect(after.last, inExclusiveRange(0.15, 0.3), reason: "ramping");
    // Heard five milliseconds late, through the limiter's lookahead.
    expect(_block(g, 0.3).last, closeTo(0.15, 0.01), reason: "at half");
  });

  test("a strip's EQ turned keeps its state: no jump at the change", () {
    const low = Eq(on: true, lowCut: EqBand(200, on: true));
    var g = MixGraph()
      ..setMaster(const MasterMix(limiter: false))
      ..setChannel("a", const ChannelMix(eq: low));
    for (var i = 0; i < 20; i++) {
      _block(g, 0.3);
    }
    // Settled, a steady level through a low cut is near nothing; begun
    // again from silence, the cut's step would show as a jump.
    g.setChannel(
        "a", ChannelMix(eq: low.copyWith(lowCut: const EqBand(210, on: true))));
    var after = _block(g, 0.3);
    expect(after.first.abs(), lessThan(0.01));
  });

  test("a channel taken away is not heard as silence by a gate keyed to it",
      () {
    const keyed = MixDevice(DeviceKind.gate,
        id: "g", source: "k", values: {"threshold": -20});
    var g = MixGraph()
      ..setMaster(const MasterMix(limiter: false))
      ..setChannel("k", const ChannelMix(gainDb: -120))
      ..setChannel("a", const ChannelMix(devices: [keyed]));
    for (var i = 0; i < 10; i++) {
      _block(g, 0.3, key: 0);
    }
    expect(_block(g, 0.3, key: 0).last.abs(), lessThan(0.01),
        reason: "its key silent: shut");
    g.removeChannel("k");
    for (var i = 0; i < 10; i++) {
      _block(g, 0.3);
    }
    expect(_block(g, 0.3).last, closeTo(0.3, 0.02),
        reason: "its key gone, it listens to its own sound, as an export does");
  });

  test("a 5.1 master's cards read as a stereo master's do", () {
    var g = MixGraph()
      ..setSpeakers(SpeakerLayout.surround51)
      ..setMaster(const MasterMix(ceilingDb: -12))
      ..setChannel("a", const ChannelMix());
    // A tone: loudness is weighted, and a steady level (no tone at all)
    // weighs nothing.
    var l = Float32List(_n), r = Float32List(_n);
    for (var b = 0; b < 100; b++) {
      g.begin(_n);
      var (il, ir) = g.input("a", _n);
      for (var i = 0; i < _n; i++) {
        il[i] =
            ir[i] = 0.6 * math.sin(2 * math.pi * 1000 * (b * _n + i) / 48000);
      }
      g.finish(l, r, _n);
    }
    expect(g.levels(limitKey).$1, lessThan(0.9),
        reason: "its limiters' turn-down shown");
    expect(g.loudnessOf()!.momentary, greaterThan(-60),
        reason: "what is heard measured, for its Loudness card");
  });

  test("an Auto-tune's knob turned as it plays leaves no gap", () {
    var g = MixGraph()
      ..setMaster(const MasterMix(limiter: false))
      ..setChannel(
          "a",
          const ChannelMix(devices: [
            MixDevice(DeviceKind.autoTune, id: "t", values: {"amount": 1})
          ]));
    var l = Float32List(_n), r = Float32List(_n);
    var b = 0;
    Float32List play() {
      g.begin(_n);
      var (il, ir) = g.input("a", _n);
      for (var i = 0; i < _n; i++) {
        il[i] =
            ir[i] = 0.3 * math.sin(2 * math.pi * 220 * (b * _n + i) / 48000);
      }
      b++;
      g.finish(l, r, _n);
      return l;
    }

    for (var i = 0; i < 20; i++) {
      play();
    }
    g.setChannel(
        "a",
        const ChannelMix(devices: [
          MixDevice(DeviceKind.autoTune, id: "t", values: {"amount": 0.5})
        ]));
    var after = play();
    var loudest = after.fold(0.0, (m, v) => math.max(m, v.abs()));
    expect(loudest, greaterThan(0.1),
        reason: "what it held back still heard; a new one would be silent");
  });
}
