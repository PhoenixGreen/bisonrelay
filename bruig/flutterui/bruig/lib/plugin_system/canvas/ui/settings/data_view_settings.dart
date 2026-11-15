import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart'
    show panelRow, cell;
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
