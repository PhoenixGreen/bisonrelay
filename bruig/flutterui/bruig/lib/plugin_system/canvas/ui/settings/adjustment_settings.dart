import 'dart:math' as math;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/render/canvas_perf.dart';
import 'package:bruig/plugin_system/canvas/model/colour_cube.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_adjustment.dart';
import 'package:bruig/plugin_system/canvas/presets/film_tables.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/raster_cache.dart';
import 'package:flutter/material.dart';

// adjustment_settings.dart is an adjustment layer's settings: what it does,
// and the numbers, colours and curves it uses (see image_adjustment.dart).

/// adjustStep is an arrow's step for [p]: a twentieth of a percentage's
/// range, a fiftieth of any other, rounded at the field's precision.
double adjustStep(AdjustParam p) {
  var span = (p.max - p.min) * (p.percent ? 100 : 1);
  var raw = span / (p.percent ? 20 : 50);
  var digit = 1 / math.pow(10, p.decimals);
  return math.max(digit, (raw / digit).roundToDouble() * digit);
}

/// adjustmentSettings is the picked adjustment layer's settings.
List<Widget> adjustmentSettings(
    CanvasController controller,
    ImageElement e,
    ImageLayer layer,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit,
    {bool kindPicker = true}) {
  var adjust = layer.adjust;
  ImageElement withAdjust(ImageAdjustment next) =>
      e.withLayer(layer.id, (l) => l.copyWith(adjust: next));
  void now(ImageAdjustment next) {
    begin();
    write(withAdjust(next));
    commit();
  }

  void live(ImageAdjustment next) {
    begin();
    write(withAdjust(next));
  }

  return [
    CanvasControlGroup(
      key: const ValueKey("adjustGroup"),
      label: "Adjustment",
      // Under tiles, in a section of the same name, the caption and reset
      // are the section's.
      hideCaption: !kindPicker,
      rule: false,
      children: [
        if (kindPicker)
          CanvasDropdown<AdjustKind>(
            key: const ValueKey("adjustKind"),
            label: "Does",
            value: adjust.kind,
            width: 180,
            options: [for (var k in AdjustKind.values) (k, k.label)],
            // Each kind previewed on the canvas as the pointer passes.
            onPreview: (k) => controller.tryElement(
                k == null ? null : withAdjust(adjust.copyWith(kind: k))),
            onChanged: (k) => now(adjust.copyWith(kind: k)),
          ),
        if (kindPicker)
          CanvasIconButton(
            key: const ValueKey("adjustReset"),
            icon: Icons.restore,
            tooltip: "Back to where it starts",
            onPressed: adjust.values.isEmpty && adjust.curves.isEmpty
                ? null
                : () => now(ImageAdjustment(
                    kind: adjust.kind,
                    colour: adjust.colour,
                    fade: adjust.fade)),
          ),
        if (kindPicker) const CanvasLineBreak(),
        for (var p in adjust.kind.params)
          if (_groupsOf(adjust.kind).isEmpty)
            CanvasStepper(
              key: ValueKey("adjust-${p.key}"),
              label: p.label,
              min: p.percent ? p.min * 100 : p.min,
              max: p.percent ? p.max * 100 : p.max,
              decimals: p.decimals,
              step: adjustStep(p),
              suffix: p.percent ? "%" : "",
              defaultValue: p.percent ? p.initial * 100 : p.initial,
              value:
                  p.percent ? adjust.value(p.key) * 100 : adjust.value(p.key),
              onChanged: (v) =>
                  live(adjust.withValue(p.key, p.percent ? v / 100 : v)),
              onCommit: commit,
            ),
        if (adjust.kind == AdjustKind.hueSaturation)
          CanvasToggle(
            key: const ValueKey("adjustColourise"),
            label: "Colourise",
            value: adjust.value("colourise") > 0.5,
            onChanged: (v) => now(adjust
                .copyWith(values: {...adjust.values, "colourise": v ? 1 : 0})),
          ),
        if (adjust.kind.usesColour)
          CanvasColorButton(
            key: const ValueKey("adjustColour"),
            label: switch (adjust.kind) {
              AdjustKind.keepColour => "Colour kept",
              AdjustKind.blackWhite => "Tint",
              _ => "Filter",
            },
            color: adjust.colour,
            allowAlpha: false,
            onChanged: (c) => now(adjust.copyWith(colour: c)),
          ),
        if (adjust.kind == AdjustKind.photoFilter)
          CanvasToggle(
            key: const ValueKey("adjustKeepLight"),
            label: "Keep brightness",
            value: (adjust.values["keepLight"] ?? 1) > 0.5,
            onChanged: (v) => now(adjust
                .copyWith(values: {...adjust.values, "keepLight": v ? 1 : 0})),
          ),
        if (adjust.kind == AdjustKind.gradientMap)
          CanvasColorButton(
            key: const ValueKey("adjustFade"),
            label: "Dark to light",
            color: adjust.fade.color,
            gradient: adjust.fade.gradient,
            onChanged: (c) =>
                now(adjust.copyWith(fade: adjust.fade.copyWith(color: c))),
            onGradientChanged: (g) => now(adjust.copyWith(
                fade: g == null
                    ? adjust.fade.copyWith(plain: true)
                    : adjust.fade.copyWith(gradient: g))),
          ),
        if (adjust.kind == AdjustKind.highPass)
          const CanvasHint("Only the detail, on grey. In Overlay or Soft "
              "light it sharpens what is under it; it starts in Overlay."),
        if (adjust.kind.neighbours)
          const CanvasHint("Sizes are thousandths of the picture's shorter "
              "side, so it looks the same at any size."),
        if (adjust.kind == AdjustKind.colourBalance)
          CanvasToggle(
            key: const ValueKey("adjustBalanceKeepLight"),
            label: "Keep brightness",
            value: (adjust.values["keepLight"] ?? 1) > 0.5,
            onChanged: (v) => now(adjust
                .copyWith(values: {...adjust.values, "keepLight": v ? 1 : 0})),
          ),
        if (adjust.kind == AdjustKind.keepColour)
          const CanvasHint("Pick the colour to keep -- a kit, a sign -- and "
              "everything else loses its colour. Range is how close a colour "
              "has to be to count."),
      ],
    ),
    if (_groupsOf(adjust.kind).isNotEmpty)
      _GroupedSettings(
        key: ValueKey("adjustGroups-${adjust.kind.name}"),
        adjust: adjust,
        live: live,
        now: now,
        commit: commit,
      ),
    if (adjust.kind == AdjustKind.colourTable)
      ColourTableSettings(
        key: const ValueKey("adjustTable"),
        adjust: adjust,
        now: now,
      ),
    if (adjust.kind == AdjustKind.levels)
      LevelsHistogram(
        key: const ValueKey("adjustLevels"),
        controller: controller,
        element: e,
        layer: layer,
        onChanged: (next, {required bool done}) =>
            done ? now(next) : live(next),
      ),
    if (adjust.kind == AdjustKind.curves)
      CurveEditor(
        key: const ValueKey("adjustCurves"),
        adjust: adjust,
        onChanged: (channel, points, {required bool done}) {
          var next = adjust.withCurve(channel, points);
          if (done) {
            now(next);
          } else {
            live(next);
          }
        },
      ),
  ];
}

