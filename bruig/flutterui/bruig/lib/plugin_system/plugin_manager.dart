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

  // _services is the flattened set of service names the currently enabled
  // plugins provide, recomputed on each reload. Precomputed rather than
  // scanned per query because these are read from build().
  Set<String> _services = const {};

  // hasCapability reports whether any enabled plugin provides it. This is
  // the whole query surface the rest of the app has: everything downstream
  // is written against the service, not against its provider.
  bool hasCapability(PluginCapability capability) =>
      hasService(capability.wireName);

  /// hasService is the same question for a service the app has no enum value
  /// for -- one plugin asking whether another is installed, or a feature
  /// written against a name that arrived after this build did.
  bool hasService(String service) => _services.contains(service);

  // _serviceDomains maps a service to the hostnames its enabled providers
  // claim, and _openServices names the services some enabled provider left
  // unnarrowed. Both recomputed on each reload, for the same reason as
  // _services: they are read from build().
  Map<String, Set<String>> _serviceDomains = const {};
  Set<String> _openServices = const {};

  /// claimsUrl reports whether an enabled provider of [capability] claims
  /// this particular URL.
  ///
  /// Narrower than hasCapability, and the difference matters. A link-card
  /// provider declares the hostnames it knows -- YouTube and X, for the one
  /// that ships -- and says nothing about the rest of the web. Asking only
  /// whether *some* provider is installed treats every URL as a card, and a
  /// link nothing will unfurl then gets laid out as one: a bare URL alone in
  /// a column, wrapped over five lines, where a preview should have been.
  ///
  /// A provider that declares no domains claims everything, which is what
  /// "domains narrows which hostnames this provider claims" means when it is
  /// left out.
  bool claimsUrl(PluginCapability capability, String url) {
    var service = capability.wireName;
    if (!hasService(service)) return false;
    if (_openServices.contains(service)) return true;

    var domains = _serviceDomains[service];
    if (domains == null || domains.isEmpty) return false;

    String host;
    try {
      host = Uri.parse(url).host.toLowerCase();
    } catch (_) {
      return false;
    }
    if (host.isEmpty) return false;
    // A declared "youtube.com" covers "www.youtube.com", so a subdomain
    // counts -- but only on a label boundary, or "notyoutube.com" would too.
    return domains.any((d) => host == d || host.endsWith(".$d"));
  }

  /// servicesProvided is every service name the enabled plugins answer,
  /// whether or not anything consumes them. For a settings page that wants
  /// to show what is on offer.
  Set<String> get servicesProvided => Set.unmodifiable(_services);

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

    applyPlugins(loaded);
  }

  /// applyPlugins takes the loaded list and works out everything asked of it
  /// afterwards -- which services are on offer, and which hostnames their
  /// providers claim.
  ///
  /// Separate from reload() only so it can be driven without a running
  /// client: the bookkeeping below is what the rest of the app's answers are
  /// made of, and a test faking it would be testing the fake.
  @protected
  @visibleForTesting
  void applyPlugins(List<PluginInfo> loaded) {
    _plugins = loaded;
    _services = {
      for (var p in loaded)
        if (p.enabled)
          for (var provided in p.manifest.provides) provided.service,
    };

    var domains = <String, Set<String>>{};
    var open = <String>{};
    for (var p in loaded) {
      if (!p.enabled) continue;
      for (var provided in p.manifest.provides) {
        if (provided.domains.isEmpty) {
          open.add(provided.service);
          continue;
        }
        domains
            .putIfAbsent(provided.service, () => <String>{})
            .addAll(provided.domains.map((d) => d.toLowerCase()));
      }
    }
    _serviceDomains = domains;
    _openServices = open;

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
