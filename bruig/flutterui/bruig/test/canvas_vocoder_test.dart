import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/media/mix/mix_graph.dart';
import 'package:bruig/plugin_system/canvas/media/mix/pitch.dart';
import 'package:bruig/plugin_system/canvas/media/mix/vocoder.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
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

// canvas_vocoder_test.dart is the Vocoder: a voice's bands laid onto a
// carrier -- hiss, a buzz, the voice's own pitch, or another channel --
// measured rather than listened to.

const int rate = 48000;

/// tone is [seconds] of a sine at [hz], or a saw when [saw].
Float32List tone(double hz, double seconds,
    {double level = 0.3, bool saw = false}) {
  var n = (seconds * rate).round();
  return Float32List.fromList([
    for (var i = 0; i < n; i++)
      saw
          ? level * (2 * ((i * hz / rate) % 1) - 1)
          : level * math.sin(2 * math.pi * hz * i / rate),
  ]);
}

/// through runs [x] through [p] in blocks of 512, both sides alike.
Float32List through(DeviceProcessor p, Float32List x) {
  var out = Float32List(x.length);
  for (var at = 0; at < x.length; at += 512) {
    var n = math.min(512, x.length - at);
    var l = Float32List.fromList(x.sublist(at, at + n));
    var r = Float32List.fromList(l);
    p.process(l, r, n);
    out.setRange(at, at + n, l);
  }
  return out;
}

double rms(Float32List x, [int from = 0]) {
  var sum = 0.0;
  for (var i = from; i < x.length; i++) {
    sum += x[i] * x[i];
  }
  return math.sqrt(sum / (x.length - from));
}

/// at is how strong [x] is at [hz]: Goertzel's single bin.
double at(Float32List x, double hz, [int from = 0]) {
  var w = 2 * math.pi * hz / rate, k = 2 * math.cos(w);
  var s1 = 0.0, s2 = 0.0;
  for (var i = from; i < x.length; i++) {
    var s = x[i] + k * s1 - s2;
    s2 = s1;
    s1 = s;
  }
  return math.sqrt(s1 * s1 + s2 * s2 - k * s1 * s2) / (x.length - from);
}

MixDevice vocoder(Map<String, double> values, {String source = ""}) =>
    MixDevice(DeviceKind.vocoder, values: values, source: source);

