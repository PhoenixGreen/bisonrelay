import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import 'package:xml/xml.dart';

// epub_book.dart reads an EPUB for Bison Relay's own reader: unpacked into a
// folder of its own, its package read for the pages in order, which side of
// a spread each belongs on, the contents, and each page's panels where it
// marks them (Kindle's Panel View, an EPUB region-based navigation). Ken,
// 2026-11-19: Files reads a book "like Thorium", so his books can be read in
// full where the stores' readers cannot.
//
// A book is somebody else's file: nothing in it is trusted. An entry whose
// name climbs out of the book's folder is refused, the unpacked size and
// the number of files are capped, and every name the package gives is
// resolved inside the book or dropped.

/// maxBookBytes and maxBookFiles bound what one book may unpack to.
const maxBookBytes = 2 * 1024 * 1024 * 1024;
const maxBookFiles = 20000;

/// EpubLayout is how a book's pages are laid out: each a fixed page, or text
/// that flows to fit the screen.
enum EpubLayout { fixed, reflowable }

/// EpubSpread is when two pages are shown side by side.
enum EpubSpread { none, landscape, both, auto }

/// EpubSide is which side of a spread a page belongs on, if it says.
enum EpubSide { any, left, right, center }

/// EpubPanel is a panel on a fixed page, in reading order, as a share of
/// the page (0 to 1 across and down).
class EpubPanel {
  final double x, y, width, height;
  const EpubPanel(this.x, this.y, this.width, this.height);
}

/// EpubPage is one item of the book's spine.
class EpubPage {
  /// href is the page's file, from the book's folder ("OEBPS/page3.xhtml").
  final String href;
  final EpubSide side;
  final bool fixed;

  /// width and height are a fixed page's own size (its viewport), or 0.
  final int width, height;

  /// panels are the page's panels, in reading order.
  final List<EpubPanel> panels;
  const EpubPage(this.href,
      {this.side = EpubSide.any,
      this.fixed = false,
      this.width = 0,
      this.height = 0,
      this.panels = const []});
}

/// EpubEntry is a line of the contents: its title, the page it opens and
/// how deep it is.
class EpubEntry {
  final String title;
  final String href;
  final int depth;
  const EpubEntry(this.title, this.href, this.depth);
}

class EpubBook {
  /// folder is where the book is unpacked.
  final String folder;
  final String title;
  final List<String> authors;
  final String language;
  final EpubLayout layout;
  final EpubSpread spread;
  final List<EpubPage> pages;
  final List<EpubEntry> contents;

  /// cover is the cover picture's file, from [folder], or null.
  final String? cover;

  const EpubBook({
    required this.folder,
    required this.title,
    this.authors = const [],
    this.language = "",
    this.layout = EpubLayout.reflowable,
    this.spread = EpubSpread.auto,
    this.pages = const [],
    this.contents = const [],
    this.cover,
  });

  bool get fixed => layout == EpubLayout.fixed;

  /// hasPanels is whether any page marks panels to read one by one.
  bool get hasPanels => pages.any((p) => p.panels.isNotEmpty);

  /// pageOf is the index of the page [href] is in (a fragment dropped), or
  /// -1.
  int pageOf(String href) {
    var file = href.split("#").first;
    return pages.indexWhere((p) => p.href == file);
  }

  /// spreads is the book as it is shown with two pages side by side: each
  /// a pair of page indices, either of which may be null (an empty side).
  /// A page marked for a side takes that side; a centred page, or one
  /// after a gap, stands alone; the rest pair in order, the first on the
  /// right as a printed book opens.
  List<(int?, int?)> get spreads {
    var out = <(int?, int?)>[];
    int? left;
    void flush() {
      if (left != null) out.add((left, null));
      left = null;
    }

    for (var (i, p) in pages.indexed) {
      switch (p.side) {
        case EpubSide.center:
          flush();
          out.add((i, null));
        case EpubSide.left:
          flush();
          left = i;
        case EpubSide.right:
          out.add((left, i));
          left = null;
        case EpubSide.any:
          if (left != null) {
            out.add((left, i));
            left = null;
          } else if (out.isEmpty) {
            // The first page alone on the right, as a book opens.
            out.add((null, i));
          } else {
            left = i;
          }
      }
    }
    flush();
    return out;
  }

