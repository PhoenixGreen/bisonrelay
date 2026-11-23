import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart' show DeviceParam;
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/motion/motion_editing.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// panel_parts.dart is what every element's settings are built from: the
// quick strip, state notes, a box placement picker, looks as rows (the
// Chain's own), and motion as lines opening the Chain, each the same on
// every element; and the small things every panel shares: how it writes
// the element, a keyframe diamond for a value, a boxed section, a number as
// a heading's summary says it.

/// CanvasQuickStrip is an element's most-changed settings in a card over
/// its sections, never a section away.
class CanvasQuickStrip extends StatelessWidget {
  final List<Widget> children;
  const CanvasQuickStrip({required this.children, super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: theme.colors.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border.all(color: theme.colors.outlineVariant),
      ),
      // Laid out as a section's controls are, a size up.
      child: CanvasCards(
        title: "",
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
          child: CanvasDense(
            height: 36,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

/// panelRow lays controls across the line, each [flex] a share or [width]
/// fixed; too narrow for all, they stack.
Widget panelRow(List<(Widget, {int flex, double? width, double min})> cells) =>
    LayoutBuilder(builder: (context, room) {
      var least = 0.0;
      for (var c in cells) {
        least += c.width ?? c.min;
      }
      if (room.maxWidth.isFinite && room.maxWidth < least) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var (i, c) in cells.indexed) ...[
              if (i > 0) const SizedBox(height: 8),
              CanvasCellFill(child: c.$1),
            ],
          ],
        );
      }
      return SizedBox(
        width: double.infinity,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var (w, flex: f, width: fixed, min: _) in cells)
              if (fixed != null)
                SizedBox(width: fixed, child: CanvasCellFill(child: w))
              else
                Expanded(flex: f, child: CanvasCellFill(child: w)),
          ],
        ),
      );
    });

/// cell is one control of a panelRow: [min] is the least it can be drawn at
/// beside the others.
(Widget, {int flex, double? width, double min}) cell(Widget w,
        {int flex = 1, double? width, double min = 84}) =>
    (w, flex: flex, width: width, min: min);

/// CanvasAddChip is a small rounded button for adding one of several things
/// (a look) without a row of full-size buttons.
class CanvasAddChip extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const CanvasAddChip(this.label, {required this.onPressed, super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6, bottom: 6),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          // A dashed edge: something not there yet.
          child: CustomPaint(
            painter: _DashedPill(theme.colors.outline.withValues(alpha: 0.7)),
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              // As wide as its words, not the line.
              child: Center(
                widthFactor: 1,
                child: Text(label,
                    style: TextStyle(
                        fontSize: 12, color: theme.colors.onSurfaceVariant)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedPill extends CustomPainter {
  final Color colour;
  const _DashedPill(this.colour);

  @override
  void paint(Canvas canvas, Size size) {
    var r = size.height / 2;
    var path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5), Radius.circular(r)));
    var line = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 6) {
        canvas.drawPath(m.extractPath(d, math.min(d + 3.5, m.length)), line);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPill old) => old.colour != colour;
}

/// KeyDiamond is a key's mark, as the Chain's Keyframes card draws it: a
/// square on its point, filled where there is a key.
class KeyDiamond extends StatelessWidget {
  final bool filled;
  final double size;
  const KeyDiamond({this.filled = false, this.size = 12, super.key});

  @override
  Widget build(BuildContext context) {
    var colour = IconTheme.of(context).color ?? Colors.white;
    return SizedBox(
      width: size,
      height: size,
      child: Transform.rotate(
        angle: math.pi / 4,
        child: Container(
          margin: EdgeInsets.all(size * 0.15),
          decoration: BoxDecoration(
            color: filled ? colour : null,
            border: Border.all(color: colour, width: 1.4),
          ),
        ),
      ),
    );
  }
}

/// CanvasStateNote says why a setting is not doing what it seems to (a size
/// worked out from the box) and offers the way out beside it.
class CanvasStateNote extends StatelessWidget {
  final String text;
  final String? action;
  final VoidCallback? onAction;
  const CanvasStateNote(this.text, {this.action, this.onAction, super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var accent = theme.colors.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: accent.withValues(alpha: 0.10),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Icon(Icons.info_outline, size: 16, color: accent),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12, color: theme.colors.onSurfaceVariant))),
        if (action != null && onAction != null)
          TextButton(
            key: ValueKey("stateNote-$action"),
            onPressed: onAction,
            style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: Text(action!, style: const TextStyle(fontSize: 12)),
          ),
      ]),
    );
  }
}

