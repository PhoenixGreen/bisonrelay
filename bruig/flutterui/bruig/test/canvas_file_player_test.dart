import 'dart:io';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_screen.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_file_player.dart';
import 'package:bruig/screens/manage_content/file_preview.dart';
import 'package:bruig/theming_system/theme_manager.dart';
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
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
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
    await tester.tap(find.text("Open"));
    for (var i = 0; i < 20 && prefs.pendingOpen == null; i++) {
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(prefs.pendingOpen, ("", "Sky Isles"));
    expect(find.text("the Canvas page"), findsOneWidget);
    var saved =
        await tester.runAsync(() => CanvasStorage.load("", "Sky Isles"));
    expect(saved?.game, isTrue);
  });
}
