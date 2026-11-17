import 'dart:async';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/ui/data/vector_saving.dart';
import 'package:bruig/plugin_system/canvas/export/vector_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/chart_play.dart';
import 'package:bruig/plugin_system/canvas/model/chart_presets.dart';
import 'package:bruig/plugin_system/canvas/model/chart_story.dart';
import 'package:bruig/plugin_system/canvas/model/chart_words.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_styles.dart';
import 'package:bruig/plugin_system/canvas/model/page_style.dart';
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
import 'package:bruig/plugin_system/canvas/ui/controls.dart' show CanvasHint;
import 'package:bruig/plugin_system/canvas/ui/data/data_studio_side.dart';
import 'package:bruig/plugin_system/canvas/ui/data/data_style_picker.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

part 'charts_checks.dart';
part 'charts_board.dart';
part 'charts_gallery.dart';
part 'charts_slots_stage.dart';
part 'charts_panel.dart';
part 'charts_motion_panels.dart';
part 'charts_part_panels.dart';

// data_charts_design.dart is the Data Studio's Charts tab. On the left, the
// sheet's columns and its charts; along the top, the slots (labels, values,
// colour by, play through, kind); in the middle the chart as the canvas
// draws it, where clicking a part picks what the right-hand panel is about.
// The marks are found by the painter itself (ChartPart, chart_common.dart),
// so what is clicked is what was drawn; each change is one undo step.

class ChartsDesign extends StatefulWidget {
  final CanvasController controller;
  final String sheetId;
  final ChartElement chart;
  final ValueChanged<String> onPickChart;

  /// startInGallery opens on the gallery, its design replacing [chart]: a
  /// first chart is chosen from the designs, not made plain then remade.
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
  // The parts are extensions, and call setState: overridden so the call
  // is this class's own, not State's protected one.
  @override
  void setState(VoidCallback fn) => super.setState(fn);

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

  // The gallery: the kind opened, the design picked, the cards' filter.
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

  /// _boardOn shows every view of the sheet together.
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

  // Motion: a preview, and steps.

  /// _playable is whether the chart moves: through dates, or by steps.
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

  /// _gliding is whether the stage drew a glide at the last tick, so the
  /// tick after it ends draws the numbers themselves.
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

  /// _stepsSaved is the steps, the one worked on saved from its fields.
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

  // Writing.

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

  // The sheet's columns, as the chart's range has them.

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

  // ---- charts_checks.dart -------------------------------------------------

  // Checks: what makes a chart hard to read, each with a fix.

  // ---- charts_board.dart --------------------------------------------------

  // Left: columns and charts.

  // The board: every view of the sheet together.

  PageLayout _pageLayout = PageLayout.rows2;

  // What each column holds, as the gallery reads it: worked out again
  // only when the sheet or the range changes.
  DataSheet? _kindsOf;
  CellRange? _kindsRange;
  List<ColumnKind> _kindsCache = const [];

  // Suggestions: a new chart chosen by how it looks with your numbers.

  // ---- charts_gallery.dart ------------------------------------------------

  // The gallery: every kind of chart, built from the ticked columns.

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

  static const _useColours = {
    ChartUse.infographic: Color(0xFF7FA8F5),
    ChartUse.video: Color(0xFFE59BF0),
    ChartUse.analysis: Color(0xFF6FD6B0),
  };

  // ---- charts_slots_stage.dart --------------------------------------------

  // The slots.

  // The stage.

  static int _rank(ChartPartKind k) => switch (k) {
        ChartPartKind.title || ChartPartKind.description => 5,
        ChartPartKind.legend || ChartPartKind.note => 4,
        ChartPartKind.mark => 3,
        ChartPartKind.xLabels || ChartPartKind.yLabels => 2,
        ChartPartKind.plot => 1,
      };

  // ---- charts_panel.dart --------------------------------------------------

