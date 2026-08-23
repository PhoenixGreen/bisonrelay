import 'package:bruig/models/resources.dart';
import 'package:bruig/plugin_system/writing_tools/post_library/page_documents.dart';
import 'package:flutter_test/flutter_test.dart';

// page_partials_test.dart covers the reader's remaining half of shared
// fragments: the Writing preview.
//
// A page fetched from a site arrives with its fragments already in it -- the
// serving side fills them in, and client/resources/pages_test.go covers that.
// What is left here is a page being written, which is a document on this
// machine with the markers still in it: a preview showing those as themselves
// would be showing something no reader will ever see.

void main() {
  group('finding what a page shares', () {
    test('names each fragment once, however often it appears', () {
      expect(partialNames("--include[nav]--\nx\n--include[nav]--"), ["nav"]);
    });

    test('finds several', () {
      expect(partialNames("--include[nav]--\n--include[footer]--").toSet(),
          {"nav", "footer"});
    });

    test('a store template is not a fragment', () {
      // Go's {{...}} is a store's, expanded where the store is served.
      // Treating the two as one mechanism would mean neither could be
      // relied on.
      expect(partialNames("{{range .Products}}{{.Title}}{{end}}"), isEmpty);
    });

    test('the path matches what the server serves them from', () {
      // The name the serving side actually uses, not a copy of it: two
      // spellings of one directory is what this test exists to stop.
      expect(partialPath("nav"), [partialsSubdir, "nav.md"]);
      expect(partialsSubdir, "fragments");
    });

    test('is capped, as the serving side caps it', () {
      // A preview that showed more than a reader will ever see would be a
      // preview of a different page.
      var many = [
        for (var i = 0; i < 5000; i++) "--include[frag" + "$i" + "]--",
      ].join("\n");
      expect(partialNames(many), hasLength(maxPartialsPerPage));
    });
  });

  group('a name that is not a fragment', () {
    test('is not read as one', () {
      // The pattern is the strictest of the guards: a name with a dot or a
      // slash in it is not an include at all, so it stays on the page as the
      // text it is.
      for (var name in [
        "password.txt",
        "../../secret",
        "../secret",
        "a/b",
        "..",
        "nav.md",
        "/etc/passwd",
        "~/.ssh/id_rsa",
      ]) {
        expect(partialNames("--include[$name]--"), isEmpty, reason: name);
      }
    });

    test('and is left where it was written', () {
      expect(expandPartials("--include[password.txt]-- and text", const {}),
          contains("--include[password.txt]--"));
    });
  });

  group('filling a preview in', () {
    test('a held fragment is put in place of its marker', () {
      var got = expandPartials(
          "--include[nav]--\n# Home", {"nav": "[Home](index.md)"});
      expect(got, contains("[Home](index.md)"));
      expect(got, contains("# Home"));
      expect(got, isNot(contains("--include[")));
    });

    test('a fragment can hold another', () {
      // A header holding a navigation bar is the ordinary case, and the page
      // names only the header.
      var got = expandPartials("--include[header]--", {
        "header": "# Site\n--include[navigation]--",
        "navigation": "[Home](index.md)",
      });
      expect(got, contains("# Site"));
      expect(got, contains("[Home](index.md)"));
    });

    test('the same fragment fills every place it appears', () {
      var got = expandPartials("--include[r]--\na\n--include[r]--", {"r": "---"});
      expect("---".allMatches(got).length, 2);
    });

    test('one that is not there leaves nothing, not the marker', () {
      // The marker itself is not writing.
      var got = expandPartials("--include[nav]--\n# Home", const {});
      expect(got, isNot(contains("--include")));
      expect(got, contains("# Home"));
    });

    test('a fragment naming itself is left as written, not looped', () {
      var got = expandPartials(
          "--include[loop]--", {"loop": "before --include[loop]-- after"});
      expect(got, contains("before"));
      expect(got, contains("after"));
      // Visible, which is what tells the writer they have made a loop.
      expect(got, contains("--include[loop]--"));
    });

    test('two naming each other do not loop', () {
      var got = expandPartials("--include[a]--",
          {"a": "A --include[b]--", "b": "B --include[a]--"});
      expect(got, contains("A"));
      expect(got, contains("B"));
    });

    test('nesting is bounded, however deep the chain', () {
      var deep = {
        for (var i = 0; i < 40; i++) "p$i": "x --include[p${i + 1}]--",
      };
      expect(() => expandPartials("--include[p0]--", deep), returnsNormally);
      expect("x".allMatches(expandPartials("--include[p0]--", deep)).length,
          lessThanOrEqualTo(maxPartialDepth));
    });

    test('a page with nothing shared is unchanged', () {
      expect(expandPartials("# Just a page", const {}), "# Just a page");
    });
  });
}