/// CanvasSlotPicker is where in a box something sits, as a picture of the
/// box: nine places, the current one lit.
class CanvasSlotPicker extends StatelessWidget implements CanvasGrowable {
  final String label;
  final TextSlot value;
  final ValueChanged<TextSlot> onChanged;
  const CanvasSlotPicker(
      {this.label = "Where",
      required this.value,
      required this.onChanged,
      super.key});

  @override
  double get least => 74;

  @override
  bool get grow => false;

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var accent = theme.colors.primary;
    Widget cell(TextSlot s) => Tooltip(
          message: s.label,
          child: InkWell(
            key: ValueKey("slot-${s.name}"),
            onTap: () => onChanged(s),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: s == value ? accent : null,
                border: Border.all(
                    color: s == value
                        ? accent
                        : theme.colors.outline.withValues(alpha: 0.6)),
              ),
            ),
          ),
        );
    return canvasLabelled(
      context,
      label,
      SizedBox(
        width: 74,
        height: canvasControlHeight(context),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colors.outlineVariant),
          ),
          // Three rows of three, sharing the height whatever it is.
          child: Column(children: [
            for (var row = 0; row < 3; row++) ...[
              if (row > 0) const SizedBox(height: 2),
              Expanded(
                child: Row(children: [
                  for (var col = 0; col < 3; col++) ...[
                    if (col > 0) const SizedBox(width: 3),
                    Expanded(child: cell(TextSlot.values[row * 3 + col])),
                  ],
                ]),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Looks

/// LookParamView is how a look's setting reads, the same in panel and
/// Chain: a share as a percentage, a shadow's angle as where it falls.
class LookParamView {
  final String label;

  /// times is what the stored value is multiplied by to be shown.
  final double times;
  final String suffix;
  final int decimals;
  const LookParamView(this.label, this.times, this.suffix, this.decimals);

  double shown(double stored) => stored * times;
  double stored(double shown) => shown / times;
}

/// lookParamView is how [p], a setting of a look, reads, as its Chain knob
/// does (DeviceParam.reading).
LookParamView lookParamView(DeviceParam p) {
  if (p.unit == "") return LookParamView(p.label, 100, "%", 0);
  return switch (p.unit) {
    "px" => LookParamView(p.label, 1, " px", p.max <= 40 ? 1 : 0),
    "°" => LookParamView(p.label, 1, "°", 0),
    "×" => LookParamView(p.label, 1, "×", 2),
    "/s" => LookParamView(p.label, 1, "/s", 2),
    _ => LookParamView(p.label, 1, "", p.max - p.min <= 4 ? 2 : 0),
  };
}

/// lookMain is the one setting shown on a look's row: the most turned.
String lookMain(MotionDeviceKind kind) => switch (kind) {
      MotionDeviceKind.outline => "width",
      MotionDeviceKind.shadow => "strength",
      MotionDeviceKind.glow => "strength",
      MotionDeviceKind.blur => "amount",
      MotionDeviceKind.colour => "saturation",
      MotionDeviceKind.wear => "amount",
      MotionDeviceKind.edges => "feather",
      MotionDeviceKind.lens => "zoom",
      _ => kind.params.first.id,
    };

/// lookTakesColour is whether a look of [kind] draws in a colour of its own.
bool lookTakesColour(MotionDeviceKind kind) =>
    kind == MotionDeviceKind.outline ||
    kind == MotionDeviceKind.shadow ||
    kind == MotionDeviceKind.glow;

/// _offeredLooks are the kinds of look that can be added.
const List<MotionDeviceKind> _offeredLooks = [
  MotionDeviceKind.outline,
  MotionDeviceKind.shadow,
  MotionDeviceKind.glow,
  MotionDeviceKind.blur,
  MotionDeviceKind.colour,
  MotionDeviceKind.wear,
  MotionDeviceKind.edges,
];

/// LooksGroup is [element]'s looks on [layer] as rows, the Chain's own, and
/// the looks it could add; a row opens to show the rest.
class LooksGroup extends StatefulWidget {
  final CanvasController controller;
  final CanvasElement element;

  /// layer is what of the element they are on: see MotionDevice.layer.
  final String layer;
  final String title;

  const LooksGroup({
    required this.controller,
    required this.element,
    required this.title,
    this.layer = "",
    super.key,
  });

  @override
  State<LooksGroup> createState() => _LooksGroupState();
}

/// _open are the look rows opened, by element and look, for the session.
final Set<String> _open = {};

/// forgetLooksForTest shuts every look's settings, as a new run has them.
@visibleForTesting
void forgetLooksForTest() => _open.clear();

class _LooksGroupState extends State<LooksGroup> {
  CanvasController get c => widget.controller;
  String get id => widget.element.id;

  List<MotionDevice> get _all => c.motionDevicesOf(id);

  void _put(MotionDevice next) {
    c.beginInteraction();
    c.setMotionDevices(id, [for (var d in _all) d.id == next.id ? next : d],
        transient: true);
    c.endInteraction();
  }

  void _add(MotionDeviceKind kind) {
    var before = {for (var d in _all) d.id};
    var next =
        withMotionDeviceIds([..._all, MotionDevice(kind, layer: widget.layer)]);
    c.beginInteraction();
    c.setMotionDevices(id, next);
    c.endInteraction();
    var added = next.where((d) => !before.contains(d.id)).firstOrNull;
    if (added != null) setState(() => _open.add("$id:${added.id}"));
  }

  void _remove(MotionDevice d) {
    c.beginInteraction();
    c.setMotionDevices(id, [
      for (var x in _all)
        if (x.id != d.id) x
    ]);
    c.endInteraction();
  }

  /// _now is setting [p] of [d] at the playhead: by its keys where it is
  /// animated.
  double _now(MotionDevice d, DeviceParam p) =>
      d.keyed(p.id) ? c.deviceValueNow(id, d, p.id) : d.value(p.id);

  /// _set changes setting [p] of [d]: a key at the playhead where animated,
  /// its resting value where not, as the Chain's knob does.
  void _set(MotionDevice d, DeviceParam p, double stored) =>
      c.setDeviceSetting(id, d.id, p.id, stored, transient: true);

  Widget _number(MotionDevice d, DeviceParam p) {
    var view = lookParamView(p);
    return CanvasNumberField(
      key: ValueKey("look-${d.id}-${p.id}"),
      label: d.keyed(p.id) ? "${view.label} (keyed)" : view.label,
      value: view.shown(_now(d, p)),
      min: view.shown(p.min),
      max: view.shown(p.max),
      decimals: view.decimals,
      suffix: view.suffix,
      width: 64,
      onChanged: (v) => _set(d, p, view.stored(v)),
      onCommit: c.endInteraction,
    );
  }

  /// _keyed says which of [d]'s settings are animated, and when.
  List<Widget> _keyed(MotionDevice d) => [
        for (var p in d.kind.params)
          if (d.keyed(p.id))
            CanvasReadout(
              key: ValueKey("lookKeys-${d.id}-${p.id}"),
              label: "${lookParamView(p).label} animated",
              value: "${d.keys[p.id]!.length} keys, "
                  "${d.keys[p.id]!.first.t.toStringAsFixed(1)}"
                  "–${d.keys[p.id]!.last.t.toStringAsFixed(1)} s",
            ),
      ];

  Widget _row(BuildContext context, MotionDevice d) {
    var theme = ThemeNotifier.of(context);
    var key = "$id:${d.id}";
    var open = _open.contains(key);
    var main = d.kind.param(lookMain(d.kind));
    var view = lookParamView(main);
    var rest = [
      for (var p in d.kind.params)
        if (p.id != main.id) p
    ];
    return Container(
      key: ValueKey("lookRow-${d.id}"),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
            // Name, main setting and switch on one line; in a narrow sidebar
            // the setting goes under the name.
            child: LayoutBuilder(builder: (context, room) {
              var name = InkWell(
                key: ValueKey("lookOpen-${d.id}"),
                borderRadius: BorderRadius.circular(8),
                onTap: () =>
                    setState(() => open ? _open.remove(key) : _open.add(key)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    AnimatedRotation(
                      turns: open ? 0.25 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: Icon(Icons.chevron_right,
                          size: 18, color: theme.colors.onSurfaceVariant),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(d.kind.label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: d.on
                                  ? theme.colors.onSurface
                                  : theme.colors.onSurfaceVariant)),
                    ),
                    // Animated in the Chain: shown, not keyed, here, as the
                    // keys are the Chain's.
                    if (d.animated) ...[
                      const SizedBox(width: 6),
                      IconTheme(
                        data: const IconThemeData(color: Color(0xFFF2C14E)),
                        child: KeyDiamond(
                            key: ValueKey("lookAnimated-${d.id}"),
                            filled: true,
                            size: 10),
                      ),
                    ],
                  ]),
                ),
              );
              var stepper = CanvasStepper(
                key: ValueKey("lookMain-${d.id}"),
                label: "",
                name: "lookMain-${d.id}",
                fill: true,
                value: view.shown(_now(d, main)),
                min: view.shown(main.min),
                max: view.shown(main.max),
                decimals: view.decimals,
                suffix: view.suffix,
                onChanged: (v) => _set(d, main, view.stored(v)),
                onCommit: c.endInteraction,
              );
              var power = CanvasSwitch(
                key: ValueKey("lookOn-${d.id}"),
                value: d.on,
                onChanged: (v) => _put(d.switched(v)),
              );
              if (room.maxWidth < 240) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [Expanded(child: name), power]),
                    stepper,
                  ],
                );
              }
              return Row(children: [
                Expanded(child: name),
                SizedBox(width: 116, child: stepper),
                power,
              ]);
            }),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: CanvasControlGroup(
                  label: d.kind.label,
                  hideCaption: true,
                  rule: false,
                  children: [
                    for (var p in rest)
                      if (p.isChoice)
                        CanvasDropdown<int>(
                          key: ValueKey("look-${d.id}-${p.id}"),
                          label: p.label,
                          value: d.value(p.id).round(),
                          width: 120,
                          options: [
                            for (var (i, ch) in p.choices.indexed) (i, ch)
                          ],
                          onChanged: (v) =>
                              _put(d.withValue(p.id, v.toDouble())),
                        )
                      else
                        _number(d, p),
                    ..._keyed(d),
                    if (lookTakesColour(d.kind))
                      CanvasColorButton(
                        key: ValueKey("lookColour-${d.id}"),
                        label: "Colour",
                        color: Color(d.colour ?? 0xFF000000),
                        onChanged: (col) => _put(d.withColour(col.toARGB32())),
                      ),
                    const CanvasLineBreak(),
                    CanvasTextButton(
                      key: ValueKey("lookInChain-${d.id}"),
                      label: "Show in the Chain",
                      tooltip: "Where it is animated, with its other devices",
                      grow: false,
                      onPressed: () => c.showInChain(id, d.id),
                    ),
                    CanvasTextButton(
                      key: ValueKey("lookRemove-${d.id}"),
                      label: "Remove",
                      grow: false,
                      onPressed: () => _remove(d),
                    ),
                  ]),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var mine = [
      for (var d in _all)
        if (d.side == MotionDeviceSide.look && d.layer == widget.layer) d
    ];
    var have = {for (var d in mine) d.kind};
    var addable = [
      for (var k in _offeredLooks)
        if (!have.contains(k)) k
    ];
    return CanvasControlGroup(
        key: ValueKey("looks-${widget.layer.isEmpty ? "all" : widget.layer}"),
        label: widget.title,
        rule: false,
        help: "These are the element's looks in its Chain, the same ones: "
            "set here they are how it rests, and the Chain animates the "
            "same settings.",
        children: [
          SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [for (var d in mine) _row(context, d)],
            ),
          ),
          if (addable.isNotEmpty)
            SizedBox(
              width: double.infinity,
              child: Wrap(children: [
                for (var k in addable)
                  CanvasAddChip(
                    "+ ${k.label}",
                    key: ValueKey(
                        "lookAdd-${widget.layer.isEmpty ? "all" : widget.layer}-${k.name}"),
                    onPressed: () => _add(k),
                  ),
              ]),
            ),
        ]);
  }
}

