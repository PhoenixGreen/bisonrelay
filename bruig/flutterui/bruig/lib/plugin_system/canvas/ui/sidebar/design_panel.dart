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
  Widget build(BuildContext context) => ListenableBuilder(
        // The whole stack, because two of the three headers say something
        // about the document: how many layers there are, and what is
        // selected. A panel whose name is out of date is worse than one with
        // no name.
        listenable: controller,
        builder: (context, _) => _stack(context),
      );

  Widget _stack(BuildContext context) => CanvasPanelStack(
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
            // Named for what is selected. The settings no longer head
            // themselves with the element's name, so this is what says what is
            // being edited -- and "Image settings" is a more useful heading
            // than a phrase that is true of everything.
            label: elementSettingsTitle(controller),
            icon: Icons.tune,
            hint: elementSettingsHint,
            builder: (context) => ListenableBuilder(
              listenable: controller,
              builder: (context, _) => SingleChildScrollView(
                // A clear gap under the header. It is a coloured band now,
                // so settings starting immediately beneath it read as being
                // part of it.
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
                child: CanvasControlScope(
                  maxWidth: 240,
                  child: elementSettingsBody(context, controller),
                ),
              ),
            ),
          ),
        ],
      );
}
