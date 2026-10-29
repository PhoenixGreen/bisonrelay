import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/transport.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// transport_controls.dart is the pieces of the timeline's control bar that
// are its own: the boxes it is grouped in, the position, the tap tempo, the
// small readouts that become a field when pressed, the menus, and the
// engine's meter. The bar itself is laid out in canvas_timeline.dart.
//
// Every number is measured before it is boxed: a box is as wide as the
// widest thing it can show, so nothing is cut and nothing jumps about as
// the playhead moves.

const _figures = [FontFeature.tabularFigures()];

/// fitWidth is how wide [text] is in [style], rounded up -- measured in the
/// font it will be drawn in: [style] over the text style in force where
/// [context] is. Measured in the bare default font, a box was sized for
/// one font and filled in another.
double fitWidth(BuildContext context, String text, TextStyle style) {
  var painter = TextPainter(
    text: TextSpan(
        text: text, style: DefaultTextStyle.of(context).style.merge(style)),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  return painter.width.ceilToDouble();
}

/// TransportGroup is one of the bar's boxes: a few controls about one thing.
class TransportGroup extends StatelessWidget {
  final List<Widget> children;
  const TransportGroup({required this.children, super.key});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    return Container(
      height: controlHeight + 6,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      margin: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// TransportButton is a square button of the bar, lit in [lit] when on.
class TransportButton extends StatelessWidget {
  final IconData? icon;
  final Widget? child;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool on;

  /// lit is the colour it lights in: the theme's own when null. Play lights
  /// green, Record red.
  final Color? lit;

  /// width is the button's, square by default; null fits what is in it.
  final double? width;

  const TransportButton({
    this.icon,
    this.child,
    required this.tooltip,
    required this.onPressed,
    this.on = false,
    this.lit,
    this.width = controlHeight,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var enabled = onPressed != null;
    var fill = on ? (lit ?? colors.secondaryContainer) : null;
    var ink = !enabled
        ? colors.onSurfaceVariant.withValues(alpha: 0.35)
        : on
            ? (lit == null
                ? colors.onSecondaryContainer
                : lit!.computeLuminance() > 0.35
                    ? const Color(0xFF10140F)
                    : Colors.white)
            : colors.onSurfaceVariant;
    Widget body = Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onPressed,
        child: Container(
          width: width,
          height: controlHeight,
          padding:
              width == null ? const EdgeInsets.symmetric(horizontal: 7) : null,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: fill, borderRadius: BorderRadius.circular(4)),
          child: IconTheme(
            data: IconThemeData(size: 15, color: ink),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700, color: ink),
              child: child ?? Icon(icon),
            ),
          ),
        ),
      ),
    );
    if (tooltip.isNotEmpty) body = Tooltip(message: tooltip, child: body);
    return Padding(padding: const EdgeInsets.only(right: 1), child: body);
  }
}

/// TransportDivider is the thin line between the parts of one box.
class TransportDivider extends StatelessWidget {
  const TransportDivider({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: controlHeight - 8,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: ThemeNotifier.of(context).colors.outlineVariant,
      );
}

/// TransportReadout is a small box with a number in it, and a word before
/// the number; pressed, it becomes a field, and what is typed is handed to
/// [onSubmit], which says whether it made sense.
class TransportReadout extends StatefulWidget {
  final String caption;
  final String value;

  /// widest is the longest value it might show, which it is sized for.
  final String widest;
  final String tooltip;
  final bool Function(String typed)? onSubmit;
  final bool dim;
  final Key? fieldKey;

  const TransportReadout({
    this.caption = "",
    required this.value,
    String? widest,
    this.tooltip = "",
    this.onSubmit,
    this.dim = false,
    this.fieldKey,
    super.key,
  }) : widest = widest ?? value;

  @override
  State<TransportReadout> createState() => _TransportReadoutState();
}

class _TransportReadoutState extends State<TransportReadout> {
  bool _editing = false;
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) setState(() => _editing = false);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _edit() {
    if (widget.onSubmit == null) return;
    setState(() {
      _editing = true;
      _text.text = widget.value;
      _text.selection =
          TextSelection(baseOffset: 0, extentOffset: _text.text.length);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _submit(String typed) {
    widget.onSubmit?.call(typed);
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var style = TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        fontFeatures: _figures,
        color: colors.onSurface);
    var captionStyle = TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: colors.onSurfaceVariant);
    var width = math.max(fitWidth(context, widget.widest, style),
            fitWidth(context, widget.value, style)) +
        4;
    Widget value = _editing
        ? SizedBox(
            width: width + 16,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    setState(() => _editing = false),
              },
              child: TextField(
                key: widget.fieldKey,
                controller: _text,
                focusNode: _focus,
                style: style,
                cursorHeight: 13,
                decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero),
                onSubmitted: _submit,
              ),
            ),
          )
        : SizedBox(
            width: width,
            child: Text(widget.value,
                maxLines: 1, softWrap: false, style: style),
          );
    Widget box = Opacity(
      opacity: widget.dim ? 0.5 : 1,
      child: Container(
        height: controlHeight - 4,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        margin: const EdgeInsets.only(right: 3),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLowest,
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (widget.caption.isNotEmpty) ...[
            Text(widget.caption, style: captionStyle),
            const SizedBox(width: 4),
          ],
          value,
        ]),
      ),
    );
    box = MouseRegion(
      cursor: widget.onSubmit == null
          ? MouseCursor.defer
          : SystemMouseCursors.text,
      child: GestureDetector(onTap: _edit, child: box),
    );
    if (widget.tooltip.isNotEmpty && !_editing) {
      box = Tooltip(message: widget.tooltip, child: box);
    }
    return box;
  }
}

