import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart' show BoxSpec;

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

  /// showTitle, showSubtitle, showComposer and showTempo are which of a
  /// score's heading it shows over the music (a score part only).
  final bool showTitle, showSubtitle, showComposer, showTempo;

  /// playbar is whether a bar to play it by (to the start, a note back,
  /// play, a note on, and how far it has got) is drawn over the music (a
  /// score part only). Off for a video, where nothing can press it.
  final bool playbar;

  /// showNames is whether the part's name is drawn at its staves' left: no
  /// need, where the sheet shows one instrument.
  final bool showNames;

  /// showMarks is whether its rehearsal marks are drawn.
  final bool showMarks;

  /// showDiagrams is whether a guitar part's chords are drawn as chord
  /// boxes under their symbols.
  final bool showDiagrams;

  /// box is its frame: corners, a border, and room round the music (its
  /// fill is [paper]).
  final BoxSpec box;

  /// fromBar and toBar are the bars it shows and plays, from the first to
  /// the last (Ken, 2026-11-14: "show bars 5 to 8"), counted from one;
  /// nought for the score's own first or last.
  final int fromBar, toBar;

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
    this.showTitle = true,
    this.showSubtitle = true,
    this.showComposer = true,
    this.showTempo = true,
    this.playbar = true,
    this.showNames = true,
    this.showMarks = true,
    this.showDiagrams = true,
    this.box = sheetBox,
    this.fromBar = 0,
    this.toBar = 0,
  });

  /// sheetBox is a sheet's frame as it starts: round corners, no border,
  /// the music to its edges.
  static const sheetBox = BoxSpec(borderRadius: 6, padding: 0);

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
      playhead: playhead,
      showTitle: showTitle,
      showSubtitle: showSubtitle,
      showComposer: showComposer,
      showTempo: showTempo,
      playbar: playbar,
      showNames: showNames,
      showMarks: showMarks,
      showDiagrams: showDiagrams,
      box: box,
      fromBar: fromBar,
      toBar: toBar);

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
    bool? showTitle,
    bool? showSubtitle,
    bool? showComposer,
    bool? showTempo,
    bool? playbar,
    bool? showNames,
    bool? showMarks,
    bool? showDiagrams,
    BoxSpec? box,
    int? fromBar,
    int? toBar,
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
          playhead: playhead ?? this.playhead,
          showTitle: showTitle ?? this.showTitle,
          showSubtitle: showSubtitle ?? this.showSubtitle,
          showComposer: showComposer ?? this.showComposer,
          showTempo: showTempo ?? this.showTempo,
          playbar: playbar ?? this.playbar,
          showNames: showNames ?? this.showNames,
          showMarks: showMarks ?? this.showMarks,
          showDiagrams: showDiagrams ?? this.showDiagrams,
          box: box ?? this.box,
          fromBar: math.max(0, fromBar ?? this.fromBar),
          toBar: math.max(0, toBar ?? this.toBar));

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
        if (!showTitle) "showTitle": false,
        if (!showSubtitle) "showSubtitle": false,
        if (!showComposer) "showComposer": false,
        if (!showTempo) "showTempo": false,
        if (!playbar) "playbar": false,
        if (!showNames) "showNames": false,
        if (!showMarks) "showMarks": false,
        if (!showDiagrams) "showDiagrams": false,
        "box": box.toJson(),
        if (fromBar > 0) "fromBar": fromBar,
        if (toBar > 0) "toBar": toBar,
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
              playhead: json["playhead"] != false,
              showTitle: json["showTitle"] != false,
              showSubtitle: json["showSubtitle"] != false,
              showComposer: json["showComposer"] != false,
              showTempo: json["showTempo"] != false,
              playbar: json["playbar"] != false,
              showNames: json["showNames"] != false,
              showMarks: json["showMarks"] != false,
              showDiagrams: json["showDiagrams"] != false,
              box: json["box"] is Map<String, dynamic>
                  ? BoxSpec.fromJson(json["box"] as Map<String, dynamic>)
                  : sheetBox,
              fromBar:
                  json["fromBar"] is num ? (json["fromBar"] as num).toInt() : 0,
              toBar: json["toBar"] is num ? (json["toBar"] as num).toInt() : 0);
}