// ---------------------------------------------------------------------------
// Motion

/// MotionSummary is [element]'s motion in a line each (arrival, movement,
/// exit), each opening the Chain, where motion lives.
class MotionSummary extends StatelessWidget {
  final CanvasController controller;
  final CanvasElement element;

  /// note is said over the lines: a piece of a text moves with the text.
  final String? note;

  const MotionSummary(
      {required this.controller, required this.element, this.note, super.key});

  @override
  Widget build(BuildContext context) {
    var e = element;
    var m = e.base.motion;
    String secs(double s) => "${s.toStringAsFixed(1)} s";
    var cue = controller.cues.where((q) => q.id == e.base.cue).firstOrNull;
    var lines = <Widget>[];
    var placed = [...m.placed]..sort((a, b) => a.start.compareTo(b.start));
    for (var p in placed) {
      var clip = m.clip(p.clip);
      if (clip == null) continue;
      var length = p.length ?? clip.span;
      var said = switch (clip.kind) {
        MotionKind.arrive =>
          cue != null ? "Arrives on “${cue.name}”" : "Arrives",
        MotionKind.leave => "Leaves",
        MotionKind.loop => "Loops",
        _ => clip.kind.label,
      };
      var name = clip.name.isNotEmpty &&
              clip.name != "Arrives" &&
              clip.name != "Leaves"
          ? ": ${clip.name}"
          : "";
      lines.add(_MotionLine(
        key: ValueKey("motionLine-${p.id}"),
        colour: switch (clip.kind) {
          MotionKind.arrive => const Color(0xFF2ED6A1),
          MotionKind.leave => const Color(0xFFE36F8E),
          _ => const Color(0xFF5B9BFF),
        },
        title: "$said$name",
        detail: "at ${secs(p.start)}, takes ${secs(length)}",
        onTap: () =>
            controller.showInChain(e.id, null, clip: clip.id, placement: p.id),
      ));
    }
    if (m.poseDevices.isNotEmpty) {
      lines.add(_MotionLine(
        key: const ValueKey("motionLine-devices"),
        colour: const Color(0xFFF2C14E),
        title: "Moved by ${[
          for (var d in m.poseDevices) d.kind.label
        ].join(", ")}",
        detail: "in its Chain, after its clips",
        onTap: () => controller.showInChain(e.id, m.poseDevices.first.id),
      ));
    }
    // Settings animated by keys: a look rising as it arrives, a move
    // easing off.
    for (var d in m.devices) {
      for (var p in d.kind.params) {
        if (!d.keyed(p.id)) continue;
        var ks = d.keys[p.id]!;
        var label =
            d.side == MotionDeviceSide.look ? lookParamView(p).label : p.label;
        var on = d.layer.isEmpty ? "" : " on ${_layerSaid(e, d.layer)}";
        lines.add(_MotionLine(
          key: ValueKey("motionLine-keys-${d.id}-${p.id}"),
          colour: const Color(0xFFF2C14E),
          title: "${d.kind.label} ${label.toLowerCase()}$on, animated",
          detail:
              "${ks.length} keys, ${secs(ks.first.t)} to ${secs(ks.last.t)}",
          onTap: () => controller.showInChain(e.id, d.id),
        ));
      }
    }
    if (lines.isEmpty) {
      lines.add(_MotionLine(
        key: const ValueKey("motionLine-none"),
        colour: ThemeNotifier.of(context).colors.outline,
        title: "Still: nothing moves it",
        detail: "Give it an arrival or a move in its Chain",
        onTap: () => controller.showInChain(e.id, null),
      ));
    }
    return CanvasControlGroup(
        key: const ValueKey("motionSummary"),
        label: "Motion",
        hideCaption: true,
        rule: false,
        children: [
          SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(note!,
                        style: TextStyle(
                            fontSize: 12,
                            color: ThemeNotifier.of(context)
                                .colors
                                .onSurfaceVariant)),
                  ),
                ...lines,
              ],
            ),
          ),
          CanvasTextButton(
            key: const ValueKey("motionOpenChain"),
            label: "Open its Chain",
            grow: false,
            onPressed: () => controller.showInChain(e.id, null),
          ),
        ]);
  }
}

