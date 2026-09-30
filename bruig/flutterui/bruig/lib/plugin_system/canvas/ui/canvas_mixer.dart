import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/export/export_media.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

// canvas_mixer.dart is the mixer: a strip for each sound on the timeline and
// a master strip, floated over the canvas from a button at the end of the
// timeline -- see CanvasTimeline -- and resized by the grip along its top.
//
// A strip, top to bottom: its name; its EQ, drawn as the curve in miniature;
// its compressor; its balance; mute and solo; a fader beside a meter; and the
// fader's reading. Clicking the EQ or the compressor opens that strip's
// editor in the panel, and back returns to the strips.
//
// Everything a strip sets is saved with the clip it belongs to, except solo,
// which is for listening -- see CanvasController.solo. What it sets is
// defined in mix.dart, in terms the editor and an export both follow.

/// mixerMinHeight and mixerMaxFraction bound the panel's height, which the
/// screen keeps.
const double mixerMinHeight = 250;
const double mixerDefaultHeight = 320;

class CanvasMixer extends StatefulWidget {
  final CanvasController controller;
  final double height;
  final ValueChanged<double> onResize;
  final VoidCallback onClose;

  const CanvasMixer({
    required this.controller,
    required this.height,
    required this.onResize,
    required this.onClose,
    super.key,
  });

  @override
  State<CanvasMixer> createState() => _CanvasMixerState();
}

/// _master is the master strip's key where a strip's key is wanted.
const _master = "\u0000master";

