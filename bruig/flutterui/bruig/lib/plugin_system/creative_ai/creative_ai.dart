import 'package:bruig/plugin_system/canvas/canvas.dart';
import 'package:bruig/plugin_system/creative_ai/creative_ai_model.dart';
import 'package:bruig/plugin_system/creative_ai/creative_ai_preferences.dart';
import 'package:bruig/plugin_system/creative_ai/tools/guide.dart';
import 'package:bruig/plugin_system/creative_ai/ui/canvas_ai_sidebar.dart';
import 'package:bruig/plugin_system/creative_ai/ui/creative_ai_settings.dart';
import 'package:bruig/plugin_system/creative_ai/ui/writing_ai_panel.dart';
import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// creative_ai.dart is the entry point to Creative AI: Claude working inline
// with Bison Relay's own tools, on the open canvas and the open document.
// App code outside this directory imports this file and nothing beneath it.
//
// Like Canvas, it is app code behind a switch rather than a wasm plugin: a
// plugin can neither run a program nor draw a panel. It sits on top of the
// two features it works in. It imports Canvas and the writing tools, adds
// itself to them through the hooks they offer (a sidebar, a panel, menu
// entries), and nothing imports it -- see
// test/plugin_system_layering_test.dart. Switched off, it leaves no trace in
// either: no icon, no menu entry, no server listening.
//
// How it reaches Claude, and why it costs nothing beyond the person's Claude
// plan: claude/claude_code.dart. What Claude is given: mcp/mcp_server.dart
// (the protocol), tools/ (the tools and what Claude is told).
//
// Layout:
//
//   creative_ai_preferences.dart  the switches, models, port and token
//   creative_ai_model.dart        the running feature: server, tokens,
//                                 activity, the canvas from before Claude
//   engine/        pure Dart: JSON edits, word differences
//   mcp/           the MCP server (Streamable HTTP, on 127.0.0.1)
//   claude/        running Claude Code on the person's own account
//   tools/         the Canvas and Writing tools, and the guide Claude reads
//   session/       a sidebar's conversation; the document's suggestions
//   ui/            settings, the Canvas sidebar, the Writing panel

export 'package:bruig/plugin_system/creative_ai/creative_ai_model.dart'
    show CreativeAi;
export 'package:bruig/plugin_system/creative_ai/creative_ai_preferences.dart'
    show CreativeAiPreferences;

/// creativeAiId names Creative AI's sidebar and panel.
const String creativeAiId = "creativeAi";

/// registerCreativeAi attaches Creative AI to the settings page, Canvas and
/// the Writing page, once at startup, after [prefs] has loaded.
void registerCreativeAi(CreativeAiPreferences prefs) {
  PluginSettingsRegistry.registerFeature(
    creativeAiId,
    (context, inPluginPanel) => const CreativeAiSettingsSection(),
  );

  CanvasSidebarExtras.register(CanvasSidebarExtra(
    id: creativeAiId,
    name: "Creative AI",
    icon: Icons.auto_awesome_outlined,
    shown: _flag(prefs, () => prefs.canvasOn),
    build: (context, controller) => CanvasAiSidebar(controller: controller),
  ));

  ComposerSidebarExtras.register(ComposerSidebarExtra(
    id: writingAiPanelId,
    label: "Creative AI",
    icon: Icons.auto_awesome_outlined,
    shown: _flag(prefs, () => prefs.writingOn),
    build: (context, composer) => WritingAiPanel(composer: composer),
  ));

  ComposerSidebarExtras.registerMenu(creativeAiId, _menuItems);
}

/// _flag is [read] kept up to date as [prefs] changes.
ValueListenable<bool> _flag(CreativeAiPreferences prefs, bool Function() read) {
  var flag = ValueNotifier(read());
  prefs.addListener(() => flag.value = read());
  return flag;
}

/// _menuItems are the right-click entries on selected text in the Writing
/// composer: improve it now, or open the panel to choose.
List<ContextMenuButtonItem> _menuItems(
    BuildContext context, EditableTextState field) {
  CreativeAi ai;
  ComposerSidebarController composer;
  try {
    ai = Provider.of<CreativeAi>(context, listen: false);
    composer = Provider.of<ComposerSidebarController>(context, listen: false);
  } catch (_) {
    return const [];
  }
  // The composer's own text only: the same menu serves other fields.
  if (!ai.writingOn || !identical(field.widget.controller, composer.editor)) {
    return const [];
  }
  var sel = field.textEditingValue.selection;
  if (!sel.isValid || sel.isCollapsed) return const [];
  return [
    ContextMenuButtonItem(
      label: "Improve with Claude",
      onPressed: () {
        field.hideToolbar();
        composer.showExtra(writingAiPanelId);
        ai.suggestions.rewrite(action: RewriteAction.improve);
      },
    ),
    ContextMenuButtonItem(
      label: "Creative AI…",
      onPressed: () {
        field.hideToolbar();
        composer.showExtra(writingAiPanelId);
      },
    ),
  ];
}
