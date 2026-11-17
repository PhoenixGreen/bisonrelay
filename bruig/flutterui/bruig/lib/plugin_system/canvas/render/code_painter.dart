import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/code_highlight.dart';
import 'package:bruig/plugin_system/canvas/model/code_timing.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:flutter/painting.dart';

// code_painter.dart draws a Code panel (code_element.dart) as the prototype
// drew it: a window bar, the files down the side, and its panes, each with
// its tabs over its code -- line numbers, the code coloured by what it is,
// typed as far as the scene has got, lit lines with their note beside them
// and the rest dimmed.
//
// codeBoxes is where everything is, in page units; the stage answers
// presses (a tab, a line between panes, a file) from the same boxes.

/// CodeColours is a theme's colours.
class CodeColours {
  final Color bg, bar, side, line, fg, dim, gutter;
  final Color keyword, string, number, comment, function, type, tag, attr;
  final Color caret, band, dimmer;
  const CodeColours({
    required this.bg,
    required this.bar,
    required this.side,
    required this.line,
    required this.fg,
    required this.dim,
    required this.gutter,
    required this.keyword,
    required this.string,
    required this.number,
    required this.comment,
    required this.function,
    required this.type,
    required this.tag,
    required this.attr,
    required this.caret,
    required this.band,
    required this.dimmer,
  });

  static CodeColours of(CodeTheme t) => switch (t) {
        CodeTheme.night => const CodeColours(
            bg: Color(0xFF14171C),
            bar: Color(0xFF1B1F25),
            side: Color(0xFF171B20),
            line: Color(0xFF262B33),
            fg: Color(0xFFD7DEE7),
            dim: Color(0xFF8A93A0),
            gutter: Color(0xFF525B69),
            keyword: Color(0xFFC792EA),
            string: Color(0xFFA8D9A0),
            number: Color(0xFFF78C6C),
            comment: Color(0xFF6E7989),
            function: Color(0xFF82AAFF),
            type: Color(0xFFFFCB6B),
            tag: Color(0xFFF07178),
            attr: Color(0xFFFFCB6B),
            caret: Color(0xFFFFCC00),
            band: Color(0x2982AAFF),
            dimmer: Color(0x9E14171C)),
        CodeTheme.day => const CodeColours(
            bg: Color(0xFFFBFAF7),
            bar: Color(0xFFECEAE4),
            side: Color(0xFFF3F1EB),
            line: Color(0xFFDCD8CE),
            fg: Color(0xFF2B2F36),
            dim: Color(0xFF666B76),
            gutter: Color(0xFFA3A6AE),
            keyword: Color(0xFF8E3BBF),
            string: Color(0xFF2E7D32),
            number: Color(0xFFB5531A),
            comment: Color(0xFF878C95),
            function: Color(0xFF1F5FBF),
            type: Color(0xFF8A5D00),
            tag: Color(0xFFC2334D),
            attr: Color(0xFF8A5D00),
            caret: Color(0xFF1F5FBF),
            band: Color(0x1F1F5FBF),
            dimmer: Color(0xA8FBFAF7)),
        CodeTheme.chalk => const CodeColours(
            bg: Color(0xFF1F3A30),
            bar: Color(0xFF18302A),
            side: Color(0xFF1B342B),
            line: Color(0xFF2C4A3F),
            fg: Color(0xFFEEF2EA),
            dim: Color(0xFFA9BDB2),
            gutter: Color(0xFF6E8F80),
            keyword: Color(0xFFFFD580),
            string: Color(0xFFB9F3C9),
            number: Color(0xFFFFB3A1),
            comment: Color(0xFF8FB3A3),
            function: Color(0xFFA8D8FF),
            type: Color(0xFFFFE9A8),
            tag: Color(0xFFFF9EAD),
            attr: Color(0xFFFFD580),
            caret: Color(0xFFFFFFFF),
            band: Color(0x1FFFFFFF),
            dimmer: Color(0x991F3A30)),
      };

  Color role(CodeRole r) => switch (r) {
        CodeRole.plain => fg,
        CodeRole.keyword => keyword,
        CodeRole.string => string,
        CodeRole.number => number,
        CodeRole.comment => comment,
        CodeRole.function => function,
        CodeRole.type => type,
        CodeRole.tag => tag,
        CodeRole.attribute => attr,
      };
}

/// codeMark is a lit line's marker and its note's colour: a highlighter's.
const codeMark = Color(0xFFF2C14E);
const _uiFont = "Inter";
const _codeFont = "RobotoMono";

/// codeLineHeight is a line's height for code [fontSize] high.
double codeLineHeight(double fontSize) => fontSize * 1.55;

/// codeStyle is code's own style at [fontSize]: every line the same height
/// (the strut), so lit lines and the editor line up with it.
TextStyle codeStyle(double fontSize, Color colour) => TextStyle(
    fontFamily: _codeFont,
    fontSize: fontSize,
    height: 1.55,
    color: colour,
    leadingDistribution: TextLeadingDistribution.even);
StrutStyle codeStrut(double fontSize) => StrutStyle(
    fontFamily: _codeFont,
    fontSize: fontSize,
    height: 1.55,
    leadingDistribution: TextLeadingDistribution.even,
    forceStrutHeight: true);

final Map<double, (double, double)> _measures = {};

/// codeCharWidth is one letter's width in code [fontSize] high.
double codeCharWidth(double fontSize) => _measure(fontSize).$1;

