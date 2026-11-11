import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
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
import 'package:bruig/plugin_system/canvas/ui/slot_face.dart';
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
/// motionLayerName is what layer [l] of [m] is called -- on the mixer's
/// chip, beside its band on the timeline: the clip on it, the first placed
/// there or else the first made for it, or L1, L2 ...
String motionLayerName(ElementMotion m, int l) {
  for (var p in m.placed) {
    if (p.layer == l) {
      if (m.clip(p.clip) case var c? when c.name.isNotEmpty) return c.name;
    }
  }
  for (var c in m.clips) {
    if (c.layer == l && c.name.isNotEmpty) return c.name;
  }
  return "L${l + 1}";
}

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

/// clipStacks is which stack each of [placed] is in, counted within its
/// layer -- or across every layer, [together], for a folded row. A clip that
/// starts before another in its stack has ended goes into the next stack
/// down, so clips that overlap are drawn one under another and none hides
/// another (Ken, 2026-11-11: an arrival, an exit and a loop drawn over each
/// other, "very hard to see").
Map<String, int> clipStacks(List<ClipPlacement> placed, MotionTimes times,
    {bool together = false}) {
  var groups = <int, List<(ClipPlacement, ClipSpan)>>{};
  for (var p in placed) {
    var s = times.span(p.id);
    if (s == null) continue;
    groups.putIfAbsent(together ? 0 : p.layer, () => []).add((p, s));
  }
  var out = <String, int>{};
  for (var group in groups.values) {
    group.sort((a, b) => a.$2.start.compareTo(b.$2.start));
    var ends = <double>[];
    for (var (p, s) in group) {
      var k = ends.indexWhere((end) => end <= s.start + 1e-6);
      if (k < 0) {
        ends.add(s.end);
        k = ends.length - 1;
      } else {
        ends[k] = s.end;
      }
      out[p.id] = k;
    }
  }
  return out;
}

/// MotionTrack is one lane of an unfolded row: a layer, and which of its
/// stacks (see clipStacks).
typedef MotionTrack = ({int layer, int stack});

/// motionTracksOf are [e]'s lanes unfolded, top to bottom: for each of its
/// layers (motionLanesOf) a lane for every stack its clips need -- what the
/// row's arrow opens (Ken: "shouldn't this ... show the different layers?").
List<MotionTrack> motionTracksOf(CanvasElement e, MotionTimes times) {
  var placed = e.base.motion.placed;
  var stacks = clipStacks(placed, times);
  return [
    for (var l in motionLanesOf(e))
      for (var k = 0;
          k <=
              [
                for (var p in placed)
                  if (p.layer == l) stacks[p.id] ?? 0
              ].fold(0, math.max);
          k++)
        (layer: l, stack: k),
  ];
}

/// motionClipRect is where placement [p] of a row is drawn, [left] to
/// [right], the row starting [y] down and [rowHeight] tall: on its track's
/// lane ([lane] tall) unfolded; a step lower for each track before its on
/// a [shared] band; and folded, in its share of the one band, a stack to a
/// share. The painter and the press both ask here, so a clip is pressed
/// where it is drawn.
Rect? motionClipRect(
  ClipPlacement p, {
  required bool folded,
  required bool shared,
  required List<MotionTrack> tracks,
  required Map<String, int> stacks,
  required double lane,
  required double y,
  required double rowHeight,
  required double left,
  required double right,
}) {
  var stack = stacks[p.id] ?? 0;
  right = math.max(right, left + 6);
  if (folded) {
    var count = stacks.values.fold(0, math.max) + 1;
    var share = lane / count;
    var top = y + 3 + stack * share;
    return Rect.fromLTRB(left, top, right, top + share - (count > 1 ? 1.5 : 0));
  }
  var row = tracks.indexOf((layer: p.layer, stack: stack));
  if (row < 0) return null;
  if (shared) {
    var step = sharedStep(tracks.length, rowHeight);
    return Rect.fromLTRB(left, y + 3 + row * step, right, y + rowHeight - 3);
  }
  var top = y + 2 + row * lane + 1;
  return Rect.fromLTRB(left, top, right, top + lane - 2);
}

class MotionLanes extends StatefulWidget {
  final CanvasController controller;
  final TimelineView view;

  /// only is the one element whose rows these are -- its sound channel
  /// under them, as CanvasChannels lays them -- or null for every one.
  final String? only;

