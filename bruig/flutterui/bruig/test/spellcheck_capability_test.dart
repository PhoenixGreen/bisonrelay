import 'dart:async';

import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';

import 'plugin_test_support.dart';

// spellcheck_capability_test.dart covers the ordering the spellcheck
// capability depends on, which no amount of reading the class reveals: it is
// driven from a ChangeNotifierProxyProvider, i.e. part-way through the build
// of the very widget that is about to read `active`.

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  _languageTests();
  // The regression this pins: `active` was flipped after `await`ing the word
  // list, so a composer building in the same turn as update() read a null
  // feature switched off for the rest of its life, and never recovered.
  // Deliberately reads `active` synchronously, exactly as a composer's
  // build does, rather than pumping first.
  test("the capability is active before its words arrive", () async {
    var fetched = Completer<SpellcheckData>();
    var capability = SpellcheckCapability(fetch: (_) => fetched.future);

    // Not awaited: a composer's build does not await this either.
    capability.update(FakePlugins({PluginCapability.spellcheckData}));

    expect(capability.active, isTrue,
        reason: "a composer building now would get spell check turned off");

    fetched.complete(SpellcheckData(["hello"], const [], []));
    await Future.delayed(Duration.zero);
    expect(capability.active, isTrue);
  });

  test("no provider means no configuration at all", () async {
    var capability = SpellcheckCapability(fetch: (_) async => throw "unused");
    await capability.update(FakePlugins({}));
    expect(capability.active, isFalse);
  });

  // A provider that hasn't finished loading must not cost the user the
  // feature -- it stays on, with whatever words it already had.
  test("a failed fetch leaves the capability active", () async {
    var capability =
        SpellcheckCapability(fetch: (_) async => throw "not loaded");
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
          create: (c) => SpellcheckCapability(fetch: (_) => fetched.future),
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

// Reported: "recognised" was corrected to "recognized". The dictionary was
// American only, so every British spelling was a misspelling with the
// American form as its nearest correction.
//
// The language is a different word list rather than a filter over one --
// "colour" is in one and "color" in the other -- so changing it has to go
// back to the provider.
void _languageTests() {
  SpellcheckData dataFor(String language) => SpellcheckData(
        language == "en-GB"
            ? const ["colour", "recognise"]
            : const ["color", "recognize"],
        const [],
        const [],
        const [],
        language.isEmpty ? "en-US" : language,
        [
          SpellcheckLanguage("en-US", "English (US)"),
          SpellcheckLanguage("en-GB", "English (UK)")
        ],
      );

  test("changing the language re-reads the dictionary", () async {
    var asked = <String>[];
    var prefs = WritingPreferences();
    var capability = SpellcheckCapability(
      fetch: (language) async {
        asked.add(language);
        return dataFor(language);
      },
      prefs: prefs,
    );
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));

    expect(asked, [""], reason: "a fresh install asks for the default");
    expect(capability.review("colour"), isNotEmpty,
        reason: "the American dictionary should flag the British spelling");

    await prefs.setLanguage("en-GB");
    // The re-fetch is asynchronous, as the first load is.
    await Future<void>.delayed(Duration.zero);

    expect(asked, ["", "en-GB"],
        reason: "a filter over the old list cannot add words it never had");
    expect(capability.review("colour"), isEmpty,
        reason: "the reported bug: recognised/colour flagged under en-GB");
    expect(capability.review("color"), isNotEmpty,
        reason: "and the other spelling is the wrong one now");
  });

  test("the languages on offer come from the provider", () async {
    var capability = SpellcheckCapability(fetch: (l) async => dataFor(l));
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));

    expect(capability.languages.map((l) => l.code), ["en-US", "en-GB"]);
    expect(capability.activeLanguage, "en-US");
  });

  // A provider that serves only one language, or none at all, must not leave
  // the app asking for one it cannot have.
  test("a provider that names no language still works", () async {
    var capability = SpellcheckCapability(
        fetch: (_) async =>
            SpellcheckData(const ["hello"], const [], const []));
    await capability.update(FakePlugins({PluginCapability.spellcheckData}));

    expect(capability.languages, isEmpty);
    expect(capability.activeLanguage, isEmpty);
    expect(capability.review("hello"), isEmpty);
  });

  // Which English somebody writes is a fact about them, not a mood: it has
  // to survive a restart, or every British spelling goes back under a line.
  test("the language is persisted", () async {
    var prefs = WritingPreferences();
    await prefs.setLanguage("en-GB");

    var reloaded = WritingPreferences();
    await reloaded.load();
    expect(reloaded.language, "en-GB");
  });
  // Loading is not cheap -- 2.2MB of JSON, 120,000 words to index and 787
  // regular expressions to compile, about 100ms of it -- and update() runs
  // from a ChangeNotifierProxyProvider, so it is called whenever the plugin
  // manager notifies about anything at all. Every one of those calls used to
  // pay in full to arrive at the data already held.
  group("reloading", () {
    PluginInfo installed(String id, String version) => PluginInfo(
        PluginManifest(id, id, version, "d", "s", "dynamic-wasm", 1, const {}, [
          PluginService("spellcheck-data", "get_spellcheck_data", const [])
        ]),
        true);

    test("the same plugin set is not fetched twice", () async {
      var fetches = 0;
      var capability = SpellcheckCapability(fetch: (_) async {
        fetches++;
        return SpellcheckData(const ["the"], const [], const [], const []);
      });
      var plugins = FakePluginManager([installed("spellcheck", "1.0.0")]);

      await capability.update(plugins);
      await capability.update(plugins);
      await capability.update(plugins);
      expect(fetches, 1, reason: "nothing about the answer had changed");
    });

    test("a plugin set that moved is fetched again", () async {
      var fetches = 0;
      var capability = SpellcheckCapability(fetch: (_) async {
        fetches++;
        return SpellcheckData(const ["the"], const [], const [], const []);
      });

      await capability
          .update(FakePluginManager([installed("spellcheck", "1.0.0")]));
      // A new version of the provider: the same capability, different data.
      await capability
          .update(FakePluginManager([installed("spellcheck", "1.1.0")]));
      expect(fetches, 2, reason: "the provider changed under it");

      // And a second provider arriving is a change as well, whoever it is.
      await capability.update(FakePluginManager(
          [installed("spellcheck", "1.1.0"), installed("other", "1.0.0")]));
      expect(fetches, 3);
    });
  });
}
