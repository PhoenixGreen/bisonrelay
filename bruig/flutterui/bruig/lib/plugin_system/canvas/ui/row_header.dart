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

/// The amber of something off the timeline, playing from its slots: as
/// Back to timeline's on the play bar.
const _slotsInk = Color(0xFFF6C46A);
const _slotsFill = Color(0xFF3A2A10);
const _slotsLine = Color(0xFF7A5A1E);

/// SlotsReturn is a row's own way back to the timeline while it plays from
/// its slots: what Back to timeline's list does for it, on its row.
class SlotsReturn extends StatelessWidget {
  final VoidCallback onTap;

  /// compact is the arrow alone, on a row of one line.
  final bool compact;
  const SlotsReturn({super.key, required this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context) => Material(
        color: _slotsFill,
        shape: RoundedRectangleBorder(
            side: const BorderSide(color: _slotsLine),
            borderRadius: BorderRadius.circular(5)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            height: 18,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.subdirectory_arrow_left,
                    size: 10, color: _slotsInk),
                if (!compact) ...[
                  const SizedBox(width: 3),
                  const Text("slots",
                      maxLines: 1,
                      style: TextStyle(fontSize: 9.5, color: _slotsInk)),
                ],
              ]),
            ),
          ),
        ),
      );
}

/// SlotsStripes is laid over a row's frames while it plays from its slots:
/// amber stripes, its timeline not being what is heard, and -- with [note]
/// -- saying so.
class SlotsStripes extends StatelessWidget {
  final bool note;
  const SlotsStripes({super.key, this.note = true});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Stack(children: [
          const Positioned.fill(child: CustomPaint(painter: _Stripes())),
          if (note)
            Positioned(
              right: 8,
              top: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                    color: const Color(0xEE241A0B),
                    border: Border.all(color: _slotsLine),
                    borderRadius: BorderRadius.circular(5)),
                child: const Text("playing from slots",
                    maxLines: 1,
                    style: TextStyle(fontSize: 10, color: _slotsInk)),
              ),
            ),
        ]),
      );
}

class _Stripes extends CustomPainter {
  const _Stripes();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    var paint = Paint()
      ..color = const Color(0x14F2A33D)
      ..strokeWidth = 5;
    for (var x = -size.height; x < size.width; x += 14) {
      canvas.drawLine(
          Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
  }

  @override
  bool shouldRepaint(_Stripes old) => false;
}

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

