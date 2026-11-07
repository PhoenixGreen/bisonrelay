import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart'
    show KeyframeEasing;
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart'
    show boxOf, motionSceneOf;
import 'package:bruig/plugin_system/canvas/render/motion_pose.dart'
    show sampleProp;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// motion_curves.dart is the Motion view's Curves (Ken, 2026-11-08: "make sure
// you use the design we built, including how the curves panel works"): the
// chain prototype's curve editor. Every value the clip moves is drawn over
// the clip's length, each scaled to fit so all can be seen at once; Speed
// shows how fast each changes instead. Drag a key to move it (Alt: without
// snapping), double-click a line to add one, right-click a key to remove it.
// The values are listed down the left, the picked key's settings on the
// right, and the element's other instances can be drawn faint behind.

/// curveColour is each value's line.
Color curveColour(MotionProp p) => switch (p) {
      MotionProp.x => const Color(0xFF5CC6B8),
      MotionProp.y => const Color(0xFF7FC8F8),
      MotionProp.scale => const Color(0xFF9A92EA),
      MotionProp.turn => const Color(0xFFE0A84F),
      MotionProp.opacity => const Color(0xFFCFCBDF),
    };

/// MotionCurves edits [clip] of [element]: [onEdit] changes it (live while
/// dragged), [onCommit] ends a drag as one undo step.
class MotionCurves extends StatefulWidget {
  final CanvasController controller;
  final CanvasElement element;
  final MotionClip clip;

  /// playhead is where in the clip it is playing now, or null.
  final double? playhead;
  final void Function(MotionClip Function(MotionClip) change, {bool live})
      onEdit;
  final VoidCallback onCommit;
  const MotionCurves(
      {required this.controller,
      required this.element,
      required this.clip,
      required this.playhead,
      required this.onEdit,
      required this.onCommit,
      super.key});

  @override
  State<MotionCurves> createState() => _MotionCurvesState();
}

/// _Pick is a key: its value and its place among that value's keys.
typedef _Pick = (MotionProp, int);

class _MotionCurvesState extends State<MotionCurves> {
  bool _speed = false;
  bool _snap = true;
  bool _others = true;
  bool _inspector = true;

  /// _hidden are the values switched off in the list.
  final Set<MotionProp> _hidden = {};
  final Set<_Pick> _picked = {};

  // A drag: the keys as they were, and each value's scale then, so the
  // lines do not rescale under the pointer.
  Map<MotionProp, List<MotionKey>>? _dragFrom;
  Map<MotionProp, (double, double)>? _dragRange;
  Offset _dragStart = Offset.zero;
  bool _alt = false;

  MotionClip get c => widget.clip;

  List<MotionProp> get _shown => [
        for (var p in MotionProp.values)
          if (!_hidden.contains(p) && (c.keys[p]?.isNotEmpty ?? false)) p,
      ];

  double _sample(MotionProp p, double t) {
    var scene =
        motionSceneOf(widget.controller.document, widget.controller.frame);
    return sampleProp(c, p, t, boxOf(widget.element), scene) ?? p.rest;
  }