/// _measure is a letter's width, and the letter spacing that makes a tab
/// four letters wide: text draws a tab one letter wide, and spacing is not
/// added one for one, so it is measured.
(double, double) _measure(double fontSize) => _measures[fontSize] ??= () {
      double xOf(InlineSpan span) {
        var tp = TextPainter(text: span, textDirection: TextDirection.ltr)
          ..layout();
        var x =
            tp.getOffsetForCaret(const TextPosition(offset: 1), Rect.zero).dx;
        tp.dispose();
        return x;
      }

      var s = codeStyle(fontSize, const Color(0xFF000000));
      var w = xOf(TextSpan(text: "00", style: s));
      if (w <= 0) w = fontSize * 0.6;
      var probe = w * 3;
      var spaced = xOf(TextSpan(children: [
        TextSpan(text: "\t", style: s.copyWith(letterSpacing: probe)),
        TextSpan(text: "0", style: s),
      ]));
      var slope = (spaced - w) / probe;
      return (w, slope > 0.01 ? w * 3 / slope : probe);
    }();

/// _linked keeps the last files' runs with other files' names marked: a
/// pane is drawn every frame it scrolls, and its file seldom changes.
final Map<String, List<CodeRun>> _linked = {};

List<CodeRun> _runsOf(CodeElement e, CodeFile file, String text) {
  var runs = highlightRuns(file.language, text);
  if (!e.links) return runs;
  var names = linkNames(e, file.id);
  var key =
      "${file.language.name}\u0000${names.entries.map((n) => "${n.key}=${n.value}").join(",")}\u0000$text";
  var hit = _linked.remove(key);
  if (hit != null) return _linked[key] = hit;
  var out = withLinks(runs, text, names);
  _linked[key] = out;
  while (_linked.length > 48) {
    _linked.remove(_linked.keys.first);
  }
  return out;
}

/// codeSpan is [text]'s first [count] letters as [file] in [e] colours
/// them: by role, other files' names underlined in their colour, and tabs
/// four letters wide. The painter and the stage's editor both use it.
TextSpan codeSpan(
    CodeElement e, CodeFile file, String text, int count, CodeColours c,
    {double? fontSize}) {
  var fs = fontSize ?? e.fontSize;
  var runs = _runsOf(e, file, text);
  var tab = _measure(fs).$2;
  var spans = <InlineSpan>[];
  for (var r in runs) {
    if (r.start >= count) break;
    var piece = text.substring(r.start, math.min(r.end, count));
    var style = codeStyle(fs, c.role(r.role));
    if (r.link.isNotEmpty) {
      var linked = e.file(r.link);
      if (linked != null) {
        style = style.copyWith(
            decoration: TextDecoration.underline,
            decorationColor: linked.colour,
            decorationThickness: 2.4);
      }
    }
    // Tabs, one span each, spaced out to four letters.
    var at = 0;
    for (var i = piece.indexOf("\t"); i >= 0; i = piece.indexOf("\t", at)) {
      if (i > at) {
        spans.add(TextSpan(text: piece.substring(at, i), style: style));
      }
      spans
          .add(TextSpan(text: "\t", style: style.copyWith(letterSpacing: tab)));
      at = i + 1;
    }
    if (at < piece.length) {
      spans.add(TextSpan(text: piece.substring(at), style: style));
    }
  }
  return TextSpan(style: codeStyle(fs, c.fg), children: spans);
}

/// CodePlayPart is a part of a Code panel's playbar.
/// reset puts its code back as it began (CodeElement.reset): shown only
/// once it has changed, with or without a lesson to play.
enum CodePlayPart { reset, full, restart, play, track }

/// codePlaybar is where [e]'s playbar's parts are in its window bar [bar]:
/// its lesson's, where it has one and shows them, and Reset, where its code
/// has changed; empty where there is no room.
Map<CodePlayPart, Rect> codePlaybar(CodeElement e, Rect? bar) {
  if (bar == null) return const {};
  var fs = e.fontSize;
  var b = fs * 1.7, gap = fs * 0.45;
  var out = <CodePlayPart, Rect>{};
  // From the right: the next part ends here.
  var left = bar.right - fs * 0.8;
  if (e.playbar && lessonSpan(e) != null) {
    var timeW = fs * 6.2;
    var trackW = math.min(fs * 11, bar.width * 0.28);
    var right = bar.right - fs * 0.8 - timeW - gap;
    var track = Rect.fromLTWH(right - trackW, bar.center.dy - b / 2, trackW, b);
    var play = Rect.fromLTWH(track.left - gap - b, bar.center.dy - b / 2, b, b);
    var restart = Rect.fromLTWH(play.left - gap * 0.6 - b, play.top, b, b);
    var full = Rect.fromLTWH(restart.left - gap * 1.4 - b, play.top, b, b);
    if (full.left >= bar.left + fs * 8) {
      out[CodePlayPart.full] = full;
      out[CodePlayPart.restart] = restart;
      out[CodePlayPart.play] = play;
      out[CodePlayPart.track] = track;
      left = full.left - gap * 1.4;
    }
  }
  if (e.changedFromStart) {
    var reset = Rect.fromLTWH(left - b, bar.center.dy - b / 2, b, b);
    if (reset.left >= bar.left + fs * 8) out[CodePlayPart.reset] = reset;
  }
  return out;
}

