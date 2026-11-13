import 'dart:math' as math;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:archive/archive.dart';
import 'package:bruig/plugin_system/canvas/export/epub_layers.dart';

// epub_writer.dart writes a document of pages as an EPUB.
//
// Fixed layout, one picture to a page: a canvas is a design, and reflowing
// it would throw the design away, so every page is declared pre-paginated at
// its own size. Written by hand because an EPUB is a zip of a few short XML
// files.

/// EpubSide is which half of a spread a page belongs on, for a reader showing
/// two at a time. Said per page because a reader cannot work it out: it
/// depends on the covers.
enum EpubSide { left, right, centre }

/// EpubLink is a rectangle on a page that goes somewhere when it is pressed,
/// in the page picture's pixels from the top left.
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
/// A sound has no size unless it can be pressed. How it plays is written onto
/// the HTML element for media.js to read, so one script serves every page.
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
  /// playing. Only a sound gets the ring.
  final double radius;

  /// playButton draws the canvas's big play button over a video while it is
  /// stopped: the one in the page picture is covered by the video.
  final bool playButton;

  /// at is the frame of the page's playhead it starts on, for a video on the
  /// timeline of a page laid out as layers: it follows the playhead, silent
  /// (its sound is in the page's soundtrack). Null for one on its own clock.
  final int? at;

  /// spans are how long each file's range plays, in seconds, for [at]: what
  /// the playhead is placed against.
  final List<double> spans;

  /// element is the element it was made from, so that on a page laid out as
  /// layers it sits and moves in the element's layer.
  final String? element;

  /// opacity and blend are the element's: how much of it shows, and the CSS
  /// mix-blend-mode it is laid on the page with (null for normal). A rain
  /// video screened at a tenth played full and black over the page (Ken,
  /// 2026-11-13).
  final double opacity;
  final String? blend;

  /// speed is how fast a video on the playhead plays: 0.5 at half speed, as
  /// MediaClip.speed. The book's Rain went round twice as fast as the
  /// canvas's, and jumped back each time.
  final double speed;

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
    this.opacity = 1,
    this.blend,
    this.speed = 1,
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

/// EpubStart is a title page folded into the page it starts: shown over it
/// until a press plays it. A press on one page cannot let the next play its
/// sound, nor can one page load the next's, in Apple Books -- the Decred
/// infographic's title Play went to a page that asked for a Play again --
/// so the title is the start screen of the page it plays.
class EpubStart {
  /// picture is the title page without its Play, and play the Play alone,
  /// both PNGs; at is where the Play goes, in the page's pixels.
  final Uint8List picture;
  final Uint8List play;
  final Rect at;

  const EpubStart(
      {required this.picture, required this.play, required this.at});
}

/// EpubPage is one leaf: a picture, its size, and anything on it that can be
/// pressed or played.
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

  /// start is the title page shown over this one until it is played, in
  /// place of the page itself under a Play. See EpubStart.
  final EpubStart? start;

  /// plays is whether the page has sound or video for media.js to run, and
  /// scripted whether it needs media.js at all.
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
    this.start,
  });
}

/// filmTarget is what a playhead button on a page aims at: the page's
/// playhead, named "film" in media.js.
const String filmTarget = "film";

/// epubMime is what an EPUB is, and what goes in the archive's first entry.
const String epubMime = "application/epub+zip";

