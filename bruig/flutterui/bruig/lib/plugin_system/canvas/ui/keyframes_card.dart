import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart'
    show DeviceFrame, DeviceSkin;
import 'package:bruig/plugin_system/canvas/ui/row_header.dart'
    show motionColour;
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// keyframes_card.dart is the Chain's Keyframes card (Ken, 2026-11-09:
// "I'd like keyframing done in the chain"; the approved keyframes
// prototype): what the timeline's keyframe row did, as the first card of
// the Motion view. A mark for each keyframe of what is picked -- an
// element's own keyframes, a team player's, or a path's points -- over a
// ruler of the scene: picked (Shift adds, a box picks several), dragged to
// retime keeping their spacing, a band between two moving the pair; Delete,
// copy and paste at the playhead, the arrows to nudge. Under it, shut until
// asked, a lane for each thing that changes. Its values and easing are the
// Curves'.

/// keyframeLanesOf are the things [track]'s keyframes change, each with a
/// name, a reading of a keyframe, and whether it is at rest there: across,
/// down, size, angle, opacity, then any channels some keyframes pin.
List<(String, String, double? Function(Keyframe))> keyframeLanesOf(
    ElementTrack track) {
  var lanes = <(String, String, double? Function(Keyframe))>[
    ("dx", "Across", (k) => k.dx),
    ("dy", "Down", (k) => k.dy),
    ("scale", "Size", (k) => k.scale),
    ("rotate", "Angle", (k) => k.rotate),
    ("opacity", "Opacity", (k) => k.opacity),
  ];
  var channels = <String>{
    for (var k in track.keys) ...k.values.keys,
  };
  for (var c in channels) {
    lanes.add((c, _channelName(c), (k) => k.values[c]));
  }
  return [
    for (var l in lanes)
      if (_changes(track, l.$3)) l
  ];
}

String _channelName(String c) =>
    c.isEmpty ? c : c[0].toUpperCase() + c.substring(1);

/// _changes is whether [read] differs between any two keyframes in a row.
bool _changes(ElementTrack track, double? Function(Keyframe) read) {
  var k = track.keys;
  for (var i = 1; i < k.length; i++) {
    if (read(k[i]) != read(k[i - 1])) return true;
  }
  return false;
}

/// KeyframesCard is the Keyframes card, [height] tall.
class KeyframesCard extends StatefulWidget {
  final CanvasController controller;
  final double height;
  final bool folded;
  final VoidCallback onFold;

  /// onCurves opens the Curves, on the picked keyframe where there is one.
  final ValueChanged<int?>? onCurves;
  const KeyframesCard(
      {required this.controller,
      required this.height,
      required this.folded,
      required this.onFold,
      this.onCurves,
      super.key});

  @override
  State<KeyframesCard> createState() => _KeyframesCardState();
}

enum _DragKind { scrub, move, box, loop }

class _KeyframesCardState extends State<KeyframesCard> {
  CanvasController get c => widget.controller;
  final Set<int> _sel = {};
  bool _lanes = false;
  final FocusNode _focus = FocusNode(debugLabel: "keyframesCard");
  String? _said;

  // A drag: what kind, from which frame, how far.
  _DragKind? _drag;
  int _from = 0, _by = 0;
  int? _pressed;
  bool _moved = false;

  /// _loopEnd is the end of the loop's bar being dragged: its stop (true)
  /// or its start.
  bool _loopEnd = false;

  static const double _labelW = 70, _rulerH = 16, _allH = 28, _laneH = 20;

  /// _loopH is the loop's row, under the keyframes, where the element loops.
  static const double _loopH = 14;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _say(String? message) => setState(() => _said = message);

  int get _last => math.max(1, c.document.frames - 1);

