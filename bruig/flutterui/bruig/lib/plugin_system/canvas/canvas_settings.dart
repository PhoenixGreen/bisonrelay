import 'package:bruig/components/text.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/theming_system/runtime/theme_tokens.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// canvas_settings.dart is Canvas's section of Settings > Plugins: the switch
// that decides whether the feature exists.
//
// One switch and an explanation, because there is only one decision to make
// about Canvas from outside it. Everything else about a canvas is a property
// of that canvas and belongs on the canvas's own settings band, not in a
// settings screen a long way from the thing being changed.

class CanvasSettingsSection extends StatelessWidget {
  const CanvasSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    var prefs = context.watch<CanvasPreferences>();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 8),
      Row(children: [
        const Expanded(child: Txt.L("Canvas")),
        Switch(
          value: prefs.enabled,
          onChanged: (v) => prefs.enabled = v,
        ),
      ]),
      Padding(
        padding: const EdgeInsets.only(right: 60, bottom: 4),
        child: Txt.S(
          "Adds a Canvas section for composing images, charts, diagrams and "
          "short animations, and publishing them into a chat, a post, a page "
          "or your shared files.",
          color: TextColor.onSurfaceVariant,
        ),
      ),
      if (prefs.enabled)
        Padding(
          padding: const EdgeInsets.only(right: 60, bottom: 8),
          child: Txt.S(
            "Saved canvases are kept as plain files in the Canvas folder of "
            "the app's data directory. Turning this off leaves them there.",
            color: TextColor.onSurfaceVariant,
          ),
        ),
      const Divider(),
    ]);
  }
}