/// _paintPlaybar draws [e]'s playbar: back to the start, play or pause, its
/// lesson's track with the typing's end and each lit step marked, and the
/// time.
void _paintPlaybar(Canvas canvas, CodeElement e, CodeColours c,
    Map<CodePlayPart, Rect> parts, double seconds, bool playing,
    {bool full = false}) {
  var fs = e.fontSize;
  var key = Paint()..color = c.line;
  var ink = Paint()..color = c.fg;
  // Reset: an arrow curled back round to where it began.
  if (parts[CodePlayPart.reset] case var r?) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(fs * 0.35)), key);
    var m = r.center, u = r.width * 0.24;
    canvas.drawArc(
        Rect.fromCircle(center: m, radius: u),
        -math.pi * 0.35,
        math.pi * 1.6,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, r.width * 0.09)
          ..strokeCap = StrokeCap.round
          ..color = c.fg);
    var tip =
        m + Offset(math.cos(-math.pi * 0.35), math.sin(-math.pi * 0.35)) * u;
    var a = u * 0.6;
    canvas.drawPath(
        Path()
          ..moveTo(tip.dx + a * 0.9, tip.dy - a * 0.1)
          ..lineTo(tip.dx - a * 0.2, tip.dy - a * 0.9)
          ..lineTo(tip.dx - a * 0.1, tip.dy + a * 0.5)
          ..close(),
        ink);
  }
  var span = lessonSpan(e);
  if (span == null || !parts.containsKey(CodePlayPart.full)) return;
  // Full code: the whole of it, by nobody's clock -- lit while it shows.
  var f = parts[CodePlayPart.full]!;
  canvas.drawRRect(RRect.fromRectAndRadius(f, Radius.circular(fs * 0.35)),
      Paint()..color = full ? codeMark : c.line);
  var fu = f.width * 0.2;
  var lines = Paint()..color = full ? const Color(0xFF1D1606) : c.fg;
  for (var (i, w) in [(-1, 2.0), (0, 1.4), (1, 1.8)]) {
    canvas.drawRect(
        Rect.fromLTWH(f.center.dx - fu, f.center.dy + i * fu * 0.8 - fu * 0.15,
            fu * w, fu * 0.3),
        lines);
  }
  for (var part in [CodePlayPart.restart, CodePlayPart.play]) {
    var r = parts[part]!;
    canvas.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(fs * 0.35)), key);
    var m = r.center, u = r.width * 0.2;
    if (part == CodePlayPart.restart) {
      canvas.drawRect(
          Rect.fromLTWH(m.dx - u * 1.1, m.dy - u, u * 0.35, u * 2), ink);
      canvas.drawPath(
          Path()
            ..moveTo(m.dx + u, m.dy - u)
            ..lineTo(m.dx - u * 0.6, m.dy)
            ..lineTo(m.dx + u, m.dy + u)
            ..close(),
          ink);
    } else if (playing) {
      canvas.drawRect(
          Rect.fromLTWH(m.dx - u * 0.9, m.dy - u, u * 0.6, u * 2), ink);
      canvas.drawRect(
          Rect.fromLTWH(m.dx + u * 0.3, m.dy - u, u * 0.6, u * 2), ink);
    } else {
      canvas.drawPath(
          Path()
            ..moveTo(m.dx - u * 0.7, m.dy - u)
            ..lineTo(m.dx + u, m.dy)
            ..lineTo(m.dx - u * 0.7, m.dy + u)
            ..close(),
          ink);
    }
  }
  var t = parts[CodePlayPart.track]!;
  double xOf(double sec) =>
      t.left + t.width * ((sec - 0) / span.$2).clamp(0.0, 1.0);
  var line = Rect.fromLTRB(
      t.left, t.center.dy - fs * 0.12, t.right, t.center.dy + fs * 0.12);
  canvas.drawRRect(
      RRect.fromRectAndRadius(line, Radius.circular(fs * 0.12)), key);
  canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTRB(line.left, line.top, xOf(seconds), line.bottom),
          Radius.circular(fs * 0.12)),
      Paint()..color = c.dim);
  // Where the typing ends, and each lit step starts.
  if (e.typing.on) {
    var tx = xOf(codePlan(e).end);
    canvas.drawRect(
        Rect.fromLTWH(tx - 0.75, t.center.dy - fs * 0.4, 1.5, fs * 0.8),
        Paint()..color = c.dim);
  }
  for (var step in e.steps) {
    canvas.drawCircle(Offset(xOf(step.at), t.center.dy), fs * 0.18,
        Paint()..color = codeMark);
  }
  canvas.drawCircle(
      Offset(xOf(seconds), t.center.dy), fs * 0.32, Paint()..color = c.fg);
  String secs(double v) => v.toStringAsFixed(1);
  _text(canvas, "${secs(math.min(seconds, span.$2))} / ${secs(span.$2)} s",
      Offset(t.right + fs * 0.6, t.center.dy), fs * 0.72, c.dim);
}

/// CodeTabBox is a tab: [file]'s, its box and its close box.
class CodeTabBox {
  final String file;
  final Rect rect;
  final Rect close;
  const CodeTabBox(this.file, this.rect, this.close);
}

/// CodePaneBox is a pane: its box, its tab row, its tabs and its code.
class CodePaneBox {
  final int index;
  final Rect rect;
  final Rect tabRow;
  final List<CodeTabBox> tabs;
  final Rect code;
  const CodePaneBox(this.index, this.rect, this.tabRow, this.tabs, this.code);
}

/// CodeDividerBox is a line between panes: dragged across ([columns]) or
/// down, between shares [index] and [index] + 1.
class CodeDividerBox {
  final Rect hit;
  final bool columns;
  final int index;
  const CodeDividerBox(this.hit, this.columns, this.index);
}

