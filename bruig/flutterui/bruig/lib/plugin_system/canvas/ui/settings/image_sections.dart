import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_adjustment.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_effects.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_mask.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart'
    show VectorCue;
import 'package:bruig/plugin_system/canvas/render/image_look.dart';
import 'package:bruig/plugin_system/canvas/render/layer_effects.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_settings.dart'
    show elementCueGroup;
import 'package:bruig/plugin_system/canvas/ui/image_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/adjustment_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/effects_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/image_layer_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/image_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/presets_section.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// image_sections.dart is a picture's panel: its layers, then the picked
// layer's settings in sections that fold -- Position, Mask, Retouch, Colour,
// Effects, Animation and the whole image's Frame for a picture; the layer's
// own kind, Blend, Mask, Effects, Animation and Frame for anything else. A
// section shut says in a line how it is set, so the panel reads as a summary
// before anything is opened. See panel_kit.dart for the parts.

/// imagePanel is the settings of the picture [e].
List<Widget> imagePanel(
    BuildContext context,
    CanvasController controller,
    ImageElement e,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit) {
  var editing = controller.imageEditing == e.id;
  // The picture's own base layer, not a fresh one: its blend, opacity and
  // effects are the picture's, layers open or not.
  var base = e.stack.firstWhere((l) => l.isBase, orElse: () => ImageLayer.base);
  var picked = editing ? controller.pickedLayer ?? base : base;
  var index = e.stack.indexWhere((l) => l.id == picked.id);
  var s = _Sections(context, controller, e, picked, write, begin, commit);
  var sections = switch (picked.kind) {
    LayerKind.base || LayerKind.picture => [
        s.position(),
        s.mask(),
        s.retouch(),
        s.colour(),
        s.effects(),
        s.animation(),
        s.frame(),
      ],
    _ => [
        s.own(),
        s.blend(),
        s.mask(),
        if (picked.kind != LayerKind.adjustment) s.effects(),
        s.animation(),
        s.frame(),
      ],
  };
  return [
    ImageLayersList(
        key: const ValueKey("imageLayers"), controller: controller, element: e),
    _PickedHeader(
        controller: controller, element: e, layer: picked, index: index),
    CanvasSections(
      key: const ValueKey("imageSections"),
      what: "a ${layerKindLabel(picked).toLowerCase()} layer",
      children: sections,
    ),
  ];
}

/// _PickedHeader says whose settings the sections are: the picked layer's
/// picture, name and kind.
class _PickedHeader extends StatelessWidget {
  final CanvasController controller;
  final ImageElement element;
  final ImageLayer layer;
  final int index;

  const _PickedHeader(
      {required this.controller,
      required this.element,
      required this.layer,
      required this.index});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Padding(
      key: const ValueKey("imagePicked"),
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 10),
      child: Row(children: [
        LayerThumbnail(
            controller: controller,
            element: element,
            layer: layer,
            width: 34,
            height: 34),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(layerName(layer, index),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.colors.onSurface)),
              Text(
                  controller.imageEditing == element.id
                      ? "${layerKindLabel(layer)} layer"
                      : "Pick a layer to work on it",
                  style: TextStyle(
                      fontSize: 10.5, color: theme.colors.onSurfaceVariant)),
            ],
          ),
        ),
      ]),
    );
  }
}

/// _Sections builds each section for the picked layer.
class _Sections {
  final BuildContext context;
  final CanvasController controller;
  final ImageElement e;
  final ImageLayer picked;
  final SettingsWrite write;
  final VoidCallback begin;
  final VoidCallback commit;

  _Sections(this.context, this.controller, this.e, this.picked, this.write,
      this.begin, this.commit);

  bool get _picture =>
      picked.kind == LayerKind.base || picked.kind == LayerKind.picture;

  /// _look is the picked picture: the element's own for the base, the
  /// layer's for a picture layer.
  ImageElement get _look => picked.isBase ? e : picked.look!;

  /// _kind names the sections' remembered open states, so a picture's and an
  /// adjustment's are kept apart: what is open on one is not what is wanted
  /// on the other.
  String get _kind => switch (picked.kind) {
        LayerKind.base || LayerKind.picture => "picture",
        var k => k.name,
      };

