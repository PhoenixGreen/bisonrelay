import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart' show mixRate;
import 'package:bruig/plugin_system/canvas/media/synth/part_render.dart';
import 'package:bruig/plugin_system/canvas/media/synth/patch_voice.dart';
import 'package:bruig/plugin_system/canvas/media/synth/sampler.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/synth_patch.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_synth_patch_test.dart is a synth of modules patched together (Ken,
// 2026-11-14: the prototype's synth modules), played: what each module
// does to the sound, measured off the sound itself.

SynthModule mod(String id, SynthModuleKind kind,
        {Map<String, double> values = const {},
        Map<String, String> choices = const {},
        Map<String, String> inputs = const {}}) =>
    SynthModule(id, kind, values: values, choices: choices, inputs: {
      for (var MapEntry(:key, :value) in inputs.entries)
        key: (module: value.split(".")[0], port: value.split(".")[1]),
    });

/// basic is the prototype's starting patch: the keyboard's pitch into a
/// sine oscillator, through the amp to the speaker.
List<SynthModule> basic({String wave = "sine"}) => [
      mod("k", SynthModuleKind.keys),
      mod("o", SynthModuleKind.osc,
          choices: {"wave": wave}, inputs: {"pitch": "k.pitch"}),
      mod("a", SynthModuleKind.amp, inputs: {"in": "o.out"}),
      mod("s", SynthModuleKind.out, inputs: {"in": "a.out"}),
    ];

/// played is [modules] played as one note of [key] held [seconds], and a
/// second after.
Float32List played(List<SynthModule> modules,
    {int key = 69, double seconds = 0.5, double tail = 1}) {
  var part = InstrumentPart(
      sound: InstrumentSound.patch,
      patch: SynthPatch(modules, "s"),
      notes: [
        MidiNote(key, 0, seconds, 100),
        // A silent note to make the render as long as the tail.
        MidiNote(key, seconds + tail, 0.001, 1),
      ]);
  return renderPart(part, null).$1;
}

double rms(Float32List x, double from, double to) {
  var a = (from * mixRate).round(),
      b = math.min(x.length, (to * mixRate).round());
  var sum = 0.0;
  for (var i = a; i < b; i++) {
    sum += x[i] * x[i];
  }
  return b > a ? math.sqrt(sum / (b - a)) : 0;
}

/// pitchOf is the frequency of [x] between [from] and [to], by its rising
/// zero crossings.
double pitchOf(Float32List x, double from, double to) {
  var a = (from * mixRate).round(), b = (to * mixRate).round();
  int? first, last;
  var n = 0;
  for (var i = a + 1; i < b; i++) {
    if (x[i - 1] < 0 && x[i] >= 0) {
      first ??= i;
      last = i;
      n++;
    }
  }
  if (first == null || n < 2) return 0;
  return (n - 1) / ((last! - first) / mixRate);
}

/// roughness is how much of [x] is in its fast changes: high for a bright
/// sound, low for a dull one, as a share of its level.
double roughness(Float32List x, double from, double to) {
  var a = (from * mixRate).round(), b = (to * mixRate).round();
  var d = 0.0, s = 0.0;
  for (var i = a + 1; i < b; i++) {
    d += (x[i] - x[i - 1]) * (x[i] - x[i - 1]);
    s += x[i] * x[i];
  }
  return s > 0 ? math.sqrt(d / s) : 0;
}

