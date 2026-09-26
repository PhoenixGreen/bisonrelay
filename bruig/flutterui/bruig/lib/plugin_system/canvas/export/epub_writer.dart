import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

// epub_writer.dart writes a document of pages as an EPUB.
//
// Fixed layout, one picture to a page. A canvas is a design rather than a
// piece of prose: its words are placed, its columns are where somebody put
// them, and a reader reflowing it into a phone-shaped column would be
// throwing away the whole of the work. So every page is declared
// pre-paginated at its own size, and what an e-reader does is show it whole
// and turn it -- which is what a document of pages is for.
//
// Written by hand rather than through a package, for the reason the GIF
// encoder is: an EPUB is a zip with a handful of XML files in it, all of them
// short, and the shape of those files is the whole of the format. A
// dependency for this would be a dependency for four templates.

/// EpubSide is which half of a spread a page belongs on, for a reader showing
/// two at a time.
///
/// Said per page rather than worked out by the reader, because the reader
/// cannot know: it depends on the covers and on where the numbering starts,
/// and a reader left to guess puts the whole document on the wrong side of
/// the spine from the first unnumbered page onwards.
enum EpubSide { left, right, centre }

/// EpubLink is a rectangle on a page that goes somewhere when it is pressed.
///
/// In page units, with the origin at the top left -- the same space the
/// canvas itself is laid out in, so a button's own bounds can be handed
/// straight over.
class EpubLink {
  final double x;
  final double y;
  final double width;
  final double height;

  /// href is another page's file name, or a URL.
  final String href;

  const EpubLink({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.href,
  });
}

/// EpubPage is one leaf: a picture, its size, and anything on it that can be
/// pressed.
class EpubPage {
  final Uint8List png;
  final int width;
  final int height;

  /// title is what the contents list calls it.
  final String title;

  final EpubSide side;

  /// cover marks the page an e-reader should use as the book's cover picture.
  final bool cover;

  /// links are empty for a plain EPUB. See writeEpub's `interactive`.
  final List<EpubLink> links;

  const EpubPage({
    required this.png,
    required this.width,
    required this.height,
    required this.title,
    this.side = EpubSide.centre,
    this.cover = false,
    this.links = const [],
  });
}

/// epubMime is what an EPUB is, and what goes in the archive's first entry.
const String epubMime = "application/epub+zip";

/// writeEpub packs the pages into the bytes of an .epub file.
///
/// [interactive] adds the hotspots and declares the document scripted. The
/// difference between the two kinds of EPUB this app writes is exactly that:
/// the plain one is pages to read, and the interactive one is pages whose
/// buttons go somewhere. Both are fixed layout, because both are this canvas.
Uint8List writeEpub({
  required List<EpubPage> pages,
  required String title,
  String author = "",
  String? identifier,
  bool interactive = false,
  bool facing = false,
}) {
  if (pages.isEmpty) {
    throw ArgumentError("an EPUB needs at least one page");
  }
  var id = identifier ?? "urn:uuid:${_uuidFrom(title, pages.length)}";
  var archive = Archive();

  // The mimetype first and uncompressed, which is not a convention: a reader
  // identifies an EPUB by finding these exact bytes at a fixed offset in the
  // file, and a deflated first entry puts them somewhere else.
  var mime = ascii.encode(epubMime);
  archive.addFile(ArchiveFile("mimetype", mime.length, mime)
    ..compression = CompressionType.none);

  _add(archive, "META-INF/container.xml", _container);

  for (var (i, page) in pages.indexed) {
    _add(archive, "OEBPS/page$i.xhtml", _pageXhtml(i, page, interactive));
    archive.addFile(ArchiveFile("OEBPS/page$i.png", page.png.length, page.png)
      // Already deflated inside the PNG. Deflating it again costs the time
      // and gives back a file a shade larger.
      ..compression = CompressionType.none);
  }

  _add(archive, "OEBPS/nav.xhtml", _nav(pages));
  _add(archive, "OEBPS/content.opf",
      _opf(pages, title, author, id, interactive, facing));

  var zip = ZipEncoder().encode(archive);
  return Uint8List.fromList(zip);
}

void _add(Archive archive, String path, String text) {
  var bytes = utf8.encode(text);
  archive.addFile(ArchiveFile(path, bytes.length, bytes));
}

const String _container = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0"
    xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf"
        media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';

