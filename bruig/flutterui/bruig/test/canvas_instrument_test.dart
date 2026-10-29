import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/media/midi_input.dart';
import 'package:bruig/plugin_system/canvas/media/synth/sampler.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/midi_file.dart';
import 'package:bruig/plugin_system/canvas/render/instrument_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/element_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/elements_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_channels.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline_view.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_instrument_test.dart is the Instrument: an Audio element playing a
// part -- its keyboard, its notes played live and recorded, read from a MIDI
// file, and played into its clip's file whenever they change.

/// smf is a format-0 MIDI file at 480 ticks a beat: C4 for a beat at 120
/// BPM, then the tempo halved and E4 for a beat, a drum hit on channel 10,
/// and a program change to 40, the violin.
Uint8List smf() {
  var t = <int>[
    0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20, // 500000us: 120 BPM
    0x00, 0xC0, 40, // program 40
    0x00, 0x90, 60, 100, // C4 on
    0x00, 0x99, 36, 100, // a kick, on the drums
    0x83, 0x60, 0x80, 60, 0, // a beat later: C4 off
    0x00, 0x89, 36, 0,
    0x00, 0xFF, 0x51, 0x03, 0x0F, 0x42, 0x40, // 1000000us: 60 BPM
    0x00, 0x90, 64, 80, // E4 on
    0x83, 0x60, 0x90, 64, 0, // a beat later: E4 off, as a velocity of 0
    0x00, 0xFF, 0x2F, 0x00,
  ];
  return Uint8List.fromList([
    ...'MThd'.codeUnits, 0, 0, 0, 6, 0, 0, 0, 1, 0x01, 0xE0, //
    ...'MTrk'.codeUnits, 0, 0, 0, t.length, ...t,
  ]);
}