/// CurveEditor is a curve in a square: click to add a point and drag it;
/// drag off or double-click to remove it. Channels are chosen above.
class CurveEditor extends StatefulWidget {
  final ImageAdjustment adjust;
  final void Function(CurveChannel, List<Offset>, {required bool done})
      onChanged;
  const CurveEditor({required this.adjust, required this.onChanged, super.key});

  @override
  State<CurveEditor> createState() => _CurveEditorState();
}

class _CurveEditorState extends State<CurveEditor> {
  CurveChannel _channel = CurveChannel.rgb;
  int _held = -1;
  List<Offset>? _points;
  DateTime _lastDown = DateTime(0);
  int _lastPoint = -1;

  static const _reach = 10.0;

  List<Offset> get _shown => _points ?? widget.adjust.curve(_channel);

  Color _colourOf(CurveChannel c, Color plain) => switch (c) {
        CurveChannel.rgb => plain,
        CurveChannel.red => const Color(0xFFE5484D),
        CurveChannel.green => const Color(0xFF30A46C),
        CurveChannel.blue => const Color(0xFF3E63DD),
      };

  Offset _toCurve(Offset local, Size size) =>
      Offset(local.dx / size.width, 1 - local.dy / size.height);

  Offset _toLocal(Offset p, Size size) =>
      Offset(p.dx * size.width, (1 - p.dy) * size.height);

