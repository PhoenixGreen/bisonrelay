import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/tabular_text.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/data_source_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/data/data_editor_shell.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// chart_data_editor.dart is a chart's numbers as pasted text or a grid,
// one ChartData either way (the text through ChartData.parse).

/// ChartStyleDefaults is how the chart draws by default: what a series
/// falls back to until it has its own. The first series drawn a given way
/// writes them, so squaring one set of bars' corners squares every set not
/// told otherwise.
class ChartStyleDefaults {
  final double width;
  final double gap;
  final double corner;

  /// floor is the least height a bar is drawn at. See ChartElement.barFloor.
  final double floor;
  final bool smooth;
  final bool points;
  final double pointSize;
  final Color pointColor;

  const ChartStyleDefaults({
    this.width = 2,
    this.gap = 0.3,
    this.corner = 4,
    this.floor = 0,
    this.smooth = false,
    this.points = false,
    this.pointSize = 0,
    this.pointColor = const Color(0x00000000),
  });

  ChartStyleDefaults copyWith({
    double? width,
    double? gap,
    double? corner,
    double? floor,
    bool? smooth,
    bool? points,
    double? pointSize,
    Color? pointColor,
  }) =>
      ChartStyleDefaults(
        width: width ?? this.width,
        gap: gap ?? this.gap,
        corner: corner ?? this.corner,
        floor: floor ?? this.floor,
        smooth: smooth ?? this.smooth,
        points: points ?? this.points,
        pointSize: pointSize ?? this.pointSize,
        pointColor: pointColor ?? this.pointColor,
      );
}

class ChartDataEditor extends StatefulWidget {
  final ChartData data;

  /// onChanged is a change to keep. The caller opens the undo step.
  final ValueChanged<ChartData> onChanged;
  final VoidCallback onCommit;

  /// sourceColumns are a fetched source's mapped columns, [boundTo] which
  /// each series draws from; empty for typed numbers.
  final List<SourceColumn> sourceColumns;
  final List<int> boundTo;

  /// sourceFields is all the source carries, mapped or not, offered beside
  /// the columns; choosing one adds it (see boundSeries).
  final List<String> sourceFields;

  /// names are likely category names, offered while typing, where the rows
  /// are what the source is asked for (DataPreset.rowNames).
  final List<String> names;

  /// onBind points one series at one of those columns.
  final void Function(int series, int column)? onBind;

  /// chartType is what the chart draws by default, so a series row can leave
  /// out settings its kind has no use for.
  final ChartType chartType;

  /// animated is whether the chart arrives at all, so the series rows offer
  /// an arrival offset only where there is one.
  final bool animated;

  /// showGrid and showSeries are which halves to build: both, or one as a
  /// panel section, sharing code so they cannot drift apart.
  final bool showGrid;
  final bool showSeries;

  /// elementId is which chart this is, so the grid's height is kept per
  /// chart. See CanvasDataEditorShell.scope.
  final String elementId;

  /// style is how the chart draws where a series has not been told otherwise,
  /// so a series' own field opens on its drawn value, not a nought.
  final ChartStyleDefaults style;

  /// onStyleChanged writes that back, for the series that leads its kind of
  /// drawing. Null where there is no chart to write to (a test).
  final ValueChanged<ChartStyleDefaults>? onStyleChanged;

  /// onChartType makes the first series' "Drawn as" the chart's own type
  /// (every kind, circular too); null leaves plain series rows.
  final ValueChanged<ChartType>? onChartType;

  const ChartDataEditor({
    required this.data,
    required this.onChanged,
    required this.onCommit,
    this.chartType = ChartType.line,
    this.animated = false,
    this.elementId = "",
    this.showGrid = true,
    this.showSeries = true,
    this.style = const ChartStyleDefaults(),
    this.onStyleChanged,
    this.onChartType,
    this.sourceColumns = const [],
    this.boundTo = const [],
    this.sourceFields = const [],
    this.names = const [],
    this.onBind,
    super.key,
  });

  @override
  State<ChartDataEditor> createState() => _ChartDataEditorState();
}

/// _typedIn is the choice meaning this series is not drawn from the source:
/// what is in the grid is what it is.
const int _typedIn = -1;

class _ChartDataEditorState extends State<ChartDataEditor> {
  ChartData get data => widget.data;

