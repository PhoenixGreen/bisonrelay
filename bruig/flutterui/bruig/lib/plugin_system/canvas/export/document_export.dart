import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/epub_media.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/export/epub_writer.dart';
import 'package:bruig/plugin_system/canvas/export/pdf_writer.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/foundation.dart';

// document_export.dart is a canvas published as something to read.
//
// The three formats are one question asked three ways -- how much of the
// document survives the trip. A PDF is the pages, exactly, for ever, and
// nothing else; an EPUB is the pages in a reader that turns them; an
// interactive EPUB is the same with whatever can be pressed still working.
// Every one of them is a page at a time, in order, at the size the canvas
// says, because that is what a document of pages *is*. See CanvasKind.
//
// Written for a document of pages, and offered for one -- but nothing here
// refuses a set of scenes. A deck of slides published as a PDF is a perfectly
// good thing to want, and the code cannot tell the difference: every canvas
// in the list is a page either way.

/// DocumentAs is which of the three.
enum DocumentAs {
  pdf("PDF", "Every page, exactly as designed — for printing and for sending"),
  epub("EPUB", "A book of pages an e-reader turns, laid out as designed"),
  interactiveEpub(
      "Interactive EPUB",
      "The same, with its buttons, sounds and videos working — sound and "
          "video need ffmpeg to be put into the book");

  final String label;
  final String description;
  const DocumentAs(this.label, this.description);

  /// isEpub is the two that are books.
  bool get isEpub => this != pdf;

  String get extension => this == pdf ? "pdf" : "epub";
  String get mime => this == pdf ? "application/pdf" : epubMime;
}

/// DocumentProgress reports how far the export has got. A document of forty
/// pages is forty renders, and a reader watching an unmoving dialog assumes
/// it has hung.
typedef DocumentProgress = void Function(int done, int total);

/// renderDocumentPage draws one leaf, exactly as the editor shows it.
///
/// Its own function rather than renderFrame, for two reasons that both come
/// from this being a *page* rather than a frame.
///
/// renderFrame draws the sequence: handed a document of several scenes it
/// asks paintSequenceFrame where the run has got to, and the scene being
/// edited has nothing to do with it. Given a document moved to page four and
/// the default frame, it drew page one -- four times over, which is a book
/// whose every leaf is its first.
///
/// And a spread is two leaves. An element laid across the gutter belongs to
/// one page and hangs over the other; printed a page at a time it would be
/// cut at the gutter and the half on the other leaf would be nowhere. So the
/// facing leaf's contents are drawn into this page as well, clipped to it --
/// which is what a printed spread is: the left half on one sheet, the right
/// half on the next, meeting when the book is open.
///
/// The caller owns the image and must dispose it. A document of forty pages
/// held forty of these at once is how a long export runs out of memory.
Future<ui.Image> renderDocumentPage(
  CanvasDocument document,
  int index, {
  double scale = 1,
  CanvasImageSource? images,
}) async {
  var asked = scale.clamp(0.05, maxExportScale);
  var s = asked * document.size.exportScale;
  var width = math.max(1, (document.size.exportSize.width * asked).round());
  var height = math.max(1, (document.size.exportSize.height * asked).round());
  var docSize = document.size.size;

  // This leaf, with its own backdrop. Taken from the document's own, every
  // page in the book wore whichever backdrop was edited last -- see
  // CanvasDocument.backgroundOf, which is the same answer paintSequenceFrame
  // takes for the same reason.
  var page = document.goToScene(index).copyWith(
        onMaster: false,
        background: document.backgroundOf(index),
      );

  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.scale(s);

  paintCanvasDocument(canvas, page,
      part: CanvasPaintPart.backdrop, images: images);

  // The facing leaf's overhang, between the paper and this page's own
  // contents -- the order the editor draws them in, so that what was designed
  // is what is printed.
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
      part: CanvasPaintPart.contents, images: images);

  var picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

