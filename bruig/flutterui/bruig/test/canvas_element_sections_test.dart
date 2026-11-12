import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_element_sections_test.dart is every element's panel built the way
// a picture's is: sections that fold, each a stack of cards -- where it is
// first, the designs saved of its kind last -- and every one of them, open,
// inside an ordinary sidebar.

void main() {
  setUpAll(() => CanvasSection.openAll = true);
  tearDownAll(() => CanvasSection.openAll = false);

  /// narrow is the sidebar at its narrowest, where a control wider than its
  /// line has nowhere to go.
  const narrow = 300.0;

  Future<void> pump(WidgetTester tester, CanvasController c) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(narrow, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(
            create: (c) => CanvasPreferences()),
      ],
      child:
          MaterialApp(home: Scaffold(body: CanvasDesignPanel(controller: c))),
    ));
    await tester.pumpAndSettle();
  }

  /// titles is the sections' titles, down the panel -- the panel's own,
  /// not the folds inside them (a drawing's Drawing, in its Content).
  List<String> titles(WidgetTester tester) {
    var found = [
      for (var element in find.byType(CanvasSection).evaluate())
        if (find
            .ancestor(
                of: find.byWidget(element.widget),
                matching: find.byType(CanvasSection))
            .evaluate()
            .isEmpty)
          (
            tester.getTopLeft(find.byWidget(element.widget)).dy,
            (element.widget as CanvasSection).title,
          ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return [for (var (_, title) in found) title];
  }

  // Rebuilt to the Text panel's shape: batch 1 the text, then batches 2-5.
  const rebuilt = {
    ElementKind.text,
    ElementKind.shape,
    ElementKind.line,
    ElementKind.path,
    ElementKind.button,
    ElementKind.counter,
    ElementKind.chart,
    ElementKind.table,
    ElementKind.vector,
    ElementKind.video,
    ElementKind.audio,
    ElementKind.sheet,
  };
  for (var kind in ElementKind.values) {
    if (kind == ElementKind.image) continue; // see canvas_panel_kit_test
    testWidgets("${kind.label} is sections of cards, open in a sidebar",
        (tester) async {
      var document = const CanvasDocument();
      var element = newElement(kind, document);
      var c = CanvasController(document.addElement(element));
      addTearDown(c.dispose);
      c.selectOnly(element.id);
      await pump(tester, c);

      var all = titles(tester);
      // Rebuilt round tasks (Ken, 2026-11-11): the rest follow, a batch at a
      // time.
      if (rebuilt.contains(kind)) {
        // Content left out where an element has none of its own.
        expect(all.where((t) => t != "Content"),
            ["Look", "Layout", "Motion", "More"],
            reason: "$all");
      } else {
        expect(all.first, "Position", reason: "$all");
        expect(all.last, "Presets", reason: "$all");
      }
      expect(all.length, greaterThanOrEqualTo(3),
          reason: "its own sections: $all");
      // No rule inside a section: a card is its own edge.
      expect(
          find.descendant(
              of: find.byType(CanvasSection),
              matching: find.byType(CanvasGroupRule)),
          findsNothing);
      expect(tester.takeException(), isNull,
          reason: "nothing overruns the sidebar with every section open");
      // A control wider than the line it is on is not something a wrapping
      // layout can fix: its right-hand edge is off the panel, a number
      // nobody can finish typing. A table that scrolls sideways is the one
      // place a control may start off the edge: it is scrolled to.
      var sideways = find.byWidgetPredicate((w) =>
          w is Scrollable &&
          axisDirectionToAxis(w.axisDirection) == Axis.horizontal);
      for (var of in [
        find.byType(CanvasNumberField),
        find.byType(CanvasTextField),
        find.byType(CanvasToggle),
        find.byType(CanvasIconButton),
      ]) {
        for (var i = 0; i < of.evaluate().length; i++) {
          if (find
              .ancestor(of: of.at(i), matching: sideways)
              .evaluate()
              .isNotEmpty) {
            continue;
          }
          var box = tester.getRect(of.at(i));
          expect(box.right, lessThanOrEqualTo(narrow + 0.5),
              reason: "${kind.label}: a control runs off the panel: $box");
        }
      }
    });
  }

  testWidgets("a camera's move goes on the timeline, opened", (tester) async {
    var document = const CanvasDocument(frames: 96, frameRate: 24);
    var cam = newElement(ElementKind.camera, document);
    var c = CanvasController(document.addElement(cam));
    addTearDown(c.dispose);
    c.selectOnly(cam.id);
    c.frame = 24;
    await pump(tester, c);
    var move = find.byKey(const ValueKey("cameraMove-Camera shake"));
    await tester.ensureVisible(move);
    await tester.tap(move);
    await tester.pumpAndSettle();
    var placed = c.document.elementById(cam.id)!.base.motion.placed.single;
    expect(placed.start, closeTo(1, 1e-9), reason: "at the playhead");
    expect((c.pickedPlacement, c.animationOpen), (placed.id, true));
  });

  testWidgets("the canvas's own background is sections too", (tester) async {
    var c = CanvasController(const CanvasDocument());
    addTearDown(c.dispose);
    await pump(tester, c);
    var all = titles(tester);
    expect(all, containsAllInOrder(["Pattern", "Presets"]));
    expect(all, contains("Picture"));
    expect(tester.takeException(), isNull);
  });
}
