import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/chart_play.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';

// chart_story.dart is a chart told by its narration: a step per script line
// ("Spurs climbed six places" lights Spurs), each taken as its line is
// spoken, so the timing is the voice's, not keyframes. A camera aimed at
// "what the narration names" follows (camera_aim.dart). chartShownAt works
// out every way a chart steps or plays, so renderer and camera agree.

/// narrationStarts is the frame in [doc]'s scene where each narration line
/// starts: each line's first word in the first Speech clip's joined take.
/// Empty where there is none.
List<int> narrationStarts(CanvasDocument doc) {
  for (var a in doc.elements.whereType<AudioElement>()) {
    var spec = a.clip.mix.speech;
    if (spec == null || !a.clip.timed) continue;
    var asset = a.clip.playlist.firstOrNull?.assetId;
    var joined = spec.takes.where((t) => t.assetId == asset).lastOrNull;
    if (joined == null || joined.words.isEmpty) continue;
    var rate = doc.frameRate;
    var speed = a.clip.speed <= 0 ? 1.0 : a.clip.speed;
    var starts = <int>[];
    var w = 0;
    for (var line in spec.lines) {
      var take = line.take;
      if (take == null) continue;
      if (w >= joined.words.length) break;
      starts.add(a.clip.at + (joined.words[w].start / speed * rate).round());
      w += take.words.length;
    }
    return starts;
  }
  return const [];
}

/// narrationLines is the first Speech clip's script, line by line, or
/// empty.
List<String> narrationLines(CanvasDocument doc) {
  for (var a in doc.elements.whereType<AudioElement>()) {
    var spec = a.clip.mix.speech;
    if (spec == null) continue;
    return [
      for (var l in spec.lines)
        if (l.text.trim().isNotEmpty) l.text.trim()
    ];
  }
  return const [];
}

/// storySteps gives [e] a step per line of [lines], titled with it and
/// lighting the chart names it says, the rest faded. Its steps then follow
/// the narration.
ChartElement storySteps(ChartElement e, List<String> lines) {
  if (lines.isEmpty) return e;
  var names = e.data.categories;
  bool says(String line, String name) =>
      RegExp("(^|[^A-Za-z0-9])${RegExp.escape(name)}(\$|[^A-Za-z0-9])",
              caseSensitive: false)
          .hasMatch(line);
  var steps = [
    for (var (i, line) in lines.indexed)
      ChartStep(
          name: "Line ${i + 1}",
          title: line,
          at: e.sheet?.at ?? "",
          highlights: [
            for (var n in names)
              if (n.trim().isNotEmpty && says(line, n))
                ChartHighlight(
                    reach: ChartReach.one, who: n, fade: true, named: true),
          ]),
  ];
  // The chart's own title and lights are the first step's (see stepOf).
  return e.copyWith(
      steps: steps,
      stepAt: 0,
      title: steps.first.title,
      highlights: steps.first.highlights,
      follow: ChartStepsFollow.speech.name);
}

/// chartShownAt is [e] on [frame] (and [between] a frame on): at its step,
/// by the timeline's marks, the scenes or the narration, or part-way through
/// its dates.
ChartElement chartShownAt(ChartElement e, CanvasDocument? doc, int frame,
    {double between = 0}) {
  var sheet = doc?.sheets.where((s) => s.id == e.sheet?.sheet).firstOrNull;
  if (sheet == null || doc == null) return e;
  var rate = doc.frameRate;
  var at = frame + between;
  if (e.steps.length > 1 && e.follow == ChartStepsFollow.marks.name) {
    // A step from each mark on the timeline (a Stop waits for a click).
    var (k, since) = stepByMarks([
      for (var a in doc.actions)
        if (a.kind == TimelineActionKind.stop ||
            a.kind == TimelineActionKind.pause ||
            a.kind == TimelineActionKind.locator)
          a.frame
    ], e.steps.length, at, rate);
    return chartAtStep(e, sheet, k, since);
  }
  if (e.steps.length > 1 && e.follow == ChartStepsFollow.speech.name) {
    // A step as each line of the narration starts.
    var starts = narrationStarts(doc);
    if (starts.isEmpty) return chartAtStep(e, sheet, 0, double.infinity);
    var (k, since) = stepByMarks(starts, e.steps.length, at, rate);
    return chartAtStep(e, sheet, k, since);
  }
  if (e.steps.length > 1 && e.follow == ChartStepsFollow.scenes.name) {
    // A step per scene (or page) it is in, linked copies included.
    var chart = e;
    bool mine(CanvasElement x) =>
        x.id == chart.id ||
        (chart.base.cast.isNotEmpty && x.base.cast == chart.base.cast);
    var inScenes = [
      for (var (i, scene) in doc.allScenes.indexed)
        if ((i == doc.at ? doc.elements : scene.elements).any(mine)) i
    ];
    return chartAtStep(
        e, sheet, stepByScenes(inScenes, doc.at), double.infinity);
  }
  if (e.play > 0) {
    var since = (at - (arrivalEnd(e, rate) ?? 0)) / rate;
    return chartPlaying(e, sheet, since);
  }
  return e;
}
