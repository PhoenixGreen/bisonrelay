import 'package:bruig/components/confirmation_dialog.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';

// plugin_settings_screen.dart is the Settings > Plugins page: the list of
// installed plugins with their enable switches, plus import and remove. It is
// the only UI in the app that knows plugins exist as a concept -- everything a
// plugin actually contributes reaches the user through a capability or a nav
// item (plugin_nav.dart) instead.
//
// No capability's settings are written here. A plugin's panel carries whatever
// sections its declared capabilities registered with PluginSettingsRegistry,
// and this file never learns what any of them are.

class PluginsSettingsScreen extends StatefulWidget {
  const PluginsSettingsScreen({super.key});

  @override
  State<PluginsSettingsScreen> createState() => _PluginsSettingsScreenState();
}

class _PluginsSettingsScreenState extends State<PluginsSettingsScreen> {
  bool importing = false;

  void importPlugin() async {
    var snackbar = SnackBarModel.of(context);
    var model = Provider.of<PluginManagerModel>(context, listen: false);

    var filePickRes = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      dialogTitle: "Pick plugin folder or .zip file",
      type: FileType.custom,
      allowedExtensions: ["zip"],
    );
    if (filePickRes == null) return;
    var fPath = filePickRes.files.first.path;
    if (fPath == null) return;

    setState(() => importing = true);
    try {
      var plugin = await model.import(fPath.trim());
      snackbar.success("Imported plugin '${plugin.manifest.name}'");
    } catch (exception) {
      snackbar.error("Unable to import plugin: $exception");
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  void setEnabled(PluginInfo plugin, bool enabled) async {
    var snackbar = SnackBarModel.of(context);
    var model = Provider.of<PluginManagerModel>(context, listen: false);
    try {
      await model.setEnabled(plugin.manifest.id, enabled);
    } catch (exception) {
      snackbar.error("Unable to update plugin: $exception");
    }
  }

  void confirmRemovePlugin(PluginInfo plugin) {
    showConfirmDialog(context,
        title: "Remove plugin?",
        content: "This will uninstall '${plugin.manifest.name}' and delete "
            "any data it has stored. This cannot be undone.",
        confirmButtonText: "Remove",
        onConfirm: () => removePlugin(plugin));
  }

  void removePlugin(PluginInfo plugin) async {
    var snackbar = SnackBarModel.of(context);
    var model = Provider.of<PluginManagerModel>(context, listen: false);
    try {
      await model.remove(plugin.manifest.id);
      snackbar.success("Removed plugin '${plugin.manifest.name}'");
    } catch (exception) {
      snackbar.error("Unable to remove plugin: $exception");
    }
  }

  /// _opened is the plugin whose panel is showing, or null for none.
  ///
  /// One at a time: the panels are long -- a full description and a page of
  /// settings -- and several open at once turns the list into something that
  /// has to be scrolled past rather than read.
  String? _opened;

  void toggleOpen(PluginInfo plugin) => setState(() =>
      _opened = _opened == plugin.manifest.id ? null : plugin.manifest.id);

  @override
  Widget build(BuildContext context) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Txt.L("Plugins"),
            const Spacer(),
            // Icon only, and up here rather than under the list: importing
            // is what you come to this page to do when the list is empty,
            // and a control below the plugins is a control you have to
            // scroll past all of them to reach once it is not.
            //
            // The spinner replaces the icon rather than sitting beside it,
            // so the button keeps its size while an import runs and nothing
            // on the row moves.
            IconButton(
              onPressed: importing ? null : importPlugin,
              tooltip: "Import a plugin",
              icon: importing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_upload_outlined),
            ),
          ]),
          const SizedBox(height: 10),
          Consumer<PluginManagerModel>(
              builder: (context, model, child) => model.plugins.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Txt.S("No plugins installed."),
                    )
                  : Column(
                      children: [
                        for (var plugin in model.plugins) _pluginTile(plugin),
                      ],
                    )),
          // A capability's settings live inside the panel of whichever plugin
          // provides them, but some of them outlive it: a word added to a
          // personal dictionary is a decision about this app, and removing the
          // plugin that prompted it must not put that decision out of reach.
          // So a section whose capability nothing installed provides appears
          // here instead of vanishing.
          Consumer<PluginManagerModel>(
            builder: (context, model, child) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var section in PluginSettingsRegistry.orphaned({
                  for (var p in model.plugins)
                    for (var provided in p.manifest.provides) provided.service,
                }))
                  section(context, false),
              ],
            ),
          ),
        ]));
  }

  Widget _pluginTile(PluginInfo plugin) {
    var theme = ThemeNotifier.of(context);
    var open = _opened == plugin.manifest.id;
    return Material(
      type: MaterialType.transparency,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ListTile(
          onTap: () => toggleOpen(plugin),
          title: Row(children: [
            Flexible(child: Txt.S(plugin.manifest.name)),
            const SizedBox(width: 8),
            // The version beside the name rather than trailing the
            // description, where it read as part of the prose.
            Txt.S("v${plugin.manifest.version}",
                color: TextColor.onSurfaceVariant),
          ]),
          subtitle: Txt.S(plugin.manifest.summaryLine,
              color: TextColor.onSurfaceVariant),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Chevron first, so the two controls that change something sit
              // together at the edge rather than either side of it.
              Icon(open ? Icons.expand_less : Icons.expand_more,
                  color: theme.colors.onSurfaceVariant),
              Switch(
                value: plugin.enabled,
                onChanged: (v) => setEnabled(plugin, v),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: "Remove plugin",
                onPressed: () => confirmRemovePlugin(plugin),
              ),
            ],
          ),
        ),
        if (open) _pluginPanel(plugin, theme),
      ]),
    );
  }

  /// _pluginPanel is what a plugin has to say for itself, and what can be
  /// changed about it.
  ///
  /// Indented to the width of the title above it and closed with a divider,
  /// so a long panel still reads as belonging to the row it opened from
  /// rather than as the start of the next one.
  Widget _pluginPanel(PluginInfo plugin, ThemeNotifier theme) {
    // Which settings belong to a plugin is decided by the capabilities it
    // declares, not by its name or id. That is the same rule the rest of the
    // app follows -- nothing here asks "is this particular plugin installed",
    // only "what has registered against what this one provides".
    var settings = PluginSettingsRegistry.forCapabilities(
        [for (var provided in plugin.manifest.provides) provided.service]);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Txt.S(plugin.manifest.description, color: TextColor.onSurfaceVariant),
        // Whatever the app itself contributes for the services this plugin
        // provides -- the writing overrides, say.
        for (var section in settings) section(context, true),
        // And whatever the plugin contributes for itself. This is the slot
        // that makes a plugin's own settings possible at all: before it, a
        // plugin's only way to offer configuration was a sub-page of a nav
        // item it may not have wanted in the first place.
        PluginSlotPanel(PluginSlots.settingsPage,
            pluginId: plugin.manifest.id, headings: false),
        const SizedBox(height: 12),
        Divider(height: 1, color: theme.colors.outlineVariant),
      ]),
    );
  }
}
