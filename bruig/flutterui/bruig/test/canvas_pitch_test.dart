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

void main() {
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
