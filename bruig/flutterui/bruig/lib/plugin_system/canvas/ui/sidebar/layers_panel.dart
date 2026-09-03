import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/element_settings_pane.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/elements_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// layers_panel.dart is the Layers tab: what is on the canvas, and everything
// about whichever of it is selected.
//
// Its own tab rather than the bottom half of Design Elements, which is where
// the list started. The two answer different questions -- "what can I add" is
// asked once at the beginning, "what is already here and which of it am I
// looking at" is asked continuously -- and sharing a panel meant the layer
// list was always scrolled below a grid of things the reader had finished
// with.
//
// The panel is in two parts with a divider between them that can be dragged,
// and the lower part can be closed altogether. The list grows without limit --
// a football canvas is thirty layers -- and settings pushed off the bottom by
// it were settings that had to be scrolled back to after every selection.
// Splitting the height means both are on screen, and how the height is shared
// is the reader's call: a document being arranged wants the list, one being
// styled wants the settings, and one being arranged with the band's copy of
// the settings open wants no settings here at all.
//
// The settings themselves are shared with the Design Elements tab and with the
// band above the canvas -- see element_settings_pane.dart, which also holds the
// section that carries them. This tab remembers its own open state and its own
// height, independently of the other two.

class CanvasLayersPanel extends StatelessWidget {
  final CanvasController controller;
  const CanvasLayersPanel({required this.controller, super.key});

  @override
  Widget build(BuildContext context) => CanvasSettingsSplit(
        controller: controller,
        storageKey: "canvasLayers",
        top: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => _layerList(),
        ),
      );

  Widget _layerList() {
    var elements = controller.document.elements;
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      children: [
        CanvasSectionHeading("Layers (${elements.length + 1})"),
        // Reversed, so what is on top of the canvas is at the top of the list.
        // The document stores paint order, where the last element is the
        // frontmost; a list showing that order literally reads upside down to
        // anybody looking at the canvas.
        for (var i = elements.length - 1; i >= 0; i--)
          CanvasLayerRow(
            controller: controller,
            element: elements[i],
            index: i,
            key: ValueKey(elements[i].id),
          ),
        // The background is always the bottom row, because it is always behind
        // everything: it is painted before any element and cannot be reordered
        // into the middle of them. Showing it in the list at all is what makes
        // it findable -- it used to be reachable only by deselecting
        // everything and then noticing that the band had changed.
        CanvasBackgroundLayerRow(controller: controller),
      ],
    );
  }
}

/// CanvasBackgroundLayerRow is the canvas's own background, shown as the
/// bottom layer.
///
/// It is not an element and has no reorder, hide or lock controls -- there is
/// nowhere for it to move to, and a canvas whose background could be switched
/// off would just be showing the editor's own colour and looking broken.
/// Selecting it is the only thing it does.
class CanvasBackgroundLayerRow extends StatelessWidget {
  final CanvasController controller;
  const CanvasBackgroundLayerRow({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var selected = controller.backgroundSelected;
    var spec = controller.document.background.spec;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Material(
        color: selected ? theme.colors.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: controller.selectBackground,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: Row(children: [
              // A swatch of the background's own colour rather than an icon:
              // it says which background this is, which matters as soon as
              // there is more than one document open in a day.
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: spec.background,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: theme.colors.outlineVariant),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Background — ${spec.style.label}",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: selected
                        ? theme.colors.onSecondaryContainer
                        : theme.colors.onSurface,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class CanvasLayerRow extends StatelessWidget {
  final CanvasController controller;
  final CanvasElement element;
  final int index;

  const CanvasLayerRow({
    required this.controller,
    required this.element,
    required this.index,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var selected = controller.selection.contains(element.id);
    var count = controller.document.elements.length;

    return InkWell(
      onTap: () => controller.selectOnly(element.id),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: selected ? theme.colors.secondaryContainer : null,
        ),
        child: Row(children: [
          Icon(
            iconForKind(element.kind),
            size: 15,
            color: selected
                ? theme.colors.onSecondaryContainer
                : theme.colors.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              element.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: element.visible
                    ? (selected
                        ? theme.colors.onSecondaryContainer
                        : theme.colors.onSurface)
                    : theme.colors.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
          // Buttons rather than dragging the rows to reorder. A drag inside a
          // scrolling list beside a canvas that also drags is two gestures
          // competing for one pointer, and the up/down pair says which
          // direction it will go before it goes there.
          _rowButton(theme, Icons.keyboard_arrow_up, "Move forward",
              index < count - 1
                  ? () => controller.apply(
                      controller.document.reorder(index, index + 1))
                  : null),
          _rowButton(theme, Icons.keyboard_arrow_down, "Move back",
              index > 0
                  ? () => controller.apply(
                      controller.document.reorder(index, index - 1))
                  : null),
          _rowButton(
            theme,
            element.visible
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            element.visible ? "Hide" : "Show",
            () => controller
                .replaceElement(element.withBase(visible: !element.visible)),
          ),
          // Filled and tinted when it is locked, outlined when it is not.
          // The pair used to be lock_outline and lock_open_outlined, which are
          // the same padlock with the shackle moved a couple of pixels -- at
          // fourteen pixels on a row of five icons the state was unreadable,
          // and locking something looked like it had done nothing.
          _rowButton(
            theme,
            element.locked ? Icons.lock : Icons.lock_open_outlined,
            element.locked ? "Unlock" : "Lock",
            () => controller
                .replaceElement(element.withBase(locked: !element.locked)),
            active: element.locked,
          ),
          // Duplicate rather than copy. A copy did nothing anybody could see:
          // the canvas was unchanged and the only evidence was that a paste
          // somewhere else would now produce this. What the button is reached
          // for is a second one of these, so it makes one. Cmd-C is still
          // there for a copy that is going somewhere.
          _rowButton(
            theme,
            Icons.control_point_duplicate_outlined,
            "Duplicate",
            () => controller.duplicateElement(element.id),
          ),
        ]),
      ),
    );
  }

  Widget _rowButton(ThemeNotifier theme, IconData icon, String tooltip,
          VoidCallback? onTap, {bool active = false}) =>
      Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Icon(
              icon,
              size: 14,
              color: onTap == null
                  ? theme.colors.onSurfaceVariant.withValues(alpha: 0.3)
                  : active
                      ? theme.colors.primary
                      : theme.colors.onSurfaceVariant,
            ),
          ),
        ),
      );
}
