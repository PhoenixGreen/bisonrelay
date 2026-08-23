import 'dart:convert';
import 'dart:typed_data';

import 'package:bruig/components/pages_bar.dart';
import 'package:bruig/models/pages.dart';
import 'package:bruig/screens/pages/browser.dart';
import 'package:bruig/models/resources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:shared_preferences/shared_preferences.dart';

FetchedResource _page(String uid, List<String> path, String body) =>
    FetchedResource(
      uid,
      1,
      1,
      0,
      DateTime.now(),
      DateTime.now(),
      RMFetchResource(path, null, 0, null, 0, 0),
      RMFetchResourceReply(
          0, 200, null, Uint8List.fromList(utf8.encode(body)), 0, 0),
      "",
    );

void main() {
  // PagesModel reads its saved sort order on construction.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the same page arriving twice', () {
    // Appending it left Back moving from a page to itself, which looks
    // exactly like Back not working: one press did nothing you could see
    // and the next did the move. Reloading, previewing again, and a reply
    // for one of a page's sections landing when the page is no longer held
    // all deliver the same page a second time.
    test('is one entry, not two', () {
      var s = PagesSession(1)
        ..currentPage = _page("u", ["index.md"], "a")
        ..currentPage = _page("u", ["index.md"], "a again");
      expect(s.history, hasLength(1));
      expect(s.canGoBack, isFalse);
    });

    test('keeps the newer copy of it', () {
      // It is a fresh fetch: the point of reloading is to see what changed.
      var s = PagesSession(1)
        ..currentPage = _page("u", ["index.md"], "old")
        ..currentPage = _page("u", ["index.md"], "new");
      expect(utf8.decode(s.currentPage!.response.data!), "new");
    });

    test('one press of Back moves, from a page reloaded on arrival', () {
      var s = PagesSession(1)
        ..currentPage = _page("u", ["index.md"], "a")
        ..currentPage = _page("u", ["store"], "s")
        ..currentPage = _page("u", ["store"], "s again");
      s.goBack();
      expect(s.currentPage!.request.path, ["index.md"]);
    });

    test('a different page is still a new entry', () {
      var s = PagesSession(1)
        ..currentPage = _page("u", ["index.md"], "a")
        ..currentPage = _page("u", ["store"], "s");
      expect(s.history, hasLength(2));
      expect(s.canGoBack, isTrue);
    });

    test('the same path from someone else is a different page', () {
      var s = PagesSession(1)
        ..currentPage = _page("u", ["index.md"], "mine")
        ..currentPage = _page("them", ["index.md"], "theirs");
      expect(s.history, hasLength(2));
    });

    test('going back and forward is unaffected', () {
      var s = PagesSession(1)
        ..currentPage = _page("u", ["a.md"], "a")
        ..currentPage = _page("u", ["b.md"], "b");
      s.goBack();
      expect(s.canGoForward, isTrue);
      s.goForward();
      expect(s.currentPage!.request.path, ["b.md"]);
    });
  });

  group('a session\'s history', () {
    test('finds a page it already holds, by who serves it and what', () {
      var s = PagesSession(1)
        ..currentPage = _page("alice", ["index.md"], "front")
        ..currentPage = _page("alice", ["about.md"], "about");

      expect(s.findInHistory("alice", ["index.md"]), 0);
      expect(s.findInHistory("alice", ["about.md"]), 1);
      // Same path, different person, is a different page.
      expect(s.findInHistory("bob", ["index.md"]), isNull);
      expect(s.findInHistory("alice", ["missing.md"]), isNull);
    });

    test('finds the most recent copy when a page was visited twice', () {
      var s = PagesSession(1)
        ..currentPage = _page("alice", ["index.md"], "old")
        ..currentPage = _page("alice", ["about.md"], "about")
        ..currentPage = _page("alice", ["index.md"], "new");
      expect(s.findInHistory("alice", ["index.md"]), 2);
    });

    test('jumping shows the held page and leaves the history intact', () {
      var s = PagesSession(1)
        ..currentPage = _page("alice", ["index.md"], "front")
        ..currentPage = _page("alice", ["about.md"], "about");

      s.jumpTo(0);
      expect(s.pageData().trim(), "front");
      expect(s.canGoForward, isTrue, reason: "about is still ahead");
      expect(s.history.length, 2);
    });

    test('jumping out of range does nothing', () {
      var s = PagesSession(1)..currentPage = _page("a", ["index.md"], "one");
      s.jumpTo(5);
      s.jumpTo(-1);
      expect(s.pageData().trim(), "one");
    });

    test('a new page after a jump truncates what was ahead', () {
      // Same rule the Back button already follows: going somewhere new from
      // part-way back drops the forward history rather than branching.
      var s = PagesSession(1)
        ..currentPage = _page("a", ["index.md"], "one")
        ..currentPage = _page("a", ["two.md"], "two");
      s.jumpTo(0);
      s.currentPage = _page("a", ["three.md"], "three");
      expect(s.history.length, 2);
      expect(s.canGoForward, isFalse);
    });
  });

  group('openPageLabel', () {
    test('a front page is named by whose site it is', () {
      expect(openPageLabel("alice", ["index.md"]), "alice");
      expect(openPageLabel("alice", []), "alice");
      expect(openPageLabel("alice", [""]), "alice");
    });

    test('anything else names the page too', () {
      // The nick alone stops being enough the moment two pages of the same
      // person's are open, which is the case the sidebar list exists for.
      expect(openPageLabel("alice", ["about.md"]), "alice / about");
      expect(openPageLabel("alice", ["blog", "first-post.md"]),
          "alice / first-post");
    });

    test('a path with no extension is left as it is', () {
      expect(openPageLabel("store", ["cart"]), "store / cart");
    });
  });

  group('PagesModel navigation', () {
    test('choosing a tab leaves the browser without closing the page', () {
      var m = PagesModel(ResourcesModel(runStream: false))
        ..browsing = true
        ..tab = pagesTabVisit;

      // Re-choosing the tab already selected still has to leave the
      // browser: the tab is what was tapped, and it was doing nothing.
      m.browsing = true;
      m.tab = pagesTabVisit;
      expect(m.browsing, isFalse);
      expect(m.tab, pagesTabVisit);
    });

    test('a different tab also leaves the browser', () {
      var m = PagesModel(ResourcesModel(runStream: false))..browsing = true;
      m.tab = pagesTabStore;
      expect(m.browsing, isFalse);
      expect(m.tab, pagesTabStore);
    });
  });

  group('the sidebar setting', () {
    test('starts open and stays where it is put', () async {
      var m = PagesModel(ResourcesModel(runStream: false));
      expect(m.sidebarOpen, isTrue);

      m.sidebarOpen = false;
      // Opening a page, moving between pages and changing section all used
      // to reopen it. The setting is the reader's, not the screen's.
      m.browsing = true;
      m.tab = pagesTabStore;
      m.browsing = true;
      expect(m.sidebarOpen, isFalse);
    });

    test('survives a restart', () async {
      SharedPreferences.setMockInitialValues({});
      PagesModel(ResourcesModel(runStream: false)).sidebarOpen = false;
      // Let the write land before reading it back.
      await Future<void>.delayed(Duration.zero);

      var next = PagesModel(ResourcesModel(runStream: false));
      await Future<void>.delayed(Duration.zero);
      expect(next.sidebarOpen, isFalse);
    });
  });

  group('closing a session', () {
    test('moves to the tab on the right', () {
      var r = ResourcesModel(runStream: false);
      var a = r.session(1), b = r.session(2);
      r.session(3);
      r.mostRecent = a;

      r.closeSession(1);
      expect(r.sessions.length, 2);
      expect(identical(r.mostRecent, b), isTrue);
    });

    test('moves to the left when the one closed was the last', () {
      var r = ResourcesModel(runStream: false);
      r.session(1);
      var b = r.session(2), c = r.session(3);
      r.mostRecent = c;

      r.closeSession(3);
      expect(identical(r.mostRecent, b), isTrue);
    });

    test('closing the only page leaves nothing on screen', () {
      // Which is what sends the area back to the contact list.
      var r = ResourcesModel(runStream: false);
      var a = r.session(1);
      r.mostRecent = a;

      r.closeSession(1);
      expect(r.sessions, isEmpty);
      expect(r.mostRecent, isNull);
    });

    test('closing one that is not on screen leaves the current one alone', () {
      var r = ResourcesModel(runStream: false);
      r.session(1);
      var b = r.session(2);
      r.mostRecent = b;

      r.closeSession(1);
      expect(identical(r.mostRecent, b), isTrue);
    });

    test('closing something already gone is not an error', () {
      var r = ResourcesModel(runStream: false);
      r.closeSession(99);
      expect(r.sessions, isEmpty);
    });
  });

  group('sections as tabs', () {
    test('opening one gives it a tab, and Visit never gets one', () {
      var m = PagesModel(ResourcesModel(runStream: false));
      expect(m.openSections, isEmpty);

      m.tab = pagesTabMySite;
      expect(m.openSections, {pagesTabMySite});

      // Visit is where a page or a section is opened from -- a tab for it
      // would be a tab for "no tab".
      m.tab = pagesTabVisit;
      expect(m.openSections, {pagesTabMySite});
    });

    test('both can be open at once', () {
      var m = PagesModel(ResourcesModel(runStream: false))
        ..tab = pagesTabMySite
        ..tab = pagesTabStore;
      expect(m.openSections, {pagesTabMySite, pagesTabStore});
      expect(m.tab, pagesTabStore);
    });

    test('closing one only takes its tab away', () {
      // Where to go next is not this model's to decide: the other tabs may
      // be pages, which belong to ResourcesModel. See nextTabAfterClosing.
      var m = PagesModel(ResourcesModel(runStream: false))
        ..tab = pagesTabStore;
      m.closeSection(pagesTabStore);
      expect(m.openSections, isEmpty);
    });

    test('closing one being left alone does not move the reader', () {
      var m = PagesModel(ResourcesModel(runStream: false))
        ..tab = pagesTabMySite
        ..tab = pagesTabStore;
      m.closeSection(pagesTabMySite);
      expect(m.tab, pagesTabStore);
    });

    group('which tab takes its place', () {
      // Closing one of several used to drop the whole area back to Visit
      // while its neighbours sat there untouched -- and only if it was a
      // section. A page did not do that, so the two kinds of tab behaved
      // differently for no reason a reader could see.
      test('the one now in its position', () {
        expect(nextTabAfterClosing(["a", "b", "c"], 0), "b");
        expect(nextTabAfterClosing(["a", "b", "c"], 1), "c");
      });

      test('the last, when the last was closed', () {
        expect(nextTabAfterClosing(["a", "b", "c"], 2), "b");
      });

      test('nothing, only when it was the only one', () {
        expect(nextTabAfterClosing(["a"], 0), isNull);
      });

      test('a tab that is not there closes nothing', () {
        expect(nextTabAfterClosing(["a", "b"], -1), isNull);
        expect(nextTabAfterClosing(["a", "b"], 5), isNull);
      });

      test('sections and pages are not told apart', () {
        // The strip shows one list, so the rule has to be one rule.
        expect(nextTabAfterClosing([pagesTabMySite, "page"], 0), "page");
        expect(nextTabAfterClosing(["page", pagesTabStore], 0), pagesTabStore);
      });
    });

    test('reopening a section already open still selects it', () {
      // It has a tab and the reader is elsewhere; clicking it has to come
      // back to it rather than do nothing.
      var m = PagesModel(ResourcesModel(runStream: false))
        ..tab = pagesTabMySite
        ..tab = pagesTabVisit;
      m.tab = pagesTabMySite;
      expect(m.tab, pagesTabMySite);
    });

    test('closing something that was never open is not an error', () {
      var m = PagesModel(ResourcesModel(runStream: false));
      m.closeSection(pagesTabStore);
      expect(m.tab, pagesTabVisit);
    });
  });
}
