import 'dart:math' as math;

import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

// orbit_pad.dart is a round button that is dragged to go round something:
// across to swing round it, up and down to go over or under it. The one
// control for orbiting a character in its own box and a stage's camera,
// so both are taken hold of the same way.

/// CanvasOrbitPad turns [turn] and [tilt], in degrees, as it is dragged:
/// across for the turn, down to look from above. A double click goes back
/// to straight on.
class CanvasOrbitPad extends StatefulWidget {
  final double turn;
  final double tilt;

  /// minTilt and maxTilt are how far over and under it goes.
  final double minTilt, maxTilt;

  /// onChanged is each step of a drag; onStart and onEnd its two ends, for
  /// an undo step round the whole of it.
  final void Function(double turn, double tilt) onChanged;
  final VoidCallback? onStart;
  final VoidCallback? onEnd;

  /// rest is where a double click puts it.
  final (double, double) rest;
  final String tooltip;

  const CanvasOrbitPad({
    required this.turn,
    required this.tilt,
    required this.onChanged,
    this.onStart,
    this.onEnd,
    this.minTilt = -85,
    this.maxTilt = 85,
    this.rest = (0, 0),
    this.tooltip = "Drag to orbit: across to go round, up and down to go "
        "over and under. Double click to face it again.",
    super.key,
  });

  /// degreesPerPixel is how far a pixel of drag turns.
  static const double degreesPerPixel = 0.8;

  @override
  State<CanvasOrbitPad> createState() => _CanvasOrbitPadState();
}

class _CanvasOrbitPadState extends State<CanvasOrbitPad> {
  late double _turn, _tilt;
  bool _held = false;

  @override
  void initState() {
    super.initState();
    _turn = widget.turn;
    _tilt = widget.tilt;
  }

  @override
  void didUpdateWidget(CanvasOrbitPad old) {
    super.didUpdateWidget(old);
    if (!_held) {
      _turn = widget.turn;
      _tilt = widget.tilt;
    }
  }

  static double _wrap(double d) {
    var w = (d + 180) % 360;
    if (w < 0) w += 360;
    return w - 180;
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var c = theme.colors;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: _held ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
        child: GestureDetector(
          // From where it was pressed, so the first stretch of a drag --
          // before it is known to be one -- turns it too.
          dragStartBehavior: DragStartBehavior.down,
          onDoubleTap: () {
            widget.onStart?.call();
            widget.onChanged(widget.rest.$1, widget.rest.$2);
            widget.onEnd?.call();
          },
          onPanStart: (_) {
            setState(() => _held = true);
            _turn = widget.turn;
            _tilt = widget.tilt;
            widget.onStart?.call();
          },
          onPanUpdate: (d) {
            _turn = _wrap(_turn + d.delta.dx * CanvasOrbitPad.degreesPerPixel);
            _tilt = (_tilt + d.delta.dy * CanvasOrbitPad.degreesPerPixel)
                .clamp(widget.minTilt, widget.maxTilt);
            widget.onChanged(
                (_turn * 10).roundToDouble() / 10, (_tilt * 10).roundToDouble() / 10);
          },
          onPanEnd: (_) {
            setState(() => _held = false);
            widget.onEnd?.call();
          },
          onPanCancel: () {
            if (!_held) return;
            setState(() => _held = false);
            widget.onEnd?.call();
          },
          child: SizedBox(
            width: 56,
            height: 56,
            child: CustomPaint(
              painter: _OrbitPainter(
                  _held ? _turn : widget.turn,
                  _held ? _tilt : widget.tilt,
                  ring: _held ? c.primary : c.outlineVariant,
                  fill: c.surfaceContainerHigh,
                  line: c.onSurfaceVariant,
                  mark: c.primary),
            ),
          ),
        ),
      ),
    );
  }
}

/// _OrbitPainter draws a globe turned as the orbit is: its lines of
/// longitude swing with the turn and its equator tips with the tilt, and a
/// dot is where it is seen from.
class _OrbitPainter extends CustomPainter {
  final double turn, tilt;
  final Color ring, fill, line, mark;
  _OrbitPainter(this.turn, this.tilt,
      {required this.ring,
      required this.fill,
      required this.line,
      required this.mark});

  @override
  void paint(Canvas canvas, Size size) {
    var c = size.center(Offset.zero);
    var r = size.shortestSide / 2 - 2;
    canvas.drawCircle(c, r, Paint()..color = fill);
    var stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = line.withValues(alpha: 0.55);
    var t = turn * math.pi / 180, k = tilt * math.pi / 180;
    // Meridians: ellipses whose width is how side-on each is.
    for (var m = 0; m < 3; m++) {
      var a = t + m * math.pi / 3;
      var w = (r * math.cos(a)).abs();
      canvas.drawOval(
          Rect.fromCenter(center: c, width: w * 2, height: r * 2), stroke);
    }
    // The equator, flattened by the tilt and dropped by it.
    var eh = (r * math.sin(k)).abs();
    canvas.drawOval(
        Rect.fromCenter(
            center: c + Offset(0, r * 0.0), width: r * 2, height: eh * 2 + 0.5),
        stroke);
    // Where it is seen from: on the near face, moved by the turn and tilt.
    var dot = c + Offset(-math.sin(t) * r * 0.7 * math.cos(k), math.sin(k) * r * 0.7);
    canvas.drawCircle(dot, 3.5, Paint()..color = mark);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = ring);
  }

  @override
  bool shouldRepaint(_OrbitPainter old) =>
      old.turn != turn ||
      old.tilt != tilt ||
      old.ring != ring ||
      old.fill != fill;
}
