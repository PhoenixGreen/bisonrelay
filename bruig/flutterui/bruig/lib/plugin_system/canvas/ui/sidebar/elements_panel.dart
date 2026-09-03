import 'package:bruig/components/text.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/element_settings_pane.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// elements_panel.dart is the Design Elements tab: what you can add, and the
// settings of whatever is selected.
//
// The *layer list* is not here and does not come back: it moved to its own tab
// (see layers_panel.dart) because the two answer different questions -- "what
// can I add" is asked once at the beginning, "what is already here" is asked
// continuously -- and sharing a panel meant the list of what was on the canvas
// was always scrolled below a grid of things the reader had finished with.
//
// The settings are a different matter. The first thing anybody does after
// adding an element is change it, and with the settings only on the Layers tab
// that was a trip to another tab and back for every element on a canvas. So
// they are here as well, in the same collapsible section, remembering its own
// open state and its own height -- see element_settings_pane.dart.
//
// An element can be added by clicking it or by dragging it onto the canvas.
// Both, because the two answer different questions -- a click means "I want
// one of those", a drag means "I want one of those *there*" -- and supporting
// only the first makes every new element start life in the middle of the page
// and need moving.

/// _addable is which kinds the panel offers, in the order it shows them.
///
/// Ordered by how often they are wanted rather than by the enum, so the two
/// that almost every canvas starts with are first and the specialised ones are
/// last.
const List<ElementKind> _addable = [
  ElementKind.text,
  ElementKind.shape,
  ElementKind.image,
  ElementKind.line,
  ElementKind.chart,
  ElementKind.table,
  ElementKind.button,
  ElementKind.background,
  ElementKind.player,
  ElementKind.path,
];

IconData iconForKind(ElementKind kind) => switch (kind) {
      ElementKind.text => Icons.title,
      ElementKind.image => Icons.image_outlined,
      ElementKind.shape => Icons.category_outlined,
      ElementKind.line => Icons.timeline,
      ElementKind.chart => Icons.bar_chart,
      ElementKind.table => Icons.table_chart_outlined,
      ElementKind.button => Icons.smart_button_outlined,
      ElementKind.background => Icons.blur_on,
      ElementKind.player => Icons.person_pin_circle_outlined,
      ElementKind.path => Icons.gesture,
    };

String _hintForKind(ElementKind kind) => switch (kind) {
      ElementKind.text => "A heading or a paragraph",
      ElementKind.image => "A picture, with its background removable",
      ElementKind.shape => "A square, circle, star or arrow",
      ElementKind.line => "A rule or an arrow between two points",
      ElementKind.chart => "Bars, lines, pies and radars",
      ElementKind.table => "A grid of text",
      ElementKind.button => "Something to press in a published canvas",
      ElementKind.background => "A generated pattern in a panel",
      ElementKind.player => "A numbered dot with a name",
      ElementKind.path =>
          "A curve, and optionally the route something takes along it",
    };

class CanvasElementsPanel extends StatelessWidget {
  final CanvasController controller;
  const CanvasElementsPanel({required this.controller, super.key});

  @override
  Widget build(BuildContext context) => CanvasSettingsSplit(
        controller: controller,
        storageKey: "canvasElements",
        // The grid is a fixed size and the settings are not, so the grid gets
        // the smaller share here -- the opposite of the Layers tab, where the
        // list is the part that grows.
        initialSplit: 0.45,
        top: ListView(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
          children: [
            const CanvasSectionHeading("Add"),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var kind in _addable) _AddChip(controller, kind),
              ],
            ),
            const SizedBox(height: 12),
            const Txt.S(
                "Click to add one in the middle of the canvas, or drag it "
                "where you want it. What is already on the canvas is in the "
                "Layers tab."),
          ],
        ),
      );
}

/// _AddChip is one element kind: click to add, or drag onto the canvas.
class _AddChip extends StatelessWidget {
  final CanvasController controller;
  final ElementKind kind;

  const _AddChip(this.controller, this.kind);

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var body = Container(
      width: 76,
      height: 62,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colors.outlineVariant),
        color: theme.colors.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(iconForKind(kind), size: 20, color: theme.colors.onSurfaceVariant),
        const SizedBox(height: 4),
        Text(
          kind.label,
          style: TextStyle(fontSize: 10, color: theme.colors.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ]),
    );

    return Tooltip(
      message: "${kind.label} — ${_hintForKind(kind)}\n"
          "Click to add, or drag onto the canvas",
      child: Draggable<ElementKind>(
        data: kind,
        // The same chip under the pointer, faded. A generic drag rectangle
        // gives no clue what is being carried once there are nine of them.
        feedback: Material(
          color: Colors.transparent,
          child: Opacity(opacity: 0.8, child: body),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: body),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => controller
              .addElement(newElement(kind, controller.document)),
          child: body,
        ),
      ),
    );
  }
}

