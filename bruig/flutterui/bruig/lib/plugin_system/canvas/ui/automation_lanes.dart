import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/automation.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart'
    show ReturnChannel;
import 'package:bruig/plugin_system/canvas/model/mix.dart' show ChannelMix;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline_view.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// automation_lanes.dart is a channel's automation on the timeline: lanes
// under the channel, opened by its A button, each showing one of its
// settings -- chosen at the lane's left -- and the points it moves through.
// A click puts a point down, a drag moves one, a right-click takes it away;
// between them the setting goes in a straight line. See automation.dart.

/// automationLaneHeight is a lane's height; automationAddHeight the row
/// under them that adds another.
const double automationLaneHeight = 56;
const double automationAddHeight = 24;

/// automationColour is automation's red: a lane's line, its points, and
/// the dot beside a setting a lane moves.
const Color automationColour = Color(0xFFE0533F);

/// _heldColour is a lane overridden by a hand: greyed until it is handed
/// back.
const Color _heldColour = Color(0xFF7D838D);

const double _pad = 6;

/// settingLabel is [t] as a clip's envelope names it: a channel's own
/// settings said to be the channel's, beside the clip's own gain and pan.
String settingLabel(
        AutomationTarget t, ChannelMix mix, List<ReturnChannel> returns) =>
    t.kind == AutomationKind.device
        ? t.label(mix, returns)
        : "Channel › ${t.label(mix, returns)}";

/// envelopeLengths are the lengths a clip's envelope of a setting can have
/// of its own, in beats -- null for the clip's -- with their names, at
/// [beatsPerBar].
List<(double?, String)> envelopeLengths(int beatsPerBar) {
  String name(double beats) => beats < beatsPerBar
      ? "${beats.round()} beat${beats == 1 ? "" : "s"}"
      : "${(beats / beatsPerBar).round()} bar${beats == beatsPerBar ? "" : "s"}";
  return [
    (null, "The clip's"),
    for (var b in [
      1.0,
      2.0,
      beatsPerBar * 1.0,
      beatsPerBar * 2.0,
      beatsPerBar * 4.0
    ])
      (b, name(b)),
  ];
}

/// AutomationLaneHeader is a lane's left end, under its channel's strip:
/// which setting it shows, its value where the playhead is, and the ways to
/// hide it and to clear it.
class AutomationLaneHeader extends StatelessWidget {
  final CanvasController controller;
  final TimelineChannel channel;
  final int index;
  final double width;

  const AutomationLaneHeader(
      {required this.controller,
      required this.channel,
      required this.index,
      required this.width,
      super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var colors = theme.colors;
    var rows = controller.automationRows(channel);
    var target = rows[index];
    var what = AutomationTarget.parse(target);
    var mix = channel.mix;
    var returns = controller.document.returns;
    var lane = controller.automationLaneOf(channel, target);
    var laned = {
      for (var l in mix.automation)
        if (l.points.isNotEmpty) l.target
    };
    var held = controller.overridden[channel.key]?.contains(target) ?? false;
    var on = lane != null && lane.points.isNotEmpty;
    var now = what == null
        ? null
        : (held ? null : lane?.valueAt(controller.automationNow)) ??
            what.own(mix);
    // Every setting the channel has, but those another lane shows.
    var choices = [
      for (var t in automationTargets(mix, returns))
        if (t.id == target || !rows.contains(t.id)) t,
    ];
    var small = TextStyle(fontSize: 10.5, color: colors.onSurface);
    return Container(
      key: ValueKey("autoHeader-${channel.key}-$index"),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: Border(
            right: BorderSide(color: colors.outlineVariant),
            bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Red: automation, indented under its channel.
        Container(
            width: 4,
            margin: const EdgeInsets.only(left: 8),
            color: automationColour.withValues(alpha: 0.7)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(5, 2, 2, 2),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(
                      child: DropdownButton<String>(
                        key: ValueKey("autoTarget-${channel.key}-$index"),
                        value:
                            choices.any((t) => t.id == target) ? target : null,
                        hint: Text("Gone", style: small),
                        isDense: true,
                        isExpanded: true,
                        underline: const SizedBox(),
                        iconSize: 14,
                        style: small,
                        dropdownColor: colors.surfaceContainerHigh,
                        items: [
                          for (var t in choices)
                            DropdownMenuItem(
                              value: t.id,
                              child: Row(children: [
                                // A setting a lane moves: its red dot.
                                Container(
                                  width: 6,
                                  height: 6,
                                  margin: const EdgeInsets.only(right: 5),
                                  decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: laned.contains(t.id)
                                          ? automationColour
                                          : Colors.transparent),
                                ),
                                Flexible(
                                  child: Text(t.label(mix, returns),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ]),
                            ),
                        ],
                        selectedItemBuilder: (_) => [
                          for (var t in choices)
                            Text(t.label(mix, returns),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: small),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            controller.showAutomationRow(channel, index, v);
                          }
                        },
                      ),
                    ),
                    _IconTap(
                      key: ValueKey("autoHide-${channel.key}-$index"),
                      icon: Icons.close,
                      tip: on
                          ? "Hide this lane: its points are kept, and played"
                          : "Hide this lane",
                      onTap: () => controller.hideAutomationRow(channel, index),
                    ),
                  ]),
                  const SizedBox(height: 1),
                  Row(children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: !on
                              ? colors.outlineVariant
                              : held
                                  ? _heldColour
                                  : automationColour),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                          now == null || what == null ? "" : what.reading(now),
                          key: ValueKey("autoValue-${channel.key}-$index"),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: small.copyWith(
                              color: colors.onSurfaceVariant,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ])),
                    ),
                    if (held && width >= 120) ...[
                      const SizedBox(width: 4),
                      Text("held",
                          style: small.copyWith(
                              fontSize: 9.5, color: colors.onSurfaceVariant)),
                    ],
                    const Spacer(),
                    if (on)
                      _IconTap(
                        key: ValueKey("autoClear-${channel.key}-$index"),
                        icon: Icons.delete_outline,
                        tip: "Clear this lane's points",
                        onTap: () {
                          controller.beginInteraction();
                          controller
                              .setAutomationPoints(channel, target, const []);
                          controller.endInteraction();
                        },
                      ),
                  ]),
                ]),
          ),
        ),
      ]),
    );
  }
}

