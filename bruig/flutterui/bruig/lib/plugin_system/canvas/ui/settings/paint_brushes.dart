import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/image_strokes.dart';
import 'package:bruig/plugin_system/canvas/render/brush_painter.dart';
import 'package:bruig/plugin_system/canvas/storage/saved_preset_store.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// paint_brushes.dart is the paint brush's settings: the brushes to start
// from -- the ones that come with the canvas and the ones somebody kept --
// each drawn as a stroke of itself; the tip's shape; how the pen drives it;
// and keeping the brush as it is now. See BrushTip and BrushPreset.

/// PaintBrushCards are the paint brush's cards, under the paint tools.
class PaintBrushCards extends StatefulWidget {
  final CanvasController controller;
  const PaintBrushCards({required this.controller, super.key});

  @override
  State<PaintBrushCards> createState() => _PaintBrushCardsState();
}

class _PaintBrushCardsState extends State<PaintBrushCards> {
  final store = SavedPresetStore.paintBrushes;
  String? _name;

  CanvasController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    store.load();
  }

  /// _brushes is every brush there is to choose: the canvas's own, then
  /// the ones kept.
  List<BrushPreset> _brushes() => [
        ...brushPresets,
        for (var p in store.presets) BrushPreset.fromJson(p.id, p.name, p.data),
      ];

  void _tip(BrushTip Function(BrushTip) change) =>
      controller.paintTip = change(controller.paintTip);

  /// _percent is a 0..1 tip setting as a percentage stepper.
  Widget _percent(String key, String label, double value, double initial,
          BrushTip Function(BrushTip, double) set,
          {double max = 100}) =>
      CanvasStepper(
        key: ValueKey(key),
        label: label,
        value: value * 100,
        min: 0,
        max: max,
        step: 5,
        dragStep: 1,
        suffix: "%",
        defaultValue: initial * 100,
        onChanged: (v) => _tip((t) => set(t, v / 100)),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          var brushes = _brushes();
          // Read while building: a tile's picture is drawn while painting,
          // and the theme cannot be asked for then.
          var ground = ThemeNotifier.of(context).colors.surfaceContainerHighest;
          var tip = controller.paintTip;
          var saved = store.presets
              .where((p) => p.id == controller.paintBrush)
              .firstOrNull;
          var name = _name ?? "Brush ${store.presets.length + 1}";
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              CanvasTiles<String>(
                key: const ValueKey("paintBrushes"),
                label: "Brushes",
                foldAs: "image.tiles.brush",
                help: "Each brush is drawn as a stroke of itself. Pick one to "
                    "start from; change it below, and keep it as your own.",
                columns: 3,
                previewHeight: 34,
                tiles: [
                  for (var b in brushes)
                    CanvasTile(b.id, b.name,
                        drawnFrom: (
                          b.tip,
                          b.size,
                          b.hardness,
                          b.strength,
                          controller.paintColour
                        ),
                        paint: (canvas, size) =>
                            _PreviewPainter(b, controller.paintColour, ground)
                                .paint(canvas, size)),
                ],
                selected: (id) => controller.paintBrush == id,
                keyOf: (id) => "paintBrush-$id",
                onPick: (id) =>
                    controller.useBrush(brushes.firstWhere((b) => b.id == id)),
              ),
              CanvasControlGroup(
                key: const ValueKey("paintTipGroup"),
                label: "Brush tip",
                help: "The shape of the tip and how the paint goes down. A "
                    "flat tip lies at its angle -- or, following the pen, the "
                    "way the pen leans. Spacing is how far apart its dabs "
                    "are, scatter throws them off the line, and grain leaves "
                    "the gaps paper does.",
                rule: false,
                children: [
                  _percent("paintRound", "Roundness", tip.roundness, 1,
                      (t, v) => t.copyWith(roundness: math.max(0.05, v))),
                  CanvasStepper(
                    key: const ValueKey("paintAngle"),
                    label: "Angle",
                    value: tip.angle,
                    min: -180,
                    max: 180,
                    step: 15,
                    dragStep: 1,
                    suffix: "°",
                    defaultValue: 0,
                    onChanged: (v) => _tip((t) => t.copyWith(angle: v)),
                  ),
                  CanvasToggle(
                    key: const ValueKey("paintFollowTilt"),
                    label: "Turn with the pen's lean",
                    value: tip.followTilt,
                    onChanged: (v) => _tip((t) => t.copyWith(followTilt: v)),
                  ),
                  _percent("paintSpacing", "Spacing", tip.spacing, 0.2,
                      (t, v) => t.copyWith(spacing: math.max(0.02, v)),
                      max: 200),
                  _percent("paintScatter", "Scatter", tip.scatter, 0,
                      (t, v) => t.copyWith(scatter: v),
                      max: 200),
                  _percent("paintGrain", "Grain", tip.grain, 0,
                      (t, v) => t.copyWith(grain: v)),
                ],
              ),
              CanvasControlGroup(
                key: const ValueKey("paintPenGroup"),
                label: "Pen",
                help: "How a pen -- a Wacom Pro Pen 3, say -- drives the "
                    "brush. Pressure can thin the line, fade it, or both; "
                    "the curve says how hard a press it takes to reach the "
                    "full line. Leaning the pen over can widen it, as the "
                    "side of a pencil does. A mouse paints at full pressure, "
                    "upright.",
                rule: false,
                children: [
                  _percent(
                      "paintPressureSize",
                      "Pressure to size",
                      tip.pressureSize,
                      0.75,
                      (t, v) => t.copyWith(pressureSize: v)),
                  _percent(
                      "paintPressureOpacity",
                      "Pressure to opacity",
                      tip.pressureOpacity,
                      0,
                      (t, v) => t.copyWith(pressureOpacity: v)),
                  CanvasDropdown<double>(
                    key: const ValueKey("paintPressureCurve"),
                    label: "Pressure curve",
                    value: _curves.any((c) => c.$1 == tip.pressureCurve)
                        ? tip.pressureCurve
                        : 1,
                    width: 128,
                    options: _curves,
                    onChanged: (v) => _tip((t) => t.copyWith(pressureCurve: v)),
                  ),
                  _percent("paintTiltSize", "Tilt to size", tip.tiltSize, 0,
                      (t, v) => t.copyWith(tiltSize: v),
                      max: 300),
                ],
              ),
              CanvasControlGroup(
                key: const ValueKey("paintKeepGroup"),
                label: "Your brushes",
                help: "Keep the brush as it is set now -- its size, "
                    "softness, strength, tip and pen -- to pick again from "
                    "the brushes above, on any paint layer.",
                rule: false,
                children: [
                  CanvasTextField(
                    key: const ValueKey("paintBrushName"),
                    label: "Name",
                    value: name,
                    width: 140,
                    onChanged: (v) => setState(() => _name = v),
                  ),
                  CanvasTextButton(
                    key: const ValueKey("paintBrushSave"),
                    icon: Icons.bookmark_add_outlined,
                    label: "Keep this brush",
                    onPressed: name.trim().isEmpty
                        ? null
                        : () async {
                            // The same name again is the same brush, changed.
                            for (var p in store.presets
                                .where((p) => p.name == name.trim())) {
                              await store.remove(p);
                            }
                            var kept = await store.save(
                                name, controller.currentBrush(name).toJson());
                            if (kept != null) {
                              controller.useBrush(BrushPreset.fromJson(
                                  kept.id, kept.name, kept.data));
                            }
                            if (mounted) setState(() => _name = null);
                          },
                  ),
                  if (saved != null)
                    CanvasTextButton(
                      key: const ValueKey("paintBrushDelete"),
                      icon: Icons.delete_outline,
                      label: "Delete ${saved.name}",
                      onPressed: () async {
                        await store.remove(saved);
                        controller.useBrush(brushPresets.first);
                      },
                    ),
                ],
              ),
            ],
          );
        },
      );
}

