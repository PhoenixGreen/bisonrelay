import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/epub_media.dart';
import 'package:bruig/plugin_system/canvas/export/epub_tasks.dart';
import 'package:bruig/plugin_system/canvas/model/elements/play_task_element.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/export/epub_writer.dart';
import 'package:bruig/plugin_system/canvas/export/opaque_png.dart';
import 'package:bruig/plugin_system/canvas/export/pdf_writer.dart';
import 'package:bruig/plugin_system/canvas/export/video_export.dart'
    show ffmpegPath;
import 'package:bruig/plugin_system/canvas/model/book_details.dart';
import 'package:bruig/plugin_system/canvas/model/web_link.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart'
    show settledFrameOf;
import 'package:bruig/plugin_system/canvas/render/panel_reading.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

// document_export.dart publishes a canvas to read: a PDF of the pages, an
// EPUB that turns them, or an interactive EPUB keeping what can be
// pressed, animated or played; one leaf per scene, in order.

/// DocumentAs is which of the three formats.
enum DocumentAs {
  pdf("PDF", "Every page, exactly as designed — for printing and for sending"),
  epub("EPUB", "A book of pages an e-reader turns, laid out as designed"),
  interactiveEpub(
      "Interactive EPUB",
      "The same, with its buttons, animation, sounds and videos working — "
          "sound and video need ffmpeg to be put into the book");

  final String label;
  final String description;
  const DocumentAs(this.label, this.description);

  String get extension => this == pdf ? "pdf" : "epub";
  String get mime => this == pdf ? "application/pdf" : epubMime;
}

/// StoreProfile is which store an EPUB is made for: what it carries and what
/// it is held to. Ken, 2026-11-19, step 4 of the ebook plan (see the ebook
/// platforms report): one export per store rather than one for all.
enum StoreProfile {
  kindle(
      "Kindle",
      "Amazon's store: the pages as pictures, two to a spread on its side, "
          "Panel View for comics. Amazon runs no scripts or sound. Pages "
          "are JPEG where ffmpeg is installed, as Amazon charges for every "
          "megabyte of a book it sells at 70%",
      interactive: false),
  apple(
      "Apple Books",
      "Apple's store: everything works -- buttons, sound, video, motion -- "
          "with pages kept within Apple's 5.6 megapixels",
      interactive: true,
      maxPixels: 5600000),
  kobo(
      "Kobo",
      "Kobo's store: everything works in its phone and tablet apps, and the "
          "pages read as pictures on its e-readers; pages kept within "
          "Kobo's 3.8 megapixels",
      interactive: true,
      maxPixels: 3800000),
  plain(
      "Google Play & libraries",
      "Google Play Books and the library services: the pages as pictures, "
          "as they run no scripts",
      interactive: false),
  direct(
      "Direct sale",
      "Sold yourself, read in Bison Relay, Thorium or Apple Books: "
          "everything on, nothing held back",
      interactive: true);

  final String label, description;
  final bool interactive;

  /// maxPixels is the most a page may have, or 0 for no limit.
  final int maxPixels;
  const StoreProfile(this.label, this.description,
      {required this.interactive, this.maxPixels = 0});

  DocumentAs get document =>
      interactive ? DocumentAs.interactiveEpub : DocumentAs.epub;

  /// jpeg is whether its pages are JPEG rather than PNG.
  bool get jpeg => this == kindle;

  static StoreProfile fromName(String? name) =>
      values.firstWhere((p) => p.name == name, orElse: () => direct);
}

/// scaleFor is [scale] held to [profile]'s page limit for [document].
double scaleFor(CanvasDocument document, StoreProfile profile, double scale) {
  if (profile.maxPixels <= 0) return scale;
  var size = document.size.exportSize;
  var pixels = size.width * size.height * scale * scale;
  if (pixels <= profile.maxPixels) return scale;
  return scale * math.sqrt(profile.maxPixels / pixels) * 0.999;
}

