import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/tabular_text.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/data_source_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/data_editor_shell.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// chart_data_editor.dart is the numbers behind a chart, in either of the two
// forms anybody wants them in.
//
// Pasted text is the fast way in and is why it was the only way for a while:
// copying a block out of a spreadsheet and getting a chart is the shortest
// path there is. It is a bad way to change one number in the middle of forty,
// which is the other thing people do to a chart all day -- so there is a grid
// as well, and a switch between them. The same ChartData either way; the grid
// writes values straight into it and the text goes through ChartData.parse.
//
// It is as wide as the sidebar and as tall as it has been dragged, both
// because a table crammed into a 240-pixel control with two visible lines is a
// table nobody can read.

/// ChartStyleDefaults is how the chart draws by default: the settings a
/// series falls back to until it has been given its own.
///
/// They were three groups of chart settings under the table -- Bars, Lines,
/// Points -- which asked anybody looking at a chart of bars with a line over
/// it to work out which group was about which half of it. The settings live
/// on the series now, behind that series' own button; what is left here is
/// the fallback, and the first series drawn a given way is what writes it.
/// So giving the first set of bars a square corner squares every other set
/// that has not been told otherwise, which is what "they inherit the first
/// one" means.
class ChartStyleDefaults {
  final double width;
  final double gap;
  final double corner;
  final bool smooth;
  final bool points;
  final double pointSize;
  final Color pointColor;

  const ChartStyleDefaults({
    this.width = 2,
    this.gap = 0.3,
    this.corner = 4,
    this.smooth = false,
    this.points = false,
    this.pointSize = 0,
    this.pointColor = const Color(0x00000000),
  });