  /// spreadOf is the spread [page] is in.
  int spreadOf(int page) {
    var s = spreads;
    var i = s.indexWhere((p) => p.$1 == page || p.$2 == page);
    return math.max(0, i);
  }
}

/// EpubError is a book that cannot be read, said plainly.
class EpubError implements Exception {
  final String message;
  const EpubError(this.message);
  @override
  String toString() => message;
}

/// unpackEpub unpacks [bytes] into [folder] (made if missing) and reads it.
/// Throws EpubError for what is not a book, or a book that breaks the rules
/// above.
Future<EpubBook> unpackEpub(List<int> bytes, String folder) async {
  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const EpubError("This is not an EPUB: it is not a zip of a book.");
  }
  if (archive.files.length > maxBookFiles) {
    throw const EpubError("This book has too many files to open.");
  }
  var root = Directory(folder);
  await root.create(recursive: true);
  var base = path.normalize(root.absolute.path);
  var total = 0;
  for (var entry in archive.files) {
    if (!entry.isFile) continue;
    var target = safeJoin(base, entry.name);
    if (target == null) {
      throw EpubError("This book has a file it may not have: ${entry.name}");
    }
    total += entry.size;
    if (total > maxBookBytes) {
      throw const EpubError("This book is too large to open.");
    }
    var file = File(target);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(entry.content as List<int>);
  }
  return readEpubFolder(base);
}

/// safeJoin is [name] inside [base], or null where it would climb out of
/// it or is absolute.
String? safeJoin(String base, String name) {
  var clean = name.replaceAll("\\", "/");
  if (clean.startsWith("/") || RegExp(r"^[a-zA-Z]:").hasMatch(clean)) {
    return null;
  }
  var joined = path.normalize(path.join(base, clean));
  return path.isWithin(base, joined) ? joined : null;
}

