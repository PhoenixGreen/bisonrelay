import 'package:bruig/components/snackbars.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/plugin_system/plugin_icons.dart';
import 'package:bruig/plugin_system/plugin_manager.dart';
import 'package:bruig/plugin_system/screens/widget_renderer.dart';
import 'package:bruig/theming_system/runtime/theme_tokens.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/golib_plugin.dart';
import 'package:provider/provider.dart';

// plugin_slots.dart is how a plugin appears somewhere other than its own tab.
//
// A slot is a named surface this app publishes. A plugin's manifest says what
// it contributes to which slot; the app draws whatever turns up, by asking the
// module for a widget tree exactly as it already does for a screen. A slot is
// a screen with somewhere to be drawn, and that is the whole of the idea.
//
// The trade is deliberate and worth stating, because it is what makes the
// system extensible rather than merely configurable. The APP owns the list of
// slots -- there is a finite number of places worth putting a plugin, and each
// costs one line where the app already draws. PLUGINS compose freely within
// them, at a cost of nothing: a new plugin contributing to five slots requires
// no change here or anywhere else.
//
// A slot this build does not draw is carried and ignored rather than rejected,
// so a plugin can target a newer host and lose only the parts that host had.
// That is the same rule the widget renderer follows for an unknown widget, and
// for the same reason.

/// PluginSlots are the surfaces this build publishes. They must match the
/// Slot* constants in client/pluginmgr -- the Go side documents them for
/// plugin authors, and neither side treats the list as an allowlist.
class PluginSlots {
  PluginSlots._();

  /// A top-level nav item with its own screens. The original slot, and still
  /// the only one whose contribution may carry sub-pages.
  static const nav = "nav";

  /// A page inside this plugin's panel in Settings > Plugins. Where a
  /// plugin's own configuration belongs, rather than as a sub-page of a nav
  /// item it may not otherwise want.
  static const settingsPage = "settingsPage";

  /// An action in a message composer's toolbar.
  static const composerAction = "composerAction";

  /// An entry in the menu opened on a message or a post.
  static const messageAction = "messageAction";

  /// A panel in the post editor's sidebar, beside the writing tools and the
  /// saved-post library.
  static const sidebarPanel = "sidebarPanel";
}

/// SlotEntry is one plugin's contribution to a slot, with the plugin it came
/// from -- which the renderer needs in order to call back into it, and which
/// nothing else should use to decide anything.
class SlotEntry {
  final String pluginId;
  final PluginContribution contribution;
  const SlotEntry(this.pluginId, this.contribution);

  String get id => contribution.id;
  String get label => contribution.label;
  IconData? get icon => pluginIconOrNull(contribution.icon);
}

/// slotEntries lists what the currently enabled plugins contribute to [slot],
/// in plugin-id order so the same set always draws the same way round.
///
/// Reads from [PluginManagerModel] rather than holding its own state: which
/// plugins are enabled is one fact with one owner, and a slot is only ever a
/// view of it.
List<SlotEntry> slotEntries(PluginManagerModel plugins, String slot) {
  var out = <SlotEntry>[];
  for (var plugin in plugins.plugins) {
    if (!plugin.enabled) continue;
    for (var contribution in plugin.manifest.contributionsTo(slot)) {
      out.add(SlotEntry(plugin.manifest.id, contribution));
    }
  }
  out.sort((a, b) => a.pluginId.compareTo(b.pluginId));
  return out;
}

/// PluginContributionView renders one contribution: it asks the plugin for a
/// widget tree, draws it, and sends activations back.
///
/// This is the piece every slot is built from, and the same piece
/// PluginScreen uses for a nav item's pages. Whether a contribution ends up
/// inline in a settings panel, inside a dialog opened from a toolbar, or as a
/// whole page is the slot's business; what it contains is always this.
class PluginContributionView extends StatefulWidget {
  final String pluginId;

  /// The screen id to render -- a contribution's own id, or one of its
  /// sub-pages.
  final String screenId;

  /// showTitle draws the title the plugin gave its screen. Off where the
  /// surrounding surface already names the contribution, which would
  /// otherwise say it twice.
  final bool showTitle;

  const PluginContributionView({
    required this.pluginId,
    required this.screenId,
    this.showTitle = false,
    super.key,
  });

  @override
  State<PluginContributionView> createState() => _PluginContributionViewState();
}

