part of 'data_table_design.dart';

// The panel for the table as a whole: its look, data, rows and columns. Part of
// _TableDesignState: its fields, lifecycle and build are in
// data_table_design.dart.

extension _TableWholePanel on _TableDesignState {
  (List<Widget>, List<Widget>) _tablePanel(BuildContext context) {
    var st = dataStyleNamed(t.style);
    var link = linkOf(t);
    var linked = link != null && c.sheetById(link.sheet) != null;
    var padSaid = t.evenPadding
        ? "padding ${t.cellPadding.round()}"
        : "padding each side";
    return (
      [
        studioRow([
          studioDrop<String>(
              key: const ValueKey("tableQuickStyle"),
              label: "Style",
              value: st?.name ?? "",
              options: [
                if (st == null) ("", "Its own"),
                for (var s in dataStyles) (s.name, s.name),
              ],
              onChanged: (name) {
                if (dataStyleNamed(name) case var s?) {
                  _set(tableInStyle(t, s));
                }
              }),
          studioButton("Canvas colours",
              key: const ValueKey("tableDesignMatchCanvas"),
              icon: Icons.format_paint_outlined,
              tooltip:
                  "Colours taken from the canvas's background and what is on it",
              onPressed: () {
            _set(tableInColours(t, canvasColoursOf(c.document, except: t.id)));
          }),
        ], flex: [
          3,
          2
        ]),
        const SizedBox(height: 8),
        studioRow([
          _typeface("tableCellFont", t.cellSpec,
              (spec) => _set(t.copyWith(cellSpec: spec))),
          _slider(
              "Size",
              t.cellSpec.fontSize,
              6,
              72,
              20,
              (v) => _live(
                  t.copyWith(cellSpec: t.cellSpec.copyWith(fontSize: v)))),
          _swatches("tableCellInk", "Words", t.cellSpec.color,
              (v) => _set(t.copyWith(cellSpec: t.cellSpec.copyWith(color: v))),
              none: false),
        ], flex: [
          3,
          2,
          2
        ]),
      ],
      [
        studioSection(
            remember: "table.style",
            icon: Icons.palette_outlined,
            title: "Style",
            summary: st?.name ?? "Its own",
            children: [
              studioGroup(
                  "",
                  [
                    DataStylePicker(
                        key: const ValueKey("tableStyles"),
                        element: t,
                        onPick: (s) => _set(tableInStyle(t, s))),
                    if (st != null)
                      studioButton("The whole page in ${st.name}",
                          key: const ValueKey("tableStylePage"),
                          icon: Icons.auto_awesome,
                          tooltip: "Every chart, table and word on this page, "
                              "and its ground, as one step to undo",
                          onPressed: () => c.stylePage(st)),
                  ],
                  help: "Its colours, typefaces, rules and corners at once; "
                      "the cells and their styles stay."),
            ]),
        if (linked) _rowsShown(context, link),
        studioSection(
            remember: "table.styles",
            icon: Icons.auto_fix_high,
            title: "Styles on it",
            count: t.rules.length,
            summary: t.rules.isEmpty
                ? "None yet"
                : "${t.rules.where((r) => !r.off).length} on · hover one to see what it reaches",
            open: true,
            children: [
              for (var (name, indices) in styleGroups(t))
                studioGroup(
                    "$name · ${indices.length}", _styleList(context, indices)),
              studioGroup("", [
                if (t.rules.isEmpty)
                  const StudioNote(
                      "None yet. Click a column, row or cell and add one there."),
                studioChips([
                  (
                    "+ New style",
                    const ValueKey("tableDesignNewStyle"),
                    () => setState(() {
                          _pointing = true;
                          _options = null;
                        })
                  ),
                ]),
              ]),
            ]),
        // The cells' face, size and colour are in the strip at the top; the
        // header row's here, beside them.
        studioSection(
            remember: "table.words",
            icon: Icons.title,
            title: "Header words",
            summary: [
              t.headerSpec.fontFamily,
              "${t.headerSpec.fontSize.round()}px",
              switch (t.headerSpec.weight) {
                300 => "light",
                700 => "bold",
                _ => "regular",
              },
            ].join(" · "),
            children: [
              studioGroup("", [
                studioRow([
                  _typeface("tableHeaderFont", t.headerSpec,
                      (spec) => _set(t.copyWith(headerSpec: spec))),
                  _slider(
                      "Header size",
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
                      onChanged: (v) => _set(t.copyWith(
                          headerSpec: t.headerSpec.copyWith(weight: v)))),
                  _swatches(
                      "tableHeaderInk",
                      "Colour",
                      t.headerSpec.color,
                      (v) => _set(t.copyWith(
                          headerSpec: t.headerSpec.copyWith(color: v))),
                      none: false),
                ], flex: [
                  3,
                  2
                ]),
                studioButton("All of the header row",
                    key: const ValueKey("tableToHeader"),
                    icon: Icons.chevron_right,
                    onPressed: () => _pick(TablePart.header)),
              ]),
            ]),
        studioSection(
            remember: "table.cells",
            icon: Icons.grid_on,
            title: "Cells",
            summary: [
              t.cellFill.a > 0 ? "Filled" : "No fill",
              t.zebra ? "striped" : "plain",
              padSaid,
            ].join(" · "),
            children: [
              studioGroup("", [
                studioRow([
                  _swatches("tableCellFill", "Fill", t.cellFill,
                      (v) => _set(t.copyWith(cellFill: v))),
                  if (t.zebra)
                    _swatches(
                        "tableZebraFill",
                        "Stripe",
                        t.zebraFill,
                        (v) => _set(
                            t.copyWith(zebraFill: v.withValues(alpha: 0.1))))
                  else
                    const SizedBox.shrink(),
                ]),
                StudioSwitchRow(
                    key: const ValueKey("tableZebra"),
                    label: "Stripes",
                    note: "every other row",
                    value: t.zebra,
                    onChanged: (v) => _set(t.copyWith(zebra: v))),
              ]),
              studioGroup("Padding", [
                // One figure until somebody wants four: a title row often wants
                // more above and below.
                studioSeg<bool>(
                    id: "tablePadSides",
                    value: t.evenPadding,
                    options: const [
                      (true, "All the same"),
                      (false, "Each side")
                    ],
                    onChanged: (even) => _set(even
                        ? t.copyWith(evenPadding: true)
                        : t.copyWith(
                            padTop: t.topPad,
                            padRight: t.rightPad,
                            padBottom: t.bottomPad,
                            padLeft: t.leftPad))),
                if (t.evenPadding)
                  studioRow([
                    _slider("Padding", t.cellPadding, 0, 40, 10,
                        (v) => _live(t.copyWith(cellPadding: v))),
                    _slider("Pictures", t.pictureScale, 0.2, 1.5, 1,
                        (v) => _live(t.copyWith(pictureScale: v)),
                        percent: true, step: 0.05),
                  ])
                else ...[
                  studioRow([
                    _slider("Top", t.topPad, 0, 40, t.cellPadding,
                        (v) => _live(t.copyWith(padTop: v))),
                    _slider("Bottom", t.bottomPad, 0, 40, t.cellPadding,
                        (v) => _live(t.copyWith(padBottom: v))),
                  ]),
                  studioRow([
                    _slider("Left", t.leftPad, 0, 40, t.cellPadding,
                        (v) => _live(t.copyWith(padLeft: v))),
                    _slider("Right", t.rightPad, 0, 40, t.cellPadding,
                        (v) => _live(t.copyWith(padRight: v))),
                  ]),
                  studioRow([
                    _slider("Pictures", t.pictureScale, 0.2, 1.5, 1,
                        (v) => _live(t.copyWith(pictureScale: v)),
                        percent: true, step: 0.05),
                    const SizedBox.shrink(),
                  ]),
                ],
              ]),
            ]),
        studioSection(
            remember: "table.lines",
            icon: Icons.border_all,
            title: "Lines and corners",
            summary: [
              t.grid == TableGrid.none
                  ? "No lines"
                  : "${t.grid.label} · ${t.gridWidth.toStringAsFixed(t.gridWidth % 1 == 0 ? 0 : 1)}px",
              "corners ${t.cornerRadius.round()}",
            ].join(" · "),
            children: [
              studioGroup("", [
                studioSeg<TableGrid>(
                    id: "tableGrid",
                    label: "Lines",
                    value: t.grid,
                    options: [
                      for (var g in TableGrid.values)
                        (g, g.label.replaceAll(" only", ""))
                    ],
                    onChanged: (v) => _set(t.copyWith(grid: v))),
                if (t.grid != TableGrid.none)
                  studioRow([
                    _swatches("tableGridColour", "Colour", t.gridColor,
                        (v) => _set(t.copyWith(gridColor: v)),
                        none: false),
                    _slider("Thickness", t.gridWidth, 0, 6, 1,
                        (v) => _live(t.copyWith(gridWidth: v)),
                        decimals: 1, step: 0.5),
                  ]),
                studioRow([
                  _slider("Corners", t.cornerRadius, 0, 40, 6,
                      (v) => _live(t.copyWith(cornerRadius: v))),
                  const SizedBox.shrink(),
                ]),
                StudioSwitchRow(
                    key: const ValueKey("tableOutline"),
                    label: "Outline round it",
                    value: t.showOutline,
                    onChanged: (v) => _set(t.copyWith(showOutline: v))),
              ]),
            ]),
        studioSection(
            remember: "table.layout",
            icon: Icons.view_quilt_outlined,
            title: "Layout",
            summary: [
              t.headerRow ? "Header row" : "No header row",
              if (t.headerColumn) "header column",
              switch (_columnSizing) {
                "fit" => "fit to contents",
                "even" => "even columns",
                _ => "columns as dragged",
              },
              if (t.cards) "cards apart",
            ].join(" · "),
            children: [
              studioGroup("", [
                StudioSwitchRow(
                    key: const ValueKey("tableHeaderRow"),
                    label: "Header row",
                    value: t.headerRow,
                    onChanged: (v) => _set(t.copyWith(headerRow: v))),
                StudioSwitchRow(
                    key: const ValueKey("tableHeaderColumn"),
                    label: "Header column",
                    note: "the first",
                    value: t.headerColumn,
                    onChanged: (v) => _set(t.copyWith(headerColumn: v))),
                studioSeg<String>(
                    id: "tableColumns",
                    label: "Column widths",
                    value: _columnSizing,
                    options: [
                      ("fit", "Fit to contents"),
                      ("even", "All the same"),
                      if (_columnSizing == "dragged") ("dragged", "As dragged"),
                    ],
                    onChanged: (v) {
                      if (v == _columnSizing || v == "dragged") return;
                      _set(t.copyWith(
                          columnWidths: v == "fit"
                              ? const []
                              : List.filled(t.columnCount,
                                  1 / math.max(1, t.columnCount))));
                    }),
                studioSeg<bool>(
                    id: "tableGroupRows",
                    label: "Rows with only a first cell",
                    value: t.groupRows,
                    options: const [
                      (false, "Like the rest"),
                      (true, "Headings across")
                    ],
                    onChanged: (v) => _set(t.copyWith(groupRows: v))),
                studioSeg<bool>(
                    id: "tableCards",
                    label: "Columns after the first",
                    value: t.cards,
                    options: const [
                      (false, "One table"),
                      (true, "Cards apart")
                    ],
                    onChanged: (v) => _set(t.copyWith(cards: v))),
                if (t.cards && t.columnCount > 1)
                  studioRow([
                    studioDrop<int>(
                        key: const ValueKey("tablePicked"),
                        label: "Raised card",
                        value: t.picked > 0 && t.picked < t.columnCount
                            ? t.picked
                            : -1,
                        options: [
                          (-1, "None"),
                          for (var col = 1; col < t.columnCount; col++)
                            (
                              col,
                              t.cell(0, col).trim().isEmpty
                                  ? "Column ${col + 1}"
                                  : t.cell(0, col).trim()
                            ),
                        ],
                        onChanged: (v) => _set(t.copyWith(picked: v))),
                    if (t.picked > 0)
                      studioText(
                          key: const ValueKey("tableRibbon"),
                          label: "Its ribbon",
                          value: t.ribbon,
                          hint: "Most popular",
                          onChanged: (v) => _live(t.copyWith(ribbon: v)))
                    else
                      const SizedBox.shrink(),
                  ]),
              ]),
            ]),
        // Sharp at any size, its words still words.
        studioSection(
            remember: "table.save",
            icon: Icons.save_alt,
            title: "Save it",
            summary: "As SVG or PDF, sharp at any size",
            children: [
              studioGroup(
                  "",
                  [
                    studioButtons([
                      for (var f in VectorFormat.values)
                        studioButton(f.label,
                            key: ValueKey("tableSave-${f.extension}"),
                            icon: Icons.download_outlined,
                            tooltip: "This table as an ${f.label}: lines and "
                                "words, not pixels",
                            onPressed: () => saveVector(context, t, f,
                                images: c.images,
                                ground: c.document.background.spec.background)),
                    ]),
                  ],
                  help: "Its words stay words and its lines stay lines, so "
                      "it prints sharp and can be edited in a drawing "
                      "program. Pictures in its cells go in as pictures."),
            ]),
        studioSection(
            remember: "table.motion",
            icon: Icons.animation,
            title: "Motion",
            summary: t.turn.label,
            children: [
              studioGroup(
                  "",
                  [
                    studioSeg<String>(
                        id: "tableTurn",
                        label: "Arrives",
                        value: t.turn.name,
                        options: [
                          for (var v in TableTurn.values) (v.name, v.label)
                        ],
                        onChanged: (v) =>
                            _set(t.copyWith(turn: TableTurn.fromName(v)))),
                  ],
                  help: "Whole, or a row or a column at a time, as it "
                      "arrives on the canvas."),
            ]),
      ]
    );
  }

