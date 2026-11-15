import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/code_highlight.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/render/code_painter.dart';
import 'package:flutter/painting.dart';

// code_html.dart is a Code panel's file as a page of its own, for a book:
// the whole of it, coloured as the panel colours it, with its line numbers,
// each lit step's lines marked and its note beside them -- in a frame over
// the pane, so a reader scrolls it and can select it, as they can't a
// picture of it (Ken, 2026-11-15).

String _css(Color c) =>
    "#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, "0")}";

String _esc(String s) => s
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");

/// codeFileHtml is [file] of [e] as a page, its type [px] pixels high.
String codeFileHtml(CodeElement e, CodeFile file, {required double px}) {
  var c = CodeColours.of(e.theme);
  var text = file.text;
  var runs = highlightRuns(file.language, text);
  if (e.links) runs = withLinks(runs, text, linkNames(e, file.id));
  var lines = text.split("\n");
  var digits = math.max(2, "${lines.length}".length);
  // Each line's lit step, and the note on its first line.
  var lit = <int, CodeStep>{};
  var notes = <int, String>{};
  for (var s in e.steps) {
    if (s.file != file.id) continue;
    var from = s.from.clamp(1, lines.length),
        to = s.to.clamp(from, lines.length);
    for (var l = from; l <= to; l++) {
      lit.putIfAbsent(l, () => s);
    }
    if (s.note.isNotEmpty) notes.putIfAbsent(from, () => s.note);
  }
  var out = StringBuffer();
  var line = 1;
  void open(int n) {
    out.write('<div class="l${lit.containsKey(n) ? " lit" : ""}">'
        '<span class="g">$n</span>');
  }

  void close(int n) {
    if (notes[n] case var note?) {
      out.write('<span class="note">${_esc(note)}</span>');
    }
    out.write("</div>");
  }

  open(line);
  for (var r in runs) {
    var colour = _css(c.role(r.role));
    var linked = r.link.isEmpty ? null : e.file(r.link);
    var style = linked == null
        ? "color:$colour"
        : "color:$colour;border-bottom:2px solid ${_css(linked.colour)}";
    var pieces = text.substring(r.start, r.end).split("\n");
    for (var (i, piece) in pieces.indexed) {
      if (i > 0) {
        close(line);
        line++;
        open(line);
      }
      if (piece.isNotEmpty) {
        out.write('<span style="$style">${_esc(piece)}</span>');
      }
    }
  }
  close(line);
  var lh = px * 1.55;
  return '''<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;background:${_css(c.bg)};}
body{overflow:auto;padding:${px * 0.7}px 0;}
.l{font:${px}px/${lh}px Menlo,Consolas,"DejaVu Sans Mono",monospace;color:${_css(c.fg)};white-space:pre;tab-size:4;min-height:${lh}px;padding-right:24px;}
.lit{background:rgba(${(c.band.r * 255).round()},${(c.band.g * 255).round()},${(c.band.b * 255).round()},${c.band.a.toStringAsFixed(3)});box-shadow:inset 4px 0 0 ${_css(codeMark)};}
.g{display:inline-block;width:${digits}ch;padding:0 ${px * 0.8}px 0 ${px * 0.8}px;text-align:right;color:${_css(c.gutter)};user-select:none;-webkit-user-select:none;}
.note{margin-left:1.5em;padding:2px 8px;border-radius:6px;background:${_css(codeMark)};color:#1d1606;font:600 ${px * 0.8}px/1.3 -apple-system,"Helvetica Neue",Arial,sans-serif;white-space:nowrap;}
</style></head><body>${out.toString()}</body></html>''';
}
