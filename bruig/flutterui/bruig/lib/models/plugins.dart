import 'package:flutter/foundation.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/golib_plugin.dart';

class PluginsModel extends ChangeNotifier {
  List<PluginInfo> _plugins = [];
  List<PluginInfo> get plugins => _plugins;

  bool get prettyLinksActive => _plugins.any(
      (p) => p.enabled && p.manifest.rendererKind == "link-card");

  bool get spellcheckActive => _plugins.any(
      (p) => p.enabled && p.manifest.rendererKind == "spellcheck");

  SpellcheckData _spellcheckData = SpellcheckData([], []);
  SpellcheckData get spellcheckData => _spellcheckData;

  Future<void> reload() async {
    _plugins = await Golib.listPlugins();
    _spellcheckData = spellcheckActive
        ? await Golib.getSpellcheckData()
        : SpellcheckData([], []);
    notifyListeners();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await Golib.setPluginEnabled(id, enabled);
    await reload();
  }

  Future<PluginInfo> import(String path) async {
    var info = await Golib.importPlugin(path);
    await reload();
    return info;
  }

  Future<void> remove(String id) async {
    await Golib.removePlugin(id);
    await reload();
  }
}
