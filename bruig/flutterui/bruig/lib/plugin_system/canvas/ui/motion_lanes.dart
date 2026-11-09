import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart'
    show AssetKind;
import 'package:bruig/plugin_system/canvas/ui/asset_elements.dart'
    show droppedAsset, droppedKind;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/element_sound.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_player.dart'
    show MotionSlotState;
import 'package:bruig/plugin_system/canvas/ui/timeline_view.dart';
import 'package:bruig/plugin_system/canvas/ui/slots_window.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline_columns.dart';
import 'package:bruig/plugin_system/canvas/ui/row_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// motion_lanes.dart is the elements' rows on the timeline: a group for each
// element with clips (and the one picked, so a first clip can be made), a
// lane for each layer it uses plus one to drop onto, and its own sound's
// lane under them. Placed clips are bars coloured by what they are for, with
// a loop's repeats, a stretched one's pace, and a dot on a pinned end.
//
// A click opens a clip in the Animation panel; a drag moves it, along or onto
// another lane of its element, and its ends stretch it. With the knife out a
// click cuts it. A double-click on an empty stretch makes a clip there from
// the ready-made motions. Laid out as the channels under it are, since it
// scrolls with them: see CanvasChannels.leading.

/// motionLaneHeight is one lane's height, before the text's size.
const double motionLaneHeight = 22;

/// MotionSlotDrag is a clip dragged from an element's slot: to another
/// slot, or onto the timeline.
class MotionSlotDrag {
  final String element;
  final int slot;
  final String clip;
  const MotionSlotDrag(this.element, this.slot, this.clip);
}

/// motionKindColours are the clips' colours, by what they are for.
const Map<MotionKind, Color> motionKindColours = {
  MotionKind.arrive: Color(0xFF2BB3A3),
  MotionKind.loop: Color(0xFF8B7CF6),
  MotionKind.leave: Color(0xFFE5677D),
  MotionKind.action: Color(0xFFE3A21A),
  MotionKind.model: Color(0xFF4F8FE6),
  MotionKind.camera: Color(0xFFD06AD8),
  MotionKind.sound: Color(0xFF3F9F6B),
};

/// motionRowsOf are the elements that have rows: those with clips, and the
/// one picked. Not the sound channels, which have their own lanes.
List<CanvasElement> motionRowsOf(CanvasController c) {
  // Those with a sound channel of their own: its lane goes under theirs.
  var owners = {
    for (var e in c.document.elements)
      if (e is AudioElement && e.clip.channel.startsWith("snd-"))
        e.clip.channel.substring(4),
  };
  return [
    for (var e in c.document.elements)
      if (!(e is AudioElement && e.clip.timed) &&
          (e.base.motion.channelled ||
              e.base.motion.instances != null ||
              owners.contains(e.id) ||
              c.selection.contains(e.id)))
        e,
  ];
}

/// motionLanesOf are [e]'s lanes, top to bottom: its motion layers in use
/// and one more. Folded, none. Its sound is a channel of its own, under
/// them: see element_sound.dart.
List<int> motionLanesOf(CanvasElement e, {bool folded = false}) {
  if (folded) return const [];
  var m = e.base.motion;
  var used = {
    for (var p in m.placed)
      if (p.layer < motionLayers) p.layer
  };
  var top = used.isEmpty ? 0 : used.reduce(math.max) + 1;
  return [
    for (var l = 0; l <= math.min(top, motionLayers - 1); l++) l,
  ];
}

class MotionLanes extends StatefulWidget {
  final CanvasController controller;
  final TimelineView view;

  /// only is the one element whose rows these are -- its sound channel
  /// under them, as CanvasChannels lays them -- or null for every one.
  final String? only;

  const MotionLanes(
      {required this.controller, required this.view, this.only, super.key});

  @override
  State<MotionLanes> createState() => _MotionLanesState();
}

enum _Grip { start, end, bar }

/// _Hit is what a press landed on: an element's lane, and the placed clip
/// there and which part of it, if any.
typedef _Hit = ({
  CanvasElement element,
  int layer,
  ClipPlacement? placement,
  _Grip? grip,
});

class _MotionLanesState extends State<MotionLanes> {
  CanvasController get controller => widget.controller;

