import 'dart:convert';
import 'dart:typed_data';

import 'package:bruig/models/pages.dart';
import 'package:bruig/models/resources.dart';
import 'package:bruig/screens/pages/browser.dart';
import 'package:bruig/screens/pages/visit.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// pages_browser_test.dart drives the Pages browser's chrome and the session
// behind it.
//
// The controls are rendered and tapped rather than the model being called
// directly: a back button whose handler throws, or which is wired to nothing,
// passes every test that only asks PagesSession whether it can go back (see
// the icon-picker and chat-header failures that prompted this).
//
// PageBrowser itself is out of reach -- it resolves a ClientModel to look up
// a nick, and constructing one loads golib.dylib. Its chrome and its status
// pages are separate widgets for exactly that reason, and those are here.

// byTooltip finds the Tooltip an IconButton builds, not the button itself,
// so the button is reached through it.
IconButton _button(WidgetTester tester, String tooltip) => tester.widget<IconButton>(
    find.ancestor(
        of: find.byTooltip(tooltip), matching: find.byType(IconButton)));

FetchedResource _page(String uid, List<String> path, String body,
    {int status = 200}) {
  return FetchedResource(
    uid,
    1,
    1,
    0,
    DateTime.now(),
    DateTime.now(),
    RMFetchResource(path, null, 0, null, 0, 0),
    RMFetchResourceReply(
        0, status, null, Uint8List.fromList(utf8.encode(body)), 0, 0),
    "",
  );
}

Widget _host(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PagesSession history', () {
    test('navigating builds history that back and forward walk', () {
      var sess = PagesSession(1);
      expect(sess.canGoBack, isFalse);
      expect(sess.canGoForward, isFalse);

      sess.currentPage = _page("u1", ["index.md"], "front");
      expect(sess.canGoBack, isFalse);

      sess.currentPage = _page("u1", ["about.md"], "about");
      expect(sess.canGoBack, isTrue);
      expect(sess.canGoForward, isFalse);

      sess.goBack();
      expect(sess.pageData(), contains("front"));
      expect(sess.canGoBack, isFalse);
      expect(sess.canGoForward, isTrue);

      sess.goForward();
      expect(sess.pageData(), contains("about"));
      expect(sess.canGoForward, isFalse);
    });

    test('navigating after going back drops the forward entries', () {
      var sess = PagesSession(1);
      sess.currentPage = _page("u1", ["index.md"], "front");
      sess.currentPage = _page("u1", ["about.md"], "about");
      sess.goBack();

      sess.currentPage = _page("u1", ["contact.md"], "contact");
      expect(sess.canGoForward, isFalse);
      expect(sess.history.length, 2);
      expect(sess.pageData(), contains("contact"));
    });

    test('an async section update does not become a history entry', () {
      var sess = PagesSession(1);
      sess.currentPage = _page("u1", ["index.md"], "front");
      var before = sess.history.length;

      sess.replaceCurrentPage(_page("u1", ["index.md"], "front, filled in"));

      expect(sess.history.length, before);
      expect(sess.canGoBack, isFalse);
      expect(sess.pageData(), contains("filled in"));
    });
  });

  group('PageBrowserBar', () {
    testWidgets('back and forward move the session and disable at the ends',
        (tester) async {
      var sess = PagesSession(1);
      sess.currentPage = _page("u1", ["index.md"], "front");
      sess.currentPage = _page("u1", ["about.md"], "about");

      Widget bar() => _host(PageBrowserBar(
            session: sess,
            nick: "alice",
            path: "about.md",
            loading: false,
            onBack: sess.goBack,
            onForward: sess.goForward,
            onReload: () {},
            onHome: () {},
          ));

      await tester.pumpWidget(bar());

      // Forward is at the end of history, so it must be dead.
      expect(_button(tester, "Forward").onPressed, isNull);

      await tester.tap(find.byTooltip("Back"));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(sess.pageData(), contains("front"));

      await tester.pumpWidget(bar());
      expect(_button(tester, "Back").onPressed, isNull);
      expect(_button(tester, "Forward").onPressed, isNotNull);
    });

    testWidgets('reload is disabled while a request is out', (tester) async {
      var sess = PagesSession(1);
      sess.currentPage = _page("u1", ["index.md"], "front");

      await tester.pumpWidget(_host(PageBrowserBar(
        session: sess,
        nick: "alice",
        path: "index.md",
        loading: true,
        onBack: () {},
        onForward: () {},
        onReload: () {},
        onHome: () {},
      )));

      expect(_button(tester, "Reload").onPressed, isNull);
      expect(find.textContaining("alice"), findsOneWidget);
    });
  });

  group('PageStatusMessage', () {
    // The point of the whole not-hosting status: a visitor must be able to
    // tell "no site" from "no such page" from a request that went nowhere.
    testWidgets('tells no-site apart from no-such-page', (tester) async {
      await tester.pumpWidget(_host(const PageStatusMessage(
          status: 501, nick: "alice", path: "index.md")));
      expect(find.text("No site"), findsOneWidget);
      expect(find.textContaining("not hosting"), findsOneWidget);

      await tester.pumpWidget(_host(const PageStatusMessage(
          status: 404, nick: "alice", path: "about.md")));
      expect(find.text("No such page"), findsOneWidget);
      expect(find.textContaining("is hosting"), findsOneWidget);

      await tester.pumpWidget(_host(const PageStatusMessage(
          status: 418, nick: "alice", path: "about.md")));
      expect(find.text("Status 418"), findsOneWidget);
    });
  });

  group('SiteStatus', () {
    test('reply statuses map to what the visitor is told', () {
      expect(siteStatusForReply(200), SiteStatus.hosting);
      expect(siteStatusForReply(404), SiteStatus.noIndex);
      expect(siteStatusForReply(501), SiteStatus.notHosting);
      expect(siteStatusForReply(400), SiteStatus.failed);
    });

    test('only a definite "serves nothing" makes a site unvisitable', () {
      // An unanswered request may still be delivered, so it must not stop
      // the visitor trying.
      expect(SiteStatus.noAnswer.visitable, isTrue);
      expect(SiteStatus.unknown.visitable, isTrue);
      expect(SiteStatus.noIndex.visitable, isTrue);
      expect(SiteStatus.notHosting.visitable, isFalse);
    });
  });

  group('relativeTime', () {
    test('reads as a person would say it', () {
      var now = DateTime(2026, 8, 19, 12, 0);
      expect(relativeTime(now.subtract(const Duration(seconds: 20)), now: now),
          "just now");
      expect(relativeTime(now.subtract(const Duration(minutes: 5)), now: now),
          "5m ago");
      expect(relativeTime(now.subtract(const Duration(hours: 3)), now: now),
          "3h ago");
      expect(relativeTime(now.subtract(const Duration(days: 2)), now: now),
          "2d ago");
      expect(relativeTime(now.subtract(const Duration(days: 60)), now: now),
          "2mo ago");
      // A clock that disagrees must not produce "in 3 hours".
      expect(relativeTime(now.add(const Duration(hours: 3)), now: now),
          "just now");
    });
  });
}
