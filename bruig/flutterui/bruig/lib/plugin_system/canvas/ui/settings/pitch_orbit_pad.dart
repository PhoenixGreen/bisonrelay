import 'dart:math' as math;

import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// PitchOrbit is the camera an orbit pad moves: degrees of tilt up and down
/// and to the side, degrees of turn, perspective from nought to one, and the
/// zoom (one fits the frame).
typedef PitchOrbit = ({
  double tilt,
  double side,
  double turn,
  double perspective,
  double zoom,
});

/// PitchOrbitPad moves a pitch's camera with one gesture instead of four
/// numbers: drag to go round the pitch and up and down over it, as an orbit
/// does in any 3D program.
///
/// - Drag: left and right turns, up and down tilts.
/// - Shift-drag, or drag with the right button: left and right tilts to the
///   side, up and down is the perspective.
/// - Scroll or pinch: zoom.
/// - Double-click: back to flat, straight down.
///
/// It draws the pitch as the camera sees it, so what the drag is doing can be
/// seen at the size of a thumb as well as on the canvas.
class PitchOrbitPad extends StatefulWidget {
  final PitchOrbit value;
  final VoidCallback onBegin;
  final ValueChanged<PitchOrbit> onChanged;
  final VoidCallback onCommit;
  final double width, height;

  const PitchOrbitPad({
    super.key,
    required this.value,
    required this.onBegin,
    required this.onChanged,
    required this.onCommit,
    this.width = 220,
    this.height = 120,
  });

  /// flat is straight down, as double-click puts it.
  static PitchOrbit flat(PitchOrbit v) =>
      (tilt: 0, side: 0, turn: 0, perspective: 0, zoom: v.zoom);

  @override
  State<PitchOrbitPad> createState() => _PitchOrbitPadState();
}

class _PitchOrbitPadState extends State<PitchOrbitPad> {
  late PitchOrbit _v = widget.value;
  bool _dragging = false;
  bool _secondary = false;
  bool _hover = false;

  @override
  void didUpdateWidget(PitchOrbitPad old) {
    super.didUpdateWidget(old);
    if (!_dragging) _v = widget.value;
  }

  void _send(PitchOrbit next) {
    setState(() => _v = next);
    widget.onChanged(next);
  }

  static double _wrap(double turn) {
    var t = (turn + 180) % 360;
    if (t < 0) t += 360;
    return t - 180;
  }

  void _drag(Offset delta) {
    var alt = _secondary || HardwareKeyboard.instance.isShiftPressed;
    if (alt) {
      _send((
        tilt: _v.tilt,
        side: (_v.side + delta.dx * 0.4).clamp(-60.0, 60.0),
        turn: _v.turn,
        perspective: (_v.perspective - delta.dy * 0.01).clamp(0.0, 1.0),
        zoom: _v.zoom,
      ));
    } else {
      _send((
        tilt: (_v.tilt - delta.dy * 0.5).clamp(0.0, 80.0),
        side: _v.side,
        turn: _wrap(_v.turn + delta.dx * 0.8),
        perspective: _v.perspective,
        zoom: _v.zoom,
      ));
    }
  }

