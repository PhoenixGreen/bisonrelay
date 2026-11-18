import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/play_task_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/synth_module_element.dart';
import 'package:bruig/plugin_system/canvas/model/synth_patch.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:flutter/painting.dart';

// element_samples.dart is one of every kind in the Add menu, for tests that
// should hold of every element: read back as written, survive a hostile
// file, draw, open a panel. A kind with sorts of its own (each synth module,
// each chart type) is here once for each sort.

/// elementSamples are (name, element) pairs: every ElementKind as it is
/// first added, then the sorts.
List<(String, CanvasElement)> elementSamples() {
  var doc = const CanvasDocument(frames: 96, frameRate: 24);
  var base = <(String, CanvasElement)>[
    for (var kind in ElementKind.values) (kind.label, newElement(kind, doc)),
  ];
  var chart = newElement(ElementKind.chart, doc) as ChartElement;
  var synth = newElement(ElementKind.synth, doc) as SynthModuleElement;
  return [
    ...base,
    for (var t in ChartType.values)
      if (t != chart.type) ("Chart: ${t.label}", chart.copyWith(type: t)),
    for (var m in SynthModuleKind.values)
      if (m != synth.module)
        ("Synth module: ${m.label}", SynthModuleElement(synth.base, module: m)),
  ];
}

/// filledSamples are elements as they are after use rather than as first
/// added: a panel that lists one row per player, column, series or file
/// overruns at twelve long-named ones, not at the three it starts with.
List<(String, CanvasElement)> filledSamples() {
  var doc = const CanvasDocument(frames: 96, frameRate: 24);
  const long = "Wolverhampton Wanderers Reserves";
  var team = newElement(ElementKind.player, doc) as TeamElement;
  var players = [
    for (var (i, p) in team.players.indexed)
      p.copyWith(
        number: "${i + 10}",
        name: "$long $i",
        captain: i == 0,
        highlight: i.isEven,
        locked: i % 3 == 0,
        hidden: i % 4 == 1,
        photo: i == 2 ? "photo-asset" : null,
      ),
  ];
  var table = newElement(ElementKind.table, doc) as TableElement;
  var chart = newElement(ElementKind.chart, doc) as ChartElement;
  var code = newElement(ElementKind.code, doc) as CodeElement;
  var text = newElement(ElementKind.text, doc) as TextElement;
  var task = newElement(ElementKind.playTask, doc) as PlayTaskElement;
  return [
    ("Team, filled", team.copyWith(players: players)),
    (
      "Table, filled",
      table.copyWith(rows: [
        [for (var c = 0; c < 9; c++) "$long column $c"],
        for (var r = 0; r < 14; r++)
          [for (var c = 0; c < 9; c++) "${r * c} $long"],
      ])
    ),
    (
      "Chart, filled",
      chart.copyWith(
          data: ChartData(
        categories: [for (var i = 0; i < 16; i++) "$long $i"],
        series: [
          for (var s = 0; s < 10; s++)
            ChartSeries(
                name: "$long series $s",
                color: Color(0xFF000000 + s * 0x151515),
                values: [for (var i = 0; i < 16; i++) (i * s % 7).toDouble()]),
        ],
      ))
    ),
    (
      "Code, filled",
      code.copyWith(files: [
        for (var i = 0; i < 8; i++)
          CodeFile(
              id: "f$i",
              name: "a_very_long_file_name_for_testing_$i.dart",
              text: "void main() {}\n" * 40),
      ])
    ),
    ("Text, filled", text.copyWith(text: "$long " * 60)),
    (
      "Play task, filled",
      task.copyWith(text: "$long " * 4, checks: [
        for (var (i, k) in PlayCheckKind.values.indexed)
          PlayCheck(k, "$long step $i " * 3,
              steps: "C2 C3+E3+G3 F#4 Bb5", count: 3, percent: 90),
      ])
    ),
  ];
}
