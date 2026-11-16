import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/vector_canvas.dart';
import 'package:bruig/plugin_system/canvas/export/vector_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_vector_export_test.dart is a chart or a table saved as SVG or PDF
// with its shapes as paths and its words as words (Ken, 2026-11-17, the
// improvements report's vector export).

/// ink is the dark ground the elements' default words are set for.
const ink = Color(0xFF111827);

const league = "Club\tPts\nArsenal\t46\nLiverpool\t44\nChelsea\t40";

ChartElement bars() => ChartElement(
    const ElementBase(id: "c", name: "League", width: 600, height: 360),
    type: ChartType.horizontalBar,
    title: "Points so far",
    showValues: true,
    data: ChartData.parse(league));

TableElement table() => const TableElement(
        ElementBase(id: "t", name: "Table", width: 400, height: 160),
        rows: [
          ["Club", "Pts"],
          ["Arsenal", "46"],
          ["Liverpool", "44"],
        ]);

/// out saves [bytes] for a look, when VECTOR_OUT names a folder.
void out(String name, List<int> bytes) {
  var dir = Platform.environment["VECTOR_OUT"];
  if (dir != null) File("$dir/$name").writeAsBytesSync(bytes);
}

void main() {
  test("shapes recorded where the transform puts them, inside their clip", () {
    var v = VectorCanvas(const Size(200, 100));
    v.save();
    v.translate(10, 20);
    v.scale(2);
    v.clipRect(const Rect.fromLTWH(0, 0, 30, 30));
    v.drawRect(const Rect.fromLTWH(1, 1, 5, 5),
        Paint()..color = const Color(0xFFFF0000));
    v.restore();
    v.drawCircle(
        const Offset(50, 50), 10, Paint()..color = const Color(0x80000000));
    var rect = v.ops[0] as VShape;
    expect(rect.polys.single.points.first, const Offset(12, 22));
    expect(rect.polys.single.points[2], const Offset(22, 32));
    expect(rect.clip, 0);
    expect(v.clips.single.polys.single.points[2], const Offset(70, 80));
    var dot = v.ops[1] as VShape;
    expect(dot.clip, -1, reason: "the clip ended with the restore");
    expect(dot.fill!.a, closeTo(0.5, 0.01));
    expect(dot.polys.single.points.length, greaterThanOrEqualTo(24));
  });

  test("a gradient or a paragraph it wasn't told the words of: a picture", () {
    var v = VectorCanvas(const Size(100, 100));
    v.drawRect(
        const Rect.fromLTWH(0, 0, 50, 50),
        Paint()
          ..shader = ui.Gradient.linear(const Offset(0, 0), const Offset(50, 0),
              [const Color(0xFF000000), const Color(0xFFFFFFFF)]));
    var tp = TextPainter(
        text: const TextSpan(text: "Hello", style: TextStyle(fontSize: 12)),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(v, const Offset(10, 60));
    expect(v.ops.whereType<VImage>(), hasLength(2));
    // Told: words.
    paintTp(tp, v, const Offset(10, 80));
    var words = v.ops.whereType<VText>().single;
    expect(words.text, "Hello");
    expect(words.matrix[4], 10);
    expect(words.width, closeTo(tp.width, 0.5));
    // Laid out to fill a wide box, its width is still its letters'.
    var wide = TextPainter(
        text: const TextSpan(text: "Hi", style: TextStyle(fontSize: 12)),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr)
      ..layout(minWidth: 300, maxWidth: 300);
    paintTp(wide, v, Offset.zero);
    var hi = v.ops.whereType<VText>().last;
    expect(hi.width, lessThan(40));
    expect(hi.matrix[4], greaterThan(100), reason: "centred in the box");
    wide.dispose();
    v.dispose();
    tp.dispose();
  });

  test("a chart as SVG: its words as words, its bars as paths", () async {
    var bytes = (await vectorOf(bars(), VectorFormat.svg, ground: ink))!;
    out("chart.svg", bytes);
    var svg = utf8.decode(bytes);
    expect(svg, startsWith("<?xml"));
    expect(svg, contains("<svg"));
    for (var w in ["Points so far", "Arsenal", "Liverpool", "Chelsea", "46"]) {
      expect(svg, contains(">$w</text>"), reason: w);
    }
    expect(RegExp("<path ").allMatches(svg).length, greaterThanOrEqualTo(3));
    expect(svg, isNot(contains("<image")),
        reason: "nothing in a plain chart needs a picture");
    expect(svg.trim(), endsWith("</svg>"));
  });

  test("a chart as PDF: a page with its words in a standard face", () async {
    var bytes = (await vectorOf(bars(), VectorFormat.pdf, ground: ink))!;
    out("chart.pdf", bytes);
    var text = latin1.decode(bytes);
    expect(text, startsWith("%PDF-1.4"));
    expect(text, contains("/BaseFont /Helvetica"));
    expect(text.trim(), endsWith("%%EOF"));
    // Every object where the cross-reference table says it is.
    var xref =
        int.parse(RegExp(r"startxref\n(\d+)").firstMatch(text)!.group(1)!);
    expect(text.substring(xref, xref + 4), "xref");
    var entries = RegExp(r"(\d{10}) 00000 n").allMatches(text).toList();
    for (var (i, m) in entries.indexed) {
      var at = int.parse(m.group(1)!);
      expect(text.substring(at), startsWith("${i + 1} 0 obj"));
    }
  });

  test("a table as SVG and PDF", () async {
    var svg =
        utf8.decode((await vectorOf(table(), VectorFormat.svg, ground: ink))!);
    out("table.svg", utf8.encode(svg));
    for (var w in ["Club", "Arsenal", "44"]) {
      expect(svg, contains(">$w</text>"), reason: w);
    }
    var pdf = (await vectorOf(table(), VectorFormat.pdf, ground: ink))!;
    out("table.pdf", pdf);
    // Its page's words, in its content stream (object 4).
    var text = latin1.decode(pdf);
    var start = text.indexOf("stream\n", text.indexOf("4 0 obj")) + 7;
    var end = text.indexOf("\nendstream", start);
    var content = latin1.decode(zlib.decode(pdf.sublist(start, end)));
    expect(content, contains("(Arsenal) Tj"));
  });
}
