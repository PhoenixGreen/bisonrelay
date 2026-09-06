import 'dart:io';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/files_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// Every one of these pumps a widget over real files, which needs the
// runAsync/pump cycle in [idle] rather than pumpAndSettle: testWidgets runs in
// a fake-async zone, a dart:io future completes on the real loop, and its
// continuation is a microtask in the fake one -- so each step of an I/O chain
// needs one turn of each. pumpAndSettle on its own hangs forever on the
// panel's loading spinner, with no error at all.
//
// canvas_files_panel_test.dart is about the Files sidebar being the same thing
// as the post library's, which is what it is meant to look like: a list of the
// reader's own documents, the things you can do to one on its row, and the
// things that make new ones along the bottom.
//
// The one that matters most is the row button. A Tooltip anywhere inside a
// reorderable row is an overlay that gets re-attached mid-layout when the row
// moves, and the sidebar is replaced by a red error box -- a crash the post
// library has already been through once. There is a test here that nothing in
// a row owns one.

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp("canvas_files_panel_test");
    CanvasStorage.rootOverride = root.path;
  });

  tearDown(() async {
    CanvasStorage.rootOverride = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// idle turns the real event loop and the fake one alternately, which is
  /// what a widget test over real file I/O needs. See the note at the top.
  Future<void> idle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 4)));
      await tester.pump();
    }
  }

  Future<CanvasController> pump(
    WidgetTester tester, {
    List<String> canvases = const [],
    List<String> folders = const [],
    CanvasController? controller,
    void Function(String folder, String name)? onNew,
  }) async {
    // Written on the real loop: this is a real directory.
    await tester.runAsync(() async {
      for (var folder in folders) {
        await CanvasStorage.createFolder(folder);
      }
      for (var name in canvases) {
        await CanvasStorage.save("", name, CanvasDocument(title: name));
      }
    });

    var it = controller ?? CanvasController(const CanvasDocument());
    addTearDown(it.dispose);

    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: CanvasFilesPanel(
              controller: it,
              onOpen: (f, n) async {},
              onPublish: (f, n) {},
              onNew: (f, n) async => onNew?.call(f, n),
            ),
          ),
        ),
      ),
    ));
    await idle(tester);
    return it;
  }

  testWidgets("the things that make something new are along the bottom",
      (tester) async {
    await pump(tester, canvases: ["Match plan"]);

    expect(find.text("New canvas"), findsOneWidget);
    expect(find.text("New folder"), findsOneWidget);
    // Icon only, so it is found by what it says on hover rather than by a
    // label it does not carry.
    expect(find.byTooltip("Open a canvas from a file"), findsOneWidget);

    // They are below the list, which is the thing somebody came here to read.
    var list = tester.getBottomLeft(find.text("Match plan")).dy;
    expect(tester.getTopLeft(find.text("New canvas")).dy, greaterThan(list));
  });

  testWidgets("the toolbar that was above the list is gone", (tester) async {
    // Save, Save as and Refresh between them: a canvas saves itself, Duplicate
    // is Save as, and a listing that reads the directory every time it is
    // shown has nothing to refresh from.
    await pump(tester, canvases: ["Match plan"]);
    expect(find.text("Save"), findsNothing);
    expect(find.byTooltip("Save as a new canvas"), findsNothing);
    expect(find.byTooltip("Refresh the list"), findsNothing);
    expect(find.byTooltip("New folder"), findsNothing,
        reason: "it is a labelled chip at the bottom now, not an icon on top");
  });

  testWidgets("a canvas with nowhere to save itself is offered a Save",
      (tester) async {
    // The one case autosave cannot cover: a canvas started from a preset has
    // never been saved, so there is no file for it to write itself to.
    var element =
        ShapeElement(const ElementBase(id: "s", width: 10, height: 10));
    var unsaved = CanvasController(const CanvasDocument().addElement(element));
    unsaved.beginInteraction();
    unsaved.replaceElement(element.withBase(x: 20));
    unsaved.endInteraction();

    expect(unsaved.name, isNull);
    expect(unsaved.dirty, isTrue);

    await pump(tester, controller: unsaved);
    expect(find.text("Save this canvas"), findsOneWidget);
  });

  testWidgets("the Save chip is only there when there is no file to save to",
      (tester) async {
    var saved = CanvasController(const CanvasDocument());
    saved.name = "Match plan";
    await pump(tester, canvases: ["Match plan"], controller: saved);
    expect(find.text("Save this canvas"), findsNothing,
        reason: "a named canvas saves itself");
  });

  testWidgets("a row's button is vertical, and owns no overlay",
      (tester) async {
    await pump(tester, canvases: ["Match plan", "Team sheet"]);

    expect(find.byIcon(Icons.more_vert), findsNWidgets(2));
    expect(find.byIcon(Icons.more_horiz), findsNothing);

    // The crash guard. A Tooltip inside a reorderable row is an OverlayPortal
    // whose child is re-attached mid-layout when the row moves, and the
    // framework refuses -- see files_panel's own note, and the post library's.
    expect(
        find.descendant(
            of: find.byType(ReorderableListView),
            matching: find.byType(Tooltip)),
        findsNothing);
  });

  testWidgets("the list says how to move a row, once", (tester) async {
    await pump(tester, canvases: ["Match plan", "Team sheet"]);
    expect(find.textContaining("press and hold", findRichText: true),
        findsNothing);
    expect(find.text("Press and hold a row's ⋮ to move it"), findsOneWidget);
  });

  testWidgets("one canvas is not worth explaining a reorder for",
      (tester) async {
    await pump(tester, canvases: ["Match plan"]);
    expect(find.text("Press and hold a row's ⋮ to move it"), findsNothing);
  });

  testWidgets("the row menu opens on a tap and offers the row's actions",
      (tester) async {
    await pump(tester, canvases: ["Match plan"]);
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();

    for (var item in ["Publish…", "Duplicate", "Rename…", "Delete"]) {
      expect(find.text(item), findsOneWidget, reason: item);
    }
  });

  testWidgets("a folder is offered only what a folder can do", (tester) async {
    await pump(tester, folders: ["Plans"]);
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();

    expect(find.text("Delete"), findsOneWidget);
    expect(find.text("Rename…"), findsOneWidget,
        reason: "a folder can be renamed, with everything in it");
    expect(find.text("Duplicate"), findsNothing,
        reason: "there is no duplicating a folder here");
  });

  testWidgets("a folder can be moved like anything else", (tester) async {
    // Folders were listed first and left there. They are listed first only
    // until somebody says otherwise, and dragging one is exactly that.
    await pump(tester, canvases: ["Match plan"], folders: ["Plans"]);

    var list =
        tester.widget<ReorderableListView>(find.byType(ReorderableListView));
    expect(list.itemCount, 2);

    // Both rows carry a drag listener, the folder included.
    expect(find.byType(ReorderableDelayedDragStartListener), findsNWidgets(2));
  });

  testWidgets("the order that comes back names folders apart from canvases",
      (tester) async {
    // A folder and a canvas can share a name. In the order file they must not
    // share a line, or one takes the other's place.
    var folder = const CanvasEntry(name: "Plans", folder: "", isFolder: true);
    var document =
        const CanvasEntry(name: "Plans", folder: "", isFolder: false);
    expect(CanvasStorage.orderKeyFor(folder),
        isNot(CanvasStorage.orderKeyFor(document)));
    expect(CanvasStorage.orderKeyFor(document), "Plans",
        reason: "a bare name has always meant a canvas, and still does");
  });

  test("a folder is renamed with everything in it", () async {
    await CanvasStorage.createFolder("Plans");
    await CanvasStorage.save(
        "Plans", "Match plan", const CanvasDocument(title: "Match plan"));

    expect(await CanvasStorage.renameFolder("Plans", "Season"), isTrue);
    expect(await CanvasStorage.load("Season", "Match plan"), isNotNull,
        reason: "what was in it came too");
    expect(await CanvasStorage.load("Plans", "Match plan"), isNull);
  });

  test("a folder is not renamed onto one that exists", () async {
    // It would merge the two with no way back.
    await CanvasStorage.createFolder("Plans");
    await CanvasStorage.createFolder("Season");
    expect(await CanvasStorage.renameFolder("Plans", "Season"), isFalse);
    expect(await CanvasStorage.list(""), hasLength(2));
  });
}
