import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/scene_sequence.dart';
import 'package:bruig/plugin_system/canvas/render/text_items.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_text_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_paint_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_painter_inputs.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_transform.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline/marker_note.dart';

// stage_paint_page.dart is the page as the stage draws it: the sheet's
// shadow; the document as the editor shows it (an open editor's own words
// left out), with the leaf facing it, or a transition being watched, or a
// game's scene giving way to the next; a held marker's label; the line
// round the leaf being edited; the screen a game starts on within its
// level; and round the page the shade, the border and the hint of more
// canvas. Drawn from the transform, the page shown, what is live and the
// text being typed into, in stage pixels: [scale] pixels to a document
// unit, the document's top-left at [origin]. [page] is the frame the
// canvas is drawn inside and [viewRect] that and any overspill round it
// (see StageTransform).

/// _skippedWords is the words an open editor draws itself, which the
/// canvas leaves out: a piece's id, textBodyWords for the paragraph, or
/// null while the canvas draws them under a see-through field.
String? _skippedWords(CanvasDocument document, StageTextEdit? text) {
  var id = text?.element;
  if (id == null) return null;
  var e = document.elementById(id);
  if (e is! TextElement) return null;
  TextItem? item;
  for (var it in e.items) {
    if (it.id == text?.item) item = it;
  }
  if (!editorDrawsWords(e, item, document)) return null;
  return item?.id ?? textBodyWords;
}

/// paintStageContents is [document] at [frame] as the editor shows it,
/// without its backdrop unless [part] is all. [motion] is what plays from
/// slots, the session's own unless given.
void paintStageContents(Canvas canvas, CanvasDocument document, int frame,
    {required StageLive live,
    required StageTextEdit? text,
    required ({String id, int frame})? previewing,
    CanvasPaintPart part = CanvasPaintPart.contents,
    (double, Offset)? camera,
    LiveMotion? motion}) {
  var hover = live.counterHover;
  paintCanvasDocument(canvas, document,
      frame: frame,
      part: part,
      camera: camera,
      images: live.images,
      hoveredButton: live.hoveredButton,
      // Only words the editor shows itself (see editorDrawsWords): the
      // box and the other pieces stay, and usually nothing is left out.
      skipTextItem: _skippedWords(document, text),
      counterValue: live.counterValue.value,
      liveMotion: motion ?? live.liveMotion.value,
      counterPressed: (e) => e.id == hover.id ? hover.button : -1,
      counterRunning: live.counterRunning.value,
      audioState: live.audioState.value,
      videoShow: live.videoShow.value,
      // Kept while design and size hold still: the editor repaints on
      // every pointer move.
      backgrounds: live.backgrounds,
      // Guide paths show only while editing.
      editing: true,
      previewing: previewing);
}

/// _Contents draws a document's contents as paintStageContents does, with
/// what is live and the text being typed into already given.
typedef _Contents = void Function(CanvasDocument document, int frame,
    {CanvasPaintPart part, (double, Offset)? camera, LiveMotion? motion});

/// paintPageShadow draws a shadow under the frame, so the canvas reads as a
/// sheet even when its background matches the editor's.
void paintPageShadow(Canvas canvas, StageTransform transform, StageShown shown,
    Rect page, Rect viewRect) {
  var shadow = Paint()
    ..color = const Color(0x55000000)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
  if (shown.previewAt case var at? when transform.spread) {
    // Only under the leaves there are: a cover stands on its own side.
    var (onLeft, onRight) = bookSides(shown.document, at);
    var leftLeaf =
        transform.facingOnLeft ? page : page.shift(Offset(-page.width, 0));
    if (onLeft) canvas.drawRect(leftLeaf.shift(const Offset(0, 6)), shadow);
    if (onRight) {
      canvas.drawRect(leftLeaf.shift(Offset(page.width, 6)), shadow);
    }
  } else {
    canvas.drawRect(
        (transform.levelShown ? page : viewRect).shift(const Offset(0, 6)),
        shadow);
  }
}

