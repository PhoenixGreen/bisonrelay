import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'plugin_test_support.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// plugin_settings_test.dart covers Settings > Plugins: what a row says when
// it is closed, and what opening one reveals.
//
// The page used to put every plugin's settings in one block at the bottom,
// which said nothing about which plugin they belonged to. They are now in
// the panel of whichever plugin provides them -- decided by the capabilities
// it declares, never by its name -- and the tests below are mostly about
// that, plus the one thing that must survive it: an override outlives the
// plugin that prompted it, so it cannot become unreachable when the plugin
// is removed.

PluginManifest _manifest({
  String id = "writing",
  String name = "Writing Tools",
  String version = "2.18.0",
  String description = "The long account of what this plugin does.",
  String summary = "A short line about it.",
  List<String> capabilities = const ["spellcheck-data"],
}) =>
    PluginManifest(id, name, version, description, summary, "dynamic-wasm", "",
        "", const [], capabilities);

Future<void> _pump(
  WidgetTester tester, {
  List<PluginInfo> plugins = const [],
  WritingPreferences? prefs,
}) async {
  var settings = prefs ?? WritingPreferences();
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<WritingPreferences>.value(value: settings),
      ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
      ChangeNotifierProvider<PluginManagerModel>(
          create: (c) => FakePluginManager(plugins)),
      Provider<SpellcheckCapability?>.value(value: null),
    ],
    child: const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(child: PluginsSettingsScreen()))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets("a closed row shows the name, summary and version",
      (tester) async {
    await _pump(tester, plugins: [
      PluginInfo(_manifest(summary: "Checks your writing as you type."), true),
    ]);

    expect(find.text("Writing Tools"), findsOneWidget);
    expect(find.text("Checks your writing as you type."), findsOneWidget);
    expect(find.text("v2.18.0"), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);

    // The long description belongs to the panel, which is closed.
    expect(
        find.text("The long account of what this plugin does."), findsNothing);
  });

  testWidgets("opening a row reveals the full description", (tester) async {
    await _pump(tester, plugins: [PluginInfo(_manifest(), true)]);
    await tester.tap(find.text("Writing Tools"));
    await tester.pumpAndSettle();

    expect(find.text("The long account of what this plugin does."),
        findsOneWidget);
  });

  testWidgets("only one panel is open at a time", (tester) async {
    await _pump(tester, plugins: [
      PluginInfo(
          _manifest(id: "a", name: "First", description: "First long."), true),
      PluginInfo(
          _manifest(id: "b", name: "Second", description: "Second long."),
          true),
    ]);

    await tester.tap(find.text("First"));
    await tester.pumpAndSettle();
    expect(find.text("First long."), findsOneWidget);

    await tester.tap(find.text("Second"));
    await tester.pumpAndSettle();
    expect(find.text("Second long."), findsOneWidget);
    expect(find.text("First long."), findsNothing);
  });

  testWidgets("tapping an open row closes it", (tester) async {
    await _pump(tester, plugins: [PluginInfo(_manifest(), true)]);
    await tester.tap(find.text("Writing Tools"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Writing Tools"));
    await tester.pumpAndSettle();
    expect(
        find.text("The long account of what this plugin does."), findsNothing);
  });

  // Importing is what you come to this page to do when the list is empty,
  // and a control below the list is one you scroll past every plugin to
  // reach once it is not.
  testWidgets("import is an icon at the top, above the list", (tester) async {
    await _pump(tester, plugins: [PluginInfo(_manifest(), true)]);

    var importer = find.widgetWithIcon(IconButton, Icons.file_upload_outlined);
    expect(importer, findsOneWidget);
    expect(find.text("Import Plugin"), findsNothing);
    expect(tester.getCenter(importer).dy,
        lessThan(tester.getCenter(find.text("Writing Tools")).dy),
        reason: "the import control belongs above the plugins, not below");
  });

  group("settings follow the capability, not the plugin", () {
    testWidgets("the writing overrides open under the provider",
        (tester) async {
      var prefs = WritingPreferences();
      await prefs.addToDictionary("bisonrelay");
      await _pump(tester,
          prefs: prefs, plugins: [PluginInfo(_manifest(), true)]);

      expect(find.text("bisonrelay"), findsNothing,
          reason: "the panel is closed, so its settings are not on the page");

      await tester.tap(find.text("Writing Tools"));
      await tester.pumpAndSettle();
      expect(find.text("bisonrelay"), findsOneWidget);
    });

    testWidgets("a plugin without the capability gets no writing settings",
        (tester) async {
      var prefs = WritingPreferences();
      await prefs.addToDictionary("bisonrelay");
      await _pump(tester, prefs: prefs, plugins: [
        PluginInfo(
            _manifest(
                id: "links", name: "Link Cards", capabilities: ["link-card"]),
            true),
        // Installed so the page-level fallback stays quiet: this test is
        // about which panel the settings appear in, not about that.
        PluginInfo(_manifest(id: "writing", name: "Writing Tools"), true),
      ]);

      await tester.tap(find.text("Link Cards"));
      await tester.pumpAndSettle();
      expect(find.text("bisonrelay"), findsNothing);
    });

    // The reason the section was on the page in the first place: an override
    // is a decision about this app and outlives the plugin that prompted it.
    // Putting it inside a panel must not make it unreachable.
    testWidgets("overrides stay reachable with no provider installed",
        (tester) async {
      var prefs = WritingPreferences();
      await prefs.addToDictionary("bisonrelay");
      await _pump(tester, prefs: prefs, plugins: const []);

      expect(find.text("bisonrelay"), findsOneWidget,
          reason: "a word added to the dictionary cannot become impossible "
              "to remove by uninstalling the plugin");
    });
  });

  // Plugins written before the summary field existed still have to list
  // sensibly rather than showing a paragraph in a subtitle.
  test("a missing summary falls back to the opening of the description", () {
    var manifest = _manifest(
        summary: "",
        description: "Spelling and grammar as you write: a 120,000-word "
            "dictionary, 326 rules, and a thesaurus covering most of it.");
    expect(manifest.summaryLine, "Spelling and grammar as you write");
  });

  test("a description with no break is cut at a word", () {
    var manifest = _manifest(summary: "", description: "word " * 60);
    expect(manifest.summaryLine.length, lessThan(115));
    expect(manifest.summaryLine, endsWith("…"));
  });

  test("a short description is used whole", () {
    var manifest =
        _manifest(summary: "", description: "Turns links into cards");
    expect(manifest.summaryLine, "Turns links into cards");
  });
}
