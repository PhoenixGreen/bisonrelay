import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/ui/procedural_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_settings_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/scenes_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/double_click.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // The pair is counted against the real clock, so a loaded machine can
    // put a second of real time between two taps made back to back.
    DoubleClick.window = const Duration(minutes: 1);
  });

  Future<CanvasController> panel(WidgetTester tester,
      {CanvasDocument? document, double width = 300}) async {
    var controller = CanvasController(document ?? const CanvasDocument());
    addTearDown(controller.dispose);

    tester.view.physicalSize = Size(width + 100, 900);
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
              width: width,
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
    await tester.tap(find.byTooltip("New scene"));
    await tester.pumpAndSettle();

    expect(controller.document.allScenes.length, 2);
    expect(controller.document.at, 1, reason: "the one just made");
    expect(find.text("Scene 2"), findsOneWidget);
  });

  testWidgets("pressing a scene is how you get to it", (tester) async {
    var controller = await panel(tester, document: const CanvasDocument());
    await tester.tap(find.byTooltip("New scene"));
    await tester.pumpAndSettle();
    expect(controller.document.at, 1);

    await tester.tap(find.text("Scene 1"));
    await tester.pumpAndSettle();
    expect(controller.document.at, 0);
  });

  testWidgets("a scene is renamed by clicking its name twice", (tester) async {
    // The way a file is renamed everywhere else. It used to be on the row's
    // menu, which is a long way round for something this common.
    var controller = await panel(tester);
    var name = find.text("Scene 1");

    // No pause between them: the second click is counted against the real
    // clock, so a test that waits for a fake fifty milliseconds is a test
    // that fails on a loaded machine.
    await tester.tap(name);
    await tester.tap(name);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget,
        reason: "the name opened for typing");
    await tester.enterText(find.byType(TextField), "Opening");
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.document.allScenes.first.name, "Opening");
  });

  testWidgets("one click on the name only chooses the scene", (tester) async {
    // And it does so at once: a double-click recognizer would hold every
    // press on this row back until its window had passed.
    var controller = await panel(tester, document: const CanvasDocument());
    await tester.tap(find.byTooltip("New scene"));
    await tester.pumpAndSettle();
    expect(controller.document.at, 1);

    await tester.tap(find.text("Scene 1"));
    await tester.pump();
    expect(controller.document.at, 0, reason: "chosen on the first click");
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets("a scene is copied from one canvas and pasted into another",
      (tester) async {
    // What Copy is for: the clipboard outlives the document, so the scene
    // can be pasted into whichever canvas is opened next.
    var controller = await panel(tester);
    controller.addElement(
        ShapeElement(const ElementBase(id: "s", width: 10, height: 10)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip("More").first);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Copy"));
    await tester.pumpAndSettle();
    expect(find.text("Rename…"), findsNothing,
        reason: "renaming is the name's own job now");

    // A different document, the way opening another canvas is.
    var other = await panel(tester, document: const CanvasDocument());
    expect(other.document.allScenes.length, 1);
    await tester.tap(find.byTooltip("Paste the copied scene"));
    await tester.pumpAndSettle();

    expect(other.document.allScenes.length, 2);
    expect(other.document.allScenes[1].elements.length, 1,
        reason: "what was on the scene came with it");
    expect(other.document.allScenes[1].elements.first.id, isNot("s"),
        reason: "and it is a copy, not the same element twice");
  });

  testWidgets("with nothing copied there is nothing to paste", (tester) async {
    CanvasController.forgetCopiedScene();
    await panel(tester);
    expect(find.byTooltip("Paste the copied scene"), findsNothing);
  });

  testWidgets("an edit lands on the scene being shown", (tester) async {
    // Which is the whole point of the list: the canvas you are on is the one
    // the rest of the editor is editing.
    var controller = await panel(tester);
    await tester.tap(find.byTooltip("New scene"));
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
    await tester.tap(find.byTooltip("New scene"));
    await tester.pumpAndSettle();
    expect(controller.document.allScenes.length, 2);

    // Drawn by the renderer rather than kept as pictures, so a preview cannot
    // be out of date.
    expect(find.byType(CustomPaint).evaluate().length, greaterThan(0));
    await tester.tap(find.byTooltip("Scene preview"));
    await tester.pumpAndSettle();
    expect(find.byTooltip("Scene preview: off"), findsOneWidget);
  });

  // A preview is as wide as the column -- until that would make it taller
  // than a page's worth of sidebar. Dragged wide, one page filled the screen.
  testWidgets("a preview is capped in height however wide the sidebar",
      (tester) async {
    await panel(tester,
        width: 900,
        document: const CanvasDocument(
            kind: CanvasKind.pages,
            size: CanvasSize(ratio: CanvasRatio.a4, width: a4PageWidth),
            scenes: [CanvasScene(id: "a")]));
    await tester.tap(find.byTooltip("Page preview"));
    await tester.pumpAndSettle();
    var box = tester.getSize(find.byKey(const ValueKey("scenePreview.0")));
    expect(box.height, lessThanOrEqualTo(220.5));
    expect(box.width / box.height, closeTo(210 / 297, 0.01),
        reason: "still the shape of the page");
  });

  // Drawn from the editor's own picture store, so the pictures on a page are
  // the pictures rather than "Loading" placeholders that nothing ever
  // replaced: the preview had no store to ask.
  testWidgets("a preview draws with the editor's pictures", (tester) async {
    var controller = await panel(tester);
    await tester.tap(find.byTooltip("Scene preview"));
    await tester.pumpAndSettle();
    var painters = tester
        .widgetList<CustomPaint>(find.descendant(
            of: find.byKey(const ValueKey("scenePreview.0")),
            matching: find.byType(CustomPaint)))
        .map((c) => c.painter)
        .whereType<CustomPainter>()
        .toList();
    expect(painters, hasLength(1));
    expect(identical((painters.single as dynamic).images, controller.images),
        isTrue);
  });

  // With facing pages on, the previews are laid out as the book is: the two
  // pages of a spread side by side, the left one on the left.
  testWidgets("facing pages are previewed side by side", (tester) async {
    await panel(tester,
        document: const CanvasDocument(
            kind: CanvasKind.pages,
            size: CanvasSize(ratio: CanvasRatio.a4, width: a4PageWidth),
            pages: PagesSpec(facing: true),
            scenes: [
              CanvasScene(id: "a"),
              CanvasScene(id: "b"),
              CanvasScene(id: "c"),
              CanvasScene(id: "d"),
            ]));
    await tester.tap(find.byTooltip("Page preview"));
    await tester.pumpAndSettle();
    Rect at(int i) => tester.getRect(find.byKey(ValueKey("scenePreview.$i")));
    var doc = const CanvasDocument(
        kind: CanvasKind.pages,
        pages: PagesSpec(facing: true),
        scenes: [
          CanvasScene(id: "a"),
          CanvasScene(id: "b"),
          CanvasScene(id: "c"),
          CanvasScene(id: "d"),
        ]);
    var (left, right) = doc.spreadOf(1)!;
    expect([left, right], everyElement(isNotNull));
    expect(at(left!).top, closeTo(at(right!).top, 0.5),
        reason: "one row for the spread");
    expect(at(left).right, lessThanOrEqualTo(at(right).left),
        reason: "the left-hand page on the left");
  });

  // A picture laid across the spread from one page shows on the page facing
  // it in the list too, as it does on the canvas. Drawn alone, each preview
  // cut the picture off at the spine.
  testWidgets("a picture across the spine is in both previews", (tester) async {
    const w = a4PageWidth * 1.0, h = w * 297 / 210;
    var doc = const CanvasDocument(
        kind: CanvasKind.pages,
        size: CanvasSize(ratio: CanvasRatio.a4, width: a4PageWidth),
        pages: PagesSpec(facing: true),
        scenes: [
          CanvasScene(id: "a"),
          CanvasScene(id: "b"),
          CanvasScene(id: "c"),
          CanvasScene(id: "d"),
        ]);
    var (left, right) = doc.spreadOf(1)!;
    var scenes = [...doc.allScenes];
    scenes[left!] = scenes[left].copyWith(elements: [
      ShapeElement(
          const ElementBase(
              id: "across", x: 0, y: h * 0.25, width: w * 2, height: h * 0.5),
          fill: const Color(0xFFFF0000)),
    ]);
    await panel(tester, document: doc.withScenes(scenes));
    await tester.tap(find.byTooltip("Page preview"));
    await tester.pumpAndSettle();

    var preview = find.byKey(ValueKey("scenePreview.${right!}"));
    var size = tester.getSize(preview);
    var painter = tester
        .widget<CustomPaint>(
            find.descendant(of: preview, matching: find.byType(CustomPaint)))
        .painter!;
    late ByteData data;
    await tester.runAsync(() async {
      var recorder = ui.PictureRecorder();
      painter.paint(ui.Canvas(recorder), size);
      var image = await recorder
          .endRecording()
          .toImage(size.width.round(), size.height.round());
      data = (await image.toByteData())!;
    });
    var c = data.getUint32(((size.height / 2).round() * size.width.round() +
            (size.width / 2).round()) *
        4);
    expect((c >> 24 & 0xFF) > 150 && (c >> 8 & 0xFF) < 80, isTrue,
        reason: "the right page shows the picture from the left "
            "(${c.toRadixString(16)})");
  });

  // Preview on, the section left and come back to: still previews. The
  // panel is built afresh each time, and it went back to the list.
  testWidgets("the preview is remembered when the section is come back to",
      (tester) async {
    await panel(tester);
    await tester.tap(find.byTooltip("Scene preview"));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("scenePreview.0")), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await panel(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("scenePreview.0")), findsOneWidget);
  });

  testWidgets("up and down go through the list", (tester) async {
    var controller = await panel(tester,
        document: const CanvasDocument(scenes: [
          CanvasScene(id: "a"),
          CanvasScene(id: "b"),
          CanvasScene(id: "c"),
        ]));
    await tester.tap(find.text("Scene 1"));
    await tester.pumpAndSettle();
    expect(controller.sceneAt, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(controller.sceneAt, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(controller.sceneAt, 2, reason: "the end is the end");
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(controller.sceneAt, 1);
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

    var buttons = find.byTooltip("More");
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

  testWidgets("the preview of a join comes back to the scene it started on",
      (tester) async {
    // Playing the document walks the editor through the scenes, so without
    // this, watching a join left the reader on the scene after the one they
    // pressed it from -- and pressing it again meant walking back first.
    var controller = await panel(tester,
        document: const CanvasDocument().withScenes([
          const CanvasScene(id: "a", frames: 4),
          const CanvasScene(id: "b", frames: 4),
          const CanvasScene(id: "c", frames: 4),
        ]));

    controller.goToScene(1);
    controller.playAll = true;
    controller.previewTransitionAfter(1);
    expect(controller.previewAt, isNotNull);

    for (var i = 0; i < 20; i++) {
      controller.tickForTest();
    }
    expect(controller.previewAt, isNull, reason: "it finished");
    expect(controller.document.at, 1,
        reason: "and left the editor where it was found");
  });

  testWidgets("the things that act on the list are above it", (tester) async {
    // A control that acts on a list belongs at the top of it, where it is
    // found without reading to the end.
    await panel(tester,
        document: const CanvasDocument().withScenes([
          for (var i = 0; i < 4; i++) CanvasScene(id: "s$i"),
        ]));

    // On the same line as the master header, and above the list.
    var newScene = tester.getRect(find.byTooltip("New scene"));
    var master = tester.getRect(find.text("Master scene"));
    var firstRow = tester.getRect(find.text("Scene 1"));
    expect(newScene.top, lessThan(firstRow.top));
    expect((newScene.center.dy - master.center.dy).abs(), lessThan(6),
        reason: "beside the header rather than on a line of its own");
    expect(newScene.left, greaterThan(master.left),
        reason: "and to the right of it");

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

  testWidgets("the bar's two ends stay put whether or not there are scenes",
      (tester) async {
    // The tools and the space before the buttons on the right were two
    // flexible children of one row, so the leftover width was split between
    // them: a hole before the buttons when there was room to spare, and the
    // last of the tools scrolled out of sight when there was not.
    var controller = CanvasController(const CanvasDocument());
    addTearDown(controller.dispose);

    tester.view.physicalSize = const Size(1400, 900);
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
    await tester.pumpAndSettle();

    var bar = tester.getRect(find.byType(CanvasSettingsBar));
    var publish = tester.getRect(find.byTooltip("Publish this canvas"));
    expect(bar.right - publish.right, lessThan(14),
        reason: "hard right with one scene: ${bar.right - publish.right}");

    // And the percentage stays with the tools it belongs to rather than
    // drifting across to the buttons on the right.
    var zoom = tester.getRect(find.byType(TextField).last);
    var zoomIn = tester.getRect(find.byIcon(Icons.zoom_in));
    expect(zoom.left - zoomIn.right, lessThan(12),
        reason: "the reading sits against the zoom buttons");
    expect(zoom.right, lessThan(bar.width * 0.6),
        reason: "on the left half of the bar, not beside Publish");

    // The margin button is the last of the tools, and it is still there once
    // the scene section has appeared in front of them.
    var margin = find.byTooltip("Show a margin outside the canvas, for "
        "animating things on and off");
    expect(margin, findsOneWidget);
    var before = tester.getRect(margin);
    expect(before.right, lessThan(bar.right));

    controller.addScene();
    controller.addScene();
    await tester.pumpAndSettle();

    expect(find.text("3/3"), findsOneWidget);
    expect(margin, findsOneWidget, reason: "not scrolled out of the row");
    expect(tester.getRect(margin).right, lessThan(bar.right));
    var after = tester.getRect(find.byTooltip("Publish this canvas"));
    expect(bar.right - after.right, lessThan(14),
        reason: "and the right-hand end has not moved");
  });

  testWidgets("the background panel shows the scene it is editing",
      (tester) async {
    // The reported fault, and it needed the panel to see it: the settings
    // read the document's background while writing to the scene's, so the
    // colours never moved -- every edit was built from the one nobody was
    // looking at, and the next undid the last.
    var controller = CanvasController(const CanvasDocument().withScenes([
      const CanvasScene(id: "a"),
      const CanvasScene(id: "b"),
    ]));
    addTearDown(controller.dispose);

    tester.view.physicalSize = const Size(900, 1200);
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
                width: 320, child: CanvasDesignPanel(controller: controller))),
      ),
    ));
    await tester.pumpAndSettle();

    ProceduralSettings settings() =>
        tester.widget<ProceduralSettings>(find.byType(ProceduralSettings));

    // Three colours, one after another, the way somebody actually works.
    const pink = Color(0xFFFF69B4);
    const green = Color(0xFF00A86B);
    const gold = Color(0xFFFFD700);

    settings().onChanged(settings().spec.copyWith(background: pink));
    await tester.pumpAndSettle();
    expect(settings().spec.background, pink,
        reason: "the panel says what was just set");

    settings().onChanged(settings().spec.copyWith(foreground: green));
    await tester.pumpAndSettle();
    settings().onChanged(settings().spec.copyWith(accent: gold));
    await tester.pumpAndSettle();

    var drawn = controller.document.drawnBackground.spec;
    expect(drawn.background, pink);
    expect(drawn.foreground, green, reason: "the second edit kept the first");
    expect(drawn.accent, gold, reason: "and the third kept both");

    // And none of it reached the scene after this one.
    expect(controller.document.backgroundOf(1).spec.background, isNot(pink));
  });

  testWidgets("the panel edits the shared backdrop when that is the one shown",
      (tester) async {
    // The same fault one level up, and the one that made the whole Background
    // panel look dead: a backdrop on the shared canvas is drawn in front of
    // every scene's, and the panel went on showing and writing the scene's --
    // so every setting changed a background nobody could see.
    var controller = CanvasController(const CanvasDocument().withScenes([
      const CanvasScene(id: "a"),
      const CanvasScene(id: "b"),
    ]).copyWith(
        master: const CanvasScene(
            id: "master",
            background: CanvasBackground(
                spec: ProceduralSpec(style: ProceduralStyle.starfield))),
        masterOn: true));
    addTearDown(controller.dispose);

    tester.view.physicalSize = const Size(900, 1200);
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
                width: 320, child: CanvasDesignPanel(controller: controller))),
      ),
    ));
    await tester.pumpAndSettle();

    ProceduralSettings settings() =>
        tester.widget<ProceduralSettings>(find.byType(ProceduralSettings));

    expect(settings().spec.style, ProceduralStyle.starfield,
        reason: "the panel was showing a background nobody could see");

    const pink = Color(0xFFFF69B4);
    settings().onChanged(settings().spec.copyWith(background: pink));
    await tester.pumpAndSettle();

    expect(controller.document.drawnBackground.spec.background, pink,
        reason: "the edit went somewhere nobody can see");
    expect(settings().spec.background, pink,
        reason: "and the panel says what was just set");
    expect(controller.document.scene.background, isNull,
        reason: "it belongs to the shared canvas, not to this scene");

    // And it says whose it is, because changing it changes every scene.
    expect(find.byKey(const ValueKey("sharedBackdropNote")), findsOneWidget);
    expect(find.textContaining("shared canvas"), findsWidgets);
  });

  testWidgets("the shared backdrop's switch answers at once", (tester) async {
    // It answered a scene later: the layers list is drawn from a summary of
    // what it shows, and the background row's own state was not in that
    // summary -- so the eye kept the state it was built with until something
    // else happened to rebuild the column.
    var controller = CanvasController(const CanvasDocument().withScenes([
      const CanvasScene(id: "a"),
      const CanvasScene(id: "b")
    ]).copyWith(
        master: const CanvasScene(id: "master", background: CanvasBackground()),
        masterOn: true));
    addTearDown(controller.dispose);

    tester.view.physicalSize = const Size(900, 1200);
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
                width: 320, child: CanvasDesignPanel(controller: controller))),
      ),
    ));
    await tester.pumpAndSettle();

    // On the shared canvas, where the switch lives.
    controller.showMaster();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.visibility), findsOneWidget,
        reason: "an open eye while the backdrop is used");
    expect(find.byIcon(Icons.visibility_off), findsNothing);

    await tester.tap(find.byKey(const ValueKey("masterBackgroundOff")));
    await tester.pumpAndSettle();

    expect(controller.document.master!.backgroundOff, isTrue);
    expect(find.byIcon(Icons.visibility_off), findsOneWidget,
        reason: "and a line through it the moment it is switched off");
    expect(find.byIcon(Icons.visibility), findsNothing);

    await tester.tap(find.byKey(const ValueKey("masterBackgroundOff")));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.visibility), findsOneWidget);
  });

  testWidgets("the background row says which canvas it is on", (tester) async {
    // Leaving the shared canvas, the row went on naming the master's backdrop
    // until something else rebuilt the column.
    var controller = CanvasController(const CanvasDocument().withScenes([
      const CanvasScene(
          id: "a",
          background: CanvasBackground(
              spec: ProceduralSpec(style: ProceduralStyle.dotGrid))),
      const CanvasScene(id: "b"),
    ]).copyWith(
        master: const CanvasScene(
            id: "master",
            background: CanvasBackground(
                spec: ProceduralSpec(style: ProceduralStyle.hexGrid))),
        masterOn: true));
    addTearDown(controller.dispose);

    tester.view.physicalSize = const Size(900, 1200);
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
                width: 320, child: CanvasDesignPanel(controller: controller))),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text("Background — Dot grid"), findsOneWidget);

    controller.showMaster();
    await tester.pumpAndSettle();
    expect(find.text("Background — Hex grid"), findsOneWidget,
        reason: "the shared canvas's own");

    controller.goToScene(0);
    await tester.pumpAndSettle();
    expect(find.text("Background — Dot grid"), findsOneWidget,
        reason: "and the scene's again the moment it is showing");
  });

  testWidgets("the run stopping here is on the scene's own menu",
      (tester) async {
    // It was on the timeline as well. One place is enough, and the list is
    // where a sequence is arranged.
    var controller = await panel(tester,
        document: const CanvasDocument().withScenes([
          const CanvasScene(id: "a"),
          const CanvasScene(id: "b"),
        ]));

    await tester.tap(find.byTooltip("More").first);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Stop at the end of this scene"));
    await tester.pumpAndSettle();

    expect(controller.document.allScenes.first.holds, isTrue);
    expect(controller.document.allScenes[1].holds, isFalse,
        reason: "this scene, not every scene");
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
