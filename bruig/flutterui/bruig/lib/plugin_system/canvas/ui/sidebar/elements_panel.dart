import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/element_offers.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// elements_panel.dart is what can be put on a canvas: a grid of chips, one
// for each of addOffers, each clicked to add it mid-page or dragged to add
// it where it is dropped.

/// CanvasElementsPanel is the Add panel's body: the chips.
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
              for (var offer in addOffers) _AddChip(controller, offer),
            ],
          ),
        ],
      );
}

/// _AddChip is one offer's chip, keyed "add" and its label without spaces
/// ("addInstrument") for tests to find it by.
class _AddChip extends StatelessWidget {
  final CanvasController controller;
  final AddOffer offer;

  const _AddChip(this.controller, this.offer);

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var body = Container(
      width: 76,
      // At least this tall, taller with larger text, so two lines fit.
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colors.outlineVariant),
        color: theme.colors.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(offer.icon, size: 20, color: theme.colors.onSurfaceVariant),
          const SizedBox(height: 4),
          Text(
            offer.label,
            style:
                TextStyle(fontSize: 10, color: theme.colors.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );

    // No hover text: the chip's own icon and name say what it adds.
    return Draggable<AddOffer>(
      data: offer,
      // Anchored at the pointer, so what is added is centred where the
      // pointer lets go, not where the chip's corner is.
      dragAnchorStrategy: pointerDragAnchorStrategy,
      // The same chip under the pointer, faded, to show what is carried.
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(opacity: 0.8, child: body),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: body),
      child: Material(
        // Its own Material inside the list: the sidebar's would let the
        // highlight spill over other sections and stay put on scroll.
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey("add${offer.label.replaceAll(" ", "")}"),
          borderRadius: BorderRadius.circular(8),
          onTap: () => offer.add(controller),
          child: body,
        ),
      ),
    );
  }
}
