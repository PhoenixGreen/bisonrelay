import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/media/synth/sampler.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/plugin_system/canvas/ui/instrument_editor.dart'
    show envelopePoints;
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_instrument_shape_test.dart is how an instrument plays its sound
// (instrument_shape.dart), as the sampler does it: its own volume envelope,
// a filter and its envelope, the LFO, one voice or many, glides, the bend
// wheel's range, tuning and the velocity curve.

const rate = 48000;

/// play renders [s] for [seconds], doing [at] (seconds in, and what) as it
/// goes, and gives the left side.
Float32List play(Sampler s, double seconds,
    [Map<double, void Function()> at = const {}]) {
  var n = (seconds * rate).round();
  var l = Float32List(n), r = Float32List(n);
  var times = at.keys.toList()..sort();
  var done = 0;
  for (var t in [...times, seconds]) {
    var to = math.min(n, (t * rate).round());
    if (to > done) {
      var bl = Float32List(to - done), br = Float32List(to - done);
      s.render(bl, br, to - done);
      l.setRange(done, to, bl);
      r.setRange(done, to, br);
      done = to;
    }
    at[t]?.call();
  }
  return l;
}

double rms(Float32List x, double from, double to) {
  var a = (from * rate).round(), b = math.min(x.length, (to * rate).round());
  var sum = 0.0;
  for (var i = a; i < b; i++) {
    sum += x[i] * x[i];
  }
  return math.sqrt(sum / math.max(1, b - a));
}

/// pitch is the strongest period of [x] around [at] seconds, as hertz,
/// looked for between [lo] and [hi].
double pitch(Float32List x, double at, {double lo = 150, double hi = 700}) {
  var a = (at * rate).round();
  var best = 0, bestC = -1e9;
  for (var lag = (rate / hi).floor(); lag <= (rate / lo).ceil(); lag++) {
    var c = 0.0;
    for (var i = a; i < a + 2400; i++) {
      c += x[i] * x[i + lag];
    }
    if (c > bestC) {
      bestC = c;
      best = lag;
    }
  }
  return rate / best;
}

Sampler sampler(InstrumentShape shape) =>
    Sampler(look: InstrumentLook.keyboard, shape: shape);