/// TransportPosition is where the playhead is, big, with the other two ways
/// of saying it small underneath. Pressed, it reads the next way; pressed
/// twice, it is a field to type where to go.
class TransportPosition extends StatefulWidget {
  final AudioSettings audio;
  final bool bars;
  final int frame;
  final int frames;
  final int rate;
  final ValueChanged<int> onGo;

  const TransportPosition({
    required this.audio,
    required this.bars,
    required this.frame,
    required this.frames,
    required this.rate,
    required this.onGo,
    super.key,
  });

  @override
  State<TransportPosition> createState() => _TransportPositionState();
}

class _TransportPositionState extends State<TransportPosition> {
  int _format = 0;
  DateTime? _lastTap;
  bool _editing = false;
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) setState(() => _editing = false);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<PositionFormat> get _formats => widget.bars
      ? PositionFormat.values
      : const [PositionFormat.frames, PositionFormat.time];

  String _say(PositionFormat f, int frame) => positionText(
      f, widget.audio, frame, widget.rate, math.max(1, widget.frames));

  void _go(String typed) {
    var to = parsePosition(typed, widget.audio, widget.rate,
        bars: _formats[_format % _formats.length] == PositionFormat.bars);
    if (to != null) widget.onGo(to.clamp(0, math.max(0, widget.frames - 1)));
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var formats = _formats;
    var format = formats[_format % formats.length];
    var big = TextStyle(
        fontSize: 13,
        height: 1.05,
        fontWeight: FontWeight.w700,
        fontFeatures: _figures,
        color: colors.onSurface);
    var small = TextStyle(
        fontSize: 8.5,
        height: 1.05,
        fontFeatures: _figures,
        color: colors.onSurfaceVariant);
    var last = math.max(0, widget.frames - 1);
    var others = [
      for (var f in formats)
        if (f != format) f
    ];
    String under(int frame) => [for (var f in others) _say(f, frame)].join("  ·  ");
    // As wide as the widest it will ever say, at the last frame.
    var width = math.max(fitWidth(context, _say(format, last), big) + 8,
            fitWidth(context, under(last), small)) +
        // The padding either side, the border, and a hair to spare.
        16 +
        2 +
        2;
    Widget body = _editing
        ? TextField(
            key: const ValueKey("positionField"),
            controller: _text,
            focusNode: _focus,
            style: big,
            cursorHeight: 14,
            decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero),
            onSubmitted: _go,
          )
        // Shrunk to fit rather than run over: the box is the bar's height,
        // and two lines of text at the reader's own text size -- Settings >
        // Appearance goes to half as big again -- are taller than that. The
        // lines are held to their size, too, whatever the font's own leading.
        : FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_say(format, widget.frame),
                    maxLines: 1,
                    softWrap: false,
                    style: big,
                    strutStyle: const StrutStyle(
                        fontSize: 13, height: 1.05, forceStrutHeight: true)),
                const SizedBox(height: 1),
                Text(under(widget.frame),
                    maxLines: 1,
                    softWrap: false,
                    style: small,
                    strutStyle: const StrutStyle(
                        fontSize: 8.5, height: 1.05, forceStrutHeight: true)),
              ],
            ),
          );
    return Tooltip(
      message: _editing
          ? ""
          : "Press to read it as "
              "${formats[(_format + 1) % formats.length].label.toLowerCase()}; "
              "double-click to type where to go",
      // A press reads it the next way at once; a second inside a double
      // click's time puts the way back and opens the field. Flutter's own
      // double tap holds every single press back until it is sure, which
      // made the display slow to answer.
      child: GestureDetector(
        key: const ValueKey("transportPosition"),
        onTap: () {
          var now = DateTime.now();
          var last = _lastTap;
          _lastTap = now;
          if (last == null ||
              now.difference(last) > kDoubleTapTimeout ||
              _editing) {
            setState(() => _format = (_format + 1) % formats.length);
            return;
          }
          _lastTap = null;
          setState(() {
            _format = (_format - 1) % formats.length;
            var back = formats[_format % formats.length];
            _editing = true;
            _text.text = _say(back, widget.frame).split(" / ").first;
            _text.selection =
                TextSelection(baseOffset: 0, extentOffset: _text.text.length);
          });
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _focus.requestFocus());
        },
        child: Container(
          width: width,
          height: controlHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          margin: const EdgeInsets.only(right: 4),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: colors.surfaceContainerLowest,
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(4),
          ),
          child: body,
        ),
      ),
    );
  }
}

/// TapTempoButton sets the tempo from presses in time with the music.
class TapTempoButton extends StatefulWidget {
  /// onTempo is handed each new tempo, in taps a minute.
  final ValueChanged<double> onTempo;