  void _down(Offset local, Size size) {
    var points = [..._shown];
    var at = -1;
    var best = _reach;
    for (var (i, p) in points.indexed) {
      var d = (_toLocal(p, size) - local).distance;
      if (d <= best) {
        best = d;
        at = i;
      }
    }
    var now = DateTime.now();
    // A quick second click on a point removes it, but never an end, which
    // the curve needs.
    if (at > 0 &&
        at < points.length - 1 &&
        at == _lastPoint &&
        now.difference(_lastDown) < const Duration(milliseconds: 350)) {
      points.removeAt(at);
      _lastPoint = -1;
      widget.onChanged(_channel, points, done: true);
      setState(() => _points = null);
      return;
    }
    _lastDown = now;
    if (at < 0) {
      var c = _toCurve(local, size);
      var x = c.dx.clamp(0.0, 1.0);
      var fresh = Offset(x, curveAt(points, x));
      points.add(fresh);
      points.sort((a, b) => a.dx.compareTo(b.dx));
      at = points.indexOf(fresh);
    }
    _lastPoint = at;
    setState(() {
      _held = at;
      _points = points;
    });
  }

  void _move(Offset local, Size size) {
    var points = _points;
    if (points == null || _held < 0) return;
    var c = _toCurve(local, size);
    var lo = _held == 0 ? 0.0 : points[_held - 1].dx + 0.01;
    var hi = _held == points.length - 1 ? 1.0 : points[_held + 1].dx - 0.01;
    var p = Offset(c.dx.clamp(lo, math.max(lo, hi)), c.dy);
    var next = [...points]..[_held] = p;
    setState(() => _points = next);
    widget.onChanged(
        _channel, [for (var q in next) Offset(q.dx, q.dy.clamp(0.0, 1.0))],
        done: false);
  }

  void _up() {
    var points = _points;
    if (points == null) return;
    var held = _held;
    // Dragged off the square, a point (not an end) is removed.
    var off = held > 0 &&
        held < points.length - 1 &&
        (points[held].dy < -0.12 || points[held].dy > 1.12);
    var next = [
      for (var (i, q) in points.indexed)
        if (!(off && i == held)) Offset(q.dx, q.dy.clamp(0.0, 1.0))
    ];
    widget.onChanged(_channel, next, done: true);
    setState(() {
      _held = -1;
      _points = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var muted = theme.colorScheme.onSurfaceVariant;
    var ink = theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 4, children: [
          for (var c in CurveChannel.values)
            ChoiceChip(
              key: ValueKey("curveChannel-${c.name}"),
              label: Text(c.label, style: const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
              selected: _channel == c,
              selectedColor: _colourOf(c, ink).withValues(alpha: 0.25),
              onSelected: (_) => setState(() {
                _channel = c;
                _points = null;
              }),
            ),
        ]),
        const SizedBox(height: 6),
        LayoutBuilder(builder: (context, box) {
          var side = math.min(box.maxWidth, 240.0);
          var size = Size(side, side);
          return Listener(
            key: const ValueKey("curveSquare"),
            onPointerDown: (e) => _down(e.localPosition, size),
            onPointerMove: (e) => _move(e.localPosition, size),
            onPointerUp: (_) => _up(),
            child: CustomPaint(
              size: size,
              painter: _CurvePainter(
                adjust: widget.adjust,
                channel: _channel,
                shown: _shown,
                held: _held,
                grid: muted.withValues(alpha: 0.35),
                colour: _colourOf(_channel, ink),
                others: {
                  for (var c in CurveChannel.values)
                    if (c != _channel) c: _colourOf(c, muted)
                },
              ),
            ),
          );
        }),
        const SizedBox(height: 4),
        const CanvasHint("Click to add a point and drag it. Drag a point off "
            "the square, or double-click it, to take it out."),
      ]),
    );
  }
}

class _CurvePainter extends CustomPainter {
  final ImageAdjustment adjust;
  final CurveChannel channel;
  final List<Offset> shown;
  final int held;
  final Color grid, colour;
  final Map<CurveChannel, Color> others;

