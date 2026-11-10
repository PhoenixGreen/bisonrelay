import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/ui/row_header.dart'
    show motionColour;
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:flutter/material.dart';

// slot_face.dart is a slot's look, one design everywhere the slots are --
// the mixer, the Slots panel, beside the timeline's rows (the approved
// design, 2026-11-08): a motion slot is cut-cornered, edged in the motion's
// teal, and draws its move; a sound slot is round-cornered and draws its
// wave, or its notes. Each has a launch strip on its left, a darker band
// with the play mark, its name, and on a tall slot how long it is. An empty
// slot is a dark well with a small square. What a slot does when pressed,
// dragged or right-clicked stays with the slot that draws this.

/// SlotSide is which part of a row's slot this is: its motion, or its
/// sound.
enum SlotSide { motion, sound }

/// slotInk is the writing on a filled slot: dark on its colour.
const slotInk = Color(0xFF10101A);

/// slotPlayingInk is the play mark of a slot playing.
const slotPlayingInk = Color(0xFF9BF0A6);

/// soundSlotColour is a sound slot's colour by what the channel is, as the
/// prototype has them: an instrument's notes amber, speech pink, an
/// element's own sound its element's colour toward blue, any other sound
/// blue.
Color soundSlotColour({bool midi = false, bool speech = false, Color? own}) {
  if (midi) return const Color(0xFFD9A15A);
  if (speech) return const Color(0xFFD77AA3);
  if (own != null) return Color.lerp(own, const Color(0xFF8FB8EC), 0.45)!;
  return const Color(0xFF6FA3E0);
}

/// SlotFace is one part of a slot: [side]'s shape, [colour] (null for an
/// empty slot), the launch strip with [go] in it, [label] beside it, a
/// faint picture of what it is drawn from [seed] (its notes where [midi])
/// and, tall enough, [meta] -- how long it is. [playing] darkens the launch
/// strip; [progress] runs along its foot while it plays.
class SlotFace extends StatelessWidget {
  final SlotSide side;
  final Color? colour;
  final Widget? go;
  final Widget? label;
  final String seed;
  final bool midi;
  final String? meta;
  final bool playing;
  final double? progress;

  /// empty is what an empty slot shows in place of its square: armed to
  /// record, for one.
  final Widget? empty;

  const SlotFace({
    super.key,
    required this.side,
    this.colour,
    this.go,
    this.label,
    this.seed = "",
    this.midi = false,
    this.meta,
    this.playing = false,
    this.progress,
    this.empty,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        var h = box.maxHeight.isFinite ? box.maxHeight : 18.0;
        var motion = side == SlotSide.motion;
        var shape = motion
            ? const _CutCorners(5)
            : RoundedRectangleBorder(borderRadius: BorderRadius.circular(4));
        if (colour == null) {
          // A dark well in the studio palette (or the theme's, as chosen).
          var studio = StudioColors.of(context);
          return DecoratedBox(
            decoration: ShapeDecoration(
              color: studio.inset,
              shape: motion
                  ? shape
                  : RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                      side: BorderSide(color: studio.edge)),
            ),
            child: Row(children: [
              const SizedBox(width: 6),
              empty ??
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: studio.edge,
                        borderRadius: BorderRadius.circular(1)),
                  ),
              const Spacer(),
            ]),
          );
        }
        var fill = motion
            ? Color.lerp(colour, const Color(0xFF0E2A24), 0.22)!
            : colour!;
        var tall = h >= 30;
        var short = h < 13;
        return ClipPath(
          clipper: ShapeBorderClipper(shape: shape),
          child: ColoredBox(
            color: fill,
            child: Stack(children: [
              // A faint picture of it: the move, the wave or the notes.
              if (h >= 16)
                Positioned(
                  right: 2,
                  top: tall ? h * 0.34 : 2,
                  bottom: 2,
                  width: box.maxWidth * (tall ? 0.58 : 0.46),
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 0.45,
                      child: CustomPaint(
                          painter: _SlotArt(side, seed, midi: midi)),
                    ),
                  ),
                ),
              Positioned.fill(
                child: Row(
                    crossAxisAlignment: tall
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.center,
                    children: [
                      // The launch strip, darker, with its play mark.
                      SizedBox(
                        width: 16,
                        height: h,
                        child: ColoredBox(
                          color: playing
                              ? const Color(0x66000000)
                              : const Color(0x33000000),
                          child: Center(child: go),
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (!short && label != null)
                        Expanded(
                          child: DefaultTextStyle.merge(
                            style: TextStyle(
                                fontSize: tall ? 11 : 10.5,
                                fontWeight: FontWeight.w500,
                                color: slotInk),
                            // Tall, the name along the top, its length
                            // along the foot.
                            child: tall
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: SizedBox(height: 16, child: label),
                                  )
                                : label!,
                          ),
                        )
                      else
                        const Spacer(),
                    ]),
              ),
              // A motion slot's edge, in the motion's teal.
              if (motion)
                const Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 3,
                    child: ColoredBox(color: motionColour)),
              // Its length, where there is room under its name.
              if (h >= 38 && meta != null)
                Positioned(
                  left: 22,
                  bottom: 4,
                  child: Opacity(
                    opacity: 0.72,
                    child: Text(meta!,
                        maxLines: 1,
                        style: const TextStyle(
                            fontSize: 9.5,
                            fontFeatures: [FontFeature.tabularFigures()],
                            color: slotInk)),
                  ),
                ),
              if (progress case var p?)
                Positioned(
                  left: 16,
                  right: 0,
                  bottom: 0,
                  height: 2,
                  child: ColoredBox(
                    color: const Color(0x55000000),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: p.clamp(0.0, 1.0),
                      child: const ColoredBox(color: Color(0xCCFFFFFF)),
                    ),
                  ),
                ),
            ]),
          ),
        );
      });
}

