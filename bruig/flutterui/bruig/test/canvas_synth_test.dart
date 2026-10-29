import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/media/synth/part_render.dart';
import 'package:bruig/plugin_system/canvas/media/synth/sampler.dart';
import 'package:bruig/plugin_system/canvas/media/synth/soundfont.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_synth_test.dart is the instruments' sound: a SoundFont bank read,
// its notes played at their pitch and shaped by their envelope, the piano
// of our own, and a part played into sound ahead of time.

/// tinyBank is a SoundFont of one preset, one instrument and one sample:
/// a sine of 480Hz recorded at key 69, looped, with [gens] added to its
/// instrument zone.
Uint8List tinyBank({Map<int, int> gens = const {}}) {
  var out = BytesBuilder();
  void u16(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
  void u32(BytesBuilder b, int v) =>
      b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  void name(BytesBuilder b, String s, int n) {
    var bytes = List.filled(n, 0);
    for (var i = 0; i < s.length && i < n; i++) {
      bytes[i] = s.codeUnitAt(i);
    }
    b.add(bytes);
  }

  List<int> chunk(String id, List<int> body) {
    var b = BytesBuilder()..add(id.codeUnits);
    u32(b, body.length);
    b.add(body);
    if (body.length.isOdd) b.add([0]);
    return b.toBytes();
  }

  List<int> list(String type, List<List<int>> chunks) {
    var body = BytesBuilder()..add(type.codeUnits);
    for (var c in chunks) {
      body.add(c);
    }
    return chunk("LIST", body.toBytes());
  }

  // The sample: 4800 frames of a 480Hz sine -- exactly 48 periods -- and
  // the 46 zeros the specification asks for after it.
  const frames = 4800;
  var smpl = BytesBuilder();
  for (var i = 0; i < frames + 46; i++) {
    var v = i < frames ? (math.sin(2 * math.pi * 480 * i / 48000) * 16000).round() : 0;
    u16(smpl, v & 0xFFFF);
  }

  var info = list("INFO", [
    chunk("ifil", [2, 0, 1, 0]),
    chunk("INAM", "Tiny\u0000\u0000".codeUnits),
  ]);
  var sdta = list("sdta", [chunk("smpl", smpl.toBytes())]);

  var phdr = BytesBuilder();
  name(phdr, "Piano", 20);
  u16(phdr, 0); u16(phdr, 0); u16(phdr, 0);
  u32(phdr, 0); u32(phdr, 0); u32(phdr, 0);
  name(phdr, "EOP", 20);
  u16(phdr, 0); u16(phdr, 0); u16(phdr, 1);
  u32(phdr, 0); u32(phdr, 0); u32(phdr, 0);
  var pbag = BytesBuilder();
  u16(pbag, 0); u16(pbag, 0);
  u16(pbag, 1); u16(pbag, 0);
  var pgen = BytesBuilder();
  u16(pgen, Gen.instrument); u16(pgen, 0);
  u16(pgen, 0); u16(pgen, 0);
  var inst = BytesBuilder();
  name(inst, "Sine", 20);
  u16(inst, 0);
  name(inst, "EOI", 20);
  u16(inst, 1);
  var igenList = <(int, int)>[
    for (var e in gens.entries) (e.key, e.value),
    (Gen.sampleModes, 1),
    (Gen.sampleId, 0),
  ];
  var ibag = BytesBuilder();
  u16(ibag, 0); u16(ibag, 0);
  u16(ibag, igenList.length); u16(ibag, 0);
  var igen = BytesBuilder();
  for (var (op, v) in igenList) {
    u16(igen, op);
    u16(igen, v & 0xFFFF);
  }
  u16(igen, 0); u16(igen, 0);
  var shdr = BytesBuilder();
  name(shdr, "sine", 20);
  u32(shdr, 0); u32(shdr, frames); u32(shdr, 100); u32(shdr, 4700);
  u32(shdr, 48000);
  shdr.add([69, 0]);
  u16(shdr, 0); u16(shdr, 1);
  name(shdr, "EOS", 20);
  shdr.add(List.filled(26, 0));
  var pdta = list("pdta", [
    chunk("phdr", phdr.toBytes()),
    chunk("pbag", pbag.toBytes()),
    chunk("pmod", List.filled(10, 0)),
    chunk("pgen", pgen.toBytes()),
    chunk("inst", inst.toBytes()),
    chunk("ibag", ibag.toBytes()),
    chunk("imod", List.filled(10, 0)),
    chunk("igen", igen.toBytes()),
    chunk("shdr", shdr.toBytes()),
  ]);
  var body = BytesBuilder()
    ..add("sfbk".codeUnits)
    ..add(info)
    ..add(sdta)
    ..add(pdta);
  out.add(chunk("RIFF", body.toBytes()));
  return out.toBytes();
}

/// _hz is the frequency of [x], from where it crosses nought.
double _hz(Float32List x, int from, int to) {
  var crossings = 0;
  for (var i = from + 1; i < to; i++) {
    if ((x[i - 1] < 0) != (x[i] < 0)) crossings++;
  }
  return crossings / 2 / ((to - from) / mixRate);
}

double _rms(Float32List x, int from, int to) {
  var s = 0.0;
  for (var i = from; i < to; i++) {
    s += x[i] * x[i];
  }
  return math.sqrt(s / math.max(1, to - from));
}

(Float32List, Float32List) _play(Sampler s, int frames) {
  var l = Float32List(frames), r = Float32List(frames);
  s.render(l, r, frames);
  return (l, r);
}

void main() {
  group("a SoundFont bank", () {
    test("is read: its preset, its instrument's zone, its sample", () {
      var font = SoundFont.read(tinyBank());
      expect(font.name, "Tiny");
      expect(font.presets.single.name, "Piano");
      var zones = font.zones(font.presets.single, 60, 100);
      expect(zones.single.sample.name, "sine");
      expect(zones.single[Gen.sampleModes], 1);
      expect(zones.single[Gen.filterFc], 13500, reason: "a default");
    });

    test("is refused when it is not one", () {
      expect(() => SoundFont.read(Uint8List.fromList(List.filled(64, 1))),
          throwsFormatException);
    });

    test("plays a note at its pitch, looped past the sample's end", () {
      var font = SoundFont.read(tinyBank());
      var s = Sampler(font: font);
      s.noteOn(81, 127);
      var (l, _) = _play(s, mixRate);
      expect(_hz(l, 4800, 9600), closeTo(960, 10),
          reason: "an octave over the sample's own key");
      expect(_rms(l, 40000, 48000), greaterThan(0.05),
          reason: "the loop holds it past the sample's 0.1 seconds");
    });

    test("let go, it dies away in its release", () {
      var font = SoundFont.read(tinyBank(gens: {Gen.releaseVolEnv: 0}));
      var s = Sampler(font: font);
      s.noteOn(69, 100);
      _play(s, 4800);
      s.noteOff(69);
      // A release of nought timecents is a second to fall 100dB.
      var (l, _) = _play(s, mixRate * 2);
      expect(_rms(l, 0, 2400), greaterThan(_rms(l, 24000, 26400) * 10));
      expect(s.sounding, 0, reason: "and is done");
    });

    test("harder is louder, by velocity squared", () {
      var font = SoundFont.read(tinyBank());
      double level(int v) {
        var s = Sampler(font: font)..noteOn(69, v);
        var (l, _) = _play(s, 9600);
        return _rms(l, 4800, 9600);
      }

      expect(level(127) / level(64), closeTo(math.pow(127 / 64, 2), 0.6));
    });

    test("a zone's attenuation and pan are heard", () {
      var quiet = SoundFont.read(tinyBank(gens: {Gen.attenuation: 200}));
      var left = SoundFont.read(tinyBank(gens: {Gen.pan: -500}));
      var full = SoundFont.read(tinyBank());
      double rms(SoundFont f, {bool right = false}) {
        var s = Sampler(font: f)..noteOn(69, 127);
        var (l, r) = _play(s, 9600);
        return _rms(right ? r : l, 4800, 9600);
      }

      // 200 centibels at FluidSynth's 0.4: eight decibels down.
      expect(20 * math.log(rms(quiet) / rms(full)) / math.ln10,
          closeTo(-8, 0.2));
      expect(rms(left, right: true), lessThan(1e-6));
    });
  });

  group("the piano of our own", () {
    test("plays the key's pitch, and fades", () {
      var s = Sampler()..noteOn(57, 110);
      var (l, _) = _play(s, mixRate * 3);
      // Its fundamental, A3, by where the waveform repeats.
      var best = 0, bestLag = 0.0;
      for (var lag = 150; lag < 300; lag++) {
        var c = 0.0;
        for (var i = 2000; i < 6000; i++) {
          c += l[i] * l[i + lag];
        }
        if (c > bestLag) {
          bestLag = c;
          best = lag;
        }
      }
      expect(mixRate / best, closeTo(220, 4));
      expect(_rms(l, 0, 4800), greaterThan(_rms(l, mixRate * 2, mixRate * 3)));
    });
  });

  group("a part played ahead of time", () {
    test("each note where it is, and a release after the last", () {
      var font = SoundFont.read(tinyBank());
      var part = const InstrumentPart(
          sound: InstrumentSound.bank,
          notes: [MidiNote(69, 0.5, 0.5), MidiNote(81, 1.5, 0.5)]);
      expect(part.length, closeTo(2 + InstrumentPart.releaseTail, 1e-9));
      var (l, _) = renderPart(part, font);
      expect(l.length, (part.length * mixRate).ceil());
      expect(_rms(l, 0, 20000), 0, reason: "silent before the first note");
      expect(_hz(l, 26000, 47000), closeTo(480, 10));
      expect(_hz(l, 74000, 95000), closeTo(960, 10));
    });

    test("with no bank, the piano of our own plays it", () {
      var part = const InstrumentPart(
          sound: InstrumentSound.bank, notes: [MidiNote(60, 0, 0.5)]);
      var (l, _) = renderPart(part, null);
      expect(_rms(l, 0, 24000), greaterThan(0.01));
    });

    test("its signature changes with what it sounds like, and only then",
        () {
      const a = InstrumentPart(notes: [MidiNote(60, 0, 1)]);
      expect(a.copyWith(lowKey: 21, keys: 88).signature, a.signature,
          reason: "the keyboard drawn is not the sound");
      expect(a.copyWith(program: 40).signature, isNot(a.signature));
      expect(a.copyWith(notes: const [MidiNote(62, 0, 1)]).signature,
          isNot(a.signature));
      expect(a.needsPlaying, isTrue);
      expect(a.copyWith(rendered: a.signature).needsPlaying, isFalse);
      var back = InstrumentPart.fromJson(a.toJson());
      expect(back.notes, a.notes);
    });

    test("the WAV is the mix rate, sixteen-bit stereo", () {
      var wav = wav16(Float32List.fromList([0.5, -2]), Float32List(2));
      var d = ByteData.sublistView(wav);
      expect(d.getUint32(24, Endian.little), mixRate);
      expect(d.getInt16(44, Endian.little), 16384);
      expect(d.getInt16(48, Endian.little), -32767, reason: "held to full");
    });
  });
}
