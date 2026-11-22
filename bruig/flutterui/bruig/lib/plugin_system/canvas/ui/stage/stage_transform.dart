import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/ui/controller/view_types.dart';

/// StageTransform is how the page sits in the stage's window: its scale, where
/// it is drawn, and how a stage point becomes a document point and back.
/// Made from plain values, so it can be worked out and tested without a
/// stage: the stage makes one from its controller, document and layout.
///
/// Stage space is the box the canvas is drawn into ([viewport]), before it
/// is scrolled; the stage's pointer events arrive in it.
class StageTransform {
  /// margin is the gap kept round the whole canvas, in stage pixels.
  static const double margin = 24;

  /// overspillFraction is how much world beyond the page shows when
  /// [overspill] is on, as a fraction of the page.
  static const double overspillFraction = 0.12;

  /// visible is the room on screen the stage was laid out into.
  final Size visible;

  /// viewport is the box the canvas is drawn into: [visible] while the page
  /// fits, bigger when zoomed past the window or fitted to a width taller
  /// than it; the difference is scrolled. It is what the last layout made
  /// of [contentSize], so it can lag a frame behind a change of zoom.
  final Size viewport;

  /// page is the document's size, in document units.
  final Size page;

  /// fit is how large the page's frame is drawn: whole, or to the width.
  final CanvasFit fit;

  /// zoom is the controller's zoom over the fitted scale.
  final double zoom;

  /// spread is whether room is given to a facing leaf beside the page.
  final bool spread;

  /// facingOnLeft is whether the edited page is the left leaf of its
  /// spread. Read even when [spread] is off: the neighbour is still drawn.
  final bool facingOnLeft;

  /// overspill is whether the world past the page's edge shows.
  final bool overspill;

  /// level is a game scene's reach past the page, in document units, or
  /// null when there is none to show.
  final Rect? level;

  const StageTransform({
    required this.visible,
    required this.viewport,
    required this.page,
    this.fit = CanvasFit.whole,
    this.zoom = 1,
    this.spread = false,
    this.facingOnLeft = false,
    this.overspill = false,
    this.level,
  });

  /// StageTransform.of is the view of [document]'s edited page: the facing leaf
  /// and the spread side read from the document, the rest handed in.
  /// [previewing] is whether a run is being previewed
  /// (CanvasController.previewAt is set), which shows a document with
  /// spreads as a book.
  factory StageTransform.of(
    CanvasDocument document, {
    required CanvasFit fit,
    required double zoom,
    required bool overspill,
    required bool previewing,
    required Size visible,
    required Size viewport,
    Rect? level,
  }) {
    // The page drawn beside the edited one, or none: scenes, facing pages
    // off, a cover, the first leaf, or the master, which would otherwise
    // look different by where it was opened from.
    var facing = document.editingMaster ? null : document.facingAt(document.at);
    // Played as a book, every leaf is drawn in its spread place, so a
    // transition between spreads moves both.
    var book = previewing && document.hasSpread;
    bool onLeft;
    if (book) {
      onLeft = document.spreadOf(document.at)?.left == document.at;
    } else if (document.editingMaster) {
      onLeft = false;
    } else {
      onLeft = document.facingIsLeft(document.at) ?? false;
    }
    return StageTransform(
      visible: visible,
      viewport: viewport,
      page: document.size.size,
      fit: fit,
      zoom: zoom,
      // Fitted to width there is no room, but the neighbour is still drawn,
      // since a picture across the gutter is part of this page.
      spread: (facing != null || book) && fit != CanvasFit.width,
      facingOnLeft: onLeft,
      overspill: overspill,
      level: level,
    );
  }

  /// _made is every value this is made from, as one record. Everything else
  /// it answers follows from these, so two made from equal values are equal;
  /// a field left out here would let two different views compare equal and
  /// a change of view go unpainted.
  (Size, Size, Size, CanvasFit, double, bool, bool, bool, Rect?) get _made => (
        visible,
        viewport,
        page,
        fit,
        zoom,
        spread,
        facingOnLeft,
        overspill,
        level
      );

