import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
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

  test("a reverb's tail is heard as ringing until it has died away", () {
    var g = MixGraph()
      ..setMaster(const MasterMix(limiter: false))
      ..setChannel(
          "a",
          const ChannelMix(devices: [
            MixDevice(DeviceKind.reverb, values: {"size": 0.9})
          ]));
    for (var i = 0; i < 20; i++) {
      _block(g, 0.3);
    }
    _block(g, 0);
    expect(g.ringing, isTrue, reason: "the tail after the sound");
    // Forty seconds of silence after it.
    for (var i = 0; i < 4000; i++) {
      _block(g, 0);
    }
    expect(g.ringing, isFalse, reason: "rung out: the engine may rest");
  });

  test("a send turned as it plays ramps rather than steps", () {
    var g = MixGraph()
      ..setMaster(const MasterMix(limiter: false))
      ..setReturns(const [ReturnChannel("fx", name: "Plain", pre: true)])
      ..setChannel("a", const ChannelMix(gainDb: -120, sends: {"fx": -120}));
    for (var i = 0; i < 4; i++) {
      _block(g, 0.5);
    }
    g.setChannel("a", const ChannelMix(gainDb: -120, sends: {"fx": 0}));
    var up = _block(g, 0.5);
    expect(up.first, lessThan(0.01), reason: "from where it was");
    expect(up.last, closeTo(0.5, 0.01), reason: "to where it is set");
  });

  test("the limiter keeps its loudest as it goes: the gain it always had", () {
    // As it was: the whole window looked through at every sample.
    (Float32List, Float32List) byScanning(Float32List l, Float32List r) {
      const ahead = 240;
      var ceiling = dbToGain(-1);
      double coefficient(double ms) => math.exp(-1 / (ms / 1000 * 48000));
      var attack = coefficient(5 / 4), release = coefficient(50);
      var dl = Float32List(ahead), dr = Float32List(ahead);
      var peaks = Float32List(ahead);
      var at = 0;
      var gain = 1.0;
      var ol = Float32List(l.length), or = Float32List(r.length);
      for (var i = 0; i < l.length; i++) {
        peaks[at] = math.max(l[i].abs(), r[i].abs());
        var loudest = 0.0;
        for (var p in peaks) {
          if (p > loudest) loudest = p;
        }
        var want = loudest > ceiling ? ceiling / loudest : 1.0;
        gain = want + (want < gain ? attack : release) * (gain - want);
        var outL = dl[at], outR = dr[at];
        dl[at] = l[i];
        dr[at] = r[i];
        at = (at + 1) % ahead;
        ol[i] = (outL * gain).clamp(-ceiling, ceiling);
        or[i] = (outR * gain).clamp(-ceiling, ceiling);
      }
      return (ol, or);
    }

    var rnd = math.Random(7);
    const n = 48000;
    var l = Float32List(n), r = Float32List(n);
    for (var i = 0; i < n; i++) {
      // Bursts over the ceiling, and quiet between.
      var loud = (i ~/ 3000).isEven ? 1.6 : 0.3;
      l[i] = (rnd.nextDouble() * 2 - 1) * loud;
      r[i] = (rnd.nextDouble() * 2 - 1) * loud;
    }
    var (wl, wr) = byScanning(l, r);
    var limiter = Limiter(-1);
    var gl = Float32List.fromList(l), gr = Float32List.fromList(r);
    for (var at = 0; at < n; at += 480) {
      limiter.process(Float32List.sublistView(gl, at, at + 480),
          Float32List.sublistView(gr, at, at + 480), 480);
    }
    for (var i = 0; i < n; i++) {
      expect(gl[i], closeTo(wl[i], 1e-6), reason: "left at $i");
      expect(gr[i], closeTo(wr[i], 1e-6), reason: "right at $i");
    }
  });
}
