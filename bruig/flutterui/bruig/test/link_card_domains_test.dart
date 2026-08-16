import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';

// link_card_domains_test.dart covers PluginManagerModel.claimsUrl: whether a
// particular URL is one an enabled provider will actually unfurl.
//
// Reported: a bare zerohedge.com link was laid out as a preview card -- alone
// in the feed's media column, wrapped over five lines -- because the app
// asked only whether *some* link-card provider was installed. A provider
// declares the hostnames it knows and says nothing about the rest of the web,
// so the question has to be asked per URL.

/// _manager is a plugin manager reporting one link-card provider claiming
/// [domains], or no provider at all when [enabled] is false.
PluginManagerModel _manager(
    {List<String> domains = const [], bool enabled = true}) {
  var manifest = PluginManifest(
    "prettylinks",
    "Pretty Links",
    "1.0.0",
    "d",
    "s",
    "dynamic-wasm",
    1,
    const {},
    [PluginService(PluginCapability.linkCard.wireName, "", domains)],
  );
  var model = _TestPlugins();
  model.load([PluginInfo(manifest, enabled)]);
  return model;
}

/// _TestPlugins is the real model with its one client call replaced.
///
/// Subclassed rather than faked, because what is under test is precisely the
/// domain bookkeeping the real reload() does -- a fake reimplementing it
/// would be testing the fake.
class _TestPlugins extends PluginManagerModel {
  void load(List<PluginInfo> plugins) => applyPlugins(plugins);
}

void main() {
  const claimed = "https://www.youtube.com/watch?v=abc";
  const unclaimed = "https://www.zerohedge.com/technology/china-cxmt";

  test("a host a provider declares is claimed", () {
    var plugins = _manager(domains: ["youtube.com", "x.com"]);
    expect(plugins.claimsUrl(PluginCapability.linkCard, claimed), isTrue);
  });

  test("a host no provider declares is not claimed", () {
    var plugins = _manager(domains: ["youtube.com", "x.com"]);
    expect(plugins.claimsUrl(PluginCapability.linkCard, unclaimed), isFalse);
  });

  // "youtube.com" covers "www.youtube.com", but only on a label boundary --
  // "notyoutube.com" is a different site entirely.
  test("a subdomain counts, a lookalike does not", () {
    var plugins = _manager(domains: ["youtube.com"]);
    expect(
        plugins.claimsUrl(PluginCapability.linkCard, "https://m.youtube.com/x"),
        isTrue);
    expect(
        plugins.claimsUrl(
            PluginCapability.linkCard, "https://notyoutube.com/x"),
        isFalse);
  });

  test("a disabled provider claims nothing", () {
    var plugins = _manager(domains: ["youtube.com"], enabled: false);
    expect(plugins.claimsUrl(PluginCapability.linkCard, claimed), isFalse);
  });

  test("no provider at all claims nothing", () {
    var model = _TestPlugins();
    model.load(const []);
    expect(model.claimsUrl(PluginCapability.linkCard, claimed), isFalse);
  });

  // Leaving domains out is what "domains narrows which hostnames this
  // provider claims" means when it is not said: the provider takes anything.
  test("a provider that narrows nothing claims everything", () {
    var plugins = _manager();
    expect(plugins.claimsUrl(PluginCapability.linkCard, claimed), isTrue);
    expect(plugins.claimsUrl(PluginCapability.linkCard, unclaimed), isTrue);
  });

  test("something that is not a URL is not claimed", () {
    var plugins = _manager(domains: ["youtube.com"]);
    expect(plugins.claimsUrl(PluginCapability.linkCard, "not a url"), isFalse);
  });
}
