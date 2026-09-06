import 'dart:io';

import 'package:bruig/plugin_system/writing_tools/post_library/post_library.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// post_entry_menu_test.dart covers what a document's own menu offers.
//
// The menu is where a document can be unmade by accident, so what it leaves
// out matters as much as what it has. A document belonging to the site is
// what it is because of the folder it is in: a page is a page because it is
// in Pages, and a fragment is one because it is in Fragments, which is where
// --include[name]-- goes looking. Moving either out is not filing it
// somewhere, it is quietly turning it into an ordinary draft and breaking
// whatever pointed at it.

void main() {
  late Directory root;
  late PostLibraryModel library;
  late TextEditingController editor;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    root = await Directory.systemTemp.createTemp("bruig-entry-menu");
    PostStorage.rootOverride = root.path;

    await PostStorage.write("", "A draft", "x");
    await PostStorage.write(pagesFolderName, "About", "x");
    await PostStorage.write(partialsFolderName, "header", "x");

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
              width: 320, height: 620, child: PostSidebar(controller: editor)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// menuFor opens one document's menu and returns what it offers.
  Future<List<String>> menuFor(
      WidgetTester tester, String folder, String name) async {
    await tester.runAsync(() => library.openFolderNamed(folder));
    await tester.pump();
    await mount(tester);

    var row =
        find.ancestor(of: find.text(name), matching: find.byType(InkWell));
    await tester.tap(
        find.descendant(of: row.first, matching: find.byIcon(Icons.more_vert)));
    await tester.pumpAndSettle();

    var items = find
        .byType(PopupMenuItem<String>)
        .evaluate()
        .map((e) => ((e.widget as PopupMenuItem<String>).child as Text).data!)
        .toList();
    // Closed again, or the next pump finds two menus.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    return items;
  }

  testWidgets('a fragment cannot be moved out of Fragments', (tester) async {
    var items = await menuFor(tester, partialsFolderName, "header");
    expect(items, isNot(contains("Move to...")));
    // Still renameable and deletable: a fragment nobody includes is just a
    // document, and its name is the name pages call it by.
    expect(items, contains("Rename"));
    expect(items, contains("Delete"));
  });

  testWidgets('nor a page out of Pages', (tester) async {
    var items = await menuFor(tester, pagesFolderName, "About");
    expect(items, isNot(contains("Move to...")));
  });

  testWidgets('an ordinary draft can still be filed', (tester) async {
    // The guard has to be about the site's folders and not about documents
    // in general, or filing stops working everywhere.
    var items = await menuFor(tester, "", "A draft");
    expect(items, contains("Move to..."));
  });
}
