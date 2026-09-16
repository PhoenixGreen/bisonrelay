import 'dart:io';

import 'package:bruig/plugin_system/writing_tools/post_library/post_library.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// post_reorder_hint_test.dart is the line under the library list.
//
// Reported as a row jumping somewhere of its own accord: a document dragged
// down always landed on the last document, however much further it was taken.
// That is the boundary doing its job -- documents and folders are separate
// runs and stay that way -- but from the outside it reads as a fault, so the
// line says so where there is a boundary to hit.
//
// Two groups rather than one with a flag, because every bit of file I/O has
// to happen in setUp: a test body runs in a zone where a real disk read never
// completes, and the test hangs rather than failing. See
// [[bisonrelay-flutter-test-real-io]].

void main() {
  late Directory root;
  late PostLibraryModel library;
  late TextEditingController editor;

  Future<void> fixture({required bool withFolder}) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    root = await Directory.systemTemp.createTemp("bruig-hint");
    PostStorage.rootOverride = root.path;
    for (var name in ["One", "Two", "Three"]) {
      await PostStorage.write("", name, "x");
    }
    if (withFolder) await PostStorage.createFolder("Archive");
    library = PostLibraryModel();
    editor = TextEditingController();
    await library.refresh();
  }

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
              width: 280, height: 500, child: PostSidebar(controller: editor)),
        ),
      ),
    ));
    await tester.pump();
  }

  group("with folders as well as documents", () {
    setUp(() => fixture(withFolder: true));

    testWidgets("it says documents stay above them", (tester) async {
      await mount(tester);
      expect(find.textContaining("Documents stay above the folders"),
          findsOneWidget,
          reason: "a document dragged past the last one stops there, and "
              "nothing on screen said why");
    });
  });

  group("with documents only", () {
    setUp(() => fixture(withFolder: false));

    testWidgets("it does not, because there is no boundary to hit",
        (tester) async {
      await mount(tester);
      expect(
          find.textContaining("Documents stay above the folders"), findsNothing,
          reason: "explaining a boundary that is not there is noise");
      expect(find.textContaining("Press and hold"), findsOneWidget);
    });
  });
}
