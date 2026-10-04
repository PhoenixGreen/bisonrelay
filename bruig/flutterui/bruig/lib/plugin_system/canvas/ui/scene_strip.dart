import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline_view.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

// scene_strip.dart is the row of scenes between the ruler and the keyframes
// while the timeline plays the whole document: one box per scene, laid on the
// ruler's own scale, so each scene's frames run along the ruler directly over
// its box. Zooming and scrolling the timeline zooms and scrolls the scenes
// with it -- close in, the frame the playhead is on in a scene can be read off
// the ruler above it.
//
// It is also where the scenes are made longer and shorter against each other.
// The gap between two boxes is a grip: dragged, it moves the join between the
// two scenes, so what one gains the other gives and the run as a whole stays
// the same length. The grip after the last box lengthens the last scene alone.

/// sceneStripLead is the gap between the ruler and the boxes.
const double sceneStripLead = 4;

/// sceneBoxHeight is how tall each scene's box is.
const double sceneBoxHeight = 30;

/// sceneStripHeight is the room the strip takes between the ruler and the
/// keyframes: the gap over the boxes, the boxes, and a gap under them.
const double sceneStripHeight = sceneStripLead + sceneBoxHeight + 6;

/// _gripWidth is the gap between two boxes, which is the grip.
const double _gripWidth = 8;

class CanvasSceneStrip extends StatefulWidget {
  final CanvasController controller;

  /// view is the timeline's, in the run's frames: the stretch of the whole
  /// document the ruler is showing.
  final TimelineView view;

  /// origin is where the scene being edited starts in the run, which is
  /// where its playhead is measured from.
  final int origin;

  const CanvasSceneStrip({
    required this.controller,
    required this.view,
    required this.origin,
    super.key,
  });

  @override
  State<CanvasSceneStrip> createState() => _CanvasSceneStripState();
}

class _CanvasSceneStripState extends State<CanvasSceneStrip> {
  CanvasController get controller => widget.controller;

  /// _held is the grip being dragged: the scene before it, how long that
  /// scene and the next were when the drag began, and frames per pixel at
  /// the time -- held, so a whole view re-fitting to a longer run does not
  /// change what a pixel is worth half way through.
  ({int index, int before, int after, double perPixel})? _held;
  double _dragged = 0;

  void _startDrag(int index, double width) {
    var frames = [for (var s in controller.scenes) s.frames];
    _held = (
      index: index,
      before: frames[index],
      after: index + 1 < frames.length ? frames[index + 1] : 0,
      perPixel: widget.view.framesPer(1, width),
    );
    _dragged = 0;
    controller.pause();
    controller.beginInteraction();
  }

  void _drag(double dx) {
    var held = _held;
    if (held == null) return;
    _dragged += dx;
    var by = (_dragged * held.perPixel).round();
    if (held.index + 1 >= controller.scenes.length) {
      // The end of the run: only the last scene changes.
      by = math.max(1 - held.before, by);
      controller
          .setSceneFrames({held.index: held.before + by}, transient: true);
    } else {
      // A join: one scene gains what the next gives, and neither goes below
      // a single frame.
      by = by.clamp(1 - held.before, held.after - 1).toInt();
      controller.setSceneFrames({
        held.index: held.before + by,
        held.index + 1: held.after - by,
      }, transient: true);
    }
  }

  void _endDrag() {
    if (_held == null) return;
    _held = null;
    controller.endInteraction();
    setState(() {});
  }

  void _open(int index) {
    if (controller.previewAt != null) controller.stopPreview();
    controller.goToScene(index);
  }

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var document = controller.document;
    var scenes = controller.scenes;
    var at = controller.onMaster ? -1 : controller.sceneAt;
    var view = widget.view;