  @override
  Widget build(BuildContext context) {
    var t = c.keyframeTarget;
    var look = MixerLook.of(context);
    var studio = look.studio;
    if (t == null) return const SizedBox.shrink();
    _sel.removeWhere((f) => t.track.keyAt(f) == null);
    var n = t.track.keys.length;
    Widget bar(String label, Key key, VoidCallback onTap, {bool lit = false}) =>
        InkWell(
          key: key,
          borderRadius: BorderRadius.circular(5),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            child: Text(label,
                style: TextStyle(
                    fontSize: 11, color: lit ? studio.on : studio.muted)),
          ),
        );
    return Focus(
      focusNode: _focus,
      onKeyEvent: (_, e) => _key(e, t),
      child: DeviceFrame(
        id: "keyframes",
        title: "Keyframes",
        help: "Each mark is a keyframe of what is picked: an element's own, a "
            "team player's, or a path's points. Drag one to retime it, a box "
            "to pick several, and the band between two to move the pair. "
            "Delete, copy and paste at the playhead, and the arrows nudge. "
            "The diamond adds a keyframe at the playhead or takes away the "
            "one there; its values and easing are in Curves.",
        skin: DeviceSkin.studio(studio),
        icon: Icons.diamond_outlined,
        accent: motionColour,
        folded: widget.folded,
        onFold: widget.onFold,
        width: 640,
        height: widget.height,
        summary: t.points
            ? "$n point${n == 1 ? "" : "s"}"
            : "$n keyframe${n == 1 ? "" : "s"}",
        foldedBody: const SizedBox(),
        body: const SizedBox.shrink(),
        besideDisplay: 420,
        besideSettings: 220,
        barExtras: [
          bar("‹", const ValueKey("keyframesPrev"), () => _step(t, -1)),
          bar("◆", const ValueKey("keyframesHere"), () {
            c.beginInteraction();
            c.toggleTargetKeyframe();
            c.endInteraction();
          }, lit: t.track.keyAt(c.frame) != null),
          bar("›", const ValueKey("keyframesNext"), () => _step(t, 1)),
          if (!t.points)
            bar("Properties", const ValueKey("keyframesLanes"),
                () => setState(() => _lanes = !_lanes),
                lit: _lanes),
          if (!t.points && widget.onCurves != null)
            bar("Curves", const ValueKey("keyframesCurves"),
                () => widget.onCurves!(_sel.isEmpty ? null : _sel.first)),
        ],
        display: _display(t, studio),
        controls: (tier) => [_inspector(t, studio)],
      ),
    );
  }

  /// _display is the players (on a team), the lanes, and what was said.
  Widget _display(KeyframeTarget t, StudioColors studio) {
    var team = c.focusedTeam;
    var lanes = !_lanes || t.points
        ? const <(String, String, double? Function(Keyframe))>[]
        : keyframeLanesOf(t.track);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (team != null)
        SizedBox(
          height: 24,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (var (i, p) in team.players.indexed)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: ChoiceChip(
                  key: ValueKey("keyframesPlayer-$i"),
                  label: Text(p.name, style: const TextStyle(fontSize: 10.5)),
                  selected: c.focusedPlayer == i,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() {
                    _sel.clear();
                    c.focusedPlayer = c.focusedPlayer == i ? null : i;
                  }),
                ),
              ),
          ]),
        ),
      Expanded(
        child: LayoutBuilder(builder: (context, box) {
          var w = box.maxWidth;
          return GestureDetector(
            key: const ValueKey("keyframesLanes-paint"),
            behavior: HitTestBehavior.opaque,
            onPanDown: (d) => _down(d.localPosition, w, t, lanes.length),
            onPanUpdate: (d) => _move(d.localPosition, w, t),
            onPanEnd: (_) => _up(t),
            onPanCancel: () => _up(t),
            child: ClipRect(
              child: CustomPaint(
                size: Size.infinite,
                painter: _LanesPainter(
                  track: t.track,
                  points: t.points,
                  lanes: lanes,
                  frames: _last,
                  playhead: c.frame,
                  rate: c.document.frameRate,
                  picked: {..._sel},
                  loop: c.keyframeLoop,
                  by: _drag == _DragKind.move ? _by : 0,
                  box: _drag == _DragKind.box ? (_from, _from + _by) : null,
                  studio: studio,
                ),
              ),
            ),
          );
        }),
      ),
      if (_said != null)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(_said!,
              key: const ValueKey("keyframesSaid"),
              maxLines: 2,
              style: TextStyle(fontSize: 10.5, color: studio.on)),
        ),
    ]);
  }

  // ---- where things are

  double _x(int f, double w) => _labelW + f / _last * (w - _labelW - 6);
  int _frameAt(double x, double w) =>
      ((x - _labelW) / math.max(1, w - _labelW - 6) * _last)
          .round()
          .clamp(0, _last)
          .toInt();

  /// _bandAt is the pair of keyframes whose band is under [x] in the all
  /// lane: the band's right end's index.
  int? _bandAt(KeyframeTarget t, double x, double w) {
    var k = t.track.keys;
    for (var i = 1; i < k.length; i++) {
      if (x > _x(k[i - 1].frame, w) && x < _x(k[i].frame, w)) return i;
    }
    return null;
  }

  void _down(Offset at, double w, KeyframeTarget t, int laneCount) {
    _focus.requestFocus();
    _said = null;
    var f = _frameAt(at.dx, w);
    if (at.dy < _rulerH) {
      _drag = _DragKind.scrub;
      c.frame = f;
      setState(() {});
      return;
    }
    _from = f;
    _by = 0;
    _moved = false;
    _pressed = null;
    // A mark, near enough.
    int? mark;
    var best = 8.0;
    for (var k in t.track.keys) {
      var d = (_x(k.frame, w) - at.dx).abs();
      if (d < best) {
        best = d;
        mark = k.frame;
      }
    }
    // The loop's row: an end of its bar, dragged, moves it.
    var loop = c.keyframeLoop;
    if (loop != null &&
        at.dy >= _rulerH + _allH &&
        at.dy < _rulerH + _allH + _loopH) {
      var (start, stop, _, _) = loop;
      var toStop = (at.dx - _x(stop + 1, w)).abs();
      var toStart = (at.dx - _x(start, w)).abs();
      if (math.min(toStop, toStart) <= 7) {
        _loopEnd = toStop <= toStart;
        _drag = _DragKind.loop;
        c.beginInteraction();
        setState(() {});
        return;
      }
    }
    var shift = HardwareKeyboard.instance.isShiftPressed;
    if (mark != null && at.dy < _rulerH + _allH) {
      if (shift) {
        _sel.contains(mark) ? _sel.remove(mark) : _sel.add(mark);
      } else if (!_sel.contains(mark)) {
        _sel
          ..clear()
          ..add(mark);
      }
      _pressed = mark;
      _drag = _DragKind.move;
    } else if (_bandAt(t, at.dx, w) case var i?) {
      var k = t.track.keys;
      _sel
        ..clear()
        ..addAll([k[i - 1].frame, k[i].frame]);
      _drag = _DragKind.move;
    } else {
      if (!shift) _sel.clear();
      _drag = _DragKind.box;
    }
    setState(() {});
  }

  void _move(Offset at, double w, KeyframeTarget t) {
    var f = _frameAt(at.dx, w);
    switch (_drag) {
      case _DragKind.scrub:
        c.frame = f;
      case _DragKind.box:
        _by = f - _from;
        var lo = math.min(_from, f), hi = math.max(_from, f);
        _sel
          ..clear()
          ..addAll([
            for (var k in t.track.keys)
              if (k.frame >= lo && k.frame <= hi) k.frame
          ]);
      case _DragKind.move:
        _by = f - _from;
        _moved = _moved || _by != 0;
      case _DragKind.loop:
        c.moveKeyframeLoopEnd(_loopEnd, f);
      case null:
        break;
    }
    setState(() {});
  }

  void _up(KeyframeTarget t) {
    var drag = _drag;
    _drag = null;
    if (drag == _DragKind.loop) c.endInteraction();
    if (drag == _DragKind.move) {
      if (!_moved) {
        // A click on a mark: the playhead to it, as the timeline's row did.
        if (_pressed case var p?
            when !HardwareKeyboard.instance.isShiftPressed) {
          c.frame = p;
        }
      } else if (_by != 0) {
        c.beginInteraction();
        var ok = c.moveTargetKeyframes(_sel.toList(), _by);
        c.endInteraction();
        if (ok) {
          var moved = {for (var f in _sel) f + _by};
          _sel
            ..clear()
            ..addAll(moved);
        } else {
          _said = "Not moved: it would land on another keyframe, or off the "
              "scene.";
        }
      }
    }
    _by = 0;
    setState(() {});
  }

  void _step(KeyframeTarget t, int dir) {
    var fs = [for (var k in t.track.keys) k.frame];
    var to = dir < 0
        ? fs.reversed.where((f) => f < c.frame).firstOrNull
        : fs.where((f) => f > c.frame).firstOrNull;
    if (to != null) c.frame = to;
  }

  KeyEventResult _key(KeyEvent e, KeyframeTarget t) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    var meta = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    var key = e.logicalKey;
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      if (_sel.isEmpty) return KeyEventResult.ignored;
      _remove();
      return KeyEventResult.handled;
    }
    if (meta && key == LogicalKeyboardKey.keyC) {
      _copy();
      return KeyEventResult.handled;
    }
    if (meta && key == LogicalKeyboardKey.keyV) {
      _paste();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      if (_sel.isEmpty) return KeyEventResult.ignored;
      var step =
          HardwareKeyboard.instance.isShiftPressed ? c.document.frameRate : 1;
      var by = key == LogicalKeyboardKey.arrowLeft ? -step : step;
      c.beginInteraction();
      var ok = c.moveTargetKeyframes(_sel.toList(), by);
      c.endInteraction();
      if (ok) {
        var moved = {for (var f in _sel) f + by};
        _sel
          ..clear()
          ..addAll(moved);
        _say(null);
      } else {
        _say("Not moved: it would land on another keyframe, or off the "
            "scene.");
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _remove() {
    var n = _sel.length;
    c.beginInteraction();
    c.removeTargetKeyframes(_sel.toList());
    c.endInteraction();
    _sel.clear();
    _say(n == 1 ? "Keyframe deleted" : "$n keyframes deleted");
  }

  void _copy() {
    var n = c.copyTargetKeys(_sel);
    if (n == 0) return;
    _say(n == 1
        ? "Keyframe copied. Move the playhead and paste it."
        : "$n keyframes copied. Move the playhead and paste them.");
  }

  void _paste() {
    c.beginInteraction();
    var (landed, why) = c.pasteTargetKeys();
    c.endInteraction();
    if (why != null) {
      _say(why);
      return;
    }
    if (landed.isEmpty) return;
    _sel
      ..clear()
      ..addAll(landed);
    _say(landed.length == 1
        ? "Keyframe pasted"
        : "${landed.length} keyframes pasted");
  }

  void _spread(KeyframeTarget t) {
    var picked = _sel.toList()..sort();
    if (picked.length < 3) return;
    var lo = picked.first, hi = picked.last;
    var to = [
      for (var i = 0; i < picked.length; i++)
        (lo + (hi - lo) * i / (picked.length - 1)).round()
    ];
    var rest = {
      for (var k in t.track.keys)
        if (!_sel.contains(k.frame)) k.frame
    };
    if (to.any(rest.contains) || to.toSet().length != to.length) {
      _say("Spread evenly they would land on another keyframe.");
      return;
    }
    c.beginInteraction();
    if (t.points) {
      // A point at a time, each by its own amount, in an order none passes.
      for (var i = 0; i < picked.length; i++) {
        c.moveTargetKeyframes([picked[i]], to[i] - picked[i]);
      }
    } else {
      var next = t.track;
      var keys = [for (var f in picked) t.track.keyAt(f)!];
      for (var k in keys) {
        next = next.withoutFrame(k.frame);
      }
      for (var (i, k) in keys.indexed) {
        next = next.withKey(k.copyWith(frame: to[i]));
      }
      c.writeTargetTrack(next);
    }
    c.endInteraction();
    _sel
      ..clear()
      ..addAll(to);
    _say("Spread evenly");
  }

  /// _inspector is the picked keyframes': one's frame, what it holds and how
  /// it eases; several's span; and what can be done with them.
  Widget _inspector(KeyframeTarget t, StudioColors studio) {
    var cap = TextStyle(fontSize: 9.5, letterSpacing: 0.6, color: studio.muted);
    var mono = TextStyle(
        fontSize: 12,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: studio.text);
    Widget act(String label, Key key, VoidCallback onTap,
            {bool danger = false}) =>
        OutlinedButton(
          key: key,
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 26),
              foregroundColor: danger ? studio.arm : studio.text,
              side: BorderSide(color: studio.edge)),
          child: Text(label, style: const TextStyle(fontSize: 11)),
        );
    var picked = [
      for (var k in t.track.keys)
        if (_sel.contains(k.frame)) k
    ];
    var rate = math.max(1, c.document.frameRate);
    if (picked.isEmpty) {
      return Text(
          "Pick a keyframe to see its frame and what it holds. The playhead "
          "is at frame ${c.frame}; the diamond adds one there.",
          key: const ValueKey("keyframesHint"),
          style: TextStyle(fontSize: 11.5, color: studio.muted));
    }
    var actions = Wrap(spacing: 6, runSpacing: 6, children: [
      if (picked.length == 1)
        act("Go to it", const ValueKey("keyframesGo"),
            () => c.frame = picked.first.frame),
      if (picked.length >= 3)
        act("Spread evenly", const ValueKey("keyframesSpread"),
            () => _spread(t)),
      if (!t.points && picked.length == 1 && widget.onCurves != null)
        act("Curves", const ValueKey("keyframesOpenCurves"),
            () => widget.onCurves!(picked.first.frame)),
      if (!t.points) act("Copy", const ValueKey("keyframesCopy"), _copy),
      act("Delete", const ValueKey("keyframesDelete"), _remove, danger: true),
    ]);
    if (picked.length > 1) {
      var lo = picked.first.frame, hi = picked.last.frame;
      return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("PICKED", style: cap),
            Text("${picked.length} keyframes · frames $lo – $hi",
                key: const ValueKey("keyframesPicked"), style: mono),
            Text("${((hi - lo) / rate).toStringAsFixed(2)} s apart, end to end",
                style: TextStyle(fontSize: 11, color: studio.muted)),
            const SizedBox(height: 8),
            actions,
          ]);
    }
    var k = picked.first;
    var holds = t.points
        ? ["a point"]
        : [
            if (k.dx != 0) "Across",
            if (k.dy != 0) "Down",
            if (k.scale != 1) "Size",
            if (k.rotate != 0) "Angle",
            if (k.opacity != 1) "Opacity",
            for (var ch in k.values.keys) _channelName(ch),
          ];
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("FRAME", style: cap),
          Text("${k.frame} · ${(k.frame / rate).toStringAsFixed(2)} s",
              key: const ValueKey("keyframesFrame"), style: mono),
          const SizedBox(height: 6),
          Text(t.points ? "IS" : "HOLDS", style: cap),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (var h in holds.isEmpty ? ["its resting pose"] : holds)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                    color: motionColour.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(9)),
                child: Text(h,
                    style: const TextStyle(
                        fontSize: 10.5, color: Color(0xFF8FE3C6))),
              ),
          ]),
          if (!t.points) ...[
            const SizedBox(height: 6),
            Text("EASES", style: cap),
            Text("${k.easing.label} · set in Curves",
                key: const ValueKey("keyframesEase"),
                style: TextStyle(fontSize: 11.5, color: studio.text)),
          ],
          const SizedBox(height: 8),
          actions,
        ]);
  }
}