  ChartStyleDefaults copyWith({
    double? width,
    double? gap,
    double? corner,
    bool? smooth,
    bool? points,
    double? pointSize,
    Color? pointColor,
  }) =>
      ChartStyleDefaults(
        width: width ?? this.width,
        gap: gap ?? this.gap,
        corner: corner ?? this.corner,
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

  /// sourceColumns are the columns a fetched source maps, where the chart has
  /// one, and [boundTo] is which of them each series is drawn from.
  ///
  /// Given so that the grid can say it: the series live here, and having to
  /// go to the Data source section to find out which column feeds series two
  /// is having the answer in a different room from the question. Empty for a
  /// chart whose numbers are typed, which is most of them.
  final List<SourceColumn> sourceColumns;
  final List<int> boundTo;

  /// sourceFields is everything the source is known to carry, mapped or not.
  ///
  /// Offered alongside the columns, so the answer to "what can this series
  /// be" is everything the source has rather than everything somebody has
  /// already mapped -- a coin comparison maps five columns out of twenty
  /// fields. Choosing one adds the column; see boundSeries.
  final List<String> sourceFields;

  /// names are what a category is likely to be, offered as somebody types
  /// one -- the coins a comparison can ask for. Empty unless the chart's rows
  /// are what its source is asked for. See DataPreset.rowNames.
  final List<String> names;

  /// onBind points one series at one of those columns.
  final void Function(int series, int column)? onBind;

  /// chartType is what the chart draws by default, so that a series row can
  /// leave out the settings its own kind of drawing has no use for -- a set
  /// of bars has no line to set the width of.
  final ChartType chartType;

  /// animated is whether the chart arrives at all, so the series rows only
  /// offer an arrival offset where there is an arrival to offset.
  final bool animated;

  /// showGrid and showSeries are which halves of this editor to build.
  ///
  /// Both, and it is the table with its series under it, which is what this
  /// was. The grid alone and the series alone are the same editor built
  /// twice, in two sections of the panel: the numbers in one and what each
  /// column is called in the other. Two widgets rather than two copies of the
  /// code, so the rows and the series cannot drift apart.
  final bool showGrid;
  final bool showSeries;

  /// elementId is which chart this is, so the grid's height is kept for this
  /// one rather than for charts in general. See CanvasDataEditorShell.scope.
  final String elementId;

  /// style is how the chart draws where a series has not been told
  /// otherwise, so a series' own field opens on what it is actually drawn at
  /// rather than on a nought that has to be decoded.
  final ChartStyleDefaults style;

  /// onStyleChanged writes that back, for the series that leads its kind of
  /// drawing. Null where the caller has no chart to write to, which is the
  /// editor standing on its own in a test.
  final ValueChanged<ChartStyleDefaults>? onStyleChanged;

  /// onChartType makes the first series' "Drawn as" the chart's own type.
  ///
  /// There was a Type dropdown at the top of the settings as well, and the
  /// two said the same thing in two places: a one-series chart set to bars
  /// with its series set to "As the chart" has one answer and two controls
  /// for it, and changing either made the other look wrong. Given, the first
  /// row *is* that control -- it offers every kind, including the circular
  /// ones no later series can be, and choosing one sets the chart. Null
  /// leaves every row a plain series row, which is what a table's editor and
  /// a bare one in a test want.
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

/// _typedIn is the choice that means this series is not drawn from the
/// source at all: whatever is in the grid is what it is.
const int _typedIn = -1;

class _ChartDataEditorState extends State<ChartDataEditor> {
  ChartData get data => widget.data;

  /// _openSeries is which series have their own settings showing.
  ///
  /// By position rather than by name, because a series has no id and its name
  /// is a field somebody is in the middle of typing. Closed again whenever a
  /// series is added or taken away, which is the only time a position means a
  /// different series.
  final Set<int> _openSeries = {};

  void _write(ChartData next) {
    widget.onChanged(next);
    widget.onCommit();
  }

  /// _withValue writes one cell, growing the series to reach it.
  ///
  /// Ragged data is normal here -- a series added to a chart that already has
  /// five rows has no values at all until somebody types them -- so a write
  /// past the end fills the gap rather than being refused.
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

  /// _addRow adds a category and a zero for it in every series.
  ///
  /// The zero matters. A row added without one leaves the series a value
  /// short, and the next row removed then takes a value that belongs to a
  /// different row -- so the numbers walk up the table one delete at a time.
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
    // Whatever was open is shut: the open set is positions, and adding or
    // removing a series is the one thing that makes a position mean a
    // different series.
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

  @override
  Widget build(BuildContext context) {
    // The series on their own, for the panel that shows them under the table
    // rather than inside it. A column of numbers and what that column is
    // called are two questions -- "are these the right figures" and "how
    // should this one look" -- and one box holding both is what made the
    // table section the longest thing in the panel.
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
      // The rows, plus the two header rows a chart's grid carries: the
      // series names and where each one comes from.
      wanted: (data.categories.length + 2) * 32 + 48,
      remember: "canvasChartData",
      // Per chart: a table of twenty rows wants a tall box and one of
      // three does not, and one height shared by every chart left a hole
      // under the small ones.
      scope: widget.elementId,
      gridTooltip: "Edit the numbers in a table",
      // "Raw table": what it shows is the table as text, and the switch is
      // read as a name for the thing it turns on rather than as a sentence
      // about editing.
      textTooltip: "Raw table",
      toolbar: [
        // The two ways a chart grows, side by side, because they are the
        // same kind of thing: a row is another category and a series is
        // another column of numbers against the same ones.
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
          // Clear of the table. The series rows are about the columns above
          // them, not another row of them, and butted up against the grid
          // they read as one more line of it.
          const SizedBox(height: 8),
          for (var i = 0; i < data.series.length; i++) _seriesRow(i),
        ],
      ],
    );
  }

