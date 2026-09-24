import 'dart:io';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/element_preset_store.dart';
import 'package:bruig/plugin_system/canvas/storage/saved_preset_store.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/preset_panels.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/presets_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/double_click.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_presets_sidebar_test.dart is the three lists of saved things.
//
// Model tests say the store keeps a preset. What they cannot say is that the
// sidebar lists it, that tapping it puts it where it belongs -- an element on
// this canvas, a scene after this one -- and that it can be renamed and
// thrown away from the row itself, which is all anybody does here.

/// idle turns the real event loop and drains the fake one, which is what a
/// widget test needs to get through a chain of real file reads.
///
/// A preset store reads a folder from disk. In a testWidgets zone a dart:io
/// future completes on the real loop while its continuation is a microtask in
/// the fake one, so each step needs a runAsync *and* a pump -- and a panel
/// waiting for one simply never fills in. See doc and the notes tests, which
/// learnt this the same way.
Future<void> idle(WidgetTester tester) async {
  for (var i = 0; i < 24; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 4)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() {
    // The pair is counted against the real clock, so a loaded machine can
    // put a second of real time between two taps made back to back.
    DoubleClick.window = const Duration(minutes: 1);
    SharedPreferences.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync("canvas-presets-sidebar");
    CanvasStorage.rootOverride = root.path;
    SavedPresetStore.scenes.forget();
    SavedPresetStore.canvases.forget();
    ElementPresetStore.instance.forget();
  });

  tearDown(() {
    CanvasStorage.rootOverride = null;
    SavedPresetStore.scenes.forget();
    SavedPresetStore.canvases.forget();
    ElementPresetStore.instance.forget();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<CanvasController> sidebar(WidgetTester tester,
      {CanvasDocument? document,
      Widget Function(CanvasController)? body}) async {
    var controller = CanvasController(document ?? const CanvasDocument());
    addTearDown(controller.dispose);

    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(
            create: (c) => CanvasPreferences()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 900,
            child: body?.call(controller) ??
                CanvasPresetsSidebar(
                    controller: controller, onChoose: (_, __) {}),
          ),
        ),
      ),
    ));
    await idle(tester);
    return controller;
  }

  testWidgets("the sidebar is three lists, in the order the work happens",
      (tester) async {
    await sidebar(tester);
    expect(find.text("CANVAS"), findsOneWidget);
    expect(find.text("SCENE"), findsOneWidget);
    expect(find.text("ELEMENT"), findsOneWidget);
  });

  testWidgets("a saved scene is added after the scene being looked at",
      (tester) async {
    await tester.runAsync(() => SavedPresetStore.scenes.save("Title card",
        const CanvasScene(id: "s", name: "Title", elements: []).toJson()));

    var controller =
        await sidebar(tester, body: (c) => ScenePresetsPanel(controller: c));
    expect(find.text("Title card"), findsOneWidget);

    await tester.tap(find.text("Title card"));
    await tester.pumpAndSettle();

    expect(controller.document.allScenes.length, 2);
    expect(controller.document.at, 1, reason: "and goes to it");
    expect(controller.document.allScenes[1].id, isNot("s"),
        reason: "a fresh scene, not the saved one itself");
  });

  testWidgets("a saved element is put on the canvas being looked at",
      (tester) async {
    await tester.runAsync(() => ElementPresetStore.instance.save(
        "Big red",
        ShapeElement(const ElementBase(id: "x", width: 40, height: 40),
            fill: const Color(0xFFFF0000))));

    var controller =
        await sidebar(tester, body: (c) => ElementPresetsPanel(controller: c));
    await tester.tap(find.text("Big red"));
    await tester.pumpAndSettle();

    expect(controller.document.elements.length, 1);
    expect(controller.document.elements.single.kind, ElementKind.shape);
  });

  testWidgets("a preset is renamed by clicking its name twice", (tester) async {
    await tester.runAsync(() => SavedPresetStore.scenes
        .save("Title card", const CanvasScene(id: "s").toJson()));
    await sidebar(tester, body: (c) => ScenePresetsPanel(controller: c));

    var name = find.text("Title card");
    // No pause between them: the second click is counted against the real
    // clock, so a test that waits for a fake fifty milliseconds is a test
    // that fails on a loaded machine.
    await tester.tap(name);
    await tester.tap(name);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey("presetRename")), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey("presetRename")), "Opening card");
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await idle(tester);

    expect(SavedPresetStore.scenes.presets.single.name, "Opening card");
  });

  testWidgets("and deleted from its own menu", (tester) async {
    await tester.runAsync(() => SavedPresetStore.scenes
        .save("Title card", const CanvasScene(id: "s").toJson()));
    await sidebar(tester, body: (c) => ScenePresetsPanel(controller: c));

    await tester.tap(find.byTooltip("More"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Delete"));
    await idle(tester);

    expect(SavedPresetStore.scenes.presets, isEmpty);
    expect(find.text("Title card"), findsNothing);
  });

  testWidgets("the element list can be filtered to one kind", (tester) async {
    await tester.runAsync(() => ElementPresetStore.instance.save("Big red",
        ShapeElement(const ElementBase(id: "x", width: 40, height: 40))));
    await tester.runAsync(() => ElementPresetStore.instance.save("Countdown",
        CounterElement(const ElementBase(id: "c", width: 40, height: 40))));

    await sidebar(tester, body: (c) => ElementPresetsPanel(controller: c));
    expect(find.text("Big red"), findsOneWidget);
    expect(find.text("Countdown"), findsOneWidget);

    // The dropdown is a caption over a menu button, so the press goes to
    // what it is showing rather than to the middle of the pair.
    await tester.tap(find.text("All"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Counter").last);
    await tester.pumpAndSettle();

    expect(find.text("Countdown"), findsOneWidget);
    expect(find.text("Big red"), findsNothing,
        reason: "filtered out, not merely further down");
  });

  testWidgets("a saved canvas starts a new document, or gives up its scenes",
      (tester) async {
    await tester.runAsync(() => SavedPresetStore.canvases.save(
        "Match report",
        const CanvasDocument().withScenes([
          const CanvasScene(id: "a", name: "One"),
          const CanvasScene(id: "b", name: "Two"),
        ]).toJson()));

    CanvasDocument? started;
    var controller = CanvasController(const CanvasDocument());
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 900,
            child: SavedCanvasPresets(
              controller: controller,
              onOpen: (d) => started = d,
            ),
          ),
        ),
      ),
    ));
    await idle(tester);

    // Its menu adds the scenes to what is already open.
    await tester.tap(find.byTooltip("More"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Add its scenes to this canvas"));
    await tester.pumpAndSettle();
    expect(controller.document.allScenes.length, 3,
        reason: "the one that was there, and the preset's two");
    expect(started, isNull, reason: "and no new document was started");

    // Tapped, it starts one instead.
    await tester.tap(find.text("Match report"));
    await tester.pumpAndSettle();
    expect(started, isNotNull);
    expect(started!.allScenes.length, 2);
  });
}