  List<CanvasElement> get _rows => [
        for (var e in motionRowsOf(controller))
          if (widget.only == null || e.id == widget.only) e
      ];

  /// _flipped are the elements whose rows were folded or opened by hand,
  /// against what the channel-height button says (small: every row folded
  /// to one); pressed again, the button puts them all back. By id, for the
  /// session.
  static final Set<String> _flipped = {};
  static Object? _flippedAt;

  bool _isFolded(CanvasElement e) =>
      (controller.laneSize == 0) != _flipped.contains(e.id);

  _Hit? _press;
  double _pressSeconds = 0;
  ClipSpan? _pressSpan;
  bool _dragged = false;
  bool _unpinned = false;

  double get _scale => math.max(1.0, MediaQuery.textScalerOf(context).scale(1));

  /// _lane is one layer's lane: taller at the button's largest.
  double get _lane =>
      motionLaneHeight * _scale * (controller.laneSize == 2 ? 1.6 : 1);
  double _rowHeight(CanvasElement e) => _isFolded(e)
      ? _lane + 4
      : math.max(_lane * 1.6, motionLanesOf(e).length * _lane) + 4;

  int get _fps => math.max(1, controller.document.frameRate);
  double _x(double seconds, double width) =>
      widget.view.xOf(seconds * _fps, width);
  double _seconds(double x, double width) =>
      widget.view.frameAt(x, width, 1 << 30) / _fps;

  /// _snap is [s] on the timeline's beat grid -- a half beat -- unless Alt
  /// is held; where the canvas has no tempo, a frame.
  double _snap(double s) {
    if (HardwareKeyboard.instance.isAltPressed) return s;
    var spb = controller.document.audio.secondsPerBeat;
    var step = spb > 0 ? spb / 2 : 1 / _fps;
    return (s / step).round() * step;
  }

  _Hit? _hit(Offset local, double width) {
    var y = 0.0;
    for (var e in _rows) {
      var h = _rowHeight(e);
      if (local.dy >= y && local.dy < y + h) {
        var folded = _isFolded(e);
        var lanes = motionLanesOf(e, folded: folded);
        var row = folded ? -1 : ((local.dy - y - 2) / _lane).floor();
        var layer = folded
            ? -1
            : row >= 0 && row < lanes.length
                ? lanes[row]
                : (lanes.isEmpty ? 0 : lanes.last);
        var times = motionTimesOf(controller.document);
        for (var p in e.base.motion.placed.reversed) {
          if (!folded && p.layer != layer) continue;
          var s = times.span(p.id);
          if (s == null) continue;
          var from = _x(s.start, width), to = _x(s.end, width);
          const reach = 6.0;
          if (local.dx < from - reach || local.dx > to + reach) continue;
          var grip = (local.dx - to).abs() <= reach
              ? _Grip.end
              : (local.dx - from).abs() <= reach
                  ? _Grip.start
                  : _Grip.bar;
          return (element: e, layer: p.layer, placement: p, grip: grip);
        }
        return (
          element: e,
          layer: layer < 0 ? 0 : layer,
          placement: null,
          grip: null
        );
      }
      y += h;
    }
    return null;
  }

  /// _open picks placement [p]: in the Chain where the Chain is out, and
  /// -- [show], a double-click -- bringing the Chain out to it. A single
  /// click never opens it (Ken).
  void _open(CanvasElement e, ClipPlacement p, {bool show = false}) {
    controller.pickMotion(e.id, p.clip, placement: p.id);
    var out = controller.animationOpen || controller.effectsOpen;
    if (!show && !out) return;
    var c = e.base.motion.clip(p.clip);
    if (c != null && c.isSound) {
      controller.effectsOpen = true;
    } else {
      controller.animationOpen = true;
    }
  }

  void _down(Offset local, double width) {
    var hit = _hit(local, width);
    _press = hit;
    _dragged = false;
    _unpinned = false;
    _pressSeconds = _seconds(local.dx, width);
    _pressSpan =
        hit?.placement == null ? null : controller.spanOf(hit!.placement!.id);
  }

