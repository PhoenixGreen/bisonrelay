import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/media/synth/sampler.dart';
import 'package:bruig/plugin_system/canvas/media/synth/soundfont.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_network.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

// part_render.dart renders an instrument's part to sound ahead of time,
// and fetches the sound bank it is played with.
//
// The bank is MuseScore General (MIT; its licence goes with what is made
// from it), downloaded on first use to the Canvas library's soundbanks
// folder. Until then the built-in piano plays.

/// soundBankUrl is where the bank comes from: MuseScore's own mirror.
const soundBankUrl =
    "https://ftp.osuosl.org/pub/musescore/soundfont/MuseScore_General/"
    "MuseScore_General.sf2";

/// soundBankBytes is the bank's exact size: shown before fetching, and
/// checked to tell a complete download.
const soundBankBytes = 215614036;

/// soundBankPath is where the bank is kept, whether or not it is there.
Future<String> soundBankPath() async => path.join(
    await CanvasStorage.libraryDir(), canvasSoundBankFolder, "MuseScore_General.sf2");

/// soundBankReady is whether the bank has been downloaded.
Future<bool> soundBankReady() async {
  var file = File(await soundBankPath());
  return await file.exists() && await file.length() == soundBankBytes;
}

/// soundBankProgress is how much of the bank has arrived while it is being
/// fetched, nought to one, and null otherwise: for whichever panel shows it.
final ValueNotifier<double?> soundBankProgress = ValueNotifier(null);

Future<bool>? _fetching;

/// downloadSoundBank fetches the bank, telling [progress] how much of it
/// has arrived, nought to one. True once it is there. Asked again while it
/// is being fetched, it is the same fetch: two into one file would each
/// undo the other.
Future<bool> downloadSoundBank({void Function(double share)? progress}) {
  void heard() => progress?.call(soundBankProgress.value ?? 0);
  if (progress != null) soundBankProgress.addListener(heard);
  var fetch = _fetching ??= _download().whenComplete(() {
    _fetching = null;
    soundBankProgress.value = null;
  });
  return fetch.whenComplete(() => soundBankProgress.removeListener(heard));
}

Future<bool> _download() async {
  void progress(double share) => soundBankProgress.value = share;
  progress(0);
  if (await networkIsProxied()) return false;
  var target = await soundBankPath();
  var partial = File("$target.part");
  var client = canvasHttpClient();
  try {
    await Directory(path.dirname(target)).create(recursive: true);
    var response = await canvasGet(client, Uri.parse(soundBankUrl));
    if (response?.statusCode != 200) return false;
    var sink = partial.openWrite();
    var got = 0;
    await for (var chunk in response!.timeout(const Duration(seconds: 60))) {
      sink.add(chunk);
      got += chunk.length;
      progress(math.min(1.0, got / soundBankBytes));
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

/// loadedSoundBank is the bank once read, at once: what a key pressed
/// plays on, without asking the disk where the bank is every time.
SoundFont? get loadedSoundBank => _loaded;

/// loadSoundBank is the bank, read once and kept. Null where it has not
/// been downloaded or cannot be read.
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

/// renderPart is [part] played on [font] (or, with none, the built-in
/// piano) as 48kHz stereo, every note starting and stopping on its own
/// sample.
(Float32List, Float32List) renderPart(InstrumentPart part, SoundFont? font) {
  var total = (part.length * mixRate).ceil();
  var l = Float32List(total), r = Float32List(total);
  if (total == 0) return (l, r);
  var sampler = Sampler(
      font: part.sound == InstrumentSound.builtin ? null : font,
      bank: part.bank,
      program: part.program,
      look: part.look,
      shape: part.shape);
  // Note-offs sort before note-ons at the same moment, so a note played
  // again straight away sounds again.
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
  var curves = [
    for (var e in part.controls.entries)
      if (e.value.isNotEmpty) (e.key, ControlCursor(e.value, e.key.rest)),
  ];
  // How many notes hold each key: two overlapping on one key -- a chord's
  // and a scale's both landing there, or drawn so -- are let go by the last
  // of them, as keys played live are, not cut short by the first.
  var holding = <int, int>{};
  while (at < total) {
    // Controllers are set before this block's notes, so a pedal down at a
    // note's start holds it.
    for (var (control, cursor) in curves) {
      sampler.control(control, cursor.at(at / mixRate));
    }
    while (next < events.length && events[next].$1 <= at) {
      var (_, on, n) = events[next++];
      if (on) {
        holding[n.key] = (holding[n.key] ?? 0) + 1;
        sampler.noteOn(n.key, n.velocity);
      } else {
        var left = (holding[n.key] ?? 1) - 1;
        if (left <= 0) {
          holding.remove(n.key);
          sampler.noteOff(n.key);
        } else {
          holding[n.key] = left;
        }
      }
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

/// partWav is [renderPart] as a 16-bit stereo WAV, run in an isolate,
/// which reads the bank from [bankPath] where the part uses it -- or, a
/// part of slices, its sound (see sliceAudioReader).
Future<Uint8List> partWav(InstrumentPart part, {String? bankPath}) async {
  var kit = part.slices;
  (Float32List, Float32List)? sound;
  if (part.sound == InstrumentSound.slices && kit != null) {
    sound = await sliceAudioReader?.call(kit.assetId);
  }
  return Isolate.run(() async {
    SoundFont? font;
    if (part.sound == InstrumentSound.bank && bankPath != null) {
      try {
        font = SoundFont.read(await File(bankPath).readAsBytes());
      } catch (_) {}
    }
    if (sound case (var l, var r) when kit != null) {
      font = SoundFont.ofSlices(l, r, kit);
    }
    var (l, r) = renderPart(part, font);
    return wav16(l, r);
  });
}

/// sliceAudioReader reads a stored sound as 48kHz stereo, for an
/// instrument of its slices: set by the canvas (CanvasController.clipAudio).
Future<(Float32List, Float32List)?> Function(String assetId)? sliceAudioReader;

final Map<String, Future<SoundFont?>> _sliceFonts = {};
final Map<String, SoundFont> _sliceFontsMade = {};

/// sliceFontOf is [kit] made a bank to play live, made once and kept.
Future<SoundFont?> sliceFontOf(SliceKit kit) =>
    _sliceFonts[kit.key] ??= () async {
      var sound = await sliceAudioReader?.call(kit.assetId);
      if (sound == null) {
        _sliceFonts.remove(kit.key);
        return null;
      }
      var (l, r) = sound;
      var font = await Isolate.run(() => SoundFont.ofSlices(l, r, kit));
      _sliceFontsMade[kit.key] = font;
      return font;
    }();

/// loadedSliceFont is [kit]'s bank where it has been made already: for a
/// key to sound at once.
SoundFont? loadedSliceFont(SliceKit kit) => _sliceFontsMade[kit.key];

/// wav16 is [l] and [r] as a 16-bit stereo WAV at the mix rate, clipped at
/// full scale.
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
