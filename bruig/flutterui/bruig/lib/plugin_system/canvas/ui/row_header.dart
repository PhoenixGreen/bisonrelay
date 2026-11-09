import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// row_header.dart is a timeline row's header, one shape for every row (Ken,
// 2026-11-08, "I'd like channels to have a more consistent look"; see
// mixer-prototype's chanHead): the row's colour as an edge with a faint wash
// of it; the name, with the motion, sound and solo buttons each in its own
// place on the name's line, so they line up down the column whatever each
// row has; under the name, on a tall row, its badges, what it is and its
// tools; the bands' labels on the right, each level with its band; and a thin
// meter beside what is heard. A short row is all one line.

/// motionColour and soundColour are the motion's and the sound's, as the
/// prototype has them.
const motionColour = Color(0xFF3FB08D);
const soundColour = Color(0xFF4F8FD6);

/// sceneColour is the Scenes row's.
const sceneColour = Color(0xFF5A9FA8);

/// RowBand is a band of a row the header names, level with it: [top] and
/// [height] within the row. [weight] is a motion layer's share playing, drawn
/// as a small bar (striped where [pinned]); otherwise a dot of [dot].
class RowBand {
  final double top, height;
  final String label;
  final Color dot;
  final double? weight;
  final bool pinned;
  const RowBand(this.top, this.height, this.label, this.dot,
      {this.weight, this.pinned = false});
}

/// RowToggle is one of the header's three buttons: the motion's, the sound's
/// or the solo.
class RowToggle {
  final Key key;
  final bool on;

  /// onTap is what pressing it does; null, it only shows the state.
  final VoidCallback? onTap;
  const RowToggle(this.key, {required this.on, this.onTap});
}

/// bandColumnWidth is the bands' column, and the header width it shows from.
const double bandColumnWidth = 66;
const double bandColumnFrom = 200;

class RowHeader extends StatelessWidget {
  final Color colour;
  final double width, height;

  /// name is the row's name: plain, or an editor to rename it.
  final Widget name;
  final String kind;

  /// fold is the row's fold arrow, where it has one.
  final Widget? fold;

  /// badges go after the name on a short row, before the kind on a tall one.
  final List<Widget> badges;

  /// tools are a tall row's own, at the end of its second line.
  final List<Widget> tools;

  final RowToggle? motion, sound, solo;
  final List<RowBand> bands;
  final bool selected;

  /// joinsBelow is a row whose own sound's rows follow it as one row: no
  /// line under it. continued is those rows: the edge, the wash, the bands'
  /// labels and the meter, under the row's name rather than with one.
  final bool joinsBelow;
  final bool continued;

  /// meter is the channel whose level the meter shows, where something is
  /// heard; [controller] reads it.
  final String? meter;
  final CanvasController? controller;

  const RowHeader({
    required this.colour,
    required this.width,
    required this.height,
    required this.name,
    this.kind = "",
    this.fold,
    this.badges = const [],
    this.tools = const [],
    this.motion,
    this.sound,
    this.solo,
    this.bands = const [],
    this.selected = false,
    this.joinsBelow = false,
    this.continued = false,
    this.meter,
    this.controller,
    super.key,
  });

  /// oneLine is whether the row is all one line: short, under two lines'
  /// height.
  bool get oneLine => height < 46;

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var base = colors.surfaceContainerLow;
    var buttons = width >= 132;
    var bandsShown = width >= bandColumnFrom;
    var line1 = SizedBox(
      height: 20,
      child: Row(children: [
        if (fold != null) fold!,
        const SizedBox(width: 2),
        Flexible(child: name),
        // Beside the name on a short row, giving way as the name does.
        if (oneLine && buttons && badges.isNotEmpty)
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (var b in badges) ...[const SizedBox(width: 4), b],
              ]),
            ),
          ),
        const Spacer(),
        if (buttons) _Toggles(motion: motion, sound: sound, solo: solo),
      ]),
    );
    var line2 = !oneLine && width >= 132
        ? Row(children: [
            const SizedBox(width: 20),
            for (var b in badges) ...[b, const SizedBox(width: 5)],
            // What it is has the room its tools leave.
            Expanded(
              child: Text(kind,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 10, color: colors.onSurfaceVariant)),
            ),
            for (var t in tools) ...[const SizedBox(width: 3), t],
          ])
        : null;
    var sb = bands.where((b) => b.dot == soundColour).firstOrNull;
    return Container(
      decoration: BoxDecoration(
        // A faint wash of the row's colour by its edge: the edge is what says
        // which row (Ken: "the gradient is too much").
        gradient: selected
            ? null
            : LinearGradient(colors: [
                Color.alphaBlend(colour.withValues(alpha: 0.05), base),
                base,
              ], stops: const [
                0,
                0.32
              ]),
        color: selected ? colors.primary.withValues(alpha: 0.16) : null,
        border: Border(
            right: BorderSide(color: colors.outlineVariant),
            bottom: joinsBelow
                ? BorderSide.none
                : BorderSide(color: colors.outline.withValues(alpha: 0.5))),
      ),
      foregroundDecoration: selected
          ? BoxDecoration(
              border: Border.all(
                  color: colors.primary.withValues(alpha: 0.4), width: 1))
          : null,
      child: Stack(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 4, color: colour),
          if (continued)
            const Spacer()
          else
            Expanded(
              child: ClipRect(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      width < 44 ? 1 : 2, oneLine ? 1 : 3, 6, oneLine ? 1 : 3),
                  child: Column(
                      mainAxisAlignment: oneLine
                          ? MainAxisAlignment.center
                          : MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        line1,
                        if (line2 != null) ...[
                          const SizedBox(height: 2),
                          SizedBox(height: 18, child: line2),
                        ],
                      ]),
                ),
              ),
            ),
          if (bandsShown)
            Container(
              width: bandColumnWidth,
              decoration: BoxDecoration(
                  border: Border(
                      left: BorderSide(
                          color:
                              colors.outlineVariant.withValues(alpha: 0.6)))),
              child: Stack(children: [
                for (var b in bands)
                  if (b.height >= 12)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: b.top,
                      height: b.height,
                      child: _BandLabel(band: b, colors: colors),
                    ),
              ]),
            ),
          const SizedBox(width: 7),
        ]),
        if (meter != null && controller != null)
          Positioned(
            right: 2,
            width: 3,
            top: sb != null && !oneLine ? sb.top + 3 : 5,
            height: math.max(
                4.0, sb != null && !oneLine ? sb.height - 6 : height - 10),
            child: _Meter(controller: controller!, channel: meter!),
          ),
      ]),
    );
  }
}

