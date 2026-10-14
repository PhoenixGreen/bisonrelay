import 'package:bruig/plugin_system/canvas/model/elements/image_adjustment.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_effects.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/adjustment_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:flutter/material.dart';

// effects_settings.dart is a texture layer's settings, and the effects on
// any layer -- see image_effects.dart.

/// _fields are the number fields for [params], read and written through
/// [value] and [set].
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
List<Widget> textureSettings(
    CanvasController controller,
    ImageElement e,
    ImageLayer layer,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit,
    {bool kindPicker = true}) {
  var texture = layer.texture;
  ImageLayer changed(TextureSpec next) {
    // A new kind brings its own usual blend, unless the blend has been
    // chosen by hand -- told apart by its still being the old kind's.
    var blend = next.kind != texture.kind &&
            layer.blend == LayerBlend.fromName(texture.kind.blend)
        ? LayerBlend.fromName(next.kind.blend)
        : layer.blend;
    return layer.copyWith(texture: next, blend: blend);
  }

  ImageElement with_(TextureSpec next) =>
      e.withLayer(layer.id, (_) => changed(next));
  void now(TextureSpec next) {
    begin();
    write(with_(next));
    commit();
  }

  return [
    CanvasControlGroup(
      key: const ValueKey("textureGroup"),
      label: "Texture",
      hideCaption: !kindPicker,
      rule: false,
      children: [
        if (kindPicker)
          CanvasDropdown<TextureKind>(
            key: const ValueKey("textureKind"),
            label: "Draws",
            value: texture.kind,
            width: 170,
            options: [for (var k in TextureKind.values) (k, k.label)],
            onPreview: (k) => controller.tryElement(k == null
                ? null
                : with_(texture.copyWith(kind: k, plainColours: true))),
            onChanged: (k) =>
                now(texture.copyWith(kind: k, plainColours: true)),
          ),
        CanvasIconButton(
          key: const ValueKey("textureSeed"),
          icon: Icons.shuffle,
          tooltip: "Another of the same -- different grain, blotches, light",
          onPressed: () => now(
              texture.copyWith(seed: (texture.seed * 7919 + 13) % 100000 + 1)),
        ),
        if (kindPicker)
          CanvasIconButton(
            key: const ValueKey("textureReset"),
            icon: Icons.restore,
            tooltip: "Back to where it starts",
            onPressed: texture.values.isEmpty
                ? null
                : () => now(texture.copyWith(values: const {})),
          ),
        if (kindPicker) const CanvasLineBreak(),
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

/// effectsGroups is the picked layer's effects: one to add, and each one
/// on it with its settings.
List<Widget> effectsGroups(
    CanvasController controller,
    ImageElement e,
    ImageLayer layer,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit,
    {bool adder = true}) {
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
    if (adder)
      CanvasControlGroup(
        key: const ValueKey("effectsGroup"),
        label: "Effects",
        rule: false,
        children: [
          CanvasDropdown<EffectKind?>(
            key: const ValueKey("effectAdd"),
            label: "Add an effect",
            value: null,
            width: 170,
            options: [
              (null, effects.isEmpty ? "None yet" : "${effects.length} on"),
              for (var k in EffectKind.values)
                if (!effects.any((f) => f.kind == k)) (k, k.label)
            ],
            // Each one seen on the canvas as the pointer passes over it.
            onPreview: (k) => controller.tryElement(
                k == null ? null : with_([...effects, LayerEffect(kind: k)])),
            onChanged: (k) {
              if (k == null) return;
              now([...effects, LayerEffect(kind: k)]);
            },
          ),
        ],
      ),
    for (var (i, f) in effects.indexed)
      CanvasControlGroup(
        key: ValueKey("effect-${f.kind.name}"),
        label: f.kind.label,
        rule: false,
        children: [
          CanvasToggle(
            key: ValueKey("effectOn-${f.kind.name}"),
            label: "On",
            value: f.on,
            onChanged: (v) => now(replaced(i, f.copyWith(on: v))),
          ),
          CanvasIconButton(
            key: ValueKey("effectRemove-${f.kind.name}"),
            icon: Icons.delete_outline,
            tooltip: "Take the ${f.kind.label.toLowerCase()} off",
            onPressed: () => now([...effects]..removeAt(i)),
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
        ],
      ),
  ];
}