  void _tap(Offset local, double width) {
    var hit = _hit(local, width);
    if (hit == null) return;
    if (hit.placement case var p?) {
      if (controller.timelineTool == TimelineTool.knife) {
        controller.cutPlacement(
            hit.element.id, p.id, _snap(_seconds(local.dx, width)));
        return;
      }
      _open(hit.element, p);
    } else {
      controller.pickMotion(hit.element.id, null);
    }
  }

  void _drag(Offset local, double width) {
    var hit = _press, span = _pressSpan;
    if (hit == null || span == null || hit.placement == null) return;
    if (controller.timelineTool == TimelineTool.knife) return;
    var p = hit.placement!;
    if (!_dragged) {
      _dragged = true;
      controller.pause();
      controller.beginInteraction();
    }
    var now = _seconds(local.dx, width);
    var by = now - _pressSeconds;
    switch (hit.grip) {
      case _Grip.end:
        controller.stretchPlacement(hit.element.id, p.id,
            end: _snap(math.max(span.start + 0.05, span.end + by)),
            transient: true);
      case _Grip.start:
        controller.stretchPlacement(hit.element.id, p.id,
            start: _snap(span.start + by), transient: true);
      default:
        var over = _hit(local, width);
        var layer = over != null &&
                over.element.id == hit.element.id &&
                (over.layer == soundLayer) == (p.layer == soundLayer)
            ? over.layer
            : null;
        if (controller.movePlacement(
            hit.element.id, p.id, _snap(span.start + by),
            layer: layer, transient: true)) {
          _unpinned = true;
        }
    }
  }

