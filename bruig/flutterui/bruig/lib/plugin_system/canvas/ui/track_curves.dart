import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/curve_view.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// track_curves.dart is the Curves of an element's own keyframes (Ken,
// 2026-11-09: the approved keyframes prototype, v2): the same design as a
// clip's Curves (motion_curves.dart), across the Motion view. The Keyframes
// card says when each keyframe is; this says how much, and how it eases to
// the next. A keyframe holds all its values at one frame, so a key dragged
// sideways moves its whole keyframe; up or down, it changes that one value.
// Double-click a line for a keyframe there; right-click a key to put that
// value back to rest (a channel's, taken out of the keyframe).

/// _laneColours are each value's line, as the clip Curves' are.
const _laneColours = {
  "dx": Color(0xFF5CC6B8),
  "dy": Color(0xFF7FC8F8),
  "scale": Color(0xFF9A92EA),
  "rotate": Color(0xFFE0A84F),
  "opacity": Color(0xFFCFCBDF),
};

Color _colourOf(String id) => _laneColours[id] ?? const Color(0xFFF08BD0);

/// _withValue is [k] with [id]'s value [v].
Keyframe _withValue(Keyframe k, String id, double v) => switch (id) {
      "dx" => k.copyWith(dx: v),
      "dy" => k.copyWith(dy: v),
      "scale" => k.copyWith(scale: v),
      "rotate" => k.copyWith(rotate: v),
      "opacity" => k.copyWith(opacity: v.clamp(0.0, 1.0).toDouble()),
      _ => k.copyWith(values: {...k.values, id: v}),
    };

/// _rested is [k] with [id] back to rest -- a channel taken out of it.
Keyframe _rested(Keyframe k, String id) => switch (id) {
      "dx" => k.copyWith(dx: 0),
      "dy" => k.copyWith(dy: 0),
      "scale" => k.copyWith(scale: 1),
      "rotate" => k.copyWith(rotate: 0),
      "opacity" => k.copyWith(opacity: 1),
      _ => k.copyWith(values: {...k.values}..remove(id)),
    };

/// TrackCurves is the Curves of what the Keyframes card edits, [height]
/// tall.
class TrackCurves extends StatefulWidget {
  final CanvasController controller;
  final double height;
  const TrackCurves(
      {required this.controller, required this.height, super.key});

  @override
  State<TrackCurves> createState() => _TrackCurvesState();
}

