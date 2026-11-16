import 'dart:async';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/chart_play.dart';
import 'package:bruig/plugin_system/canvas/model/chart_presets.dart';
import 'package:bruig/plugin_system/canvas/model/chart_words.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_styles.dart';
import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_numbers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/render/image_store.dart';
import 'package:bruig/plugin_system/canvas/render/table_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/data_style_picker.dart';
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

  /// startInGallery opens on the gallery, its design taking the place of
  /// [chart] rather than adding another: the sheet's first chart, chosen
  /// from the designs rather than made plain and then made again (found
  /// making the Charts canvas, 2026-11-17).
  final bool startInGallery;
  const ChartsDesign(
      {required this.controller,
      required this.sheetId,
      required this.chart,
      required this.onPickChart,
      this.startInGallery = false,
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

class ChartsDesignState extends State<ChartsDesign>
    with TickerProviderStateMixin {
  /// _preview plays the chart through its dates or steps on the stage, as
  /// the canvas will once it has arrived (chart_play.dart).
  late final AnimationController _preview = AnimationController(vsync: this)
    ..addListener(() => setState(() {}));

  CanvasController get c => widget.controller;
  ChartElement get e => widget.chart;
  ChartPick _picked = ChartPick.chart;
  ChartPick? _hover;
  int? _hoverHighlight;
  int? _offering;
  Timer? _ending;

  /// _gallery is the columns ticked for a new chart, while choosing one
  /// from the suggestions; null otherwise.
  List<int>? _gallery;

  /// _replacing is whether the gallery's design takes the place of this
  /// chart (ChartsDesign.startInGallery) rather than adding one.
  bool _replacing = false;

  // The gallery (Ken, 2026-11-17; prototype v7): the kind opened, the
  // starting design picked, and what the cards are filtered by.
  ChartType? _galleryKind;
  int? _galleryPreset;
  ChartQuestion? _galleryQuestion;
  ChartUse? _galleryUse;
  String _galleryQuery = "";
  String _galleryStyle = "";
  Set<ChartModifier> _galleryMods = {};
  late final AnimationController _galleryPlay = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600), value: 1)
    ..addListener(() => setState(() {}));

  /// _boardOn shows every view of the sheet together (prototype v5's board).
  bool _boardOn = false;
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
    if (_picked.kind == "note" && _picked.index >= e.notes.length) {
      _picked = ChartPick.chart;
    }
    if (_picked.series >= e.data.series.length) _picked = ChartPick.chart;
  }

  @override
  void dispose() {
    c.keysHeld.removeListener(_glideTick);
    _end();
    _preview.dispose();
    _galleryPlay.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ---- Motion: a preview, and steps.

  /// _playable is whether the chart can move: it plays through a column of
  /// dates, or has steps.
  bool get _playable => e.sheet!.through >= 0 || e.steps.length > 1;

  /// _shown is the chart as the stage draws it: playing, while previewing.
  ChartElement _shown() {
    var s = _sheet;
    if (!_preview.isAnimating || s == null) {
      // Numbers just changed ease to their new values, as on the canvas.
      return chartGlides.containsKey(e.id)
          ? e.copyWith(data: glided(e.id, e.data))
          : e;
    }
    // The preview plays steps at a pace, whatever moves them on the canvas.
    var playing = (e.play > 0 ? e : e.copyWith(play: 1.0))
        .copyWith(follow: ChartStepsFollow.time.name);
    return chartPlaying(playing, s, _preview.value * playLength(playing, s));
  }

  /// _gliding is whether the stage was drawing a glide at the last tick, so
  /// the tick after it ends draws the numbers themselves.
  bool _gliding = false;

  void _glideTick() {
    var now = chartGlides.containsKey(e.id);
    if ((now || _gliding) && mounted) setState(() {});
    _gliding = now;
  }

  @override
  void initState() {
    super.initState();
    c.keysHeld.addListener(_glideTick);
    if (widget.startInGallery) {
      _gallery = _startingPicks();
      _galleryStyle = e.style;
      _replacing = true;
    }
  }

  void _play() {
    var s = _sheet;
    if (s == null) return;
    var each = e.play > 0 ? e.play : 1.0;
    var length = playLength(e.play > 0 ? e : e.copyWith(play: each), s);
    if (length <= 0) return;
    _preview.duration = Duration(milliseconds: (length * 1000).round());
    _preview.forward(from: 0);
  }

  /// _stepsSaved is the chart's steps with the one being worked on saved
  /// from its own fields.
  List<ChartStep> _stepsSaved() => [
        for (var k = 0; k < e.steps.length; k++) stepOf(e, k),
      ];

  /// _loadStep is [next] (steps saved) showing step [k] in its own fields.
  ChartElement _loadStep(ChartElement next, int k) {
    var st = next.steps[k];
    return next.copyWith(
        stepAt: k,
        title: st.title,
        highlights: st.highlights,
        notes: st.notes,
        sheet: next.sheet!.copyWith(at: st.at));
  }

  void _toStep(int k) {
    if (k == e.stepAt || k < 0 || k >= e.steps.length) return;
    _set(_loadStep(e.copyWith(steps: _stepsSaved()), k));
    _pick(ChartPick.chart);
  }

  /// _addStep is a copy of the step being worked on, after it, to change.
  void _addStep() {
    var here = ChartStep(
        title: e.title,
        highlights: e.highlights,
        notes: e.notes,
        at: e.sheet!.at);
    if (e.steps.isEmpty) {
      _set(e.copyWith(steps: [
        here.copyWith(name: "Step 1"),
        here.copyWith(name: "Step 2"),
      ], stepAt: 1));
    } else {
      var steps = _stepsSaved()
        ..insert(
            e.stepAt + 1, here.copyWith(name: "Step ${e.steps.length + 1}"));
      _set(e.copyWith(steps: steps, stepAt: e.stepAt + 1));
    }
    _pick(ChartPick.chart);
  }

  void _deleteStep() {
    if (e.steps.length < 2) return;
    var steps = _stepsSaved()..removeAt(e.stepAt);
    if (steps.length == 1) {
      // One step left is no steps: the chart is that step.
      var only = e.copyWith(steps: steps, stepAt: 0);
      _set(_loadStep(only, 0).copyWith(steps: const [], stepAt: 0));
    } else {
      _set(_loadStep(
          e.copyWith(steps: steps), (e.stepAt - 1).clamp(0, steps.length - 1)));
    }
    _pick(ChartPick.chart);
  }

  Widget _stepStrip(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
      child: Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text("STEPS",
                style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurfaceVariant)),
            if (e.steps.isEmpty)
              const StudioPill(label: "1 Whole chart", selected: true)
            else
              for (var (k, st) in e.steps.indexed)
                StudioPill(
                    key: ValueKey("chartsStep-$k"),
                    label: "${k + 1} ${st.name.isEmpty ? "Step" : st.name}",
                    selected: k == e.stepAt,
                    onTap: () => _toStep(k)),
            StudioPill(
                key: const ValueKey("chartsAddStep"),
                label: "+",
                tooltip: "A step: a copy of this one to change",
                onTap: _addStep),
            if (e.steps.length > 1)
              StudioPill(
                  key: const ValueKey("chartsDeleteStep"),
                  label: "Delete step",
                  onTap: _deleteStep),
            if (_playable)
              StudioPill(
                  key: const ValueKey("chartsPreview"),
                  label: _preview.isAnimating ? "Playing…" : "▶ Preview",
                  filled: true,
                  onTap: _preview.isAnimating ? null : _play),
            if (e.steps.isEmpty)
              Text(
                  "Add a step to tell it in parts: each has its own title, highlights, notes and date.",
                  style: TextStyle(
                      fontSize: 11.5, color: colors.onSurfaceVariant)),
          ]),
    );
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
            if (_gallery == null) _shelf(context),
            if (_offering != null && _gallery == null)
              _offer(context, _offering!),
            if (_gallery == null) ..._checkRows(context),
            if (_gallery == null && !_boardOn) _stepStrip(context),
            Divider(height: 1, thickness: 1, color: colors.outlineVariant),
            Expanded(
                child: _gallery != null
                    ? _galleryView(context)
                    : _boardOn
                        ? _board(context)
                        : _stage(context)),
          ]),
        ),
        VerticalDivider(width: 1, thickness: 1, color: colors.outlineVariant),
        SizedBox(
            width: 380,
            child: _gallery != null ? _galleryPanel(context) : _panel(context)),
      ]),
    );
  }

  // ---- Checks: what makes a chart hard to read, each with a fix.

  /// _checks is what might make the chart hard to read, each with the fixes
  /// that would help (prototype v5-v6's checks).
  List<(String, List<(String, VoidCallback)>)> _checks() {
    var s = _sheet;
    if (s == null) return const [];
    var l = _link,
        data = e.data,
        out = <(String, List<(String, VoidCallback)>)>[];
    var n = data.categories.length;
    if ((e.type == ChartType.pie || e.type == ChartType.donut) && n > 8) {
      out.add((
        "$n slices are hard to read.",
        [
          (
            "Ranked bars",
            () => _setLinkAndType(
                l.copyWith(sortBy: l.series.firstOrNull ?? -1),
                ChartType.horizontalBar)
          ),
          (
            "The biggest eight",
            () =>
                _setLink(l.copyWith(sortBy: l.series.firstOrNull ?? -1, top: 8))
          ),
        ]
      ));
    }
    // Labels said more than once and nothing bringing them together: only
    // the last of each is drawn.
    if (l.group.isEmpty && l.through < 0 && !(l.colourBy >= 0 && n > 0)) {
      var g = l.range, seen = <String>{}, twice = false;
      for (var r = g.r0 + 1; r <= g.r1; r++) {
        if (!seen.add(sheetShown(s, r, g.c0 + l.labels))) twice = true;
      }
      if (twice) {
        var kinds = columnKinds(s, g);
        var date = kinds.indexOf(ColumnKind.dates);
        out.add((
          "Each ${_columnName(l.labels)} has several rows; only the last is shown.",
          [
            if (date >= 0 && date != l.labels)
              (
                "Play through ${_columnName(date)}",
                () => _setLink(l.copyWith(through: date))
              ),
            ("Total for each", () => _setLink(l.copyWith(group: "total"))),
          ]
        ));
      }
    }
    if ((e.type == ChartType.line || e.type == ChartType.area) &&
        data.series.length > 8 &&
        !e.highlights.any((h) => !h.off) &&
        s.spotlight.isEmpty) {
      out.add((
        "${data.series.length} lines are hard to follow.",
        [
          (
            "Light up the top 3",
            () => _set(e.copyWith(highlights: [
                  ...e.highlights,
                  const ChartHighlight(
                      reach: ChartReach.top,
                      n: 3,
                      colour: Color(0xFF2FE08A),
                      named: true),
                ]))
          ),
        ]
      ));
    }
    var base = data.series.isEmpty ? null : data.series.first.color;
    for (var (i, h) in e.highlights.indexed) {
      if (h.off || base == null || h.colour != base) continue;
      out.add((
        "“${_highlightName(h)}” is the same colour as the rest.",
        [
          (
            "Make it gold",
            () {
              var all = [...e.highlights];
              all[i] = h.copyWith(colour: const Color(0xFFF2B33D));
              _set(e.copyWith(highlights: all));
            }
          ),
        ]
      ));
    }
    return out;
  }

  void _setLinkAndType(SheetLink link, ChartType type) =>
      _set(withLink(e.copyWith(type: type), link) as ChartElement);

  List<Widget> _checkRows(BuildContext context) {
    var checks = _checks();
    if (checks.isEmpty) return const [];
    return [
      Container(
        key: const ValueKey("chartsChecks"),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Column(children: [
          for (var (i, (say, fixes)) in checks.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Expanded(
                  child: Text(say,
                      style: const TextStyle(
                          fontSize: 12.5, color: Color(0xFFF2B33D))),
                ),
                for (var (j, (label, fix)) in fixes.indexed)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: StudioPill(
                        key: ValueKey("chartsFix-$i-$j"),
                        label: label,
                        onTap: fix),
                  ),
              ]),
            ),
        ]),
      ),
    ];
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
          if (_sheet case var sheet? when sheet.spotlight.isNotEmpty) ...[
            const StudioLabel("Picked out everywhere"),
            Row(children: [
              Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                      color: sheet.spotlightColour,
                      borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 6),
              Expanded(
                child: Text(sheet.spotlight,
                    key: const ValueKey("chartsSpotlightName"),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: colors.onSurface)),
              ),
              StudioPill(
                  key: const ValueKey("chartsSpotlightOff"),
                  label: "Stop",
                  onTap: () => c.setSheet(sheet.copyWith(spotlight: ""))),
            ]),
            Text("In every chart of this sheet, and its tables.",
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
          ],
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: StudioPill(
                key: const ValueKey("chartsNew"),
                label: "+ New chart",
                filled: true,
                onTap: () => setState(() {
                      _gallery = _startingPicks();
                      _offering = null;
                      _boardOn = false;
                      _galleryKind = null;
                      _galleryPreset = null;
                      _galleryMods = {};
                      _galleryStyle = e.style;
                    })),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: StudioPill(
                key: const ValueKey("chartsBoard"),
                label: "Board",
                selected: _boardOn,
                tooltip: "Every view of this sheet together",
                onTap: () => setState(() {
                      _boardOn = !_boardOn;
                      _gallery = null;
                    })),
          ),
        ]),
      ),
    );
  }

  // ---- The board: every view of the sheet together.

  /// _views is the tables and charts of this sheet on the page being made.
  List<CanvasElement> get _onPage => [
        for (var v in c.document.elements)
          if (linkOf(v)?.sheet == widget.sheetId) v
      ];

  Widget _board(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var views = viewsOf(c.document, widget.sheetId);
    return GridView.extent(
      key: const ValueKey("chartsBoardGrid"),
      padding: const EdgeInsets.all(14),
      maxCrossAxisExtent: 340,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.1,
      children: [
        for (var v in views)
          Material(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: ValueKey("chartsBoardView-${v.id}"),
              onTap: v is ChartElement
                  ? () {
                      setState(() => _boardOn = false);
                      widget.onPickChart(v.id);
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: CustomPaint(
                            size: Size.infinite,
                            painter: _ViewThumb(v, c.images,
                                c.document.background.spec.background),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                          "${v is ChartElement ? "Chart" : "Table"} · "
                          "${v.name.isEmpty ? v.kind.label : v.name}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: colors.onSurface)),
                    ]),
              ),
            ),
          ),
        Material(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              StudioPill(
                  key: const ValueKey("chartsLayOut"),
                  label: "Lay them out together",
                  filled: true,
                  onTap: _layOut),
              _hint(context,
                  "The ones on this page, side by side in rows from where the first is, as one step to undo."),
            ]),
          ),
        ),
      ],
    );
  }

  /// _layOut puts this sheet's views on the page side by side, two to a
  /// row, from where the top-left one is.
  void _layOut() {
    var views = _onPage;
    if (views.isEmpty) return;
    var x0 = views.map((v) => v.base.x).reduce(math.min);
    var y0 = views.map((v) => v.base.y).reduce(math.min);
    const gap = 40.0;
    _end();
    c.beginInteraction();
    var y = y0;
    for (var i = 0; i < views.length; i += 2) {
      var row = views.skip(i).take(2).toList();
      var x = x0;
      for (var v in row) {
        c.replaceElement(v.rebase(v.base.copyWith(x: x, y: y)));
        x += v.base.width + gap;
      }
      y += row.map((v) => v.base.height).reduce(math.max) + gap;
    }
    c.endInteraction();
  }

  // What each column holds, as the gallery reads it: worked out again only
  // when the sheet or the range changes.
  DataSheet? _kindsOf;
  CellRange? _kindsRange;
  List<ColumnKind> _kindsCache = const [];
  ColumnKind _kindOf(int col) {
    var s = _sheet;
    if (s == null) return ColumnKind.empty;
    if (!identical(_kindsOf, s) || _kindsRange != _link.range) {
      _kindsOf = s;
      _kindsRange = _link.range;
      _kindsCache = columnKinds(s, _link.range);
    }
    return col < _kindsCache.length ? _kindsCache[col] : ColumnKind.empty;
  }

  Widget _chip(BuildContext context, int col) {
    final colors = ThemeNotifier.of(context).colors;
    var numbers = _numbers(col);
    // A column of weeks or years says so, as the gallery reads it as when
    // (found making the Charts canvas: "123 Week").
    var when = _kindOf(col) == ColumnKind.dates;
    return Material(
      color: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
          side: BorderSide(
              color: _offering == col || (_gallery?.contains(col) ?? false)
                  ? colors.primary
                  : colors.outlineVariant,
              width: _gallery?.contains(col) ?? false ? 2 : 1)),
      child: InkWell(
        key: ValueKey("chartsColumn-$col"),
        borderRadius: BorderRadius.circular(7),
        onTap: () => setState(() {
          var g = _gallery;
          if (g != null) {
            _gallery = g.contains(col) ? ([...g]..remove(col)) : [...g, col];
          } else {
            _offering = _offering == col ? null : col;
          }
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(
                when
                    ? "date"
                    : numbers
                        ? "123"
                        : "abc",
                style: TextStyle(
                    fontSize: 9,
                    color: when
                        ? const Color(0xFF5FD3A8)
                        : numbers
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
            if (!numbers && col != l.labels)
              StudioPill(
                  key: const ValueKey("chartsPutSplit"),
                  label: "Small charts by",
                  onTap: () {
                    _setLink(l.copyWith(split: col));
                    setState(() => _offering = null);
                  }),
            StudioPill(
                label: "Cancel", onTap: () => setState(() => _offering = null)),
          ]),
    );
  }

  // ---- Suggestions: a new chart chosen by how it looks with your numbers.

  /// _startingPicks are the columns ticked when the gallery opens: the one
  /// naming the rows (or a date) and the last of numbers.
  List<int> _startingPicks() {
    var s = _sheet;
    if (s == null) return const [];
    var g = _link.range;
    var kinds = columnKinds(s, g);
    var date = kinds.indexOf(ColumnKind.dates);
    // The names column that names the rows best (a team's name, not its
    // code or its form: namingScore).
    var name = -1;
    var most = 0.0;
    for (var (col, k) in kinds.indexed) {
      if (k != ColumnKind.names) continue;
      var score = namingScore(s, g, col);
      if (score > most) {
        most = score;
        name = col;
      }
    }
    var number = kinds.lastIndexOf(ColumnKind.numbers);
    return [
      if (date >= 0) date,
      if (name >= 0) name,
      if (number >= 0) number,
    ];
  }

  // ---- The gallery: every kind of chart, built from the ticked columns.

  /// _picks is the ticked columns, sorted by what they hold.
  Picks? get _picks {
    var s = _sheet, g = _gallery;
    if (s == null || g == null) return null;
    var range = _link.range;
    var kinds = columnKinds(s, range);
    List<int> of(ColumnKind k) => [
          for (var c = 0; c < kinds.length; c++)
            if (kinds[c] == k) c
        ];
    return picksOf(s, range, g, of(ColumnKind.numbers), of(ColumnKind.dates),
        of(ColumnKind.names));
  }

  DataStyle? get _gStyle => dataStyleNamed(_galleryStyle);

  /// _galleryChart is [kind]'s [preset] made from the ticked columns, in
  /// the gallery's style; null when it can't be.
  ChartElement? _galleryChart(ChartKind kind, ChartPreset preset,
      {Set<ChartModifier> mods = const {}}) {
    var p = _picks;
    if (p == null) return null;
    var made = presetChart(kind, preset, p, e.copyWith(title: ""), mods: mods);
    if (made == null) return null;
    var st = _gStyle;
    return st == null ? made : reread(chartInStyle(made, st), p.sheet);
  }

  Color get _galleryGround =>
      _gStyle?.ground ?? c.document.background.spec.background;

  static const _synonyms = {
    "spider": [ChartType.radar],
    "race": [ChartType.horizontalBar],
    "coxcomb": [ChartType.radialBar],
    "kpi": [ChartType.gauge, ChartType.bullet],
    "money": [ChartType.sankey],
    "share": [
      ChartType.pie,
      ChartType.donut,
      ChartType.waffle,
      ChartType.shareBar
    ],
  };

  bool _kindShown(ChartKind k) {
    if (_galleryQuestion != null && !k.questions.contains(_galleryQuestion)) {
      return false;
    }
    if (_galleryUse != null &&
        !k.presets.any((pr) => pr.uses.contains(_galleryUse))) {
      return false;
    }
    var q = _galleryQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    var text = "${k.name} ${k.use} ${k.presets.map((pr) => pr.name).join(" ")}"
        .toLowerCase();
    if (text.contains(q)) return true;
    return _synonyms.entries
        .any((en) => en.key.startsWith(q) && en.value.contains(k.type));
  }

  Widget _galleryView(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var p = _picks;
    if (p == null || p.numbers.isEmpty) {
      return Center(
          child: Text("Tick at least one column of numbers on the left.",
              style: TextStyle(color: colors.onSurfaceVariant)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
        child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 190,
                child: _Field(
                    key: const ValueKey("chartsGallerySearch"),
                    text: _galleryQuery,
                    hint: "Search: race, spider, share…",
                    onChanged: (v) => setState(() {
                          _galleryQuery = v;
                          _galleryKind = null;
                          _galleryPreset = null;
                        })),
              ),
              for (var (u, name) in [
                (null, "All"),
                for (var x in ChartUse.values) (x, x.label),
              ])
                StudioPill(
                    key: ValueKey("chartsGalleryUse-${u?.name ?? "all"}"),
                    label: name,
                    selected: _galleryUse == u,
                    onTap: () => setState(() => _galleryUse = u)),
              SizedBox(
                width: 170,
                child: _Menu<String>(
                    key: const ValueKey("chartsGalleryStyle"),
                    value: _galleryStyle,
                    options: [
                      ("", "Style: as it is"),
                      for (var st in dataStyles) (st.name, "Style: ${st.name}"),
                    ],
                    onChanged: (v) => setState(() => _galleryStyle = v)),
              ),
            ]),
      ),
      if (_galleryKind == null)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
          child: Wrap(spacing: 4, runSpacing: 4, children: [
            for (var (q, name) in [
              (null, "All charts"),
              for (var x in ChartQuestion.values) (x, x.label),
            ])
              StudioPill(
                  key: ValueKey("chartsGalleryAsk-${q?.name ?? "all"}"),
                  label: name,
                  selected: _galleryQuestion == q,
                  onTap: () => setState(() => _galleryQuestion = q)),
          ]),
        ),
      Expanded(
          child: _galleryKind == null
              ? _kindGrid(context, p)
              : _presetGrid(context, p)),
    ]);
  }

  Widget _kindGrid(BuildContext context, Picks p) {
    final colors = ThemeNotifier.of(context).colors;
    var s = _sheet!;
    var ideas = chartIdeas(s, _link.range, _gallery!);
    var best = ideas.isEmpty ? null : ideas.first.type;
    var shown = chartKinds.where(_kindShown).toList();
    var fit = [
      for (var k in shown)
        if (k.reads(p) != null) k
    ];
    var unfit = [
      for (var k in shown)
        if (k.reads(p) == null) k
    ];
    // The best fit for the ticked columns first, as the suggestions had it;
    // then by how well each suits them (kindFit), a poor one saying why.
    var suits = {for (var k in fit) k.type: kindFit(k, p)};
    var order = {for (var (i, k) in fit.indexed) k.type: i};
    fit.sort((a, b) {
      var first = (a.type == best ? 0 : 1).compareTo(b.type == best ? 0 : 1);
      if (first != 0) return first;
      var bySuit = suits[b.type]!.score.compareTo(suits[a.type]!.score);
      return bySuit != 0 ? bySuit : order[a.type]!.compareTo(order[b.type]!);
    });
    Widget card(ChartKind k, bool fits) {
      var preset = k.presets.firstWhere(
          (pr) => _galleryUse == null || pr.uses.contains(_galleryUse),
          orElse: () => k.presets.first);
      var chart = fits ? _galleryChart(k, preset) : null;
      var suit = suits[k.type] ?? KindFit.good;
      return Opacity(
        opacity: !fits
            ? 0.45
            : suit.poor
                ? 0.7
                : 1,
        child: Material(
          color: colors.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                  color: k.type == best && fits
                      ? colors.primary
                      : colors.outlineVariant)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey("chartsKind-${k.type.name}"),
            onTap: fits
                ? () => setState(() {
                      _galleryKind = k.type;
                      _galleryPreset = null;
                      _galleryMods = {};
                    })
                : null,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: chart == null
                            ? ColoredBox(
                                color: colors.surfaceContainerHighest,
                                child: Center(
                                    child: Text(k.type.label,
                                        style: TextStyle(
                                            color: colors.onSurfaceVariant))))
                            : CustomPaint(
                                size: Size.infinite,
                                painter: _Thumb(chart, _galleryGround)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(
                        child: Text(
                            "${k.name}${k.type == best && fits ? " · best fit" : ""}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurface)),
                      ),
                      if (k.isNew)
                        _badge(context, "New", const Color(0xFFFF7A59)),
                    ]),
                    Text(!fits ? "Needs ${k.needs}" : suit.why ?? k.use,
                        key: ValueKey("chartsKindSays-${k.type.name}"),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        // A warning in amber: the theme's tertiary is a
                        // panel fill, and words in it vanish.
                        style: TextStyle(
                            fontSize: 11.5,
                            color: fits && suit.why == null
                                ? colors.onSurfaceVariant
                                : const Color(0xFFD99A3E))),
                  ]),
            ),
          ),
        ),
      );
    }

    // Every card built (a few dozen thumbnails), so none waits for a scroll.
    return SingleChildScrollView(
        key: const ValueKey("chartsGallery"),
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (shown.isEmpty)
            Text("Nothing matches “$_galleryQuery”.",
                style: TextStyle(color: colors.onSurfaceVariant)),
          _cardGrid([for (var k in fit) card(k, true)]),
          if (unfit.isNotEmpty) ...[
            const StudioLabel("Need other columns"),
            Text("Tick columns like these on the left to use them.",
                style:
                    TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant)),
            const SizedBox(height: 8),
            _cardGrid([for (var k in unfit) card(k, false)]),
          ],
        ]));
  }

  Widget _cardGrid(List<Widget> cards) =>
      LayoutBuilder(builder: (context, box) {
        var n = math.max(1, (box.maxWidth / 250).floor());
        var w = (box.maxWidth - 12 * (n - 1)) / n;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (var c in cards) SizedBox(width: w, height: w * 0.82, child: c),
        ]);
      });

  Widget _badge(BuildContext context, String text, Color colour) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: colour.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(4)),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 9.5,
                letterSpacing: 0.5,
                fontWeight: FontWeight.w800,
                color: colour)),
      );

  static const _useColours = {
    ChartUse.infographic: Color(0xFF7FA8F5),
    ChartUse.video: Color(0xFFE59BF0),
    ChartUse.analysis: Color(0xFF6FD6B0),
  };

  ChartKind get _kind => chartKinds.firstWhere((k) => k.type == _galleryKind);

  Widget _presetGrid(BuildContext context, Picks p) {
    final colors = ThemeNotifier.of(context).colors;
    var kind = _kind;
    Widget card(int i, ChartPreset pr) {
      var needs = pr.needs?.call(p);
      var chart = needs == null ? _galleryChart(kind, pr) : null;
      return Opacity(
        opacity: needs == null ? 1 : 0.45,
        child: Material(
          color: colors.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                  color: _galleryPreset == i
                      ? colors.primary
                      : colors.outlineVariant,
                  width: _galleryPreset == i ? 2 : 1)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey("chartsPreset-$i"),
            onTap: needs != null
                ? null
                : () {
                    setState(() {
                      _galleryPreset = i;
                      _galleryMods = {};
                    });
                    _galleryPlay.forward(from: 0);
                  },
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: chart == null
                            ? ColoredBox(color: colors.surfaceContainerHighest)
                            : CustomPaint(
                                size: Size.infinite,
                                painter: _Thumb(chart, _galleryGround)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(
                        child: Text(pr.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurface)),
                      ),
                      if (pr.plays)
                        _badge(context, "Plays", const Color(0xFFF2B33D)),
                    ]),
                    Text(needs == null ? pr.says : "Needs $needs",
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5, color: colors.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 4, children: [
                      for (var u in pr.uses)
                        _badge(context, u.label, _useColours[u]!),
                    ]),
                  ]),
            ),
          ),
        ),
      );
    }

    var presets = [
      for (var (i, pr) in kind.presets.indexed)
        if (_galleryUse == null || pr.uses.contains(_galleryUse)) (i, pr)
    ];
    if (presets.isEmpty) presets = [...kind.presets.indexed];
    // Every card built (a few dozen thumbnails), so none waits for a scroll.
    return SingleChildScrollView(
        key: const ValueKey("chartsGalleryPresets"),
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            StudioPill(
                key: const ValueKey("chartsGalleryBack"),
                label: "All charts",
                icon: Icons.arrow_back,
                onTap: () => setState(() {
                      _galleryKind = null;
                      _galleryPreset = null;
                    })),
            const SizedBox(width: 10),
            Expanded(
              child: Text(kind.name,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: colors.onSurface)),
            ),
          ]),
          _hint(context,
              "${kind.use} Pick a starting design; every part can still be changed afterwards."),
          if (kind.caveat.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(kind.caveat,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFFF2B33D))),
            ),
          const SizedBox(height: 10),
          _cardGrid([for (var (i, pr) in presets) card(i, pr)]),
        ]));
  }

  Widget _galleryPanel(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var p = _picks;
    var preset = _galleryKind != null && _galleryPreset != null
        ? _kind.presets[_galleryPreset!]
        : null;
    var chart = preset == null
        ? null
        : _galleryChart(_kind, preset, mods: _galleryMods);
    return Container(
      color: colors.surfaceContainerLow,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(preset == null ? "New chart" : "${_kind.name} · ${preset.name}",
              key: const ValueKey("chartsTitle"),
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface)),
          if (chart == null || p == null)
            _hint(context,
                "Tick the columns to show on the left. Every kind of chart is drawn with them; the best fit first. Open one to see its starting designs.")
          else ...[
            const SizedBox(height: 8),
            AspectRatio(
              aspectRatio: 1.45,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CustomPaint(
                    key: const ValueKey("chartsGalleryPreview"),
                    size: Size.infinite,
                    painter: _PlayThumb(
                        chart, _galleryGround, _galleryPlay.value, _sheet)),
              ),
            ),
            _buttons([
              StudioPill(
                  key: const ValueKey("chartsGalleryReplay"),
                  label: "Play its arrival",
                  icon: Icons.play_arrow,
                  onTap: () => _galleryPlay.forward(from: 0)),
            ]),
            _hint(context, preset!.says),
            if ([
              for (var m in ChartModifier.values)
                if (m.fits(_kind.type, p)) m
            ]
                case var mods when mods.isNotEmpty) ...[
              const StudioLabel("Add to it"),
              Wrap(spacing: 4, runSpacing: 4, children: [
                for (var m in mods)
                  StudioPill(
                      key: ValueKey("chartsGalleryMod-${m.name}"),
                      label: m.label,
                      icon: _galleryMods.contains(m) ? Icons.check : Icons.add,
                      selected: _galleryMods.contains(m),
                      tooltip: m.says,
                      onTap: () => setState(() => _galleryMods.contains(m)
                          ? _galleryMods.remove(m)
                          : _galleryMods.add(m))),
              ]),
            ],
            _hint(context,
                "It sets the layout, labels, what's picked out, notes, grid and how it arrives. It keeps your data and words; the style sets the colours and typefaces."),
          ],
          _buttons([
            if (chart != null)
              StudioPill(
                  key: const ValueKey("chartsGalleryStart"),
                  label: "Start with this",
                  filled: true,
                  onTap: () => _makePreset(chart)),
            StudioPill(
                key: const ValueKey("chartsGalleryCancel"),
                label: "Cancel",
                onTap: () => setState(() {
                      _gallery = null;
                      _replacing = false;
                    })),
          ]),
        ]),
      ),
    );
  }

  /// _makePreset puts [chart] -- a starting design made from the ticked
  /// columns -- on the canvas as a chart of this sheet, one step to undo,
  /// and opens it.
  void _makePreset(ChartElement chart) {
    var s = _sheet;
    if (s == null) return;
    _end();
    c.beginInteraction();
    String id;
    if (_replacing && c.document.elementById(e.id) != null) {
      c.replaceElement(chart.rebase(e.base));
      id = e.id;
    } else {
      var made = c.addDataView(ElementKind.chart, s.id, _link.range);
      c.replaceElement(chart.rebase(made.base));
      id = made.id;
    }
    c.endInteraction();
    setState(() {
      _gallery = null;
      _replacing = false;
    });
    widget.onPickChart(id);
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
            slot("Small charts by", [
              _Menu<int>(
                  key: const ValueKey("chartsSplit"),
                  width: 130,
                  value: l.split,
                  options: [
                    (-1, "One chart"),
                    for (var col in wordColumns)
                      if (col != l.labels) (col, _columnName(col)),
                  ],
                  onChanged: (v) => _setLink(l.copyWith(split: v))),
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
        if (best.kind == ChartPartKind.note) {
          return ChartPick("note", index: best.index);
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
                e: _shown(),
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
        ChartPartKind.legend || ChartPartKind.note => 4,
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
      "mark" when data.panels.isNotEmpty => (
          _markLabel(p.index),
          "Its small chart: ${data.panels[p.index].data.categories.length} points."
        ),
      "mark" => (
          p.index < data.categories.length ? data.categories[p.index] : "Mark",
          "${seriesName(p.series)}: ${data.hasValueAt(p.series, p.index) ? _num(data.valueAt(p.series, p.index)) : "–"}"
        ),
      "highlight" => (
          _highlightName(e.highlights[p.index]),
          "A highlight: lit up on the chart."
        ),
      "note" => (
          switch (e.notes[p.index].kind) {
            ChartNoteKind.line => "Line",
            ChartNoteKind.band => "Band",
            ChartNoteKind.label => "Label",
          },
          "A note on the chart."
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
                  "description" => _descriptionPanel(context),
                  "legend" => _legendPanel(context),
                  "plot" => _plotPanel(context),
                  "xLabels" => _axisPanel(context, x: true),
                  "yLabels" => _axisPanel(context, x: false),
                  "series" => _seriesPanel(context, p.series),
                  "mark" => _markPanel(context, p.series, p.index),
                  "highlight" => _highlightPanel(context, p.index),
                  "note" => _notePanel(context, p.index),
                  _ => const [],
                }),
          ),
        ),
      ]),
    );
  }

  /// _markLabel is what mark [i] is of: its category, or on a split chart,
  /// whose small chart it is.
  String _markLabel(int i) {
    var data = e.data;
    if (data.panels.isNotEmpty) {
      return i >= 0 && i < data.panels.length ? data.panels[i].name : "";
    }
    return i >= 0 && i < data.categories.length ? data.categories[i] : "";
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
      // The six styles (Ken, 2026-11-17: they replace the Looks).
      const StudioLabel("Style"),
      DataStylePicker(
          key: const ValueKey("chartsStyles"),
          element: e,
          onPick: (st) => _set(
              chartInStyle(e, st, panel: e.panel.a > 0 || e.style.isEmpty))),
      StudioPills<bool>(
          id: "chartsGround",
          label: "Ground",
          value: e.panel.a > 0,
          options: const [(true, "Its own"), (false, "The canvas")],
          onChanged: (v) => _set(e.copyWith(
              panel: v
                  ? (dataStyleNamed(e.style)?.ground ?? const Color(0xFFFFFFFF))
                  : const Color(0x00000000)))),
      _hint(context,
          "A style sets its colours, typefaces and corners; the data and your words stay. Its own ground keeps a dark style readable on a light page."),
      const StudioLabel("Motion"),
      if (e.steps.length > 1) ...[
        StudioPills<String>(
            id: "chartsFollow",
            label: "Steps move on with",
            value: e.follow,
            options: [for (var f in ChartStepsFollow.values) (f.name, f.label)],
            onChanged: (v) => _set(e.copyWith(follow: v))),
        _hint(
            context,
            switch (ChartStepsFollow.fromName(e.follow)) {
              ChartStepsFollow.time =>
                "Once it has arrived, a step after another at the pace below.",
              ChartStepsFollow.marks =>
                "A step from each mark on the timeline. At a Stop mark the canvas waits, so in a presentation the next step comes at a click.",
              ChartStepsFollow.scenes =>
                "A step in each scene or page it is in: step 1 in the first, step 2 in the next. Put linked copies of it in the scenes after.",
            }),
      ],
      if (_playable &&
          (e.steps.length < 2 || e.follow == ChartStepsFollow.time.name)) ...[
        StudioSlider(
          key: const ValueKey("chartsSlider-Each"),
          label: e.steps.length > 1 ? "Each step" : "Each date",
          value: e.play,
          min: 0,
          max: 6,
          rest: 0,
          format: (v) => v <= 0 ? "Still" : "${v.toStringAsFixed(1)}s",
          onChanged: (v) =>
              _live(e.copyWith(play: (v * 10).roundToDouble() / 10)),
          onChangeEnd: (_) => _end(),
        ),
        _hint(
            context,
            e.play <= 0
                ? "Still: it shows ${e.steps.length > 1 ? "this step" : "one date"}. Give it seconds and, once it has arrived on the canvas, it plays through them."
                : "Once it has arrived on the canvas it plays through its ${e.steps.length > 1 ? "steps" : "dates"}, ${e.play.toStringAsFixed(1)}s each: ${_sheet == null ? 0 : playLength(e, _sheet!).toStringAsFixed(1)}s in all. ▶ Preview, above the chart, shows it here."),
      ] else
        _hint(context,
            "Play through a column of dates, or add steps, and it can move."),
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
      StudioLabel("Notes · ${e.notes.length}"),
      for (var (i, n) in e.notes.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Material(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              key: ValueKey("chartsNote-$i"),
              borderRadius: BorderRadius.circular(8),
              onTap: () => _pick(ChartPick("note", index: i)),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                          color: n.colour,
                          borderRadius: BorderRadius.circular(4))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_noteName(n),
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurface)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      _buttons([
        StudioPill(
            key: const ValueKey("chartsAddAverage"),
            label: "+ Average line",
            onTap: () => _addNote(const ChartNote(text: "Average"))),
        StudioPill(
            key: const ValueKey("chartsAddBand"),
            label: "+ Band",
            onTap: () => _addNote(ChartNote(
                kind: ChartNoteKind.band,
                from: 1,
                to: math.min(3, math.max(1, e.data.categories.length)),
                text: "Top",
                colour: const Color(0xFF2FE08A)))),
      ]),
      if (l.charted)
        _hint(context,
            "Read as only a chart can (grouped, by places, one date at a time), its numbers are worked out from the sheet and not written back to it."),
      ..._kindParts(context),
    ];
  }

  /// _kindParts are the settings only some kinds of chart have: a
  /// doughnut's hole and the words in it, a pictogram's icons.
  List<Widget> _kindParts(BuildContext context) => [
        // The new kinds' ways (ChartDesign.mode, chartModes).
        if (chartModes[e.type.name] case var ways?)
          StudioPills<String>(
              id: "chartsMode",
              label: "Drawn as",
              value: modeOf(e.design, e.type.name),
              options: [for (var (m, says) in ways) (m, says)],
              onChanged: (m) =>
                  _set(e.copyWith(design: e.design.copyWith(mode: m)))),
        if (e.type == ChartType.pie || e.type == ChartType.donut) ...[
          const StudioLabel("Its shape"),
          StudioPills<bool>(
              id: "chartsHalf",
              label: "",
              value: e.design.half,
              options: const [(false, "A whole circle"), (true, "An arch")],
              onChanged: (v) =>
                  _set(e.copyWith(design: e.design.copyWith(half: v)))),
          StudioPills<bool>(
              id: "chartsGaps",
              label: "Between the slices",
              value: e.design.gaps,
              options: const [(false, "Touching"), (true, "A gap")],
              onChanged: (v) =>
                  _set(e.copyWith(design: e.design.copyWith(gaps: v)))),
        ],
        if (e.type == ChartType.donut || e.type == ChartType.gauge) ...[
          StudioLabel(e.type == ChartType.donut ? "Its middle" : "The dial"),
          _slider("Hole", e.innerRadius, 0.2, 0.9, 0.55,
              (v) => _live(e.copyWith(innerRadius: v))),
          _Field(
              key: const ValueKey("chartsCentreWords"),
              text: e.centreLabel,
              hint: "Words in the middle: {total of Points}",
              words: wordChoices(e.data),
              reads: (t) => liveWords(e.data, t),
              onChanged: (v) => _live(e.copyWith(centreLabel: v))),
        ],
        if (e.type == ChartType.pictogram) ...[
          const StudioLabel("Its icons"),
          StudioPills<String>(
              id: "chartsPictoShape",
              label: "Shape",
              value: e.pictoShape.name,
              options: [for (var p in PictoShape.values) (p.name, p.label)],
              onChanged: (v) =>
                  _set(e.copyWith(pictoShape: PictoShape.fromName(v)))),
          _slider("How many", e.pictoCount.toDouble(), 5, 100, 20,
              (v) => _live(e.copyWith(pictoCount: v.round()))),
        ],
      ];

  void _addNote(ChartNote note) {
    _set(e.copyWith(notes: [...e.notes, note]));
    _pick(ChartPick("note", index: e.notes.length));
  }

  static String _noteName(ChartNote n) => switch (n.kind) {
        ChartNoteKind.line =>
          "${n.text.isEmpty ? "Line" : n.text} · ${n.value.isNaN ? "at the average" : "at ${_num(n.value)}"}",
        ChartNoteKind.band =>
          "${n.text.isEmpty ? "Band" : n.text} · places ${n.from}–${n.to}",
        ChartNoteKind.label =>
          "“${n.text.isEmpty ? n.who : n.text}” on ${n.who}",
      };

  List<Widget> _notePanel(BuildContext context, int i) {
    var n = e.notes[i];
    void put(ChartNote next, {bool live = false}) {
      var all = [...e.notes];
      all[i] = next;
      live ? _live(e.copyWith(notes: all)) : _set(e.copyWith(notes: all));
    }

    var count = math.max(1, e.data.categories.length);
    return [
      const StudioLabel("Says"),
      _Field(
          key: ValueKey("chartsNoteText-$i"),
          text: n.text,
          hint: n.kind == ChartNoteKind.label ? n.who : "Words beside it",
          words: wordChoices(e.data),
          reads: (t) => liveWords(e.data, t),
          onChanged: (v) => put(n.copyWith(text: v), live: true)),
      if (n.kind == ChartNoteKind.line) ...[
        StudioPills<bool>(
            id: "chartsNoteAt",
            label: "At",
            value: n.value.isNaN,
            options: const [(true, "The average"), (false, "A number")],
            onChanged: (v) => put(n.copyWith(value: v ? double.nan : 0))),
        if (!n.value.isNaN) ...[
          const SizedBox(height: 6),
          _Field(
              key: ValueKey("chartsNoteValue-$i"),
              text: _num(n.value),
              hint: "A number",
              onChanged: (v) {
                var x = double.tryParse(v.trim());
                if (x != null) put(n.copyWith(value: x), live: true);
              }),
        ],
      ],
      if (n.kind == ChartNoteKind.band) ...[
        _slider(
            "From place",
            n.from.toDouble(),
            1,
            count.toDouble(),
            1,
            (v) => put(
                n.copyWith(from: v.round(), to: math.max(v.round(), n.to)),
                live: true)),
        _slider(
            "To place",
            n.to.toDouble(),
            1,
            count.toDouble(),
            1,
            (v) => put(
                n.copyWith(to: v.round(), from: math.min(v.round(), n.from)),
                live: true)),
        _hint(context,
            "Behind those places, whoever is in them: a cut-off that stays put."),
      ],
      _swatches("chartsNoteColour", "Colour", n.colour,
          (v) => put(n.copyWith(colour: v))),
      _buttons([
        StudioPill(
            key: const ValueKey("chartsNoteOff"),
            label: n.off ? "Switch on" : "Switch off",
            onTap: () => put(n.copyWith(off: !n.off))),
        StudioPill(
            key: const ValueKey("chartsNoteDelete"),
            label: "Delete",
            onTap: () {
              _set(e.copyWith(notes: [...e.notes]..removeAt(i)));
              _pick(ChartPick.chart);
            }),
      ]),
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
            words: wordChoices(e.data),
            reads: (t) => liveWords(e.data, t),
            onChanged: (v) => _live(e.copyWith(title: v))),
        _hint(context,
            "Words in { } are worked out from the numbers, and change when they do."),
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
        ..._typeface("chartsTitleFont", e.titleSpec,
            (spec) => _set(e.copyWith(titleSpec: spec))),
      ];

  /// _typeface is a face and a weight for [spec].
  List<Widget> _typeface(
          String id, TextSpec spec, ValueChanged<TextSpec> set) =>
      [
        const StudioLabel("Typeface"),
        _Menu<String>(
            key: ValueKey(id),
            value: spec.fontFamily,
            options: [
              if (!canvasFonts.contains(spec.fontFamily))
                (spec.fontFamily, spec.fontFamily),
              for (var f in canvasFonts) (f, f),
            ],
            onChanged: (f) => set(spec.copyWith(fontFamily: f))),
        StudioPills<int>(
            id: "${id}Weight",
            label: "Weight",
            value: spec.weight,
            options: const [(400, "Regular"), (600, "Semibold"), (800, "Bold")],
            onChanged: (w) => set(spec.copyWith(weight: w))),
      ];

  List<Widget> _descriptionPanel(BuildContext context) {
    var spec = e.descriptionText;
    return [
      const StudioLabel("Words"),
      _Field(
          key: const ValueKey("chartsDescriptionText"),
          text: e.description,
          hint: "A line under the title",
          words: wordChoices(e.data),
          reads: (t) => liveWords(e.data, t),
          onChanged: (v) => _live(e.copyWith(description: v))),
      _slider(
          "Size",
          spec.fontSize,
          6,
          48,
          e.labelSpec.fontSize,
          (v) =>
              _live(e.copyWith(descriptionSpec: spec.copyWith(fontSize: v)))),
      _swatches("chartsDescriptionInk", "Colour", spec.color,
          (v) => _set(e.copyWith(descriptionSpec: spec.copyWith(color: v)))),
      ..._typeface("chartsDescriptionFont", spec,
          (next) => _set(e.copyWith(descriptionSpec: next))),
    ];
  }

  List<Widget> _legendPanel(BuildContext context) => [
        StudioPills<bool>(
            id: "chartsLegend",
            label: "Shown",
            value: e.showLegend,
            options: const [(true, "Shown"), (false, "Hidden")],
            onChanged: (v) => _set(e.copyWith(showLegend: v))),
        if (e.showLegend) ...[
          StudioPills<String>(
              id: "chartsLegendPlace",
              label: "Where",
              value: e.legend.placement.name,
              options: [
                for (var p in LegendPlacement.values) (p.name, p.label)
              ],
              onChanged: (v) => _set(e.copyWith(
                  legend: e.legend
                      .copyWith(placement: LegendPlacement.values.byName(v))))),
          StudioPills<bool>(
              id: "chartsLegendStack",
              label: "Entries",
              value: e.legend.vertical,
              options: const [(false, "In a row"), (true, "One a line")],
              onChanged: (v) =>
                  _set(e.copyWith(legend: e.legend.copyWith(vertical: v)))),
          _slider("Key size", e.legend.scale, 0.5, 2, 1,
              (v) => _live(e.copyWith(legend: e.legend.copyWith(scale: v)))),
        ],
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
        if (e.showGrid)
          _swatches("chartsGridColour", "Grid colour", e.gridColor,
              (v) => _set(e.copyWith(gridColor: v))),
        _slider("Corners", e.barRadius, 0, 24, 0,
            (v) => _live(e.copyWith(barRadius: v))),
        if (e.type.isBar || e.type == ChartType.lollipop)
          _slider("Gap between", e.barGap, 0, 0.9, 0.2,
              (v) => _live(e.copyWith(barGap: v))),
        if (e.type.isCartesian)
          StudioPills<bool>(
              id: "chartsLogScale",
              label: "Scale",
              value: e.logScale,
              options: const [
                (false, "Even steps"),
                (true, "Log (×10 a step)")
              ],
              onChanged: (v) => _set(e.copyWith(logScale: v))),
        ..._designParts(context),
        ..._numbersParts(context),
      ];

  /// _designParts are the ways its marks are drawn beyond its type
  /// (ChartDesign): tracks, values inside, names above; steps; quadrants,
  /// a trend, joined points.
  List<Widget> _designParts(BuildContext context) {
    var d = e.design;
    void put(ChartDesign next) => _set(e.copyWith(design: next));
    StudioPills<bool> onOff(String id, String label, bool value,
            ChartDesign Function(bool) next,
            {String on = "On", String off = "Off"}) =>
        StudioPills<bool>(
            id: id,
            label: label,
            value: value,
            options: [(true, on), (false, off)],
            onChanged: (v) => put(next(v)));
    return [
      if (e.type.isBar && !e.type.isStacked) ...[
        onOff("chartsTrack", "Tracks behind bars", d.track,
            (v) => d.copyWith(track: v)),
        if (e.showValues)
          onOff("chartsValuesInside", "Values", d.valuesInside,
              (v) => d.copyWith(valuesInside: v),
              on: "Inside the bars", off: "Past the ends"),
      ],
      if (e.type == ChartType.horizontalBar)
        onOff("chartsLabelsAbove", "Names", d.labelsAbove,
            (v) => d.copyWith(labelsAbove: v),
            on: "Above each bar", off: "Beside"),
      if (e.type == ChartType.line)
        onOff(
            "chartsStep", "Between points", d.step, (v) => d.copyWith(step: v),
            on: "Steps", off: "Straight or curved"),
      if (e.type == ChartType.scatter) ...[
        onOff("chartsQuadrants", "Quadrants", d.quadrants,
            (v) => d.copyWith(quadrants: v)),
        onOff(
            "chartsTrend", "Trend line", d.trend, (v) => d.copyWith(trend: v)),
        onOff("chartsConnect", "Points joined", d.connect,
            (v) => d.copyWith(connect: v)),
      ],
    ];
  }

  /// _numbersParts is how the chart writes its numbers: shortened or in
  /// full, decimals, and a sign or unit either side ("\$300", "40%").
  List<Widget> _numbersParts(BuildContext context) {
    var n = e.numbers;
    void put(ChartNumbers next) => _set(e.copyWith(numbers: next));
    return [
      const StudioLabel("Numbers"),
      _Menu<String>(
          key: const ValueKey("chartsNumberStyle"),
          value: n.style.name,
          options: [
            for (var st in NumberStyle.values) (st.name, st.label),
          ],
          onChanged: (v) =>
              put(n.copyWith(style: NumberStyle.values.byName(v)))),
      StudioPills<int>(
          id: "chartsDecimals",
          label: "Decimals",
          value: n.decimals,
          options: const [(0, "0"), (1, "1"), (2, "2"), (3, "3")],
          onChanged: (v) => put(n.copyWith(decimals: v))),
      Row(children: [
        Expanded(
          child: _Field(
              key: const ValueKey("chartsNumberBefore"),
              text: n.before,
              hint: "Before: \$",
              onChanged: (v) =>
                  _live(e.copyWith(numbers: e.numbers.copyWith(before: v)))),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _Field(
              key: const ValueKey("chartsNumberAfter"),
              text: n.after,
              hint: "After: %",
              onChanged: (v) =>
                  _live(e.copyWith(numbers: e.numbers.copyWith(after: v)))),
        ),
      ]),
    ];
  }

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
        _swatches(
            x ? "chartsXInk" : "chartsYInk",
            "Colour",
            (x ? e.xLabelColor : e.yLabelColor) ?? e.labelSpec.color,
            (v) => _set(
                x ? e.copyWith(xLabelColor: v) : e.copyWith(yLabelColor: v))),
        _slider(
            "Distance",
            x ? e.xLabelGap : e.yLabelGap,
            0,
            40,
            0,
            (v) =>
                _live(x ? e.copyWith(xLabelGap: v) : e.copyWith(yLabelGap: v))),
        if (!x)
          _slider("Steps", e.axisSteps.toDouble(), 2, 12, 5,
              (v) => _live(e.copyWith(axisSteps: v.round()))),
        const StudioLabel("Its title"),
        _Field(
            key: ValueKey(x ? "chartsXTitle" : "chartsYTitle"),
            text: x ? e.xAxisLabel : e.yAxisLabel,
            hint: x ? "What runs along: Month" : "What goes up: Points",
            onChanged: (v) => _live(x
                ? e.copyWith(xAxisLabel: v, showXTitle: v.trim().isNotEmpty)
                : e.copyWith(yAxisLabel: v, showYTitle: v.trim().isNotEmpty))),
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
      if (e.type.isLinear || e.type.usesSmooth) ...[
        _slider("Line", e.strokeWidth, 0.5, 12, 2.5,
            (v) => _live(e.copyWith(strokeWidth: v))),
        if (e.type.usesSmooth)
          StudioPills<bool>(
              id: "chartsSmooth",
              label: "Between points",
              value: e.smooth,
              options: const [(false, "Straight"), (true, "Curved")],
              onChanged: (v) => _set(e.copyWith(smooth: v))),
        StudioPills<bool>(
            id: "chartsPoints",
            label: "Points",
            value: e.showPoints,
            options: const [(true, "Shown"), (false, "Hidden")],
            onChanged: (v) => _set(e.copyWith(showPoints: v))),
        if (e.showPoints)
          _slider("Point size", e.pointSize, 1, 16, 4,
              (v) => _live(e.copyWith(pointSize: v))),
      ],
      if (e.type.isCandles) ...[
        _swatches("chartsRise", "Up", e.riseColor,
            (v) => _set(e.copyWith(riseColor: v))),
        _swatches("chartsFall", "Down", e.fallColor,
            (v) => _set(e.copyWith(fallColor: v))),
      ],
    ];
  }

  List<Widget> _markPanel(BuildContext context, int s, int i) {
    var label = _markLabel(i);
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
            key: const ValueKey("chartsSpotlight"),
            label: "Pick $label out everywhere",
            tooltip: "In every chart of this sheet, and its tables' rows",
            onTap: () {
              var sheet = _sheet;
              if (sheet != null) c.setSheet(sheet.copyWith(spotlight: label));
            }),
        StudioPill(
            key: const ValueKey("chartsLabelMark"),
            label: "Label it",
            onTap: () => _addNote(ChartNote(
                kind: ChartNoteKind.label,
                who: label,
                colour: const Color(0xFFFFFFFF)))),
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
          "note" => [
              for (var q in parts)
                if (q.kind == ChartPartKind.note && q.index == p.index) q
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

  /// words are live words to put in with a press (chart_words.dart), as
  /// (what the button says, what it puts in); [reads] says what the field
  /// reads now, worked out.
  final List<(String, String)> words;
  final String Function(String)? reads;
  const _Field(
      {required this.text,
      required this.hint,
      required this.onChanged,
      this.words = const [],
      this.reads,
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

  /// _insert puts [word] where the cursor is (or at the end), as typed.
  void _insert(String word) {
    var sel = _c.selection;
    var at = sel.isValid ? sel.start : _c.text.length;
    var to = sel.isValid ? sel.end : _c.text.length;
    var text = _c.text.replaceRange(at, to, word);
    _c.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: at + word.length));
    widget.onChanged(text);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var field = TextField(
      controller: _c,
      focusNode: _f,
      onChanged: (v) {
        widget.onChanged(v);
        if (widget.reads != null) setState(() {});
      },
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
    var reads = widget.reads;
    if (widget.words.isEmpty && reads == null) return field;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      field,
      if (widget.words.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text("Insert",
                    style: TextStyle(
                        fontSize: 11.5, color: colors.onSurfaceVariant)),
                for (var (label, word) in widget.words)
                  StudioPill(
                      key: ValueKey("chartsWord-$label"),
                      label: label,
                      onTap: () => _insert(word)),
              ]),
        ),
      if (reads != null && _c.text.contains("{"))
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text("Reads now: ${reads(_c.text)}",
              key: const ValueKey("chartsReadsNow"),
              style: TextStyle(fontSize: 12, color: colors.onSurface)),
        ),
    ]);
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
  int? last;
  for (var col = 0; col < g.cols; col++) {
    var values = [
      for (var r = g.r0 + 1; r <= g.r1; r++) sheetValue(sheet, r, g.c0 + col)
    ];
    var filled = values.where((v) => v != null && v != "").toList();
    if (filled.isNotEmpty && filled.every((v) => v is double)) last = col;
  }
  var names = namingColumn(sheet, g);
  if (names < 0 || last == null) return made;
  var next = withLink(made, link.copyWith(labels: names, series: [last]));
  c.replaceElement(next);
  return next;
}

