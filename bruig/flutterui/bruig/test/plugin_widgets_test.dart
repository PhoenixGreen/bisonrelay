import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:bruig/plugin_system/screens/widget_renderer.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';

import 'plugin_test_support.dart';

// plugin_widgets_test.dart covers what a plugin is able to draw, which is the
// whole of what a plugin is able to do in any slot -- so a gap here is a gap
// in every plugin at once.
//
// The renderer degrades silently by design: an unknown widget type draws
// nothing rather than failing the screen, so that a plugin built against a
// later host loses only the parts this one lacks. That is the right
// behaviour and it is also why this file has to exist. A widget type that is
// documented but not implemented looks exactly like a widget type a plugin
// got wrong, and "section" was in that state -- named in the Go ABI, absent
// from the renderer, drawing nothing at all -- for as long as both existed.

/// _widget builds one node. The generated model takes fourteen positional
/// arguments, almost all of which are empty for any given widget type, so
/// every test would otherwise be mostly commas.
DynWidget _widget(
  String type, {
  String text = "",
  String hint = "",
  String value = "",
  bool boolValue = false,
  String name = "",
  String event = "",
  String openUrl = "",
  bool danger = false,
  bool muted = false,
  List<DynWidget> items = const [],
  Map<String, dynamic> props = const {},
}) =>
    DynWidget(type, text, hint, value, boolValue, name, event, openUrl, danger,
        muted, false, false, items, props);

