import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_data.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_chart_card_test.dart is a chart drawn on a card of its own
// (ChartElement.box): The History of Decred's data pages set each chart on
// a rounded panel with its caption above it, three elements where one will
// do (Ken, 2026-11-18: "charts have titles that are text elements when they
// could be part of the chart").

const _card = Color(0xFF0E2160);

ChartElement _chart({BoxSpec box = const BoxSpec(padding: 0)}) => ChartElement(
      const ElementBase(id: "c", x: 100, y: 100, width: 600, height: 400),
      type: ChartType.bar,
      title: "Spent (DCR)",
      data: ChartData.parse("Year\tSpent\n2021\t1\n2022\t5\n2023\t9"),
      box: box,
    );

Future<Color> _pixel(WidgetTester tester, CanvasDocument doc, Offset at) async {
  var rec = ui.PictureRecorder();
  paintCanvasDocument(ui.Canvas(rec), doc, frame: 0);
  var picture = rec.endRecording();
  var image = await tester.runAsync(
      () => picture.toImage(doc.size.width.round(), doc.size.height.round()));
  var bytes = await tester
      .runAsync(() => image!.toByteData(format: ui.ImageByteFormat.rawRgba));
  var i = (at.dy.round() * image!.width + at.dx.round()) * 4;
  var c = Color.fromARGB(bytes!.getUint8(i + 3), bytes.getUint8(i),
      bytes.getUint8(i + 1), bytes.getUint8(i + 2));
  image.dispose();
  picture.dispose();
  return c;
}

void main() {
  test("a chart as made has no card, and writes none down", () {
    var e = _chart();
    expect(chartBoxIsPlain(e.box), isTrue);
    expect(e.toJson().containsKey("box"), isFalse);
    expect(chartInner(e, e.bounds), e.bounds);
  });

  test("a card is kept", () {
    var e = _chart(
        box: const BoxSpec(
            fill: _card, borderRadius: 18, padding: 24, padT: 18));
    var back =
        CanvasDocument.fromJson(const CanvasDocument().addElement(e).toJson())
            .elementById("c") as ChartElement;
    expect(back.box.toJson(), e.box.toJson());
  });

  test("its title and key are placed inside the padding", () {
    var plain = _chart().copyWith(floatingLabels: true);
    var carded = plain.copyWith(box: const BoxSpec(padding: 30));
    var a = chartLabelPlaces(plain, plain.bounds)[ChartLabelPart.title]!;
    var b = chartLabelPlaces(carded, carded.bounds)[ChartLabelPart.title]!;
    expect(b.left, greaterThan(a.left), reason: "moved in by the padding");
    expect(b.top, greaterThan(a.top));
    expect(carded.bounds.deflate(30).contains(b.topLeft), isTrue);
  });

  testWidgets("the card is drawn to the element's edges", (tester) async {
    var e =
        _chart(box: const BoxSpec(fill: _card, borderRadius: 0, padding: 24));
    var doc = const CanvasDocument().addElement(e);
    // Just inside the corner: the card, not the page.
    expect(await _pixel(tester, doc, const Offset(102, 102)), _card);
    var bare = const CanvasDocument().addElement(_chart());
    expect(await _pixel(tester, bare, const Offset(102, 102)), isNot(_card));
  });

  test("a box's border can sit inside its edge, and is kept and scaled", () {
    // The History's quote plaques: a frame with a rule ten in from it.
    const box =
        BoxSpec(fill: _card, borderWidth: 2, borderRadius: 10, borderInset: 10);
    var back = BoxSpec.fromJson(box.toJson());
    expect(back.borderInset, 10);
    expect(back, box);
    expect(box.scaledBy(2).borderInset, 20);
    expect(box.withEvenPad(4).borderInset, 10,
        reason: "replacing the padding keeps it");
    expect(const BoxSpec().toJson().containsKey("bi"), isFalse);
  });
}
