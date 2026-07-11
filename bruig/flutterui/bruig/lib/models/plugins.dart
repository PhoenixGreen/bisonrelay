import 'package:flutter/foundation.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/golib_plugin.dart';

class PluginsModel extends ChangeNotifier {
  List<PluginInfo> _plugins = [];
  List<PluginInfo> get plugins => _plugins;

  bool get prettyLinksActive => _plugins.any(
      (p) => p.enabled && p.manifest.capabilities.contains("link-card"));

  bool get spellcheckActive => _plugins.any(
      (p) => p.enabled && p.manifest.capabilities.contains("spellcheck-data"));

  SpellcheckData _spellcheckData = SpellcheckData([], []);
  SpellcheckData get spellcheckData => _spellcheckData;

  // reloadRetriesLeft guards against retrying forever on a genuine,
  // persistent error -- this is specifically a safety net for the
  // transient "client not started yet" race below, not general error
  // handling.
  int _reloadRetriesLeft = 10;

  Future<void> reload() async {
    try {
      _plugins = await Golib.listPlugins();
    } catch (exception) {
      // The very first reload() (triggered eagerly at app startup by
      // DynPluginsModel, which must build before the client handle is
      // necessarily registered) can race client startup and throw
      // "unknown client handle". Without a retry, that leaves _plugins
      // permanently empty for the rest of the session -- nothing else
      // automatically calls reload() again until a user action (e.g.
      // importing a plugin) happens to trigger one.
      if (_reloadRetriesLeft <= 0) rethrow;
      _reloadRetriesLeft--;
      Future.delayed(const Duration(seconds: 1), reload);
      return;
    }
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