/// _pageXhtml is one leaf: a picture filling a viewport of its own size.
///
/// The viewport is what makes a fixed-layout page fixed. Without it a reader
/// has no idea how large the page is meant to be and falls back to reflowing
/// it, which for a design is the one thing that must not happen.
String _pageXhtml(int index, EpubPage page, bool interactive) {
  var hotspots = interactive
      ? [
          for (var link in page.links)
            '<a class="hit" href="${_attr(link.href)}" '
                'style="left:${_px(link.x)};top:${_px(link.y)};'
                'width:${_px(link.width)};height:${_px(link.height)}"></a>',
        ].join("\n    ")
      : "";
  return '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml"
    xmlns:epub="http://www.idpf.org/2007/ops">
  <head>
    <title>${_text(page.title)}</title>
    <meta name="viewport"
        content="width=${page.width}, height=${page.height}"/>
    <style>
      html, body { margin: 0; padding: 0; height: 100%; }
      body { width: ${page.width}px; height: ${page.height}px; }
      img.page { width: 100%; height: 100%; display: block; }
      a.hit { position: absolute; display: block; }
    </style>
  </head>
  <body>
    <img class="page" src="page$index.png" alt="${_text(page.title)}"/>
    $hotspots
  </body>
</html>
''';
}

/// _nav is the contents, which EPUB 3 requires whether or not anybody wants
/// one. Hidden, because a document of designed pages has a contents list only
/// if its author drew one.
String _nav(List<EpubPage> pages) {
  var items = [
    for (var (i, page) in pages.indexed)
      '<li><a href="page$i.xhtml">${_text(page.title)}</a></li>',
  ].join("\n        ");
  return '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml"
    xmlns:epub="http://www.idpf.org/2007/ops">
  <head><title>Contents</title></head>
  <body>
    <nav epub:type="toc" id="toc" hidden="hidden">
      <h1>Contents</h1>
      <ol>
        $items
      </ol>
    </nav>
  </body>
</html>
''';
}

/// _opf is the package: what is in the book, and in what order.
String _opf(List<EpubPage> pages, String title, String author, String id,
    bool interactive, bool facing) {
  var coverAt = pages.indexWhere((p) => p.cover);
  var manifest = <String>[
    '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" '
        'properties="nav"/>',
    for (var (i, page) in pages.indexed) ...[
      '<item id="page$i" href="page$i.xhtml" '
          'media-type="application/xhtml+xml"'
          '${interactive && page.links.isNotEmpty ? ' properties="scripted"' : ''}/>',
      '<item id="img$i" href="page$i.png" media-type="image/png"'
          '${i == coverAt ? ' properties="cover-image"' : ''}/>',
    ],
  ].join("\n    ");

  // Which side of the spine each page belongs on. A fixed-layout reader
  // showing two at a time has no way to work this out: it depends on the
  // covers and on where the numbering starts.
  var spine = [
    for (var (i, page) in pages.indexed)
      '<itemref idref="page$i"${switch (page.side) {
        EpubSide.left => ' properties="page-spread-left"',
        EpubSide.right => ' properties="page-spread-right"',
        EpubSide.centre => '',
      }}/>',
  ].join("\n    ");

  var when = DateTime.now().toUtc().toIso8601String().split(".").first;
  return '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0"
    unique-identifier="bookid"
    prefix="rendition: http://www.idpf.org/vocab/rendition/#">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">${_text(id)}</dc:identifier>
    <dc:title>${_text(title)}</dc:title>
    <dc:language>en</dc:language>
${author.isEmpty ? "" : "    <dc:creator>${_text(author)}</dc:creator>\n"}    <meta property="dcterms:modified">${when}Z</meta>
    <meta property="rendition:layout">pre-paginated</meta>
    <meta property="rendition:spread">${facing ? "landscape" : "none"}</meta>
${coverAt < 0 ? "" : '    <meta name="cover" content="img$coverAt"/>\n'}  </metadata>
  <manifest>
    $manifest
  </manifest>
  <spine>
    $spine
  </spine>
</package>
''';
}

String _px(double v) => "${v.toStringAsFixed(2)}px";

/// _text escapes for XML character data, and _attr for an attribute.
String _text(String s) =>
    s.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");

String _attr(String s) => _text(s).replaceAll('"', "&quot;");

/// _uuidFrom makes a stable identifier out of what the book is, so that the
/// same document exported twice is the same book rather than two.
///
/// Not a random one: a reader keeps somebody's place by identifier, and a new
/// one on every export is a document that loses its bookmarks each time it is
/// sent.
String _uuidFrom(String title, int pages) {
  var seed = "$title/$pages";
  var hash = 0x811c9dc5;
  for (var unit in utf8.encode(seed)) {
    hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  var hex = hash.toRadixString(16).padLeft(8, "0");
  return "$hex-0000-4000-8000-${hex.padLeft(12, "0").substring(0, 12)}";
}