  /// _openSeries is which series have their settings showing, by position,
  /// since a series has no id and its name may be mid-edit. Cleared whenever
  /// a series is added or removed, which changes what a position means.
  final Set<int> _openSeries = {};

  void _write(ChartData next) {
    widget.onChanged(next);
    widget.onCommit();
  }

  /// _withValue writes one cell, growing the series to reach it: ragged data
  /// is normal, so a write past the end fills the gap.
  void _withValue(int series, int row, double value) {
    var out = [...data.series];
    var values = [...out[series].values];
    while (values.length <= row) {
      values.add(0);
    }
    values[row] = value;
    out[series] = out[series].copyWith(values: values);
    _write(data.copyWith(series: out));
  }

  /// _addRow adds a category with a zero in every series: a value short,
  /// the next row removed would take a value from another row.
  void _addRow() {
    _write(data.copyWith(
      categories: [...data.categories, "Row ${data.categories.length + 1}"],
      series: [
        for (var s in data.series)
          s.copyWith(values: [
            ...s.values,
            for (var i = s.values.length; i <= data.categories.length; i++) 0.0,
          ]),
      ],
    ));
  }

  void _addSeries() {
    // See _openSeries.
    _openSeries.clear();
    var series = [...data.series];
    series.add(ChartSeries(
      name: "Series ${series.length + 1}",
      color: chartPalette[series.length % chartPalette.length],
      values: List.filled(data.categories.length, 0),
    ));
    _write(data.copyWith(series: series));
  }

  void _removeSeries(int index) {
    _openSeries.clear();
    var series = [...data.series]..removeAt(index);
    _write(data.copyWith(series: series));
  }

  void _writeSeries(int index, ChartSeries next) {
    var series = [...data.series];
    series[index] = next;
    _write(data.copyWith(series: series));
  }

  void _removeRow(int row) => _write(data.withRowRemoved(row));

  /// _moveRow and _moveSeries reorder the grid by taking out and putting
  /// back, which is right in both directions.
  void _moveRow(int row, int by) {
    var to = row + by;
    if (to < 0 || to >= data.categories.length) return;

    List<T> shifted<T>(List<T> list) {
      if (row >= list.length) return list;
      var out = [...list];
      out.insert(to.clamp(0, out.length - 1), out.removeAt(row));
      return out;
    }

    var estimated = [...data.estimated];
    while (estimated.isNotEmpty && estimated.length < data.categories.length) {
      estimated.add(false);
    }
    _write(data.copyWith(
      categories: shifted(data.categories),
      // Every series' values move with the row: one reading each.
      series: [
        for (var s in data.series) s.copyWith(values: shifted(s.values))
      ],
      estimated: shifted(estimated),
    ));
  }

  void _moveSeries(int series, int by) {
    var to = series + by;
    if (to < 0 || to >= data.series.length) return;
    _openSeries.clear();
    var out = [...data.series];
    out.insert(to, out.removeAt(series));
    _write(data.copyWith(series: out));
  }

  // At the ordinary size inside a card: card-sized buttons overran a
  // grid with buttons over each column.
  @override
  Widget build(BuildContext context) =>
      CanvasCards.none(Builder(builder: _build));

