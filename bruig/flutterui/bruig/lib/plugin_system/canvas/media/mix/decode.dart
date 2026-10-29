import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:flutter/foundation.dart';

// decode.dart reads a sound file as 48kHz stereo floats, a block at a time,
// for the mix engine to play.
//
// Through miniaudio -- the decoder SoLoud itself is built on, compiled into
// its plugin -- called directly, since flutter_soloud has no call that hands
// back a file's samples (its readSamples is for drawing a waveform: one
// level per point, not the sound). So it reads exactly what SoLoud would
// have played: MP3, WAV and FLAC by miniaudio's own decoders, Ogg Vorbis and
// Opus by the libvorbis backend SoLoud registers for them.
//
// The two structures handed across are miniaudio 0.11's. Their layout was
// measured with the compiler against flutter_soloud 4.1.7's own header, on
// arm64 and x86_64 alike: ma_decoder_config is 144 bytes with the custom
// backend list at 120 and its count at 128; ma_decoder is 552 bytes. A
// decoder is given far more room than that, so a rebuild that grows it a
// little does no harm. If flutter_soloud is upgraded, measure again.

/// TrackSource is a sound the engine reads from: a file being decoded, or --
/// in the tests -- samples already in memory.
abstract class TrackSource {
  /// frames is how long it is, in frames at mixRate.
  int get frames;

  /// read fills [l] and [r] from where it is, up to [n] frames, and says how
  /// many it filled: fewer at the end.
  int read(Float32List l, Float32List r, int n);

  /// seek moves to [frame].
  void seek(int frame);

  void close();
}

/// MemoryTrack is samples already in memory.
class MemoryTrack implements TrackSource {
  final Float32List l, r;
  int _at = 0;
  MemoryTrack(this.l, this.r);

  @override
  int get frames => l.length;

  @override
  int read(Float32List outL, Float32List outR, int n) {
    var count = (l.length - _at).clamp(0, n);
    outL.setRange(0, count, l, _at);
    outR.setRange(0, count, r, _at);
    _at += count;
    return count;
  }

  @override
  void seek(int frame) => _at = frame.clamp(0, l.length);

  @override
  void close() {}
}

typedef _ConfigInitC = _Config Function(ffi.Int32, ffi.Uint32, ffi.Uint32);
typedef _ConfigInit = _Config Function(int, int, int);

final class _Config extends ffi.Struct {
  @ffi.Array(144)
  external ffi.Array<ffi.Uint8> bytes;
}

/// _Miniaudio is the handful of miniaudio's functions the decoder calls,
/// looked up once.
class _Miniaudio {
  final ffi.Pointer<ffi.Void> Function(int, ffi.Pointer<ffi.Void>) malloc;
  final void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>) free;
  final _ConfigInit configInit;
  final int Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>,
      ffi.Pointer<ffi.Uint8>) initFile;
  final int Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Float>, int,
      ffi.Pointer<ffi.Uint64>) readFrames;
  final int Function(ffi.Pointer<ffi.Uint8>, int) seek;
  final int Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint64>) length;
  final int Function(ffi.Pointer<ffi.Uint8>) uninit;
  final ffi.Pointer<ffi.Void>? vorbis;

  _Miniaudio(ffi.DynamicLibrary lib)
      : malloc = lib.lookupFunction<
            ffi.Pointer<ffi.Void> Function(ffi.Size, ffi.Pointer<ffi.Void>),
            ffi.Pointer<ffi.Void> Function(
                int, ffi.Pointer<ffi.Void>)>("ma_malloc"),
        free = lib.lookupFunction<
            ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>),
            void Function(
                ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>)>("ma_free"),
        configInit = lib.lookupFunction<_ConfigInitC, _ConfigInit>(
            "ma_decoder_config_init"),
        initFile = lib.lookupFunction<
            ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>,
                ffi.Pointer<ffi.Uint8>),
            int Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>,
                ffi.Pointer<ffi.Uint8>)>("ma_decoder_init_file"),
        readFrames = lib.lookupFunction<
            ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Float>,
                ffi.Uint64, ffi.Pointer<ffi.Uint64>),
            int Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Float>, int,
                ffi.Pointer<ffi.Uint64>)>("ma_decoder_read_pcm_frames"),
        seek = lib.lookupFunction<
            ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.Uint64),
            int Function(
                ffi.Pointer<ffi.Uint8>, int)>("ma_decoder_seek_to_pcm_frame"),
        length = lib.lookupFunction<
            ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint64>),
            int Function(ffi.Pointer<ffi.Uint8>,
                ffi.Pointer<ffi.Uint64>)>("ma_decoder_get_length_in_pcm_frames"),
        uninit = lib.lookupFunction<ffi.Int32 Function(ffi.Pointer<ffi.Uint8>),
            int Function(ffi.Pointer<ffi.Uint8>)>("ma_decoder_uninit"),
        vorbis = _optional(lib, "ma_decoding_backend_libvorbis");

  static ffi.Pointer<ffi.Void>? _optional(ffi.DynamicLibrary lib, String n) {
    try {
      return lib.lookup<ffi.Void>(n);
    } catch (_) {
      return null;
    }
  }

  ffi.Pointer<T> alloc<T extends ffi.NativeType>(int bytes) =>
      malloc(bytes, ffi.nullptr).cast<T>();

  void release(ffi.Pointer p) => free(p.cast(), ffi.nullptr);
}

