import 'package:bruig/plugin_system/canvas/model/elements/image_adjustment.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_effects.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/adjustment_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:flutter/material.dart';

// effects_settings.dart is a texture layer's settings, and the effects on
// any layer (see image_effects.dart).

/// _fields are the number fields for [params], read and written by [value]
/// and [set].
List<Widget> _fields(
        String prefix,
        List<AdjustParam> params,
        double Function(String) value,
        void Function(String, double) set,
        VoidCallback commit) =>
    [
      for (var p in params)
        CanvasStepper(
          key: ValueKey("$prefix-${p.key}"),
          label: p.label,
          min: p.percent ? p.min * 100 : p.min,
          max: p.percent ? p.max * 100 : p.max,
          decimals: p.decimals,
          step: adjustStep(p),
          suffix: p.percent ? "%" : "",
          defaultValue: p.percent ? p.initial * 100 : p.initial,
          value: p.percent ? value(p.key) * 100 : value(p.key),
          onChanged: (v) => set(p.key, p.percent ? v / 100 : v),
          onCommit: commit,
        ),
    ];

/// textureSettings is the picked texture layer's settings.
List<Widget> textureSettings(ImageElement e, ImageLayer layer,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  var texture = layer.texture;
  ImageElement with_(TextureSpec next) =>
      e.withLayer(layer.id, (_) => layer.copyWith(texture: next));
  void now(TextureSpec next) {
    begin();
    write(with_(next));
    commit();
  }

  return [
    CanvasControlGroup(
      key: const ValueKey("textureGroup"),
      label: "Texture",
      hideCaption: true,
      rule: false,
      children: [
        CanvasIconButton(
          key: const ValueKey("textureSeed"),
          icon: Icons.shuffle,
          tooltip: "Another of the same -- different grain, blotches, light",
          onPressed: () => now(
              texture.copyWith(seed: (texture.seed * 7919 + 13) % 100000 + 1)),
        ),
        ..._fields("texture", texture.kind.params, texture.value, (k, v) {
          begin();
          write(with_(texture.withValue(k, v)));
        }, commit),
        if (texture.kind.usesColour)
          CanvasColorButton(
            key: const ValueKey("textureColour"),
            label: "Colour",
            color: texture.colour,
            onChanged: (c) => now(texture.copyWith(colour: c)),
          ),
        if (texture.kind.usesSecond)
          CanvasColorButton(
            key: const ValueKey("textureSecond"),
            label: "And",
            color: texture.second,
            onChanged: (c) => now(texture.copyWith(second: c)),
          ),
      ],
    ),
  ];
}

/// effectsGroups is the settings of each of the picked layer's effects
/// that is in [shown].
List<Widget> effectsGroups(ImageElement e, ImageLayer layer,
    SettingsWrite write, VoidCallback begin, VoidCallback commit,
    {required Set<EffectKind> shown}) {
  var effects = layer.effects;
  ImageElement with_(List<LayerEffect> next) =>
      e.withLayer(layer.id, (l) => l.copyWith(effects: next));
  void now(List<LayerEffect> next) {
    begin();
    write(with_(next));
    commit();
  }

  List<LayerEffect> replaced(int i, LayerEffect f) => [...effects]..[i] = f;

  return [
    for (var (i, f) in effects.indexed)
      if (shown.contains(f.kind))
        CanvasControlGroup(
          key: ValueKey("effect-${f.kind.name}"),
          label: f.kind.label,
          help: "Switched off here, it stays on the list, ready to come back; "
              "the bin takes it off altogether.",
          rule: false,
          children: [
            CanvasToggle(
              key: ValueKey("effectOn-${f.kind.name}"),
              label: "On",
              value: f.on,
              onChanged: (v) => now(replaced(i, f.copyWith(on: v))),
            ),
            if (f.kind.usesColour)
              CanvasColorButton(
                key: ValueKey("effectColour-${f.kind.name}"),
                label: "Colour",
                color: f.colour,
                onChanged: (c) => now(replaced(i, f.copyWith(colour: c))),
              ),
            const CanvasLineBreak(),
            ..._fields("effect-${f.kind.name}", f.kind.params, f.value, (k, v) {
              begin();
              write(with_(replaced(i, f.withValue(k, v))));
            }, commit),
            CanvasTextButton(
              key: ValueKey("effectRemove-${f.kind.name}"),
              icon: Icons.delete_outline,
              label: "Take it off",
              onPressed: () => now([...effects]..removeAt(i)),
            ),
          ],
        ),
  ];
}

/// _openEffects is each layer's open effects this run: the panel rebuilds
/// on every edit, and an opened setting must stay open through it.
final Map<String, Set<EffectKind>> _openEffects = {};

/// forgetEffectsForTest shuts every effect's settings, as a new run has
/// them.
@visibleForTesting
void forgetEffectsForTest() => _openEffects.clear();

/// EffectTiles is a layer's effects as tiles: the first press adds and
/// opens one; later presses open and shut it, and only its switch turns it
/// off. A tick marks one on; a lit tile is open.
class EffectTiles extends StatefulWidget {
  final ImageElement element;
  final ImageLayer layer;
  final SettingsWrite write;
  final VoidCallback begin;
  final VoidCallback commit;
  final List<CanvasTile<EffectKind>> tiles;

  const EffectTiles(
      {required this.element,
      required this.layer,
      required this.write,
      required this.begin,
      required this.commit,
      required this.tiles,
      super.key});

  @override
  State<EffectTiles> createState() => _EffectTilesState();
}

class _EffectTilesState extends State<EffectTiles> {
  Set<EffectKind> get _open => _openEffects.putIfAbsent(
      "${widget.element.id}|${widget.layer.id}", () => {});

  void _press(EffectKind k) {
    var effects = widget.layer.effects;
    if (!effects.any((f) => f.kind == k)) {
      widget.begin();
      widget.write(widget.element.withLayer(widget.layer.id,
          (l) => l.copyWith(effects: [...effects, LayerEffect(kind: k)])));
      widget.commit();
      setState(() => _open.add(k));
      return;
    }
    setState(() => _open.contains(k) ? _open.remove(k) : _open.add(k));
  }

  @override
  Widget build(BuildContext context) {
    var effects = widget.layer.effects;
    var open = _open;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CanvasTiles<EffectKind>(
          key: const ValueKey("imageEffects"),
          label: "Effects",
          help: "Press one to put it on and open its settings; press it again "
              "to shut them -- the effect stays on, ticked. Turn it off with "
              "the switch in its settings.",
          // One scrolling line, as the tools are, not squeezed rows.
          scrolls: true,
          tileWidth: 84,
          multiple: true,
          previewHeight: 28,
          tiles: widget.tiles,
          selected: (k) => open.contains(k) && effects.any((f) => f.kind == k),
          ticked: (k) => effects.any((f) => f.kind == k && f.on),
          keyOf: (k) => "effectTile-${k.name}",
          onPick: _press,
        ),
        ...effectsGroups(widget.element, widget.layer, widget.write,
            widget.begin, widget.commit,
            shown: open),
      ],
    );
  }
}