/// CodeBoxes is where everything of a Code panel is, on the page.
class CodeBoxes {
  final Rect box;
  final Rect? bar;
  final Rect? fileList;
  final List<(String, Rect)> fileRows;
  final Rect panesArea;
  final List<CodePaneBox> panes;
  final List<CodeDividerBox> dividers;
  const CodeBoxes(this.box, this.bar, this.fileList, this.fileRows,
      this.panesArea, this.panes, this.dividers);
}

double _uiSize(CodeElement e) => e.fontSize * 0.86;
double _tabHeight(CodeElement e) => e.fontSize * 2.3;

/// codeTextPad is the space above a pane's first line.
double codeTextPad(CodeElement e) => e.fontSize * 0.7;

double _nameWidth(String name, double size) {
  var tp = TextPainter(
      text: TextSpan(
          text: name, style: TextStyle(fontFamily: _uiFont, fontSize: size)),
      textDirection: TextDirection.ltr)
    ..layout();
  var w = tp.width;
  tp.dispose();
  return w;
}

/// paneRects is [e]'s panes laid in [area] by its shares, and the lines
/// between them.
(List<Rect>, List<CodeDividerBox>) paneRects(CodeElement e, Rect area) {
  List<double> fr(List<double> s) {
    var sum = s.fold(0.0, (a, b) => a + b);
    return [for (var v in s) sum <= 0 ? 1 / s.length : v / sum];
  }

  var hit = e.fontSize * 0.7;
  var rects = <Rect>[];
  var divs = <CodeDividerBox>[];
  Rect r(double x, double y, double w, double h) => Rect.fromLTWH(
      area.left + x * area.width,
      area.top + y * area.height,
      w * area.width,
      h * area.height);
  switch (e.layout) {
    case CodeLayout.one:
      rects.add(area);
    case CodeLayout.twoSide || CodeLayout.threeSide:
      var c = fr(e.columns);
      var x = 0.0;
      for (var (i, w) in c.indexed) {
        rects.add(r(x, 0, w, 1));
        x += w;
        if (i < c.length - 1) {
          var at = area.left + x * area.width;
          divs.add(CodeDividerBox(
              Rect.fromLTRB(at - hit / 2, area.top, at + hit / 2, area.bottom),
              true,
              i));
        }
      }
    case CodeLayout.twoStacked:
      var rs = fr(e.rows);
      rects
        ..add(r(0, 0, 1, rs[0]))
        ..add(r(0, rs[0], 1, rs[1]));
      var at = area.top + rs[0] * area.height;
      divs.add(CodeDividerBox(
          Rect.fromLTRB(area.left, at - hit / 2, area.right, at + hit / 2),
          false,
          0));
    case CodeLayout.oneOverTwo:
      var rs = fr(e.rows), c = fr(e.columns);
      rects
        ..add(r(0, 0, 1, rs[0]))
        ..add(r(0, rs[0], c[0], rs[1]))
        ..add(r(c[0], rs[0], c[1], rs[1]));
      var y = area.top + rs[0] * area.height;
      var x = area.left + c[0] * area.width;
      divs
        ..add(CodeDividerBox(
            Rect.fromLTRB(area.left, y - hit / 2, area.right, y + hit / 2),
            false,
            0))
        ..add(CodeDividerBox(
            Rect.fromLTRB(x - hit / 2, y + hit / 2, x + hit / 2, area.bottom),
            true,
            0));
  }
  return (rects, divs);
}

/// codeBoxes lays [e] out in [box].
CodeBoxes codeBoxes(CodeElement e, Rect box) {
  var fs = e.fontSize;
  var barH = e.windowBar ? fs * 2.6 : 0.0;
  var bar =
      e.windowBar ? Rect.fromLTWH(box.left, box.top, box.width, barH) : null;
  var body = Rect.fromLTRB(box.left, box.top + barH, box.right, box.bottom);
  var listW = e.showFiles ? math.min(fs * 10.5, box.width * 0.3) : 0.0;
  var fileList = e.showFiles
      ? Rect.fromLTWH(body.left, body.top, listW, body.height)
      : null;
  var rows = <(String, Rect)>[];
  if (fileList != null) {
    var y = fileList.top + fs * 2.3;
    for (var f in e.files) {
      var row = Rect.fromLTWH(
          fileList.left + fs * 0.45, y, listW - fs * 0.9, fs * 2.0);
      if (row.bottom > fileList.bottom) break;
      rows.add((f.id, row));
      y += fs * 2.05;
    }
  }
  var area =
      Rect.fromLTRB(body.left + listW, body.top, body.right, body.bottom);
  var (rects, divs) = paneRects(e, area);
  var ui = _uiSize(e);
  var panes = <CodePaneBox>[];
  for (var (i, rect) in rects.indexed) {
    var row = Rect.fromLTWH(rect.left, rect.top, rect.width, _tabHeight(e));
    var tabs = <CodeTabBox>[];
    var x = row.left;
    var p = i < e.panes.length ? e.panes[i] : const CodePane();
    for (var id in p.tabs) {
      var f = e.file(id);
      if (f == null) continue;
      var w = _nameWidth(f.name, ui) + fs * 3.4;
      var t = Rect.fromLTWH(x, row.top, w, row.height);
      var c = fs * 1.25;
      tabs.add(CodeTabBox(id, t,
          Rect.fromLTWH(t.right - fs * 0.35 - c, t.center.dy - c / 2, c, c)));
      x += w;
    }
    panes.add(CodePaneBox(i, rect, row, tabs,
        Rect.fromLTRB(rect.left, row.bottom, rect.right, rect.bottom)));
  }
  return CodeBoxes(box, bar, fileList, rows, area, panes, divs);
}

