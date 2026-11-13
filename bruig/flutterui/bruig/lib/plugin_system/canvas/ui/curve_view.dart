import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// curve_view.dart is what the two Curves editors share (Ken, 2026-11-14):
// the clip's (motion_curves.dart) and an element's own keyframes'
// (track_curves.dart). How far in on time and values they look, moved by
// pinch, swipe and scroll; the playhead's cap; and an ease's handles.
//
// Time is a share of the whole the editor shows when fitted (0..1 across);
// a value is a share of its line's range (0 at the foot, 1 at the top), so
// one view moves every line together.

/// CurveView is how far in, and where, a Curves graph is looking.
class CurveView {
  /// from is the share of the whole at the left edge; zoom how many times
  /// closer than the whole.
  double from = 0;
  double zoom = 1;

  /// vMid is the value share at the graph's middle; vZoom how many times
  /// closer than the lines' ranges -- below one, room past them, to see an
  /// overshoot.
  double vMid = 0.5;
  double vZoom = 1;

  static const double most = 64;
  static const double least = 0.25;

  bool get fitted => zoom == 1 && from == 0 && vMid == 0.5 && vZoom == 1;

  double x(double u, Rect a) => a.left + (u - from) * zoom * a.width;
  double u(double x, Rect a) => from + (x - a.left) / a.width / zoom;
  double y(double n, Rect a) => a.top + (0.5 - (n - vMid) * vZoom) * a.height;
  double n(double y, Rect a) => vMid + (0.5 - (y - a.top) / a.height) / vZoom;

  /// zoomTime closes in by [factor], keeping the moment under [atX] there.
  void zoomTime(double factor, double atX, Rect a) {
    if (!factor.isFinite || factor <= 0 || a.width <= 0) return;
    var at = u(atX, a);
    zoom = (zoom * factor).clamp(1.0, most).toDouble();
    from = (at - (atX - a.left) / a.width / zoom)
        .clamp(0.0, math.max(0.0, 1 - 1 / zoom))
        .toDouble();
  }

  /// panTime moves the view [dx] px, as a finger drags it.
  void panTime(double dx, Rect a) {
    if (a.width <= 0) return;
    from = (from - dx / a.width / zoom)
        .clamp(0.0, math.max(0.0, 1 - 1 / zoom))
        .toDouble();
  }

  /// zoomValues closes in on the values by [factor] about [atY].
  void zoomValues(double factor, double atY, Rect a) {
    if (!factor.isFinite || factor <= 0 || a.height <= 0) return;
    var at = n(atY, a);
    vZoom = (vZoom * factor).clamp(least, most).toDouble();
    vMid = at - (0.5 - (atY - a.top) / a.height) / vZoom;
  }

  /// panValues moves the values [dy] px, as a finger drags them.
  void panValues(double dy, Rect a) {
    if (a.height <= 0) return;
    vMid += dy / a.height / vZoom;
  }

  void fit() {
    from = 0;
    zoom = 1;
    vMid = 0.5;
    vZoom = 1;
  }

  /// step is a tidy gap between the ruler's marks, in the units [whole]
  /// spans, for about one mark each 70 px of [width].
  double step(double whole, double width) {
    var shown = whole / zoom;
    var want = shown / math.max(1, width / 70);
    for (var s in const [
      1 / 24, 0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 15.0, 30.0, 60.0, //
    ]) {
      if (s >= want) return s;
    }
    return 120;
  }
}

/// CurveViewing is a Curves editor's view, moved by the pointer: a pinch
/// or ⌘-scroll closes in on time, with ⌥ on the values instead; a
/// two-finger swipe, or a scroll, moves along time and up and down the
/// values; a double-click on the ruler shows it all again.
mixin CurveViewing<T extends StatefulWidget> on State<T> {
  final CurveView view = CurveView();

  /// graphArea is where the lines are drawn, set as the graph is laid out.
  Rect graphArea = Rect.zero;
  double _pinched = 1;

  static bool get _alt => HardwareKeyboard.instance.isAltPressed;

  Widget curveGestures(Widget child) => Listener(
        onPointerSignal: _signal,
        onPointerPanZoomStart: (_) => _pinched = 1,
        onPointerPanZoomUpdate: _panZoom,
        child: child,
      );

  void _signal(PointerSignalEvent ev) {
    var a = graphArea;
    if (ev is PointerScaleEvent) {
      GestureBinding.instance.pointerSignalResolver.register(
          ev,
          (_) => setState(() => _alt
              ? view.zoomValues(ev.scale, ev.localPosition.dy, a)
              : view.zoomTime(ev.scale, ev.localPosition.dx, a)));
      return;
    }
    if (ev is! PointerScrollEvent) return;
    var keys = HardwareKeyboard.instance;
    var d = ev.scrollDelta;
    GestureBinding.instance.pointerSignalResolver.register(ev, (_) {
      setState(() {
        if (keys.isMetaPressed || keys.isControlPressed) {
          var f = math.exp(-(d.dy == 0 ? d.dx : d.dy) / 240);
          _alt
              ? view.zoomValues(f, ev.localPosition.dy, a)
              : view.zoomTime(f, ev.localPosition.dx, a);
        } else if (keys.isShiftPressed) {
          view.panTime(-(d.dx != 0 ? d.dx : d.dy), a);
        } else {
          view.panTime(-d.dx, a);
          view.panValues(-d.dy, a);
        }
      });
    });
  }

  void _panZoom(PointerPanZoomUpdateEvent ev) {
    var a = graphArea;
    setState(() {
      if (ev.scale != _pinched) {
        var f = ev.scale / _pinched;
        _alt
            ? view.zoomValues(f, ev.localPosition.dy, a)
            : view.zoomTime(f, ev.localPosition.dx, a);
        _pinched = ev.scale;
      }
      view.panTime(ev.panDelta.dx, a);
      view.panValues(ev.panDelta.dy, a);
    });
  }
}