class _CanvasMixerState extends State<CanvasMixer>
    with SingleTickerProviderStateMixin {
  CanvasController get controller => widget.controller;
  late final Ticker _ticker;

  /// _peaks is each strip's held peak, per side, in decibels; they fall back
  /// slowly, as a meter's peak hold does.
  final Map<String, (double, double)> _peaks = {};
  final Map<String, (double, double)> _now = {};

  /// _editing is the strip whose EQ or compressor is open, and _what which.
  String? _editing;
  bool _editingComp = false;

  Loudness? _measured;
  bool _measuring = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_meter)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// _meter reads every strip's level, about thirty times a second.
  Duration _last = Duration.zero;
  void _meter(Duration now) {
    if (now - _last < const Duration(milliseconds: 33)) return;
    _last = now;
    var channels = {
      for (var channel in controller.timelineChannels) channel.key: channel,
    };
    var keys = [...channels.keys, _master];
    var moved = false;
    for (var key in keys) {
      // A channel is as loud as the loudest sound on it.
      var (l, r) = key == _master
          ? controller.levels()
          : controller.channelLevels(channels[key]!);
      var db = (gainToDb(l), gainToDb(r));
      var was = _now[key];
      if (was == null ||
          (was.$1 - db.$1).abs() > 0.3 ||
          (was.$2 - db.$2).abs() > 0.3) {
        moved = true;
      }
      _now[key] = db;
      var held = _peaks[key] ?? (-90.0, -90.0);
      // Held for a moment, then falling at twenty decibels a second.
      _peaks[key] = (
        math.max(db.$1, held.$1 - 0.66),
        math.max(db.$2, held.$2 - 0.66),
      );
    }
    if (moved && mounted) setState(() {});
  }

  Future<void> _measure() async {
    setState(() {
      _measuring = true;
      _measured = null;
    });
    var result = await measureMix(controller.document);
    if (!mounted) return;
    setState(() {
      _measuring = false;
      _measured = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        var lanes = controller.timelineChannels;
        var editing = _editing;
        TimelineChannel? lane;
        if (editing != null && editing != _master) {
          lane = lanes.where((l) => l.key == editing).firstOrNull;
          if (lane == null) editing = null;
        }
        return Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: theme.colors.surfaceContainerLow.withValues(alpha: 0.97),
            border: Border(
                top: BorderSide(color: theme.colors.outlineVariant, width: 1)),
          ),
          child: Column(children: [
            // The grip: dragged up, the mixer is taller. Over the canvas, so
            // it never moves the design, whatever its height.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (d) =>
                  widget.onResize(widget.height - d.delta.dy),
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                child: SizedBox(
                  height: 12,
                  child: Center(
                    child: Container(
                      width: 44,
                      height: 3,
                      decoration: BoxDecoration(
                          color: theme.colors.outline,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 6, 4),
              child: Row(children: [
                Expanded(
                  child: Text(
                    editing == null
                        ? "MIXER"
                        : "MIXER · ${editing == _master ? "Master" : lane!.name}"
                            " · ${_editingComp ? "Compressor" : "EQ"}",
                    style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w600,
                        color: theme.colors.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (editing != null)
                  CanvasIconButton(
                    key: const ValueKey("mixerBack"),
                    icon: Icons.arrow_back,
                    tooltip: "Back to the strips",
                    tight: true,
                    onPressed: () => setState(() => _editing = null),
                  ),
                CanvasIconButton(
                  icon: Icons.close,
                  tooltip: "Close the mixer",
                  tight: true,
                  onPressed: widget.onClose,
                ),
              ]),
            ),
            Expanded(
              child: editing == null
                  ? _strips(theme, lanes)
                  : _editor(theme, editing, lane),
            ),
          ]),
        );
      },
    );
  }

  Widget _strips(ThemeNotifier theme, List<TimelineChannel> lanes) {
    var master = controller.document.masterMix;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: lanes.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      "A strip appears here for each video and background "
                      "sound on the timeline. The master strip is always "
                      "here, and sets how the whole canvas sounds.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, color: theme.colors.onSurfaceVariant),
                    ),
                  ),
                )
              : ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var lane in lanes)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _ChannelStrip(
                          key: ValueKey("strip-${lane.key}"),
                          name: lane.name,
                          mix: lane.mix,
                          editable: lane.editable,
                          soloed: controller.solo.contains(lane.key),
                          level: _now[lane.key] ?? (-90, -90),
                          peak: _peaks[lane.key] ?? (-90, -90),
                          theme: theme,
                          onChanged: (mix, {transient = false}) {
                            controller.beginInteraction();
                            controller.setChannelMix(lane, mix,
                                transient: true);
                            if (!transient) controller.endInteraction();
                          },
                          onCommit: controller.endInteraction,
                          onSolo: () => controller.toggleSolo(lane.key),
                          onOpenEq: () => setState(() {
                            _editing = lane.key;
                            _editingComp = false;
                          }),
                          onOpenComp: () => setState(() {
                            _editing = lane.key;
                            _editingComp = true;
                          }),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(width: 8),
        _MasterStrip(
          key: const ValueKey("strip-master"),
          mix: master,
          level: _now[_master] ?? (-90, -90),
          peak: _peaks[_master] ?? (-90, -90),
          theme: theme,
          measured: _measured,
          measuring: _measuring,
          onMeasure: _measure,
          onChanged: (mix, {transient = false}) {
            controller.beginInteraction();
            controller.setMasterMix(mix, transient: true);
            if (!transient) controller.endInteraction();
          },
          onCommit: controller.endInteraction,
          onOpenEq: () => setState(() {
            _editing = _master;
            _editingComp = false;
          }),
          onOpenComp: () => setState(() {
            _editing = _master;
            _editingComp = true;
          }),
        ),
      ]),
    );
  }

  Widget _editor(ThemeNotifier theme, String key, TimelineChannel? lane) {
    var isMaster = key == _master;
    var master = controller.document.masterMix;
    var eq = isMaster ? master.eq : lane!.mix.eq;
    var comp = isMaster ? master.comp : lane!.mix.comp;

    void write({Eq? eq, Dynamics? comp, bool transient = false}) {
      controller.beginInteraction();
      if (isMaster) {
        controller.setMasterMix(master.copyWith(eq: eq, comp: comp),
            transient: true);
      } else {
        controller.setChannelMix(lane!, lane.mix.copyWith(eq: eq, comp: comp),
            transient: true);
      }
      if (!transient) controller.endInteraction();
    }

    if (_editingComp) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: SingleChildScrollView(
          child: CanvasControlScope(
            maxWidth: 400,
            child: Wrap(spacing: 10, runSpacing: 8, children: [
              CanvasToggle(
                key: const ValueKey("compOn"),
                label: isMaster ? "Glue on" : "Compressor on",
                value: comp.on,
                onChanged: (v) => write(comp: comp.copyWith(on: v)),
              ),
              for (var (label, value, lo, hi, apply) in <(
                String,
                double,
                double,
                double,
                Dynamics Function(double)
              )>[
                (
                  "Threshold dB",
                  comp.threshold,
                  -60,
                  0,
                  (v) => comp.copyWith(threshold: v)
                ),
                ("Ratio", comp.ratio, 1, 10, (v) => comp.copyWith(ratio: v)),
                (
                  "Attack ms",
                  comp.attackMs,
                  0.1,
                  100,
                  (v) => comp.copyWith(attackMs: v)
                ),
                (
                  "Release ms",
                  comp.releaseMs,
                  10,
                  1000,
                  (v) => comp.copyWith(releaseMs: v)
                ),
                (
                  "Makeup dB",
                  comp.makeupDb,
                  0,
                  24,
                  (v) => comp.copyWith(makeupDb: v)
                ),
              ])
                CanvasNumberField(
                  label: label,
                  value: value,
                  min: lo,
                  max: hi,
                  decimals: 1,
                  width: 76,
                  onChanged: (v) => write(comp: apply(v), transient: true),
                  onCommit: controller.endInteraction,
                ),
              SizedBox(
                width: 380,
                child: Text(
                  isMaster
                      ? "The glue is a gentle compressor over the whole mix, "
                          "so the parts sit together. Above the threshold the "
                          "level is turned down by the ratio."
                      : "Above the threshold the level is turned down by the "
                          "ratio: a voice that comes and goes is kept even.",
                  style: TextStyle(
                      fontSize: 11, color: theme.colors.onSurfaceVariant),
                ),
              ),
            ]),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: _EqEditor(
        eq: eq,
        theme: theme,
        onChanged: (next, {transient = false}) =>
            write(eq: next, transient: transient),
        onCommit: controller.endInteraction,
      ),
    );
  }
}

