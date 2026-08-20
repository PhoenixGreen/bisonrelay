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

  group('the link a page is reached by', () {
    test('has no spaces, because a space ends a Markdown link', () {
      // "[x](Test Page.md)" links to "Test" and leaves "Page.md)" as text.
      expect(pageSlug("Test Page"), "test_page");
      expect(pageFileNameFor("Test Page"), "test_page.md");
    });

    test('is lowercased, so the writer need not recall the capitals', () {
      expect(pageSlug("About Me"), "about_me");
      expect(pageSlug("ABOUT"), "about");
    });

    test('collapses runs and trims the ends', () {
      expect(pageSlug("a - b"), "a_b");
      expect(pageSlug("  spaced  "), "spaced");
      expect(pageSlug("!!!leading"), "leading");
    });

    test('drops an extension the writer typed rather than doubling it', () {
      expect(pageFileNameFor("about.md"), "about.md");
    });

    test('a name of nothing but punctuation still gets a link', () {
      // It has to be reachable by something.
      expect(pageSlug("???"), "page");
      expect(pageSlug(""), "page");
    });

    test('two names can slug to one link, which is why conflicts exist', () {
      expect(pageSlug("Test Page"), pageSlug("test-page"));
    });
  });

  group('the front page', () {
    test('is recognised by either name', () {
      const doc = PageDocument(name: "index", state: PagePublishState.draft);
      expect(doc.isIndex, isTrue);
      const withExt =
          PageDocument(name: "index.md", state: PagePublishState.draft);
      expect(withExt.isIndex, isTrue);
      // However it was capitalised.
      const caps = PageDocument(name: "Index", state: PagePublishState.draft);
      expect(caps.isIndex, isTrue);
    });

    test('is not just any page starting with index', () {
      const doc =
          PageDocument(name: "index-old", state: PagePublishState.draft);
      expect(doc.isIndex, isFalse);
    });
  });
}