/// _pumpTree renders [widgets] the way a slot or a screen would, and reports
/// the events they fire.
Future<List<(String, Map<String, dynamic>)>> _pumpTree(
  WidgetTester tester,
  List<DynWidget> widgets,
) async {
  var fired = <(String, Map<String, dynamic>)>[];
  var state = PluginUiState();
  addTearDown(state.dispose);

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ListView(
            children: buildPluginWidgets(
              context,
              widgets,
              root: widgets,
              state: state,
              onEvent: (event, payload) => fired.add((event, payload)),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return fired;
}

void main() {
  // The regression this file was written for. "section" was documented in
  // wasmhost.Widget's own comment as the grouping type, and the renderer had
  // no case for it -- so a plugin following the published ABI had that part
  // of its screen silently discarded, along with everything nested inside it.
  testWidgets("a section draws its heading and its children", (tester) async {
    await _pumpTree(tester, [
      _widget("section", text: "Feeds", items: [
        _widget("text", text: "inside the section"),
      ]),
    ]);

    expect(find.text("Feeds"), findsOneWidget);
    expect(find.text("inside the section"), findsOneWidget,
        reason: "a section that drops its children loses the whole group");
  });

  testWidgets("an unknown widget type is skipped, not fatal", (tester) async {
    await _pumpTree(tester, [
      _widget("text", text: "before"),
      _widget("something-a-later-host-added", text: "invisible"),
      _widget("text", text: "after"),
    ]);

    expect(find.text("invisible"), findsNothing);
    expect(find.text("before"), findsOneWidget);
    expect(find.text("after"), findsOneWidget,
        reason: "an unknown widget must not take the rest of the screen down");
  });

  group("the widget vocabulary", () {
    testWidgets("row, column and card group their children", (tester) async {
      await _pumpTree(tester, [
        _widget("row", items: [_widget("text", text: "in a row")]),
        _widget("column", items: [_widget("text", text: "in a column")]),
        _widget("card", text: "Card", items: [_widget("text", text: "in a card")]),
      ]);

      expect(find.text("in a row"), findsOneWidget);
      expect(find.text("in a column"), findsOneWidget);
      expect(find.text("in a card"), findsOneWidget);
      expect(find.text("Card"), findsOneWidget);
    });

    testWidgets("a checkbox reports its own name", (tester) async {
      var fired = await _pumpTree(tester, [
        _widget("checkbox", text: "Notify me", name: "notify", event: "set"),
      ]);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      expect(fired, hasLength(1));
      expect(fired.first.$1, "set");
      expect(fired.first.$2["notify"], true);
    });

    testWidgets("a dropdown offers its options and reports the choice",
        (tester) async {
      var fired = await _pumpTree(tester, [
        _widget("dropdown",
            name: "lang",
            value: "en-US",
            event: "chooseLanguage",
            props: {
              "options": [
                {"value": "en-US", "label": "English (US)"},
                {"value": "en-GB", "label": "English (UK)"},
              ]
            }),
      ]);

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text("English (UK)").last);
      await tester.pumpAndSettle();

      expect(fired, hasLength(1));
      expect(fired.first.$2["lang"], "en-GB");
    });

    // A plugin whose values and labels are the same thing should not have to
    // write both, so a bare list of strings is accepted too.
    testWidgets("a dropdown accepts bare string options", (tester) async {
      await _pumpTree(tester, [
        _widget("dropdown",
            name: "size",
            value: "medium",
            props: {
              "options": ["small", "medium", "large"]
            }),
      ]);

      expect(find.text("medium"), findsOneWidget);
    });

    testWidgets("an image renders bytes the plugin supplied", (tester) async {
      // A 1x1 transparent PNG, which is enough to prove the decode path.
      const png =
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";
      await _pumpTree(tester, [
        _widget("image", props: {"dataB64": png}),
      ]);

      expect(find.byType(Image), findsOneWidget);
    });

    // A plugin can send bytes that are not an image at all; that is its
    // mistake to make and must not take the screen with it.
    testWidgets("a broken image draws nothing", (tester) async {
      await _pumpTree(tester, [
        _widget("text", text: "still here"),
        _widget("image", props: {"dataB64": "not base64 at all!!"}),
      ]);

      expect(find.text("still here"), findsOneWidget);
    });

    testWidgets("props are coerced rather than trusted", (tester) async {
      // A size written as a string and a progress value out of range: both
      // are things a plugin will send, and neither may throw.
      await _pumpTree(tester, [
        _widget("spacer", props: {"size": "24"}),
        _widget("progress", props: {"value": 5}),
        _widget("icon", props: {"icon": "no-such-icon", "size": "not a number"}),
        _widget("text", text: "survived"),
      ]);

      expect(find.text("survived"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group("what a button submits", () {
    testWidgets("a button carries every named field on the screen",
        (tester) async {
      var widgets = [
        _widget("textfield", name: "url", value: "https://example.com/feed"),
        _widget("switch", name: "auto", boolValue: true),
        _widget("row", items: [
          _widget("button", text: "Add", event: "addFeed"),
        ]),
      ];
      var fired = await _pumpTree(tester, widgets);

      await tester.tap(find.text("Add"));
      await tester.pumpAndSettle();

      expect(fired, hasLength(1));
      expect(fired.first.$1, "addFeed");
      // Gathered from the whole tree, not just the button's own row -- a
      // nested button still submits the form around it.
      expect(fired.first.$2["url"], "https://example.com/feed");
      expect(fired.first.$2["auto"], true);
    });

    testWidgets("a per-item button adds its own value", (tester) async {
      var fired = await _pumpTree(tester, [
        _widget("button", text: "Remove", event: "removeFeed", value: "feed-7"),
      ]);

      await tester.tap(find.text("Remove"));
      await tester.pumpAndSettle();

      expect(fired.first.$2["value"], "feed-7");
    });
  });

  // A widget tree is data, never code -- that is what makes it safe to draw a
  // plugin's UI in the app's own surfaces. openUrl is the one place a plugin
  // reaches outside the tree, so it is the one place that needs a guard.
  group("openUrl is restricted", () {
    testWidgets("a non-web scheme is not handed to the OS", (tester) async {
      var launched = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel("plugins.flutter.io/url_launcher"),
        (call) async {
          launched.add(call.arguments.toString());
          return true;
        },
      );
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel("plugins.flutter.io/url_launcher"), null));

      await _pumpTree(tester, [
        _widget("text", text: "tap me", openUrl: "file:///etc/passwd"),
      ]);
      await tester.tap(find.text("tap me"));
      await tester.pumpAndSettle();

      expect(launched, isEmpty,
          reason: "a plugin must not open arbitrary schemes on the host");
    });
  });

  group("slots", () {
    PluginManifest manifestWith(
            String id, Map<String, List<PluginContribution>> contributes,
            {String? name}) =>
        PluginManifest(id, name ?? id, "1.0.0", "d", "s", "dynamic-wasm", 1,
            contributes, const []);

    test("a slot lists the contributions to it, in plugin-id order", () {
      var plugins = FakePluginManager([
        PluginInfo(
            manifestWith("zed", {
              PluginSlots.settingsPage: [
                PluginContribution("prefs", "Zed Settings", "settings", const [])
              ]
            }),
            true),
        PluginInfo(
            manifestWith("alpha", {
              PluginSlots.settingsPage: [
                PluginContribution("prefs", "Alpha Settings", "", const [])
              ]
            }),
            true),
      ]);

      var entries = slotEntries(plugins, PluginSlots.settingsPage);
      expect(entries.map((e) => e.pluginId), ["alpha", "zed"],
          reason: "a stable order means the same set always draws the same");
      expect(entries.last.label, "Zed Settings");
    });

    // Attribution is a security property, not a nicety. A widget tree cannot
    // execute anything, so the worst a hostile plugin can do is *say*
    // something -- but saying it inside Settings, where the reader takes the
    // app to be speaking, is most of what makes a convincing lie. Every slot
    // that draws a plugin's UI has to name the plugin.
    group("attribution", () {
      test("a contribution is labelled with the plugin behind it", () {
        var plugins = FakePluginManager([
          PluginInfo(
              manifestWith(
                  "citations",
                  {
                    PluginSlots.composerAction: [
                      PluginContribution("insert", "Insert citation", "", const [])
                    ]
                  },
                  name: "Citations"),
              true),
        ]);

        var entry = slotEntries(plugins, PluginSlots.composerAction).single;
        expect(entry.attributedLabel, "Insert citation \u2014 Citations");
      });

      test("a label that already names the plugin is not doubled", () {
        var plugins = FakePluginManager([
          PluginInfo(
              manifestWith(
                  "rss",
                  {
                    PluginSlots.settingsPage: [
                      PluginContribution("prefs", "RSS Settings", "", const [])
                    ]
                  },
                  name: "RSS"),
              true),
        ]);

        var entry = slotEntries(plugins, PluginSlots.settingsPage).single;
        expect(entry.attributedLabel, "RSS Settings",
            reason: "\"RSS Settings -- RSS\" reads as a mistake");
      });

      test("a plugin with no name falls back to the bare label", () {
        var plugins = FakePluginManager([
          PluginInfo(
              manifestWith(
                  "x",
                  {
                    PluginSlots.settingsPage: [
                      PluginContribution("p", "Options", "", const [])
                    ]
                  },
                  name: ""),
              true),
        ]);

        expect(slotEntries(plugins, PluginSlots.settingsPage).single
            .attributedLabel, "Options");
      });
    });

    test("a disabled plugin contributes nothing", () {
      var plugins = FakePluginManager([
        PluginInfo(
            manifestWith("off", {
              PluginSlots.composerAction: [
                PluginContribution("go", "Go", "", const [])
              ]
            }),
            false),
      ]);

      expect(slotEntries(plugins, PluginSlots.composerAction), isEmpty);
    });

    // The property that lets a plugin target a newer host: a contribution to
    // a slot this build has never drawn is carried, ignored, and costs
    // nothing -- rather than failing to install, which is what an unknown
    // capability used to do.
    test("a slot this build does not draw is simply never asked for", () {
      var plugins = FakePluginManager([
        PluginInfo(
            manifestWith("future", {
              "someSlotFromALaterVersion": [
                PluginContribution("x", "X", "", const [])
              ]
            }),
            true),
      ]);

      expect(slotEntries(plugins, PluginSlots.settingsPage), isEmpty);
      expect(slotEntries(plugins, "someSlotFromALaterVersion"), hasLength(1),
          reason: "the contribution is kept, just never drawn by this build");
    });
  });
}
