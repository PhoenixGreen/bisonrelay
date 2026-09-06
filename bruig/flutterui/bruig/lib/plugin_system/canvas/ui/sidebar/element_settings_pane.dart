import 'package:bruig/components/text.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/procedural_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// element_settings_pane.dart is the settings of whatever is selected, and the
// collapsible section that carries them.
//
// They were in three places at once -- both sidebar tabs and the band above
// the canvas -- because the things they belong with were in different tabs,
// and the first thing anybody does after adding an element is change it. Now
// that adding, the layer list and these live in one column together, they are
// needed in one place, and this is the body of one of its panels. See
// panel_stack.dart.

/// elementSettingsBody is the settings for the current selection.
///
/// Three cases: something is selected, several things are, or nothing is --
/// and the last one falls back to the canvas's own background rather than to
/// an empty column.
///
/// The background, because this panel should never be empty. Nothing selected
/// is the state a canvas starts in and returns to every time somebody clicks
/// the page, and a panel that empties itself is a panel that keeps taking its
/// room back and giving it away again. The background is also the one thing on
/// a canvas that is always there and always worth changing, so it is the
/// honest answer to "what am I editing" rather than a placeholder.
///
/// [stacked] lays the controls down a column, which is what a sidebar wants.
/// False puts them along a row.
Widget elementSettingsBody(BuildContext context, CanvasController controller,
    {bool stacked = true}) {
  var selected = controller.selected;

  if (controller.selection.length > 1) {
    return Txt.S("${controller.selection.length} elements selected. "
        "Choose one to change its settings.");
  }

  if (selected == null) {
    return ProceduralSettings(
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
  }

  var controls = elementSettings(context, controller, selected);
  return stacked
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CanvasSectionHeading(selected.name),
            ...controls,
          ],
        )
      : Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: controls,
        );
}

/// elementSettingsHint is what this section is for, in one sentence, for the
/// question mark beside its name.
const String elementSettingsHint =
    "The settings of whatever is selected. With nothing selected these are "
    "the canvas's own background, which is what the whole page is drawn on.";

/// CanvasSectionHeading is a small capitalised label above a group of things,
/// with an optional question mark beside it explaining what they are.
class CanvasSectionHeading extends StatelessWidget {
  final String text;
  final String? hint;
  const CanvasSectionHeading(this.text, {this.hint, super.key});

  @override
  Widget build(BuildContext context) {
    var label = Text(
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
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 2),
      child: hint == null
          ? label
          : Row(mainAxisSize: MainAxisSize.min, children: [
              label,
              CanvasHint(hint!),
            ]),
    );
  }
}