/// _layerSaid is what of [e] layer [layer] is, in a word or two.
String _layerSaid(CanvasElement e, String layer) {
  if (layer == MotionDevice.bodyLayer) return "its words";
  if (e is TextElement) {
    for (var item in e.items) {
      if (item.id == layer) return item.says;
    }
  }
  return layer;
}

class _MotionLine extends StatelessWidget {
  final Color colour;
  final String title;
  final String detail;
  final VoidCallback onTap;
  const _MotionLine(
      {required this.colour,
      required this.title,
      required this.detail,
      required this.onTap,
      super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.colors.outlineVariant),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 4, right: 10),
                decoration: BoxDecoration(
                    color: colour, borderRadius: BorderRadius.circular(3)),
              ),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontSize: 13, color: theme.colors.onSurface)),
                      Text(detail,
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colors.onSurfaceVariant)),
                    ]),
              ),
              Text("Chain ›",
                  style: TextStyle(fontSize: 12, color: theme.colors.primary)),
            ]),
          ),
        ),
      ),
    );
  }
}

typedef SettingsWrite = void Function(CanvasElement);

/// freshOf is [e] as the document has it now, or null: after an await the
/// old read may be stale, and writing it back would undo changes.
T? freshOf<T extends CanvasElement>(CanvasController controller, T e) {
  var now = controller.document.elementById(e.id);
  return now is T ? now : null;
}

