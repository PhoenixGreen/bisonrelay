import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_settings_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/scenes_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_scenes_panel_test.dart is the list of canvases in the sidebar.
//
// Model tests can say a document holds three scenes. What they cannot say is
// that pressing New scene makes one, that the row you press is the canvas you
// end up editing, or that the master scene cannot be deleted -- and those are
// the things somebody actually does with this panel.

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<CanvasController> panel(WidgetTester tester,
      {CanvasDocument? document}) async {
    var controller = CanvasController(document ?? const CanvasDocument());
    addTearDown(controller.dispose);

    tester.view.physicalSize = const Size(400, 900);
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
          // A height, the way the panel stack gives one. Left unbounded, a
          // list that is too long for its panel cannot overflow it -- which
          // is exactly the thing that needs catching.
          body: SizedBox(
              width: 300,
              height: 420,
              child: CanvasScenesPanel(controller: controller)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets("a new document is one scene, and says so", (tester) async {
    var controller = await panel(tester);
    expect(controller.document.allScenes.length, 1);
    expect(find.text("Scene 1"), findsOneWidget);
    expect(find.text("Master scene"), findsOneWidget,
        reason: "pinned above the list, whether or not it is on");
  });

  testWidgets("New scene makes one and goes to it", (tester) async {
    var controller = await panel(tester);
    await tester.tap(find.text("New scene"));
    await tester.pumpAndSettle();

    expect(controller.document.allScenes.length, 2);
    expect(controller.document.at, 1, reason: "the one just made");
    expect(find.text("Scene 2"), findsOneWidget);
  });

  testWidgets("pressing a scene is how you get to it", (tester) async {
    var controller = await panel(tester, document: const CanvasDocument());
    await tester.tap(find.text("New scene"));
    await tester.pumpAndSettle();
    expect(controller.document.at, 1);

    await tester.tap(find.text("Scene 1"));
    await tester.pumpAndSettle();
    expect(controller.document.at, 0);
  });

  testWidgets("an edit lands on the scene being shown", (tester) async {
    // Which is the whole point of the list: the canvas you are on is the one
    // the rest of the editor is editing.
    var controller = await panel(tester);
    await tester.tap(find.text("New scene"));
    await tester.pumpAndSettle();

    controller.addElement(
        ShapeElement(const ElementBase(id: "s", width: 10, height: 10)));
    expect(controller.document.elements.length, 1);
    expect(controller.document.allScenes.first.elements, isEmpty,
        reason: "the scene that was not being shown");
  });

  testWidgets("the master scene is switched on by asking to edit it",
      (tester) async {
    var controller = await panel(tester);
    expect(controller.document.masterOn, isFalse, reason: "off by default");

    await tester.tap(find.text("Master scene"));
    await tester.pumpAndSettle();
    expect(controller.document.masterOn, isTrue);
    expect(controller.document.editingMaster, isTrue);

    // And what is added now goes on the shared canvas, not on a scene.
    controller.addElement(
        ShapeElement(const ElementBase(id: "logo", width: 10, height: 10)));
    expect(controller.document.master!.elements.single.id, "logo");
    expect(controller.document.allScenes.first.elements, isEmpty);
  });

  testWidgets("and it cannot be deleted, moved or renamed", (tester) async {
    var controller = await panel(tester, document: const CanvasDocument());
    await tester.tap(find.text("Master scene"));
    await tester.pumpAndSettle();

    // The row has a switch and nothing else: no menu, so nothing to delete
    // or rename it with, and it is not a Draggable so it cannot be moved.
    var master = find.ancestor(
        of: find.text("Master scene"), matching: find.byType(InkWell));
    expect(
        find.descendant(
            of: master.first,
            matching: find.byType(LongPressDraggable<String>)),
        findsNothing);
    expect(controller.document.allScenes.length, 1,
        reason: "it is not one of the scenes");
  });

  testWidgets("the list can show a picture of each scene", (tester) async {
    var controller = await panel(tester, document: const CanvasDocument());
    await tester.tap(find.text("New scene"));
    await tester.pumpAndSettle();
    expect(controller.document.allScenes.length, 2);

    // Drawn by the renderer rather than kept as pictures, so a preview cannot
    // be out of date.
    expect(find.byType(CustomPaint).evaluate().length, greaterThan(0));
    await tester.tap(find.byTooltip("Show a picture of each scene"));
    await tester.pumpAndSettle();
    expect(find.byTooltip("Show a plain list"), findsOneWidget);
  });

  testWidgets("the menu opens under the button that was pressed",
      (tester) async {
    // Placed from the panel rather than from the button, it appeared beside
    // the panel -- which for a row half way down a list is nowhere near what
    // was pressed.
    // Enough of them that the bottom of the list is a long way from the
    // middle of the panel, which is where the menu used to appear.
    var controller = await panel(tester,
        document: const CanvasDocument().withScenes([
          for (var i = 0; i < 8; i++) CanvasScene(id: "s$i"),
        ]));
    expect(controller.document.allScenes.length, 8);

    var buttons = find.byTooltip("What can be done with this scene");
    expect(buttons, findsNWidgets(8));

    // The first row's button, which is a long way from the middle of the
    // panel -- where the menu used to appear whichever row was pressed.
    var at = tester.getRect(buttons.first);
    await tester.tap(buttons.first);
    await tester.pumpAndSettle();

    // Under it, which is where a menu opens from a button, rather than
    // somewhere else down the column.
    var menu = tester.getRect(find.text("Duplicate"));
    expect(menu.top - at.top, greaterThan(0));
    expect(menu.top - at.top, lessThan(90),
        reason: "the menu belongs to its button: button at ${at.top}, menu at "
            "${menu.top}");
  });

  testWidgets("a long list scrolls rather than overflowing its panel",
      (tester) async {
    // The panel is given a height by the stack it sits in, and a dozen
    // scenes -- or three with their pictures drawn -- is taller than that.
    await panel(tester,
        document: const CanvasDocument().withScenes([
          for (var i = 0; i < 14; i++) CanvasScene(id: "s$i"),
        ]));

    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsWidgets);

    // And the master row is the top of the list rather than something the
    // scrolling pushes away.
    expect(find.text("Master scene"), findsOneWidget);
  });

  testWidgets("the things that act on the list are above it", (tester) async {
    // A control that acts on a list belongs at the top of it, where it is
    // found without reading to the end.
    await panel(tester,
        document: const CanvasDocument().withScenes([
          for (var i = 0; i < 4; i++) CanvasScene(id: "s$i"),
        ]));

    var newScene = tester.getRect(find.text("New scene"));
    var firstRow = tester.getRect(find.text("Scene 1"));
    expect(newScene.top, lessThan(firstRow.top));

    // And Duplicate is not offered twice: every row's menu has it, and a
    // button that copies whichever scene you happen to be on is a button
    // whose meaning depends on something else in the panel.
    expect(find.byTooltip("Duplicate this scene"), findsNothing);
  });

  testWidgets("a scene that holds says so in the list", (tester) async {
    var controller = await panel(tester,
        document: const CanvasDocument().withScenes([
          const CanvasScene(id: "a", holds: true),
          const CanvasScene(id: "b"),
        ]));
    expect(controller.document.allScenes.first.holds, isTrue);
    expect(find.byTooltip("Playback stops at the end of this scene"),
        findsOneWidget);
  });

  testWidgets("the bar counts the scenes, and only when there are some",
      (tester) async {
    // A counter reading 1/1 and two dead arrows are three controls for a
    // thing that does not exist yet.
    var controller = CanvasController(const CanvasDocument());
    addTearDown(controller.dispose);

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Future<void> pumpBar() => tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeNotifier>(
                create: (c) => ThemeNotifier(doLoad: false)),
            ChangeNotifierProvider<SnackBarModel>(
                create: (c) => SnackBarModel()),
            ChangeNotifierProvider<CanvasPreferences>(
                create: (c) => CanvasPreferences()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: CanvasSettingsBar(
                controller: controller,
                onPublish: () {},
                canvasSettingsOpen: false,
                onToggleCanvasSettings: () {},
                guidesOpen: false,
                onToggleGuides: () {},
                timelineOpen: false,
                onToggleTimeline: () {},
              ),
            ),
          ),
        ));

    await pumpBar();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("sceneField")), findsNothing);

    controller.addScene();
    controller.addScene();
    await tester.pumpAndSettle();
    expect(find.text("3/3"), findsOneWidget);

    await tester.tap(find.byTooltip("The scene before this one"));
    await tester.pumpAndSettle();
    expect(controller.document.at, 1);
    expect(find.text("2/3"), findsOneWidget);

    // And it says what it is showing when that is the shared canvas.
    controller.showMaster();
    await tester.pumpAndSettle();
    expect(find.text("Master"), findsOneWidget);
  });

  testWidgets("a scene with its own transition is marked", (tester) async {
    // Plain for the document's default, and its own mark for a scene that has
    // been given something particular -- which is the question somebody
    // scanning a list of twelve scenes is asking.
    await panel(tester,
        document: const CanvasDocument().withScenes([
          const CanvasScene(
              id: "a",
              transition: SceneTransition(kind: SceneTransitionKind.fade)),
          const CanvasScene(id: "b"),
        ]));
    expect(find.byTooltip("Cross fade, set on this scene"), findsOneWidget);
  });
}
