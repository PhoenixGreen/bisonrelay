import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart'
    show elementPhaseSpans;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// keys_strip.dart is the Chain's Keys strip (Ken, 2026-11-12, the approved
// chain prototype): opened from the Chain's header and laid over its cards,
// the whole width. A ruler of the scene with what the voice says, the
// element's arrival, loop and leaving, its own keyframes, and a row for each
// setting of its chain that has keys -- each key coloured by where it plays.
// Pick a key to change it in the inspector on the right; drag it to retime
// it; double-click a row to add one; Delete takes it away. Click or drag the
// ruler to move the playhead. It took the Keyframes card's place.

/// phaseColour is what a key, a clip or a card's button is drawn in for
/// where it plays.
Color phaseColour(MotionPhase ph) => switch (ph) {
      MotionPhase.arrive => const Color(0xFF2ED6A1),
      MotionPhase.leave => const Color(0xFFE36F8E),
      MotionPhase.loop => const Color(0xFF8FA8FF),
      MotionPhase.free => const Color(0xFFF2C14E),
    };

/// trackKeyColour is the element's own keyframes' marks.
const trackKeyColour = Color(0xFF9FB3C8);

/// KeysLane is one row of the strip: a setting of a device with keys.
class KeysLane {
  final MotionDevice device;
  final String param;
  const KeysLane(this.device, this.param);

  String get label => device.kind.label;
  String get what => device.kind.param(param).label;
}

/// keysLanesOf are [devices]' keyed settings, Design's first, as far as
/// [filter] shows them (null for all).
List<KeysLane> keysLanesOf(List<MotionDevice> devices, MotionPhase? filter) {
  bool shows(MotionDevice d, String p) =>
      filter == null ? d.keyed(p) : d.keyedIn(p, filter);
  var ordered = [
    for (var d in devices)
      if (d.kind == MotionDeviceKind.design) d,
    for (var d in devices)
      if (d.kind != MotionDeviceKind.design) d,
  ];
  return [
    for (var d in ordered)
      for (var p in d.kind.params)
        if (shows(d, p.id)) KeysLane(d, p.id),
  ];
}

/// _Pick is a key picked on a lane: its device, setting, phase and place in
/// that phase's keys.
typedef _Pick = ({String device, String param, MotionPhase ph, int i});

class KeysStrip extends StatefulWidget {
  final CanvasController controller;
  final CanvasElement element;

  /// height is the most the strip may take; it is shorter with few rows,
  /// and scrolls with more.
  final double height;

  const KeysStrip(
      {required this.controller,
      required this.element,
      required this.height,
      super.key});

  static const labelWidth = 136.0;
  static const inspectorWidth = 300.0;
  static const rulerHeight = 36.0;
  static const rowHeight = 26.0;

  /// rowsFor are how many rows [e]'s strip has under its ruler: its
  /// clips, its own keyframes where it has a track to show, and a row a
  /// keyed setting.
  static int rowsFor(CanvasController c, CanvasElement e) {
    var f = c.chainPhase;
    var track =
        (f == null || f == MotionPhase.free) && c.keyframeTarget != null;
    return 1 + (track ? 1 : 0) + keysLanesOf(c.motionDevicesOf(e.id), f).length;
  }

  /// heightFor is the strip's height with [rows] rows under its ruler,
  /// within [most].
  static double heightFor(int rows, double most) =>
      math.min(most, math.max(leastHeight, rulerHeight + rows * rowHeight + 1));

  /// leastHeight is as short as it goes: the inspector's two lines.
  static const leastHeight = 100.0;

  /// startHeight is as tall as it opens, until it is dragged (Ken,
  /// 2026-11-12: "should start minimal and also be able to be resized"):
  /// the ruler and three rows.
  static const startHeight = rulerHeight + 3 * rowHeight + 10;

  @override
  State<KeysStrip> createState() => _KeysStripState();
}

class _KeysStripState extends State<KeysStrip> {
  CanvasController get c => widget.controller;
  CanvasElement get e => widget.element;

  final FocusNode _focus = FocusNode(debugLabel: "keysStrip");

  _Pick? _pick;

  /// _frames are the element's own keyframes picked, by frame.
  final Set<int> _frames = {};

  String? _said;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  double get _rate => math.max(1, c.document.frameRate).toDouble();
  double get _scene => math.max(1, c.document.frames) / _rate;

  List<MotionDevice> get _devices => c.motionDevicesOf(e.id);

  List<KeysLane> get _lanes => keysLanesOf(_devices, c.chainPhase);

  KeyframeTarget? get _track {
    var f = c.chainPhase;
    if (f != null && f != MotionPhase.free) return null;
    return c.keyframeTarget;
  }

  MotionDevice? _deviceOf(String id) =>
      _devices.where((d) => d.id == id).firstOrNull;