class _PluginContributionViewState extends State<PluginContributionView> {
  final PluginUiState _uiState = PluginUiState();
  DynScreenUI? _ui;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PluginContributionView old) {
    super.didUpdateWidget(old);
    if (old.pluginId != widget.pluginId || old.screenId != widget.screenId) {
      _load();
    }
  }

  @override
  void dispose() {
    _uiState.dispose();
    super.dispose();
  }

  void _load() async {
    setState(() => _loading = true);
    try {
      var ui = await Golib.renderDynPluginScreen(widget.pluginId, widget.screenId);
      if (!mounted) return;
      setState(() {
        _ui = ui;
        _error = null;
        _loading = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        _error = "$exception";
        _loading = false;
      });
    }
  }

  void _onEvent(String event, Map<String, dynamic> payload) async {
    if (event.isEmpty) return;
    try {
      var ui = await Golib.handleDynPluginEvent(
          widget.pluginId, widget.screenId, event, payload);
      if (!mounted) return;
      setState(() => _ui = ui);
      _uiState.syncToUi(ui.widgets);
    } catch (exception) {
      if (!mounted) return;
      showErrorSnackbar(context, "Unable to perform action: $exception");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Txt.S("Unable to render: $_error", color: TextColor.error),
      );
    }
    var ui = _ui;
    if (ui == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showTitle && ui.title.isNotEmpty) ...[
          Txt.L(ui.title),
          const SizedBox(height: 8),
        ],
        ...buildPluginWidgets(
          context,
          ui.widgets,
          root: ui.widgets,
          state: _uiState,
          onEvent: _onEvent,
        ),
        // A screen that has finished loading and drew nothing is a plugin
        // saying it has nothing to show right now, not a failure -- but an
        // empty panel with no explanation reads as broken.
        if (ui.widgets.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Txt.S("Nothing to show.", color: TextColor.onSurfaceVariant),
          ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }
}

/// PluginSlotPanel draws every contribution to [slot], one after another,
/// inline. For the slots that are a place on a page rather than a control:
/// a settings section, a sidebar panel.
///
/// Draws nothing at all when no plugin contributes, so a caller can place it
/// unconditionally and forget about it.
class PluginSlotPanel extends StatelessWidget {
  final String slot;

  /// pluginId limits the panel to one plugin's contributions, for a surface
  /// that is already about a particular plugin -- its row in Settings.
  final String? pluginId;

  /// heading draws each contribution's label above it. Off where the
  /// surrounding surface already names them.
  final bool headings;

  const PluginSlotPanel(this.slot,
      {this.pluginId, this.headings = true, super.key});

  @override
  Widget build(BuildContext context) {
    var plugins = context.watch<PluginManagerModel>();
    var entries = slotEntries(plugins, slot)
        .where((e) => pluginId == null || e.pluginId == pluginId)
        .toList();
    if (entries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var entry in entries) ...[
          if (headings)
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Row(children: [
                if (entry.icon != null) ...[
                  Icon(entry.icon, size: 16),
                  const SizedBox(width: 6),
                ],
                Txt.S(entry.label,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ),
          PluginContributionView(
            // Keyed so switching between two plugins' contributions starts a
            // fresh render rather than showing the previous one's tree.
            key: ValueKey("${entry.pluginId}/${entry.id}"),
            pluginId: entry.pluginId,
            screenId: entry.id,
          ),
        ],
      ],
    );
  }
}

/// PluginSlotActions is a row of icon buttons, one per contribution to
/// [slot], each opening the plugin's UI in a dialog. For the slots that are a
/// control rather than a place: a composer toolbar.
///
/// An empty row when nothing contributes, so a toolbar can include it
/// unconditionally.
class PluginSlotActions extends StatelessWidget {
  final String slot;
  final double iconSize;

  const PluginSlotActions(this.slot, {this.iconSize = 20, super.key});

  @override
  Widget build(BuildContext context) {
    var plugins = context.watch<PluginManagerModel>();
    var entries = slotEntries(plugins, slot);
    if (entries.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var entry in entries)
          IconButton(
            iconSize: iconSize,
            tooltip: entry.label,
            // A contribution with no icon still needs something pressable;
            // the generic plugin marker says "this came from a plugin",
            // which is the honest thing for it to say.
            icon: Icon(entry.icon ?? pluginIcon("")),
            onPressed: () => showPluginContributionDialog(context, entry),
          ),
      ],
    );
  }
}

/// pluginSlotMenuItems is [slot]'s contributions as entries for a text
/// selection or context menu, each opening the plugin's UI in a dialog.
///
/// Returns nothing when no plugin contributes, which a caller splices into
/// its own menu with `...` and never has to test for.
List<ContextMenuButtonItem> pluginSlotMenuItems(
  BuildContext context,
  String slot, {
  VoidCallback? beforeOpen,
}) {
  var plugins = context.read<PluginManagerModel>();
  return [
    for (var entry in slotEntries(plugins, slot))
      ContextMenuButtonItem(
        label: entry.label,
        onPressed: () {
          // The caller usually has a toolbar to dismiss first: leaving it up
          // puts two overlapping popups on screen, anchored to the same spot.
          beforeOpen?.call();
          showPluginContributionDialog(context, entry);
        },
      ),
  ];
}

/// showPluginContributionDialog opens one contribution in a dialog, for the
/// slots whose surface is too small to hold a widget tree.
Future<void> showPluginContributionDialog(
        BuildContext context, SlotEntry entry) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(entry.label),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: PluginContributionView(
              pluginId: entry.pluginId,
              screenId: entry.id,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Close"),
          ),
        ],
      ),
    );