void main() {
  group("the model", () {
    test("a carrier channel is kept in the file, and only heard when chosen",
        () {
      var d =
          vocoder({"carrier": carrierFromChannel.toDouble()}, source: "synth");
      var back = MixDevice.fromJson(d.toJson())!;
      expect(back, d);
      expect(back.source, "synth");
      expect(back.sidechain, "synth");
      expect(back.withValue("bands", 12).source, "synth",
          reason: "a knob turned keeps the channel");
      expect(back.switched(false).sidechain, isNull,
          reason: "switched off, it hears nothing");
      expect(back.withValue("carrier", 0).sidechain, isNull,
          reason: "a noise carrier needs no channel");
      expect(const MixDevice(DeviceKind.vocoder).toJson().containsKey("source"),
          isFalse);
    });

    test("Note is only shown for a buzz on one note", () {
      var note = DeviceKind.vocoder.param("note");
      expect(paramShown(vocoder({"carrier": 1}), note), isTrue);
      for (var c in [0.0, 2.0, 3.0]) {
        expect(paramShown(vocoder({"carrier": c}), note), isFalse);
      }
      expect(note.reading(60), "C4");
      expect(DeviceKind.vocoder.param("formant").reading(-3), "−3.0 st");
    });
  });

  group("the sound", () {
    test("silence stays silent", () {
      var out = through(Vocoder(vocoder({"carrier": 0})), Float32List(9600));
      expect(rms(out), lessThan(1e-6));
    });

    test("a noise carrier says the voice's tone where the voice has it", () {
      var voice = tone(1000, 1);
      var out = through(Vocoder(vocoder({"carrier": 0, "unvoiced": 0})), voice);
      var from = rate ~/ 4;
      expect(at(out, 1000, from), greaterThan(4 * at(out, 300, from)));
      expect(at(out, 1000, from), greaterThan(4 * at(out, 4000, from)));
      var db = gainToDb(rms(out, from) / rms(voice, from));
      expect(db, inInclusiveRange(-12, 6),
          reason: "about as loud as the voice: $db dB");
    });

    test("a buzz carrier is pitched at its note, whatever the voice", () {
      // A voice on A3; the buzz on C3, 130.8 Hz.
      var out = through(
          Vocoder(vocoder({"carrier": 1, "note": 48, "unvoiced": 0})),
          tone(220, 1, saw: true));
      var heard = detectPitch(Float32List.fromList(out.sublist(24000, 26048)));
      expect(heard, isNotNull);
      expect(heard!.hz, closeTo(130.8, 2));
    });

    test("following the voice, the buzz takes its pitch", () {
      var out = through(Vocoder(vocoder({"carrier": 2, "unvoiced": 0})),
          tone(220, 1, saw: true));
      var heard = detectPitch(Float32List.fromList(out.sublist(30000, 32048)));
      expect(heard, isNotNull);
      expect(heard!.hz, closeTo(220, 4));
    });

    test("Mix at none leaves the voice as it was", () {
      var voice = tone(440, 0.2);
      var out = through(Vocoder(vocoder({"mix": 0})), voice);
      for (var i = 0; i < voice.length; i += 997) {
        expect(out[i], closeTo(voice[i], 1e-6));
      }
    });
  });

  group("a channel as the carrier", () {
    /// run is a second of a voice on "voice", vocoded, and a tone on
    /// "synth" -- muted, so only the vocoder is heard.
    Float32List run(MixDevice device) {
      var g = MixGraph()
        ..setMaster(const MasterMix(limiter: false))
        ..setReturns(const [])
        ..setChannel("voice", ChannelMix(devices: [device]))
        ..setChannel("synth", const ChannelMix(mute: true));
      var voice = tone(220, 1, saw: true), synth = tone(330, 1, saw: true);
      var out = Float32List(voice.length);
      for (var at = 0; at < voice.length; at += 512) {
        var n = math.min(512, voice.length - at);
        g.begin(n);
        var (vl, vr) = g.input("voice", n);
        var (sl, sr) = g.input("synth", n);
        for (var i = 0; i < n; i++) {
          vl[i] += voice[at + i];
          vr[i] += voice[at + i];
          sl[i] += synth[at + i];
          sr[i] += synth[at + i];
        }
        var l = Float32List(n), r = Float32List(n);
        g.finish(l, r, n);
        out.setRange(at, at + n, l);
      }
      return out;
    }

    test("a muted channel carries, at its own pitch", () {
      var out = run(vocoder({"carrier": 3, "unvoiced": 0}, source: "synth"));
      expect(rms(out, 24000), greaterThan(0.01));
      var heard = detectPitch(Float32List.fromList(out.sublist(24000, 26048)));
      expect(heard, isNotNull);
      expect(heard!.hz, closeTo(330, 5));
    });

    test("with no channel chosen, there is nothing to carry", () {
      var out = run(vocoder({"carrier": 3, "unvoiced": 0}));
      expect(rms(out, 24000), lessThan(1e-4));
    });
  });

  group("the device", () {
    for (var scale in [1.0, 1.5]) {
      testWidgets("its carrier channel is chosen beside its knobs, at $scale",
          (tester) async {
        var c = CanvasController(
            CanvasDocument(frames: 100, elements: [
              for (var (id, name) in [("a", "Voice"), ("b", "Synth")])
                AudioElement(ElementBase(id: id, name: name),
                    clip: const MediaClip(
                        playlist: [MediaSource(assetId: "t", length: 2)],
                        timed: true)),
            ]),
            audioEngine: FakeEngine({"t": 2}));
        c.setDevicesOf("a", [const MixDevice(DeviceKind.vocoder)]);
        c.openEffects("a", device: "dev0");
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeNotifier>(
                create: (c) => ThemeNotifier(doLoad: false)),
            ChangeNotifierProvider<SnackBarModel>(
                create: (c) => SnackBarModel()),
          ],
          child: MaterialApp(
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: Scaffold(
                  body: ListenableBuilder(
                      listenable: c,
                      builder: (context, _) => Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                CanvasMixer.effects(
                                    controller: c,
                                    height: 360,
                                    onResize: (_) {},
                                    onClose: () {}),
                              ])))),
        ));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        var source = find.byKey(const ValueKey("deviceSource-0"));
        var note = find.byKey(const ValueKey("device-0-note"));
        // A buzz: its note, and no channel.
        expect(note, findsOneWidget);
        expect(source, findsNothing);
        c.setDevicesOf("a", [
          const MixDevice(DeviceKind.vocoder)
              .withValue("carrier", carrierFromChannel.toDouble())
        ]);
        await tester.pump();
        expect(note, findsNothing, reason: "a channel carries its own notes");
        expect(source, findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(source);
        await tester.pump(const Duration(milliseconds: 500));
        // Every channel but its own.
        expect(find.widgetWithText(DropdownMenuItem<String>, "Voice"),
            findsNothing);
        expect(find.widgetWithText(DropdownMenuItem<String>, "Synth"),
            findsOneWidget);
        await tester.tap(find.text("Synth").last);
        await tester.pump(const Duration(milliseconds: 500));
        expect(c.devicesOf("a").single.sidechain, "b");
        expect(tester.takeException(), isNull);
      });
    }
  });
}