  DeviceKey? get _picked {
    var p = _pick;
    if (p == null) return null;
    var ks = _deviceOf(p.device)?.keysIn(p.ph)[p.param];
    return ks != null && p.i >= 0 && p.i < ks.length ? ks[p.i] : null;
  }

  void _say(String s) => setState(() => _said = s);

  // ---- picking, dragging and adding ----

  _Drag? _drag;
  (DateTime, int, double)? _lastDown;

  /// _rowAt is the row under [y] in the lanes: -2 the ruler, -1 the clips,
  /// 0 the keyframes where shown, then the lanes; null below them all.
  int? _rowAt(double y) {
    if (y < KeysStrip.rulerHeight) return -2;
    var r = ((y - KeysStrip.rulerHeight) / KeysStrip.rowHeight).floor();
    return r - 1;
  }

  void _down(PointerDownEvent ev, _Geometry g) {
    _focus.requestFocus();
    var x = ev.localPosition.dx, y = ev.localPosition.dy;
    var row = _rowAt(y);
    var now = DateTime.now();
    var twice = _lastDown != null &&
        now.difference(_lastDown!.$1).inMilliseconds < 350 &&
        _lastDown!.$2 == row &&
        (x - _lastDown!.$3).abs() < 6;
    _lastDown = (now, row ?? -3, x);
    var shift = HardwareKeyboard.instance.isShiftPressed;
    var hasTrack = _track != null;
    // The loop's ends, on the clips row: dragged, where it starts and stops.
    if (row == -1) {
      if (_loopBar case (var a, var b)) {
        var start = (g.xOf(a) - x).abs(), stop = (g.xOf(b) - x).abs();
        if (math.min(start, stop) <= 6) {
          _drag = _Drag.loop(stop < start);
          return;
        }
      }
    }
    var lanes = _lanes;
    // The element's own keyframes.
    if (hasTrack && row == 0) {
      var t = _track!;
      var hit =
          _nearest([for (var k in t.track.keys) k.frame / _rate], x, g)?.$1;
      if (hit != null) {
        var f = t.track.keys[hit].frame;
        setState(() {
          _pick = null;
          if (shift) {
            _frames.contains(f) ? _frames.remove(f) : _frames.add(f);
          } else if (!_frames.contains(f)) {
            _frames
              ..clear()
              ..add(f);
          }
          _said = null;
        });
        c.frame = f;
        _drag = _Drag.track(x, [..._frames]);
        return;
      }
      if (twice) {
        c.frame = g.frameAt(x, c.document.frames);
        c.beginInteraction();
        c.toggleTargetKeyframe();
        c.endInteraction();
        setState(() => _frames
          ..clear()
          ..add(c.frame));
        return;
      }
    }
    var laneRow = (row ?? -3) - (hasTrack ? 1 : 0);
    if (row != null && row >= 0 && laneRow >= 0 && laneRow < lanes.length) {
      var lane = lanes[laneRow];
      var spans = elementPhaseSpans(e, c.document);
      var marks = _marksOf(lane, spans);
      var hit = _nearest([for (var m in marks) m.t], x, g)?.$1;
      if (hit != null) {
        var m = marks[hit];
        setState(() {
          _pick = (device: lane.device.id, param: lane.param, ph: m.ph, i: m.i);
          _frames.clear();
          _said = null;
        });
        c.frame = (m.t * _rate).round().clamp(0, c.document.frames - 1);
        _drag = _Drag.key(x, m.t);
        return;
      }
      if (twice) {
        c.frame = g.frameAt(x, c.document.frames);
        c.toggleDeviceKey(e.id, lane.device.id, lane.param);
        var d = _deviceOf(lane.device.id);
        if (d != null) {
          var sp = c.phaseSpansFor(e.id);
          var ph = d.keyPhase(c.playheadSeconds, sp);
          var at = ph == MotionPhase.free
              ? c.playheadSeconds
              : sp.shareIn(ph, c.playheadSeconds);
          var ks = d.keysIn(ph)[lane.param] ?? const <DeviceKey>[];
          var i = ks.indexWhere((k) => (k.t - at).abs() < 0.02);
          setState(() => _pick =
              i < 0 ? null : (device: d.id, param: lane.param, ph: ph, i: i));
        }
        return;
      }
    }
    // The ruler, or anywhere else: the playhead.
    _drag = _Drag.scrub();
    c.frame = g.frameAt(x, c.document.frames);
  }

