import 'package:bruig/plugin_system/writing_tools/post_library/post_library.dart';
import 'package:flutter_test/flutter_test.dart';

// page_documents_test.dart covers where a page stands relative to the site.
//
// The document in the library is the one thing anybody edits; the file in
// the served directory is output. They are allowed to differ, and that
// difference is the feature -- it is the gap between what is published and
// what is being written -- so what matters is that the gap is reported
// accurately.

void main() {
  group('pagePublishState', () {
    test('nothing served is a draft', () {
      expect(pagePublishState(null, "anything"), PagePublishState.draft);
      // Including an empty document, which is still not published.
      expect(pagePublishState(null, ""), PagePublishState.draft);
    });

    test('the same text either side is published and current', () {
      expect(pagePublishState("# Hi", "# Hi"), PagePublishState.published);
    });

    test('any difference is edited since publishing', () {
      expect(pagePublishState("# Hi", "# Hi "), PagePublishState.edited);
      expect(pagePublishState("# Hi", ""), PagePublishState.edited);
      // Published-but-emptied is still published: something is being served.
      expect(pagePublishState("", "# Hi"), PagePublishState.edited);
    });

    test('a published empty page that matches is current', () {
      expect(pagePublishState("", ""), PagePublishState.published);
    });

    test('only a draft is not live', () {
      // Live means a visitor can fetch something, not that it is current.
      expect(PagePublishState.draft.live, isFalse);
      expect(PagePublishState.published.live, isTrue);
      expect(PagePublishState.edited.live, isTrue,
          reason: "the older version is still being served");
    });
  });

  group('names', () {
    test('the library drops the extension, the site keeps it', () {
      expect(pageFileNameFor("about"), "about.md");
      expect(documentNameFor("about.md"), "about");
    });

    test('a name that already has one is not given a second', () {
      expect(pageFileNameFor("about.md"), "about.md");
      expect(documentNameFor("about"), "about");
    });

    test('they round-trip', () {
      for (var n in ["about", "index", "a.b", "notes.md"]) {
        expect(documentNameFor(pageFileNameFor(n)), documentNameFor(n));
      }
    });
  });

  group('the front page', () {
    test('is recognised by either name', () {
      const doc = PageDocument(name: "index", state: PagePublishState.draft);
      expect(doc.isIndex, isTrue);
      const withExt =
          PageDocument(name: "index.md", state: PagePublishState.draft);
      expect(withExt.isIndex, isTrue);
    });

    test('is not just any page starting with index', () {
      const doc =
          PageDocument(name: "index-old", state: PagePublishState.draft);
      expect(doc.isIndex, isFalse);
    });
  });
}