    return LayoutBuilder(builder: (context, box) {
      var width = box.maxWidth;
      double x(num frame) => view.xOf(frame, width);
      var playhead = x(widget.origin + controller.frame);

      // From where the run reaches each scene to where it reaches the next:
      // a transition that overlaps two scenes is the join between them,
      // which is where the grip is.
      var ends = [
        for (var i = 0; i < scenes.length; i++)
          i + 1 < scenes.length
              ? document.startOfScene(i + 1)
              : document.startOfScene(i) + scenes[i].frames,
      ];

      var children = <Widget>[];
      for (var i = 0; i < scenes.length; i++) {
        var left = x(document.startOfScene(i)) + _gripWidth / 2;
        var right = x(ends[i]) - _gripWidth / 2;
        if (right < 0 || left > width) continue;
        children.add(Positioned(
          left: left,
          width: math.max(2.0, right - left),
          top: 0,
          bottom: 0,
          child: _box(
              // Where the box starts off the left edge, its words start at
              // the edge instead, so a scene zoomed into is still named.
              math.max(0.0, -left),
              i,
              document.nameOf(i),
              scenes[i].frames,
              i == at
                  ? (playhead - left).clamp(0.0, math.max(0.0, right - left))
                  : null,
              colors),
        ));
      }
      // The grips after the boxes, so a box drawn up against its neighbour
      // never covers the one between them.
      for (var i = 0; i < scenes.length; i++) {
        var join = x(ends[i]);
        if (join < -_gripWidth || join > width + _gripWidth) continue;
        children.add(Positioned(
          // Inside the strip: showing the whole run, the last join is the
          // strip's right edge, and half a grip past it cannot be pressed.
          left: (join - _gripWidth / 2)
              .clamp(0.0, math.max(0.0, width - _gripWidth))
              .toDouble(),
          width: _gripWidth,
          top: 0,
          bottom: 0,
          child: _grip(i, width, colors),
        ));
      }
      // The playhead, through the boxes as it is through the ruler.
      if (playhead >= 0 && playhead <= width) {
        children.add(Positioned(
          left: playhead - 0.75,
          width: 1.5,
          top: 0,
          bottom: 0,
          child: IgnorePointer(child: ColoredBox(color: colors.primary)),
        ));
      }

      return ClipRect(
        child: Stack(key: const ValueKey("sceneStrip"), children: children),
      );
    });
  }

  /// _box is one scene: its name and how many frames it has, lit and filled
  /// as far as [reached] pixels where it is the one playing.
  Widget _box(double inset, int index, String name, int frames, double? reached,
      ColorScheme colors) {
    var current = reached != null;
    return GestureDetector(
      key: ValueKey("sceneBox$index"),
      behavior: HitTestBehavior.opaque,
      onTap: () => _open(index),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
              color: current ? colors.primary : colors.outlineVariant,
              width: current ? 1.5 : 1),
        ),
        child: Stack(children: [
          if (current)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: reached,
              child: ColoredBox(color: colors.primary.withValues(alpha: 0.22)),
            ),
          // Words only where there is room for them: zoomed out, a short
          // scene is a sliver, and a sliver is still a box to click.
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, box) => box.maxWidth - inset < 28
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: EdgeInsets.only(left: 6 + inset, right: 6),
                      child: Row(children: [
                        Expanded(
                          child: Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 10,
                                  height: 1.2,
                                  fontWeight: current
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: colors.onSurface)),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text("$frames",
                              key: ValueKey("sceneFrames$index"),
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: TextStyle(
                                  fontSize: 10,
                                  height: 1.2,
                                  color: colors.onSurfaceVariant)),
                        ),
                      ]),
                    ),
            ),
          ),
        ]),
      ),
    );
  }

  /// _grip is the gap after scene [index]: dragged, it moves the join with
  /// the next scene, or after the last, the end of the run.
  Widget _grip(int index, double width, ColorScheme colors) {
    var held = _held?.index == index;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        key: ValueKey("sceneGrip$index"),
        behavior: HitTestBehavior.opaque,
        supportedDevices: timelinePointers,
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: (_) => setState(() => _startDrag(index, width)),
        onHorizontalDragUpdate: (d) => _drag(d.delta.dx),
        onHorizontalDragEnd: (_) => _endDrag(),
        onHorizontalDragCancel: _endDrag,
        child: Center(
          child: Container(
            width: 2,
            height: sceneBoxHeight * 0.5,
            decoration: BoxDecoration(
              color: held
                  ? colors.primary
                  : colors.onSurfaceVariant.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }
}
