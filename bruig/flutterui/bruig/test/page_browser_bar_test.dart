import 'dart:convert';
import 'dart:typed_data';

import 'package:bruig/models/resources.dart';
import 'package:bruig/screens/pages/browser.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

FetchedResource _page(List<String> path) => FetchedResource(
      "uid",
      1,
      1,
      0,
      DateTime.now(),
      DateTime.now(),
      RMFetchResource(path, null, 0, null, 0, 0),
      RMFetchResourceReply(0, 200, null, Uint8List.fromList(utf8.encode("x")), 0, 0),
      "",
    );

// page_browser_bar_test.dart covers the two pieces of the browser chrome
// that decide something rather than draw it: what the address reads, and
// what order the tabs sit in.

void main() {
  group('the address', () {
    test('reads as one, not as a sentence', () {
      // "Your site / about.md" read as three words and a file rather than
      // as somewhere you are.
      expect(pageAddress("Your site", "about.md"), "your_site/about.md");
    });

    test('a nick with spaces still makes one word', () {
      expect(pageAddress("Some One", "index.md"), "some_one/index.md");
      expect(pageAddress("a  b", "x"), "a_b/x");
    });

    test('an ordinary nick is left recognisable', () {
      expect(pageAddress("karamble", "index.md"), "karamble/index.md");
    });

    test('a path already has its own separators', () {
      expect(pageAddress("me", "assets/banner.png"), "me/assets/banner.png");
    });

    test('the front page is just the site', () {
      // No trailing slash with nothing after it.
      expect(pageAddress("Your site", ""), "your_site");
    });
  });

  group('the order tabs sit in', () {
    test('is the order they opened, until one is moved', () {
      expect(reorderTabs(const [], ["a", "b"]), ["a", "b"]);
    });

    test('a new tab goes on the end', () {
      // Where a new tab appears everywhere else.
      expect(reorderTabs(["b", "a"], ["a", "b", "c"]), ["b", "a", "c"]);
    });

    test('an arrangement survives opening another', () {
      // The point of the whole thing: dragging a tab left must not be
      // undone by the next page you open.
      expect(reorderTabs(["c", "a", "b"], ["a", "b", "c", "d"]),
          ["c", "a", "b", "d"]);
    });

    test('a closed tab drops out and the rest keep their places', () {
      expect(reorderTabs(["c", "a", "b"], ["a", "c"]), ["c", "a"]);
    });

    test('closing every tab leaves nothing', () {
      expect(reorderTabs(["a", "b"], const []), isEmpty);
    });

    test('a remembered tab that never reopens is forgotten', () {
      expect(reorderTabs(["a", "b"], ["b"]), ["b"]);
    });

    test('sections and pages are ordered together', () {
      // The strip is one strip, so a section can be dragged past a page.
      expect(reorderTabs([2, "page", 1], [1, 2, "page"]), [2, "page", 1]);
    });
  });

  group('the bar reads the session as it is now', () {
    // Back and forward move a cursor inside the session and tell the
    // session. Nothing else hears, and the bar was rebuilt only when the
    // models around the session changed -- so the page moved underneath a
    // bar that did not. The address went on naming the page just left, and
    // Forward stayed greyed because it was still reading the answer from
    // before Back was pressed.
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('the address follows Back, and Forward lights up',
        (tester) async {
      var session = PagesSession(1)
        ..currentPage = _page(["index.md"])
        ..currentPage = _page(["about.md"]);

      String pathOf(PagesSession s) =>
          (s.currentPage?.request.path ?? const []).join("/");

      await tester.pumpWidget(MultiProvider(providers: [
        ChangeNotifierProvider<ThemeNotifier>(create: (_) => ThemeNotifier()),
      ], child: MaterialApp(
          home: Scaffold(
              body: ListenableBuilder(
                  listenable: session,
                  builder: (context, _) => PageBrowserBar(
                        session: session,
                        sectionLabel: "",
                        nick: "Your site",
                        path: pathOf(session),
                        loading: false,
                        sidebarOpen: true,
                        onToggleSidebar: null,
                        onBack: session.goBack,
                        onForward: session.goForward,
                        onReload: () {},
                        onHome: () {},
                      ))))));
      await tester.pumpAndSettle();

      expect(find.text("your_site/about.md"), findsOneWidget);
      expect(
          tester
              .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.arrow_forward))
              .onPressed,
          isNull);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text("your_site/index.md"), findsOneWidget);
      expect(
          tester
              .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.arrow_forward))
              .onPressed,
          isNotNull);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_forward));
      await tester.pumpAndSettle();
      expect(find.text("your_site/about.md"), findsOneWidget);
    });
  });
}
