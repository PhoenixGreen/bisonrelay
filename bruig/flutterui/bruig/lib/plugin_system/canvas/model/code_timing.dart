import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_run_element.dart';

// code_timing.dart is what a Code panel shows at a moment of its scene: how
// much of each file is typed, which tab each pane shows, which lines are
// lit, and when a Run panel runs it, all from the element and the time
// alone, so the stage, a video and a book agree.

final LinkedHashMap<String, Float64List> _times = LinkedHashMap();

/// letterTimes is when each of [text]'s letters is typed, in seconds from
/// its file's start ([text].length + 1 of them: the last is when it is
/// done). Indents come quickly, as an editor fills them; each line's end
/// waits [CodeTyping.pause].
Float64List letterTimes(String text, CodeTyping typing) {
  var key = "${typing.speed}|${typing.pause}|$text";
  var hit = _times.remove(key);
  if (hit != null) return _times[key] = hit;
  var a = Float64List(text.length + 1);
  var each = 1 / typing.speed;
  var acc = 0.0;
  var lineStart = true;
  for (var i = 0; i < text.length; i++) {
    a[i] = acc;
    var c = text.codeUnitAt(i);
    if (c == 10) {
      acc += each + typing.pause;
      lineStart = true;
    } else if (lineStart && (c == 32 || c == 9)) {
      acc += each * 0.2;
    } else {
      lineStart = false;
      acc += each;
    }
  }
  a[text.length] = acc;
  _times[key] = a;
  while (_times.length > 32) {
    _times.remove(_times.keys.first);
  }
  return a;
}

/// CodePlan is when each open file is typed: from and to, in scene seconds.
class CodePlan {
  final Map<String, (double, double)> files;
  final double end;
  const CodePlan(this.files, this.end);
}

/// codePlan is [e]'s typing: pane by pane, each pane's tabs in order (a
/// file open in two panes is typed once), or every pane at once.
CodePlan codePlan(CodeElement e) {
  var files = <String, (double, double)>{};
  if (!e.typing.on) return CodePlan(files, 0);
  var seen = <String>{};
  var at = e.typing.start, end = e.typing.start;
  for (var pane in e.shownPanes) {
    if (e.typing.together) at = e.typing.start;
    for (var id in pane.tabs) {
      var f = e.file(id);
      if (f == null || !seen.add(id)) continue;
      var len = letterTimes(f.text, e.typing).last;
      files[id] = (at, at + len);
      end = math.max(end, at + len);
      at += len + 0.5;
    }
  }
  return CodePlan(files, end);
}

