import 'dart:io';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/canvas_screen.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/canvas_file_player.dart';
import 'package:bruig/screens/manage_content/file_preview.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

// canvas_file_player_test.dart is a canvas file previewed in Files, as a
// PDF is: played, with play, pause and start again (Ken, 2026-11-01). A
// game is previewed as any canvas is: games are no longer published.

void main() {
  test("what is shared is written beside downloads and the library", () async {
    var root = await Directory.systemTemp.createTemp("shared-dir");
    CanvasStorage.rootOverride = root.path;
    addTearDown(() async {
      CanvasStorage.rootOverride = null;
      await root.delete(recursive: true);
    });
    expect(await CanvasStorage.sharedDir(), path.join(root.path, "shared"));
    expect(Directory(path.join(root.path, "shared")).existsSync(), isTrue);
  });

  test("a canvas file is one Files can preview", () {
    expect(fileKindOf("/x/Sky Isles.bcanvas"), FileKind.canvas);
    expect(fileKindOf("/x/notes.bin"), FileKind.other);
    expect(fileKindOf("/x/The History of Decred.epub"), FileKind.epub,
        reason: "a book, read in Bison Relay's own reader");
  });

  group("played in the preview", () {
    late Directory root;

    Future<File> write(WidgetTester tester, CanvasDocument doc) async {
      root = (await tester
          .runAsync(() => Directory.systemTemp.createTemp("canvas-file")))!;
      CanvasStorage.rootOverride = root.path;
      addTearDown(() async {
        CanvasStorage.rootOverride = null;
        await tester.runAsync(() => root.delete(recursive: true));
      });
      var file = File(path.join(root.path, "Shared.bcanvas"));
      await tester.runAsync(() => file.writeAsString(doc.encode()));
      return file;
    }

    Future<void> show(WidgetTester tester, File file) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(
              create: (c) => CanvasPreferences()..enabled = true),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: SizedBox(
                    width: 800,
                    height: 600,
                    child: CanvasFilePlayer(file: file)))),
      ));
      for (var i = 0; i < 20; i++) {
        await tester
            .runAsync(() => Future.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
    }

    testWidgets("a canvas plays, pauses and starts again", (tester) async {
      var file = await write(
          tester,
          CanvasDocument(frames: 60, elements: [
            ShapeElement(const ElementBase(id: "a", width: 100, height: 100)),
          ]));
      await show(tester, file);
      expect(find.byKey(const ValueKey("canvasFileView")), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("canvasFilePlay")));
      await tester.pump();
      expect(find.byIcon(Icons.pause), findsOneWidget, reason: "playing");
      await tester.tap(find.byKey(const ValueKey("canvasFilePlay")));
      await tester.pump();
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("canvasFileAgain")));
      await tester.pump();
      expect(find.byIcon(Icons.pause), findsOneWidget,
          reason: "from the start, playing");
      await tester.tap(find.byKey(const ValueKey("canvasFilePlay")));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });

    // Ken, 2026-11-18: a comic book read panel by panel, back and forward.
    testWidgets("a comic is read in Panel mode, and played again",
        (tester) async {
      var file = await write(
          tester,
          const CanvasDocument().addElement(LayoutElement(
              const ElementBase(id: "L", width: 1280, height: 720),
              root: const LayoutNode.cut(
                  vertical: true,
                  a: LayoutNode.leaf("a"),
                  b: LayoutNode.leaf("b")),
              cells: const [LayoutCell(id: "a"), LayoutCell(id: "b")])));
      await show(tester, file);
      var toggle = find.byKey(const ValueKey("canvasFilePanels"));
      expect(toggle, findsOneWidget, reason: "offered: it has panels");
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey("canvasFilePanelReader")), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("panelReaderForward")));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey("panelReaderWhere")))
              .data,
          endsWith("panel 1 of 2"));
      await tester.tap(find.byKey(const ValueKey("canvasFilePanels")));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("canvasFileView")), findsOneWidget,
          reason: "played as before");
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("no Panel mode where there are no panels", (tester) async {
      var file = await write(
          tester,
          CanvasDocument(elements: [
            ShapeElement(const ElementBase(id: "a", width: 100, height: 100)),
          ]));
      await show(tester, file);
      expect(find.byKey(const ValueKey("canvasFilePanels")), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("its buttons are pressed in the preview", (tester) async {
      var file = await write(
          tester,
          CanvasDocument(frames: 60, elements: [
            ShapeElement(const ElementBase(
                id: "door", x: 900, y: 100, width: 100, height: 100)),
            ButtonElement(
                const ElementBase(
                    id: "b", x: 0, y: 0, width: 1280, height: 720),
                action: const ButtonAction(
                    kind: ButtonActionKind.toggleElement, elementId: "door")),
          ]));
      await show(tester, file);
      var view = find.byKey(const ValueKey("canvasFileView"));
      await tester.tapAt(tester.getCenter(view));
      await tester.pump();
      // The door hidden by the press: drawn by the player's own controller.
      var player = tester.state(find.byType(CanvasFilePlayer));
      expect(
          (player as dynamic)
              .controllerForTest
              .document
              .elementById("door")!
              .visible,
          isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });

    // A click on a button turned as it rests, or turned by its keys about
    // its corner, lands on it where it is drawn: on its ink near a corner,
    // which its upright box leaves out, and not on a corner of that upright
    // box, which is not drawn.
    for (var (name, base) in [
      (
        "turned as it rests",
        const ElementBase(
            id: "b", x: 400, y: 200, width: 400, height: 100, rotation: 45),
      ),
      (
        "turned by its keys about its corner",
        ElementBase(
            id: "b",
            x: 400,
            y: 200,
            width: 400,
            height: 100,
            anchorX: 0,
            anchorY: 0,
            track: ElementTrack(const [
              Keyframe(frame: 0),
              Keyframe(frame: 24, rotate: 70),
            ])),
      ),
    ]) {
      for (var (point, presses) in [
        ("on its ink near a corner", true),
        ("on a corner of its upright box", false),
      ]) {
        testWidgets(
            "a button $name is clicked $point: ${presses ? "it acts" : "nothing"}",
            (tester) async {
          var button = ButtonElement(base,
              action: const ButtonAction(
                  kind: ButtonActionKind.toggleElement, elementId: "door"));
          var file = await write(
              tester,
              CanvasDocument(frames: 60, elements: [
                ShapeElement(const ElementBase(
                    id: "door", x: 1100, y: 600, width: 100, height: 100)),
                button,
              ]));
          await show(tester, file);
          var player = tester.state(find.byType(CanvasFilePlayer));
          CanvasController c = (player as dynamic).controllerForTest;
          c.pause();
          c.frame = 12;
          await tester.pump();
          var place = placeOnPage(button, 12, c.document, null).place;
          var box = button.bounds;
          var at = presses
              ? place.place(box.topRight + const Offset(-8, 8))
              : box.bottomRight - const Offset(4, 4);
          // Said of the points, as the painter lays the button out.
          var local = place.unplace(at);
          expect(box.contains(local), presses);
          expect(box.contains(at), !presses);
          var view =
              tester.getRect(find.byKey(const ValueKey("canvasFileView")));
          var scale = view.width / c.document.size.size.width;
          await tester.tapAt(view.topLeft + at * scale);
          await tester.pump();
          expect(c.document.elementById("door")!.visible, !presses);
          await tester.pumpWidget(const SizedBox());
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets("a clip that starts on a click starts when it is clicked",
        (tester) async {
      var hop = MotionClip.ofKind("hop", MotionKind.action, name: "Hop")
          .copyWith(quantise: () => "off", triggers: const [
        ClipTrigger(ClipTriggerKind.clicked, target: "a")
      ], keys: {
        MotionProp.y: const [
          MotionKey(0, MotionNumber(0)),
          MotionKey(1, MotionNumber(-50)),
        ],
      });
      var file = await write(
          tester,
          CanvasDocument(frames: 60, elements: [
            ShapeElement(ElementBase(
                id: "a",
                x: 540,
                y: 260,
                width: 200,
                height: 200,
                motion: ElementMotion(clips: [hop]))),
          ]));
      await show(tester, file);
      var player = tester.state(find.byType(CanvasFilePlayer));
      CanvasController c = (player as dynamic).controllerForTest;
      expect(c.motionPlayer.isOff("a"), isFalse);
      await tester.tapAt(
          tester.getCenter(find.byKey(const ValueKey("canvasFileView"))));
      await tester.pump();
      expect(c.motionPlayer.isOff("a"), isTrue, reason: "hopping");
      c.pause();
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });

    testWidgets("a game is played as any canvas is", (tester) async {
      var file = await write(
          tester,
          CanvasDocument(game: true, elements: [
            ShapeElement(const ElementBase(id: "a", width: 100, height: 100)),
          ]));
      await show(tester, file);
      expect(find.byKey(const ValueKey("canvasFilePlay")), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  });

  // Ken: Open on a shared game did nothing -- a .bcanvas has no program of
  // its own to open it.
  testWidgets("Open puts a canvas in the library and goes to Canvas",
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    var root = (await tester
        .runAsync(() => Directory.systemTemp.createTemp("canvas-open")))!;
    CanvasStorage.rootOverride = root.path;
    addTearDown(() async {
      CanvasStorage.rootOverride = null;
      await tester.runAsync(() => root.delete(recursive: true));
    });
    var file = File(path.join(root.path, "Sky Isles.bcanvas"));
    await tester.runAsync(() => file.writeAsString(
        const CanvasDocument(title: "Sky Isles", game: true).encode()));
    var prefs = CanvasPreferences()..enabled = true;
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>.value(value: prefs),
      ],
      child: MaterialApp(
        routes: {CanvasScreen.routeName: (_) => const Text("the Canvas page")},
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => openCanvasFile(context, file.path),
                child: const Text("Open"))),
      ),
    ));
    // What the button does, in real time: it reads and stores the file off
    // the test's own clock, which pumping alone never let finish quickly.
    var context = tester.element(find.text("Open"));
    await tester.runAsync(() => openCanvasFile(context, file.path));
    await tester.pumpAndSettle();
    expect(prefs.pendingOpen, ("", "Sky Isles"));
    expect(find.text("the Canvas page"), findsOneWidget);
    var saved =
        await tester.runAsync(() => CanvasStorage.load("", "Sky Isles"));
    expect(saved?.game, isTrue);
  });
}