void main() {
  group("the shape", () {
    test("kept; as it is by default, nothing, and the same part as before", () {
      const notes = [MidiNote(60, 0, 1)];
      const plain = InstrumentPart(notes: notes);
      expect(plain.toJson().containsKey("shape"), isFalse);
      expect(plain.copyWith(shape: const InstrumentShape()).signature,
          plain.signature,
          reason: "a part from before keeps its file");
      var shaped = plain.copyWith(
          shape: const InstrumentShape(
              envelope: true,
              attack: 0.3,
              filter: SynthFilter.highPass,
              lfoTarget: LfoTarget.volume,
              mode: VoiceMode.legato,
              voices: 3,
              tune: -20));
      expect(shaped.signature, isNot(plain.signature));
      var back = InstrumentPart.fromJson(shaped.toJson());
      expect(back.shape, shaped.shape);
      expect(back.signature, shaped.signature);
    });

    test("held within its ranges", () {
      var s = const InstrumentShape()
          .copyWith(voices: 500, cutoff: 1, resonance: 3, attack: -1);
      expect((s.voices, s.cutoff, s.resonance, s.attack),
          (InstrumentShape.maxVoices, 20.0, 1.0, 0.001));
    });

    test("the velocity curve: harder needs more, lighter less", () {
      const asPlayed = InstrumentShape();
      expect(asPlayed.velocity(64), 64);
      expect(
          const InstrumentShape(velocityCurve: 1).velocity(64), lessThan(40));
      expect(const InstrumentShape(velocityCurve: -1).velocity(64),
          greaterThan(90));
      expect(const InstrumentShape(velocityCurve: 1).velocity(127), 127);
    });
  });

  group("played", () {
    test("its own envelope: rising over its attack, gone after its release",
        () {
      var s = sampler(const InstrumentShape(
          envelope: true, attack: 0.3, decay: 1, sustain: 1, release: 0.1));
      var x = play(
          s, 1.2, {0.0: () => s.noteOn(60, 100), 0.8: () => s.noteOff(60)});
      expect(rms(x, 0.0, 0.05), lessThan(rms(x, 0.3, 0.35) * 0.4),
          reason: "still rising");
      expect(rms(x, 1.0, 1.2), 0, reason: "released and gone");
      expect(s.sounding, 0);
    });

    test("a low-pass takes away what is over it, opened by its envelope", () {
      // C6: its partials all over a 200Hz corner.
      var s0 = sampler(const InstrumentShape());
      var open = play(s0, 0.3, {0.0: () => s0.noteOn(84, 100)});
      var s1 = sampler(const InstrumentShape(
          filter: SynthFilter.lowPass, cutoff: 200, resonance: 0));
      var shut = play(s1, 0.3, {0.0: () => s1.noteOn(84, 100)});
      expect(rms(shut, 0.05, 0.3), lessThan(rms(open, 0.05, 0.3) * 0.1));
      // Its envelope opens it four octaves at the note's start, closing
      // over a tenth of a second.
      var s2 = sampler(const InstrumentShape(
          filter: SynthFilter.lowPass,
          cutoff: 200,
          resonance: 0,
          filterEnvelope: 1,
          filterDecay: 0.1));
      var swept = play(s2, 0.3, {0.0: () => s2.noteOn(84, 100)});
      expect(rms(swept, 0.0, 0.02), greaterThan(rms(shut, 0.0, 0.02) * 3));
      expect(rms(swept, 0.2, 0.3), closeTo(rms(shut, 0.2, 0.3), 0.01));
    });

    test("a high-pass keeps the top: a low note mostly gone", () {
      var s0 = sampler(const InstrumentShape());
      var open = play(s0, 0.3, {0.0: () => s0.noteOn(36, 100)});
      var s1 = sampler(const InstrumentShape(
          filter: SynthFilter.highPass, cutoff: 2000, resonance: 0));
      var cut = play(s1, 0.3, {0.0: () => s1.noteOn(36, 100)});
      expect(rms(cut, 0.05, 0.3), lessThan(rms(open, 0.05, 0.3) * 0.2));
    });

    test("the LFO on the volume swings it, on the pitch bends it", () {
      var s = sampler(const InstrumentShape(
          lfoTarget: LfoTarget.volume, lfoDepth: 1, lfoRate: 4));
      var x = play(s, 0.5, {0.0: () => s.noteOn(60, 100)});
      // Quiet at a quarter-cycle's trough, loud at its crest.
      var levels = [
        for (var t = 0.0; t < 0.45; t += 0.025) rms(x, t, t + 0.02)
      ];
      expect(levels.reduce(math.min), lessThan(levels.reduce(math.max) * 0.3));
      var p = sampler(const InstrumentShape(lfoDepth: 1, lfoRate: 2));
      var y = play(p, 0.5, {0.0: () => p.noteOn(69, 100)});
      // A semitone over A at the top of its swing (an eighth of a second).
      expect(pitch(y, 0.11), closeTo(440 * math.pow(2, 1 / 12), 8));
    });

    test("the bend wheel bends as far as its range; tune moves every note", () {
      var s = sampler(const InstrumentShape(bendRange: 12));
      s.control(MidiControl.pitchBend, 1);
      var x = play(s, 0.3, {0.0: () => s.noteOn(57, 100)});
      expect(pitch(x, 0.1), closeTo(440, 6), reason: "an octave over A3");
      var t = sampler(const InstrumentShape(tune: 100));
      var y = play(t, 0.3, {0.0: () => t.noteOn(57, 100)});
      expect(pitch(y, 0.1), closeTo(233.1, 4), reason: "a semitone up");
    });

    test("voices: no more notes at once than it has", () {
      var s = sampler(const InstrumentShape(voices: 2));
      play(s, 0.1, {
        0.0: () => s
          ..noteOn(60, 100)
          ..noteOn(64, 100)
          ..noteOn(67, 100)
          ..noteOn(72, 100),
      });
      expect(s.sounding, 2);
    });

    test("legato: one voice, moved to the new key and back on letting go", () {
      var s = sampler(const InstrumentShape(mode: VoiceMode.legato, glide: 0));
      var x = play(s, 0.9, {
        0.0: () => s.noteOn(57, 100), // A3
        0.3: () => s.noteOn(64, 100), // E4
        0.6: () => s.noteOff(64),
      });
      expect(s.sounding, 1, reason: "the one voice, moved");
      expect(pitch(x, 0.1), closeTo(220, 4));
      expect(pitch(x, 0.4), closeTo(329.6, 6));
      expect(pitch(x, 0.7), closeTo(220, 4), reason: "back to A, still held");
    });

    test("mono glides: started afresh, sliding from the last note", () {
      var s = sampler(const InstrumentShape(mode: VoiceMode.mono, glide: 0.4));
      var x = play(s, 1.2, {
        0.0: () => s.noteOn(57, 100), // A3
        0.3: () => s.noteOn(69, 100), // A4
      });
      var halfway = pitch(x, 0.36, lo: 200, hi: 480);
      expect(halfway, inExclusiveRange(240, 420), reason: "on its way");
      expect(pitch(x, 1.0, lo: 300, hi: 700), closeTo(440, 8),
          reason: "there by the end of its glide");
      // Poly does not glide.
      var p = sampler(const InstrumentShape(glide: 0.4));
      var y = play(p, 0.6, {
        0.0: () => p.noteOn(69, 100),
      });
      expect(pitch(y, 0.06, lo: 300, hi: 700), closeTo(440, 8));
    });
  });

  group("the editor", () {
    CanvasController make() => CanvasController(
        CanvasDocument(frames: 100, elements: [
          AudioElement(const ElementBase(id: "p", name: "Keys"),
              clip: const MediaClip(timed: true),
              instrument: const InstrumentPart()),
        ]),
        audioEngine: FakeEngine({}));

    Future<void> show(WidgetTester tester, CanvasController c,
        {double scale = 1,
        double width = 1600,
        ValueNotifier<double>? height}) async {
      height ??= ValueNotifier(420);
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ],
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: Scaffold(
                body: Align(
                    alignment: Alignment.bottomCenter,
                    child: ValueListenableBuilder(
                        valueListenable: height,
                        builder: (context, h, _) => ListenableBuilder(
                            listenable: c,
                            builder: (context, _) => CanvasMixer.effects(
                                controller: c,
                                height: h,
                                onResize: (_) {},
                                onClose: () {})))))),
      ));
      await tester.pump();
    }

    InstrumentShape shape(CanvasController c) =>
        (c.document.elements.single as AudioElement).instrument!.shape;

    /// centre scrolls [key] to the middle of the chain, clear of its edges.
    Future<void> centre(WidgetTester tester, String key) async {
      await Scrollable.ensureVisible(tester.element(find.byKey(ValueKey(key))),
          alignment: 0.5);
      await tester.pump();
    }

    /// pick presses a choice, as the editor's joined buttons have them.
    Future<void> pick(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pump();
    }

    testWidgets("its card in the chain opens it; its settings are set there",
        (tester) async {
      var c = make();
      addTearDown(c.dispose);
      c.openEffects("p");
      await show(tester, c);
      expect(find.byKey(const ValueKey("instrumentEdit")), findsOneWidget,
          reason: "the instrument's card, after its MIDI effects");
      await tester.ensureVisible(find.byKey(const ValueKey("instrumentEdit")));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("instrumentEdit")));
      await tester.pump();
      expect(c.instrumentShown, isTrue);
      for (var card in ["Envelope", "Filter", "Lfo", "Voices"]) {
        expect(find.byKey(ValueKey("instrument${card}Card")), findsOneWidget);
      }
      // Its own envelope, then an attack turned up.
      await pick(tester, "instrumentEnvelope-own");
      expect(shape(c).envelope, isTrue);
      var attack = shape(c).attack;
      await tester
          .ensureVisible(find.byKey(const ValueKey("instrumentAttack")));
      await tester.pump();
      await tester.drag(
          find.byKey(const ValueKey("instrumentAttack")), const Offset(0, -60));
      await tester.pump();
      expect(shape(c).attack, greaterThan(attack));
      // Its peak dragged further out: a longer attack still.
      attack = shape(c).attack;
      await centre(tester, "instrumentEnvelopeGraph");
      var graph =
          tester.getRect(find.byKey(const ValueKey("instrumentEnvelopeGraph")));
      var (_, _, peak, _, _, _) = envelopePoints(shape(c), graph.size);
      await tester.dragFrom(graph.topLeft + peak, const Offset(30, 0),
          kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(shape(c).attack, greaterThan(attack));
      // A low-pass, its corner dragged across its curve.
      await pick(tester, "instrumentFilter-lowPass");
      expect(shape(c).filter, SynthFilter.lowPass);
      var cutoff = shape(c).cutoff;
      await centre(tester, "instrumentFilterGraph");
      var curve =
          tester.getRect(find.byKey(const ValueKey("instrumentFilterGraph")));
      await tester.dragFrom(curve.center, const Offset(-40, 0),
          kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(shape(c).cutoff, lessThan(cutoff));
      // Legato; the LFO on the filter.
      await pick(tester, "instrumentVoiceMode-legato");
      expect(shape(c).mode, VoiceMode.legato);
      await pick(tester, "instrumentLfoTarget-filter");
      expect(shape(c).lfoTarget, LfoTarget.filter);
      // Each one step to undo.
      c.undo();
      expect(shape(c).lfoTarget, LfoTarget.pitch);
      // Back to the sound as it is.
      await tester.ensureVisible(find.byKey(const ValueKey("instrumentPlain")));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("instrumentPlain")));
      await tester.pump();
      expect(shape(c).plain, isTrue);
      expect(tester.takeException(), isNull);
      // The knobs' double-click waits out its moment.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("the Chain's Instrument tab opens it", (tester) async {
      var c = make();
      addTearDown(c.dispose);
      c.showInstrument("p");
      expect(c.instrumentShown, isTrue);
      expect(c.pitchShown || c.pianoRollShown || c.clipEditorShown, isFalse);
      c.openPianoRoll("p");
      expect(c.instrumentShown, isFalse, reason: "one editor at a time");
      c.showInstrument("p");
      c.closeEditor();
      expect(c.instrumentShown, isFalse);
    });

    testWidgets("it fits, at every size and text size", (tester) async {
      var failures = <String>[];
      for (var scale in [1.0, 1.25, 1.5]) {
        for (var width in [900.0, 1600.0]) {
          var height = ValueNotifier(200.0);
          var c = make();
          c.showInstrument("p");
          c.setInstrumentShape("p",
              (s) => s.copyWith(envelope: true, filter: SynthFilter.bandPass));
          await show(tester, c, scale: scale, width: width, height: height);
          for (var h = 200.0; h <= 620; h += 30) {
            height.value = h;
            await tester.pump();
            if (tester.takeException() case var e?) {
              failures.add("$width $h ${scale}x: "
                  "${e.toString().split("\n").first}");
            }
          }
          await tester.pumpWidget(const SizedBox());
          c.dispose();
        }
      }
      expect(failures, isEmpty);
    });
  });
}