/// writeEpub packs the pages into the bytes of an .epub file.
///
/// [interactive] adds the links, media, presses and layers, and media.js for
/// the pages that need it. Without it the book is pictures only.
Uint8List writeEpub({
  required List<EpubPage> pages,
  required String title,
  String author = "",
  String? identifier,
  bool interactive = false,
  bool facing = false,

  /// cover is the book's cover picture, an opaque PNG of its own, where
  /// there is one: else the cover page's picture stands in.
  Uint8List? cover,
}) {
  if (pages.isEmpty) {
    throw ArgumentError("an EPUB needs at least one page");
  }
  var id = identifier ?? "urn:uuid:${_uuidFrom(title, pages.length)}";
  var archive = Archive();

  // The mimetype first and uncompressed: a reader identifies an EPUB by these
  // exact bytes at a fixed offset.
  var mime = ascii.encode(epubMime);
  archive.addFile(ArchiveFile("mimetype", mime.length, mime)
    ..compression = CompressionType.none);

  _add(archive, "META-INF/container.xml", _container);
  // Without these Apple Books opens a fixed-layout book as if it might flow,
  // showing a stretched cover while it decides.
  _add(archive, "META-INF/com.apple.ibooks.display-options.xml",
      _appleOptions(interactive));

  // Each file once, however many pages play it.
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
      // Already deflated inside the PNG.
      ..compression = CompressionType.none);
  }
  // The start screens' pictures: see EpubStart.
  var starts = <EpubFile>[
    for (var (i, page) in pages.indexed)
      if (interactive && page.start != null && page.stage != null) ...[
        EpubFile("start$i.png", page.start!.picture, "image/png"),
        EpubFile("start$i-play.png", page.start!.play, "image/png"),
      ],
    if (cover != null) EpubFile("cover.png", cover, "image/png"),
  ];
  for (var f in starts) {
    archive.addFile(ArchiveFile("OEBPS/${f.href}", f.bytes.length, f.bytes)
      ..compression = CompressionType.none);
  }

  _add(archive, "OEBPS/nav.xhtml", _nav(pages));
  _add(
      archive,
      "OEBPS/content.opf",
      _opf(pages, title, author, id, interactive, facing,
          [...carried.values, ...starts.where((f) => f.href != "cover.png")],
          cover: cover != null));

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
/// Without the viewport a reader falls back to reflowing the page.
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
  // Under a camera, the presses go where it moves what they press.
  var framed = stage != null && stage.camera.isNotEmpty;
  var face = stage != null
      ? _stageTag(
          stage,
          page,
          box,
          poster: "page$index.png",
          start: page.start == null ? null : "start$index",
          inside: framed ? hotspots : "",
          [
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
      /* No size of its own: what is in it is placed from the page's corner
         and shows past it, so a layer is drawn as big as what it paints, not
         a page each -- a hundred page-sized layers that move stuttered
         (Ken, 2026-11-13). */
      .layer { position: absolute; left: 0; top: 0; width: 0;
        height: 0; overflow: visible; pointer-events: none; }
      .layer.moves, .layer.moves .pt { will-change: transform, opacity; }
      .layer .hit { pointer-events: auto; }
      .rx { position: absolute; left: 0; top: 0; width: 0;
        height: 0; overflow: visible; pointer-events: none; }
      /* The start: the page as it ends up, a Play and how much has loaded. */
      .intro { position: absolute; left: 0; top: 0; width: 100%;
        height: 100%; z-index: 5; }
      .stage .intro img { width: 100%; height: 100%; left: 0; top: 0; }
      .intro .veil { position: absolute; left: 0; top: 0; width: 100%;
        height: 100%; background: rgba(0, 0, 0, 0.55); }
      button.start { position: absolute; margin: 0; padding: 0;
        border-style: solid; border-color: #ffffff; border-radius: 50%;
        background: rgba(0, 0, 0, 0.6); cursor: pointer; opacity: 0.4;
        -webkit-appearance: none; appearance: none;
        -webkit-tap-highlight-color: transparent; }
      button.start.ready { opacity: 1; }
      button.start.title { border: none; border-radius: 0; background: none;
        opacity: 1; }
      .stage .intro button.start.title img { position: absolute; left: 0;
        top: 0; width: 100%; height: 100%; }
      button.start span { position: absolute; width: 0; height: 0;
        border-style: solid; border-color: transparent transparent
        transparent #ffffff; }
      .intro .bar { position: absolute; overflow: hidden;
        background: rgba(255, 255, 255, 0.2); }
      .intro .bar span { display: block; height: 100%; width: 0;
        background: #2ed6a1; }
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
    <span id="play"></span>
    $face
    ${framed ? "" : hotspots}$script
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
    List<(String, String)> presses,
    {String? poster,
    String? start,
    String inside = ""}) {
  var marks = [
    for (var m in stage.marks)
      "${m.frame}:${m.kind.name}:${m.target}:${m.repeats}:${m.holdFrames}",
  ].join("|");
  var out = <String>[
    '<div class="stage" id="stage" data-frames="${stage.frames}" '
        'data-rate="${stage.rate}" data-marks="${_attr(marks)}" '
        'data-autoplay="${stage.autoplay && stage.animates}" '
        'data-intro="${stage.animates}">',
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

  // The Camera: everything on the stage but its start screen, framed as the
  // camera frames the canvas -- moved and scaled as one.
  if (stage.camera.isNotEmpty) {
    out.add('<div class="cam" ${animated(stage.camera, "position:absolute;"
        "left:0;top:0;width:${page.width}px;height:${page.height}px;"
        "transform-origin:0 0;-webkit-transform-origin:0 0")}>');
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
        // A video laid on as light or shade: blended as its layer, with the
        // page under it -- inside the layer it would blend with nothing.
        var blend = page.media
            .where((m) => m.element == layer.id && m.blend != null)
            .map((m) => m.blend)
            .firstOrNull;
        out.add('<div class="layer${layer.moves ? " moves" : ""}'
            '${layer.hover == null ? "" : " hovers"}" '
            'id="l-${_attr(layer.id)}" '
            '${animated(layer.pose, "transform-origin:${_px(layer.originX)} ${_px(layer.originY)}${layer.visible ? "" : ";display:none"}${blend == null ? "" : ";mix-blend-mode:$blend"}")}>');
        // Its reactions -- clips it plays on a click or after another clip
        // -- on a wrapper round it, so they go over its place on the
        // timeline rather than instead of it. Not on a layer that changes
        // under the pointer or by its key, whose rules name its pictures
        // as its own children.
        var reacts = layer.reactions.isNotEmpty &&
            layer.hover == null &&
            layer.switched.isEmpty;
        if (reacts) {
          var list = [
            for (var r in layer.reactions)
              {
                "c": r.clip,
                "on": r.on,
                "ms": (r.frames / math.max(1, stage.rate) * 1000).round(),
                "kf": [
                  for (var k in r.keys)
                    {
                      "offset": double.parse(
                          (k.frame / math.max(1, r.frames)).toStringAsFixed(6)),
                      for (var MapEntry(:key, :value) in k.css.entries)
                        _camel(key): value,
                    },
                ],
                if (r.sound != null) "s": r.sound,
                if (r.sound != null)
                  "v": double.parse(r.volume.toStringAsFixed(3)),
              },
          ];
          out.add('  <div class="rx" data-rx="${_attr(jsonEncode(list))}" '
              'style="transform-origin:${_px(layer.originX)} ${_px(layer.originY)}">');
        }
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
        if (reacts) out.add('  </div>');
        out.add('</div>');
    }
  }
  // Where a click starts a reaction: over everything, so whatever is drawn
  // above the element it lands on, it lands.
  for (var (id, r) in stage.clickable) {
    out.add('<button type="button" class="hit react" data-act="react" '
        'data-target="${_attr(id)}" aria-label="${_attr(id)}" '
        'style="${box(r.left, r.top, r.width, r.height)}"></button>');
  }
  for (var sound in stage.sounds) {
    out.add('<audio class="rxs" src="${_attr(sound)}" preload="auto"></audio>');
  }
  if (stage.camera.isNotEmpty) {
    // The presses outside the layers, framed with the rest.
    if (inside.isNotEmpty) out.add(inside);
    out.add('</div>');
  }
  // The start (Ken, 2026-11-13: the book opened blank, its Play not yet
  // arrived, and slowly): the page as it ends up -- all a reader that runs
  // no script shows -- and, for one that does, a Play over it and a bar of
  // how much has loaded. Pressed, it plays from the top with its sound,
  // which a reader lets start only on a press.
  if (stage.animates && poster != null) {
    var w = page.width.toDouble(), h = page.height.toDouble();
    var barH = math.max(6.0, h * 0.006);
    // The bar where the Play will be, and the Play in its place once all
    // has loaded (Ken, 2026-11-13: a Play pressed before the page was ready
    // did nothing the first time, and nothing said why).
    String bar(double cx, double cy, double barW) =>
        '<div class="bar" id="bar" style="display:none;'
        'left:${_px(cx - barW / 2)};top:${_px(cy - barH / 2)};'
        'width:${_px(barW)};height:${_px(barH)};'
        'border-radius:${_px(barH / 2)}"><span id="barFill"></span></div>';
    if (page.start case var title? when start != null) {
      // A title page folded in (see EpubStart): its picture, and its own
      // Play where it was drawn.
      var at = title.at;
      out.add('<div class="intro" id="intro">'
          '<img src="${_attr(start)}.png" alt="${_text(page.title)}"/>'
          '<button type="button" class="start title" id="start" '
          'aria-label="Play" style="display:none;'
          '${box(at.left, at.top, at.width, at.height)}">'
          '<img src="${_attr(start)}-play.png" alt="Play"/></button>'
          '${bar(at.center.dx, at.center.dy, at.width * 0.9)}'
          '</div>');
    } else {
      var d = math.min(w, h) * 0.2;
      var tall = d * 0.42, wide = tall * 0.87;
      out.add('<div class="intro" id="intro">'
          '<img src="${_attr(poster)}" alt="${_text(page.title)}"/>'
          '<div class="veil" style="display:none"></div>'
          '<button type="button" class="start" id="start" aria-label="Play" '
          'style="display:none;left:${_px((w - d) / 2)};top:${_px((h - d) / 2)};'
          'width:${_px(d)};height:${_px(d)};border-width:${_px(d * 0.035)}">'
          '<span style="left:${_px(d / 2 - wide / 3)};top:${_px(d / 2 - tall / 2)};'
          'border-width:${_px(tall / 2)} 0 ${_px(tall / 2)} ${_px(wide)}"></span>'
          '</button>'
          '${bar(w / 2, h / 2, w * 0.4)}'
          '</div>');
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

/// _inBook is whether [href] is another page of this book rather than a web
/// address.
bool _inBook(String href) => RegExp(r"^page\d+\.xhtml(#play)?$").hasMatch(href);

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
      '${m.at == null ? '' : ' data-at="${m.at}" data-spans="${m.spans.join("|")}"'}'
      '${m.at == null || m.speed == 1 ? '' : ' data-speed="${m.speed}"'}';
  if (!m.video) return '<audio $data preload="auto"></audio>';
  return '<video class="media" $data playsinline="playsinline" '
      'preload="metadata"${m.controls ? ' controls="controls"' : ''}'
      '${m.poster == null ? '' : ' poster="${_attr(m.poster!)}"'} '
      'style="${box(m.x, m.y, m.width, m.height, m.rotation)}'
      '${m.opacity < 1 ? ";opacity:${m.opacity.toStringAsFixed(3)}" : ""}'
      '${m.blend != null && m.element == null ? ";mix-blend-mode:${m.blend}" : ""}"></video>';
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

    // The reactions: clips an element plays on a click on the page, or when
    // another clip ends -- each over its own length, with its sound, then
    // let go, and what follows it started. See EpubReaction.
    var reactions = [];
    all(".rx[data-rx]").forEach(function (el) {
      var list;
      try { list = JSON.parse(el.getAttribute("data-rx")); } catch (e) { return; }
      list.forEach(function (r) { r.el = el; reactions.push(r); });
    });
    var reactionSounds = {};
    all("audio.rxs").forEach(function (a) { reactionSounds[a.getAttribute("src")] = a; });
    var react = function (on, depth) {
      if (depth > 16) return;
      reactions.forEach(function (r) {
        if (r.on !== on) return;
        if (r.el.animate) {
          try {
            if (r.a) r.a.cancel();
            r.a = r.el.animate(r.kf, { duration: Math.max(1, r.ms), fill: "none", easing: "linear" });
          } catch (e) {}
        }
        var s = r.s && reactionSounds[r.s];
        if (s) {
          try {
            s.pause(); s.currentTime = 0; s.volume = Math.max(0, Math.min(1, r.v || 1));
            var p = s.play(); if (p && p.catch) p.catch(function () {});
          } catch (e) {}
        }
        setTimeout(function () { react("end:" + r.c, depth + 1); }, Math.max(1, r.ms));
      });
    };
    media.react = function (on) { react(on, 0); };

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
      var speed = parseFloat(m.getAttribute("data-speed") || "1") || 1;
      var file = -1, wanted = 0;
      m.muted = true;
      var paced = function () {
        try { m.defaultPlaybackRate = speed; m.playbackRate = speed; } catch (e) {}
      };
      paced();
      m.addEventListener("loadedmetadata", function () {
        try { m.currentTime = wanted; } catch (e) {}
        paced();
      });
      // Which file, and where in it, t seconds after it starts: the same
      // answer as MediaClip.momentAt.
      var moment = function (t) {
        var total = 0;
        spans.forEach(function (s) { if (s > 0) total += s; });
        total /= speed;
        if (t < 0 || total <= 0) return null;
        if (t >= total) { if (loop === "none") return null; t = t % total; }
        // Into the files at their speed: the spans are their own seconds.
        t *= speed;
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
    // The soundtrack, playing, is the clock (see tick): it is moved only
    // when the playhead is put somewhere, never to catch the clock up --
    // each such move a gap in the sound (Ken, 2026-11-13: the book's music
    // stuttered).
    var soundtrack = document.getElementById("soundtrack");
    var placed = true;
    if (soundtrack) {
      followers.push(function (seconds, on) {
        var a = soundtrack;
        if (isFinite(a.duration) && seconds >= a.duration) { if (!a.paused) a.pause(); return; }
        if ((placed || a.paused) && Math.abs(a.currentTime - seconds) > 0.05) {
          try { a.currentTime = seconds; } catch (e) {}
        }
        if (on && a.paused) go(a);
        else if (!on && !a.paused) a.pause();
      });
    }
    // Where the sound has got to, when it is the clock: playing, and not
    // past its end.
    var heard = function () {
      var a = soundtrack;
      if (!a || a.paused || a.seeking || a.readyState < 3) return -1;
      if (isFinite(a.duration) && a.currentTime >= a.duration - 0.05) return -1;
      return a.currentTime;
    };

    var now = function () { return window.performance && performance.now ? performance.now() : Date.now(); };
    var later = window.requestAnimationFrame ? function (f) { window.requestAnimationFrame(f); }
      : function (f) { setTimeout(function () { f(now()); }, 16); };
    var holding = function () { return holdUntil > now(); };
    var follow = function () {
      var on = playing && !holding();
      followers.forEach(function (f) { f(t, on); });
      placed = false;
    };
    // Everything to [seconds], and playing on from there if the clock is.
    var place = function (seconds) {
      placed = true;
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
      // With a soundtrack, everything starts when its sound does: a sound
      // takes a moment to start, and the page would be ahead of it.
      var started = false;
      var run = function () {
        if (started || !playing) return;
        started = true;
        since = now() - t * 1000;
        anims.forEach(function (a) { try { a.currentTime = t * 1000; a.play(); } catch (e) {} });
        follow();
        later(tick);
      };
      var a = soundtrack;
      if (a && a.paused && !(isFinite(a.duration) && t >= a.duration)) {
        try { a.currentTime = t; } catch (e) {}
        // run is once only: a later "playing" finds it started.
        a.addEventListener("playing", run);
        go(a);
        setTimeout(run, 700);
      } else run();
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
      // Kept to the sound: where it has drifted from the page's clock, the
      // clock and the animations go to it.
      var sound = heard();
      if (sound >= 0 && Math.abs(sound - seconds) > 0.1) {
        seconds = sound;
        since = now() - seconds * 1000;
        anims.forEach(function (x) { try { x.currentTime = seconds * 1000; } catch (e) {} });
      }
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
    // A background video goes round by itself under the page: from the
    // start, or with the Play behind a start screen -- whose loading loads
    // it again, which would stop it.
    var backdrop = document.getElementById("backdrop");
    var round = function () { if (backdrop && backdrop.paused) go(backdrop); };
    place(0);
    var intro = document.getElementById("intro");
    if (intro && stage.getAttribute("data-intro") === "true") {
      // The start: everything fetched before the first press, the bar
      // filling as it comes; the press plays from the top.
      var start = document.getElementById("start");
      var bar = document.getElementById("bar");
      var fill = document.getElementById("barFill");
      var veil = intro.getElementsByClassName("veil")[0];
      if (veil) veil.style.display = "";
      // The bar first, where the Play will be; the Play once all is in.
      start.style.display = "";
      start.style.visibility = "hidden";
      bar.style.display = "";
      var total = 0, loaded = 0, ready = false;
      var progress = function () {
        fill.style.width = (total ? Math.round(loaded / total * 100) : 100) + "%";
        if (!ready && loaded >= total) {
          ready = true;
          start.className += " ready";
          bar.style.visibility = "hidden";
          start.style.visibility = "";
        }
      };
      var waitFor = function (el, events) {
        var once = false;
        var done = function () { if (once) return; once = true; loaded++; progress(); };
        total++;
        events.forEach(function (ev) { el.addEventListener(ev, done); });
        // Never held up for ever by one that does not come.
        setTimeout(done, 20000);
        return done;
      };
      all(".stage img").forEach(function (img) {
        if (img.complete) return;
        waitFor(img, ["load", "error"]);
      });
      all(".stage video, .stage audio").forEach(function (m) {
        if (m.readyState >= 3) return;
        waitFor(m, ["canplaythrough", "error"]);
        try { m.preload = "auto"; m.load(); } catch (e) {}
      });
      // Come to by a Play on another page (a link to #play): no second
      // press -- it plays as soon as it has loaded. A reader that holds the
      // sound back until a press on this page leaves the Play to press.
      var asked = window.location.hash === "#play";
      var begin = function () {
        intro.style.display = "none";
        round();
        place(0);
        play();
        var sound = document.getElementById("soundtrack");
        if (asked && sound) {
          setTimeout(function () {
            if (playing && sound.paused && t < (sound.duration || 1e9)) {
              pause();
              place(0);
              asked = false;
              intro.style.display = "";
            }
          }, 700);
        }
      };
      progress = (function (shown) {
        return function () {
          shown();
          if (ready && asked === true) {
            asked = "started";
            begin();
          }
        };
      })(progress);
      progress();
      start.addEventListener("click", function (e) {
        e.preventDefault(); e.stopPropagation();
        asked = false;
        begin();
      });
    } else {
      round();
      if (stage.getAttribute("data-autoplay") === "true") play();
    }
  }

  all("[data-act]").forEach(function (b) {
    var touched = 0;
    function run() {
      // A click that starts reactions: see media.react.
      if (b.getAttribute("data-act") === "react") {
        if (media.react) media.react("click:" + b.getAttribute("data-target"));
        return;
      }
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

/// _nav is the contents, which EPUB 3 requires. Hidden: a document of
/// designed pages has a contents list only if its author drew one.
String _nav(List<EpubPage> pages) {
  var items = [
    for (var (i, page) in pages.indexed)
      '<li><a href="page$i.xhtml">${_text(page.title)}</a></li>',
  ].join("\n        ");
  // Where the cover is and where the book begins, which a reader asks
  // before it has opened a page.
  var coverAt = math.max(0, pages.indexWhere((p) => p.cover));
  var bodyAt = pages.length > 1 && coverAt == 0 ? 1 : 0;
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
    <nav epub:type="landmarks" id="landmarks" hidden="hidden">
      <h1>Landmarks</h1>
      <ol>
        <li><a epub:type="cover" href="page$coverAt.xhtml">Cover</a></li>
        <li><a epub:type="bodymatter" href="page$bodyAt.xhtml">Start</a></li>
      </ol>
    </nav>
  </body>
</html>
''';
}

/// _opf is the package: what is in the book, and in what order.
String _opf(List<EpubPage> pages, String title, String author, String id,
    bool interactive, bool facing, Iterable<EpubFile> files,
    {bool cover = false}) {
  var coverAt = pages.indexWhere((p) => p.cover);
  var manifest = <String>[
    if (cover)
      '<item id="cover" href="cover.png" media-type="image/png" '
          'properties="cover-image"/>',
    '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" '
        'properties="nav"/>',
    for (var (i, page) in pages.indexed) ...[
      '<item id="page$i" href="page$i.xhtml" '
          'media-type="application/xhtml+xml"'
          '${interactive && page.scripted ? ' properties="scripted"' : ''}/>',
      '<item id="img$i" href="page$i.png" media-type="image/png"'
          '${i == coverAt && !cover ? ' properties="cover-image"' : ''}/>',
    ],
    // A reader will not open a file the manifest does not list.
    for (var (i, f) in files.indexed)
      '<item id="media$i" href="${_attr(f.href)}" media-type="${f.mime}"/>',
    if (interactive && pages.any((p) => p.scripted))
      '<item id="script" href="media.js" media-type="application/javascript"/>',
  ].join("\n    ");

  // Which side of the spine each page belongs on: see EpubSide.
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
${cover ? '    <meta name="cover" content="cover"/>\n' : coverAt < 0 ? "" : '    <meta name="cover" content="img$coverAt"/>\n'}  </metadata>
  <manifest>
    $manifest
  </manifest>
  <spine>
    $spine
  </spine>
  <guide>
    <reference type="cover" title="Cover" href="page${math.max(0, coverAt)}.xhtml"/>
  </guide>
</package>
''';
}

String _px(double v) => "${v.toStringAsFixed(2)}px";

/// _text escapes for XML character data, and _attr for an attribute.
String _text(String s) =>
    s.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");

String _attr(String s) => _text(s).replaceAll('"', "&quot;");

/// _uuidFrom makes a stable identifier out of what the book is, so the same
/// document exported twice keeps its bookmarks: a reader keeps a place by
/// identifier.
String _uuidFrom(String title, int pages) {
  var seed = "$title/$pages";
  var hash = 0x811c9dc5;
  for (var unit in utf8.encode(seed)) {
    hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  var hex = hash.toRadixString(16).padLeft(8, "0");
  return "$hex-0000-4000-8000-${hex.padLeft(12, "0").substring(0, 12)}";
}
