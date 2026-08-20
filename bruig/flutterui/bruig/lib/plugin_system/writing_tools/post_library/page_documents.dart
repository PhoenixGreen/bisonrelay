import 'package:bruig/models/pages.dart';
import 'package:bruig/plugin_system/writing_tools/post_library/post_storage.dart';

// page_documents.dart is the join between the post library and the site.
//
// A page is written as an ordinary document in the library's reserved Pages
// folder, and published by copying it into the directory the client serves.
// The document is the one thing anybody edits; the served file is output,
// never read back and never edited in place.
//
// The two are allowed to differ, and that difference is the point: it is the
// gap between what is published and what is being written. Editing a live
// page therefore costs a visitor nothing -- they go on reading the last
// published version until the writer says otherwise -- and a session that
// ends in a crash leaves the site exactly as it was.

/// PagePublishState is where a document stands relative to the site.
enum PagePublishState {
  /// Written, never published. Nobody can fetch it.
  draft,

  /// Published, and the served copy is what the document says.
  published,

  /// Published, but written since. Visitors are reading the older version.
  edited,
}

extension PagePublishStateLabel on PagePublishState {
  String get label {
    switch (this) {
      case PagePublishState.draft:
        return "Not published";
      case PagePublishState.published:
        return "Published";
      case PagePublishState.edited:
        return "Edited since publishing";
    }
  }

  /// live is whether a visitor can fetch anything at all for this page.
  bool get live => this != PagePublishState.draft;
}

/// pagePublishState compares a document with what is being served for it.
///
/// [served] is null when nothing is published under that name.
///
/// Deliberately compares content rather than modification times. Publishing
/// copies the document, which sets the copy's time to now -- so the times
/// agree the instant a page is published and say nothing about it ever
/// after. Pages are small; comparing them costs nothing worth counting.
PagePublishState pagePublishState(String? served, String document) {
  if (served == null) return PagePublishState.draft;
  return served == document
      ? PagePublishState.published
      : PagePublishState.edited;
}

/// pageSlug reduces a document's name to what goes in a link.
///
/// A page called "Test Page" is served as "test_page.md" and linked as
/// "[...](test_page.md)". The document keeps the name the writer gave it,
/// because that is what belongs in a sidebar; the link does not, because a
/// space in a Markdown link ends it -- "[x](Test Page.md)" links to "Test"
/// and leaves "Page.md)" as text.
///
/// Lowercased for the same reason: the writer types the link by hand and
/// should not have to remember which words they capitalised, and two
/// filesystems disagree about whether "About.md" and "about.md" are the same
/// file.
String pageSlug(String documentName) {
  var name = documentName.endsWith(".md")
      ? documentName.substring(0, documentName.length - 3)
      : documentName;
  var out = StringBuffer();
  for (var rune in name.trim().toLowerCase().runes) {
    var c = String.fromCharCode(rune);
    var ok = (rune >= 0x30 && rune <= 0x39) || // 0-9
        (rune >= 0x61 && rune <= 0x7A); // a-z
    out.write(ok ? c : "_");
  }
  // Collapse the runs the substitution makes, so "a - b" is "a_b" rather
  // than "a___b", and trim the ones at the ends.
  var slug = out
      .toString()
      .replaceAll(RegExp(r'_+'), "_")
      .replaceAll(RegExp(r'^_+|_+$'), "");
  // Everything was punctuation. A page still needs a name to be linked by.
  return slug.isEmpty ? "page" : slug;
}

/// pageFileNameFor is the file a library document is published as.
///
/// The library holds names as the writer typed them, because that is what a
/// reader wants to see in a sidebar; the site serves a slug with ".md" on
/// it, because that is what has to survive being written into a link.
String pageFileNameFor(String documentName) => "${pageSlug(documentName)}.md";

/// documentNameFor is the name to show for a file.
///
/// Not [pageFileNameFor] backwards -- it cannot be, because slugging throws
/// away the capitals and spaces. It is only used for a file being served
/// with no document behind it, where the filename is all there is to go on.
String documentNameFor(String fileName) => fileName.endsWith(".md")
    ? fileName.substring(0, fileName.length - 3)
    : fileName;