  void _zoomBy(double factor) {
    widget.onBegin();
    _send((
      tilt: _v.tilt,
      side: _v.side,
      turn: _v.turn,
      perspective: _v.perspective,
      zoom: (_v.zoom * factor).clamp(0.1, 5.0),
    ));
    widget.onCommit();
  }

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    return MouseRegion(
      cursor: _dragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        onPointerDown: (e) => _secondary = e.buttons == kSecondaryMouseButton,
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) {
            _zoomBy(math.pow(1.0015, -e.scrollDelta.dy).toDouble());
          }
        },
        onPointerPanZoomUpdate: (e) {
          if (e.scale != 1) _zoomBy(1 + (e.scale - 1) * 0.1);
        },
        child: GestureDetector(
          key: const ValueKey("pitchOrbitPad"),
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) {
            _dragging = true;
            widget.onBegin();
          },
          onPanUpdate: (d) => _drag(d.delta),
          onPanEnd: (_) {
            _dragging = false;
            _secondary = false;
            widget.onCommit();
          },
          onPanCancel: () {
            _dragging = false;
            _secondary = false;
          },
          onDoubleTap: () {
            widget.onBegin();
            _send(PitchOrbitPad.flat(_v));
            widget.onCommit();
          },
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: _hover || _dragging
                      ? colors.primary
                      : colors.outlineVariant),
            ),
            child: CustomPaint(
              painter: _OrbitPainter(
                _v,
                line: colors.onSurface,
                fill: colors.primary,
                faint: colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// _OrbitPainter draws a pitch as the camera sees it, and the camera's
/// numbers along the bottom.
class _OrbitPainter extends CustomPainter {
  final PitchOrbit v;
  final Color line, fill, faint;
  _OrbitPainter(this.v,
      {required this.line, required this.fill, required this.faint});

  @override
  void paint(Canvas canvas, Size size) {
    var turn = v.turn * math.pi / 180;
    var tilt = v.tilt * math.pi / 180;
    var side = v.side * math.pi / 180;
    var reach = 1.0;
    var distance =
        v.perspective <= 0 ? 0.0 : reach * (1 + (1 - v.perspective) * 6);

    // A pitch 105 by 68, as fractions of its length.
    Offset project(double x, double y) {
      var c = math.cos(turn), s = math.sin(turn);
      var gx = x * c - y * s, gy = x * s + y * c;
      var sy = gy * math.cos(tilt);
      var depth = gy * math.sin(tilt);
      var k = distance <= 0 ? 1.0 : distance / (distance + depth);
      var p = Offset(gx * k, -sy * k);
      var cs = math.cos(side), sn = math.sin(side);
      return Offset(p.dx * cs - p.dy * sn, p.dx * sn + p.dy * cs);
    }

    var area = Rect.fromLTWH(0, 0, size.width, size.height - 16);
    var outline = [
      for (var (x, y) in [
        (-0.5, -0.324),
        (0.5, -0.324),
        (0.5, 0.324),
        (-0.5, 0.324)
      ])
        project(x, y),
    ];
    var bounds = outline.skip(1).fold(Rect.fromPoints(outline[0], outline[0]),
        (Rect r, p) => r.expandToInclude(Rect.fromPoints(p, p)));
    var scale = math.min(area.width * 0.78 / math.max(bounds.width, 0.01),
        area.height * 0.78 / math.max(bounds.height, 0.01));
    Offset place(Offset p) => area.center + (p - bounds.center) * scale;

    var path = Path()..addPolygon([for (var p in outline) place(p)], true);
    canvas.drawPath(path, Paint()..color = fill.withValues(alpha: 0.18));
    var pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = line.withValues(alpha: 0.85);
    canvas.drawPath(path, pen);
    canvas.drawLine(place(project(0, -0.324)), place(project(0, 0.324)), pen);
    var circle = Path();
    for (var i = 0; i <= 24; i++) {
      var a = i / 24 * math.pi * 2;
      var p = place(project(math.cos(a) * 0.087, math.sin(a) * 0.087));
      i == 0 ? circle.moveTo(p.dx, p.dy) : circle.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(circle, pen);
    // The near touchline, so which way round it is can be told.
    canvas.drawLine(
        place(outline[0]),
        place(outline[1]),
        pen
          ..color = fill
          ..strokeWidth = 2.4);

    var tp = TextPainter(
      text: TextSpan(
          text: "Turn ${v.turn.round()}°  Tilt ${v.tilt.round()}°  "
              "Side ${v.side.round()}°  Lens ${(v.perspective * 100).round()}%",
          style: TextStyle(fontSize: 9.5, color: faint)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: "…",
    )..layout(maxWidth: size.width - 8);
    tp.paint(canvas, Offset((size.width - tp.width) / 2, size.height - 14));
  }

  @override
  bool shouldRepaint(_OrbitPainter old) =>
      old.v != v || old.line != line || old.fill != fill;
}