  @override
  bool operator ==(Object other) =>
      other is StageTransform && other._made == _made;

  @override
  int get hashCode => _made.hashCode;

  /// fitScale is the scale at which the whole canvas fits, with [margin] to
  /// spare. It changes with the window and sidebar, which the controller
  /// does not know.
  double get fitScale {
    var size = page;
    if (size.width <= 0 || size.height <= 0) return 1;
    // A spread is two pages across: only the width makes room.
    var across = size.width * (spread ? 2 : 1);
    var byWidth = (visible.width - margin * 2) / across;
    // Fit to width ignores the height: a 9:16 story would be a narrow strip.
    var fitted = fit == CanvasFit.width
        ? byWidth
        : math.min(byWidth, (visible.height - margin * 2) / size.height);
    // The page gives up room for the overspill, not the margin.
    if (overspill) {
      fitted /= 1 + overspillFraction * 2;
    }
    return fitted.isFinite && fitted > 0 ? fitted : 1;
  }

  /// scale is one document unit on screen: the fit times the zoom.
  double get scale => fitScale * zoom;

  /// scaleOrOne is [scale], or 1 while it is 0: what a stage length is
  /// divided by to give a document length.
  double get scaleOrOne => scale == 0 ? 1 : scale;

  /// pageRect is the page on screen at [scale], centred in the [viewport].
  Rect get pageRect {
    var size = page * scale;
    // The spread is centred, the edited page taking its half, so it does not
    // shift when the edited page changes sides.
    var across =
        !spread ? 0.0 : (facingOnLeft ? -size.width / 2 : size.width / 2);
    return Rect.fromCenter(
      center: Offset(viewport.width / 2 + across, viewport.height / 2),
      width: size.width,
      height: size.height,
    );
  }

  /// scaledSize is the page's size on screen.
  Size get scaledSize => page * scale;

  /// origin is the document's top-left in stage space: the page's own.
  Offset get origin => pageRect.topLeft;

  /// viewRect is everything drawn: the page, plus overspill when showing.
  /// Clipped and hit-tested against, so off-page elements are grabbable
  /// exactly when seen.
  Rect get viewRect {
    var page = pageRect;
    // The neighbour's half of the spread, on its own side. The edited page
    // keeps its frame and origin, so the pointer code knows of one leaf.
    if (spread) {
      page = facingOnLeft
          ? Rect.fromLTWH(page.left, page.top, page.width * 2, page.height)
          : Rect.fromLTWH(
              page.left - page.width, page.top, page.width * 2, page.height);
    }
    var shown = !overspill
        ? page
        : Rect.fromCenter(
            center: page.center,
            width: page.width * (1 + overspillFraction * 2),
            height: page.height * (1 + overspillFraction * 2),
          );
    // A game's level, drawn, grabbable and scrollable while not played.
    if (level case var level?) {
      shown = shown.expandToInclude(
          Rect.fromPoints(toStage(level.topLeft), toStage(level.bottomRight)));
    }
    return shown;
  }

  /// levelShown is whether a game's level reaches past the page.
  bool get levelShown => level != null;

  /// scrolls is whether the [viewport] is bigger than the room on screen, so
  /// the page is in scroll views and the rulers are drawn in a layer of
  /// their own over them, not by the stage's painter.
  bool get scrolls =>
      viewport.width > visible.width + 0.5 ||
      viewport.height > visible.height + 0.5;

