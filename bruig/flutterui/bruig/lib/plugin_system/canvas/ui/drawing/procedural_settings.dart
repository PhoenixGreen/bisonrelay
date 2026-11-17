import 'package:bruig/plugin_system/canvas/model/procedural_effects.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_layers.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_light.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_palettes.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_params.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_style_params.dart';
import 'package:bruig/plugin_system/canvas/presets/background_looks.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/procedural_thumb.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_rings.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/recent_pictures.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/image_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/pitch_orbit_pad.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/pitch_views.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/pitch.dart';

part 'procedural_icon_slot.dart';
part 'procedural_groups.dart';
part 'procedural_effects.dart';

// procedural_settings.dart is the one panel for a generated background, on the
// canvas or in an element. The five shared amounts (density, scale, intensity,
// variation, seed) and the colours show for every style, so every generator
// must give all five a meaning; see render/procedural/generators.dart.

/// ProceduralSettings edits a [ProceduralSpec].
class ProceduralSettings extends StatelessWidget {
  final ProceduralSpec spec;
  final ValueChanged<ProceduralSpec> onChanged;
  final VoidCallback onBegin;
  final VoidCallback onCommit;

  /// onReset puts the whole thing back to its default, where the caller has
  /// something for that to mean. Null leaves the button out.
  final VoidCallback? onReset;

  /// canvasFrames is how long the canvas is, for the button that makes one
  /// run of the movement fit it; null where there is none to offer.
  final int? canvasFrames;

  /// label names the group. Empty by default: the panel's own header already
  /// says whose background this is.
  final String label;

  /// layer is whether this is a layer over a background: only its pattern is
  /// drawn, so the light, lens, film and the movement's run are not offered.
  final bool layer;

  /// fill is whether this is a pattern painted into text or a shape, with its
  /// style, look, colours and amounts on the row above: only the style's own
  /// settings and the effects are left.
  final bool fill;

  /// sections lays the settings out in the sections every element's panel has,
  /// each remembered open or shut under [rememberAs]. See panel_kit.dart.
  final bool sections;
  final String rememberAs;

  /// kindPicker chooses what the background draws (this pattern, or a stage),
  /// put first in its Pattern layers; null for a layer or a fill. See
  /// backdrop_settings.dart.
  final Widget? kindPicker;

  const ProceduralSettings({
    this.kindPicker,
    this.sections = false,
    this.rememberAs = "background",
    required this.spec,
    required this.onChanged,
    required this.onBegin,
    required this.onCommit,
    this.onReset,
    this.canvasFrames,
    this.label = "",
    this.layer = false,
    this.fill = false,
    super.key,
  });

  void _set(ProceduralSpec next) => onChanged(next);

  /// _rings and _ringsNow are _set and _setNow for the Rings style's own
  /// settings, which live in a spec of their own. See RingSpec.
  void _rings(RingSpec next) => _set(spec.copyWith(rings: next));

  void _ringsNow(RingSpec next) => _setNow(spec.copyWith(rings: next));

  /// _put replaces or removes the icon for one of the two placings. A document
  /// holding more than one of a placing is collapsed to the first when touched.
  void _put(RingSpec rings, RingIconPlace place, RingIcon? next) {
    var kept = {
      for (var p in RingIconPlace.values)
        p: p == place
            ? next
            : rings.icons.where((icon) => icon.place == p).firstOrNull,
    };
    _ringsNow(rings.copyWith(icons: [
      for (var p in RingIconPlace.values)
        if (kept[p] != null) kept[p]!,
    ]));
  }

  // ---- procedural_icon_slot.dart ------------------------------------------

  /// _sectionOf is which section [w], one of [_groups], belongs in.
  static String _sectionOf(Widget w) {
    if (w is Padding && w.child is CanvasExpander) w = w.child!;
    var label = switch (w) {
      CanvasControlGroup g => g.label,
      CanvasExpander x => x.label,
      _ => "",
    };
    return switch (label) {
      "Colours" || "Amount" => "colour",
      "Movement" => "movement",
      "Effects" => "effects",
      "Lights" => "lights",
      _ => "pattern",
    };
  }