/// CodeShow is what the stage adds to a Code panel's drawing: the tab each
/// pane was shown by hand (while paused), and a pane being edited, which
/// the editor covers.
class CodeShow {
  final Map<int, String> picked;
  final int editing;

  /// playing is whether the canvas is playing: its playbar shows pause.
  final bool playing;

  /// full shows the whole of its code and every lit step at once, by
  /// nobody's clock (its playbar's Full code button).
  final bool full;

  /// scroll is each pane scrolled by hand, in lines, over what the scene
  /// has it showing.
  final Map<int, double> scroll;

  /// onStage is whether it is drawn on the stage, where its playbar can
  /// be pressed: not in a video or a book.
  final bool onStage;
  const CodeShow(
      {this.onStage = false,
      this.picked = const {},
      this.editing = -1,
      this.playing = false,
      this.full = false,
      this.scroll = const {}});
}

/// codeShowOf is how the stage shows each Code panel, set by the
/// controller; null -- in an export -- each plays by its clock alone.
CodeShow Function(CodeElement e)? codeShowOf;

void _text(Canvas canvas, String t, Offset at, double size, Color colour,
    {FontWeight weight = FontWeight.w500,
    double? maxWidth,
    bool centreY = true,
    double spacing = 0}) {
  var tp = TextPainter(
      text: TextSpan(
          text: t,
          style: TextStyle(
              fontFamily: _uiFont,
              fontSize: size,
              fontWeight: weight,
              letterSpacing: spacing,
              color: colour)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: maxWidth == null ? null : "…")
    ..layout(maxWidth: maxWidth ?? double.infinity);
  tp.paint(canvas, centreY ? at - Offset(0, tp.height / 2) : at);
  tp.dispose();
}

/// paintCode draws [e] in [box] at [seconds] into its scene.
void paintCode(Canvas canvas, Rect box, CodeElement e,
    {double seconds = 0, CodeShow show = const CodeShow()}) {
  var c = CodeColours.of(e.theme);
  var fs = e.fontSize;
  var b = codeBoxes(e, box);
  var radius = Radius.circular(fs * 0.9);
  canvas.save();
  canvas.clipRRect(RRect.fromRectAndRadius(box, radius));
  canvas.drawRect(box, Paint()..color = c.bg);

  // The window bar: three dots and the project's name.
  if (b.bar case var bar?) {
    canvas.drawRect(bar, Paint()..color = c.bar);
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(Offset(bar.left + fs * (1.2 + i * 1.05), bar.center.dy),
          fs * 0.34, Paint()..color = c.line);
    }
    var play =
        show.onStage ? codePlaybar(e, bar) : const <CodePlayPart, Rect>{};
    var titleRoom = play.isEmpty
        ? bar.width - fs * 5.5
        : play.values.map((r) => r.left).reduce(math.min) - bar.left - fs * 5.2;
    _text(canvas, e.title, Offset(bar.left + fs * 4.6, bar.center.dy),
        _uiSize(e), c.dim,
        maxWidth: math.max(0, titleRoom));
    _paintPlaybar(canvas, e, c, play, seconds, show.playing, full: show.full);
  }

  var plan = codePlan(e);
  var open = {for (var p in e.shownPanes) ...p.tabs};

  // The files, down the side.
  if (b.fileList case var list?) {
    canvas.drawRect(list, Paint()..color = c.side);
    canvas.drawRect(Rect.fromLTWH(list.right - 1, list.top, 1, list.height),
        Paint()..color = c.line);
    _text(canvas, "FILES", Offset(list.left + fs * 0.9, list.top + fs * 1.2),
        fs * 0.62, c.dim,
        weight: FontWeight.w600, spacing: fs * 0.06);
    for (var (id, row) in b.fileRows) {
      var f = e.file(id)!;
      if (open.contains(id)) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(row, Radius.circular(fs * 0.3)),
            Paint()..color = c.bg);
      }
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(row.left + fs * 0.75, row.center.dy),
                  width: fs * 0.5,
                  height: fs * 0.5),
              Radius.circular(fs * 0.1)),
          Paint()..color = f.colour);
      var label = f.language.label;
      var labelW = _nameWidth(label, fs * 0.6);
      _text(canvas, f.name, Offset(row.left + fs * 1.4, row.center.dy),
          _uiSize(e), c.fg,
          weight: FontWeight.w400,
          maxWidth: math.max(0, row.width - fs * 2.0 - labelW));
      _text(canvas, label, Offset(row.right - labelW - fs * 0.3, row.center.dy),
          fs * 0.6, c.dim);
    }
  }

  // The panes.
  var lit = litSteps(e, seconds);
  for (var pane in b.panes) {
    _paintPane(canvas, e, c, pane, plan, lit, seconds, show);
  }
  // The lines between them.
  var (rects, _) = paneRects(e, b.panesArea);
  var line = Paint()..color = c.line;
  for (var r in rects) {
    if (r.left > b.panesArea.left + 0.5) {
      canvas.drawRect(Rect.fromLTWH(r.left, r.top, 1, r.height), line);
    }
    if (r.top > b.panesArea.top + 0.5) {
      canvas.drawRect(Rect.fromLTWH(r.left, r.top, r.width, 1), line);
    }
  }
  canvas.restore();
}