  _CurvePainter({
    required this.adjust,
    required this.channel,
    required this.shown,
    required this.held,
    required this.grid,
    required this.colour,
    required this.others,
  });

  @override
  void paint(Canvas canvas, Size size) {
    var line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = grid;
    canvas.drawRect(Offset.zero & size, line);
    for (var q = 1; q < 4; q++) {
      var x = size.width * q / 4, y = size.height * q / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), line);

    Path pathOf(List<Offset> points) {
      var path = Path();
      for (var i = 0; i <= 64; i++) {
        var x = i / 64;
        var y = curveAt(points, x).clamp(0.0, 1.0);
        var at = Offset(x * size.width, (1 - y) * size.height);
        if (i == 0) {
          path.moveTo(at.dx, at.dy);
        } else {
          path.lineTo(at.dx, at.dy);
        }
      }
      return path;
    }

    // The other channels' bent curves, faintly.
    for (var e in others.entries) {
      if (!adjust.curves.containsKey(e.key)) continue;
      canvas.drawPath(
          pathOf(adjust.curve(e.key)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = e.value.withValues(alpha: 0.6));
    }
    canvas.drawPath(
        pathOf([for (var p in shown) Offset(p.dx, p.dy.clamp(0.0, 1.0))]),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = colour);
    for (var (i, p) in shown.indexed) {
      var at = Offset(p.dx * size.width, (1 - p.dy) * size.height);
      var r = Rect.fromCenter(center: at, width: 8, height: 8);
      canvas.drawRect(r, Paint()..color = i == held ? colour : Colors.white);
      canvas.drawRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = colour);
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) => true;
}

/// _histograms are counts keyed on what is under the layer, not the
/// picture, which is new on every change, the adjustment's own included.
final Map<String, (List<Object?>, List<int>)> _histograms = {};

/// _sameUnder is whether two lists of what is under a layer are the same.
bool _sameUnder(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!identical(a[i], b[i]) && a[i] != b[i]) return false;
  }
  return true;
}

/// histogramOf counts the brightness under layer [layerId] of [e] in 256
/// steps, weighted by each pixel's coverage.
Future<List<int>?> histogramOf(
    ImageElement e, String layerId, CanvasImageSource? images) async {
  var at = e.stack.indexWhere((l) => l.id == layerId);
  if (at < 0) return null;
  var inner = e.box.inner(e.bounds);
  var under = [inner.size, ...layersFrom(e, e.stack.sublist(0, at))];
  var name = "${e.id}|$layerId";
  if (_histograms[name] case (var from, var bins)
      when _sameUnder(from, under)) {
    return bins;
  }
  if (inner.width <= 0 || inner.height <= 0) return null;
  // Counted a few hundred pixels across: a histogram's shape, not grain.
  var k = math.min(1.0, 256 / math.max(inner.width, inner.height));
  var w = math.max(1, (inner.width * k).round());
  var h = math.max(1, (inner.height * k).round());
  CanvasPerf.count("histogram");
  var image = await renderUnder(e, layerId, images, w, h);
  if (image == null) return null;
  try {
    var data =
        await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    if (data == null) return null;
    var p = data.buffer.asUint8List();
    var bins = List<int>.filled(256, 0);
    for (var i = 0; i < p.length; i += 4) {
      if (p[i + 3] < 8) continue;
      var l = (0.299 * p[i] + 0.587 * p[i + 1] + 0.114 * p[i + 2]).round();
      bins[l.clamp(0, 255)] += p[i + 3];
    }
    _histograms[name] = (under, bins);
    // A few dozen pictures' worth at most; the oldest go first.
    while (_histograms.length > 32) {
      _histograms.remove(_histograms.keys.first);
    }
    return bins;
  } finally {
    image.dispose();
  }
}

/// LevelsHistogram is a levels adjustment's histogram (the brightness under
/// it) with the black, midtone and white input handles dragged along it.
class LevelsHistogram extends StatefulWidget {
  final CanvasController controller;
  final ImageElement element;
  final ImageLayer layer;
  final void Function(ImageAdjustment, {required bool done}) onChanged;
  const LevelsHistogram(
      {required this.controller,
      required this.element,
      required this.layer,
      required this.onChanged,
      super.key});

  @override
  State<LevelsHistogram> createState() => _LevelsHistogramState();
}

