import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/pitch.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/media/mix/mix_graph.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/pitch_edit.dart';
import 'package:bruig/plugin_system/canvas/ui/pitch_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_pitch_test.dart is a voice's pitch: heard by YIN, and pulled to a
// note by Auto-tune's PSOLA.

/// tone is [seconds] of [hz] with its first few harmonics -- more like a
/// voice than a sine.
Float32List tone(double hz, double seconds) {
  var n = (seconds * 48000).round();
  var x = Float32List(n);
  for (var i = 0; i < n; i++) {
    var t = i / 48000;
    x[i] = 0.3 * math.sin(2 * math.pi * hz * t) +
        0.15 * math.sin(4 * math.pi * hz * t) +
        0.08 * math.sin(6 * math.pi * hz * t);
  }
  return x;
}

/// through runs [x] through [p], a block at a time, and answers what came
/// out.
Float32List through(AutoTune p, Float32List x) {
  var l = Float32List.fromList(x), r = Float32List.fromList(x);
  for (var at = 0; at < l.length; at += 512) {
    var n = math.min(512, l.length - at);
    p.process(Float32List.sublistView(l, at, at + n),
        Float32List.sublistView(r, at, at + n), n);
  }
  return l;
}

double pitchAt(Float32List x, double second) {
  var from = (second * 48000).round();
  return detectPitch(Float32List.sublistView(x, from, from + 2048))!.hz;
}

/// _fullSearch is detectPitch as it was, working out every lag before
/// looking for the dip: what its early stop must agree with exactly.
PitchReading? _fullSearch(Float32List x) {
  const rate = 48000.0, minHz = 60.0, maxHz = 1200.0, threshold = 0.15;
  var maxLag = math.min((rate / minHz).floor(), x.length ~/ 2);
  var minLag = math.max(2, (rate / maxHz).floor());
  if (maxLag <= minLag + 2) return null;
  var w = x.length - maxLag;
  var energy = 0.0;
  for (var i = 0; i < w; i++) {
    energy += x[i] * x[i];
  }
  if (energy / w < 1e-7) return null;
  var d = Float64List(maxLag + 1);
  for (var tau = 1; tau <= maxLag; tau++) {
    var sum = 0.0;
    for (var i = 0; i < w; i++) {
      var diff = x[i] - x[i + tau];
      sum += diff * diff;
    }
    d[tau] = sum;
  }
  var cmnd = Float64List(maxLag + 1)..[0] = 1;
  var running = 0.0;
  for (var tau = 1; tau <= maxLag; tau++) {
    running += d[tau];
    cmnd[tau] = running == 0 ? 1 : d[tau] * tau / running;
  }
  var tau = -1;
  for (var t = minLag; t < maxLag; t++) {
    if (cmnd[t] < threshold) {
      while (t + 1 < maxLag && cmnd[t + 1] < cmnd[t]) {
        t++;
      }
      tau = t;
      break;
    }
  }
  if (tau < 0) return null;
  var better = tau.toDouble();
  if (tau > 1 && tau < maxLag) {
    var a = cmnd[tau - 1], b = cmnd[tau], c = cmnd[tau + 1];
    var den = a + c - 2 * b;
    if (den.abs() > 1e-12) better = tau + 0.5 * (a - c) / den;
  }
  return (hz: rate / better, clarity: (1 - cmnd[tau]).clamp(0.0, 1.0));
}