  /// _columnSizing is which of three states its columns are in: sized by
  /// what is in them, all the same, or as they were dragged.
  String get _columnSizing {
    if (t.evenColumns) return "fit";
    var first = t.columnWidths.first;
    for (var w in t.columnWidths) {
      if ((w - first).abs() > 0.001) return "dragged";
    }
    return "even";
  }

  /// _rowsShown is which of its sheet's rows the table shows, and in what
  /// order: its own, the sheet left as it is.
  Widget _rowsShown(BuildContext context, SheetLink link) {
    var sheet = c.sheetById(link.sheet)!;
    void set(SheetLink next) => _set(withLink(t, next) as TableElement);
    var columns = [
      for (var col = 0; col < link.range.cols; col++)
        (col, sheetColumnName(sheet, link, col)),
    ];
    String name(int col) =>
        columns.firstWhere((x) => x.$1 == col, orElse: () => (col, "?")).$2;
    var sorted = link.sortBy >= 0;
    return studioSection(
        remember: "table.rows",
        icon: Icons.format_list_numbered,
        title: "Rows",
        summary: [
          link.top <= 0
              ? "Every row"
              : "${sorted ? "Top" : "First"} ${link.top}",
          sorted
              ? "by ${name(link.sortBy)}, ${link.descending ? "largest" : "smallest"} first"
              : "the sheet's order",
          if (link.whereColumn >= 0 && link.where.trim().isNotEmpty)
            "${name(link.whereColumn)} ${link.where.trim()}",
        ].join(" · "),
        children: [
          studioGroup(
              "",
              [
                studioRow([
                  studioSeg<int>(
                      id: "tableRowsTop",
                      label: "Show",
                      value: link.top > 0 ? (link.top) : 0,
                      options: [
                        (0, "Every row"),
                        (link.top > 0 ? link.top : 5, sorted ? "Top" : "First"),
                      ],
                      onChanged: (n) => set(link.copyWith(top: n))),
                  if (link.top > 0)
                    studioStepper(
                        key: const ValueKey("tableRowsHowMany"),
                        label: "How many",
                        value: link.top.toDouble(),
                        min: 1,
                        max: 100,
                        onChanged: (v) => set(link.copyWith(top: v.round())))
                  else
                    const SizedBox.shrink(),
                ], flex: [
                  3,
                  2
                ]),
              ],
              help: "Which of the sheet's rows this table shows, and in what "
                  "order. The sheet isn't changed: a table can show every "
                  "club while a chart of the same sheet shows the top five."),
          studioGroup("In order of", [
            studioRow([
              studioDrop<int>(
                  key: const ValueKey("tableRowsSort"),
                  value: link.sortBy.clamp(-1, link.range.cols - 1),
                  options: [(-1, "The sheet's own order"), ...columns],
                  onChanged: (v) => set(link.copyWith(sortBy: v))),
              if (sorted)
                studioSeg<bool>(
                    id: "tableRowsOrder",
                    value: link.descending,
                    options: const [(true, "Largest"), (false, "Smallest")],
                    onChanged: (v) => set(link.copyWith(descending: v)))
              else
                const SizedBox.shrink(),
            ]),
            // A league's positions stay 1, 2, 3 while the clubs move.
            if (sorted)
              studioSeg<bool>(
                  id: "tableRowsNumbering",
                  label: "First column",
                  value: link.numbering,
                  options: const [
                    (true, "Keeps its place"),
                    (false, "Moves with its row")
                  ],
                  onChanged: (v) => set(link.copyWith(numbering: v))),
          ]),
          studioGroup("Only where", [
            studioRow([
              studioDrop<int>(
                  key: const ValueKey("tableRowsWhere"),
                  value: link.whereColumn.clamp(-1, link.range.cols - 1),
                  options: [(-1, "Every row"), ...columns],
                  onChanged: (v) => set(link.copyWith(whereColumn: v))),
              if (link.whereColumn >= 0)
                studioText(
                    key: const ValueKey("tableRowsIs"),
                    value: link.where,
                    hint: "is: >5, Arsenal, <>0",
                    onChanged: (v) => _live(
                        withLink(t, link.copyWith(where: v)) as TableElement))
              else
                const SizedBox.shrink(),
            ]),
          ]),
        ]);
  }
}
