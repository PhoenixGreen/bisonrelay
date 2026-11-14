import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/music_score.dart';
import 'package:bruig/plugin_system/canvas/model/score_samples.dart';
import 'package:bruig/plugin_system/canvas/render/score_engraver.dart';
import 'package:flutter/services.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_score_engraver_test.dart is a score engraved (Ken, 2026-11-14: the
// Score Studio): its bars laid out in systems, every event a place to press,
// every marking a place to drag, and a picture to look at -- set SCORE_PNG
// to a path to have one written.

Future<void> _font(String family, List<String> files) async {
  var loader = FontLoader(family);
  for (var f in files) {
    loader.addFont(File("assets/fonts/$f")
        .readAsBytes()
        .then((b) => ByteData.view(Uint8List.fromList(b).buffer)));
  }
  await loader.load();
}

Future<ui.Image> render(EngravedScore es, [ScorePaintState? state]) {
  var rec = ui.PictureRecorder();
  paintScore(ui.Canvas(rec), es, state: state ?? const ScorePaintState());
  return rec
      .endRecording()
      .toImage(es.options.width.round(), es.height.round());
}

/// painted is [es] drawn (its marks' places are found as they are drawn).
Future<EngravedScore> painted(EngravedScore es) async {
  (await render(es)).dispose();
  return es;
}

