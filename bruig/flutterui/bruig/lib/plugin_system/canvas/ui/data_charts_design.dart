import 'dart:async';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// data_charts_design.dart is the Data Studio's Charts tab (Ken, 2026-11-15:
// "design the data in to visual data / chart data ... very visual and
// flexible so users can design a wide range of data visuals and even
// multiple data displays from the same data set"; prototypes v5 and v6).
//
// On the left, the sheet's columns and the charts of it. Along the top, the
// slots: what labels the marks (and whether rows with the same label are
// brought together), the values, a column to colour by, a column of dates
// to play through, and the kind of chart. In the middle the chart, drawn
// as the canvas draws it: click its title, its key, its plot, the labels
// along a side, a series, or one mark, and the panel on the right is about
// that. The chart's own panel has which rows it shows and its highlights.
//
// The marks are found by the painter itself (ChartPart, chart_common.dart),
// so what is clicked is what was drawn. Every change goes through the
// controller as one step to undo.

/// ChartsDesign is the Charts tab for the charts of one sheet.
class ChartsDesign extends StatefulWidget {
  final CanvasController controller;
  final String sheetId;
  final ChartElement chart;
  final ValueChanged<String> onPickChart;
  const ChartsDesign(
      {required this.controller,
      required this.sheetId,
      required this.chart,
      required this.onPickChart,
      super.key});

  @override
  State<ChartsDesign> createState() => ChartsDesignState();
}

/// ChartPick is what is picked in the Charts tab: the chart, a part of it,
/// a series, one mark, or a highlight.
class ChartPick {
  final String kind;
  final int series, index;
  const ChartPick(this.kind, {this.series = -1, this.index = -1});
  static const chart = ChartPick("chart");

  @override
  bool operator ==(Object other) =>
      other is ChartPick &&
      other.kind == kind &&
      other.series == series &&
      other.index == index;

  @override
  int get hashCode => Object.hash(kind, series, index);
}

const _palette = [
  0x4C8DF6, 0x2FE08A, 0x0C8310, 0xF2B33D, 0xF7DE8E, 0xE8645A, 0xC82B0E, //
  0x9B7CF4, 0x3FC1D9, 0xFFFFFF, 0xC9D6EA, 0x8D97A6, 0x1D2127, 0x073E8C,
];
const _hoverInk = Color(0xFF9B7CF4);
const _groups = [
  ("", "each row"),
  ("total", "total"),
  ("average", "average"),
  ("count", "count"),
  ("most", "most"),
  ("least", "least"),
];
const _commonTypes = [
  ChartType.bar,
  ChartType.horizontalBar,
  ChartType.groupedBar,
  ChartType.line,
  ChartType.area,
  ChartType.scatter,
  ChartType.lollipop,
  ChartType.pie,
  ChartType.donut,
];

class ChartsDesignState extends State<ChartsDesign> {
  CanvasController get c => widget.controller;
  ChartElement get e => widget.chart;
  ChartPick _picked = ChartPick.chart;
  ChartPick? _hover;
  int? _hoverHighlight;
  int? _offering;
  Timer? _ending;
  final FocusNode _focus = FocusNode();

  /// parts and where they were drawn, for clicks: what the painter noted
  /// last, and the stage's scale and offset to map a click into it.
  List<ChartPart> parts = const [];
  double _k = 1;
  Offset _o = Offset.zero;

  DataSheet? get _sheet => c.sheetById(widget.sheetId);
  SheetLink get _link => e.sheet!;