/// codeScrollLines is how many lines pane [pane] is scrolled down at
/// [seconds]: enough to keep the line being typed in view, or a lit
/// line's start; else none.
int codeScrollLines(CodeElement e, CodePaneBox pane, String file, int typed,
    String text, List<CodeStep> lit) {
  var lh = codeLineHeight(e.fontSize);
  var fits =
      math.max(1, ((pane.code.height - codeTextPad(e) * 2) / lh).floor());
  if (typed < text.length) {
    var line = "\n".allMatches(text.substring(0, typed)).length;
    return math.max(0, line - fits + 2);
  }
  for (var s in lit) {
    if (s.file == file && s.to > fits) return math.max(0, s.from - 3);
  }
  return 0;
}

void _paintPane(Canvas canvas, CodeElement e, CodeColours c, CodePaneBox pane,
    CodePlan plan, List<CodeStep> lit, double seconds, CodeShow show) {
  var fs = e.fontSize;
  var ui = _uiSize(e);
  var shown = show.full
      ? (show.picked[pane.index] ??
          (pane.index < e.shownPanes.length
              ? e.shownPanes[pane.index].shows
              : null))
      : shownFile(e, pane.index, seconds, plan,
          picked: show.picked[pane.index]);

  // Its tabs.
  canvas.drawRect(pane.tabRow, Paint()..color = c.side);
  canvas.drawRect(
      Rect.fromLTWH(
          pane.tabRow.left, pane.tabRow.bottom - 1, pane.tabRow.width, 1),
      Paint()..color = c.line);
  canvas.save();
  canvas.clipRect(pane.tabRow);
  for (var t in pane.tabs) {
    var f = e.file(t.file)!;
    var on = t.file == shown;
    if (on) {
      canvas.drawRect(t.rect, Paint()..color = c.bg);
      canvas.drawRect(
          Rect.fromLTWH(t.rect.left, t.rect.top, t.rect.width, fs * 0.18),
          Paint()..color = f.colour);
    } else {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(t.rect.left + fs * 1.0, t.rect.center.dy),
                  width: fs * 0.45,
                  height: fs * 0.45),
              Radius.circular(fs * 0.1)),
          Paint()..color = f.colour);
    }
    canvas.drawRect(
        Rect.fromLTWH(t.rect.right - 1, t.rect.top, 1, t.rect.height),
        Paint()..color = c.line);
    _text(
        canvas,
        f.name,
        Offset(t.rect.left + fs * (on ? 0.9 : 1.55), t.rect.center.dy),
        ui,
        on ? c.fg : c.dim,
        weight: on ? FontWeight.w500 : FontWeight.w400);
    // Its close cross.
    var x = t.close.deflate(t.close.width * 0.32);
    var pen = Paint()
      ..color = c.dim
      ..strokeWidth = math.max(1, fs * 0.09)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(x.topLeft, x.bottomRight, pen);
    canvas.drawLine(x.topRight, x.bottomLeft, pen);
  }
  canvas.restore();

  var f = shown == null ? null : e.file(shown);
  canvas.save();
  canvas.clipRect(pane.code);
  if (f == null) {
    _text(
        canvas,
        e.panes.isEmpty ? "" : "Drag a tab here, or pick a file from the list",
        pane.code.center,
        ui,
        c.dim,
        maxWidth: pane.code.width * 0.9,
        centreY: true);
    canvas.restore();
    return;
  }
  if (show.editing == pane.index) {
    canvas.restore();
    return;
  }

  var typed = show.full ? f.text.length : typedCount(e, f.id, seconds, plan);
  var span = plan.files[f.id];
  // The caret only in the file being typed now, not one waiting its turn.
  var typing = typed < f.text.length &&
      span != null &&
      seconds >= span.$1 &&
      seconds < span.$2;
  var lh = codeLineHeight(fs);
  var pad = codeTextPad(e);
  var charW = codeCharWidth(fs);
  var lines = "\n".allMatches(f.text.substring(0, typed)).length + 1;
  var allLines = f.text.split("\n");
  var digits = math.max(2, "${allLines.length}".length);
  var gutter = e.lineNumbers ? digits * charW + fs * 1.6 : fs * 0.5;
  var textLeft = pane.code.left + gutter;
  // Lit: as the clock has it; shown whole, every step of the file.
  var here = [
    for (var s in show.full ? e.steps : lit)
      if (s.file == f.id) s
  ];
  // Scrolled by hand, where it has been; else as the scene has it.
  var scroll = show.scroll[pane.index] ??
      (show.full
          ? 0.0
          : codeScrollLines(e, pane, f.id, typed, f.text, lit).toDouble());
  var top = pane.code.top + pad - scroll * lh;

  // Lit lines: a band, a marker, the rest dimmed (for the first), and the
  // note beside them.
  for (var s in here) {
    var from = s.from.clamp(1, allLines.length),
        to = s.to.clamp(from, allLines.length);
    var y0 = top + (from - 1) * lh, y1 = top + to * lh;
    canvas.drawRect(Rect.fromLTRB(pane.code.left, y0, pane.code.right, y1),
        Paint()..color = c.band);
    canvas.drawRect(
        Rect.fromLTRB(pane.code.left, y0, pane.code.left + fs * 0.22, y1),
        Paint()..color = codeMark);
  }

  // The line numbers, as far as it is typed.
  // One block for the lines in view, right-aligned: laid out once, not a
  // line at a time.
  if (e.lineNumbers) {
    var first = math.max(0, ((pane.code.top - top) / lh).floor());
    var last = math.min(lines, ((pane.code.bottom - top) / lh).ceil() + 1);
    if (last > first) {
      var width = textLeft - fs * 0.8 - pane.code.left;
      var n = TextPainter(
          text: TextSpan(
              text: [for (var i = first; i < last; i++) "${i + 1}"].join("\n"),
              style: codeStyle(fs, c.gutter)),
          strutStyle: codeStrut(fs),
          textAlign: TextAlign.right,
          textDirection: TextDirection.ltr)
        ..layout(minWidth: width, maxWidth: width);
      n.paint(canvas, Offset(pane.code.left, top + first * lh));
      n.dispose();
    }
  }

  // The code, typed so far.
  var tp = TextPainter(
      text: codeSpan(e, f, f.text, typed, c),
      strutStyle: codeStrut(fs),
      textDirection: TextDirection.ltr)
    ..layout();
  tp.paint(canvas, Offset(textLeft, top));
  if (typing && e.typing.caret) {
    var at =
        tp.getOffsetForCaret(TextPosition(offset: _shownLength(tp)), Rect.zero);
    canvas.drawRect(
        Rect.fromLTWH(textLeft + at.dx + fs * 0.05, top + at.dy + lh * 0.18,
            math.max(1.5, fs * 0.12), lh * 0.64),
        Paint()..color = c.caret);
  }
  tp.dispose();

  if (here.isNotEmpty && e.dim && !show.full) {
    var s = here.first;
    var from = s.from.clamp(1, allLines.length),
        to = s.to.clamp(from, allLines.length);
    var y0 = top + (from - 1) * lh, y1 = top + to * lh;
    var dimmer = Paint()..color = c.dimmer;
    canvas.drawRect(
        Rect.fromLTRB(pane.code.left, pane.code.top, pane.code.right, y0),
        dimmer);
    canvas.drawRect(
        Rect.fromLTRB(pane.code.left, y1, pane.code.right, pane.code.bottom),
        dimmer);
  }
  for (var s in here) {
    if (s.note.isEmpty) continue;
    var from = s.from.clamp(1, allLines.length),
        to = s.to.clamp(from, allLines.length);
    var widest = 0;
    for (var l in allLines.sublist(from - 1, to)) {
      widest = math.max(widest, l.replaceAll("\t", "    ").length);
    }
    _paintNote(
        canvas,
        s.note,
        textLeft + widest * charW + fs * 1.3,
        top + (from - 1 + (to - from + 1) / 2) * lh,
        top + to * lh,
        pane.code,
        fs);
  }
  canvas.restore();
}

