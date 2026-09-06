import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// elements_panel.dart is what you can put on a canvas: a grid of chips, and
// nothing else.
//
// It used to carry the settings as well, and before that the layer list, both
// for the same reason -- the three are used together and were in different
// tabs, so each one kept a copy of its neighbour. They are one column now (see
// design_panel.dart), which is what lets this go back to being one thing.
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
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var kind in _addable) _AddChip(controller, kind),
            ],
          ),
        ],
      );
}

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
          onTap: () =>
              controller.addElement(newElement(kind, controller.document)),
          child: body,
        ),
      ),
    );
  }
}
