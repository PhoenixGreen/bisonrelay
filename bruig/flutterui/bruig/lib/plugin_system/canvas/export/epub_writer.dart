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
/// EpubFile is a file the book carries besides its pages: a sound, a video.
class EpubFile {
  /// href is where it is, relative to the pages -- "media/…".
  final String href;
  final Uint8List bytes;
  final String mime;
  const EpubFile(this.href, this.bytes, this.mime);
}

/// EpubMedia is a sound or a video on a page, played by the page's script.
///
/// A sound has no size unless it can be pressed; a video is placed where it
/// was on the canvas. Everything about how it plays -- the files in order,
/// the part of each, repeat, fades, where it starts -- is written onto the
/// element for media.js to read, so the one script serves every page.
class EpubMedia {
  final String id;
  final bool video;

  /// x, y, width and height are in the page's pixels.
  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;

  /// sources are the files' hrefs in playing order, and ranges the part of
  /// each that plays: seconds from and to, a to of nought being the end.
  final List<String> sources;
  final List<(double, double)> ranges;

  /// loop is "none", "one" or "all" -- see MediaLoop.
  final String loop;
  final bool autoplay;
  final bool muted;
  final double volume;
  final double fadeIn;
  final double fadeOut;

  /// controls is the reader's own player controls on a video.
  final bool controls;

  /// pressable is whether pressing it plays and pauses it.
  final bool pressable;

  final String? poster;

  const EpubMedia({
    required this.id,
    required this.video,
    this.x = 0,
    this.y = 0,
    this.width = 0,
    this.height = 0,
    this.rotation = 0,
    required this.sources,
    required this.ranges,
    this.loop = "none",
    this.autoplay = false,
    this.muted = false,
    this.volume = 1,
    this.fadeIn = 0,
    this.fadeOut = 0,
    this.controls = false,
    this.pressable = false,
    this.poster,
  });
}

/// EpubAction is a rectangle that does something to a sound or a video on
/// the page when pressed: a button whose action is one of the media ones.
class EpubAction {
  final double x;
  final double y;
  final double width;
  final double height;

  /// act is "play", "pause", "toggle", "stop" or "mute".
  final String act;
  final String target;

