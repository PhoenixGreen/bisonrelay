part of 'canvas_stage.dart';

// Guides on the stage: one taken by a press near it, or pulled out of a
// ruler; moved by a drag, snapped to the grid; and dropped on release, or
// removed when dragged off the page. Part of CanvasStageState: its fields,
// lifecycle and build are in canvas_stage.dart.

extension StageGuides on CanvasStageState {
  /// _guidesInView is whether the grid and guides are drawn over the page:
  /// not while it plays, previews or runs as a game, when the scene's camera
  /// moves the page under them. The rulers stay.
  bool get _guidesInView =>
      !controller.playing &&
      !controller.gaming &&
      controller.previewAt == null &&
      controller.previewing == null;

  /// _pullGuide begins pulling a new guide out of the ruler under [stage],
  /// and says whether it did. The guide is put down by the drag's first
  /// move (see _putGuide), so a click on a ruler changes nothing.
  bool _pullGuide(Offset stage) {
    var from = _rulerUnder(stage);
    if (from == null) return false;
    controller.beginInteraction();
    _gesture = _GuideDrag.pulled(from);
    return true;
  }

  /// _putGuide puts down the guide pulled out of a ruler along [axis] at
  /// [doc], showing guides if they were hidden, since a guide pulled out is
  /// meant to be seen, and says where it is in the list.
  int _putGuide(GuideAxis axis, Offset doc) {
    var at = axis == GuideAxis.vertical ? doc.dx : doc.dy;
    var next = document.guides
        .copyWith(showGuides: true)
        .withGuide(CanvasGuide(axis: axis, at: at));
    controller.apply(document.copyWith(guides: next), transient: true);
    return next.guides.length - 1;
  }

  /// _grabGuide takes the guide nearest [doc], if one is in reach where it
  /// is drawn: on the page, not along its line beyond it. Not while guides
  /// are locked, hidden or put away while the canvas plays.
  bool _grabGuide(Offset doc) {
    var guides = document.guides;
    if (!guides.showGuides || guides.lockGuides || !_guidesInView) {
      return false;
    }
    var reach = guideGrabSlop / _scale;
    if (!(Offset.zero & document.size.size).inflate(reach).contains(doc)) {
      return false;
    }
    int? nearest;
    var closest = reach;
    for (var (i, guide) in guides.guides.indexed) {
      var gap = guide.axis == GuideAxis.vertical
          ? (doc.dx - guide.at).abs()
          : (doc.dy - guide.at).abs();
      if (gap > closest) continue;
      closest = gap;
      nearest = i;
    }
    if (nearest == null) return false;
    _gesture = _GuideDrag(nearest);
    controller.beginInteraction();
    return true;
  }

  /// _rulerUnder is the ruler under the pointer, as the axis of the guide it
  /// makes, or null. The strips come from what draws them, so what can be
  /// dragged from is what is seen. None while guides are put away, as no
  /// guide could be drawn coming out of one.
  GuideAxis? _rulerUnder(Offset stage) {
    if (!document.guides.showRulers || !_guidesInView) return null;
    var rulers = document.guides.rulers;
    if (!rulers.any) return null;
    // The strips are at the window's edges, the page scrolled under them.
    return rulerBandsFor(_pageRect.shift(-_scrolled), _visible, rulers)
        .axisAt(stage - _scrolled);
  }

  /// _applyGuide moves the guide at [index] to [doc], snapped so it can sit
  /// on a gridline. Not snapped to itself: its own last place is always in
  /// reach of a small step, which would hold it back.
  void _applyGuide(int index, Offset doc) {
    var guides = document.guides;
    if (index < 0 || index >= guides.guides.length) return;
    var guide = guides.guides[index];

    var at = guide.axis == GuideAxis.vertical ? doc.dx : doc.dy;
    if (!HardwareKeyboard.instance.isAltPressed) {
      var line = snapEdgeTo(
        at,
        guides.withoutGuide(index),
        document.size.size,
        vertical: guide.axis == GuideAxis.vertical,
        within: guides.snapWithin / _scale,
      );
      if (line != null) at = line;
    }

    controller.apply(document.copyWith(guides: guides.movedGuide(index, at)),
        transient: true);
  }

  /// _finishGuide drops the guide at [index], or removes it if dragged off
  /// the canvas.
  void _finishGuide(int index) {
    var guides = document.guides;
    if (index < 0 || index >= guides.guides.length) return;
    var guide = guides.guides[index];
    var page = document.size.size;
    var off = guide.axis == GuideAxis.vertical
        ? guide.at < 0 || guide.at > page.width
        : guide.at < 0 || guide.at > page.height;

    if (off) {
      controller.apply(document.copyWith(guides: guides.withoutGuide(index)));
    }
  }
}