/// ColumnKind is what a column of a sheet holds, for the suggestions:
/// numbers; dates (a column the rows come in runs of, or headed so); or
/// names.
enum ColumnKind { numbers, dates, names, empty }

/// columnKinds is each column of [range]'s kind.
List<ColumnKind> columnKinds(DataSheet sheet, CellRange range) {
  var datey = RegExp(r"date|week|month|year|day|time|season|round|period",
      caseSensitive: false);
  // A heading that is a date word itself ("Week", "Season 2025", "Year"),
  // not one that merely holds one ("Days injured").
  var dateHead = RegExp(
      r"^\s*(date|week|wk|gameweek|matchday|month|year|yr|day|time|season|"
      r"round|period|quarter|qtr)s?(\s*\d+|\s*\(.*\))?\s*$",
      caseSensitive: false);
  var monthOrDay = RegExp(
      r"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|mon|tue|wed|thu|"
      r"fri|sat|sun|q[1-4])",
      caseSensitive: false);
  return [
    for (var col = 0; col < range.cols; col++)
      () {
        var values = [
          for (var r = range.r0 + 1; r <= range.r1; r++)
            sheetValue(sheet, r, range.c0 + col)
        ].where((v) => v != null && v != "").toList();
        if (values.isEmpty) return ColumnKind.empty;
        var head = sheetShown(sheet, range.r0, range.c0 + col);
        var numbers = values.whereType<double>().toList();
        if (numbers.length * 2 > values.length) {
          // Whole numbers that count time -- weeks 1 to 38, seasons, years
          // -- are when, not how much (found making the Charts canvas: no
          // line could be drawn of points by season).
          var whole = numbers.length == values.length &&
              numbers.every((v) => v == v.roundToDouble());
          var years = whole && numbers.every((v) => v >= 1800 && v <= 2200);
          return whole && (dateHead.hasMatch(head) || years)
              ? ColumnKind.dates
              : ColumnKind.numbers;
        }
        var words = [for (var v in values) "$v"];
        // Runs: each value comes as one block of rows, more than one long --
        // a long sheet's weeks or dates. Words in runs that don't read as
        // dates ("Top four", "Chasing") are groups: names.
        var runs = <String>[];
        for (var w in words) {
          if (runs.isEmpty || runs.last != w) runs.add(w);
        }
        var blocks =
            runs.toSet().length == runs.length && runs.length < words.length;
        var datelike = words
            .every((w) => RegExp(r"\d").hasMatch(w) || monthOrDay.hasMatch(w));
        return datey.hasMatch(head) || (blocks && datelike)
            ? ColumnKind.dates
            : ColumnKind.names;
      }(),
  ];
}

