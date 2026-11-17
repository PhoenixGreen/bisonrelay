import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// metronome_element.dart is a metronome on a canvas for practice: a wooden
// pyramid, its pendulum swinging a beat each way and its weight sliding
// down as it speeds up, with buttons for the beats a minute (or tap), the
// beats in a bar, and start and stop; it clicks, the bar's first beat
// louder. Whether it is going is the reader's (see CanvasMetronomes), so a
// canvas opens with it still.

/// metronomeSlowest and metronomeFastest are the beats a minute it goes
/// between, as a clockwork one's.
const metronomeSlowest = 30.0, metronomeFastest = 240.0;

/// metronomeBeats are the bars it counts, as its beats button steps through
/// them: 1 is every beat alike.
const metronomeBeats = [1, 2, 3, 4, 6];

class MetronomeElement extends CanvasElement {
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
          beats: (beats ?? this.beats).clamp(1, 12),
          body: body ?? this.body,
          accent: accent ?? this.accent);

  @override
  Map<String, dynamic> props() => {
        "bpm": bpm,
        "beats": beats,
        "body": colorToJson(body),
        "accent": colorToJson(accent),
      };

  factory MetronomeElement.fromJson(Map<String, dynamic> json, ElementBase b) =>
      MetronomeElement(b,
          bpm: (json["bpm"] is num ? (json["bpm"] as num).toDouble() : 100.0)
              .clamp(metronomeSlowest, metronomeFastest)
              .toDouble(),
          beats: (json["beats"] is num ? (json["beats"] as num).toInt() : 4)
              .clamp(1, 12),
          body: colorFromJson(json["body"], const Color(0xFF7A4526)),
          accent: colorFromJson(json["accent"], const Color(0xFFE2622B)));
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
