import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/media/synth/sampler.dart';
import 'package:bruig/plugin_system/canvas/media/synth/soundfont.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

// part_render.dart plays an instrument's part into sound -- once, ahead of
// time -- and keeps the sound bank it is played with.
//
// The bank is MuseScore General (MIT; see its licence, which goes with what
// is made from it), downloaded when it is first asked for, to the Canvas
// library's "soundbanks" folder. Until it is there, the piano of our own
// plays.

/// soundBankUrl is where the bank comes from: MuseScore's own mirror.
const soundBankUrl =
    "https://ftp.osuosl.org/pub/musescore/soundfont/MuseScore_General/"
    "MuseScore_General.sf2";

/// soundBankBytes is how big it is, for saying so before it is fetched.
const soundBankBytes = 215614036;

/// soundBankPath is where the bank is kept, whether or not it is there.
Future<String> soundBankPath() async => path.join(
    await CanvasStorage.libraryDir(), "soundbanks", "MuseScore_General.sf2");

/// soundBankReady is whether the bank has been downloaded.
Future<bool> soundBankReady() async {
  var file = File(await soundBankPath());
  return await file.exists() && await file.length() == soundBankBytes;
}

/// downloadSoundBank fetches the bank, telling [progress] how much of it
/// has arrived, nought to one. True once it is there.
Future<bool> downloadSoundBank({void Function(double share)? progress}) async {
  var target = await soundBankPath();
  var partial = File("$target.part");
  var client = HttpClient();
  try {
    await Directory(path.dirname(target)).create(recursive: true);
    var request = await client.getUrl(Uri.parse(soundBankUrl));
    var response = await request.close();
    if (response.statusCode != 200) return false;
    var sink = partial.openWrite();
    var got = 0;
    await for (var chunk in response) {
      sink.add(chunk);
      got += chunk.length;
      progress?.call(math.min(1.0, got / soundBankBytes));
    }
    await sink.close();
    if (got != soundBankBytes) {
      await partial.delete();
      return false;
    }
    await partial.rename(target);
    return true;
  } catch (exception) {
    debugPrint("Unable to download the sound bank: $exception");
    try {
      if (await partial.exists()) await partial.delete();
    } catch (_) {}
    return false;
  } finally {
    client.close(force: true);
  }
}

SoundFont? _loaded;
String? _loadedFrom;

/// loadSoundBank is the bank, read -- once, and kept: two hundred megabytes
/// is read in a fraction of a second, but not every time a key is pressed.
/// Null where it has not been downloaded, or cannot be read.
Future<SoundFont?> loadSoundBank() async {
  var at = await soundBankPath();
  if (_loaded != null && _loadedFrom == at) return _loaded;
  if (!await soundBankReady()) return null;
  try {
    _loaded = SoundFont.read(await File(at).readAsBytes());
    _loadedFrom = at;
    return _loaded;
  } catch (exception) {
    debugPrint("Unable to read the sound bank: $exception");
    return null;
  }
}

/// renderPart is [part] played on [font] -- or, with none, the piano of our
/// own -- as 48kHz stereo: every note starting and stopping on its own
/// sample.
(Float32List, Float32List) renderPart(InstrumentPart part, SoundFont? font) {
  var total = (part.length * mixRate).ceil();
  var l = Float32List(total), r = Float32List(total);
  if (total == 0) return (l, r);
  var sampler = Sampler(
      font: part.sound == InstrumentSound.bank ? font : null,
      bank: part.bank,
      program: part.program,
      look: part.look);
  // Every press and every let-go, in order; a let-go before a press at the
  // same moment, so a note played again straight away sounds again.
  var events = <(int, bool, MidiNote)>[
    for (var n in part.notes) ...[
      ((n.start * mixRate).round(), true, n),
      ((n.end * mixRate).round(), false, n),
    ]
  ]..sort((a, b) => a.$1 != b.$1
      ? a.$1.compareTo(b.$1)
      : (a.$2 ? 1 : 0).compareTo(b.$2 ? 1 : 0));
  const block = 256;
  var bl = Float32List(block), br = Float32List(block);
  var next = 0;
  var at = 0;
  var curves = part.controls.entries.where((e) => e.value.isNotEmpty).toList();
  while (at < total) {
    // The controllers where their curves are now, before this block's
    // presses: a pedal down at a note's start holds it.
    for (var e in curves) {
      sampler.control(e.key, controlAt(e.value, at / mixRate, e.key.rest));
    }
    while (next < events.length && events[next].$1 <= at) {
      var (_, on, n) = events[next++];
      on ? sampler.noteOn(n.key, n.velocity) : sampler.noteOff(n.key);
    }
    var until = next < events.length ? events[next].$1 : total;
    var n = math.max(1, math.min(block, math.min(until, total) - at));
    bl.fillRange(0, n, 0);
    br.fillRange(0, n, 0);
    sampler.render(bl, br, n);
    l.setRange(at, at + n, bl);
    r.setRange(at, at + n, br);
    at += n;
  }
  return (l, r);
}

/// partWav is [part] played -- see renderPart -- as the bytes of a 16-bit
/// stereo WAV, in an isolate. The bank, where the part asks for it, is read
/// there from [bankPath].
Future<Uint8List> partWav(InstrumentPart part, {String? bankPath}) =>
    Isolate.run(() async {
      SoundFont? font;
      if (part.sound == InstrumentSound.bank && bankPath != null) {
        try {
          font = SoundFont.read(await File(bankPath).readAsBytes());
        } catch (_) {}
      }
      var (l, r) = renderPart(part, font);
      return wav16(l, r);
    });

/// wav16 is [l] and [r] as a 16-bit stereo WAV at the mix rate, any peak
/// over full scale held to it.
Uint8List wav16(Float32List l, Float32List r) {
  var frames = l.length;
  var b = ByteData(44 + frames * 4);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, "RIFF");
  b.setUint32(4, 36 + frames * 4, Endian.little);
  tag(8, "WAVE");
  tag(12, "fmt ");
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 2, Endian.little);
  b.setUint32(24, mixRate, Endian.little);
  b.setUint32(28, mixRate * 4, Endian.little);
  b.setUint16(32, 4, Endian.little);
  b.setUint16(34, 16, Endian.little);
  tag(36, "data");
  b.setUint32(40, frames * 4, Endian.little);
  for (var i = 0; i < frames; i++) {
    b.setInt16(
        44 + i * 4, (l[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
    b.setInt16(
        46 + i * 4, (r[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  return b.buffer.asUint8List();
}