/// _curves are the pressure curves offered: how hard a press the full line
/// takes.
const List<(double, String)> _curves = [
  (0.5, "Soft — light touch"),
  (0.75, "Light"),
  (1, "Even"),
  (1.5, "Firm"),
  (2.2, "Hard — full press"),
];

/// BrushPreview is a brush drawn as a stroke of itself: a wave across, the
/// pressure rising and falling, the pen leaning as a hand does.
class BrushPreview extends StatelessWidget {
  final BrushPreset brush;
  final Color colour;
  const BrushPreview(this.brush, {required this.colour, super.key});

  @override
  Widget build(BuildContext context) => CustomPaint(
      painter: _PreviewPainter(brush, colour,
          ThemeNotifier.of(context).colors.surfaceContainerHighest));
}

class _PreviewPainter extends CustomPainter {
  final BrushPreset brush;
  final Color colour;
  final Color ground;
  _PreviewPainter(this.brush, this.colour, this.ground);

  @override
  void paint(Canvas canvas, Size size) {
    var all = Offset.zero & size;
    canvas.drawRect(all, Paint()..color = ground);
    const n = 40;
    var points = <Offset>[], pressure = <double>[], tilt = <Offset>[];
    for (var i = 0; i <= n; i++) {
      var t = i / n;
      points.add(Offset(size.width * (0.1 + 0.8 * t),
          size.height * (0.5 + 0.25 * math.sin(t * math.pi * 2))));
      pressure.add(math.sin(t * math.pi).clamp(0.15, 1.0));
      tilt.add(Offset(0.5, -0.4 + 0.8 * t));
    }
    // The brush's size against a picture a few tiles across, so a fine
    // pen and a broad airbrush look like themselves side by side.
    var radius = (brush.size * size.width * 4).clamp(1.0, size.height * 0.35);
    canvas.saveLayer(
        all, Paint()..color = Color.fromRGBO(0, 0, 0, brush.strength));
    paintDabs(canvas, points, pressure, radius, brush.hardness,
        Paint()..color = colour,
        tip: brush.tip, tilt: tilt, seed: brush.id.hashCode);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PreviewPainter old) =>
      old.brush.id != brush.id ||
      old.brush.tip != brush.tip ||
      old.colour != colour ||
      old.ground != ground;
}