class _LevelsHistogramState extends State<LevelsHistogram> {
  Future<List<int>?>? _counting;
  ImageElement? _countedFor;
  int _held = -1;

  @override
  Widget build(BuildContext context) {
    // Recounted only when the layers under it change, which a handle never
    // touches.
    var e = widget.element;
    var at = e.stack.indexWhere((l) => l.id == widget.layer.id);
    var below = at < 0 ? const <ImageLayer>[] : e.stack.sublist(0, at);
    var counted = _countedFor;
    var same = counted != null &&
        identical(counted.assetId, e.assetId) &&
        _sameLayers(counted, below, at);
    if (!same) {
      _countedFor = e;
      _counting = histogramOf(e, widget.layer.id, widget.controller.images);
    }
    var theme = Theme.of(context);
    var a = widget.layer.adjust;
    var black = a.value("inBlack"), white = a.value("inWhite");
    var gamma = a.value("gamma");
    var mid = black + (white - black) * math.pow(0.5, gamma);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LayoutBuilder(builder: (context, box) {
        var width = math.min(box.maxWidth, 280.0);
        var size = Size(width, 90);
        double xOf(double v) => v * width;
        void drag(Offset local, {required bool done}) {
          var v = (local.dx / width).clamp(0.0, 1.0);
          var next = a;
          switch (_held) {
            case 0:
              next = a.withValue("inBlack", math.min(v, white - 0.01));
            case 2:
              next = a.withValue("inWhite", math.max(v, black + 0.01));
            case 1:
              var t = ((v - black) / math.max(0.01, white - black))
                  .clamp(0.01, 0.99);
              next = a.withValue("gamma", math.log(t) / math.log(0.5));
          }
          widget.onChanged(next, done: done);
        }

        // Held to its own size: stretched to the panel, the plot would not
        // match its handles (laid out on 280 pixels) and drags would miss.
        return Align(
            alignment: Alignment.centerLeft,
            child: SizedBox.fromSize(
                size: size,
                child: Listener(
                  key: const ValueKey("levelsHistogram"),
                  onPointerDown: (ev) {
                    var x = ev.localPosition.dx;
                    var handles = [xOf(black), xOf(mid.toDouble()), xOf(white)];
                    var best = 0;
                    for (var i = 1; i < 3; i++) {
                      if ((handles[i] - x).abs() < (handles[best] - x).abs()) {
                        best = i;
                      }
                    }
                    setState(() => _held = best);
                    drag(ev.localPosition, done: false);
                  },
                  onPointerMove: (ev) => drag(ev.localPosition, done: false),
                  onPointerUp: (ev) {
                    drag(ev.localPosition, done: true);
                    setState(() => _held = -1);
                  },
                  child: FutureBuilder<List<int>?>(
                    future: _counting,
                    builder: (context, snap) => CustomPaint(
                      size: size,
                      painter: _HistogramPainter(
                        bins: snap.data,
                        black: black,
                        mid: mid.toDouble(),
                        white: white,
                        bar: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.55),
                        frame: theme.colorScheme.outlineVariant,
                        ink: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                )));
      }),
    );
  }

  bool _sameLayers(ImageElement was, List<ImageLayer> below, int at) {
    var before = was.stack.indexWhere((l) => l.id == widget.layer.id);
    if (before != at) return false;
    for (var i = 0; i < at; i++) {
      if (!identical(was.stack[i], below[i])) return false;
    }
    return true;
  }
}

class _HistogramPainter extends CustomPainter {
  final List<int>? bins;
  final double black, mid, white;
  final Color bar, frame, ink;
  _HistogramPainter(
      {required this.bins,
      required this.black,
      required this.mid,
      required this.white,
      required this.bar,
      required this.frame,
      required this.ink});