/// _CutCorners is a motion slot's shape: its top-left and bottom-right
/// corners cut.
class _CutCorners extends OutlinedBorder {
  final double cut;
  const _CutCorners(this.cut);

  Path _path(Rect r) => cutCornersPath(r, cut);

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => _CutCorners(cut * t);

  @override
  _CutCorners copyWith({BorderSide? side}) => _CutCorners(cut);
}

/// _SlotArt is the faint picture on a filled slot, the same for the same
/// [seed] every time: a motion's curve, a sound's wave, or an instrument's
/// notes.
class _SlotArt extends CustomPainter {
  final SlotSide side;
  final String seed;
  final bool midi;
  _SlotArt(this.side, this.seed, {this.midi = false});

  @override
  void paint(Canvas canvas, Size size) =>
      paintSlotArt(canvas, Offset.zero & size, side, seed, midi: midi);

  @override
  bool shouldRepaint(_SlotArt old) =>
      old.side != side || old.seed != seed || old.midi != midi;
}

/// cutCornersPath is a motion slot's or clip's shape in [r]: its top-left
/// and bottom-right corners cut by [cut].
Path cutCornersPath(Rect r, double cut) {
  var c = math.min(cut, math.min(r.width, r.height) / 2);
  return Path()
    ..moveTo(r.left + c, r.top)
    ..lineTo(r.right, r.top)
    ..lineTo(r.right, r.bottom - c)
    ..lineTo(r.right - c, r.bottom)
    ..lineTo(r.left, r.bottom)
    ..lineTo(r.left, r.top + c)
    ..close();
}

/// paintSlotArt draws a slot's faint picture into [rect], the same for the
/// same [seed] every time: a motion's curve, a sound's wave, an
/// instrument's notes. [opacity] fades it, as the timeline's clips have it.
void paintSlotArt(Canvas canvas, Rect rect, SlotSide side, String seed,
    {bool midi = false, double opacity = 1}) {
  var w = rect.width, h = rect.height;
  if (w <= 2 || h <= 2) return;
  Color ink(int argb) {
    var c = Color(argb);
    return c.withValues(alpha: c.a * opacity);
  }

  canvas.save();
  canvas.translate(rect.left, rect.top);
  var r = math.Random(seed.hashCode);
  if (side == SlotSide.motion) {
    var path = Path()..moveTo(0, h * 0.6);
    var step = math.max(14.0, w / 10);
    for (var x = step; x <= w + step; x += step) {
      path.quadraticBezierTo(x - step / 2, h * (0.15 + r.nextDouble() * 0.7), x,
          h * (0.25 + r.nextDouble() * 0.5));
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = ink(0xFF08201A));
  } else if (midi) {
    var note = Paint()..color = ink(0xFF2A1604);
    for (var x = 4.0; x < w; x += 9 + r.nextDouble() * 6) {
      var y = 2 + (r.nextInt(5) * 0.18 * h);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(x, math.min(y, h - 3), 5 + r.nextDouble() * 6, 2.6),
              const Radius.circular(1)),
          note);
    }
  } else {
    var line = Paint()
      ..color = ink(0xFF0A1A30)
      ..strokeWidth = 1;
    var mid = h / 2;
    for (var x = 1.0; x < w; x += 2) {
      var a = (0.15 + r.nextDouble() * 0.35 + (math.sin(x / 23)).abs() * 0.3) *
          h /
          2;
      canvas.drawLine(Offset(x, mid - a), Offset(x, mid + a), line);
    }
  }
  canvas.restore();
}

/// paintLinkMark draws the link mark on a clip linked to another, at [at]
/// (its top-left), in [colour]: the link icon, as a glyph -- not the ⛓
/// emoji, which costs the renderer seconds a frame (see bisonrelay_no_emoji).
void paintLinkMark(Canvas canvas, Offset at, Color colour) {
  var tp = TextPainter(
      text: TextSpan(
          text: String.fromCharCode(Icons.link.codePoint),
          style: TextStyle(
              fontFamily: Icons.link.fontFamily,
              package: Icons.link.fontPackage,
              fontSize: 11,
              height: 1,
              color: colour)),
      textDirection: TextDirection.ltr)
    ..layout();
  tp.paint(canvas, at);
}
