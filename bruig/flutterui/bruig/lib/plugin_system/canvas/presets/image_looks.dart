import 'dart:ui';

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_adjustment.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_effects.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/saved_preset.dart';

// image_looks.dart is the looks a picture is offered before any has been
// saved: each a few adjustment and texture layers that turn a photograph
// into something drawn or printed. Worn like a saved look, they become the
// picture's own layers, there to be changed.

/// builtInLookPrefix starts the id of every look here, so a saved look is
/// never taken for one and one is never offered for deletion.
const builtInLookPrefix = "builtin:";

ImageLayer _adjust(AdjustKind kind,
        {Map<String, double> values = const {}, PaintSpec? colours}) =>
    ImageLayer.adjusting(kind).copyWith(
        adjust: colours == null
            ? ImageAdjustment(kind: kind, values: values)
            : ImageAdjustment(kind: kind, values: values, fade: colours));

/// _ramp is [colours] spread evenly from dark to light, as a gradient map's.
PaintSpec _ramp(List<Color> colours) => PaintSpec(colours.first,
    gradient:
        GradientSpec(to: colours[1], end: 1 / (colours.length - 1), more: [
      for (var i = 2; i < colours.length; i++)
        GradientStop(colours[i], i / (colours.length - 1))
    ]));

SavedPreset _look(String key, String name, List<ImageLayer> over,
        {double soften = 0}) =>
    SavedPreset(
      id: "$builtInLookPrefix$key",
      name: name,
      kind: SavedPresetKind.look,
      made: DateTime.utc(2026),
      data: lookData(ImageElement(const ElementBase(id: "look"), layers: [
        ImageLayer.base.copyWith(effects: [
          // Softened first, so the flat tones come out as shapes, not specks.
          if (soften > 0)
            const LayerEffect(kind: EffectKind.blur)
                .withValue("amount", soften),
        ]),
        ...over,
      ])),
    );

const _ink = Color(0xFF091440);
const _paper = Color(0xFFF6F3EC);

/// builtInLooks are the looks offered with the saved ones.
final List<SavedPreset> builtInLooks = [
  // A photograph as a flat illustration: a few tones, each a colour, from
  // ink in the shadows through skin to cream.
  _look(
      "flat-portrait",
      "Flat portrait",
      [
        _adjust(AdjustKind.blackWhite),
        _adjust(AdjustKind.brightness, values: {"contrast": 0.15}),
        _adjust(AdjustKind.posterise, values: {"levels": 4}),
        _adjust(AdjustKind.gradientMap,
            colours: _ramp(const [
              _ink,
              Color(0xFF5A4A63),
              Color(0xFFC98F6B),
              Color(0xFFF1C9A5),
              Color(0xFFFFF1E0),
            ])),
      ],
      soften: 6),
  // Its own colours, cut to a few flat steps: a screen print.
  _look(
      "poster",
      "Poster",
      [
        _adjust(AdjustKind.vibrance,
            values: {"vibrance": 0.3, "saturation": 0.15}),
        _adjust(AdjustKind.posterise, values: {"levels": 5}),
      ],
      soften: 5),
  // Ink and paper, and every tone between them.
  _look("two-tone", "Two-tone", [
    _adjust(AdjustKind.blackWhite),
    _adjust(AdjustKind.gradientMap, colours: _ramp(const [_ink, _paper])),
  ]),
  // Ink or paper and nothing between: cut from card.
  _look(
      "stencil",
      "Stencil",
      [
        _adjust(AdjustKind.blackWhite),
        _adjust(AdjustKind.threshold, values: {"level": 0.45}),
        _adjust(AdjustKind.gradientMap, colours: _ramp(const [_ink, _paper])),
      ],
      soften: 4),
  // A newspaper's picture: grey, hard, and through a screen of dots.
  _look("newsprint", "Newsprint", [
    _adjust(AdjustKind.blackWhite),
    _adjust(AdjustKind.brightness, values: {"contrast": 0.3}),
    ImageLayer.texturing(TextureKind.halftone),
  ]),
];
