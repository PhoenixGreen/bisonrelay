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
  interactiveEpub("Interactive EPUB",
      "The same, with buttons that still go where they point");

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

/// renderDocument writes the whole document as [as].
Future<CanvasExport?> renderDocument(
  CanvasDocument document, {
  DocumentAs as = DocumentAs.pdf,
  double scale = 1,
  CanvasImageSource? images,
  PdfPaper paper = PdfPaper.canvas,
  PdfOrientation orientation = PdfOrientation.auto,
  DocumentProgress? onProgress,
}) async {
  // A PDF of every page already exists and is the same job, so it is that
  // rather than a second one -- see renderPdf, which walks the scenes and
  // writes a page for each.
  if (as == DocumentAs.pdf) {
    return renderPdf(document,
        scale: scale, images: images, paper: paper, orientation: orientation);
  }

  try {
    var scenes = document.allScenes;
    var covers = document.pageCovers;
    var pages = <EpubPage>[];
    for (var (i, scene) in scenes.indexed) {
      onProgress?.call(i, scenes.length);
      // Rendered and encoded one at a time, so only one decoded page is alive
      // at once. The obvious shape -- render them all, then pack them -- is
      // what makes a long document run out of memory.
      var png = await renderImage(
        document.goToScene(i).copyWith(onMaster: false),
        scale: scale,
        images: images,
      );
      if (png == null) return null;
      pages.add(EpubPage(
        png: png.data,
        width: png.width,
        height: png.height,
        title: scene.saysAt(i, document.kind),
        side: _sideOf(document, covers, i),
        // The first cover the document marks, and the first page otherwise: a
        // reader wants a picture for its shelf either way, and the front of
        // the document is the only honest answer to what it should be.
        cover: document.isPages
            ? covers[i] == PageCover.front
            : i == 0 && !covers.any((c) => c == PageCover.front),
        links: as == DocumentAs.interactiveEpub
            ? _linksOn(document, scene, i)
            : const [],
      ));
    }
    onProgress?.call(scenes.length, scenes.length);
    if (pages.isEmpty) return null;

    // A cover was never marked and the document has none: the first page
    // stands in, so the book has a picture on the shelf.
    if (!pages.any((p) => p.cover)) {
      pages[0] = _withCover(pages[0]);
    }

    var bytes = writeEpub(
      pages: pages,
      title: document.title,
      interactive: as == DocumentAs.interactiveEpub,
      facing: document.isPages && document.pages.facing,
    );
    return CanvasExport(bytes, as.mime,
        width: pages.first.width, height: pages.first.height);
  } catch (exception) {
    debugPrint("Unable to write the canvas as an EPUB: $exception");
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
List<EpubLink> _linksOn(CanvasDocument document, CanvasScene scene, int index) {
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
        x: box.left,
        y: box.top,
        width: box.width,
        height: box.height,
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
