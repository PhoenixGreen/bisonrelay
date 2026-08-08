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
// installed plugins with their enable switches, plus import and remove.
// It is the only UI in the app that knows plugins exist as a concept --
// everything a plugin actually contributes reaches the user through a
// capability (see plugin_system/capabilities/) or a nav item (plugin_nav
// .dart) instead.

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
          const Txt.L("Plugins"),
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
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: importing ? null : importPlugin,
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text("Import Plugin"),
          ),
          // The writing overrides live inside the panel of whichever plugin
          // provides them, but they outlive it: a word added to the personal
          // dictionary is a decision about this app, and removing the plugin
          // that prompted it must not put that decision out of reach. So
          // when nothing installed provides the capability, they appear here
          // instead of vanishing.
          Consumer<PluginManagerModel>(
            builder: (context, model, child) => model.plugins.any((p) => p
                    .manifest.capabilities
                    .contains(PluginCapability.spellcheckData.wireName))
                ? const SizedBox.shrink()
                : const WritingOverridesSection(),
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
    // app follows -- nothing here asks "is the writing tools plugin
    // installed", only "does this plugin provide the writing data".
    var settings = <Widget>[
      if (plugin.manifest.capabilities
          .contains(PluginCapability.spellcheckData.wireName))
        const WritingOverridesSection(inPluginPanel: true),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Txt.S(plugin.manifest.description, color: TextColor.onSurfaceVariant),
        ...settings,
        const SizedBox(height: 12),
        Divider(height: 1, color: theme.colors.outlineVariant),
      ]),
    );
  }
}

/// WritingOverridesSection lists what the user has told the writing tools to
/// stop reporting, and takes it back.
///
/// It belongs on this page because the overrides outlive any one plugin --
/// they are decisions about the user's own app, and a word added to the
/// dictionary must stay ignored across a provider being updated or swapped.
/// Somewhere to undo them matters more than usual: an accidental "Add to
/// dictionary" on a genuine typo is otherwise invisible and permanent.
///
/// Absent entirely until something has been overridden, so the page is
/// unchanged for anyone who has never used it.
class WritingOverridesSection extends StatelessWidget {
  /// inPluginPanel drops the heading and the rule above it. Inside a panel
  /// the plugin's name is already at the top and the panel has its own
  /// divider, so both would be saying a second time what the surroundings
  /// already say.
  final bool inPluginPanel;

  const WritingOverridesSection({this.inPluginPanel = false, super.key});

  @override
  Widget build(BuildContext context) {
    var prefs = context.watch<WritingPreferences>();
    var spellcheck = context.watch<SpellcheckCapability?>();
    var languages = spellcheck?.languages ?? const <SpellcheckLanguage>[];

    // Nothing to show at all when no provider offers a choice and nothing
    // has been overridden. A section that is always there but usually empty
    // is a section people learn to skip.
    if (languages.length < 2 &&
        prefs.personalDictionary.isEmpty &&
        prefs.disabledChecks.isEmpty) {
      return const SizedBox.shrink();
    }

    var words = prefs.personalDictionary.toList()..sort();
    var checks = prefs.disabledChecks.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (!inPluginPanel) ...[
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 8),
        const Txt.L("Writing tools"),
      ],
      const SizedBox(height: 16),
      // Offered only when a provider has more than one to offer, and built
      // from what it says it has rather than from a list held here: the
      // languages are the provider's, and an app-side list would go stale
      // the moment one shipped another.
      if (languages.length > 1) ...[
        const Txt.S("Language", color: TextColor.onSurfaceVariant),
        const SizedBox(height: 6),
        DropdownButton<String>(
          value: languages.any((l) => l.code == spellcheck!.activeLanguage)
              ? spellcheck!.activeLanguage
              : null,
          hint: const Txt.S("Choose a language"),
          items: [
            for (var language in languages)
              DropdownMenuItem(
                  value: language.code, child: Txt.S(language.name)),
          ],
          onChanged: (code) {
            if (code != null) prefs.setLanguage(code);
          },
        ),
        const SizedBox(height: 6),
        const Txt.S(
            "Changes which dictionary your writing is checked against. "
            "\"Colour\" and \"color\" are each correct in one and wrong in "
            "the other.",
            color: TextColor.onSurfaceVariant),
        const SizedBox(height: 16),
      ],
      if (words.isNotEmpty) ...[
        const Txt.S("Words added to your dictionary",
            color: TextColor.onSurfaceVariant),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var word in words)
              InputChip(
                label: Text(word),
                onDeleted: () => prefs.removeFromDictionary(word),
                tooltip: "Check this word again",
              ),
          ],
        ),
        const SizedBox(height: 16),
      ],
      if (checks.isNotEmpty) ...[
        const Txt.S("Checks you turned off", color: TextColor.onSurfaceVariant),
        const SizedBox(height: 6),
        // Shown by the rule's own description. A check is identified by its
        // pattern, which is what makes a rule unique, but a regular
        // expression is not something to put in front of anyone -- it only
        // appears as a fallback for an entry saved before descriptions were
        // recorded.
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var check in checks)
              InputChip(
                label: Text(check.value.isEmpty ? check.key : check.value),
                onDeleted: () => prefs.enableCheck(check.key),
                tooltip: "Turn this check back on",
              ),
          ],
        ),
      ],
    ]);
  }
}