/// PageDocument is one page of the site, as the writer sees it.
class PageDocument {
  /// name is the library name, without ".md".
  final String name;
  final PagePublishState state;
  final DateTime? modified;

  const PageDocument({
    required this.name,
    required this.state,
    this.modified,
    this.conflict = false,
  });

  /// link is what another page writes to reach this one.
  String get link => pageFileNameFor(name);

  /// conflict is true when another document publishes to the same file.
  ///
  /// Two names can slug to one link -- "Test Page" and "test-page" both
  /// become "test_page.md" -- and publishing the second would quietly
  /// replace the first. Worth saying rather than discovering.
  final bool conflict;

  /// isIndex marks the front page, which is the one every visitor lands on.
  /// Worth saying out loud wherever this is shown: a front page that is not
  /// published does not take one page down, it makes the whole site answer
  /// "no front page" to everyone who asks.
  bool get isIndex => pageSlug(name) == "index";
}

/// PageDocuments reads and writes the pages of the site.
class PageDocuments {
  /// list is every page of the site: the documents in the library's Pages
  /// folder, each with where it stands.
  ///
  /// Published files with no document behind them are included too. They are
  /// how a site written before any of this existed appears -- and leaving
  /// them out would mean a page being served that nothing in the app admits
  /// to.
  static Future<List<PageDocument>> list(PagesModel pages) async {
    var docs = await PostStorage.list(pagesFolderName);
    var served = {for (var p in pages.localPages) p.name: p};

    var out = <PageDocument>[];
    var claimed = <String>{};

    // Which link each document takes, counted first: two names can slug to
    // one file and publishing the second would replace the first, so both
    // are marked rather than one of them silently losing.
    var linkCounts = <String, int>{};
    for (var doc in docs) {
      if (doc.isFolder) continue;
      var file = pageFileNameFor(doc.name);
      linkCounts[file] = (linkCounts[file] ?? 0) + 1;
    }

    for (var doc in docs) {
      if (doc.isFolder) continue;
      var file = pageFileNameFor(doc.name);
      claimed.add(file);
      String? servedText;
      if (served.containsKey(file)) {
        servedText = await pages.readPage(file);
      }
      var text = await PostStorage.read(pagesFolderName, doc.name) ?? "";
      out.add(PageDocument(
        name: doc.name,
        state: pagePublishState(servedText, text),
        modified: doc.modified,
        conflict: (linkCounts[file] ?? 0) > 1,
      ));
    }

    for (var file in served.keys) {
      if (claimed.contains(file)) continue;
      out.add(PageDocument(
        name: documentNameFor(file),
        state: PagePublishState.published,
        modified: served[file]!.modified,
      ));
    }

    out.sort((a, b) {
      // The front page first: it is the one every visitor sees.
      if (a.isIndex != b.isIndex) return a.isIndex ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  /// adopt brings a page that is only being served into the library, so it
  /// can be written like any other. Does nothing if a document already
  /// exists for it.
  static Future<void> adopt(PagesModel pages, String name) async {
    var doc = documentNameFor(name);
    if (await PostStorage.read(pagesFolderName, doc) != null) return;
    // The served file, not the slug of the display name: this is called for
    // a page that is only being served, so the file is what exists and the
    // name came from it.
    var file = name.endsWith(".md") ? name : pageFileNameFor(name);
    await PostStorage.write(pagesFolderName, doc, await pages.readPage(file));
  }

  /// publish copies the document into the served directory, which is what
  /// makes it fetchable -- and what "Publish update" does to a page that has
  /// been written since.
  static Future<void> publish(PagesModel pages, String name) async {
    var text = await PostStorage.read(pagesFolderName, name);
    if (text == null) return;
    await pages.savePage(pageFileNameFor(name), text);
  }

  /// unpublish takes the page down, keeping the document.
  ///
  /// A deliberate act rather than a side effect of editing: taking a page
  /// down is something a writer means to do, and having it happen because
  /// they fixed a typo would be a visitor's 404 nobody chose.
  static Future<void> unpublish(PagesModel pages, String name) async {
    await pages.deletePage(pageFileNameFor(name));
  }
}