/// paintStagePage draws the document in document units, with the leaf
/// facing it, a transition being watched or a game's change of scene, then
/// a held marker's label and the line round the leaf being edited. True
/// when a transition is being watched, which is all that is drawn then.
bool paintStagePage(Canvas canvas, StageTransform transform, StageShown shown,
    StageLive live, StageTextEdit? text, double scale, Offset origin) {
  var document = shown.document;
  var docSize = document.size.size;
  saveInDocument(canvas, scale, origin);
  // The leaf beside this one. Both backdrops go down first, then both
  // contents, so a picture across the gutter shows without a seam. The
  // neighbour is a document page even while the master is edited:
  // goToScene alone would leave onMaster set and draw the master twice.
  var beside = shown.facing;
  var over = beside == null
      ? null
      : document.goToScene(beside.index).copyWith(onMaster: false);
  var aside = transform.facingOnLeft ? docSize.width : -docSize.width;
  // At the frame it was left on, so a chart on it neither vanishes nor
  // jumps to its end.
  var overFrame = beside?.frame ?? 0;

  if (shown.previewAt case var at?) {
    _paintRun(canvas, document, at, transform, live);
    canvas.restore();
    return true;
  }
  void contents(CanvasDocument document, int frame,
          {CanvasPaintPart part = CanvasPaintPart.contents,
          (double, Offset)? camera,
          LiveMotion? motion}) =>
      paintStageContents(canvas, document, frame,
          live: live,
          text: text,
          previewing: shown.previewing,
          part: part,
          camera: camera,
          motion: motion);
  if (over != null) {
    _paintFacing(
        canvas, shown, over, overFrame, aside, transform, live, contents);
  }
  _paintEdited(canvas, shown, over, aside, contents);

  // A marker's label while playback holds at it, in canvas units.
  if (shown.markerNote case var note?) {
    paintMarkerNote(canvas, docSize, note, selected: shown.markerNoteGrip);
  }

  // A line round the leaf being edited, not a dimmed neighbour, which
  // would dim a picture across the gutter too. After the contents, or an
  // element against the edge hides it.
  if (over != null && transform.spread) {
    canvas.drawRect(
      (Offset.zero & docSize).deflate(docSize.width * 0.002),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = docSize.width * 0.004
        ..color = stageBlue.withAlpha(0x77),
    );
  }
  canvas.restore();
  return false;
}

/// _paintRun draws frame [at] of the whole run while a transition is
/// watched, with the export's own painting.
void _paintRun(Canvas canvas, CanvasDocument document, int at,
    StageTransform transform, StageLive live) {
  var docSize = document.size.size;
  // Played as a book, each leaf is drawn in its place in the spread and
  // a transition between spreads moves both (see paintBookFrame).
  if (transform.spread) {
    paintBookFrame(canvas, document, at,
        left: transform.facingOnLeft ? 0.0 : -docSize.width,
        images: live.images,
        backgrounds: live.backgrounds,
        audioState: live.audioState.value,
        videoShow: live.videoShow.value);
  } else {
    paintSequenceFrame(canvas, document, at,
        images: live.images,
        backgrounds: live.backgrounds,
        audioState: live.audioState.value,
        videoShow: live.videoShow.value,
        liveMotion: live.liveMotion.value,
        counterValue: live.counterValue.value);
  }
}

