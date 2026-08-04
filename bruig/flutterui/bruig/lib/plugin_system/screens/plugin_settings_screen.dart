import 'package:bruig/components/confirmation_dialog.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/plugin_system.dart';
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
                      children: model.plugins
                          .map((plugin) => Material(
                                type: MaterialType.transparency,
                                child: ListTile(
                                  title: Txt.S(plugin.manifest.name),
                                  subtitle: Txt.S(
                                      "${plugin.manifest.description} (v${plugin.manifest.version})"),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Switch(
                                        value: plugin.enabled,
                                        onChanged: (v) => setEnabled(plugin, v),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline,
                                            color: Colors.red),
                                        tooltip: "Remove plugin",
                                        onPressed: () =>
                                            confirmRemovePlugin(plugin),
                                      ),
                                    ],
                                  ),
                                ),
                              ))
                          .toList(),
                    )),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: importing ? null : importPlugin,
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text("Import Plugin"),
          ),
        ]));
  }
}
