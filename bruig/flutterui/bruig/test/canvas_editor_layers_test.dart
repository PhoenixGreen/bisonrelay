import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:bruig/components/panel_stack.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/sidebar_layout.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/element_settings_pane.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/elements_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/layers_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/presets_library.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/sidebar_panels.dart';
import 'package:bruig/theming_system/theme_manager.dart';

import 'support/canvas_app.dart';
import 'support/canvas_sidebar_host.dart';
import 'support/canvas_panel_helpers.dart';

// canvas_editor_layers_test.dart is the sidebar's layers and design panels:
// listing, naming, dragging and picking layers, and what the sidebar rebuilds
// for.
//
// Built as widgets and used, rather than tested through the controller: a
// control drawn but wired to nothing passes every model test there is. So
// these tap the thing and look at the document.

void main() {
  // What the controls do, not where they are folded: every section open.
  setUpAll(() => CanvasSection.openAll = true);
  tearDownAll(() => CanvasSection.openAll = false);

  Future<void> pump(WidgetTester tester, Widget child,
          {CanvasPreferences? prefs}) =>
      pumpCanvasApp(tester, child, size: const Size(1400, 900), prefs: prefs);

  group("the design elements panel", () {
    testWidgets("offers every kind, and adding one selects it", (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasElementsPanel(controller: controller));

      // All but the 3D stage and parallax, which are chosen in a
      // background's Pattern layers rather than added, and a 3D character,
      // made in the Character Studio and placed from Assets.
      for (var kind in ElementKind.values) {
        if (kind == ElementKind.stage ||
            kind == ElementKind.parallax ||
            kind == ElementKind.character3d ||
            // Placed from the library's 3D objects, with its model.
            kind == ElementKind.object3d) {
          continue;
        }
        // Synth modules are put down as a rack, by the Synth chip, and a
        // task card from a module's settings, beside its rack.
        if (kind == ElementKind.synth || kind == ElementKind.synthTask) {
          expect(find.text("Synth"), findsOneWidget);
          continue;
        }
        // A Run panel is put down with the Code panel it runs, by the Code
        // chip; a task card from a Code panel's settings.
        if (kind == ElementKind.codeRun || kind == ElementKind.codeTask) {
          expect(find.text("Code"), findsWidgets);
          continue;
        }
        // Tables and charts are one Data element (Ken, 2026-11-15): its
        // chip puts down a table, made a chart in its quick settings.
        if (kind == ElementKind.table || kind == ElementKind.chart) {
          expect(find.text("Data"), findsOneWidget);
          continue;
        }
        expect(find.text(kind.label), findsWidgets, reason: kind.name);
      }

      await tester.tap(find.text("Data").first);
      await tester.pumpAndSettle();

      expect(controller.document.elements.length, 1);
      expect(controller.document.elements.single.kind, ElementKind.table);
      expect(controller.selection, {controller.document.elements.single.id});
    });

    testWidgets("a new element lands inside the canvas", (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasElementsPanel(controller: controller));

      await tester.tap(find.text("Text").first);
      await tester.pumpAndSettle();

      var element = controller.document.elements.single;
      var page = controller.document.size.rect;
      expect(page.contains(element.center), isTrue,
          reason: "a new element must be somewhere the reader can see it");
      expect(element.width, greaterThan(0));
      expect(element.height, greaterThan(0));
    });

    testWidgets("is the grid and nothing else", (tester) async {
      // It carried the layer list once and the settings after that, both
      // because the three were in different tabs and each kept a copy of its
      // neighbour. They share a column now, so this is one thing again.
      var document = const CanvasDocument();
      var controller = CanvasController(
          document.addElement(newElement(ElementKind.text, document)));
      addTearDown(controller.dispose);
      await pump(tester, CanvasElementsPanel(controller: controller));

      expect(find.byType(CanvasLayerRow), findsNothing);
      expect(find.text("Opacity"), findsNothing);
    });
  });

  group("the layers panel", () {
    testWidgets("the layer list reorders, hides and locks", (tester) async {
      // A handful of plain elements rather than a preset: the football preset
      // is two team elements now, and swapping two of anything cannot show
      // that a reorder left the rest of the stack alone.
      var document = const CanvasDocument();
      for (var kind in [
        ElementKind.shape,
        ElementKind.text,
        ElementKind.line,
        ElementKind.shape,
      ]) {
        document = document.addElement(newElement(kind, document));
      }
      var controller = CanvasController(document);
      addTearDown(controller.dispose);
      await pump(tester, designSidebar(controller));

      var first = controller.document.elements.first;

      await tester.tap(byTip("Hide").first);
      await tester.pumpAndSettle();
      expect(controller.document.elements.any((e) => !e.visible), isTrue);

      await tester.tap(byTip("Lock").first);
      await tester.pumpAndSettle();
      expect(controller.document.elements.any((e) => e.locked), isTrue);

      // The list is drawn front-to-back, so its first row is the last element.
      // "Move back" on it must actually change the paint order.
      var before = controller.document.elements.last.id;
      await tester.tap(byTip("Move back").first);
      await tester.pumpAndSettle();
      expect(controller.document.elements.last.id, isNot(before));
      expect(controller.document.elements.first.id, first.id);
    });

    testWidgets("shows the selected element's settings below the list",
        (tester) async {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.text, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      await pump(tester, designSidebar(controller));

      // Nothing selected: the list, and no settings under it.
      expect(find.text("Fit to box"), findsNothing);

      controller.selectOnly(element.id);
      await tester.pumpAndSettle();
      expect(find.text("Fit to box"), findsWidgets);
    });

    testWidgets("the background is the bottom layer, and selectable",
        (tester) async {
      // It is not an element, so it cannot be reordered into the middle of
      // them -- it is painted before all of them. Showing it in the list is
      // what makes it findable at all; it used to be reachable only by
      // deselecting everything and noticing the band had changed.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.text, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      await pump(tester, designSidebar(controller));

      var background = find.byType(CanvasBackgroundLayerRow);
      expect(background, findsOneWidget);
      expect(tester.getCenter(background).dy,
          greaterThan(tester.getCenter(find.byType(CanvasLayerRow).first).dy),
          reason: "the background sits below every element");

      await tester.tap(background);
      await tester.pumpAndSettle();
      expect(controller.backgroundSelected, isTrue);
      expect(controller.selection, isEmpty,
          reason: "selecting the background deselects elements");

      // Its settings are what the panel now shows.
      expect(byTip("Try the next variation"), findsOneWidget);
      var seed = controller.document.background.spec.seed;
      await tester.ensureVisible(byTip("Try the next variation"));
      await tester.pumpAndSettle();
      await tester.tap(byTip("Try the next variation"));
      await tester.pumpAndSettle();
      expect(controller.document.background.spec.seed, isNot(seed));
    });

    testWidgets("selecting an element deselects the background",
        (tester) async {
      // The two are exclusive: both mean "this is what the settings below the
      // list are about", and there is only one of those.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.text, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);

      controller.selectBackground();
      expect(controller.backgroundSelected, isTrue);

      controller.selectOnly(element.id);
      expect(controller.backgroundSelected, isFalse);
      expect(controller.selection, {element.id});

      controller.selectBackground();
      controller.clearSelection();
      expect(controller.backgroundSelected, isFalse);
    });

    testWidgets("a panel's top edge resizes the one above it", (tester) async {
      // The grip is the header's own top edge rather than a bar of its own: a
      // bar between two panels is a row of pixels that does nothing but be
      // dragged, in a column where every row is wanted for something.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false),
            child: SizedBox(
              width: 280,
              height: 600,
              child: designSidebar(controller),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      var before = tester.getSize(find.byType(CanvasLayersPanel)).height;

      // The line between Layers and the settings. Dragging it down gives
      // Layers the room. Taken between two panels that are both open: a shut
      // one is its own header and has no room to give.
      var grip = find
          .byWidgetPredicate((w) =>
              w is MouseRegion && w.cursor == SystemMouseCursors.resizeUpDown)
          .last;
      await tester.drag(grip, const Offset(0, 60));
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byType(CanvasLayersPanel)).height,
          greaterThan(before));
    });

    testWidgets("the stacked settings fit a narrow sidebar", (tester) async {
      // The same controls as the band above the canvas, laid out stacked. A
      // control sized past its parent overflows rather than shrinking, and the
      // chart's data box asks for 260 -- so without the scope's width cap this
      // is a wall of stripes. A chart is the widest element there is.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.chart, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeNotifier>(
                  create: (c) => ThemeNotifier(doLoad: false)),
              // A chart has a data source of its own now, and the panel that
              // fills it in asks whether fetching is allowed.
              ChangeNotifierProvider<CanvasPreferences>(
                  create: (c) => CanvasPreferences()),
            ],
            child: SizedBox(
              width: 260,
              height: 800,
              child: designSidebar(controller),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: "the settings column must not overflow the sidebar");
    });
  });

  group("renaming a layer", () {
    // The settings under the list are full of text fields, so the rename is
    // found by its own key rather than by being "the text field".
    var field = find.byKey(layerRenameFieldKey);

    Future<CanvasController> panel(WidgetTester tester) async {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      await pump(tester, designSidebar(controller));
      return controller;
    }

    /// inRow scopes a name to the layer list. Selecting a layer puts its own
    /// settings under the list, and those are headed with the same word.
    Finder inRow(String name) => find.descendant(
        of: find.byType(CanvasLayerRow), matching: find.text(name));

    Future<void> doubleClick(WidgetTester tester, String name) async {
      await tester.tap(inRow(name));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(inRow(name));
      await tester.pumpAndSettle();
    }

    testWidgets("double clicking the name opens a field", (tester) async {
      // Double click rather than a pencil button: the row already carries five
      // controls, and a sixth for something done occasionally would be paid
      // for on every row of every canvas.
      var controller = await panel(tester);
      expect(field, findsNothing);

      await doubleClick(tester, "Shape");
      expect(field, findsOneWidget);

      await enterValue(tester, field, "Goal area");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(controller.document.elements.single.name, "Goal area");
      expect(inRow("Goal area"), findsOneWidget);
      expect(field, findsNothing);
    });

    testWidgets("clearing it puts the kind's own name back", (tester) async {
      // An empty name is not a name, and it is also how the model says "use
      // the kind's label" -- so clearing the field is how you undo a rename
      // rather than how you get a row with nothing written on it.
      var controller = await panel(tester);
      controller.replaceElement(
          controller.document.elements.single.withBase(name: "Goal area"));
      await tester.pumpAndSettle();

      await doubleClick(tester, "Goal area");
      await enterValue(tester, field, "   ");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(controller.document.elements.single.name, "Shape");
    });

    testWidgets("a single click selects it, and does so at once",
        (tester) async {
      // Not GestureDetector.onDoubleTap, which holds the arena open for the
      // three hundred milliseconds a second tap might arrive in -- so every
      // single click on a layer name would have selected it a third of a
      // second late, and selecting layers is what this list is mostly for.
      var controller = await panel(tester);
      await tester.tap(inRow("Shape"));
      await tester.pump();

      expect(controller.selection, {controller.document.elements.single.id});
      expect(field, findsNothing);
    });
  });

  group("dragging a layer", () {
    /// three builds a document with three named layers, bottom to top.
    Future<CanvasController> panel(WidgetTester tester) async {
      var document = const CanvasDocument();
      for (var name in ["Bottom", "Middle", "Top"]) {
        document = document.addElement(
            newElement(ElementKind.shape, document).withBase(name: name));
      }
      var controller = CanvasController(document);
      addTearDown(controller.dispose);
      await pump(tester, designSidebar(controller));
      return controller;
    }

    List<String> order(CanvasController controller) =>
        [for (var e in controller.document.elements) e.name];

    testWidgets("press and hold moves it to the row it is dropped on",
        (tester) async {
      // A long press to start rather than a plain drag: the list scrolls, and
      // a row that begins moving the moment a pointer travels across it is a
      // row that cannot be scrolled past.
      var controller = await panel(tester);
      expect(order(controller), ["Bottom", "Middle", "Top"]);

      // The list is drawn top-first, so "Top" is the first row and "Bottom"
      // the last. Dragging Top onto Bottom's row sends it to the back.
      var drag = await tester.startGesture(tester.getCenter(find.text("Top")));
      await tester.pump(const Duration(milliseconds: 700));
      await drag.moveTo(tester.getCenter(find.text("Bottom")));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();

      expect(order(controller), ["Top", "Bottom", "Middle"]);
      expect(controller.selection.length, 1,
          reason: "what was dropped is what is selected, so it can be found");
    });

    testWidgets("a short drag scrolls rather than reordering", (tester) async {
      var controller = await panel(tester);
      await tester.drag(find.text("Top"), const Offset(0, 60));
      await tester.pumpAndSettle();

      expect(order(controller), ["Bottom", "Middle", "Top"],
          reason: "no long press, no reorder");
    });

    testWidgets("the background is neither picked up nor dropped on",
        (tester) async {
      // It is painted before every element and cannot be reordered into the
      // middle of them, so it is not a row that moves. It has no draggable and
      // no target of its own; a layer dropped on it goes nowhere.
      var controller = await panel(tester);
      // Scoped to the layer list: with nothing selected the settings panel is
      // showing the background's own controls, which are also called that.
      var background = find.descendant(
          of: find.byType(CanvasBackgroundLayerRow),
          matching: find.textContaining("Background"));
      expect(background, findsOneWidget);

      expect(
          find.ancestor(
              of: background,
              matching: find.byType(LongPressDraggable<String>)),
          findsNothing);
      expect(
          find.ancestor(
              of: background, matching: find.byType(DragTarget<String>)),
          findsNothing);

      var drag = await tester.startGesture(tester.getCenter(find.text("Top")));
      await tester.pump(const Duration(milliseconds: 700));
      await drag.moveTo(tester.getCenter(background));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();

      expect(order(controller), ["Bottom", "Middle", "Top"]);
    });
  });

  group("the sidebar's explanations", () {
    // Each panel carried a paragraph, permanently, taking a fifth of a narrow
    // column to say something read once and never again. Behind a question
    // mark it is still there for whoever has not read it and costs nothing to
    // whoever has.

    /// shown is the text of every hint the panel is offering.
    // Both kinds: the canvas's own hint inside a settings group, and the
    // shared panel stack's, which is what a panel header carries now.
    List<String> shown(WidgetTester tester) => [
          for (var h in tester.widgetList<CanvasHint>(find.byType(CanvasHint)))
            h.message,
          for (var h in tester.widgetList<PanelHint>(find.byType(PanelHint)))
            h.message,
        ];

    testWidgets("the Add grid explains itself on a question mark",
        (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      // Through the design panel, because the hint hangs off the Add panel's
      // own header now rather than off a heading inside the grid.
      await pump(tester, designSidebar(controller));

      const hint = "Click to add one in the middle of the canvas, or drag it "
          "where you want it.";
      expect(find.text(hint), findsNothing, reason: "not in the column");
      expect(shown(tester), contains(hint));

      // Tap as well as hover: a hint reachable only by hovering does not
      // exist on a touch screen.
      await tester.tap(find.byType(PanelHint).first);
      await tester.pumpAndSettle();
      expect(find.text(hint), findsOneWidget);
    });

    testWidgets("so do the presets, in their one panel", (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(
          tester,
          PanelStack(storageKey: "presetsHint", panels: [
            canvasSidebarPanel(
                SidebarPanel.presets,
                controller,
                CanvasPresetsLibrary(
                    controller: controller, onChoose: (_, __) {})),
          ]));
      // One list of every kind now, under the files: a canvas to start
      // from, a scene to add, an element to drop on, and the rest.
      for (var kind in ["canvas", "scene", "element", "football"]) {
        expect(find.byKey(ValueKey("presetFilter-$kind")), findsOneWidget,
            reason: kind);
      }
      expect(
          shown(tester), contains(startsWith("Everything there is to start")));
    });

    testWidgets("and the element settings, on their panel's own header",
        (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);

      await pump(tester, designSidebar(controller));
      expect(find.text(elementSettingsHint), findsNothing,
          reason: "not sitting in the column");
      expect(shown(tester), contains(elementSettingsHint));
    });
  });

  group("a layer row", () {
    Future<CanvasController> panel(WidgetTester tester) async {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      await pump(tester, designSidebar(controller));
      return controller;
    }

    testWidgets("duplicates rather than copying", (tester) async {
      // A copy did nothing anybody could see: the canvas was unchanged and the
      // only evidence was that a paste somewhere else would now produce this.
      var controller = await panel(tester);
      var original = controller.document.elements.single;

      expect(byTip("Copy"), findsNothing);
      await tester.tap(byTip("Duplicate"));
      await tester.pumpAndSettle();

      var elements = controller.document.elements;
      expect(elements.length, 2);
      expect(elements.last.id, isNot(original.id), reason: "a new element");
      expect(elements.last.x, greaterThan(original.x),
          reason: "offset, so it is visibly a second thing");
      expect(controller.selection, {elements.last.id},
          reason: "and selected, which is what makes it findable");
    });

    testWidgets("duplicating leaves the clipboard alone", (tester) async {
      // Wanting a second one of these is not a reason to lose whatever was
      // copied to paste onto another canvas.
      var controller = await panel(tester);
      controller.selectOnly(controller.document.elements.single.id);
      controller.copySelected();
      var copied = controller.document.elements.single.id;

      await tester.tap(byTip("Duplicate"));
      await tester.pumpAndSettle();
      controller.paste();

      expect(controller.document.elements.length, 3);
      expect(controller.canPaste, isTrue);
      expect(copied, isNotEmpty);
    });

    testWidgets("the lock is legible either way round", (tester) async {
      // It was lock_outline against lock_open_outlined, which are the same
      // padlock with the shackle moved a couple of pixels. At fourteen pixels
      // on a row of five icons, locking something looked like it had done
      // nothing at all.
      var controller = await panel(tester);

      expect(find.byIcon(Icons.lock_open_outlined), findsOneWidget);
      await tester.tap(byTip("Lock"));
      await tester.pumpAndSettle();

      expect(controller.document.elements.single.locked, isTrue);
      expect(find.byIcon(Icons.lock), findsOneWidget,
          reason: "filled, not another outline");
      expect(find.byIcon(Icons.lock_open_outlined), findsNothing);

      await tester.tap(byTip("Unlock"));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.lock_open_outlined), findsOneWidget);
    });
  });

  group("the design panel", () {
    // Adding, the layer list and the settings used to be tabs, and two of them
    // carried copies of the third just to shorten the journey between them.
    // They are one column of panels now, each opening, closing, resizing and
    // moving, and all of that remembered.
    Future<CanvasController> panel(WidgetTester tester) async {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      await pump(tester, designSidebar(controller));
      return controller;
    }

    testWidgets("all three are in one column", (tester) async {
      await panel(tester);
      for (var name in ["ADD", "LAYERS", "BACKGROUND SETTINGS"]) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      expect(find.byType(PanelStack), findsOneWidget);
    });

    testWidgets("the settings are never empty", (tester) async {
      // Nothing selected is the state a canvas starts in and returns to every
      // time somebody clicks the page. A panel that empties itself is a panel
      // that keeps taking its room back and giving it away again -- so with
      // nothing selected these are the canvas's own background, which is the
      // one thing always there and always worth changing.
      var controller = await panel(tester);
      expect(controller.selected, isNull);
      expect(find.text("Background"), findsWidgets);

      controller.selectOnly(controller.document.elements.single.id);
      await tester.pumpAndSettle();
      expect(find.text("Opacity"), findsOneWidget,
          reason: "and the element's own controls once there is one");

      controller.clearSelection();
      await tester.pumpAndSettle();
      expect(find.text("Background"), findsWidgets,
          reason: "and back to the background rather than to nothing");
    });

    testWidgets("a panel closes and stays closed when something is selected",
        (tester) async {
      // The instruction that makes closing one worth doing. A panel that
      // reopens because an element was clicked has to be closed again after
      // every click.
      var controller = await panel(tester);

      // The header names what is being edited, so with nothing selected it is
      // the background's.
      await tester.tap(find.text("BACKGROUND SETTINGS"));
      await tester.pumpAndSettle();
      expect(find.text("Opacity"), findsNothing);

      controller.selectOnly(controller.document.elements.single.id);
      await tester.pumpAndSettle();
      expect(find.text("Opacity"), findsNothing,
          reason: "selecting does not reopen it");

      controller.addElement(newElement(ElementKind.text, controller.document));
      await tester.pumpAndSettle();
      expect(find.text("Opacity"), findsNothing, reason: "nor does adding one");

      // And the header is still there, because a panel with no way back is a
      // trap. It is named for whatever is selected by now, so it is found by
      // what every one of those names ends with.
      await tester.tap(find.textContaining("SETTINGS").last);
      await tester.pumpAndSettle();
      expect(find.text("Opacity"), findsOneWidget);
    });

    testWidgets("every panel can be carried, and none of them by its name",
        (tester) async {
      await panel(tester);
      // One handle each. The name is the switch, so it cannot also be the
      // grip -- a panel that moved when you tried to open it would be a panel
      // you could not open.
      // One per panel: Add, Scenes, Vocal cues, Layers, Colour and the
      // settings.
      expect(find.byType(Draggable<PanelDrag>), findsNWidgets(6),
          reason: "and carried as their own type, not as the plain strings "
              "the layer list drags -- otherwise a panel could be dropped on "
              "a layer");
      expect(find.byIcon(Icons.drag_indicator), findsNWidgets(6));
    });

    testWidgets("the boundaries are the grips, and the top has none",
        (tester) async {
      // Resizing is done on the line between two panels rather than on an icon
      // in a header: the boundary is the thing being moved. Three panels have
      // two boundaries, and the top of the first is not one of them -- there
      // is nothing above it to take the room from.
      await panel(tester);
      expect(find.byIcon(Icons.drag_handle), findsNothing,
          reason: "the grip that used to sit in the header is gone");
      expect(
          find.descendant(
              of: find.byType(PanelStack),
              matching: find.byWidgetPredicate((w) =>
                  w is MouseRegion &&
                  w.cursor == SystemMouseCursors.resizeUpDown)),
          findsNWidgets(5),
          reason: "six panels have five boundaries, and the top of the "
              "first is not one of them");
    });

    testWidgets("every handle is in the same place, hard right",
        (tester) async {
      // They were at three different places, because the label was a Flexible
      // and the space after it was a Spacer -- two flexible children of one
      // Row, so the gap was half of whatever was left and the handle sat
      // wherever the name's length put it.
      await panel(tester);
      var handles =
          tester.widgetList<Widget>(find.byIcon(Icons.drag_indicator)).length;
      expect(handles, 6);

      var rights = [
        for (var i = 0; i < handles; i++)
          tester.getRect(find.byIcon(Icons.drag_indicator).at(i)).right,
      ];
      expect(rights.toSet(), hasLength(1),
          reason: "all of them line up: $rights");

      // And hard right, not floating in the middle of the band.
      var band = tester.getRect(find.byType(PanelStack)).right;
      expect(rights.first, closeTo(band, 14));
    });

    testWidgets("a header is a band, and the whole of it is the switch",
        (tester) async {
      // No expander arrow: the whole band opens and closes the panel, and an
      // arrow beside it is a smaller target that looks like the only one.
      await panel(tester);

      // Beside the name, rather than anywhere on the page: a section *inside*
      // a panel -- the Lights under a background, the Table under a chart --
      // is a CanvasExpander and has an arrow of its own, which is a different
      // control and not what this is about.
      var header = tester.getRect(find.text("ADD"));
      for (var arrow in [Icons.expand_more, Icons.chevron_right]) {
        for (var element in find.byIcon(arrow).evaluate()) {
          expect(tester.getRect(find.byElementPredicate((e) => e == element)),
              isNot(predicate<Rect>((r) => r.overlaps(header))),
              reason: "an arrow on the header's own line");
        }
      }

      // Tapping the name, which is nowhere near where an arrow would have
      // been, still closes it.
      expect(find.byType(CanvasElementsPanel), findsOneWidget);
      await tester.tap(find.text("ADD"));
      await tester.pumpAndSettle();
      expect(find.byType(CanvasElementsPanel), findsNothing);
    });
  });

  group("what the sidebar rebuilds for", () {
    // The controller notifies for everything: every pixel of a drag, every
    // frame of playback, every notch of the zoom. The settings panel is
    // twenty or thirty text fields, and laying those out for a change it does
    // not show is the whole of why clicking around felt slow.

    testWidgets("a watch ignores a notification that changes nothing",
        (tester) async {
      var source = ValueNotifier<int>(0);
      addTearDown(source.dispose);
      var builds = 0;

      await pump(
          tester,
          CanvasWatch<String>(
            listenable: source,
            // Deliberately blind to the odd numbers.
            select: () => "${source.value ~/ 2}",
            builder: (context, value) {
              builds++;
              return Text(value);
            },
          ));
      expect(builds, 1);

      source.value = 1;
      await tester.pumpAndSettle();
      expect(builds, 1, reason: "the key did not move, so nor did the panel");

      source.value = 2;
      await tester.pumpAndSettle();
      expect(builds, 2, reason: "and it does rebuild when the key moves");
      expect(find.text("1"), findsOneWidget);
    });

    testWidgets("zooming does not rebuild the settings", (tester) async {
      // The zoom, the pan, how the canvas is framed, which tool is held: the
      // settings show none of it.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.text, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, designSidebar(controller));

      var before =
          tester.widget<CanvasStepper>(find.byType(CanvasStepper).first);
      controller.zoom = 2.5;
      controller.pan = const Offset2(30, 30);
      await tester.pumpAndSettle();

      expect(
          identical(
              tester.widget<CanvasStepper>(find.byType(CanvasStepper).first),
              before),
          isTrue,
          reason: "the same widget instance: nothing was rebuilt");
    });

    testWidgets("a brush is not in the document, and still rebuilds them",
        (tester) async {
      // The trap this counts the safe way round for. These controls show the
      // retouching brush, its size and its hardness, and none of that is in
      // the document -- so a key naming what the settings read would have
      // gone stale here. The revision moves for everything except the view.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      var before = controller.revision;

      controller.retouch = RetouchBrush.erase;
      expect(controller.revision, greaterThan(before),
          reason: "not a view change, so the settings hear about it");

      before = controller.revision;
      controller.zoom = 2;
      controller.pan = const Offset2(10, 10);
      controller.showHelpers = false;
      expect(controller.revision, before,
          reason: "and these are, so they do not");
    });

    testWidgets("moving an element does rebuild them", (tester) async {
      // The other half of the rule. A panel that is cheap because it is stale
      // is not cheap, it is broken.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, designSidebar(controller));

      controller.replaceElement(element.withBase(x: 321), transient: true);
      await tester.pumpAndSettle();

      expect(
          find.descendant(
              of: find.byKey(const ValueKey("elementX")),
              matching: find.text("321")),
          findsOneWidget);
    });
  });
}
