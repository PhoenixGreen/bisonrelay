import 'dart:async';

import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';

// spellcheck_capability_test.dart covers the ordering the spellcheck
// capability depends on, which no amount of reading the class reveals: it is
// driven from a ChangeNotifierProxyProvider, i.e. part-way through the build
// of the very widget that is about to read `configuration`.

// _FakePlugins stands in for PluginManagerModel's capability reporting. The
// real one needs a running client to populate itself.
class _FakePlugins extends ChangeNotifier implements PluginManagerModel {
  Set<PluginCapability> present;
  _FakePlugins(this.present);

  @override
  bool hasCapability(PluginCapability capability) =>
      present.contains(capability);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // The regression this pins: `active` was flipped after `await`ing the word
  // list, so a composer building in the same turn as update() read a null
  // configuration -- Flutter's "spell check off" -- and never recovered.
  // Deliberately reads `configuration` synchronously, exactly as a composer's
  // build does, rather than pumping first.
  test("the capability is active before its words arrive", () async {
    var fetched = Completer<SpellcheckData>();
    var capability = SpellcheckCapability(fetch: () => fetched.future);

    // Not awaited: a composer's build does not await this either.
    capability.update(_FakePlugins({PluginCapability.spellcheckData}));

    expect(capability.configuration, isNotNull,
        reason: "a composer building now would get spell check turned off");

    fetched.complete(SpellcheckData(["hello"], []));
    await Future.delayed(Duration.zero);
    expect(capability.configuration, isNotNull);
  });

  test("no provider means no configuration at all", () async {
    var capability = SpellcheckCapability(fetch: () async => throw "unused");
    await capability.update(_FakePlugins({}));
    expect(capability.configuration, isNull);
  });

  // A provider that hasn't finished loading must not cost the user the
  // feature -- it stays on, with whatever words it already had.
  test("a failed fetch leaves the capability active", () async {
    var capability =
        SpellcheckCapability(fetch: () async => throw "not loaded");
    await capability.update(_FakePlugins({PluginCapability.spellcheckData}));
    expect(capability.configuration, isNotNull);
  });

  // The end-to-end shape: the real provider wiring from main.dart, and a real
  // TextField, asserting the configuration actually reaches the widget.
  testWidgets("a composer receives the configuration through the provider",
      (tester) async {
    var fetched = Completer<SpellcheckData>();
    var plugins = _FakePlugins({PluginCapability.spellcheckData});
    SpellCheckConfiguration? seen;

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<PluginManagerModel>.value(value: plugins),
        ChangeNotifierProxyProvider<PluginManagerModel, SpellcheckCapability>(
          create: (c) => SpellcheckCapability(fetch: () => fetched.future),
          update: (c, p, capability) => capability!..update(p),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            seen = Provider.of<SpellcheckCapability>(context).configuration;
            return TextField(spellCheckConfiguration: seen);
          }),
        ),
      ),
    ));

    expect(seen, isNotNull,
        reason: "the composer's first build must already have spell check");

    fetched.complete(SpellcheckData(["hello"], []));
    await tester.pumpAndSettle();
    expect(seen, isNotNull);
  });
}
