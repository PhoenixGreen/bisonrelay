import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/epub_media.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/export/epub_writer.dart';
import 'package:bruig/plugin_system/canvas/export/opaque_png.dart';
import 'package:bruig/plugin_system/canvas/export/pdf_writer.dart';
import 'package:bruig/plugin_system/canvas/model/web_link.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart'
    show settledFrameOf;
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/foundation.dart';

// document_export.dart is a canvas published as something to read.
//
// A PDF is the pages exactly; an EPUB is the pages in a reader that turns
// them; an interactive EPUB also keeps what can be pressed, animated or
// played. Each is one leaf per scene, in order. Written for a document of
// pages (see CanvasKind) but a set of scenes works the same way.

/// DocumentAs is which of the three.
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

/// DocumentProgress reports how far the export has got, a page at a time.
typedef DocumentProgress = void Function(int done, int total);

/// renderDocumentPage draws leaf [index], exactly as the editor shows it.
///
/// Not renderFrame, which draws a frame of the sequence rather than a given
/// scene. And in a spread, the facing leaf's contents are drawn too, clipped
/// to this page, so an element laid across the gutter is printed on both
/// halves.
///
/// The caller owns the image and must dispose it.
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

  // As it settles, everything arrived: the page as it is read -- printed,
  // shown by a reader that runs no script, and behind an interactive book's
  // start (Ken, 2026-11-13: the book opened on a blank page, its frame 0,
  // before anything had arrived).
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
}) async {
  // The looks' shaders, for the pages and an interactive book's layers.
  await loadExportShaders();
  try {
    // The book's cover picture: the cover page, opaque and no bigger than a
    // reader takes (Ken, 2026-11-13: Apple Books showed no cover at first).
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
    var sheets = <PdfPicture>[];

    // An interactive book's sound and video: converted once for the book,
    // placed page by page. See epub_media.dart.
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
        // Design units to the page picture's pixels, for the hotspots.
        var pixels = image.width / document.size.size.width;
        var extra = builder == null
            ? const EpubPageMedia()
            : await builder.page(document, i, pixels,
                width: image.width, height: image.height);
        pages.add(EpubPage(
          png: png.buffer.asUint8List(),
          width: image.width,
          height: image.height,
          title: document.nameOf(i),
          side: _sideOf(document, covers, i),
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

    var bytes = writeEpub(
      pages: pages,
      title: document.title,
      interactive: as == DocumentAs.interactiveEpub,
      facing: document.isPages && document.pages.facing,
      cover: cover,
    );
    return CanvasExport(bytes, as.mime,
        width: pages.first.width, height: pages.first.height);
  } catch (exception) {
    debugPrint("Unable to write the canvas as a document: $exception");
    return null;
  }
}

/// _titleOf is a title page to fold into the page after it (see EpubStart):
/// a first scene that stands still, whose one button goes to the second,
/// which moves -- with nothing else on it to press or hear.
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

/// _startOf draws the title page twice -- without its Play, and the Play
/// cut from it -- for the page after it to start behind.
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
EpubSide _sideOf(CanvasDocument document, List<PageCover> covers, int index) {
  if (!document.isPages || !document.pages.facing) return EpubSide.centre;
  if (covers[index].isCover) return EpubSide.centre;
  return pageIsLeft(index) ? EpubSide.left : EpubSide.right;
}

/// _linksOn is every button on a page that goes to another page or opens a
/// URL. Buttons that play, show or hide are EpubActions: see
/// EpubMediaBuilder.page.
List<EpubLink> _linksOn(
    CanvasDocument document, CanvasScene scene, int index, double pixels) {
  var links = <EpubLink>[];
  // The master's buttons too: they are drawn on every page, and a book's
  // navigation lives there.
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
        // To a page that moves: #play, which plays it from the top as soon
        // as it has loaded, without its start screen -- the press that went
        // there was the press to play (Ken's infographic: Play on a title
        // page, then the page that builds).
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
    );

/// estimateDocumentBytes is roughly how large the file will be: a page's
/// worth of PNG times the number of pages.
int estimateDocumentBytes(CanvasDocument document, {double scale = 1}) {
  var one = estimateStillBytes(document, scale: scale);
  return one * document.allScenes.length + 4096;
}