typedef _MixWrite<T> = void Function(T next, {bool transient});

// ---------------------------------------------------------------------------
// Pieces of a strip
// ---------------------------------------------------------------------------

/// faderTop and faderBottom are the fader's travel, in decibels. The bottom is
/// silence.
const double _faderTop = 6;
const double _faderBottom = -60;

/// faderPosition is where [db] sits on the fader, nought at the top to one at
/// the bottom. Not a straight line in decibels: most of the travel is spent
/// where mixing happens, between minus thirty and the top.
double faderPosition(double db) => db <= _faderBottom
    ? 1
    : math
        .pow((_faderTop - db) / (_faderTop - _faderBottom), 0.6)
        .toDouble()
        .clamp(0.0, 1.0);

double faderDb(double position) => position >= 0.995
    ? -90
    : _faderTop -
        math.pow(position.clamp(0.0, 1.0), 1 / 0.6) *
            (_faderTop - _faderBottom);

String dbText(double db) => db <= -89
    ? "−∞"
    : "${db > 0 ? "+" : db < 0 ? "−" : ""}${db.abs().toStringAsFixed(1)}";

/// parseDb reads a level somebody typed: "-6", "−6.5 dB", "+3", "0", or
/// "-inf" for silence -- clamped to what the fader reaches. Null for anything
/// that is not a level, which leaves the fader where it was.
double? parseDb(String text) {
  var t = text
      .trim()
      .toLowerCase()
      .replaceAll("−", "-")
      .replaceAll("db", "")
      .replaceAll(" ", "");
  if (t == "-inf" || t == "-∞" || t == "inf" || t == "∞") return -90;
  var v = double.tryParse(t);
  if (v == null || !v.isFinite) return null;
  if (v <= _faderBottom - 30) return -90;
  return v.clamp(-90.0, _faderTop).toDouble();
}

/// DbReading is the level under a fader: clicked, it takes a typed value.
class DbReading extends StatefulWidget {
  final double db;
  final ValueChanged<double> onSet;
  final TextStyle style;

  /// textKey is on the reading itself, so a test can find it by its old name.
  final Key? textKey;

  /// fieldHeight is how tall the box for typing is, to fit where it is.
  final double fieldHeight;

  /// unit follows the number: " dB" under a fader, nothing where there is
  /// no room for it.
  final String unit;

  const DbReading(
      {required this.db,
      required this.onSet,
      required this.style,
      this.textKey,
      this.fieldHeight = 16,
      this.unit = " dB",
      super.key});

  @override
  State<DbReading> createState() => _DbReadingState();
}