/// Readiness is one thing a store will say of the book: [problem] is what
/// it would refuse, else what to know.
typedef Readiness = ({bool problem, String text});

/// storeReadiness is what [profile]'s store would say of [document] made at
/// [scale]: what is missing, what is made smaller, and what it costs.
List<Readiness> storeReadiness(CanvasDocument document, StoreProfile profile,
    {double scale = 1, bool ffmpeg = true}) {
  var book = document.pages.book;
  var out = <Readiness>[];
  if (book.author.isEmpty) {
    out.add((problem: true, text: "No author: every store asks for one."));
  }
  if (book.description.isEmpty) {
    out.add((
      problem: false,
      text: "No description: the store shows one beside the cover."
    ));
  }
  var edition =
      profile.interactive ? BookEdition.interactive : BookEdition.ebook;
  if (book.isbnOf(edition).isEmpty && profile == StoreProfile.apple) {
    out.add((
      problem: false,
      text: "No ISBN for the ${edition.label.toLowerCase()}: Apple takes one "
          "only with the first upload, never later."
    ));
  }
  if (scaleFor(document, profile, scale) < scale) {
    var pixels = profile.maxPixels / 1000000;
    out.add((
      problem: false,
      text: "Pages are made a little smaller, to ${profile.label}'s "
          "$pixels-megapixel limit."
    ));
  }
  switch (profile) {
    case StoreProfile.kindle:
      var mb = estimateDocumentBytes(document, scale: scale) /
          (1024 * 1024) *
          (ffmpeg ? 0.5 : 1);
      out.add((
        problem: false,
        text: "About ${mb.toStringAsFixed(1)} MB: at the 70% royalty Amazon "
            "keeps \$${(mb * 0.15).toStringAsFixed(2)} of each US sale for "
            "delivering it."
      ));
      if (!ffmpeg) {
        out.add((
          problem: false,
          text: "Install ffmpeg and the pages are made JPEG, about a "
              "half the size (the History book: 9.0 MB to 4.6 MB), so Amazon "
              "keeps less of each sale."
        ));
      }
    case StoreProfile.apple:
      out.add((
        problem: false,
        text: "Apple refuses pages whose words are part of the picture, "
            "comics excepted: list the book under Comics & Graphic Novels."
      ));
    case StoreProfile.kobo || StoreProfile.plain || StoreProfile.direct:
      break;
  }
  return out;
}

/// _jpegOf is [png] as a JPEG, through ffmpeg; null where it cannot be made.
/// Its working folder is its own, made and cleared here.
Future<Uint8List?> _jpegOf(Uint8List png, String ffmpeg) async {
  var work = await Directory.systemTemp.createTemp("bruig-jpeg");
  try {
    var from = path.join(work.path, "page.png");
    var to = path.join(work.path, "page.jpg");
    await File(from).writeAsBytes(png);
    var run = await Process.run(
        ffmpeg, ["-y", "-loglevel", "error", "-i", from, "-q:v", "3", to]);
    if (run.exitCode != 0) return null;
    return await File(to).readAsBytes();
  } catch (_) {
    return null;
  } finally {
    try {
      await work.delete(recursive: true);
    } catch (_) {}
  }
}

/// DocumentProgress reports how far the export has got, a page at a time.
typedef DocumentProgress = void Function(int done, int total);

