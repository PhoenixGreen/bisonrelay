import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/media/midi_input.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/midi_effects.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart'
    show DeviceKnob;
import 'package:bruig/plugin_system/canvas/ui/motion_cards.dart'
    show StudioDrop;
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';
import 'canvas_chain_helpers.dart';

// canvas_midi_channel_test.dart is the rest of a MIDI channel: where its
// notes come from (From), when it plays them (Monitor), the sustain pedal,
// and its MIDI effects -- on the keys played live, and on its part played
// into a file. Also the empty channels the + adds.

AudioElement keys(String id,
        {List<MidiEffect> effects = const [],
        MidiMonitor monitor = MidiMonitor.auto,
        String input = "",
        List<MidiNote> notes = const []}) =>
    AudioElement(ElementBase(id: id, name: id),
        clip: const MediaClip(timed: true),
        instrument: InstrumentPart(
            effects: effects, monitor: monitor, input: input, notes: notes));

void main() {
  group("MIDI effects on notes", () {
    test("a chord is built on each key, and kept to the scale", () {
      var chord = const MidiEffect(MidiEffectKind.chord);
      expect([for (var (k, _) in liveKeys([chord], 60, 90)) k], [60, 64, 67],
          reason: "a major triad, by default");
      // C minor: the E is taken down to E flat, the G kept.
      var minor = const MidiEffect(MidiEffectKind.scale, values: {"scale": 1});
      expect([for (var (k, _) in liveKeys([chord, minor], 60, 90)) k],
          [60, 63, 67]);
      // Switched off, nothing is done.
      expect(liveKeys([chord.switched(false)], 60, 90), [(60, 90)]);
    });

    test("velocity is squeezed into its range", () {
      var v = const MidiEffect(MidiEffectKind.velocity,
          values: {"low": 64, "high": 100});
      expect(liveKeys([v], 60, 1).single.$2, 64);
      expect(liveKeys([v], 60, 127).single.$2, 100);
    });

    test("an arpeggiator plays a held chord one note a step", () {
      // A C major chord held two beats, sixteenths at 120: a step is an
      // eighth of a second, so sixteen steps, up and round.
      var arp = const MidiEffect(MidiEffectKind.arpeggiator);
      var played = applyMidiEffects(const [
        MidiNote(60, 0, 1),
        MidiNote(64, 0, 1),
        MidiNote(67, 0, 1),
      ], [
        arp
      ], 0.5);
      expect(played, hasLength(8));
      expect([for (var n in played.take(4)) n.key], [60, 64, 67, 60]);
      expect(played[1].start, closeTo(0.125, 1e-9));
      expect(played.first.length, closeTo(0.125 * 0.6, 1e-9),
          reason: "for the gate's share of the step");
      var down = applyMidiEffects(const [
        MidiNote(60, 0, 0.5),
        MidiNote(64, 0, 0.5),
      ], [
        const MidiEffect(MidiEffectKind.arpeggiator,
            values: {"style": 1, "octaves": 2})
      ], 0.5);
      expect([for (var n in down) n.key], [76, 72, 64, 60]);
    });

    test("the effects are saved with the part", () {
      var part = const InstrumentPart(
          monitor: MidiMonitor.input,
          input: "Keystation",
          effects: [
            MidiEffect(MidiEffectKind.scale, values: {"root": 2}),
            MidiEffect(MidiEffectKind.arpeggiator, on: false),
          ]);
      var back = InstrumentPart.fromJson(part.toJson());
      expect(back.monitor, MidiMonitor.input);
      expect(back.input, "Keystation");
      expect(back.effects.first.choice("root"), 2);
      expect(back.effects.last.on, isFalse);
      // An effect changes what is played, so the file is played again.
      expect(part.signature, isNot(const InstrumentPart().signature));
    });

    test("an arpeggiated part is played again at another tempo", () {
      var part = const InstrumentPart(
          notes: [MidiNote(60, 0, 1)],
          effects: [MidiEffect(MidiEffectKind.arpeggiator)]);
      expect(part.signatureAt(0.5), isNot(part.signatureAt(0.4)));
      var plain = const InstrumentPart(notes: [MidiNote(60, 0, 1)]);
      expect(plain.signatureAt(0.5), plain.signatureAt(0.4),
          reason: "without an arpeggiator the tempo changes nothing");
    });
  });

  group("the keys played live", () {
    late FakeEngine engine;
    setUp(() => engine = FakeEngine({}));

    CanvasController make(List<AudioElement> elements) => CanvasController(
        CanvasDocument(
            frames: 100, audio: const AudioSettings(tempo: 120),
            elements: elements),
        audioEngine: engine);

    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test("Monitor: In always, Auto while armed, Off never", () async {
      var c = make([
        keys("in", monitor: MidiMonitor.input),
        keys("auto"),
        keys("off", monitor: MidiMonitor.off),
      ]);
      addTearDown(c.dispose);
      expect(c.midiHearers(null).map((e) => e.id), ["in"]);
      c.toggleArm("auto");
      expect(c.midiHearers(null).map((e) => e.id), ["in", "auto"]);
      c.toggleArm("off");
      expect(c.midiHearers(null).map((e) => e.id), ["in"],
          reason: "armed, Off still plays nothing that comes in");
    });

    test("with nothing armed or on In, the one picked plays", () {
      var c = make([keys("a"), keys("b"), keys("c", monitor: MidiMonitor.off)]);
      addTearDown(c.dispose);
      c.selectOnly("b");
      expect(c.midiHearers(null).map((e) => e.id), ["b"]);
      c.selectOnly("c");
      expect(c.midiHearers(null).map((e) => e.id), ["a"],
          reason: "the one picked is Off: the first that is not");
    });

    test("From takes one keyboard's notes, or none", () {
      var c = make([
        keys("k1", monitor: MidiMonitor.input, input: "Keystation"),
        keys("k2", monitor: MidiMonitor.input, input: noInput),
        keys("k3", monitor: MidiMonitor.input),
      ]);
      addTearDown(c.dispose);
      expect(c.midiHearers("Keystation").map((e) => e.id), ["k1", "k3"]);
      expect(c.midiHearers("Launchkey").map((e) => e.id), ["k3"]);
    });

    test("a key through a chord sounds three, and lets all three go",
        () async {
      var c = make([
        keys("p", effects: const [MidiEffect(MidiEffectKind.chord)]),
      ]);
      addTearDown(c.dispose);
      c.midiNote(60, 100, from: "any");
      await settle();
      expect(engine.notes.map((n) => n.$2), [60, 64, 67]);
      c.midiNote(60, 0);
      expect(engine.notes.where((n) => n.$3 == 0).map((n) => n.$2),
          [60, 64, 67]);
    });

    // Ken's systems review, 2026-11-08: notes left ringing.
    test("a key held as the scene turns is let go when it comes up",
        () async {
      var c = CanvasController(
          CanvasDocument(
              frames: 100,
              audio: const AudioSettings(tempo: 120),
              scenes: [
                CanvasScene(id: "a", elements: [keys("p")]),
                const CanvasScene(id: "b"),
              ]),
          audioEngine: engine);
      addTearDown(c.dispose);
      var e = c.document.elements.single as AudioElement;
      c.noteOn(e, 60);
      await settle();
      c.goToScene(1);
      c.midiNote(60, 0);
      await settle();
      expect(engine.notes.where((n) => n.$3 == 0).map((n) => n.$2), [60]);
      // And pressed again on the scene it is on, it sounds.
      c.goToScene(0);
      c.noteOn(c.document.elements.single as AudioElement, 60);
      await settle();
      expect(engine.notes.where((n) => n.$2 == 60 && n.$3 > 0), hasLength(2));
    });

    // Ken, 2026-11-08: one sustain pedal, the instrument's own.
    test("the pedal is the instrument's: its keys let go at once", () async {
      var c = make([keys("p")]);
      addTearDown(c.dispose);
      var e = c.document.elements.single as AudioElement;
      var channel = c.timelineChannels.single.key;
      c.midiControl(MidiControl.sustain, 1);
      c.noteOn(e, 60);
      await settle();
      c.noteOff(e, 60);
      c.noteOn(e, 60);
      await settle();
      expect(engine.controls.last, (channel, MidiControl.sustain, 1.0),
          reason: "the instrument holds the sound");
      expect(engine.notes.map((n) => n.$3 > 0), [true, false, true],
          reason: "let go and struck again, as played");
      expect(c.heldKeys("p"), {60});
    });

    test("a knob turned on the instrument does not cut a held key", () async {
      var c = make([keys("p")]);
      addTearDown(c.dispose);
      var e = c.document.elements.single as AudioElement;
      c.noteOn(e, 60);
      c.setChannelPart(c.timelineChannels.single.key,
          (p) => p.copyWith(monitor: MidiMonitor.input));
      await settle();
      expect(engine.notes.where((n) => n.$3 == 0), isEmpty);
      c.noteOff(c.document.elements.single as AudioElement, 60);
      await settle();
      expect(engine.notes.where((n) => n.$3 == 0).map((n) => n.$2), [60]);
    });

    test("two keys sounding one note: the first let go does not stop it",
        () async {
      // C and E, each with a fifth: G is both E's third... rather, C's
      // fifth and E's minor third up -- set so both make 67.
      var c = make([
        keys("p", effects: const [
          MidiEffect(MidiEffectKind.chord,
              values: {"shift1": 7, "shift2": 0, "shift3": 0}),
        ]),
      ]);
      addTearDown(c.dispose);
      var e = c.document.elements.single as AudioElement;
      c.noteOn(e, 60);
      c.noteOn(e, 67 - 7); // the same key: nothing new
      c.noteOn(e, 64);
      c.noteOn(e, 67); // 67 and 74; 67 is already sounding
      await settle();
      c.noteOff(e, 60); // 60 and 67 let go -- but 67 is still held
      expect(engine.notes.where((n) => n.$3 == 0).map((n) => n.$2), [60]);
    });

    test("pressed, let go and pressed as the engine starts: one sound", () async {
      var c = make([keys("p")]);
      addTearDown(c.dispose);
      var e = c.document.elements.single as AudioElement;
      c.noteOn(e, 60);
      c.noteOff(e, 60);
      c.noteOn(e, 60);
      await settle();
      expect(engine.notes, hasLength(1),
          reason: "the second press heard, the first never: none left ringing");
    });

    test("a keyboard's pedal reaches the instrument as its Sustain", () {
      var got = <(MidiControl, double)>[];
      var midi = MidiInput()..onControl = (c, v) => got.add((c, v));
      midi.handle(Uint8List.fromList([0xB0, 64, 127]));
      midi.handle(Uint8List.fromList([0xB0, 64, 0]));
      expect(got, [(MidiControl.sustain, 1.0), (MidiControl.sustain, 0.0)]);
    });

    test("an arpeggiator plays held keys one at a time, live", () async {
      var c = make([
        keys("p", effects: const [
          // Quarter notes at 120: a step every half second.
          MidiEffect(MidiEffectKind.arpeggiator, values: {"rate": 0}),
        ]),
      ]);
      addTearDown(c.dispose);
      var e = c.document.elements.single as AudioElement;
      c.noteOn(e, 60);
      c.noteOn(e, 64);
      await settle();
      expect(engine.notes.where((n) => n.$3 > 0).map((n) => n.$2), [60],
          reason: "only the first, at once");
      await Future<void>.delayed(const Duration(milliseconds: 560));
      await settle();
      expect(engine.notes.where((n) => n.$3 > 0).map((n) => n.$2), [60, 64]);
      c.noteOff(e, 60);
      c.noteOff(e, 64);
      var on = engine.notes.where((n) => n.$3 > 0).length;
      await Future<void>.delayed(const Duration(milliseconds: 560));
      expect(engine.notes.where((n) => n.$3 > 0).length, on,
          reason: "let go, it stops");
    });

    // Ken's systems review, 2026-11-08: the live arpeggiator played the
    // key's own velocity, not what the Velocity effect made of it.
    test("a live arpeggio is as loud as its effects make it", () async {
      var c = make([
        keys("p", effects: const [
          MidiEffect(MidiEffectKind.velocity, values: {"low": 40, "high": 40}),
          MidiEffect(MidiEffectKind.arpeggiator, values: {"rate": 0}),
        ]),
      ]);
      addTearDown(c.dispose);
      var e = c.document.elements.single as AudioElement;
      c.noteOn(e, 60, velocity: 120);
      await settle();
      expect(engine.notes.where((n) => n.$3 > 0).map((n) => n.$3), [40]);
      c.noteOff(e, 60);
    });

    test("a part is played into a file through its effects", () async {
      var renderer = CanvasController.partRenderer;
      var store = CanvasController.partStore;
      addTearDown(() {
        CanvasController.partRenderer = renderer;
        CanvasController.partStore = store;
      });
      var got = <InstrumentPart>[];
      CanvasController.partRenderer = (part, {bankPath}) async {
        got.add(part);
        return Uint8List(0);
      };
      CanvasController.partStore = (_) async => "part.wav";
      var c = make([
        keys("p",
            notes: const [MidiNote(60, 0, 1)],
            effects: const [MidiEffect(MidiEffectKind.chord)]),
      ]);
      addTearDown(c.dispose);
      await c.renderParts();
      expect(got.single.notes.map((n) => n.key), [60, 64, 67]);
      // What is written stays as written.
      expect(
          (c.document.elements.single as AudioElement).instrument!.notes,
          hasLength(1));
    });
  });

  group("channels from the +", () {
    test("an empty audio channel is a lane and a strip, with no sound", () {
      var c = CanvasController(const CanvasDocument(frames: 100),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      var e = c.addEmptyAudioChannel();
      expect(e.clip.playlist, isEmpty);
      expect(e.base.visible, isFalse);
      var lane = c.timelineChannels.single;
      expect(lane.name, "Audio");
      expect(c.instrumentChannel(lane.key), isFalse);
      c.addEmptyAudioChannel();
      expect(c.timelineChannels.map((l) => l.name), ["Audio", "Audio 2"]);
    });

    test("an empty MIDI channel is on the timeline only", () {
      var c = CanvasController(const CanvasDocument(frames: 100),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      var on = c.addMidiChannel();
      var off = c.addMidiChannel(onCanvas: false);
      expect(on.base.visible, isTrue);
      expect(off.base.visible, isFalse);
      expect(c.timelineChannels, hasLength(2));
    });
  });

  // The prototype's Note clips card: a feel the notes are played with,
  // the notes as drawn left alone (Ken's audit, 2026-11-08).
  group("quantise and swing", () {
    const spb = 0.5; // 120 a minute: a sixteenth is an eighth of a second.
    test("pulled onto the sixteenths by as much as asked", () {
      var notes = const [MidiNote(60, 0.04, 0.1), MidiNote(62, 0.27, 0.1)];
      var half = groovedNotes(notes, spb, quantise: 0.5);
      expect(half[0].start, closeTo(0.02, 1e-9));
      expect(half[1].start, closeTo(0.26, 1e-9));
      var all = groovedNotes(notes, spb, quantise: 1);
      expect([for (var n in all) n.start], [0.0, 0.25]);
      expect([for (var n in all) n.length], [0.1, 0.1], reason: "lengths kept");
      expect(
        identical(groovedNotes(notes, spb), notes),
        isTrue,
        reason: "with neither, nothing done",
      );
    });

    test("every second sixteenth swung late", () {
      var straight = [for (var i = 0; i < 4; i++) MidiNote(60, i * 0.125, 0.1)];
      var swung = groovedNotes(straight, spb, swing: 1);
      expect(
        [for (var n in swung) n.start],
        [
          0.0,
          closeTo(0.125 + 0.125 / 3, 1e-9),
          0.25,
          closeTo(0.375 + 0.125 / 3, 1e-9),
        ],
      );
    });

    test("the part plays with it, kept, and its file made again", () {
      var part = const InstrumentPart(
        notes: [MidiNote(60, 0.04, 0.1), MidiNote(62, 0.125, 0.1)],
      );
      var felt = part.copyWith(quantise: 1, swing: 0.5);
      expect(felt.played(spb).notes.first.start, 0.0);
      expect(felt.notes.first.start, 0.04, reason: "the notes as drawn");
      expect(felt.signature, isNot(part.signature));
      expect(
        felt.signatureAt(spb),
        isNot(felt.signatureAt(0.4)),
        reason: "the grid is the tempo's",
      );
      var back = InstrumentPart.fromJson(felt.toJson());
      expect((back.quantise, back.swing), (1.0, 0.5));
      expect(
        part.toJson().containsKey("quantise"),
        isFalse,
        reason: "a part from before is saved as it was",
      );
    });
  });

  group("the chain", () {
    testWidgets("a MIDI channel's chain starts with its In and MIDI effects",
        (tester) async {
      var c = CanvasController(
          CanvasDocument(frames: 100, elements: [keys("p")]),
          audioEngine: FakeEngine({}));
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      c.openEffects("p");
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
      await tester.pump();
      expect(find.byKey(const ValueKey("device-midiIn")), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("midiMonitor-input")));
      await tester.pump();
      InstrumentPart part() =>
          (c.document.elements.single as AudioElement).instrument!;
      expect(part().monitor, MidiMonitor.input);

      await openAdd(tester, find.byKey(const ValueKey("addMidiOpen")));
      await tester.tap(find.byKey(const ValueKey("addMidi-chord")));
      await tester.pump(const Duration(milliseconds: 400));
      expect(part().effects.single.kind, MidiEffectKind.chord);
      expect(find.byKey(const ValueKey("device-midi0")), findsOneWidget);
      c.undo();
      expect(part().effects, isEmpty, reason: "one change to undo");
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets("the Note clips card sets its quantise and swing", (
      tester,
    ) async {
      var c = CanvasController(
        CanvasDocument(
          frames: 100,
          elements: [
            keys("p", notes: const [MidiNote(60, 0.04, 0.2)]),
          ],
        ),
        audioEngine: FakeEngine({}),
      );
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      c.openEffects("p");
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false),
            ),
            ChangeNotifierProvider<SnackBarModel>(
              create: (c) => SnackBarModel(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: ListenableBuilder(
                  listenable: c,
                  builder: (context, _) => CanvasMixer.effects(
                    controller: c,
                    height: 380,
                    onResize: (_) {},
                    onClose: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      InstrumentPart part() =>
          (c.document.elements.single as AudioElement).instrument!;
      tester
          .widget<DeviceKnob>(find.byKey(const ValueKey("noteQuantise")))
          .onChanged(0.75);
      await tester.pump();
      tester
          .widget<DeviceKnob>(find.byKey(const ValueKey("noteSwing")))
          .onChanged(0.4);
      await tester.pump();
      expect((part().quantise, part().swing), (0.75, 0.4));
      expect(part().notes.single.start, 0.04, reason: "the notes untouched");
      c.undo();
      expect(part().swing, 0, reason: "each one undo step");
      expect(part().quantise, 0.75);
      // Its slots' note clips as chips, and the picked one's Length.
      c.newMidiClip("p", 0);
      await tester.pump();
      expect(find.byKey(const ValueKey("noteClipsChip-0")), findsOneWidget);
      tester
          .widget<StudioDrop<double>>(
              find.byKey(const ValueKey("noteClipsLength")))
          .onChanged(4);
      await tester.pump();
      expect(c.session.at("p", 0)!.bars, 4);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    // The chain prototype's joins on a MIDI chain: the notes passing as
    // dots, a chord's made three.
    testWidgets("its joins show the notes passing, a chord's three",
        (tester) async {
      var c = CanvasController(
          CanvasDocument(frames: 100, elements: [
            keys("p",
                effects: const [MidiEffect(MidiEffectKind.chord)],
                notes: const [MidiNote(60, 0, 2)])
          ]),
          audioEngine: FakeEngine({}));
      tester.view.physicalSize = const Size(1800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      c.openEffects("p");
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
                    child: ListenableBuilder(
                        listenable: c,
                        builder: (context, _) => CanvasMixer.effects(
                            controller: c,
                            height: 380,
                            onResize: (_) {},
                            onClose: () {}))))),
      ));
      await tester.pump();
      String says(int upto) => tester
          .widget<Tooltip>(find
              .ancestor(
                  of: find.byKey(ValueKey("noteJoin-$upto")).first,
                  matching: find.byType(Tooltip))
              .first)
          .message!;
      expect(says(0), "1 note passing", reason: "before its effects");
      expect(says(1), "3 notes passing", reason: "after the chord");
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    // Its rate and style chosen from lists, and a second set to compare,
    // as a sound device's (Ken's audit, 2026-11-08).
    for (var scale in [1.0, 1.5]) {
      testWidgets("an arpeggiator's choices are lists, and it has A|B, at "
          "$scale", (tester) async {
        var c = CanvasController(
            CanvasDocument(frames: 100, elements: [
              keys("p",
                  effects: const [MidiEffect(MidiEffectKind.arpeggiator)])
            ]),
            audioEngine: FakeEngine({}));
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        c.openEffects("p");
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
                  body: Align(
                      alignment: Alignment.bottomCenter,
                      child: ListenableBuilder(
                          listenable: c,
                          builder: (context, _) => CanvasMixer.effects(
                              controller: c,
                              height: 380,
                              onResize: (_) {},
                              onClose: () {}))))),
        ));
        await tester.pump();
        MidiEffect arp() => (c.document.elements.single as AudioElement)
            .instrument!
            .effects
            .single;
        var rate = tester.widget<StudioDrop<int>>(
            find.byKey(const ValueKey("midi-0-rate")));
        expect([for (var o in rate.options) o.$2], arpRateNames);
        expect(find.byKey(const ValueKey("midi-0-style")), findsOneWidget);
        rate.onChanged(1);
        await tester.pump();
        expect(arp().choice("rate"), 1);

        await tester.tap(find.byKey(const ValueKey("deviceAB-midi0")));
        await tester.pump();
        tester
            .widget<StudioDrop<int>>(find.byKey(const ValueKey("midi-0-rate")))
            .onChanged(5);
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey("deviceAB-midi0")));
        await tester.pump();
        expect(arp().choice("rate"), 1, reason: "A");
        await tester.tap(find.byKey(const ValueKey("deviceAB-midi0")));
        await tester.pump();
        expect(arp().choice("rate"), 5, reason: "B");
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      });
    }
  });
}