/// curvesShowHandles is whether the Curves draw each ease's handles: kept
/// for the session, as the Keys strip's switch is.
bool curvesShowHandles = false;

/// CurveHandles are one ease's handles drawn on one line: from the key it
/// leaves ([p0]) to the key it reaches ([p1]), through [h1] and [h2].
class CurveHandles {
  final Offset p0, h1, h2, p1;
  final Color colour;

  /// key says whose ease it is, for the editor; lane which line it is on.
  final Object key;
  final String lane;
  const CurveHandles(
      this.p0, this.h1, this.h2, this.p1, this.colour, this.key, this.lane);

  /// at is which handle [point] is on, 1 or 2, or null.
  int? at(Offset point, {double reach = 8}) {
    if ((h1 - point).distance <= reach) return 1;
    if ((h2 - point).distance <= reach) return 2;
    return null;
  }
}

/// handlesOf is [curve]'s handles between two keys on a line, in the
/// graph's own space, given each end's place there.
(Offset, Offset) handlesOf(EaseCurve curve, Offset p0, Offset p1) => (
      Offset(p0.dx + curve.x1 * (p1.dx - p0.dx),
          p0.dy + curve.y1 * (p1.dy - p0.dy)),
      Offset(p0.dx + curve.x2 * (p1.dx - p0.dx),
          p0.dy + curve.y2 * (p1.dy - p0.dy)),
    );

/// curveDragged is [curve] with handle [which] moved to [point], given the
/// two keys' places: across stays between them, up and down is free.
EaseCurve curveDragged(
    EaseCurve curve, int which, Offset point, Offset p0, Offset p1) {
  var dx = p1.dx - p0.dx, dy = p1.dy - p0.dy;
  var x = dx.abs() < 1e-9 ? 0.5 : (point.dx - p0.dx) / dx;
  var y = dy.abs() < 1e-9 ? 0.5 : (point.dy - p0.dy) / dy;
  double tidy(double v) => (v * 1000).round() / 1000;
  return which == 1
      ? curve.copyWith(x1: tidy(x), y1: tidy(y))
      : curve.copyWith(x2: tidy(x), y2: tidy(y));
}

/// paintHandles draws [handles]: a line from each key to its handle and a
/// round knob on its end.
void paintHandles(Canvas canvas, List<CurveHandles> handles) {
  for (var h in handles) {
    var line = Paint()
      ..strokeWidth = 1
      ..color = h.colour.withValues(alpha: 0.75);
    canvas.drawLine(h.p0, h.h1, line);
    canvas.drawLine(h.p1, h.h2, line);
    for (var k in [h.h1, h.h2]) {
      canvas.drawCircle(k, 4, Paint()..color = const Color(0xFF15171C));
      canvas.drawCircle(
          k,
          4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = h.colour);
    }
  }
}

/// paintPlayhead draws the playhead at [x]: a line down the graph and a
/// cap in the ruler, [ruler] tall, to take hold of.
void paintPlayhead(
    Canvas canvas, double x, double ruler, double height, Color colour) {
  var paint = Paint()..color = colour;
  canvas.drawRect(Rect.fromLTWH(x - 0.75, 0, 1.5, height), paint);
  var cap = Path()
    ..moveTo(x - 6, 2)
    ..lineTo(x + 6, 2)
    ..lineTo(x + 6, ruler - 8)
    ..lineTo(x, ruler - 2)
    ..lineTo(x - 6, ruler - 8)
    ..close();
  canvas.drawPath(cap, paint);
}

/// nearPlayhead is whether a press at [point] takes hold of a playhead at
/// [x]: on its cap in the ruler, or on its line.
bool nearPlayhead(Offset point, double? x, double ruler) =>
    x != null && (point.dx - x).abs() <= (point.dy < ruler ? 8 : 5);
