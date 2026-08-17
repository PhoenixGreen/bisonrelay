import 'dart:io';

import 'package:bruig/plugin_system/writing_tools/notes/notes.dart';
import 'package:bruig/plugin_system/writing_tools/post_library/post_library.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// post_sidebar_stability_test.dart is about the sidebar sitting still.
//
// The reported symptom was a flicker: the whole document list twitched every
// time autosave ran, which while somebody is typing is every second or so.
//
// The cause was a widget that came and went. The saving spinner lived in
// _header, and _header returned null at the top level *unless* a save was in
// flight -- so each save inserted a row into the Column and removed it again a
// moment later, shoving everything below it down and back. Nothing was
// rebuilding wrongly and nothing was slow; a row simply existed for 200
// milliseconds at a time.
//
// So this test does not measure rebuilds. It measures where the first row is,
// which is what a reader was actually complaining about, and it would have
// failed on the old code by about forty pixels.

void main() {
  late Directory root;
  late PostLibraryModel library;
  late TextEditingController editor;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    root = await Directory.systemTemp.createTemp("bruig-sidebar-stability");
    PostStorage.rootOverride = root.path;

    for (var name in ["Draft one", "Draft two"]) {
      await PostStorage.write("", name, "x");
    }

    library = PostLibraryModel();
    editor = TextEditingController();
    library.watch(editor);
    await library.refresh();
  });

  tearDown(() async {
    editor.dispose();
    library.dispose();
    PostStorage.rootOverride = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// _real runs model work that touches the disk.
  ///
  /// testWidgets is a fake-async zone, where a dart:io future never completes
  /// on its own -- awaiting one of these directly hangs the test with no
  /// error at all. runAsync puts it back on the real event loop.
  Future<void> _real(WidgetTester tester, Future<void> Function() op) async {
    await tester.runAsync(op);
    await tester.pump();
  }

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<PostLibraryModel>.value(value: library),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
              width: 280, height: 500, child: PostSidebar(controller: editor)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets("a save in flight does not move the list", (tester) async {
    await mount(tester);
    var before = tester.getTopLeft(find.text("Draft one"));

    // The state the sidebar is in for the couple of hundred milliseconds after
    // every keystroke pause, which is the whole of the bug's window.
    await _real(tester, () => library.open(library.entries.first));
    editor.text = "something new";
    await tester.pump();
    // Fires the autosave debounce. The write itself is left in flight on
    // purpose -- "saving" staying true is exactly the state being asserted
    // against.
    await tester.pump(const Duration(seconds: 4));
    expect(library.saving, isTrue, reason: "the test never reached a save");

    expect(tester.getTopLeft(find.text("Draft one")), before,
        reason: "the list moved while a save was in flight");
  });

  testWidgets("the top level has no header to appear and disappear",
      (tester) async {
    await mount(tester);
    // The header's presence must depend only on which folder is open. At the
    // top level there is none, saving or not -- the nav icon above already
    // says which panel this is.
    expect(find.byIcon(Icons.arrow_back), findsNothing);

    await _real(tester, () => library.open(library.entries.first));
    editor.text = "something new";
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(library.saving, isTrue, reason: "the test never reached a save");
    expect(find.byIcon(Icons.arrow_back), findsNothing);
  });

  testWidgets("the reserved notes folder offers no way to remove it",
      (tester) async {
    await _real(tester, () async {
      await NoteStorage.write(
          NoteTarget.page("/manage/downloads", "Downloads"), "a note");
      await library.refresh();
    });
    await mount(tester);

    expect(find.text(notesFolderName), findsOneWidget);
    // No ⋮ on that row: it can be neither renamed, deleted nor dragged, so the
    // control that offers those is not drawn. Two documents plus the folder
    // would otherwise be three.
    expect(find.byIcon(Icons.more_vert), findsNWidgets(2));
  });
}