  String _remember(String section) => "image.$_kind.$section";

  void _writeLook(CanvasElement next) => write(picked.isBase
      ? next
      : e.withLayer(picked.id, (l) => l.copyWith(look: next as ImageElement)));

  void _tryLook(ImageElement? look) => controller.tryElement(picked.isBase
      ? look
      : look == null
          ? null
          : e.withLayer(picked.id, (l) => l.copyWith(look: look)));

  Rect? get _layerFrame => picked.isBase ? null : e.box.inner(e.bounds);

  bool _holds(List<ImageTool> tools) =>
      controller.imageEditing == e.id && tools.contains(controller.imageTool);

  void _now(ImageElement next) {
    begin();
    write(next);
    commit();
  }

  // ---- Position ---------------------------------------------------------

  Widget position() {
    var look = _look;
    String summary;
    if (picked.isBase) {
      summary = "${e.x.round()}, ${e.y.round()} · "
          "${e.width.round()} × ${e.height.round()}";
    } else {
      var r = layerRect(e.box.inner(e.bounds), picked.place);
      summary = "${r.left.round()}, ${r.top.round()} · "
          "${r.width.round()} × ${r.height.round()}"
          "${picked.turn != 0 ? " · ${picked.turn.round()}°" : ""}";
    }
    return CanvasSection(
      key: const ValueKey("imageSection-position"),
      icon: Icons.open_with,
      title: "Position",
      summary: summary,
      remember: _remember("position"),
      initiallyOpen: true,
      keywords: const [
        "x", "y", "width", "height", "angle", "turn", "opacity", "flip", //
        "fit", "fill", "crop", "framing", "zoom", "shape", "cut to",
        "replace", "picture",
      ],
      children: [
        if (picked.isBase)
          positionGroup(controller, e, write, begin, commit)
        else ...[
          layerPositionGroup(controller, e, picked, write, begin, commit),
          CanvasControlGroup(
            label: "Quick moves",
            rule: false,
            children:
                layerQuickMoves(controller, e, picked, write, begin, commit),
          ),
        ],
        CanvasControlGroup(
          label: "Picture",
          rule: false,
          children: [
            ...pictureSourceButtons(context, look, _writeLook, begin, commit,
                layerFrame: _layerFrame),
            CanvasDropdown<ImageFit>(
              label: "Fit",
              value: look.fit,
              width: 106,
              options: [for (var f in ImageFit.values) (f, f.label)],
              onChanged: (v) {
                begin();
                _writeLook(look.copyWith(fit: v));
                commit();
              },
            ),
          ],
        ),
        ...pictureLookGroups(look, _writeLook, begin, commit,
            shown: look.hasImage,
            tryLook: _tryLook,
            filter: false,
            overlay: false,
            outline: false),
      ],
    );
  }

  // ---- Mask -------------------------------------------------------------

  Widget mask() {
    var framed = !_picture;
    var mask = framed ? picked.mask : _look.mask;
    var tools = framed ? framedMaskTools : maskTools;
    var settings = _holds(tools)
        ? maskToolSettings(controller, e, picked)
        : const <Widget>[];
    var feather = mask.refine.feather;
    var summary = mask.empty
        ? framed
            ? "Shows everywhere"
            : "Nothing hidden"
        : [
            !mask.on
                ? "Mask off"
                : mask.invert
                    ? "Swapped"
                    : mask.subject.isNotEmpty
                        ? "Subject kept"
                        : "Masked",
            if (mask.marks.isNotEmpty)
              "${mask.marks.length} mark${mask.marks.length == 1 ? "" : "s"}",
            if (feather > 0) "feather ${_trim(feather)} px",
          ].join(" · ");
    if (_picture && _look.removal.mode != RemovalMode.none) {
      summary += " · ${_look.removal.mode.label}";
    }
    var changes = (mask.empty ? 0 : 1) + (mask.refine.any ? 1 : 0);
    void put(ImageMask next) {
      if (framed) {
        write(e.withLayer(picked.id, (l) => l.copyWith(mask: next)));
      } else {
        _writeLook(_look.copyWith(mask: next));
      }
    }

    return CanvasSection(
      key: const ValueKey("imageSection-mask"),
      icon: Icons.content_cut,
      title: "Mask",
      summary: summary,
      remember: _remember("mask"),
      forceOpen: _holds(tools),
      changes: changes,
      onReset: () {
        begin();
        put(const ImageMask());
        commit();
      },
      keywords: [
        for (var t in tools) t.label,
        "subject", "remove background", "feather", "shift", "smooth", //
        "contrast", "clean colour", "invert", "refine", "edge",
        if (!framed) ...["logos", "scans", "colour key", "threshold"],
      ],
      children: [
        imageToolTiles(controller, e, picked, tools, settings),
        ...maskGroupsFor(mask, put, begin, commit, framed: framed),
        if (_picture)
          pictureRemovalGroup(controller, _look, _writeLook, begin, commit,
              layer: !picked.isBase),
      ],
    );
  }

