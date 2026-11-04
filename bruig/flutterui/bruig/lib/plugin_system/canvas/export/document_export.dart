import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/epub_media.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/export/epub_writer.dart';
import 'package:bruig/plugin_system/canvas/export/pdf_writer.dart';
import 'package:bruig/plugin_system/canvas/model/web_link.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
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

  void draw(ui.Canvas canvas) {
    canvas.scale(s);

    paintCanvasDocument(canvas, page,
        part: CanvasPaintPart.backdrop, images: images);

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
        part: CanvasPaintPart.contents, images: images);
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
  try {
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
    );
    return CanvasExport(bytes, as.mime,
        width: pages.first.width, height: pages.first.height);
  } catch (exception) {
    debugPrint("Unable to write the canvas as a document: $exception");
    return null;
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
        if (to >= 0 && to != index) href = "page$to.xhtml";
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