/// _LanesPainter draws the ruler, the lane of every keyframe with a band
/// wherever anything changes between two, and -- asked for -- a lane for
/// each thing that changes, with a band where it does.
class _LanesPainter extends CustomPainter {
  final ElementTrack track;
  final bool points;
  final List<(String, String, double? Function(Keyframe))> lanes;
  final int frames;
  final int playhead;
  final int rate;
  final Set<int> picked;
  final int by;
  final (int, int)? box;

  /// loop is the element's loop, where it has one: from, to, cycle, gap.
  final (int, int, int, int)? loop;
  final StudioColors studio;
  _LanesPainter(
      {required this.track,
      required this.points,
      required this.lanes,
      required this.frames,
      required this.playhead,
      required this.rate,
      required this.picked,
      required this.by,
      required this.box,
      this.loop,
      required this.studio});

  static const double labelW = _KeyframesCardState._labelW;
  static const double rulerH = _KeyframesCardState._rulerH;
  static const double allH = _KeyframesCardState._allH;
  static const double laneH = _KeyframesCardState._laneH;
  static const double loopH = _KeyframesCardState._loopH;

  double _x(num f, double w) => labelW + f / frames * (w - labelW - 6);

  void _label(Canvas canvas, String text, Offset at, Color colour,
      {double size = 10}) {
    var tp = TextPainter(
        text: TextSpan(
            text: text, style: TextStyle(fontSize: size, color: colour)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: "…")
      ..layout(maxWidth: labelW - 8);
    tp.paint(canvas, at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    var w = size.width;
    var line = Paint()..color = studio.edge.withValues(alpha: 0.6);
    canvas.drawRect(Offset.zero & size, Paint()..color = studio.inset);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, w, rulerH), Paint()..color = studio.strip);
    // Every second: a line down the lanes, its number on the ruler.
    var seconds = frames / math.max(1, rate);
    for (var s = 0; s <= seconds; s++) {
      var x = _x(s * rate, w);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      _label(canvas, "${s}s", Offset(x + 2, 2), studio.muted, size: 8.5);
    }
    var rows = [
      (points ? "Points" : "Keyframes", rulerH, allH, null),
      for (var (i, l) in lanes.indexed)
        (
          l.$2,
          rulerH + allH + (loop == null ? 0 : loopH) + i * laneH,
          laneH,
          l.$3
        ),
    ];
    var keys = track.keys;
    // The stretches something changes over, as bandsIn has it: not one that
    // reads the same at both ends, nor one leaving a held keyframe.
    var travels = {for (var b in bandsIn(track)) b.from};
    var band = Paint()..color = motionColour.withValues(alpha: 0.45);
    var bandPicked = Paint()..color = studio.on.withValues(alpha: 0.5);
    for (var (name, top, h, read) in rows) {
      canvas.drawLine(Offset(0, top + h), Offset(w, top + h), line);
      _label(canvas, name, Offset(6, top + h / 2 - 6),
          read == null ? studio.text : studio.muted);
      var mid = top + h / 2;
      for (var i = 1; i < keys.length; i++) {
        var a = keys[i - 1], b = keys[i];
        var changes = points ||
            (read == null
                ? travels.contains(a.frame)
                : a.easing != KeyframeEasing.hold && read(a) != read(b));
        if (!changes) continue;
        var both = picked.contains(a.frame) && picked.contains(b.frame);
        var thick = read == null ? 2.0 : 4.0;
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTRB(
                    _x(a.frame, w), mid - thick, _x(b.frame, w), mid + thick),
                const Radius.circular(2)),
            both ? bandPicked : band);
      }
      // The marks: on the keyframes' lane, the full diamond; on a thing's
      // lane, a small one where a keyframe holds it.
      for (var k in keys) {
        var moving = read == null && picked.contains(k.frame) && by != 0;
        var at = moving ? k.frame + by : k.frame;
        var x = _x(at.clamp(0, frames), w);
        if (read != null) {
          _diamond(canvas, Offset(x, mid), 3.5,
              const Color(0xFF8FE3C6).withValues(alpha: 0.8));
          continue;
        }
        var clash = moving &&
            (at < 0 ||
                at > frames ||
                keys.any((o) => !picked.contains(o.frame) && o.frame == at));
        var colour = clash
            ? studio.arm
            : picked.contains(k.frame)
                ? studio.on
                : motionColour;
        if (points) {
          canvas.drawCircle(Offset(x, mid), 6, Paint()..color = colour);
        } else {
          _diamond(canvas, Offset(x, mid), 6.5, colour);
        }
      }
    }
    if (loop case (var start, var end, var cycle, var gap)) {
      _paintLoop(canvas, w, start, end, cycle, gap);
    }
    if (box case (var a, var b)) {
      var l = _x(math.min(a, b), w), r = _x(math.max(a, b), w);
      var rect = Rect.fromLTRB(l, rulerH, r, size.height);
      canvas.drawRect(rect, Paint()..color = studio.on.withValues(alpha: 0.12));
      canvas.drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = studio.on.withValues(alpha: 0.6));
    }
    var px = _x(playhead.clamp(0, frames), w);
    canvas.drawLine(
        Offset(px, 0),
        Offset(px, size.height),
        Paint()
          ..color = studio.on
          ..strokeWidth = 2);
  }

  /// _paintLoop is the loop's row: a bar from where it starts to where it
  /// stops, ticked where each go round starts, a handle at each end.
  void _paintLoop(
      Canvas canvas, double w, int start, int end, int cycle, int gap) {
    var top = rulerH + allH;
    var y = top + loopH / 2;
    canvas.drawLine(Offset(0, top + loopH), Offset(w, top + loopH),
        Paint()..color = studio.edge.withValues(alpha: 0.6));
    _label(canvas, "Loop", Offset(6, y - 6), studio.muted);
    var from = _x(start, w), to = _x(end + 1, w);
    var ink = studio.on;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTRB(from, y - 2, to, y + 2), const Radius.circular(2)),
        Paint()..color = ink.withValues(alpha: 0.35));
    var tick = Paint()
      ..color = ink.withValues(alpha: 0.8)
      ..strokeWidth = 1;
    var period = math.max(1, cycle + gap);
    // No closer than four pixels apart, on a long loop.
    var every = math.max(
        1, (4 / math.max(0.0001, _x(1, w) - _x(0, w)) / period).ceil());
    for (var f = start, i = 0; f <= end; f += period, i++) {
      if (i % every != 0) continue;
      var x = _x(f, w);
      canvas.drawLine(Offset(x, y - 3), Offset(x, y + 3), tick);
    }
    for (var x in [from, to]) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset(x, y), width: 4, height: 9),
              const Radius.circular(1.5)),
          Paint()..color = ink);
    }
  }

  void _diamond(Canvas canvas, Offset at, double r, Color colour) {
    var path = Path()
      ..moveTo(at.dx, at.dy - r)
      ..lineTo(at.dx + r, at.dy)
      ..lineTo(at.dx, at.dy + r)
      ..lineTo(at.dx - r, at.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = colour);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0xFF0E2A24));
  }

  @override
  bool shouldRepaint(_LanesPainter old) => true;
}