  // ---- Retouch ----------------------------------------------------------

  Widget retouch() {
    var look = _look;
    var n = look.retouch.length;
    var settings = _holds(retouchTools)
        ? brushToolSettings(controller, picked)
        : const <Widget>[];
    void set(List<dynamic> next) {
      begin();
      _writeLook(look.copyWith(retouch: next.cast()));
      commit();
    }

    return CanvasSection(
      key: const ValueKey("imageSection-retouch"),
      icon: Icons.healing,
      title: "Retouch",
      summary: n == 0 ? "No retouching yet" : "$n stroke${n == 1 ? "" : "s"}",
      remember: _remember("retouch"),
      forceOpen: _holds(retouchTools),
      // Strokes are work done, not a setting moved: no dot, and no reset
      // that would wipe them -- the Strokes group takes them back one at a
      // time, or clears them when that is what is meant.
      keywords: [for (var t in retouchTools) t.label, "strokes", "brush"],
      children: [
        imageToolTiles(controller, e, picked, retouchTools, settings),
        strokesGroup("Retouching", look.retouch, set),
      ],
    );
  }

  // ---- Colour -----------------------------------------------------------

  Widget colour() {
    var look = _look;
    var image = look.hasImage
        ? controller.images.resolve(look.assetId, look.removal)
        : null;
    var changes = [
      look.filter != ImageFilterPreset.none,
      picked.blend != LayerBlend.normal,
      picked.opacity < 1,
      look.saturation != 1,
      look.brightness != 1,
      look.blend != OverlayBlend.none,
      picked.clip,
    ].where((c) => c).length;
    return CanvasSection(
      key: const ValueKey("imageSection-colour"),
      icon: Icons.palette_outlined,
      title: "Colour",
      summary: "${look.filter.label} · ${picked.blend.label} · "
          "${(picked.opacity * 100).round()}%",
      remember: _remember("colour"),
      changes: changes,
      onReset: () {
        var reset = look.copyWith(
            filter: ImageFilterPreset.none,
            saturation: 1,
            brightness: 1,
            blend: OverlayBlend.none);
        var next = picked.isBase
            ? reset
            : e.withLayer(picked.id, (l) => l.copyWith(look: reset));
        _now(next.withLayer(
            picked.id,
            (l) =>
                l.copyWith(blend: LayerBlend.normal, opacity: 1, clip: false)));
      },
      keywords: const [
        "filter", "blend", "opacity", "overlay", "saturation", //
        "brightness", "clip", "greyscale", "sepia", "noir", "warm", "cool",
      ],
      children: [
        CanvasTiles<ImageFilterPreset>(
          key: const ValueKey("imageFilter"),
          label: "Filter",
          columns: 4,
          tiles: [
            for (var f in ImageFilterPreset.values)
              CanvasTile(f, f.label,
                  preview: (_) => _FilterPreview(image: image, filter: f)),
          ],
          selected: (f) => look.filter == f,
          keyOf: (f) => "imageFilter-${f.name}",
          onPreview: (f) =>
              _tryLook(f == null ? null : look.copyWith(filter: f)),
          onPick: (f) {
            begin();
            _writeLook(look.copyWith(filter: f));
            commit();
          },
        ),
        layerBlendTiles(controller, e, picked, write, begin, commit),
        layerStrengthGroup(e, picked, write, begin, commit),
        CanvasControlGroup(label: "Fine-tune", rule: false, children: [
          CanvasStepper(
            key: const ValueKey("imageSaturation"),
            label: "Saturation",
            decimals: 2,
            step: 0.05,
            dragStep: 0.01,
            min: 0,
            max: 3,
            defaultValue: 1,
            value: look.saturation,
            onChanged: (v) {
              begin();
              _writeLook(look.copyWith(saturation: v));
            },
            onCommit: commit,
          ),
          CanvasStepper(
            key: const ValueKey("imageBrightness"),
            label: "Brightness",
            decimals: 2,
            step: 0.05,
            dragStep: 0.01,
            min: 0,
            max: 3,
            defaultValue: 1,
            value: look.brightness,
            onChanged: (v) {
              begin();
              _writeLook(look.copyWith(brightness: v));
            },
            onCommit: commit,
          ),
        ]),
        ...pictureLookGroups(look, _writeLook, begin, commit,
            shown: look.hasImage,
            tryLook: _tryLook,
            shape: false,
            framing: false,
            crop: false,
            filter: false,
            outline: false),
      ],
    );
  }

