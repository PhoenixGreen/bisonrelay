import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/table_data_editor.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/data_source_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';

// table settings.dart is a table's settings.

List<Widget> tableSettings(
        BuildContext context,
        CanvasController controller,
        TableElement e,
        SettingsWrite write,
        VoidCallback begin,
        VoidCallback commit) =>
    [
      // Its own section, like the chart's numbers. The cells are the longest
      // thing in these settings and the least often changed once they are
      // right, so they were pushing everything else off the bottom.
      boxed(
        context,
        CanvasExpander(
          label: "Table",
          remember: "tableCells",
          trailing: "${e.rows.length} rows, ${e.columnCount} columns",
          initiallyOpen: true,
          children: [
            TableDataEditor(
              rows: e.rows,
              onChanged: (rows) {
                begin();
                write(e.copyWith(rows: rows));
              },
              onCommit: commit,
            ),
          ],
        ),
      ),
      dataSourceSection(context, controller, e, write, begin, commit),
      // Sorting is its own section next to the cells, because it is about the
      // data rather than about how the table looks -- and because three
      // columns and their directions is more than a band's worth of controls.
      boxed(
        context,
        CanvasExpander(
          label: "Order",
          remember: "tableSort",
          trailing: _sortSummary(e),
          // In the heading, so putting a table back in order is one press
          // without opening anything. It is the only thing this section does
          // that anybody wants without reading it.
          action: CanvasIconButton(
            icon: Icons.refresh,
            tooltip: e.sort.on
                ? "Put the rows back in this order"
                : "Choose a column to order by first",
            onPressed: e.sort.on
                ? () {
                    begin();
                    write(e.sorted());
                    commit();
                  }
                : null,
          ),
          children: [
            CanvasHint("Choose a column to order the rows by. The second and "
                "third only decide the rows the one before them left equal — "
                "for a league table that is points, then goal difference, "
                "then goals scored. Sorting happens when you press Sort, not "
                "as you type."),
            for (var level = 0; level < 3; level++)
              CanvasControlGroup(
                label: level == 0 ? "Order by" : "Then by",
                children: [
                  CanvasDropdown<int>(
                    label: "Column",
                    value: e.sort.at(level).column,
                    width: 132,
                    options: [
                      (-1, "—"),
                      for (var c = 0; c < e.columnCount; c++)
                        (c, _columnName(e, c)),
                    ],
                    onChanged: (v) => _setLevel(e, write, begin, commit, level,
                        e.sort.at(level).copyWith(column: v)),
                  ),
                  if (e.sort.at(level).on)
                    CanvasDropdown<bool>(
                      label: "Direction",
                      value: e.sort.at(level).descending,
                      width: 116,
                      options: const [
                        (true, "Highest first"),
                        (false, "Lowest first"),
                      ],
                      onChanged: (v) => _setLevel(e, write, begin, commit,
                          level, e.sort.at(level).copyWith(descending: v)),
                    ),
                ],
              ),
            CanvasControlGroup(label: "First column", children: [
              CanvasToggle(
                label: "Keep the numbering",
                value: e.sort.pinFirstColumn,
                onChanged: (v) {
                  begin();
                  write(e.copyWith(sort: e.sort.copyWith(pinFirstColumn: v)));
                  commit();
                },
              ),
              CanvasHint("A league table's first column is the position, "
                  "which belongs to the place rather than to the team in it — "
                  "so it stays reading 1, 2, 3 while everything else moves."),
            ]),
          ],
        ),
      ),
      // One mechanism for three things that were asked for separately, and
      // they really are one: a green chip wherever a column says W is a rule
      // about a column and a word, a highlighted row is a rule about a row,
      // and a points column set slightly larger is a rule about a column.
      boxed(
        context,
        CanvasExpander(
          label: "Special cells",
          remember: "tableRules",
          trailing: e.rules.isEmpty ? null : "${e.rules.length}",
          children: [
            for (var i = 0; i < e.rules.length; i++)
              _tableRuleSettings(e, i, write, begin, commit),
            CanvasControlGroup(label: "Add", bandOnlyLabel: true, children: [
              CanvasIconButton(
                icon: Icons.add_box_outlined,
                tooltip: "Add a rule",
                onPressed: () {
                  begin();
                  write(e.copyWith(rules: [
                    ...e.rules,
                    const TableRule(
                        style: TableCellStyle(background: Color(0xFF2E7D32))),
                  ]));
                  commit();
                },
              ),
              const CanvasHint(
                  "A rule says which cells look different and how. Leave the "
                  "column, the row or the text blank to mean any of them -- "
                  "so a column and a word is a chip wherever that word "
                  "appears, a row on its own is a highlighted row, and a "
                  "column on its own restyles the whole column."),
            ]),
          ],
        ),
      ),
      // Everything about how the table looks, in one place and below the
      // things that are about what it says. Two sets of type controls and a
      // dozen colour rows are what pushed the data and the order off the
      // bottom of the panel; a reader setting a table up goes to those first
      // and comes here once.
      boxed(
        context,
        CanvasExpander(
          label: "Style",
          remember: "tableStyle",
          children: [
            CanvasControlGroup(label: "Headers", children: [
              CanvasToggle(
                label: "Header row",
                value: e.headerRow,
                onChanged: (v) {
                  begin();
                  write(e.copyWith(headerRow: v));
                  commit();
                },
              ),
              CanvasToggle(
                label: "Header column",
                value: e.headerColumn,
                onChanged: (v) {
                  begin();
                  write(e.copyWith(headerColumn: v));
                  commit();
                },
              ),
              for (var c = 0; c < e.columnCount; c++)
                CanvasToggle(
                  label: _headingName(e, c),
                  value: !e.hiddenHeaders.contains(c),
                  onChanged: (v) {
                    begin();
                    write(e.copyWith(hiddenHeaders: [
                      for (var i = 0; i < e.columnCount; i++)
                        if (i == c ? !v : e.hiddenHeaders.contains(i)) i,
                    ]));
                    commit();
                  },
                ),
              const CanvasHint(
                  "Switch a heading off to keep its name without showing it. "
                  "A column of badges wants a name so the data mapping and "
                  "the order can refer to it, and wants nothing written over "
                  "the badges — the name is still there in the Table section "
                  "above, it is simply not drawn or measured."),
            ]),
            CanvasControlGroup(label: "Look", children: [
              CanvasDropdown<TableGrid>(
                label: "Rules",
                value: e.grid,
                width: 108,
                options: [for (var g in TableGrid.values) (g, g.label)],
                onChanged: (v) {
                  begin();
                  write(e.copyWith(grid: v));
                  commit();
                },
              ),
              CanvasColorButton(
                label: "Rules",
                color: e.gridColor,
                onChanged: (c) {
                  begin();
                  write(e.copyWith(gridColor: c));
                  commit();
                },
              ),
              CanvasColorButton(
                label: "Header",
                color: e.headerFill,
                onChanged: (c) {
                  begin();
                  write(e.copyWith(headerFill: c));
                  commit();
                },
              ),
              CanvasColorButton(
                label: "Cells",
                color: e.cellFill,
                onChanged: (c) {
                  begin();
                  write(e.copyWith(cellFill: c));
                  commit();
                },
              ),
              CanvasToggle(
                label: "Outline",
                value: e.showOutline,
                onChanged: (v) {
                  begin();
                  write(e.copyWith(showOutline: v));
                  commit();
                },
              ),
              CanvasToggle(
                label: "Zebra",
                value: e.zebra,
                onChanged: (v) {
                  begin();
                  write(e.copyWith(zebra: v));
                  commit();
                },
              ),
              CanvasColorButton(
                label: "Zebra",
                color: e.zebraFill,
                onChanged: (c) {
                  begin();
                  write(e.copyWith(zebraFill: c));
                  commit();
                },
              ),
              CanvasNumberField(
                label: "Padding",
                value: e.cellPadding,
                min: 0,
                max: 120,
                width: 54,
                onChanged: (v) => write(e.copyWith(cellPadding: v)),
                onCommit: commit,
              ),
              CanvasNumberField(
                label: "Radius",
                value: e.cornerRadius,
                min: 0,
                max: 120,
                width: 54,
                onChanged: (v) => write(e.copyWith(cornerRadius: v)),
                onCommit: commit,
              ),
              CanvasNumberField(
                label: "Picture size",
                value: e.pictureScale,
                min: 0.05,
                max: 1,
                decimals: 2,
                width: 62,
                onChanged: (v) => write(e.copyWith(pictureScale: v)),
                onCommit: commit,
              ),
              const CanvasHint(
                  "Picture size is how much of its cell a picture fills, on top of "
                  "the cell padding. Less than one leaves room round the outside, "
                  "which the padding cannot do on its own -- that is the words' "
                  "margin as well."),
            ]),
            boxed(
              context,
              CanvasExpander(
                label: "Header type",
                remember: "tableHeaderType",
                trailing: "${e.headerSpec.fontSize.round()}",
                children: typeGroups(
                    e.headerSpec,
                    (spec) => write(e.copyWith(headerSpec: spec)),
                    begin,
                    commit,
                    label: "Header type",
                    bandOnlyLabel: true),
              ),
            ),
            boxed(
              context,
              CanvasExpander(
                label: "Cell type",
                remember: "tableCellType",
                trailing: "${e.cellSpec.fontSize.round()}",
                children: typeGroups(e.cellSpec,
                    (spec) => write(e.copyWith(cellSpec: spec)), begin, commit,
                    label: "Cell type", bandOnlyLabel: true),
              ),
            ),
          ],
        ),
      ),
    ];