class _DbReadingState extends State<DbReading> {
  bool _typing = false;
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _open() {
    setState(() {
      _typing = true;
      _text.text = widget.db <= -89 ? "-inf" : widget.db.toStringAsFixed(1);
      _text.selection =
          TextSelection(baseOffset: 0, extentOffset: _text.text.length);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _commit() {
    if (!_typing) return;
    var v = parseDb(_text.text);
    setState(() => _typing = false);
    if (v != null && v != widget.db) widget.onSet(v);
  }

  @override
  Widget build(BuildContext context) {
    if (_typing) {
      return SizedBox(
        height: widget.fieldHeight,
        child: TextField(
          key: const ValueKey("dbEntry"),
          controller: _text,
          focusNode: _focus,
          textAlign: TextAlign.center,
          style: widget.style,
          decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none),
          onSubmitted: (_) => _commit(),
          onTapOutside: (_) => _commit(),
        ),
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _open,
        child: Text("${dbText(widget.db)}${widget.unit}",
            key: widget.textKey,
            textAlign: TextAlign.center,
            style: widget.style),
      ),
    );
  }
}

class _Fader extends StatelessWidget {
  final double db;
  final (double, double) level;
  final (double, double) peak;
  final ThemeNotifier theme;
  final _MixWrite<double> onChanged;
  final VoidCallback onCommit;
  final bool wide;

  const _Fader({
    required this.db,
    required this.level,
    required this.peak,
    required this.theme,
    required this.onChanged,
    required this.onCommit,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          var h = box.maxHeight;
          void at(double y) =>
              onChanged(faderDb(((y - 6) / (h - 12)).clamp(0.0, 1.0)),
                  transient: true);
          return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            GestureDetector(
              key: const ValueKey("fader"),
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (d) => at(d.localPosition.dy),
              onVerticalDragUpdate: (d) => at(d.localPosition.dy),
              onVerticalDragEnd: (_) => onCommit(),
              onDoubleTap: () => onChanged(0),
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                child: CustomPaint(
                  size: Size(26, h),
                  painter: _FaderPainter(db, theme.colors),
                ),
              ),
            ),
            const SizedBox(width: 4),
            CustomPaint(
              size: Size(wide ? 22 : 14, h),
              painter: _MeterPainter(level, peak, theme.colors),
            ),
          ]);
        },
      );
}

class _FaderPainter extends CustomPainter {
  final double db;
  final ColorScheme colors;
  _FaderPainter(this.db, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    var cx = size.width / 2;
    canvas.drawRRect(
        RRect.fromLTRBR(
            cx - 1.5, 6, cx + 1.5, size.height - 6, const Radius.circular(2)),
        Paint()..color = colors.surfaceContainerHighest);
    // Unity, marked: the one place on a fader everybody wants to find.
    var unity = 6 + faderPosition(0) * (size.height - 12);
    canvas.drawLine(Offset(cx - 9, unity), Offset(cx - 4, unity),
        Paint()..color = colors.outline);
    var y = 6 + faderPosition(db) * (size.height - 12);
    var cap = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, y), width: 24, height: 14),
        const Radius.circular(3));
    canvas.drawRRect(cap, Paint()..color = colors.onSurfaceVariant);
    canvas.drawLine(
        Offset(cx - 9, y), Offset(cx + 9, y), Paint()..color = colors.surface);
  }

  @override
  bool shouldRepaint(_FaderPainter old) => old.db != db;
}

class _MeterPainter extends CustomPainter {
  final (double, double) level;
  final (double, double) peak;
  final ColorScheme colors;
  _MeterPainter(this.level, this.peak, this.colors);

  /// A meter reads from minus sixty to nought, with the last six decibels in
  /// amber and the top in red -- the colours of every meter anybody has seen.
  double _fill(double db) => ((db + 60) / 60).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    var w = (size.width - 2) / 2;
    for (var (i, (db, held))
        in [(level.$1, peak.$1), (level.$2, peak.$2)].indexed) {
      var x = i * (w + 2);
      var well = Rect.fromLTWH(x, 6, w, size.height - 12);
      canvas.drawRect(well, Paint()..color = colors.surfaceContainerHighest);
      var top = well.bottom - _fill(db) * well.height;
      canvas.drawRect(
          Rect.fromLTRB(x, top, x + w, well.bottom),
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Color(0xFF3FCF73),
                Color(0xFF3FCF73),
                Color(0xFFF0B43C),
                Color(0xFFEF4D4D)
              ],
              stops: [0, 0.8, 0.9, 1],
            ).createShader(well));
      var peakY = well.bottom - _fill(held) * well.height;
      canvas.drawRect(Rect.fromLTWH(x, peakY - 1, w, 2),
          Paint()..color = colors.onSurface.withValues(alpha: 0.8));
    }
  }

  @override
  bool shouldRepaint(_MeterPainter old) =>
      old.level != level || old.peak != peak;
}

/// _MiniCurve is an EQ drawn small, on a strip's EQ slot.
class _MiniCurve extends CustomPainter {
  final Eq eq;
  final ColorScheme colors;
  _MiniCurve(this.eq, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    var path = Path();
    for (var i = 0; i <= 40; i++) {
      var f = 20 * math.pow(1000, i / 40).toDouble();
      var db = eq.responseDb(f).clamp(-12.0, 12.0);
      var x = i / 40 * size.width;
      var y = size.height / 2 - db / 12 * (size.height / 2 - 1);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = eq.on ? colors.primary : colors.outline);
  }