/// miniaudioLibrary is where to find the library instead of the running
/// app: for a test that loads a built copy of the plugin to decode real
/// files with it.
@visibleForTesting
String? miniaudioLibrary;

/// _miniaudio is the library, or null where it cannot be had -- in the
/// tests, which do not load the plugin, and on the web.
_Miniaudio? get _miniaudio => _loaded ??= _load();
_Miniaudio? _loaded;

_Miniaudio? _load() {
  try {
    var lib = miniaudioLibrary != null
        ? ffi.DynamicLibrary.open(miniaudioLibrary!)
        : Platform.isLinux || Platform.isAndroid
            ? ffi.DynamicLibrary.open("libflutter_soloud_plugin.so")
            : Platform.isWindows
                ? ffi.DynamicLibrary.open("flutter_soloud_plugin.dll")
                : ffi.DynamicLibrary.process();
    return _Miniaudio(lib);
  } catch (exception) {
    debugPrint("The mix engine's decoder is unavailable: $exception");
    return null;
  }
}

/// canDecode is whether files can be decoded here at all.
bool get canDecode => _miniaudio != null;

/// FileTrack is a file decoded as it is read.
class FileTrack implements TrackSource {
  final _Miniaudio _ma;
  final ffi.Pointer<ffi.Uint8> _decoder;
  final ffi.Pointer<ffi.Uint8> _config;
  final ffi.Pointer<ffi.Float> _buffer;
  final ffi.Pointer<ffi.Uint64> _count;
  final ffi.Pointer<ffi.Pointer<ffi.Void>> _vtables;
  @override
  final int frames;
  bool _closed = false;

  static const int _decoderRoom = 8192;
  static const int _bufferFrames = 4096;

  FileTrack._(this._ma, this._decoder, this._config, this._buffer, this._count,
      this._vtables, this.frames);

  /// open decodes [path], or returns null where it cannot be.
  static FileTrack? open(String path) {
    var ma = _miniaudio;
    if (ma == null) return null;
    var decoder = ma.alloc<ffi.Uint8>(_decoderRoom);
    var config = ma.alloc<ffi.Uint8>(144);
    var count = ma.alloc<ffi.Uint64>(8);
    var name = utf8.encode(path);
    var cName = ma.alloc<ffi.Uint8>(name.length + 1);
    var vtables = ma.alloc<ffi.Pointer<ffi.Void>>(8);
    var ok = false;
    try {
      cName.asTypedList(name.length + 1)
        ..setRange(0, name.length, name)
        ..[name.length] = 0;
      decoder.asTypedList(_decoderRoom).fillRange(0, _decoderRoom, 0);
      // f32 is format 5; two channels; the mix's rate.
      var made = ma.configInit(5, 2, mixRate);
      var bytes = config.asTypedList(144);
      for (var i = 0; i < 144; i++) {
        bytes[i] = made.bytes[i];
      }
      // An Ogg file is read by the libvorbis backend, as SoLoud reads it.
      if (ma.vorbis case var v? when _isOgg(path)) {
        vtables.value = v.cast<ffi.Pointer<ffi.Void>>().value;
        (config + 120).cast<ffi.Pointer<ffi.Void>>().value = vtables.cast();
        (config + 128).cast<ffi.Uint32>().value = 1;
      }
      if (ma.initFile(cName, config, decoder) != 0) return null;
      if (ma.length(decoder, count) != 0) {
        ma.uninit(decoder);
        return null;
      }
      var frames = count.value;
      ok = true;
      return FileTrack._(ma, decoder, config,
          ma.alloc<ffi.Float>(_bufferFrames * 2 * 4), count, vtables, frames);
    } finally {
      ma.release(cName);
      if (!ok) {
        ma.release(decoder);
        ma.release(config);
        ma.release(count);
        ma.release(vtables);
      }
    }
  }