  // The panel: the Studio's sidebar (data_studio_side.dart), the part
  // picked in its header, a strip of the most used, folding sections.

  static String _num(double v) =>
      v == v.roundToDouble() ? "${v.round()}" : v.toStringAsFixed(2);

  // ---- charts_motion_panels.dart ------------------------------------------

  static String _noteName(ChartNote n) => switch (n.kind) {
        ChartNoteKind.line =>
          "${n.text.isEmpty ? "Line" : n.text} · ${n.value.isNaN ? "at the average" : "at ${_num(n.value)}"}",
        ChartNoteKind.band =>
          "${n.text.isEmpty ? "Band" : n.text} · places ${n.from}–${n.to}",
        ChartNoteKind.label =>
          "“${n.text.isEmpty ? n.who : n.text}” on ${n.who}",
        ChartNoteKind.callout =>
          "Callout on ${n.who}${n.text.isEmpty ? "" : ": “${n.text}”"}",
        ChartNoteKind.arrow =>
          "Arrow to ${n.who}${n.text.isEmpty ? "" : ": “${n.text}”"}",
        ChartNoteKind.bracket => "Bracket, ${n.who} to ${n.whom}",
      };

  // ---- charts_part_panels.dart --------------------------------------------
}

/// _ChartStage draws the chart as the canvas does, fitted, outlining what
/// is hovered and picked, and notes where each part was put.
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

/// _Field is a one-line field keeping its typing while the panel rebuilds.
class _Field extends StatefulWidget {
  final String text, hint;
  final ValueChanged<String> onChanged;

  /// words are live words a press puts in (chart_words.dart), as (button,
  /// inserted); [reads] what the field reads now.
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

/// startedChart is a new sheet chart set as a person would start: labelled
/// by the column naming its rows, showing its last numbers.
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

/// ColumnKind is what a sheet column holds, for the suggestions: numbers,
/// dates (rows come in runs of it, or headed so), or names.
enum ColumnKind { numbers, dates, names, empty }

List<ColumnKind> columnKinds(DataSheet sheet, CellRange range) {
  var datey = RegExp(r"date|week|month|year|day|time|season|round|period",
      caseSensitive: false);
  // A heading that is a date word itself ("Week", "Season 2025", "Year"),
  // not one that merely holds one ("Days injured").
  var dateHead = RegExp(
      r"^\s*(date|week|wk|month|year|yr|day|time|season|"
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
          // Whole numbers that count time (weeks 1 to 38, seasons, years) are
          // when, not how much, so a line can be drawn by season.
          var whole = numbers.length == values.length &&
              numbers.every((v) => v == v.roundToDouble());
          var years = whole && numbers.every((v) => v >= 1800 && v <= 2200);
          // A date word over years, or over small counts (weeks 1 to 38,
          // rounds, months): not over a club's matchday income.
          var counts = whole && numbers.every((v) => v >= 0 && v <= 60);
          return whole && ((dateHead.hasMatch(head) && counts) || years)
              ? ColumnKind.dates
              : ColumnKind.numbers;
        }
        var words = [for (var v in values) "$v"];
        // Runs: each value one block of rows, longer than one (weeks,
        // dates). Runs of words that are not dates ("Top four") are names.
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
/// makes (a kind, a way of reading the sheet, any highlights).
class ChartIdea {
  final String name, why, title;
  final ChartType type;
  final SheetLink link;
  final List<ChartHighlight> highlights;
  const ChartIdea(this.name, this.why, this.type, this.link,
      {this.title = "", this.highlights = const []});

  /// preview is the chart as it would look on its card, [like]'s size.
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
/// as, best fit first: a date with names and a number, a race, a line each,
/// totals; a date and a number, totals and averages; names and a number,
/// ranked bars, columns, a lollipop, a donut; two numbers, a scatter, side
/// by side, a slope.
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

/// _Thumb draws a suggestion's chart fitted to its card.
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