/// _paintFacing draws the leaf [over] beside the one being edited, [aside]
/// across, and this page's own contents over that leaf.
void _paintFacing(
    Canvas canvas,
    StageShown shown,
    CanvasDocument over,
    int overFrame,
    double aside,
    StageTransform transform,
    StageLive live,
    _Contents contents) {
  var document = shown.document;
  var docSize = document.size.size;
  // This page's paper goes down between the two: the neighbour's
  // backdrop under it, the neighbour's overhang over it.
  if (transform.spread) {
    canvas.save();
    canvas.translate(aside, 0);
    canvas.clipRect(Offset.zero & docSize);
    paintCanvasDocument(canvas, over,
        frame: overFrame,
        part: CanvasPaintPart.backdrop,
        images: live.images,
        backgrounds: live.backgrounds);
    canvas.restore();
  }
  paintCanvasDocument(canvas, document,
      part: CanvasPaintPart.backdrop,
      images: live.images,
      backgrounds: live.backgrounds);
  // On the neighbour's leaf, its own elements go over whatever this page
  // hangs across the gutter, as in the book, whichever leaf is selected.
  canvas.save();
  canvas.clipRect(Rect.fromLTWH(aside, 0, docSize.width, docSize.height));
  contents(document, shown.frame);
  canvas.restore();
  canvas.save();
  canvas.translate(aside, 0);
  paintCanvasDocument(canvas, over,
      frame: overFrame, part: CanvasPaintPart.contents, images: live.images);
  canvas.restore();

  // The spine, so two pages edge to edge do not read as one canvas.
  if (transform.spread) {
    var join = transform.facingOnLeft ? docSize.width : 0.0;
    canvas.drawRect(
      Rect.fromLTWH(join - docSize.width * 0.003, 0, docSize.width * 0.006,
          docSize.height),
      Paint()..color = const Color(0x22000000),
    );
  }
}

/// _paintEdited draws the page being edited: beside a facing leaf
/// [over], everywhere but on it; or giving way to the scene a game has gone
/// on to; or whole, through the scene's camera.
void _paintEdited(Canvas canvas, StageShown shown, CanvasDocument? over,
    double aside, _Contents contents) {
  var document = shown.document;
  var docSize = document.size.size;
  if (over != null) {
    // Everywhere but the neighbour's leaf, which drew this page's overhang
    // above.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(aside, 0, docSize.width, docSize.height),
        clipOp: ui.ClipOp.difference);
    contents(document, shown.frame);
    canvas.restore();
  } else if (shown.gameChange
      case (var left, var leftAt, var over, var t, var leftLive)?) {
    // A game gone on to another scene: the one it left gives way, framed
    // by its own camera, its elements as their slots had them when left.
    paintTransition(canvas, Offset.zero & docSize, over, t,
        from: () => contents(left, leftAt,
            part: CanvasPaintPart.all,
            camera: sceneFraming(left, leftAt, live: leftLive),
            motion: leftLive),
        to: () => contents(document, shown.frame,
            part: CanvasPaintPart.all, camera: shown.camera));
  } else {
    contents(document, shown.frame,
        part: CanvasPaintPart.all, camera: shown.camera);
  }
}

/// paintLevelFrame draws the screen the game starts on, within the level
/// round it.
void paintLevelFrame(Canvas canvas, StageTransform transform, Rect page) {
  if (transform.levelShown) {
    canvas.drawRect(
        page,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0x99FFFFFF));
  }
}

/// paintPageSurround draws what goes round the page, outside the clip: the
/// world outside it dimmed, its border, and a hint of more canvas when the
/// document, [docSize] at [scale], is wider than the frame.
void paintPageSurround(
    Canvas canvas, Rect page, Rect viewRect, Size docSize, double scale) {
  // Outside the page dimmed, so the published edge is obvious: four bands
  // rather than a Path.difference.
  if (viewRect != page) {
    var shade = Paint()..color = const Color(0x66000000);
    canvas.drawRect(
        Rect.fromLTRB(viewRect.left, viewRect.top, viewRect.right, page.top),
        shade);
    canvas.drawRect(
        Rect.fromLTRB(
            viewRect.left, page.bottom, viewRect.right, viewRect.bottom),
        shade);
    canvas.drawRect(
        Rect.fromLTRB(viewRect.left, page.top, page.left, page.bottom), shade);
    canvas.drawRect(
        Rect.fromLTRB(page.right, page.top, viewRect.right, page.bottom),
        shade);
  }

  // The border last and outside the clip, or it is half a line.
  canvas.drawRect(
      page,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x55FFFFFF));

  // A hint that there is more canvas outside the frame.
  if (docSize.width * scale > page.width + 1) {
    canvas.drawRect(
      page,
      Paint()
        ..shader = ui.Gradient.radial(
          page.center,
          math.max(page.width, page.height) * 0.7,
          [const Color(0x00000000), const Color(0x33000000)],
          [0.7, 1.0],
        ),
    );
  }
}