  /// _seriesRow is one series: its name, how it is drawn, its colour and when
  /// it arrives, with the rest behind a button.
  ///
  /// Behind a button because the row is read far more often than it is
  /// changed. What anybody scans a list of series for is which one is which
  /// -- the name, the colour, the kind of drawing -- and every setting laid
  /// out beside those buried the answer in a thicket. Three series with five
  /// controls each is fifteen controls to look past.
  ///
  /// The arrival offset stays out on the row rather than going behind the
  /// button with the rest, because it is the one setting that is about this
  /// series *against the others*: it is set by looking down the column and
  /// comparing, which is not something you can do one flyout at a time.
  Widget _seriesRow(int i) {
    var series = data.series[i];
    var drawnAs = series.typeIn(widget.chartType);
    var stroked = _stroked(drawnAs);
    // Bars have settings of their own -- how far apart they stand and how
    // round their corners are -- so the button is not a line chart's alone.
    var settable = stroked || drawnAs.isBar;
    // The first series is what the rest are offset against, so it has none.
    var offsettable = widget.animated && i > 0;
    var open = _openSeries.contains(i);

    return Padding(
      // Clear of the series after it: a handful of controls run together into
      // one block unless the gap between series is bigger than the gap
      // between the lines of one.
      padding: EdgeInsets.only(bottom: i == data.series.length - 1 ? 16 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // A CanvasWrap rather than a Wrap, so the name and the kind grow
          // into a wide sidebar the way the settings under them do. A row that
          // fills the panel above a row of fixed boxes reads as two panels.
          CanvasWrap(children: [
            // An ordinary settings field rather than a grid cell. It sits in a
            // line of settings, not in a table: a cell is drawn to a table's
            // height and takes a table's typeface, which beside a dropdown is
            // a box half a caption short.
            CanvasTextField(
              key: ValueKey("seriesName$i"),
              label: i == 0 ? "Name" : "",
              value: series.name,
              // The least it will be, and small enough that the name, the
              // kind, the colour and the button all make one line of a narrow
              // sidebar. It grows into a wide one, so the floor only has to
              // hold a legend entry -- "Revenue", "2024" -- not a sentence.
              width: 56,
              onChanged: (v) {
                var out = [...data.series];
                out[i] = out[i].copyWith(name: v);
                widget.onChanged(data.copyWith(series: out));
              },
              onCommit: widget.onCommit,
            ),
            // The first row is the chart's own type where the caller has one
            // to set -- see onChartType. Every row after it is "As the chart"
            // or a kind of its own: a series that follows the chart keeps
            // following it when the chart is changed, which is what almost
            // every series wants.
            if (i == 0 && widget.onChartType != null)
              CanvasDropdown<String>(
                key: const ValueKey("chartType"),
                label: "Drawn as",
                value: widget.chartType.name,
                width: 96,
                options: [for (var t in ChartType.values) (t.name, t.label)],
                // The caller puts the series back to following the chart in
                // the same write. Left pinned to what it was, choosing a new
                // kind here would change the chart and draw the first series
                // the old way, which reads as the dropdown not working -- and
                // done as a second write from here it would be a write
                // against the element as it was before the first one.
                onChanged: (v) => widget.onChartType!(ChartType.fromName(v)),
              )
            else
              CanvasDropdown<String>(
                label: i == 0 ? "Drawn as" : "",
                value: series.type?.name ?? "",
                width: 96,
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
              // Held to the swatch's own width so the caption cannot be what
              // decides whether this row fits on one line.
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
                value: series.delay * 100,
                min: -100,
                max: 100,
                decimals: 0,
                width: 52,
                suffix: "%",
                onChanged: (v) =>
                    _writeSeries(i, series.copyWith(delay: v / 100)),
                onCommit: widget.onCommit,
              ),
            // Nothing behind the button for a series with nothing to set --
            // a set of bars takes its thickness from nowhere.
            // Not wrapped in _captioned: the button reserves the caption's
            // height itself, and reserving it twice put it a caption lower
            // than the controls it sits beside -- far enough that the middle
            // of it was empty space.
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

  /// _seriesSettings is what is behind one series' button: the settings that
  /// belong to the way *that* series is drawn, and nothing else.
  ///
  /// Which is the whole point of the button. A chart of bars with a line over
  /// it used to carry a Bars group, a Lines group and a Points group under
  /// the table, and working out which of them was about which half of the
  /// chart was left to the reader. Here the question and the answer are in
  /// the same place.
  List<Widget> _seriesSettings(int i, ChartSeries series, ChartType kind) {
    var style = widget.style;
    // The first series drawn this way owns the chart's own setting, so every
    // other series drawn the same way follows it until it is given its own.
    var leads = _firstDrawn(kind) == i;

    void writeStyle(ChartStyleDefaults next) {
      widget.onStyleChanged?.call(next);
      widget.onCommit();
    }

    if (kind.isBar) {
      return [
        // Only on the series that leads: the bars all stand in the same
        // slots, so how wide those slots are is one number for the chart and
        // not one per series. It is here rather than in a group of its own
        // because this is where somebody shaping the bars is standing.
        if (leads)
          CanvasNumberField(
            key: ValueKey("seriesGap$i"),
            // "Spacing" rather than "Gap": the animation section has a Gap of
            // its own -- how much one item's arrival overlaps the next -- and
            // two settings called Gap in one panel is one too many.
            label: "Spacing",
            value: style.gap,
            min: 0,
            max: 0.9,
            decimals: 2,
            width: 58,
            onChanged: (v) => writeStyle(style.copyWith(gap: v)),
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
        CanvasHint(leads
            ? "How the bars are shaped. Spacing is the gap between one "
                "category and the next, and every other set of bars on this "
                "chart takes these until it is given its own."
            : "How round this set of bars is. It follows the first set until "
                "it is changed here."),
      ];
    }

    return [
      CanvasNumberField(
        key: ValueKey("seriesWidth$i"),
        label: "Width",
        // The width it is actually drawn at, so the field is never a bare
        // nought that has to be decoded.
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
      // Nothing to curve on a scatter, which is unconnected by definition.
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
            // Nought is a real answer -- take the line's own weight -- so the
            // field opens on it rather than on the weight it works out to.
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
            // The series' own colour until one is chosen, which is what a dot
            // on a line is unless somebody says otherwise.
            color: series.pointColorOn(style.pointColor).a > 0
                ? series.pointColorOn(style.pointColor)
                : series.color,
            onChanged: (c) => leads
                ? writeStyle(style.copyWith(pointColor: c))
                : _writeSeries(i, series.copyWith(pointColor: c)),
          ),
        ],
      ],
      CanvasHint(leads
          ? "How this series is drawn. Every other series drawn the same way "
              "takes these until it is given its own."
          : "How this series is drawn. It follows the first series drawn the "
              "same way until it is changed here."),
    ];
  }

  /// _firstDrawn is the first series drawn the same way as [kind]: the one
  /// whose settings the rest of that kind follow.
  ///
  /// By kind rather than by position, because a chart of bars with a line
  /// over it has two firsts -- the first set of bars and the first line --
  /// and each leads its own.
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

  /// _grip drags the editor taller or shorter.
  /// _raw is the whole table as one block of text, in the tab or comma
  /// separated form a spreadsheet copies.
  Widget _raw() => CanvasGridCell(
        value: data.asText(),
        multiline: true,
        hint: "Name\tSeries\nWeek 1\t120",
        // Parsed against the series it is replacing, so editing the numbers
        // does not throw away a series' colour or the fact that it was drawn
        // as a line.
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

    const nameWidth = 86.0;

    const valueWidth = 62.0;

    Widget header() => Row(children: [
          const SizedBox(width: nameWidth + 4),
          for (var s = 0; s < data.series.length; s++)
            Padding(
              padding: const EdgeInsets.only(right: 4, bottom: 3),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: valueWidth,
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
                // Against the column it removes, which is the only place a
                // "remove this series" control is unambiguous -- a list of
                // them somewhere else is a list of names to match up.
                CanvasIconButton(
                  icon: Icons.close,
                  tooltip: "Remove this series",
                  onPressed: () => _removeSeries(s),
                ),
              ]),
            ),
        ]);

    /// bindings is a row of "where does this series come from", under the
    /// names. Only for a chart with a fetched source: a chart of typed
    /// numbers has nowhere for a series to come from but the grid itself.
    Widget bindings() => Row(children: [
          const SizedBox(width: nameWidth + 4),
          for (var s = 0; s < data.series.length; s++)
            Padding(
              padding: const EdgeInsets.only(right: 4, bottom: 4),
              child: SizedBox(
                width: valueWidth + 30,
                child: CanvasDropdown<int>(
                  key: ValueKey("chartGridSeries$s"),
                  label: "From",
                  value:
                      s < widget.boundTo.length ? widget.boundTo[s] : _typedIn,
                  width: valueWidth + 30,
                  options: [
                    (_typedIn, "Typed in"),
                    for (var (c, column) in widget.sourceColumns.indexed)
                      (
                        c,
                        column.header.isEmpty
                            ? "Column ${c + 1}"
                            : column.header
                      ),
                    // The fields with no column yet, numbered past the end of
                    // the mapping exactly as the Data source panel numbers
                    // them -- see spareFields, which both ask.
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
            width: nameWidth,
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
          const SizedBox(width: 4),
          for (var s = 0; s < data.series.length; s++)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: SizedBox(
                width: valueWidth,
                child: CanvasGridCell(
                  value: _number(data.valueAt(s, i)),
                  dense: true,
                  // Through cellNumber rather than tryParse, so a figure
                  // pasted or typed the way it is written -- 222,203 or 45% --
                  // is the number it plainly is. Refusing the separators and
                  // charting a nought is the sort of wrong that looks like
                  // the chart's fault rather than the typing's.
                  // A cell cleared out is a cell nobody has filled in, not a
                  // nought: the chart leaves a hole there rather than drawing
                  // a bar of no height or a line straight across. Anything
                  // else that will not parse is still a nought, which is what
                  // a stray word in a pasted column has always been.
                  onChanged: (v) => _withValue(s, i,
                      v.trim().isEmpty ? missingValue : cellNumber(v) ?? 0),
                  onCommit: widget.onCommit,
                ),
              ),
            ),
          // Whether this row's figures were looked up or worked out. On the
          // row because that is where the doubt lives: a year is sourced or
          // it is not, and when it is not, every figure in the row came out
          // of the same arithmetic.
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

    // Both ways, because a chart with eight series is wider than any sidebar
    // and a chart with forty rows is taller than any panel.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
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
