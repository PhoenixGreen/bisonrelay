import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/colour_map.dart';

// metronome_element.dart is a metronome on a canvas for practice: a wooden
// pyramid, its pendulum swinging a beat each way and its weight sliding
// down as it speeds up, with buttons for the beats a minute (or tap), the
// beats in a bar, and start and stop; it clicks, the bar's first beat
// louder. Whether it is going is the reader's (see CanvasMetronomes), so a
// canvas opens with it still.

/// metronomeSlowest and metronomeFastest are the beats a minute it goes
/// between, as a clockwork one's.
const metronomeSlowest = 30.0, metronomeFastest = 240.0;

/// metronomeBeats are the bars it counts, as its settings offer them and
/// its beats button steps through them: 1 is every beat alike. Whatever it
/// holds is one of these.
const metronomeBeats = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];

/// MetronomeElement is a clockwork metronome on the page, swinging and
/// clicking while the editor has it going (controller/metronomes.dart).
class MetronomeElement extends CanvasElement {
  /// bpm is its beats a minute, metronomeSlowest to metronomeFastest.
  final double bpm;

  /// beats is beats in a bar, the first louder; 1 for all alike.
  final int beats;

  /// body is the wood's colour, and accent the lamp's and the playing's.
  final Color body;
  final Color accent;

  const MetronomeElement(
    super.base, {
    this.bpm = 100,
    this.beats = 4,
    this.body = const Color(0xFF7A4526),
    this.accent = const Color(0xFFE2622B),
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = MetronomeElement(ElementBase(id: ""));

  @override
  ElementKind get kind => ElementKind.metronome;

  @override
  CanvasElement rebase(ElementBase base) => MetronomeElement(base,
      bpm: bpm, beats: beats, body: body, accent: accent);

  MetronomeElement copyWith(
          {double? bpm, int? beats, Color? body, Color? accent}) =>
      MetronomeElement(base,
          bpm: (bpm ?? this.bpm)
              .clamp(metronomeSlowest, metronomeFastest)
              .roundToDouble(),
          beats: (beats ?? this.beats)
              .clamp(metronomeBeats.first, metronomeBeats.last),
          body: body ?? this.body,
          accent: accent ?? this.accent);

  @override
  MetronomeElement mapOwnColours(ColourMap f) {
    var p = ColourPass(f);
    var body = p(this.body);
    var accent = p(this.accent);
    if (!p.changed) return this;
    return copyWith(body: body, accent: accent);
  }

  @override
  Map<String, dynamic> props() => {
        "bpm": bpm,
        "beats": beats,
        "body": colorToJson(body),
        "accent": colorToJson(accent),
      };

  /// fromJson holds what it reads as copyWith holds what the panel sets:
  /// whole beats a minute, as fast as a clockwork one goes.
  factory MetronomeElement.fromJson(Map<String, dynamic> json, ElementBase b) =>
      MetronomeElement(b).copyWith(
          bpm: jsonDouble(json["bpm"], _defaults.bpm),
          beats: jsonInt(json["beats"], _defaults.beats),
          body: colorFromJson(json["body"], _defaults.body),
          accent: colorFromJson(json["accent"], _defaults.accent));
}

/// tempoWord is how [bpm] is marked on music: Largo to Presto.
String tempoWord(double bpm) => switch (bpm) {
      < 50 => "Largo",
      < 66 => "Adagio",
      < 80 => "Andante",
      < 108 => "Moderato",
      < 160 => "Allegro",
      _ => "Presto",
    };