  /// _ranges are each shown value's lowest and highest over the clip, so it
  /// fills the height: Speed's from nought to its fastest.
  Map<MotionProp, (double, double)> _ranges() {
    var out = <MotionProp, (double, double)>{};
    var len = math.max(0.05, c.length);
    for (var p in _shown) {
      var lo = double.infinity, hi = -double.infinity;
      for (var i = 0; i <= 120; i++) {
        var v = _speed ? _rate(p, len * i / 120) : _sample(p, len * i / 120);
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
      if (_speed) lo = 0;
      if (hi - lo < 1e-6) {
        lo -= 1;
        hi += 1;
      }
      out[p] = (lo, hi);
    }
    return out;
  }

  double _rate(MotionProp p, double t) {
    const h = 1 / 60;
    return ((_sample(p, t + h) - _sample(p, t - h)) / (2 * h)).abs();
  }

  double get _grid =>
      math.max(0.01, widget.controller.document.audio.secondsPerBeat / 4);

  void _write(Map<MotionProp, List<MotionKey>> keys, {bool live = false}) =>
      widget.onEdit((x) => x.copyWith(keys: keys, edited: true), live: live);

  void _ease(KeyframeEasing ease) {
    if (_picked.isEmpty) return;
    var keys = {
      for (var e in c.keys.entries) e.key: [...e.value]
    };
    for (var (p, i) in _picked) {
      var list = keys[p];
      if (list == null || i >= list.length) continue;
      list[i] = list[i].copyWith(ease: ease);
    }
    _write(keys);
  }

  void _remove(_Pick k) {
    var keys = {
      for (var e in c.keys.entries) e.key: [...e.value]
    };
    var list = keys[k.$1];
    if (list == null || k.$2 >= list.length) return;
    list.removeAt(k.$2);
    if (list.isEmpty) keys.remove(k.$1);
    _picked.clear();
    _write(keys);
  }

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var s = look.studio;
    var tiny = TextStyle(fontSize: 11, color: s.muted);
    Widget tb(String key, String label, bool on, VoidCallback onTap,
            {IconData? icon, String? tip}) =>
        Tooltip(
          message: tip ?? label,
          child: InkWell(
            key: ValueKey(key),
            borderRadius: BorderRadius.circular(5),
            onTap: onTap,
            child: Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                  color:
                      on ? look.colors.primary.withValues(alpha: 0.35) : null,
                  borderRadius: BorderRadius.circular(5)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: on ? s.text : s.muted),
                  if (label.isNotEmpty) const SizedBox(width: 4),
                ],
                if (label.isNotEmpty)
                  Text(label,
                      style: TextStyle(
                          fontSize: 11.5, color: on ? s.text : s.muted)),
              ]),
            ),
          ),
        );
    var one = _picked.length == 1 ? _picked.first : null;
    var oneKey = one == null ? null : c.keys[one.$1]?.elementAtOrNull(one.$2);
    var toolbar = Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: s.edge))),
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              tb("curvesValues", "Values", !_speed,
                  () => setState(() => _speed = false),
                  icon: Icons.show_chart, tip: "Each value over time"),
              tb("curvesSpeed", "Speed", _speed,
                  () => setState(() => _speed = true),
                  icon: Icons.speed,
                  tip: "How fast each value changes, the way an animator "
                      "reads motion"),
              Container(
                  width: 1,
                  height: 18,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: s.edge),
              tb("curvesAll", "All values", _hidden.isEmpty,
                  () => setState(_hidden.clear),
                  tip: "Show every value it moves"),
              Container(
                  width: 1,
                  height: 18,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: s.edge),
              Text("Ease", style: tiny),
              const SizedBox(width: 4),
              for (var ease in const [
                KeyframeEasing.linear,
                KeyframeEasing.easeIn,
                KeyframeEasing.easeOut,
                KeyframeEasing.easeInOut,
                KeyframeEasing.hold,
                KeyframeEasing.overshoot,
                KeyframeEasing.bounce,
                KeyframeEasing.spring,
              ])
                tb(
                    "curvesEase-${ease.name}",
                    ease == KeyframeEasing.easeInOut ? "In-out" : ease.label,
                    oneKey?.ease == ease,
                    () => _ease(ease),
                    tip: _picked.isEmpty
                        ? "Pick a key first: how it gets there"
                        : "How the picked key${_picked.length == 1 ? " is" : "s are"} reached"),
              Container(
                  width: 1,
                  height: 18,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: s.edge),
              tb("curvesSnap", "Snap 1/4", _snap,
                  () => setState(() => _snap = !_snap),
                  tip: "Keys move by a quarter of a beat. Alt drags freely."),
            ]),
          ),
        ),
        tb("curvesInspector", "", _inspector,
            () => setState(() => _inspector = !_inspector),
            icon: Icons.view_sidebar_outlined,
            tip: _inspector ? "Hide the key's settings" : "Show them"),
      ]),
    );

    // The values, down the left: each switched on or off, with its keys.
    var list = Container(
      width: 180,
      decoration:
          BoxDecoration(border: Border(right: BorderSide(color: s.edge))),
      child: ListView(padding: const EdgeInsets.all(6), children: [
        _head(look, "Values"),
        for (var p in MotionProp.values)
          if (c.keys[p]?.isNotEmpty ?? false)
            _listRow(
                look,
                "curvesValue-${p.name}",
                p == MotionProp.y ? "Up and down" : p.label,
                "${c.keys[p]!.length} key${c.keys[p]!.length == 1 ? "" : "s"}",
                !_hidden.contains(p),
                curveColour(p),
                () => setState(() =>
                    _hidden.contains(p) ? _hidden.remove(p) : _hidden.add(p))),
        for (var p in MotionProp.values)
          if (!(c.keys[p]?.isNotEmpty ?? false))
            _listRow(
                look,
                "curvesAdd-${p.name}",
                p == MotionProp.y ? "Up and down" : p.label,
                "+ key",
                false,
                curveColour(p), () {
              // A first key, at its start, as it rests.
              _write({
                ...c.keys,
                p: [MotionKey(0, MotionNumber(p.rest))]
              });
            }),
        const SizedBox(height: 8),
        _head(look, "Show"),
        if (widget.element.base.motion.instances != null)
          _listRow(look, "curvesOthers", "Other instances, faint", "", _others,
              null, () => setState(() => _others = !_others)),
      ]),
    );

    var ranges = _dragRange ?? _ranges();
    var graph = LayoutBuilder(builder: (context, box) {
      var size = Size(box.maxWidth, box.maxHeight);
      const top = 24.0, pad = 12.0;
      var len = math.max(0.05, c.length);
      double xOf(double t) => pad + t / len * (size.width - pad * 2);
      double tOf(double x) => ((x - pad) / (size.width - pad * 2) * len);
      double yOf(MotionProp p, double v) {
        var (lo, hi) = ranges[p] ?? (0.0, 1.0);
        return top + 10 + (1 - (v - lo) / (hi - lo)) * (size.height - top - 30);
      }

      double vOf(MotionProp p, double y) {
        var (lo, hi) = ranges[p] ?? (0.0, 1.0);
        return lo + (1 - (y - top - 10) / (size.height - top - 30)) * (hi - lo);
      }

      _Pick? keyAt(Offset at) {
        _Pick? best;
        var bestD = 9.0;
        for (var p in _shown) {
          for (var (i, k) in c.keys[p]!.indexed) {
            var y = _speed ? null : yOf(p, _sample(p, k.t));
            var d = y == null
                ? (xOf(k.t) - at.dx).abs()
                : (Offset(xOf(k.t), y) - at).distance;
            if (d < bestD) {
              bestD = d;
              best = (p, i);
            }
          }
        }
        return best;
      }

      return Listener(
        onPointerDown: (e) {
          _alt = HardwareKeyboard.instance.isAltPressed;
          // Right-click: the key there taken away.
          if (e.buttons == kSecondaryMouseButton) {
            var k = keyAt(e.localPosition);
            if (k != null) _remove(k);
          }
        },
        child: GestureDetector(
          key: const ValueKey("curvesGraph"),
          behavior: HitTestBehavior.opaque,
          // From where it was pressed, not where the drag was noticed: a
          // key is small.
          dragStartBehavior: DragStartBehavior.down,
          onTapUp: (d) {
            var k = keyAt(d.localPosition);
            setState(() {
              if (!HardwareKeyboard.instance.isShiftPressed) _picked.clear();
              if (k != null) _picked.add(k);
            });
          },
          // Double-clicked on a line: a key there, on that value.
          onDoubleTapDown: (d) {
            if (_speed) return;
            var at = d.localPosition;
            var t = tOf(at.dx).clamp(0.0, len);
            if (_snap) t = (t / _grid).round() * _grid;
            MotionProp? near;
            var bestD = 12.0;
            for (var p in _shown) {
              var dd = (yOf(p, _sample(p, tOf(at.dx))) - at.dy).abs();
              if (dd < bestD) {
                bestD = dd;
                near = p;
              }
            }
            if (near == null) return;
            var v = _sample(near, t);
            var keys = [
              ...c.keys[near]!,
              MotionKey(t, MotionNumber(double.parse(v.toStringAsFixed(3))),
                  ease: KeyframeEasing.easeInOut)
            ]..sort((a, b) => a.t.compareTo(b.t));
            _write({...c.keys, near: keys});
            setState(() {
              _picked
                ..clear()
                ..add((near!, keys.indexWhere((k) => k.t == t)));
            });
          },
          onPanStart: (d) {
            var k = keyAt(d.localPosition);
            if (k == null) return;
            if (!_picked.contains(k)) {
              _picked
                ..clear()
                ..add(k);
            }
            _dragFrom = {
              for (var e in c.keys.entries) e.key: [...e.value]
            };
            _dragRange = _ranges();
            _dragStart = d.localPosition;
            widget.controller.beginInteraction();
          },
          onPanUpdate: (d) {
            var from = _dragFrom;
            if (from == null) return;
            var dt = (d.localPosition.dx - _dragStart.dx) /
                (size.width - pad * 2) *
                len;
            var keys = {
              for (var e in from.entries) e.key: [...e.value]
            };
            for (var (p, i) in _picked) {
              var was = from[p]![i];
              var t = (was.t + dt).clamp(0.0, len);
              if (_snap && !_alt) t = (t / _grid).round() * _grid;
              var value = was.value;
              // A number moves up and down too; a place keeps where it is.
              if (!_speed && value is MotionNumber) {
                var y =
                    yOf(p, value.value) + (d.localPosition.dy - _dragStart.dy);
                value =
                    MotionNumber(double.parse(vOf(p, y).toStringAsFixed(3)));
              }
              keys[p]![i] = was.copyWith(t: t, value: value);
            }
            _write(keys, live: true);
          },
          onPanEnd: (_) {
            if (_dragFrom == null) return;
            // Kept in order, and the ones moved still picked.
            var moved = {
              for (var (p, i) in _picked) (p, c.keys[p]![i]),
            };
            var keys = {
              for (var e in c.keys.entries)
                e.key: [...e.value]..sort((a, b) => a.t.compareTo(b.t)),
            };
            _write(keys, live: true);
            widget.onCommit();
            setState(() {
              _picked
                ..clear()
                ..addAll([
                  for (var (p, k) in moved) (p, keys[p]!.indexOf(k)),
                ]);
              _dragFrom = null;
              _dragRange = null;
            });
          },
          child: CustomPaint(
            painter: _CurvesPainter(
              clip: c,
              shown: _shown,
              speed: _speed,
              picked: _picked,
              sample: _sample,
              rate: _rate,
              xOf: xOf,
              yOf: yOf,
              len: len,
              grid: _grid,
              playhead: widget.playhead,
              others: _others
                  ? [
                      for (var i = 1;
                          i <
                              math.min(
                                  8,
                                  widget.element.base.motion.instances?.count ??
                                      0);
                          i++)
                        widget.element.base.motion.instances!.startOf(i),
                    ]
                  : const [],
              studio: s,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      );
    });

    var inspector = Container(
      width: 220,
      padding: const EdgeInsets.all(10),
      decoration:
          BoxDecoration(border: Border(left: BorderSide(color: s.edge))),
      child: ListView(children: [
        _head(look,
            widget.element.name.isEmpty ? "Element" : widget.element.name),
        if (one != null && oneKey != null) ...[
          Text(
              "${one.$1 == MotionProp.y ? "Up and down" : one.$1.label} · key ${one.$2 + 1}",
              key: const ValueKey("curvesKeyName"),
              style: TextStyle(fontSize: 12, color: s.text)),
          const SizedBox(height: 6),
          Text(
              "At ${oneKey.t.toStringAsFixed(2)} s · "
              "${oneKey.value is MotionNumber ? (oneKey.value as MotionNumber).value.toStringAsFixed(2) : "a place, worked out as it plays"}",
              style: TextStyle(fontSize: 11, color: s.muted)),
          const SizedBox(height: 4),
          Text("Gets there: ${oneKey.ease.label}",
              style: TextStyle(fontSize: 11, color: s.muted)),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey("curvesRemove"),
              onPressed: () => _remove(one),
              child: const Text("Remove the key"),
            ),
          ),
        ] else
          Text(
              "Drag a key to move it. Double-click a line to add a key, and "
              "right-click a key to remove it.\n\nEach value is scaled to "
              "fit, so you can see them all at once. Speed shows how fast "
              "each one changes, the way an animator reads motion.",
              style: TextStyle(fontSize: 11, height: 1.45, color: s.muted)),
        if (widget.element.base.motion.instances case var set?) ...[
          const SizedBox(height: 12),
          _head(look, "Instances"),
          Text(
              "Every instance uses these curves, starting one after another"
              "${set.count > 1 ? ": ${set.count} of them" : ""}.",
              style: TextStyle(fontSize: 11, height: 1.45, color: s.muted)),
        ],
      ]),
    );

    var status = Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(border: Border(top: BorderSide(color: s.edge))),
      child: Text(
          "${widget.element.name.isEmpty ? "It" : widget.element.name}: "
          "${_shown.length} value${_shown.length == 1 ? "" : "s"} · drag keys, "
          "double-click to add, right-click to remove · Alt drags without "
          "snapping",
          key: const ValueKey("curvesStatus"),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tiny),
    );

    return Container(
      color: s.panel,
      child: Column(children: [
        toolbar,
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            list,
            Expanded(child: ClipRect(child: graph)),
            if (_inspector) inspector,
          ]),
        ),
        status,
      ]),
    );
  }

  Widget _head(MixerLook look, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 6),
        child: Text(text.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
                color: look.studio.muted)),
      );

  Widget _listRow(MixerLook look, String key, String label, String end, bool on,
          Color? dot, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: InkWell(
          key: ValueKey(key),
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
                color: on
                    ? look.colors.primary.withValues(alpha: 0.3)
                    : look.studio.raised,
                borderRadius: BorderRadius.circular(4)),
            child: Row(children: [
              if (dot != null) ...[
                Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                        color: on ? dot : dot.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        color: on ? look.studio.text : look.studio.muted)),
              ),
              if (end.isNotEmpty)
                Text(end,
                    style: TextStyle(
                        fontSize: 9.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: look.studio.muted)),
            ]),
          ),
        ),
      );
}