  void _move(PointerMoveEvent ev, _Geometry g) {
    var d = _drag;
    if (d == null) return;
    var x = ev.localPosition.dx;
    if (d.scrub) {
      c.frame = g.frameAt(x, c.document.frames);
      return;
    }
    if (d.loopEnd case var end?) {
      if (!d.moved) c.beginInteraction();
      d.moved = true;
      c.moveKeyframeLoopEnd(
          end, (g.timeAt(x) * _rate).round().clamp(0, c.document.frames));
      return;
    }
    var dt = (x - d.x) / g.perSecond;
    if (!d.moved && (x - d.x).abs() < 3) return;
    if (!d.moved) c.beginInteraction();
    d.moved = true;
    if (d.frames != null) {
      // Keyframes keep their spacing: moved a frame at a time, all or none.
      var want = (dt * _rate).round();
      var step = want - d.applied;
      if (step != 0 && c.moveTargetKeyframes(d.frames!, step)) {
        d.frames = [for (var f in d.frames!) f + step];
        d.applied = want;
        setState(() => _frames
          ..clear()
          ..addAll(d.frames!));
        c.frame = d.frames!.first.clamp(0, c.document.frames - 1);
      }
      return;
    }
    var p = _pick;
    if (p == null) return;
    var to = ((d.from + dt) * _rate).round() / _rate;
    var i = c.moveDeviceKey(
        e.id, p.device, p.param, p.ph, p.i, to.clamp(0, _scene),
        transient: true);
    setState(() => _pick = (device: p.device, param: p.param, ph: p.ph, i: i));
    c.frame = (to * _rate).round().clamp(0, c.document.frames - 1);
  }

  void _up(PointerEvent ev) {
    var d = _drag;
    _drag = null;
    if (d != null && d.moved) c.endInteraction();
  }

  /// _loopBar is where the element's own loop plays, in seconds, where its
  /// ends can be dragged: see CanvasController.keyframeLoop.
  (double, double)? get _loopBar {
    if (c.keyframeLoop case (var a, var b, _, _)) {
      var f = c.chainPhase;
      if (f != null && f != MotionPhase.loop) return null;
      return (a / _rate, (b + 1) / _rate);
    }
    return null;
  }

  /// _nearest is the index of the time in [times] drawn nearest [x], within
  /// a mark's reach, and how far.
  (int, double)? _nearest(List<double> times, double x, _Geometry g) {
    (int, double)? best;
    for (var (i, t) in times.indexed) {
      var dx = (g.xOf(t) - x).abs();
      if (dx <= 7 && (best == null || dx < best.$2)) best = (i, dx);
    }
    return best;
  }

  /// _marksOf are [lane]'s keys as drawn: each phase's, in seconds, as far
  /// as the filter shows them.
  List<_Mark> _marksOf(KeysLane lane, PhaseSpans spans) {
    var f = c.chainPhase;
    return [
      for (var ph in MotionPhase.values)
        if (f == null || f == ph)
          for (var (i, k)
              in (lane.device.keysIn(ph)[lane.param] ?? const <DeviceKey>[])
                  .indexed)
            if (ph == MotionPhase.free || spans.spanOf(ph) != null)
              _Mark(ph, i, ph == MotionPhase.free ? k.t : spans.timeOf(ph, k.t),
                  k),
    ];
  }

  // ---- the keyboard ----

