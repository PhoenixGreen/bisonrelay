part of 'canvas_stage.dart';

// Guides on the stage: one taken by a press near it, or pulled out of a
// ruler; moved by a drag, snapped to the grid; and dropped on release, or
// removed when dragged off the page. Part of CanvasStageState: its fields,
// lifecycle and build are in canvas_stage.dart.

extension StageGuides on CanvasStageState {
  /// _startGuideDrag takes a guide, or pulls a new one out of a ruler, and
  /// says whether it did. A press in a ruler always means a new guide; near a
  /// line, that line, unless guides are locked or hidden.
  bool _startGuideDrag(Offset stage, Offset doc) {
    var guides = document.guides;
    if (!guides.showGuides) return false;

    var from = _rulerUnder(stage);
    if (from != null) {
      var axis = from == GuideAxis.vertical
          ? GuideAxis.vertical
          : GuideAxis.horizontal;
      var at = axis == GuideAxis.vertical ? doc.dx : doc.dy;
      controller.beginInteraction();
      var next = guides.withGuide(CanvasGuide(axis: axis, at: at));
      _gesture = _GuideDrag(next.guides.length - 1);
      controller.apply(document.copyWith(guides: next), transient: true);
      return true;
    }

    if (guides.lockGuides) return false;
    var reach = guideGrabSlop / _scale;
    for (var (i, guide) in guides.guides.indexed) {
      var gap = guide.axis == GuideAxis.vertical
          ? (doc.dx - guide.at).abs()
          : (doc.dy - guide.at).abs();
      if (gap > reach) continue;
      _gesture = _GuideDrag(i);
      controller.beginInteraction();
      return true;
    }
    return false;
  }

  /// _rulerUnder is the ruler under the pointer, as the axis of the guide it
  /// makes, or null. The strips come from what draws them, so what can be
  /// dragged from is what is seen.
  GuideAxis? _rulerUnder(Offset stage) {
    if (!document.guides.showRulers) return null;
    var rulers = document.guides.rulers;
    if (!rulers.any) return null;
    // The strips are at the window's edges, the page scrolled under them.
    return rulerBandsFor(_pageRect.shift(-_scrolled), _visible, rulers)
        .axisAt(stage - _scrolled);
  }

  /// _applyGuide moves the guide at [index] to [doc], snapped so it can sit
  /// on a gridline.
  void _applyGuide(int index, Offset doc) {
    var guides = document.guides;
    if (index < 0 || index >= guides.guides.length) return;
    var guide = guides.guides[index];

    var at = guide.axis == GuideAxis.vertical ? doc.dx : doc.dy;
    if (!HardwareKeyboard.instance.isAltPressed) {
      var line = snapEdgeTo(
        at,
        guides,
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
