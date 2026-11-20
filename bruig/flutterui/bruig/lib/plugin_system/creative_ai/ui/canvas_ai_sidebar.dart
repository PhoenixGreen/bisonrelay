import 'package:bruig/components/panel_stack.dart';
import 'package:bruig/plugin_system/canvas/canvas.dart';
import 'package:bruig/plugin_system/creative_ai/creative_ai_model.dart';
import 'package:bruig/plugin_system/creative_ai/ui/chat_view.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// canvas_ai_sidebar.dart is Creative AI's sidebar on the Canvas page: ask
// Claude to work on the open canvas, see what it did, and keep it or put the
// canvas back as it was before Claude started.

class CanvasAiSidebar extends StatelessWidget {
  final CanvasController controller;
  const CanvasAiSidebar({required this.controller, super.key});

  static const examples = [
    "Make a title card for this scene with a bold headline and a subtitle",
    "Animate everything on this scene in one after another",
    "Check the text fits and reads well against the background",
    "Duck the music under the voice-over and measure the mix",
  ];

  @override
  Widget build(BuildContext context) {
    var ai = context.watch<CreativeAi>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AiChangesBar(ai: ai),
      Expanded(
        child: PanelStack(
          key: const ValueKey("creativeAiCanvasStack"),
          storageKey: "creativeAiCanvas",
          panels: [
            StackPanel(
              id: "chat",
              label: "Ask Claude",
              icon: Icons.auto_awesome_outlined,
              hint: "Claude works on the open canvas with Bison Relay's own "
                  "tools, on your Claude plan through Claude Code. Each "
                  "change is a step of Undo.",
              body: AiChatView(
                key: const ValueKey("creativeAiCanvasChat"),
                ai: ai,
                chat: ai.canvasChat,
                examples: examples,
                context: () => _context(controller),
                hint: "Ask Claude to change this canvas…",
              ),
            ),
            StackPanel(
              id: "activity",
              label: "What Claude did",
              icon: Icons.history,
              startsOpen: false,
              hint: "Every tool used on the canvas, from this sidebar or "
                  "from Claude Code elsewhere.",
              body: AiActivityList(ai: ai, area: "canvas"),
            ),
          ],
        ),
      ),
    ]);
  }

  /// _context tells Claude what the person is looking at: the scene, the
  /// playhead and what is selected.
  static String _context(CanvasController c) {
    var d = c.document;
    var picked = [
      for (var id in c.selection)
        if (d.elementById(id) case var e?) "${e.name} ($id)"
    ];
    return "[The person is on scene ${d.at} at frame ${c.frame}"
        "${picked.isEmpty ? ", with nothing selected" : ", with ${picked.join(", ")} selected"}.]";
  }
}

/// AiChangesBar offers to keep Claude's changes to the canvas, or undo them
/// all at once, while there are some.
class AiChangesBar extends StatelessWidget {
  final CreativeAi ai;
  const AiChangesBar({required this.ai, super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: Listenable.merge([ai, ai.canvasChat]),
      builder: (context, _) => _bar(context));

  Widget _bar(BuildContext context) {
    if (!ai.hasCheckpoint) return const SizedBox.shrink();
    var colors = ThemeNotifier.of(context).colors;
    return Container(
      color: colors.secondaryContainer,
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      child: Row(children: [
        Expanded(
          child: Text("Claude has changed this canvas.",
              style: TextStyle(
                  fontSize: 12.5, color: colors.onSecondaryContainer)),
        ),
        TextButton(
          key: const ValueKey("creativeAiUndoAll"),
          onPressed: ai.canvasChat.running ? null : ai.undoCanvas,
          child: const Text("Undo all"),
        ),
        TextButton(
          key: const ValueKey("creativeAiKeep"),
          onPressed: ai.keepCanvas,
          child: const Text("Keep"),
        ),
      ]),
    );
  }
}
