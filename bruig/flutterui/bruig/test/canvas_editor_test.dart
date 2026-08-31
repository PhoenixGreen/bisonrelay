import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/canvas_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/presets/builtin_presets.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_settings_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/elements_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/canvas_sidebar.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/layers_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
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

    testWidgets("steps the playhead", (tester) async {
      var controller = CanvasController(const CanvasDocument(frames: 10));
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      // A fraction rather than a sentence: it is read at a glance while
      // scrubbing.
      expect(find.text("1/10"), findsOneWidget);
      await tester.tap(find.byTooltip("Next frame"));
      await tester.pumpAndSettle();
      expect(controller.frame, 1);
      expect(find.text("2/10"), findsOneWidget);

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
}