void main() {
  setUpAll(() async {
    await _font("Bravura", ["Bravura.otf"]);
    await _font("Inter", ["Inter-Regular.otf", "Inter-Bold.otf"]);
    await _font("PTSerif", ["PTSerif-Regular.ttf", "PTSerif-Italic.ttf"]);
  });

  test("the sample laid out: systems, every event a place", () async {
    var s = odeToJoy();
    var es = layoutScore(s, const EngraveOptions());
    expect(es.systems, isNotEmpty);
    expect([for (var sys in es.systems) ...sys.bars], [0, 1, 2, 3, 4],
        reason: "each bar once, in order");
    var ids = {
      for (var p in s.parts)
        for (var st in p.staves)
          for (var b in st.bars)
            for (var e in b) e.id
    };
    var placed = {
      for (var h in es.hits)
        if (h.kind == ScoreHitKind.event) h.event
    };
    expect(placed, ids);
    if (Platform.environment["SCORE_PNG"] case var path?) {
      var img = await render(
          es, const ScorePaintState(playhead: (bar: 1, at: 1), picked: {"e6"}));
      var png = await img.toByteData(format: ui.ImageByteFormat.png);
      File(path).writeAsBytesSync(png!.buffer.asUint8List());
    }
  });

  test("narrow, the bars wrap onto more systems", () {
    var wide = layoutScore(odeToJoy(), const EngraveOptions(width: 1400));
    var narrow = layoutScore(odeToJoy(), const EngraveOptions(width: 500));
    expect(narrow.systems.length, greaterThan(wide.systems.length));
  });

  test("one part, one hand: only its staff, only its events", () {
    var es = layoutScore(
        odeToJoy(),
        const EngraveOptions(parts: {
          "pno"
        }, staves: {
          "pno": {0}
        }, heading: false));
    var parts = {
      for (var h in es.hits)
        if (h.kind != ScoreHitKind.barline) (h.part, h.staff)
    };
    expect(parts, {("pno", 0)});
  });

  test("a press on a staff: the step and the time there", () {
    var s = odeToJoy();
    var es = layoutScore(s, const EngraveOptions());
    var staff = es.hits.firstWhere(
        (h) => h.kind == ScoreHitKind.staff && h.part == "pno" && h.staff == 0);
    var sp = es.options.space;
    // The bottom line of a treble staff is E4; a space up, F4... a line up G4.
    expect(staff.stepAt(staff.bottom, sp), Pitch.parse("E4")!.step);
    expect(staff.stepAt(staff.bottom - sp, sp), Pitch.parse("G4")!.step);
    // Where the third crotchet is, the time is two beats in.
    var third = es.hits.firstWhere((h) =>
        h.kind == ScoreHitKind.event &&
        h.event == s.parts[0].staves[0].bars[0][2].id);
    expect(staff.timeAt(third.rect.center.dx, 4), 2);
  });

  test("a press on a note finds it", () {
    var s = odeToJoy();
    var es = layoutScore(s, const EngraveOptions());
    var e = s.parts[1].staves[0].bars[0][1]; // the violin's B4
    var at = es.hits
        .firstWhere((h) => h.kind == ScoreHitKind.event && h.event == e.id)
        .rect
        .center;
    expect(es.eventAt(at)?.event, e.id);
  });

  test("markings are places to drag, where their offsets put them", () async {
    var s = odeToJoy();
    var es = await painted(layoutScore(s, const EngraveOptions()));
    var chord = es.hits.firstWhere((h) => h.mark == MarkKind.chord);
    expect(es.markAt(chord.rect.center)?.event, chord.event);
    expect(es.hits.where((h) => h.mark == MarkKind.rehearsal), hasLength(1));
    expect(es.hits.where((h) => h.mark == MarkKind.tempo), hasLength(1));
    expect(es.hits.where((h) => h.mark == MarkKind.strum).length, 27);
    // Moved, the chord symbol is drawn (and found) there.
    var moved = s.copyWith(parts: [
      for (var p in s.parts)
        p.copyWith(staves: [
          for (var st in p.staves)
            st.copyWith(bars: [
              for (var b in st.bars)
                [
                  for (var e in b)
                    e.id == chord.event
                        ? e.movedMark(MarkKind.chord, const Offset(30, -10))
                        : e
                ]
            ])
        ])
    ]);
    var es2 = await painted(layoutScore(moved, const EngraveOptions()));
    var again = es2.hits
        .firstWhere((h) => h.mark == MarkKind.chord && h.event == chord.event);
    expect(again.rect.topLeft - chord.rect.topLeft, const Offset(30, -10));
  });

  test("the playhead and the picked are drawn in their colours", () async {
    var s = odeToJoy();
    var es = layoutScore(s, const EngraveOptions());
    Future<int> orange(ScorePaintState st) async {
      var img = await render(es, st);
      var raw = (await img.toByteData())!;
      var n = 0;
      for (var i = 0; i < raw.lengthInBytes; i += 4) {
        var r = raw.getUint8(i),
            g = raw.getUint8(i + 1),
            b = raw.getUint8(i + 2);
        if (r > 200 && g > 80 && g < 120 && b < 70) n++;
      }
      return n;
    }

    var none = await orange(const ScorePaintState());
    var ph = await orange(const ScorePaintState(playhead: (bar: 0, at: 1)));
    var playing = await orange(
        ScorePaintState(playing: {s.parts[0].staves[0].bars[0][0].id}));
    expect(ph, greaterThan(none + 100));
    expect(playing, greaterThan(none + 20));
  });

  // Ken, 2026-11-14: the strum's slash "moved down one line and
  // repositioned to line up with the bottom of the stem".
  test("a strum's slash on the second line, under its stem", () {
    var s = odeToJoy();
    var es = layoutScore(s, const EngraveOptions());
    var sp = es.options.space;
    var e = s.parts[2].staves[0].bars[0][0];
    var head = es.hits
        .firstWhere((h) => h.kind == ScoreHitKind.event && h.event == e.id);
    var staff = es.hits.firstWhere(
        (h) => h.kind == ScoreHitKind.staff && h.part == "gtr" && h.bar == 0);
    expect(head.rect.center.dy, closeTo(staff.bottom - sp, 0.5),
        reason: "centred on the second line");
  });

  // Ken, 2026-11-14: "the last note of bar 4 is being hidden by the repeat
  // mark".
  test("a closing repeat's lines and dots after the last note, not on it", () {
    var s = odeToJoy();
    var es = layoutScore(s, const EngraveOptions());
    var sp = es.options.space;
    var line =
        es.hits.firstWhere((h) => h.kind == ScoreHitKind.barline && h.bar == 3);
    var end = line.rect.center.dx;
    for (var p in s.parts) {
      for (var st in p.staves) {
        var last = st.bars[3].last;
        var head = es.hits.firstWhere(
            (h) => h.kind == ScoreHitKind.event && h.event == last.id);
        // The dots sit 1.5 spaces in from the line, a quarter space round.
        expect(head.rect.right - sp * 0.3, lessThan(end - sp * 1.75),
            reason: "${p.name}'s last note in bar 4");
      }
    }
  });

  // "click on a bar line to change the bar's width".
  test("a bar made wider takes more of its line", () {
    var s = odeToJoy();
    double widthOf(MusicScore x, int bar) =>
        layoutScore(x, const EngraveOptions())
            .hits
            .firstWhere((h) => h.kind == ScoreHitKind.staff && h.bar == bar)
            .rect
            .width;
    var wider = s.copyWith(bars: [
      for (var (i, b) in s.bars.indexed) i == 1 ? b.copyWith(width: 2) : b
    ]);
    expect(widthOf(wider, 1), greaterThan(widthOf(s, 1) * 1.3));
    expect(widthOf(wider, 0), lessThan(widthOf(s, 0)),
        reason: "the line is still the page's width");
    var back = BarInfo.fromJson(const BarInfo(width: 2).toJson());
    expect(back.width, 2);
  });

  // "show/hide instrument names".
  test("without the names, the music starts further left", () {
    var s = odeToJoy();
    double leftOf(EngraveOptions o) => layoutScore(s, o)
        .hits
        .firstWhere((h) => h.kind == ScoreHitKind.staff && h.bar == 0)
        .rect
        .left;
    expect(leftOf(const EngraveOptions(names: false)),
        lessThan(leftOf(const EngraveOptions()) - 40));
  });
}
