import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/table_painter.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_table_turns_redact_test.dart is batch 3's table additions from the
// privacy video's report (Ken, 2026-11-12): a table arriving a row or a
// column at a time, and a cell rule that blacks its words out.

const _box = Rect.fromLTWH(0, 0, 200, 200);

/// _drawn is [paint] on a 200 x 200 picture, as bytes.
Future<ByteData> _drawn(void Function(Canvas) paint) async {
  var recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  var image = await recorder.endRecording().toImage(200, 200);
  return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
}

int _alphaAt(ByteData bytes, double x, double y) =>
    bytes.getUint8((y.round() * 200 + x.round()) * 4 + 3);

void main() {
  group("rows and columns in turn", () {
    test("a cascade: the first starts at once, the last ends at the end", () {
      expect(TableTurn.revealOf(0, 0, 4), 0);
      expect(TableTurn.revealOf(0.3, 0, 4), closeTo(0.75, 1e-9));
      expect(TableTurn.revealOf(0.3, 1, 4), closeTo(0.25, 1e-9));
      expect(TableTurn.revealOf(0.3, 3, 4), 0);
      expect(TableTurn.revealOf(1, 3, 4), 1);
      // One piece is the whole arrival.
      expect(TableTurn.revealOf(0.4, 0, 1), closeTo(0.4, 1e-9));
    });

    test("kept, and nothing written when together", () {
      var e = const TableElement(ElementBase(id: "t"), turn: TableTurn.columns);
      var back = TableElement.fromJson(e.props(), e.base);
      expect(back.turn, TableTurn.columns);
      expect(
          const TableElement(ElementBase(id: "t")).props().containsKey("turn"),
          isFalse);
    });

    for (var turn in [TableTurn.rows, TableTurn.columns]) {
      test("${turn.label}: the first in, the last not yet", () async {
        var e = TableElement(
          const ElementBase(id: "t", width: 200, height: 200),
          rows: const [
            ["A", "B", "C", "D"],
            ["1", "2", "3", "4"],
            ["5", "6", "7", "8"],
            ["9", "10", "11", "12"],
          ],
          cellFill: const Color(0xFFFFFFFF),
          zebra: false,
          grid: TableGrid.none,
          cornerRadius: 0,
          animation:
              const ElementAnimation(preset: ElementAnimationPreset.fadeIn),
          turn: turn,
        );
        var bytes = await _drawn((c) => paintTableInTurn(
            c,
            _box,
            e,
            const Keyframe(frame: 0, values: {KeyframeChannel.reveal: 0.3}),
            null));
        // Four rows or columns, 50 across: the first, the last.
        Offset at(int piece) => turn == TableTurn.rows
            ? Offset(100, piece * 50 + 25)
            : Offset(piece * 50 + 25, 100);
        expect(_alphaAt(bytes, at(0).dx, at(0).dy), greaterThan(0),
            reason: "the first is three quarters in");
        expect(_alphaAt(bytes, at(3).dx, at(3).dy), 0,
            reason: "the last has not started");
      });
    }
  });

  group("redact", () {
    test("kept; a word rule cannot black out a cell", () {
      const style = TableCellStyle(redact: true);
      expect(TableCellStyle.fromJson(style.toJson()).redact, isTrue);
      expect(const TableCellStyle().toJson().containsKey("redact"), isFalse);

      var rows = const [
        ["Name"],
        ["Satoshi"],
      ];
      var whole = TableElement(const ElementBase(id: "t"),
          rows: rows, rules: const [TableRule(rows: "2", style: style)]);
      expect(whole.styleFor(1, 0)?.redact, isTrue);
      var word = TableElement(const ElementBase(id: "t"), rows: rows, rules: [
        const TableRule(match: "Satoshi", how: TableMatch.word, style: style),
      ]);
      expect(word.styleFor(1, 0)?.redact, isFalse);
    });

    test("drawn as a solid bar the words' own width", () async {
      TableElement table(bool redact) => TableElement(
            const ElementBase(id: "t", width: 200, height: 200),
            rows: const [
              ["A B"],
            ],
            headerRow: false,
            zebra: false,
            grid: TableGrid.none,
            cellPadding: 10,
            cellSpec: const TextSpec(
                fontSize: 24,
                color: Color(0xFFFFFFFF),
                align: TextAlignSpec.left),
            rules: [
              TableRule(style: TableCellStyle(redact: redact)),
            ],
          );
      // The test font draws every letter as a solid box, a space as
      // nothing: the space between A and B is where a bar shows.
      var words = await _drawn((c) => paintTable(c, _box, table(false)));
      var bars = await _drawn((c) => paintTable(c, _box, table(true)));
      // The line the words are on, and along it: the end of A, the start
      // of B, the end of B.
      var y = [
        for (var y = 0; y < 200; y++)
          if (_alphaAt(words, 30, y.toDouble()) == 255) y
      ];
      expect(y, isNotEmpty);
      var line = (y.first + y.last) / 2;
      var inked = [
        for (var x = 0; x < 200; x++)
          if (_alphaAt(words, x.toDouble(), line) == 255) x
      ];
      var gapAt = [
        for (var x = inked.first; x < inked.last; x++)
          if (!inked.contains(x)) x
      ];
      expect(gapAt, isNotEmpty, reason: "a space between the two words");
      var gap = (gapAt.first + gapAt.last) / 2;
      expect(_alphaAt(bars, gap, line), 255, reason: "the bar runs over it");
      // As long as the words, not the cell.
      expect(_alphaAt(bars, inked.last + 6.0, line), 0);
    });
  });
}