/// _tableRuleName says what a rule picks out, for its own heading and for the
/// button that removes it.
String _tableRuleName(TableRule rule, int index) {
  var name = [
    if (rule.column.isNotEmpty) rule.column,
    if (rule.rows.isNotEmpty) "rows ${rule.rows}",
    if (rule.match.isNotEmpty) '"${rule.match}"',
  ].join(" ");
  return name.isEmpty ? "every cell" : name;
}

/// _tableRuleSettings is one rule: which cells, and what they look like.

/// _tableRuleSettings is one rule: which cells, and what they look like.
Widget _tableRuleSettings(TableElement e, int index, SettingsWrite write,
    VoidCallback begin, VoidCallback commit) {
  var rule = e.rules[index];

  void put(TableRule next) {
    begin();
    var out = [...e.rules];
    out[index] = next;
    write(e.copyWith(rules: out));
  }

  void now(TableRule next) {
    put(next);
    commit();
  }

  var style = rule.style;
  void styled(TableCellStyle next) => now(rule.copyWith(style: next));

  return CanvasExpander(
    // Named for what it does rather than "Rule 3", so a list of them can be
    // read without opening each one.
    label: _tableRuleName(rule, index),
    // Remembered like every other section. A rule being worked on used to
    // shut the moment the element was deselected and selected again, which is
    // every time anybody looks at the canvas and comes back.
    remember: "tableRule$index",
    children: [
      CanvasControlGroup(label: "Which cells", children: [
        CanvasTextField(
          label: "Column",
          value: rule.column,
          hint: "any",
          width: 96,
          onChanged: (v) => put(rule.copyWith(column: v)),
          onCommit: commit,
        ),
        CanvasTextField(
          label: "Rows",
          value: rule.rows,
          hint: "any",
          width: 78,
          onChanged: (v) => put(rule.copyWith(rows: v)),
          onCommit: commit,
        ),
        CanvasTextField(
          label: "Text",
          value: rule.match,
          hint: "any",
          width: 96,
          onChanged: (v) => put(rule.copyWith(match: v)),
          onCommit: commit,
        ),
        CanvasDropdown<TableMatch>(
          label: "Matching",
          value: rule.how,
          width: 116,
          // Whole cell by default: "W" appearing inside "Won" is not what
          // anybody typing W means.
          options: [for (var m in TableMatch.values) (m, m.label)],
          onChanged: (v) => now(rule.copyWith(how: v)),
        ),
        const CanvasHint(
            "A whole word finds it on its own -- W in \"--- W\" but not in "
            "\"Won\" -- and draws its box round that word rather than round "
            "the cell.\n\n"
            "Column takes a heading -- Points -- or the same ranges the rows "
            "take. Rows counts from one and includes the header: 2 is one "
            "row, 2:4 a block of them, >1 everything under the header. Left "
            "blank either means any, which is what a rule about the other one "
            "wants."),
      ]),
      CanvasControlGroup(label: "Look", children: [
        CanvasColorButton(
          label: "Background",
          color: style.background,
          onChanged: (c) => styled(style.copyWith(background: c)),
        ),
        // Beside the colour it rounds, rather than three rows below it.
        CanvasNumberField(
          label: "Radius",
          value: style.radius,
          min: 0,
          max: 80,
          decimals: 1,
          width: 54,
          onChanged: (v) =>
              put(rule.copyWith(style: style.copyWith(radius: v))),
          onCommit: commit,
        ),
        CanvasColorButton(
          label: "Text",
          color: style.textColor,
          onChanged: (c) => styled(style.copyWith(textColor: c)),
        ),
        CanvasColorButton(
          label: "Border",
          color: style.borderColor,
          onChanged: (c) => styled(style.copyWith(borderColor: c)),
        ),
        const CanvasLineBreak(),
        CanvasNumberField(
          label: "Size",
          value: style.fontScale,
          min: 0.2,
          max: 6,
          decimals: 2,
          width: 54,
          onChanged: (v) =>
              put(rule.copyWith(style: style.copyWith(fontScale: v))),
          onCommit: commit,
        ),
        // A list, not a number. Weight is nine values and a field scrubbing
        // through nine hundred of them one pixel at a time was a control that
        // moved and did nothing until it crossed a boundary.
        CanvasDropdown<int>(
          label: "Weight",
          value: style.weight,
          width: 98,
          options: const [
            (0, "As the cell"),
            (300, "Light"),
            (400, "Regular"),
            (500, "Medium"),
            (600, "Semi-bold"),
            (700, "Bold"),
            (800, "Extra-bold"),
            (900, "Black"),
          ],
          onChanged: (v) => styled(style.copyWith(weight: v)),
        ),
        CanvasNumberField(
          label: "Border w",
          value: style.borderWidth,
          min: 0,
          max: 40,
          decimals: 1,
          width: 58,
          onChanged: (v) =>
              put(rule.copyWith(style: style.copyWith(borderWidth: v))),
          onCommit: commit,
        ),
        const CanvasLineBreak(),
        CanvasNumberField(
          label: "Min width",
          value: style.minWidth,
          min: 0,
          max: 400,
          decimals: 1,
          width: 62,
          onChanged: (v) =>
              put(rule.copyWith(style: style.copyWith(minWidth: v))),
          onCommit: commit,
        ),
        CanvasNumberField(
          label: "Min height",
          value: style.minHeight,
          min: 0,
          max: 400,
          decimals: 1,
          width: 66,
          onChanged: (v) =>
              put(rule.copyWith(style: style.copyWith(minHeight: v))),
          onCommit: commit,
        ),
        // Only on a rule about a cell. The pitch is how the whole cell is
        // laid out, so a rule that names one letter has no business deciding
        // it for the others -- offered there, setting it on the D respaced
        // the Ls and Ws beside it.
        if (rule.match.isEmpty) ...[
          CanvasNumberField(
            label: "Letter width",
            value: style.letterWidth,
            min: 0,
            max: 300,
            decimals: 1,
            width: 66,
            onChanged: (v) =>
                put(rule.copyWith(style: style.copyWith(letterWidth: v))),
            onCommit: commit,
          ),
          CanvasNumberField(
            label: "Letter space",
            value: style.letterSpacing,
            min: -20,
            max: 200,
            decimals: 1,
            width: 66,
            onChanged: (v) =>
                put(rule.copyWith(style: style.copyWith(letterSpacing: v))),
            onCommit: commit,
          ),
        ],
        CanvasNumberField(
          label: "Nudge X",
          value: style.nudgeX,
          min: -100,
          max: 100,
          decimals: 1,
          width: 58,
          onChanged: (v) =>
              put(rule.copyWith(style: style.copyWith(nudgeX: v))),
          onCommit: commit,
        ),
        CanvasNumberField(
          label: "Nudge Y",
          value: style.nudgeY,
          min: -100,
          max: 100,
          decimals: 1,
          width: 58,
          onChanged: (v) =>
              put(rule.copyWith(style: style.copyWith(nudgeY: v))),
          onCommit: commit,
        ),
        CanvasNumberField(
          label: "Text space",
          value: style.textPad,
          min: 0,
          max: 200,
          decimals: 1,
          width: 62,
          onChanged: (v) =>
              put(rule.copyWith(style: style.copyWith(textPad: v))),
          onCommit: commit,
        ),
        CanvasNumberField(
          label: "Padding",
          value: style.inset,
          min: -40,
          max: 60,
          decimals: 1,
          width: 54,
          onChanged: (v) => put(rule.copyWith(style: style.copyWith(inset: v))),
          onCommit: commit,
        ),
        const CanvasLineBreak(),
        // Which edges the border is drawn on. Four buttons rather than a list
        // of combinations, because "the top and the bottom" is a pair of
        // decisions and not a named style.
        for (var (at, icon, name) in const [
          (0, Icons.border_top, "Top"),
          (1, Icons.border_right, "Right"),
          (2, Icons.border_bottom, "Bottom"),
          (3, Icons.border_left, "Left"),
        ])
          CanvasIconButton(
            icon: icon,
            tooltip: "$name border",
            active: style.sides[at],
            onPressed: () {
              var sides = [...style.sides];
              sides[at] = !sides[at];
              styled(style.copyWith(sides: sides));
            },
          ),
        CanvasToggle(
          label: "Fill the cell",
          value: !style.hug,
          onChanged: (v) => styled(style.copyWith(hug: !v)),
        ),
        const CanvasLineBreak(),
        // On the rule rather than only on the table's type: a column of
        // numbers wants to be right-aligned and the column of names beside it
        // does not, and one alignment for the whole table cannot say that.
        CanvasDropdown<String>(
          label: "Align",
          value: style.align?.name ?? "",
          width: 96,
          options: [
            ("", "As the cell"),
            for (var a in TextAlignSpec.values) (a.name, a.label),
          ],
          onChanged: (v) => styled(v.isEmpty
              ? style.copyWith(clearAlign: true)
              : style.copyWith(align: TextAlignSpec.fromName(v))),
        ),
        CanvasDropdown<String>(
          label: "Vertical",
          value: style.verticalAlign?.name ?? "",
          width: 96,
          options: [
            ("", "As the cell"),
            for (var a in VerticalAlignSpec.values) (a.name, a.label),
          ],
          onChanged: (v) => styled(v.isEmpty
              ? style.copyWith(clearVerticalAlign: true)
              : style.copyWith(verticalAlign: VerticalAlignSpec.fromName(v))),
        ),
        // At the foot of the rule it removes. Beside Add it was one button
        // per rule on one line, which is fine for two rules and is twenty
        // buttons for twenty.
        CanvasIconButton(
          icon: Icons.delete_outline,
          tooltip: "Remove this rule",
          onPressed: () {
            begin();
            write(e.copyWith(rules: [...e.rules]..removeAt(index)));
            commit();
          },
        ),
        const CanvasHint(
            "Size multiplies the cell's own font size and weight overrides "
            "it, so a column can be made bigger or bolder without giving it "
            "a font of its own. A rule that names a word draws its box round "
            "the word; one that names a row or a column draws a single box "
            "round all of it, and Fill the cell takes the whole cell instead. "
            "Padding is the room round the word, or the amount taken off the "
            "inside of a band. Text space is room either side of the words "
            "themselves, which is what alignment needs to be usable -- pushed "
            "left or right they otherwise sit against the edge of the cell.\n\n"
            "Min width and min height stop a box shrinking to its letters, "
            "which is what makes a row of chips one size rather than three -- "
            "a W is wider than an L. The same number in both makes them "
            "square.\n\n"
            "Letter width gives every character in the cell a slot of the "
            "same width, and letter space is the gap between the slots. That "
            "is what lines a row of boxes up: a W is wider than an L, so "
            "without it no amount of spacing puts them in the same places. "
            "Set them on a rule with no text -- one about the column -- since "
            "the pitch is how the whole cell is laid out. Then a rule that "
            "names a letter draws its box on those slots, and min height "
            "makes the box taller than the letters.\n\n"
            "Nudge moves the letter inside its box, for the letters whose "
            "ink does not sit in the middle of the room the font gives them "
            "-- a W often does not. The box stays where it is, since the "
            "boxes being in line is the point of a letter width."),
      ]),
    ],
  );
}

/// _columnName is what to call a column in the Order controls: its header
/// where there is one, and its number where there is not.
String _columnName(TableElement e, int column) {
  var head = e.header;
  var name = column < head.length ? head[column].trim() : "";
  return name.isEmpty ? "Column ${column + 1}" : name;
}

/// _sortSummary is the closed section's one line.
String _sortSummary(TableElement e) {
  var named = [
    for (var level in e.sort.levels)
      if (level.on) _columnName(e, level.column),
  ];
  return named.isEmpty ? "Not sorted" : named.join(", then ");
}

void _setLevel(TableElement e, SettingsWrite write, VoidCallback begin,
    VoidCallback commit, int level, TableSortLevel value) {
  begin();
  write(e.copyWith(sort: e.sort.withLevel(level, value)));
  commit();
}

/// _headingName is what to call a column in the Headings switches: what its
/// header says, or its number when it says nothing yet.
String _headingName(TableElement e, int column) {
  var header = e.header;
  var name = column < header.length ? header[column].trim() : "";
  return name.isEmpty ? "Column ${column + 1}" : name;
}
