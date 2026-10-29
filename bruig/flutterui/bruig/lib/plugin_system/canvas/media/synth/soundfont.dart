import 'dart:convert';
import 'dart:typed_data';

// soundfont.dart reads a SoundFont 2 bank: its samples, and the presets
// and instruments that say which sample plays which key, how loud, tuned
// how, and shaped by which envelope. See the SoundFont 2.01 specification;
// generator numbers are the specification's.
//
// What a key and a velocity play is worked out once, here -- preset zones
// over instrument zones, global zones under both -- as a list of Zone,
// each a sample and every setting it plays with. sampler.dart plays them.

/// Gen is the generators this reader understands, by the specification's
/// numbers.
abstract final class Gen {
  static const startOffset = 0,
      endOffset = 1,
      loopStartOffset = 2,
      loopEndOffset = 3,
      startCoarse = 4,
      filterFc = 8,
      filterQ = 9,
      endCoarse = 12,
      pan = 17,
      delayVolEnv = 33,
      attackVolEnv = 34,
      holdVolEnv = 35,
      decayVolEnv = 36,
      sustainVolEnv = 37,
      releaseVolEnv = 38,
      keyToVolEnvHold = 39,
      keyToVolEnvDecay = 40,
      instrument = 41,
      keyRange = 43,
      velRange = 44,
      loopStartCoarse = 45,
      keynum = 46,
      velocity = 47,
      attenuation = 48,
      loopEndCoarse = 50,
      coarseTune = 51,
      fineTune = 52,
      sampleId = 53,
      sampleModes = 54,
      scaleTuning = 56,
      exclusiveClass = 57,
      rootKey = 58;

  static const count = 61;

  /// defaults are each generator's value where nothing sets it.
  static final Int32List defaults = () {
    var d = Int32List(count);
    for (var g in [
      delayVolEnv, attackVolEnv, holdVolEnv, decayVolEnv, releaseVolEnv, //
      21, 23, 25, 26, 27, 28, 30, // the modulation envelope and LFOs
    ]) {
      d[g] = -12000;
    }
    d[filterFc] = 13500;
    d[keyRange] = 127 << 8;
    d[velRange] = 127 << 8;
    d[keynum] = -1;
    d[velocity] = -1;
    d[scaleTuning] = 100;
    d[rootKey] = -1;
    return d;
  }();

  /// instrumentOnly are those a preset may not set: where in the sample a
  /// note plays from, the sample itself, how it loops and what overrides
  /// the key and velocity. A preset's values for the rest are added to its
  /// instrument's.
  static const instrumentOnly = {
    0, 1, 2, 3, 4, 12, 45, 50, 46, 47, 53, 54, 57, 58, //
  };
}

/// SfSample is one sample's header: where it is in the bank's samples, how
/// it loops, and the key it was recorded at.
class SfSample {
  final String name;
  final int start, end, loopStart, loopEnd, rate;
  final int originalKey;
  final int correction;
  const SfSample(this.name, this.start, this.end, this.loopStart,
      this.loopEnd, this.rate, this.originalKey, this.correction);
}

/// Zone is what one key at one velocity plays: a sample and every
/// generator worked out.
class Zone {
  final SfSample sample;
  final Int32List gens;
  const Zone(this.sample, this.gens);

  int operator [](int gen) => gens[gen];
}

class _RawZone {
  final Int32List gens;
  final Set<int> set;
  _RawZone(this.gens, this.set);

  int get keyLo => gens[Gen.keyRange] & 0xFF;
  int get keyHi => (gens[Gen.keyRange] >> 8) & 0xFF;
  int get velLo => gens[Gen.velRange] & 0xFF;
  int get velHi => (gens[Gen.velRange] >> 8) & 0xFF;
  bool covers(int key, int vel) =>
      key >= keyLo && key <= keyHi && vel >= velLo && vel <= velHi;
}

class _Instrument {
  final String name;
  final _RawZone? global;
  final List<_RawZone> zones;
  _Instrument(this.name, this.global, this.zones);
}

/// SfPreset is one preset: an instrument as a player chooses it, by bank
/// and program number.
class SfPreset {
  final String name;
  final int bank, program;
  final _RawZone? _global;
  final List<_RawZone> _zones;
  SfPreset._(this.name, this.bank, this.program, this._global, this._zones);
}