/// readEpubFolder reads a book already unpacked in [folder].
Future<EpubBook> readEpubFolder(String folder) async {
  String? read(String rel) {
    var p = safeJoin(folder, rel);
    if (p == null) return null;
    var f = File(p);
    return f.existsSync() ? f.readAsStringSync() : null;
  }

  XmlDocument parse(String? text, String what) {
    if (text == null) throw EpubError("This book has no $what.");
    try {
      return XmlDocument.parse(text);
    } catch (_) {
      throw EpubError("This book's $what cannot be read.");
    }
  }

  var container = parse(read("META-INF/container.xml"), "container");
  var opfPath = container
      .findAllElements("rootfile")
      .map((e) => e.getAttribute("full-path"))
      .whereType<String>()
      .firstOrNull;
  if (opfPath == null) throw const EpubError("This book names no package.");
  var opf = parse(read(opfPath), "package");
  var opfDir = path.posix.dirname(opfPath);
  String inBook(String href) {
    var decoded = Uri.decodeComponent(href.split("#").first);
    return path.posix
        .normalize(opfDir == "." ? decoded : path.posix.join(opfDir, decoded));
  }

  // The package's own words, with or without a namespace prefix.
  Iterable<XmlElement> all(XmlNode n, String local) =>
      n.descendants.whereType<XmlElement>().where((e) => e.localName == local);
  String metaProperty(String property) =>
      all(opf, "meta")
          .where((m) => m.getAttribute("property") == property)
          .map((m) => m.innerText.trim())
          .firstOrNull ??
      "";
  String metaName(String name) =>
      all(opf, "meta")
          .where((m) => m.getAttribute("name") == name)
          .map((m) => m.getAttribute("content") ?? "")
          .firstOrNull ??
      "";

  var title =
      all(opf, "title").map((e) => e.innerText.trim()).firstOrNull ?? "";
  var authors = [for (var c in all(opf, "creator")) c.innerText.trim()];
  var language =
      all(opf, "language").map((e) => e.innerText.trim()).firstOrNull ?? "";
  var fixedBook = metaProperty("rendition:layout") == "pre-paginated" ||
      metaName("fixed-layout") == "true";
  var spread = switch (metaProperty("rendition:spread")) {
    "none" => EpubSpread.none,
    "landscape" => EpubSpread.landscape,
    "both" => EpubSpread.both,
    _ => EpubSpread.auto,
  };

  // The manifest: what each id is, where, and what it is.
  var items = <String, (String, String, String)>{};
  for (var item in all(opf, "item")) {
    var id = item.getAttribute("id"), href = item.getAttribute("href");
    if (id == null || href == null) continue;
    items[id] = (
      inBook(href),
      item.getAttribute("media-type") ?? "",
      item.getAttribute("properties") ?? "",
    );
  }

  // Panels a page marks for Kindle's Panel View, read off the page itself.
  var regionPanels = <String, List<EpubPanel>>{};
  var regions = items.values
      .where((i) => i.$3.split(" ").contains("data-nav"))
      .map((i) => i.$1)
      .firstOrNull;
  var regionsText = regions == null ? null : read(regions);
  if (regionsText case var text?) {
    try {
      var doc = XmlDocument.parse(text);
      var dir = path.posix.dirname(regions!);
      for (var a in all(doc, "a")) {
        var href = a.getAttribute("href") ?? "";
        var m =
            RegExp(r"^(.*)#xywh=percent:([\d.]+),([\d.]+),([\d.]+),([\d.]+)$")
                .firstMatch(href);
        if (m == null) continue;
        var page = path.posix.normalize(path.posix.join(dir, m[1]!));
        double v(int i) => (double.tryParse(m[i]!) ?? 0) / 100;
        (regionPanels[page] ??= []).add(EpubPanel(v(2), v(3), v(4), v(5)));
      }
    } catch (_) {
      // A broken list of regions: the pages are read without it.
    }
  }

  var pages = <EpubPage>[];
  for (var ref in all(opf, "itemref")) {
    var item = items[ref.getAttribute("idref")];
    if (item == null) continue;
    if (ref.getAttribute("linear") == "no") continue;
    var props = (ref.getAttribute("properties") ?? "").split(" ");
    var side = props.contains("page-spread-left")
        ? EpubSide.left
        : props.contains("page-spread-right")
            ? EpubSide.right
            : props.contains("rendition:page-spread-center") ||
                    props.contains("page-spread-center")
                ? EpubSide.center
                : EpubSide.any;
    var fixed = props.contains("rendition:layout-pre-paginated") ||
        (fixedBook && !props.contains("rendition:layout-reflowable"));
    var w = 0, h = 0;
    var panels = regionPanels[item.$1] ?? const <EpubPanel>[];
    if (fixed) {
      var page = read(item.$1);
      if (page != null) {
        (w, h) = _viewport(page);
        if (panels.isEmpty) panels = _kindlePanels(page, w, h);
      }
    }
    pages.add(EpubPage(item.$1,
        side: side, fixed: fixed, width: w, height: h, panels: panels));
  }
  if (pages.isEmpty) throw const EpubError("This book has no pages.");

  // The contents: the navigation document, or the old NCX.
  var contents = <EpubEntry>[];
  var nav = items.values
      .where((i) => i.$3.split(" ").contains("nav"))
      .map((i) => i.$1)
      .firstOrNull;
  var navText = nav == null ? null : read(nav);
  if (navText case var text?) {
    try {
      var doc = XmlDocument.parse(text);
      var dir = path.posix.dirname(nav!);
      var toc = all(doc, "nav").firstWhere(
          (n) => (n.getAttribute("epub:type") ?? n.getAttribute("type") ?? "")
              .contains("toc"),
          orElse: () => all(doc, "nav").first);
      void walk(XmlElement list, int depth) {
        for (var li in list.childElements.where((e) => e.localName == "li")) {
          var a = li.childElements
              .where((e) => e.localName == "a" || e.localName == "span")
              .firstOrNull;
          var href = a?.getAttribute("href");
          if (a != null && href != null) {
            contents.add(EpubEntry(a.innerText.trim(),
                path.posix.normalize(path.posix.join(dir, href)), depth));
          }
          for (var sub in li.childElements.where((e) => e.localName == "ol")) {
            walk(sub, depth + 1);
          }
        }
      }

      for (var ol in toc.childElements.where((e) => e.localName == "ol")) {
        walk(ol, 0);
      }
    } catch (_) {
      // No readable contents: the book still reads.
    }
  }

  var coverId = metaName("cover");
  var cover = items.values
          .where((i) => i.$3.split(" ").contains("cover-image"))
          .map((i) => i.$1)
          .firstOrNull ??
      items[coverId]?.$1;

  return EpubBook(
    folder: folder,
    title: title,
    authors: authors,
    language: language,
    layout: fixedBook ? EpubLayout.fixed : EpubLayout.reflowable,
    spread: spread,
    pages: pages,
    contents: contents,
    cover: cover,
  );
}

