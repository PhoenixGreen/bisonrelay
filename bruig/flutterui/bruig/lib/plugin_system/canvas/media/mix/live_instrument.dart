import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/decode.dart';
import 'package:bruig/plugin_system/canvas/media/synth/sampler.dart';
import 'package:bruig/plugin_system/canvas/media/synth/soundfont.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';

// live_instrument.dart is a channel's instrument played live -- keys on a
// keyboard, the editor's own -- as the mix plays it: the same here, where
// the mix runs on the editor's isolate, and in the mix worker (Ken's
// systems review, 2026-11-08: the two had a copy each, and their copies of
// which sound to play had come apart).

/// LiveInstrument is a sampler played live, as an endless track.
class LiveInstrument implements TrackSource {
  /// which is what it plays, as liveWhich has it: a key pressed with
  /// another sound to play is played by another.
  final String which;
  final Sampler sampler;
  LiveInstrument(this.which, this.sampler);

  /// LiveInstrument.of plays [part] -- on [font], for a part played on a
  /// bank or on its slices.
  LiveInstrument.of(InstrumentPart part, SoundFont? font)
      : which = liveWhich(part, font),
        sampler = Sampler(
            font: part.sound == InstrumentSound.builtin ? null : font,
            bank: part.bank,
            program: part.program,
            look: part.look);

  @override
  int get frames => 1 << 40;

  @override
  int read(Float32List l, Float32List r, int n) {
    l.fillRange(0, n, 0);
    r.fillRange(0, n, 0);
    sampler.render(l, r, n);
    return n;
  }

  @override
  void seek(int frame) {}

  @override
  void close() => sampler.allOff();
}

/// liveWhich is what playing [part] on [font] sounds like, for telling
/// whether the instrument playing a channel can play its next key.
String liveWhich(InstrumentPart part, SoundFont? font) =>
    "${part.look.name}:${part.sound.name}:${part.bank}:${part.program}:"
    "${font != null && part.sound != InstrumentSound.builtin}:"
    "${part.sound == InstrumentSound.slices ? part.slices?.key : null}";