  static bool _isOgg(String path) {
    try {
      var f = File(path).openSync();
      try {
        var head = f.readSync(4);
        return head.length == 4 &&
            head[0] == 0x4F &&
            head[1] == 0x67 &&
            head[2] == 0x67 &&
            head[3] == 0x53;
      } finally {
        f.closeSync();
      }
    } catch (_) {
      return false;
    }
  }

  @override
  int read(Float32List l, Float32List r, int n) {
    if (_closed) return 0;
    var done = 0;
    while (done < n) {
      var want = (n - done).clamp(0, _bufferFrames);
      if (_ma.readFrames(_decoder, _buffer, want, _count) != 0 &&
          _count.value == 0) {
        break;
      }
      var got = _count.value;
      if (got == 0) break;
      var pcm = _buffer.asTypedList(got * 2);
      for (var i = 0; i < got; i++) {
        l[done + i] = pcm[i * 2];
        r[done + i] = pcm[i * 2 + 1];
      }
      done += got;
      if (got < want) break;
    }
    return done;
  }

  @override
  void seek(int frame) {
    if (_closed) return;
    _ma.seek(_decoder, frame.clamp(0, frames));
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _ma.uninit(_decoder);
    _ma.release(_decoder);
    _ma.release(_config);
    _ma.release(_buffer);
    _ma.release(_count);
    _ma.release(_vtables);
  }
}

/// ffmpegDecode is [path] -- or [length] seconds of it from [from] -- as
/// 48kHz stereo, by ffmpeg, or null where ffmpeg cannot read it.
///
/// A mono file is put on both sides at its own level, as the editor plays
/// one: ffmpeg's own mono-to-stereo spreads it at the -3dB of a centre pan,
/// and exports of a mono voice-over came out three decibels under what was
/// heard while editing. So it is decoded in its own channels and split here;
/// only a file of more than two is folded down by ffmpeg.
Future<(Float32List, Float32List)?> ffmpegDecode(String ffmpeg, String path,
    {double? from, double? length}) async {
  Future<ProcessResult> run(bool fold) => Process.run(
      ffmpeg,
      [
        "-hide_banner", //
        if (from != null) ...["-ss", from.toStringAsFixed(4)],
        if (length != null) ...["-t", length.toStringAsFixed(4)],
        "-i", path,
        "-f", "f32le", "-acodec", "pcm_f32le", "-ar", "$mixRate",
        if (fold) ...["-ac", "2"],
        "-",
      ],
      stdoutEncoding: null);
  var result = await run(false);
  if (result.exitCode != 0) return null;
  // How many channels it has, from what ffmpeg says of the input.
  var said = "${result.stderr}";
  var m = RegExp(r"Audio: [^\n]*?Hz, ([^,\n]+)").firstMatch(said);
  var layout = m?.group(1)?.trim() ?? "stereo";
  var channels = switch (layout) {
    "mono" => 1,
    "stereo" => 2,
    _ => int.tryParse(layout.split(" ").first) ?? 3,
  };
  if (channels > 2) {
    result = await run(true);
    if (result.exitCode != 0) return null;
    channels = 2;
  }
  var raw = result.stdout as List<int>;
  var bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
  var frames = bytes.lengthInBytes ~/ (4 * channels);
  if (frames == 0) return null;
  var all = bytes.buffer.asFloat32List(bytes.offsetInBytes, frames * channels);
  var l = Float32List(frames), r = Float32List(frames);
  for (var i = 0; i < frames; i++) {
    l[i] = all[i * channels];
    r[i] = all[i * channels + channels - 1];
  }
  return (l, r);
}

/// ffmpegTrack is [path] decoded whole by ffmpeg, for a file miniaudio
/// cannot read -- Ogg Opus, which SoLoud's Vorbis backend does not cover.
/// Null where ffmpeg cannot read it either.
Future<MemoryTrack?> ffmpegTrack(String ffmpeg, String path) async {
  var pcm = await ffmpegDecode(ffmpeg, path);
  return pcm == null ? null : MemoryTrack(pcm.$1, pcm.$2);
}
