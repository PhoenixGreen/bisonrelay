import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/code_runners.dart';
import 'package:bruig/plugin_system/canvas/model/code_timing.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_run_element.dart';
import 'package:flutter/painting.dart';

// code_run_painter.dart draws a Run panel (code_run_element.dart): a bar
// with what runs it and its Run button, the preview its last run made, and
// what that run printed -- or, before its time on the scene's clock, when
// it will run.

const _ui = "Inter";
const _mono = "RobotoMono";
const _bg = Color(0xFF0E1114);
const _bar = Color(0xFF1B1F25);
const _line = Color(0xFF262B33);
const _fg = Color(0xFFD7DEE7);
const _dim = Color(0xFF8A93A0);
const _go = Color(0xFF2ED6A1);
const _warn = Color(0xFFF2C14E);
const _error = Color(0xFFFF8A8A);

/// CodeRunBoxes is where a Run panel's parts are, on the page.
class CodeRunBoxes {
  final Rect bar;
  final Rect runButton;
  final Rect? preview;
  final Rect? output;
  const CodeRunBoxes(this.bar, this.runButton, this.preview, this.output);
}

/// codeRunBoxes lays [e] out in [box].
CodeRunBoxes codeRunBoxes(CodeRunElement e, Rect box, {CodeRunner? runner}) {
  var fs = e.outputSize;
  var bar = Rect.fromLTWH(box.left, box.top, box.width, fs * 2.7);
  var bw = fs * 5.2, bh = fs * 1.9;
  var run =
      Rect.fromLTWH(bar.right - bw - fs * 0.6, bar.center.dy - bh / 2, bw, bh);
  var body = Rect.fromLTRB(box.left, bar.bottom, box.right, box.bottom);
  var shows = e.shows;
  // Something that makes no picture shows only its output.
  if (runner != null && !runner.previews && shows == CodeRunShows.both) {
    shows = CodeRunShows.output;
  }
  return switch (shows) {
    CodeRunShows.preview => CodeRunBoxes(bar, run, body, null),
    CodeRunShows.output => CodeRunBoxes(bar, run, null, body),
    CodeRunShows.both => CodeRunBoxes(
        bar,
        run,
        Rect.fromLTWH(body.left, body.top, body.width, body.height * e.split),
        Rect.fromLTRB(body.left, body.top + body.height * e.split, body.right,
            body.bottom)),
  };
}

/// CodeRunShow is what the stage adds to a Run panel's drawing: whether it
/// is running now, and whether its live preview covers its picture.
class CodeRunShow {
  final bool running;
  final bool live;

  /// logs is what it has printed so far, while running.
  final List<CodeLog> logs;

  /// now shows its run whatever the scene's clock says: run by hand, or its
  /// Code panel showing the whole of its code (Ken, 2026-11-15).
  final bool now;
  const CodeRunShow(
      {this.running = false,
      this.live = false,
      this.logs = const [],
      this.now = false});
}

/// codeRunShowOf is how the stage shows each Run panel, set by the
/// controller; null in an export.
CodeRunShow Function(CodeRunElement e)? codeRunShowOf;