/// _viewport is a fixed page's size from its viewport meta
/// ("width=1240, height=1754"), or (0, 0).
(int, int) _viewport(String page) {
  var m =
      RegExp(r'''<meta[^>]+name=["']viewport["'][^>]*>''', caseSensitive: false)
          .firstMatch(page);
  if (m == null) return (0, 0);
  var tag = m[0]!;
  int part(String name) {
    var v =
        RegExp("$name\\s*=\\s*(\\d+)", caseSensitive: false).firstMatch(tag);
    return v == null ? 0 : int.parse(v[1]!).clamp(0, 20000);
  }

  return (part("width"), part("height"));
}

/// _kindlePanels are the panels a page marks for Kindle's Panel View: each
/// app-amzn-magnify link's box, ordered by its "ordinal". Boxes in pixels
/// are made shares of the page [w] by [h]; boxes in percent are shares.
List<EpubPanel> _kindlePanels(String page, int w, int h) {
  if (!page.contains("app-amzn-magnify")) return const [];
  var found = <(int, EpubPanel)>[];
  // The JSON is in single quotes as Amazon writes it, or in double quotes
  // with its own quotes as &quot;.
  var tap = RegExp(
      r'''<div[^>]*style=["']([^"']*)["'][^>]*>\s*<a[^>]*data-app-amzn-magnify=(?:'([^']*)'|"([^"]*)")''',
      caseSensitive: false);
  for (var m in tap.allMatches(page)) {
    var style = m[1]!, data = m[2] ?? m[3]!.replaceAll("&quot;", '"');
    double? at(String name) {
      var v = RegExp("$name\\s*:\\s*(-?[\\d.]+)(px|%)?").firstMatch(style);
      if (v == null) return null;
      var n = double.tryParse(v[1]!);
      if (n == null) return null;
      var of = name == "left" || name == "width" ? w : h;
      return v[2] == "%" ? n / 100 : (of <= 0 ? null : n / of);
    }

    var x = at("left"), y = at("top"), pw = at("width"), ph = at("height");
    if (x == null || y == null || pw == null || ph == null) continue;
    var ordinal = int.tryParse(
            RegExp(r'"ordinal"\s*:\s*(\d+)').firstMatch(data)?[1] ?? "") ??
        found.length + 1;
    found.add((ordinal, EpubPanel(x, y, pw, ph)));
  }
  found.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (var f in found) f.$2];
}
