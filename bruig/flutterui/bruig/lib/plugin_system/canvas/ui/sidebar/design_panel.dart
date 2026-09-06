import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/element_settings_pane.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/elements_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/layers_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/panel_stack.dart';
import 'package:flutter/material.dart';

// design_panel.dart is the three things you use to build a canvas, in one
// column: what you can add, what is already there, and the settings of
// whichever of it is selected.
//
// They were three tabs, and the cost of that was paid on every element: add
// one from the first tab, change it on the third, look for it on the second.
// Two of the three ended up carrying copies of the settings just to shorten
// the journey, which is how you can tell tabs were the wrong shape -- the
// work does not divide the way the tabs did.
//
// A stack rather than a fixed split, so the arrangement is the reader's:
// each panel opens, closes, takes the height it is given and sits where it is
// put, and all of that is remembered. See panel_stack.dart.

class CanvasDesignPanel extends StatelessWidget {
  final CanvasController controller;
  const CanvasDesignPanel({required this.controller, super.key});

  @override
  Widget build(BuildContext context) => CanvasPanelStack(
        storageKey: "canvasDesign",
        panels: [
          CanvasStackPanel(
            id: "add",
            label: "Add",
            icon: Icons.category_outlined,
            hint: "Click to add one in the middle of the canvas, or drag it "
                "where you want it.",
            builder: (context) => CanvasElementsPanel(controller: controller),
          ),
          CanvasStackPanel(
            id: "layers",
            label: "Layers",
            icon: Icons.layers_outlined,
            // The count on the heading rather than inside the list, so a shut
            // panel still says how much is behind it. One more than the
            // elements, because the background is a layer too.
            trailing: "${controller.document.elements.length + 1}",
            builder: (context) => CanvasLayersPanel(controller: controller),
          ),
          CanvasStackPanel(
            id: "settings",
            label: "Element settings",
            icon: Icons.tune,
            hint: elementSettingsHint,
            builder: (context) => ListenableBuilder(
              listenable: controller,
              builder: (context, _) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
                child: CanvasControlScope(
                  stacked: true,
                  maxWidth: 240,
                  child: elementSettingsBody(context, controller),
                ),
              ),
            ),
          ),
        ],
      );
}