void main() {
  test("kept: a patch, its modules, settings and cables", () {
    var p = SynthPatch([
      ...basic(),
      mod("f", SynthModuleKind.filter,
          values: {"cutoff": 900}, choices: {"type": "highpass"}),
    ], "s");
    var back = SynthPatch.fromJson(p.toJson())!;
    expect(back.wiring, p.wiring);
    expect(back.byId("f")!.value("cutoff"), 900);
    expect(back.byId("f")!.choice("type"), "highpass");
    expect(back.byId("o")!.inputs["pitch"], (module: "k", port: "pitch"));
    var part = InstrumentPart.fromJson(
        InstrumentPart(sound: InstrumentSound.patch, patch: p).toJson());
    expect(part.sound, InstrumentSound.patch);
    expect(part.patch!.wiring, p.wiring);
  });

  test(
      "what the speaker hears: sources first, the unpatched and loops left out",
      () {
    var p = SynthPatch([
      ...basic(),
      mod("lonely", SynthModuleKind.lfo),
      // A loop: the amp fed back into itself through a mixer.
      mod("m", SynthModuleKind.mixer, inputs: {"a": "a.out"}),
    ], "s");
    expect([for (var m in p.heard) m.id], ["k", "o", "a", "s"]);
    var loop = SynthPatch([
      mod("a", SynthModuleKind.amp, inputs: {"in": "m.out"}),
      mod("m", SynthModuleKind.mixer, inputs: {"a": "a.out"}),
      mod("s", SynthModuleKind.out, inputs: {"in": "a.out"}),
    ], "s");
    expect(loop.heard.length, 3, reason: "each once, the loop cut");
    expect(
        synthPlugFits(SynthModuleKind.lfo.outs.first,
            SynthModuleKind.filter.input("in")!),
        isFalse,
        reason: "a control is not sound");
  });

  test("the keyboard's pitch: the note played; without it, a drone on A", () {
    var keyed = played(basic(), key: 69);
    expect(pitchOf(keyed, 0.05, 0.45), closeTo(440, 2));
    var low = played(basic(), key: 57);
    expect(pitchOf(low, 0.05, 0.45), closeTo(220, 1));
    var unkeyed = played([
      mod("o", SynthModuleKind.osc),
      mod("a", SynthModuleKind.amp, inputs: {"in": "o.out"}),
      mod("s", SynthModuleKind.out, inputs: {"in": "a.out"}),
    ], key: 72);
    expect(pitchOf(unkeyed, 0.05, 0.45), closeTo(220, 1));
    // An octave up, a fifth's worth of cents (700) on top.
    var up = played([
      for (var m in basic())
        m.id == "o" ? m.copyWith(values: {"octave": 1, "detune": 700}) : m
    ], key: 57);
    expect(pitchOf(up, 0.05, 0.45), closeTo(440 * 1.4983, 3));
  });

  test("an amp with nothing in its gain: heard while the key is held", () {
    var x = played(basic(), seconds: 0.5);
    expect(rms(x, 0.1, 0.45), greaterThan(0.05));
    expect(rms(x, 0.6, 0.9), lessThan(1e-4), reason: "silent once let go");
  });

  test("an envelope shapes it -- once the gate is patched in", () {
    List<SynthModule> withEnv({required bool gated}) => [
          ...basic().where((m) => m.id != "a"),
          mod("e", SynthModuleKind.env,
              values: {"a": 0.3, "d": 0.1, "s": 1, "r": 0.5},
              inputs: {if (gated) "gate": "k.gate"}),
          mod("a", SynthModuleKind.amp,
              inputs: {"in": "o.out", "gain": "e.env"}),
        ];
    var slow = played(withEnv(gated: true), seconds: 0.6);
    expect(rms(slow, 0.0, 0.05), lessThan(rms(slow, 0.35, 0.55) * 0.3),
        reason: "a slow attack: quiet at first");
    expect(rms(slow, 0.7, 0.8), greaterThan(0.01),
        reason: "its release rings on after the key");
    var ungated = played(withEnv(gated: false), seconds: 0.6);
    expect(rms(ungated, 0.0, 0.05), greaterThan(rms(ungated, 0.35, 0.55) * 0.6),
        reason: "not gated: the envelope moves nothing");
  });

  test("a low-pass filter dulls it; opened, it is bright again", () {
    List<SynthModule> through(double cutoff) => [
          mod("k", SynthModuleKind.keys),
          mod("o", SynthModuleKind.osc,
              choices: {"wave": "sawtooth"}, inputs: {"pitch": "k.pitch"}),
          mod("f", SynthModuleKind.filter,
              values: {"cutoff": cutoff, "res": 0.1}, inputs: {"in": "o.out"}),
          mod("a", SynthModuleKind.amp, inputs: {"in": "f.out"}),
          mod("s", SynthModuleKind.out, inputs: {"in": "a.out"}),
        ];
    var dull = roughness(played(through(300), key: 45), 0.1, 0.4);
    var bright = roughness(played(through(12000), key: 45), 0.1, 0.4);
    expect(dull, lessThan(bright * 0.5));
  });

  test("an LFO in the amp's gain: a tremolo at its rate", () {
    var x = played([
      ...basic().where((m) => m.id != "a"),
      mod("l", SynthModuleKind.lfo, values: {"rate": 4, "depth": 1}),
      mod("a", SynthModuleKind.amp, inputs: {"in": "o.out", "gain": "l.lfo"}),
    ], seconds: 1.5);
    // The level, a sixtieth of a second at a time, rises and falls 4 times
    // a second.
    var levels = [
      for (var t = 0.0; t < 1.4; t += 1 / 60) rms(x, t, t + 1 / 60)
    ];
    var peaks = 0;
    for (var i = 1; i < levels.length - 1; i++) {
      if (levels[i] > levels[i - 1] &&
          levels[i] >= levels[i + 1] &&
          levels[i] > 0.05) {
        peaks++;
      }
    }
    expect(peaks, inInclusiveRange(5, 6), reason: "4 a second for 1.4 s");
  });

  test("a mixer: two oscillators heard together; noise is not a note", () {
    var two = played([
      mod("k", SynthModuleKind.keys),
      mod("o", SynthModuleKind.osc, inputs: {"pitch": "k.pitch"}),
      mod("p", SynthModuleKind.osc,
          values: {"octave": 1}, inputs: {"pitch": "k.pitch"}),
      mod("m", SynthModuleKind.mixer, inputs: {"a": "o.out", "b": "p.out"}),
      mod("a", SynthModuleKind.amp, inputs: {"in": "m.out"}),
      mod("s", SynthModuleKind.out, inputs: {"in": "a.out"}),
    ]);
    var one = played(basic());
    // Each through the mixer at 0.8, an octave apart: together √2 × 0.8 of
    // one alone.
    expect(rms(two, 0.1, 0.4) / rms(one, 0.1, 0.4),
        closeTo(0.8 * math.sqrt2, 0.03));
    var noise = played([
      mod("n", SynthModuleKind.noise),
      mod("a", SynthModuleKind.amp, inputs: {"in": "n.out"}),
      mod("s", SynthModuleKind.out, inputs: {"in": "a.out"}),
    ]);
    expect(rms(noise, 0.1, 0.4), greaterThan(0.02));
    expect(roughness(noise, 0.1, 0.4), greaterThan(1));
  });

  test("a setting changed as it plays: the note sounding hears it", () {
    var p = SynthPatch(basic(), "s");
    var sampler = Sampler(patch: p);
    sampler.noteOn(69, 100);
    var l = Float32List(4800), r = Float32List(4800);
    sampler.render(l, r, 4800);
    var before = rms(l, 0, 0.1);
    // Louder, wired the same: the same voice, the new level.
    sampler.patch = SynthPatch([
      for (var m in basic())
        m.id == "s" ? m.copyWith(values: {"volume": 0.35}) : m
    ], "s");
    expect(sampler.sounding, 1, reason: "the note goes on");
    l.fillRange(0, 4800, 0);
    r.fillRange(0, 4800, 0);
    sampler.render(l, r, 4800);
    expect(rms(l, 0, 0.1), closeTo(before / 2, before * 0.05));
  });

  /// through is [basic] with [fx] between the amp and the speaker.
  List<SynthModule> through(SynthModule fx) => [
        ...basic().where((m) => m.id != "s"),
        mod(fx.id, fx.kind, values: fx.values, inputs: {"in": "a.out"}),
        mod("s", SynthModuleKind.out, inputs: {"in": "${fx.id}.out"}),
      ];

  test("a delay: the note again, a delay's time later, quieter", () {
    var x = played(
        through(const SynthModule("d", SynthModuleKind.delay,
            values: {"time": 0.2, "feedback": 0.5, "mix": 0.5})),
        seconds: 0.05,
        tail: 1.5);
    var dry = played(basic(), seconds: 0.05, tail: 1.5);
    expect(rms(dry, 0.22, 0.24), lessThan(1e-4), reason: "nothing then dry");
    var first = rms(x, 0.21, 0.24), second = rms(x, 0.41, 0.44);
    expect(first, greaterThan(0.01), reason: "the echo, 0.2 s on");
    expect(second, closeTo(first * 0.5, first * 0.15),
        reason: "the next, at the feedback's level");
  });

  test("a reverb: a tail after the note ends; a scope changes nothing", () {
    var wet = played(
        through(const SynthModule("r", SynthModuleKind.reverb,
            values: {"size": 0.8, "mix": 0.5})),
        seconds: 0.2,
        tail: 2);
    expect(rms(wet, 0.4, 0.7), greaterThan(0.002),
        reason: "the room rings on after the key is let go");
    var seen = played(through(const SynthModule("v", SynthModuleKind.scope)));
    var plain = played(basic());
    expect(rms(seen, 0.1, 0.4), closeTo(rms(plain, 0.1, 0.4), 1e-6));
  });

  test("a note watched: each module's sound, its envelope, until it ends", () {
    var w = PatchWatch(
        SynthPatch([
          ...basic().where((m) => m.id != "a"),
          mod("e", SynthModuleKind.env,
              values: {"a": 0.1, "r": 0.1}, inputs: {"gate": "k.gate"}),
          mod("a", SynthModuleKind.amp,
              inputs: {"in": "o.out", "gain": "e.env"}),
        ], "s"),
        69);
    w.advance(2400);
    var mid = w.valueOf("e");
    expect(mid, closeTo(0.5, 0.05), reason: "half way up a 0.1 s attack");
    var osc = w.waveOf("o")!;
    var crossings = 0;
    for (var i = 1; i < osc.length; i++) {
      if (osc[i - 1] < 0 && osc[i] >= 0) crossings++;
    }
    // 1024 samples of 440 Hz: about nine and a half cycles.
    expect(crossings, inInclusiveRange(9, 10));
    expect(w.levelOf("s"), greaterThan(0), reason: "the speaker heard");
    w.release();
    w.advance(48000);
    expect(w.done, isTrue);
  });

  test("a knob turned as it plays: lanes, stepped between, kept", () {
    var p = SynthPatch(basic(), "s").withLanes({
      "o/level": [0, 1, 1],
      "o/detune": [10]
    }, 2);
    var half = p.at(0.25);
    expect(half.byId("o")!.value("level"), closeTo(0.5, 1e-9));
    expect(half.byId("o")!.value("detune"), 10, reason: "one value: held");
    expect(p.at(5).byId("o")!.value("level"), 1, reason: "past the end");
    expect(p.at(0.25).wiring, p.wiring);
    var back = SynthPatch.fromJson(p.toJson())!;
    expect(back.lanes["o/level"], [0, 1, 1]);
    expect(back.laneRate, 2);
  });

  test("rendered with a filter's cutoff swept: dull first, bright after", () {
    var mods = [
      mod("k", SynthModuleKind.keys),
      mod("o", SynthModuleKind.osc,
          choices: {"wave": "sawtooth"}, inputs: {"pitch": "k.pitch"}),
      mod("f", SynthModuleKind.filter,
          values: {"cutoff": 300, "res": 0.1}, inputs: {"in": "o.out"}),
      mod("a", SynthModuleKind.amp, inputs: {"in": "f.out"}),
      mod("s", SynthModuleKind.out, inputs: {"in": "a.out"}),
    ];
    var part = InstrumentPart(
        sound: InstrumentSound.patch,
        patch: SynthPatch(mods, "s").withLanes({
          "f/cutoff": [for (var i = 0; i <= 10; i++) i < 5 ? 300.0 : 12000.0]
        }, 10),
        notes: [MidiNote(45, 0, 1, 100)]);
    var x = renderPart(part, null).$1;
    expect(roughness(x, 0.1, 0.4), lessThan(roughness(x, 0.6, 0.9) * 0.5));
  });
}