  /// contentSize is the room the canvas and margins need in [visible], the
  /// excess over it scrolled: what the stage lays the [viewport] out at.
  Size get contentSize {
    if (visible.width <= 0 || visible.height <= 0) return visible;
    var spill = overspill ? 1 + overspillFraction * 2 : 1.0;
    var page = this.page * scale;
    var wide = page.width * spill * (spread ? 2 : 1) + margin * 2;
    var tall = page.height * spill + margin * 2;
    // A game's level: the page stays centred, so each side gets as much room
    // as the level reaches past the far side.
    if (level case var level?) {
      var doc = this.page;
      var across = math.max(-level.left, level.right - doc.width) * scale;
      var down = math.max(-level.top, level.bottom - doc.height) * scale;
      wide = math.max(wide, page.width + across * 2 + margin * 2);
      tall = math.max(tall, page.height + down * 2 + margin * 2);
    }
    // Zoomed, room to move it about: half a window past its edges, so it can
    // be lifted clear of the timeline and mixer. Unzoomed it stays centred.
    if ((zoom - 1).abs() > 0.001) {
      wide = math.max(wide, visible.width * 2 - wide) + visible.width;
      tall = math.max(tall, visible.height * 2 - tall) + visible.height;
    }
    return Size(math.max(visible.width, wide), math.max(visible.height, tall));
  }

  /// onFacingPage is whether stage point [stage] is over the facing leaf.
  bool onFacingPage(Offset stage) {
    if (!spread) return false;
    var page = pageRect;
    if (stage.dy < page.top || stage.dy > page.bottom) return false;
    return facingOnLeft ? stage.dx > page.right : stage.dx < page.left;
  }

  /// toDocument is stage point [stage] in document space.
  Offset toDocument(Offset stage) => (stage - origin) / scaleOrOne;

  /// toStage is document point [doc] in stage space.
  Offset toStage(Offset doc) => doc * scale + origin;

  /// toStageRect is document rect [doc] on the stage: its corner moved like
  /// a point, its size scaled.
  Rect toStageRect(Rect doc) {
    var tl = toStage(doc.topLeft);
    return Rect.fromLTWH(tl.dx, tl.dy, doc.width * scale, doc.height * scale);
  }

  /// toDocumentRect is stage rect [stage] in document space: its corner
  /// moved like a point, its size divided as [toDocumentLength] divides.
  Rect toDocumentRect(Rect stage) {
    var tl = toDocument(stage.topLeft);
    return Rect.fromLTWH(tl.dx, tl.dy, toDocumentLength(stage.width),
        toDocumentLength(stage.height));
  }

  /// toStageLength is [length] document units in stage pixels.
  double toStageLength(double length) => length * scale;

  /// toDocumentLength is [pixels] stage pixels in document units: a reach
  /// or a slop that is so many pixels at any zoom.
  double toDocumentLength(double pixels) => pixels / scaleOrOne;

  /// scrollFor is the scroll that puts the view at [pan] (the page's middle
  /// from the window's, in screen pixels, as CanvasController.pan holds it),
  /// within the range the [viewport] can be scrolled over [visible].
  Offset scrollFor(Offset pan) {
    var page = pageRect.center;
    var want = page - Offset(visible.width / 2, visible.height / 2) - pan;
    return Offset(
      want.dx
          .clamp(0.0, math.max(0.0, viewport.width - visible.width))
          .toDouble(),
      want.dy
          .clamp(0.0, math.max(0.0, viewport.height - visible.height))
          .toDouble(),
    );
  }

  /// panAt is the view as CanvasController.pan holds it with the page
  /// scrolled by [scrolled]: the page's middle from the window's.
  Offset panAt(Offset scrolled) {
    var page = pageRect.center;
    var at = scrolled + Offset(visible.width / 2, visible.height / 2);
    return page - at;
  }

  /// panScrolledTo is the pan that scroll [to] gives, as [scrollFor] works
  /// it out: the window's middle taken off the page's first, then the
  /// scroll, which is not quite [panAt]'s order of sums.
  Offset panScrolledTo(Offset to) {
    var page = pageRect.center;
    return page - Offset(visible.width / 2, visible.height / 2) - to;
  }
}