  /// clock is the time in seconds, for tests; a stopwatch otherwise.
  final double Function()? clock;
  const TapTempoButton({required this.onTempo, this.clock, super.key});

  @override
  State<TapTempoButton> createState() => _TapTempoButtonState();
}

class _TapTempoButtonState extends State<TapTempoButton> {
  final Stopwatch _watch = Stopwatch()..start();
  final List<double> _taps = [];

  double get _now =>
      widget.clock?.call() ?? _watch.elapsedMicroseconds / 1000000;

  @override
  Widget build(BuildContext context) => TransportButton(
        key: const ValueKey("tapTempo"),
        width: 34,
        tooltip: "Tap in time, four times or more, to set the tempo",
        onPressed: () {
          _taps.add(_now);
          if (_taps.length > 16) _taps.removeAt(0);
          if (tapTempo(_taps) case var bpm?) widget.onTempo(bpm);
        },
        child: const Text("TAP", style: TextStyle(letterSpacing: 0.6)),
      );
}

/// TransportMenu is a button that drops a short list of actions: the keys
/// a piece of sound keeps folded away, and Clear.
class TransportMenu extends StatelessWidget {
  final String label;
  final IconData? icon;
  final String tooltip;

  /// items are each a label, what it does (null for not now), and whether it
  /// shows as ticked (null for not a switch).
  final List<(String, VoidCallback?, bool?)> items;

  const TransportMenu({
    required this.label,
    this.icon,
    this.tooltip = "",
    required this.items,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    return MenuAnchor(
      menuChildren: [
        for (var (i, (text, act, ticked)) in items.indexed)
          MenuItemButton(
            key: ValueKey("${key is ValueKey ? (key as ValueKey).value : label}-$i"),
            onPressed: act,
            leadingIcon: ticked == null
                ? null
                : Icon(ticked ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 16),
            child: Text(text, style: const TextStyle(fontSize: 12)),
          ),
      ],
      builder: (context, menu, _) {
        Widget button = Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => menu.isOpen ? menu.close() : menu.open(),
            child: Container(
              height: controlHeight,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: colors.onSurfaceVariant),
                  const SizedBox(width: 4),
                ],
                Text(label,
                    style:
                        TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
                Icon(Icons.arrow_drop_down,
                    size: 16, color: colors.onSurfaceVariant),
              ]),
            ),
          ),
        );
        return tooltip.isEmpty
            ? button
            : Tooltip(message: tooltip, child: button);
      },
    );
  }
}

/// EngineMeter is how hard the mix engine is working.
class EngineMeter extends StatelessWidget {
  final double load;
  const EngineMeter({required this.load, super.key});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var share = load.clamp(0.0, 1.0);
    var hot = load > 0.8
        ? const Color(0xFFFF5A5A)
        : load > 0.5
            ? const Color(0xFFF2B33D)
            : const Color(0xFF3CCF7A);
    var percent = "${(load * 100).round()}%";
    var style = TextStyle(
        fontSize: 10, fontFeatures: _figures, color: colors.onSurfaceVariant);
    return Tooltip(
      message: "How hard the mix engine is working: the share of the time "
          "it has that it spends making the sound. Over 100% and it cannot "
          "keep up.",
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("ENGINE",
                    style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        color: colors.onSurfaceVariant)),
                const SizedBox(height: 2),
                Container(
                  width: 40,
                  height: 4,
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                      color: colors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(2)),
                  child: FractionallySizedBox(
                    widthFactor: share,
                    child: Container(
                        decoration: BoxDecoration(
                            color: hot,
                            borderRadius: BorderRadius.circular(2))),
                  ),
                ),
              ]),
          const SizedBox(width: 6),
          SizedBox(
              width: fitWidth(context, "100%", style) + 2,
              child: Text(percent,
                  key: const ValueKey("engineLoad"), style: style)),
        ]),
      ),
    );
  }
}

/// MetronomeIcon is a metronome, drawn: there is none among the icons.
class MetronomeIcon extends StatelessWidget {
  const MetronomeIcon({super.key});

  @override
  Widget build(BuildContext context) {
    var theme = IconTheme.of(context);
    var size = theme.size ?? 15;
    return CustomPaint(
        size: Size.square(size),
        painter: _MetronomePainter(theme.color ?? Colors.grey));
  }
}

class _MetronomePainter extends CustomPainter {
  final Color color;
  const _MetronomePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    var u = size.width / 16;
    var line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4 * u
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
        Path()
          ..moveTo(5.5 * u, 1.5 * u)
          ..lineTo(10.5 * u, 1.5 * u)
          ..lineTo(13.5 * u, 14.5 * u)
          ..lineTo(2.5 * u, 14.5 * u)
          ..close(),
        line);
    canvas.drawLine(Offset(8 * u, 11 * u), Offset(12 * u, 4 * u), line);
    canvas.drawLine(Offset(4.2 * u, 11 * u), Offset(11.8 * u, 11 * u), line);
  }

  @override
  bool shouldRepaint(_MetronomePainter old) => old.color != color;
}