  @override
  void paint(Canvas canvas, Size size) {
    var plot = Rect.fromLTWH(0, 0, size.width, size.height - 14);
    canvas.drawRect(
        plot,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = frame);
    var b = bins;
    if (b != null) {
      // Scaled to the busiest step but one, or a lot of pure black or white
      // flattens everything else.
      var sorted = [...b]..sort();
      var top = math.max(1, sorted[sorted.length - 2]);
      var path = Path()..moveTo(0, plot.bottom);
      for (var i = 0; i < 256; i++) {
        var x = i / 255 * size.width;
        var y = plot.bottom - math.min(1.0, b[i] / top) * plot.height;
        path.lineTo(x, y);
      }
      path
        ..lineTo(size.width, plot.bottom)
        ..close();
      canvas.drawPath(path, Paint()..color = bar);
    }
    void handle(double v, Color fill) {
      var x = v * size.width;
      var tip = Offset(x, plot.bottom + 1);
      var p = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - 6, size.height)
        ..lineTo(tip.dx + 6, size.height)
        ..close();
      canvas.drawPath(p, Paint()..color = fill);
      canvas.drawPath(
          p,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = ink);
    }

    handle(black, const Color(0xFF000000));
    handle(mid, const Color(0xFF808080));
    handle(white, const Color(0xFFFFFFFF));
  }

  @override
  bool shouldRepaint(_HistogramPainter old) =>
      old.bins != bins ||
      old.black != black ||
      old.mid != mid ||
      old.white != white;
}

/// _groupsOf are the settings of a kind with many, shown a group at a time:
/// each group's key starts its settings' keys.
List<(String, String)> _groupsOf(AdjustKind k) => switch (k) {
      AdjustKind.colourMixer => [for (var b in mixerBands) (b.key, b.label)],
      AdjustKind.colourBalance => const [
          ("shadows", "Shadows"),
          ("mids", "Midtones"),
          ("highs", "Highlights"),
        ],
      AdjustKind.channelMixer => const [
          ("r", "Red"),
          ("g", "Green"),
          ("b", "Blue"),
        ],
      _ => const [],
    };

/// _withinGroup is [label] without the group's name it starts with, which
/// the picker above already says: "Red hue" is "Hue" under Red.
String _withinGroup(String label, String group) {
  if (!label.startsWith(group)) return label;
  var rest = label.substring(group.length).replaceFirst(RegExp(r"^:?\s*"), "");
  return rest.isEmpty ? label : rest[0].toUpperCase() + rest.substring(1);
}

/// _shownGroup is the group last shown for each kind, for the run.
final Map<AdjustKind, String> _shownGroup = {};

/// _GroupedSettings is a many-setting kind's settings, a group at a time:
/// the colour mixer's eight colours, colour balance's three tones, the
/// channel mixer's three channels out.
class _GroupedSettings extends StatefulWidget {
  final ImageAdjustment adjust;
  final ValueChanged<ImageAdjustment> live;
  final ValueChanged<ImageAdjustment> now;
  final VoidCallback commit;
  const _GroupedSettings(
      {required this.adjust,
      required this.live,
      required this.now,
      required this.commit,
      super.key});

  @override
  State<_GroupedSettings> createState() => _GroupedSettingsState();
}

class _GroupedSettingsState extends State<_GroupedSettings> {
  @override
  Widget build(BuildContext context) {
    var adjust = widget.adjust;
    var kind = adjust.kind;
    var groups = _groupsOf(kind);
    var group = _shownGroup[kind] ?? groups.first.$1;
    var groupLabel = groups.firstWhere((g) => g.$1 == group).$2;
    bool moved(String g) => kind.params
        .any((p) => p.key.startsWith(g) && adjust.values.containsKey(p.key));
    return CanvasControlGroup(
      label: switch (kind) {
        AdjustKind.colourMixer => "Colour",
        AdjustKind.colourBalance => "Tones",
        _ => "Channel out",
      },
      rule: false,
      children: [
        CanvasSegmented<String>(
          key: const ValueKey("adjustGroup-picker"),
          options: [
            // A dot after a group that has been moved.
            for (var (key, label) in groups)
              (key, moved(key) ? "$label ·" : label)
          ],
          value: group,
          keyOf: (g) => "adjustGroup-$g",
          onChanged: (g) => setState(() => _shownGroup[kind] = g),
        ),
        const CanvasLineBreak(),
        for (var p in kind.params)
          // Every key in a group starts with the group's key: the channel
          // mixer's red channel out is "rr", "rg" and "rb".
          if (p.key.startsWith(group))
            CanvasStepper(
              key: ValueKey("adjust-${p.key}"),
              label: _withinGroup(p.label, groupLabel),
              min: p.percent ? p.min * 100 : p.min,
              max: p.percent ? p.max * 100 : p.max,
              decimals: p.decimals,
              step: adjustStep(p),
              suffix: p.percent ? "%" : "",
              defaultValue: p.percent ? p.initial * 100 : p.initial,
              value:
                  p.percent ? adjust.value(p.key) * 100 : adjust.value(p.key),
              onChanged: (v) =>
                  widget.live(adjust.withValue(p.key, p.percent ? v / 100 : v)),
              onCommit: widget.commit,
            ),
      ],
    );
  }
}