  const EpubAction({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.act,
    required this.target,
  });
}

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

  /// media, actions and files are an interactive page's sounds and videos,
  /// the presses that drive them, and the files they play.
  final List<EpubMedia> media;
  final List<EpubAction> actions;
  final List<EpubFile> files;

  /// film is a video of the whole page, where the page has media on its
  /// timeline: the page played through with its sound, exactly as an MP4
  /// export of it would be. Shown in place of the page's picture, which is
  /// its poster.
  final String? film;

  /// plays is whether the page has sound or video for media.js to run, and
  /// scripted whether it is declared so -- which a page with links has always
  /// been, as the place where what they drive is written.
  bool get plays => media.isNotEmpty;
  bool get scripted => plays || links.isNotEmpty || actions.isNotEmpty;

  const EpubPage({
    required this.png,
    required this.width,
    required this.height,
    required this.title,
    this.side = EpubSide.centre,
    this.cover = false,
    this.links = const [],
    this.media = const [],
    this.actions = const [],
    this.files = const [],
    this.film,
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

  // Each file once, however many pages play it: the same song under ten
  // pages is one song in the book.
  var carried = <String, EpubFile>{};
  for (var page in pages) {
    if (!interactive) break;
    for (var f in page.files) {
      carried.putIfAbsent(f.href, () => f);
    }
  }
  for (var f in carried.values) {
    archive.addFile(ArchiveFile("OEBPS/${f.href}", f.bytes.length, f.bytes)
      // Sound and video are compressed already.
      ..compression = CompressionType.none);
  }
  if (interactive && pages.any((p) => p.plays)) {
    _add(archive, "OEBPS/media.js", _mediaScript);
  }

  for (var (i, page) in pages.indexed) {
    _add(archive, "OEBPS/page$i.xhtml", _pageXhtml(i, page, interactive));
    archive.addFile(ArchiveFile("OEBPS/page$i.png", page.png.length, page.png)
      // Already deflated inside the PNG. Deflating it again costs the time
      // and gives back a file a shade larger.
      ..compression = CompressionType.none);
  }

  _add(archive, "OEBPS/nav.xhtml", _nav(pages));
  _add(archive, "OEBPS/content.opf",
      _opf(pages, title, author, id, interactive, facing, carried.values));

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
  String box(double x, double y, double w, double h, [double turn = 0]) =>
      "left:${_px(x)};top:${_px(y)};width:${_px(w)};height:${_px(h)}"
      "${turn == 0 ? "" : ";transform:rotate(${turn.toStringAsFixed(2)}deg)"}";
  var hotspots = interactive
      ? [
          for (var link in page.links)
            '<a class="hit" href="${_attr(link.href)}" '
                'style="${box(link.x, link.y, link.width, link.height)}"></a>',
          for (var m in page.media) _mediaTag(m, box),
          for (var m in page.media)
            if (m.pressable && m.width > 0)
              '<a class="hit" href="#" data-act="toggle" '
                  'data-target="${_attr(m.id)}" '
                  'style="${box(m.x, m.y, m.width, m.height, m.rotation)}"></a>',
          for (var a in page.actions)
            '<a class="hit" href="#" data-act="${_attr(a.act)}" '
                'data-target="${_attr(a.target)}" '
                'style="${box(a.x, a.y, a.width, a.height)}"></a>',
        ].join("\n    ")
      : "";
  var film = interactive ? page.film : null;
  // The page's picture is the film's poster: what shows before it plays, and
  // in a reader that will not play it.
  var face = film == null
      ? '<img class="page" src="page$index.png" alt="${_text(page.title)}"/>'
      : '<video class="page" src="${_attr(film)}" poster="page$index.png" '
          'controls="controls" playsinline="playsinline" '
          'preload="metadata"></video>';
  var script =
      interactive && page.plays ? '\n    <script src="media.js"></script>' : "";
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
      img.page, video.page { width: 100%; height: 100%; display: block; }
      a.hit { position: absolute; display: block; }
      video.media { position: absolute; display: block; object-fit: cover; }
      a.hit.on { box-shadow: 0 0 0 3px rgba(61, 126, 255, 0.7); border-radius: 50%; }
    </style>
  </head>
  <body>
    $face
    $hotspots$script
  </body>
</html>
''';
}

/// _nav is the contents, which EPUB 3 requires whether or not anybody wants
/// one. Hidden, because a document of designed pages has a contents list only
/// if its author drew one.
/// _mediaTag is one sound or video as the page's HTML, carrying how it plays
/// for media.js to read.
String _mediaTag(EpubMedia m,
    String Function(double, double, double, double, [double]) box) {
  var data = 'id="m-${_attr(m.id)}" '
      'data-list="${_attr(m.sources.join("|"))}" '
      'data-ranges="${m.ranges.map((r) => "${r.$1},${r.$2}").join("|")}" '
      'data-loop="${m.loop}" data-volume="${m.volume}" '
      'data-fadein="${m.fadeIn}" data-fadeout="${m.fadeOut}" '
      'data-autoplay="${m.autoplay}"${m.muted ? ' muted="muted"' : ''}';
  if (!m.video) return '<audio $data preload="auto"></audio>';
  return '<video class="media" $data playsinline="playsinline" '
      'preload="metadata"${m.controls ? ' controls="controls"' : ''}'
      '${m.poster == null ? '' : ' poster="${_attr(m.poster!)}"'} '
      'style="${box(m.x, m.y, m.width, m.height, m.rotation)}"></video>';
}

/// _mediaScript plays a page's sounds and videos: a playlist in order, each
/// file's range, repeat, fades and autoplay, and the presses that play,
/// pause, stop and mute them. One file for the whole book.
///
/// Written for the oldest engine a reader is likely to have -- no arrow
/// functions, no let -- because an EPUB reader's web view is often years
/// behind a browser.
const String _mediaScript = r"""(function () {
  function all(s) { return Array.prototype.slice.call(document.querySelectorAll(s)); }
  var media = {};
  all("[data-list]").forEach(function (m) {
    var list = m.getAttribute("data-list").split("|");
    var ranges = (m.getAttribute("data-ranges") || "").split("|").map(function (r) {
      var p = r.split(","); return [parseFloat(p[0]) || 0, parseFloat(p[1]) || 0];
    });
    var loop = m.getAttribute("data-loop") || "none";
    var volume = parseFloat(m.getAttribute("data-volume") || "1");
    var fadeIn = parseFloat(m.getAttribute("data-fadein") || "0");
    var fadeOut = parseFloat(m.getAttribute("data-fadeout") || "0");
    var at = 0, moving = false;
    function load(i) { at = i; m.src = list[i]; m.load(); }
    m.addEventListener("loadedmetadata", function () {
      try { m.currentTime = (ranges[at] || [0, 0])[0]; } catch (e) {}
      moving = false;
    });
    function next() {
      if (moving) return;
      moving = true;
      if (loop === "one") load(at);
      else if (at + 1 < list.length) load(at + 1);
      else if (loop === "all") load(0);
      else { m.pause(); load(0); return; }
      var p = m.play(); if (p && p.catch) p.catch(function () {});
    }
    m.addEventListener("ended", next);
    m.addEventListener("timeupdate", function () {
      var r = ranges[at] || [0, 0];
      var end = r[1] > 0 ? r[1] : m.duration;
      var gain = 1, into = m.currentTime - r[0];
      if (fadeIn > 0) gain = Math.min(gain, into / fadeIn);
      if (fadeOut > 0 && isFinite(end)) gain = Math.min(gain, (end - m.currentTime) / fadeOut);
      m.volume = Math.max(0, Math.min(1, volume * gain));
      if (r[1] > 0 && m.currentTime >= r[1] && !m.paused) next();
    });
    var id = m.id.substring(2);
    function mark() {
      all('a[data-target="' + id + '"][data-act="toggle"]').forEach(function (a) {
        if (m.paused) a.classList.remove("on"); else a.classList.add("on");
      });
    }
    m.addEventListener("play", mark);
    m.addEventListener("pause", mark);
    load(0);
    m.volume = volume;
    media[id] = { m: m, stop: function () { m.pause(); load(0); } };
    if (m.getAttribute("data-autoplay") === "true") {
      var p = m.play(); if (p && p.catch) p.catch(function () {});
    }
  });
  all("a[data-act]").forEach(function (a) {
    a.addEventListener("click", function (e) {
      e.preventDefault();
      var t = media[a.getAttribute("data-target")];
      if (!t) return;
      var m = t.m, act = a.getAttribute("data-act");
      if (act === "play" || (act === "toggle" && m.paused)) {
        var p = m.play(); if (p && p.catch) p.catch(function () {});
      } else if (act === "pause" || act === "toggle") m.pause();
      else if (act === "stop") t.stop();
      else if (act === "mute") m.muted = !m.muted;
    });
  });
})();
""";

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
    bool interactive, bool facing, Iterable<EpubFile> files) {
  var coverAt = pages.indexWhere((p) => p.cover);
  var manifest = <String>[
    '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" '
        'properties="nav"/>',
    for (var (i, page) in pages.indexed) ...[
      '<item id="page$i" href="page$i.xhtml" '
          'media-type="application/xhtml+xml"'
          '${interactive && page.scripted ? ' properties="scripted"' : ''}/>',
      '<item id="img$i" href="page$i.png" media-type="image/png"'
          '${i == coverAt ? ' properties="cover-image"' : ''}/>',
    ],
    // A reader will not open a file the manifest does not list.
    for (var (i, f) in files.indexed)
      '<item id="media$i" href="${_attr(f.href)}" media-type="${f.mime}"/>',
    if (interactive && pages.any((p) => p.plays))
      '<item id="script" href="media.js" media-type="application/javascript"/>',
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
