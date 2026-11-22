import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/transport.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// transport_controls.dart is the play bar's pieces: boxes, buttons, the
// position, tap tempo and readouts that become fields; play_bar.dart lays
// the bar out. Each box is sized to the widest thing it can show, so nothing
// is cut or jumps as the playhead moves.

const _figures = [FontFeature.tabularFigures()];

/// _textWidth is how wide [text] is in [style] over the text style in force
/// at [context], rounded up.
///
/// Kept: the readouts ask on every build, a frame at a time in play, and
/// the answer is the same text's width until the text, the style or the
/// text size changes.
double _textWidth(BuildContext context, String text, TextStyle style) {
  var merged = DefaultTextStyle.of(context).style.merge(style);
  var scaler = MediaQuery.textScalerOf(context);
  var key = (text, merged, scaler);
  if (_widths[key] case var hit?) return hit;
  var painter = TextPainter(
    text: TextSpan(text: text, style: merged),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  var width = painter.width.ceilToDouble();
  painter.dispose();
  if (_widths.length >= 256) _widths.remove(_widths.keys.first);
  return _widths[key] = width;
}

final _widths = <(String, TextStyle, TextScaler), double>{};

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

  /// lit is the colour it lights in, the theme's own when null: Play green,
  /// Record red.
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

/// _OpensAField is a readout that becomes a field when pressed, for
/// TransportReadout and TransportPosition: the field opens holding what the
/// readout said, all of it picked to type over, takes the keyboard once it
/// is built, and turns back into the readout when the keyboard leaves it.
mixin _OpensAField<T extends StatefulWidget> on State<T> {
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

  /// _openField turns the readout into the field, holding [text]. Called
  /// inside setState.
  void _openField(String text) {
    _editing = true;
    _text.text = text;
    _pickAll();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _pickAll() => _text.selection =
      TextSelection(baseOffset: 0, extentOffset: _text.text.length);
}

/// TransportReadout is a small box with a word and a number; pressed, it
/// becomes a field, and what is typed goes to [onSubmit], which says
/// whether it made sense: if not, the field stays open to be put right.
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

class _TransportReadoutState extends State<TransportReadout>
    with _OpensAField {
  void _edit() {
    if (widget.onSubmit == null) return;
    setState(() => _openField(widget.value));
  }

  /// _submit hands [typed] to onSubmit. Taken, the field closes; not, it
  /// stays open with all of it picked, so a mistake is seen and typed over
  /// rather than vanishing.
  void _submit(String typed) {
    if (widget.onSubmit?.call(typed) ?? true) {
      _focus.unfocus();
      setState(() => _editing = false);
      return;
    }
    setState(_pickAll);
    _focus.requestFocus();
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
    var width = math.max(_textWidth(context, widget.widest, style),
            _textWidth(context, widget.value, style)) +
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
                // Enter does not let go of the keyboard by itself: _submit
                // decides whether the field closes.
                onEditingComplete: () {},
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

class _TransportPositionState extends State<TransportPosition>
    with _OpensAField {
  int _format = 0;
  DateTime? _lastTap;

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
    var width = math.max(_textWidth(context, _say(format, last), big) + 8,
            _textWidth(context, under(last), small)) +
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
        // Shrunk to fit: two lines at a larger text size are taller than the
        // bar. The lines keep their size whatever the font's leading.
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
      // A press reads it the next way at once; a second within a double
      // click's time puts the way back and opens the field. Not Flutter's
      // double tap, which holds every press back until it is sure.
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
            _openField(_say(back, widget.frame).split(" / ").first);
          });
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
