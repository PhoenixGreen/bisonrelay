import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// sheet_element.dart is Sheet music: an instrument's part, engraved -- see
// notation.dart and sheet_painter.dart -- with the playhead on it as it
// plays, and practised against: the instrument played along with it, each
// note marked right or wrong as it goes.
//
// It shows the part of the instrument it follows, so a part recorded or
// read from a MIDI file is a score at once, and its score is played through
// that instrument's sound.

/// PracticeMode is how a take goes.
enum PracticeMode {
  /// listen plays the piece, the keys lit, and asks nothing.
  listen("Listen"),

  /// along plays at the tempo set and marks each note played.
  along("Play along"),

  /// wait holds on each note until it is played.
  wait("Wait for me");

  final String label;
  const PracticeMode(this.label);

  static PracticeMode fromName(String? name) =>
      values.firstWhere((m) => m.name == name, orElse: () => wait);
}

/// PracticeHands is which hand is practised: the other is played for you.
enum PracticeHands {
  right("Right"),
  left("Left"),
  both("Both");

  final String label;
  const PracticeHands(this.label);

  static PracticeHands fromName(String? name) =>
      values.firstWhere((m) => m.name == name, orElse: () => both);
}

class SheetElement extends CanvasElement {
  /// follows is the instrument whose part is shown, by element id.
  final String follows;
  final String title;
  final Color paper, ink;

  /// mode, hands and tempo are how it is practised; tempo is a share of
  /// the piece's own, from 0.4 to 1.2.
  final PracticeMode mode;
  final PracticeHands hands;
  final double tempo;

  const SheetElement(
    super.base, {
    this.follows = "",
    this.title = "",
    this.paper = const Color(0xFFFBFAF6),
    this.ink = const Color(0xFF1B1B1B),
    this.mode = PracticeMode.wait,
    this.hands = PracticeHands.both,
    this.tempo = 1,
  });

  @override
  ElementKind get kind => ElementKind.sheet;

  @override
  CanvasElement rebase(ElementBase base) => SheetElement(base,
      follows: follows,
      title: title,
      paper: paper,
      ink: ink,
      mode: mode,
      hands: hands,
      tempo: tempo);

  SheetElement copyWith({
    String? follows,
    String? title,
    Color? paper,
    Color? ink,
    PracticeMode? mode,
    PracticeHands? hands,
    double? tempo,
  }) =>
      SheetElement(base,
          follows: follows ?? this.follows,
          title: title ?? this.title,
          paper: paper ?? this.paper,
          ink: ink ?? this.ink,
          mode: mode ?? this.mode,
          hands: hands ?? this.hands,
          tempo: (tempo ?? this.tempo).clamp(0.4, 1.2));

  @override
  Map<String, dynamic> props() => {
        if (follows.isNotEmpty) "follows": follows,
        if (title.isNotEmpty) "title": title,
        "paper": colorToJson(paper),
        "ink": colorToJson(ink),
        if (mode != PracticeMode.wait) "mode": mode.name,
        if (hands != PracticeHands.both) "hands": hands.name,
        if (tempo != 1) "tempo": tempo,
      };

  factory SheetElement.fromJson(Map<String, dynamic> json, ElementBase b) =>
      SheetElement(b,
              follows: jsonString(json["follows"], ""),
              title: jsonString(json["title"], ""),
              paper: colorFromJson(json["paper"], const Color(0xFFFBFAF6)),
              ink: colorFromJson(json["ink"], const Color(0xFF1B1B1B)),
              mode: PracticeMode.fromName(json["mode"] as String?),
              hands: PracticeHands.fromName(json["hands"] as String?))
          .copyWith(tempo: jsonDouble(json["tempo"], 1));
}
