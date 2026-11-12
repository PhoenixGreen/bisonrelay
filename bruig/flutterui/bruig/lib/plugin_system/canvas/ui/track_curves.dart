import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

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

class _TrackCurvesState extends State<TrackCurves> {
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
      double xOf(num f) => pad + f / _last * (size.width - pad * 2);
      int fOf(double x) => ((x - pad) / (size.width - pad * 2) * _last)
          .round()
          .clamp(0, _last)
          .toInt();
      double yOf(String id, double v) {
        var (lo, hi) = ranges[id] ?? (0.0, 1.0);
        return top + 10 + (1 - (v - lo) / (hi - lo)) * (size.height - top - 30);
      }

      double vOf(String id, double y) {
        var (lo, hi) = ranges[id] ?? (0.0, 1.0);
        return lo + (1 - (y - top - 10) / (size.height - top - 30)) * (hi - lo);
      }

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

      return Listener(
        onPointerDown: (e) {
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
          onDoubleTapDown: (d) => _add(t, fOf(d.localPosition.dx)),
          onDoubleTap: () {},
          onPanStart: (d) {
            var k = keyAt(d.localPosition);
            if (k == null) {
              if (d.localPosition.dy < top) c.frame = fOf(d.localPosition.dx);
              return;
            }
            setState(() {
              _pick = k;
              _dragFrame = k.$2;
              _dragX = d.localPosition.dx - xOf(k.$2);
              _dragRange = ranges;
            });
            c.beginInteraction();
          },
          onPanUpdate: (d) {
            var p = _pick, at = _dragFrame;
            if (p == null || at == null) {
              if (d.localPosition.dy < top) c.frame = fOf(d.localPosition.dx);
              return;
            }
            var now = c.keyframeTarget?.track;
            var k = now?.keyAt(at);
            if (now == null || k == null) return;
            // Up or down: that one value.
            var next =
                now.withKey(_withValue(k, p.$1, vOf(p.$1, d.localPosition.dy)));
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
            if (_dragFrame != null) c.endInteraction();
            setState(() {
              _dragFrame = null;
              _dragRange = null;
            });
          },
          child: CustomPaint(
            size: Size.infinite,
            painter: _CurvesPainter(
              track: t.track,
              shown: shown,
              ranges: ranges,
              speed: _speed,
              last: _last,
              rate: math.max(1, c.document.frameRate),
              playhead: c.frame,
              pick: _pick,
              studio: s,
            ),
          ),
        ),
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
              "to put that value back to rest.",
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
/// with a key wherever a keyframe holds it.
class _CurvesPainter extends CustomPainter {
  final ElementTrack track;
  final List<(String, String, double? Function(Keyframe))> shown;
  final Map<String, (double, double)> ranges;
  final bool speed;
  final int last;
  final int rate;
  final int playhead;
  final (String, int)? pick;
  final StudioColors studio;
  _CurvesPainter(
      {required this.track,
      required this.shown,
      required this.ranges,
      required this.speed,
      required this.last,
      required this.rate,
      required this.playhead,
      required this.pick,
      required this.studio});

  @override
  void paint(Canvas canvas, Size size) {
    const top = 24.0, pad = 12.0;
    double xOf(num f) => pad + f / last * (size.width - pad * 2);
    double yOf(String id, double v) {
      var (lo, hi) = ranges[id] ?? (0.0, 1.0);
      return top + 10 + (1 - (v - lo) / (hi - lo)) * (size.height - top - 30);
    }

    canvas.drawRect(Offset.zero & size, Paint()..color = studio.inset);
    var grid = Paint()..color = studio.edge.withValues(alpha: 0.5);
    for (var s = 0; s * rate <= last; s++) {
      var x = xOf(s * rate);
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
      for (var x = pad; x <= size.width - pad; x += 2) {
        var f = (x - pad) / (size.width - pad * 2) * last;
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
    // The ruler, and the playhead over everything.
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, top), Paint()..color = studio.strip);
    for (var s = 0; s * rate <= last; s++) {
      var x = xOf(s * rate);
      canvas.drawLine(
          Offset(x, top - 8), Offset(x, top), Paint()..color = studio.edge);
      var tp = TextPainter(
          text: TextSpan(
              text: "${s}s",
              style: TextStyle(fontSize: 9, color: studio.muted)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(x + 3, 4));
    }
    var px = xOf(playhead.clamp(0, last));
    canvas.drawLine(
        Offset(px, 0),
        Offset(px, size.height),
        Paint()
          ..color = studio.on
          ..strokeWidth = 2);
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
