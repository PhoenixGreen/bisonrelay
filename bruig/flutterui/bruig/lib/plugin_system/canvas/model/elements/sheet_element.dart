import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// sheet_element.dart is Sheet music: the part of the instrument it follows,
// engraved (see notation.dart and sheet_painter.dart) with a playhead, and
// practised against, each note marked right or wrong as it is played.

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

/// SheetElement is a score of one instrument's part, played through that
/// instrument's sound.
class SheetElement extends CanvasElement {
  /// follows is the instrument whose part is shown, by element id.
  final String follows;

  /// score and part are the score part it shows (see music_score.dart),
  /// or "" for an instrument's own notes. Showing a score part, [follows]
  /// is that part's channel.
  final String score, part;
  final String title;
  final Color paper, ink;

  /// mode, hands and tempo are how it is practised; tempo is a share of
  /// the piece's own, from 0.4 to 1.2.
  final PracticeMode mode;
  final PracticeHands hands;
  final double tempo;

  /// key is the key signature (sharps positive, flats negative), or null to
  /// work it out: the instrument's Scale effect if it has one, else
  /// keyFifthsOf its notes.
  final int? key;

  /// lines is how many systems show at once (1 to 8), turned as a page when
  /// the playhead reaches the last.
  final int lines;

  /// playhead is whether the playhead's line is drawn; off, the notes under
  /// it are lit and that is all (Ken: "sometimes the highlight will be
  /// enough").
  final bool playhead;

  const SheetElement(
    super.base, {
    this.follows = "",
    this.score = "",
    this.part = "",
    this.title = "",
    this.paper = const Color(0xFFFBFAF6),
    this.ink = const Color(0xFF1B1B1B),
    this.mode = PracticeMode.wait,
    this.hands = PracticeHands.both,
    this.tempo = 1,
    this.key,
    this.lines = 2,
    this.playhead = true,
  });

  @override
  ElementKind get kind => ElementKind.sheet;

  @override
  CanvasElement rebase(ElementBase base) => SheetElement(base,
      follows: follows,
      score: score,
      part: part,
      title: title,
      paper: paper,
      ink: ink,
      mode: mode,
      hands: hands,
      tempo: tempo,
      key: key,
      lines: lines,
      playhead: playhead);

  SheetElement copyWith({
    String? follows,
    String? score,
    String? part,
    String? title,
    Color? paper,
    Color? ink,
    PracticeMode? mode,
    PracticeHands? hands,
    double? tempo,
    int? key,
    bool autoKey = false,
    int? lines,
    bool? playhead,
  }) =>
      SheetElement(base,
          follows: follows ?? this.follows,
          score: score ?? this.score,
          part: part ?? this.part,
          title: title ?? this.title,
          paper: paper ?? this.paper,
          ink: ink ?? this.ink,
          mode: mode ?? this.mode,
          hands: hands ?? this.hands,
          tempo: (tempo ?? this.tempo).clamp(0.4, 1.2),
          key: autoKey ? null : (key ?? this.key)?.clamp(-7, 7),
          lines: (lines ?? this.lines).clamp(1, 8),
          playhead: playhead ?? this.playhead);

  @override
  Map<String, dynamic> props() => {
        if (follows.isNotEmpty) "follows": follows,
        if (score.isNotEmpty) "score": score,
        if (part.isNotEmpty) "part": part,
        if (title.isNotEmpty) "title": title,
        "paper": colorToJson(paper),
        "ink": colorToJson(ink),
        if (mode != PracticeMode.wait) "mode": mode.name,
        if (hands != PracticeHands.both) "hands": hands.name,
        if (tempo != 1) "tempo": tempo,
        if (key case var k?) "key": k,
        if (lines != 2) "lines": lines,
        if (!playhead) "playhead": false,
      };

  factory SheetElement.fromJson(Map<String, dynamic> json, ElementBase b) =>
      SheetElement(b,
              follows: jsonString(json["follows"], ""),
              score: jsonString(json["score"], ""),
              part: jsonString(json["part"], ""),
              title: jsonString(json["title"], ""),
              paper: colorFromJson(json["paper"], const Color(0xFFFBFAF6)),
              ink: colorFromJson(json["ink"], const Color(0xFF1B1B1B)),
              mode: PracticeMode.fromName(jsonStr(json["mode"])),
              hands: PracticeHands.fromName(jsonStr(json["hands"])))
          .copyWith(
              tempo: jsonDouble(json["tempo"], 1),
              key: json["key"] is num ? (json["key"] as num).toInt() : null,
              lines: json["lines"] is num ? (json["lines"] as num).toInt() : 2,
              playhead: json["playhead"] != false);
}