  @override
  void didUpdateWidget(ChartsDesign oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chart.id != e.id) {
      _picked = ChartPick.chart;
      _hover = null;
    }
    if (_picked.kind == "highlight" && _picked.index >= e.highlights.length) {
      _picked = ChartPick.chart;
    }
    if (_picked.series >= e.data.series.length) _picked = ChartPick.chart;
  }

  @override
  void dispose() {
    _end();
    _focus.dispose();
    super.dispose();
  }

  // ---- Writing.

  void _set(ChartElement next) {
    _end();
    c.beginInteraction();
    c.replaceElement(next, transient: true);
    c.endInteraction();
  }

  void _live(ChartElement next) {
    c.beginInteraction();
    c.replaceElement(next, transient: true);
    _ending?.cancel();
    _ending = Timer(const Duration(milliseconds: 400), _end);
  }

  void _end() {
    _ending?.cancel();
    _ending = null;
    c.endInteraction();
  }

  void _setLink(SheetLink next) => _set(withLink(e, next) as ChartElement);

  void _pick(ChartPick p) => setState(() {
        _picked = p;
        _offering = null;
      });

  // ---- The sheet's columns, as the chart's range has them.

  String _columnName(int col) {
    var s = _sheet;
    if (s == null) return "Column ${col + 1}";
    var name = sheetShown(s, _link.range.r0, _link.range.c0 + col).trim();
    return name.isEmpty ? columnName(_link.range.c0 + col) : name;
  }

  /// _numbers is whether column [col] of the range holds numbers.
  bool _numbers(int col) {
    var s = _sheet;
    if (s == null) return false;
    var g = _link.range;
    var seen = 0, ok = 0;
    for (var r = g.r0 + 1; r <= g.r1; r++) {
      var v = sheetValue(s, r, g.c0 + col);
      if (v == null || v == "") continue;
      seen++;
      if (v is double) ok++;
    }
    return seen > 0 && ok * 2 > seen;
  }

  List<int> get _columns => [for (var i = 0; i < _link.range.cols; i++) i];

  /// _dates is the values of column [col] in the sheet's order, each once:
  /// what Play through steps along.
  List<String> _dates(int col) {
    var s = _sheet;
    if (s == null) return const [];
    var g = _link.range, out = <String>[];
    for (var r = g.r0 + 1; r <= g.r1; r++) {
      var v = sheetShown(s, r, g.c0 + col);
      if (!out.contains(v)) out.add(v);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (node, ev) {
        if (ev is KeyDownEvent && ev.logicalKey == LogicalKeyboardKey.escape) {
          _pick(_picked.kind == "mark"
              ? ChartPick("series", series: _picked.series)
              : ChartPick.chart);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: 210, child: _left(context)),
        VerticalDivider(width: 1, thickness: 1, color: colors.outlineVariant),
        Expanded(
          child: Column(children: [
            _shelf(context),
            if (_offering != null) _offer(context, _offering!),
            Divider(height: 1, thickness: 1, color: colors.outlineVariant),
            Expanded(child: _stage(context)),
          ]),
        ),
        VerticalDivider(width: 1, thickness: 1, color: colors.outlineVariant),
        SizedBox(width: 380, child: _panel(context)),
      ]),
    );
  }

  // ---- Left: columns and charts.

  Widget _left(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var charts = viewsOf(c.document, widget.sheetId).whereType<ChartElement>();
    return Container(
      color: colors.surfaceContainerLow,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const StudioLabel("Columns"),
          Text("Click one to put it in a slot.",
              style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant)),
          const SizedBox(height: 6),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (var col in _columns) _chip(context, col),
          ]),
          const StudioLabel("Charts of this sheet"),
          for (var ch in charts)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Material(
                color: colors.surfaceContainerHigh,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                        color: ch.id == e.id
                            ? colors.primary
                            : const Color(0x00000000))),
                child: InkWell(
                  key: ValueKey("chartsPick-${ch.id}"),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => widget.onPickChart(ch.id),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(ch.name.isEmpty ? "Chart" : ch.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: colors.onSurface)),
                          Text(ch.type.label,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: colors.onSurfaceVariant)),
                        ]),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: StudioPill(
                key: const ValueKey("chartsNew"),
                label: "+ New chart",
                filled: true,
                onTap: () {
                  var s = _sheet;
                  if (s == null) return;
                  var made = c.addDataView(ElementKind.chart, s.id, s.used);
                  widget.onPickChart(startedChart(c, made).id);
                }),
          ),
        ]),
      ),
    );
  }

  Widget _chip(BuildContext context, int col) {
    final colors = ThemeNotifier.of(context).colors;
    var numbers = _numbers(col);
    return Material(
      color: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
          side: BorderSide(
              color:
                  _offering == col ? colors.primary : colors.outlineVariant)),
      child: InkWell(
        key: ValueKey("chartsColumn-$col"),
        borderRadius: BorderRadius.circular(7),
        onTap: () => setState(() => _offering = _offering == col ? null : col),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(numbers ? "123" : "abc",
                style: TextStyle(
                    fontSize: 9,
                    color: numbers
                        ? const Color(0xFF6FA4F8)
                        : const Color(0xFFF2B33D))),
            const SizedBox(width: 5),
            Text(_columnName(col),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface)),
          ]),
        ),
      ),
    );
  }

  /// _offer is the slots a column clicked on the left can go in.
  Widget _offer(BuildContext context, int col) {
    final colors = ThemeNotifier.of(context).colors;
    var l = _link;
    var numbers = _numbers(col);
    return Container(
      key: const ValueKey("chartsOffer"),
      width: double.infinity,
      color: colors.surfaceContainerLowest,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text("Put ${_columnName(col)} in:",
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
            if (!numbers)
              StudioPill(
                  key: const ValueKey("chartsPutLabels"),
                  label: "Labels",
                  onTap: () {
                    _setLink(l.copyWith(
                        labels: col, through: l.through == col ? -1 : null));
                    setState(() => _offering = null);
                  }),
            if (numbers && !l.series.contains(col))
              StudioPill(
                  key: const ValueKey("chartsPutValues"),
                  label: "Values",
                  onTap: () {
                    _setLink(l.copyWith(series: [...l.series, col]));
                    setState(() => _offering = null);
                  }),
            StudioPill(
                key: const ValueKey("chartsPutColour"),
                label: "Colour by",
                onTap: () {
                  _setLink(l.copyWith(colourBy: col));
                  setState(() => _offering = null);
                }),
            if (!numbers && col != l.labels)
              StudioPill(
                  key: const ValueKey("chartsPutThrough"),
                  label: "Play through",
                  onTap: () {
                    _setLink(l.copyWith(through: col, at: ""));
                    setState(() => _offering = null);
                  }),
            StudioPill(
                label: "Cancel", onTap: () => setState(() => _offering = null)),
          ]),
    );
  }

  // ---- The slots.

  Widget _shelf(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var l = _link;
    Widget slot(String name, List<Widget> children) => Container(
          padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
          decoration: BoxDecoration(
              border: Border.all(color: colors.outlineVariant),
              borderRadius: BorderRadius.circular(9)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(name.toUpperCase(),
                style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurfaceVariant)),
            const SizedBox(width: 6),
            ...children,
          ]),
        );
    var numberColumns = [
      for (var col in _columns)
        if (_numbers(col)) col
    ];
    var wordColumns = [
      for (var col in _columns)
        if (!_numbers(col)) col
    ];
    var dates = l.through >= 0 ? _dates(l.through) : const <String>[];
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            slot("Labels", [
              _Menu<int>(
                  key: const ValueKey("chartsLabels"),
                  width: 140,
                  value: l.labels,
                  options: [for (var col in _columns) (col, _columnName(col))],
                  onChanged: (v) => _setLink(l.copyWith(labels: v))),
              _Menu<String>(
                  key: const ValueKey("chartsGroup"),
                  width: 104,
                  value: l.group,
                  options: _groups,
                  onChanged: (v) => _setLink(l.copyWith(group: v))),
            ]),
            slot("Values", [
              for (var col in l.series)
                _SlotChip(
                    key: ValueKey("chartsValue-$col"),
                    label: _columnName(col),
                    onRemove: l.series.length < 2
                        ? null
                        : () => _setLink(
                            l.copyWith(series: [...l.series]..remove(col)))),
              _Menu<int>(
                  key: const ValueKey("chartsAddValue"),
                  width: 64,
                  value: -1,
                  options: [
                    (-1, "+"),
                    for (var col in numberColumns)
                      if (!l.series.contains(col)) (col, _columnName(col)),
                  ],
                  onChanged: (v) {
                    if (v >= 0) _setLink(l.copyWith(series: [...l.series, v]));
                  }),
            ]),
            slot("Colour by", [
              _Menu<int>(
                  key: const ValueKey("chartsColourBy"),
                  width: 130,
                  value: l.colourBy,
                  options: [
                    (-1, "Nothing"),
                    for (var col in _columns) (col, _columnName(col)),
                  ],
                  onChanged: (v) => _setLink(l.copyWith(colourBy: v))),
            ]),
            slot("Play through", [
              _Menu<int>(
                  key: const ValueKey("chartsThrough"),
                  width: 130,
                  value: l.through,
                  options: [
                    (-1, "Nothing"),
                    for (var col in wordColumns)
                      if (col != l.labels) (col, _columnName(col)),
                  ],
                  onChanged: (v) => _setLink(l.copyWith(through: v, at: ""))),
              if (dates.isNotEmpty)
                _Menu<String>(
                    key: const ValueKey("chartsAt"),
                    width: 110,
                    value: dates.contains(l.at) ? l.at : "",
                    options: [
                      ("", "the last"),
                      for (var d in dates) (d, d),
                    ],
                    onChanged: (v) => _setLink(l.copyWith(at: v))),
            ]),
            slot("Kind", [
              _Menu<ChartType>(
                  key: const ValueKey("chartsType"),
                  width: 150,
                  value: e.type,
                  options: [
                    for (var t in _commonTypes) (t, t.label),
                    for (var t in ChartType.values)
                      if (!_commonTypes.contains(t)) (t, t.label),
                  ],
                  onChanged: (v) => _set(e.copyWith(type: v))),
            ]),
          ]),
    );
  }

  // ---- The stage.

  Widget _stage(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    return LayoutBuilder(builder: (context, box) {
      var w = math.max(1.0, e.width), h = math.max(1.0, e.height);
      var k = math
          .min((box.maxWidth - 40) / w, (box.maxHeight - 40) / h)
          .clamp(0.1, 2.5)
          .toDouble();
      var o = Offset((box.maxWidth - w * k) / 2, (box.maxHeight - h * k) / 2);
      _k = k;
      _o = o;
      ChartPick? pickAt(Offset p) {
        var at = (p - o) / k;
        ChartPart? best;
        for (var part in parts) {
          if (!part.contains(at)) continue;
          // A mark over the plot it sits in; writing over everything.
          if (best == null || _rank(part.kind) > _rank(best.kind)) best = part;
        }
        if (best == null) return null;
        if (best.kind == ChartPartKind.mark) {
          return ChartPick("mark", series: best.series, index: best.index);
        }
        return ChartPick(best.kind.name);
      }

      return Container(
        color: colors.surfaceContainerLowest,
        child: MouseRegion(
          onHover: (ev) {
            var p = pickAt(ev.localPosition);
            if (p?.kind == "mark" &&
                _picked.kind != "series" &&
                _picked.kind != "mark") {
              p = ChartPick("series", series: p!.series);
            }
            if (p != _hover) setState(() => _hover = p);
          },
          onExit: (_) => setState(() => _hover = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              _focus.requestFocus();
              var p = pickAt(d.localPosition);
              if (p == null) return _pick(ChartPick.chart);
              if (p.kind == "mark") {
                // A mark: first its series, then that mark alone.
                var again =
                    (_picked.kind == "series" && _picked.series == p.series) ||
                        _picked.kind == "mark";
                return _pick(again ? p : ChartPick("series", series: p.series));
              }
              _pick(p);
            },
            child: CustomPaint(
              key: const ValueKey("chartsStage"),
              size: Size(box.maxWidth, box.maxHeight),
              painter: _ChartStage(
                e: e,
                k: k,
                o: o,
                ground: c.document.background.spec.background,
                picked: _picked,
                hover: _hover,
                accent: colors.primary,
                onParts: (p) => parts = p,
              ),
            ),
          ),
        ),
      );
    });
  }

  static int _rank(ChartPartKind k) => switch (k) {
        ChartPartKind.title || ChartPartKind.description => 5,
        ChartPartKind.legend => 4,
        ChartPartKind.mark => 3,
        ChartPartKind.xLabels || ChartPartKind.yLabels => 2,
        ChartPartKind.plot => 1,
      };

  /// stageOffsetOf is where a part was drawn, on the stage: for tests.
  Offset stageOffsetOf(ChartPart part) => stageAt(part.rect.center);

  /// stageAt is a point of the chart's own, on the stage.
  Offset stageAt(Offset local) => _o + local * _k;

  // ---- The panel.

  Widget _panel(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var p = _picked;
    var data = e.data;
    String seriesName(int s) =>
        s >= 0 && s < data.series.length ? data.series[s].name : "Series";
    var (title, says) = switch (p.kind) {
      "chart" => (
          e.name.isEmpty ? "Chart" : e.name,
          "${e.type.label} of ${[
            for (var s in data.series) s.name
          ].join(", ")}. Click any part of it."
        ),
      "title" => ("Title", "Its words and size."),
      "description" => ("Description", "The words under the title."),
      "legend" => ("Key", "Which colour is which."),
      "plot" => ("Plot", "Its grid, its axes, its values."),
      "xLabels" => ("Labels along", "The writing along the bottom."),
      "yLabels" => ("Numbers up", "The writing up the side."),
      "series" => (
          seriesName(p.series),
          "Every mark of it. Click one again for that one alone."
        ),
      "mark" => (
          p.index < data.categories.length ? data.categories[p.index] : "Mark",
          "${seriesName(p.series)}: ${data.hasValueAt(p.series, p.index) ? _num(data.valueAt(p.series, p.index)) : "–"}"
        ),
      "highlight" => (
          _highlightName(e.highlights[p.index]),
          "A highlight: lit up on the chart."
        ),
      _ => ("Chart", ""),
    };
    return Container(
      color: colors.surfaceContainerLow,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                key: const ValueKey("chartsTitle"),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface)),
            const SizedBox(height: 2),
            Text(says,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
          ]),
        ),
        Divider(height: 1, thickness: 1, color: colors.outlineVariant),
        Expanded(
          child: SingleChildScrollView(
            key: ValueKey("chartsPanel-${p.kind}"),
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: switch (p.kind) {
                  "chart" => _chartPanel(context),
                  "title" => _titlePanel(context),
                  "legend" => [
                      StudioPills<bool>(
                          id: "chartsLegend",
                          label: "Shown",
                          value: e.showLegend,
                          options: const [(true, "Shown"), (false, "Hidden")],
                          onChanged: (v) => _set(e.copyWith(showLegend: v))),
                    ],
                  "plot" => _plotPanel(context),
                  "xLabels" => _axisPanel(context, x: true),
                  "yLabels" => _axisPanel(context, x: false),
                  "series" => _seriesPanel(context, p.series),
                  "mark" => _markPanel(context, p.series, p.index),
                  "highlight" => _highlightPanel(context, p.index),
                  _ => const [],
                }),
          ),
        ),
      ]),
    );
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? "${v.round()}" : v.toStringAsFixed(2);

  Widget _hint(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                color: ThemeNotifier.of(context).colors.onSurfaceVariant)),
      );

  Widget _swatches(
          String id, String label, Color value, ValueChanged<Color> set) =>
      StudioSwatches(
          id: id,
          label: label,
          palette: [
            if (!_palette.contains(value.toARGB32() & 0xFFFFFF))
              value.toARGB32() & 0xFFFFFF,
            ..._palette
          ],
          value: value.toARGB32() & 0xFFFFFF,
          onPick: (v) {
            if (v != null) set(Color(0xFF000000 | v));
          });

  Widget _slider(String label, double value, double min, double max,
          double rest, void Function(double) live) =>
      StudioSlider(
        key: ValueKey("chartsSlider-$label"),
        label: label,
        value: value,
        min: min,
        max: max,
        rest: rest,
        format: (v) => v.toStringAsFixed(v.abs() < 10 ? 1 : 0),
        onChanged: live,
        onChangeEnd: (_) => _end(),
      );

  Widget _buttons(List<Widget> pills) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Wrap(spacing: 6, runSpacing: 6, children: pills),
      );

  List<Widget> _chartPanel(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var l = _link;
    var rows = l.places.trim().isNotEmpty
        ? "places"
        : l.top > 0
            ? (l.bottom ? "bottom" : "top")
            : "all";
    var numberColumns = [
      for (var col in _columns)
        if (_numbers(col)) col
    ];
    return [
      StudioPills<String>(
          id: "chartsRows",
          label: "Rows shown",
          value: rows,
          options: const [
            ("all", "Every one"),
            ("top", "Top"),
            ("bottom", "Bottom"),
            ("places", "Places"),
          ],
          onChanged: (v) => _setLink(switch (v) {
                "top" => l.copyWith(
                    top: l.top > 0 ? l.top : 5, bottom: false, places: ""),
                "bottom" => l.copyWith(
                    top: l.top > 0 ? l.top : 5, bottom: true, places: ""),
                "places" => l.copyWith(top: 0, bottom: false, places: "1-3"),
                _ => l.copyWith(top: 0, bottom: false, places: ""),
              })),
      if (rows == "top" || rows == "bottom")
        _slider(
            "How many",
            l.top.toDouble(),
            1,
            30,
            5,
            (v) =>
                _live(withLink(e, l.copyWith(top: v.round())) as ChartElement)),
      if (rows == "places") ...[
        const SizedBox(height: 6),
        _Field(
            key: const ValueKey("chartsPlaces"),
            text: l.places,
            hint: "1-3, 16-19",
            onChanged: (v) =>
                _live(withLink(e, l.copyWith(places: v)) as ChartElement)),
        _hint(context, "Places and ranges, counted after the order."),
        StudioPills<bool>(
            id: "chartsGap",
            label: "Between groups",
            value: l.gap,
            options: const [(true, "A gap (…)"), (false, "Close up")],
            onChanged: (v) => _setLink(l.copyWith(gap: v))),
      ],
      const StudioLabel("In order of"),
      _Menu<int>(
          key: const ValueKey("chartsSort"),
          value: l.sortBy,
          options: [
            (-1, "The sheet's own order"),
            for (var col in numberColumns) (col, _columnName(col)),
          ],
          onChanged: (v) => _setLink(l.copyWith(sortBy: v))),
      if (l.sortBy >= 0)
        StudioPills<bool>(
            id: "chartsDescending",
            label: "",
            value: l.descending,
            options: const [(true, "Largest first"), (false, "Smallest first")],
            onChanged: (v) => _setLink(l.copyWith(descending: v))),
      StudioLabel("Highlights · ${e.highlights.length}"),
      for (var (i, h) in e.highlights.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hoverHighlight = i),
            onExit: (_) => setState(() => _hoverHighlight = null),
            child: Material(
              color: colors.surfaceContainerHigh,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                      color: _hoverHighlight == i
                          ? _hoverInk
                          : const Color(0x00000000))),
              child: InkWell(
                key: ValueKey("chartsHighlight-$i"),
                borderRadius: BorderRadius.circular(8),
                onTap: () => _pick(ChartPick("highlight", index: i)),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(children: [
                    Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                            color: h.colour,
                            borderRadius: BorderRadius.circular(4))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Opacity(
                        opacity: h.off ? 0.5 : 1,
                        child: Text(_highlightName(h),
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurface)),
                      ),
                    ),
                    if (h.fade)
                      Text("the rest faded",
                          style: TextStyle(
                              fontSize: 11, color: colors.onSurfaceVariant)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      _buttons([
        StudioPill(
            key: const ValueKey("chartsAddHighlight"),
            label: "+ Highlight",
            onTap: () {
              _set(e.copyWith(highlights: [
                ...e.highlights,
                const ChartHighlight(reach: ChartReach.top, n: 3, fade: true),
              ]));
              _pick(ChartPick("highlight", index: e.highlights.length));
            }),
      ]),
      _hint(context,
          "A highlight follows the numbers: “top 3” lights whoever is in the top three after a refresh."),
      if (l.charted)
        _hint(context,
            "Read as only a chart can (grouped, by places, one date at a time), its numbers are worked out from the sheet and not written back to it."),
    ];
  }

  String _highlightName(ChartHighlight h) {
    if (h.name.trim().isNotEmpty) return h.name.trim();
    var by = h.by < 0
        ? (e.data.series.isEmpty ? "" : e.data.series.first.name)
        : _columnName(h.by);
    return switch (h.reach) {
      ChartReach.one => "Just ${h.who.isEmpty ? "one" : h.who}",
      ChartReach.top => "Top ${h.n} by $by",
      ChartReach.bottom => "Bottom ${h.n} by $by",
      ChartReach.when => "$by ${switch (h.op) {
          ">=" => "at least",
          "<=" => "at most",
          ">" => "over",
          "<" => "under",
          _ => "exactly",
        }} ${_num(h.value)}",
    };
  }

  List<Widget> _titlePanel(BuildContext context) => [
        const StudioLabel("Words"),
        _Field(
            key: const ValueKey("chartsTitleText"),
            text: e.title,
            hint: "A title",
            onChanged: (v) => _live(e.copyWith(title: v))),
        _slider(
            "Size",
            e.titleSpec.fontSize,
            8,
            72,
            24,
            (v) => _live(
                e.copyWith(titleSpec: e.titleSpec.copyWith(fontSize: v)))),
        _swatches("chartsTitleInk", "Colour", e.titleSpec.color,
            (v) => _set(e.copyWith(titleSpec: e.titleSpec.copyWith(color: v)))),
      ];

  List<Widget> _plotPanel(BuildContext context) => [
        StudioPills<bool>(
            id: "chartsGrid",
            label: "Grid",
            value: e.showGrid,
            options: const [(true, "Shown"), (false, "Hidden")],
            onChanged: (v) => _set(e.copyWith(showGrid: v))),
        StudioPills<bool>(
            id: "chartsAxes",
            label: "Axes",
            value: e.showAxes,
            options: const [(true, "Shown"), (false, "Hidden")],
            onChanged: (v) => _set(e.copyWith(showAxes: v))),
        StudioPills<bool>(
            id: "chartsValues",
            label: "Values on the marks",
            value: e.showValues,
            options: const [(true, "Shown"), (false, "Hidden")],
            onChanged: (v) => _set(e.copyWith(showValues: v))),
        _slider("Corners", e.barRadius, 0, 24, 0,
            (v) => _live(e.copyWith(barRadius: v))),
      ];

  List<Widget> _axisPanel(BuildContext context, {required bool x}) => [
        StudioPills<bool>(
            id: x ? "chartsXShown" : "chartsYShown",
            label: "Shown",
            value: x ? e.showXLabels : e.showYLabels,
            options: const [(true, "Shown"), (false, "Hidden")],
            onChanged: (v) => _set(
                x ? e.copyWith(showXLabels: v) : e.copyWith(showYLabels: v))),
        _slider(
            "Size",
            (x ? e.xLabelSize : e.yLabelSize) ?? e.labelSpec.fontSize,
            6,
            40,
            e.labelSpec.fontSize,
            (v) => _live(
                x ? e.copyWith(xLabelSize: v) : e.copyWith(yLabelSize: v))),
      ];

  List<Widget> _seriesPanel(BuildContext context, int s) {
    if (s < 0 || s >= e.data.series.length) return const [];
    var series = e.data.series[s];
    return [
      _swatches("chartsSeriesColour", "Colour", series.color, (v) {
        var all = [...e.data.series];
        all[s] = series.copyWith(color: v);
        _set(e.copyWith(data: e.data.copyWith(series: all)));
      }),
      _hint(context,
          "A highlight or colour-by colours its own marks over this one."),
    ];
  }

  List<Widget> _markPanel(BuildContext context, int s, int i) {
    var label = i < e.data.categories.length ? e.data.categories[i] : "";
    return [
      _buttons([
        StudioPill(
            key: const ValueKey("chartsHighlightMark"),
            label: "Highlight $label",
            filled: true,
            onTap: () {
              _set(e.copyWith(highlights: [
                ...e.highlights,
                ChartHighlight(who: label, fade: true, named: true),
              ]));
              _pick(ChartPick("highlight", index: e.highlights.length));
            }),
        StudioPill(
            label: "Its series",
            onTap: () => _pick(ChartPick("series", series: s))),
      ]),
    ];
  }

  List<Widget> _highlightPanel(BuildContext context, int i) {
    var h = e.highlights[i];
    void put(ChartHighlight next, {bool live = false}) {
      var all = [...e.highlights];
      all[i] = next;
      live
          ? _live(e.copyWith(highlights: all))
          : _set(e.copyWith(highlights: all));
    }

    var numberColumns = [
      for (var col in _columns)
        if (_numbers(col)) col
    ];
    var labels = [
      for (var l in e.data.categories)
        if (l != "…") l
    ];
    return [
      const StudioLabel("Name"),
      _Field(
          key: ValueKey("chartsHighlightName-$i"),
          text: h.name,
          hint: _highlightName(h.copyWith(name: "")),
          onChanged: (v) => put(h.copyWith(name: v), live: true)),
      StudioPills<ChartReach>(
          id: "chartsReach",
          label: "Picks out",
          value: h.reach,
          options: [for (var r in ChartReach.values) (r, r.label)],
          onChanged: (v) => put(h.copyWith(
              reach: v,
              who: v == ChartReach.one && h.who.isEmpty && labels.isNotEmpty
                  ? labels.first
                  : null))),
      if (h.reach == ChartReach.one) ...[
        const SizedBox(height: 6),
        _Menu<String>(
            key: const ValueKey("chartsWho"),
            value: labels.contains(h.who) ? h.who : (labels.firstOrNull ?? ""),
            options: [for (var l in labels) (l, l)],
            onChanged: (v) => put(h.copyWith(who: v))),
      ],
      if (h.reach == ChartReach.top || h.reach == ChartReach.bottom)
        _slider("How many", h.n.toDouble(), 1, 20, 3,
            (v) => put(h.copyWith(n: v.round()), live: true)),
      if (h.reach != ChartReach.one) ...[
        const StudioLabel("By"),
        _Menu<int>(
            key: const ValueKey("chartsBy"),
            value: h.by,
            options: [
              (-1, "Its first series"),
              for (var col in numberColumns) (col, _columnName(col)),
            ],
            onChanged: (v) => put(h.copyWith(by: v))),
      ],
      if (h.reach == ChartReach.when) ...[
        StudioPills<String>(
            id: "chartsOp",
            label: "Is",
            value: h.op,
            options: const [
              (">=", "at least"),
              ("<=", "at most"),
              (">", "over"),
              ("<", "under"),
              ("=", "exactly"),
            ],
            onChanged: (v) => put(h.copyWith(op: v))),
        const SizedBox(height: 6),
        _Field(
            key: ValueKey("chartsValue-$i"),
            text: _num(h.value),
            hint: "A number",
            onChanged: (v) {
              var n = double.tryParse(v.trim());
              if (n != null) put(h.copyWith(value: n), live: true);
            }),
      ],
      _swatches("chartsHighlightColour", "Colour", h.colour,
          (v) => put(h.copyWith(colour: v))),
      StudioPills<bool>(
          id: "chartsFade",
          label: "The rest",
          value: h.fade,
          options: const [(false, "As they are"), (true, "Faded")],
          onChanged: (v) => put(h.copyWith(fade: v))),
      _buttons([
        StudioPill(
            key: const ValueKey("chartsHighlightOff"),
            label: h.off ? "Switch on" : "Switch off",
            onTap: () => put(h.copyWith(off: !h.off))),
        StudioPill(
            key: const ValueKey("chartsHighlightDelete"),
            label: "Delete",
            onTap: () {
              _set(e.copyWith(highlights: [...e.highlights]..removeAt(i)));
              _pick(ChartPick.chart);
            }),
      ]),
      _hint(context,
          "Made like a table style: what it picks out, then its look. Later highlights win where two pick out the same mark."),
    ];
  }
}

