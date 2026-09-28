import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bruig/plugin_system/canvas/export/epub_layers.dart';

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

  /// element is the button it was made from, so that on a page laid out as
  /// layers it travels with the button -- see EpubStage.
  final String? element;

  const EpubLink({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.href,
    this.element,
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

  /// radius is a speaker's corners, in pixels, for the ring that shows it is
  /// playing. Only a sound gets the ring: a speaker drawn in a picture cannot
  /// light up by itself, and a video plainly is playing -- ringed, its
  /// rectangle came out as an oval over the picture.
  final double radius;

  /// playButton draws the canvas's big play button over a video while it is
  /// stopped. The canvas draws it into the page's picture, and the video laid
  /// over the picture covers it -- so without its own, a video with no
  /// controls showed no sign of being something to press.
  final bool playButton;

  /// at is the frame of the page's playhead it starts on, for a video on the
  /// timeline of a page laid out as layers: it follows the playhead rather
  /// than being played by itself, silent -- its sound is in the page's
  /// soundtrack. Null for one that plays on its own clock.
  final int? at;

  /// spans are how long each file's range plays, in seconds, for [at]: what
  /// the playhead is placed against.
  final List<double> spans;

  /// element is the element it was made from, so that on a page laid out as
  /// layers it sits in the element's layer -- above what is under it, below
  /// what is over it, and moving with it.
  final String? element;

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
    this.radius = 0,
    this.playButton = false,
    this.at,
    this.spans = const [],
    this.element,
  });
}

/// EpubAction is a rectangle that does something to a sound or a video on
/// the page when pressed: a button whose action is one of the media ones.
class EpubAction {
  final double x;
  final double y;
  final double width;
  final double height;

  /// act is "play", "pause", "toggle", "stop" or "mute" -- or, aimed at the
  /// page's playhead, one of its own: "restart", "goto", "playfrom",
  /// "playto", at [frame] -- or "showhide", aimed at an element's layer.
  final String act;
  final String target;
  final int frame;

  /// element is the button it was made from. See EpubLink.element.
  final String? element;

  const EpubAction({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.act,
    required this.target,
    this.frame = 0,
    this.element,
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

  /// stage is the page as the things on it, moved by the page's script, where
  /// it has anything that moves. See epub_layers.dart.
  final EpubStage? stage;

  /// soundtrack is the page's timeline sound, mixed, for a page laid out as
  /// layers: played in step with its playhead. See renderSoundtrack.
  final String? soundtrack;

  /// plays is whether the page has sound or video for media.js to run, and
  /// scripted whether it is declared so -- which a page with links has always
  /// been, as the place where what they drive is written.
  bool get plays => media.isNotEmpty;
  bool get scripted =>
      plays || links.isNotEmpty || actions.isNotEmpty || stage != null;

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
    this.stage,
    this.soundtrack,
  });
}