  // ---- Effects ----------------------------------------------------------

  Widget effects() {
    var effects = picked.effects;
    var outline = _picture ? _look.outline.width : 0.0;
    var names = [
      for (var f in effects) f.kind.label,
      if (outline > 0) "Outline",
    ];
    void now(List<LayerEffect> next) {
      begin();
      write(e.withLayer(picked.id, (l) => l.copyWith(effects: next)));
      commit();
    }

    return CanvasSection(
      key: const ValueKey("imageSection-effects"),
      icon: Icons.auto_awesome_outlined,
      title: "Effects",
      summary: names.isEmpty ? "None" : names.join(" · "),
      remember: _remember("effects"),
      changes: names.length,
      onReset: () {
        var next = e.withLayer(picked.id, (l) => l.copyWith(effects: const []));
        if (_picture) {
          var look = _look.copyWith(outline: _look.outline.copyWith(width: 0));
          next = picked.isBase
              ? next.copyWith(outline: look.outline)
              : next.withLayer(picked.id, (l) => l.copyWith(look: look));
        }
        _now(next);
      },
      keywords: [
        for (var k in EffectKind.values) k.label,
        "shadow", "glow", "outline", //
      ],
      children: [
        CanvasTiles<EffectKind>(
          key: const ValueKey("imageEffects"),
          columns: 4,
          multiple: true,
          previewHeight: 28,
          tiles: [
            for (var k in EffectKind.values)
              CanvasTile(k, k.label, icon: _effectIcon(k)),
          ],
          selected: (k) => effects.any((f) => f.kind == k),
          keyOf: (k) => "effectTile-${k.name}",
          onPick: (k) => now(effects.any((f) => f.kind == k)
              ? [
                  for (var f in effects)
                    if (f.kind != k) f
                ]
              : [...effects, LayerEffect(kind: k)]),
        ),
        ...effectsGroups(controller, e, picked, write, begin, commit,
            adder: false),
        if (_picture)
          ...pictureLookGroups(_look, _writeLook, begin, commit,
              shown: _look.hasImage,
              shape: false,
              framing: false,
              crop: false,
              filter: false,
              overlay: false),
      ],
    );
  }

  // ---- A layer's own kind -----------------------------------------------

  Widget own() => switch (picked.kind) {
        LayerKind.adjustment => _adjustment(),
        LayerKind.texture => _texture(),
        LayerKind.paint => _paint(),
        _ => _fill(),
      };

