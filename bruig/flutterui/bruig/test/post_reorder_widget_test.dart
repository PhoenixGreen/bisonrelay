import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:bruig/plugin_system/writing_tools/post_library/post_library.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// post_reorder_widget_test.dart drags a row rather than calling reorder().
//
// post_reorder_test.dart covers the model, and passed throughout a crash that
// only a real drag could produce. Reported after dragging a document to the
// bottom of a folder: the sidebar was replaced by a red error box reading
//
//   A _RenderLayoutBuilder was mutated in _RenderLayoutBuilder.performLayout
//
// The row's "more" button carried a Tooltip, which is an OverlayPortal.
// Reordering *moves* a row's element rather than rebuilding it -- every row
// carries a GlobalKey of ReorderableListView's own -- and reactivating an
// OverlayPortal that way re-attaches its overlay child during a layout pass,
// which the framework refuses outright.
//
// Two things about reproducing it are worth keeping, because a test missing
// either one passes against the bug:
//
//   - It needs a real pointer. The tooltip has to be *showing* for the portal
//     to have a child to re-attach, and it is showing because the pointer is
//     resting on the button -- which is where it has to rest to press and
//     hold. A synthetic touch drag never hovers, and never fails.
//   - It needs the shell: a Navigator, whose Overlay is what the tooltip
//     renders into, sitting inside a LayoutBuilder. That is the app (a page
//     inside the nested navigator, inside SecondarySideMenuLayout), and it is
//     what puts the Overlay's render tree under a layout the sidebar's
//     rebuild is running inside. A bare MaterialApp does not fail.
//
// So mount() below builds that shell rather than the widget on its own, and
// the hover case is the one that matters; the plain drags are here because
// they are what a reader will reach for first.

void main() {
  late Directory root;
  late PostLibraryModel library;
  late TextEditingController editor;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    root = await Directory.systemTemp.createTemp("bruig-reorder-widget");
    PostStorage.rootOverride = root.path;

    await PostStorage.createFolder("Error Checking");
    for (var name in ["Style guide test", "Spelling and Grammar check"]) {
      await PostStorage.write("Error Checking", name, "x");
    }
    await PostStorage.writeOrder(
        "Error Checking", ["Style guide test", "Spelling and Grammar check"]);

    library = PostLibraryModel();
    editor = TextEditingController();
    await library.openFolderNamed("Error Checking");
  });

  tearDown(() async {
    editor.dispose();
    library.dispose();
    PostStorage.rootOverride = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  List<String> names() => library.entries.map((e) => e.name).toList();

  /// mount puts the sidebar in the shape the app puts it in -- see the note
  /// at the top of this file on why the shell is load-bearing.
  Future<void> mount(WidgetTester tester) async {
    final Widget panel = SizedBox(
        width: 280, height: 500, child: PostSidebar(controller: editor));
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<PostLibraryModel>.value(value: library),
      ],
      child: MaterialApp(
        home: Scaffold(
          // SecondarySideMenuLayout's LayoutBuilder, and the page's own
          // Navigator inside it -- whose Overlay is where a tooltip in the
          // sidebar would go.
          body: LayoutBuilder(
            builder: (context, constraints) => Navigator(
              onGenerateRoute: (settings) =>
                  MaterialPageRoute<void>(builder: (context) => panel),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// dragRow holds the row's handle until the list takes the drag, moves it
  /// by [by], and lets go -- the gesture a reader actually makes.
  ///
  /// With [withMouse] the pointer arrives first and rests on the handle, as a
  /// real one does on the way to pressing it. That is what a touch drag
  /// cannot do, and what the crash needed.
  Future<void> dragRow(WidgetTester tester, int index, double by,
      {bool withMouse = false}) async {
    var handle = find.byIcon(Icons.more_vert).at(index);
    var at = tester.getCenter(handle);
    var gesture = await tester.createGesture(
        kind: withMouse ? PointerDeviceKind.mouse : PointerDeviceKind.touch);
    if (withMouse) {
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(at);
      // Long enough for anything hover puts on screen to be up.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }
    await gesture.down(at);
    // The handle is a delayed listener, so the drag only starts after a hold.
    await tester.pump(const Duration(milliseconds: 700));
    var step = by / 10;
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(0, step));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    if (withMouse) await gesture.removePointer();
  }

  testWidgets("dragging a document to the bottom moves it there",
      (tester) async {
    await mount(tester);
    expect(names(), ["Style guide test", "Spelling and Grammar check"]);

    await dragRow(tester, 0, 200);

    expect(tester.takeException(), isNull,
        reason: "the drop tore the sidebar down and left a red error box");
    expect(names(), ["Spelling and Grammar check", "Style guide test"]);
  });

  testWidgets("and the row that moved is drawn in its new place",
      (tester) async {
    await mount(tester);
    await dragRow(tester, 0, 200);

    // The list itself, not only the model behind it: the crash this covers
    // left the model correct and the sidebar replaced by an error box.
    var rows = find.descendant(
        of: find.byType(ReorderableListView), matching: find.byType(Text));
    expect(rows, findsWidgets);
    expect(
        tester
            .widgetList<Text>(rows)
            .map((t) => t.data)
            .whereType<String>()
            .toList(),
        containsAllInOrder(["Spelling and Grammar check", "Style guide test"]));
  });

  // The other direction, and the case where the drop lands where it started
  // -- the list still finishes its drop, and still must not be rebuilt into.
  testWidgets("dragging back up moves it back", (tester) async {
    await mount(tester);
    await dragRow(tester, 0, 200);
    expect(names().first, "Spelling and Grammar check");

    await dragRow(tester, 1, -200);
    expect(tester.takeException(), isNull);
    expect(names(), ["Style guide test", "Spelling and Grammar check"]);
  });

  testWidgets("a drag that goes nowhere leaves the list alone", (tester) async {
    await mount(tester);
    await dragRow(tester, 0, 4);

    expect(tester.takeException(), isNull);
    expect(names(), ["Style guide test", "Spelling and Grammar check"]);
  });

  // The reported crash, and the only one of these that ever caught it.
  testWidgets("dragging with the pointer resting on the handle survives",
      (tester) async {
    await mount(tester);
    await dragRow(tester, 0, 200, withMouse: true);

    expect(tester.takeException(), isNull,
        reason:
            "a hover-triggered overlay inside a reorderable row re-attaches "
            "itself mid-layout when the row moves, and takes the sidebar down "
            "with it");
    expect(names(), ["Spelling and Grammar check", "Style guide test"]);
  });

  // The rule the fix rests on, asserted directly: a row may own nothing that
  // lives in the Overlay. Stated here because the next person to want a
  // tooltip on that button will not read the comment above it first.
  testWidgets("a row owns no overlay of its own", (tester) async {
    await mount(tester);

    var rows = find.descendant(
        of: find.byType(ReorderableListView), matching: find.byType(Tooltip));
    expect(rows, findsNothing,
        reason: "a Tooltip is an OverlayPortal, and reordering reactivates it "
            "during layout -- see _rowButton");
  });

  // What the row tooltips used to say, said once where it cannot crash.
  testWidgets("the list says how to move a row", (tester) async {
    await mount(tester);
    expect(find.textContaining("Press and hold"), findsOneWidget);
  });
}
