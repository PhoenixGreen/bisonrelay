import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_painter.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// garment_shape_editor.dart edits a garment's own outline -- see
// Garment.outline -- on the character itself, drawn large: its points are
// dragged, an edge clicked to put a point in it, a point double clicked to
// take it out. The outline is kept in the body's terms, so what is drawn
// here goes with the body however it later stands or turns.

/// GarmentShapeEditor edits [outline], drawn on [dna] -- which is wearing
/// the garment -- in [style].
class GarmentShapeEditor extends StatefulWidget {
  final CharacterDna dna;
  final CharacterStyle style;
  final List<Offset> outline;
  final CanvasImageSource? images;

  /// onChanged is the outline as it changes; onStart and onEnd the two
  /// ends of a drag, for one undo step round it.
  final void Function(List<Offset> outline) onChanged;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  const GarmentShapeEditor({
    required this.dna,
    required this.style,
    required this.outline,
    required this.onChanged,
    required this.onStart,
    required this.onEnd,
    this.images,
    super.key,
  });

  static const Size size = Size(240, 220);

  @override
  State<GarmentShapeEditor> createState() => GarmentShapeEditorState();
}

/// _Frame is where the body's chest and hips are in the editor, and how
/// wide it is at each: what the outline's points are measured against.
class _Frame {
  final Rect figure;
  final Offset chest, hips;
  final double half, low;
  const _Frame(this.figure, this.chest, this.hips, this.half, this.low);

  factory _Frame.of(CharacterDna dna, CharacterStyle style) {
    var drawn = style.dnaOf(dna);
    // Sized so the chest to the hips is four tenths of the editor's
    // height, a third of the way down.
    var probe = CharacterRig.of(
        drawn, CharacterElement.restPose, const Rect.fromLTWH(0, 0, 500, 1000));
    var torso = (probe.hips.dy - probe.chest.dy) / 1000;
    var h = GarmentShapeEditor.size.height * 0.4 / math.max(0.01, torso);
    var top = GarmentShapeEditor.size.height * 0.3 - probe.chest.dy / 1000 * h;
    var figure = Rect.fromLTWH(
        GarmentShapeEditor.size.width / 2 - h * 0.25, top, h * 0.5, h);
    var rig = CharacterRig.of(drawn, CharacterElement.restPose, figure);
    return _Frame(figure, rig.chest, rig.hips, rig.shoulderHalf,
        rig.hipHalf * 1.12);
  }

  double _width(double down) => half + (low - half) * down.clamp(0.0, 1.0);

  Offset toEditor(Offset p) =>
      Offset.lerp(chest, hips, p.dy)! + Offset(_width(p.dy) * p.dx, 0);

  Offset toOutline(Offset at) {
    var down = (at.dy - chest.dy) / math.max(1, hips.dy - chest.dy);
    var across = (at.dx - Offset.lerp(chest, hips, down)!.dx) / _width(down);
    return Offset(across.clamp(-3.0, 3.0), down.clamp(-1.0, 3.0));
  }
}

class GarmentShapeEditorState extends State<GarmentShapeEditor> {
  /// _held is the point being dragged, or -1.
  int _held = -1;
  Offset _doubleAt = Offset.zero;

  static const double _reach = 9;

  _Frame get _frame => _Frame.of(widget.dna, widget.style);

  int _pointNear(Offset at) {
    var f = _frame;
    var best = -1;
    var nearest = _reach;
    for (var (i, p) in widget.outline.indexed) {
      var d = (f.toEditor(p) - at).distance;
      if (d <= nearest) {
        nearest = d;
        best = i;
      }
    }
    return best;
  }

  /// _insertAt puts a point at [at], in the edge it is nearest -- or, with
  /// fewer than three points, at the end.
  void _insertAt(Offset at) {
    var f = _frame;
    var pts = widget.outline;
    var next = [...pts];
    var point = f.toOutline(at);
    if (pts.length < 3) {
      next.add(point);
    } else {
      var best = 0;
      var nearest = double.infinity;
      for (var i = 0; i < pts.length; i++) {
        var a = f.toEditor(pts[i]), b = f.toEditor(pts[(i + 1) % pts.length]);
        var d = _toSegment(at, a, b);
        if (d < nearest) {
          nearest = d;
          best = i;
        }
      }
      next.insert(best + 1, point);
    }
    widget.onStart();
    widget.onChanged(next);
    widget.onEnd();
  }

  static double _toSegment(Offset p, Offset a, Offset b) {
    var ab = b - a;
    var len = ab.distanceSquared;
    if (len == 0) return (p - a).distance;
    var t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var f = _frame;
    return MouseRegion(
      cursor: _held >= 0 ? SystemMouseCursors.grabbing : SystemMouseCursors.precise,
      child: GestureDetector(
        onTapUp: (d) {
          if (_pointNear(d.localPosition) < 0) _insertAt(d.localPosition);
        },
        onDoubleTapDown: (d) => _doubleAt = d.localPosition,
        onDoubleTap: () {
          var i = _pointNear(_doubleAt);
          if (i < 0) return;
          widget.onStart();
          widget.onChanged([...widget.outline]..removeAt(i));
          widget.onEnd();
        },
        onPanStart: (d) {
          var i = _pointNear(d.localPosition);
          if (i < 0) return;
          setState(() => _held = i);
          widget.onStart();
        },
        onPanUpdate: (d) {
          if (_held < 0 || _held >= widget.outline.length) return;
          var next = [...widget.outline];
          next[_held] = f.toOutline(d.localPosition);
          widget.onChanged(next);
        },
        onPanEnd: (_) {
          if (_held < 0) return;
          setState(() => _held = -1);
          widget.onEnd();
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: GarmentShapeEditor.size.width,
            height: GarmentShapeEditor.size.height,
            color: theme.colors.surfaceContainerHighest,
            child: CustomPaint(
              painter: _EditorPainter(
                widget.dna,
                widget.style,
                widget.outline,
                f,
                widget.images,
                held: _held,
                line: theme.colors.primary,
                handle: theme.colors.surface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditorPainter extends CustomPainter {
  final CharacterDna dna;
  final CharacterStyle style;
  final List<Offset> outline;
  final _Frame frame;
  final CanvasImageSource? images;
  final int held;
  final Color line, handle;

  _EditorPainter(this.dna, this.style, this.outline, this.frame, this.images,
      {required this.held, required this.line, required this.handle});

  @override
  void paint(Canvas canvas, Size size) {
    paintCharacterFigure(
        canvas, frame.figure, dna, CharacterElement.restPose,
        style: style, images: images);
    if (outline.isEmpty) return;
    var pts = [for (var p in outline) frame.toEditor(p)];
    var stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = line.withValues(alpha: 0.8);
    canvas.drawPath(Path()..addPolygon(pts, pts.length >= 3), stroke);
    for (var (i, p) in pts.indexed) {
      canvas.drawCircle(p, i == held ? 5.5 : 4.5, Paint()..color = handle);
      canvas.drawCircle(
          p,
          i == held ? 5.5 : 4.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = line);
    }
  }

  @override
  bool shouldRepaint(_EditorPainter old) =>
      old.outline != outline ||
      old.held != held ||
      !identical(old.dna, dna) ||
      old.style != style;
}
