import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/model/fretting.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/music_score.dart';
import 'package:bruig/plugin_system/canvas/model/score_edit.dart';
import 'package:bruig/plugin_system/canvas/model/score_samples.dart';
import 'package:bruig/plugin_system/canvas/render/audio_painter.dart';
import 'package:bruig/plugin_system/canvas/render/instrument_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:flutter_test/flutter_test.dart';

import 'canvas_audio_fake.dart';

// canvas_fretting_test.dart is a guitar's and a bass's notes on the neck
// (Ken, 2026-11-14: "when playing a single note further down the neck it
// triggers a note somewhere else ... the "G" chord is playing notes that
// aren't on the fret board"): chord symbols as the shapes a guitarist
// holds, the common one first; notes sounding together one to a string;
// a run kept where the hand is; a press lit where it was pressed.

String fretsOf(GuitarShape s) =>
    s.frets.map((f) => f?.toString() ?? "x").join();

void main() {
  test("the common chords, as a chord chart has them", () {
    var want = {
      "C": "x32010",
      "A": "x02220",
      "G": "320003",
      "E": "022100",
      "D": "xx0232",
      "F": "xx3211",
      "Am": "x02210",
      "Em": "022000",
      "Dm": "xx0231",
      "G7": "320001",
      "Bm": "x24432",
      "C#m": "x46654",
    };
    for (var MapEntry(:key, :value) in want.entries) {
      expect(fretsOf(guitarChord(key)!), value, reason: key);
    }
  });

  test("every shape sounds its chord's notes, the bass lowest", () {
    for (var symbol in [
      "C",
      "G",
      "D",
      "F",
      "Bb",
      "F#m",
      "E7",
      "Cmaj7",
      "Asus4",
      "Bdim",
      "Eaug",
      "C/G",
      "G/B",
      "D/F#"
    ]) {
      var c = readChord(symbol)!;
      var pcs = {for (var t in chordTones(c.kind)) (c.root + t) % 12, c.bass};
      for (var shape in guitarChordShapes(symbol)) {
        var keys = shape.keysOn(guitarStrings);
        expect(keys.length, greaterThanOrEqualTo(3), reason: "$symbol $shape");
        for (var k in keys) {
          expect(pcs, contains(k % 12), reason: "$symbol $shape: $k");
        }
        expect(keys.first % 12, c.bass, reason: "$symbol $shape: its bass");
        var held = [
          for (var f in shape.frets)
            if (f != null && f > 0) f
        ];
        if (held.isNotEmpty) {
          expect(
              held.reduce((a, b) => a > b ? a : b) -
                  held.reduce((a, b) => a < b ? a : b),
              lessThanOrEqualTo(4),
              reason: "$symbol $shape: a hand's stretch");
        }
      }
    }
  });

  test("slash chords: the bass on a low string", () {
    expect(fretsOf(guitarChord("C/G")!), "332010");
    expect(fretsOf(guitarChord("G/B")!), "x20003");
    expect(fretsOf(guitarChord("D/F#")!), "2x0232");
  });

  test("its places up the neck, and the fingers, as a chart numbers them", () {
    var g = guitarChordShapes("G");
    expect([
      for (var s in g) s.name
    ], [
      "Open",
      "Barre, 3rd fret (E shape)",
      "Barre, 10th fret (A shape)",
    ]);
    expect(fretsOf(g[1]), "355433");
    expect(guitarChord("G")!.fingers, [2, 1, null, null, null, 3]);
    expect(guitarChord("C")!.fingers, [null, 3, 2, null, 1, null]);
    expect(guitarChord("D")!.fingers, [null, null, null, 1, 3, 2]);
    expect(guitarChord("A")!.fingers, [null, null, 1, 2, 3, null]);
    expect(g[1].fingers, [1, 3, 4, 2, 1, 1],
        reason: "a barre: the first finger");
    expect(guitarChord("G", 9)!.name, "Open", reason: "out of range: common");
  });

  test("notes together go one to a string: the G chord as it is held", () {
    var keys = guitarChord("G")!.keysOn(guitarStrings);
    var places = neckPlaces(keys, guitarStrings);
    expect(places, guitarChord("G")!.places);
    // Never two notes on one string, even for notes that cannot all be
    // held: those the neck has no room for are left out.
    var crowded = neckPlaces([43, 47, 50, 55, 59, 62], guitarStrings);
    expect({for (var (s, _) in crowded) s}.length, crowded.length);
  });

  test("a run stays where the hand is; with nowhere to start, low", () {
    // The B barre at the 7th fret, then a D: on the G string's 7th, not
    // the B string's 3rd.
    var b = guitarChordShapes("B").firstWhere((s) => s.name.contains("7th"));
    var notes = [
      for (var k in b.keysOn(guitarStrings)) MidiNote(k, 0, 0.5, 90),
      const MidiNote(62, 0.5, 0.25, 90),
      const MidiNote(64, 0.75, 0.25, 90),
    ];
    var at = fretting(notes, guitarStrings);
    expect(at[notes.length - 2], (3, 7));
    expect(at.last!.$2, greaterThanOrEqualTo(5),
        reason: "an E, held up the neck rather than the open string");
    // Alone, the lowest place.
    expect(
        fretting([const MidiNote(62, 0, 1, 90)], guitarStrings).single, (4, 3));
  });

  test("a bass: its notes on its four strings; under a strum, the bass", () {
    var at = fretting([
      const MidiNote(33, 0, 0.5, 90),
      const MidiNote(40, 0.5, 0.5, 90),
    ], bassStrings);
    expect(at, [(1, 0), (2, 2)]);
    expect(bassChordKeys("G"), [31]);
    expect(bassChordKeys("C/E"), [28]);
  });

  test("a strummed chord sounds its shape -- the one chosen in the Studio", () {
    var s = odeToJoy();
    var strum = s.parts.firstWhere((p) => p.strum);
    var first = strum.staves[0].bars[0][0];
    var chord = first.chord!;
    List<int> struck(MusicScore x) {
      var notes = x.partNotes(strum.id);
      var t0 = notes.first.note.start;
      return [
        for (var n in notes)
          if (n.note.start < t0 + 0.2) n.note.key
      ]..sort();
    }

    expect(struck(s), guitarChord(chord)!.keysOn(guitarStrings)..sort());
    var moved = s.withEvent(first.id, (e) => e.copyWith(shape: 1));
    expect(struck(moved), guitarChord(chord, 1)!.keysOn(guitarStrings)..sort());
    expect(MusicScore.fromJson(moved.toJson()).event(first.id)!.shape, 1);
  });

  test("an instrument lights its notes where the part plays them", () {
    var b = guitarChordShapes("B").firstWhere((s) => s.name.contains("7th"));
    var part = InstrumentPart(look: InstrumentLook.guitar, notes: [
      for (var k in b.keysOn(guitarStrings)) MidiNote(k, 0, 0.5, 90),
      const MidiNote(62, 0.5, 0.5, 90),
    ]);
    var e = newInstrument(const CanvasDocument()).copyWith(instrument: part);
    var state = AudioState.atFrame(e, 18, 24); // 0.75 s in
    expect(state.keys, {62});
    expect(state.places[62], (3, 7));
  });

  test("a press on the neck lit where it was pressed", () {
    var c =
        CanvasController(const CanvasDocument(), audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    var e = newInstrument(c.document);
    e = e.copyWith(instrument: e.instrument!.withLook(InstrumentLook.guitar));
    c.addElement(e);
    var layout = keyboardLayout(e.instrument!, e.bounds);
    // The A string's 7th fret: an E, which the low E string has open.
    var rect = layout.keys[1 * (frets + 1) + 7].rect;
    var place = neckPlaceAt(layout, e.instrument!, rect.center);
    expect(place, (1, 7));
    var key = layout.keyAt(rect.center)!.$1;
    expect(key, 52);
    c.noteOn(c.document.elementById(e.id) as AudioElement, key, place: place);
    expect(
        c.audioState(c.document.elementById(e.id) as AudioElement).places[52],
        (1, 7));
    c.noteOff(c.document.elementById(e.id) as AudioElement, key);
    expect(
        c
            .audioState(c.document.elementById(e.id) as AudioElement)
            .places
            .containsKey(52),
        isFalse);
  });

  test("off the neck, no place", () {
    var part = const InstrumentPart(look: InstrumentLook.guitar);
    var layout = keyboardLayout(part, const Rect.fromLTWH(0, 0, 400, 120));
    expect(neckPlaceAt(layout, part, const Offset(-5, -5)), isNull);
    expect(neckPlaceAt(layout, const InstrumentPart(), const Offset(10, 60)),
        isNull,
        reason: "a keyboard has no neck");
  });

  test("a sheet keeps whether it draws guitar chord boxes", () {
    var e = const SheetElement(ElementBase(id: "s"));
    expect(e.showDiagrams, isTrue);
    var back = elementFromJson(e.copyWith(showDiagrams: false).toJson())
        as SheetElement;
    expect(back.showDiagrams, isFalse);
  });
}