  Widget _build(BuildContext context) {
    // The series alone, for the panel showing them under the table.
    if (!widget.showGrid) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < data.series.length; i++) _seriesRow(i),
        ],
      );
    }
    return CanvasDataEditorShell(
      // The rows, plus two header rows: series names and sources.
      wanted: (data.categories.length + 2) * 32 + 48,
      remember: "canvasChartData",
      // Per chart: twenty rows want a tall box, three do not.
      scope: widget.elementId,
      gridTooltip: "Edit the numbers in a table",
      textTooltip: "Raw table",
      toolbar: [
        // The two ways a chart grows: a category, or a series.
        CanvasIconButton(
          icon: Icons.add,
          tooltip: "Add a row",
          onPressed: _addRow,
        ),
        CanvasIconButton(
          icon: Icons.add_chart,
          tooltip: "Add a series — give it its own type below to lay one "
              "kind of chart over another",
          onPressed: _addSeries,
        ),
      ],
      text: (_) => _raw(),
      grid: (context) => _table(ThemeNotifier.of(context)),
      below: [
        if (widget.showSeries) ...[
          // Clear of the table, so they do not read as a row.
          const SizedBox(height: 8),
          for (var i = 0; i < data.series.length; i++) _seriesRow(i),
        ],
      ],
    );
  }

  /// _seriesRow is one series: name, how it is drawn, colour and arrival
  /// offset, the rest behind a button since the row is read far more than
  /// changed. The offset stays on the row, as it is set by comparing series
  /// down the column.
  Widget _seriesRow(int i) {
    var series = data.series[i];
    var drawnAs = series.typeIn(widget.chartType);
    var stroked = _stroked(drawnAs);
    // Bars have settings too (spacing, corners).
    var settable = stroked || drawnAs.isBar;
    // The first series is what the rest are offset against, so it has none.
    var offsettable = widget.animated && i > 0;
    var open = _openSeries.contains(i);

    return Padding(
      // The gap between series is bigger than between the lines of one, so
      // each reads as its own block.
      padding: EdgeInsets.only(bottom: i == data.series.length - 1 ? 16 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // A CanvasWrap, so the name and the kind grow into a wide sidebar as
          // the settings under them do.
          CanvasWrap(children: [
            // A settings field, not a grid cell, which is drawn to a table's
            // height and looks short beside a dropdown.
            CanvasTextField(
              key: ValueKey("seriesName$i"),
              label: i == 0 ? "Name" : "",
              value: series.name,
              // The least it will be, so name, kind, colour and button make one
              // line of a narrow sidebar.
              width: 50,
              onChanged: (v) {
                var out = [...data.series];
                out[i] = out[i].copyWith(name: v);
                widget.onChanged(data.copyWith(series: out));
              },
              onCommit: widget.onCommit,
            ),
            // The first row is the chart's own type where the caller sets one
            // (see onChartType); every later row is "As the chart" or its own
            // kind, and one following the chart keeps following it.
            if (i == 0 && widget.onChartType != null)
              CanvasDropdown<String>(
                key: const ValueKey("chartType"),
                label: "Drawn as",
                value: widget.chartType.name,
                width: 90,
                options: [for (var t in ChartType.values) (t.name, t.label)],
                // The caller puts the series back to following the chart in the
                // same write: left pinned, the first series would draw the old
                // way, and a second write would be against the element as it
                // was.
                onChanged: (v) => widget.onChartType!(ChartType.fromName(v)),
              )
            else
              CanvasDropdown<String>(
                label: i == 0 ? "Drawn as" : "",
                value: series.type?.name ?? "",
                width: 90,
                options: [
                  ("", "As the chart"),
                  for (var t in ChartType.values)
                    if (!t.isCircular) (t.name, t.label),
                ],
                onChanged: (v) => _writeSeries(
                    i,
                    v.isEmpty
                        ? series.copyWith(followChart: true)
                        : series.copyWith(type: ChartType.fromName(v))),
              ),
            CanvasColorButton(
              label: i == 0 ? "Colour" : "",
              // Held to the swatch's width so the caption cannot decide whether
              // this row fits on one line.
              labelWidth: 30,
              color: series.color,
              gradient: series.gradient,
              onChanged: (c) => _writeSeries(i, series.copyWith(color: c)),
              onGradientChanged: (g) => _writeSeries(
                  i,
                  g == null
                      ? series.copyWith(oneColour: true)
                      : series.copyWith(gradient: g)),
            ),
            if (offsettable)
              CanvasNumberField(
                key: ValueKey("seriesDelay$i"),
                label: i == 1 ? "Offset" : "",
                value: series.delay,
                min: -maxSeriesDelay,
                max: maxSeriesDelay,
                // Seconds, to a tenth: as fine as lining two series up needs.
                decimals: 1,
                step: 0.1,
                width: 58,
                suffix: "s",
                onChanged: (v) => _writeSeries(i, series.copyWith(delay: v)),
                onCommit: widget.onCommit,
              ),
            // Nothing behind the button for a series with nothing to set. Not
            // in _captioned: the button reserves the caption's height itself,
            // and reserving it twice puts it a caption low.
            if (settable)
              CanvasIconButton(
                key: ValueKey("seriesMore$i"),
                icon: open ? Icons.expand_less : Icons.tune,
                tooltip: open
                    ? "Hide this series' settings"
                    : "This series' own settings",
                onPressed: () => setState(
                    () => open ? _openSeries.remove(i) : _openSeries.add(i)),
              ),
          ]),
          if (open && settable) ...[
            const SizedBox(height: 4),
            CanvasWrap(children: _seriesSettings(i, series, drawnAs)),
          ],
        ],
      ),
    );
  }

  /// _seriesSettings is what is behind one series' button: the settings for
  /// the way that series is drawn, and nothing else.
  List<Widget> _seriesSettings(int i, ChartSeries series, ChartType kind) {
    var style = widget.style;
    // The first series drawn this way owns the chart's setting, so every
    // other series drawn the same way follows it until given its own.
    var leads = _firstDrawn(kind) == i;

    /// writeStyle writes the chart's own setting, which the leading series'
    /// controls change, and clears that series' overrides in the same write:
    /// leading means "my settings are the chart's", and an override left on
    /// top would keep winning, making the control look dead.
    void writeStyle(ChartStyleDefaults next) {
      widget.onStyleChanged?.call(next);
      if (series.width != 0 ||
          series.corner != null ||
          series.smooth != null ||
          series.points != null ||
          series.pointSize != null ||
          series.pointColor != null) {
        var out = [...data.series];
        out[i] = series.copyWith(drawnLikeChart: true);
        widget.onChanged(data.copyWith(series: out));
      }
      widget.onCommit();
    }

    if (kind.isBar) {
      return [
        // Only on the leading series: the bars stand in the same slots, so
        // their width is one number for the chart.
        if (leads)
          CanvasNumberField(
            key: ValueKey("seriesGap$i"),
            // "Spacing", not "Gap": the animation section has a Gap of its own.
            label: "Spacing",
            value: style.gap,
            min: 0,
            max: 0.9,
            decimals: 2,
            width: 58,
            onChanged: (v) => writeStyle(style.copyWith(gap: v)),
            onCommit: widget.onCommit,
          ),
        // Also only on the leading series: the floor is the chart's.
        if (leads)
          CanvasNumberField(
            key: ValueKey("seriesFloor$i"),
            label: "Least",
            value: style.floor,
            min: 0,
            max: 20,
            decimals: 0,
            width: 50,
            onChanged: (v) => writeStyle(style.copyWith(floor: v)),
            onCommit: widget.onCommit,
          ),
        CanvasNumberField(
          key: ValueKey("seriesCorner$i"),
          label: "Corner",
          value: series.cornerOn(style.corner),
          min: 0,
          max: 100,
          width: 54,
          onChanged: (v) => leads
              ? writeStyle(style.copyWith(corner: v))
              : _writeSeries(i, series.copyWith(corner: v)),
          onCommit: widget.onCommit,
        ),
        // A panel behind each of this series' bars, per series: a track
        // behind one set and not another is the usual reason to want one.
        const CanvasLineBreak(),
        CanvasToggle(
          key: ValueKey("seriesBackdrop$i"),
          label: "Background",
          value: series.backdrop?.on ?? false,
          onChanged: (v) => _writeSeries(
              i,
              series.copyWith(
                  backdrop: (series.backdrop ?? const ChartBackdrop())
                      .copyWith(on: v))),
        ),
        if (series.backdrop?.on ?? false)
          ..._backdropSettings(i, series, series.backdrop!),
        const CanvasLineBreak(),
        CanvasHint(leads
            ? "How the bars are shaped. Spacing is the gap between one "
                "category and the next. Least is the smallest a bar is ever "
                "drawn, in pixels: at 0 a reading of nought has no height and "
                "so no pixels, which looks exactly like a year nobody has a "
                "figure for — a pixel or two says \"measured, and it was "
                "nothing\". Every other set of bars on this chart takes these "
                "until it is given its own."
            : "How round this set of bars is. It follows the first set until "
                "it is changed here."),
      ];
    }

    return [
      CanvasNumberField(
        key: ValueKey("seriesWidth$i"),
        label: "Width",
        // The width it is drawn at, never a bare nought.
        value: series.widthOn(style.width),
        min: 0.5,
        max: 40,
        decimals: 1,
        width: 54,
        onChanged: (v) => leads
            ? writeStyle(style.copyWith(width: v))
            : _writeSeries(i, series.copyWith(width: v)),
        onCommit: widget.onCommit,
      ),
      // A stroke, dashes or dots, per series (a projection beside a
      // measurement). A scatter is dots already.
      if (kind.usesSmooth)
        CanvasDropdown<ChartLineStyle>(
          key: ValueKey("seriesLineStyle$i"),
          label: "Line",
          value: series.lineStyle,
          width: 78,
          options: [for (var v in ChartLineStyle.values) (v, v.label)],
          onChanged: (v) => _writeSeries(i, series.copyWith(lineStyle: v)),
        ),
      // The space between this line and the next, where there is a next.
      if (kind.usesSmooth && i < data.series.length - 1)
        CanvasToggle(
          key: ValueKey("seriesBand$i"),
          label: "Band",
          value: series.band,
          onChanged: (v) => _writeSeries(i, series.copyWith(band: v)),
        ),
      // Nothing to curve on a scatter, which is unconnected.
      if (kind.usesSmooth)
        CanvasToggle(
          key: ValueKey("seriesSmooth$i"),
          label: "Smooth",
          value: series.smoothOn(style.smooth),
          onChanged: (v) => leads
              ? writeStyle(style.copyWith(smooth: v))
              : _writeSeries(i, series.copyWith(smooth: v)),
        ),
      // A scatter is dots already, so there is nothing to mark.
      if (kind.usesSmooth) ...[
        CanvasToggle(
          key: ValueKey("seriesPoints$i"),
          label: "Points",
          value: series.pointsOn(style.points),
          onChanged: (v) => leads
              ? writeStyle(style.copyWith(points: v))
              : _writeSeries(i, series.copyWith(points: v)),
        ),
        if (series.pointsOn(style.points)) ...[
          CanvasNumberField(
            key: ValueKey("seriesPointSize$i"),
            label: "Size",
            // Nought is a real answer (take the line's weight), so the field
            // opens on it rather than the weight it works out to.
            value: series.pointSizeOn(style.pointSize),
            min: 0,
            max: 60,
            decimals: 1,
            width: 54,
            onChanged: (v) => leads
                ? writeStyle(style.copyWith(pointSize: v))
                : _writeSeries(i, series.copyWith(pointSize: v)),
            onCommit: widget.onCommit,
          ),
          CanvasColorButton(
            key: ValueKey("seriesPointColour$i"),
            label: "Dots",
            // The series' own colour until one is chosen.
            color: series.pointColorOn(style.pointColor).a > 0
                ? series.pointColorOn(style.pointColor)
                : series.color,
            onChanged: (c) => leads
                ? writeStyle(style.copyWith(pointColor: c))
                : _writeSeries(i, series.copyWith(pointColor: c)),
          ),
        ],
      ],
      CanvasHint("${leads ? "How this series is drawn. Every other series "
              "drawn the same way takes these until it is given its own." : "How this series is drawn. It follows the first series drawn "
              "the same way until it is changed here."} "
          "Line is this one's own either way: solid, dashed or dotted says "
          "what kind of thing it is — a projection beside a measurement — "
          "which is a different question from whether a year's figure was "
          "worked out."
          "${i < data.series.length - 1 ? " Band fills the space between this "
              "line and the next one down the list, fading from this "
              "colour into that one's." : ""}"),
    ];
  }

  /// _backdropSettings are the controls for the panel behind one series'
  /// bars, shown while it is switched on.
  List<Widget> _backdropSettings(int i, ChartSeries series, ChartBackdrop b) {
    void set(ChartBackdrop next) =>
        _writeSeries(i, series.copyWith(backdrop: next));
    // Three lines: the switch, size and growth, then paint.
    return [
      const CanvasLineBreak(),
      CanvasNumberField(
        key: ValueKey("seriesBackdropHeight$i"),
        label: "Height",
        // A share of the chart's height, as a percentage: 100 reaches the
        // top of the plot, more stands above it.
        value: b.height * 100,
        min: 0,
        max: maxBackdropHeight * 100,
        decimals: 0,
        width: 58,
        suffix: "%",
        onChanged: (v) => set(b.copyWith(height: v / 100)),
        onCommit: widget.onCommit,
      ),
      CanvasNumberField(
        key: ValueKey("seriesBackdropWidth$i"),
        label: "Width",
        // A share of the bar's own thickness: 100 is exactly as wide.
        value: b.width * 100,
        min: 10,
        max: 400,
        decimals: 0,
        width: 58,
        suffix: "%",
        onChanged: (v) => set(b.copyWith(width: v / 100)),
        onCommit: widget.onCommit,
      ),
      CanvasDropdown<ChartBackdropGrow>(
        key: ValueKey("seriesBackdropGrow$i"),
        label: "Grow from",
        value: b.grow,
        width: 78,
        options: [for (var v in ChartBackdropGrow.values) (v, v.label)],
        onChanged: (v) => set(b.copyWith(grow: v)),
      ),
      const CanvasLineBreak(),
      CanvasColorButton(
        key: ValueKey("seriesBackdropFill$i"),
        label: "Fill",
        color: b.fill,
        onChanged: (c) => set(b.copyWith(fill: c)),
      ),
      CanvasColorButton(
        key: ValueKey("seriesBackdropBorder$i"),
        label: "Border",
        color: b.border,
        onChanged: (c) => set(b.copyWith(border: c)),
      ),
      CanvasNumberField(
        key: ValueKey("seriesBackdropBorderWidth$i"),
        label: "Border width",
        value: b.borderWidth,
        min: 0,
        max: 40,
        decimals: 1,
        width: 54,
        onChanged: (v) => set(b.copyWith(borderWidth: v)),
        onCommit: widget.onCommit,
      ),
      CanvasNumberField(
        key: ValueKey("seriesBackdropRadius$i"),
        label: "Radius",
        value: b.radius,
        min: 0,
        max: 200,
        decimals: 0,
        width: 54,
        onChanged: (v) => set(b.copyWith(radius: v)),
        onCommit: widget.onCommit,
      ),
    ];
  }

  /// _firstDrawn is the first series drawn the same way as [kind], whose
  /// settings the rest of that kind follow. By kind, not position: bars with
  /// a line over them have two firsts, each leading its own.
  int _firstDrawn(ChartType kind) {
    for (var i = 0; i < data.series.length; i++) {
      var drawn = data.series[i].typeIn(widget.chartType);
      if (kind.isBar ? drawn.isBar : _stroked(drawn)) return i;
    }
    return -1;
  }

  /// _stroked is whether a kind of drawing has a line whose width can be set.
  bool _stroked(ChartType type) =>
      type == ChartType.line ||
      type == ChartType.area ||
      type == ChartType.scatter ||
      type == ChartType.radar;

  /// _raw is the whole table as one block, as a spreadsheet copies it.
  Widget _raw() => CanvasGridCell(
        value: data.asText(),
        multiline: true,
        hint: "Name\tSeries\nWeek 1\t120",
        // Parsed against the series it replaces, so editing the numbers
        // keeps each series' colour and kind.
        onChanged: (text) =>
            widget.onChanged(ChartData.parse(text, keep: data.series)),
        onCommit: widget.onCommit,
      );

  /// _table is the grid: a column of category names and one column per series.
  Widget _table(ThemeNotifier theme) {
    if (data.series.isEmpty) {
      return Center(
        child: Text("No series yet",
            style:
                TextStyle(fontSize: 11, color: theme.colors.onSurfaceVariant)),
      );
    }

    // One width for every column, so a series' buttons, name, source and
    // numbers line up, as in the table element's grid.
    const columnWidth = 92.0;
    const columnGap = 4.0;

    /// actions is a row of buttons standing in one column's width.
    Widget actions(List<Widget> buttons) => SizedBox(
          width: columnWidth + columnGap,
          child: Row(mainAxisSize: MainAxisSize.min, children: buttons),
        );

    // A row of buttons over the columns, a series' by its column.
    Widget columnButtons() => Row(children: [
          const SizedBox(width: columnWidth + columnGap),
          for (var s = 0; s < data.series.length; s++)
            actions([
              CanvasIconButton(
                key: ValueKey("seriesLeft$s"),
                icon: Icons.chevron_left,
                tooltip: "Move this series left",
                onPressed: s == 0 ? null : () => _moveSeries(s, -1),
              ),
              CanvasIconButton(
                key: ValueKey("seriesRight$s"),
                icon: Icons.chevron_right,
                tooltip: "Move this series right",
                onPressed: s == data.series.length - 1
                    ? null
                    : () => _moveSeries(s, 1),
              ),
              CanvasIconButton(
                icon: Icons.close,
                tooltip: "Remove this series",
                onPressed: () => _removeSeries(s),
              ),
            ]),
        ]);

    Widget header() => Row(children: [
          const SizedBox(width: columnWidth + columnGap),
          for (var s = 0; s < data.series.length; s++)
            Padding(
              padding: const EdgeInsets.only(right: columnGap, bottom: 3),
              child: SizedBox(
                width: columnWidth,
                child: CanvasGridCell(
                  value: data.series[s].name,
                  dense: true,
                  onChanged: (v) {
                    var out = [...data.series];
                    out[s] = out[s].copyWith(name: v);
                    widget.onChanged(data.copyWith(series: out));
                  },
                  onCommit: widget.onCommit,
                ),
              ),
            ),
        ]);

    /// bindings is a row of "where does this series come from" under the
    /// names, for a chart with a fetched source.
    Widget bindings() => Row(children: [
          const SizedBox(width: columnWidth + columnGap),
          for (var s = 0; s < data.series.length; s++)
            Padding(
              padding: const EdgeInsets.only(right: columnGap, bottom: 4),
              child: SizedBox(
                width: columnWidth,
                child: CanvasDropdown<int>(
                  key: ValueKey("chartGridSeries$s"),
                  label: "",
                  value:
                      s < widget.boundTo.length ? widget.boundTo[s] : _typedIn,
                  width: columnWidth,
                  grow: false,
                  options: [
                    (_typedIn, "Typed in"),
                    for (var (c, column) in widget.sourceColumns.indexed)
                      (
                        c,
                        column.header.isEmpty
                            ? "Column ${c + 1}"
                            : column.header
                      ),
                    // Unmapped fields, numbered on as the Data source
                    // panel numbers them (see spareFields).
                    for (var (i, field) in spareFields(
                            widget.sourceColumns, widget.sourceFields)
                        .indexed)
                      (widget.sourceColumns.length + i, field),
                  ],
                  onChanged: (c) => widget.onBind!(s, c),
                ),
              ),
            ),
        ]);

    Widget row(int i) => Row(children: [
          SizedBox(
            width: columnWidth,
            child: CanvasGridCell(
              value: data.categories[i],
              dense: true,
              suggestions: widget.names,
              onChanged: (v) {
                var out = [...data.categories];
                out[i] = v;
                widget.onChanged(data.copyWith(categories: out));
              },
              onCommit: widget.onCommit,
            ),
          ),
          const SizedBox(width: columnGap),
          for (var s = 0; s < data.series.length; s++)
            Padding(
              padding: const EdgeInsets.only(right: columnGap),
              child: SizedBox(
                width: columnWidth,
                child: CanvasGridCell(
                  value: _number(data.valueAt(s, i)),
                  dense: true,
                  // Through cellNumber, not tryParse, so 222,203 or 45% is the
                  // number it plainly is. A cleared cell is a hole in the
                  // chart, not a nought; anything else unparseable is a nought.
                  onChanged: (v) => _withValue(s, i,
                      v.trim().isEmpty ? missingValue : cellNumber(v) ?? 0),
                  onCommit: widget.onCommit,
                ),
              ),
            ),
          // The row's own buttons on the end, where the table element's are.
          CanvasIconButton(
            key: ValueKey("rowUp$i"),
            icon: Icons.keyboard_arrow_up,
            tooltip: "Move this row up",
            onPressed: i == 0 ? null : () => _moveRow(i, -1),
          ),
          CanvasIconButton(
            key: ValueKey("rowDown$i"),
            icon: Icons.keyboard_arrow_down,
            tooltip: "Move this row down",
            onPressed:
                i == data.categories.length - 1 ? null : () => _moveRow(i, 1),
          ),
          // Whether this row's figures were looked up or worked out: on the
          // row, since a year is sourced or it is not.
          CanvasIconButton(
            key: ValueKey("rowEstimated$i"),
            icon: data.isEstimated(i)
                ? Icons.auto_graph
                : Icons.check_circle_outline,
            tooltip: data.isEstimated(i)
                ? "Worked out, not looked up — drawn faint and dashed"
                : "Looked up. Press to mark it as an estimate",
            active: data.isEstimated(i),
            onPressed: () =>
                _write(data.withEstimated(i, !data.isEstimated(i))),
          ),
          CanvasIconButton(
            icon: Icons.close,
            tooltip: "Remove this row",
            onPressed: () => _removeRow(i),
          ),
        ]);

    // Both ways: eight series and forty rows outgrow any panel.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            columnButtons(),
            header(),
            if (widget.onBind != null && widget.sourceColumns.isNotEmpty)
              bindings(),
            for (var i = 0; i < data.categories.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: row(i),
              ),
          ],
        ),
      ),
    );
  }

  static String _number(double v) => v.isNaN
      ? ""
      : v == v.roundToDouble()
          ? v.round().toString()
          : v.toString();
}
