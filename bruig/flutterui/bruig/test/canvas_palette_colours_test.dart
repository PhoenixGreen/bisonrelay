import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_palette.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_palette_colours_test.dart is a table that arrives in the colours
// the canvas is already in: the accent its shapes stand out in, the ink its
// words are written in.

const _gold = Color(0xFFE8B630);
const _ink = Color(0xFFF5F0E6);
const _ground = Color(0xFF0B1220);

List<CanvasElement> _dressed() => [
      for (var i = 0; i < 3; i++)
        ShapeElement(ElementBase(id: "s$i", width: 10, height: 10),
            fill: _gold, strokeColor: _gold),
      for (var i = 0; i < 4; i++)
        TextElement(ElementBase(id: "t$i", width: 10, height: 10),
            textSpec: const TextSpec(color: _ink)),
    ];

void main() {
  test("the accent is the bright colour used most, the ink the readable one",
      () {
    var c = canvasColours(_ground, _dressed());
    expect(c.accent, _gold);
    expect(c.ink, _ink);
  });

  test("a bare canvas still gives words that can be read", () {
    expect(canvasColours(_ground, const []).ink.computeLuminance(),
        greaterThan(0.5));
    expect(
        canvasColours(const Color(0xFFFFFFFF), const []).ink.computeLuminance(),
        lessThan(0.1));
  });

  test("a new table arrives in the canvas's colours", () {
    var document = const CanvasDocument();
    for (var e in _dressed()) {
      document = document.addElement(e);
    }
    var table = newElement(ElementKind.table, document) as TableElement;
    expect(table.headerFill, _gold);
    expect(table.cellSpec.color, _ink);
    expect(table.headerSpec.color.computeLuminance(), lessThan(0.1),
        reason: "dark words on a gold band");
    expect(table.gridColor.withValues(alpha: 1), _ink);
  });
}