/// ColourTableSettings picks a colour table: one of the app's film tables,
/// or one read in from a .cube file or a HaldCLUT picture.
class ColourTableSettings extends StatelessWidget {
  final ImageAdjustment adjust;
  final ValueChanged<ImageAdjustment> now;
  const ColourTableSettings(
      {required this.adjust, required this.now, super.key});

  static const _own = "own";

  @override
  Widget build(BuildContext context) {
    var picked = adjust.cube != null ? _own : adjust.table;
    return CanvasControlGroup(
      label: "Table",
      rule: false,
      children: [
        CanvasDropdown<String>(
          key: const ValueKey("adjustTablePick"),
          label: "Look",
          value: picked,
          width: 220,
          options: [
            ("", "None"),
            if (adjust.cube != null)
              (_own, adjust.tableName.isEmpty ? "Read in" : adjust.tableName),
            for (var t in filmTables) (t.id, t.name),
          ],
          onChanged: (id) {
            if (id == _own) return;
            now(adjust.copyWith(table: id, clearCube: true, tableName: ""));
          },
        ),
        CanvasTextButton(
          key: const ValueKey("adjustTableLoad"),
          label: "Load a .cube or HaldCLUT",
          icon: Icons.file_open_outlined,
          onPressed: () async {
            var read = await pickColourTable(context);
            if (read == null) return;
            now(adjust.copyWith(
                table: "", cube: read.cube, tableName: read.title));
          },
        ),
        const CanvasHint("Read-in tables are kept in the picture, so it "
            "looks the same wherever it goes."),
        // Said where it shows, not behind the "?": the film tables' licence
        // asks for their makers to be named.
        Text(filmTablesCredit,
            key: const ValueKey("adjustTableCredit"),
            style: TextStyle(
                fontSize: 11,
                color: ThemeNotifier.of(context).colors.onSurfaceVariant)),
      ],
    );
  }
}

/// pickColourTable asks for a .cube file or a HaldCLUT picture and reads
/// it, saying why when it cannot.
Future<CubeFile?> pickColourTable(BuildContext context) async {
  void say(String text) => ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(text)));
  try {
    var picked = await FilePicker.platform.pickFiles(
        dialogTitle: "Load a colour table",
        type: FileType.custom,
        allowedExtensions: const ["cube", "png"]);
    var path = picked?.files.firstOrNull?.path;
    if (path == null) return null;
    var (read, problem) = await readColourTableFile(path);
    if (read == null && context.mounted) say(problem ?? "Could not read it.");
    return read;
  } catch (e) {
    if (context.mounted) say("Could not read it: $e");
    return null;
  }
}

/// readColourTableFile is the table in the file at [path]: a .cube file,
/// or a HaldCLUT picture.
Future<(CubeFile?, String?)> readColourTableFile(String path) async {
  var file = File(path);
  if (await file.length() > maxCubeFileBytes) {
    return (null, "That is too large to be a colour table.");
  }
  var name = p.basenameWithoutExtension(path);
  if (path.toLowerCase().endsWith(".png")) {
    var bytes = await file.readAsBytes();
    var codec = await ui.instantiateImageCodec(bytes);
    var frame = await codec.getNextFrame();
    codec.dispose();
    var image = frame.image;
    var data =
        await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    var (w, h) = (image.width, image.height);
    image.dispose();
    if (data == null) return (null, "Could not read that picture.");
    var (cube, problem) = haldCube(data.buffer.asUint8List(), w, h);
    return (cube == null ? null : CubeFile(name, cube), problem);
  }
  var (read, problem) = parseCubeFile(await file.readAsString());
  if (read != null && read.title.isEmpty) {
    read = CubeFile(name, read.cube);
  }
  return (read, problem);
}
