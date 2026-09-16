import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/table_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_table_padding_test.dart is the room round the words in a table's
// cells.
//
// It was the words' margin left and right and nothing at all above or below
// them: at any setting the writing sat hard against the rule over it, which is
// not what a control called Padding says it does. Every side is its own
// figure now, for the tables that want a heading with room to breathe over it
// and cells without.
//
// Measured off the drawing wherever the question is where the words sit,
// because that is a thing about pixels.

const Rect _rect = Rect.fromLTWH(0, 0, 400, 300);

TableElement _table({
  double all = 10,
  double? top,
  double? bottom,
  VerticalAlignSpec down = VerticalAlignSpec.top,
}) =>
    TableElement(
      const ElementBase(id: "t", width: 400, height: 300),
      rows: const [
        ["Team", "Pts"],
        ["Hull City", "6"],
        ["Leeds United", "4"],
      ],
      cellPadding: all,
      padTop: top,
      padBottom: bottom,
      showOutline: false,
      grid: TableGrid.none,
      zebra: false,
      headerFill: const Color(0xFF000000),
      headerSpec: TextSpec(
          fontSize: 20, color: const Color(0xFFFFFFFF), verticalAlign: down),
      cellSpec: TextSpec(
          fontSize: 20, color: const Color(0xFFFFFFFF), verticalAlign: down),
    );

/// _inkTop is the first row of the picture with any writing on it.
Future<int> _inkTop(TableElement e) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(_rect, Paint()..color = const Color(0xFF000000));
  paintTable(canvas, _rect, e);
  var image = await recorder.endRecording().toImage(400, 300);
  var bytes = (await image.toByteData())!;
  image.dispose();
  for (var y = 0; y < 300; y++) {
    for (var x = 0; x < 400; x++) {
      var p = bytes.getUint32((y * 400 + x) * 4);
      if (((p >> 24) & 0xFF) > 150) return y;
    }
  }
  return -1;
}

void main() {
  group("the padding", () {
    testWidgets("holds the words off the rule above them", (tester) async {
      // Words set to the top of their cells, where the padding above them is
      // the only thing between the writing and the rule. It was nothing at
      // all, at any setting.
      late int tight, roomy;
      await tester.runAsync(() async {
        tight = await _inkTop(_table(all: 2));
        roomy = await _inkTop(_table(all: 30));
      });
      expect(tight, greaterThanOrEqualTo(0),
          reason: "there is writing to find");
      expect(roomy, closeTo(tight + 28, 2),
          reason: "as much more as was asked");
    });

    testWidgets("and a side can be asked for on its own", (tester) async {
      late int even, below;
      await tester.runAsync(() async {
        even = await _inkTop(_table(all: 4));
        below = await _inkTop(_table(all: 4, top: 40));
      });
      expect(below, closeTo(even + 36, 2));
    });

    testWidgets("even where the words are centred in the cell", (tester) async {
      // Centred, even padding moves nothing: the middle of a box inset by the
      // same amount above and below is the same middle. A side on its own
      // still moves them, by half of what it adds.
      late int even, below;
      await tester.runAsync(() async {
        even = await _inkTop(_table(all: 4, down: VerticalAlignSpec.middle));
        below = await _inkTop(
            _table(all: 4, top: 40, down: VerticalAlignSpec.middle));
      });
      expect(below, closeTo(even + 18, 2));
    });

    test("a side that is not set takes the single figure", () {
      const e = TableElement(ElementBase(id: "t"), cellPadding: 7);
      expect(e.topPad, 7);
      expect(e.rightPad, 7);
      expect(e.bottomPad, 7);
      expect(e.leftPad, 7);
      expect(e.evenPadding, isTrue, reason: "one field, not four");
    });

    test("and goes on taking it when that figure changes", () {
      // The point of holding a side as nothing rather than as a copy: a table
      // set up with even padding stays even.
      const e = TableElement(ElementBase(id: "t"), cellPadding: 7);
      expect(e.copyWith(cellPadding: 20).topPad, 20);
    });

    test("until it is given one of its own, and forgotten when it is not", () {
      const e = TableElement(ElementBase(id: "t"), cellPadding: 7);
      var sided = e.copyWith(padTop: 30);
      expect(sided.topPad, 30);
      expect(sided.leftPad, 7);
      expect(sided.evenPadding, isFalse);
      expect(sided.copyWith(evenPadding: true).topPad, 7,
          reason: "switched off, the four are dropped rather than kept unseen");
    });

    test("and a saved file carries the sides only where they were asked for",
        () {
      const even = TableElement(ElementBase(id: "t"), cellPadding: 7);
      expect(even.props().containsKey("padTop"), isFalse);

      var sided = even.copyWith(padTop: 30, padLeft: 4);
      var back = TableElement.fromJson(sided.props(), ElementBase(id: "t"));
      expect(back.topPad, 30);
      expect(back.leftPad, 4);
      expect(back.rightPad, 7, reason: "the two nobody set still follow");
      expect(back.padRight, isNull);
    });
  });

  group("the columns", () {
    test("start sized by what is in them", () {
      const e = TableElement(ElementBase(id: "t"));
      expect(e.evenColumns, isTrue,
          reason: "an empty list of widths is the table sizing itself");
    });

    test("and a width dragged on the table is what stops that", () {
      const e = TableElement(ElementBase(id: "t"));
      expect(e.copyWith(columnWidths: const [0.7, 0.3]).evenColumns, isFalse);
    });

    test("and clearing the widths is the way back", () {
      // There was none. The moment one edge moved, every column's width was
      // written down, and a table set up by dragging could not be put back to
      // the widths it had worked out for itself.
      var dragged = const TableElement(ElementBase(id: "t"))
          .copyWith(columnWidths: const [0.7, 0.3]);
      expect(dragged.copyWith(columnWidths: const []).evenColumns, isTrue);
    });
  });
}