/// typedCount is how many of file [id]'s letters are typed at [t].
int typedCount(CodeElement e, String id, double t, CodePlan plan) {
  var f = e.file(id);
  if (f == null) return 0;
  var span = plan.files[id];
  if (span == null || t >= span.$2) return f.text.length;
  if (t <= span.$1) return 0;
  var a = letterTimes(f.text, e.typing);
  var local = t - span.$1;
  var lo = 0, hi = f.text.length;
  while (lo < hi) {
    var mid = (lo + hi + 1) >> 1;
    if (a[mid] <= local) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo;
}

List<CodeStep> litSteps(CodeElement e, double t) => [
      for (var s in e.steps)
        if (s.litAt(t)) s
    ];

/// shownFile is the file pane [pane] shows at [t]: one picked there by hand
/// ([picked], the reader's, while paused); else a file being lit; else the
/// one being typed (or about to be); else the pane's own pick. So a lesson
/// moves from tab to tab by itself as it plays.
String? shownFile(CodeElement e, int pane, double t, CodePlan plan,
    {String? picked}) {
  var panes = e.shownPanes;
  if (pane < 0 || pane >= panes.length) return null;
  var p = panes[pane];
  if (p.tabs.isEmpty) return null;
  if (picked != null && p.tabs.contains(picked)) return picked;
  for (var s in e.steps) {
    if (s.litAt(t) && p.tabs.contains(s.file)) return s.file;
  }
  var spans = [
    for (var id in p.tabs)
      if (plan.files[id] case var s?) (id, s)
  ];
  if (spans.isNotEmpty && t < spans.map((s) => s.$2.$2).reduce(math.max)) {
    var started = spans.where((s) => s.$2.$1 <= t).toList();
    if (started.isEmpty) {
      return spans.reduce((a, b) => b.$2.$1 < a.$2.$1 ? b : a).$1;
    }
    return started.reduce((a, b) => b.$2.$1 > a.$2.$1 ? b : a).$1;
  }
  return p.shows;
}

/// runAt is when [run] runs on its scene's clock, for the Code panel [code]
/// it runs (null for one with none): when its typing ends, as the scene
/// starts, or only when Run is pressed (null).
double? runAt(CodeRunElement run, CodeElement? code) => switch (run.when) {
      CodeRunWhen.press => null,
      CodeRunWhen.start => 0,
      CodeRunWhen.typed =>
        code == null ? 0 : (code.typing.on ? codePlan(code).end + 0.6 : 0),
    };

/// lessonLength is how long [e]'s typing and steps take, so a scene fits.
double lessonLength(CodeElement e) {
  var end = codePlan(e).end;
  for (var s in e.steps) {
    end = math.max(end, s.at + s.length);
  }
  return end;
}

/// lessonSpan is when [e]'s lesson is on the timeline, from its typing's
/// start (else its first lit lines) to its last lit lines' end; else null.
(double, double)? lessonSpan(CodeElement e) {
  var end = lessonLength(e);
  if (end <= 0) return null;
  var start = e.typing.on
      ? e.typing.start
      : e.steps.map((s) => s.at).fold(double.infinity, math.min);
  if (!start.isFinite) return null;
  return (math.min(start, end), end);
}

/// lessonMoved is [e]'s lesson [by] seconds later (earlier, negative): its
/// typing and every lit line together, none before the scene's start.
CodeElement lessonMoved(CodeElement e, double by) {
  var span = lessonSpan(e);
  if (span == null) return e;
  var d = math.max(by, -span.$1);
  return e.copyWith(
      typing: e.typing.copyWith(start: e.typing.start + d),
      steps: [for (var s in e.steps) s.copyWith(at: s.at + d)]);
}

/// lessonTypedBy is [e] typed in by [end] seconds, its typing faster or
/// slower to end there and its lit lines moved by as much as that end.
CodeElement lessonTypedBy(CodeElement e, double end) {
  if (!e.typing.on) return e;
  var plan = codePlan(e);
  var was = plan.end;
  var took = was - e.typing.start;
  if (took <= 0) return e;
  // What does not change with the speed (each line's pause, the half second
  // between files), and what does.
  var fixed = 0.0;
  if (!e.typing.together) fixed += 0.5 * math.max(0, plan.files.length - 1);
  for (var id in plan.files.keys) {
    var f = e.file(id);
    if (f != null) fixed += e.typing.pause * "\n".allMatches(f.text).length;
  }
  if (e.typing.together) fixed = e.typing.pause * _mostLines(e, plan);
  var letters = (took - fixed) * e.typing.speed;
  var want = math.max(fixed + 0.3, end - e.typing.start);
  var typed =
      e.copyWith(typing: e.typing.copyWith(speed: letters / (want - fixed)));
  var by = codePlan(typed).end - was;
  return typed.copyWith(steps: [
    for (var s in e.steps) s.at >= was - 1e-6 ? s.copyWith(at: s.at + by) : s
  ]);
}

/// _mostLines is the most lines any one pane types: its pauses' total with
/// the panes typing all at once.
int _mostLines(CodeElement e, CodePlan plan) {
  var most = 0;
  for (var pane in e.shownPanes) {
    var n = 0;
    for (var id in pane.tabs) {
      if (plan.files.containsKey(id)) {
        n += "\n".allMatches(e.file(id)?.text ?? "").length;
      }
    }
    most = math.max(most, n);
  }
  return most;
}