/// ChartIdea is one suggestion: its name, why it suits, and the chart it
/// makes -- a kind, a way of reading the sheet, and any highlights.
class ChartIdea {
  final String name, why, title;
  final ChartType type;
  final SheetLink link;
  final List<ChartHighlight> highlights;
  const ChartIdea(this.name, this.why, this.type, this.link,
      {this.title = "", this.highlights = const []});

  /// preview is the chart as it would look, for its card, the size of
  /// [like].
  ChartElement preview(DataSheet sheet, ChartElement like) {
    var chart = ChartElement(
        ElementBase(id: "idea", width: like.width, height: like.height),
        type: type,
        title: title,
        highlights: highlights,
        sheet: link);
    return chart.copyWith(
        data: chartDataOf(sheet, link, const ChartData(),
            type: type, highlights: highlights));
  }
}

/// chartIdeas is what the ticked columns [picks] of [range] could be drawn
/// as, the best fit first (prototype v6's suggestions): a date with names
/// and a number, a race, a line each, totals; a date and a number, totals
/// and averages; names and one number, ranked bars, columns, a lollipop, a
/// donut; two numbers, a scatter, side by side, a slope.
List<ChartIdea> chartIdeas(DataSheet sheet, CellRange range, List<int> picks) {
  var kinds = columnKinds(sheet, range);
  String name(int col) {
    var n = sheetShown(sheet, range.r0, range.c0 + col).trim();
    return n.isEmpty ? columnName(range.c0 + col) : n;
  }

  List<int> ofKind(ColumnKind k) => [
        for (var p in picks)
          if (p < kinds.length && kinds[p] == k) p
      ];
  var nums = ofKind(ColumnKind.numbers);
  var dates = ofKind(ColumnKind.dates);
  var names = ofKind(ColumnKind.names);
  if (nums.isEmpty) return const [];
  var v = nums.first, vn = name(v);
  SheetLink link(int labels, List<int> series) =>
      SheetLink(sheet.id, range, labels: labels, series: series);
  var out = <ChartIdea>[];

  if (dates.isNotEmpty && names.isNotEmpty) {
    var d = dates.first, n = names.first, dn = name(d), nn = name(n);
    out.add(ChartIdea(
        "Race through $dn",
        "Ranked by $vn, one ${dn.toLowerCase()} at a time: watch them overtake.",
        ChartType.horizontalBar,
        link(n, [v]).copyWith(through: d, sortBy: v),
        title: "$vn by $nn"));
    out.add(ChartIdea("A line per $nn", "Each its own line; the top three lit.",
        ChartType.line, link(d, [v]).copyWith(colourBy: n),
        title: "$vn through the ${dn.toLowerCase()}s",
        highlights: const [
          ChartHighlight(
              reach: ChartReach.top,
              n: 3,
              colour: Color(0xFF2FE08A),
              named: true),
        ]));
    out.add(ChartIdea(
        "A small chart for each $nn",
        "One little chart each, all on one scale, so they compare.",
        ChartType.line,
        link(d, [v]).copyWith(split: n),
        title: "Every $nn, on the same scale"));
    out.add(ChartIdea(
        "Total each $dn",
        "Every row of each ${dn.toLowerCase()} added up.",
        ChartType.bar,
        link(d, [v]).copyWith(group: "total"),
        title: "$vn each ${dn.toLowerCase()}"));
    out.add(ChartIdea(
        "$vn per $nn, the most",
        "Each one's best, longest first.",
        ChartType.horizontalBar,
        link(n, [v]).copyWith(group: "most", sortBy: v),
        title: "$vn by $nn"));
  } else if (dates.isNotEmpty) {
    var d = dates.first, dn = name(d);
    out.add(ChartIdea(
        "Total each $dn",
        "The rows of each ${dn.toLowerCase()} added up.",
        ChartType.bar,
        link(d, [v]).copyWith(group: "total"),
        title: "$vn each ${dn.toLowerCase()}"));
    out.add(ChartIdea(
        "Average each $dn",
        "What a typical row was, one ${dn.toLowerCase()} after another.",
        ChartType.line,
        link(d, [v]).copyWith(group: "average"),
        title: "Average $vn"));
    out.add(ChartIdea("Total as an area", "The same totals, filled in.",
        ChartType.area, link(d, [v]).copyWith(group: "total")));
  } else {
    var n = names.isNotEmpty
        ? names.first
        : kinds.indexWhere((k) => k == ColumnKind.names);
    if (n < 0) n = 0;
    var nn = name(n);
    if (nums.length == 1) {
      out.add(ChartIdea(
          "Ranked bars",
          "One number each, longest first: the easiest to compare.",
          ChartType.horizontalBar,
          link(n, [v]).copyWith(sortBy: v),
          title: "$vn by $nn"));
      out.add(ChartIdea("Columns", "In the sheet's order, left to right.",
          ChartType.bar, link(n, [v]),
          title: vn));
      out.add(ChartIdea("Lollipop", "Bars made light: good with many rows.",
          ChartType.lollipop, link(n, [v]),
          title: vn));
      out.add(ChartIdea(
          "Donut",
          "Shares of a whole: the biggest eight. With twenty, bars read better.",
          ChartType.donut,
          link(n, [v]).copyWith(sortBy: v, top: 8),
          title: vn));
    } else {
      var w = nums[1], wn = name(w);
      out.add(ChartIdea(
          "Scatter",
          "How $vn and $wn go together: $vn across, $wn up.",
          ChartType.scatter,
          link(v, [w]),
          title: "$vn and $wn"));
      out.add(ChartIdea("Side by side", "Each number for each $nn.",
          ChartType.groupedBar, link(n, nums.take(4).toList()),
          title: nums.take(4).map(name).join(" and ")));
      out.add(ChartIdea("Slope", "From $vn to $wn, a line each.",
          ChartType.slope, link(n, [v, w]),
          title: "$vn to $wn"));
    }
  }
  return out;
}