/// renderDocumentPage draws leaf [index] as the editor shows it (not
/// renderFrame, a frame of the sequence). In a spread the facing leaf is
/// drawn too, clipped, so an element across the gutter prints on both
/// halves. The caller must dispose the image.
Future<ui.Image> renderDocumentPage(
  CanvasDocument document,
  int index, {
  double scale = 1,
  CanvasImageSource? images,
}) async {
  await loadExportShaders();
  var asked = scale.clamp(0.05, maxExportScale);
  var s = asked * document.size.exportScale;
  var width = math.max(1, (document.size.exportSize.width * asked).round());
  var height = math.max(1, (document.size.exportSize.height * asked).round());
  var docSize = document.size.size;

  // This leaf with its own backdrop (backgroundOf), not the document's,
  // which is whichever was edited last.
  var page = document.goToScene(index).copyWith(
        onMaster: false,
        background: document.backgroundOf(index),
      );

  // As it settles, everything arrived: the page as read in print, by a
  // reader running no script, and behind an interactive book's start.
  var settled = settledFrameOf(page);

  void draw(ui.Canvas canvas) {
    canvas.scale(s);

    paintCanvasDocument(canvas, page,
        frame: settled, part: CanvasPaintPart.backdrop, images: images);

    // The facing leaf's overhang, between the paper and this page's own
    // contents: the editor's order.
    var beside = document.facingAt(index);
    if (beside != null) {
      var onLeft = document.facingIsLeft(index) ?? false;
      canvas.save();
      canvas.clipRect(ui.Offset.zero & docSize);
      canvas.translate(onLeft ? docSize.width : -docSize.width, 0);
      paintCanvasDocument(
          canvas, document.goToScene(beside).copyWith(onMaster: false),
          part: CanvasPaintPart.contents, images: images);
      canvas.restore();
    }

    paintCanvasDocument(canvas, page,
        frame: settled, part: CanvasPaintPart.contents, images: images);
  }

  // Pictures on both leaves, read rather than their placeholders.
  await drawWhenLoaded(images, draw);
  var recorder = ui.PictureRecorder();
  draw(ui.Canvas(recorder));

  var picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

/// renderDocument writes the whole document as [as]. Every format goes
/// through renderDocumentPage, so a page is the same in all three.
Future<CanvasExport?> renderDocument(
  CanvasDocument document, {
  DocumentAs as = DocumentAs.pdf,
  double scale = 1,
  CanvasImageSource? images,
  PdfPaper paper = PdfPaper.canvas,
  PdfOrientation orientation = PdfOrientation.auto,
  DocumentProgress? onProgress,

  /// soundKbps is the bitrate an interactive book's sound is written at.
  int soundKbps = 160,

  /// spreads lays a book of pages out two to a spread when the reader is
  /// turned on its side, as a printed book opens; null follows the
  /// canvas's own facing pages. Not for a PDF.
  bool? spreads,

  /// profile makes the EPUB for one store (StoreProfile): plain or
  /// interactive as it needs, its pages within its limit, JPEG for Kindle.
  StoreProfile? profile,
}) async {
  if (profile != null) {
    as = profile.document;
    scale = scaleFor(document, profile, scale);
  }
  var jpegWith = (profile?.jpeg ?? false) ? await ffmpegPath() : null;
  // The looks' shaders, for the pages and an interactive book's layers.
  await loadExportShaders();
  try {
    // The book's cover picture: the cover page, opaque and no bigger than a
    // reader takes (see _coverPicture).
    Uint8List? cover;
    if (as != DocumentAs.pdf) {
      var front = document.pageCovers.indexOf(PageCover.front);
      cover = await _coverPicture(
          document, document.isPages && front >= 0 ? front : 0, images);
    }
    // A title page folded into the page it plays: see EpubStart.
    EpubStart? start;
    if (as == DocumentAs.interactiveEpub) {
      if (_titleOf(document) case var play?) {
        start = await _startOf(document, play, scale, images);
        if (start != null) {
          document = document.scenesFrom(1, document.allScenes.length - 1);
        }
      }
    }
    var scenes = document.allScenes;
    var covers = document.pageCovers;
    var pages = <EpubPage>[];

    var facing = document.isPages && (spreads ?? document.pages.facing);
    // A comic's panels in reading order, for a reader that reads panel by
    // panel (Kindle's Panel View, Bison Relay's; see EpubPanel). Listed in
    // either book; only a plain one has places to tap (epub_writer).
    var panels = as != DocumentAs.pdf
        ? panelSteps(document).where((p) => !p.whole).toList()
        : const <PanelStep>[];
    var sheets = <PdfPicture>[];

    // An interactive book's sound and video: converted once for the book,
    // placed page by page (see epub_media.dart).
    var builder = as == DocumentAs.interactiveEpub
        ? await EpubMediaBuilder.start(
            scale: scale, images: images, audioKbps: soundKbps)
        : null;

    for (var (i, scene) in scenes.indexed) {
      onProgress?.call(i, scenes.length);
      // One ui.Image alive at a time; each page's encoded bytes are still
      // held until the file is written.
      ui.Image? image;
      try {
        image =
            await renderDocumentPage(document, i, scale: scale, images: images);
        if (as == DocumentAs.pdf) {
          // Straight alpha: see renderPdf.
          var raw = await image.toByteData(
              format: ui.ImageByteFormat.rawStraightRgba);
          if (raw == null) return null;
          sheets.add(PdfPicture(raw.buffer.asUint8List(),
              width: image.width, height: image.height));
          continue;
        }
        var png = await image.toByteData(format: ui.ImageByteFormat.png);
        if (png == null) return null;
        // A Kindle page as a JPEG, where ffmpeg can make one: Amazon charges
        // for every megabyte of every sale.
        var picture = png.buffer.asUint8List();
        var jpeg = jpegWith == null ? null : await _jpegOf(picture, jpegWith);
        // Design units to the page picture's pixels, for the hotspots.
        var pixels = image.width / document.size.size.width;
        var extra = builder == null
            ? const EpubPageMedia()
            : await builder.page(document, i, pixels,
                width: image.width, height: image.height);
        pages.add(EpubPage(
          png: jpeg ?? picture,
          jpeg: jpeg != null,
          width: image.width,
          height: image.height,
          title: document.nameOf(i),
          side: _sideOf(document, covers, i, facing),
          panels: [
            for (var p in panels)
              if (p.scene == i)
                EpubPanel(p.focus.left * pixels, p.focus.top * pixels,
                    p.focus.width * pixels, p.focus.height * pixels),
          ],
          // The front cover the document marks, or else the first page.
          cover: document.isPages
              ? covers[i] == PageCover.front
              : i == 0 && !covers.any((c) => c == PageCover.front),
          links: as == DocumentAs.interactiveEpub
              ? [..._linksOn(document, scene, i, pixels), ...extra.links]
              : const [],
          media: extra.media,
          actions: extra.actions,
          files: extra.files,
          stage: extra.stage,
          soundtrack: extra.soundtrack,
          start: i == 0 ? start : null,
          // Its play task cards, ticking their steps as they are played.
          tasks: as == DocumentAs.interactiveEpub
              ? [
                  for (var e in scene.elements)
                    if (e is PlayTaskElement)
                      if (epubTaskOf(e, pixels) case var t?) t,
                ]
              : const [],
        ));
      } finally {
        image?.dispose();
      }
    }
    onProgress?.call(scenes.length, scenes.length);

    if (as == DocumentAs.pdf) {
      if (sheets.isEmpty) return null;
      var sheet = pageFor(paper, document.size.size, orientation: orientation);
      return CanvasExport(writePdf(sheets, page: sheet), as.mime,
          width: sheet.width.round(), height: sheet.height.round());
    }

    if (pages.isEmpty) return null;
    // No cover marked: the first page stands in.
    if (!pages.any((p) => p.cover)) pages[0] = _withCover(pages[0]);

    // Each edition under its own ISBN, where it has one; a book without
    // keeps the identifier made from its title.
    var book = document.pages.book;
    var isbn = isbn13(book.isbnOf(as == DocumentAs.interactiveEpub
        ? BookEdition.interactive
        : BookEdition.ebook));
    var bytes = writeEpub(
      pages: pages,
      title: document.title,
      identifier: isbn == null ? null : "urn:isbn:$isbn",
      interactive: as == DocumentAs.interactiveEpub,
      facing: facing,
      cover: cover,
      book: book,
    );
    return CanvasExport(bytes, as.mime,
        width: pages.first.width, height: pages.first.height);
  } catch (exception) {
    debugPrint("Unable to write the canvas as a document: $exception");
    return null;
  }
}

/// _titleOf is a title page to fold into the next (see EpubStart): a still
/// first scene whose only button goes to the moving second.
ButtonElement? _titleOf(CanvasDocument document) {
  if (document.isPages) return null;
  var scenes = document.allScenes;
  if (scenes.length < 2) return null;
  var first = scenes[0];
  if (first.frames > 1 || scenes[1].frames <= 1) return null;
  if (first.elements.any((e) => e is AudioElement || e is VideoElement)) {
    return null;
  }
  var buttons = [
    for (var e in first.elements)
      if (e is ButtonElement && e.visible) e,
  ];
  if (buttons.length != 1) return null;
  var play = buttons.single;
  if (play.action.kind != ButtonActionKind.goToScene ||
      document.sceneIndexNamed(play.action.elementId) != 1) {
    return null;
  }
  return play;
}

/// _startOf draws the title page twice, without its Play and the Play cut
/// from it, for the page after it to start behind.
Future<EpubStart?> _startOf(CanvasDocument document, ButtonElement play,
    double scale, CanvasImageSource? images) async {
  var scene = document.allScenes[0];
  var bare = document.withScene(
      0,
      scene.copyWith(elements: [
        for (var e in scene.elements)
          if (e.id != play.id) e,
      ]));
  var whole =
      await renderDocumentPage(document, 0, scale: scale, images: images);
  ui.Image? without, cut;
  try {
    without = await renderDocumentPage(bare, 0, scale: scale, images: images);
    var pixels = whole.width / document.size.size.width;
    var b = play.bounds;
    var at = ui.Rect.fromLTRB(
      (b.left * pixels).floorToDouble().clamp(0, whole.width - 1),
      (b.top * pixels).floorToDouble().clamp(0, whole.height - 1),
      (b.right * pixels).ceilToDouble().clamp(1, whole.width.toDouble()),
      (b.bottom * pixels).ceilToDouble().clamp(1, whole.height.toDouble()),
    );
    var recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
        .drawImageRect(whole, at, ui.Offset.zero & at.size, ui.Paint());
    var picture = recorder.endRecording();
    cut = await picture.toImage(at.width.round(), at.height.round());
    picture.dispose();
    var a = await without.toByteData(format: ui.ImageByteFormat.png);
    var p = await cut.toByteData(format: ui.ImageByteFormat.png);
    if (a == null || p == null) return null;
    return EpubStart(
        picture: a.buffer.asUint8List(), play: p.buffer.asUint8List(), at: at);
  } finally {
    whole.dispose();
    without?.dispose();
    cut?.dispose();
  }
}

/// _coverPicture is page [index] as a book's cover: opaque, and at most
/// about 4 million pixels, the most Apple Books takes in a picture.
Future<Uint8List?> _coverPicture(
    CanvasDocument document, int index, CanvasImageSource? images) async {
  var size = document.size.exportSize;
  var most = math.sqrt(3.9e6 / math.max(1.0, size.width * size.height));
  var image = await renderDocumentPage(document, index,
      scale: math.min(1.0, most), images: images);
  try {
    var raw =
        await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    if (raw == null) return null;
    return opaquePng(raw.buffer.asUint8List(), image.width, image.height);
  } finally {
    image.dispose();
  }
}

/// _sideOf is which half of a spread a page belongs on. Decided here because
/// a reader cannot know: it depends on the covers.
EpubSide _sideOf(
    CanvasDocument document, List<PageCover> covers, int index, bool facing) {
  if (!facing) return EpubSide.centre;
  if (covers[index].isCover) return EpubSide.centre;
  return pageIsLeft(index) ? EpubSide.left : EpubSide.right;
}

/// _linksOn is every button on a page going to another page or a URL;
/// those that play, show or hide are EpubActions (EpubMediaBuilder.page).
List<EpubLink> _linksOn(
    CanvasDocument document, CanvasScene scene, int index, double pixels) {
  var links = <EpubLink>[];
  // The master's buttons too: drawn on every page, a book's navigation.
  for (var element in [
    ...?document.masterScene?.elements,
    ...scene.elements,
  ]) {
    if (element is! ButtonElement || !element.visible) continue;
    var action = element.action;
    String? href;
    switch (action.kind) {
      case ButtonActionKind.goToScene:
        var to = document.sceneIndexNamed(action.elementId);
        // To a page that moves: #play, played from the top once loaded,
        // with no start screen: the press that went there was the play.
        if (to >= 0 && to != index) {
          var moves = document.allScenes[to].frames > 1;
          href = "page$to.xhtml${moves ? "#play" : ""}";
        }
      case ButtonActionKind.openLink:
        href = webLink(action.url)?.toString();
      default:
        break;
    }
    if (href == null) continue;
    var box = element.bounds;
    links.add(EpubLink(
        x: box.left * pixels,
        y: box.top * pixels,
        width: box.width * pixels,
        height: box.height * pixels,
        href: href,
        element: element.id));
  }
  return links;
}

EpubPage _withCover(EpubPage page) => EpubPage(
      png: page.png,
      width: page.width,
      height: page.height,
      title: page.title,
      side: page.side,
      cover: true,
      links: page.links,
      media: page.media,
      actions: page.actions,
      files: page.files,
      stage: page.stage,
      soundtrack: page.soundtrack,
      start: page.start,
      panels: page.panels,
      jpeg: page.jpeg,
      tasks: page.tasks,
    );

/// estimateDocumentBytes is roughly how large the file will be: a page's
/// worth of PNG times the number of pages and, for an [interactive] book,
/// what it carries besides (Ken, 2026-11-19: estimated at 4 MB, made at
/// 17). That is the pictures of what moves or plays on a page, about a
/// page's worth again; each page's sound at [soundKbps]; an instrument's
/// keys, once for every page playing the same one (epub_layers_maker.dart
/// names the file by what is in it); and the videos it carries,
/// [mediaBytes], as stored.
int estimateDocumentBytes(CanvasDocument document,
    {double scale = 1,
    bool interactive = false,
    int soundKbps = 160,
    int mediaBytes = 0}) {
  var one = estimateStillBytes(document, scale: scale);
  var total = one * document.allScenes.length + 4096;
  if (!interactive) return total;
  var rate = math.max(1, document.frameRate);
  var instruments = <String>{};
  for (var (i, scene) in document.allScenes.indexed) {
    var frames = document.goToScene(i).frames;
    var played = scene.elements.where((e) =>
        e.visible &&
        (e is AudioElement || e is SheetElement || e is VideoElement));
    if (frames > 1 || played.isNotEmpty) total += one;
    if (played.any((e) => e is AudioElement || e is VideoElement)) {
      total += (frames / rate * soundKbps * 1000 / 8).round();
    }
    for (var e in played) {
      if (e case AudioElement(:var instrument?)) {
        var p = instrument;
        if (instruments.add(
            "${p.sound.name}|${p.bank}|${p.program}|${p.lowKey}|${p.keys}")) {
          total += (p.keys * _keyStepSeconds * _keyKbps * 1000 / 8).round();
        }
      }
    }
  }
  return total + mediaBytes;
}

/// _keyStepSeconds and _keyKbps are how an instrument's keys are written
/// for a reader to play (_LayerMaker.keyStep in epub_layers_maker.dart, and
/// its AAC bitrate).
const _keyStepSeconds = 1.6;
const _keyKbps = 96;