  Widget _adjustment() {
    var adjust = picked.adjust;
    ImageElement withKind(AdjustKind k) => e.withLayer(
        picked.id, (l) => l.copyWith(adjust: adjust.copyWith(kind: k)));
    return CanvasSection(
      key: const ValueKey("imageSection-adjustment"),
      icon: Icons.tune,
      title: "Adjustment",
      summary: "${adjust.kind.label} · "
          "${picked.clip ? "the layer under it" : "every layer under it"}",
      remember: _remember("own"),
      initiallyOpen: true,
      changes: adjust.values.isEmpty && adjust.curves.isEmpty ? 0 : 1,
      onReset: () => _now(e.withLayer(
          picked.id,
          (l) => l.copyWith(
              adjust: ImageAdjustment(
                  kind: adjust.kind,
                  colour: adjust.colour,
                  fade: adjust.fade)))),
      keywords: [
        for (var k in AdjustKind.values) k.label,
        for (var p in adjust.kind.params) p.label,
      ],
      children: [
        CanvasTiles<AdjustKind>(
          key: const ValueKey("adjustKind"),
          columns: 4,
          previewHeight: 28,
          tiles: [
            for (var k in AdjustKind.values)
              CanvasTile(k, k.label, icon: _adjustIcon(k)),
          ],
          selected: (k) => adjust.kind == k,
          keyOf: (k) => "adjustKind-${k.name}",
          onPreview: (k) =>
              controller.tryElement(k == null ? null : withKind(k)),
          onPick: (k) => _now(withKind(k)),
        ),
        ...adjustmentSettings(controller, e, picked, write, begin, commit,
            kindPicker: false),
      ],
    );
  }

  Widget _texture() {
    var texture = picked.texture;
    ImageElement withKind(TextureKind k) {
      var next = texture.copyWith(kind: k, plainColours: true);
      // A new kind brings its own usual blend, unless the blend has been
      // chosen by hand -- see textureSettings.
      var blend = picked.blend == LayerBlend.fromName(texture.kind.blend)
          ? LayerBlend.fromName(k.blend)
          : picked.blend;
      return e.withLayer(
          picked.id, (l) => l.copyWith(texture: next, blend: blend));
    }

    return CanvasSection(
      key: const ValueKey("imageSection-texture"),
      icon: Icons.grain,
      title: "Texture",
      summary: texture.kind.label,
      remember: _remember("own"),
      initiallyOpen: true,
      changes: texture.values.isEmpty ? 0 : 1,
      onReset: () => _now(e.withLayer(picked.id,
          (l) => l.copyWith(texture: texture.copyWith(values: const {})))),
      keywords: [
        for (var k in TextureKind.values) k.label,
        for (var p in texture.kind.params) p.label,
      ],
      children: [
        CanvasTiles<TextureKind>(
          key: const ValueKey("textureKind"),
          columns: 4,
          tiles: [
            for (var k in TextureKind.values)
              CanvasTile(k, k.label, preview: (_) => _TexturePreview(k)),
          ],
          selected: (k) => texture.kind == k,
          keyOf: (k) => "textureKind-${k.name}",
          onPreview: (k) =>
              controller.tryElement(k == null ? null : withKind(k)),
          onPick: (k) => _now(withKind(k)),
        ),
        ...textureSettings(controller, e, picked, write, begin, commit,
            kindPicker: false),
      ],
    );
  }

  Widget _paint() {
    var settings = _holds(paintTools)
        ? brushToolSettings(controller, picked)
        : const <Widget>[];
    var n = picked.strokes.length;
    void set(List<dynamic> next) {
      begin();
      write(e.withLayer(picked.id, (l) => l.copyWith(strokes: next.cast())));
      commit();
    }

    return CanvasSection(
      key: const ValueKey("imageSection-paint"),
      icon: Icons.brush,
      title: "Paint",
      summary: n == 0 ? "Nothing painted yet" : "$n stroke${n == 1 ? "" : "s"}",
      remember: _remember("own"),
      initiallyOpen: true,
      forceOpen: _holds(paintTools),
      // Strokes are work done, not a setting moved: no dot, and no reset
      // that would wipe them -- the Strokes group takes them back one at a
      // time, or clears them when that is what is meant.
      keywords: const ["paint", "erase", "brush", "colour", "strokes"],
      children: [
        imageToolTiles(controller, e, picked, paintTools, settings),
        strokesGroup("Paint", picked.strokes, set),
      ],
    );
  }