/// SoundFont is a bank, read.
class SoundFont {
  /// samples are the bank's sample data, sixteen-bit, every sample end to
  /// end.
  final Int16List samples;
  final List<SfPreset> presets;
  final List<_Instrument> _instruments;
  final List<SfSample> _headers;
  final String name;

  SoundFont._(this.samples, this.presets, this._instruments, this._headers,
      this.name);

  /// preset is the preset at [bank] and [program], or the bank's first
  /// with that program, or its first of all.
  SfPreset? preset(int bank, int program) {
    for (var p in presets) {
      if (p.bank == bank && p.program == program) return p;
    }
    for (var p in presets) {
      if (p.program == program && p.bank != 128) return p;
    }
    return presets.isEmpty ? null : presets.first;
  }

  /// zones are what [key] at [velocity] plays in [preset]: one zone for each
  /// sample sounding -- two for a stereo pair, more for a layered sound.
  List<Zone> zones(SfPreset preset, int key, int velocity) {
    var out = <Zone>[];
    for (var pz in preset._zones) {
      if (!pz.covers(key, velocity)) continue;
      var index = pz.gens[Gen.instrument];
      if (index < 0 || index >= _instruments.length) continue;
      var inst = _instruments[index];
      for (var iz in inst.zones) {
        if (!iz.covers(key, velocity)) continue;
        var id = iz.gens[Gen.sampleId];
        if (id < 0 || id >= _headers.length) continue;
        var gens = Int32List.fromList(Gen.defaults);
        // The instrument's global zone, then its own: each overrides.
        for (var src in [inst.global, iz]) {
          if (src == null) continue;
          for (var g in src.set) {
            gens[g] = src.gens[g];
          }
        }
        // The preset's, added on top -- the global zone's where the zone's
        // own does not set it.
        for (var g = 0; g < Gen.count; g++) {
          if (Gen.instrumentOnly.contains(g) ||
              g == Gen.keyRange ||
              g == Gen.velRange ||
              g == Gen.instrument) {
            continue;
          }
          int? add;
          if (pz.set.contains(g)) {
            add = pz.gens[g];
          } else if (preset._global?.set.contains(g) == true) {
            add = preset._global!.gens[g];
          }
          if (add != null) gens[g] += add;
        }
        out.add(Zone(_headers[id], gens));
      }
    }
    return out;
  }