  @override
  Widget build(BuildContext context) {
    if (fill) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ..._ownGroups(),
            if (spec.style.usesGlyphs) _symbols(),
            if (spec.style == ProceduralStyle.metal) _metalGroup(),
            _effects(),
          ]);
    }
    if (!layer) return _Layered(owner: this);
    var groups = _groups(context);
    if (sections) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: _sectioned(groups));
    }
    // Down the column like every other element's settings: a Row of five
    // groups in a narrow sidebar overflows, and does not shrink.
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: groups);
  }

  // ---- procedural_effects.dart --------------------------------------------

  static const _fineTune = {
    "perspective",
    "tiltV",
    "tiltH",
    "turn",
    "panX",
    "panY"
  };
}

/// _Layered is a background's settings with its layers: a list of them over
/// the settings of the one chosen, which is this panel's to remember, not
/// the document's.
class _Layered extends StatefulWidget {
  final ProceduralSettings owner;
  const _Layered({required this.owner});

  @override
  State<_Layered> createState() => _LayeredState();
}

class _LayeredState extends State<_Layered> {
  /// editing is nought for the background's own pattern, or one more than
  /// the index of the layer being edited.
  int editing = 0;

  ProceduralSettings get owner => widget.owner;
  ProceduralSpec get spec => owner.spec;

  void _layers(List<BackgroundLayer> next, {int? select}) {
    owner.onBegin();
    owner.onChanged(spec.copyWith(layers: next));
    owner.onCommit();
    if (select != null) setState(() => editing = select);
  }

  void _put(int i, BackgroundLayer next, {bool now = true}) {
    var layers = [...spec.layers];
    layers[i] = next;
    if (now) {
      _layers(layers);
    } else {
      owner.onChanged(spec.copyWith(layers: layers));
    }
  }

  /// _added is a new layer: a fine dot grid in the background's own colours,
  /// screened over it -- something to see at once, and to change from there.
  BackgroundLayer _added() {
    var first = looksFor(ProceduralStyle.dotGrid).firstOrNull?.spec ??
        const ProceduralSpec(style: ProceduralStyle.dotGrid);
    return BackgroundLayer(
      spec: first.copyWith(
        background: spec.background,
        foreground: spec.foreground,
        accent: spec.accent,
        vignette: 0,
      ),
      opacity: 0.6,
      blend: LayerBlend.screen,
    );
  }