  Widget _fill() => CanvasSection(
        key: const ValueKey("imageSection-fill"),
        icon: Icons.format_color_fill,
        title: "Colour fill",
        summary: picked.fill.fades ? "A fade" : "One colour",
        remember: _remember("own"),
        initiallyOpen: true,
        keywords: const ["colour", "gradient", "fade"],
        children: fillLayerSettings(e, picked, write, begin, commit),
      );

  // ---- Blend, for a layer that is not a picture -------------------------

  Widget blend() => CanvasSection(
        key: const ValueKey("imageSection-blend"),
        icon: Icons.join_inner,
        title: "Blend",
        summary: "${picked.blend.label} · ${(picked.opacity * 100).round()}%"
            "${picked.clip ? " · clipped" : ""}",
        remember: _remember("blend"),
        changes: [
          picked.blend != LayerBlend.normal,
          picked.opacity < 1,
          picked.clip,
        ].where((c) => c).length,
        onReset: () => _now(e.withLayer(
            picked.id,
            (l) =>
                l.copyWith(blend: LayerBlend.normal, opacity: 1, clip: false))),
        keywords: const ["blend", "opacity", "clip", "mode"],
        children: [
          layerBlendTiles(controller, e, picked, write, begin, commit),
          layerStrengthGroup(e, picked, write, begin, commit),
        ],
      );

  // ---- Animation --------------------------------------------------------

  Widget animation() {
    var a = e.animation;
    var stack = e.stack;
    var index = stack.indexWhere((l) => l.id == picked.id);
    var sequenced = layersSequenced(stack);
    var summary = !a.on
        ? "Arrives with the scene"
        : [
            presetName(a.preset),
            if (sequenced) "layers one after another",
          ].join(" · ");
    void change(ImageElement next) => controller.changeImage(next);
    return CanvasSection(
      key: const ValueKey("imageSection-animation"),
      icon: Icons.play_circle_outline,
      title: "Animation",
      summary: summary,
      remember: _remember("animation"),
      keywords: const [
        "arrive", "exit", "loop", "fade", "slide", "stagger", "cue", //
        "timing", "together", "preview", "keyframe",
      ],
      children: [
        elementAnimationSection(controller, e, a,
            (next) => write(e.copyWith(animation: next)), begin, commit,
            flat: true),
        if (controller.cues.isNotEmpty) elementCueGroup(controller, e),
        if (index > 0 && a.on)
          CanvasControlGroup(
            key: const ValueKey("imageLayerTiming"),
            label: "This layer",
            rule: false,
            children: [
              CanvasDropdown<VectorCue>(
                key: ValueKey("imageLayerCue-${picked.id}"),
                label: "Comes in",
                value: picked.cue,
                width: 130,
                options: [for (var c in VectorCue.values) (c, c.label)],
                onChanged: (v) =>
                    change(e.withLayer(picked.id, (l) => l.copyWith(cue: v))),
              ),
              if (picked.cue == VectorCue.gap)
                CanvasStepper(
                  key: ValueKey("imageLayerGap-${picked.id}"),
                  label: "Gap",
                  value: picked.cueGap.toDouble(),
                  min: -240,
                  max: 240,
                  suffix: " fr",
                  defaultValue: 0,
                  onChanged: (v) => controller.changeImage(
                      e.withLayer(
                          picked.id, (l) => l.copyWith(cueGap: v.round())),
                      transient: true),
                  onCommit: commit,
                ),
            ],
          ),
        if (stack.length > 1)
          CanvasControlGroup(
            label: "Every layer",
            rule: false,
            children: [
              CanvasIconButton(
                key: const ValueKey("imageLayersStagger"),
                icon: Icons.stacked_line_chart,
                tooltip: "Bring the layers in one after another",
                onPressed: () => staggerLayers(controller, e),
              ),
              if (sequenced)
                CanvasIconButton(
                  key: const ValueKey("imageLayersTogether"),
                  icon: Icons.restore,
                  tooltip: "Bring every layer in at once again",
                  onPressed: () => change(withLayersTogether(e)),
                ),
              if (a.any) previewButton(controller, e),
            ],
          ),
      ],
    );
  }

  // ---- Frame: the whole image -------------------------------------------