  /// read reads a bank from its bytes, or throws a FormatException.
  static SoundFont read(Uint8List bytes) {
    var data = ByteData.sublistView(bytes);
    String tag(int at) => ascii.decode(bytes.sublist(at, at + 4),
        allowInvalid: true);
    if (bytes.length < 12 || tag(0) != "RIFF" || tag(8) != "sfbk") {
      throw const FormatException("Not a SoundFont 2 bank");
    }
    Int16List? smpl;
    var name = "";
    var chunks = <String, (int, int)>{};
    void walk(int from, int to) {
      var at = from;
      while (at + 8 <= to) {
        var id = tag(at);
        var size = data.getUint32(at + 4, Endian.little);
        var body = at + 8;
        if (id == "LIST") {
          walk(body + 4, body + size);
        } else {
          chunks[id] = (body, size);
        }
        at = body + size + (size & 1);
      }
    }

    walk(12, bytes.length);
    if (chunks["INAM"] case (var at, var size)) {
      name = utf8
          .decode(bytes.sublist(at, at + size), allowMalformed: true)
          .replaceAll("\u0000", "")
          .trim();
    }
    if (chunks["smpl"] case (var at, var size)) {
      // RIFF chunks start on even bytes, so the samples can be viewed in
      // place -- two hundred megabytes is not copied.
      smpl = at.isEven
          ? Int16List.view(bytes.buffer, bytes.offsetInBytes + at, size ~/ 2)
          : Int16List.fromList([
              for (var i = 0; i < size ~/ 2; i++)
                data.getInt16(at + i * 2, Endian.little)
            ]);
    }
    if (smpl == null) throw const FormatException("No samples");

    (int, int) chunk(String id) =>
        chunks[id] ?? (throw FormatException("No $id"));
    String text(int at, int n) {
      var raw = bytes.sublist(at, at + n);
      var end = raw.indexOf(0);
      return latin1.decode(end < 0 ? raw : raw.sublist(0, end)).trim();
    }

    // Generators and bags: a bag is a zone, its generators the run from its
    // index to the next bag's.
    List<(int, int)> gens(String id) {
      var (at, size) = chunk(id);
      return [
        for (var i = 0; i < size ~/ 4; i++)
          (
            data.getUint16(at + i * 4, Endian.little),
            data.getInt16(at + i * 4 + 2, Endian.little),
          )
      ];
    }

    List<int> bags(String id) {
      var (at, size) = chunk(id);
      return [
        for (var i = 0; i < size ~/ 4; i++)
          data.getUint16(at + i * 4, Endian.little)
      ];
    }

    _RawZone zone(List<(int, int)> list, int from, int to) {
      var g = Int32List(Gen.count);
      var set = <int>{};
      for (var i = from; i < to && i < list.length; i++) {
        var (op, amount) = list[i];
        if (op >= Gen.count) continue;
        // Ranges are two bytes, low then high: kept as they were read.
        if (op == Gen.keyRange || op == Gen.velRange) {
          g[op] = amount & 0xFFFF;
        } else if (op == Gen.instrument || op == Gen.sampleId) {
          g[op] = amount & 0xFFFF;
        } else {
          g[op] = amount;
        }
        set.add(op);
      }
      for (var k in [Gen.keyRange, Gen.velRange]) {
        if (!set.contains(k)) g[k] = Gen.defaults[k];
      }
      return _RawZone(g, set);
    }

    (_RawZone?, List<_RawZone>) zonesOf(
        List<int> bagList, List<(int, int)> genList, int from, int to,
        int terminal) {
      _RawZone? global;
      var out = <_RawZone>[];
      for (var b = from; b < to && b + 1 < bagList.length; b++) {
        var z = zone(genList, bagList[b], bagList[b + 1]);
        if (!z.set.contains(terminal)) {
          // The first zone, with no instrument or sample, is the global one.
          if (b == from) global = z;
          continue;
        }
        out.add(z);
      }
      return (global, out);
    }

    // Samples.
    var (shAt, shSize) = chunk("shdr");
    var headers = <SfSample>[];
    for (var i = 0; i < shSize ~/ 46 - 1; i++) {
      var at = shAt + i * 46;
      headers.add(SfSample(
        text(at, 20),
        data.getUint32(at + 20, Endian.little),
        data.getUint32(at + 24, Endian.little),
        data.getUint32(at + 28, Endian.little),
        data.getUint32(at + 32, Endian.little),
        data.getUint32(at + 36, Endian.little),
        data.getUint8(at + 40),
        data.getInt8(at + 41),
      ));
    }

    // Instruments.
    var iBags = bags("ibag");
    var iGens = gens("igen");
    var (inAt, inSize) = chunk("inst");
    var instruments = <_Instrument>[];
    var count = inSize ~/ 22;
    for (var i = 0; i < count - 1; i++) {
      var at = inAt + i * 22;
      var from = data.getUint16(at + 20, Endian.little);
      var to = data.getUint16(at + 22 + 20, Endian.little);
      var (global, zones) = zonesOf(iBags, iGens, from, to, Gen.sampleId);
      instruments.add(_Instrument(text(at, 20), global, zones));
    }

    // Presets.
    var pBags = bags("pbag");
    var pGens = gens("pgen");
    var (phAt, phSize) = chunk("phdr");
    var presets = <SfPreset>[];
    var pCount = phSize ~/ 38;
    for (var i = 0; i < pCount - 1; i++) {
      var at = phAt + i * 38;
      var from = data.getUint16(at + 24, Endian.little);
      var to = data.getUint16(at + 38 + 24, Endian.little);
      var (global, zones) = zonesOf(pBags, pGens, from, to, Gen.instrument);
      presets.add(SfPreset._(
        text(at, 20),
        data.getUint16(at + 22, Endian.little),
        data.getUint16(at + 20, Endian.little),
        global,
        zones,
      ));
    }
    presets.sort((a, b) => a.bank != b.bank
        ? a.bank.compareTo(b.bank)
        : a.program.compareTo(b.program));
    return SoundFont._(smpl, presets, instruments, headers, name);
  }
}
