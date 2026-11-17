part of 'data_table_design.dart';

// The panel for a style: what it applies to, its rules and its look. Part of
// _TableDesignState: its fields, lifecycle and build are in
// data_table_design.dart.

extension _TableStylePanel on _TableDesignState {
  (List<Widget>, List<Widget>) _stylePanel(BuildContext context, int i) {
    var rule = t.rules[i];
    var s = rule.style;
    void look(TableCellStyle next, {bool live = false}) =>
        _setRule(i, rule.copyWith(style: next), live: live);
    var idle = styleIdle(t, rule);
    var columns = <(String, String)>[
      ("", "Every column"),
      for (var col = 0; col < t.columnCount; col++)
        (columnKey(t, col), t.columnName(col)),
    ];
    var colValue = rule.column.trim();
    if (!columns.any((o) => o.$1.toLowerCase() == colValue.toLowerCase())) {
      columns.add((colValue, spanWords(colValue, "column")));
    } else {
      colValue = columns
          .firstWhere((o) => o.$1.toLowerCase() == colValue.toLowerCase())
          .$1;
    }
    var rowsKind = switch (rule.rows.trim()) {
      "" => "",
      "1" when t.headerRow => "1",
      ">1" when t.headerRow => ">1",
      _ => "some",
    };
    List<bool> sidesOf(String k) => switch (k) {
          "above" => const [true, false, false, false],
          "under" => const [false, false, true, false],
          "both" => const [true, false, true, false],
          "sides" => const [false, true, false, true],
          _ => const [true, true, true, true],
        };
    var sidesKey = s.allSides
        ? "all"
        : switch (s.sides) {
            [true, false, false, false] => "above",
            [false, false, true, false] => "under",
            [true, false, true, false] => "both",
            [false, true, false, true] => "sides",
            _ => "own",
          };
    var lookSaid = [
      if (s.background.a > 0) "filled",
      if (s.textColor.a > 0) "coloured words",
      if (s.weight == 700) "bold",
      if (s.weight == 300) "light",
      if ((s.fontScale - 1).abs() > 0.01) "${(s.fontScale * 100).round()}%",
      if (s.align != null) "lined up ${s.align!.name}",
    ];
    var fineSaid = [
      if (s.letterWidth > 0) "letters ${s.letterWidth.round()}",
      if (s.minWidth > 0 || s.minHeight > 0) "least size",
      if (s.nudgeX != 0 || s.nudgeY != 0) "nudged",
      if (s.redact) "words hidden",
    ];
    return (
      [
        if (_made) ...[
          _note(
              "Step 2 of 2: its look. It names itself from what it reaches "
              "and looks like, until you type a name.",
              color: ThemeNotifier.of(context).colors.primary),
          const SizedBox(height: 6),
          studioButtons([
            studioButton("Done",
                key: const ValueKey("tableNewDone"),
                primary: true,
                onPressed: () => _pick(TablePart.table)),
          ]),
          const SizedBox(height: 8),
        ],
        if (idle != null) ...[
          _note("Does nothing: $idle.", color: const Color(0xFFF2B33D)),
          const SizedBox(height: 6),
        ],
        studioRow([
          studioText(
            key: ValueKey("tableStyleName-$i"),
            label: "Name",
            value: rule.name,
            hint: styleName(t.copyWith(rules: [rule.copyWith(name: "")]), 0),
            onChanged: (v) => _setRule(i, rule.copyWith(name: v), live: true),
          ),
        ]),
        const SizedBox(height: 8),
        studioButtons([
          studioButton(rule.off ? "Switch on" : "Switch off",
              key: const ValueKey("tableStyleOff"),
              icon: rule.off
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              onPressed: () => _setRule(i, rule.copyWith(off: !rule.off))),
          studioButton("Copy look",
              key: const ValueKey("tableStyleCopy"),
              onPressed: () => setState(() => _copied = s)),
          studioButton("Paste look",
              key: const ValueKey("tableStylePaste"),
              onPressed: _copied == null ? null : () => look(_copied!)),
          studioButton("Duplicate", key: const ValueKey("tableStyleDuplicate"),
              onPressed: () {
            var rules = [...t.rules]..insert(
                i + 1,
                rule.copyWith(
                    name: rule.name.isEmpty ? "" : "${rule.name} (copy)"));
            _set(t.copyWith(rules: rules));
            _pick(TablePart.style(i + 1));
          }),
          studioButton("Earlier",
              key: const ValueKey("tableStyleEarlier"),
              icon: Icons.arrow_upward,
              tooltip: "Applied before the one above it",
              onPressed: i == 0 ? null : () => _move(i, -1)),
          studioButton("Later",
              key: const ValueKey("tableStyleLater"),
              icon: Icons.arrow_downward,
              tooltip: "Applied after the one below it, so it wins",
              onPressed: i == t.rules.length - 1 ? null : () => _move(i, 1)),
          studioButton("Delete",
              key: const ValueKey("tableStyleDelete"),
              icon: Icons.delete_outline, onPressed: () {
            _set(t.copyWith(rules: [...t.rules]..removeAt(i)));
            _pick(TablePart.table);
          }),
        ]),
      ],
      [
        studioSection(
            remember: "table.styleReach",
            icon: Icons.place_outlined,
            title: "What it reaches",
            summary: styleReach(t, rule),
            open: true,
            children: [
              studioGroup("", [
                studioDrop<String>(
                  key: ValueKey("tableStyleColumn-$i"),
                  label: "Column",
                  value: colValue,
                  options: columns,
                  onChanged: (v) => _setRule(i, rule.copyWith(column: v)),
                ),
                if (rule.keys.isNotEmpty) ...[
                  studioText(
                    key: ValueKey("tableStyleKeys-$i"),
                    label: "Follows",
                    value: rule.keys.join(", "),
                    hint: "Names, with commas between",
                    onChanged: (v) => _setRule(
                        i,
                        rule.copyWith(keys: [
                          for (var k in v.split(","))
                            if (k.trim().isNotEmpty) k.trim()
                        ]),
                        live: true),
                  ),
                  _note("Found in the ${rule.keyColumn} column, wherever "
                      "they are as the numbers change."),
                  studioButtons([
                    studioButton("Keep to their places now",
                        key: const ValueKey("tableStyleKeep"),
                        onPressed: () => _setRule(i, _kept(rule))),
                  ]),
                ] else
                  studioDrop<String>(
                      key: const ValueKey("tableStyleRows"),
                      label: "Rows",
                      value: rowsKind,
                      options: [
                        ("", "Every row"),
                        if (t.headerRow) ("1", "The header"),
                        if (t.headerRow) (">1", "All but the header"),
                        ("some", "Some rows"),
                      ],
                      onChanged: (v) => _setRule(
                          i,
                          rule.copyWith(
                              rows: v == "some"
                                  ? (t.headerRow ? "2" : "1")
                                  : v))),
                if (rowsKind == "some") ...[
                  studioText(
                    key: ValueKey("tableStyleRowsText-$i"),
                    label: "Which rows",
                    value: rule.rows,
                    hint: "5, or 18:20, or >1",
                    onChanged: (v) =>
                        _setRule(i, rule.copyWith(rows: v), live: true),
                  ),
                  _note(
                      "${spanWords(rule.rows, "row", header: t.headerRow)}. Counting the header as 1: “18:20” is three rows, “>1” every row after the first."),
                ],
                if (rule.keys.isEmpty &&
                    rowsKind == "some" &&
                    keyColumnOf(t) >= 0 &&
                    _followable(rule))
                  studioButtons([
                    studioButton("Follow who is there now",
                        key: const ValueKey("tableStyleFollow"),
                        onPressed: () => _setRule(i, _followed(rule))),
                  ]),
              ]),
              ..._whenPart(context, i, rule),
              studioGroup("Only where it says", [
                studioText(
                  key: ValueKey("tableStyleMatch-$i"),
                  value: rule.match,
                  hint: "Words to look for (empty: every cell)",
                  onChanged: (v) =>
                      _setRule(i, rule.copyWith(match: v), live: true),
                ),
                if (rule.match.isNotEmpty)
                  studioSeg<TableMatch>(
                      id: "tableStyleHow",
                      label: "Found as",
                      value: rule.how,
                      options: [for (var m in TableMatch.values) (m, m.label)],
                      onChanged: (v) => _setRule(i, rule.copyWith(how: v))),
              ]),
            ]),
        studioSection(
            remember: "table.styleLook",
            icon: Icons.palette_outlined,
            title: "Its look",
            summary: lookSaid.isEmpty ? "As the table" : lookSaid.join(" · "),
            open: true,
            children: [
              studioGroup("", [
                studioRow([
                  _swatches("tableStyleFill", "Fill", s.background,
                      (v) => look(s.copyWith(background: v))),
                  _swatches("tableStyleInk", "Words", s.textColor,
                      (v) => look(s.copyWith(textColor: v))),
                ]),
                studioRow([
                  _slider("Size", s.fontScale, 0.4, 2.5, 1,
                      (v) => look(s.copyWith(fontScale: v), live: true),
                      percent: true, step: 0.1),
                  const SizedBox.shrink(),
                ]),
                studioSeg<int>(
                    id: "tableStyleWeight",
                    label: "Weight",
                    value: s.weight,
                    options: const [
                      (0, "Its own"),
                      (300, "Light"),
                      (400, "Regular"),
                      (700, "Bold")
                    ],
                    onChanged: (v) => look(s.copyWith(weight: v))),
                studioSeg<String>(
                    id: "tableStyleAlign",
                    label: "Lined up",
                    value: s.align?.name ?? "",
                    options: const [
                      ("", "Its own"),
                      ("left", "Left"),
                      ("center", "Centre"),
                      ("right", "Right")
                    ],
                    onChanged: (v) => look(v.isEmpty
                        ? TableCellStyle.fromJson(
                            {...s.toJson()}..remove("align"))
                        : s.copyWith(align: TextAlignSpec.values.byName(v)))),
                if (rule.match.isNotEmpty || s.background.a > 0)
                  studioSeg<bool>(
                      id: "tableStyleHug",
                      label: "Box",
                      value: s.hug,
                      options: const [
                        (true, "Round the words"),
                        (false, "Fills the cell")
                      ],
                      onChanged: (v) => look(s.copyWith(hug: v))),
                if (s.background.a > 0)
                  studioRow([
                    _slider("Corners", s.radius, 0, 24, 4,
                        (v) => look(s.copyWith(radius: v), live: true)),
                    _slider("Inset", s.inset, 0, 24, 6,
                        (v) => look(s.copyWith(inset: v), live: true)),
                  ]),
              ]),
            ]),
        studioSection(
            remember: "table.styleLines",
            icon: Icons.border_style,
            title: "Lines",
            summary: s.borderColor.a > 0
                ? "${s.borderWidth.round()}px · $sidesKey"
                : "None",
            children: [
              studioGroup("", [
                studioRow([
                  _swatches("tableStyleLine", "Colour", s.borderColor, (v) {
                    look(s.copyWith(
                        borderColor: v,
                        borderWidth:
                            v.a > 0 && s.borderWidth == 0 ? 2 : s.borderWidth));
                  }),
                  if (s.borderColor.a > 0)
                    _slider("Thickness", s.borderWidth, 0, 8, 0,
                        (v) => look(s.copyWith(borderWidth: v), live: true))
                  else
                    const SizedBox.shrink(),
                ]),
                if (s.borderColor.a > 0)
                  studioDrop<String>(
                      key: const ValueKey("tableStyleSides"),
                      label: "Where",
                      value: sidesKey,
                      options: [
                        ("all", "All round"),
                        ("above", "Above"),
                        ("under", "Under"),
                        ("both", "Above and under"),
                        ("sides", "Either side"),
                        if (sidesKey == "own") ("own", "Its own"),
                      ],
                      onChanged: (v) {
                        if (v != "own") look(s.copyWith(sides: sidesOf(v)));
                      }),
              ]),
            ]),
        studioSection(
            remember: "table.styleFine",
            icon: Icons.straighten,
            title: "Fine placement",
            summary: fineSaid.isEmpty ? "As made" : fineSaid.join(" · "),
            children: [
              studioGroup(
                  "",
                  [
                    studioRow([
                      _slider("Letter width", s.letterWidth, 0, 40, 0,
                          (v) => look(s.copyWith(letterWidth: v), live: true)),
                      _slider(
                          "Letter gap",
                          s.letterSpacing,
                          -5,
                          20,
                          0,
                          (v) =>
                              look(s.copyWith(letterSpacing: v), live: true)),
                    ]),
                    studioRow([
                      _slider("Margin", s.textPad, 0, 30, 0,
                          (v) => look(s.copyWith(textPad: v), live: true)),
                      _slider("Least width", s.minWidth, 0, 80, 0,
                          (v) => look(s.copyWith(minWidth: v), live: true)),
                    ]),
                    studioRow([
                      _slider("Least height", s.minHeight, 0, 80, 0,
                          (v) => look(s.copyWith(minHeight: v), live: true)),
                      _slider("Nudge across", s.nudgeX, -10, 10, 0,
                          (v) => look(s.copyWith(nudgeX: v), live: true)),
                    ]),
                    studioRow([
                      _slider("Nudge down", s.nudgeY, -10, 10, 0,
                          (v) => look(s.copyWith(nudgeY: v), live: true)),
                      studioSeg<bool>(
                          id: "tableStyleRedact",
                          label: "Words",
                          value: s.redact,
                          options: const [(false, "Shown"), (true, "Hidden")],
                          onChanged: (v) => look(s.copyWith(redact: v))),
                    ]),
                  ],
                  help: "For boxes round single letters, so a row of them "
                      "lines up: a fixed width per letter, the gap, a least "
                      "size, and nudges for a letter whose ink sits "
                      "off-centre."),
            ]),
      ]
    );
  }

