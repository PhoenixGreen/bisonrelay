import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/data_styles.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/page_style.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/canvas_audio_fake.dart';

// canvas_page_style_test.dart is a whole page in one data style, and a
// page's data laid out over it (Ken, 2026-11-17, the improvements report's
// fifth item).

TextElement words(String id, double size) => TextElement(ElementBase(id: id),
    text: id,
    textSpec: TextSpec(fontSize: size, color: const Color(0xFF000000)));

void main() {
  var broadcast = dataStyleNamed("Broadcast")!;

  test("a page's words take the style's faces and inks by their size", () {
    var page = pageInStyle([
      words("title", 60),
      words("body", 24),
      words("source", 14),
      const ChartElement(ElementBase(id: "c")),
      const TableElement(ElementBase(id: "t"), rows: [
        ["A"]
      ]),
    ], broadcast);
    var title = page[0] as TextElement, body = page[1] as TextElement;
    var source = page[2] as TextElement;
    expect(title.textSpec.fontFamily, broadcast.headFont);
    expect(body.textSpec.fontFamily, broadcast.bodyFont);
    expect(body.textSpec.color, broadcast.ink);
    expect(source.textSpec.color, broadcast.dim, reason: "small print");
    expect((page[3] as ChartElement).style, "Broadcast");
    expect((page[4] as TableElement).style, "Broadcast");
  });

  test("layouts fill the area, apart, and never overlap", () {
    const area = Rect.fromLTWH(0, 0, 1000, 600);
    for (var l in PageLayout.values) {
      var rects = pageLayoutRects(5, l, area, 20);
      expect(rects, hasLength(5), reason: l.name);
      for (var i = 0; i < rects.length; i++) {
        expect(area.inflate(0.01).contains(rects[i].topLeft), isTrue);
        for (var j = i + 1; j < rects.length; j++) {
          expect(
              rects[i].intersect(rects[j]).isEmpty ||
                  rects[i].intersect(rects[j]).width <= 0 ||
                  rects[i].intersect(rects[j]).height <= 0,
              isTrue,
              reason: "${l.name} $i $j");
        }
      }
    }
    var main = pageLayoutRects(3, PageLayout.main, area, 20);
    expect(main.first.width, greaterThan(main[1].width));
  });

  test("the page styled, and laid out, each one step to undo", () {
    var c = CanvasController(
        CanvasDocument(elements: [
          words("title", 60),
          const ChartElement(ElementBase(id: "a", width: 100, height: 80)),
          const ChartElement(
              ElementBase(id: "b", x: 300, y: 200, width: 100, height: 80)),
        ]),
        audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    c.stylePage(broadcast);
    expect(c.document.background.spec.background, broadcast.ground);
    expect((c.document.elementById("a") as ChartElement).style, "Broadcast");
    c.undo();
    expect((c.document.elementById("a") as ChartElement).style, isEmpty);
    var charts = c.document.elements.whereType<ChartElement>().toList();
    c.layOutPage(charts, PageLayout.rows2);
    var a = c.document.elementById("a")!, b = c.document.elementById("b")!;
    expect(a.base.y, b.base.y, reason: "side by side");
    expect(a.base.width, greaterThan(100), reason: "filling the page");
    c.undo();
    expect(c.document.elementById("a")!.base.width, 100);
  });

  test("a report: key figures along the top, charts left, tables right", () {
    const area = Rect.fromLTWH(0, 0, 1000, 600);
    var r = reportLayoutRects(["figure", "chart", "table", "figure"], area, 20);
    expect(r[0].top, 0);
    expect(r[3].top, 0, reason: "both figures in the strip");
    expect(r[1].top, greaterThan(r[0].bottom));
    expect(r[1].right, lessThan(r[2].left), reason: "chart left of table");
    var snapped = snapToBaseline(const Rect.fromLTWH(3, 17, 98, 186), 18);
    expect(snapped, const Rect.fromLTWH(0, 18, 90, 180));
  });
}