class _TrackCurvesState extends State<TrackCurves>
    with CurveViewing<TrackCurves> {
  CanvasController get c => widget.controller;
  bool _speed = false;
  final Set<String> _hidden = {};

  /// _pick is the key picked: its value's id and its keyframe's frame.
  (String, int)? _pick;

  // A drag: the keyframe's frame then, where it was pressed, and each
  // value's scale then, so the lines do not rescale under the pointer.
  int? _dragFrame;
  double _dragX = 0;
  Map<String, (double, double)>? _dragRange;

  /// _handle is a handle being dragged: the keyframe whose ease it is, which
  /// of its two, and where the two keys were on the line it was taken on.
  (int, int, Offset, Offset)? _handle;

  /// _scrub is whether a drag is moving the playhead; _pan the view.
  bool _scrub = false, _pan = false;
  final FocusNode _focus = FocusNode(debugLabel: "trackCurves");

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  int get _last => math.max(1, c.document.frames - 1);

  @override
  void initState() {
    super.initState();
    // Opened on a keyframe: its first value that changes, picked.
    var f = c.trackCurvesFrame;
    var t = c.keyframeTarget;
    if (f != null && t != null && t.track.keyAt(f) != null) {
      var first = keyframeLanesOf(t.track).firstOrNull?.$1;
      if (first != null) _pick = (first, f);
    }
  }

  @override
  Widget build(BuildContext context) {
    var t = c.keyframeTarget;
    var look = MixerLook.of(context);
    var s = look.studio;
    if (t == null || t.points) return const SizedBox.shrink();
    var lanes = keyframeLanesOf(t.track);
    var shown = [
      for (var l in lanes)
        if (!_hidden.contains(l.$1)) l
    ];
    var pick = _pick;
    if (pick != null && t.track.keyAt(pick.$2) == null) pick = _pick = null;
    var picked = pick == null ? null : t.track.keyAt(pick.$2);

    Widget tb(String key, String label, bool on, VoidCallback onTap) => InkWell(
          key: ValueKey(key),
          borderRadius: BorderRadius.circular(5),
          onTap: onTap,
          child: Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: on ? look.colors.primary.withValues(alpha: 0.35) : null,
                borderRadius: BorderRadius.circular(5)),
            child: Text(label,
                style: TextStyle(fontSize: 11.5, color: on ? s.text : s.muted)),
          ),
        );
    var toolbar = Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: s.edge))),
      child: Row(children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 8),
          child: Text("CURVES · ${t.name.toUpperCase()}",
              style: TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600,
                  color: s.text)),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              tb("trackCurvesValues", "Values", !_speed,
                  () => setState(() => _speed = false)),
              tb("trackCurvesSpeed", "Speed", _speed,
                  () => setState(() => _speed = true)),
              Container(
                  width: 1,
                  height: 18,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: s.edge),
              Text("Ease", style: TextStyle(fontSize: 11, color: s.muted)),
              for (var e in KeyframeEasing.values)
                tb("trackCurvesEase-${e.name}", e.label, picked?.easing == e,
                    () => _ease(e)),
              Container(
                  width: 1,
                  height: 18,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: s.edge),
              // Each ease's handles on its lines, to shape it by hand (Ken,
              // 2026-11-14), and the whole of it again after zooming.
              tb("trackCurvesHandles", "Handles", curvesShowHandles,
                  () => setState(() => curvesShowHandles = !curvesShowHandles)),
              if (!view.fitted)
                tb("trackCurvesFit", "Fit", false, () => setState(view.fit)),
            ]),
          ),
        ),
        IconButton(
          key: const ValueKey("trackCurvesClose"),
          visualDensity: VisualDensity.compact,
          iconSize: 16,
          color: s.muted,
          onPressed: c.closeTrackCurves,
          icon: const Icon(Icons.close),
        ),
      ]),
    );

    var list = Container(
      width: 170,
      decoration:
          BoxDecoration(border: Border(right: BorderSide(color: s.edge))),
      child: ListView(padding: const EdgeInsets.all(6), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
          child: Text("VALUES",
              style:
                  TextStyle(fontSize: 9.5, letterSpacing: 0.7, color: s.muted)),
        ),
        for (var (id, name, _) in lanes)
          InkWell(
            key: ValueKey("trackCurvesValue-$id"),
            borderRadius: BorderRadius.circular(5),
            onTap: () => setState(() =>
                _hidden.contains(id) ? _hidden.remove(id) : _hidden.add(id)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: Row(children: [
                Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: _hidden.contains(id) ? s.edge : _colourOf(id),
                        borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(name,
                      style: TextStyle(
                          fontSize: 11.5,
                          color: _hidden.contains(id) ? s.muted : s.text)),
                ),
              ]),
            ),
          ),
        if (lanes.isEmpty)
          Padding(
            padding: const EdgeInsets.all(4),
            child: Text(
                "Nothing changes between its keyframes yet: set a keyframe's "
                "values in the element's settings, or drag a key here.",
                style: TextStyle(fontSize: 11, color: s.muted)),
          ),
      ]),
    );

    var ranges = _dragRange ?? _ranges(t.track, shown);
    var graph = LayoutBuilder(builder: (context, box) {
      var size = Size(box.maxWidth, box.maxHeight);
      const top = 24.0, pad = 12.0;
      var area =
          Rect.fromLTRB(pad, top + 10, size.width - pad, size.height - 20);
      graphArea = area;
      double fAt(double x) => view.u(x, area) * _last;
      double xOf(num f) => view.x(f / _last, area);
      int fOf(double x) => fAt(x).round().clamp(0, _last).toInt();
      double yOf(String id, double v) {
        var (lo, hi) = ranges[id] ?? (0.0, 1.0);
        return view.y((v - lo) / (hi - lo), area);
      }

      double vOf(String id, double y) {
        var (lo, hi) = ranges[id] ?? (0.0, 1.0);
        return lo + view.n(y, area) * (hi - lo);
      }

      // Each ease's handles, on each line it moves, where shown.
      var handles = <CurveHandles>[
        if (curvesShowHandles && !_speed)
          for (var (id, _, read) in shown)
            for (var i = 0; i < t.track.keys.length - 1; i++)
              if (_handlesOn(t.track.keys[i], t.track.keys[i + 1], read)
                  case (var va, var vb))
                () {
                  var a = t.track.keys[i], b = t.track.keys[i + 1];
                  var p0 = Offset(xOf(a.frame), yOf(id, va));
                  var p1 = Offset(xOf(b.frame), yOf(id, vb));
                  var (h1, h2) = handlesOf(_curveOf(a), p0, p1);
                  return CurveHandles(
                      p0, h1, h2, p1, _colourOf(id), a.frame, id);
                }(),
      ];

      (String, int)? keyAt(Offset at) {
        (String, int)? best;
        var bestD = 9.0;
        for (var (id, _, read) in shown) {
          for (var k in t.track.keys) {
            var v = read(k);
            if (v == null) continue;
            var d = (Offset(xOf(k.frame), yOf(id, v)) - at).distance;
            if (d < bestD) {
              bestD = d;
              best = (id, k.frame);
            }
          }
        }
        return best;
      }

      var playheadX = xOf(c.frame.clamp(0, _last));
      return Focus(
        focusNode: _focus,
        onKeyEvent: (_, ev) => _key(t, ev),
        child: curveGestures(Listener(
          onPointerDown: (e) {
            _focus.requestFocus();
            // Right-click: that value back to rest.
            if (e.buttons == kSecondaryMouseButton) {
              if (keyAt(e.localPosition) case (var id, var f)) _rest(t, id, f);
            }
          },
          child: GestureDetector(
            key: const ValueKey("trackCurvesGraph"),
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onTapDown: (d) {
              if (d.localPosition.dy < top) {
                c.frame = fOf(d.localPosition.dx);
                return;
              }
              setState(() => _pick = keyAt(d.localPosition));
            },
            // On the ruler, the whole of it again; on the lines, a keyframe.
            onDoubleTapDown: (d) => d.localPosition.dy < top
                ? setState(view.fit)
                : _add(t, fOf(d.localPosition.dx)),
            onDoubleTap: () {},
            onPanStart: (d) {
              var at = d.localPosition;
              // A handle first: it sits over the lines and the keys.
              for (var h in handles) {
                if (h.at(at) case var which?) {
                  setState(() {
                    _handle = (h.key as int, which, h.p0, h.p1);
                    _dragRange = ranges;
                  });
                  c.beginInteraction();
                  return;
                }
              }
              var k = keyAt(at);
              if (k == null) {
                // The playhead, by its cap or its line, or the ruler; else
                // the view itself.
                if (at.dy < top || nearPlayhead(at, playheadX, top)) {
                  _scrub = true;
                  c.frame = fOf(at.dx);
                } else {
                  _pan = true;
                }
                return;
              }
              setState(() {
                _pick = k;
                _dragFrame = k.$2;
                _dragX = at.dx - xOf(k.$2);
                _dragRange = ranges;
              });
              c.beginInteraction();
            },
            onPanUpdate: (d) {
              if (_scrub) {
                c.frame = fOf(d.localPosition.dx);
                return;
              }
              if (_pan) {
                setState(() {
                  view.panTime(d.delta.dx, area);
                  view.panValues(d.delta.dy, area);
                });
                return;
              }
              if (_handle case (var f, var which, var p0, var p1)) {
                var now = c.keyframeTarget?.track;
                var k = now?.keyAt(f);
                if (now == null || k == null) return;
                var curve =
                    curveDragged(_curveOf(k), which, d.localPosition, p0, p1);
                c.writeTargetTrack(now.withKey(
                    k.copyWith(easing: KeyframeEasing.custom, curve: curve)));
                setState(() {});
                return;
              }
              var p = _pick, at = _dragFrame;
              if (p == null || at == null) return;
              var now = c.keyframeTarget?.track;
              var k = now?.keyAt(at);
              if (now == null || k == null) return;
              // Up or down: that one value.
              var next = now
                  .withKey(_withValue(k, p.$1, vOf(p.$1, d.localPosition.dy)));
              c.writeTargetTrack(next);
              // Sideways: the whole keyframe, where nothing else is.
              var to = fOf(d.localPosition.dx - _dragX);
              if (to != at && c.moveTargetKeyframes([at], to - at)) {
                _dragFrame = to;
                _pick = (p.$1, to);
              }
              setState(() {});
            },
            onPanEnd: (_) {
              if (_dragFrame != null || _handle != null) c.endInteraction();
              setState(() {
                _dragFrame = null;
                _dragRange = null;
                _handle = null;
                _scrub = false;
                _pan = false;
              });
            },
            child: ClipRect(
              child: CustomPaint(
                size: Size.infinite,
                painter: _CurvesPainter(
                  track: t.track,
                  shown: shown,
                  speed: _speed,
                  last: _last,
                  rate: math.max(1, c.document.frameRate),
                  playhead: c.frame,
                  pick: _pick,
                  studio: s,
                  area: area,
                  view: view,
                  xOf: xOf,
                  yOf: yOf,
                  handles: handles,
                ),
              ),
            ),
          ),
        )),
      );
    });

    var inspector = Container(
      width: 210,
      padding: const EdgeInsets.all(10),
      decoration:
          BoxDecoration(border: Border(left: BorderSide(color: s.edge))),
      child: picked == null || pick == null
          ? Text(
              "The Keyframes card says when each keyframe is; here is how "
              "much, and how it eases to the next. Drag a key sideways to "
              "move its keyframe, up or down to change that value. "
              "Double-click a line for a keyframe there; right-click a key "
              "to put that value back to rest, or Delete to take its "
              "keyframe away.\n\nPinch or ⌘-scroll to zoom in on time, "
              "with ⌥ on the values; swipe or drag the background to move; "
              "double-click the ruler to see it all. Drag the playhead by "
              "its cap. Handles shapes an ease by hand.",
              key: const ValueKey("trackCurvesHint"),
              style: TextStyle(fontSize: 11.5, height: 1.45, color: s.muted))
          : _inspector(t, pick, picked, lanes, s),
    );

    return Container(
      key: const ValueKey("trackCurves"),
      height: widget.height,
      color: s.panel,
      child: Column(children: [
        toolbar,
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            list,
            Expanded(child: graph),
            inspector,
          ]),
        ),
      ]),
    );
  }

  Widget _inspector(
      KeyframeTarget t,
      (String, int) pick,
      Keyframe k,
      List<(String, String, double? Function(Keyframe))> lanes,
      StudioColors s) {
    var lane = lanes.where((l) => l.$1 == pick.$1).firstOrNull;
    var name = lane?.$2 ?? pick.$1;
    var v = lane?.$3(k) ?? 0;
    var cap = TextStyle(fontSize: 9.5, letterSpacing: 0.6, color: s.muted);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text("$name at frame ${k.frame}",
          key: const ValueKey("trackCurvesKeyName"),
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: s.text)),
      const SizedBox(height: 10),
      Text("VALUE", style: cap),
      Text(v.toStringAsFixed(2),
          key: const ValueKey("trackCurvesValue"),
          style: TextStyle(
              fontSize: 13,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: s.text)),
      const SizedBox(height: 10),
      Text("EASES TO THE NEXT", style: cap),
      Text(k.easing.label, style: TextStyle(fontSize: 12, color: s.text)),
      const SizedBox(height: 12),
      OutlinedButton(
        key: const ValueKey("trackCurvesRest"),
        onPressed: () => _rest(t, pick.$1, k.frame),
        style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            foregroundColor: s.text,
            side: BorderSide(color: s.edge)),
        child: Text(
            _laneColours.containsKey(pick.$1)
                ? "Put $name back to rest"
                : "Take $name out",
            style: const TextStyle(fontSize: 11)),
      ),
    ]);
  }

  /// _curveOf is [k]'s ease as handles: its own, or its easing's nearest.
  static EaseCurve _curveOf(Keyframe k) =>
      k.easing == KeyframeEasing.custom && k.curve != null
          ? k.curve!
          : k.easing.asCurve;

  /// _handlesOn is the two values a line has at [a] and [b], where it
  /// changes between them and so has an ease to shape.
  static (double, double)? _handlesOn(
      Keyframe a, Keyframe b, double? Function(Keyframe) read) {
    var va = read(a), vb = read(b);
    if (va == null || vb == null || (vb - va).abs() < 1e-9) return null;
    if (b.frame <= a.frame) return null;
    return (va, vb);
  }

  /// _key takes the picked keyframe away on Delete or Backspace.
  KeyEventResult _key(KeyframeTarget t, KeyEvent ev) {
    if (ev is! KeyDownEvent) return KeyEventResult.ignored;
    var k = ev.logicalKey;
    if (k != LogicalKeyboardKey.delete && k != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    var p = _pick;
    if (p == null) return KeyEventResult.ignored;
    c.beginInteraction();
    c.removeTargetKeyframes([p.$2]);
    c.endInteraction();
    setState(() => _pick = null);
    return KeyEventResult.handled;
  }

  Map<String, (double, double)> _ranges(ElementTrack track,
      List<(String, String, double? Function(Keyframe))> shown) {
    var out = <String, (double, double)>{};
    for (var (id, _, read) in shown) {
      var lo = double.infinity, hi = -double.infinity;
      for (var i = 0; i <= 120; i++) {
        var f = (_last * i / 120).round();
        var v = _speed ? _rate(track, read, f) : read(track.at(f));
        if (v == null) continue;
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
      if (!lo.isFinite) (lo, hi) = (0, 1);
      if (_speed) lo = 0;
      if (hi - lo < 1e-6) {
        lo -= 1;
        hi += 1;
      }
      var padBy = (hi - lo) * 0.1;
      out[id] = (lo - padBy, hi + padBy);
    }
    return out;
  }

  static double? _rate(
      ElementTrack track, double? Function(Keyframe) read, int f) {
    var a = read(track.between(math.max(0, f - 0.5)));
    var b = read(track.between(f + 0.5));
    if (a == null || b == null) return null;
    return (b - a).abs();
  }

  void _ease(KeyframeEasing e) {
    var p = _pick;
    if (p == null) return;
    c.beginInteraction();
    c.easeTargetKeyframes([p.$2], e);
    c.endInteraction();
    setState(() {});
  }

  void _add(KeyframeTarget t, int f) {
    if (t.track.keyAt(f) != null) return;
    c.beginInteraction();
    c.writeTargetTrack(t.track.withKey(t.track.isEmpty
        ? Keyframe(frame: f)
        : t.track.at(f).copyWith(frame: f)));
    c.endInteraction();
    var first =
        keyframeLanesOf(c.keyframeTarget?.track ?? t.track).firstOrNull?.$1;
    setState(() => _pick = first == null ? null : (first, f));
  }

  void _rest(KeyframeTarget t, String id, int f) {
    var k = t.track.keyAt(f);
    if (k == null) return;
    c.beginInteraction();
    c.writeTargetTrack(t.track.withKey(_rested(k, id)));
    c.endInteraction();
    setState(() => _pick = null);
  }
}

/// _CurvesPainter draws each shown value over the scene, scaled to fit,
/// with a key wherever a keyframe holds it, through the graph's [view].
class _CurvesPainter extends CustomPainter {
  final ElementTrack track;
  final List<(String, String, double? Function(Keyframe))> shown;
  final bool speed;
  final int last;
  final int rate;
  final int playhead;
  final (String, int)? pick;
  final StudioColors studio;
  final Rect area;
  final CurveView view;
  final double Function(num) xOf;
  final double Function(String, double) yOf;
  final List<CurveHandles> handles;
  _CurvesPainter(
      {required this.track,
      required this.shown,
      required this.speed,
      required this.last,
      required this.rate,
      required this.playhead,
      required this.pick,
      required this.studio,
      required this.area,
      required this.view,
      required this.xOf,
      required this.yOf,
      required this.handles});

  @override
  void paint(Canvas canvas, Size size) {
    const top = 24.0;
    double fAt(double x) => view.u(x, area) * last;
    canvas.drawRect(Offset.zero & size, Paint()..color = studio.inset);
    // A mark each tidy step of seconds the zoom leaves room for.
    var step = view.step(last / rate, area.width);
    var first = (fAt(0) / rate / step).floor();
    var lastMark = (fAt(size.width) / rate / step).ceil();
    var grid = Paint()..color = studio.edge.withValues(alpha: 0.5);
    for (var i = math.max(0, first); i <= lastMark; i++) {
      var x = xOf(i * step * rate);
      canvas.drawLine(Offset(x, top), Offset(x, size.height), grid);
    }
    for (var i = 1; i < 4; i++) {
      var y = top + (size.height - top) * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y),
          Paint()..color = studio.edge.withValues(alpha: 0.25));
    }
    for (var (id, _, read) in shown) {
      var colour = _colourOf(id);
      var path = Path();
      var started = false;
      // Read between frames, so a curve is drawn smooth, not in steps.
      for (var x = 0.0; x <= size.width; x += 2) {
        var f = fAt(x);
        if (f < 0 || f > last) continue;
        double? v;
        if (speed) {
          var a = read(track.between(math.max(0, f - 0.5)));
          var b = read(track.between(f + 0.5));
          v = a == null || b == null ? null : (b - a).abs();
        } else {
          v = read(track.between(f));
        }
        if (v == null) continue;
        var y = yOf(id, v);
        started ? path.lineTo(x, y) : path.moveTo(x, y);
        started = true;
      }
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = colour);
      if (speed) continue;
      for (var k in track.keys) {
        var v = read(k);
        if (v == null) continue;
        var at = Offset(xOf(k.frame), yOf(id, v));
        var on = pick == (id, k.frame);
        var r = on ? 5.5 : 4.5;
        var d = Path()
          ..moveTo(at.dx, at.dy - r)
          ..lineTo(at.dx + r, at.dy)
          ..lineTo(at.dx, at.dy + r)
          ..lineTo(at.dx - r, at.dy)
          ..close();
        canvas.drawPath(d, Paint()..color = on ? Colors.white : colour);
        canvas.drawPath(
            d,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = studio.inset);
      }
    }
    paintHandles(canvas, handles);
    // The ruler, and the playhead over everything.
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, top), Paint()..color = studio.strip);
    for (var i = math.max(0, first); i <= lastMark; i++) {
      var secs = i * step;
      var x = xOf(secs * rate);
      canvas.drawLine(
          Offset(x, top - 8), Offset(x, top), Paint()..color = studio.edge);
      var tp = TextPainter(
          text: TextSpan(
              text: secs == secs.roundToDouble()
                  ? "${secs.round()}s"
                  : "${secs.toStringAsFixed(secs * 10 == (secs * 10).roundToDouble() ? 1 : 2)}s",
              style: TextStyle(fontSize: 9, color: studio.muted)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(x + 3, 4));
    }
    paintPlayhead(
        canvas, xOf(playhead.clamp(0, last)), top, size.height, studio.on);
  }

  @override
  bool shouldRepaint(_CurvesPainter old) => true;
}

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