  void _up() {
    if (_dragged) {
      controller.endInteraction();
      if (_unpinned && mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
            content: Text("Moved by hand, it let go of what it was pinned "
                "to: it stays where it was put. Pin it again in Timing.")));
      }
    }
    _press = null;
    _dragged = false;
  }

  /// _make is a double-click on a row: on a clip, that clip opened in the
  /// Chain; on an empty spot, a short clip made there at once and picked --
  /// double-clicked in turn, set up in the Chain (Ken: no list of options).
  void _make(Offset local, double width) {
    var hit = _hit(local, width);
    if (hit == null) return;
    if (hit.placement case var p?) {
      _open(hit.element, p, show: true);
      return;
    }
    var e = hit.element;
    var seconds = math.max(0.0, _snap(_seconds(local.dx, width)));
    var kind = hit.layer == soundLayer
        ? MotionKind.sound
        : e is CameraElement
            ? MotionKind.camera
            : MotionKind.action;
    controller.beginInteraction();
    var clip = controller.newClip(e.id, kind: kind, layer: hit.layer);
    var placed =
        controller.placeClip(e.id, clip, seconds: seconds, layer: hit.layer);
    controller.endInteraction();
    var now = controller.document.elementById(e.id);
    var p = now?.base.motion.placement(placed);
    if (now != null && p != null) _open(now, p);
  }

  @override
  Widget build(BuildContext context) {
    // The button's size, on this canvas: another canvas -- whose elements
    // may have the same ids -- starts as its button says.
    var at =
        (controller, controller.folder, controller.name, controller.laneSize);
    if (_flippedAt != at) {
      _flippedAt = at;
      _flipped.clear();
    }
    var rows = _rows;
    if (rows.isEmpty) return const SizedBox.shrink();
    var theme = ThemeNotifier.of(context);
    var colors = theme.colors;
    var height = rows.fold(0.0, (a, e) => a + _rowHeight(e));
    var label = TextStyle(
        fontSize: 11, color: colors.onSurface, fontWeight: FontWeight.w600);
    return SizedBox(
      key: const ValueKey("motionLanes"),
      height: height,
      child: Row(children: [
        SizedBox(
          width: controller.headerWidth,
          child: Column(children: [
            for (var e in rows)
              SizedBox(
                key: ValueKey("motionRow-${e.id}"),
                height: _rowHeight(e),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => controller.selectOnly(e.id),
                  child: _header(e, colors, label),
                ),
              ),
          ]),
        ),
        // Its slots beside its rows, a cue each, when they are.
        if (slotsWidthIn(context, controller) > 0)
          SizedBox(
            width: slotsWidthIn(context, controller),
            child: Column(children: [
              for (var e in rows)
                SizedBox(
                    height: _rowHeight(e),
                    child: _RowSlots(controller: controller, element: e)),
            ]),
          ),
        // The frames, unless this is the slots shown alone.
        if (!lanesIn(context))
          const Spacer()
        else
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              var width = constraints.maxWidth;
              // A clip dragged from a slot -- in the mixer, or beside the
              // rows -- let go on a row: placed there, on the lane it is let
              // go on. Another element's, copied to this one first.
              return DragTarget<Object>(
                // A sound let go on its rows: on its own channel, there.
                onWillAcceptWithDetails: (d) =>
                    d.data is MotionSlotDrag ||
                    droppedKind(d.data) == AssetKind.audio,
                onAcceptWithDetails: (d) async {
                  var box = context.findRenderObject() as RenderBox?;
                  if (box == null) return;
                  var local = box.globalToLocal(d.offset);
                  if (d.data case MotionSlotDrag drag) {
                    _dropped(drag, local, width);
                    return;
                  }
                  var hit = _hit(local, width);
                  var asset = await droppedAsset(d.data);
                  if (hit == null || asset == null || !mounted) return;
                  var frame =
                      (math.max(0.0, _snap(_seconds(local.dx, width))) * _fps)
                          .round();
                  controller.addElementSound(
                      hit.element.id, asset.source, frame);
                },
                builder: (context, over, _) {
                  var lanes =
                      _lanes(over.isNotEmpty, rows, height, width, colors);
                  // A row playing from its slots, striped (row_header.dart).
                  var top = 0.0;
                  var striped = <Widget>[];
                  for (var e in rows) {
                    var h = _rowHeight(e);
                    if (controller.fromSlotsOf(e.id) != null) {
                      striped.add(Positioned(
                          left: 0,
                          right: 0,
                          top: top,
                          height: h,
                          child: SlotsStripes(
                              key: ValueKey("rowFromSlots-${e.id}"))));
                    }
                    top += h;
                  }
                  if (striped.isEmpty) return lanes;
                  return Stack(children: [lanes, ...striped]);
                },
              );
            }),
          ),
      ]),
    );
  }

  /// _header is [e]'s row header (see row_header.dart): its name, what it
  /// is, and the motion, sound and solo buttons -- the sound and the solo
  /// its own sound's, whose rows follow as the same row (see canvas_rows.dart)
  /// from the channel height M up; each motion layer's label level with its
  /// lane, a bar of how much of it plays.
  Widget _header(CanvasElement e, ColorScheme colors, TextStyle label) {
    var own = controller.soundChannelOf(e.id);
    var heard = own != null &&
        controller.laneSize > 0 &&
        controller.timelineShow != TimelineShow.animation;
    var m = e.base.motion;
    var layers = {
      for (var p in m.placed)
        if (p.layer < motionLayers) p.layer
    }.length;
    var copies = m.instances?.count ?? 1;
    void mute(TimelineChannel own) {
      var now = controller.mixNow(own);
      controller.beginInteraction();
      controller.changeChannelMix(own, now, now.copyWith(mute: !now.mute),
          transient: true);
      controller.endInteraction();
    }

    return RowHeader(
      colour: colors.primary,
      width: controller.headerWidth,
      height: _rowHeight(e),
      selected: controller.selection.contains(e.id),
      joinsBelow: heard,
      back: switch (controller.fromSlotsOf(e.id)) {
        var item? => SlotsReturn(
            key: ValueKey("rowBack-${e.id}"),
            onTap: () => controller.backToTimelineFor(item)),
        _ => null,
      },
      fold: InkWell(
        key: ValueKey("motionFold-${e.id}"),
        onTap: () => setState(() => _flipped.contains(e.id)
            ? _flipped.remove(e.id)
            : _flipped.add(e.id)),
        child: SizedBox(
          width: 18,
          height: 20,
          child: Icon(_isFolded(e) ? Icons.chevron_right : Icons.expand_more,
              size: 14, color: colors.onSurfaceVariant),
        ),
      ),
      name: Text(e.name.isEmpty ? e.id : e.name,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: label),
      kind: [
        layers == 0 ? "Motion" : "$layers layer${layers == 1 ? "" : "s"}",
        if (own != null) "sound",
      ].join(" · "),
      badges: [
        if (copies > 1)
          Container(
            key: ValueKey("rowCopies-${e.id}"),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
                color: colors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(6)),
            child: Text("×$copies",
                style: const TextStyle(
                    fontSize: 9, height: 1.4, color: Color(0xFFE2B04A))),
          ),
      ],
      // Its motion: shown as on; switching a row's motion off is to come.
      motion: RowToggle(ValueKey("rowMotion-${e.id}"), on: true),
      sound: own == null
          ? null
          : RowToggle(ValueKey("rowMute-${e.id}"),
              on: !controller.mixNow(own).mute, onTap: () => mute(own)),
      solo: own == null
          ? null
          : RowToggle(ValueKey("rowSolo-${e.id}"),
              on: controller.solo.contains(own.key),
              onTap: () => controller.toggleSolo(own.key)),
      bands: [
        for (var (i, l) in motionLanesOf(e, folded: _isFolded(e)).indexed)
          RowBand(2 + i * _lane, _lane, "L${l + 1}", motionColour,
              weight: m.weight(l)),
      ],
    );
  }

  void _dropped(MotionSlotDrag drag, Offset local, double width) {
    var hit = _hit(local, width);
    if (hit == null) return;
    var into = hit.element.id;
    var seconds = math.max(0.0, _snap(_seconds(local.dx, width)));
    controller.beginInteraction();
    var clip = into == drag.element
        ? drag.clip
        : controller.copyClipTo(drag.element, drag.clip, into);
    if (clip == null) {
      controller.endInteraction();
      return;
    }
    var c = controller.motionOf(into).clip(clip);
    var layer =
        c == null || c.isSound || hit.layer == soundLayer ? null : hit.layer;
    var placed =
        controller.placeClip(into, clip, seconds: seconds, layer: layer);
    controller.endInteraction();
    var now = controller.document.elementById(into);
    var p = now?.base.motion.placement(placed);
    if (now != null && p != null) _open(now, p);
  }

  Widget _lanes(bool over, List<CanvasElement> rows, double height,
      double width, ColorScheme colors) {
    return DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
            border: over ? Border.all(color: colors.primary, width: 2) : null),
        child: GestureDetector(
          supportedDevices: timelinePointers,
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _tap(d.localPosition, width),
          onDoubleTapDown: (d) => _make(d.localPosition, width),
          onDoubleTap: () {},
          onHorizontalDragDown: (d) => _down(d.localPosition, width),
          onHorizontalDragUpdate: (d) => _drag(d.localPosition, width),
          onHorizontalDragEnd: (_) => _up(),
          onHorizontalDragCancel: _up,
          child: MouseRegion(
            cursor: controller.timelineTool == TimelineTool.knife
                ? SystemMouseCursors.precise
                : SystemMouseCursors.basic,
            child: CustomPaint(
              key: ValueKey(widget.only == null
                  ? "motionLanesPaint"
                  : "motionLanesPaint-${widget.only}"),
              size: Size(width, height),
              painter: _LanesPainter(
                rows: rows,
                folded: {
                  for (var e in rows)
                    if (_isFolded(e)) e.id
                },
                lane: _lane,
                rowHeight: _rowHeight,
                times: motionTimesOf(controller.document),
                x: (s) => _x(s, width),
                picked: controller.pickedPlacement,
                colors: colors,
                textScaler: MediaQuery.textScalerOf(context),
              ),
            ),
          ),
        ));
  }
}