/// _ChartStage draws the chart as the canvas does, fitted to the stage, and
/// outlines what is hovered and picked; it hands back where the painter
/// put each part.
class _ChartStage extends CustomPainter {
  final ChartElement e;
  final double k;
  final Offset o;
  final Color ground, accent;
  final ChartPick picked;
  final ChartPick? hover;
  final ValueChanged<List<ChartPart>> onParts;
  _ChartStage({
    required this.e,
    required this.k,
    required this.o,
    required this.ground,
    required this.accent,
    required this.picked,
    required this.hover,
    required this.onParts,
  });

  @override
  void paint(Canvas canvas, Size size) {
    var rect = Rect.fromLTWH(0, 0, e.width, e.height);
    canvas.save();
    canvas.translate(o.dx, o.dy);
    canvas.scale(k);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(10), const Radius.circular(8)),
        Paint()..color = ground);
    var parts = <ChartPart>[];
    chartParts = parts;
    try {
      paintChart(canvas, rect, e);
    } finally {
      chartParts = null;
    }
    onParts(parts);

    List<ChartPart> partsOf(ChartPick p) => switch (p.kind) {
          "series" => [
              for (var q in parts)
                if (q.kind == ChartPartKind.mark && q.series == p.series) q
            ],
          "mark" => [
              for (var q in parts)
                if (q.kind == ChartPartKind.mark &&
                    q.series == p.series &&
                    q.index == p.index)
                  q
            ],
          "chart" || "highlight" => const [],
          _ => [
              for (var q in parts)
                if (q.kind.name == p.kind) q
            ],
        };
    void outline(List<ChartPart> ps, Color colour, double width) {
      var paint = Paint()
        ..color = colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = width / k;
      for (var q in ps.take(200)) {
        if (q.path != null) {
          canvas.drawPath(q.path!, paint);
        } else {
          canvas.drawRect(q.rect, paint);
        }
      }
    }

    var hv = hover;
    if (hv != null && hv != picked) outline(partsOf(hv), _hoverInk, 1.5);
    outline(partsOf(picked), accent, 2);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ChartStage old) =>
      !identical(old.e, e) ||
      old.k != k ||
      old.o != o ||
      old.picked != picked ||
      old.hover != hover ||
      old.ground != ground ||
      old.accent != accent;
}

