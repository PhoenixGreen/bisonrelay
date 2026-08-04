import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:flutter/foundation.dart';

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
