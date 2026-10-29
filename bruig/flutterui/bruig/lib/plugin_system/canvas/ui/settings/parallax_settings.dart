import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/parallax_element.dart';
import 'package:bruig/plugin_system/canvas/presets/parallax_looks.dart';
import 'package:bruig/plugin_system/canvas/render/parallax_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/image_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/procedural_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// parallax_settings.dart is a background's settings while it is parallax
// scenery: its layers in Pattern layers, whole scenes to start from, the
// camera that pans across them, and the picked layer's own settings --
// what it is, and how far it moves when the camera does.

/// ParallaxSettings edits [scenery], handing each edit to [write] for the
/// caller to put back where the scenery lives.
class ParallaxSettings extends StatefulWidget {
  final CanvasController controller;
  final ParallaxElement scenery;
  final Widget picker;
  final void Function(ParallaxElement) write;
  final VoidCallback begin;
  final VoidCallback commit;
  final String rememberAs;

  const ParallaxSettings({
    required this.controller,
    required this.scenery,
    required this.picker,
    required this.write,
    required this.begin,
    required this.commit,
    required this.rememberAs,
    super.key,
  });

  @override
  State<ParallaxSettings> createState() => _ParallaxSettingsState();
}

class _ParallaxSettingsState extends State<ParallaxSettings> {
  /// picked is the layer being edited: the panel's to remember, not the
  /// document's. Null for the front one.
  int? picked;

  ParallaxElement get p => widget.scenery;
  CanvasController get controller => widget.controller;

  void _now(ParallaxElement next) {
    widget.begin();
    widget.write(next);
    widget.commit();
  }

  void _layers(List<ParallaxLayer> next, {int? select}) {
    _now(p.copyWith(layers: next));
    if (select != null) setState(() => picked = select);
  }

