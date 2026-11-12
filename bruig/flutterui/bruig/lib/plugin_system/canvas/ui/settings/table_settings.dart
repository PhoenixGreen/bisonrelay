import 'dart:math' as math;
import 'package:bruig/plugin_system/canvas/model/canvas_palette.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/model/data_presets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_row_names.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/table_data_editor.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/data_source_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/type_parts.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';

// table_settings.dart is a table's settings.

/// tablePanel is [e]'s panel: the Text panel's shape (see
/// element_panel.dart) -- a quick strip of its rules and colours; Content
/// (its cells, where they come from, their order and special cells) and
/// Look (headers, rules, colours, sizes and type).
Widget tablePanel(
    BuildContext context,
    CanvasController controller,
    TableElement e,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit) {
  void now(TableElement next) {
    begin();
    write(next);
    commit();
  }

  return elementPanel(context, controller, e, write, begin, commit,
      quick: CanvasQuickStrip(key: const ValueKey("quickStrip"), children: [
        panelRow([
          cell(
              CanvasColorButton(
                key: const ValueKey("quickTableHeader"),
                label: "Header",
                color: e.headerFill,
                onChanged: (c) => now(e.copyWith(headerFill: c)),
              ),
              width: 104),
          cell(
              CanvasColorButton(
                key: const ValueKey("quickTableCells"),
                label: "Cells",
                color: e.cellFill,
                onChanged: (c) => now(e.copyWith(cellFill: c)),
              ),
              width: 104),
        ]),
        const SizedBox(height: 8),
        panelRow([
          cell(
              CanvasDropdown<TableGrid>(
                key: const ValueKey("quickTableRules"),
                label: "Rules",
                value: e.grid,
                options: [for (var g in TableGrid.values) (g, g.label)],
                onChanged: (v) => now(e.copyWith(grid: v)),
              ),
              flex: 2,
              min: 110),
          cell(
              CanvasSwitch(
                key: const ValueKey("quickTableZebra"),
                value: e.zebra,
                onChanged: (v) => now(e.copyWith(zebra: v)),
              ),
              width: 52),
        ]),
      ]),
      // Its cells are what its settings are opened for: not shut away.
      contentOpen: true,
      bits: tableBits(context, controller, e, write, begin, commit));
}