  @override
  bool shouldRepaint(_MiniCurve old) =>
      old.eq.toJson().toString() != eq.toJson().toString();
}

Widget _slot(ThemeNotifier theme, String label, bool on, Widget trailing,
        VoidCallback onTap,
        {Key? key}) =>
    Material(
      color: theme.colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(children: [
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                    color: on
                        ? theme.colors.onSurface
                        : theme.colors.onSurfaceVariant)),
            const SizedBox(width: 4),
            // Scaled down rather than overflowing: a reading like
            // "−12.0 dBTP" beside its label is wider than a strip in some
            // fonts, and a strip that overflows is a striped warning where
            // the control should be.
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(fit: BoxFit.scaleDown, child: trailing),
              ),
            ),
          ]),
        ),
      ),
    );

class _ChannelStrip extends StatelessWidget {
  final String name;
  final ChannelMix mix;
  final bool editable;
  final bool soloed;
  final (double, double) level;
  final (double, double) peak;
  final ThemeNotifier theme;
  final _MixWrite<ChannelMix> onChanged;
  final VoidCallback onCommit;
  final VoidCallback onSolo;
  final VoidCallback onOpenEq;
  final VoidCallback onOpenComp;

  const _ChannelStrip({
    required this.name,
    required this.mix,
    required this.editable,
    required this.soloed,
    required this.level,
    required this.peak,
    required this.theme,
    required this.onChanged,
    required this.onCommit,
    required this.onSolo,
    required this.onOpenEq,
    required this.onOpenComp,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var colors = theme.colors;
    var body = Container(
      width: 104,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.onSurface)),
        const SizedBox(height: 6),
        _slot(
            theme,
            "EQ",
            mix.eq.on,
            CustomPaint(
                size: const Size(40, 14), painter: _MiniCurve(mix.eq, colors)),
            onOpenEq,
            key: const ValueKey("eqSlot")),
        const SizedBox(height: 4),
        _slot(
            theme,
            "Comp",
            mix.comp.on,
            Icon(Icons.circle,
                size: 7,
                color: mix.comp.on ? const Color(0xFFF0B43C) : colors.outline),
            onOpenComp,
            key: const ValueKey("compSlot")),
        const SizedBox(height: 6),
        _Balance(
          value: mix.balance,
          theme: theme,
          onChanged: (v, {transient = false}) =>
              onChanged(mix.copyWith(balance: v), transient: transient),
          onCommit: onCommit,
        ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: _Toggle(
                key: const ValueKey("mute"),
                label: "M",
                on: mix.mute,
                onColor: const Color(0xFFB23B3B),
                theme: theme,
                tooltip: "Mute: silent here and in exports",
                onTap: () => onChanged(mix.copyWith(mute: !mix.mute))),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _Toggle(
                key: const ValueKey("solo"),
                label: "S",
                on: soloed,
                onColor: const Color(0xFFB28A1F),
                theme: theme,
                tooltip: "Solo: hear only this, while you listen",
                onTap: onSolo),
          ),
        ]),
        const SizedBox(height: 6),
        Expanded(
          child: _Fader(
            db: mix.gainDb,
            level: level,
            peak: peak,
            theme: theme,
            onChanged: (db, {transient = false}) =>
                onChanged(mix.copyWith(gainDb: db), transient: transient),
            onCommit: onCommit,
          ),
        ),
        const SizedBox(height: 4),
        DbReading(
            db: mix.gainDb,
            textKey: const ValueKey("faderReading"),
            onSet: (db) => onChanged(mix.copyWith(gainDb: db)),
            style: TextStyle(
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: colors.onSurface)),
      ]),
    );
    if (editable) return body;
    return Tooltip(
      message: "On the master: changed there",
      child: IgnorePointer(child: Opacity(opacity: 0.55, child: body)),
    );
  }
}

class _Toggle extends StatelessWidget {
  final String label;
  final bool on;
  final Color onColor;
  final ThemeNotifier theme;
  final String tooltip;
  final VoidCallback onTap;

  const _Toggle({
    required this.label,
    required this.on,
    required this.onColor,
    required this.theme,
    required this.tooltip,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: on ? onColor : theme.colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: onTap,
            child: SizedBox(
              height: 20,
              child: Center(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: on
                            ? const Color(0xFFFFFFFF)
                            : theme.colors.onSurfaceVariant)),
              ),
            ),
          ),
        ),
      );
}