  @override
  Widget build(BuildContext context) {
    var layers = p.layers;
    var at = layers.isEmpty
        ? null
        : (picked ?? layers.length - 1).clamp(0, layers.length - 1);
    var camera = p.cameraAt(controller.frame);
    var keyed = controller.hasCameraKey(p);
    var remember = widget.rememberAs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CanvasSection(
          key: const ValueKey("backgroundSection-layers"),
          icon: Icons.layers_outlined,
          title: "Pattern layers",
          summary: "Parallax · ${layers.length} "
              "${layers.length == 1 ? "layer" : "layers"}",
          remember: "$remember.layers",
          initiallyOpen: true,
          children: [
            widget.picker,
            _list(context, layers, at),
          ],
        ),
        CanvasSection(
          key: const ValueKey("parallaxSection-looks"),
          icon: Icons.landscape_outlined,
          title: "Scenes",
          summary: parallaxLooks
                  .where((l) => _sameLayers(l.layers, layers))
                  .firstOrNull
                  ?.name ??
              "Your own",
          remember: "$remember.parallaxLooks",
          children: [
            CanvasTiles<int>(
              label: "Start from",
              help: "A whole scene, back to front. Every layer can be "
                  "changed, moved, hidden or taken out afterwards.",
              columns: 3,
              previewHeight: 48,
              tiles: [
                for (var (i, look) in parallaxLooks.indexed)
                  CanvasTile(i, look.name,
                      paint: (canvas, size) => paintParallax(
                          canvas,
                          Offset.zero & size,
                          look.scenery.withBase(
                              width: size.width,
                              height: size.height) as ParallaxElement,
                          0)),
              ],
              selected: (i) => _sameLayers(parallaxLooks[i].layers, layers),
              keyOf: (i) => "parallaxLook-${parallaxLooks[i].name}",
              onPick: (i) => _layers(parallaxLooks[i].layers,
                  select: parallaxLooks[i].layers.length - 1),
            ),
          ],
        ),
        CanvasSection(
          key: const ValueKey("parallaxSection-camera"),
          icon: Icons.videocam_outlined,
          title: "Camera",
          summary: "${camera.x.round()}, ${camera.y.round()}"
              "${camera.zoom == 1 ? "" : " · ×${camera.zoom.toStringAsFixed(2)}"}"
              "${keyed ? " · keyed here" : ""}",
          remember: "$remember.parallaxCamera",
          initiallyOpen: true,
          children: _camera(camera, keyed),
        ),
        if (at != null)
          CanvasSection(
            key: const ValueKey("parallaxSection-layer"),
            icon: Icons.tune,
            title: layers[at].title,
            summary: "Moves ${(layers[at].scrollX * 100).round()}%",
            remember: "$remember.parallaxLayer",
            initiallyOpen: true,
            children: _layer(context, at, layers[at]),
          ),
      ],
    );
  }

  Widget _list(BuildContext context, List<ParallaxLayer> layers, int? at) {
    var theme = ThemeNotifier.of(context);
    Widget row(int i) {
      var layer = layers[i];
      var chosen = at == i;
      return Material(
        key: ValueKey("parallaxLayer-$i"),
        color:
            chosen ? theme.colors.surfaceContainerHighest : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => setState(() => picked = i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: Row(children: [
              Opacity(
                opacity: layer.visible ? 1 : 0.35,
                child: SizedBox(
                  width: 44,
                  height: 26,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: CustomPaint(painter: _LayerThumb(layer)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "${layer.title} · ${(layer.scrollX * 100).round()}%",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      color: chosen
                          ? theme.colors.onSurface
                          : theme.colors.onSurfaceVariant),
                ),
              ),
              CanvasIconButton(
                key: ValueKey("parallaxEye-$i"),
                icon: layer.visible
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                tooltip: layer.visible ? "Hide" : "Show",
                tight: true,
                onPressed: () => _now(
                    p.withLayer(i, layer.copyWith(visible: !layer.visible))),
              ),
              CanvasIconButton(
                key: ValueKey("parallaxUp-$i"),
                icon: Icons.arrow_upward,
                tooltip: "Nearer: in front of the one above",
                tight: true,
                onPressed: i == layers.length - 1
                    ? null
                    : () => _layers(
                        [...layers]
                          ..insert(i + 2, layers[i])
                          ..removeAt(i),
                        select: i + 1),
              ),
              CanvasIconButton(
                key: ValueKey("parallaxDown-$i"),
                icon: Icons.arrow_downward,
                tooltip: "Further: behind the one below",
                tight: true,
                onPressed: i == 0
                    ? null
                    : () => _layers(
                        [...layers]
                          ..removeAt(i)
                          ..insert(i - 1, layer),
                        select: i - 1),
              ),
              CanvasIconButton(
                key: ValueKey("parallaxDelete-$i"),
                icon: Icons.delete_outline,
                tooltip: "Remove",
                tight: true,
                onPressed: () => _layers([...layers]..removeAt(i),
                    select: (i - 1).clamp(0, 1 << 20)),
              ),
            ]),
          ),
        ),
      );
    }

    var full = layers.length >= maxParallaxLayers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Front first, as a stack is seen from the camera.
        for (var i = layers.length - 1; i >= 0; i--) row(i),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: CanvasDropdown<SceneryKind?>(
            key: const ValueKey("parallaxAdd"),
            label: full ? "As many layers as there can be" : "Add a layer",
            value: null,
            width: 170,
            options: [
              (null, "Choose…"),
              if (!full)
                for (var k in SceneryKind.values) (k, k.label),
            ],
            onChanged: (k) {
              if (k == null) return;
              _layers([...layers, parallaxLayerStart(k)],
                  select: layers.length);
            },
          ),
        ),
      ],
    );
  }

  List<Widget> _camera(ParallaxCamera camera, bool keyed) {
    var animated = controller.document.isAnimated;
    void film(ParallaxCamera next) =>
        widget.write(controller.parallaxFilmed(p, next));
    var across = controller.document.size.width * 1.5;
    return [
      CanvasControlGroup(
          label: "Where it looks",
          help: "How far the camera has travelled across and down the "
              "scene, in the canvas's units, and how far it is zoomed in. "
              "Each layer moves by its own share of that -- so the far "
              "hills slide slowly and the near ground keeps up. Hold Option "
              "and drag on the canvas to pan it by hand.",
          children: [
            CanvasStepper(
              key: const ValueKey("parallaxCamX"),
              label: "Across",
              value: camera.x,
              min: -100000,
              max: 100000,
              step: 50,
              defaultValue: 0,
              onChanged: (v) => film(camera.copyWith(x: v)),
              onCommit: widget.commit,
            ),
            CanvasStepper(
              key: const ValueKey("parallaxCamY"),
              label: "Down",
              value: camera.y,
              min: -100000,
              max: 100000,
              step: 25,
              defaultValue: 0,
              onChanged: (v) => film(camera.copyWith(y: v)),
              onCommit: widget.commit,
            ),
            CanvasStepper(
              key: const ValueKey("parallaxCamZoom"),
              label: "Zoom",
              value: camera.zoom,
              min: 0.25,
              max: 8,
              step: 0.1,
              decimals: 2,
              suffix: "×",
              defaultValue: 1,
              onChanged: (v) => film(camera.copyWith(zoom: v)),
              onCommit: widget.commit,
            ),
          ]),
      CanvasControlGroup(
          label: "Camera moves",
          help: "Key the camera on one frame, move it on a later one, and "
              "it pans between them. Pan across keys the whole move at "
              "once: from where the camera is on the first frame to a page "
              "and a half further on by the last.",
          children: [
            if (keyed)
              CanvasTextButton(
                key: const ValueKey("parallaxUnkey"),
                icon: Icons.remove_circle_outline,
                label: "Remove this key",
                onPressed: () {
                  controller.beginInteraction();
                  controller.clearCameraKey(p);
                  controller.endInteraction();
                },
              )
            else
              CanvasTextButton(
                key: const ValueKey("parallaxKey"),
                icon: Icons.add_circle_outline,
                label: "Key the camera here",
                onPressed: animated
                    ? () {
                        controller.beginInteraction();
                        controller.keyCamera(p);
                        controller.endInteraction();
                      }
                    : null,
              ),
            CanvasTextButton(
              key: const ValueKey("parallaxPanAcross"),
              icon: Icons.east,
              label: "Pan across",
              onPressed: animated
                  ? () {
                      controller.beginInteraction();
                      controller.panAcross(p, across);
                      controller.endInteraction();
                    }
                  : null,
            ),
          ]),
    ];
  }

  List<Widget> _layer(BuildContext context, int i, ParallaxLayer layer) {
    void live(ParallaxLayer next) => widget.write(p.withLayer(i, next));
    void now(ParallaxLayer next) => _now(p.withLayer(i, next));

    CanvasStepper stepper(String key, String label, double value, double min,
            double max, double step, ParallaxLayer Function(double) set,
            {int decimals = 0, String suffix = "", double? reset}) =>
        CanvasStepper(
          key: ValueKey("parallax-$key"),
          label: label,
          value: value,
          min: min,
          max: max,
          step: step,
          decimals: decimals,
          suffix: suffix,
          defaultValue: reset,
          onChanged: (v) {
            widget.begin();
            live(set(v));
          },
          onCommit: widget.commit,
        );

    var kind = layer.kind;
    return [
      if (kind.drawn)
        CanvasControlGroup(
            label: "Look",
            help: switch (kind) {
              SceneryKind.sky => "The top of the sky and the horizon; "
                  "Sun is the size of a sun or moon in it, none at nought.",
              SceneryKind.clouds =>
                "The clouds' light and their shade; Amount is how many.",
              SceneryKind.city => "The buildings and their lit windows; "
                  "Amount is how many buildings to a page.",
              SceneryKind.trees => "Amount is how many trees to a page.",
              _ => "Its colour, and the haze at its top; Height is how "
                  "tall it stands, Amount how rough.",
            },
            children: [
              CanvasColorButton(
                label: kind == SceneryKind.sky ? "Top" : "Colour",
                color: layer.color,
                onChanged: (c) => now(layer.copyWith(color: c)),
              ),
              if (kind != SceneryKind.trees)
                CanvasColorButton(
                  label: switch (kind) {
                    SceneryKind.sky => "Horizon",
                    SceneryKind.city => "Windows",
                    SceneryKind.clouds => "Shade",
                    _ => "Haze",
                  },
                  color: layer.color2,
                  onChanged: (c) => now(layer.copyWith(color2: c)),
                ),
              if (kind.silhouette)
                stepper("height", "Height", layer.height * 100, 2, 100, 2,
                    (v) => layer.copyWith(height: v / 100),
                    suffix: "%"),
              stepper(
                  "amount",
                  kind == SceneryKind.sky ? "Sun" : "Amount",
                  layer.amount * 100,
                  0,
                  100,
                  5,
                  (v) => layer.copyWith(amount: v / 100),
                  suffix: "%"),
              CanvasIconButton(
                key: const ValueKey("parallaxShuffle"),
                icon: Icons.casino_outlined,
                tooltip: "Try the next variation",
                onPressed: () => now(layer.copyWith(seed: layer.seed + 1)),
              ),
            ]),
      if (kind == SceneryKind.picture)
        CanvasControlGroup(
            label: "Picture",
            help: "A picture with a see-through sky works best -- a row of "
                "trees, a skyline -- so the layers behind show through it.",
            children: [
              CanvasTextButton(
                key: const ValueKey("parallaxPicture"),
                icon: Icons.add_photo_alternate_outlined,
                label: layer.assetId.isEmpty
                    ? "Choose a picture"
                    : "Change the picture",
                onPressed: () async {
                  var id = await pickCanvasImage(context);
                  if (id == null) return;
                  now(layer.copyWith(assetId: id));
                },
              ),
            ]),
      if (kind == SceneryKind.pattern)
        CanvasControlGroup(label: "Pattern", children: [
          patternStyleDropdown(
            key: const ValueKey("parallaxPatternStyle"),
            spec: layer.spec,
            onChanged: (s) => now(layer.copyWith(spec: s)),
          ),
          patternLookDropdown(
            spec: layer.spec,
            onChanged: (s) => now(layer.copyWith(spec: s)),
          ),
        ]),
      CanvasControlGroup(
          label: "Depth",
          help: "How much of the camera's move this layer makes: 0% stays "
              "put, like a sky; 100% keeps up with the camera, like the "
              "ground it travels over; more than 100% passes in front. "
              "Drift moves it by itself, in units a second -- clouds "
              "crossing the sky.",
          children: [
            stepper("scrollX", "Across", layer.scrollX * 100, -400, 400, 5,
                (v) => layer.copyWith(scrollX: v / 100),
                suffix: "%", reset: 50),
            stepper("scrollY", "Down", layer.scrollY * 100, -400, 400, 5,
                (v) => layer.copyWith(scrollY: v / 100),
                suffix: "%", reset: 50),
            stepper("autoX", "Drift across", layer.autoX, -2000, 2000, 5,
                (v) => layer.copyWith(autoX: v),
                reset: 0),
            stepper("autoY", "Drift down", layer.autoY, -2000, 2000, 5,
                (v) => layer.copyWith(autoY: v),
                reset: 0),
          ]),
      CanvasControlGroup(
          label: "Placing",
          help: "Where it sits in the page, how big one tile of it is, and "
              "whether it goes on for ever across or down -- with repeat "
              "off it ends, and the camera can pan past it.",
          children: [
            CanvasSegmented<LayerAnchor>(
              key: const ValueKey("parallaxAnchor"),
              options: [for (var a in LayerAnchor.values) (a, a.label)],
              value: layer.anchor,
              keyOf: (a) => "parallaxAnchor-${a.name}",
              onChanged: (a) => now(layer.copyWith(anchor: a)),
            ),
            stepper("size", "Size", layer.size * 100, 10, 800, 10,
                (v) => layer.copyWith(size: v / 100),
                suffix: "%", reset: 100),
            stepper("offsetX", "Nudge across", layer.offset.dx, -10000, 10000,
                10, (v) => layer.copyWith(offset: Offset(v, layer.offset.dy)),
                reset: 0),
            stepper("offsetY", "Nudge down", layer.offset.dy, -10000, 10000, 10,
                (v) => layer.copyWith(offset: Offset(layer.offset.dx, v)),
                reset: 0),
            CanvasToggle(
              key: const ValueKey("parallaxRepeatX"),
              label: "Repeat across",
              value: layer.repeatX,
              onChanged: (v) => now(layer.copyWith(repeatX: v)),
            ),
            CanvasToggle(
              key: const ValueKey("parallaxRepeatY"),
              label: "Repeat down",
              value: layer.repeatY,
              onChanged: (v) => now(layer.copyWith(repeatY: v)),
            ),
            stepper("opacity", "Opacity", layer.opacity * 100, 0, 100, 5,
                (v) => layer.copyWith(opacity: v / 100),
                suffix: "%", reset: 100),
          ]),
    ];
  }
}

bool _sameLayers(List<ParallaxLayer> a, List<ParallaxLayer> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].toJson().toString() != b[i].toJson().toString()) return false;
  }
  return true;
}

/// _LayerThumb is one layer by itself, at rest, for its row.
class _LayerThumb extends CustomPainter {
  final ParallaxLayer layer;
  _LayerThumb(this.layer);

  @override
  void paint(ui.Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0x22808080));
    paintParallax(
        canvas,
        Offset.zero & size,
        ParallaxElement(
            ElementBase(id: "", width: size.width, height: size.height),
            layers: [layer.copyWith(visible: true, opacity: 1)]),
        0);
  }

  @override
  bool shouldRepaint(_LayerThumb old) =>
      old.layer.toJson().toString() != layer.toJson().toString();
}