/// _RowSlots are an element's slots beside its rows, a cue each, as on its
/// strip in the mixer: its triangle launches it -- an empty one stops the
/// element's clips; its name, clicked, opens it in the Animation panel;
/// dragged, it goes onto the timeline or into another slot.
class _RowSlots extends StatelessWidget {
  final CanvasController controller;
  final CanvasElement element;
  const _RowSlots({required this.controller, required this.element});

  @override
  Widget build(BuildContext context) {
    var c = controller;
    var colors = ThemeNotifier.of(context).colors;
    var m = element.base.motion;
    Widget cell(int i) {
      var clip = m.slot(i);
      var state = c.motionSlotState(element.id, i);
      var lit = state == MotionSlotState.playing ||
          state == MotionSlotState.stopping ||
          state == MotionSlotState.queued;
      var ink = lit ? const Color(0xFF0E0F12) : colors.onSurface;
      var launch = Listener(
        key: ValueKey("rowSlot-${element.id}-$i"),
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => c.pressMotionSlot(element.id, i),
        onPointerUp: (_) {
          if (clip != null) c.releaseMotionClip(element.id, clip.id);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Icon(clip == null ? Icons.stop : Icons.play_arrow,
              size: 11, color: clip == null ? colors.onSurfaceVariant : ink),
        ),
      );
      var box = Container(
        decoration: BoxDecoration(
          color: clip == null
              ? colors.surfaceContainerHigh
              : motionKindColours[clip.kind]!.withValues(alpha: lit ? 1 : 0.45),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
              color: c.pickedMotion != null && c.pickedMotion == clip?.id
                  ? colors.onSurface
                  : colors.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Row(children: [
          launch,
          // Empty: pressed, a new clip in it, opened -- as the mixer's
          // slots do.
          if (clip == null)
            Expanded(
              child: GestureDetector(
                key: ValueKey("rowSlotNew-${element.id}-$i"),
                behavior: HitTestBehavior.opaque,
                // Double-clicked: a new clip in it, picked (Ken).
                onDoubleTap: () {
                  var id = c.newClip(element.id,
                      kind: element is CameraElement
                          ? MotionKind.camera
                          : MotionKind.action,
                      slot: i);
                  c.pickMotion(element.id, id);
                },
              ),
            ),
          if (clip != null)
            Expanded(
              // Clicked, it has the keyboard: Delete or Backspace empties
              // the slot, not the canvas's selection (Ken: it took the
              // element, and its channel with it).
              child: SlotFocus(
                key: ValueKey("rowSlotKeys-${element.id}-$i"),
                onDelete: () {
                  c.beginInteraction();
                  c.clearMotionSlot(element.id, i);
                  c.endInteraction();
                },
                builder: (focus) => GestureDetector(
                  key: ValueKey("rowSlotName-${element.id}-$i"),
                  behavior: HitTestBehavior.opaque,
                  // A click picks it; a double-click opens it in the Chain.
                  onTap: () {
                    c.pickMotion(element.id, clip.id);
                    if (c.effectsOpen) c.animationOpen = true;
                    focus.requestFocus();
                  },
                  onDoubleTap: () {
                    c.pickMotion(element.id, clip.id);
                    c.animationOpen = true;
                  },
                  child: Text(clip.name.isEmpty ? "Clip" : clip.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, height: 1.1, color: ink)),
                ),
              ),
            ),
        ]),
      );
      if (clip == null) return box;
      return Draggable<Object>(
        data: MotionSlotDrag(element.id, i, clip.id),
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Material(
          color: motionKindColours[clip.kind],
          borderRadius: BorderRadius.circular(3),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(clip.name,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0E0F12))),
          ),
        ),
        child: box,
      );
    }

    return SlotsWindow(controller: c, cell: cell);
  }
}

