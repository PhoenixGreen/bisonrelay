import 'package:bruig/components/text.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/theming_system/runtime/theme_tokens.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// canvas_settings.dart is Canvas's section of Settings > Plugins: the switch
// that decides whether the feature exists.
//
// Two switches and an explanation. Everything else about a canvas is a
// property of that canvas and belongs on the canvas's own settings band, not
// in a settings screen a long way from the thing being changed -- these two
// are here because neither is about a canvas. One decides whether the feature
// exists at all; the other is about what this app is allowed to do with the
// network, which is a decision about the app and not about a design.

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
      if (prefs.enabled) ...[
        Padding(
          padding: const EdgeInsets.only(right: 60, bottom: 8),
          child: Txt.S(
            "Saved canvases are kept as plain files in the Canvas folder of "
            "the app's data directory. Turning this off leaves them there.",
            color: TextColor.onSurfaceVariant,
          ),
        ),
        Row(children: [
          const Expanded(child: Txt.M("Let a canvas fetch data")),
          Switch(
            value: prefs.allowFetching,
            onChanged: (v) => prefs.allowFetching = v,
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: 60, bottom: 8),
          child: Txt.S(
            "Off by default. A table or a chart can pull its numbers from a "
            "web address — a league table, a price, a count — but nothing "
            "else in this app connects out on its own, and a fetch from a "
            "canvas does not go through the proxy set in Settings > Network. "
            "The address you fetch from would see your connection. Nothing "
            "is ever fetched without you pressing Refresh, and a canvas can "
            "read the same data from a file with this switched off.",
            color: TextColor.onSurfaceVariant,
          ),
        ),
      ],
      const Divider(),
    ]);
  }
}
