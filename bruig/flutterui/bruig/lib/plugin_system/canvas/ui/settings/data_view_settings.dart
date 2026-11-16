import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart'
    show panelRow, cell;
import 'package:bruig/plugin_system/canvas/ui/settings/data_source_settings.dart'
    show sheetColumnName;
import 'package:flutter/material.dart';

// data_view_settings.dart is the top of a Data element's quick settings,
// the same for its table and its chart (Ken, 2026-11-15: Table and Chart
// made one Data element): whether it shows its data as a table or a chart,
// and which of the canvas's sheets it shows.

/// dataViewStrip is [e]'s View and Sheet.
Widget dataViewStrip(CanvasController controller, CanvasElement e) {
  var link = linkOf(e);
  var sheets = controller.document.sheets;
  return panelRow([
    cell(
        CanvasSegmented<ElementKind>(
          key: const ValueKey("dataView"),
          value: e.kind,
          options: const [
            (ElementKind.table, "Table"),
            (ElementKind.chart, "Chart"),
          ],
          keyOf: (k) => "dataView-${k.name}",
          onChanged: (k) => controller.showDataAs(e, k),
        ),
        flex: 3,
        min: 120),
    if (sheets.isNotEmpty)
      cell(
          CanvasDropdown<String>(
            key: const ValueKey("dataSheet"),
            label: "Sheet",
            value: sheets.any((s) => s.id == link?.sheet) ? link!.sheet : "",
            options: [
              if (!sheets.any((s) => s.id == link?.sheet)) ("", "—"),
              for (var s in sheets) (s.id, s.name),
            ],
            onChanged: (id) {
              if (id.isNotEmpty) controller.showSheet(e, id);
            },
          ),
          flex: 3,
          min: 120),
  ]);
}

/// dataStudioButton opens the Data Studio on [e]'s sheet, [e] picked.
Widget dataStudioButton(CanvasController controller, CanvasElement e) {
  var link = linkOf(e);
  return CanvasTextButton(
    key: const ValueKey("dataOpenStudio"),
    label: "Data Studio",
    icon: Icons.table_view_outlined,
    onPressed: link == null
        ? null
        : () => controller.openDataStudio(link.sheet, view: e.id),
  );
}

/// dataRowsGroup is which of its range's rows Data element [e] shows, and
/// in what order -- its own, the sheet left as it is (Ken's plan: "the
/// table shows all 20 clubs, the chart the top 5").
Widget dataRowsGroup(CanvasController controller, CanvasElement e) {
  var link = linkOf(e);
  var sheet = link == null ? null : controller.sheetById(link.sheet);
  if (link == null || sheet == null) return const SizedBox.shrink();
  void set(SheetLink next) => controller.replaceElement(withLink(e, next));
  var columns = [
    for (var c = 0; c < link.range.cols; c++)
      (c, sheetColumnName(sheet, link, c)),
  ];
  return CanvasControlGroup(
    key: const ValueKey("dataRows"),
    label: "Rows shown",
    help: "Which of its rows this one shows, and in what order. The sheet "
        "isn't changed: a table can show every club while a chart of the "
        "same sheet shows the top five.",
    children: [
      panelRow([
        cell(
            CanvasDropdown<int>(
              key: const ValueKey("dataRowsSort"),
              label: "Sort by",
              value: link.sortBy.clamp(-1, link.range.cols - 1),
              options: [(-1, "The sheet's order"), ...columns],
              onChanged: (c) => set(link.copyWith(sortBy: c)),
            ),
            flex: 3),
        if (link.sortBy >= 0)
          cell(
              CanvasSegmented<bool>(
                key: const ValueKey("dataRowsOrder"),
                value: link.descending,
                options: const [(true, "Largest"), (false, "Smallest")],
                keyOf: (d) => "dataRowsOrder-$d",
                onChanged: (d) => set(link.copyWith(descending: d)),
              ),
              flex: 3),
      ]),
      CanvasDropdown<int>(
        key: const ValueKey("dataRowsTop"),
        label: "Show",
        value: const [0, 3, 5, 10, 20].contains(link.top) ? link.top : 0,
        options: [
          (0, "Every row"),
          for (var n in const [3, 5, 10, 20])
            (n, link.sortBy >= 0 ? "The top $n" : "The first $n"),
        ],
        onChanged: (n) => set(link.copyWith(top: n)),
      ),
      panelRow([
        cell(
            CanvasDropdown<int>(
              key: const ValueKey("dataRowsWhere"),
              label: "Only where",
              value: link.whereColumn.clamp(-1, link.range.cols - 1),
              options: [(-1, "—"), ...columns],
              onChanged: (c) => set(link.copyWith(whereColumn: c)),
            ),
            flex: 3),
        if (link.whereColumn >= 0)
          cell(
              CanvasTextField(
                key: const ValueKey("dataRowsIs"),
                label: "is",
                value: link.where,
                hint: ">5, Arsenal, <>0",
                // A word typed is one change to undo, not one per key.
                onChanged: (v) {
                  controller.beginInteraction();
                  controller.replaceElement(
                      withLink(e, link.copyWith(where: v)),
                      transient: true);
                },
                onCommit: controller.endInteraction,
              ),
              flex: 2),
      ]),
    ],
  );
}
