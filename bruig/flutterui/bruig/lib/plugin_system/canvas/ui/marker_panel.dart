import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/transport.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart'
    show motionId;
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// marker_panel.dart is the play bar's Marker menu (Ken, 2026-11-08: "the
// marker menu needs a redesign ... more like the length, frame rate settings
// menu"): a panel, as the timing's is. At its top, the markers before and
// after; then the marker under the playhead -- what it does as five picture
// buttons with a line about the one chosen, and its fields captioned under
// them -- or, with none there, the same five buttons to add one; then every
// marker in the canvas, to jump to.

/// markerKinds are the kinds the panel offers, in its order, each with the
/// colour its flag is drawn in.
const markerKinds = [
  (TimelineActionKind.locator, Color(0xFF9A92EA)),
  (TimelineActionKind.stop, Color(0xFFE0564F)),
  (TimelineActionKind.pause, Color(0xFFE2B04A)),
  (TimelineActionKind.loop, Color(0xFF5BC46B)),
  (TimelineActionKind.jump, Color(0xFF7FC8F8)),
];

Color markerColour(TimelineActionKind kind) => markerKinds
    .firstWhere((k) => k.$1 == kind, orElse: () => markerKinds[1])
    .$2;

/// addMarker puts a marker of [kind] under the playhead, in place of any
/// there. A locator is named as addLocator names it.
void addMarker(CanvasController controller, TimelineActionKind kind) {
  var document = controller.document;
  if (kind == TimelineActionKind.locator &&
      !document.actions.any((a) => a.frame == controller.frame)) {
    controller.addLocator();
    return;
  }
  controller.apply(document.copyWith(actions: [
    ...document.actions.where((a) => a.frame != controller.frame),
    TimelineAction(
      id: motionId("m"),
      frame: controller.frame,
      kind: kind,
      // A loop with nothing to loop back to is useless, so it defaults to
      // the start.
      target: 0,
    ),
  ]));
}

void removeMarker(CanvasController controller, int frame) {
  var document = controller.document;
  controller.apply(document.copyWith(
      actions: document.actions.where((a) => a.frame != frame).toList()));
}

void replaceMarker(CanvasController controller, TimelineAction action,
    {bool transient = false}) {
  var document = controller.document;
  controller.apply(
      document.copyWith(actions: [
        ...document.actions.where((a) => a.frame != action.frame),
        action,
      ]),
      transient: transient);
}

/// MarkerPanel is the Marker menu's panel: see the top of the file.
class MarkerPanel extends StatelessWidget {
  final CanvasController controller;
  const MarkerPanel({required this.controller, super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) => CanvasControlScope(
          maxWidth: 360, child: _panel(ThemeNotifier.of(context).colors)));

