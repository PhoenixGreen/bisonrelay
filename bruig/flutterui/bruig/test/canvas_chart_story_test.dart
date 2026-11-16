import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/chart_play.dart';
import 'package:bruig/plugin_system/canvas/model/chart_story.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';
import 'package:bruig/plugin_system/canvas/render/camera_aim.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_chart_story_test.dart is a chart told by its narration (Ken,
// 2026-11-17, the improvements report's seventh item): a step for each
// line, taken as the line is spoken, lighting the names it says; a camera
// aimed at what the narration names follows.

SpeechTake take(String id, List<String> words, double from) =>
    SpeechTake(id, words.length * 0.5, [
      for (var (i, w) in words.indexed)
        (text: w, start: from + i * 0.5, end: from + i * 0.5 + 0.4)
    ]);

void main() {
  var lines = ["Liverpool lead the way", "Spurs climbed six places"];
  var a = take("a", lines[0].split(" "), 0),
      b = take("b", lines[1].split(" "), 0);
  // Joined: the second line's words two seconds after the first's start.
  var joined = SpeechTake("joined", 6, [
    ...a.words,
    for (var w in b.words) (text: w.text, start: w.start + 3, end: w.end + 3),
  ]);
  var spec = SpeechSpec(lines: [
    SpeechLine(lines[0], slots: [a], chosen: 0),
    SpeechLine(lines[1], slots: [b], chosen: 0),
  ], takes: [
    joined
  ], clip: "voice");
  var voice = AudioElement(const ElementBase(id: "voice"),
      clip: MediaClip(
          timed: true,
          at: 24,
          playlist: const [MediaSource(assetId: "joined", name: "Speech")],
          mix: ChannelMix(speech: spec)));
  var sheet = DataSheet(id: "s", cells: [
    ["Club", "Pts"],
    ["Liverpool", "88"],
    ["Arsenal", "79"],
    ["Spurs", "52"],
  ]);
  var chart = ChartElement(
      const ElementBase(id: "c", x: 100, y: 100, width: 1000, height: 500),
      type: ChartType.bar,
      sheet: SheetLink("s", sheet.used, labels: 0, series: const [1]),
      data:
          ChartData.parse("Club\tPts\nLiverpool\t88\nArsenal\t79\nSpurs\t52"));

  test("each line starts where its first word is spoken", () {
    var doc = CanvasDocument(elements: [voice], frameRate: 24);
    expect(narrationStarts(doc), [24, 24 + 72]);
    expect(narrationLines(doc), lines);
  });

  test("a step a line, lighting the names it says, as it is spoken", () {
    var told = storySteps(chart, lines);
    expect(told.steps, hasLength(2));
    expect(told.follow, ChartStepsFollow.speech.name);
    expect(told.steps[1].title, "Spurs climbed six places");
    expect([for (var h in told.steps[1].highlights) h.who], ["Spurs"]);
    var doc =
        CanvasDocument(elements: [voice, told], sheets: [sheet], frameRate: 24);
    expect(chartShownAt(told, doc, 30).title, lines[0]);
    expect(chartShownAt(told, doc, 24 + 80).title, lines[1]);
  });

  test("a camera aimed at what the narration names follows it", () {
    var told = storySteps(chart, lines);
    var doc =
        CanvasDocument(elements: [voice, told], sheets: [sheet], frameRate: 24);
    expect(aimChoices(told).map((c) => c.$1), contains("lit"));
    var first = chartAimRect(told, "lit", 30, doc)!;
    var second = chartAimRect(told, "lit", 24 + 80, doc)!;
    var spurs = chartAimRect(told, "item:Spurs", 24 + 80, doc)!;
    expect(second, spurs, reason: "the line said Spurs");
    expect(first.center.dx, lessThan(second.center.dx),
        reason: "Liverpool first, then over to Spurs");
    // Saved, the camera keeps its aim.
    var cam =
        const CameraElement(ElementBase(id: "cam"), aim: "c", aimAt: "lit");
    expect(CameraElement.fromJson(cam.props(), cam.base).aimAt, "lit");
  });
}