  /// back is the row's way back to the timeline while it plays from its
  /// slots (a [SlotsReturn]): on the name's line on a short row, after what
  /// it is on a tall one.
  final SlotsReturn? back;

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
    this.back,
    this.meter,
    this.controller,
    super.key,
  });

  /// oneLine is whether the row is all one line: short, under two lines'
  /// height -- the lines (20 + 2 + 18), their padding (3 + 3) and the
  /// border under them (1). Any less, and a row 46.1 tall overflowed.
  bool get oneLine => height < 47;

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var base = colors.surfaceContainerLow;
    var buttons = width >= 132;
    var bandsShown = width >= bandColumnFrom;
    var line1 = SizedBox(
      height: 20,
      child: Row(children: [
        // Narrowed to its least, the arrow goes before the name does.
        if (fold != null && width >= 60) fold!,
        const SizedBox(width: 2),
        // The name has the room the buttons leave, before any gap.
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            var chips = Row(mainAxisSize: MainAxisSize.min, children: [
              for (var b in badges) ...[const SizedBox(width: 4), b],
            ]);
            var withChips = oneLine && buttons && badges.isNotEmpty;
            return Row(children: [
              Flexible(child: name),
              // Beside the name on a short row: as wide as they are, the
              // name having the rest -- split half and half, "Strings" was
              // "Stri..." with room to spare (Ken, 2026-11-10). Where the
              // row is too narrow for both, they give way as the name does.
              if (withChips && box.maxWidth >= 96)
                chips
              else if (withChips)
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    child: chips,
                  ),
                ),
            ]);
          }),
        ),
        // On a short row, the way back is its arrow alone.
        if (oneLine && buttons && back != null) ...[
          const SizedBox(width: 4),
          SlotsReturn(key: back!.key, onTap: back!.onTap, compact: true),
          const SizedBox(width: 4),
        ],
        if (buttons) _Toggles(motion: motion, sound: sound, solo: solo),
      ]),
    );
    var line2 = !oneLine && width >= 132
        ? LayoutBuilder(
            builder: (context, box) => Row(children: [
                  const SizedBox(width: 20),
                  for (var b in badges) ...[b, const SizedBox(width: 5)],
                  // What it is has the room its tools leave.
                  Expanded(
                    child: Text(kind,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10, color: colors.onSurfaceVariant)),
                  ),
                  // The arrow alone where the line is short of room.
                  if (back != null) ...[
                    const SizedBox(width: 3),
                    box.maxWidth >= 200
                        ? back!
                        : SlotsReturn(
                            key: back!.key, onTap: back!.onTap, compact: true),
                  ],
                  for (var t in tools) ...[const SizedBox(width: 3), t],
                ]))
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
                  // A row shorter than its line -- dragged down to a lane's
                  // height, or folded -- has the line clipped, centred, not
                  // overflowing (Ken's log, 2026-11-13: a 19.5 px header).
                  child: oneLine
                      ? OverflowBox(
                          alignment: Alignment.center,
                          minHeight: 20,
                          maxHeight: 20,
                          child: line1)
                      : Column(
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

/// RowFold is a row's fold arrow: › folded to one line, ⌄ open.
class RowFold extends StatelessWidget {
  final bool folded;
  final VoidCallback onTap;
  const RowFold({required this.folded, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 18,
          height: 20,
          child: Icon(folded ? Icons.chevron_right : Icons.expand_more,
              size: 14,
              color: ThemeNotifier.of(context).colors.onSurfaceVariant),
        ),
      );
}

/// rowPalette is the colours a row can be given or picked: the approved
/// design's.
const rowPalette = [
  Color(0xFFE2B04A),
  Color(0xFF5A9FA8),
  Color(0xFF8E6BD1),
  Color(0xFF3FB08D),
  Color(0xFFD77AA3),
  Color(0xFF6FA3E0),
  Color(0xFFD9A15A),
  Color(0xFF9A92EA),
  Color(0xFFE0564F),
  Color(0xFF7FC8F8),
];

/// givenRowColour is the colour row [key] is given until one is picked: by
/// its key, so the same row is the same colour every time, wherever it is
/// in the list.
Color givenRowColour(String key) {
  // FNV-1a: the same for the same key in every run (String.hashCode is not
  // promised to be).
  var h = 0x811C9DC5;
  for (var u in key.codeUnits) {
    h ^= u;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return rowPalette[h % rowPalette.length];
}

/// rowColourMenu is a row's colours, for its header's right-click menu: a
/// swatch for each of rowPalette, and Automatic. What was picked comes back
/// from the menu as "colour:<i>" or "colour:auto": see rowColourPicked.
List<PopupMenuEntry<String>> rowColourMenu(Color now) => [
      PopupMenuItem<String>(
        enabled: false,
        height: 34,
        child: Builder(
          builder: (context) => Wrap(spacing: 4, runSpacing: 4, children: [
            for (var (i, c) in rowPalette.indexed)
              InkWell(
                key: ValueKey("rowColour-$i"),
                borderRadius: BorderRadius.circular(4),
                onTap: () => Navigator.of(context).pop("colour:$i"),
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: c == now
                            ? const Color(0xFFFFFFFF)
                            : const Color(0x00000000),
                        width: 2),
                  ),
                ),
              ),
          ]),
        ),
      ),
      const PopupMenuItem<String>(
        key: ValueKey("rowColourAuto"),
        value: "colour:auto",
        height: 30,
        child: Text("Its own colour again", style: TextStyle(fontSize: 12.5)),
      ),
    ];

/// rowColourPicked is what [choice], from rowColourMenu, picked: (true, a
/// colour) or (true, null) for its given one; (false, null) where it was
/// not a colour.
(bool, Color?) rowColourPicked(String? choice) {
  if (choice == null || !choice.startsWith("colour:")) return (false, null);
  var i = int.tryParse(choice.substring(7));
  return (true, i == null ? null : rowPalette[i]);
}
