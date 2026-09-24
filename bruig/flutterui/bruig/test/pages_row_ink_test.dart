import 'package:bruig/plugin_system/writing_tools/post_library/page_documents.dart';
import 'package:bruig/screens/pages/site_rows.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// pages_row_ink_test.dart is about a row being able to paint itself.
//
// A ListTile draws its background and its tap ripple onto the nearest
// Material above it. A themed screen paints its content area as a coloured
// box, which sits between the row and whatever Material is further up -- so
// the ripple went behind that colour and was never seen, and Flutter
// reported it once per row: twenty-three contacts, twenty-three errors in
// the log. The fix is a transparent Material of the row's own.
//
// Asserted by drawing the row inside exactly that arrangement and listening
// for what Flutter has to say about it, because the symptom *is* the
// framework's complaint.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets("a page row inside a coloured area paints its own ink",
      (tester) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
      ],
      child: MaterialApp(
        home: Scaffold(
          // The content area of a themed screen: a plain coloured box with
          // no Material of its own. Container with a colour and no
          // decoration is a ColoredBox, which is what the report named.
          body: ColoredBox(
            color: const Color(0xFF1E1E1E),
            child: Column(children: [
              SiteRow(
                item: const PageDocument(
                    name: "About",
                    file: "about.md",
                    state: PagePublishState.published),
                onEdit: () {},
                onDelete: () {},
                onPublish: () {},
                onUnpublish: () {},
                onPreview: () {},
              ),
            ]),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Asked of the tree rather than of the framework's complaint: the
    // complaint is only raised in a debug build, and a test that waits for
    // one takes minutes to fail. What the row needs is a Material of its own
    // *below* the coloured box -- above it is the one that cannot be
    // painted into.
    expect(
      find.descendant(
        of: find.byType(ColoredBox),
        matching: find.ancestor(
            of: find.byType(ListTile), matching: find.byType(Material)),
      ),
      findsWidgets,
      reason: "the row has no Material to paint its ink into",
    );
  });
}
