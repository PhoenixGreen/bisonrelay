import 'package:flutter/widgets.dart';

import 'package:bruig/plugin_system/canvas/ui/stage/stage_transform.dart';

/// StageScroll is the stage's two scroll views, which scroll a page bigger
/// than its window, and the view they show kept in step with
/// CanvasController.pan. The stage owns one and disposes it.
class StageScroll {
  /// down scrolls the page up and down.
  final ScrollController down = ScrollController();

  /// across scrolls the page from side to side.
  final ScrollController across = ScrollController();

  bool _syncing = false;

  /// syncing is set while the scroll views are moved to follow the view, so
  /// a listener on them does not take the move for a scroll by hand.
  bool get syncing => _syncing;

  /// scrolled is how far the page is scrolled, across and down; zero for a
  /// view not yet laid out.
  Offset get scrolled => Offset(
      across.hasClients ? across.offset : 0, down.hasClients ? down.offset : 0);

  /// jumpTo scrolls to [to] at once, as near as each view's range allows,
  /// leaving a view alone that is within half a pixel of it already.
  void jumpTo(Offset to) {
    _syncing = true;
    if (across.hasClients && (across.offset - to.dx).abs() > 0.5) {
      across.jumpTo(to.dx.clamp(0.0, across.position.maxScrollExtent));
    }
    if (down.hasClients && (down.offset - to.dy).abs() > 0.5) {
      down.jumpTo(to.dy.clamp(0.0, down.position.maxScrollExtent));
    }
    _syncing = false;
  }

  /// panOf is the view as CanvasController.pan holds it, the page laid out
  /// as [view] says and scrolled as it is now.
  Offset panOf(StageTransform view) => view.panAt(scrolled);

  /// moveTo scrolls as near the view at [pan] as the page can be scrolled
  /// in [view], and gives back the pan that scroll makes.
  Offset moveTo(StageTransform view, Offset pan) {
    var to = view.scrollFor(pan);
    jumpTo(to);
    return view.panScrolledTo(to);
  }

  /// dispose lets go of the scroll controllers.
  void dispose() {
    down.dispose();
    across.dispose();
  }
}