  KeyEventResult _key(FocusNode node, KeyEvent ev) {
    if (ev is! KeyDownEvent && ev is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    var key = ev.logicalKey;
    var meta = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      if (_pick == null && _frames.isEmpty) return KeyEventResult.ignored;
      _delete();
      return KeyEventResult.handled;
    }
    if (meta && key == LogicalKeyboardKey.keyC && _frames.isNotEmpty) {
      var n = c.copyTargetKeys(_frames);
      if (n > 0) {
        _say(n == 1
            ? "Keyframe copied. Move the playhead and paste it."
            : "$n keyframes copied. Move the playhead and paste them.");
      }
      return KeyEventResult.handled;
    }
    if (meta && key == LogicalKeyboardKey.keyV && c.hasCopiedKeys) {
      c.beginInteraction();
      var (landed, why) = c.pasteTargetKeys();
      c.endInteraction();
      if (why != null) {
        _say(why);
      } else {
        setState(() => _frames
          ..clear()
          ..addAll(landed));
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _delete() {
    if (_pick case var p?) {
      c.removeDeviceKey(e.id, p.device, p.param, p.ph, p.i);
      setState(() => _pick = null);
      return;
    }
    if (_frames.isNotEmpty) {
      var n = _frames.length;
      c.beginInteraction();
      c.removeTargetKeyframes(_frames.toList());
      c.endInteraction();
      _frames.clear();
      _say(n == 1 ? "Keyframe deleted" : "$n keyframes deleted");
    }
  }

  /// _step picks the key before or after the one picked, on its row.
  void _step(int dir) {
    if (_pick case var p?) {
      var lane = _lanes
          .where((l) => l.device.id == p.device && l.param == p.param)
          .firstOrNull;
      if (lane == null) return;
      var marks = _marksOf(lane, elementPhaseSpans(e, c.document))
        ..sort((a, b) => a.t.compareTo(b.t));
      var at = marks.indexWhere((m) => m.ph == p.ph && m.i == p.i);
      var to = at + dir;
      if (at < 0 || to < 0 || to >= marks.length) return;
      var m = marks[to];
      setState(
          () => _pick = (device: p.device, param: p.param, ph: m.ph, i: m.i));
      c.frame = (m.t * _rate).round().clamp(0, c.document.frames - 1);
      return;
    }
    var t = _track;
    if (t == null) return;
    var fs = [for (var k in t.track.keys) k.frame];
    var from = _frames.isEmpty ? c.frame : (_frames.toList()..sort()).first;
    var to = dir < 0
        ? fs.reversed.where((f) => f < from).firstOrNull
        : fs.where((f) => f > from).firstOrNull;
    if (to == null) return;
    setState(() => _frames
      ..clear()
      ..add(to));
    c.frame = to;
  }

  void _spread(KeyframeTarget t) {
    var picked = _frames.toList()..sort();
    if (picked.length < 3) return;
    var lo = picked.first, hi = picked.last;
    var to = [
      for (var i = 0; i < picked.length; i++)
        (lo + (hi - lo) * i / (picked.length - 1)).round()
    ];
    var rest = {
      for (var k in t.track.keys)
        if (!_frames.contains(k.frame)) k.frame
    };
    if (to.any(rest.contains) || to.toSet().length != to.length) {
      _say("Spread evenly they would land on another keyframe.");
      return;
    }
    c.beginInteraction();
    if (t.points) {
      for (var i = 0; i < picked.length; i++) {
        c.moveTargetKeyframes([picked[i]], to[i] - picked[i]);
      }
    } else {
      var moved = {for (var i = 0; i < picked.length; i++) picked[i]: to[i]};
      c.writeTargetTrack(ElementTrack([
        for (var k in t.track.keys) k.copyWith(frame: moved[k.frame] ?? k.frame)
      ]..sort((a, b) => a.frame.compareTo(b.frame))));
    }
    c.endInteraction();
    setState(() => _frames
      ..clear()
      ..addAll(to));
  }

  // ---- drawn ----

  @override
  Widget build(BuildContext context) {
    var studio = MixerLook.of(context).studio;
    var lanes = _lanes;
    var track = _track;
    // A pick whose key has gone -- undone, or deleted elsewhere -- is let go.
    if (_pick != null && _picked == null) _pick = null;
    if (track != null) {
      _frames.removeWhere((f) => track.track.keyAt(f) == null);
    } else {
      _frames.clear();
    }
    var rows = 1 + (track != null ? 1 : 0) + lanes.length;
    var h = widget.height;
    var label = TextStyle(fontSize: 11.5, color: studio.muted);
    var bold = TextStyle(
        fontSize: 11.5, color: studio.text, fontWeight: FontWeight.w500);
    Widget labelRow(String key, String a, String b) => Container(
          key: ValueKey("keysLabel-$key"),
          height: KeysStrip.rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
              border: Border(
                  bottom:
                      BorderSide(color: studio.edge.withValues(alpha: 0.35)))),
          child: Text.rich(
              TextSpan(children: [
                TextSpan(text: a, style: bold),
                if (b.isNotEmpty) TextSpan(text: "  $b", style: label),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        );
    var rowsBody = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: KeysStrip.labelWidth,
        decoration: BoxDecoration(
            border: Border(right: BorderSide(color: studio.edge))),
        child: Column(children: [
          Container(
            height: KeysStrip.rulerHeight,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerLeft,
            child: Text("TIME",
                style: TextStyle(
                    fontSize: 10.5, letterSpacing: 0.84, color: studio.muted)),
          ),
          labelRow("clips", "Clips", ""),
          if (track != null)
            labelRow("keyframes", track.points ? "Points" : "Keyframes",
                track.points ? "" : "its own"),
          for (var l in lanes)
            labelRow("${l.device.id}-${l.param}", l.label, l.what),
        ]),
      ),
      Expanded(
        child: LayoutBuilder(builder: (context, box) {
          var g = _Geometry(box.maxWidth, _scene);
          var spans = elementPhaseSpans(e, c.document);
          return Listener(
            key: const ValueKey("keysLanes"),
            behavior: HitTestBehavior.opaque,
            onPointerDown: (ev) => _down(ev, g),
            onPointerMove: (ev) => _move(ev, g),
            onPointerUp: _up,
            onPointerCancel: _up,
            child: CustomPaint(
              size: Size(box.maxWidth,
                  KeysStrip.rulerHeight + rows * KeysStrip.rowHeight),
              painter: _LanesPainter(
                font: DefaultTextStyle.of(context).style.fontFamily,
                loopBar: _loopBar,
                frameRate: _rate,
                geometry: g,
                studio: studio,
                spans: spans,
                filter: c.chainPhase,
                playhead: c.frame / _rate,
                words: _words(),
                clipNames: _clipNames(),
                track: track,
                trackPicked: {..._frames},
                lanes: [
                  for (var l in lanes) (l, _marksOf(l, spans)),
                ],
                pick: _pick,
              ),
            ),
          );
        }),
      ),
    ]);
    return Focus(
      focusNode: _focus,
      onKeyEvent: _key,
      child: Container(
        key: const ValueKey("keysStrip"),
        height: h,
        decoration: BoxDecoration(
          color: studio.strip,
          border: Border(bottom: BorderSide(color: studio.edge)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: SingleChildScrollView(child: rowsBody)),
          Container(
            width: KeysStrip.inspectorWidth,
            decoration: BoxDecoration(
                border: Border(left: BorderSide(color: studio.edge))),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: CanvasDense(
                  height: 28, child: _inspector(context, studio, track)),
            ),
          ),
        ]),
      ),
    );
  }