/// renderDocument writes the whole document as [as].
///
/// Every format goes through renderDocumentPage, so a page is the same page
/// whichever of the three it is printed into. The PDF used to go through
/// renderPdf, which draws frames of a run rather than leaves of a document
/// and knows nothing about a spread.
Future<CanvasExport?> renderDocument(
  CanvasDocument document, {
  DocumentAs as = DocumentAs.pdf,
  double scale = 1,
  CanvasImageSource? images,
  PdfPaper paper = PdfPaper.canvas,
  PdfOrientation orientation = PdfOrientation.auto,
  DocumentProgress? onProgress,
}) async {
  try {
    var scenes = document.allScenes;
    var covers = document.pageCovers;
    var pages = <EpubPage>[];
    var sheets = <PdfPicture>[];

    // An interactive book's sound and video: converted once for the book,
    // placed page by page. See epub_media.dart.
    var builder = as == DocumentAs.interactiveEpub
        ? await EpubMediaBuilder.start(scale: scale, images: images)
        : null;

    for (var (i, scene) in scenes.indexed) {
      onProgress?.call(i, scenes.length);
      // Rendered and encoded one at a time, so only one decoded page is alive
      // at once. The obvious shape -- render them all, then pack them -- is
      // what makes a long document run out of memory.
      ui.Image? image;
      try {
        image =
            await renderDocumentPage(document, i, scale: scale, images: images);
        if (as == DocumentAs.pdf) {
          // Straight rather than premultiplied: a PDF keeps the colours and
          // the transparency as two separate images, and separating them out
          // of premultiplied pixels means dividing the colour back out of its
          // own alpha, which loses a little of every half-transparent pixel
          // for nothing.
          var raw = await image.toByteData(
              format: ui.ImageByteFormat.rawStraightRgba);
          if (raw == null) return null;
          sheets.add(PdfPicture(raw.buffer.asUint8List(),
              width: image.width, height: image.height));
          continue;
        }
        var png = await image.toByteData(format: ui.ImageByteFormat.png);
        if (png == null) return null;
        // Design units to the page picture's pixels. The hotspots were
        // placed in design units, which is right only where the picture is
        // exactly the design's size -- on any other they missed what they
        // were over.
        var pixels = image.width / document.size.size.width;
        var extra = builder == null
            ? const EpubPageMedia()
            : await builder.page(document, i, pixels);
        pages.add(EpubPage(
          png: png.buffer.asUint8List(),
          width: image.width,
          height: image.height,
          title: scene.saysAt(i, document.kind),
          side: _sideOf(document, covers, i),
          // The first cover the document marks, and the first page otherwise:
          // a reader wants a picture for its shelf either way, and the front
          // of the document is the only honest answer to what it should be.
          cover: document.isPages
              ? covers[i] == PageCover.front
              : i == 0 && !covers.any((c) => c == PageCover.front),
          links: as == DocumentAs.interactiveEpub
              ? [..._linksOn(document, scene, i, pixels), ...extra.links]
              : const [],
          media: extra.media,
          actions: extra.actions,
          files: extra.files,
          film: extra.film,
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
    // A cover was never marked and the document has none: the first page
    // stands in, so the book has a picture on the shelf.
    if (!pages.any((p) => p.cover)) pages[0] = _withCover(pages[0]);

    var bytes = writeEpub(
      pages: pages,
      title: document.title,
      interactive: as == DocumentAs.interactiveEpub,
      facing: document.isPages && document.pages.facing,
    );
    return CanvasExport(bytes, as.mime,
        width: pages.first.width, height: pages.first.height);
  } catch (exception) {
    debugPrint("Unable to write the canvas as a document: $exception");
    return null;
  }
}

/// _sideOf is which half of a spread a page belongs on.
///
/// Read from the document rather than left to the reader, which cannot know:
/// it depends on the covers and on where the numbering starts. A document
/// that is not pages says nothing, and a reader shows one at a time.
EpubSide _sideOf(CanvasDocument document, List<PageCover> covers, int index) {
  if (!document.isPages || !document.pages.facing) return EpubSide.centre;
  if (covers[index].isCover) return EpubSide.centre;
  return pageIsLeft(index) ? EpubSide.left : EpubSide.right;
}

/// _linksOn is every button on a page that goes somewhere a book can go.
///
/// Two of the nine actions survive being printed into a book: going to
/// another canvas, which is a link to that page's file, and opening a URL,
/// which is a link. The other seven are about a playhead, and a book has
/// none -- a button that played an animation would be a button that does
/// nothing, and drawing a hotspot over it makes a page look broken rather
/// than making it work.
List<EpubLink> _linksOn(
    CanvasDocument document, CanvasScene scene, int index, double pixels) {
  var links = <EpubLink>[];
  for (var element in scene.elements) {
    if (element is! ButtonElement || !element.visible) continue;
    var action = element.action;
    String? href;
    switch (action.kind) {
      case ButtonActionKind.goToScene:
        var to = document.sceneIndexNamed(action.elementId);
        if (to >= 0 && to != index) href = "page$to.xhtml";
      case ButtonActionKind.openLink:
        if (action.url.trim().isNotEmpty) href = action.url.trim();
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
        href: href));
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
      film: page.film,
    );

/// estimateDocumentBytes is roughly how large the file will be.
///
/// A page's worth of PNG times the number of pages, which is what every one
/// of these formats is: the XML round an EPUB is a few kilobytes whatever the
/// document, and a PDF's structure is smaller still.
int estimateDocumentBytes(CanvasDocument document, {double scale = 1}) {
  var one = estimateStillBytes(document, scale: scale);
  return one * document.allScenes.length + 4096;
}