int _shownLength(TextPainter tp) => tp.text?.toPlainText().length ?? 0;

/// _paintNote draws a lit line's note: a marker-yellow label pointing at
/// the lines, beside them at [x] (their middle at [y]) where it fits, else
/// just under them ([below]) at the pane's right, pointing up.
void _paintNote(Canvas canvas, String note, double x, double y, double below,
    Rect pane, double fs) {
  var tp = TextPainter(
      text: TextSpan(
          text: note,
          style: TextStyle(
              fontFamily: _uiFont,
              fontSize: fs * 0.8,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1D1606))),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: "…")
    ..layout(maxWidth: math.max(fs * 4, pane.width - fs * 2));
  var w = tp.width + fs * 1.1, h = tp.height + fs * 0.6;
  var paint = Paint()..color = codeMark;
  var beside = x + w <= pane.right - fs * 0.4;
  var r = beside
      ? Rect.fromLTWH(x, y - h / 2, w, h)
      : Rect.fromLTWH(math.max(pane.left + fs * 0.4, pane.right - w - fs * 0.6),
          below + fs * 0.45, w, h);
  canvas.drawRRect(
      RRect.fromRectAndRadius(r, Radius.circular(fs * 0.4)), paint);
  var p = fs * 0.35;
  canvas.drawPath(
      beside
          ? (Path()
            ..moveTo(r.left - p, r.center.dy)
            ..lineTo(r.left + 1, r.center.dy - p)
            ..lineTo(r.left + 1, r.center.dy + p)
            ..close())
          : (Path()
            ..moveTo(r.left + fs * 1.2, r.top - p)
            ..lineTo(r.left + fs * 1.2 - p, r.top + 1)
            ..lineTo(r.left + fs * 1.2 + p, r.top + 1)
            ..close()),
      paint);
  tp.paint(canvas, Offset(r.left + fs * 0.55, r.top + fs * 0.3));
  tp.dispose();
}

/// CodeHit is what a press on a Code panel landed on.
sealed class CodeHit {
  const CodeHit();
}

class CodeTabHit extends CodeHit {
  final int pane;
  final String file;
  final bool close;
  const CodeTabHit(this.pane, this.file, {this.close = false});
}

class CodePlayHit extends CodeHit {
  final CodePlayPart part;

  /// at is where on its track it was pressed, in the scene's seconds.
  final double at;
  const CodePlayHit(this.part, {this.at = 0});
}

class CodeDividerHit extends CodeHit {
  final CodeDividerBox divider;
  const CodeDividerHit(this.divider);
}

class CodeFileHit extends CodeHit {
  final String file;
  const CodeFileHit(this.file);
}

class CodePaneHit extends CodeHit {
  final int pane;