class _CurvesPainter extends CustomPainter {
  final MotionClip clip;
  final List<MotionProp> shown;
  final bool speed;
  final Set<_Pick> picked;
  final double Function(MotionProp, double) sample, rate;
  final double Function(double) xOf;
  final double Function(MotionProp, double) yOf;
  final double len, grid;
  final double? playhead;
  final List<double> others;
  final StudioColors studio;
  _CurvesPainter(
      {required this.clip,
      required this.shown,
      required this.speed,
      required this.picked,
      required this.sample,
      required this.rate,
      required this.xOf,
      required this.yOf,
      required this.len,
      required this.grid,
      required this.playhead,
      required this.others,
      required this.studio});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = studio.display);
    // The grid: a line each quarter beat, brighter on the beat; the
    // ruler's seconds along the top.
    var fine = Paint()..color = Colors.white.withValues(alpha: 0.03);
    var beat = Paint()..color = Colors.white.withValues(alpha: 0.08);
    var n = 0;
    for (var t = 0.0; t <= len + 1e-9; t += grid, n++) {
      canvas.drawRect(Rect.fromLTWH(xOf(t).roundToDouble(), 0, 1, size.height),
          n % 4 == 0 ? beat : fine);
    }
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 22),
        Paint()..color = Colors.black.withValues(alpha: 0.2));
    var step = len <= 2
        ? 0.25
        : len <= 6
            ? 0.5
            : len <= 20
                ? 1.0
                : 5.0;
    for (var t = 0.0; t <= len + 1e-9; t += step) {
      var tp = TextPainter(
          text: TextSpan(
              text: t == t.roundToDouble()
                  ? "${t.round()} s"
                  : t.toStringAsFixed(2),
              style: TextStyle(fontSize: 10, color: studio.muted)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(xOf(t) + 3, 5));
    }
    double value(MotionProp p, double t) => speed ? rate(p, t) : sample(p, t);
    Path line(MotionProp p, double shift) {
      var path = Path();
      for (var i = 0; i <= 200; i++) {
        var t = len * i / 200;
        var at = (t - shift).clamp(0.0, len);
        var pt = Offset(xOf(t), yOf(p, value(p, at)));
        i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
      }
      return path;
    }

    for (var p in shown) {
      var colour = curveColour(p);
      // The other instances, faint: the same curves, each from its start.
      for (var start in others) {
        canvas.drawPath(
            line(p, start),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = colour.withValues(alpha: 0.18));
      }
      canvas.drawPath(
          line(p, 0),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeJoin = StrokeJoin.round
            ..color = colour);
      for (var (i, k) in clip.keys[p]!.indexed) {
        var at = Offset(xOf(k.t), yOf(p, value(p, k.t)));
        var on = picked.contains((p, i));
        var place = k.value is! MotionNumber;
        var d = Path()
          ..moveTo(at.dx, at.dy - 6)
          ..lineTo(at.dx + 6, at.dy)
          ..lineTo(at.dx, at.dy + 6)
          ..lineTo(at.dx - 6, at.dy)
          ..close();
        canvas.drawPath(
            d,
            Paint()
              ..color = place
                  ? const Color(0xFFE2B04A)
                  : on
                      ? Colors.white
                      : colour);
        if (on) {
          canvas.drawPath(
              d,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5
                ..color = studio.text);
        }
      }
    }
    if (playhead case var t?) {
      canvas.drawRect(Rect.fromLTWH(xOf(t), 0, 1.5, size.height),
          Paint()..color = const Color(0xFFE2B04A));
    }
    if (shown.isEmpty) {
      var tp = TextPainter(
          text: TextSpan(
              text: "No values shown: pick one on the left, or add a key "
                  "to one.",
              style: TextStyle(fontSize: 12, color: studio.muted)),
          textDirection: TextDirection.ltr)
        ..layout(maxWidth: size.width - 40);
      tp.paint(canvas, Offset(20, size.height / 2 - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_CurvesPainter old) => true;
}
