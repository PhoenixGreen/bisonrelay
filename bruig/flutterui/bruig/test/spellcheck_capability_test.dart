import 'dart:async';

import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';

import 'plugin_test_support.dart';

// spellcheck_capability_test.dart covers the ordering the spellcheck
// capability depends on, which no amount of reading the class reveals: it is
// driven from a ChangeNotifierProxyProvider, i.e. part-way through the build
// of the very widget that is about to read `active`.

void main() {
  // The regression this pins: `active` was flipped after `await`ing the word
  // list, so a composer building in the same turn as update() read a null
  // feature switched off for the rest of its life, and never recovered.
  // Deliberately reads `active` synchronously, exactly as a composer's
  // build does, rather than pumping first.
  test("the capability is active before its words arrive", () async {
    var fetched = Completer<SpellcheckData>();
    var capability = SpellcheckCapability(fetch: () => fetched.future);

    // Not awaited: a composer's build does not await this either.
    capability.update(FakePlugins({PluginCapability.spellcheckData}));

    expect(capability.active, isTrue,
        reason: "a composer building now would get spell check turned off");

    fetched.complete(SpellcheckData(["hello"], const [], []));
    await Future.delayed(Duration.zero);
    expect(capability.active, isTrue);
  });

  test("no provider means no configuration at all", () async {
    var capability = SpellcheckCapability(fetch: () async => throw "unused");
    await capability.update(FakePlugins({}));
    expect(capability.active, isFalse);
  });

  // A provider that hasn't finished loading must not cost the user the
  // feature -- it stays on, with whatever words it already had.
  test("a failed fetch leaves the capability active", () async {
    var capability =
        SpellcheckCapability(fetch: () async => throw "not loaded");
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));
    expect(capability.active, isTrue);
  });

  // The end-to-end shape: the real provider wiring from main.dart, and a real
  // TextField, asserting the capability actually reaches the widget.
  testWidgets("a composer sees the capability active on its first build",
      (tester) async {
    var fetched = Completer<SpellcheckData>();
    var plugins = FakePlugins({PluginCapability.spellcheckData});
    bool? seen;

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
            seen = Provider.of<SpellcheckCapability>(context).active;
            return TextField(controller: WritingTextEditingController());
          }),
        ),
      ),
    ));

    expect(seen, isTrue,
        reason: "the composer's first build must already have spell check");

    fetched.complete(SpellcheckData(["hello"], const [], []));
    await tester.pumpAndSettle();
    expect(seen, isTrue);
  });
}