/// _Balance is a knob: dragged up to turn right, down to turn left, double-
/// clicked to centre.
class _Balance extends StatelessWidget {
  final double value;
  final ThemeNotifier theme;
  final _MixWrite<double> onChanged;
  final VoidCallback onCommit;

  const _Balance({
    required this.value,
    required this.theme,
    required this.onChanged,
    required this.onCommit,
  });

  @override
  Widget build(BuildContext context) {
    var reading = value.abs() < 0.02
        ? "C"
        : "${value < 0 ? "L" : "R"}${(value.abs() * 100).round()}";
    return Row(children: [
      Text("Pan",
          style: TextStyle(fontSize: 10, color: theme.colors.onSurfaceVariant)),
      const Spacer(),
      GestureDetector(
        key: const ValueKey("balance"),
        onVerticalDragUpdate: (d) => onChanged(
            (value - d.delta.dy / 80).clamp(-1.0, 1.0),
            transient: true),
        onVerticalDragEnd: (_) => onCommit(),
        onDoubleTap: () => onChanged(0),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpDown,
          child: CustomPaint(
            size: const Size(24, 24),
            painter: _KnobPainter(value, theme.colors),
          ),
        ),
      ),
      const Spacer(),
      SizedBox(
        width: 26,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(reading,
              style: TextStyle(fontSize: 10, color: theme.colors.onSurface)),
        ),
      ),
    ]);
  }
}

class _KnobPainter extends CustomPainter {
  final double value;
  final ColorScheme colors;
  _KnobPainter(this.value, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    var c = size.center(Offset.zero);
    var r = size.shortestSide / 2 - 1;
    canvas.drawCircle(c, r, Paint()..color = colors.surfaceContainerHighest);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = colors.outlineVariant);
    var angle = -math.pi / 2 + value * math.pi * 0.75;
    canvas.drawLine(
        c,
        c + Offset(math.cos(angle), math.sin(angle)) * (r - 2),
        Paint()
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = colors.onSurface);
  }

  @override
  bool shouldRepaint(_KnobPainter old) => old.value != value;
}

class _MasterStrip extends StatelessWidget {
  final MasterMix mix;
  final (double, double) level;
  final (double, double) peak;
  final ThemeNotifier theme;
  final Loudness? measured;
  final bool measuring;
  final VoidCallback onMeasure;
  final _MixWrite<MasterMix> onChanged;
  final VoidCallback onCommit;
  final VoidCallback onOpenEq;
  final VoidCallback onOpenComp;