/// tableBits are what of [e] goes in which of its panel's sections.
List<PanelBit> tableBits(
        BuildContext context,
        CanvasController controller,
        TableElement e,
        SettingsWrite write,
        VoidCallback begin,
        VoidCallback commit) =>
    [
      // Its own section, like the chart's numbers: the cells are long and seldom
      // changed once right, and pushed everything else off the bottom.
      PanelBit(PanelSection.content, children: [
        CanvasExpander(
          label: "Table",
          remember: "tableCells",
          trailing: "${e.rows.length} rows, ${e.columnCount} columns",
          // The same Refresh the Data section carries, here where somebody
          // looking at the cells wants the numbers again.
          action:
              sourceRefreshButton(context, controller, e, write, begin, commit),
          initiallyOpen: true,
          children: [
            TableDataEditor(
              rows: e.rows,
              elementId: e.base.id,
              // What the source has, where its rows are what it is asked
              // for: typing a coin offers the coins. See DataPreset.rowNames.
              names: e.source.fromRows
                  ? CanvasRowNames.suggestionsFor(presetById(e.source.preset))
                  : const [],
              namesColumn: e.source.matchColumn < 0 ? 0 : e.source.matchColumn,
              onChanged: (rows) {
                begin();
                write(e.copyWith(rows: rows));
              },
              onCommit: commit,
            ),
          ],
        )
      ]),
      // Where the cells come from, a fold with its Refresh on its heading:
      // pressed without opening anything.
      PanelBit(PanelSection.content, summary: e.source.kind.label, children: [
        CanvasExpander(
          label: "Data source",
          remember: "tableSource",
          trailing: e.source.kind.label,
          action: sourceRefreshButton(
              context, controller, e, write, begin, commit,
              whenOff: true),
          children: [
            dataSourceSection(context, controller, e, write, begin, commit),
          ],
        ),
      ]),
      // Sorting is its own section beside the cells: it is about the data, not
      // the look, and too much for a band.
      PanelBit(PanelSection.content, children: [
        CanvasExpander(
          label: "Order",
          remember: "tableSort",
          trailing: _sortSummary(e),
          // In the heading, so putting a table back in order is one press.
          action: CanvasIconButton(
            key: const ValueKey("tableSortApply"),
            // On the section's heading, level with its arrow.
            tight: true,
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
            for (var level = 0; level < 3; level++)
              CanvasControlGroup(
                label: level == 0 ? "Order by" : "Then by",
                // Beside the first heading rather than on the section's:
                // it is about these three, not the numbering under them.
                help: level == 0
                    ? "Choose a column to order the rows by. The second and "
                        "third only decide the rows the one before them left "
                        "equal — for a league table that is points, then goal "
                        "difference, then goals scored. The rows are put in "
                        "order when you press the refresh button on this "
                        "section's heading, not as you type."
                    : null,
                children: [
                  CanvasDropdown<int>(
                    label: "Column",
                    value: e.sort.at(level).column,
                    width: 132,
                    options: [
                      (-1, "—"),
                      for (var c = 0; c < e.columnCount; c++)
                        (c, e.columnName(c)),
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
        )
      ]),
      // One mechanism for three asks: a chip where a column says W (a column and
      // a word), a highlighted row, a larger points column.
      PanelBit(PanelSection.content, children: [
        CanvasExpander(
          label: "Special cells",
          remember: "tableRules",
          trailing: e.rules.isEmpty ? null : "${e.rules.length}",
          children: [
            for (var i = 0; i < e.rules.length; i++)
              _tableRuleSettings(e, i, write, begin, commit),
            CanvasControlGroup(label: "Add", hideCaption: true, children: [
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
        )
      ]),
      // Everything about how the table looks, below what it says: somebody
      // setting a table up goes to the data and the order first.
      PanelBit(PanelSection.look, children: [
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
              label: e.columnName(c),
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
          CanvasTextButton(
            key: const ValueKey("tableMatchCanvas"),
            icon: Icons.format_paint_outlined,
            label: "Match the canvas",
            onPressed: () {
              var d = controller.document;
              begin();
              write(tableInColours(
                  e,
                  canvasColours(d.background.spec.background, [
                    for (var other in d.elements)
                      if (other.id != e.id) other
                  ])));
              commit();
            },
          ),
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
            gradient: e.headerFade,
            onChanged: (c) {
              begin();
              write(e.copyWith(headerFill: c));
              commit();
            },
            onGradientChanged: (g) {
              begin();
              write(g == null
                  ? e.copyWith(flatHeader: true)
                  : e.copyWith(headerFade: g));
              commit();
            },
          ),
          CanvasColorButton(
            label: "Cells",
            color: e.cellFill,
            gradient: e.cellFade,
            onChanged: (c) {
              begin();
              write(e.copyWith(cellFill: c));
              commit();
            },
            onGradientChanged: (g) {
              begin();
              write(g == null
                  ? e.copyWith(flatCells: true)
                  : e.copyWith(cellFade: g));
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
            key: const ValueKey("tablePadding"),
            label: "Padding",
            value: e.cellPadding,
            min: 0,
            max: 120,
            width: 54,
            onChanged: (v) => write(e.copyWith(cellPadding: v)),
            onCommit: commit,
          ),
          // One figure until somebody wants four: most tables want the same
          // room on every side, but a title row often wants more above and below.
          CanvasToggle(
            key: const ValueKey("tableSidedPadding"),
            label: "Sides",
            value: !e.evenPadding,
            onChanged: (v) {
              begin();
              // On: each side starts where the single figure left it, so
              // switching it on changes nothing until something is typed.
              // Off: back to the one figure, and the four are forgotten
              // rather than kept invisibly.
              write(v
                  ? e.copyWith(
                      padTop: e.topPad,
                      padRight: e.rightPad,
                      padBottom: e.bottomPad,
                      padLeft: e.leftPad)
                  : e.copyWith(evenPadding: true));
              commit();
            },
          ),
          if (!e.evenPadding) ...[
            CanvasNumberField(
              key: const ValueKey("tablePadTop"),
              label: "Top",
              value: e.topPad,
              min: 0,
              max: 120,
              width: 50,
              onChanged: (v) => write(e.copyWith(padTop: v)),
              onCommit: commit,
            ),
            CanvasNumberField(
              key: const ValueKey("tablePadRight"),
              label: "Right",
              value: e.rightPad,
              min: 0,
              max: 120,
              width: 50,
              onChanged: (v) => write(e.copyWith(padRight: v)),
              onCommit: commit,
            ),
            CanvasNumberField(
              key: const ValueKey("tablePadBottom"),
              label: "Bottom",
              value: e.bottomPad,
              min: 0,
              max: 120,
              width: 50,
              onChanged: (v) => write(e.copyWith(padBottom: v)),
              onCommit: commit,
            ),
            CanvasNumberField(
              key: const ValueKey("tablePadLeft"),
              label: "Left",
              value: e.leftPad,
              min: 0,
              max: 120,
              width: 50,
              onChanged: (v) => write(e.copyWith(padLeft: v)),
              onCommit: commit,
            ),
          ],
          // How the columns are sized, as a state rather than a button: dragging
          // an edge writes every column's width, and this is the way back. Sized
          // by content is not the same as all matching, which a button called
          // "Even" would hide.
          CanvasDropdown<String>(
            key: const ValueKey("tableColumnSizing"),
            label: "Columns",
            value: _columnSizing(e),
            width: 128,
            options: [
              ("fit", "Fit to contents"),
              ("even", "All the same"),
              if (_columnSizing(e) == "dragged") ("dragged", "Dragged"),
            ],
            onChanged: (v) {
              if (v == _columnSizing(e)) return;
              begin();
              write(e.copyWith(
                  columnWidths: v == "fit"
                      ? const []
                      : List.filled(
                          e.columnCount, 1 / math.max(1, e.columnCount))));
              commit();
            },
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
            children: [
              labelType(
                  TypeEdit(
                      e.headerSpec,
                      (spec) => write(e.copyWith(headerSpec: spec)),
                      begin,
                      commit),
                  label: "Header type",
                  remember: "tableHeader"),
            ],
          ),
        ),
        boxed(
          context,
          CanvasExpander(
            label: "Cell type",
            remember: "tableCellType",
            trailing: "${e.cellSpec.fontSize.round()}",
            children: [
              labelType(
                  TypeEdit(
                      e.cellSpec,
                      (spec) => write(e.copyWith(cellSpec: spec)),
                      begin,
                      commit),
                  label: "Cell type",
                  remember: "tableCell"),
            ],
          ),
        ),
      ]),
      // How it arrives, in a section of its own like a headline's.
      // Its animation: the Chain's Motion view (Ken, 2026-11-08).
    ];

/// _columnSizing is which of the three states a table's columns are in:
/// sized by what is in them, all the same, or whatever they were dragged to.
String _columnSizing(TableElement e) {
  if (e.evenColumns) return "fit";
  var first = e.columnWidths.first;
  for (var w in e.columnWidths) {
    if ((w - first).abs() > 0.001) return "dragged";
  }
  return "even";
}

/// _tableRuleName says what a rule picks out, for its own heading and for the
/// button that removes it.
String _tableRuleName(TableRule rule) {
  var name = [
    if (rule.column.isNotEmpty) rule.column,
    if (rule.rows.isNotEmpty) "rows ${rule.rows}",
    if (rule.match.isNotEmpty) '"${rule.match}"',
  ].join(" ");
  return name.isEmpty ? "every cell" : name;
}

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
    label: _tableRuleName(rule),
    // Remembered like every other section, so a rule being worked on stays
    // open when the element is selected again.
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
        // A list, not a number: weight is nine values, and a scrubbed field
        // moved through nine hundred doing nothing between them.
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
        // Only on a rule about a whole cell: the pitch lays out the whole cell,
        // so a rule naming one letter would respace the others.
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
        // Which edges the border is drawn on: four buttons, since top and
        // bottom are two decisions, not a named style.
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
        // At the foot of the rule it removes, not one per rule beside Add.
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

/// _sortSummary is the closed section's one line.
String _sortSummary(TableElement e) {
  var named = [
    for (var level in e.sort.levels)
      if (level.on) e.columnName(level.column),
  ];
  return named.isEmpty ? "Not sorted" : named.join(", then ");
}

void _setLevel(TableElement e, SettingsWrite write, VoidCallback begin,
    VoidCallback commit, int level, TableSortLevel value) {
  begin();
  write(e.copyWith(sort: e.sort.withLevel(level, value)));
  commit();
}
