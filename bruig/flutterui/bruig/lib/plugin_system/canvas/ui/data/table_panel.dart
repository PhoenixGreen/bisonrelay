part of 'data_table_design.dart';

// The panel: the Studio's sidebar, the part picked in its header, the panels
// for a new table and its rows, and the controls they share. Part of
// _TableDesignState: its fields, lifecycle and build are in
// data_table_design.dart.

extension _TablePanel on _TableDesignState {
  /// _trail is the way to what is picked, from the table.
  List<TablePart> get _trail {
    var trail = <TablePart>[TablePart.table];
    if (_picked.kind == TablePartKind.cell) {
      trail.add(TablePart.column(_picked.col));
    }
    if (_picked != TablePart.table) trail.add(_picked);
    return trail;
  }

  Widget _panel(BuildContext context) {
    var p = _picked;
    var drafting = _pointing || _options != null;
    var several = _rows.length > 1 && !drafting;
    var trail = _trail;
    var crumbs = drafting
        ? <(String, VoidCallback?)>[("Table", _cancelNew), ("New style", null)]
        : several
            ? <(String, VoidCallback?)>[
                ("Table", () => _pick(TablePart.table)),
                ("${_rows.length} rows", null)
              ]
            : <(String, VoidCallback?)>[
                for (var (i, part) in trail.indexed)
                  (
                    _partName(part),
                    i == trail.length - 1 ? null : () => _pick(part)
                  ),
              ];
    var title = drafting
        ? "New style"
        : several
            ? "${_rows.length} rows"
            : switch (p.kind) {
                TablePartKind.table =>
                  t.name.isEmpty ? "The whole table" : t.name,
                TablePartKind.header => "Header row",
                TablePartKind.column => t.columnName(p.col),
                TablePartKind.row => "Row ${_rowLabel(p.row)}",
                TablePartKind.cell =>
                  "Cell ${_columnLetter(p.col)}${_rowLabel(p.row)}",
                TablePartKind.style => styleName(t, p.style),
              };
    var key = drafting
        ? "new"
        : several
            ? "rows"
            : p.kind.name;
    var (quick, body) = drafting
        ? _newPanel(context)
        : several
            ? _rowsPanel(context)
            : switch (p.kind) {
                TablePartKind.table => _tablePanel(context),
                TablePartKind.header => _headerPanel(context),
                TablePartKind.column => _columnPanel(context, p.col),
                TablePartKind.row => _rowPanel(context, p.row),
                TablePartKind.cell => _cellPanel(context, p.row, p.col),
                TablePartKind.style => _stylePanel(context, p.style),
              };
    return StudioSide(
      header: StudioSideHeader(
        icon: p.kind == TablePartKind.style && !drafting
            ? Icons.auto_fix_high
            : Icons.table_chart_outlined,
        crumbs: crumbs,
        crumbKey: "tableDesignCrumb",
        title: title,
        titleKey: const ValueKey("tableDesignTitle"),
        onUp: p == TablePart.table && !drafting && !several ? null : _up,
      ),
      scrollKey: ValueKey("tableDesignPanel-$key"),
      quick: quick,
      body: body,
    );
  }

  /// _newPanel is the New style's first step: pointing, or the options.
  (List<Widget>, List<Widget>) _newPanel(BuildContext context) {
    var options = _options;
    return (
      const <Widget>[],
      [
        studioSection(
            remember: "table.new",
            icon: Icons.ads_click,
            title: options == null
                ? "Click what to style"
                : "What should it reach?",
            summary: options == null
                ? "A cell, a row tab or a column tab"
                : "Hover one to see it lit",
            open: true,
            children: [
              studioGroup(
                  "",
                  [
                    if (options == null)
                      const StudioNote(
                          "Click a cell, a row tab or a column tab on the table. "
                          "Shift-click row tabs for several rows.")
                    else ...[
                      if (options.isEmpty)
                        const StudioNote("Nothing to offer from that."),
                      for (var (i, o) in options.indexed)
                        StudioItem(
                            key: ValueKey("tableReach-$i"),
                            mark: const Icon(Icons.adjust, size: 14),
                            title: o.label,
                            lit: _optionHover == i,
                            onHover: (h) =>
                                setState(() => _optionHover = h ? i : null),
                            onTap: () => _make(o)),
                    ],
                    studioButtons([
                      if (options != null)
                        studioButton("Click something else",
                            key: const ValueKey("tableNewRepoint"),
                            onPressed: () => setState(() {
                                  _options = null;
                                  _pointing = true;
                                })),
                      studioButton("Cancel",
                          key: const ValueKey("tableNewCancel"),
                          onPressed: _cancelNew),
                    ]),
                  ],
                  help: options == null
                      ? null
                      : "“Wherever it is” follows that team as the numbers "
                          "move it; “whoever is there” stays on that place."),
            ]),
      ]
    );
  }