/// _ViewThumb draws a table or a chart fitted to a board card.
class _ViewThumb extends CustomPainter {
  final CanvasElement e;
  final CanvasImageStore images;
  final Color ground;
  _ViewThumb(this.e, this.images, this.ground) : super(repaint: images);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = ground);
    var w = math.max(1.0, e.width), h = math.max(1.0, e.height);
    var k = math.min((size.width - 8) / w, (size.height - 8) / h);
    canvas.save();
    canvas.translate((size.width - w * k) / 2, (size.height - h * k) / 2);
    canvas.scale(k);
    var rect = Rect.fromLTWH(0, 0, w, h);
    switch (e) {
      case TableElement t:
        paintTable(canvas, rect, t, images: images);
      case ChartElement ch:
        paintChart(canvas, rect, ch);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ViewThumb old) =>
      !identical(old.e, e) || old.ground != ground;
}

/// _Thumb draws a suggestion's chart fitted to its card.
/// _PlayThumb is [e] fitted on [ground], [reveal] of the way arrived.
class _PlayThumb extends CustomPainter {
  final ChartElement e;
  final Color ground;
  final double reveal;
  final DataSheet? sheet;
  _PlayThumb(this.e, this.ground, this.reveal, this.sheet);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = ground);
    var w = math.max(1.0, e.width), h = math.max(1.0, e.height);
    var k = math.min((size.width - 8) / w, (size.height - 8) / h);
    canvas.save();
    canvas.translate((size.width - w * k) / 2, (size.height - h * k) / 2);
    canvas.scale(k);
    // One that plays (a race) plays through its dates; the rest arrive.
    var sh = sheet;
    var playing = e.play > 0 && sh != null;
    var chart = playing ? chartPlaying(e, sh, reveal * playLength(e, sh)) : e;
    paintChart(canvas, Rect.fromLTWH(0, 0, w, h), chart,
        reveal: playing ? 1 : reveal);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PlayThumb old) =>
      !identical(old.e, e) || old.ground != ground || old.reveal != reveal;
}

class _Thumb extends CustomPainter {
  final ChartElement e;
  final Color ground;
  _Thumb(this.e, this.ground);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = ground);
    var w = math.max(1.0, e.width), h = math.max(1.0, e.height);
    var k = math.min((size.width - 8) / w, (size.height - 8) / h);
    canvas.save();
    canvas.translate((size.width - w * k) / 2, (size.height - h * k) / 2);
    canvas.scale(k);
    paintChart(canvas, Rect.fromLTWH(0, 0, w, h), e);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Thumb old) =>
      !identical(old.e, e) || old.ground != ground;
}
