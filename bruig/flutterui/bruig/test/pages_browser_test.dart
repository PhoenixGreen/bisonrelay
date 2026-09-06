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
IconButton _button(WidgetTester tester, String tooltip) =>
    tester.widget<IconButton>(find.ancestor(
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
            sidebarOpen: false,
            onToggleSidebar: () {},
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
        sidebarOpen: false,
        onToggleSidebar: () {},
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

  group('sortSites', () {
    var t0 = DateTime(2026, 8, 19, 12, 0);
    ({String nick, SiteInfo info}) c(String nick, SiteStatus st, [int? mins]) =>
        (
          nick: nick,
          info: SiteInfo(
              status: st,
              lastSeen:
                  mins == null ? null : t0.subtract(Duration(minutes: mins)))
        );

    List<String> order(List<({String nick, SiteInfo info})> items,
        [PagesSort mode = PagesSort.sitesFirst]) {
      var l = List.of(items);
      sortSites(l, mode, nick: (e) => e.nick, info: (e) => e.info);
      return l.map((e) => e.nick).toList();
    }

    test('sites come before everything else, whatever their nick', () {
      expect(
          order([
            c("aaa", SiteStatus.notHosting, 1),
            c("zzz", SiteStatus.hosting, 500),
          ]),
          ["zzz", "aaa"]);
    });

    test('within the same status, most recently heard from wins', () {
      expect(
          order([
            c("old", SiteStatus.hosting, 6000),
            c("recent", SiteStatus.hosting, 5),
            c("mid", SiteStatus.hosting, 300),
          ]),
          ["recent", "mid", "old"]);
    });

    test('a contact never heard from sorts after those who have been', () {
      expect(
          order([
            c("never", SiteStatus.hosting),
            c("ancient", SiteStatus.hosting, 99999),
          ]),
          ["ancient", "never"]);
    });

    test('an inference of no site outranks a definite one, and both sink', () {
      // Nothing known beats probably-nothing, which beats their own answer
      // that they serve nothing.
      expect(
          order([
            c("said-no", SiteStatus.notHosting, 1),
            c("probably-no", SiteStatus.silent, 1),
            c("unknown", SiteStatus.unknown, 1),
          ]),
          ["unknown", "probably-no", "said-no"]);
    });

    test('ties break on nick, so the list does not shuffle as it redraws', () {
      var items = [
        c("Bravo", SiteStatus.unknown),
        c("alpha", SiteStatus.unknown),
      ];
      expect(order(items), ["alpha", "Bravo"]);
      expect(order(items), ["alpha", "Bravo"]);
    });

    test('name mode ignores status entirely', () {
      expect(
          order([
            c("zed", SiteStatus.hosting, 1),
            c("amy", SiteStatus.notHosting),
          ], PagesSort.name),
          ["amy", "zed"]);
    });
  });

  group('noAnswerDetail', () {
    test('names both reasons, since neither can be ruled out', () {
      var d = noAnswerDetail("alice");
      expect(d, contains("not online"));
      expect(d, contains("host nothing"));
      expect(d, contains("alice"));
      // The old copy asserted only the queued explanation, which read as
      // though the page were about to arrive.
      expect(d.startsWith("The request is still queued"), isFalse);
    });
  });

  group('SiteStatus recheck', () {
    test('offers another try for every inconclusive outcome', () {
      expect(SiteStatus.unknown.rechecking, isTrue);
      expect(SiteStatus.noAnswer.rechecking, isTrue);
      expect(SiteStatus.silent.rechecking, isTrue);
      expect(SiteStatus.failed.rechecking, isTrue);
      // A definite answer is not worth asking again for.
      expect(SiteStatus.hosting.rechecking, isFalse);
      expect(SiteStatus.notHosting.rechecking, isFalse);
      expect(SiteStatus.noIndex.rechecking, isFalse);
      expect(SiteStatus.checking.rechecking, isFalse);
    });

    test('silence is evidence, so it stays visitable', () {
      // A contact heard from since the request went out probably hosts
      // nothing -- but that is an inference, not their answer.
      expect(SiteStatus.silent.visitable, isTrue);
      expect(SiteStatus.silent.label, "Probably no site");
    });
  });

  group('pageOwnerName', () {
    test('names the reader own site rather than showing their public id', () {
      // The reader has no chat with themselves, so getNick returns nothing
      // and the address bar would otherwise read as 64 hex characters on the
      // page they open most.
      expect(pageOwnerName("me", "me", ""), "Your site");
      expect(pageOwnerName("them", "me", "alice"), "alice");
      // A contact with no nick still has to be identifiable.
      expect(pageOwnerName("abc123", "me", ""), "abc123");
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
