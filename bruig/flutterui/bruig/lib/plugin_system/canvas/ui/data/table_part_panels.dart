part of 'data_table_design.dart';

// The panels for a header, a column, a row and a cell picked. Part of
// _TableDesignState: its fields, lifecycle and build are in
// data_table_design.dart.

extension _TablePartPanels on _TableDesignState {
  (List<Widget>, List<Widget>) _headerPanel(BuildContext context) => (
        [
          studioRow([
            _typeface("tableHeaderFont", t.headerSpec,
                (spec) => _set(t.copyWith(headerSpec: spec))),
            _slider(
                "Size",
                t.headerSpec.fontSize,
                6,
                72,
                20,
                (v) => _live(t.copyWith(
                    headerSpec: t.headerSpec.copyWith(fontSize: v)))),
          ], flex: [
            3,
            2
          ]),
          const SizedBox(height: 8),
          studioRow([
            studioSeg<int>(
                id: "tableHeaderWeight",
                label: "Weight",
                value: t.headerSpec.weight,
                options: const [
                  (300, "Light"),
                  (400, "Regular"),
                  (700, "Bold")
                ],
                onChanged: (v) => _set(
                    t.copyWith(headerSpec: t.headerSpec.copyWith(weight: v)))),
            _swatches(
                "tableHeaderInk",
                "Words",
                t.headerSpec.color,
                (v) => _set(
                    t.copyWith(headerSpec: t.headerSpec.copyWith(color: v))),
                none: false),
          ], flex: [
            3,
            2
          ]),
        ],
        [
          studioSection(
              remember: "table.headerLook",
              icon: Icons.format_color_fill,
              title: "Its look",
              summary: [
                t.headerFill.a > 0 ? "Filled" : "No fill",
                "${t.headerHeightRatio.toStringAsFixed(2)}× a row",
              ].join(" · "),
              open: true,
              children: [
                studioGroup(
                    "",
                    [
                      studioRow([
                        _swatches("tableHeaderFill", "Fill", t.headerFill,
                            (v) => _set(t.copyWith(headerFill: v))),
                        _slider("Height", t.headerHeightRatio, 0.5, 3, 1.15,
                            (v) => _live(t.copyWith(headerHeightRatio: v)),
                            decimals: 2, step: 0.05, suffix: "×"),
                      ]),
                    ],
                    help: "Its height against a row's."),
              ]),
          studioSection(
              remember: "table.headerStyles",
              icon: Icons.auto_fix_high,
              title: "Styles on it",
              count: stylesOnRow(t, 0).length,
              summary: stylesOnRow(t, 0).isEmpty ? "None" : "",
              children: [
                studioGroup("", [
                  if (stylesOnRow(t, 0).isEmpty) const StudioNote("None."),
                  ..._styleList(context, stylesOnRow(t, 0)),
                ]),
              ]),
        ]
      );

  (List<Widget>, List<Widget>) _columnPanel(BuildContext context, int col) {
    var g = _Geom.of(t, 1000);
    var widths = g.w;
    var stylesHere = stylesOnColumn(t, col);
    var kind = t.columnKinds[col] ?? "";
    return (
      [
        studioRow([
          _slider("Width", widths[col], 10, math.max(60, t.width * 0.7),
              widths[col], (v) {
            var next = [...widths];
            next[col] = v;
            _live(t.copyWith(columnWidths: next));
          }),
          // Drawn rather than written (TableElement.columnKinds).
          studioDrop<String>(
              key: const ValueKey("tableColumnKind"),
              label: "Its cells show",
              value: kind,
              options: [for (var (k, says) in tableCellKinds) (k, says)],
              onChanged: (k) => _set(t.copyWith(columnKinds: {
                    for (var MapEntry(:key, :value) in t.columnKinds.entries)
                      if (key != col) key: value,
                    if (k.isNotEmpty) col: k,
                  }))),
        ], flex: [
          2,
          3
        ]),
        const SizedBox(height: 6),
        _note(switch (kind) {
          "spark" =>
            "Each cell's numbers, like “3, 5, 4, 8”, as a small line ending on a dot.",
          "ticks" =>
            "Yes, true or 1 a tick; no, false or 0 a cross; blank a dash.",
          "harvey" =>
            "0 to 4, a share up to 1, or a percentage, as a part-filled circle.",
          "change" => "Up green with ▲, down red with ▼, by the size of it.",
          "merge" =>
            "The same value in the rows below runs on as one tall cell.",
          "heat" =>
            "Shaded by its size among the column's numbers, the number written over it.",
          _ => "Written as typed. The other columns make room for its width.",
        }),
      ],
      [
        studioSection(
            remember: "table.columnStyles",
            icon: Icons.auto_fix_high,
            title: "Styles on this column",
            count: stylesHere.length,
            summary: stylesHere.isEmpty
                ? "None"
                : [for (var i in stylesHere) styleName(t, i)].join(", "),
            open: true,
            children: [
              studioGroup("", [
                ..._styleList(context, stylesHere),
                studioChips([
                  (
                    "+ New style from this",
                    const ValueKey("tableDesignStyleColumn"),
                    () => _offer(reachOptions(t, TablePart.column(col)))
                  ),
                ]),
              ]),
            ]),
        ..._wordsGuide(context, col),
      ]
    );
  }