class _IconTap extends StatelessWidget {
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  const _IconTap(
      {required this.icon, required this.tip, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(3),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(icon,
                size: 13, color: ThemeNotifier.of(context).colors.onSurface),
          ),
        ),
      );
}

/// AutomationAddRow is the row under a channel's lanes: another lane.
class AutomationAddRow extends StatelessWidget {
  final CanvasController controller;
  final TimelineChannel channel;
  const AutomationAddRow(
      {required this.controller, required this.channel, super.key});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: Border(
            right: BorderSide(color: colors.outlineVariant),
            bottom: BorderSide(color: colors.outline.withValues(alpha: 0.7))),
      ),
      padding: const EdgeInsets.only(left: 12),
      alignment: Alignment.centerLeft,
      child: TextButton(
        key: ValueKey("autoAdd-${channel.key}"),
        style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: const Size(0, 20),
            textStyle: const TextStyle(fontSize: 10.5)),
        onPressed: () => controller.addAutomationRow(channel),
        child: const Text("+ Automation lane",
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

/// AutomationLaneBody is a lane's points along the timeline, in the same
/// frames as the channel's sounds above it.
class AutomationLaneBody extends StatefulWidget {
  final CanvasController controller;
  final TimelineChannel channel;
  final String target;
  final TimelineView view;

  const AutomationLaneBody(
      {required this.controller,
      required this.channel,
      required this.target,
      required this.view,
      super.key});

  @override
  State<AutomationLaneBody> createState() => _AutomationLaneBodyState();
}

class _AutomationLaneBodyState extends State<AutomationLaneBody> {
  CanvasController get c => widget.controller;

  /// _held is the point being dragged, by its place -- kept here so a drag
  /// survives the rebuilds its own changes make.
  int? _held;

  double get _rate => math.max(1, c.document.frameRate).toDouble();

  List<AutomationPoint> get _points =>
      c.automationLaneOf(_channel, widget.target)?.points ?? const [];

  /// _channel is the channel as it is now: the one built from may be gone
  /// by the time a drag's next move arrives.
  TimelineChannel get _channel =>
      c.timelineChannels
          .where((x) => x.key == widget.channel.key)
          .firstOrNull ??
      widget.channel;

  double _xOf(double seconds, double width) =>
      widget.view.xOf(seconds * _rate, width);

  double _yOf(double v, double height, AutomationTarget what) =>
      _pad + (1 - what.height(v)) * (height - 2 * _pad);

  /// _secondsAt is the time at [x], to a sixteenth unless Shift is held.
  double _secondsAt(double x, double width) {
    var v = widget.view;
    var seconds = (v.first + x / math.max(1, width) * v.span) / _rate;
    if (!HardwareKeyboard.instance.isShiftPressed) {
      var step = c.document.audio.secondsPerBeat / 4;
      if (step > 0) seconds = (seconds / step).round() * step;
    }
    return math.max(0, seconds);
  }

  double _valueAt(double y, double height, AutomationTarget what) =>
      what.valueAt(1 - (y - _pad) / math.max(1, height - 2 * _pad));

  int? _pointAt(Offset p, Size size, AutomationTarget what) {
    var points = _points;
    for (var i = points.length - 1; i >= 0; i--) {
      var (t, v) = points[i];
      var at = Offset(_xOf(t, size.width), _yOf(v, size.height, what));
      if ((at - p).distance <= 7) return i;
    }
    return null;
  }

  void _write(List<AutomationPoint> points, {bool transient = false}) =>
      c.setAutomationPoints(_channel, widget.target, points,
          transient: transient);

  void _add(Offset p, Size size, AutomationTarget what, {bool drag = false}) {
    var point =
        (_secondsAt(p.dx, size.width), _valueAt(p.dy, size.height, what));
    var next = [..._points, point]..sort((a, b) => a.$1.compareTo(b.$1));
    if (drag) {
      c.beginInteraction();
      _write(next, transient: true);
      _held = next.indexOf(point);
    } else {
      c.beginInteraction();
      _write(next);
      c.endInteraction();
    }
  }

  void _move(Offset p, Size size, AutomationTarget what) {
    var i = _held;
    var points = [..._points];
    if (i == null || i >= points.length) return;
    // Kept between its neighbours: a point dragged past one stays the one
    // being dragged, and the line never doubles back.
    var lo = i > 0 ? points[i - 1].$1 : 0.0;
    var hi = i < points.length - 1 ? points[i + 1].$1 : double.infinity;
    points[i] = (
      _secondsAt(p.dx, size.width).clamp(lo, hi).toDouble(),
      _valueAt(p.dy, size.height, what)
    );
    _write(points, transient: true);
  }

  @override
  Widget build(BuildContext context) {
    var what = AutomationTarget.parse(widget.target);
    var colors = ThemeNotifier.of(context).colors;
    var held =
        c.overridden[widget.channel.key]?.contains(widget.target) ?? false;
    return LayoutBuilder(builder: (context, box) {
      var size = Size(box.maxWidth, box.maxHeight);
      var body = CustomPaint(
        size: size,
        painter: _LanePainter(
          points: _points,
          what: what,
          xOf: (t) => _xOf(t, size.width),
          yOf: (v) => what == null ? 0 : _yOf(v, size.height, what),
          head: widget.view.xOf(c.frame + c.betweenFrames, size.width),
          line: held ? _heldColour : automationColour,
          colors: colors,
          hint: what == null
              ? "Its device is gone"
              : _points.isEmpty
                  ? "Click to put a point down"
                  : null,
        ),
      );
      if (what == null || !widget.channel.editable) return body;
      return GestureDetector(
        key: ValueKey("autoLane-${widget.channel.key}-${widget.target}"),
        supportedDevices: timelinePointers,
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onTapUp: (d) {
          if (_pointAt(d.localPosition, size, what) != null) return;
          _add(d.localPosition, size, what);
        },
        // Right-clicked, a point is taken out.
        onSecondaryTapUp: (d) {
          var i = _pointAt(d.localPosition, size, what);
          if (i == null) return;
          c.beginInteraction();
          _write([..._points]..removeAt(i));
          c.endInteraction();
        },
        onPanStart: (d) {
          var i = _pointAt(d.localPosition, size, what);
          if (i == null) {
            // From where it was pressed: a point there, then dragged.
            _add(d.localPosition, size, what, drag: true);
          } else {
            c.beginInteraction();
            _held = i;
          }
        },
        onPanUpdate: (d) => _move(d.localPosition, size, what),
        onPanEnd: (_) {
          if (_held != null) c.endInteraction();
          _held = null;
        },
        onPanCancel: () {
          if (_held != null) c.endInteraction();
          _held = null;
        },
        child: MouseRegion(cursor: SystemMouseCursors.precise, child: body),
      );
    });
  }
}

class _LanePainter extends CustomPainter {
  final List<AutomationPoint> points;
  final AutomationTarget? what;
  final double Function(double) xOf;
  final double Function(double) yOf;
  final double head;
  final Color line;
  final ColorScheme colors;
  final String? hint;

  _LanePainter({
    required this.points,
    required this.what,
    required this.xOf,
    required this.yOf,
    required this.head,
    required this.line,
    required this.colors,
    required this.hint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size,
        Paint()..color = colors.surfaceContainerLow.withValues(alpha: 0.6));
    canvas.drawLine(
        Offset(0, size.height - 0.5),
        Offset(size.width, size.height - 0.5),
        Paint()..color = colors.outlineVariant);
    if (hint case var h?) {
      var tp = TextPainter(
        text: TextSpan(
            text: h,
            style: TextStyle(
                fontSize: 10.5,
                fontStyle: FontStyle.italic,
                color: colors.onSurfaceVariant.withValues(alpha: 0.7))),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      tp.paint(canvas, Offset(8, (size.height - tp.height) / 2));
    }
    if (points.isNotEmpty && what != null) {
      var steps = what!.steps;
      var path = Path()..moveTo(0, yOf(points.first.$2));
      for (var (i, (t, v)) in points.indexed) {
        var x = xOf(t);
        if (steps && i > 0) path.lineTo(x, yOf(points[i - 1].$2));
        path.lineTo(x, yOf(v));
      }
      path.lineTo(size.width, yOf(points.last.$2));
      var fill = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(fill, Paint()..color = line.withValues(alpha: 0.12));
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..color = line);
      for (var (t, v) in points) {
        var at = Offset(xOf(t), yOf(v));
        if (at.dx < -6 || at.dx > size.width + 6) continue;
        canvas.drawCircle(at, 4, Paint()..color = colors.surface);
        canvas.drawCircle(at, 3.2, Paint()..color = line);
      }
    }
    if (head >= 0 && head <= size.width) {
      canvas.drawLine(
          Offset(head, 0),
          Offset(head, size.height),
          Paint()
            ..strokeWidth = 1.5
            ..color = colors.onSurface.withValues(alpha: 0.7));
    }
  }

  @override
  bool shouldRepaint(_LanePainter old) => true;
}
