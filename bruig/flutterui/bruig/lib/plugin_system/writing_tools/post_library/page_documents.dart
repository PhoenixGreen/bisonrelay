import 'package:bruig/models/pages.dart';
import 'package:bruig/plugin_system/writing_tools/post_library/embed_store.dart';
import 'package:golib_plugin/definitions.dart';
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

/// partialFileNameFor is the same for a shared fragment, which lives in the
/// one subdirectory a site has. The name has to match what --include[name]--
/// resolves to, so the slug is what a page refers to it by.
String partialFileNameFor(String documentName) =>
    "$partialsSubdir/${pageSlug(documentName)}.md";

/// partialsSubdir is where fragments are served from. Kept in step with
/// resources.PartialsDir on the Go side.
const String partialsSubdir = "fragments";

/// _embedReference matches a picture a document refers to rather than
/// carries. Must match what the composer writes -- see EmbedStore.
final RegExp _embedReference =
    RegExp(r"(--embed\[.*?data=)\[content ([a-zA-Z0-9]{12})\]");

/// resolveEmbeds puts the pictures back into a document's text.
///
/// A reference with nothing behind it is left as it stands rather than
/// throwing. Publishing a page with one picture missing is a page with one
/// picture missing; refusing to publish at all is a site that cannot be
/// updated because of something the writer may not even remember adding.
///
/// [missing] counts those, so the writer can be told. They cannot see it
/// themselves: their own preview fills the references in from memory, so a
/// page with a hole in it looks right to the only person able to look.
Future<({String text, int missing})> resolveEmbeds(String text) async {
  if (!_embedReference.hasMatch(text)) return (text: text, missing: 0);
  var contents = await EmbedStore.loadFor(text);
  var missing = 0;
  var out = text.replaceAllMapped(_embedReference, (m) {
    var data = contents[m.group(2)];
    if (data == null) {
      missing++;
      return m[0]!;
    }
    return "${m.group(1)}$data";
  });
  return (text: out, missing: missing);
}

/// picturesNamedIn is the total size of the site pictures [text] shows,
/// counting each distinct one once however often it appears.
///
/// Once, because that is what a reader pays: a banner shown at the top and
/// again at the foot is one file, fetched one time. Counting it twice would
/// overstate the page in exactly the case the writer was being careful.
///
/// A name with no size behind it counts nothing rather than guessing --
/// that is a picture pointing at a file the site does not have, which is a
/// broken link and not a cost.
int picturesNamedIn(String text, Map<String, int> sizes) {
  var named = <String>{
    for (var m in RegExp(r'!\[[^\]]*\]\(([^)\s]+)\)').allMatches(text))
      m.group(1)!
  };
  var total = 0;
  for (var path in named) {
    total += sizes[path] ?? 0;
  }
  return total;
}

/// isSiteFolder is whether documents in [folder] belong to the site -- the
/// pages themselves, and the fragments those pages share.
///
/// One definition, because two would drift: the publish menu asks it to
/// decide whether to offer publishing at all, and asking it about only the
/// Pages folder is what left a fragment offering Create Post.
bool isSiteFolder(String folder) =>
    folder == pagesFolderName || folder == partialsFolderName;

