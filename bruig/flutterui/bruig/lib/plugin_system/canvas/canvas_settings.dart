import 'package:bruig/components/text.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
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
        Row(children: [
          const Expanded(child: Txt.M("Play through the mix engine")),
          Switch(
            key: const ValueKey("mixEngine"),
            value: prefs.mixEngine,
            onChanged: (v) => prefs.mixEngine = v,
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: 60, bottom: 8),
          child: Txt.S(
            "On: the editor's sound goes through the same mixer an export "
            "is made with, so what you hear is what is exported, sends and "
            "returns included. Off: the older engine, which plays each "
            "channel through SoLoud's own filters and cannot play a send. "
            "Takes effect for the next canvas opened.",
            color: TextColor.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        const Txt.M("Studio colours"),
        Padding(
          padding: const EdgeInsets.only(right: 60, top: 4, bottom: 8),
          child: Txt.S(
            "The colours of the mixer, the effects and the instruments. "
            "Studio is a dark desk of its own; Follow my theme takes them "
            "from the app's theme. Either way, press a colour to change it.",
            color: TextColor.onSurfaceVariant,
          ),
        ),
        SegmentedButton<StudioLook>(
          key: const ValueKey("studioLook"),
          segments: [
            for (var l in StudioLook.values)
              ButtonSegment(value: l, label: Text(l.label)),
          ],
          selected: {prefs.studioLook},
          onSelectionChanged: (v) => prefs.studioLook = v.first,
        ),
        const SizedBox(height: 10),
        _StudioSwatches(prefs: prefs),
      ],
      const Divider(),
    ]);
  }
}

/// _StudioSwatches is every studio colour as it is now, each pressed to
/// change it; one changed by hand has a way back beside it.
class _StudioSwatches extends StatelessWidget {
  final CanvasPreferences prefs;
  const _StudioSwatches({required this.prefs});

  @override
  Widget build(BuildContext context) {
    var colours = StudioColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 10, runSpacing: 8, children: [
        for (var role in StudioRole.values)
          Row(mainAxisSize: MainAxisSize.min, children: [
            CanvasColorButton(
              key: ValueKey("studioColour-${role.name}"),
              label: role.label,
              color: colours[role],
              onChanged: (c) => prefs.setStudioColour(role, c),
            ),
            if (prefs.studioOverrides.containsKey(role))
              IconButton(
                key: ValueKey("studioColourReset-${role.name}"),
                tooltip: "Put ${role.label.toLowerCase()} back",
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.restart_alt),
                onPressed: () => prefs.setStudioColour(role, null),
              ),
          ]),
      ]),
      if (prefs.studioOverrides.isNotEmpty)
        TextButton.icon(
          key: const ValueKey("studioColoursReset"),
          onPressed: prefs.clearStudioColours,
          icon: const Icon(Icons.restart_alt, size: 16),
          label: const Text("Put every colour back"),
        ),
    ]);
  }
}