/// _Toggles are the motion, sound and solo buttons, each in its own place:
/// one the row does not have leaves its place empty.
class _Toggles extends StatelessWidget {
  final RowToggle? motion, sound, solo;
  const _Toggles({this.motion, this.sound, this.solo});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    Widget slot(RowToggle? t, Widget Function(Color) face, Color tint,
        {bool solid = false}) {
      if (t == null) return const SizedBox(width: 18, height: 17);
      var on = t.on;
      var ink = on
          ? (solid
              ? const Color(0xFF0A1A2E)
              : Color.lerp(tint, Colors.white, 0.45)!)
          : colors.onSurfaceVariant.withValues(alpha: 0.7);
      return InkWell(
        key: t.key,
        borderRadius: BorderRadius.circular(4),
        onTap: t.onTap,
        child: Container(
          width: 18,
          height: 17,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: on
                ? (solid ? tint : tint.withValues(alpha: 0.16))
                : Colors.transparent,
            border: Border.all(
                color: on && !solid
                    ? tint.withValues(alpha: 0.55)
                    : on
                        ? tint
                        : colors.outlineVariant),
          ),
          child: face(ink),
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      // A small square on its corner: the motion's mark (an icon this small
      // reads as something else).
      slot(
          motion,
          (ink) => Transform.rotate(
              angle: math.pi / 4,
              child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      color: ink, borderRadius: BorderRadius.circular(1)))),
          motionColour),
      const SizedBox(width: 2),
      slot(sound, (ink) => Icon(Icons.music_note, size: 11, color: ink),
          soundColour),
      const SizedBox(width: 2),
      slot(
          solo,
          (ink) => Text("S",
              style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w700, color: ink)),
          soundColour,
          solid: true),
    ]);
  }
}

class _BandLabel extends StatelessWidget {
  final RowBand band;
  final ColorScheme colors;
  const _BandLabel({required this.band, required this.colors});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, right: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Flexible(
            child: Text(band.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 9.5, color: colors.onSurfaceVariant)),
          ),
          const SizedBox(width: 4),
          if (band.weight case var w?)
            Container(
              width: 14,
              height: 5,
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                  color: colors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(2)),
              child: FractionallySizedBox(
                widthFactor: w.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: band.pinned
                        ? motionColour.withValues(alpha: 0.6)
                        : motionColour,
                  ),
                ),
              ),
            )
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                  color: band.dot, borderRadius: BorderRadius.circular(2)),
            ),
        ]),
      );
}

/// _Meter is a channel's level, upright, moving as the playhead does.
class _Meter extends StatelessWidget {
  final CanvasController controller;
  final String channel;
  const _Meter({required this.controller, required this.channel});

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          painter: _MeterPainter(controller, channel,
              ThemeNotifier.of(context).colors.surfaceContainerLowest),
        ),
      );
}

class _MeterPainter extends CustomPainter {
  final CanvasController controller;
  final String channel;
  final Color well;
  _MeterPainter(this.controller, this.channel, this.well)
      : super(repaint: controller.playheadMoved);

  @override
  void paint(Canvas canvas, Size size) {
    var r =
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(2));
    canvas.drawRRect(r, Paint()..color = well);
    var (l, rr) = controller.playing ? controller.levels(channel) : (0.0, 0.0);
    var level = math.max(l, rr).clamp(0.0, 1.0);
    if (level <= 0) return;
    var h = size.height * level;
    canvas.save();
    canvas.clipRRect(r);
    canvas.drawRect(
        Rect.fromLTWH(0, size.height - h, size.width, h),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Color(0xFF5BC46B),
              Color(0xFF5BC46B),
              Color(0xFFE2B04A),
              Color(0xFFE0564F)
            ],
            stops: [0, 0.7, 0.9, 1],
          ).createShader(Offset.zero & size));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MeterPainter old) =>
      old.channel != channel || old.well != well;
}
