import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/decode.dart';
import 'package:bruig/plugin_system/canvas/media/synth/sampler.dart';
import 'package:bruig/plugin_system/canvas/media/synth/soundfont.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';

// live_instrument.dart is a channel's instrument played live, defined once
// for the editor's isolate and the mix worker so the two cannot drift.

/// LiveInstrument is a sampler played live, as an endless track.
class LiveInstrument implements TrackSource {
  /// which is what it plays, as liveWhich has it: a key wanting another
  /// sound is played by another instrument.
  final String which;
  final Sampler sampler;
  LiveInstrument(this.which, this.sampler);

  /// LiveInstrument.of plays [part], on [font] for a bank or slices part.
  LiveInstrument.of(InstrumentPart part, SoundFont? font)
      : which = liveWhich(part, font),
        sampler = Sampler(
            font: part.sound == InstrumentSound.builtin ? null : font,
            bank: part.bank,
            program: part.program,
            look: part.look,
            patch: part.sound == InstrumentSound.patch ? part.patch : null);

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

/// liveWhich is what playing [part] on [font] sounds like, to tell whether
/// the channel's instrument can play its next key.
String liveWhich(InstrumentPart part, SoundFont? font) =>
    "${part.look.name}:${part.sound.name}:${part.bank}:${part.program}:"
    "${font != null && part.sound != InstrumentSound.builtin}:"
    "${part.sound == InstrumentSound.slices ? part.slices?.key : null}:"
    // A rewired patch is another instrument; other changes play on.
    "${part.sound == InstrumentSound.patch ? part.patch?.wiring : null}";