  /// _kept is [rule] keeping to where the teams it follows are now.
  TableRule _kept(TableRule rule) {
    var rows = [
      for (var r = 0; r < t.rows.length; r++)
        if (rule.reachesRow(r, t.header, (c) => t.cell(r, c))) r + 1
    ];
    var spec = rows.isEmpty
        ? rule.rows
        : rows.length == 1
            ? "${rows.first}"
            : rows.last - rows.first + 1 == rows.length
                ? "${rows.first}:${rows.last}"
                : "${rows.first}";
    return rule.copyWith(rows: spec, keys: const []);
  }

  /// _followable is whether [rule]'s rows are body rows that can be named.
  bool _followable(TableRule rule) {
    var n = 0;
    for (var r = 0; r < t.rows.length; r++) {
      if (rule.matchesRow(r)) {
        if (t.headerRow && r == 0) return false;
        n++;
      }
    }
    return n > 0 && n <= 8;
  }

  /// _followed is [rule] going with the teams in its rows now.
  TableRule _followed(TableRule rule) {
    var k = keyColumnOf(t);
    return rule.copyWith(rows: "", keyColumn: columnKey(t, k), keys: [
      for (var r = 0; r < t.rows.length; r++)
        if (rule.matchesRow(r)) t.cell(r, k).trim()
    ]);
  }

