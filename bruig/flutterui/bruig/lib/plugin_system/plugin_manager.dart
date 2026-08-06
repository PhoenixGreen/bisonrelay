import 'package:bruig/plugin_system/plugin_capability.dart';
import 'package:flutter/foundation.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/golib_plugin.dart';

// PluginManagerModel is the app's view of which plugins are installed and
// enabled. It is deliberately the *only* thing in the app that holds that
// list, and it knows nothing about what any individual plugin does: a
// consumer asks whether some capability is available (see PluginCapability),
// never whether a named plugin is installed.
class PluginManagerModel extends ChangeNotifier {
  List<PluginInfo> _plugins = const [];
  List<PluginInfo> get plugins => _plugins;

  // _capabilities is the flattened set of capabilities the currently enabled
  // plugins provide, recomputed on each reload. Precomputed rather than
  // scanned per query because hasCapability is read from build().
  Set<String> _capabilities = const {};

  // hasCapability reports whether any enabled plugin provides it. This is
  // the whole query surface the rest of the app has: everything downstream
  // is written against the capability, not against its provider.
  bool hasCapability(PluginCapability capability) =>
      _capabilities.contains(capability.wireName);

  // _reloadRetriesLeft guards against retrying forever on a genuine,
  // persistent error -- this is specifically a safety net for the transient
  // "client not started yet" race below, not general error handling.
  int _reloadRetriesLeft = 10;

  Future<void> reload() async {
    List<PluginInfo> loaded;
    try {
      loaded = await Golib.listPlugins();
    } catch (exception) {
      // The very first reload() runs at app startup, before the client
      // handle is necessarily registered, and can lose that race with
      // "unknown client handle". Without a retry that leaves the list
      // permanently empty for the rest of the session -- nothing calls
      // reload() again until a user action (e.g. importing a plugin)
      // happens to trigger one.
      if (_reloadRetriesLeft <= 0) rethrow;
      _reloadRetriesLeft--;
      Future.delayed(const Duration(seconds: 1), reload);
      return;
    }

    _plugins = loaded;
    _capabilities = {
      for (var p in loaded)
        if (p.enabled) ...p.manifest.capabilities,
    };
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
