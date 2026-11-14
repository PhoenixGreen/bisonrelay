import 'package:bruig/plugin_system/canvas/model/music_score.dart';

// score_samples.dart holds a score to start from: "Ode to Joy" (Beethoven,
// with Henry van Dyke's "Joyful, Joyful" words of 1907, both in the public
// domain) for piano, violin and strummed guitar -- the Score Studio
// prototype's lesson score, with something of everything: two staves and two
// verses, chords and strums, dynamics, a hairpin, slurs, articulations, a
// repeat with first and second endings, a rehearsal mark.

/// odeToJoy is the sample score, as [id].
MusicScore odeToJoy([String id = "ode"]) {
  var n = 0;
  ScoreEvent ev(double value, List<String> pitches,
          {int dots = 0,
          Dynamic? dyn,
          List<String> lyrics = const [],
          String? chord,
          Set<Articulation> art = const {}}) =>
      ScoreEvent("e${++n}", value,
          dots: dots,
          pitches: [for (var p in pitches) Pitch.parse(p)!],
          dyn: dyn,
          lyrics: lyrics,
          chord: chord,
          articulations: art);
  ScoreEvent strum(double value, Strum dir, {String? chord, Dynamic? dyn}) =>
      ScoreEvent("e${++n}", value,
          slash: true, strum: dir, chord: chord, dyn: dyn);

  var rh = [
    [
      ev(1, ["E4"], dyn: Dynamic.mf, lyrics: ["Joy-", "Hearts"], chord: "C"),
      ev(1, ["E4"], lyrics: ["ful,", "un-"]),
      ev(1, ["F4"], lyrics: ["joy-", "fold"]),
      ev(1, ["G4"], lyrics: ["ful,", "like"]),
    ],
    [
      ev(1, ["G4"], lyrics: ["we", "flow'rs"], chord: "G"),
      ev(1, ["F4"], lyrics: ["a-", "be-"]),
      ev(1, ["E4"], lyrics: ["dore", "fore"]),
      ev(1, ["D4"], lyrics: ["thee,", "Thee,"], art: {Articulation.staccato}),
    ],
    [
      ev(1, ["C4"],
          lyrics: ["God", "op'n-"], chord: "C", art: {Articulation.accent}),
      ev(1, ["C4"], lyrics: ["of", "ing"]),
      ev(1, ["D4"], lyrics: ["glo-", "to"]),
      ev(1, ["E4"], lyrics: ["ry,", "the"]),
    ],
    [
      ev(1, ["E4"], dots: 1, lyrics: ["Lord"], chord: "G", dyn: Dynamic.f),
      ev(0.5, ["D4"], lyrics: ["of"]),
      ev(2, ["D4"], lyrics: ["love."]),
    ],
    [
      ev(1, ["D4"], dots: 1, lyrics: ["", "sun"], chord: "G"),
      ev(0.5, ["C4"], lyrics: ["", "a-"]),
      ev(2, ["C4"],
          lyrics: ["", "bove."], chord: "C", art: {Articulation.tenuto}),
    ],
  ];
  var lh = [
    [
      ev(2, ["C3", "G3"]),
      ev(2, ["C3", "G3"])
    ],
    [
      ev(2, ["G2", "D3"]),
      ev(2, ["G2", "D3"])
    ],
    [
      ev(2, ["C3", "G3"]),
      ev(2, ["C3", "G3"])
    ],
    [
      ev(2, ["G2", "D3"]),
      ev(2, ["G2", "B2", "D3"])
    ],
    [
      ev(2, ["G2", "D3"]),
      ev(2, ["C3", "G3"])
    ],
  ];
  var vn = [
    [
      ev(2, ["C5"], dyn: Dynamic.p),
      ev(2, ["B4"])
    ],
    [
      ev(2, ["B4"]),
      ev(2, ["G4"])
    ],
    [
      ev(2, ["A4"]),
      ev(2, ["G4"])
    ],
    [
      ev(2, ["G4"]),
      ev(2, ["F4"])
    ],
    [
      ev(2, ["F4"]),
      ev(2, ["E4"])
    ],
  ];
  List<ScoreEvent> pattern(String chord, {Dynamic? dyn}) => [
        strum(1, Strum.down, chord: chord, dyn: dyn),
        strum(0.5, Strum.down),
        strum(0.5, Strum.up),
        strum(0.5, Strum.up),
        strum(0.5, Strum.down),
        strum(1, Strum.up),
      ];
  var gt = [
    pattern("C", dyn: Dynamic.mp),
    pattern("G"),
    pattern("C"),
    pattern("G"),
    [
      strum(1, Strum.down, chord: "G"),
      strum(1, Strum.up),
      strum(2, Strum.down, chord: "C"),
    ],
  ];
  return MusicScore(id,
      title: "Ode to Joy",
      subtitle: "“Joyful, Joyful” · words Henry van Dyke (1907)",
      composer: "L. van Beethoven, arr. for lesson",
      tempo: 112,
      tempoText: "Allegro",
      verses: 2,
      bars: const [
        BarInfo(repeatStart: true, mark: "A"),
        BarInfo(),
        BarInfo(),
        BarInfo(endings: [1], repeatEnd: 2),
        BarInfo(endings: [2]),
      ],
      spanners: const [
        Spanner(
            "s1", SpannerKind.slur, "pno", 0, (bar: 0, at: 0), (bar: 1, at: 3)),
        Spanner("s2", SpannerKind.crescendo, "pno", 0, (bar: 2, at: 0),
            (bar: 2, at: 3)),
        Spanner(
            "s3", SpannerKind.slur, "vln", 0, (bar: 0, at: 0), (bar: 0, at: 2)),
      ],
      parts: [
        ScorePart(
            "pno",
            "Piano",
            "piano",
            [
              ScoreStaff(Clef.treble, rh),
              ScoreStaff(Clef.bass, lh),
            ],
            short: "Pno."),
        ScorePart("vln", "Violin", "violin", [ScoreStaff(Clef.treble, vn)],
            short: "Vln."),
        ScorePart("gtr", "Guitar", "guitarStrum", [ScoreStaff(Clef.treble, gt)],
            short: "Gtr."),
      ]);
}