  /// _words are what the voice says in this scene, in seconds.
  List<(double, String)> _words() {
    var doc = c.document;
    var start = doc.startOfScene(doc.at);
    return [
      for (var w in doc.words)
        if (w.frame >= start && w.frame - start < doc.frames)
          ((w.frame - start) / _rate, w.text),
    ];
  }

  /// _clipNames are what its arrival, loop and leaving are called on the
  /// clips row.
  Map<MotionPhase, String> _clipNames() => {
        MotionPhase.arrive: "Arrive",
        MotionPhase.loop: "Loop",
        MotionPhase.leave: "Leave",
      };

  Widget _inspector(
      BuildContext context, StudioColors studio, KeyframeTarget? track) {
    var title = TextStyle(
        fontSize: 12.5, fontWeight: FontWeight.w600, color: studio.text);
    var note = TextStyle(fontSize: 11.5, height: 1.35, color: studio.muted);
    var said = _said;
    // Laid out flat -- a line for what is picked and its buttons, a line
    // of its settings -- so it fits the strip at its least.
    Widget head(Widget name, List<Widget> buttons) => SizedBox(
          height: 28,
          child: Row(children: [
            Expanded(child: name),
            for (var b in buttons) ...[const SizedBox(width: 4), b],
          ]),
        );
    List<Widget> nav(VoidCallback onDelete) => [
          _navButton("keysPrev", Icons.chevron_left, () => _step(-1), studio),
          _navButton("keysNext", Icons.chevron_right, () => _step(1), studio),
          CanvasTextButton(
              key: const ValueKey("keysDelete"),
              label: "Delete",
              grow: false,
              onPressed: onDelete),
        ];
    Widget line(List<(double?, Widget)> cells) =>
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var (i, (w, cell)) in cells.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            w == null
                ? Expanded(child: CanvasCellFill(child: cell))
                : SizedBox(width: w, child: CanvasCellFill(child: cell)),
          ],
        ]);
    const gap = SizedBox(height: 8);
    // A setting's key.
    if (_pick case var p?) {
      var d = _deviceOf(p.device);
      var k = _picked;
      if (d != null && k != null) {
        var param = d.kind.param(p.param);
        var spans = elementPhaseSpans(e, c.document);
        var at = p.ph == MotionPhase.free ? k.t : spans.timeOf(p.ph, k.t);
        return Column(
            key: const ValueKey("keysInspector-key"),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              head(
                  Row(children: [
                    PhaseChip(phase: p.ph, on: true, onTap: null),
                    const SizedBox(width: 6),
                    Flexible(
                        child: Text(
                            "${d.kind.label} · ${param.label} · "
                            "${p.ph.label}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: title)),
                  ]),
                  nav(_delete)),
              gap,
              line([
                (
                  86,
                  CanvasStepper(
                      key: const ValueKey("keysAt"),
                      label: "At",
                      value: at,
                      min: 0,
                      max: _scene,
                      decimals: 2,
                      step: 1 / _rate,
                      suffix: " s",
                      fill: true,
                      onChanged: (v) {
                        var i = c.moveDeviceKey(
                            e.id, p.device, p.param, p.ph, p.i, v,
                            transient: true);
                        setState(() => _pick =
                            (device: p.device, param: p.param, ph: p.ph, i: i));
                      },
                      onCommit: c.endInteraction)
                ),
                if (param.unit != "argb")
                  (
                    86,
                    CanvasStepper(
                        key: const ValueKey("keysValue"),
                        label: "Value",
                        value: k.v,
                        min: param.min,
                        max: param.max,
                        decimals: param.unit == "#" ? 0 : 2,
                        fill: true,
                        onChanged: (v) => c.editDeviceKey(
                            e.id, p.device, p.param, p.ph, p.i,
                            v: v, transient: true),
                        onCommit: c.endInteraction)
                  ),
                (
                  null,
                  CanvasDropdown<KeyEase>(
                      key: const ValueKey("keysEase"),
                      label: "Into the next",
                      value: k.ease,
                      options: [for (var x in KeyEase.values) (x, x.label)],
                      onChanged: (x) => c.editDeviceKey(
                          e.id, p.device, p.param, p.ph, p.i,
                          ease: x))
                ),
              ]),
            ]);
      }
    }
    // The element's own keyframes.
    if (track != null && _frames.isNotEmpty) {
      var picked = _frames.toList()..sort();
      var one = picked.length == 1;
      var key = one ? track.track.keyAt(picked.first) : null;
      return Column(
          key: const ValueKey("keysInspector-track"),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            head(
                Text(
                    one
                        ? "${track.points ? "Point" : "Keyframe"} at "
                            "${(picked.first / _rate).toStringAsFixed(2)} s"
                        : "${picked.length} "
                            "${track.points ? "points" : "keyframes"}",
                    key: const ValueKey("keysPicked"),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: title),
                nav(_delete)),
            gap,
            line([
              if (!track.points)
                (
                  null,
                  CanvasDropdown<KeyframeEasing>(
                      key: const ValueKey("keysTrackEase"),
                      label: "Into the next",
                      value: key?.easing ?? KeyframeEasing.linear,
                      options: [
                        for (var x in KeyframeEasing.values) (x, x.label)
                      ],
                      onChanged: (x) {
                        c.beginInteraction();
                        c.easeTargetKeyframes(picked, x);
                        c.endInteraction();
                      })
                ),
              if (!track.points)
                (
                  70,
                  CanvasTextButton(
                      key: const ValueKey("keysCurves"),
                      label: "Curves",
                      grow: false,
                      onPressed: () => c.showTrackCurves(frame: picked.first))
                ),
              if (picked.length >= 3)
                (
                  100,
                  CanvasTextButton(
                      key: const ValueKey("keysSpread"),
                      label: "Spread evenly",
                      grow: false,
                      onPressed: () => _spread(track))
                ),
            ]),
            if (said != null) ...[
              gap,
              Text(said, key: const ValueKey("keysSaid"), style: note),
            ],
          ]);
    }
    return Column(
        key: const ValueKey("keysInspector-none"),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          head(Text("Keys", style: title), [
            if (track != null && !track.points && track.track.keys.isNotEmpty)
              CanvasTextButton(
                  key: const ValueKey("keysCurves"),
                  label: "Curves",
                  grow: false,
                  onPressed: () => c.showTrackCurves(frame: c.frame)),
          ]),
          const SizedBox(height: 4),
          Text(
              said ??
                  "Coloured by where each plays: arrival, loop, leaving or "
                      "independent. Pick a key to change it, drag to move "
                      "it, double-click a row to add one.",
              key: ValueKey(said == null ? "keysHint" : "keysSaid"),
              style: note),
        ]);
  }

  Widget _navButton(
          String key, IconData icon, VoidCallback onTap, StudioColors studio) =>
      InkWell(
        key: ValueKey(key),
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          width: 30,
          height: 28,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: studio.edge),
          ),
          child: Icon(icon, size: 16, color: studio.text),
        ),
      );
}

