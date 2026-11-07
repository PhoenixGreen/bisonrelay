import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/synth/part_render.dart';
import 'package:bruig/plugin_system/canvas/media/synth/soundfont.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/session.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'canvas_audio_fake.dart';

// canvas_clip_slices_test.dart is what the clip editor's prototype has
// that ours did not (Ken, 2026-11-07): Normalise, slicing every 1/8 and
// 1/16, and a clip sliced into a note clip or onto drum pads -- a new
// channel whose instrument plays the slices of its sound.

const _rate = 48000;

/// _hits is two bars at 120 of hits a beat apart, each a different pitch
/// so a slice can be told by its sound, the loudest at [peak].
(Float32List, Float32List) _hits({double peak = 0.5}) {
  var n = 4 * _rate;
  var l = Float32List(n), r = Float32List(n);
  for (var beat = 0; beat < 8; beat++) {
    var at = beat * _rate ~/ 2;
    var hz = 200.0 + 100 * beat;
    // Faded right out before the next: no click where it stops.
    for (var k = 0; k < _rate ~/ 2 && at + k < n; k++) {
      var v = (beat == 3 ? peak : peak * 0.6) *
          math.exp(-k / 2000) *
          math.sin(2 * math.pi * hz * k / _rate);
      l[at + k] = v;
      r[at + k] = v;
    }
  }
  return (l, r);
}

void main() {
  late CanvasController c;
  var audioWas = CanvasController.clipAudio;
  var readerWas = sliceAudioReader;

  setUp(() {
    CanvasController.clipAudio = (id) async => _hits();
    c = CanvasController(
        CanvasDocument(
            frames: 600,
            frameRate: 60,
            audio: const AudioSettings(tempo: 120),
            elements: [
              AudioElement(const ElementBase(id: "a", name: "Drums"),
                  clip: const MediaClip(
                      playlist: [MediaSource(assetId: "beat.wav", length: 4)],
                      timed: true)),
            ]),
        audioEngine: FakeEngine({"beat.wav": 4}));
    c.setSessionClip(
        "a",
        0,
        const SessionClip(
            id: "bed",
            name: "Bed A",
            sound: MediaSource(assetId: "beat.wav", name: "Beat", length: 4),
            bars: 2));
    c.openClipEditor("a", 0);
  });

  tearDown(() {
    c.dispose();
    CanvasController.clipAudio = audioWas;
    sliceAudioReader = readerWas;
  });

  test("Normalise: its gain set so its loudest reaches 0 dB", () async {
    var said = await c.normaliseClip();
    // Loudest 0.5: six decibels up.
    expect(c.session.at("a", 0)!.gain, closeTo(6.0, 0.15));
    expect(said, startsWith("Normalised: +6."));
  });

  test("sliced every 1/8: four slices a bar", () async {
    expect(await c.sliceClip(SliceBy.eighth), isNull);
    // Two bars, an eighth of a beat a slice: sixteen, under the clip.
    expect(c.session.at("a", 16)?.name, "Bed A 16");
    expect(c.session.at("a", 17), isNull);
  });

  test("into a note clip: a new channel playing its slices, a note each",
      () async {
    var before = c.document.elements.length;
    var said = await c.sliceToInstrument(pads: false);
    expect(said, contains("note clip of 8 slices"));
    expect(c.document.elements.length, before + 1);
    var made = c.document.elements.last as AudioElement;
    var part = made.instrument!;
    expect(part.sound, InstrumentSound.slices);
    expect(part.slices!.assetId, "beat.wav");
    expect(part.slices!.keys, [for (var i = 0; i < 8; i++) 36 + i]);
    expect(part.slices!.oneShot, isFalse);
    // Its first slot: a note a slice, where each was, a beat apart.
    var channel = c.timelineChannels
        .firstWhere((ch) => ch.lanes.any((l) => l.element.id == made.id));
    var clip = c.session.at(channel.key, 0)!;
    expect(clip.midi, isTrue);
    expect(clip.notes.map((n) => n.key), part.slices!.keys);
    for (var (i, n) in clip.notes.indexed) {
      expect(n.start, closeTo(i.toDouble(), 0.05), reason: "slice $i");
    }
    // One undo takes it all back.
    c.undo();
    expect(c.document.elements.length, before);
  });

  test("onto drum pads: one a pad, each played to its end", () async {
    var said = await c.sliceToInstrument(pads: true);
    expect(said, contains("8 slices on drum pads"));
    var part = (c.document.elements.last as AudioElement).instrument!;
    expect(part.look, InstrumentLook.drums);
    expect(part.slices!.oneShot, isTrue);
    // The bottom row of pads first: the kick's.
    expect(part.slices!.keys.first, 36);
    expect(part.slices!.keys.toSet(), hasLength(8), reason: "a pad each");
  });

  test("its slices kept with the canvas", () {
    var part = const InstrumentPart(
        sound: InstrumentSound.slices,
        slices: SliceKit("beat.wav", [0, 0.5, 1.0], [36, 37], oneShot: true));
    var back = InstrumentPart.fromJson(part.toJson());
    expect(back.sound, InstrumentSound.slices);
    expect(back.slices, part.slices);
    expect(back.signature, part.signature);
    expect(
        part
            .copyWith(
                slices: const SliceKit("beat.wav", [0, 0.6, 1.0], [36, 37]))
            .signature,
        isNot(part.signature),
        reason: "other slices are another sound");
  });

  test("a slice's key plays that slice, at its own pitch", () {
    var (l, r) = _hits();
    var kit = SliceKit("beat.wav", [for (var b = 0; b <= 8; b++) b * 0.5],
        [for (var i = 0; i < 8; i++) 36 + i]);
    var font = SoundFont.ofSlices(l, r, kit);
    // The fourth slice, a 500Hz hit at 0.3 loud, struck on its key.
    var (pl, pr) = renderPart(
        InstrumentPart(
            sound: InstrumentSound.slices,
            slices: kit,
            notes: const [MidiNote(39, 0, 0.4, 127)]),
        font);
    var peak = 0.0;
    for (var i = 0; i < _rate ~/ 4; i++) {
      peak = math.max(peak, math.max(pl[i].abs(), pr[i].abs()));
    }
    expect(peak, greaterThan(0.05), reason: "it sounds");
    // Its pitch: zero crossings over 50ms near its start, about 500Hz.
    var crossings = 0;
    for (var i = 200; i < 200 + _rate ~/ 20; i++) {
      if ((pl[i] >= 0) != (pl[i + 1] >= 0)) crossings++;
    }
    expect(crossings / 2 / 0.05, closeTo(500, 40));
  });
}
