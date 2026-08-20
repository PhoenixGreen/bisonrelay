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

/// pageFileName is the file a library document is published as.
///
/// The library holds names without the extension, because that is what a
/// reader wants to see in a sidebar; the site serves ".md" files, because
/// that is what the other end asks for.
String pageFileNameFor(String documentName) =>
    documentName.endsWith(".md") ? documentName : "$documentName.md";

/// documentNameFor is [pageFileNameFor] backwards.
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
  });

  /// isIndex marks the front page, which is the one every visitor lands on.
  /// Worth saying out loud wherever this is shown: a front page that is not
  /// published does not take one page down, it makes the whole site answer
  /// "no front page" to everyone who asks.
  bool get isIndex => pageFileNameFor(name) == "index.md";
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
    var file = pageFileNameFor(name);
    var doc = documentNameFor(name);
    if (await PostStorage.read(pagesFolderName, doc) != null) return;
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