/// PhaseChip is one of a card's A, L, Loop and I buttons -- and, alone,
/// where a picked key plays.
class PhaseChip extends StatelessWidget {
  final MotionPhase phase;
  final bool on;
  final VoidCallback? onTap;
  const PhaseChip(
      {required this.phase, required this.on, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    var studio = MixerLook.of(context).studio;
    var colour = phaseColour(phase);
    var chip = Container(
      height: 22,
      constraints: const BoxConstraints(minWidth: 22),
      padding: const EdgeInsets.fromLTRB(6, 3, 6, 0),
      decoration: BoxDecoration(
        color: on ? colour : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: on ? Colors.transparent : studio.edge),
      ),
      child: Text(phase.short,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: on ? const Color(0xFF0B0E12) : studio.muted)),
    );
    if (onTap == null) return chip;
    return Semantics(
      button: true,
      toggled: on,
      label: phase.label,
      child: GestureDetector(
          behavior: HitTestBehavior.opaque, onTap: onTap, child: chip),
    );
  }
}

class _Mark {
  final MotionPhase ph;
  final int i;
  final double t;
  final DeviceKey key;
  const _Mark(this.ph, this.i, this.t, this.key);
}

class _Drag {
  final double x;
  final double from;
  final bool scrub;

  /// loopEnd is which end of the loop is dragged: its stop (true) or start.
  bool? loopEnd;
  List<int>? frames;
  int applied = 0;
  bool moved = false;
  _Drag.key(this.x, this.from) : scrub = false;
  _Drag.track(this.x, List<int> this.frames)
      : from = 0,
        scrub = false;
  _Drag.scrub()
      : x = 0,
        from = 0,
        scrub = true;
  _Drag.loop(bool end)
      : x = 0,
        from = 0,
        scrub = false,
        loopEnd = end;
}