  /// inTabs is whether it is on the pane's tab row (past its tabs).
  final bool inTabs;
  const CodePaneHit(this.pane, {this.inTabs = false});
}

/// codeHitAt is what of [e] is at [point] on the page, or null.
CodeHit? codeHitAt(CodeElement e, Offset point) {
  var b = codeBoxes(e, e.bounds);
  for (var MapEntry(:key, :value) in codePlaybar(e, b.bar).entries) {
    var reach = value.inflate(e.fontSize * 0.2);
    if (!reach.contains(point)) continue;
    var end = lessonSpan(e)?.$2 ?? 0;
    return CodePlayHit(key,
        at: end * ((point.dx - value.left) / value.width).clamp(0.0, 1.0));
  }
  for (var d in b.dividers) {
    if (d.hit.contains(point)) return CodeDividerHit(d);
  }
  for (var (id, row) in b.fileRows) {
    if (row.contains(point)) return CodeFileHit(id);
  }
  for (var p in b.panes) {
    for (var t in p.tabs) {
      if (t.rect.contains(point) && t.rect.overlaps(p.tabRow)) {
        return CodeTabHit(p.index, t.file,
            close: t.close.inflate(2).contains(point));
      }
    }
    if (p.tabRow.contains(point)) return CodePaneHit(p.index, inTabs: true);
    if (p.rect.contains(point)) return CodePaneHit(p.index);
  }
  return null;
}

/// codeTabDrop is where a tab dropped at [point] goes: the pane, and the
/// place among its tabs (by which tab's middle it is before); null off the
/// panes.
(int, int)? codeTabDrop(CodeElement e, Offset point) {
  var b = codeBoxes(e, e.bounds);
  for (var p in b.panes) {
    if (!p.rect.contains(point)) continue;
    if (!p.tabRow.contains(point)) return (p.index, p.tabs.length);
    var i = p.tabs.indexWhere((t) => point.dx < t.rect.center.dx);
    return (p.index, i < 0 ? p.tabs.length : i);
  }
  return null;
}

/// codeDividerDragged is [e] with divider [d] moved to [point]: the two
/// panes either side of it shared out again, neither under an eighth.
CodeElement codeDividerDragged(CodeElement e, CodeDividerBox d, Offset point) =>
    codeDividerDraggedIn(e, d, point, codeBoxes(e, e.bounds).panesArea);

/// codeDividerDraggedIn is the same for panes laid out in [area] (the Code
/// Studio's, in its own pixels).
CodeElement codeDividerDraggedIn(
    CodeElement e, CodeDividerBox d, Offset point, Rect area) {
  var shares = [...(d.columns ? e.columns : e.rows)];
  if (d.index + 1 >= shares.length) return e;
  var sum = shares.fold(0.0, (a, b) => a + b);
  var before = shares.sublist(0, d.index).fold(0.0, (a, b) => a + b);
  var pair = shares[d.index] + shares[d.index + 1];
  var f = d.columns
      ? (point.dx - area.left) / area.width
      : (point.dy - area.top) / area.height;
  var least = sum / 8;
  var a =
      (f * sum - before).clamp(least, math.max(least, pair - least)).toDouble();
  shares[d.index] = a;
  shares[d.index + 1] = pair - a;
  return d.columns ? e.copyWith(columns: shares) : e.copyWith(rows: shares);
}

/// codeEditorRect is where the stage's editor covers pane [pane]'s code
/// (past its line numbers), and the scroll it opens at.
Rect? codeEditorRect(CodeElement e, int pane) {
  var b = codeBoxes(e, e.bounds);
  if (pane < 0 || pane >= b.panes.length) return null;
  return b.panes[pane].code;
}

/// codeTrackSeconds is where on [e]'s playbar track [point] is, in the
/// scene's seconds, held to the track: for a drag along it.
double codeTrackSeconds(CodeElement e, Offset point) {
  var t = codePlaybar(e, codeBoxes(e, e.bounds).bar)[CodePlayPart.track];
  var end = lessonSpan(e)?.$2 ?? 0;
  if (t == null) return 0;
  return end * ((point.dx - t.left) / t.width).clamp(0.0, 1.0);
}

/// codeScrollRoom is how many lines pane [pane] of [e] can be scrolled
/// down showing [file]: as far as its last line at the pane's foot.
double codeScrollRoom(CodeElement e, int pane, String file) {
  var b = codeBoxes(e, e.bounds);
  var f = e.file(file);
  if (pane < 0 || pane >= b.panes.length || f == null) return 0;
  var lh = codeLineHeight(e.fontSize);
  var fits = (b.panes[pane].code.height - codeTextPad(e) * 2) / lh;
  return math.max(0, f.text.split("\n").length - fits + 1);
}

/// codeShownScroll is how far pane [pane] of [e] is scrolled now, in
/// lines: by hand where it has been, else as the scene has it at
/// [seconds].
double codeShownScroll(CodeElement e, int pane, double seconds, CodeShow show) {
  var b = codeBoxes(e, e.bounds);
  if (pane < 0 || pane >= b.panes.length) return 0;
  if (show.scroll[pane] case var s?) return s;
  if (show.full) return 0;
  var plan = codePlan(e);
  var file = shownFile(e, pane, seconds, plan, picked: show.picked[pane]);
  var f = file == null ? null : e.file(file);
  if (f == null) return 0;
  return codeScrollLines(e, b.panes[pane], f.id,
          typedCount(e, f.id, seconds, plan), f.text, litSteps(e, seconds))
      .toDouble();
}