  Widget _panel(ColorScheme colors) {
    var document = controller.document;
    var frame = controller.frame;
    var sound = document.kind.isAudio;
    var rate = math.max(1, document.frameRate);
    String at(int f) => sound ? barsText(document.audio, f, rate) : "${f + 1}";
    var here = document.actions.where((a) => a.frame == frame).firstOrNull;
    var all = [...document.actions]..sort((a, b) => a.frame.compareTo(b.frame));
    var before = all.where((a) => a.frame < frame).lastOrNull;
    var after = all.where((a) => a.frame > frame).firstOrNull;
    var muted = TextStyle(fontSize: 11, color: colors.onSurfaceVariant);
    Widget caption(String text) => Text(text.toUpperCase(),
        style: TextStyle(
            fontSize: 10,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
            color: colors.onSurfaceVariant));
    void go(int f) => controller.stepFrame(f - controller.frame);

    return SizedBox(
      key: const ValueKey("markerPanel"),
      width: 380,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              caption("Markers"),
              const Spacer(),
              TextButton(
                key: const ValueKey("markerPrevious"),
                onPressed: before == null ? null : () => go(before.frame),
                child: const Text("‹ Previous", style: TextStyle(fontSize: 12)),
              ),
              TextButton(
                key: const ValueKey("markerNext"),
                onPressed: after == null ? null : () => go(after.frame),
                child: const Text("Next ›", style: TextStyle(fontSize: 12)),
              ),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                  child: Text(
                      here == null
                          ? "Add a marker at ${at(frame)}"
                          : "Marker at ${at(frame)}",
                      style: muted)),
              if (here != null)
                TextButton(
                  key: const ValueKey("markerRemove"),
                  onPressed: () => removeMarker(controller, frame),
                  child: const Text("Remove", style: TextStyle(fontSize: 12)),
                ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              for (var (i, (kind, colour)) in markerKinds.indexed) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: _KindTile(
                    key: ValueKey("markerKind-${kind.name}"),
                    label: kind.label,
                    colour: colour,
                    on: here?.kind == kind,
                    colors: colors,
                    onTap: () => here == null
                        ? addMarker(controller, kind)
                        : replaceMarker(controller, here.copyWith(kind: kind)),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 6),
            Text(
                here?.kind.description ??
                    "Pick what the marker does. You can change it after.",
                key: const ValueKey("markerAbout"),
                style: muted.copyWith(height: 1.4)),
            if (here != null) ...[
              const SizedBox(height: 8),
              _fields(here, document.controlsNow, at),
            ],
            const Divider(height: 20),
            caption("In this canvas · ${all.length}"),
            const SizedBox(height: 4),
            for (var a in all)
              _MarkerRow(
                key: ValueKey("markerRow-${a.frame}"),
                action: a,
                at: at(a.frame),
                on: a.frame == frame,
                colors: colors,
                onTap: () => go(a.frame),
              ),
          ]),
    );
  }

  /// _fields are the marker's own settings, captioned as the timing's are.
  Widget _fields(
      TimelineAction here, List<dynamic> controls, String Function(int) at) {
    void write(TimelineAction next) => replaceMarker(controller, next);
    var document = controller.document;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      CanvasTextField(
        key: const ValueKey("actionLabel"),
        label: "Label",
        value: here.label,
        width: here.kind == TimelineActionKind.locator ? 360 : 170,
        grow: false,
        onChanged: (v) {
          controller.beginInteraction();
          replaceMarker(controller, here.copyWith(label: v), transient: true);
        },
        onCommit: controller.endInteraction,
      ),
      if (here.kind != TimelineActionKind.locator)
        CanvasToggle(
          key: const ValueKey("actionShowLabel"),
          label: "Show on the canvas",
          value: here.showLabel,
          onChanged: (v) => write(here.copyWith(showLabel: v)),
        ),
      // A stop that waits for one of the game's actions as well as Play
      // ("press A to start").
      if (here.kind == TimelineActionKind.stop)
        CanvasDropdown<String>(
          key: const ValueKey("actionWaitsFor"),
          label: "Goes on when",
          value: document.controlsNow.any((a) => a.id == here.waitsFor)
              ? here.waitsFor
              : "",
          width: 360,
          options: [
            ("", "It is played again"),
            for (var a in document.controlsNow) (a.id, "${a.name} is pressed"),
          ],
          onChanged: (v) => write(here.copyWith(waitsFor: v)),
        ),
      if (here.kind == TimelineActionKind.loop ||
          here.kind == TimelineActionKind.jump)
        CanvasNumberField(
          key: const ValueKey("actionTarget"),
          label: "To frame",
          value: here.target.toDouble() + 1,
          min: 1,
          max: document.frames.toDouble(),
          width: 80,
          onChanged: (v) => write(here.copyWith(target: v.round() - 1)),
        ),
      if (here.kind == TimelineActionKind.loop)
        CanvasNumberField(
          key: const ValueKey("actionRepeats"),
          label: "Times (0 = ∞)",
          value: here.repeats.toDouble(),
          min: 0,
          max: 999,
          width: 80,
          onChanged: (v) => write(here.copyWith(repeats: v.round())),
        ),
    ]);
  }
}

/// _KindTile is one of the five things a marker can do: its flag, its name.
class _KindTile extends StatelessWidget {
  final String label;
  final Color colour;
  final bool on;
  final ColorScheme colors;
  final VoidCallback onTap;
  const _KindTile(
      {required this.label,
      required this.colour,
      required this.on,
      required this.colors,
      required this.onTap,
      super.key});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            color: on
                ? Color.alphaBlend(colour.withValues(alpha: 0.18),
                    colors.surfaceContainerLowest)
                : colors.surfaceContainerLowest,
            border: Border.all(color: on ? colour : colors.outlineVariant),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            CustomPaint(size: const Size(12, 13), painter: _Flag(colour)),
            const SizedBox(height: 4),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10.5,
                    color: on ? colors.onSurface : colors.onSurfaceVariant)),
          ]),
        ),
      );
}

/// _MarkerRow is a marker in the list: its flag, where it is, its label and
/// what it does; pressed, the playhead goes to it.
class _MarkerRow extends StatelessWidget {
  final TimelineAction action;
  final String at;
  final bool on;
  final ColorScheme colors;
  final VoidCallback onTap;
  const _MarkerRow(
      {required this.action,
      required this.at,
      required this.on,
      required this.colors,
      required this.onTap,
      super.key});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: on ? colors.primary.withValues(alpha: 0.18) : null,
          ),
          child: Row(children: [
            CustomPaint(
                size: const Size(10, 12),
                painter: _Flag(markerColour(action.kind))),
            const SizedBox(width: 8),
            SizedBox(
              width: 64,
              child: Text(at,
                  style: TextStyle(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontSize: 11,
                      color: colors.onSurfaceVariant)),
            ),
            Expanded(
              child: Text(action.label.isEmpty ? "—" : action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: colors.onSurface)),
            ),
            Text(action.kind.label,
                style:
                    TextStyle(fontSize: 10.5, color: colors.onSurfaceVariant)),
          ]),
        ),
      );
}

/// _Flag is a marker's flag, as the ruler draws it.
class _Flag extends CustomPainter {
  final Color colour;
  const _Flag(this.colour);

  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()..color = colour;
    canvas.drawRect(Rect.fromLTWH(0, 0, 1.4, size.height), paint);
    canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(size.width, size.height * 0.27)
          ..lineTo(0, size.height * 0.55)
          ..close(),
        paint);
  }

  @override
  bool shouldRepaint(_Flag old) => old.colour != colour;
}