  const _MasterStrip({
    required this.mix,
    required this.level,
    required this.peak,
    required this.theme,
    required this.measured,
    required this.measuring,
    required this.onMeasure,
    required this.onChanged,
    required this.onCommit,
    required this.onOpenEq,
    required this.onOpenComp,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var colors = theme.colors;
    TextStyle small([Color? c]) =>
        TextStyle(fontSize: 10, color: c ?? colors.onSurfaceVariant);
    String lufs(double v) => v.isFinite ? v.toStringAsFixed(1) : "−∞";
    return Container(
      width: 250,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.outline),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 104,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text("Master",
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface)),
            const SizedBox(height: 6),
            _slot(
                theme,
                "EQ",
                mix.eq.on,
                CustomPaint(
                    size: const Size(40, 14),
                    painter: _MiniCurve(mix.eq, colors)),
                onOpenEq,
                key: const ValueKey("masterEqSlot")),
            const SizedBox(height: 4),
            _slot(
                theme,
                "Glue",
                mix.comp.on,
                Icon(Icons.circle,
                    size: 7,
                    color:
                        mix.comp.on ? const Color(0xFFF0B43C) : colors.outline),
                onOpenComp,
                key: const ValueKey("masterCompSlot")),
            const SizedBox(height: 4),
            _slot(
                theme,
                "Limit",
                mix.limiter,
                Text("${dbText(mix.ceilingDb)} dBTP", style: small()),
                () => onChanged(mix.copyWith(limiter: !mix.limiter)),
                key: const ValueKey("limiterSlot")),
            const SizedBox(height: 6),
            Expanded(
              child: _Fader(
                db: mix.gainDb,
                level: level,
                peak: peak,
                theme: theme,
                wide: true,
                onChanged: (db, {transient = false}) =>
                    onChanged(mix.copyWith(gainDb: db), transient: transient),
                onCommit: onCommit,
              ),
            ),
            const SizedBox(height: 4),
            DbReading(
                db: mix.gainDb,
                textKey: const ValueKey("masterReading"),
                onSet: (db) => onChanged(mix.copyWith(gainDb: db)),
                style: TextStyle(fontSize: 11, color: colors.onSurface)),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text("LOUDNESS", style: small().copyWith(letterSpacing: 0.8)),
                const SizedBox(height: 4),
                Text("Target", style: small()),
                DropdownButton<double>(
                  key: const ValueKey("loudnessTarget"),
                  value: mix.target,
                  isDense: true,
                  isExpanded: true,
                  style: TextStyle(fontSize: 11, color: colors.onSurface),
                  items: [
                    for (var (v, label) in loudnessTargets)
                      DropdownMenuItem(value: v, child: Text(label)),
                  ],
                  onChanged: (v) {
                    if (v != null) onChanged(mix.copyWith(target: v));
                  },
                ),
                const SizedBox(height: 4),
                Row(children: [
                  SizedBox(
                    height: 24,
                    child: Checkbox(
                      key: const ValueKey("normalise"),
                      value: mix.normalise,
                      visualDensity: VisualDensity.compact,
                      onChanged: (v) =>
                          onChanged(mix.copyWith(normalise: v ?? false)),
                    ),
                  ),
                  Expanded(
                      child: Text("Bring exports to the target",
                          style: small(colors.onSurface))),
                ]),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  key: const ValueKey("measure"),
                  onPressed: measuring ? null : onMeasure,
                  icon: const Icon(Icons.graphic_eq, size: 14),
                  label: Text(measuring ? "Measuring…" : "Measure",
                      style: const TextStyle(fontSize: 11)),
                ),
                const SizedBox(height: 6),
                if (measured case var m?) ...[
                  _reading(
                      "Integrated",
                      "${lufs(m.integrated)} LUFS",
                      m.integrated > mix.target + 1
                          ? const Color(0xFFEF4D4D)
                          : m.integrated < mix.target - 2
                              ? const Color(0xFFF0B43C)
                              : const Color(0xFF3FCF73)),
                  _reading("Range", "${m.range.toStringAsFixed(1)} LU", null),
                  _reading(
                      "True peak",
                      "${lufs(m.truePeak)} dBTP",
                      m.truePeak > mix.ceilingDb
                          ? const Color(0xFFEF4D4D)
                          : null),
                ] else
                  Text(
                      "Measure plays the timeline's sound through this mix "
                      "into a broadcast loudness meter, as an export would.",
                      style: small()),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _reading(String label, String value, Color? colour) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10, color: theme.colors.onSurfaceVariant)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: colour ?? theme.colors.onSurface)),
        ]),
      );
}

// ---------------------------------------------------------------------------
// The EQ editor
// ---------------------------------------------------------------------------

class _EqEditor extends StatefulWidget {
  final Eq eq;
  final ThemeNotifier theme;
  final _MixWrite<Eq> onChanged;
  final VoidCallback onCommit;

  const _EqEditor({
    required this.eq,
    required this.theme,
    required this.onChanged,
    required this.onCommit,
  });

  @override
  State<_EqEditor> createState() => _EqEditorState();
}

class _EqEditorState extends State<_EqEditor> {
  int? _dragging;

  static const _fMin = 20.0, _fMax = 20000.0, _gMax = 12.0;
  double _x(double f, double w) =>
      math.log(f / _fMin) / math.log(_fMax / _fMin) * w;
  double _f(double x, double w) =>
      _fMin * math.pow(_fMax / _fMin, (x / w).clamp(0.0, 1.0));
  double _y(double g, double h) => h / 2 - g / _gMax * (h / 2 - 8);
  double _g(double y, double h) =>
      ((h / 2 - y) / (h / 2 - 8) * _gMax).clamp(-_gMax, _gMax);

  List<EqBand> get _bands => [widget.eq.low, widget.eq.mid, widget.eq.high];

  Eq _with(int i, EqBand band) => switch (i) {
        0 => widget.eq.copyWith(low: band, on: true),
        1 => widget.eq.copyWith(mid: band, on: true),
        _ => widget.eq.copyWith(high: band, on: true),
      };