/// _Menu is a dropdown of (value, name) choices.
class _Menu<T> extends StatelessWidget {
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  /// width is what it fills, so a long choice is cut short rather than
  /// pushing past its slot; null fills its parent.
  final double? width;
  const _Menu(
      {required this.value,
      required this.options,
      required this.onChanged,
      this.width,
      super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var has = options.any((o) => o.$1 == value);
    return Container(
      height: 28,
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(6)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: has ? value : null,
          isDense: true,
          isExpanded: true,
          style: TextStyle(fontSize: 12, color: colors.onSurface),
          dropdownColor: colors.surfaceContainerHigh,
          items: [
            for (var (v, name) in options)
              DropdownMenuItem(
                  value: v, child: Text(name, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v as T);
          },
        ),
      ),
    );
  }
}

/// _SlotChip is a column in a slot, with a cross to take it out.
class _SlotChip extends StatelessWidget {
  final String label;
  final VoidCallback? onRemove;
  const _SlotChip({required this.label, this.onRemove, super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.fromLTRB(8, 3, 4, 3),
      decoration: BoxDecoration(
          color: const Color(0x334C8DF6),
          borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.onSurface)),
        if (onRemove != null)
          InkWell(
            key: ValueKey("chartsRemove-$label"),
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child:
                  Icon(Icons.close, size: 13, color: colors.onSurfaceVariant),
            ),
          ),
      ]),
    );
  }
}