  @override
  Widget build(BuildContext context) {
    var layers = spec.layers;
    var at = editing.clamp(0, layers.length);
    var theme = ThemeNotifier.of(context);

    Widget row(int index) {
      // Index nought is the background; the rest are layers, top first.
      var isBase = index == 0;
      var layer = isBase ? null : layers[index - 1];
      var shown = isBase
          ? spec.copyWith(layers: const [])
          : layer!.spec.copyWith(
              background: layer.spec.style == ProceduralStyle.plain
                  ? null
                  : spec.background,
              vignette: 0);
      var chosen = at == index;
      return Material(
        key: ValueKey("layerRow-$index"),
        color:
            chosen ? theme.colors.surfaceContainerHighest : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => setState(() => editing = index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: Row(children: [
              Opacity(
                opacity: layer?.visible == false ? 0.35 : 1,
                child: ProceduralThumb(shown),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isBase
                      ? "Background · ${spec.style.label}"
                      : "${layer!.spec.style.label}"
                          "${layer.blend == LayerBlend.normal ? "" : " · ${layer.blend.label}"}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      color: chosen
                          ? theme.colors.onSurface
                          : theme.colors.onSurfaceVariant),
                ),
              ),
              if (!isBase) ...[
                CanvasIconButton(
                  key: ValueKey("layerEye-$index"),
                  icon: layer!.visible
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  tooltip: layer.visible ? "Hide" : "Show",
                  tight: true,
                  onPressed: () =>
                      _put(index - 1, layer.copyWith(visible: !layer.visible)),
                ),
                CanvasIconButton(
                  key: ValueKey("layerUp-$index"),
                  icon: Icons.arrow_upward,
                  tooltip: "Move up",
                  tight: true,
                  onPressed: index == layers.length
                      ? null
                      : () {
                          var next = [...layers];
                          next.insert(index, next.removeAt(index - 1));
                          _layers(next, select: index + 1);
                        },
                ),
                CanvasIconButton(
                  key: ValueKey("layerDown-$index"),
                  icon: Icons.arrow_downward,
                  tooltip: "Move down",
                  tight: true,
                  onPressed: index == 1
                      ? null
                      : () {
                          var next = [...layers];
                          next.insert(index - 2, next.removeAt(index - 1));
                          _layers(next, select: index - 1);
                        },
                ),
                CanvasIconButton(
                  key: ValueKey("layerDelete-$index"),
                  icon: Icons.delete_outline,
                  tooltip: "Remove",
                  tight: true,
                  onPressed: () =>
                      _layers([...layers]..removeAt(index - 1), select: 0),
                ),
              ],
            ]),
          ),
        ),
      );
    }

    var list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top first, as a stack is seen from above: the background last.
        for (var i = layers.length; i >= 0; i--) row(i),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey("addLayer"),
            onPressed: layers.length >= maxBackgroundLayers
                ? null
                : () =>
                    _layers([...layers, _added()], select: layers.length + 1),
            icon: const Icon(Icons.add, size: 16),
            label: Text(layers.length >= maxBackgroundLayers
                ? "Three layers at most"
                : "Add layer"),
          ),
        ),
      ],
    );

    List<Widget> body;
    if (at == 0) {
      body = owner._groups(context);
      if (owner.sections) body = owner._sectioned(body);
    } else {
      var layer = layers[at - 1];
      body = [
        CanvasControlGroup(label: "Layer", children: [
          CanvasNumberField(
            key: const ValueKey("layerOpacity"),
            label: "Opacity",
            value: layer.opacity,
            min: 0,
            max: 1,
            decimals: 2,
            width: 62,
            onChanged: (v) {
              owner.onBegin();
              _put(at - 1, layer.copyWith(opacity: v), now: false);
            },
            onCommit: owner.onCommit,
          ),
          CanvasDropdown<LayerBlend>(
            key: const ValueKey("layerBlend"),
            label: "Blend",
            value: layer.blend,
            width: 110,
            options: [for (var b in LayerBlend.values) (b, b.label)],
            onChanged: (v) => _put(at - 1, layer.copyWith(blend: v)),
          ),
        ]),
        ProceduralSettings(
          key: ValueKey("layerSettings-$at"),
          layer: true,
          sections: owner.sections,
          rememberAs: "${owner.rememberAs}.layer",
          spec: layer.spec,
          onBegin: owner.onBegin,
          onCommit: owner.onCommit,
          onChanged: (s) => _put(at - 1, layer.copyWith(spec: s), now: false),
        ),
      ];
    }

    if (owner.sections) {
      // The layers as a section of their own, and the picked one's
      // settings under them, its opacity and blend in their own section.
      var picked = at == 0 ? null : layers[at - 1];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          CanvasSection(
            key: const ValueKey("backgroundSection-layers"),
            icon: Icons.layers_outlined,
            title: "Pattern layers",
            summary: layers.isEmpty
                ? "One pattern"
                : "${layers.length + 1} patterns · editing "
                    "${at == 0 ? "the background" : "layer $at"}",
            remember: "${owner.rememberAs}.layers",
            children: [if (owner.kindPicker case var k?) k, list],
          ),
          if (picked != null)
            CanvasSection(
              key: const ValueKey("backgroundSection-layer"),
              icon: Icons.tune,
              title: "Layer $at",
              summary: "${(picked.opacity * 100).round()}% · "
                  "${picked.blend.label}",
              remember: "${owner.rememberAs}.layer",
              initiallyOpen: true,
              children: [body.first],
            ),
          ...(picked == null ? body : body.skip(1)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // "Pattern layers" rather than "Layers", which is already the name
        // of the sidebar's list of everything on the canvas.
        CanvasExpander(
          label: "Pattern layers",
          remember: "background.layers",
          initiallyOpen: true,
          trailing: layers.isEmpty ? "None" : "${layers.length}",
          children: [
            if (owner.kindPicker case var k?) k,
            Padding(
              padding: const EdgeInsets.only(bottom: canvasGroupGap - 10),
              child: list,
            ),
          ],
        ),
        ...body,
      ],
    );
  }
}