void main() {
  tearDown(() {
    CanvasController.partRenderer = (part, {bankPath}) async => Uint8List(0);
    CanvasController.partStore = (wav) async => null;
    CanvasController.bankReady = () async => false;
  });

  test("an instrument is kept: its part, its notes, its keyboard", () {
    var e = AudioElement(const ElementBase(id: "p"),
        instrument: const InstrumentPart(
            sound: InstrumentSound.bank,
            program: 40,
            lowKey: 21,
            keys: 88,
            notes: [MidiNote(60, 0.5, 1, 90)]));
    var back = AudioElement.fromJson(
        e.toJson()["props"] ?? e.props(), const ElementBase(id: "p"));
    var part = back.instrument!;
    expect((part.sound, part.program, part.lowKey, part.keys),
        (InstrumentSound.bank, 40, 21, 88));
    expect(part.notes.single, const MidiNote(60, 0.5, 1, 90));
    expect(part.name, "Violin");
    expect(AudioElement.fromJson(const AudioElement(ElementBase(id: "a")).props(),
            const ElementBase(id: "a"))
        .instrument, isNull, reason: "a speaker is not an instrument");
  });

  test("a MIDI file is read through its tempo changes, drums left out", () {
    var read = readMidiFile(smf());
    expect(read.program, 40);
    expect(read.notes.length, 2);
    var (c, e) = (read.notes[0], read.notes[1]);
    expect((c.key, c.start, c.length, c.velocity), (60, 0.0, 0.5, 100));
    expect(e.key, 64);
    expect(e.start, closeTo(0.5, 1e-9));
    expect(e.length, closeTo(1.0, 1e-9), reason: "a beat at 60 BPM");
    expect(() => readMidiFile(Uint8List.fromList([1, 2, 3])),
        throwsFormatException);
  });

  test("the keyboard: white keys across, black keys over their joins", () {
    const part = InstrumentPart(lowKey: 60, keys: 13); // C4 to C5
    var layout = keyboardLayout(part, const Rect.fromLTWH(0, 0, 400, 120));
    var whites = layout.keys.where((k) => !k.black).toList();
    var blacks = layout.keys.where((k) => k.black).toList();
    expect(whites.length, 8);
    expect(blacks.length, 5);
    // Pressed on the black key between C and D: C sharp, not C.
    var cSharp = blacks.firstWhere((k) => k.key == 61).rect;
    expect(layout.keyAt(cSharp.center)!.$1, 61);
    // Low on the white key, under the black ones: the white key, and hard.
    var d = whites.firstWhere((k) => k.key == 62).rect;
    var (key, depth) = layout.keyAt(Offset(d.left + 3, d.bottom - 2))!;
    expect((key, depth > 0.9), (62, true));
  });

  group("drum pads, guitar and bass", () {
    test("each pad is its drum; a neck's places are string plus fret", () {
      const pads = InstrumentPart(look: InstrumentLook.drums);
      var layout = keyboardLayout(pads, const Rect.fromLTWH(0, 0, 400, 400));
      expect(layout.keys.length, 16);
      var kick = layout.keys.firstWhere((k) => k.key == 36).rect;
      expect(layout.keyAt(kick.center)!.$1, 36);

      const guitar = InstrumentPart(look: InstrumentLook.guitar);
      var neck = keyboardLayout(guitar, const Rect.fromLTWH(0, 0, 800, 200));
      expect(neck.keys.length, 6 * (frets + 1));
      // The low E string's third fret is a G.
      var g = neck.keys.firstWhere((k) => k.key == 43 && k.rect.bottom > 190);
      expect(neck.keyAt(g.rect.center)!.$1, 43);
      expect(fretFor(43, guitarStrings), (0, 3));
      expect(fretFor(64, guitarStrings), (5, 0), reason: "the open top string");
      expect(fretFor(20, guitarStrings), isNull, reason: "under the neck");
    });

    test("played on another, its General MIDI sound comes with it", () {
      var drums = const InstrumentPart().withLook(InstrumentLook.drums);
      expect((drums.bank, drums.program, drums.name), (128, 0, "Drums"));
      var bass = const InstrumentPart(sound: InstrumentSound.bank)
          .withLook(InstrumentLook.bass);
      expect(bass.name, "Fingered bass");
      expect(InstrumentPart.fromJson(drums.toJson()).look, InstrumentLook.drums);
      expect(const InstrumentPart(notes: [MidiNote(60, 0, 1)]).signature,
          isNot(const InstrumentPart(
                  look: InstrumentLook.guitar, notes: [MidiNote(60, 0, 1)])
              .signature),
          reason: "on our own sounds, a guitar is not a piano");
    });

    test("our own drums and strings sound", () {
      double level(InstrumentLook look, int key) {
        var s = Sampler(look: look)..noteOn(key, 110);
        var l = Float32List(24000), r = Float32List(24000);
        s.render(l, r, 24000);
        var sum = 0.0;
        for (var v in l) {
          sum += v * v;
        }
        return sum;
      }

      for (var key in [36, 38, 42, 46, 49, 45, 56]) {
        expect(level(InstrumentLook.drums, key), greaterThan(0.5),
            reason: "drum $key");
      }
      expect(level(InstrumentLook.guitar, 52), greaterThan(0.5));
      expect(level(InstrumentLook.bass, 28), greaterThan(0.5));
    });

    test("a plucked string is at its pitch", () {
      var s = Sampler(look: InstrumentLook.guitar)..noteOn(57, 110); // A3
      var l = Float32List(24000), r = Float32List(24000);
      s.render(l, r, 24000);
      var best = 0, bestC = 0.0;
      for (var lag = 150; lag < 300; lag++) {
        var c = 0.0;
        for (var i = 2000; i < 8000; i++) {
          c += l[i] * l[i + lag];
        }
        if (c > bestC) {
          bestC = c;
          best = lag;
        }
      }
      expect(48000 / best, closeTo(220, 3));
    });
  });

  group("the controller", () {
    CanvasController make({List<MidiNote> notes = const []}) {
      var e = newInstrument(const CanvasDocument(frames: 240, frameRate: 24));
      return CanvasController(
          CanvasDocument(frames: 240, frameRate: 24, elements: [
            e.copyWith(instrument: e.instrument!.copyWith(notes: notes)),
          ]),
          audioEngine: FakeEngine({}));
    }

    AudioElement piano(CanvasController c) =>
        c.document.elements.single as AudioElement;

    test("keys played live sound on its channel, and are lit", () async {
      var c = make();
      addTearDown(c.dispose);
      var e = piano(c);
      c.noteOn(e, 60, velocity: 90);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(c.heldKeys(e.id), {60});
      expect(c.audioState(e).keys, {60});
      c.noteOff(e, 60);
      var engine = c.audio.engine as FakeEngine;
      expect(engine.notes, [(e.id, 60, 90), (e.id, 60, 0)]);
      expect(c.audioState(e).keys, isEmpty);
    });

    test("the notes under the playhead are lit", () {
      var c = make(notes: const [MidiNote(64, 1, 1)]);
      addTearDown(c.dispose);
      c.frame = 36; // 1.5 seconds
      expect(c.audioState(piano(c)).keys, {64});
      c.frame = 60;
      expect(c.audioState(piano(c)).keys, isEmpty);
    });

    test("recording writes what is played into the part, one undo", () {
      var c = make();
      addTearDown(c.dispose);
      var e = piano(c);
      c.frame = 24;
      c.recording = true;
      expect(c.playing, isTrue, reason: "Record plays");
      c.noteOn(e, 67, velocity: 100);
      for (var i = 0; i < 12; i++) {
        c.tickForTest();
      }
      c.noteOff(e, 67);
      c.noteOn(e, 69);
      c.tickForTest();
      c.pause();
      expect(c.recording, isFalse);
      var notes = piano(c).instrument!.notes;
      expect(notes.length, 2, reason: "one let go, one held to the stop");
      expect(notes.first.key, 67);
      expect(notes.first.start, closeTo(1, 0.05));
      expect(notes.first.length, closeTo(0.5, 0.05));
      c.undo();
      expect(piano(c).instrument!.notes, isEmpty);
    });

    test("a changed part is played into its clip's file -- not an undo",
        () async {
      var played = <InstrumentPart>[];
      CanvasController.partRenderer = (part, {bankPath}) async {
        played.add(part);
        return Uint8List.fromList([1, 2, 3]);
      };
      CanvasController.partStore = (wav) async => "0123456789abcdef.wav";
      var c = make();
      addTearDown(c.dispose);
      var e = piano(c);
      c.setInstrument(e,
          e.instrument!.copyWith(notes: const [MidiNote(60, 0, 1)]));
      await c.renderParts();
      var now = piano(c);
      expect(played.single.notes.single.key, 60);
      expect(now.clip.playlist.single.assetId, "0123456789abcdef.wav");
      expect(now.clip.playlist.single.length,
          closeTo(1 + InstrumentPart.releaseTail, 1e-9));
      expect(now.instrument!.needsPlaying, isFalse);
      // Undo takes back the notes, not the playing of them.
      c.undo();
      expect(piano(c).instrument!.notes, isEmpty);
      // Played again only when something it is played from changes.
      c.redo();
      await c.renderParts();
      expect(played.length, 1);
    });

    test("wanting the bank without it: the piano now, the bank later",
        () async {
      var banks = <String?>[];
      CanvasController.partRenderer = (part, {bankPath}) async {
        banks.add(bankPath);
        return Uint8List(1);
      };
      CanvasController.partStore = (wav) async => "0123456789abcdef.wav";
      CanvasController.bankReady = () async => false;
      var c = make();
      addTearDown(c.dispose);
      var e = piano(c);
      c.setInstrument(
          e,
          e.instrument!.copyWith(
              sound: InstrumentSound.bank,
              notes: const [MidiNote(60, 0, 1)]));
      await c.renderParts();
      await c.renderParts();
      expect(banks, [null], reason: "once, on the piano -- not over and over");
      expect(piano(c).instrument!.needsPlaying, isTrue);
    });
  });

  group("a MIDI keyboard", () {
    test("its keys pressed and let go reach whoever listens", () {
      var got = <(int, int)>[];
      var midi = MidiInput()..onNote = (k, v) => got.add((k, v));
      midi.handle(Uint8List.fromList([0x90, 60, 100]));
      midi.handle(Uint8List.fromList([0x93, 64, 0])); // let go, as a 0
      midi.handle(Uint8List.fromList([0x80, 60, 40]));
      midi.handle(Uint8List.fromList([0xB0, 64, 127])); // the pedal: passed
      midi.handle(Uint8List.fromList([0xF8])); // the clock: passed
      expect(got, [(60, 100), (64, 0), (60, 0)]);
    });

    test("plays the selected instrument, or the first", () async {
      var a = newInstrument(const CanvasDocument());
      var b = newInstrument(const CanvasDocument());
      var c = CanvasController(CanvasDocument(elements: [a, b]),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      c.midiNote(60, 90);
      expect(c.heldKeys(a.id), {60});
      c.midiNote(60, 0);
      c.selectOnly(b.id);
      c.midiNote(62, 70);
      expect(c.heldKeys(b.id), {62});
      expect(c.heldKeys(a.id), isEmpty);
      var none = CanvasController(const CanvasDocument());
      addTearDown(none.dispose);
      none.midiNote(60, 90); // nothing to play: nothing happens
    });
  });

  group("a MIDI channel from the timeline's +", () {
    Future<CanvasController> lanes(WidgetTester tester, CanvasDocument doc) async {
      var c = CanvasController(doc, audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(1000, 400);
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
                body: ListenableBuilder(
                    listenable: c,
                    builder: (context, _) => Align(
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                            height: 300,
                            child: CanvasChannels(
                                controller: c,
                                view: TimelineView.whole(
                                    c.document.frames))))))),
      ));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets("adds an instrument on a channel of its own, there at once",
        (tester) async {
      var c = await lanes(
          tester,
          const CanvasDocument(
              kind: CanvasKind.audio, hasCanvas: false, frames: 240));
      await tester.tap(find.byKey(const ValueKey("addChannel")));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("addAudioChannel")), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("addMidiChannel")));
      await tester.pumpAndSettle();
      var e = c.document.elements.single as AudioElement;
      expect(e.instrument, isNotNull);
      expect(e.visible, isFalse,
          reason: "no canvas to draw it on: it lives on the timeline");
      expect(e.name, "Piano");
      expect(c.selected?.id, e.id, reason: "picked, for a MIDI keyboard");
      expect(find.byKey(ValueKey("lane-${e.id}")), findsOneWidget,
          reason: "its lane, before it has a note");
      expect(c.addMidiChannel().name, "Piano 2");
    });

    test("on a canvas, its keyboard is drawn too", () {
      var c = CanvasController(const CanvasDocument(),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      expect(c.addMidiChannel().visible, isTrue);
    });
  });

  group("in the editor", () {
    Future<void> show(WidgetTester tester, Widget child,
        {bool settle = true}) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(
              create: (c) => CanvasPreferences()),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      ));
      settle
          ? await tester.pumpAndSettle()
          : await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets("Add has an Instrument, and it arrives a keyboard",
        (tester) async {
      var c = CanvasController(const CanvasDocument(),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      await show(tester, CanvasElementsPanel(controller: c));
      await tester.tap(find.byKey(const ValueKey("addInstrument")));
      await tester.pumpAndSettle();
      var added = c.document.elements.single as AudioElement;
      expect(added.instrument, isNotNull);
      expect(added.name, "Piano");
      expect(added.clip.timed, isTrue, reason: "its part is on the timeline");
    });

    testWidgets("its settings: sound, keyboard, part", (tester) async {
      var c = CanvasController(
          CanvasDocument(elements: [newInstrument(const CanvasDocument())]),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      c.selectOnly(c.document.elements.single.id);
      await show(
          tester,
          ListenableBuilder(
            listenable: c,
            builder: (context, _) => SingleChildScrollView(
              child: SizedBox(
                width: 320,
                child: CanvasControlScope(
                  maxWidth: 280,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: elementSettings(context, c, c.selected!),
                  ),
                ),
              ),
            ),
          ),
          settle: false);
      expect(find.byKey(const ValueKey("elementSection-instrument")),
          findsOneWidget);
      expect(find.byKey(const ValueKey("audioAdd")), findsNothing,
          reason: "an instrument's sound is its part, not a file");
      expect(find.text("No notes yet"), findsOneWidget);
      tester
          .widget<CanvasDropdown<int>>(
              find.byKey(const ValueKey("instrumentKeys")))
          .onChanged(keyboards.length - 1);
      await tester.pump(const Duration(milliseconds: 100));
      var part = (c.document.elements.single as AudioElement).instrument!;
      expect((part.lowKey, part.keys), (21, 88));
      tester
          .widget<CanvasDropdown<InstrumentSound>>(
              find.byKey(const ValueKey("instrumentSound")))
          .onChanged(InstrumentSound.bank);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey("instrumentProgram")), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
