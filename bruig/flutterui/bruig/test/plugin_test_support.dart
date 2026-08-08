import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:flutter/foundation.dart';
import 'package:golib_plugin/definitions.dart';

/// FakePlugins stands in for PluginManagerModel's capability reporting. The
/// real one populates itself from a running client, which a unit test has
/// no way to provide.
class FakePlugins extends ChangeNotifier implements PluginManagerModel {
  Set<PluginCapability> present;
  FakePlugins(this.present);

  @override
  bool hasCapability(PluginCapability capability) =>
      present.contains(capability);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// FakePluginManager stands in for the real model on the Plugins page, which
/// needs the list itself rather than only the capability question FakePlugins
/// answers.
class FakePluginManager extends ChangeNotifier implements PluginManagerModel {
  final List<PluginInfo> _plugins;
  FakePluginManager(this._plugins);

  @override
  List<PluginInfo> get plugins => _plugins;

  @override
  bool hasCapability(PluginCapability capability) => _plugins.any((p) =>
      p.enabled && p.manifest.capabilities.contains(capability.wireName));

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