  /// _rowsPanel is several rows picked with shift.
  (List<Widget>, List<Widget>) _rowsPanel(BuildContext context) => (
        [
          StudioNote(
              "${[for (var r in _rows) _rowLabel(r)].join(", ")}. A style on "
              "them can keep to these places or go with who is in them."),
          const SizedBox(height: 8),
          studioButtons([
            studioButton("New style for these",
                key: const ValueKey("tableDesignStyleRows"),
                icon: Icons.add,
                primary: true,
                onPressed: () => _offer(
                    reachOptions(t, TablePart.row(_rows.last), rows: _rows))),
          ]),
        ],
        const <Widget>[]
      );

  Widget _hint(BuildContext context, String text) => CanvasHint(text);

  /// _note is words that must be seen: a state, a warning.
  Widget _note(String text, {Color? color}) => StudioNote(text, colour: color);

  /// _styleColours are the colours of the table's style, offered first.
  List<Color> get _styleColours {
    var s = dataStyleNamed(t.style);
    if (s == null) {
      return [
        for (var c in [
          t.cellFill,
          t.cellSpec.color,
          t.headerFill,
          t.headerSpec.color,
          t.gridColor
        ])
          if (c.a > 0) c
      ];
    }
    return [
      s.ground,
      s.ink,
      s.dim,
      s.accent,
      s.headFill,
      s.headInk,
      s.grid,
      ...s.palette.take(4)
    ];
  }

  Widget _swatches(
          String id, String label, Color value, ValueChanged<Color> set,
          {bool none = true}) =>
      StudioColourField(
          id: id,
          label: label,
          value: value,
          styleColours: _styleColours,
          palette: _palette,
          asMade: none,
          onPick: (c) => set(c.a == 0 ? _colour(null) : c));

  Widget _slider(String label, double value, double min, double max,
          double rest, void Function(double) live,
          {bool percent = false,
          int decimals = 0,
          double? step,
          String suffix = ""}) =>
      studioStepper(
          key: ValueKey("tableSlider-$label"),
          label: label,
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          rest: rest,
          percent: percent,
          decimals: decimals,
          step: step,
          suffix: suffix,
          onChanged: live,
          onCommit: _end);

  /// _styleList is styles [indices] as rows: name and reach, an eye, a mark
  /// when it does nothing; hovered, all it reaches lights up.
  List<Widget> _styleList(BuildContext context, List<int> indices) => [
        for (var i in indices)
          StudioItem(
            key: ValueKey("tableStyle-$i"),
            mark: studioDot(t.rules[i].style.background.a > 0
                ? t.rules[i].style.background
                : t.rules[i].style.textColor.a > 0
                    ? t.rules[i].style.textColor
                    : const Color(0xFF59606B)),
            title: styleName(t, i),
            subtitle: styleReach(t, t.rules[i]),
            off: t.rules[i].off,
            tag: styleIdle(t, t.rules[i]) != null ? "does nothing" : null,
            tagKey: ValueKey("tableStyleIdle-$i"),
            lit: _hoverStyle == i,
            onHover: (h) => setState(() => _hoverStyle = h ? i : null),
            onEye: () => _setRule(i, t.rules[i].copyWith(off: !t.rules[i].off)),
            eyeKey: ValueKey("tableStyleEye-$i"),
            onTap: () => _pick(TablePart.style(i)),
          ),
      ];

  /// _typeface is a dropdown of the faces for [spec].
  Widget _typeface(String id, TextSpec spec, ValueChanged<TextSpec> set) =>
      studioDrop<String>(
          key: ValueKey(id),
          label: "Typeface",
          value: spec.fontFamily,
          options: [
            if (!canvasFonts.contains(spec.fontFamily))
              (spec.fontFamily, spec.fontFamily),
            for (var f in canvasFonts) (f, f),
          ],
          onChanged: (f) => set(spec.copyWith(fontFamily: f)));
}
