import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/play_task_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/text_document.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
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
    ("Text, every part used", fullText(text)),
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

/// fullText is [text] with every part of a text in use: pieces of words and
/// a picture, parts with marks and an arrival, its own marks, columns, wrap,
/// a document, an arrival of its own and a line to ride. Nonsense together
/// (a line wins over the box), but a received file may hold all of it.
TextElement fullText(TextElement text) => text.copyWith(
      text: "Spend or burn the ledger's own words",
      // No outline, shadow or glow: those are read as looks (text_looks.dart).
      textSpec: const TextSpec(letterSpacing: 2, lineHeight: 1.4),
      box: const BoxSpec(
          fill: Color(0x33000000),
          borderWidth: 2,
          borderRadius: 8,
          padding: 12,
          padL: 20),
      items: const [
        TextItem(
            id: "kicker",
            text: "LEDGER",
            name: "Kicker",
            gap: 12,
            side: 4,
            box: BoxSpec(fill: Color(0xFF223344), borderRadius: 4)),
        TextItem(
            id: "badge",
            slot: TextSlot.bottomRight,
            icon: TextIcon(
                assetId: "badge-asset",
                size: 48,
                underline: PartUnderline(width: 2))),
      ],
      parts: const [
        TextPart(
            from: 1,
            to: 2,
            weight: 800,
            scale: 1.5,
            family: "Oswald",
            outlineWidth: 1,
            highlight: PartHighlight(radius: 3),
            underline: PartUnderline(away: 4),
            animation: TextPartAnimation(
                arrival: TextAnimation(preset: TextAnimationPreset.highlight),
                offset: 6)),
      ],
      highlight: const PartHighlight(padLeft: 6),
      underline: const PartUnderline(width: 2),
      columns: const TextColumns(
          count: 2, gap: 30, ruleStyle: ColumnRuleStyle.solid),
      wrap: const TextWrap(on: true, gap: 16),
      document: const TextDocumentRef(folder: "notes", name: "ledger.md"),
      documentParts: const [TextPart(from: 3, to: 3, italic: true)],
      animation: const TextAnimation(
          preset: TextAnimationPreset.words,
          draw: TextDrawSpec(padLeft: 4, radius: 2)),
      style: "Heading",
      flowTo: "next-box",
      curve: const TextOnCurve(elementId: "a-line", spacing: 2, offset: 0.2),
    );
