import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/canvas_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/presets/builtin_presets.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/ui/chart_data_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_settings_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/element_settings_pane.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/elements_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/presets_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/canvas_sidebar.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/layers_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_editor_test.dart builds the controls and uses them.
//
// The point of testing them as widgets rather than testing the controller is
// that a control which is drawn but wired to nothing passes every model test
// there is. The settings band and the timeline are almost entirely wiring, so
// wiring is what these check: tap the thing, look at the document.

void main() {
  var published = 0;
  setUp(() => published = 0);

  Future<void> pump(WidgetTester tester, Widget child,
      {CanvasPreferences? prefs}) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        if (prefs != null) ChangeNotifierProvider.value(value: prefs),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    ));
    await tester.pumpAndSettle();
  }

  group("the settings band", () {
    /// bar builds the band. Every test needs the two canvas-settings
    /// parameters, and none of them cares what they are, because the panel
    /// those drive is a separate widget the screen floats over the canvas.
    Widget bar(CanvasController controller,
            {bool open = false, VoidCallback? toggle, VoidCallback? showSidebar}) =>
        CanvasSettingsBar(
          controller: controller,
          onPublish: () => published++,
          canvasSettingsOpen: open,
          onToggleCanvasSettings: toggle ?? () {},
          onShowSidebar: showSidebar,
        );

    testWidgets("is one line, open or closed", (tester) async {
      // The whole point of splitting the panel out. As a second row inside the
      // band, opening the canvas settings pushed the canvas down -- the design
      // jumped and the zoom changed under whatever was being looked at.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);

      tester.view.physicalSize = const Size(700, 900);
      await pump(tester, bar(controller));
      var closed = tester.getSize(find.byType(CanvasSettingsBar)).height;

      await pump(tester, bar(controller, open: true));
      expect(tester.getSize(find.byType(CanvasSettingsBar)).height, closed,
          reason: "opening the settings must not change the band's height");
      expect(closed, lessThan(50), reason: "one line, always");
      expect(tester.takeException(), isNull);
    });

    testWidgets("the canvas settings button reports its state", (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);

      var toggled = 0;
      await pump(tester, bar(controller, toggle: () => toggled++));
      await tester.tap(find.byTooltip("Canvas settings"));
      await tester.pumpAndSettle();
      expect(toggled, 1);
    });

    testWidgets("carries no element settings until they are asked for",
        (tester) async {
      // The band is one line unless the button has been pressed, and selecting
      // something is not pressing the button. A line that appears because an
      // element was selected is a line that has to be dismissed again after
      // every selection.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.text, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);

      await pump(tester, bar(controller));
      var oneLine = tester.getSize(find.byType(CanvasSettingsBar)).height;

      controller.selectOnly(element.id);
      await tester.pumpAndSettle();

      expect(find.byTooltip("Try the next variation"), findsNothing);
      expect(tester.getSize(find.byType(CanvasSettingsBar)).height, oneLine,
          reason: "selecting something does not open the second line");
    });

    testWidgets("the element button opens a second line and keeps it",
        (tester) async {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.text, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);

      await pump(tester, bar(controller));
      var oneLine = tester.getSize(find.byType(CanvasSettingsBar)).height;

      await tester.tap(find.byTooltip(
          "Element settings — the selected element's controls, on a second "
          "line"));
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byType(CanvasSettingsBar)).height,
          greaterThan(oneLine),
          reason: "the settings are a second line, as asked for");
      // Along a row rather than down a column: the band has a window's width
      // and no height to spare.
      expect(find.byType(SingleChildScrollView), findsWidgets);
      expect(find.text("Opacity"), findsOneWidget);

      await tester.tap(find.byTooltip("Hide the element settings"));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(CanvasSettingsBar)).height, oneLine);
    });

    testWidgets("the second line is one height whatever is selected",
        (tester) async {
      // It pushes the canvas down, so a line that were as tall as its contents
      // would move the design and re-fit the zoom on every change of
      // selection. Opening it costs a line once; selecting things after that
      // costs nothing.
      var document = const CanvasDocument();
      var text = newElement(ElementKind.text, document);
      var chart = newElement(ElementKind.chart, document);
      var controller =
          CanvasController(document.addElement(text).addElement(chart));
      addTearDown(controller.dispose);

      await pump(tester, bar(controller));
      await tester.tap(find.byTooltip(
          "Element settings — the selected element's controls, on a second "
          "line"));
      await tester.pumpAndSettle();
      var empty = tester.getSize(find.byType(CanvasSettingsBar)).height;

      for (var element in [text, chart]) {
        controller.selectOnly(element.id);
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(CanvasSettingsBar)).height, empty,
            reason: "${element.kind.name} makes the band no taller");
      }
      expect(tester.takeException(), isNull,
          reason: "and a control taller than the line scrolls, not overflows");
    });

    testWidgets("the second line has the same gap above as below",
        (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, bar(controller));
      await tester.tap(find.byTooltip(
          "Element settings — the selected element's controls, on a second "
          "line"));
      await tester.pumpAndSettle();

      // Measured off the rule the line hangs from and the bottom of the band,
      // because the gap between them is what was actually complained about.
      var line =
          tester.getRect(find.byKey(const ValueKey("canvasBarElementLine")));
      var controls = tester.getRect(find.byType(CanvasControlScope).first);
      var above = controls.top - line.top;
      var below = line.bottom - controls.bottom;

      expect(above, closeTo(below, 1.5), reason: "above $above, below $below");
      // Only the band's own bottom rule below it, and nothing else.
      expect(line.bottom,
          closeTo(tester.getRect(find.byType(CanvasSettingsBar)).bottom, 1.5),
          reason: "the band adds no padding of its own under the line");
    });

    testWidgets("offers both frame buttons", (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, bar(controller));

      expect(controller.fit, CanvasFit.whole);
      await tester.tap(find.byTooltip(
          "${CanvasFit.width.label} — the canvas scrolls if it is taller "
          "than the window"));
      await tester.pumpAndSettle();
      expect(controller.fit, CanvasFit.width);

      await tester.tap(find.byTooltip(CanvasFit.whole.label));
      await tester.pumpAndSettle();
      expect(controller.fit, CanvasFit.whole);
    });

    testWidgets("turns the editing helpers off", (tester) async {
      // A pitch of twenty-two dots with a box and eight handles over one of
      // them is a picture of an editor, not a picture of a formation.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, bar(controller));

      expect(controller.showHelpers, isTrue, reason: "on by default");
      await tester.tap(find.byTooltip("Hide the selection box and handles"));
      await tester.pumpAndSettle();
      expect(controller.showHelpers, isFalse);

      await tester.tap(find.byTooltip("Show the selection box and handles"));
      await tester.pumpAndSettle();
      expect(controller.showHelpers, isTrue);
    });

    testWidgets("offers the two tools", (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, bar(controller));

      await tester.tap(find.byTooltip(
          "${CanvasTool.pan.label} — ${CanvasTool.pan.description}"));
      await tester.pumpAndSettle();
      expect(controller.tool, CanvasTool.pan);

      await tester.tap(find.byTooltip(
          "${CanvasTool.select.label} — ${CanvasTool.select.description}"));
      await tester.pumpAndSettle();
      expect(controller.tool, CanvasTool.select);
    });

    testWidgets("hides and restores the sidebar", (tester) async {
      // The same pair of controls the Writing page has. A hidden sidebar with
      // no way back is a trap, so the restore control lives in the band, where
      // everything else on the page already is.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);

      var hidden = 0;
      await pump(
          tester,
          CanvasSidebarShell(
            panel: CanvasPanel.files,
            onPanelChanged: (_) {},
            onHide: () => hidden++,
            child: const SizedBox(),
          ));
      await tester.tap(find.byTooltip("Hide the sidebar"));
      await tester.pumpAndSettle();
      expect(hidden, 1);

      // While it is showing, the band carries no restore control.
      await pump(tester, bar(controller));
      expect(find.byTooltip("Show the sidebar"), findsNothing);

      var shown = 0;
      await pump(tester, bar(controller, showSidebar: () => shown++));
      await tester.tap(find.byTooltip("Show the sidebar"));
      await tester.pumpAndSettle();
      expect(shown, 1);
    });

    testWidgets("publish, undo and redo are pinned to the band", (tester) async {
      // They used to float over the top-right corner of the canvas, on top of
      // the design. Publish is an icon now, so the tooltip is what names it.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, bar(controller));

      expect(find.byTooltip("Undo"), findsOneWidget);
      expect(find.byTooltip("Redo"), findsOneWidget);

      await tester.tap(find.byTooltip("Publish this canvas"));
      await tester.pumpAndSettle();
      expect(published, 1);
    });
  });

  group("the canvas settings panel", () {
    testWidgets("changes the canvas width", (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasSettingsPanel(controller: controller));

      var field = find.byKey(const ValueKey("canvasWidth"));
      expect(field, findsOneWidget);
      expect(find.descendant(of: field, matching: find.text("1280")),
          findsOneWidget,
          reason: "it should show the current width");

      await tester.enterText(field, "800");
      await tester.pump();
      expect(controller.document.size.width, 800);
      // The height follows the ratio rather than being edited separately.
      expect(controller.document.size.height, 450);
    });

    testWidgets("changes the ratio", (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasSettingsPanel(controller: controller));

      await tester.tap(find.text("16:9").first);
      await tester.pumpAndSettle();
      await tester.tap(find.text("1:1").last);
      await tester.pumpAndSettle();

      expect(controller.document.size.ratio, CanvasRatio.square);
      expect(controller.document.size.height, controller.document.size.width);
    });

    testWidgets("shows what publishing will cost", (tester) async {
      // Moved here from a chip floating over the bottom-left corner of the
      // canvas. It belongs with the two settings that decide it.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasSettingsPanel(controller: controller));

      expect(find.text("ESTIMATED SIZE"), findsOneWidget);
      expect(find.text("as a PNG"), findsOneWidget);

      controller.apply(controller.document.copyWith(frames: 24));
      await tester.pumpAndSettle();
      expect(find.text("as a GIF"), findsOneWidget);
    });

    testWidgets("does not overflow a narrow window", (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      tester.view.physicalSize = const Size(700, 900);
      await pump(tester, CanvasSettingsPanel(controller: controller));
      expect(tester.takeException(), isNull);
    });

    testWidgets("typing a width is one undo step", (tester) async {
      // The panel writes transient edits and commits when the control is let
      // go. Without that, typing a four-digit width would be four undo steps.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasSettingsPanel(controller: controller));

      var field = find.byKey(const ValueKey("canvasWidth"));
      await tester.enterText(field, "900");
      await tester.pump();
      await tester.enterText(field, "901");
      await tester.pump();
      controller.endInteraction();

      expect(controller.canUndo, isTrue,
          reason: "a change made through the panel must be undoable at all");
      controller.undo();
      expect(controller.document.size.width, 1280,
          reason: "the whole typed edit is one step, not two");
    });
  });

  group("the design elements panel", () {
    testWidgets("offers every kind, and adding one selects it",
        (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasElementsPanel(controller: controller));

      for (var kind in ElementKind.values) {
        expect(find.text(kind.label), findsWidgets, reason: kind.name);
      }

      await tester.tap(find.text("Chart").first);
      await tester.pumpAndSettle();

      expect(controller.document.elements.length, 1);
      expect(controller.document.elements.single.kind, ElementKind.chart);
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

    testWidgets("no longer carries the layer list", (tester) async {
      // It moved to its own tab. Adding is asked once, "what is here" is asked
      // continuously, and sharing a panel buried the second under the first.
      var document = const CanvasDocument();
      var controller =
          CanvasController(document.addElement(newElement(ElementKind.text, document)));
      addTearDown(controller.dispose);
      await pump(tester, CanvasElementsPanel(controller: controller));

      expect(find.text("ADD"), findsOneWidget);
      expect(find.text("LAYERS"), findsNothing);
      expect(find.byType(CanvasLayerRow), findsNothing);
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
      await pump(tester, CanvasLayersPanel(controller: controller));

      var first = controller.document.elements.first;

      await tester.tap(find.byTooltip("Hide").first);
      await tester.pumpAndSettle();
      expect(
          controller.document.elements.any((e) => !e.visible), isTrue);

      await tester.tap(find.byTooltip("Lock").first);
      await tester.pumpAndSettle();
      expect(controller.document.elements.any((e) => e.locked), isTrue);

      // The list is drawn front-to-back, so its first row is the last element.
      // "Move back" on it must actually change the paint order.
      var before = controller.document.elements.last.id;
      await tester.tap(find.byTooltip("Move back").first);
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
      await pump(tester, CanvasLayersPanel(controller: controller));

      // Nothing selected: the list, and no settings under it.
      expect(find.text("TYPE"), findsNothing);

      controller.selectOnly(element.id);
      await tester.pumpAndSettle();
      expect(find.text("TYPE"), findsWidgets);
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
      await pump(tester, CanvasLayersPanel(controller: controller));

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
      expect(find.byTooltip("Try the next variation"), findsOneWidget);
      var seed = controller.document.background.spec.seed;
      await tester.tap(find.byTooltip("Try the next variation"));
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

    testWidgets("the divider resizes the settings area", (tester) async {
      // The list grows without limit -- a football canvas is thirty layers --
      // and settings pushed off the bottom by it are settings that have to be
      // scrolled back to after every selection.
      var controller = CanvasController(footballCanvas());
      addTearDown(controller.dispose);
      controller.selectBackground();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false),
            child: SizedBox(
              width: 280,
              height: 600,
              child: CanvasLayersPanel(controller: controller),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      var top = tester.getTopLeft(find.byType(CanvasLayersPanel)).dy;
      var listBefore = tester.getSize(find.byType(ListView).first).height;

      // The grip sits just under the list. Dragging it up shrinks the list and
      // gives the settings the room.
      await tester.dragFrom(
          Offset(140, top + listBefore + 5), const Offset(0, -120));
      await tester.pumpAndSettle();

      var listAfter = tester.getSize(find.byType(ListView).first).height;
      expect(listAfter, lessThan(listBefore));
      expect(listAfter, closeTo(listBefore - 120, 2));
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
          body: ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false),
            child: SizedBox(
              width: 260,
              height: 800,
              child: CanvasLayersPanel(controller: controller),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: "the settings column must not overflow the sidebar");
    });
  });

  group("a team's settings", () {
    /// panel pumps the Layers sidebar with a team selected, which is where an
    /// element's settings live.
    Future<CanvasController> panel(WidgetTester tester,
        {TeamElement? team}) async {
      var document = const CanvasDocument(size: CanvasSize(width: 1000));
      var element = (team ??
              TeamElement(
                ElementBase(id: newElementId(), width: 400, height: 300),
              ).withFormation(TeamFormation.f442))
          as CanvasElement;
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasLayersPanel(controller: controller));
      return controller;
    }

    TeamElement teamIn(CanvasController c) =>
        c.document.elements.whereType<TeamElement>().single;

    testWidgets("one element is the whole team", (tester) async {
      var controller = await panel(tester);
      expect(teamIn(controller).players.length, 11,
          reason: "ten outfield players and a goalkeeper");
      expect(find.text("TEAM"), findsWidgets);
      expect(find.text("PLAYERS"), findsOneWidget);
    });

    testWidgets("choosing a formation moves everybody", (tester) async {
      var controller = await panel(tester);
      var before = [for (var p in teamIn(controller).players) (p.dx, p.dy)];

      await tester.tap(find.text("4-4-2").first);
      await tester.pumpAndSettle();
      await tester.tap(find.text("4-3-3").last);
      await tester.pumpAndSettle();

      var after = teamIn(controller);
      expect(after.formation, TeamFormation.f433);
      expect([for (var p in after.players) (p.dx, p.dy)], isNot(before));
      expect(after.players.length, 11);
    });

    testWidgets("the squad list opens and edits one player", (tester) async {
      // Behind an expander because eleven rows of four fields is more than
      // every other element's settings put together.
      var controller = await panel(tester);
      var id = teamIn(controller).id;

      expect(find.byKey(ValueKey("name-0-$id")), findsNothing);
      await tester.tap(find.text("PLAYERS"));
      await tester.pumpAndSettle();

      // The goalkeeper is the first row, and is labelled as such.
      expect(find.text("GK"), findsOneWidget);

      await tester.enterText(find.byKey(ValueKey("name-0-$id")), "Banks");
      await tester.pump();
      expect(teamIn(controller).players.first.name, "Banks");

      await tester.enterText(find.byKey(ValueKey("num-0-$id")), "01");
      await tester.pump();
      expect(teamIn(controller).players.first.number, "01",
          reason: "a squad number is written, not counted");
    });

    testWidgets("a player's coordinates are the canvas's, not the box's",
        (tester) async {
      var team = TeamElement(
        ElementBase(id: newElementId(), x: 100, y: 50, width: 400, height: 300),
      ).withFormation(TeamFormation.f442);
      var controller = await panel(tester, team: team);
      var id = teamIn(controller).id;

      await tester.tap(find.text("PLAYERS"));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(ValueKey("x-0-$id")), "260");
      await tester.pump();
      var keeper = teamIn(controller).players.first;
      expect(teamIn(controller).centreOf(keeper).dx, closeTo(260, 0.5),
          reason: "typed as a canvas coordinate, stored as a fraction");
      expect(keeper.dx, closeTo((260 - 100) / 400, 0.001));
    });

    testWidgets("lock, hide and reorder work per player", (tester) async {
      var controller = await panel(tester);
      await tester.tap(find.text("PLAYERS"));
      await tester.pumpAndSettle();

      /// press taps a control inside one player's row.
      ///
      /// Scoped to the row rather than found by tooltip alone, because the
      /// element's own Lock and Hide sit above the squad list with exactly the
      /// same tooltips -- so `.first` locks the whole team instead of the
      /// goalkeeper. And scrolled into view first: eleven rows of four fields
      /// is taller than the settings column, so most of the squad is below the
      /// fold and a tap at its computed position lands outside the viewport.
      Future<void> press(int index, String tooltip) async {
        var finder = find.descendant(
          of: find.byKey(ValueKey("player-$index-${teamIn(controller).id}")),
          matching: find.byTooltip(tooltip),
        );
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await press(0, "Lock in place");
      expect(teamIn(controller).players.first.locked, isTrue);
      expect(teamIn(controller).locked, isFalse,
          reason: "locking a player must not lock the whole team");

      await press(0, "Hide");
      expect(teamIn(controller).players.first.hidden, isTrue);

      var second = teamIn(controller).players[1].number;
      await press(0, "Bring forward");
      expect(teamIn(controller).players[0].number, second,
          reason: "the keeper moved up one, so the next player is now first");
    });

    testWidgets("the dot's width and height are locked together",
        (tester) async {
      // A player marker is a circle, and an oval is almost always somebody
      // having dragged one field without meaning to.
      var controller = await panel(tester);
      expect(teamIn(controller).lockDotAspect, isTrue);

      await tester.enterText(
          find.byKey(const ValueKey("teamDotWidth")), "60");
      await tester.pump();
      expect(teamIn(controller).dotWidth, 60);
      expect(teamIn(controller).dotHeight, 60);

      // Scrolled to first: a team has more settings than fit in the panel,
      // and a tap on something below the fold lands on whatever is there.
      var lock = find.byTooltip("Width and height move together");
      await tester.ensureVisible(lock);
      await tester.pumpAndSettle();
      await tester.tap(lock);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey("teamDotHeight")), "20");
      await tester.pump();
      expect(teamIn(controller).dotWidth, 60, reason: "now independent");
      expect(teamIn(controller).dotHeight, 20);
    });

    testWidgets("numbers and names share one set of type controls",
        (tester) async {
      // They were two identical panels, and the two drifted -- a team's names
      // ended up in a different face from its numbers.
      var controller = await panel(tester);
      expect(find.text("NUMBERS AND NAMES"), findsOneWidget);
      expect(teamIn(controller).labelSpec.fontSize, isNotNull);
    });
  });

  group("the timeline", () {

    testWidgets("adds and removes a keyframe for the selected element",
        (tester) async {
      var document = const CanvasDocument(frames: 20);
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      controller.frame = 7;

      await pump(tester, CanvasTimeline(controller: controller));

      await tester.tap(find.byTooltip(
          "Add a keyframe for ${element.name} here"));
      await tester.pumpAndSettle();

      var track = controller.document.elements.single.track;
      expect(track, isNotNull);
      expect(track!.keyAt(7), isNotNull);

      // The tooltip names what it belongs to, since the same button also
      // edits a focused player's keyframes.
      await tester.tap(
          find.byTooltip("Remove this keyframe from ${element.name}"));
      await tester.pumpAndSettle();
      // The track goes entirely rather than being left empty, so a saved file
      // carries no dead animation.
      expect(controller.document.elements.single.track, isNull);
    });

    testWidgets("says what to do when nothing is selected", (tester) async {
      var controller = CanvasController(const CanvasDocument(frames: 10));
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      // On the disclosure itself, since with nothing selected there is
      // nothing to open it for.
      expect(
          find.byTooltip(
              "Select an element, or click a player, to give it a keyframe"),
          findsOneWidget);
    });

    testWidgets("changes the frame count and the frame rate", (tester) async {
      // Both moved here from the settings band: they describe the strip they
      // now sit on.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      expect(find.text("Still"), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey("canvasFrames")), "24");
      await tester.pump();
      expect(controller.document.frames, 24);
      expect(find.text("Still"), findsNothing);

      await tester.enterText(
          find.byKey(const ValueKey("canvasFrameRate")), "30");
      await tester.pump();
      expect(controller.document.frameRate, 30);
      expect(find.text("0.8s"), findsOneWidget);
    });

    testWidgets("the playhead and the length are one editable control",
        (tester) async {
      // They were a readout and a separate Frames field a few pixels apart,
      // saying the same number twice -- and the field was too narrow for four
      // digits, so a long document showed "10000" clipped to "1000".
      var controller = CanvasController(const CanvasDocument(frames: 40));
      addTearDown(controller.dispose);
      controller.frame = 12;
      await pump(tester, CanvasTimeline(controller: controller));

      var playhead = find.byKey(const ValueKey("canvasFrame"));
      var length = find.byKey(const ValueKey("canvasFrames"));
      // One-based on screen: the first frame is frame 1 to everybody except a
      // computer.
      expect(find.descendant(of: playhead, matching: find.text("13")),
          findsOneWidget);
      expect(find.descendant(of: length, matching: find.text("40")),
          findsOneWidget);

      await tester.enterText(playhead, "25");
      await tester.pump();
      expect(controller.frame, 24);

      await tester.enterText(length, "600");
      await tester.pump();
      expect(controller.document.frames, 600);
    });

    testWidgets("a long document's numbers still fit", (tester) async {
      var controller =
          CanvasController(const CanvasDocument(frames: maxFrameCount));
      addTearDown(controller.dispose);
      controller.frame = maxFrameCount - 1;
      await pump(tester, CanvasTimeline(controller: controller));

      expect(tester.takeException(), isNull);
      var length = find.byKey(const ValueKey("canvasFrames"));
      expect(find.descendant(of: length, matching: find.text("$maxFrameCount")),
          findsOneWidget);
      // One line: the control plus its caption. Two would be a caption and
      // two rows of field.
      expect(tester.getSize(length).height,
          lessThan(controlHeight + controlLabelHeight + 4));
    });

    testWidgets("typing in a field keeps its own arrow keys and space bar",
        (tester) async {
      // The transport's Focus sits below the app's text-editing shortcuts, so
      // its handler ran first: an arrow pressed while typing a frame number
      // scrubbed the timeline instead of moving the caret, and a space started
      // playback instead of typing.
      var controller = CanvasController(const CanvasDocument(frames: 40));
      addTearDown(controller.dispose);
      controller.frame = 12;
      await pump(tester, CanvasTimeline(controller: controller));

      await tester.tap(find.byKey(const ValueKey("canvasFrameRate")));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      expect(controller.frame, 12, reason: "the playhead did not move");
      expect(controller.playing, isFalse, reason: "and nothing started");
    });

    testWidgets("steps the playhead", (tester) async {
      var controller = CanvasController(const CanvasDocument(frames: 10));
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      expect(
          find.descendant(
              of: find.byKey(const ValueKey("canvasFrame")),
              matching: find.text("1")),
          findsOneWidget);
      await tester.tap(find.byTooltip("Next frame"));
      await tester.pumpAndSettle();
      expect(controller.frame, 1);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey("canvasFrame")),
              matching: find.text("2")),
          findsOneWidget);

      // Clamped rather than wrapping or running past the end.
      await tester.tap(find.byTooltip("Previous frame"));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip("Previous frame"));
      await tester.pumpAndSettle();
      expect(controller.frame, 0);
    });

    testWidgets("the transport row does not move when the playhead lands on a "
        "keyframe", (tester) async {
      // The reported problem: the pose controls sat on the transport row and
      // appeared as the playhead crossed a keyframe, so the row changed width
      // under the pointer and the play buttons moved while scrubbing.
      var document = const CanvasDocument(frames: 20);
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasTimeline(controller: controller));

      var playAt = tester.getTopLeft(find.byTooltip("Play"));
      controller.setKeyframe(element.id, const Keyframe(frame: 0));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.byTooltip("Play")), playAt,
          reason: "landing on a keyframe must not move the transport");
      expect(find.text("Easing"), findsNothing,
          reason: "the pose controls are behind the disclosure");
      // The two keyframe buttons stay on this row -- they are pressed
      // constantly while animating and neither changes width, so neither can
      // shift it.
      expect(find.byTooltip("Remove this keyframe from ${element.name}"),
          findsOneWidget);
      expect(
          find.byTooltip(
              "Auto-keyframe: record a keyframe whenever something moves"),
          findsOneWidget);
    });

    testWidgets("the pose bar floats rather than resizing the strip",
        (tester) async {
      // Opening it must not change the timeline's height: the strip is at the
      // bottom of the screen, so a taller one takes height from the canvas
      // area and re-fits the canvas -- opening a panel moved the design.
      var document = const CanvasDocument(frames: 20);
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      controller.setKeyframe(element.id, const Keyframe(frame: 0));

      var open = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false),
            child: StatefulBuilder(
              builder: (context, setState) => Column(children: [
                const Spacer(),
                CanvasTimeline(
                  controller: controller,
                  keyframesOpen: open,
                  onToggleKeyframes: () => setState(() => open = !open),
                ),
              ]),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      var closed = tester.getSize(find.byType(CanvasTimeline)).height;
      await tester.tap(
          find.byTooltip("Keyframe settings for ${element.name}"));
      await tester.pumpAndSettle();

      expect(open, isTrue);
      expect(tester.getSize(find.byType(CanvasTimeline)).height, closed,
          reason: "the strip is exactly as tall as it was");
      expect(find.text("Easing"), findsNothing,
          reason: "the controls are in the floating bar, not in the strip");
    });

    testWidgets("the pose bar carries the keyframe's controls",
        (tester) async {
      var document = const CanvasDocument(frames: 20);
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasKeyframeBar(controller: controller));

      // Opened on a frame with no keyframe it would otherwise be blank, which
      // reads as broken rather than as empty.
      expect(find.textContaining("No keyframe on this frame"), findsOneWidget);

      controller.setKeyframe(element.id, const Keyframe(frame: 0));
      await tester.pumpAndSettle();
      expect(find.text("Easing"), findsOneWidget);

      await tester.tap(find.text("Linear").first);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Ease in-out").last);
      await tester.pumpAndSettle();
      expect(controller.document.elements.single.track!.keyAt(0)!.easing,
          KeyframeEasing.easeInOut);
    });

    testWidgets("auto-keyframe can be turned on from the transport",
        (tester) async {
      var controller = CanvasController(const CanvasDocument(frames: 24));
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      expect(controller.autoKeyframe, isFalse, reason: "off by default");
      await tester.tap(find.byTooltip(
          "Auto-keyframe: record a keyframe whenever something moves"));
      await tester.pumpAndSettle();
      expect(controller.autoKeyframe, isTrue);
    });

    testWidgets("keyframes follow the focused player", (tester) async {
      // A player has no id and cannot be selected, so the focused player is
      // the only thing that says the controls are about them rather than about
      // the team they are in.
      var team = TeamElement(
        ElementBase(id: newElementId(), width: 400, height: 300),
      ).withFormation(TeamFormation.f442);
      var controller = CanvasController(
          const CanvasDocument(frames: 24).addElement(team));
      addTearDown(controller.dispose);
      controller.selectOnly(team.id);
      controller.frame = 6;
      await pump(tester, CanvasTimeline(controller: controller));

      controller.focusedPlayer = 4;
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip("Add a keyframe for #5 (Team) here"));
      await tester.pumpAndSettle();

      var after =
          controller.document.elements.whereType<TeamElement>().single;
      expect(after.players[4].track?.keyAt(6), isNotNull);
      expect(after.track, isNull,
          reason: "the team itself did not get the keyframe");
    });

    testWidgets("adds a timeline marker and lets it be removed",
        (tester) async {
      var controller = CanvasController(const CanvasDocument(frames: 30));
      addTearDown(controller.dispose);
      controller.frame = 12;
      await pump(tester, CanvasTimeline(controller: controller));

      await tester.tap(find.byTooltip(
          "Loop back — Jump back to the target frame and carry on"));
      await tester.pumpAndSettle();

      expect(controller.document.actions.single.frame, 12);
      expect(find.text("To frame"), findsOneWidget);

      await tester.tap(find.byTooltip("Remove this marker"));
      await tester.pumpAndSettle();
      expect(controller.document.actions, isEmpty);
    });
  });

  group("the settings section", () {
    testWidgets("turns Canvas on and off", (tester) async {
      var prefs = CanvasPreferences();
      addTearDown(prefs.dispose);

      await pump(tester, const CanvasSettingsSection(), prefs: prefs);

      // Off by default: a whole page and a nav item has to be asked for.
      expect(prefs.enabled, isFalse);
      expect(find.text("Canvas"), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(prefs.enabled, isTrue);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(prefs.enabled, isFalse);
    });
  });

  group("the clipboard", () {
    test("copy and paste makes a separate element", () {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);

      controller.copySelected();
      expect(controller.canPaste, isTrue);
      controller.paste();

      expect(controller.document.elements.length, 2);
      var pasted = controller.document.elements.last;
      expect(pasted.id, isNot(element.id), reason: "a new element, not an alias");
      // Offset, because a copy landing exactly on its original is
      // indistinguishable from nothing having happened.
      expect(pasted.x, greaterThan(element.x));
      expect(controller.selection, {pasted.id},
          reason: "what was pasted is what is selected");
    });

    test("pasting twice makes two copies, each visible", () {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      controller.copySelected();
      controller.paste();
      controller.paste();

      var xs = controller.document.elements.map((e) => e.x).toSet();
      expect(controller.document.elements.length, 3);
      expect(xs.length, 2,
          reason: "both copies are off the original; they may share a place");
    });

    test("cut copies before it deletes", () {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.text, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);

      controller.cutSelected();
      expect(controller.document.elements, isEmpty);

      controller.paste();
      expect(controller.document.elements.length, 1);
      expect(controller.document.elements.single.kind, ElementKind.text);
    });

    test("the clipboard survives the page being left", () {
      // Static, for the same reason the session is a provider: leaving Canvas
      // for a chat and coming back must not lose what was copied.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var first = CanvasController(document.addElement(element));
      first.selectOnly(element.id);
      first.copySelected();
      first.dispose();

      var second = CanvasController(const CanvasDocument());
      addTearDown(second.dispose);
      expect(second.canPaste, isTrue);
      second.paste();
      expect(second.document.elements.length, 1);
    });
  });

  group("autosave", () {
    test("does nothing until the document has been saved once", () {
      // Otherwise there is nowhere to write to, and inventing a filename would
      // leave documents in the library nobody asked to keep -- somebody who
      // opens a preset, plays with it and walks away should find nothing new.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      expect(controller.name, isNull);

      controller.apply(controller.document.copyWith(frames: 12));
      expect(controller.dirty, isTrue);
      // scheduleAutosave is called by apply; with no name it must arm nothing.
      controller.scheduleAutosave();
      expect(controller.name, isNull,
          reason: "and it certainly must not invent one");
    });
  });

  group("the session", () {
    test("outlives the page, and only restores on its first open", () {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      expect(controller.opened, isFalse,
          reason: "the first visit restores the last saved file");

      controller.markOpened();
      expect(controller.opened, isTrue,
          reason: "every visit after that keeps the work in progress");
    });
  });

  group("a path on the timeline", () {
    (CanvasController, PathElement) withPath() {
      var path = PathElement(
        const ElementBase(id: "p", x: 0, y: 0, width: 200, height: 200),
        nodes: const [
          PathNode(x: 0, y: 0, frame: 0),
          PathNode(x: 0.5, y: 0.5, frame: 10),
          PathNode(x: 1, y: 1, frame: 20),
        ],
      );
      var controller =
          CanvasController(const CanvasDocument(frames: 30).addElement(path));
      controller.selectOnly("p");
      return (controller, path);
    }

    testWidgets("the strip is about its points, not its (empty) track",
        (tester) async {
      // A path's own track is empty -- what moves is the follower -- so
      // without this a selected path showed a bare strip, and the one thing
      // worth retiming from the timeline could not be reached from it.
      var (controller, _) = withPath();
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      controller.frame = 10;
      await tester.pumpAndSettle();
      expect(find.byTooltip("Remove this keyframe from Path"), findsOneWidget,
          reason: "frame 10 has a point on it");

      controller.frame = 11;
      await tester.pumpAndSettle();
      expect(find.byTooltip("Add a keyframe for Path here"), findsOneWidget);
    });

    testWidgets("the diamond adds and removes a point", (tester) async {
      var (controller, _) = withPath();
      addTearDown(controller.dispose);
      controller.frame = 15;
      await pump(tester, CanvasTimeline(controller: controller));

      // The pose bar is a message for a path: easing, fade, scale and turn all
      // belong to the follower rather than to the point, so offering them here
      // would be four controls that quietly do nothing.
      await pump(tester, CanvasKeyframeBar(controller: controller));
      expect(find.textContaining("No point on this frame"), findsOneWidget);

      await pump(tester, CanvasTimeline(controller: controller));
      await tester.tap(find.byTooltip("Add a keyframe for Path here"));
      await tester.pumpAndSettle();

      var after = controller.document.elements.single as PathElement;
      expect(after.nodes.length, 4);
      expect(after.nodes.map((n) => n.frame).toList(), [0, 10, 15, 20]);

      await tester.tap(find.byTooltip("Remove this keyframe from Path"));
      await tester.pumpAndSettle();
      expect((controller.document.elements.single as PathElement).nodes.length, 3);
    });

    testWidgets("a point drags along the strip to retime it", (tester) async {
      var (controller, _) = withPath();
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      // The ruler is the strip's own CustomPaint, and the marks sit at
      // _rulerHeight + 14 down it -- see _keyframeAt, which is what this is
      // exercising.
      var ruler = find
          .descendant(
              of: find.byType(CanvasTimeline), matching: find.byType(CustomPaint))
          .last;
      var box = tester.getRect(ruler);
      // The same mapping _xFor uses, so the drag starts exactly on the mark.
      double xFor(int frame) => box.left + (frame + 0.5) / 30 * box.width;

      await tester.dragFrom(
        Offset(xFor(10), box.top + 22 + 14),
        Offset(xFor(15) - xFor(10), 0),
      );
      await tester.pumpAndSettle();

      var after = controller.document.elements.single as PathElement;
      expect(after.nodes[1].frame, greaterThan(10),
          reason: "the middle point moved later");
      expect(after.nodes[1].frame, lessThanOrEqualTo(20),
          reason: "clamped by its neighbour rather than reordering the curve");
      expect(after.nodes[0].frame, 0, reason: "the others stayed put");
      expect(after.nodes[2].frame, 20);
    });

    testWidgets("a drag away from the marks still scrubs", (tester) async {
      var (controller, _) = withPath();
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      var ruler = find
          .descendant(
              of: find.byType(CanvasTimeline), matching: find.byType(CustomPaint))
          .last;
      var box = tester.getRect(ruler);

      // On the ruler's numbers, above the keyframe row: that is where the
      // playhead is grabbed, and a drag starting there scrubs even if it
      // happens to begin above a mark.
      await tester.dragFrom(
          Offset(box.left + 12, box.top + 4), const Offset(200, 0));
      await tester.pumpAndSettle();

      expect(controller.frame, greaterThan(0));
      var after = controller.document.elements.single as PathElement;
      expect(after.nodes.map((n) => n.frame).toList(), [0, 10, 20],
          reason: "nothing was retimed");
    });

  });

  group("clearing keyframes", () {
    /// pitch is a team with a run on one player, plus a shape with its own
    /// animation -- two channels, so "this one" and "all of them" can be told
    /// apart.
    (CanvasController, TeamElement, CanvasElement) pitch() {
      var team = TeamElement(
        const ElementBase(id: "t", x: 0, y: 0, width: 400, height: 300),
      ).withFormation(TeamFormation.f442);
      var shape = ShapeElement(const ElementBase(id: "s", width: 40, height: 40));
      var controller = CanvasController(
          const CanvasDocument(frames: 30).addElement(team).addElement(shape));

      controller.setPlayerKeyframe("t", 6, const Keyframe(frame: 0));
      controller.setPlayerKeyframe("t", 6, const Keyframe(frame: 12, dx: 50));
      controller.setPlayerKeyframe("t", 2, const Keyframe(frame: 4, dy: 20));
      controller.setKeyframe("s", const Keyframe(frame: 8, dx: 30));
      return (controller, team, shape);
    }

    TeamElement teamOf(CanvasController c) =>
        c.document.elements.whereType<TeamElement>().single;

    testWidgets("clear channel takes one player's run and nobody else's",
        (tester) async {
      var (controller, team, _) = pitch();
      addTearDown(controller.dispose);
      controller.selectOnly("t");
      controller.focusedPlayer = 6;
      await pump(tester, CanvasTimeline(controller: controller));

      await tester.tap(find.byTooltip(
          "Clear every keyframe on #7 (${team.name})"));
      await tester.pumpAndSettle();

      expect(teamOf(controller).players[6].track, isNull);
      expect(teamOf(controller).players[2].track, isNotNull,
          reason: "the other player kept his");
      expect(controller.document.elementById("s")!.track, isNotNull,
          reason: "and so did the shape");
    });

    testWidgets("clear channel works on a plain element too", (tester) async {
      var (controller, _, shape) = pitch();
      addTearDown(controller.dispose);
      controller.selectOnly(shape.id);
      await pump(tester, CanvasTimeline(controller: controller));

      await tester.tap(find.byTooltip("Clear every keyframe on ${shape.name}"));
      await tester.pumpAndSettle();

      expect(controller.document.elementById("s")!.track, isNull);
      expect(teamOf(controller).players[6].track, isNotNull);
    });

    testWidgets("clear all empties every channel at once", (tester) async {
      var (controller, _, _) = pitch();
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      expect(controller.document.hasKeyframes, isTrue);
      await tester.tap(
          find.byTooltip("Clear every keyframe in the whole canvas"));
      await tester.pumpAndSettle();

      expect(controller.document.hasKeyframes, isFalse);
      expect(teamOf(controller).players[6].track, isNull);
      expect(teamOf(controller).players[2].track, isNull);
      expect(controller.document.elementById("s")!.track, isNull);
    });

    testWidgets("clear all is one undo step", (tester) async {
      // A single decision, and unpicking it element by element is not
      // something anybody would want to do twenty-two times.
      var (controller, _, _) = pitch();
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      await tester.tap(
          find.byTooltip("Clear every keyframe in the whole canvas"));
      await tester.pumpAndSettle();
      controller.undo();

      expect(controller.document.hasKeyframes, isTrue);
      expect(teamOf(controller).players[6].track, isNotNull);
      expect(controller.document.elementById("s")!.track, isNotNull);
    });

    testWidgets("both are off when there is nothing to clear", (tester) async {
      var controller = CanvasController(const CanvasDocument(frames: 30));
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      expect(
          tester
              .widget<InkWell>(find.descendant(
                  of: find.byTooltip(
                      "Clear every keyframe in the whole canvas"),
                  matching: find.byType(InkWell)))
              .onTap,
          isNull);
    });

    testWidgets("a path's points are not clearable from the strip",
        (tester) async {
      // They are where the curve goes rather than a pose, so clearing them
      // would delete the route instead of its timing -- and a path with no
      // points is not a path.
      var path = PathElement(
        const ElementBase(id: "p", width: 200, height: 200),
        nodes: const [
          PathNode(x: 0, y: 0, frame: 0),
          PathNode(x: 1, y: 1, frame: 10),
        ],
      );
      var controller =
          CanvasController(const CanvasDocument(frames: 30).addElement(path));
      addTearDown(controller.dispose);
      controller.selectOnly("p");
      await pump(tester, CanvasTimeline(controller: controller));

      var button = find.byTooltip(
          "A path's marks are its points — remove them in its settings");
      expect(button, findsOneWidget);
      expect(
          tester
              .widget<InkWell>(find.descendant(
                  of: button, matching: find.byType(InkWell)))
              .onTap,
          isNull);
      expect((controller.document.elements.single as PathElement).nodes.length, 2);
    });

    test("clearing the whole document leaves paths their points", () {
      // Re-applying a route is a button press; redrawing it is not.
      var path = PathElement(
        const ElementBase(id: "p", width: 200, height: 200),
        nodes: const [
          PathNode(x: 0, y: 0, frame: 0),
          PathNode(x: 1, y: 1, frame: 10),
        ],
        follow: const PathFollow(elementId: "s"),
      );
      var shape = ShapeElement(const ElementBase(id: "s", width: 20, height: 20));
      var controller = CanvasController(
          const CanvasDocument(frames: 30).addElement(shape).addElement(path));
      addTearDown(controller.dispose);

      controller.applyPathFollow(
          controller.document.elements.whereType<PathElement>().single);
      expect(controller.document.hasKeyframes, isTrue);

      controller.clearAllKeyframes();
      expect(controller.document.hasKeyframes, isFalse);
      expect(
          controller.document.elements.whereType<PathElement>().single.nodes.length,
          2);
    });
  });

  group("a follower's row on the strip", () {
    (CanvasController, TeamElement) followed() {
      var team = TeamElement(
        const ElementBase(
            id: "t", name: "Home", x: 0, y: 0, width: 400, height: 300),
      ).withFormation(TeamFormation.f442);
      var path = PathElement(
        const ElementBase(
            id: "p", name: "Run", x: 0, y: 0, width: 400, height: 300),
        nodes: const [
          PathNode(x: 0, y: 0, frame: 0),
          PathNode(x: 1, y: 1, frame: 12),
        ],
        follow: const PathFollow(elementId: "t", playerIndex: 0),
      );
      var controller = CanvasController(
          const CanvasDocument(frames: 30).addElement(team).addElement(path));
      controller.applyPathFollow(path);
      return (controller, team);
    }

    testWidgets("shows no marks of its own", (tester) async {
      // The reported problem: assigning the keeper to a path put keyframes on
      // the player *and* on the path, and editing the copy on the player did
      // nothing that survived the next re-bake.
      var (controller, _) = followed();
      addTearDown(controller.dispose);
      controller.selectOnly("t");
      controller.focusedPlayer = 0;
      await pump(tester, CanvasTimeline(controller: controller));

      expect(find.byTooltip("#1 (Home) is following Run — "
          "its timing is that path's points"), findsOneWidget);
      expect(find.byTooltip("Add a keyframe for #1 (Home) here"), findsNothing);
      expect(find.byTooltip("Remove this keyframe from #1 (Home)"),
          findsNothing);
    });

    testWidgets("cannot be cleared from the strip either", (tester) async {
      var (controller, _) = followed();
      addTearDown(controller.dispose);
      controller.selectOnly("t");
      controller.focusedPlayer = 0;
      await pump(tester, CanvasTimeline(controller: controller));

      var button = find.byTooltip("#1 (Home) is following Run — "
          "clear it by unlinking the path");
      expect(button, findsOneWidget);
      expect(
          tester
              .widget<InkWell>(
                  find.descendant(of: button, matching: find.byType(InkWell)))
              .onTap,
          isNull);
    });

    testWidgets("the pose bar says where the timing lives", (tester) async {
      var (controller, _) = followed();
      addTearDown(controller.dispose);
      controller.selectOnly("t");
      controller.focusedPlayer = 0;
      await pump(tester, CanvasKeyframeBar(controller: controller));

      expect(find.textContaining("is following Run"), findsOneWidget);
      expect(find.text("Easing"), findsNothing);
    });

    testWidgets("another player of the same team keeps his own row",
        (tester) async {
      var (controller, _) = followed();
      addTearDown(controller.dispose);
      controller.selectOnly("t");
      controller.focusedPlayer = 5;
      await pump(tester, CanvasTimeline(controller: controller));

      expect(find.byTooltip("Add a keyframe for #6 (Home) here"),
          findsOneWidget);
    });
  });

  group("the area outside the canvas", () {
    testWidgets("is off by default and toggles from the band", (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(
          tester,
          CanvasSettingsBar(
            controller: controller,
            onPublish: () {},
            canvasSettingsOpen: false,
            onToggleCanvasSettings: () {},
          ));

      expect(controller.showOverspill, isFalse,
          reason: "what the canvas shows is what gets published");
      await tester.tap(find.byTooltip("Show a margin outside the canvas, "
          "for animating things on and off"));
      await tester.pumpAndSettle();
      expect(controller.showOverspill, isTrue);

      await tester.tap(find.byTooltip("Hide the area outside the canvas"));
      await tester.pumpAndSettle();
      expect(controller.showOverspill, isFalse);
    });
  });

  group("selecting a keyframe", () {
    (CanvasController, CanvasElement) animated() {
      var document = const CanvasDocument(frames: 30);
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      controller.selectOnly(element.id);
      controller.setKeyframe(element.id, const Keyframe(frame: 0));
      controller.setKeyframe(element.id, const Keyframe(frame: 10, dx: 40));
      controller.setKeyframe(element.id, const Keyframe(frame: 20, dx: 80));
      return (controller, element);
    }

    /// tapMark clicks the mark at [frame] on the strip.
    Future<void> tapMark(WidgetTester tester, int frame, int frames) async {
      var ruler = find
          .descendant(
              of: find.byType(CanvasTimeline), matching: find.byType(CustomPaint))
          .last;
      var box = tester.getRect(ruler);
      await tester.tapAt(Offset(
          box.left + (frame + 0.5) / frames * box.width, box.top + 22 + 14));
      await tester.pumpAndSettle();
    }

    testWidgets("delete takes the keyframe, not the element", (tester) async {
      // The canvas's own Delete removes what is selected there, and with a
      // keyframe picked out that is the wrong thing by a long way: one is a
      // pose, the other is the whole element and everything on it.
      var (controller, element) = animated();
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      await tapMark(tester, 10, 30);
      expect(controller.frame, 10, reason: "clicking a mark goes to it");

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      expect(controller.document.elements.length, 1,
          reason: "the element is still there");
      var track = controller.document.elementById(element.id)!.track!;
      expect(track.keyAt(10), isNull, reason: "but that pose is gone");
      expect(track.keyAt(0), isNotNull);
      expect(track.keyAt(20), isNotNull);
    });

    testWidgets("delete does nothing with no mark picked out", (tester) async {
      var (controller, element) = animated();
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      // Focus the strip without landing on a mark.
      await tapMark(tester, 5, 30);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      expect(controller.document.elementById(element.id)!.track!.keys.length, 3);
    });

    testWidgets("the selection is dropped when the row changes",
        (tester) async {
      // A frame number means nothing once the strip is showing somebody
      // else's keyframes, and a stale one would put Delete on a mark the
      // reader never picked.
      var (controller, element) = animated();
      addTearDown(controller.dispose);
      var other = newElement(ElementKind.text, controller.document);
      controller.apply(controller.document.addElement(other));
      await pump(tester, CanvasTimeline(controller: controller));

      await tapMark(tester, 10, 30);
      controller.selectOnly(other.id);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      expect(controller.document.elementById(element.id)!.track!.keys.length, 3,
          reason: "the other element's keyframes were left alone");
      expect(controller.document.elements.length, 2);
    });
  });

  group("the element settings", () {
    testWidgets("carry no lock, hide or reorder controls", (tester) async {
      // All four are properties of the *layer* rather than of the thing on it,
      // and the layer list already shows them on the row that names the
      // element -- where hiding something does not make the panel you are
      // hiding it from disappear.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);

      await pump(
          tester,
          CanvasLayersPanel(controller: controller));

      // The layer row has them.
      expect(find.byTooltip("Lock"), findsOneWidget);
      expect(find.byTooltip("Hide"), findsOneWidget);
      expect(find.byTooltip("Move forward"), findsOneWidget);
      // The settings below it do not.
      expect(find.byTooltip("Lock in place"), findsNothing);
      expect(find.byTooltip("Bring to front"), findsNothing);
      expect(find.byTooltip("Send to back"), findsNothing);
    });

    testWidgets("a player row keeps its own, since the layer list has none",
        (tester) async {
      var team = TeamElement(
        const ElementBase(id: "t", name: "Home", width: 400, height: 300),
      ).withFormation(TeamFormation.f442);
      var controller =
          CanvasController(const CanvasDocument().addElement(team));
      addTearDown(controller.dispose);
      controller.selectOnly("t");

      await pump(tester, CanvasLayersPanel(controller: controller));
      await tester.tap(find.text("PLAYERS"));
      await tester.pumpAndSettle();

      expect(find.byTooltip("Lock in place"), findsWidgets,
          reason: "a player is not a layer and has nowhere else to be locked");
    });
  });

  group("animated settings", () {
    (CanvasController, CanvasElement) moving() {
      var document = const CanvasDocument(frames: 30);
      var element = ShapeElement(
          const ElementBase(id: "s", x: 100, y: 50, width: 40, height: 40));
      var controller = CanvasController(document.addElement(element));
      controller.selectOnly("s");
      controller.setKeyframe("s", const Keyframe(frame: 0));
      controller.setKeyframe("s", const Keyframe(frame: 20, dx: 200, dy: 60));
      return (controller, element);
    }

    testWidgets("X and Y show where the element is on this frame",
        (tester) async {
      // They showed where it *rests*, so scrubbing into the middle of a move
      // left two numbers describing somewhere the element visibly was not.
      var (controller, _) = moving();
      addTearDown(controller.dispose);
      controller.frame = 10;
      await pump(tester, CanvasLayersPanel(controller: controller));

      var x = find.byKey(const ValueKey("elementX"));
      expect(find.descendant(of: x, matching: find.text("200")), findsOneWidget,
          reason: "half way along a 100 to 300 move");
    });

    testWidgets("typing a position while animating writes a keyframe",
        (tester) async {
      var (controller, _) = moving();
      addTearDown(controller.dispose);
      controller.frame = 10;
      await pump(tester, CanvasLayersPanel(controller: controller));

      await tester.enterText(find.byKey(const ValueKey("elementX")), "500");
      await tester.pumpAndSettle();

      var element = controller.document.elementById("s")!;
      expect(element.x, 100, reason: "the resting position is untouched");
      expect(element.track!.keyAt(10)!.dx, 400);
      expect(element.boundsAt(10).left, 500);
      expect(element.boundsAt(0).left, 100, reason: "and frame 0 is unchanged");
    });

    testWidgets("the diamond adds and removes the pose here", (tester) async {
      var (controller, _) = moving();
      addTearDown(controller.dispose);
      controller.frame = 7;
      await pump(tester, CanvasLayersPanel(controller: controller));

      expect(controller.document.elementById("s")!.track!.keyAt(7), isNull);
      await tester.tap(find.byTooltip("Add a keyframe here for this element's "
          "position, size, angle and fade"));
      await tester.pumpAndSettle();
      expect(controller.document.elementById("s")!.track!.keyAt(7), isNotNull);

      await tester.tap(find.byTooltip(
          "Remove this element's keyframe here — one keyframe holds its "
          "position, size, angle and fade together"));
      await tester.pumpAndSettle();
      expect(controller.document.elementById("s")!.track!.keyAt(7), isNull);
    });

    testWidgets("the diamonds are off on a still canvas", (tester) async {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasLayersPanel(controller: controller));

      // One diamond for the group, not one per field: a keyframe here is a
      // whole pose, so six of them lit up and went out in unison.
      var dot = find
          .byTooltip("Give the canvas more than one frame to animate this "
              "element");
      expect(dot, findsOneWidget);
      expect(
          tester
              .widget<InkWell>(
                  find.descendant(of: dot, matching: find.byType(InkWell)))
              .onTap,
          isNull);
    });

    testWidgets("angle and opacity follow the pose too", (tester) async {
      var (controller, _) = moving();
      addTearDown(controller.dispose);
      controller.setKeyframe(
          "s", const Keyframe(frame: 20, rotate: 90, opacity: 0.5));
      controller.frame = 20;
      await pump(tester, CanvasLayersPanel(controller: controller));

      expect(
          find.descendant(
              of: find.byKey(const ValueKey("elementAngle")),
              matching: find.text("90")),
          findsOneWidget);
    });
  });

  group("the shape settings", () {
    /// panel builds an element's settings the way the Layers sidebar does.
    Future<CanvasController> panel(WidgetTester tester, ShapeElement shape,
        {String? text}) async {
      var element = text == null ? shape : shape.copyWith(text: text);
      var controller =
          CanvasController(const CanvasDocument().addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasLayersPanel(controller: controller));
      return controller;
    }

    ShapeElement shapeOf(ShapeKind kind) => ShapeElement(
          const ElementBase(id: "s", width: 200, height: 120),
          shape: kind,
        );

    testWidgets("a bubble shows its own settings, label or no label",
        (tester) async {
      // They were nested inside "if there is a label" by accident, so a bubble
      // with nothing written in it offered none of them -- which is exactly
      // the state a bubble is in when it has just been added.
      await panel(tester, shapeOf(ShapeKind.speechBubble));
      expect(find.text("BUBBLE"), findsOneWidget);
      expect(find.text("Body"), findsOneWidget);
      expect(find.text("Tail"), findsOneWidget);
      expect(find.text("Points"), findsOneWidget);
    });

    testWidgets("and still shows them once it has one", (tester) async {
      await panel(tester, shapeOf(ShapeKind.speechBubble), text: "Hello");
      expect(find.text("BUBBLE"), findsOneWidget);
      expect(find.text("LABEL TYPE"), findsOneWidget);
    });

    testWidgets("another shape shows none of them", (tester) async {
      await panel(tester, shapeOf(ShapeKind.star), text: "Hi");
      expect(find.text("BUBBLE"), findsNothing);
      expect(find.text("Tail"), findsNothing);
    });

    testWidgets("the label's type appears only when there is a label",
        (tester) async {
      await panel(tester, shapeOf(ShapeKind.star));
      expect(find.text("LABEL TYPE"), findsNothing);
    });

    testWidgets("changing the tail writes it to the element", (tester) async {
      var controller = await panel(tester, shapeOf(ShapeKind.speechBubble));

      await tester.tap(find.text(BubbleTail.pointer.label).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(BubbleTail.thought.label).last);
      await tester.pumpAndSettle();

      var after = controller.document.elements.single as ShapeElement;
      expect(after.bubble.tail, BubbleTail.thought);
    });

    testWidgets("the tail angle can be typed", (tester) async {
      var controller = await panel(tester, shapeOf(ShapeKind.speechBubble));
      await tester.enterText(
          find.byKey(const ValueKey("bubbleTailAngle")), "270");
      await tester.pump();
      expect(
          (controller.document.elements.single as ShapeElement).bubble.tailAngle,
          270);
    });

    testWidgets("the curl appears only for a curved tail", (tester) async {
      await panel(tester, shapeOf(ShapeKind.speechBubble));
      expect(find.text("Curl"), findsNothing);

      var curved = ShapeElement(
        const ElementBase(id: "s", width: 200, height: 120),
        shape: ShapeKind.speechBubble,
        bubble: const SpeechBubbleSpec(tail: BubbleTail.curved),
      );
      await panel(tester, curved);
      expect(find.text("Curl"), findsOneWidget);
    });
  });

  group("scrubbing a number", () {
    testWidgets("one pixel is one of the field's own last digits",
        (tester) async {
      // Not a fraction of the field's range, which was the first attempt and
      // was hundreds per pixel: most of these ranges are guard rails rather
      // than scales.
      var controller = CanvasController(const CanvasDocument(frames: 200));
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      var caption = find.descendant(
          of: find.byKey(const ValueKey("canvasFrames")),
          matching: find.text("Length"));
      await tester.drag(caption, const Offset(40, 0));
      await tester.pumpAndSettle();

      // A whole-number field, so forty pixels is forty frames.
      expect(controller.document.frames, 240);
    });

    testWidgets("dragging the caption runs the value up and down",
        (tester) async {
      var controller = CanvasController(const CanvasDocument(frames: 40));
      addTearDown(controller.dispose);
      controller.frame = 10;
      await pump(tester, CanvasTimeline(controller: controller));

      var before = controller.document.frames;
      // The caption above the field is the handle -- a TextField owns its own
      // drag, which is how text is selected, so the field itself cannot be it.
      var caption = find.descendant(
          of: find.byKey(const ValueKey("canvasFrames")),
          matching: find.text("Length"));
      expect(caption, findsOneWidget);

      await tester.drag(caption, const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(controller.document.frames, greaterThan(before));

      var up = controller.document.frames;
      await tester.drag(caption, const Offset(-60, 0));
      await tester.pumpAndSettle();
      expect(controller.document.frames, lessThan(up),
          reason: "and back down again");
    });

    testWidgets("it stays inside the field's own limits", (tester) async {
      var controller = CanvasController(const CanvasDocument(frames: 40));
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      var caption = find.descendant(
          of: find.byKey(const ValueKey("canvasFrameRate")),
          matching: find.text("Per second"));
      // Far past the bottom of a 1..60 field.
      await tester.drag(caption, const Offset(-4000, 0));
      await tester.pumpAndSettle();
      expect(controller.document.frameRate, 1);

      await tester.drag(caption, const Offset(8000, 0));
      await tester.pumpAndSettle();
      expect(controller.document.frameRate, 60);
    });

    testWidgets("where in the caption it is grabbed makes no difference",
        (tester) async {
      // The gesture reports the pointer's position within the widget rather
      // than how far it has travelled, so an unadjusted read moved the value
      // by wherever in the label it was taken hold of.
      Future<int> dragFromFraction(double at) async {
        var controller = CanvasController(const CanvasDocument(frames: 200));
        addTearDown(controller.dispose);
        await pump(tester, CanvasTimeline(controller: controller));

        var caption = find.descendant(
            of: find.byKey(const ValueKey("canvasFrames")),
            matching: find.text("Length"));
        var box = tester.getRect(caption);
        await tester.dragFrom(
            Offset(box.left + box.width * at, box.center.dy),
            const Offset(30, 0));
        await tester.pumpAndSettle();
        return controller.document.frames;
      }

      expect(await dragFromFraction(0.1), await dragFromFraction(0.9));
      expect(await dragFromFraction(0.5), 230);
    });

    testWidgets("typing into the field still works", (tester) async {
      // The scrub must not have taken the field over.
      var controller = CanvasController(const CanvasDocument(frames: 40));
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      await tester.enterText(
          find.byKey(const ValueKey("canvasFrames")), "125");
      await tester.pump();
      expect(controller.document.frames, 125);
    });
  });

  group("the image settings", () {
    Future<CanvasController> panel(
        WidgetTester tester, ImageElement image) async {
      var controller =
          CanvasController(const CanvasDocument().addElement(image));
      addTearDown(controller.dispose);
      controller.selectOnly(image.id);
      await pump(tester, CanvasLayersPanel(controller: controller));
      return controller;
    }

    ImageElement empty() =>
        const ImageElement(ElementBase(id: "i", width: 200, height: 200));
    ImageElement filled() => const ImageElement(
        ElementBase(id: "i", width: 200, height: 200),
        assetId: "abcdefghij123456");

    testWidgets("an empty one offers somewhere to put a picture",
        (tester) async {
      // The control the element did not have, and without which it does
      // nothing at all.
      await panel(tester, empty());
      expect(find.byTooltip("Add a picture"), findsOneWidget);
    });

    testWidgets("a filled one offers to replace or remove it", (tester) async {
      var controller = await panel(tester, filled());
      expect(find.byTooltip("Replace this picture"), findsOneWidget);

      await tester.tap(find.byTooltip("Take the picture out"));
      await tester.pumpAndSettle();
      expect((controller.document.elements.single as ImageElement).hasImage,
          isFalse);
    });

    testWidgets("frame, crop and look appear only once there is a picture",
        (tester) async {
      await panel(tester, empty());
      expect(find.text("FRAME"), findsNothing);
      expect(find.text("CROP"), findsNothing);
      expect(find.text("LOOK"), findsNothing);

      await panel(tester, filled());
      expect(find.text("FRAME"), findsOneWidget);
      expect(find.text("CROP"), findsOneWidget);
      expect(find.text("LOOK"), findsOneWidget);
    });

    testWidgets("the overlay colour appears only once a blend is chosen",
        (tester) async {
      // By key: several groups have a colour in them, and the border's is
      // always there.
      await panel(tester, filled());
      expect(find.byKey(const ValueKey("imageOverlayColour")), findsNothing);

      await panel(
          tester, filled().copyWith(blend: OverlayBlend.multiply));
      expect(
          find.byKey(const ValueKey("imageOverlayColour")), findsOneWidget);
    });

    testWidgets("a frame can be chosen and cleared", (tester) async {
      var controller = await panel(tester, filled());

      await tester.tap(find.text("Rectangle").first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(ShapeKind.circle.label).last);
      await tester.pumpAndSettle();
      expect((controller.document.elements.single as ImageElement).frame,
          ShapeKind.circle);
    });
  });

  group("element settings use numbers, not sliders", () {
    testWidgets("a fraction is typed and dragged like every other number",
        (tester) async {
      // A slider inside a settings row is a few dozen pixels wide, so the
      // whole of an opacity is about forty pixels of travel and nothing can be
      // set precisely. They are number fields now, which type and scrub.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasLayersPanel(controller: controller));

      expect(find.byType(Slider), findsNothing,
          reason: "no sliders left in an element's settings");

      var opacity = find.ancestor(
          of: find.text("Opacity"), matching: find.byType(CanvasNumberField));
      expect(opacity, findsOneWidget);

      await tester.enterText(
          find.descendant(of: opacity, matching: find.byType(TextField)), "0.4");
      await tester.pump();
      expect(controller.document.elements.single.opacity, closeTo(0.4, 0.001));
    });

    testWidgets("dragging its caption scrubs in hundredths", (tester) async {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasLayersPanel(controller: controller));

      await tester.drag(find.text("Opacity"), const Offset(-25, 0));
      await tester.pumpAndSettle();

      // Two decimals, so twenty-five pixels is a quarter.
      expect(controller.document.elements.single.opacity, closeTo(0.75, 0.02));
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
      await pump(tester, CanvasLayersPanel(controller: controller));
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

      await tester.enterText(field, "Goal area");
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
      await tester.enterText(field, "   ");
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
      await pump(tester, CanvasLayersPanel(controller: controller));
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
      var background = find.textContaining("Background");
      expect(background, findsOneWidget);

      expect(
          find.ancestor(
              of: background, matching: find.byType(LongPressDraggable<String>)),
          findsNothing);
      expect(find.ancestor(of: background, matching: find.byType(DragTarget<String>)),
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
    List<String> shown(WidgetTester tester) => tester
        .widgetList<CanvasHint>(find.byType(CanvasHint))
        .map((h) => h.message)
        .toList();

    testWidgets("the Add grid explains itself on a question mark",
        (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasElementsPanel(controller: controller));

      const hint = "Click to add one in the middle of the canvas, or drag it "
          "where you want it. What is already on the canvas is in the Layers "
          "tab.";
      expect(find.text(hint), findsNothing, reason: "not in the column");
      expect(shown(tester), contains(hint));

      // Tap as well as hover: a hint reachable only by hovering does not
      // exist on a touch screen.
      await tester.tap(find.byType(CanvasHint).first);
      await tester.pumpAndSettle();
      expect(find.text(hint), findsOneWidget);
    });

    testWidgets("so do the presets", (tester) async {
      await pump(tester, CanvasPresetsPanel(onChoose: (_, __) {}));

      expect(find.text("PRESETS"), findsOneWidget,
          reason: "a heading to hang the question mark off");
      expect(
          shown(tester),
          contains("Start from one of these, then change whatever you like "
              "and save your own copy."));
    });

    testWidgets("and the element settings, in the sidebar but not the band",
        (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);

      await pump(tester, CanvasLayersPanel(controller: controller));
      expect(find.text(elementSettingsHint), findsNothing);
      expect(shown(tester), contains(elementSettingsHint));

      // The band keeps the words. Its line is there whether anything is
      // selected or not, and an empty strip reads as broken.
      await pump(
          tester,
          CanvasSettingsBar(
            controller: controller,
            onPublish: () {},
            canvasSettingsOpen: false,
            onToggleCanvasSettings: () {},
          ));
      await tester.tap(find.byTooltip(
          "Element settings — the selected element's controls, on a second "
          "line"));
      await tester.pumpAndSettle();
      expect(find.text(elementSettingsHint), findsOneWidget);
    });
  });

  group("a layer row", () {
    Future<CanvasController> panel(WidgetTester tester) async {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      await pump(tester, CanvasLayersPanel(controller: controller));
      return controller;
    }

    testWidgets("duplicates rather than copying", (tester) async {
      // A copy did nothing anybody could see: the canvas was unchanged and the
      // only evidence was that a paste somewhere else would now produce this.
      var controller = await panel(tester);
      var original = controller.document.elements.single;

      expect(find.byTooltip("Copy"), findsNothing);
      await tester.tap(find.byTooltip("Duplicate"));
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

      await tester.tap(find.byTooltip("Duplicate"));
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
      await tester.tap(find.byTooltip("Lock"));
      await tester.pumpAndSettle();

      expect(controller.document.elements.single.locked, isTrue);
      expect(find.byIcon(Icons.lock), findsOneWidget,
          reason: "filled, not another outline");
      expect(find.byIcon(Icons.lock_open_outlined), findsNothing);

      await tester.tap(find.byTooltip("Unlock"));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.lock_open_outlined), findsOneWidget);
    });
  });

  group("the element settings section", () {
    Future<CanvasController> panel(WidgetTester tester, Widget Function(
            CanvasController) build) async {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      await pump(tester, build(controller));
      return controller;
    }

    testWidgets("is on the Design Elements tab as well as Layers",
        (tester) async {
      // The first thing anybody does after adding an element is change it, and
      // with the settings only on Layers that was a trip to another tab and
      // back for every element on a canvas.
      var controller = await panel(
          tester, (c) => CanvasElementsPanel(controller: c));

      expect(find.text("ADD"), findsOneWidget, reason: "still the add grid");
      expect(find.text("Element settings"), findsOneWidget);

      controller.selectOnly(controller.document.elements.single.id);
      await tester.pumpAndSettle();
      expect(find.text("Opacity"), findsOneWidget,
          reason: "and the selected element's controls under it");
    });

    for (var (name, build) in <(String, Widget Function(CanvasController))>[
      ("Design Elements", (c) => CanvasElementsPanel(controller: c)),
      ("Layers", (c) => CanvasLayersPanel(controller: c)),
    ]) {
      testWidgets("closed on the $name tab, it stays closed when something "
          "is selected", (tester) async {
        // The instruction that makes closing it worth doing. A section that
        // reopens because an element was clicked is a section that has to be
        // closed again after every click.
        var controller = await panel(tester, build);

        await tester.tap(find.text("Element settings"));
        await tester.pumpAndSettle();
        expect(find.text("Opacity"), findsNothing);

        controller.selectOnly(controller.document.elements.single.id);
        await tester.pumpAndSettle();
        expect(find.text("Opacity"), findsNothing,
            reason: "selecting does not reopen it");

        controller.addElement(newElement(ElementKind.text, controller.document));
        await tester.pumpAndSettle();
        expect(find.text("Opacity"), findsNothing,
            reason: "nor does adding one");

        // And the handle is still there, because a section with no way back is
        // a trap.
        await tester.tap(find.text("Element settings"));
        await tester.pumpAndSettle();
        expect(find.text("Opacity"), findsOneWidget);
      });
    }

    testWidgets("the two tabs remember separately", (tester) async {
      // Three sections, three keys -- the band's is the third. Somebody
      // working in the band wants the sidebar's copy shut so the layer list
      // has the room, which does not work if they share one switch.
      await panel(tester, (c) => CanvasElementsPanel(controller: c));
      var elements = tester
          .widget<CanvasSettingsSplit>(find.byType(CanvasSettingsSplit))
          .storageKey;

      await panel(tester, (c) => CanvasLayersPanel(controller: c));
      var layers = tester
          .widget<CanvasSettingsSplit>(find.byType(CanvasSettingsSplit))
          .storageKey;

      expect(elements, isNot(layers));
    });

    testWidgets("the height each tab gives the settings is its own",
        (tester) async {
      // A grid of ten chips is a fixed height and a layer list is not, so the
      // two do not want the same share -- and having dragged one there is no
      // reason to have moved the other.
      await panel(tester, (c) => CanvasElementsPanel(controller: c));
      var elements = tester
          .widget<CanvasSettingsSplit>(find.byType(CanvasSettingsSplit))
          .initialSplit;

      await panel(tester, (c) => CanvasLayersPanel(controller: c));
      var layers = tester
          .widget<CanvasSettingsSplit>(find.byType(CanvasSettingsSplit))
          .initialSplit;

      expect(elements, lessThan(layers),
          reason: "the add grid needs less room than the layer list");
    });
  });

  group("the chart settings", () {
    Future<CanvasController> panel(WidgetTester tester,
        {ChartElement Function(ChartElement)? shape}) async {
      var element = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        title: "Messages",
        description: "By week",
        data: ChartData.parse("Cat\tA\nx\t10\ny\t6"),
      );
      if (shape != null) element = shape(element);
      var controller =
          CanvasController(const CanvasDocument().addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("c");
      await pump(tester, CanvasLayersPanel(controller: controller));
      return controller;
    }

    ChartElement chartIn(CanvasController controller) =>
        controller.document.elements.single as ChartElement;

    /// press scrolls the settings to a control and taps it. A chart has more
    /// settings than fit in the panel, so most of them start off screen.
    Future<void> press(WidgetTester tester, Finder what) async {
      await tester.ensureVisible(what);
      await tester.pumpAndSettle();
      await tester.tap(what);
      await tester.pumpAndSettle();
    }

    /// labels opens the section the title, the description and the key are
    /// now gathered in. Closed to begin with, like the other sections.
    Future<void> labels(WidgetTester tester) async {
      if (find.text("TITLE").evaluate().isEmpty) {
        await press(tester, find.text("LABELS"));
      }
    }

    testWidgets("smooth is only offered where there is a line to curve",
        (tester) async {
      // Offered on a bar chart it was a switch that did nothing, which is
      // indistinguishable from a broken one.
      await panel(tester);
      expect(find.text("Smooth"), findsNothing);

      await panel(tester, shape: (e) => e.copyWith(type: ChartType.line));
      expect(find.text("Smooth"), findsOneWidget);
    });

    testWidgets("grouped bars say what they need", (tester) async {
      // They draw exactly what plain bars draw until there is a second series
      // to group, so choosing one on a one-series chart looks like the setting
      // doing nothing at all.
      var controller =
          await panel(tester, shape: (e) => e.copyWith(type: ChartType.bar));
      Iterable<String> hints() => tester
          .widgetList<CanvasHint>(find.byType(CanvasHint))
          .map((h) => h.message)
          .where((m) => m.contains("Grouped and stacked"));
      expect(hints(), isEmpty);

      controller.replaceElement(
          chartIn(controller).copyWith(type: ChartType.groupedBar));
      await tester.pumpAndSettle();
      expect(hints(), isNotEmpty);

      controller.replaceElement(chartIn(controller).copyWith(
          data: ChartData.parse("Cat\tA\tB\nx\t10\t5\ny\t6\t9")));
      await tester.pumpAndSettle();
      expect(hints(), isEmpty, reason: "with two series it has its answer");
    });

    testWidgets("the title and the description can be switched off",
        (tester) async {
      var controller = await panel(tester);
      await labels(tester);
      // The group's caption. The field under it has none of its own any more
      // -- "Title > Title" was the heading saying the word twice.
      expect(find.text("TITLE"), findsOneWidget);
      expect(find.text("DESCRIPTION"), findsOneWidget);
      expect(chartIn(controller).titleBox.show, isTrue);

      // Two "Show" toggles, one per label, so the title's is the first.
      await press(tester, find.text("Show").first);
      expect(chartIn(controller).titleBox.show, isFalse);
      expect(chartIn(controller).descriptionBox.show, isTrue,
          reason: "one switch each");
    });

    testWidgets("floating offers where each label goes", (tester) async {
      // There used to be a "place it yourself" button per label, which was a
      // second switch saying the same thing as "Over the chart": a label that
      // floats is one that sits where it is put.
      var controller = await panel(tester);
      await labels(tester);
      expect(chartIn(controller).floatingLabels, isFalse);
      // One X already: the element's own position, at the top of the panel.
      expect(find.text("X"), findsOneWidget);
      expect(find.byTooltip("Place it yourself — then drag it on the canvas"),
          findsNothing);

      await press(tester, find.text("Over the chart"));

      // And now one for the title and one for the description as well.
      expect(find.text("X"), findsNWidgets(3));
      expect(find.text("H"), findsNWidgets(3));
    });

    testWidgets("switching it off keeps where they were put", (tester) async {
      // The switch goes both ways without losing anything: off puts the chart
      // back exactly as it was, and on again finds the labels where they were
      // dragged rather than back at their defaults.
      var controller = await panel(tester);
      await labels(tester);
      await press(tester, find.text("Over the chart"));

      controller.replaceElement(chartIn(controller).copyWith(
          titleBox: const ChartLabel(
              x: 0.4, y: 0.5, width: 0.3, height: 0.12)));
      await tester.pumpAndSettle();

      // And the box goes back round the chart, rather than staying as big as
      // the labels made it while they were floating.
      controller.replaceElement(chartIn(controller).copyWith(
          body: const ChartBody(x: 0.1, y: 0.1, width: 0.9, height: 0.9)));
      await tester.pumpAndSettle();

      await press(tester, find.text("Over the chart"));
      expect(chartIn(controller).floatingLabels, isFalse);
      expect(chartIn(controller).body.isWhole, isTrue,
          reason: "the chart fills its element again");
      expect(chartIn(controller).titleBox.x, 0.4,
          reason: "kept, not thrown away");

      await press(tester, find.text("Over the chart"));
      expect(chartIn(controller).titleBox.x, 0.4);
    });

    testWidgets("a pie is offered no axes, but still its values",
        (tester) async {
      // The switches are all the same question -- what does this chart write
      // on itself -- so they are one group, and a pie keeps the half of it
      // that applies.
      await panel(tester);
      expect(find.text("AXES AND VALUES"), findsOneWidget);
      expect(find.text("X label"), findsOneWidget);
      // "Grid" twice over: the switch here and the colour in Style, so it is
      // found by the control it belongs to rather than by its word.
      Finder toggle(String label) => find.ancestor(
          of: find.text(label), matching: find.byType(CanvasToggle));
      expect(toggle("Grid"), findsOneWidget);
      expect(find.text("Axes labels"), findsOneWidget);
      expect(toggle("Values"), findsOneWidget);

      await panel(tester, shape: (e) => e.copyWith(type: ChartType.pie));
      expect(find.text("AXES AND VALUES"), findsOneWidget);
      expect(find.text("X label"), findsNothing);
      expect(toggle("Grid"), findsNothing);
      expect(find.text("Axes labels"), findsNothing);
      expect(toggle("Values"), findsOneWidget);
    });

    testWidgets("the axes labels can be switched off", (tester) async {
      var controller = await panel(tester);
      expect(chartIn(controller).showAxisLabels, isTrue);

      await press(tester, find.text("Axes labels"));
      expect(chartIn(controller).showAxisLabels, isFalse);
    });

    testWidgets("a radial bar says where its numbers went", (tester) async {
      // Rings a few pixels thick have nowhere to write a number and no axis to
      // read one against, so theirs go in the legend -- which is no use with
      // the legend switched off.
      const hint = "A radial bar has no room to write a number on and no axis "
          "to read one against, so its values go in the legend. Switch the "
          "legend on, and its values with it, to see them.";
      Iterable<String> hints() => tester
          .widgetList<CanvasHint>(find.byType(CanvasHint))
          .map((h) => h.message);

      await panel(
          tester,
          shape: (e) =>
              e.copyWith(type: ChartType.radialBar, showLegend: false));
      expect(hints(), contains(hint));

      // The legend on but its own values off is still nowhere for them to go:
      // the two switches are separate now.
      await panel(
          tester,
          shape: (e) =>
              e.copyWith(type: ChartType.radialBar, showLegend: true));
      expect(hints(), contains(hint));

      await panel(
          tester,
          shape: (e) => e.copyWith(
              type: ChartType.radialBar,
              showLegend: true,
              legend: const ChartLegend(values: true)));
      expect(hints(), isNot(contains(hint)),
          reason: "with both on, the numbers are where it says");
    });

    testWidgets("one switch decides whether the labels take room",
        (tester) async {
      // The three of them together, because taking room is what made every
      // one of their settings a setting that resized the chart.
      var controller = await panel(tester);
      await labels(tester);
      expect(chartIn(controller).floatingLabels, isFalse,
          reason: "stacked above the plot is what a chart looks like");

      await press(tester, find.text("Over the chart"));
      expect(chartIn(controller).floatingLabels, isTrue);
    });

    testWidgets("a section remembers whether it was open", (tester) async {
      // The panel is rebuilt from scratch whenever the selection changes, so
      // a section opened, deselected and selected again used to be shut --
      // the stored answer arrives asynchronously and the default is what
      // anybody saw.
      var controller = await panel(tester);
      await labels(tester);
      expect(find.text("TITLE"), findsOneWidget);

      controller.clearSelection();
      await tester.pumpAndSettle();
      expect(find.text("TITLE"), findsNothing);

      controller.selectOnly("c");
      await tester.pumpAndSettle();
      expect(find.text("TITLE"), findsOneWidget,
          reason: "still open, without waiting for a preference to load");
    });

    testWidgets("a closed section still fills the column", (tester) async {
      // The settings are a Column of start-aligned children, so a box left to
      // size itself shrank to fit its own heading -- and a closed section
      // narrower than the one above it does not read as a section, it reads
      // as a button somebody has left lying there.
      await panel(tester);

      var panelWidth = tester.getSize(find.byType(CanvasLayersPanel)).width;
      for (var name in ["LABELS", "DATA", "ANIMATION"]) {
        var heading = find.text(name);
        await tester.ensureVisible(heading);
        await tester.pumpAndSettle();
        // The box around the section, which is the widest thing in it.
        var box = tester.getSize(find.ancestor(
                of: heading,
                matching: find.byWidgetPredicate(
                    (w) => w is Container && w.decoration is BoxDecoration))
            .first);
        expect(box.width, greaterThan(panelWidth * 0.8), reason: name);
      }
    });

    testWidgets("the legend is in with the other words on the chart",
        (tester) async {
      // The title, the description and the key are the same kind of thing --
      // writing laid over a picture -- and were three clusters and an
      // expander scattered down the panel with the data between them.
      var controller = await panel(tester);
      await labels(tester);

      expect(find.text("TITLE"), findsOneWidget);
      expect(find.text("DESCRIPTION"), findsOneWidget);
      expect(find.text("LEGEND"), findsOneWidget);
      expect(find.text("Place"), findsNothing, reason: "the key is off");

      await press(tester, find.text("Show").last);
      expect(chartIn(controller).showLegend, isTrue);
      expect(find.text("Place"), findsOneWidget);
      expect(find.text("Along"), findsOneWidget);
      expect(find.byType(CanvasDropdown<LegendPlacement>), findsOneWidget);
      expect(find.text("Between"), findsNothing,
          reason: "nothing to separate until the key shows values");

      // Two "Values" on the panel now: the chart's own, up in Axes and
      // values, and the key's down here. The key's is the later of the two.
      await press(tester, find.text("Values").last);
      expect(chartIn(controller).legend.values, isTrue);
      expect(find.text("Between"), findsOneWidget);
    });

    testWidgets("the title and the description size separately",
        (tester) async {
      // The description took the label size, which is also the tick labels'
      // -- so making the description bigger made the numbers up the side of
      // the chart bigger with it.
      var controller = await panel(tester);
      await labels(tester);
      var before = chartIn(controller).labelSpec.fontSize;

      // Two "Size" fields, the title's first.
      var sizes = find.ancestor(
          of: find.text("Size"), matching: find.byType(CanvasNumberField));
      expect(sizes, findsNWidgets(2));

      await tester.enterText(
          find.descendant(of: sizes.at(1), matching: find.byType(TextField)),
          "44");
      await tester.pump();

      var after = chartIn(controller);
      expect(after.descriptionText.fontSize, 44);
      expect(after.labelSpec.fontSize, before,
          reason: "and the axis labels are where they were");
    });

    testWidgets("a series is added beside the data, not in a section of its "
        "own", (tester) async {
      // A series is a column of the table, so it is added where the table is
      // and its name, colour and type sit under the table rather than three
      // headings away.
      var controller = await panel(tester);
      expect(chartIn(controller).data.series.length, 1);
      expect(find.text("SERIES"), findsNothing);

      await press(
          tester,
          find.byTooltip("Add a series — give it its own type below to lay "
              "one kind of chart over another"));

      var data = chartIn(controller).data;
      expect(data.series.length, 2);
      expect(data.series[1].type, isNull, reason: "following the chart");
      expect(data.series[1].values.length, data.categories.length,
          reason: "a value per row, so it lines up with what is there");

      // Two "Drawn as" dropdowns now, one per series, under the table.
      expect(find.byType(CanvasDropdown<String>), findsNWidgets(2));
    });
  });

  group("the settings' layout", () {
    // Six clusters of small controls down one narrow column, separated by nine
    // pixels of nothing, ran together into one field of boxes: the caption
    // over each was the only thing saying where one ended, and a caption is
    // nine pixels tall and grey.

    testWidgets("a group is ruled off from the next", (tester) async {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasLayersPanel(controller: controller));

      expect(find.byType(CanvasControlGroup), findsWidgets);
      // One rule per group, drawn under it.
      var rules = find.descendant(
          of: find.byType(CanvasControlGroup),
          matching: find.byWidgetPredicate((w) =>
              w is Container &&
              w.constraints?.maxHeight == 1.0));
      expect(rules, findsWidgets);
    });

    testWidgets("where it is and how it is turned are two lines",
        (tester) async {
      // Left to the Wrap, the line fell between W and H or after Angle
      // depending on how wide the sidebar happened to be.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasLayersPanel(controller: controller));

      expect(find.byType(CanvasLineBreak), findsWidgets);
      var x = tester.getRect(find.byKey(const ValueKey("elementX")));
      var angle = tester.getRect(find.byKey(const ValueKey("elementAngle")));
      expect(angle.top, greaterThan(x.bottom - 2),
          reason: "Angle starts a line of its own, under X");
    });

    testWidgets("the element's own name is not said twice", (tester) async {
      // The settings are headed with it already, so the group caption under
      // that heading said "Chart" directly under "Chart".
      var document = const CanvasDocument();
      var element = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        data: ChartData.parse("Cat\tA\nx\t10"),
      );
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("c");
      await pump(tester, CanvasLayersPanel(controller: controller));

      // Once: the settings' own heading. The position group's caption was a
      // second one directly under it.
      expect(find.text("CHART"), findsOneWidget);
      expect(find.text("Chart"), findsOneWidget,
          reason: "and the layer row that names it, which is not the same "
              "thing");
    });
  });

  group("a chart's animation", () {
    /// openAnimation opens the section if it is not already open.
    ///
    /// Whether a section is open is remembered for the session, deliberately
    /// -- somebody who opens the animation settings is working on animation
    /// -- so a test cannot assume it starts closed and cannot simply tap the
    /// heading, which would shut one a previous test left open.
    Future<void> openAnimation(WidgetTester tester) async {
      if (find.text("PRESET").evaluate().isNotEmpty) return;
      var heading = find.text("ANIMATION");
      await tester.ensureVisible(heading);
      await tester.pumpAndSettle();
      await tester.tap(heading);
      await tester.pumpAndSettle();
    }

    (CanvasController, ChartElement) build({int frames = 1}) {
      var document = CanvasDocument(frames: frames);
      var chart = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        data: ChartData.parse("Cat\tA\nx\t10\ny\t6"),
      );
      var controller = CanvasController(document.addElement(chart));
      return (controller, chart);
    }

    ChartElement chartIn(CanvasController controller) =>
        controller.document.elements.single as ChartElement;

    test("choosing a preset lays a keyframe at each end of it", () {
      // One gesture, because it is one decision. A preset with nothing
      // pinning the reveal channel draws exactly what a still chart draws, so
      // applying it separately from keying it would be asking somebody to
      // know how this is implemented.
      var (controller, chart) = build(frames: 24);
      addTearDown(controller.dispose);

      controller.applyChartAnimation(chart, ChartAnimationPreset.grow);

      var after = chartIn(controller);
      expect(after.animation.preset, ChartAnimationPreset.grow);

      var keys = after.track!.keys;
      expect(keys.length, 2);
      expect(keys.first.values[KeyframeChannel.reveal], 0);
      expect(keys.last.values[KeyframeChannel.reveal], 1);
      expect(keys.last.frame, greaterThan(keys.first.frame),
          reason: "the gap between them is the length of the animation");
    });

    test("a still document is given frames to play it in", () {
      // An animation on a one-frame canvas is an animation nobody can watch.
      var (controller, chart) = build();
      addTearDown(controller.dispose);
      expect(controller.document.isAnimated, isFalse);

      controller.applyChartAnimation(chart, ChartAnimationPreset.wipe);

      expect(controller.document.isAnimated, isTrue);
      expect(chartIn(controller).track!.keys.length, 2);
    });

    test("it starts from where the reader is looking", () {
      var (controller, chart) = build(frames: 60);
      addTearDown(controller.dispose);
      controller.frame = 20;

      controller.applyChartAnimation(chart, ChartAnimationPreset.grow);

      expect(chartIn(controller).track!.keys.first.frame, 20,
          reason: "rather than jumping the playhead back to the start");
    });

    test("choosing None takes the keyframes away with it", () {
      var (controller, chart) = build(frames: 24);
      addTearDown(controller.dispose);
      controller.applyChartAnimation(chart, ChartAnimationPreset.grow);
      expect(chartIn(controller).track, isNotNull);

      controller.applyChartAnimation(
          chartIn(controller), ChartAnimationPreset.none);

      expect(chartIn(controller).animation.on, isFalse);
      expect(chartIn(controller).track, isNull,
          reason: "no animation left, so no empty track in the saved file");
    });

    test("it is one undo step", () {
      var (controller, chart) = build(frames: 24);
      addTearDown(controller.dispose);
      controller.applyChartAnimation(chart, ChartAnimationPreset.grow);

      controller.undo();
      var back = controller.document.elements.single as ChartElement;
      expect(back.animation.on, isFalse);
      expect(back.track, isNull);
    });

    testWidgets("the presets offered suit the chart", (tester) async {
      // A sweep round a bar chart is a sweep round a rectangle, and a wipe
      // across a pie is worse.
      var (controller, _) = build(frames: 24);
      addTearDown(controller.dispose);
      controller.selectOnly("c");
      await pump(tester, CanvasLayersPanel(controller: controller));

      await openAnimation(tester);

      expect(find.text("Grow"), findsOneWidget);
      expect(find.text("Wipe across"), findsOneWidget);
      expect(find.text("Sweep round"), findsNothing,
          reason: "not on a bar chart");

      controller.replaceElement(
          (controller.document.elements.single as ChartElement)
              .copyWith(type: ChartType.pie));
      await tester.pumpAndSettle();
      expect(find.text("Sweep round"), findsOneWidget);
      expect(find.text("Wipe across"), findsNothing,
          reason: "nor a wipe across a circle");
    });

    testWidgets("the gap is only offered where there is something to space",
        (tester) async {
      var (controller, chart) = build(frames: 24);
      addTearDown(controller.dispose);
      controller.selectOnly("c");
      await pump(tester, CanvasLayersPanel(controller: controller));

      await openAnimation(tester);
      expect(find.text("Gap"), findsNothing, reason: "no preset yet");

      controller.applyChartAnimation(chart, ChartAnimationPreset.grow);
      await tester.pumpAndSettle();
      expect(find.text("Gap"), findsOneWidget);
      expect(find.text("End curve"), findsOneWidget);

      controller.applyChartAnimation(
          chartIn(controller), ChartAnimationPreset.wipe);
      await tester.pumpAndSettle();
      expect(find.text("Gap"), findsNothing,
          reason: "one edge crossing everything has nothing to space out");
      expect(find.text("End curve"), findsOneWidget);
    });
  });

  group("the chart's numbers", () {
    Future<CanvasController> panel(WidgetTester tester) async {
      var element = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        data: ChartData.parse("Cat\tA\nx\t10\ny\t6"),
      );
      var controller =
          CanvasController(const CanvasDocument().addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("c");
      await pump(tester, CanvasLayersPanel(controller: controller));
      return controller;
    }

    ChartData dataIn(CanvasController controller) =>
        (controller.document.elements.single as ChartElement).data;

    Future<void> press(WidgetTester tester, Finder what) async {
      await tester.ensureVisible(what);
      await tester.pumpAndSettle();
      await tester.tap(what);
      await tester.pumpAndSettle();
    }

    /// grid switches to the table, if it is not already showing one.
    ///
    /// Which view the editor is in is remembered for the session, deliberately
    /// -- somebody who works in the grid works in the grid, whatever chart
    /// they open next -- so a test cannot assume it starts in the text one.
    Future<void> grid(WidgetTester tester) async {
      var toTable = find.byTooltip("Edit the numbers in a table");
      if (toTable.evaluate().isNotEmpty) await press(tester, toTable);
    }

    testWidgets("the numbers are a section of their own", (tester) async {
      // They are the longest thing in a chart's settings and the least often
      // changed once they are right, so they were pushing everything else off
      // the bottom of the panel.
      await panel(tester);
      expect(find.text("DATA"), findsOneWidget);
      expect(find.text("2 rows, 1 series"), findsOneWidget);
    });

    testWidgets("it switches between pasted text and a table", (tester) async {
      // Pasted text is the fast way in; it is a bad way to change one number
      // in the middle of forty, which is the other thing people do all day.
      var controller = await panel(tester);
      expect(find.byType(ChartDataEditor), findsOneWidget);
      expect(find.byTooltip("Add a row"), findsOneWidget,
          reason: "rows and series are added the same way in either view");

      await grid(tester);
      expect(find.byTooltip("Edit the numbers as pasted text"), findsOneWidget);

      // The first row's category, then its value.
      await tester.enterText(
          find.descendant(
              of: find.byType(ChartDataEditor),
              matching: find.byType(TextField)).at(2),
          "42");
      await tester.pumpAndSettle();
      expect(dataIn(controller).valueAt(0, 0), 42);
    });

    testWidgets("a row can be added and taken away", (tester) async {
      var controller = await panel(tester);
      await grid(tester);

      await press(tester, find.byTooltip("Add a row"));
      expect(dataIn(controller).categories.length, 3);

      await press(tester, find.byTooltip("Remove this row").first);
      expect(dataIn(controller).categories.length, 2);
      expect(dataIn(controller).series.single.values.length, 2,
          reason: "the series loses the row too, or the data goes ragged");
    });
  });

  group("the outline settings", () {
    Future<CanvasController> panel(WidgetTester tester,
        {ImageOutline outline = const ImageOutline(),
        String assetId = "abcdefghijklmnop"}) async {
      var element = ImageElement(
        const ElementBase(id: "i", width: 200, height: 200),
        assetId: assetId,
        outline: outline,
      );
      var controller =
          CanvasController(const CanvasDocument().addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("i");
      await pump(tester, CanvasLayersPanel(controller: controller));
      return controller;
    }

    testWidgets("the width is the only control until there is a width",
        (tester) async {
      // The width is also the off switch, so everything else is noise while
      // it is zero -- and a colour and a style sitting there doing nothing is
      // how a reader concludes the feature is broken.
      await panel(tester);

      expect(find.text("Width"), findsOneWidget);
      expect(find.byKey(const ValueKey("imageOutlineColour")), findsNothing);
      expect(find.text("Feather"), findsNothing);
    });

    testWidgets("with a width, it offers a colour, a style and a feather",
        (tester) async {
      await panel(tester, outline: const ImageOutline(width: 4));

      expect(find.byKey(const ValueKey("imageOutlineColour")), findsOneWidget);
      expect(find.text("Feather"), findsOneWidget);
      expect(find.byType(CanvasDropdown<OutlineStyle>), findsOneWidget);
    });

    testWidgets("typing a width turns it on", (tester) async {
      var controller = await panel(tester);
      var width = find.ancestor(
          of: find.text("Width"), matching: find.byType(CanvasNumberField));

      await tester.enterText(
          find.descendant(of: width, matching: find.byType(TextField)), "6");
      await tester.pump();

      var element = controller.document.elements.single as ImageElement;
      expect(element.outline.width, 6);
      expect(element.outline.on, isTrue);
    });

    testWidgets("a picture's size can be changed after it is already in",
        (tester) async {
      // The width, quality and format controls are offered on the way in, and
      // only above half a megabyte, so a reader who wanted them for a smaller
      // picture -- or who took a size on the way in and thought better of it
      // -- had nowhere to go.
      const tooltip = "Change this picture's size and quality";
      await panel(tester);
      expect(find.byTooltip(tooltip), findsOneWidget);

      await panel(tester, assetId: "");
      expect(find.byTooltip(tooltip), findsNothing,
          reason: "nothing to resize until there is a picture");
    });

    testWidgets("there is nothing to outline without a picture",
        (tester) async {
      await panel(tester, assetId: "");
      expect(find.text("Width"), findsNothing);
    });
  });

  group("the remove-background settings", () {
    Future<CanvasController> panel(WidgetTester tester,
        {BackgroundRemoval removal = const BackgroundRemoval()}) async {
      var element = ImageElement(
        const ElementBase(id: "i", width: 200, height: 200),
        assetId: "abcdefghijklmnop",
        removal: removal,
      );
      var controller =
          CanvasController(const CanvasDocument().addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("i");
      await pump(tester, CanvasLayersPanel(controller: controller));
      return controller;
    }

    testWidgets("the brushes are there on a picture nothing has been done to",
        (tester) async {
      // They were inside "if anything is being removed", which made them
      // unreachable on exactly the picture they are for: a fresh image has no
      // method and no strokes, so nothing was being removed, so the brushes
      // were hidden -- and the only way to reach the tool that needs no method
      // was to choose a method first.
      await panel(tester);

      expect(find.byTooltip("Rub the background out by hand"), findsOneWidget);
      expect(find.byTooltip("Put back what was taken by mistake"),
          findsOneWidget);
    });

    testWidgets("turning a brush on offers its size, hardness and cling",
        (tester) async {
      var controller = await panel(tester);
      expect(find.text("Brush"), findsNothing,
          reason: "not until there is a brush in hand");

      controller.retouch = RetouchBrush.erase;
      await tester.pumpAndSettle();

      expect(find.text("Brush"), findsOneWidget);
      expect(find.text("Hardness"), findsOneWidget);
      expect(find.text("Cling"), findsOneWidget);
    });

    testWidgets("the cut offers to take the other side of the line",
        (tester) async {
      var controller = await panel(tester);
      const outward = "Taking what is outside the line — press to take what "
          "is inside";
      const inward = "Taking what is inside the line — press to take what "
          "is outside";


      expect(find.byTooltip(outward), findsNothing,
          reason: "only the cut has two sides to choose between");

      controller.retouch = RetouchBrush.cutAround;
      await tester.pumpAndSettle();

      expect(find.byTooltip(outward), findsOneWidget);
      expect(find.byTooltip("Cling"), findsNothing);

      await tester.tap(find.byTooltip(outward));
      await tester.pumpAndSettle();

      expect(controller.cutInside, isTrue);
      expect(find.byTooltip(inward), findsOneWidget);
    });

    testWidgets("a marking brush offers neither hardness nor cling",
        (tester) async {
      // A hint is a sample rather than a mark on the picture, so it is taken
      // exactly where it was drawn.
      var controller =
          await panel(tester, removal: const BackgroundRemoval(
              mode: RemovalMode.learn));
      controller.retouch = RetouchBrush.markBackground;
      await tester.pumpAndSettle();

      expect(find.text("Brush"), findsOneWidget);
      expect(find.text("Hardness"), findsNothing);
      expect(find.text("Cling"), findsNothing);
    });

    testWidgets("the marking brushes appear with the method that uses them",
        (tester) async {
      await panel(tester);
      expect(find.byTooltip("Mark some background — draw over a few parts "
          "that should go"), findsNothing);

      await panel(tester,
          removal: const BackgroundRemoval(mode: RemovalMode.learn));
      expect(find.byTooltip("Mark some background — draw over a few parts "
          "that should go"), findsOneWidget);
      expect(find.byTooltip("Mark the subject — draw over a few parts that "
          "should stay"), findsOneWidget);
    });

    testWidgets("undo and clear appear once something has been painted",
        (tester) async {
      await panel(tester);
      expect(find.byTooltip("Undo the last brush stroke"), findsNothing);

      await panel(tester,
          removal: const BackgroundRemoval(strokes: [
            RemovalStroke(
                points: [Offset(0.5, 0.5)], radius: 0.1, keep: false),
          ]));
      expect(find.byTooltip("Undo the last brush stroke"), findsOneWidget);
      expect(find.byTooltip("Clear every brush stroke"), findsOneWidget);
    });

    testWidgets("a picture worked on by hand is offered no method settings",
        (tester) async {
      // They were shown whenever anything was being removed, which includes a
      // picture the brush alone has been used on -- so somebody working by
      // hand was offered a tolerance and a softness that nothing reads.
      await panel(tester,
          removal: const BackgroundRemoval(strokes: [
            RemovalStroke(
                points: [Offset(0.5, 0.5)], radius: 0.1, keep: false),
          ]));

      expect(find.text("Softness"), findsNothing);
      expect(find.text("Tolerance"), findsNothing);
      expect(find.text("Spread"), findsNothing);
      expect(find.text("Invert"), findsNothing);
      // The brush's own are still there.
      expect(find.byTooltip("Undo the last brush stroke"), findsOneWidget);
    });

    testWidgets("the brightness method is offered no tolerance",
        (tester) async {
      // It cuts at a threshold and never reads one.
      await panel(tester,
          removal: const BackgroundRemoval(mode: RemovalMode.luminance));
      expect(find.text("Threshold"), findsOneWidget);
      expect(find.text("Tolerance"), findsNothing);
      expect(find.text("Softness"), findsOneWidget);
    });

    testWidgets("a method's own settings stay behind the method",
        (tester) async {
      await panel(tester);
      expect(find.text("Edge"), findsNothing);
      expect(find.text("Spread"), findsNothing);

      await panel(tester,
          removal: const BackgroundRemoval(mode: RemovalMode.cornerFlood));
      expect(find.text("Edge"), findsOneWidget);
      expect(find.text("Spread"), findsOneWidget);
    });
  });
}