/// filmTarget is what a playhead button on a page aims at: the page's
/// playhead. Named "film" in the book's script for the films pages used to
/// be; the name is only a name.
const String filmTarget = "film";

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
  // Apple Books reads its own options beside the container: without them it
  // opens a fixed-layout book as though it might be a flowing one, and shows
  // a stretched picture of the cover while it decides.
  _add(archive, "META-INF/com.apple.ibooks.display-options.xml",
      _appleOptions(interactive));

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
  if (interactive && pages.any((p) => p.scripted)) {
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

String _appleOptions(bool interactive) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<display_options>
  <platform name="*">
    <option name="fixed-layout">true</option>
    <option name="open-to-spread">false</option>
${interactive ? '    <option name="interactive">true</option>\n' : ''}  </platform>
</display_options>
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
  // A button whose element is a layer is pressed where the layer is, so it
  // goes inside it: a button that slides in takes the place to press it
  // with it, and one that is hidden cannot be pressed.
  var stage = interactive ? page.stage : null;
  var layered = {for (var l in stage?.layers ?? const <EpubLayer>[]) l.id};
  bool inLayer(String? element) => element != null && layered.contains(element);
  // Something inside each link: Apple Books passes over a tap on a link with
  // nothing in it. A link to another page of the book is also followed by
  // media.js on the touch itself -- see there.
  String linkTag(EpubLink link) => '<a class="hit" href="${_attr(link.href)}"'
      '${_inBook(link.href) ? ' data-go="page"' : ''} '
      'style="${box(link.x, link.y, link.width, link.height)}">'
      '<span class="fill"></span></a>';
  // Buttons, not links: a press on a link that goes nowhere is one Apple
  // Books may take as a tap on the page, and turn it. See the press handling
  // in media.js, which keeps the touch to itself.
  String pressTag(EpubMedia m) =>
      '<button type="button" class="hit${m.video ? "" : " speaker"}" '
      'data-act="toggle" data-target="${_attr(m.id)}" '
      'style="${box(m.x, m.y, m.width, m.height, m.rotation)}'
      '${m.video ? "" : ";border-radius:${_px(m.radius)}"}">'
      '${m.video && m.playButton ? _playButton(m) : ""}</button>';
  String actionTag(EpubAction a) =>
      '<button type="button" class="hit" data-act="${_attr(a.act)}" '
      'data-target="${_attr(a.target)}" data-frame="${a.frame}" '
      'style="${box(a.x, a.y, a.width, a.height)}"></button>';
  var hotspots = interactive
      ? [
          for (var link in page.links)
            if (!inLayer(link.element)) linkTag(link),
          for (var m in page.media)
            if (!inLayer(m.element)) _mediaTag(m, box),
          for (var m in page.media)
            if (m.pressable && m.width > 0 && !inLayer(m.element)) pressTag(m),
          for (var a in page.actions)
            if (!inLayer(a.element)) actionTag(a),
        ].join("\n    ")
      : "";
  var face = stage != null
      ? _stageTag(stage, page, box, [
          for (var m in page.media)
            if (inLayer(m.element)) (m.element!, _mediaTag(m, box)),
          for (var m in page.media)
            if (m.pressable && m.width > 0 && inLayer(m.element))
              (m.element!, pressTag(m)),
          for (var link in page.links)
            if (inLayer(link.element)) (link.element!, linkTag(link)),
          for (var a in page.actions)
            if (inLayer(a.element)) (a.element!, actionTag(a)),
        ])
      : '<img class="page" src="page$index.png" alt="${_text(page.title)}"/>';
  var script = interactive && page.scripted
      ? '\n    <script src="media.js"></script>'
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
      /* Nothing on the page is text a reader can select -- it is pictures --
         and Apple Books shows a text cursor over what it thinks is. */
      html, body { -webkit-user-select: none; user-select: none;
        -webkit-touch-callout: none; cursor: default; }
      body { width: ${page.width}px; height: ${page.height}px; }
      img.page, video.page { width: 100%; height: 100%; display: block; }
      a.hit { position: absolute; display: block; cursor: pointer;
        -webkit-tap-highlight-color: transparent; }
      .hit .fill { display: block; width: 100%; height: 100%; }
      button.hit {
        position: absolute; display: block; margin: 0; padding: 0;
        border: 0; background: transparent; cursor: pointer;
        -webkit-appearance: none; appearance: none;
        -webkit-tap-highlight-color: transparent;
      }
      video.media { position: absolute; display: block; object-fit: cover; }
      .hit.speaker.on { box-shadow: 0 0 0 3px rgba(61, 126, 255, 0.7); }
      .hit .play {
        position: absolute; left: 50%; top: 50%; border-radius: 50%;
        background: rgba(0, 0, 0, 0.55);
      }
      .hit .play span { position: absolute; width: 0; height: 0;
        border-style: solid; border-color: transparent transparent
        transparent #ffffff; }
      .hit.on .play { display: none; }
      .stage { position: absolute; left: 0; top: 0; overflow: hidden;
        width: ${page.width}px; height: ${page.height}px; }
      .stage .page { position: absolute; left: 0; top: 0; }
      .stage img { position: absolute; display: block;
        pointer-events: none; max-width: none; }
      .stage .pic, .stage .slab, .stage .cw, .stage .clip {
        position: absolute; display: block; pointer-events: none; }
      .stage .pic, .stage .slab { overflow: hidden; }
      .stage .pt { position: absolute; left: 0; top: 0; width: 100%;
        height: 100%; overflow: hidden; }
      .layer { position: absolute; left: 0; top: 0; width: 100%;
        height: 100%; pointer-events: none; }
      .layer.moves, .layer.moves .pt { will-change: transform, opacity; }
      .layer .hit { pointer-events: auto; }
      .hit.idle { cursor: default; }
      .layer.hovers:hover > .cw, .layer.hovering > .cw,
      .layer.hovers:hover > .clip, .layer.hovering > .clip,
      .layer.hovers:hover > .cb, .layer.hovering > .cb,
      .layer.hovers:hover > .ca, .layer.hovering > .ca {
        visibility: hidden !important; }
      .layer.hovers:hover > .h, .layer.hovering > .h {
        visibility: visible !important; }
      .layer.switched > .cw, .layer.switched > .clip,
      .layer.switched > .cb, .layer.switched > .ca {
        visibility: hidden !important; }
    </style>
  </head>
  <body>
    $face
    $hotspots$script
  </body>
</html>
''';
}

/// _stageTag is a page laid out as layers: the slabs that do not move and
/// the layers that do, bottom to top, and the presses that belong to each
/// layer's element. Each layer carries its keyframes for the reader to play
/// -- see media.js. Written at frame 0, so that a reader that will not run
/// the script shows the page as its picture does.
String _stageTag(
    EpubStage stage,
    EpubPage page,
    String Function(double, double, double, double, [double]) box,
    List<(String, String)> presses) {
  var marks = [
    for (var m in stage.marks)
      "${m.frame}:${m.kind.name}:${m.target}:${m.repeats}:${m.holdFrames}",
  ].join("|");
  var out = <String>[
    '<div class="stage" id="stage" data-frames="${stage.frames}" '
        'data-rate="${stage.rate}" data-marks="${_attr(marks)}" '
        'data-autoplay="${stage.autoplay && stage.animates}">',
    if (page.soundtrack case var sound?)
      '<audio id="soundtrack" src="${_attr(sound)}" preload="auto"></audio>',
  ];
  var span = stage.frames - 1;

  // A keyframed thing: its frame-0 values written inline for a reader that
  // will not run the script, and all of them for one that will.
  String animated(List<EpubKey> keys, String style) {
    if (keys.isEmpty) return 'style="$style"';
    var inline = [
      for (var MapEntry(:key, :value) in keys.first.css.entries) ...[
        if (key == "transform" || key == "clip-path" || key == "filter")
          "-webkit-$key:$value",
        "$key:$value",
      ],
    ].join(";");
    var attrs = 'style="$style;$inline"';
    if (keys.length == 1 || span <= 0) return attrs;
    var frames = [
      for (var k in keys)
        {
          "offset": double.parse((k.frame / span).toStringAsFixed(6)),
          for (var MapEntry(:key, :value) in k.css.entries) _camel(key): value,
        },
    ];
    return '$attrs data-kf="${_attr(jsonEncode(frames))}"';
  }

  for (var item in stage.items) {
    if (isBackdropVideo(item)) {
      if (stage.backdropVideo case var video?) {
        // The page's own background video, going round as itself.
        out.add('<video class="page" id="backdrop" src="${_attr(video)}" '
            'style="width:${page.width}px;height:${page.height}px;'
            'object-fit:cover" loop="loop" muted="muted" '
            'playsinline="playsinline" preload="auto"></video>');
      }
      continue;
    }
    switch (item) {
      case EpubSlab slab:
        out.add(_spriteTag(slab.sprite, "slab", true, box));
      case EpubLayer layer:
        out.add('<div class="layer${layer.moves ? " moves" : ""}'
            '${layer.hover == null ? "" : " hovers"}" '
            'id="l-${_attr(layer.id)}" '
            '${animated(layer.pose, "transform-origin:${_px(layer.originX)} ${_px(layer.originY)}${layer.visible ? "" : ";display:none"}")}>');
        for (var part in layer.parts) {
          var s = part.sprite;
          out.add('  <div class="cw" '
              '${animated(part.clipKeys, box(s.x, s.y, s.width, s.height))}>'
              '<div class="pt" '
              '${animated(part.keys, "transform-origin:${_px(-s.x)} ${_px(-s.y)}")}>'
              '<img src="${_attr(s.href)}" alt="" '
              'style="left:${_px(-s.sx)};top:${_px(-s.sy)}"/></div></div>');
        }
        if (layer.clip case var clip?) {
          // Its change as a video of it alone, and itself either side.
          if (clip.before case var b?) {
            out.add("  ${_spriteTag(b, "cb", true, box)}");
          }
          var r = clip.rect;
          out.add('  <video class="clip" src="${_attr(clip.href)}" '
              'data-at="${clip.at}" data-n="${clip.frames}" '
              'muted="muted" playsinline="playsinline" preload="auto" '
              'style="${box(r.left, r.top, r.width, r.height)};'
              'visibility:hidden"></video>');
          if (clip.after case var a?) {
            out.add("  ${_spriteTag(a, "ca", false, box)}");
          }
        }
        if (layer.hover case var hover?) {
          out.add("  ${_spriteTag(hover, "h", false, box)}");
        }
        // A chart's key: a picture of the chart for each set of its series
        // switched off, and an entry to press for each series.
        for (var MapEntry(key: mask, value: s) in layer.switched.entries) {
          out.add("  ${_spriteTag(s, "sw", false, box, mask: mask)}");
        }
        for (var (bit, r) in layer.legend) {
          out.add('  <button type="button" class="hit legend" '
              'data-act="series" data-target="${_attr(layer.id)}" '
              'data-bit="$bit" '
              'style="${box(r.left, r.top, r.width, r.height)}"></button>');
        }
        var pressed = false;
        for (var (element, press) in presses) {
          if (element == layer.id) {
            out.add("  $press");
            pressed = true;
          }
        }
        // A button that changes under the pointer but does nothing a book can
        // do still has to be something the pointer can be over.
        var b = layer.hoverBox;
        if (!pressed && b != null) {
          out.add('  <span class="hit idle" '
              'style="${box(b.left, b.top, b.width, b.height)}"></span>');
        }
        out.add('</div>');
    }
  }
  out.add('</div>');
  return out.join("\n    ");
}

String _camel(String css) =>
    css.replaceAllMapped(RegExp(r"-([a-z])"), (m) => m.group(1)!.toUpperCase());

/// _spriteTag is one picture off a sheet: a box the size of the picture, at
/// its place on the page, showing its part of the sheet.
String _spriteTag(EpubSprite s, String kind, bool shown,
        String Function(double, double, double, double, [double]) box,
        {int? mask}) =>
    '<span class="pic $kind"${mask == null ? "" : ' data-mask="$mask"'} '
    'style="${box(s.x, s.y, s.width, s.height)}'
    '${shown ? "" : ";visibility:hidden"}">'
    '<img src="${_attr(s.href)}" alt="" '
    'style="left:${_px(-s.sx)};top:${_px(-s.sy)}"/></span>';

/// _nav is the contents, which EPUB 3 requires whether or not anybody wants
/// one. Hidden, because a document of designed pages has a contents list only
/// if its author drew one.
/// _inBook is whether [href] is another page of this book rather than a web
/// address.
bool _inBook(String href) =>
    href.startsWith("page") && href.endsWith(".xhtml") && !href.contains(":");

/// _playButton is the canvas's big play button, drawn in HTML: a dark disc a
/// quarter of the picture's shorter side across, and a white triangle in it.
/// See video_painter.dart, whose proportions these are.
String _playButton(EpubMedia m) {
  var side = (m.width < m.height ? m.width : m.height) * 0.24;
  var tall = side * 0.4, wide = tall * 0.87;
  return '<span class="play" style="width:${_px(side)};height:${_px(side)};'
      'margin:${_px(-side / 2)} 0 0 ${_px(-side / 2)}">'
      '<span style="left:${_px(side / 2 - wide / 3)};top:${_px(side / 2 - tall / 2)};'
      'border-width:${_px(tall / 2)} 0 ${_px(tall / 2)} ${_px(wide)}"></span>'
      '</span>';
}

/// _mediaTag is one sound or video as the page's HTML, carrying how it plays
/// for media.js to read.
String _mediaTag(EpubMedia m,
    String Function(double, double, double, double, [double]) box) {
  var data = 'id="m-${_attr(m.id)}" '
      'data-list="${_attr(m.sources.join("|"))}" '
      'data-ranges="${m.ranges.map((r) => "${r.$1},${r.$2}").join("|")}" '
      'data-loop="${m.loop}" data-volume="${m.volume}" '
      'data-fadein="${m.fadeIn}" data-fadeout="${m.fadeOut}" '
      'data-autoplay="${m.autoplay}"${m.muted ? ' muted="muted"' : ''}'
      '${m.at == null ? '' : ' data-at="${m.at}" data-spans="${m.spans.join("|")}"'}';
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
  // A video on the playhead is placed by the playhead, below, rather than
  // played by itself.
  var onPlayhead = [];
  all("[data-list]").forEach(function (m) {
    if (m.getAttribute("data-at") !== null) { onPlayhead.push(m); return; }
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
      all('.hit[data-act="toggle"][data-target="' + id + '"]').forEach(function (b) {
        if (m.paused) b.classList.remove("on"); else b.classList.add("on");
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
  // A link to another page is followed on the touch itself, not left to the
  // reader: a fixed-layout page in Apple Books may keep a tap on a link for
  // its own page-turning and never follow it.
  all("a[data-go]").forEach(function (a) {
    var touched = 0;
    a.addEventListener("touchstart", function (e) { e.stopPropagation(); }, false);
    a.addEventListener("touchend", function (e) {
      e.preventDefault(); e.stopPropagation();
      touched = Date.now();
      window.location.href = a.getAttribute("href");
    }, false);
    a.addEventListener("click", function (e) {
      if (Date.now() - touched < 800) { e.preventDefault(); e.stopPropagation(); }
    }, false);
  });

  // A press is kept to itself, from the first touch to the last. Apple Books
  // turns the page on a tap that reaches the page, and a tap it saw the end
  // of as well as the start of reaches it -- so the second press on a
  // speaker, stopping it, also turned the page. The touch ends here, and the
  // click the browser would make of it afterwards is ignored.
  function go(m) { var p = m.play(); if (p && p.catch) p.catch(function () {}); }

  // A page laid out as layers has a playhead of its own, and every animation
  // on it is the reader's own -- keyframes played by the reader's engine,
  // smooth between the canvas's frames -- held to one clock: played, paused
  // and moved together. The clock obeys the timeline's markers as the canvas
  // does, and plays through once and stops on the last frame -- a page is
  // read, and one that started itself over every few seconds would never be
  // finished -- unless a marker loops it.
  var stage = document.getElementById("stage");
  if (stage) {
    var runs = function (text, read) {
      var out = [];
      (text || "").split("|").forEach(function (run) {
        if (!run) return;
        var p = run.split("*"), n = p.length > 1 ? parseInt(p[1], 10) : 1, v = read(p[0]);
        for (var i = 0; i < n; i++) out.push(v);
      });
      return out;
    };
    var frames = parseInt(stage.getAttribute("data-frames") || "1", 10);
    var rate = parseFloat(stage.getAttribute("data-rate") || "24");
    var length = Math.max(0, frames - 1) / rate;
    var marks = runs(stage.getAttribute("data-marks"), function (v) {
      var p = v.split(":");
      return { f: parseInt(p[0], 10), k: p[1], t: parseInt(p[2], 10),
        r: parseInt(p[3], 10), h: parseInt(p[4], 10) };
    });

    // The animations: one for each thing that moves, all as long as the page.
    var anims = [];
    all("[data-kf]").forEach(function (el) {
      if (!el.animate) return;
      var kf;
      try { kf = JSON.parse(el.getAttribute("data-kf")); } catch (e) { return; }
      try {
        var a = el.animate(kf, { duration: Math.max(1, length * 1000), fill: "both", easing: "linear" });
        a.pause();
        a.currentTime = 0;
        anims.push(a);
      } catch (e) {}
    });

    // What the pointer is over, for a reader that does not pass :hover up
    // to the layer: the press says so itself.
    all(".layer").forEach(function (l) {
      Array.prototype.slice.call(l.getElementsByClassName("hit")).forEach(function (h) {
        h.addEventListener("mouseenter", function () { l.classList.add("hovering"); });
        h.addEventListener("mouseleave", function () { l.classList.remove("hovering"); });
      });
    });

    var t = 0, playing = false, since = 0, holdUntil = 0, stopAt = -1, counts = {}, done = -1;

    // What follows the playhead besides the animations: each video on it, an
    // element's change filmed on its own, and the page's soundtrack. Each is
    // put where it should be every time the clock moves -- moved only when it
    // has drifted, so a playing one is left to play.
    var followers = onPlayhead.map(function (m) {
      var list = m.getAttribute("data-list").split("|");
      var starts = (m.getAttribute("data-ranges") || "").split("|").map(function (r) {
        return parseFloat(r.split(",")[0]) || 0;
      });
      var spans = (m.getAttribute("data-spans") || "").split("|").map(parseFloat);
      var at = parseInt(m.getAttribute("data-at") || "0", 10);
      var loop = m.getAttribute("data-loop") || "none";
      var file = -1, wanted = 0;
      m.muted = true;
      m.addEventListener("loadedmetadata", function () {
        try { m.currentTime = wanted; } catch (e) {}
      });
      // Which file, and where in it, t seconds after it starts: the same
      // answer as MediaClip.momentAt.
      var moment = function (t) {
        var total = 0;
        spans.forEach(function (s) { if (s > 0) total += s; });
        if (t < 0 || total <= 0) return null;
        if (t >= total) { if (loop === "none") return null; t = t % total; }
        var from = 0;
        for (var i = 0; i < spans.length; i++) {
          if (!(spans[i] > 0)) continue;
          if (t < from + spans[i]) return [i, starts[i] + t - from];
          from += spans[i];
        }
        return null;
      };
      return function (seconds, on) {
        var here = seconds - at / rate;
        var mo = moment(here);
        if (!mo) {
          if (!m.paused) m.pause();
          if (here < 0 && file !== 0 && list.length) { file = 0; wanted = starts[0]; m.src = list[0]; m.load(); }
          return;
        }
        if (mo[0] !== file) { file = mo[0]; wanted = mo[1]; m.src = list[file]; m.load(); }
        else if (Math.abs(m.currentTime - mo[1]) > (on ? 0.3 : 0.05)) {
          wanted = mo[1];
          try { m.currentTime = mo[1]; } catch (e) {}
        }
        if (on && m.paused) go(m);
        else if (!on && !m.paused) m.pause();
      };
    });
    all("video.clip").forEach(function (v) {
      var at = parseInt(v.getAttribute("data-at") || "0", 10) / rate;
      var last = (parseInt(v.getAttribute("data-n") || "1", 10) - 1) / rate;
      var layer = v.parentNode;
      var before = layer.getElementsByClassName("cb")[0], after = layer.getElementsByClassName("ca")[0];
      var show = function (el, on) { if (el) el.style.visibility = on ? "visible" : "hidden"; };
      v.muted = true;
      followers.push(function (seconds, on) {
        var here = seconds - at;
        var inside = here >= 0 && here <= last;
        show(before, here < 0);
        show(after, here > last);
        show(v, inside);
        var want = Math.max(0, Math.min(last, here));
        if (Math.abs(v.currentTime - want) > (on && inside ? 0.2 : 0.03)) {
          try { v.currentTime = want; } catch (e) {}
        }
        if (on && inside && v.paused) go(v);
        else if (!(on && inside) && !v.paused) v.pause();
      });
    });
    var soundtrack = document.getElementById("soundtrack");
    if (soundtrack) {
      followers.push(function (seconds, on) {
        var a = soundtrack;
        if (isFinite(a.duration) && seconds >= a.duration) { if (!a.paused) a.pause(); return; }
        if (Math.abs(a.currentTime - seconds) > (on ? 0.25 : 0.05)) {
          try { a.currentTime = seconds; } catch (e) {}
        }
        if (on && a.paused) go(a);
        else if (!on && !a.paused) a.pause();
      });
    }

    var now = function () { return window.performance && performance.now ? performance.now() : Date.now(); };
    var later = window.requestAnimationFrame ? function (f) { window.requestAnimationFrame(f); }
      : function (f) { setTimeout(function () { f(now()); }, 16); };
    var holding = function () { return holdUntil > now(); };
    var follow = function () {
      var on = playing && !holding();
      followers.forEach(function (f) { f(t, on); });
    };
    // Everything to [seconds], and playing on from there if the clock is.
    var place = function (seconds) {
      t = Math.max(0, Math.min(length, seconds));
      anims.forEach(function (a) { try { a.currentTime = t * 1000; } catch (e) {} });
      since = now() - t * 1000;
      done = Math.floor(t * rate + 1e-6);
      follow();
    };
    var pause = function () {
      playing = false;
      anims.forEach(function (a) { try { a.pause(); a.currentTime = t * 1000; } catch (e) {} });
      follow();
    };
    var play = function () {
      if (playing || frames <= 1) return;
      if (t >= length) { counts = {}; place(0); }
      playing = true;
      since = now() - t * 1000;
      anims.forEach(function (a) { try { a.currentTime = t * 1000; a.play(); } catch (e) {} });
      follow();
      later(tick);
    };
    // The clock: where the animations have got to, and the markers on the
    // frames they have passed since last time.
    var tick = function () {
      if (!playing) return;
      if (holding()) {
        since = now() - t * 1000;
        later(tick);
        return;
      }
      var seconds = (now() - since) / 1000;
      var frame = Math.floor(seconds * rate + 1e-6);
      for (var f = done + 1; f <= frame && playing; f++) {
        done = f;
        for (var i = 0; i < marks.length && playing; i++) {
          var m = marks[i];
          if (m.f !== f) continue;
          if (m.k === "stop") { place(f / rate); pause(); return; }
          if (m.k === "pause") {
            // Held where it is for a moment, then on.
            place(f / rate);
            anims.forEach(function (a) { try { a.pause(); } catch (e) {} });
            holdUntil = now() + m.h / rate * 1000;
            setTimeout(function () {
              if (!playing) return;
              since = now() - t * 1000;
              anims.forEach(function (a) { try { a.currentTime = t * 1000; a.play(); } catch (e) {} });
              follow();
            }, m.h / rate * 1000);
            follow();
            later(tick);
            return;
          }
          if (m.k === "loop") {
            counts[m.f] = (counts[m.f] || 0) + 1;
            if (m.r === 0 || counts[m.f] <= m.r) {
              place(Math.max(0, Math.min(frames - 1, m.t)) / rate);
              later(tick);
              return;
            }
          } else if (m.k === "jump") {
            place(Math.max(0, Math.min(frames - 1, m.t)) / rate);
            later(tick);
            return;
          }
        }
        if (stopAt >= 0 && f === stopAt) { stopAt = -1; place(f / rate); pause(); return; }
      }
      if (seconds >= length) { place(length); pause(); return; }
      t = seconds;
      follow();
      later(tick);
    };
    // The playhead's buttons are aimed at "film": see filmTarget.
    media.film = { clock: true, act: function (act, f) {
      switch (act) {
        case "restart": stopAt = -1; counts = {}; place(0); if (!playing) play(); return;
        case "goto": stopAt = -1; pause(); place(f / rate); return;
        case "playfrom": stopAt = -1; place(f / rate); if (!playing) play(); return;
        case "playto": stopAt = f; if (t >= length) place(0); if (!playing) play(); return;
        case "play": play(); return;
        case "pause": pause(); return;
        case "toggle": if (playing) pause(); else play(); return;
      }
    } };
    // Shown and hidden by a button, the way the canvas flips an element.
    all(".layer").forEach(function (l) {
      media[l.id.substring(2)] = { layer: l };
    });
    // A background video goes round by itself under the page.
    var backdrop = document.getElementById("backdrop");
    if (backdrop) go(backdrop);
    place(0);
    if (stage.getAttribute("data-autoplay") === "true") play();
  }

  all("[data-act]").forEach(function (b) {
    var touched = 0;
    function run() {
      var t = media[b.getAttribute("data-target")];
      if (!t) return;
      var frame = parseInt(b.getAttribute("data-frame") || "0", 10);
      if (t.clock) { t.act(b.getAttribute("data-act"), frame); return; }
      if (t.layer) {
        if (b.getAttribute("data-act") === "showhide") {
          t.layer.style.display = t.layer.style.display === "none" ? "" : "none";
        } else if (b.getAttribute("data-act") === "series") {
          // A series of a chart switched on or off, as its key does on the
          // canvas: the chart with that set of series switched is shown in
          // place of the chart as it plays, and put back when none are.
          var L = t.layer;
          var mask = (parseInt(L.getAttribute("data-mask") || "0", 10) ^
            (1 << parseInt(b.getAttribute("data-bit") || "0", 10)));
          L.setAttribute("data-mask", "" + mask);
          Array.prototype.slice.call(L.getElementsByClassName("sw")).forEach(function (s) {
            s.style.visibility = s.getAttribute("data-mask") === "" + mask ? "visible" : "hidden";
          });
          if (mask) L.classList.add("switched"); else L.classList.remove("switched");
        }
        return;
      }
      var m = t.m, act = b.getAttribute("data-act");
      if (act === "play" || (act === "toggle" && m.paused)) {
        var p = m.play(); if (p && p.catch) p.catch(function () {});
      } else if (act === "pause" || act === "toggle") m.pause();
      else if (act === "stop") t.stop();
      else if (act === "mute") m.muted = !m.muted;
    }
    function keep(e) { e.preventDefault(); e.stopPropagation(); }
    b.addEventListener("touchstart", function (e) { e.stopPropagation(); }, false);
    b.addEventListener("touchmove", function (e) { e.stopPropagation(); }, false);
    b.addEventListener("touchend", function (e) {
      keep(e);
      touched = Date.now();
      run();
    }, false);
    b.addEventListener("click", function (e) {
      keep(e);
      if (Date.now() - touched < 800) return;
      run();
    }, false);
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
    if (interactive && pages.any((p) => p.scripted))
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
        // A cover in a book of spreads stands alone in the middle, and says
        // so: left unsaid, a reader lays it into half a spread.
        EpubSide.centre =>
          facing ? ' properties="rendition:page-spread-center"' : '',
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
