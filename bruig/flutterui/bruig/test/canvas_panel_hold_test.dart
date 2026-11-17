import 'dart:io';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/canvas_app.dart';
import 'support/canvas_audio_fake.dart';
import 'support/temp_dirs.dart';

// canvas_panel_hold_test.dart is what an element's settings build while a
// pointer is held in a gesture: a drag on the canvas, or a number scrubbed
// in the panel. Every step changes the element, and the panel once built
// all of itself again for each: thousands of widgets, several frames'
// worth. Now the sections not being touched keep what they built (see
// PanelHold), the Layout section follows a drag on the canvas, and all of
// it is built again when the pointer lifts.

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync("panel_hold");
    CanvasStorage.rootOverride = root.path;
    CanvasLibrary.resetForTest();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    CanvasStorage.rootOverride = null;
    debugOnRebuildDirtyWidget = null;
    deleteTempDir(root);
  });
  setUpAll(() => CanvasSection.openAll = true);
  tearDownAll(() => CanvasSection.openAll = false);

  /// show puts [kind]'s settings, every section open, in a sidebar beside
  /// room standing for the canvas.
  Future<(CanvasController, String)> show(
      WidgetTester tester, ElementKind kind) async {
    var doc = const CanvasDocument(frames: 96, frameRate: 24);
    var e = newElement(kind, doc);
    var c = CanvasController(doc.addElement(e), audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    c.selectOnly(e.id);
    setTestScreen(tester, const Size(700, 9000));
    await tester.pumpWidget(canvasApp(Row(children: [
      const SizedBox(width: 340, child: ColoredBox(color: Colors.black)),
      SizedBox(width: 360, child: CanvasDesignPanel(controller: c)),
    ])));
    await tester.pump(const Duration(milliseconds: 200));
    return (c, e.id);
  }

  /// steps moves [id] ten times, transiently, as a drag does, and is the
  /// widgets built for each step.
  Future<int> steps(WidgetTester tester, CanvasController c, String id) async {
    var built = 0;
    debugOnRebuildDirtyWidget = (e, b) => built++;
    c.beginInteraction();
    for (var i = 0; i < 10; i++) {
      var e = c.document.elementById(id)!;
      c.replaceElement(e.withBase(x: e.base.x + 1), transient: true);
      await tester.pump(const Duration(milliseconds: 16));
    }
    debugOnRebuildDirtyWidget = null;
    return built ~/ 10;
  }

  /// layout is the Layout section's body: keyed "sectionBody-<kind>.layout".
  final layout = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith("sectionBody-") &&
          (w.key as ValueKey<String>).value.endsWith(".layout"),
      skipOffstage: false);

  /// shownX is the Layout section's X, as its field shows it.
  String shownX(WidgetTester tester) => tester
      .widget<CanvasStepper>(find.descendant(
          of: layout,
          matching: find.byWidgetPredicate(
              (w) => w is CanvasStepper && w.label == "X",
              skipOffstage: false),
          skipOffstage: false))
      .value
      .round()
      .toString();

  for (var (kind, before) in [
    (ElementKind.text, 2300),
    (ElementKind.chart, 2737),
    (ElementKind.player, 5390),
    (ElementKind.shape, 1327),
  ]) {
    testWidgets("${kind.label}: a drag on the canvas builds little",
        (tester) async {
      var (c, id) = await show(tester, kind);
      // A pointer down on the canvas, outside the panel, held.
      var drag = await tester.startGesture(const Offset(100, 100));
      var built = await steps(tester, c, id);
      expect(built, lessThan(before ~/ 4),
          reason: "was $before a step, every section built again");
      // The Layout section follows the drag as it goes.
      expect(shownX(tester), "${c.document.elementById(id)!.base.x.round()}");
      c.endInteraction();
      await drag.up();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets("a number scrubbed builds its own section, and the rest after",
      (tester) async {
    var (c, id) = await show(tester, ElementKind.text);
    // The pointer down in the Layout section: it is the live one.
    var at = tester.getCenter(layout.first);
    var scrub = await tester.startGesture(at);
    var built = await steps(tester, c, id);
    expect(built, lessThan(2300 ~/ 3));
    expect(shownX(tester), "${c.document.elementById(id)!.base.x.round()}");
    c.endInteraction();
    await scrub.up();
    await tester.pump();
    // Let go, everything is built from the element as it now is.
    var built2 = 0;
    debugOnRebuildDirtyWidget = (e, b) => built2++;
    var e = c.document.elementById(id)!;
    c.replaceElement(e.withBase(y: e.base.y + 1));
    await tester.pump();
    debugOnRebuildDirtyWidget = null;
    expect(built2, greaterThan(1000),
        reason: "no gesture, so every section is built as before");
    expect(tester.takeException(), isNull);
  });

  testWidgets("a section kept during a drag is built fresh when it ends",
      (tester) async {
    var (c, id) = await show(tester, ElementKind.shape);
    var drag = await tester.startGesture(const Offset(100, 100));
    c.beginInteraction();
    var e = c.document.elementById(id)!;
    // Something only a kept section shows, changed mid-gesture.
    c.replaceElement(e.withBase(name: "Renamed in the gesture"),
        transient: true);
    await tester.pump();
    c.endInteraction();
    await drag.up();
    await tester.pump();
    expect(
        find.text("Renamed in the gesture", skipOffstage: false), findsWidgets,
        reason: "the panel was built again from the element as it is");
  });
}