/// patternStyleDropdown chooses a pattern's style, shown rather than named,
/// under the kind each one is. Choosing one starts from its first look: a style
/// in the last one's colours and numbers is rarely a good picture of it.
Widget patternStyleDropdown({
  Key? key,
  required ProceduralSpec spec,
  required ValueChanged<ProceduralSpec> onChanged,
  String label = "Style",
  double width = 150,
}) =>
    CanvasDropdown<ProceduralStyle>(
      key: key,
      label: label,
      value: spec.style,
      width: width,
      options: [
        for (var f in StyleFamily.values)
          for (var s in ProceduralStyle.values)
            if (s.family == f) (s, s.label),
      ],
      groupOf: (s) => s.family.label,
      leading: (s) => ProceduralThumb(styleThumbSpec(s)),
      onChanged: (v) {
        if (v == spec.style) return;
        var first = looksFor(v).firstOrNull;
        onChanged(first == null
            ? spec.copyWith(style: v, params: const {})
            : withLook(spec, first));
      },
    );

/// patternLookDropdown chooses one of a style's looks, each shown.
Widget patternLookDropdown({
  Key? key,
  required ProceduralSpec spec,
  required ValueChanged<ProceduralSpec> onChanged,
  double width = 150,
}) {
  var looks = looksFor(spec.style);
  var chosen = lookMatching(spec)?.name ?? "";
  return CanvasDropdown<String>(
    key: key,
    label: "Look",
    value: chosen,
    width: width,
    options: [
      if (chosen.isEmpty) ("", "Custom"),
      for (var l in looks) (l.name, l.name),
    ],
    leading: (name) {
      var look = looks.where((l) => l.name == name).firstOrNull;
      return look == null
          ? const SizedBox(width: 36, height: 20)
          : ProceduralThumb(look.spec);
    },
    onChanged: (name) {
      for (var l in looks) {
        if (l.name == name) onChanged(withLook(spec, l));
      }
    },
  );
}

/// patternPaletteDropdown recolours a pattern with a palette or the app's own.
Widget patternPaletteDropdown(
  BuildContext context, {
  Key? key,
  required ProceduralSpec spec,
  required ValueChanged<ProceduralSpec> onChanged,
  double width = 150,
}) {
  var theme = themePalette(context);
  var name = theme.matches(spec)
      ? "theme"
      : backgroundPalettes.where((p) => p.matches(spec)).firstOrNull?.name ??
          "";
  BackgroundPalette? named(String n) => n == "theme" ? theme : paletteNamed(n);
  return CanvasDropdown<String>(
    key: key,
    label: "Palette",
    value: name,
    width: width,
    options: [
      if (name == "") ("", "Custom"),
      ("theme", "My theme"),
      for (var p in backgroundPalettes) (p.name, p.name),
    ],
    leading: (n) => paletteSwatch(named(n)),
    onChanged: (n) {
      var p = named(n);
      if (p != null) onChanged(p.on(spec));
    },
  );
}

/// themePalette is the colours the app is wearing, as a palette.
BackgroundPalette themePalette(BuildContext context) {
  var c = Theme.of(context).colorScheme;
  return BackgroundPalette("My theme", c.surface, c.primary, c.secondary,
      baseTo: c.surfaceContainerHighest);
}

/// paletteSwatch is a palette's colours side by side, or a blank the same
/// size for none.
Widget paletteSwatch(BackgroundPalette? p) => SizedBox(
      width: 36,
      height: 16,
      child: p == null
          ? null
          : ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var c in p.colours)
                      Expanded(child: ColoredBox(color: c)),
                  ]),
            ),
    );