/// fileNameFor is the served file for a document in [folder].
String fileNameFor(String folder, String documentName) =>
    folder == partialsFolderName
        ? partialFileNameFor(documentName)
        : pageFileNameFor(documentName);

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
    required this.file,
    required this.state,
    this.folder = pagesFolderName,
    this.modified,
    this.conflict = false,
  });

  /// file is the served file this page is, or would be.
  ///
  /// Carried rather than derived from [name]. Slugging is one-way, so a page
  /// published before the slug rule existed is served under a name that
  /// cannot be recovered from the document -- and re-deriving it meant every
  /// action aimed at a file that was not there: preview fetched nothing,
  /// unpublish deleted nothing, and adopting one made a second row for the
  /// page that was already listed.
  final String file;

  /// link is what another page writes to reach this one -- the name it is
  /// actually served under, which is what works today. Publishing moves it
  /// to the slug, so it becomes [pageFileNameFor] once republished.
  String get link => file;

  /// conflict is true when another document publishes to the same file.
  ///
  /// Two names can slug to one link -- "Test Page" and "test-page" both
  /// become "test_page.md" -- and publishing the second would quietly
  /// replace the first. Worth saying rather than discovering.
  final bool conflict;

  /// folder is the library folder this came from -- Pages, or Partials for
  /// a shared fragment. What decides where publishing puts it.
  final String folder;

  /// isPartial is whether this is a shared fragment rather than a page.
  bool get isPartial => folder == partialsFolderName;

  /// isIndex marks the front page, which is the one every visitor lands on.
  /// Worth saying out loud wherever this is shown: a front page that is not
  /// published does not take one page down, it makes the whole site answer
  /// "no front page" to everyone who asks.
  bool get isIndex => !isPartial && pageSlug(name) == "index";
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
  static Future<List<PageDocument>> list(PagesModel pages,
      {String folder = pagesFolderName}) async {
    var docs = await PostStorage.list(folder);

    // Keyed by slug rather than by file name, so a document finds the file
    // it is published as even when that file predates the slug rule --
    // "Test page.md" and a document called "Test page" are one page, not
    // two, and listing them separately is what put the same page on screen
    // twice.
    // Only the files this folder publishes: a fragment lives under
    // partials/ and a page at the root, so listing one must not find the
    // other's file and call it published.
    var wantPartials = folder == partialsFolderName;
    var served = <String, LocalPage>{};
    for (var p in pages.localPages) {
      var isPartial = p.name.startsWith("$partialsSubdir/");
      if (isPartial != wantPartials) continue;
      served[pageSlug(p.name.split("/").last)] = p;
    }

    var out = <PageDocument>[];
    var claimed = <String>{};

    // Which link each document takes, counted first: two names can slug to
    // one file and publishing the second would replace the first, so both
    // are marked rather than one of them silently losing.
    var slugCounts = <String, int>{};
    for (var doc in docs) {
      if (doc.isFolder) continue;
      var slug = pageSlug(doc.name);
      slugCounts[slug] = (slugCounts[slug] ?? 0) + 1;
    }

    for (var doc in docs) {
      if (doc.isFolder) continue;
      var slug = pageSlug(doc.name);
      claimed.add(slug);

      // The file it is actually served as, when it is served at all --
      // otherwise the one it would take.
      var servedFile = served[slug];
      var file = servedFile?.name ?? fileNameFor(folder, doc.name);
      String? servedText;
      if (servedFile != null) {
        servedText = await pages.readPage(servedFile.name);
      }
      // Put the pictures back before comparing. What is served has them
      // filled in and the document holds references, so comparing the two
      // as written reported every page with a picture in it as edited the
      // moment it was published, and went on reporting it.
      var text = await PostStorage.read(folder, doc.name) ?? "";
      if (servedText != null) text = (await resolveEmbeds(text)).text;
      out.add(PageDocument(
        name: doc.name,
        file: file,
        folder: folder,
        state: pagePublishState(servedText, text),
        modified: doc.modified,
        conflict: (slugCounts[slug] ?? 0) > 1,
      ));
    }

    for (var entry in served.entries) {
      if (claimed.contains(entry.key)) continue;
      out.add(PageDocument(
        name: documentNameFor(entry.value.name.split("/").last),
        file: entry.value.name,
        folder: folder,
        state: PagePublishState.published,
        modified: entry.value.modified,
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
  /// forName builds the page a name refers to, finding the file it is
  /// actually served as.
  ///
  /// For callers that hold a name rather than a row -- the editor, the
  /// starter front page. Same slug lookup [list] uses, so a page served
  /// under a name predating the slug rule is found rather than missed.
  static PageDocument forName(PagesModel pages, String name,
      {String folder = pagesFolderName}) {
    var doc = documentNameFor(name.split("/").last);
    var slug = pageSlug(doc);
    var wantPartials = folder == partialsFolderName;
    var served = pages.localPages.where((p) {
      var isPartial = p.name.startsWith("$partialsSubdir/");
      return isPartial == wantPartials &&
          pageSlug(p.name.split("/").last) == slug;
    }).toList();
    return PageDocument(
      name: doc,
      file: served.isEmpty ? fileNameFor(folder, doc) : served.first.name,
      folder: folder,
      state: served.isEmpty
          ? PagePublishState.draft
          : PagePublishState.published,
    );
  }

  static Future<void> adopt(PagesModel pages, PageDocument page) async {
    if (await PostStorage.read(page.folder, page.name) != null) return;
    await PostStorage.write(
        page.folder, page.name, await pages.readPage(page.file));
  }

  /// publish copies the document into the served directory, which is what
  /// makes it fetchable -- and what "Publish update" does to a page that has
  /// been written since.
  ///
  /// Publishing is also where a page served under an old, unsluggable name
  /// moves to its slug: the new file is written first and the old one
  /// dropped after, so there is no moment where nothing is served.
  /// publish returns how many pictures could not be filled in, which is
  /// zero for almost every page and worth saying out loud when it is not.
  static Future<int> publish(PagesModel pages, PageDocument page) async {
    var text = await PostStorage.read(page.folder, page.name);
    if (text == null) return 0;

    // Pictures are kept out of the document while it is being written --
    // the text carries "data=[content abc]" and the bytes live in the embed
    // store -- so what is published has to have them put back. Without
    // this a page with a picture in it published the reference, and every
    // visitor got a page with a hole where the picture was.
    var resolved = await resolveEmbeds(text);
    text = resolved.text;
    var target = fileNameFor(page.folder, page.name);
    await pages.savePage(target, text);
    if (page.state.live && page.file != target) {
      await pages.deletePage(page.file);
    }
    return resolved.missing;
  }

  /// unpublish takes the page down, keeping the document.
  ///
  /// A deliberate act rather than a side effect of editing: taking a page
  /// down is something a writer means to do, and having it happen because
  /// they fixed a typo would be a visitor's 404 nobody chose.
  static Future<void> unpublish(PagesModel pages, PageDocument page) async {
    await pages.deletePage(page.file);
  }
}
