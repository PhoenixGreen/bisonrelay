import 'dart:convert';
import 'dart:typed_data';

import 'package:bruig/models/resources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';

// page_partials_test.dart covers the reader's half of shared fragments.
//
// The Go side decides what to send (see client/resources/pages_test.go);
// this is what happens to --include[name]-- once it arrives. It has to
// survive the trip -- a fragment expanded before sending would cost the same
// as having no fragments at all -- and be filled in here from what this
// client already holds.

FetchedResource _page(String body) => FetchedResource(
      "alice",
      1,
      1,
      0,
      DateTime.now(),
      DateTime.now(),
      RMFetchResource(const ["index.md"], null, 0, null, 0, 0),
      RMFetchResourceReply(
          0, 200, null, Uint8List.fromList(utf8.encode(body)), 0, 0),
      "",
    );

void main() {
  group('finding what a page shares', () {
    test('names each fragment once, however often it appears', () {
      expect(partialNames("--include[nav]--\nx\n--include[nav]--"), ["nav"]);
    });

    test('finds several', () {
      var got = partialNames("--include[nav]--\n--include[footer]--");
      expect(got.toSet(), {"nav", "footer"});
    });

    test('a store template is not a fragment', () {
      // Go's {{...}} is expanded before anything is sent. Treating the two
      // as one mechanism would mean neither could be relied on.
      expect(partialNames("{{range .Products}}{{.Title}}{{end}}"), isEmpty);
    });

    test('the path matches what the server serves them from', () {
      expect(partialPath("nav"), ["partials", "nav.md"]);
    });
  });

  group('filling a page in', () {
    test('a held fragment is put in place of its marker', () {
      var s = PagesSession(1)
        ..partials = {"nav": "[Home](index.md)"}
        ..currentPage = _page("--include[nav]--\n# Home");

      expect(s.pageData(), contains("[Home](index.md)"));
      expect(s.pageData(), contains("# Home"));
      // The marker itself is consumed.
      expect(s.pageData(), isNot(contains("--include[")));
    });

    test('the same fragment fills every place it appears', () {
      var s = PagesSession(1)
        ..partials = {"r": "---"}
        ..currentPage = _page("--include[r]--\na\n--include[r]--");
      expect("---".allMatches(s.pageData()).length, 2);
    });

    test('one not yet arrived leaves nothing, not the marker', () {
      // The raw marker on screen reads as something the writer typed wrong.
      var s = PagesSession(1)..currentPage = _page("--include[nav]--\n# Home");
      expect(s.pageData(), isNot(contains("--include")));
      expect(s.pageData(), contains("# Home"));
    });

    test('a fragment naming itself does not loop', () {
      // Substitution is one pass on purpose. A second would never finish.
      var s = PagesSession(1)
        ..partials = {"loop": "before --include[loop]-- after"}
        ..currentPage = _page("--include[loop]--");
      expect(s.pageData(), contains("before"));
      expect(s.pageData(), contains("after"));
      expect(s.pageData(), contains("--include[loop]--"),
          reason: "left as written rather than expanded again");
    });

    test('a page with nothing shared is unchanged', () {
      var s = PagesSession(1)..currentPage = _page("# Just a page");
      expect(s.pageData().trim(), "# Just a page");
    });
  });

  group('a reply that is not text', () {
    test('does not take the viewer down', () {
      // A reply is whatever the other end sent. This used to throw a
      // FormatException out of the render and blank the screen; a page that
      // looks wrong is better than no screen at all.
      var s = PagesSession(1)
        ..currentPage = FetchedResource(
          "alice",
          1,
          1,
          0,
          DateTime.now(),
          DateTime.now(),
          RMFetchResource(const ["index.md"], null, 0, null, 0, 0),
          RMFetchResourceReply(
              0, 200, null, Uint8List.fromList([0x78, 0x9c, 0xff, 0xfe]), 0, 0),
          "",
        );

      expect(() => s.pageData(), returnsNormally);
    });

    test('an empty body reads as empty rather than throwing', () {
      var s = PagesSession(1);
      expect(s.pageData().trim(), isEmpty);
    });
  });
}