void _text(Canvas canvas, String t, Offset at, double size, Color colour,
    {FontWeight weight = FontWeight.w500,
    double? maxWidth,
    String family = _ui,
    bool centre = false}) {
  var tp = TextPainter(
      text: TextSpan(
          text: t,
          style: TextStyle(
              fontFamily: family,
              fontSize: size,
              fontWeight: weight,
              color: colour)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: maxWidth == null ? null : "…")
    ..layout(maxWidth: maxWidth ?? double.infinity);
  tp.paint(
      canvas,
      centre
          ? at - Offset(tp.width / 2, tp.height / 2)
          : at - Offset(0, tp.height / 2));
  tp.dispose();
}

/// waitingSaid is what a Run panel says before it has run at [seconds]:
/// null once it shows its run.
String? waitingSaid(CodeRunElement e, CodeElement? code, double seconds) {
  var at = runAt(e, code);
  if (at != null && seconds < at) {
    return e.when == CodeRunWhen.typed
        ? "Runs when the typing ends, at ${at.toStringAsFixed(1)} s"
        : "Runs as the scene starts";
  }
  if (e.result == null) return "Press Run";
  return null;
}

/// paintCodeRun draws [e], running [code], in [box] at [seconds]; [image]
/// is its preview's picture, once loaded.
void paintCodeRun(Canvas canvas, Rect box, CodeRunElement e, CodeElement? code,
    {double seconds = 0,
    ui.Image? image,
    CodeRunShow show = const CodeRunShow()}) {
  var fs = e.outputSize;
  var runner = runnerOf(e, code);
  var b = codeRunBoxes(e, box, runner: runner);
  canvas.save();
  canvas.clipRRect(RRect.fromRectAndRadius(box, Radius.circular(fs * 0.9)));
  canvas.drawRect(box, Paint()..color = _bg);

  // The bar: "Run", what runs it, and the button.
  canvas.drawRect(b.bar, Paint()..color = _bar);
  _text(canvas, "Run", Offset(b.bar.left + fs * 1.1, b.bar.center.dy),
      fs * 1.05, const Color(0xFFB7BEC7));
  var label = runner.online ? "${runner.label} · online" : runner.label;
  var lp = TextPainter(
      text: TextSpan(
          text: label,
          style: TextStyle(fontFamily: _ui, fontSize: fs * 0.78, color: _dim)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: "…")
    ..layout(maxWidth: math.max(0, b.runButton.left - b.bar.left - fs * 5.5));
  var pill = Rect.fromLTWH(b.bar.left + fs * 3.6, b.bar.center.dy - fs * 0.75,
      lp.width + fs * 1.2, fs * 1.5);
  canvas.drawRRect(
      RRect.fromRectAndRadius(pill, Radius.circular(fs * 0.75)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, fs * 0.06)
        ..color = runner.online ? _warn : const Color(0xFF363D47));
  lp.paint(
      canvas, Offset(pill.left + fs * 0.6, pill.center.dy - lp.height / 2));
  lp.dispose();
  var button = RRect.fromRectAndRadius(b.runButton, Radius.circular(fs * 0.5));
  canvas.drawRRect(button,
      Paint()..color = show.running ? _go.withValues(alpha: 0.55) : _go);
  var tri = b.runButton.left + fs * 1.1;
  canvas.drawPath(
      Path()
        ..moveTo(tri, b.runButton.center.dy - fs * 0.42)
        ..lineTo(tri + fs * 0.72, b.runButton.center.dy)
        ..lineTo(tri, b.runButton.center.dy + fs * 0.42)
        ..close(),
      Paint()..color = const Color(0xFF062018));
  _text(
      canvas,
      show.running ? "…" : "Run",
      Offset(tri + fs * 1.2, b.runButton.center.dy),
      fs * 0.95,
      const Color(0xFF062018),
      weight: FontWeight.w600);

  var waiting = show.running || show.live || (show.now && e.result != null)
      ? null
      : waitingSaid(e, code, seconds);

  // The preview: the picture of the last run.
  if (b.preview case var p?) {
    if (waiting != null) {
      canvas.drawRect(p, Paint()..color = const Color(0xFF15191E));
      _text(canvas, waiting, p.center, fs * 1.0, _dim,
          centre: true, maxWidth: p.width * 0.9);
    } else if (image != null) {
      canvas.drawRect(p, Paint()..color = const Color(0xFFFFFFFF));
      // As wide as the preview, from its top: the page as it was laid out.
      var src = Rect.fromLTWH(0, 0, image.width.toDouble(),
          math.min(image.height.toDouble(), image.width * p.height / p.width));
      var dst = Rect.fromLTWH(
          p.left, p.top, p.width, p.width * src.height / src.width);
      canvas.save();
      canvas.clipRect(p);
      canvas.drawImageRect(
          image, src, dst, Paint()..filterQuality = FilterQuality.medium);
      canvas.restore();
    } else {
      canvas.drawRect(
          p,
          Paint()
            ..color = runner.previews
                ? const Color(0xFFFFFFFF)
                : const Color(0xFF15191E));
      if (show.running) {
        _text(canvas, "Running…", p.center, fs, _dim, centre: true);
      }
    }
  }

  // The output: what the run printed.
  if (b.output case var o?) {
    canvas.drawRect(
        Rect.fromLTWH(o.left, o.top, o.width, 1), Paint()..color = _line);
    _text(canvas, "OUTPUT", Offset(o.left + fs * 1.1, o.top + fs * 1.2),
        fs * 0.72, _dim,
        weight: FontWeight.w600);
    var logs = show.running || show.live
        ? show.logs
        : waiting == null
            ? (e.result?.logs ?? const <CodeLog>[])
            : const <CodeLog>[];
    var y = o.top + fs * 2.3;
    var lineH = fs * 1.55;
    // The last lines that fit, as a console scrolled to its end.
    var fits = math.max(0, ((o.bottom - y - fs * 0.6) / lineH).floor());
    var shown = logs.length > fits ? logs.sublist(logs.length - fits) : logs;
    canvas.save();
    canvas.clipRect(o);
    for (var l in shown) {
      var (mark, colour) = switch (l.kind) {
        CodeLogKind.log => ("›", _fg),
        CodeLogKind.warn => ("!", _warn),
        CodeLogKind.error => ("✕", _error),
        CodeLogKind.note => ("", _dim),
      };
      if (mark.isNotEmpty) {
        _text(canvas, mark, Offset(o.left + fs * 1.1, y + lineH / 2), fs * 0.9,
            const Color(0xFF6E7989),
            family: _mono);
      }
      _text(canvas, l.text, Offset(o.left + fs * 2.3, y + lineH / 2), fs * 0.95,
          colour,
          family: l.kind == CodeLogKind.note ? _ui : _mono,
          weight: FontWeight.w400,
          maxWidth: math.max(0, o.width - fs * 3.2));
      y += lineH;
    }
    canvas.restore();
  }
  canvas.restore();
}