  /// alt is a row of the timeline's every other, tinted (the approved
  /// design's alternate rows).
  final bool alt;

  /// onBoxStart, onBox and onBoxEnd are a press on an empty lane dragged:
  /// the box the timeline picks clips with, sounds and motion alike, given
  /// the pointer on screen (see CanvasChannels).
  final void Function(Offset global)? onBoxStart;
  final void Function(Offset global)? onBox;
  final VoidCallback? onBoxEnd;

  const MotionLanes(
      {required this.controller,
      required this.view,
      this.only,
      this.alt = false,
      this.onBoxStart,
      this.onBox,
      this.onBoxEnd,
      super.key});

  @override
  State<MotionLanes> createState() => _MotionLanesState();
}

enum _Grip { start, end, bar }

/// _live are the motion lanes on screen, for the box: see
/// motionPlacementsIn.
final Set<_MotionLanesState> _live = {};

/// motionPlacementsIn are the clips the box [global] (on screen) touches on
/// every motion lane showing, as (element, placement).
Set<(String, String)> motionPlacementsIn(Rect global) => {
      for (var lanes in _live) ...lanes._placementsIn(global),
    };

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

  /// _paint is the lanes' drawing, for where they are on screen.
  final GlobalKey _paint = GlobalKey();

  /// _boxing is whether the press under way is the box (begun on an empty
  /// lane).
  bool _boxing = false;

  /// _others are the other clips picked with the one dragged, and where
  /// each started: motion placements by their seconds, sounds as the
  /// channels move them (see CanvasChannels._group).
  List<(String, String, double)> _others = const [];
  List<(CanvasElement, MediaClip, int?)> _sounds = const [];

  @override
  void initState() {
    super.initState();
    _live.add(this);
  }

  @override
  void dispose() {
    _live.remove(this);
    super.dispose();
  }

  /// _placementsIn are this lane's clips the box [global] touches.
  Iterable<(String, String)> _placementsIn(Rect global) sync* {
    var box = _paint.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    var origin = box.localToGlobal(Offset.zero);
    var width = box.size.width;
    var y = 0.0;
    for (var e in _rows) {
      for (var p in e.base.motion.placed) {
        var r = _clipRect(e, p, y, width);
        if (r != null && r.shift(origin).overlaps(global)) yield (e.id, p.id);
      }
      y += _rowHeight(e);
    }
  }

  List<CanvasElement> get _rows => [
        for (var e in motionRowsOf(controller))
          if (widget.only == null || e.id == widget.only) e
      ];

  /// _isFolded is whether [e]'s row is folded to one: see
  /// CanvasController.rowFolded.
  bool _isFolded(CanvasElement e) => controller.rowFolded(e.id);

  _Hit? _press;

  /// _linkFrom is the sound the pressed clip is linked to, and where it was
  /// then: dragged, it moves with the clip.
  (TimedLane, int)? _linkFrom;
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
      : _shared(e)
          ? _lane * 1.6 + 4
          : math.max(_lane * 1.6, _tracks(e).length * _lane) + 4;

  MotionTimes get _times => motionTimesOf(controller.document);

  /// _tracks are [e]'s lanes unfolded: see motionTracksOf.
  List<MotionTrack> _tracks(CanvasElement e) => motionTracksOf(e, _times);

  /// _shared is whether [e]'s layers share one band, each a step lower than
  /// the one before (the approved design, at S and M); at L each layer has
  /// a band of its own.
  bool _shared(CanvasElement e) =>
      !_isFolded(e) && controller.laneSize < 2 && _tracks(e).length > 1;

  /// _clipRect is where placement [p] of [e] is drawn, its row starting [y]
  /// down: see motionClipRect.
  Rect? _clipRect(CanvasElement e, ClipPlacement p, double y, double width) {
    var s = _times.span(p.id);
    if (s == null) return null;
    var folded = _isFolded(e);
    return motionClipRect(p,
        folded: folded,
        shared: _shared(e),
        tracks: folded ? const [] : _tracks(e),
        stacks: clipStacks(e.base.motion.placed, _times, together: folded),
        lane: _lane,
        y: y,
        rowHeight: _rowHeight(e),
        left: _x(s.start, width),
        right: _x(s.end, width));
  }

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
        // The topmost drawn first: the last drawn, back to the first.
        const reach = 6.0;
        for (var p in e.base.motion.placed.reversed) {
          var r = _clipRect(e, p, y, width);
          if (r == null) continue;
          if (local.dy < r.top || local.dy > r.bottom) continue;
          if (local.dx < r.left - reach || local.dx > r.right + reach) {
            continue;
          }
          var grip = (local.dx - r.right).abs() <= reach
              ? _Grip.end
              : (local.dx - r.left).abs() <= reach
                  ? _Grip.start
                  : _Grip.bar;
          return (element: e, layer: p.layer, placement: p, grip: grip);
        }
        // Nothing there: the lane under the press, to drop onto.
        if (_isFolded(e)) {
          return (element: e, layer: 0, placement: null, grip: null);
        }
        var tracks = _tracks(e);
        var row = _shared(e)
            ? ((local.dy - y - 3) / sharedStep(tracks.length, h)).floor()
            : ((local.dy - y - 2) / _lane).floor();
        var track = tracks[row.clamp(0, tracks.length - 1)];
        return (element: e, layer: track.layer, placement: null, grip: null);
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

  void _down(Offset local, Offset global, double width) {
    var hit = _hit(local, width);
    // An empty spot, dragged: the box, as on the sound lanes.
    _boxing = hit != null &&
        hit.placement == null &&
        controller.timelineTool == TimelineTool.select &&
        widget.onBoxStart != null;
    if (_boxing) {
      widget.onBoxStart!(global);
      _press = null;
      return;
    }
    _press = hit;
    _linkFrom = null;
    if (hit?.placement case var p?) {
      if (controller.linkedSound(hit!.element.id, p.id) case var l?) {
        _linkFrom = (l, l.clip.at);
      }
    }
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
      // Shift adds it to what is picked, or takes it out.
      if (HardwareKeyboard.instance.isShiftPressed) {
        controller.toggleMotionPick(hit.element.id, p.id);
        return;
      }
      _open(hit.element, p);
    } else {
      controller.pickMotion(hit.element.id, null);
    }
  }

  void _drag(Offset local, Offset global, double width) {
    if (_boxing) {
      widget.onBox?.call(global);
      return;
    }
    var hit = _press, span = _pressSpan;
    if (hit == null || span == null || hit.placement == null) return;
    if (controller.timelineTool == TimelineTool.knife) return;
    var p = hit.placement!;
    if (!_dragged) {
      _dragged = true;
      controller.pause();
      controller.beginInteraction();
      // One of several picked, moved by its bar: all of them go, together
      // -- the other clips by as many seconds, the sounds by as many
      // frames.
      var mine = (hit.element.id, p.id);
      var picks = controller.motionPicks;
      var together = hit.grip == _Grip.bar &&
          picks.contains(mine) &&
          (picks.length > 1 || controller.clipSelection.isNotEmpty);
      _others = !together
          ? const []
          : [
              for (var (el, id) in picks)
                if ((el, id) != mine)
                  if (controller.spanOf(id) case var s?) (el, id, s.start),
            ];
      var sounds = together ? controller.clipSelection : const <String>{};
      _sounds = [
        for (var l in controller.timedLanes)
          if (sounds.contains(l.element.id))
            (l.element, l.clip, controller.clipRunStart(l.element.id)),
      ];
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
        var to = _snap(span.start + by);
        if (controller.movePlacement(hit.element.id, p.id, to,
            layer: _others.isEmpty && _sounds.isEmpty ? layer : null,
            transient: true)) {
          _unpinned = true;
        }
        var moved = math.max(0.0, to) - span.start;
        for (var (el, id, start) in _others) {
          controller.movePlacement(el, id, math.max(0.0, start + moved),
              transient: true);
        }
        var frames = (moved * controller.document.frameRate).round();
        for (var (e, clip, run) in _sounds) {
          if (run == null) {
            controller.setTimedClip(
                e, clip.copyWith(at: math.max(0, clip.at + frames)),
                transient: true);
          } else {
            controller.placeTimedClip(e, clip, run + frames, transient: true);
          }
        }
        // Linked: its sound by as much (Ken, 2026-11-10).
        if (_linkFrom case (var l, var at)) {
          var fps = controller.document.frameRate;
          var moved = (math.max(0.0, to) - span.start) * fps;
          controller.setTimedClip(
              l.element, l.clip.copyWith(at: math.max(0, at + moved.round())),
              transient: true);
        }
    }
  }

  void _up() {
    if (_boxing) {
      _boxing = false;
      widget.onBoxEnd?.call();
      return;
    }
    _others = const [];
    _sounds = const [];
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
                  // Right-clicked: its row's colour (Ken, 2026-11-10).
                  onSecondaryTapUp: (d) =>
                      _colourMenu(context, e.id, d.globalPosition),
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
      colour: controller.rowColour(e.id),
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
      fold: RowFold(
          key: ValueKey("motionFold-${e.id}"),
          folded: _isFolded(e),
          onTap: () => controller.toggleRowFold(e.id)),
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
      // Its motion, switched off and on: drawn as if it had none.
      motion: RowToggle(ValueKey("rowMotion-${e.id}"),
          on: !m.off, onTap: () => controller.switchMotion(e.id, m.off)),
      sound: own == null
          ? null
          : RowToggle(ValueKey("rowMute-${e.id}"),
              on: !controller.mixNow(own).mute, onTap: () => mute(own)),
      solo: own == null
          ? null
          : RowToggle(ValueKey("rowSolo-${e.id}"),
              on: controller.solo.contains(own.key),
              onTap: () => controller.toggleSolo(own.key)),
      // At L a band for each layer, by its name, its bar striped where it
      // is pinned; at S and M one band, "Motion" or how many layers.
      bands: _isFolded(e) || _shared(e)
          ? [
              RowBand(2, _rowHeight(e) - 4,
                  layers > 1 ? "$layers layers" : "Motion", motionColour),
            ]
          : [
              // A band for each lane: a layer's name on its first, its
              // further stacks unnamed under it.
              for (var (i, t) in _tracks(e).indexed)
                RowBand(
                    2 + i * _lane,
                    _lane,
                    t.stack == 0 ? motionLayerName(m, t.layer) : "",
                    motionColour,
                    weight: m.weight(t.layer),
                    pinned: m.isPinned(t.layer)),
            ],
    );
  }

  /// _linkMenu is a clip's right-click menu: linked with a sound of its
  /// element's own that is picked, the two move together (Ken, 2026-11-10);
  /// or unlinked.
  Future<void> _linkMenu(
      BuildContext context, Offset local, Offset at, double width) async {
    var hit = _hit(local, width);
    var p = hit?.placement;
    if (hit == null || p == null) return;
    var e = hit.element;
    var own = elementSoundKey(e.id);
    var picked = controller.timedLanes
        .where((l) =>
            l.channelKey == own &&
            controller.clipSelection.contains(l.element.id))
        .firstOrNull;
    var items = <PopupMenuEntry<String>>[
      if (picked != null && picked.element.id != p.link)
        const PopupMenuItem(
            key: ValueKey("placementLink"),
            value: "link",
            height: 32,
            child: Text("Link with the picked sound",
                style: TextStyle(fontSize: 12.5))),
      if (p.link.isNotEmpty)
        const PopupMenuItem(
            key: ValueKey("placementUnlink"),
            value: "unlink",
            height: 32,
            child: Text("Unlink from its sound",
                style: TextStyle(fontSize: 12.5))),
    ];
    if (items.isEmpty) {
      items.add(const PopupMenuItem(
          enabled: false,
          height: 32,
          child: Text("Pick one of its sounds too, to link the two",
              style: TextStyle(fontSize: 12.5))));
    }
    var choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: items,
    );
    if (choice == "link") {
      controller.linkPlacement(e.id, p.id, picked!.element.id);
    } else if (choice == "unlink") {
      controller.linkPlacement(e.id, p.id, "");
    }
  }

  /// _colourMenu is a row's right-click menu: its colours.
  Future<void> _colourMenu(BuildContext context, String id, Offset at) async {
    var choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: rowColourMenu(controller.rowColour(id)),
    );
    var (picked, colour) = rowColourPicked(choice);
    if (picked) controller.setRowColour(id, colour);
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
          // Pan, not just across: the box is dragged up and down too.
          onPanDown: (d) => _down(d.localPosition, d.globalPosition, width),
          onSecondaryTapUp: (d) =>
              _linkMenu(context, d.localPosition, d.globalPosition, width),
          onPanUpdate: (d) => _drag(d.localPosition, d.globalPosition, width),
          onPanEnd: (_) => _up(),
          onPanCancel: _up,
          child: MouseRegion(
            cursor: controller.timelineTool == TimelineTool.knife
                ? SystemMouseCursors.precise
                : SystemMouseCursors.basic,
            child: KeyedSubtree(
              key: _paint,
              child: CustomPaint(
                key: ValueKey(widget.only == null
                    ? "motionLanesPaint"
                    : "motionLanesPaint-${widget.only}"),
                size: Size(width, height),
                painter: _LanesPainter(
                  colourOf: (e) => controller.rowColour(e.id),
                  alt: widget.alt,
                  rows: rows,
                  folded: {
                    for (var e in rows)
                      if (_isFolded(e)) e.id
                  },
                  shared: {
                    for (var e in rows)
                      if (_shared(e)) e.id
                  },
                  tracksOf: _tracks,
                  lane: _lane,
                  rowHeight: _rowHeight,
                  times: motionTimesOf(controller.document),
                  x: (s) => _x(s, width),
                  picked: {
                    if (controller.pickedPlacement case var p?) p,
                    for (var (_, p) in controller.motionPicks) p,
                  },
                  colors: colors,
                  textScaler: MediaQuery.textScalerOf(context),
                ),
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
      // The launch: pressed, it plays (an empty one stops the row's).
      var launch = Listener(
        key: ValueKey("rowSlot-${element.id}-$i"),
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => c.pressMotionSlot(element.id, i),
        onPointerUp: (_) {
          if (clip != null) c.releaseMotionClip(element.id, clip.id);
        },
        child: clip == null
            ? Icon(Icons.stop, size: 9, color: colors.onSurfaceVariant)
            : SizedBox.expand(
                child: Icon(Icons.play_arrow,
                    size: 10, color: lit ? slotPlayingInk : slotInk)),
      );
      // One design everywhere (slot_face.dart): cut-cornered, teal-edged.
      Widget box;
      if (clip == null) {
        box = Stack(children: [
          Positioned.fill(
              child: SlotFace(side: SlotSide.motion, empty: launch)),
          // Empty: double-clicked, a new clip in it, opened -- as the
          // mixer's slots do.
          Positioned(
            left: 20,
            top: 0,
            right: 0,
            bottom: 0,
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
        ]);
      } else {
        var picked = c.pickedMotion != null && c.pickedMotion == clip.id;
        box = DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
              border: picked ? Border.all(color: colors.onSurface) : null),
          child: SlotFace(
            side: SlotSide.motion,
            colour: c.rowColour(element.id),
            playing: lit,
            seed: clip.id,
            go: launch,
            // Clicked, it has the keyboard: Delete or Backspace empties the
            // slot, not the canvas's selection (Ken: it took the element,
            // and its channel with it).
            label: SlotFocus(
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
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(clip.name.isEmpty ? "Clip" : clip.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
          ),
        );
      }
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

  /// colourOf is each row's colour: its clips are drawn in it.
  final Color Function(CanvasElement) colourOf;

  /// shared are the rows whose lanes share one band: see motionClipRect.
  final Set<String> shared;
  final double lane;

  /// tracksOf are a row's lanes unfolded: see motionTracksOf.
  final List<MotionTrack> Function(CanvasElement) tracksOf;
  final double Function(CanvasElement) rowHeight;
  final MotionTimes times;
  final double Function(double seconds) x;

  /// picked are the placements picked, outlined.
  final Set<String> picked;
  final ColorScheme colors;
  final TextScaler textScaler;
  final bool alt;

  _LanesPainter({
    this.alt = false,
    this.shared = const {},
    required this.colourOf,
    required this.rows,
    required this.folded,
    required this.lane,
    required this.tracksOf,
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
    // Every other row tinted, and a faint line at every second, as the
    // sound lanes have (the approved design's grid).
    if (alt) {
      canvas.drawRect(Offset.zero & size,
          Paint()..color = colors.onSurface.withValues(alpha: 0.025));
    }
    var x0 = x(0), step = x(1) - x0;
    if (step > 8) {
      var grid = Paint()
        ..color = colors.outlineVariant.withValues(alpha: 0.35)
        ..strokeWidth = 1;
      for (var s = math.max(0, (-x0 / step).ceil());; s++) {
        var gx = x0 + s * step;
        if (gx > size.width) break;
        canvas.drawLine(Offset(gx, 0), Offset(gx, size.height), grid);
      }
    }
    var y = 0.0;
    var line = Paint()..color = colors.outlineVariant.withValues(alpha: 0.5);
    for (var e in rows) {
      var h = rowHeight(e);
      var isFolded = folded.contains(e.id);
      var isShared = shared.contains(e.id);
      var tracks = isFolded ? const <MotionTrack>[] : tracksOf(e);
      canvas.drawLine(
          Offset(0, y + h - 0.5), Offset(size.width, y + h - 0.5), line);
      // The lanes' own lines, faint; the sound's lane tinted.
      for (var (i, t)
          in isShared ? const <(int, MotionTrack)>[] : tracks.indexed) {
        var top = y + 2 + i * lane;
        if (t.layer == soundLayer) {
          canvas.drawRect(Rect.fromLTWH(0, top, size.width, lane),
              Paint()..color = const Color(0x143F9F6B));
        } else if (i > 0) {
          canvas.drawLine(Offset(0, top), Offset(size.width, top),
              Paint()..color = colors.outlineVariant.withValues(alpha: 0.2));
        }
      }
      var m = e.base.motion;
      var stacks = clipStacks(m.placed, times, together: isFolded);
      // Shared, a lane under the next: drawn from the first lane up.
      var order = isShared
          ? ([...m.placed]..sort((a, b) {
              var byLayer = a.layer - b.layer;
              return byLayer != 0
                  ? byLayer
                  : (stacks[a.id] ?? 0) - (stacks[b.id] ?? 0);
            }))
          : m.placed;
      for (var p in order) {
        var c = m.clip(p.clip);
        var s = times.span(p.id);
        if (c == null || s == null) continue;
        var rect = motionClipRect(p,
            folded: isFolded,
            shared: isShared,
            tracks: tracks,
            stacks: stacks,
            lane: lane,
            y: y,
            rowHeight: h,
            left: x(s.start),
            right: x(s.end));
        if (rect == null || rect.right < 0 || rect.left > size.width) continue;
        _clip(canvas, rect, c, p, s, colourOf(e));
      }
      // An element reused: where each copy's clips start, as short amber
      // ticks along the top of its row (the approved design), from its first
      // clip -- only with a clip on the timeline for them to start (Ken:
      // without one, three blue lines that meant nothing).
      if (m.instances case var set? when set.count > 1) {
        var from = [
          for (var p in m.placed)
            if (times.span(p.id) case var s?) s.start
        ].fold<double?>(null, (a, b) => a == null ? b : math.min(a, b));
        var starts = [for (var i = 0; i < set.count; i++) set.startOf(i)];
        if (from != null && starts.any((t) => t > 0)) {
          var tick = Paint()
            ..color = colors.primary.withValues(alpha: 0.8)
            ..strokeWidth = 1;
          for (var t in starts) {
            var tx = x(from + t);
            if (tx < 0 || tx > size.width) continue;
            canvas.drawLine(Offset(tx, y), Offset(tx, y + 5), tick);
          }
        }
      }
      y += h;
    }
  }

  void _clip(Canvas canvas, Rect rect, MotionClip c, ClipPlacement p,
      ClipSpan s, Color row) {
    // As its slot is (the approved design): its corners cut, a teal edge,
    // its curve drawn faint in it.
    var colour = Color.lerp(row, const Color(0xFF0E2A24), 0.22)!;
    var shape = cutCornersPath(rect, 4);
    canvas.drawPath(shape, Paint()..color = colour);
    canvas.save();
    canvas.clipPath(shape);
    paintSlotArt(canvas, rect, SlotSide.motion, p.id, opacity: 0.5);
    canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, 3, rect.height),
        Paint()..color = motionColour);
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
              fontSize: 10.5, color: slotInk, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    var left = rect.left + (p.startPin != null ? 12 : 6);
    tp.paint(canvas, Offset(left, rect.center.dy - tp.height / 2));
    canvas.restore();
    // Linked to a sound: its mark, top right.
    if (p.link.isNotEmpty && rect.width >= 30) {
      paintLinkMark(canvas, Offset(rect.right - 14, rect.top + 2), slotInk);
    }
    // Picked: outlined, over its shape.
    if (picked.contains(p.id)) {
      canvas.drawPath(
          cutCornersPath(rect.inflate(1.5), 5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = colors.onSurface);
    }
    // A dot at each pinned end.
    var dot = Paint()..color = slotInk;
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

/// sharedStep is how much lower each layer's clips are drawn than the one
/// before's, on a shared band of [lanes] layers in a row [rowHeight] tall.
double sharedStep(int lanes, double rowHeight) =>
    math.max(2.0, (rowHeight - 4 - 10) / math.max(1, lanes));
