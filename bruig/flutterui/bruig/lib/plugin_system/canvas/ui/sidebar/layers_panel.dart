import 'package:bruig/components/text.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/procedural_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/elements_panel.dart';
import 'package:bruig/storage_manager.dart';
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
// The panel is in two parts with a divider between them that can be dragged.
// The list grows without limit -- a football canvas is thirty layers -- and
// settings pushed off the bottom by it were settings that had to be scrolled
// back to after every selection. Splitting the height means both are always on
// screen, and how the height is shared is the reader's call: a document being
// arranged wants the list, one being styled wants the settings.
//
// The settings are the same controls as the band above the canvas used to
// carry, laid out stacked rather than in a row (see CanvasControlScope). They
// are only here now. Two places to change the same thing meant neither was the
// obvious one, and the band's copy could only show a few at a time along a
// line that had to be scrolled sideways.

/// _settingsMaxControlWidth caps a control in this column.
///
/// The chart's data box asks for 260 and the sidebar is narrower than that on
/// a small window. A control sized past its parent overflows rather than
/// shrinking, so the cap is what keeps the stripes off the screen.
const double _settingsMaxControlWidth = 240;

/// _splitKey remembers where the divider was left.
///
/// Persisted because it is a decision about the shape of the window rather
/// than a mood -- somebody who has dragged the settings open to work on a
/// chart should not find them shut again after switching tabs.
const String _splitKey = "canvasLayersSplit";

/// _minSection keeps either half from being dragged away entirely. A divider
/// that can be pushed to the edge is a divider that can be lost.
const double _minSection = 90;

class CanvasLayersPanel extends StatefulWidget {
  final CanvasController controller;
  const CanvasLayersPanel({required this.controller, super.key});

  @override
  State<CanvasLayersPanel> createState() => _CanvasLayersPanelState();
}

class _CanvasLayersPanelState extends State<CanvasLayersPanel> {
  /// _split is the fraction of the panel's height the layer list gets.
  double _split = 0.55;

  @override
  void initState() {
    super.initState();
    _restoreSplit();
  }

  Future<void> _restoreSplit() async {
    var saved = await StorageManager.readData(_splitKey);
    if (saved is num && mounted) {
      setState(() => _split = saved.toDouble().clamp(0.1, 0.9));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            var height = constraints.maxHeight;
            // With too little room to split, the list gets all of it and the
            // settings are reached by scrolling. Better than two sections too
            // short to show anything.
            if (height < _minSection * 2 + _dividerHeight) {
              return _layerList();
            }

            var listHeight = (height * _split)
                .clamp(_minSection, height - _minSection - _dividerHeight);
            return Column(children: [
              SizedBox(height: listHeight, child: _layerList()),
              _divider(height),
              Expanded(child: _settings()),
            ]);
          },
        ),
      );

  static const double _dividerHeight = 11;

  /// _divider is the grip between the two halves.
  Widget _divider(double panelHeight) {
    var theme = ThemeNotifier.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Vertical drag rather than a pan, so a slightly diagonal drag still
        // moves the divider instead of being claimed by the list's scroll.
        onVerticalDragUpdate: (details) {
          if (panelHeight <= 0) return;
          setState(() => _split =
              (_split + details.delta.dy / panelHeight).clamp(0.1, 0.9));
        },
        onVerticalDragEnd: (_) => StorageManager.saveData(_splitKey, _split),
        child: SizedBox(
          height: _dividerHeight,
          child: Center(
            child: Container(
              height: 3,
              width: 34,
              decoration: BoxDecoration(
                color: theme.colors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _layerList() {
    var controller = widget.controller;
    var elements = controller.document.elements;
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      children: [
        _SectionHeading("Layers (${elements.length + 1})"),
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

  Widget _settings() {
    var controller = widget.controller;
    var selected = controller.selected;

    Widget body;
    if (controller.backgroundSelected) {
      body = ProceduralSettings(
        spec: controller.document.background.spec,
        label: "Background",
        onBegin: controller.beginInteraction,
        onCommit: controller.endInteraction,
        onChanged: (spec) {
          controller.beginInteraction();
          controller.apply(
              controller.document.copyWith(
                  background:
                      controller.document.background.copyWith(spec: spec)),
              transient: true);
        },
      );
    } else if (selected != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeading(selected.name),
          ...elementSettings(context, controller, selected),
        ],
      );
    } else if (controller.selection.length > 1) {
      body = Txt.S("${controller.selection.length} elements selected. "
          "Choose one to change its settings.");
    } else {
      body = const Txt.S(
          "Choose a layer to change its settings, or the background at the "
          "bottom of the list to change the whole canvas.");
    }

    return CanvasControlScope(
      stacked: true,
      maxWidth: _settingsMaxControlWidth,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
        children: [body],
      ),
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

class _SectionHeading extends StatelessWidget {
  final String text;
  const _SectionHeading(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 2),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
            color: ThemeNotifier.of(context)
                .colors
                .onSurfaceVariant
                .withValues(alpha: 0.75),
          ),
        ),
      );
}

/// CanvasLayerRow is one element in the Layers list.
///
/// Public because the list it belongs to lives in layers_panel.dart, next
/// door; it stays a single widget so that a row's controls -- reorder, hide,
/// lock -- are described once.
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
          _rowButton(
            theme,
            element.locked ? Icons.lock_outline : Icons.lock_open_outlined,
            element.locked ? "Unlock" : "Lock",
            () => controller
                .replaceElement(element.withBase(locked: !element.locked)),
          ),
          // Copy is on the row as well as on Cmd-C, because the row is where
          // you already are when you have found the element you want -- and
          // because a shortcut nobody is told about is a shortcut nobody uses.
          _rowButton(
            theme,
            Icons.copy_outlined,
            "Copy",
            () => controller.copyElement(element.id),
          ),
        ]),
      ),
    );
  }

  Widget _rowButton(ThemeNotifier theme, IconData icon, String tooltip,
          VoidCallback? onTap) =>
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
                  : theme.colors.onSurfaceVariant,
            ),
          ),
        ),
      );
}