  @override
  Widget build(BuildContext context) {
    var eq = widget.eq;
    var colors = widget.theme.colors;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: LayoutBuilder(
          builder: (context, box) {
            var w = box.maxWidth, h = box.maxHeight;
            return GestureDetector(
              key: const ValueKey("eqCurve"),
              onPanStart: (d) {
                var best = -1;
                var closest = 24.0;
                for (var (i, b) in _bands.indexed) {
                  var dist =
                      (Offset(_x(b.freq, w), _y(b.gainDb, h)) - d.localPosition)
                          .distance;
                  if (dist < closest) {
                    closest = dist;
                    best = i;
                  }
                }
                setState(() => _dragging = best < 0 ? null : best);
              },
              onPanUpdate: (d) {
                var i = _dragging;
                if (i == null) return;
                var band = _bands[i].copyWith(
                    freq: _f(d.localPosition.dx, w).clamp(20.0, 20000.0),
                    gainDb:
                        (_g(d.localPosition.dy, h) * 2).roundToDouble() / 2);
                widget.onChanged(_with(i, band), transient: true);
              },
              onPanEnd: (_) {
                setState(() => _dragging = null);
                widget.onCommit();
              },
              onDoubleTapDown: (d) {
                for (var (i, b) in _bands.indexed) {
                  if ((Offset(_x(b.freq, w), _y(b.gainDb, h)) - d.localPosition)
                          .distance <
                      14) {
                    widget.onChanged(_with(i, b.copyWith(gainDb: 0)));
                    return;
                  }
                }
              },
              child: CustomPaint(
                size: Size(w, h),
                painter: _EqPainter(eq, colors, _x, _y),
              ),
            );
          },
        ),
      ),
      const SizedBox(width: 12),
      SizedBox(
        width: 200,
        child: SingleChildScrollView(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CanvasToggle(
              key: const ValueKey("eqOn"),
              label: "EQ on",
              value: eq.on,
              onChanged: (v) => widget.onChanged(eq.copyWith(on: v)),
            ),
            const SizedBox(height: 6),
            for (var (i, (name, band)) in [
              ("Low shelf", eq.low),
              ("Bell", eq.mid),
              ("High shelf", eq.high),
            ].indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                    "$name  ${band.freq >= 1000 ? "${(band.freq / 1000).toStringAsFixed(1)} kHz" : "${band.freq.round()} Hz"}"
                    "  ${dbText(band.gainDb)} dB"
                    "${i == 1 ? "  Q ${band.q.toStringAsFixed(1)}" : ""}",
                    style: TextStyle(
                        fontSize: 11,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: colors.onSurface)),
              ),
            Text(
                "Drag a point: sideways for the frequency, up and down for "
                "how much. Double-click one to flatten it.",
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
          ]),
        ),
      ),
    ]);
  }
}

class _EqPainter extends CustomPainter {
  final Eq eq;
  final ColorScheme colors;
  final double Function(double, double) x;
  final double Function(double, double) y;
  _EqPainter(this.eq, this.colors, this.x, this.y);

  @override
  void paint(Canvas canvas, Size size) {
    var w = size.width, h = size.height;
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
        Paint()..color = colors.surfaceContainerHighest);
    var grid = Paint()..color = colors.outlineVariant.withValues(alpha: 0.5);
    for (var f in const [
      50.0,
      100.0,
      200.0,
      500.0,
      1000.0,
      2000.0,
      5000.0,
      10000.0
    ]) {
      canvas.drawLine(Offset(x(f, w), 0), Offset(x(f, w), h), grid);
    }
    for (var g in const [-12.0, -6.0, 0.0, 6.0, 12.0]) {
      canvas.drawLine(Offset(0, y(g, h)), Offset(w, y(g, h)),
          g == 0 ? (Paint()..color = colors.outline) : grid);
    }
    var shown = eq.copyWith(on: true);
    var path = Path();
    for (var i = 0; i <= 120; i++) {
      var px = i / 120 * w;
      var f = 20 * math.pow(1000, px / w).toDouble();
      var py = y(shown.responseDb(f).clamp(-12.0, 12.0), h);
      i == 0 ? path.moveTo(px, py) : path.lineTo(px, py);
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = eq.on ? colors.primary : colors.outline);
    for (var b in [eq.low, eq.mid, eq.high]) {
      canvas.drawCircle(Offset(x(b.freq, w), y(b.gainDb, h)), 7,
          Paint()..color = eq.on ? colors.primary : colors.outline);
      canvas.drawCircle(
          Offset(x(b.freq, w), y(b.gainDb, h)),
          7,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = colors.surface);
    }
  }

  @override
  bool shouldRepaint(_EqPainter old) =>
      old.eq.toJson().toString() != eq.toJson().toString();
}