/// valueDot is the diamond beside an animatable property: a real channel,
/// so a key can pin a caption's slide without pinning its box.
Widget valueDot(CanvasController controller, CanvasElement e, String channel,
    String what, double value) {
  var animated = controller.document.isAnimated;
  var on = controller.hasValueKey(e, channel);
  return CanvasKeyframeDot(
    on: on,
    enabled: animated,
    tooltip: !animated
        ? "Give the canvas more than one frame to animate $what"
        : on
            ? "Remove the keyframe for $what here"
            : "Add a keyframe for $what here",
    onPressed: () {
      controller.beginInteraction();
      if (on) {
        controller.clearValueKey(e, channel);
      } else {
        controller.setValueKey(e, channel, value);
      }
      controller.endInteraction();
    },
  );
}

/// boxed draws a rule and a gap round a section that is a panel (a table
/// with scrollbars), giving it an edge among captioned groups.
Widget boxed(BuildContext context, Widget child) => Builder(
    // Asked where drawn, not of [context], which is above any section: in a
    // section the box is the card the expander draws itself as.
    builder: (context) =>
        CanvasCards.on(context) ? child : _boxed(context, child));

Widget _boxed(BuildContext context, Widget child) {
  var theme = ThemeNotifier.of(context);
  return Padding(
    // A group's own gap below, so boxed sections and captioned groups space
    // alike.
    padding: const EdgeInsets.only(bottom: canvasGroupGap),
    // Builder, because the settings' context is above the CanvasControlScope
    // that says column or band, so asking it directly always says "band".
    child: Builder(
      builder: (context) => Container(
        // Full column width, open or shut: sized to itself, a shut section
        // shrinks to its heading and reads as a stray button.
        width: double.infinity,
        // Equal above and below, so a heading's button is not hard against
        // the top.
        padding: const EdgeInsets.fromLTRB(7, 5, 7, 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.colors.outlineVariant),
          color: theme.colors.surfaceContainerHighest.withValues(alpha: 0.25),
        ),
        child: child,
      ),
    ),
  );
}

/// shortNumber is [v] as a summary writes it: whole where whole, else to
/// one place.
String shortNumber(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