/// _Geometry is where a moment is drawn across the lanes.
class _Geometry {
  static const pad = 8.0;
  final double width;
  final double scene;
  const _Geometry(this.width, this.scene);

  double get perSecond => math.max(1, width - 2 * pad) / scene;
  double xOf(double t) => pad + t * perSecond;
  double timeAt(double x) => ((x - pad) / perSecond).clamp(0.0, scene);
  int frameAt(double x, int frames) =>
      (timeAt(x) / scene * frames).round().clamp(0, math.max(0, frames - 1));
}

class _LanesPainter extends CustomPainter {
  final _Geometry geometry;
  final StudioColors studio;
  final PhaseSpans spans;
  final MotionPhase? filter;
  final double playhead;
  final List<(double, String)> words;
  final Map<MotionPhase, String> clipNames;
  final KeyframeTarget? track;
  final Set<int> trackPicked;
  final List<(KeysLane, List<_Mark>)> lanes;
  final _Pick? pick;

  /// loopBar is the element's own loop where it has one, drawn as its loop
  /// clip with handles at its ends.
  final (double, double)? loopBar;

  /// frameRate is the scene's, for the keyframes' frames.
  final double frameRate;

  /// font is the app's, for the ruler and the clips' names.
  final String? font;

  _LanesPainter({
    required this.font,
    required this.loopBar,
    required this.frameRate,
    required this.geometry,
    required this.studio,
    required this.spans,
    required this.filter,
    required this.playhead,
    required this.words,
    required this.clipNames,
    required this.track,
    required this.trackPicked,
    required this.lanes,
    required this.pick,
  });

  static const _ruler = KeysStrip.rulerHeight;
  static const _row = KeysStrip.rowHeight;

