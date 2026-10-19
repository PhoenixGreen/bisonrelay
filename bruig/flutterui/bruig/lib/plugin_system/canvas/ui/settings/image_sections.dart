import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
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
import 'package:bruig/plugin_system/canvas/ui/settings/paint_brushes.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/presets_section.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
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
  var s = _Sections(context, controller, e, picked, write, begin, commit);
  var together = editing && controller.alignableLayers.length >= 2;
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
    CanvasSections(
      key: const ValueKey("imageSections"),
      children: [if (together) s.arrange(), ...sections],
    ),
  ];
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

  // ---- Arrange: several picture layers picked ----------------------------

  Widget arrange() {
    var n = controller.alignableLayers.length;
    return CanvasSection(
      key: const ValueKey("imageSection-arrange"),
      icon: Icons.align_horizontal_left,
      title: "Arrange",
      summary: "$n layers picked",
      remember: "image.arrange",
      initiallyOpen: true,
      forceOpen: true,
      children: [
        CanvasControlGroup(
          key: const ValueKey("imageArrangeAlign"),
          label: "Line up",
          help: "Lined up against the box the picked layers make between "
              "them, so the outermost stay where they are. Shift- or "
              "Command-click a layer, here or on the canvas, to pick it with "
              "the others.",
          rule: false,
          children: [
            for (var align in CanvasAlign.values)
              CanvasTextButton(
                key: ValueKey("layerAlign-${align.name}"),
                icon: align.icon,
                label: "",
                tooltip: align.label,
                onPressed: () => controller.alignSelected(align),
              ),
          ],
        ),
        CanvasControlGroup(
          key: const ValueKey("imageArrangeSpread"),
          label: "Spread out",
          help: "Even gaps between three or more picked layers; the two on "
              "the ends stay put.",
          rule: false,
          children: [
            CanvasTextButton(
              key: const ValueKey("layerSpreadAcross"),
              icon: Icons.horizontal_distribute,
              label: "Across",
              onPressed: n < 3 ? null : () => controller.spreadSelected(true),
            ),
            CanvasTextButton(
              key: const ValueKey("layerSpreadDown"),
              icon: Icons.vertical_distribute,
              label: "Down",
              onPressed: n < 3 ? null : () => controller.spreadSelected(false),
            ),
          ],
        ),
      ],
    );
  }

  // ---- Position ---------------------------------------------------------

  Widget position() {
    var look = _look;
    String summary;
    // A plain picture is its frame, and is placed as any element is; with
    // layers, its base picture has a place in the frame of its own, and the
    // frame is the Frame section's.
    var framed = picked.isBase && !e.layered;
    if (framed) {
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
      children: [
        if (framed)
          positionGroup(controller, e, write, begin, commit)
        else ...[
          layerPositionGroup(controller, e, picked, write, begin, commit),
          CanvasControlGroup(
            label: "Quick moves",
            help: "One press each: flip it, fill the frame with it, fit it "
                "inside, put it in the middle, or give it back the picture's "
                "own proportions.",
            rule: false,
            children:
                layerQuickMoves(controller, e, picked, write, begin, commit),
          ),
        ],
        CanvasControlGroup(
          label: "Picture",
          help: "Put a picture in or replace it -- from a file or from the "
              "pictures already added -- change its size and quality, or "
              "take it out. Fit is how it fills its frame; with Cover, "
              "double-click the picture to move it about inside its frame "
              "and scroll to zoom.",
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
            // Framing only where there is slack to frame with -- the note
            // saying so is in the Picture card's "?".
            framing: look.fit == ImageFit.cover,
            // A drift runs on the picture the element is, not on a layer.
            drift: picked.isBase,
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
            if (feather > 0) "feather ${shortNumber(feather)} px",
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
      children: [
        imageToolTiles(controller, e, picked, tools, settings,
            help: framed
                ? "Hide parts of this layer: brush it away, draw round it, or "
                    "fade it across. Every mark can be taken back."
                : "Hide the background, or anything else: let Select subject "
                    "find the person, brush over what to keep, refine the "
                    "hair, or mark by hand. Every mark can be taken back."),
        ...maskGroupsFor(mask, put, begin, commit,
            framed: framed, controller: controller),
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
      children: [
        imageToolTiles(controller, e, picked, retouchTools, settings,
            help: "Brushwork on the picture itself: copy one part over "
                "another, heal a spot, lighten or darken, soften, crisp or "
                "smudge. Kept as strokes, so it stays sharp at any size."),
        strokesGroup("Retouching", look.retouch, set),
      ],
    );
  }

  // ---- Colour -----------------------------------------------------------

  Widget colour() {
    var look = _look;
    var picture = look.hasImage
        ? controller.images.resolve(look.assetId, look.removal)
        : null;
    var image = picture == null ? null : controller.images.thumbnail(picture);
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
      children: [
        CanvasTiles<ImageFilterPreset>(
          key: const ValueKey("imageFilter"),
          foldAs: "image.tiles.filter",
          label: "Filter",
          help: "A ready-made look for the whole picture. Click one to "
              "use it.",
          columns: 4,
          tiles: [
            for (var f in ImageFilterPreset.values)
              CanvasTile(f, f.label,
                  drawnFrom: (f, image),
                  paint: (canvas, size) =>
                      paintFilterPreview(canvas, size, image, f)),
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
        CanvasControlGroup(
            label: "Fine-tune",
            help: "Small changes on top of the filter. 1 is as the picture "
                "came.",
            rule: false,
            children: [
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
      children: [
        EffectTiles(
          controller: controller,
          element: e,
          layer: picked,
          write: write,
          begin: begin,
          commit: commit,
          tiles: [
            for (var k in EffectKind.values)
              CanvasTile(k, k.label, icon: _effectIcon(k)),
          ],
        ),
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
      children: [
        CanvasTiles<AdjustKind>(
          help:
              "What the adjustment does to every layer under it -- or, clipped, to the one under it.",
          key: const ValueKey("adjustKind"),
          foldAs: "image.tiles.adjust",
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
      children: [
        CanvasTiles<TextureKind>(
          help: "Drawn over the whole frame by the canvas itself, at any size.",
          key: const ValueKey("textureKind"),
          foldAs: "image.tiles.texture",
          columns: 4,
          tiles: [
            for (var k in TextureKind.values)
              CanvasTile(k, k.label,
                  drawnFrom: (k, TextureShader.ready.value),
                  paint: (canvas, size) =>
                      _TexturePainter(k).paint(canvas, size)),
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
    var retouching = _holds(retouchTools)
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
      forceOpen: _holds(paintTools) || _holds(retouchTools),
      // Strokes are work done, not a setting moved: no dot, and no reset
      // that would wipe them -- the Strokes group takes them back one at a
      // time, or clears them when that is what is meant.
      children: [
        imageToolTiles(controller, e, picked, paintTools, settings,
            help: "Paint on this layer, and rub it out again. Pick a brush "
                "below, or make one of your own; a pen's pressure and lean "
                "drive it as its Pen settings say."),
        if (_holds(paintTools)) PaintBrushCards(controller: controller),
        imageToolTiles(controller, e, picked, retouchTools, retouching,
            help: "Retouching on a paint layer works on everything under it, "
                "anywhere in the frame: copy one part over another, heal, "
                "lighten or darken, soften, crisp or smudge."),
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
      children: [
        elementAnimationSection(controller, e, a,
            (next) => write(e.copyWith(animation: next)), begin, commit),
        if (controller.cues.isNotEmpty) elementCueGroup(controller, e),
        if (index > 0 && a.on)
          CanvasControlGroup(
            key: const ValueKey("imageLayerTiming"),
            label: "This layer",
            help: "When this layer comes in against the one under it. Its "
                "lane on the timeline can be dragged as well.",
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
            help: "The timing of all the layers at once: one after another, "
                "or all together.",
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
        summary: e.layered
            ? "${e.width.round()} × ${e.height.round()} · "
                "${e.scaleContent ? "content scales" : "content stays put"}"
            : "Background, border, saved designs and looks",
        remember: "image.frame",
        children: [
          // The frame round the layers: where it is and how big, and whether
          // sizing it sizes them. A plain picture's is in Position.
          if (e.layered) ...[
            positionGroup(controller, e, write, begin, commit),
            CanvasControlGroup(
              key: const ValueKey("imageFrameScaling"),
              label: "When the frame is resized",
              help: "Off, the frame is resized round the layers: each stays "
                  "its size, where it is on the page -- so a layer can run "
                  "past the base picture, and the base picture can be sized "
                  "on its own in Position. On, everything in the frame is "
                  "scaled with it.",
              rule: false,
              children: [
                CanvasToggle(
                  key: const ValueKey("imageScaleContent"),
                  label: "Scale content",
                  value: e.scaleContent,
                  onChanged: (v) {
                    begin();
                    write(e.copyWith(scaleContent: v));
                    commit();
                  },
                ),
              ],
            ),
            CanvasControlGroup(
              key: const ValueKey("imageFrameClip"),
              label: "What runs past the frame",
              help: "Off, nothing is cut: paint a stroke past the frame or "
                  "drag a layer out of it and the frame grows to take it in, "
                  "and a shadow or a glow is drawn where it falls. On, "
                  "everything is cut to the frame -- for a picture cut to a "
                  "shape, or with rounded corners. Fit to content makes the "
                  "frame exactly round what is in it, smaller as well as "
                  "larger.",
              rule: false,
              children: [
                CanvasToggle(
                  key: const ValueKey("imageClip"),
                  label: "Clip to frame",
                  value: e.clip,
                  onChanged: (v) {
                    begin();
                    write(e.copyWith(clip: v));
                    commit();
                  },
                ),
                CanvasTextButton(
                  key: const ValueKey("imageFitFrame"),
                  icon: Icons.fit_screen_outlined,
                  label: "Fit frame to content",
                  onPressed: () {
                    begin();
                    write(e.fittedToContent());
                    commit();
                  },
                ),
              ],
            ),
          ],
          presetsSection(context, controller, e),
          // Rounding the corners cuts to them: corners round a picture that
          // spills past them are not corners.
          boxGroup(
              e.box,
              (box) => write(e.copyWith(
                  box: box,
                  clip: box.isRounded && !e.box.isRounded ? true : null)),
              begin,
              commit,
              remember: "image",
              label: "Background and border",
              fillLabel: "Background",
              rule: false,
              onPadding: (box) => write(grownForPadding(e, box))),
          ImageLooks(controller: controller, element: e),
        ],
      );
}

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

/// paintFilterPreview is the picture itself through [filter], or -- with no
/// picture yet -- a strip of colour through it, so the tiles still differ.
void paintFilterPreview(
    Canvas canvas, Size size, ui.Image? image, ImageFilterPreset filter) {
  var all = Offset.zero & size;
  var matrix = presetMatrix(filter);
  var paint = Paint()..filterQuality = FilterQuality.medium;
  if (matrix != null) paint.colorFilter = ColorFilter.matrix(matrix);
  if (image == null) {
    paint.shader = const LinearGradient(colors: [
      Color(0xFF3E4A5C),
      Color(0xFFE8B630),
      Color(0xFF3F8A4E),
    ]).createShader(all);
    canvas.drawRect(all, paint);
    return;
  }
  // Cover: the picture's middle, cut to the tile's shape.
  var iw = image.width.toDouble(), ih = image.height.toDouble();
  var scale = math.max(size.width / iw, size.height / ih);
  var sw = size.width / scale, sh = size.height / scale;
  canvas.drawImageRect(
      image, Rect.fromLTWH((iw - sw) / 2, (ih - sh) / 2, sw, sh), all, paint);
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