class _LanesPainter extends CustomPainter {
  final List<CanvasElement> rows;
  final Set<String> folded;
  final double lane;
  final double Function(CanvasElement) rowHeight;
  final MotionTimes times;
  final double Function(double seconds) x;
  final String? picked;
  final ColorScheme colors;
  final TextScaler textScaler;

  _LanesPainter({
    required this.rows,
    required this.folded,
    required this.lane,
    required this.rowHeight,
    required this.times,
    required this.x,
    required this.picked,
    required this.colors,
    required this.textScaler,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // A clip starting before the frames shown, zoomed in, is drawn from
    // where it starts: kept to the lanes, not over the strips beside them.
    canvas.clipRect(Offset.zero & size);
    var y = 0.0;
    var line = Paint()..color = colors.outlineVariant.withValues(alpha: 0.5);
    for (var e in rows) {
      var h = rowHeight(e);
      var isFolded = folded.contains(e.id);
      var lanes = motionLanesOf(e, folded: isFolded);
      canvas.drawLine(
          Offset(0, y + h - 0.5), Offset(size.width, y + h - 0.5), line);
      // The lanes' own lines, faint; the sound's lane tinted.
      for (var (i, l) in lanes.indexed) {
        var top = y + 2 + i * lane;
        if (l == soundLayer) {
          canvas.drawRect(Rect.fromLTWH(0, top, size.width, lane),
              Paint()..color = const Color(0x143F9F6B));
        } else if (i > 0) {
          canvas.drawLine(Offset(0, top), Offset(size.width, top),
              Paint()..color = colors.outlineVariant.withValues(alpha: 0.2));
        }
      }
      var m = e.base.motion;
      for (var p in m.placed) {
        var c = m.clip(p.clip);
        var s = times.span(p.id);
        if (c == null || s == null) continue;
        var row = isFolded ? 0 : lanes.indexOf(p.layer);
        if (row < 0) continue;
        var top = y + 2 + row * lane + 1;
        var rect = Rect.fromLTRB(
            x(s.start),
            top,
            math.max(x(s.end), x(s.start) + 6),
            top + (isFolded ? lane : lane - 2));
        if (rect.right < 0 || rect.left > size.width) continue;
        _clip(canvas, rect, c, p, s);
      }
      // An element reused: where each copy's clips start, as numbered
      // ticks along the foot of its row, from its first clip -- only with a
      // clip on the timeline for them to start (Ken: without one, three
      // blue lines that meant nothing).
      if (m.instances case var set? when set.count > 1) {
        var from = [
          for (var p in m.placed)
            if (times.span(p.id) case var s?) s.start
        ].fold<double?>(null, (a, b) => a == null ? b : math.min(a, b));
        var starts = [for (var i = 0; i < set.count; i++) set.startOf(i)];
        if (from != null && starts.any((t) => t > 0)) {
          var tick = Paint()
            ..color = colors.primary
            ..strokeWidth = 1.5;
          for (var (i, t) in starts.indexed) {
            var tx = x(from + t);
            if (tx < 0 || tx > size.width) continue;
            canvas.drawLine(
                Offset(tx, y + h - 7), Offset(tx, y + h - 1.5), tick);
            var tp = TextPainter(
                text: TextSpan(
                    text: "${i + 1}",
                    style: TextStyle(
                        fontSize: 8,
                        color: colors.primary,
                        fontWeight: FontWeight.w700)),
                textDirection: TextDirection.ltr,
                textScaler: TextScaler.noScaling)
              ..layout();
            tp.paint(canvas, Offset(tx + 2, y + h - 2 - tp.height));
          }
        }
      }
      y += h;
    }
  }

  void _clip(
      Canvas canvas, Rect rect, MotionClip c, ClipPlacement p, ClipSpan s) {
    var colour = motionKindColours[c.kind]!;
    var r = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawRRect(r, Paint()..color = colour);
    if (p.id == picked) {
      canvas.drawRRect(
          r.inflate(1.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = colors.onSurface);
    }
    canvas.save();
    canvas.clipRRect(r);
    // A loop's repeats, where they are far enough apart to see.
    if (c.loop && c.span > 0 && x(s.start + c.span) - x(s.start) >= 3) {
      var tick = Paint()..color = const Color(0x73FFFFFF);
      for (var t = s.start + c.span; t < s.end - 0.01; t += c.span) {
        canvas.drawLine(
            Offset(x(t), rect.top + 3), Offset(x(t), rect.bottom - 3), tick);
      }
    }
    var name = c.name.isEmpty ? c.kind.label : c.name;
    var pace = !c.loop && !c.isSound && (s.speed - c.speed).abs() > 0.02
        ? "  ${s.speed.toStringAsFixed(2)}×"
        : "";
    var tp = TextPainter(
      text: TextSpan(
          text: "$name$pace",
          style: const TextStyle(
              fontSize: 10.5,
              color: Colors.white,
              fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    var left = rect.left + (p.startPin != null ? 12 : 6);
    tp.paint(canvas, Offset(left, rect.center.dy - tp.height / 2));
    canvas.restore();
    // A dot at each pinned end.
    var dot = Paint()..color = Colors.white;
    if (p.startPin != null) {
      canvas.drawCircle(Offset(rect.left + 5, rect.top + 5), 3, dot);
    }
    if (p.endPin != null) {
      canvas.drawCircle(Offset(rect.right - 5, rect.top + 5), 3, dot);
    }
  }

  @override
  bool shouldRepaint(_LanesPainter old) => true;
}