/// _Field is a one-line field that keeps what is typed while the panel
/// rebuilds under it.
class _Field extends StatefulWidget {
  final String text, hint;
  final ValueChanged<String> onChanged;
  const _Field(
      {required this.text,
      required this.hint,
      required this.onChanged,
      super.key});

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late final TextEditingController _c =
      TextEditingController(text: widget.text);
  final FocusNode _f = FocusNode();

  @override
  void didUpdateWidget(_Field old) {
    super.didUpdateWidget(old);
    if (!_f.hasFocus && _c.text != widget.text) _c.text = widget.text;
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    return TextField(
      controller: _c,
      focusNode: _f,
      onChanged: widget.onChanged,
      style: TextStyle(fontSize: 13, color: colors.onSurface),
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hint,
        hintStyle: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
        filled: true,
        fillColor: colors.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: BorderSide.none),
      ),
    );
  }
}

/// startedChart is a chart just made of a sheet, set to read it as a person
/// would start: labelled by the column that names its rows (the longest
/// distinct words, a team's name), showing its last column of numbers.
CanvasElement startedChart(CanvasController c, CanvasElement made) {
  var link = linkOf(made);
  var sheet = link == null ? null : c.sheetById(link.sheet);
  if (link == null || sheet == null) return made;
  var g = link.range;
  int? names, last;
  var longest = 0.0;
  for (var col = 0; col < g.cols; col++) {
    var values = [
      for (var r = g.r0 + 1; r <= g.r1; r++) sheetValue(sheet, r, g.c0 + col)
    ];
    var filled = values.where((v) => v != null && v != "").toList();
    if (filled.isEmpty) continue;
    if (filled.every((v) => v is double)) {
      last = col;
      continue;
    }
    var words = [for (var v in filled) "$v"];
    if (words.toSet().length != words.length) continue;
    var length = words.fold(0, (a, w) => a + w.length) / words.length;
    if (length > longest) {
      longest = length;
      names = col;
    }
  }
  if (names == null || last == null) return made;
  var next = withLink(made, link.copyWith(labels: names, series: [last]));
  c.replaceElement(next);
  return next;
}