  Widget frame() => CanvasSection(
        key: const ValueKey("imageSection-frame"),
        icon: Icons.crop_square,
        title: "Frame",
        scope: "Whole image",
        summary: "Background, border, saved designs and looks",
        remember: "image.frame",
        keywords: const [
          "background", "border", "padding", "corners", "radius", //
          "preset", "design", "looks", "save",
        ],
        children: [
          presetsSection(context, controller, e),
          boxGroup(e.box, (box) => write(e.copyWith(box: box)), begin, commit,
              remember: "image",
              label: "Background and border",
              fillLabel: "Background",
              rule: false,
              onPadding: (box) => write(grownForPadding(e, box))),
          ImageLooks(controller: controller, element: e),
        ],
      );
}

String _trim(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

IconData _effectIcon(EffectKind k) => switch (k) {
      EffectKind.dropShadow => Icons.filter_none,
      EffectKind.outerGlow => Icons.wb_sunny_outlined,
      EffectKind.innerShadow => Icons.crop_din,
      EffectKind.blur => Icons.blur_on,
      EffectKind.motionBlur => Icons.fast_forward_outlined,
      EffectKind.zoomBlur => Icons.center_focus_strong_outlined,
      EffectKind.fringe => Icons.blur_linear,
    };

IconData _adjustIcon(AdjustKind k) => switch (k) {
      AdjustKind.brightness => Icons.brightness_6_outlined,
      AdjustKind.levels => Icons.bar_chart,
      AdjustKind.curves => Icons.show_chart,
      AdjustKind.exposure => Icons.exposure,
      AdjustKind.hueSaturation => Icons.palette_outlined,
      AdjustKind.vibrance => Icons.auto_awesome_outlined,
      AdjustKind.temperature => Icons.thermostat,
      AdjustKind.photoFilter => Icons.camera_outlined,
      AdjustKind.keepColour => Icons.colorize,
      AdjustKind.blackWhite => Icons.contrast,
      AdjustKind.gradientMap => Icons.gradient,
      AdjustKind.posterise => Icons.layers_outlined,
      AdjustKind.threshold => Icons.filter_b_and_w,
      AdjustKind.invert => Icons.invert_colors,
    };

/// _FilterPreview is the picture itself through a filter, or -- with no
/// picture loaded yet -- a run of colours through it.
class _FilterPreview extends StatelessWidget {
  final dynamic image;
  final ImageFilterPreset filter;
  const _FilterPreview({required this.image, required this.filter});

  @override
  Widget build(BuildContext context) {
    Widget picture = image == null
        ? const DecoratedBox(
            decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
            Color(0xFF3E4A5C),
            Color(0xFFE8B630),
            Color(0xFF3F8A4E),
          ])))
        : RawImage(image: image, fit: BoxFit.cover);
    var matrix = presetMatrix(filter);
    if (matrix == null) return picture;
    return ColorFiltered(
        colorFilter: ColorFilter.matrix(matrix), child: picture);
  }
}

/// _TexturePreview is a texture drawn by its own shader, over a mid grey.
class _TexturePreview extends StatelessWidget {
  final TextureKind kind;
  const _TexturePreview(this.kind);

  @override
  Widget build(BuildContext context) {
    TextureShader.load();
    return ValueListenableBuilder<bool>(
      valueListenable: TextureShader.ready,
      builder: (context, ready, _) => ready
          ? CustomPaint(painter: _TexturePainter(kind))
          : const Icon(Icons.grain, size: 18),
    );
  }
}

class _TexturePainter extends CustomPainter {
  final TextureKind kind;
  _TexturePainter(this.kind);

  @override
  void paint(Canvas canvas, Size size) {
    var all = Offset.zero & size;
    canvas.drawRect(all, Paint()..color = const Color(0xFF7D8794));
    canvas.saveLayer(all, Paint());
    canvas.drawRect(all, Paint()..color = const Color(0xFF7D8794));
    // Drawn at a bigger frame's scale and then shrunk, so a grain meant for a
    // whole picture reads at the size of a tile.
    canvas.save();
    canvas.scale(0.4);
    paintTexture(canvas, Offset.zero & (size / 0.4), TextureSpec(kind: kind));
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TexturePainter old) => old.kind != kind;
}