  /// _whenPart is a style's number condition ("Points 9 or more"), or Add.
  List<Widget> _whenPart(BuildContext context, int i, TableRule rule) {
    var numeric = [
      for (var col = 0; col < t.columnCount; col++)
        if (t.rows.length > 1 &&
            [
              for (var r = t.headerRow ? 1 : 0; r < t.rows.length; r++)
                t.cell(r, col)
            ]
                .where((v) => v.trim().isNotEmpty)
                .every((v) => cellNumber(v) != null))
          columnKey(t, col)
    ];
    var w = rule.when;
    if (w == null) {
      if (numeric.isEmpty) return const [];
      return [
        studioGroup("", [
          studioChips([
            (
              "+ Only where a number is…",
              const ValueKey("tableStyleWhenAdd"),
              () => _setRule(
                  i, rule.copyWith(when: TableWhen(numeric.last, ">=", 0)))
            ),
          ]),
        ]),
      ];
    }
    return [
      studioGroup("Only where a number is", [
        studioRow([
          studioDrop<String>(
            key: ValueKey("tableStyleWhenColumn-$i"),
            value: numeric.contains(w.column)
                ? w.column
                : numeric.firstOrNull ?? w.column,
            options: [
              for (var n in {...numeric, w.column}) (n, n)
            ],
            onChanged: (v) =>
                _setRule(i, rule.copyWith(when: w.copyWith(column: v))),
          ),
          studioText(
            key: ValueKey("tableStyleWhenValue-$i"),
            value: w.value == w.value.roundToDouble()
                ? "${w.value.round()}"
                : "${w.value}",
            hint: "A number",
            onChanged: (v) {
              var n = double.tryParse(v.trim());
              if (n != null) {
                _setRule(i, rule.copyWith(when: w.copyWith(value: n)),
                    live: true);
              }
            },
          ),
        ]),
        studioSeg<String>(
            id: "tableStyleWhenOp",
            label: "Is",
            value: w.op,
            options: const [
              (">=", "or more"),
              ("<=", "or less"),
              (">", "over"),
              ("<", "under"),
              ("=", "exactly"),
            ],
            onChanged: (v) =>
                _setRule(i, rule.copyWith(when: w.copyWith(op: v)))),
        _note("Changes as the numbers do: ${whenWords(w)}."),
        studioButtons([
          studioButton("No number condition",
              key: const ValueKey("tableStyleWhenRemove"),
              onPressed: () => _setRule(i, rule.copyWith(noWhen: true))),
        ]),
      ]),
    ];
  }

  void _move(int i, int by) {
    var rules = [...t.rules];
    var r = rules.removeAt(i);
    rules.insert(i + by, r);
    _set(t.copyWith(rules: rules));
    _pick(TablePart.style(i + by));
  }
}
