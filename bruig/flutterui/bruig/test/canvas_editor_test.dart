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
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_settings_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/elements_panel.dart';
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

    testWidgets("carries no element or background settings", (tester) async {
      // They are in the Layers sidebar, and only there. Two places to change
      // the same thing meant neither was the obvious one, and the band's copy
      // could only show a few controls at a time along a line that had to be
      // scrolled sideways.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.text, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);

      await pump(tester, bar(controller));
      expect(find.text("TEXT"), findsNothing);
      expect(find.byTooltip("Try the next variation"), findsNothing);
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

      await tester.tap(find.byTooltip("Width and height move together"));
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