  /// _wordsGuide gathers one column's word styles (a Form column's W, D, L)
  /// so their boxes, size and corners are set side by side.
  List<Widget> _wordsGuide(BuildContext context, int col) {
    var words = [
      for (var i in stylesOnColumn(t, col))
        if (t.rules[i].match.isNotEmpty && t.rules[i].column.trim().isNotEmpty)
          i
    ];
    if (words.length < 2) return const [];
    var boxed = [
      for (var i in words)
        if (t.rules[i].style.background.a > 0) i
    ];
    void all(TableCellStyle Function(TableCellStyle) change) {
      var rules = [...t.rules];
      for (var i in boxed) {
        rules[i] = rules[i].copyWith(style: change(rules[i].style));
      }
      _live(t.copyWith(rules: rules));
    }

    var size = boxed.isEmpty ? 0.0 : t.rules[boxed.first].style.minWidth;
    var corners = boxed.isEmpty ? 0.0 : t.rules[boxed.first].style.radius;
    return [
      studioSection(
          remember: "table.words",
          icon: Icons.text_fields,
          title: "Its words",
          count: words.length,
          summary: [for (var i in words) t.rules[i].match].join(" · "),
          open: true,
          children: [
            for (var i in words)
              studioGroup("“${t.rules[i].match}”", [
                studioRow([
                  _swatches(
                      "tableWordBox-$i",
                      "Box",
                      t.rules[i].style.background,
                      (v) => _setRule(
                          i,
                          t.rules[i].copyWith(
                              style:
                                  t.rules[i].style.copyWith(background: v)))),
                  _swatches(
                      "tableWordInk-$i",
                      "Words",
                      t.rules[i].style.textColor,
                      (v) => _setRule(
                          i,
                          t.rules[i].copyWith(
                              style: t.rules[i].style.copyWith(textColor: v)))),
                ]),
              ]),
            if (boxed.isNotEmpty)
              studioGroup("Every box", [
                studioRow([
                  _slider("Box size", size, 0, 60, 0,
                      (v) => all((s) => s.copyWith(minWidth: v, minHeight: v))),
                  _slider("Box corners", corners, 0, 20, 4,
                      (v) => all((s) => s.copyWith(radius: v))),
                ]),
              ]),
          ]),
    ];
  }

  (List<Widget>, List<Widget>) _rowPanel(BuildContext context, int row) {
    var stylesHere = stylesOnRow(t, row);
    return (
      const <Widget>[],
      [
        studioSection(
            remember: "table.rowStyles",
            icon: Icons.auto_fix_high,
            title: "Styles on this row",
            count: stylesHere.length,
            summary: "Shift-click other row tabs to style several",
            open: true,
            children: [
              studioGroup("", [
                ..._styleList(context, stylesHere),
                studioChips([
                  (
                    "+ New style from this",
                    const ValueKey("tableDesignStyleRow"),
                    () => _offer(reachOptions(t, TablePart.row(row)))
                  ),
                ]),
              ]),
            ]),
      ]
    );
  }

  (List<Widget>, List<Widget>) _cellPanel(
      BuildContext context, int row, int col) {
    var on = stylesAt(t, row, col);
    return (
      [
        studioButtons([
          studioButton("New style from this",
              key: const ValueKey("tableDesignStyleCell"),
              icon: Icons.add,
              onPressed: () =>
                  _offer(reachOptions(t, TablePart.cell(row, col)))),
          studioButton("Copy its look",
              key: const ValueKey("tableCellCopy"),
              icon: Icons.content_copy,
              onPressed: () => setState(() => _copied =
                  t.lookAt(row, col).style ?? const TableCellStyle())),
          if (t.lookAt(row, col).style != null)
            studioButton("Make a style from its look",
                key: const ValueKey("tableCellMake"), onPressed: () {
              var o = reachOptions(t, TablePart.cell(row, col)).firstOrNull;
              if (o == null) return;
              _newStyle(o.rule.copyWith(style: t.lookAt(row, col).style));
            }),
          studioButton("Its column",
              key: const ValueKey("tableCellColumn"),
              onPressed: () => _pick(TablePart.column(col))),
          studioButton(row == 0 && t.headerRow ? "The header" : "Its row",
              key: const ValueKey("tableCellRow"),
              onPressed: () => _pick(row == 0 && t.headerRow
                  ? TablePart.header
                  : TablePart.row(row))),
        ]),
      ],
      [
        studioSection(
            remember: "table.cellStyles",
            icon: Icons.auto_fix_high,
            title: "Styles reaching it",
            count: on.length,
            summary: on.isEmpty
                ? "None: it has the table's look"
                : "In the order they apply",
            open: true,
            children: [
              studioGroup(
                  "",
                  [
                    if (on.isEmpty)
                      const StudioNote(
                          "No styles reach it: it has the table's look."),
                    ..._styleList(context, on),
                  ],
                  help: on.isEmpty
                      ? null
                      : "In the order they apply: where two say different "
                          "things, the lower one wins."),
            ]),
      ]
    );
  }
}