  void _text(Canvas canvas, String s, Offset at, TextStyle style,
      {bool centre = false, double? maxWidth}) {
    var tp = TextPainter(
        text: TextSpan(text: s, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: maxWidth == null ? null : "…")
      ..layout(maxWidth: maxWidth ?? double.infinity);
    tp.paint(canvas, centre ? at - Offset(tp.width / 2, 0) : at);
  }

  void _diamond(Canvas canvas, Offset at, Color fill,
      {double alpha = 1, bool picked = false, bool ghost = false}) {
    var path = Path()
      ..moveTo(at.dx, at.dy - 6)
      ..lineTo(at.dx + 6, at.dy)
      ..lineTo(at.dx, at.dy + 6)
      ..lineTo(at.dx - 6, at.dy)
      ..close();
    canvas.drawPath(path,
        Paint()..color = fill.withValues(alpha: (ghost ? 0.35 : 1) * alpha));
    if (!ghost) {
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xFF0B0E12).withValues(alpha: alpha));
    }
    if (picked) {
      var ring = Path()
        ..moveTo(at.dx, at.dy - 9)
        ..lineTo(at.dx + 9, at.dy)
        ..lineTo(at.dx, at.dy + 9)
        ..lineTo(at.dx - 9, at.dy)
        ..close();
      canvas.drawPath(
          ring,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = studio.text);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    var g = geometry;
    var mono = TextStyle(
        fontSize: 10,
        color: studio.muted,
        fontFamily: font,
        fontFeatures: const [FontFeature.tabularFigures()]);
    // The ruler: a tick a second (fewer on a long scene) and the words.
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, _ruler), Paint()..color = studio.inset);
    var every = g.perSecond >= 40
        ? 1
        : g.perSecond >= 12
            ? 5
            : 10;
    var line = Paint()..color = studio.edge.withValues(alpha: 0.5);
    for (var s = 0; s <= g.scene; s += every) {
      var x = g.xOf(s.toDouble());
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      _text(canvas, "${s}s", Offset(x + 3, 2), mono);
    }
    var said = TextStyle(
        fontSize: 10,
        color: studio.text.withValues(alpha: 0.75),
        fontFamily: font);
    var lastEnd = -1e9;
    for (var (t, w) in words) {
      var x = g.xOf(t);
      // Words that would sit on one another are left out.
      if (x < lastEnd + 4) continue;
      var tp = TextPainter(
          text: TextSpan(text: w, style: said),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, _ruler - 15));
      lastEnd = x + tp.width / 2;
    }
    var rowsDivider = Paint()..color = studio.edge.withValues(alpha: 0.35);
    double rowTop(int r) => _ruler + r * _row;
    void divider(int r) => canvas.drawLine(Offset(0, rowTop(r + 1) - 0.5),
        Offset(size.width, rowTop(r + 1) - 0.5), rowsDivider);
    // The clips: its arrival, loop and leaving.
    for (var ph in const [
      MotionPhase.arrive,
      MotionPhase.loop,
      MotionPhase.leave
    ]) {
      if (filter != null && filter != ph) continue;
      var span = ph == MotionPhase.loop && loopBar != null
          ? loopBar
          : spans.spanOf(ph);
      if (span case (var a, var b)) {
        var to = b.isFinite ? b : g.scene;
        var r = Rect.fromLTRB(g.xOf(a), rowTop(0) + 4,
            math.max(g.xOf(a) + 4, g.xOf(to)), rowTop(0) + 22);
        // A loop with no loop of its own -- only keys to play in it -- dim.
        var faint = ph == MotionPhase.loop && loopBar == null;
        canvas.drawRRect(
            RRect.fromRectAndRadius(r, const Radius.circular(5)),
            Paint()
              ..color = phaseColour(ph).withValues(alpha: faint ? 0.45 : 1));
        canvas.save();
        canvas.clipRect(r);
        _text(
            canvas,
            clipNames[ph] ?? ph.label,
            Offset(r.left + 6, r.top + 2),
            TextStyle(
                fontSize: 11,
                fontFamily: font,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF0B0E12)));
        canvas.restore();
        if (ph == MotionPhase.loop && loopBar != null) {
          var handle = Paint()..color = const Color(0xFF0B0E12);
          for (var x in [r.left + 2, r.right - 2]) {
            canvas.drawRRect(
                RRect.fromRectAndRadius(
                    Rect.fromCenter(
                        center: Offset(x, r.center.dy), width: 3, height: 10),
                    const Radius.circular(1.5)),
                handle);
          }
        }
      }
    }
    divider(0);
    var row = 1;
    // The element's own keyframes.
    if (track case var t?) {
      var y = rowTop(row) + _row / 2;
      var keys = t.track.keys;
      var span = Paint()
        ..color = trackKeyColour.withValues(alpha: 0.45)
        ..strokeWidth = 2;
      for (var i = 1; i < keys.length; i++) {
        canvas.drawLine(Offset(g.xOf(keys[i - 1].frame / _rateOf(t)), y),
            Offset(g.xOf(keys[i].frame / _rateOf(t)), y), span);
      }
      for (var k in keys) {
        _diamond(canvas, Offset(g.xOf(k.frame / _rateOf(t)), y), trackKeyColour,
            picked: trackPicked.contains(k.frame));
      }
      divider(row);
      row++;
    }
    // Each keyed setting.
    for (var (lane, marks) in lanes) {
      var y = rowTop(row) + _row / 2;
      for (var ph in MotionPhase.values) {
        var mine = [
          for (var m in marks)
            if (m.ph == ph) m
        ]..sort((a, b) => a.t.compareTo(b.t));
        if (mine.isEmpty) continue;
        var off = !lane.device.playing(ph);
        var colour = phaseColour(ph);
        var span = Paint()
          ..color = colour.withValues(alpha: off ? 0.12 : 0.4)
          ..strokeWidth = 2;
        for (var i = 1; i < mine.length; i++) {
          canvas.drawLine(Offset(g.xOf(mine[i - 1].t), y),
              Offset(g.xOf(mine[i].t), y), span);
        }
        // The loop's keys again on each go round after the first.
        if (ph == MotionPhase.loop) {
          if (spans.loop case (var a, var b)) {
            var end = b.isFinite ? b : g.scene;
            for (var n = 1; a + n * spans.cycle < end && n < 200; n++) {
              for (var m in mine) {
                var t = m.t + n * spans.cycle;
                if (t < end) {
                  _diamond(canvas, Offset(g.xOf(t), y), colour, ghost: true);
                }
              }
            }
          }
        }
        for (var m in mine) {
          var picked = pick != null &&
              pick!.device == lane.device.id &&
              pick!.param == lane.param &&
              pick!.ph == m.ph &&
              pick!.i == m.i;
          _diamond(canvas, Offset(g.xOf(m.t), y), colour,
              alpha: off ? 0.35 : 1, picked: picked);
        }
      }
      divider(row);
      row++;
    }
    // The playhead.
    var x = g.xOf(playhead.clamp(0, g.scene).toDouble());
    canvas.drawRect(
        Rect.fromLTWH(x - 1, 0, 2, size.height), Paint()..color = studio.text);
  }

  double _rateOf(KeyframeTarget t) => frameRate;

  @override
  bool shouldRepaint(covariant _LanesPainter old) => true;
}
