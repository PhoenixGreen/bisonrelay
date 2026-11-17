import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_morph.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/canvas_audio_fake.dart';

// canvas_chart_morph_test.dart is a chart arriving out of the one before
// it (Ken, 2026-11-17, the improvements report's eighth item).

void main() {
  test("bars in one scene become a pie in the next", () async {
    var sheet = const DataSheet(id: "s", cells: [
      ["Source", "£m"],
      ["Broadcast", "260"],
      ["Commercial", "190"],
      ["Matchday", "110"],
    ]);
    var c = CanvasController(
        CanvasDocument(sheets: [sheet], frames: 72, frameRate: 24),
        audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    var link = SheetLink("s", sheet.used, labels: 0, series: const [1]);
    var data = ChartData.parse(
        "Source\t£m\nBroadcast\t260\nCommercial\t190\nMatchday\t110");
    c.addElement(ChartElement(
        const ElementBase(id: "bars", x: 80, y: 80, width: 900, height: 500),
        type: ChartType.bar,
        sheet: link,
        data: data));
    c.addScene();
    c.addElement(ChartElement(
        const ElementBase(id: "pie", x: 300, y: 100, width: 600, height: 520),
        type: ChartType.pie,
        sheet: link,
        data: data));
    c.applyChartAnimation(c.document.elementById("pie") as ChartElement,
        ChartAnimationPreset.morph);
    var doc = c.document;
    var pie = doc.elementById("pie") as ChartElement;
    expect(morphFrom(pie, doc)?.id, "bars");
    Future<List<int>> frame(int f) async {
      var img =
          await renderFrame(doc, frame: doc.startOfScene(1) + f, scale: 0.2);
      return (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
    }

    var early = await frame(6), late = await frame(60);
    expect(early, isNot(late), reason: "on its way, then the pie");
    // In the first scene there is nothing before it: it fades in.
    c.goToScene(0);
    expect(
        morphFrom(c.document.elementById("bars") as ChartElement, c.document),
        isNull);
  });
}