void main() {
  // Ken's systems review, 2026-11-08: it stops at the dip now, rather than
  // working out every lag -- and must hear exactly what it heard before.
  test("stopped at its dip, it hears what the full search heard", () {
    var r = math.Random(3);
    for (var trial = 0; trial < 300; trial++) {
      var hz = 50 + r.nextDouble() * 1400;
      var noise = r.nextDouble() * 0.6;
      var x = Float32List(2048);
      for (var i = 0; i < x.length; i++) {
        x[i] = math.sin(2 * math.pi * hz * i / 48000) * 0.5 +
            math.sin(2 * math.pi * hz * 2 * i / 48000) * 0.2 +
            (r.nextDouble() - 0.5) * noise;
      }
      var fast = detectPitch(x), full = _fullSearch(x);
      expect(fast?.hz, full?.hz, reason: "$hz Hz, noise $noise");
      expect(fast?.clarity, full?.clarity);
    }
  });

  test("YIN hears a note's pitch, and nothing in silence", () {
    for (var hz in [82.4, 110.0, 220.0, 440.0, 880.0]) {
      var p = detectPitch(Float32List.sublistView(tone(hz, 0.1), 0, 2048))!;
      expect(p.hz, closeTo(hz, hz * 0.005), reason: "$hz");
      expect(p.clarity, greaterThan(0.8));
    }
    expect(detectPitch(Float32List(2048)), isNull);
  });

  test("a note is snapped to the scale's nearest", () {
    expect(snapNote(69.4, 0, const []), 69, reason: "chromatic: A");
    // C major: G sharp is between G and A, and goes to the nearer.
    expect(snapNote(67.9, 0, const [0, 2, 4, 5, 7, 9, 11]), 67);
    expect(snapNote(68.6, 0, const [0, 2, 4, 5, 7, 9, 11]), 69);
  });

  test("Auto-tune pulls a sharp A down onto A", () {
    // 450Hz is 39 cents sharp of A440.
    var tuned = through(
        AutoTune(const MixDevice(DeviceKind.autoTune,
            values: {"retune": 0, "amount": 1})),
        tone(450, 1.5));
    expect(pitchAt(tuned, 1.0), closeTo(440, 3));
  });

  test("with no amount it leaves the pitch alone, and keeps the level", () {
    var input = tone(450, 1.5);
    var out = through(
        AutoTune(const MixDevice(DeviceKind.autoTune, values: {"amount": 0})),
        tone(450, 1.5));
    expect(pitchAt(out, 1.0), closeTo(450, 3));
    double rms(Float32List x, int from) {
      var s = 0.0;
      for (var i = from; i < from + 4800; i++) {
        s += x[i] * x[i];
      }
      return math.sqrt(s / 4800);
    }

    expect(
        rms(out, 48000), closeTo(rms(input, 48000), rms(input, 48000) * 0.15));
  });

  test("the retune time eases it in", () {
    var slow = through(
        AutoTune(const MixDevice(DeviceKind.autoTune,
            values: {"retune": 400, "amount": 1})),
        tone(450, 2));
    // Early on still near where it was; later on the note.
    expect(pitchAt(slow, 0.1), greaterThan(445));
    expect(pitchAt(slow, 1.8), closeTo(440, 3));
  });

  // The prototype's Vibrato: the singer's own vibrato kept, as sung or not
  // at all, while the note under it goes onto the scale.
  test("Vibrato keeps the singer's vibrato round the note it is tuned to", () {
    // A sharp A (450Hz), sung with a third of a semitone of vibrato at 5Hz.
    Float32List sung(double seconds) {
      var n = (seconds * 48000).round();
      var x = Float32List(n);
      var phase = 0.0;
      for (var i = 0; i < n; i++) {
        var t = i / 48000;
        var hz = 450 * math.pow(2, 0.33 * math.sin(2 * math.pi * 5 * t) / 12);
        phase += 2 * math.pi * hz / 48000;
        x[i] = 0.5 * math.sin(phase);
      }
      return x;
    }

    List<double> heard(double vibrato) {
      var out = through(
          AutoTune(MixDevice(DeviceKind.autoTune, values: {
            "retune": 0,
            "amount": 1,
            "humanise": 0,
            "vibrato": vibrato,
          })),
          sung(2));
      return [for (var t = 1.0; t < 1.4; t += 0.025) pitchAt(out, t)];
    }

    double spread(List<double> hz) => hz.reduce(math.max) - hz.reduce(math.min);
    double mean(List<double> hz) => hz.reduce((a, b) => a + b) / hz.length;
    var flat = heard(0), kept = heard(1);
    expect(mean(flat), closeTo(440, 4), reason: "onto A");
    expect(spread(flat), lessThan(6), reason: "its vibrato taken out");
    expect(mean(kept), closeTo(440, 5), reason: "still round A");
    expect(spread(kept), greaterThan(10), reason: "its vibrato kept");
  });

  // The prototype's Auto-tune "Notes to MIDI": what was sung, played by a
  // new MIDI channel from where the recording starts, in the key.
  test("Notes to MIDI makes a MIDI channel of what was sung", () {
    var c = CanvasController(
        const CanvasDocument(frames: 200, elements: [
          AudioElement(ElementBase(id: "v", name: "Vocal"),
              clip: MediaClip(at: 24, timed: true, playlist: [
                MediaSource(
                    assetId: "t",
                    length: 3,
                    start: 0.5,
                    pitch: PitchEdit("t", notes: [
                      PitchNote(0.6, 1.0, 60.3),
                      PitchNote(1.0, 1.5, 61.2),
                    ])),
              ])),
        ]),
        audioEngine: FakeEngine({"t": 3}));
    addTearDown(c.dispose);
    expect(c.notesToMidi("v", root: 0, steps: const [0, 2, 4, 5, 7, 9, 11]),
        isNull);
    var made = c.document.elements.whereType<AudioElement>().last;
    expect(made.instrument, isNotNull);
    expect(made.clip.at, 24, reason: "where the recording starts");
    var notes = made.instrument!.notes;
    expect([for (var n in notes) n.key], [60, 62], reason: "in C major");
    expect(notes[0].start, closeTo(0.1, 1e-9));
    expect(notes[1].start, closeTo(0.5, 1e-9));
    expect(c.notesToMidi("nothing"), isNotNull);
  });

  test("a tuner on a channel hears its note through the mix", () {
    var g = MixGraph()
      ..setMaster(const MasterMix(limiter: false))
      ..setChannel(
          "a", const ChannelMix(devices: [MixDevice(DeviceKind.tuner)]));
    var x = tone(196, 0.5); // G3
    for (var at = 0; at + 512 <= x.length; at += 512) {
      g.begin(512);
      var (l, r) = g.input("a", 512);
      l.setRange(0, 512, x, at);
      r.setRange(0, 512, x, at);
      g.finish(Float32List(512), Float32List(512), 512);
    }
    expect(g.pitchOf("a")!.hz, closeTo(196, 1));
    expect(g.pitchOf("b"), isNull);
  });

  testWidgets("the Tuner shows the note, and how far off", (tester) async {
    var engine = FakeEngine({"t": 2});
    var c = CanvasController(
        CanvasDocument(frames: 100, elements: [
          AudioElement(const ElementBase(id: "a", name: "Voice"),
              clip: const MediaClip(
                  playlist: [MediaSource(assetId: "t", length: 2)],
                  timed: true,
                  mix: ChannelMix(devices: [MixDevice(DeviceKind.tuner)]))),
        ]),
        audioEngine: engine);
    c.openEffects("a");
    // The engine started, as playing does, and hearing 445Hz: A, sharp.
    await c.audio.ready();
    engine.heardPitch = (hz: 445.0, clarity: 0.95);
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: Align(
                  alignment: Alignment.bottomCenter,
                  child: CanvasMixer.effects(
                      controller: c,
                      height: 380,
                      onResize: (_) {},
                      onClose: () {})))),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text("A4"), findsOneWidget);
    expect(find.textContaining("+20 cents"), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
