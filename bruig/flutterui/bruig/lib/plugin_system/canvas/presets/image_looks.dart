import 'dart:ui';

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_adjustment.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_effects.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/saved_preset.dart';

// image_looks.dart is the actions a picture is offered before any has been
// saved: each a few layers -- adjustments, textures, colour, copies of the
// picture with their own blend and effects -- that turn a photograph into
// something filmed, drawn or printed. Done like a saved action, they become
// the picture's own layers, there to be changed. They grew from looks,
// whose ids they keep.

/// builtInLookPrefix starts the id of every action here, so a saved look is
/// never taken for one and one is never offered for deletion.
const builtInLookPrefix = "builtin:";

ImageLayer _adjust(AdjustKind kind,
        {Map<String, double> values = const {},
        PaintSpec? colours,
        String table = "",
        bool clip = false,
        double opacity = 1,
        LayerBlend blend = LayerBlend.normal}) =>
    ImageLayer.adjusting(kind).copyWith(
        clip: clip,
        opacity: opacity,
        blend: blend,
        adjust: colours == null
            ? ImageAdjustment(kind: kind, values: values, table: table)
            : ImageAdjustment(kind: kind, values: values, fade: colours));

/// _curve is a curves adjustment through [points] (across, up; 0 to 1).
ImageLayer _curve(List<Offset> points) =>
    ImageLayer.adjusting(AdjustKind.curves).copyWith(
        adjust: const ImageAdjustment(kind: AdjustKind.curves)
            .withCurve(CurveChannel.rgb, points));

/// _texture is a texture layer of [kind] in its usual blend.
ImageLayer _texture(TextureKind kind,
    {Map<String, double> values = const {}, double opacity = 1}) {
  var layer = ImageLayer.texturing(kind);
  return layer.copyWith(
      opacity: opacity, texture: layer.texture.copyWith(values: values));
}

/// _stand is the picture the actions here are made on: copies of it are
/// copies of whatever picture an action is done to.
const _stand = ImageElement(ElementBase(id: "look", width: 1000, height: 1000),
    assetId: "builtin-picture");

/// _copy is a copy of the picture, moved by [shift] (see pictureCopy), in
/// [blend] at [opacity], with [effects].
ImageLayer _copy(
        {LayerBlend blend = LayerBlend.normal,
        double opacity = 1,
        List<LayerEffect> effects = const [],
        List<double> shift = const [0, 0, 1, 1],
        bool flipX = false}) =>
    pictureCopy(_stand, shift: shift).copyWith(
        blend: blend, opacity: opacity, effects: effects, flipX: flipX);

LayerEffect _blur(double amount) =>
    const LayerEffect(kind: EffectKind.blur).withValue("amount", amount);

/// _ramp is [colours] spread evenly from dark to light, as a gradient map's.
PaintSpec _ramp(List<Color> colours) => PaintSpec(colours.first,
    gradient:
        GradientSpec(to: colours[1], end: 1 / (colours.length - 1), more: [
      for (var i = 2; i < colours.length; i++)
        GradientStop(colours[i], i / (colours.length - 1))
    ]));

SavedPreset _look(String key, String name, List<ImageLayer> over,
        {double soften = 0, List<LayerEffect> baseEffects = const []}) =>
    SavedPreset(
      id: "$builtInLookPrefix$key",
      name: name,
      kind: SavedPresetKind.look,
      made: DateTime.utc(2026),
      data: lookData(_stand.withLayers([
        ImageLayer.base.copyWith(effects: [
          // Softened first, so the flat tones come out as shapes, not specks.
          if (soften > 0)
            const LayerEffect(kind: EffectKind.blur)
                .withValue("amount", soften),
          ...baseEffects,
        ]),
        ...over,
      ])),
    );

const _ink = Color(0xFF091440);
const _paper = Color(0xFFF6F3EC);

/// builtInLooks are the actions offered with the saved ones.
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

  // ---- Film ----------------------------------------------------------------

  // Blacks lifted to grey, whites dulled, a little warmth and grain.
  _look("faded-film", "Faded film", [
    _curve(const [Offset(0, 0.12), Offset(0.5, 0.52), Offset(1, 0.92)]),
    _adjust(AdjustKind.vibrance, values: {"saturation": -0.2}),
    _adjust(AdjustKind.temperature, values: {"warmth": 0.12}),
    _texture(TextureKind.grain, values: {"amount": 0.25}),
  ]),
  _look("portrait-film", "Portrait film", [
    _adjust(AdjustKind.colourTable, table: "portrait-warm"),
    _texture(TextureKind.grain, values: {"amount": 0.2}),
  ]),
  _look("slide-film", "Slide film", [
    _adjust(AdjustKind.colourTable, table: "slide-vivid"),
    _adjust(AdjustKind.clarity, values: {"clarity": 0.2}),
  ]),
  _look("cinema", "Cinema", [
    _adjust(AdjustKind.colourTable, table: "cinema-cool"),
    _texture(TextureKind.vignette, values: {"radius": 0.7}, opacity: 0.6),
  ]),
  // Shadows to teal, skin and highlights to orange: a blockbuster's grade.
  _look("teal-orange", "Teal and orange", [
    _adjust(AdjustKind.colourBalance, values: {
      "shadowsRed": -0.5,
      "shadowsBlue": 0.45,
      "highsRed": 0.45,
      "highsBlue": -0.4,
    }),
    _adjust(AdjustKind.colourMixer, values: {
      "orangeSat": 0.25,
      "aquaHue": -0.3,
      "blueHue": -0.5,
      "greenSat": -0.4,
    }),
    _adjust(AdjustKind.brightness, values: {"contrast": 0.12}),
  ]),
  _look("cross-process", "Cross-processed", [
    _adjust(AdjustKind.colourTable, table: "cross-process"),
  ]),
  _look("vintage-warm", "Vintage warm", [
    _adjust(AdjustKind.photoFilter, values: {"density": 0.35}),
    _curve(const [Offset(0, 0.08), Offset(1, 0.95)]),
    _texture(TextureKind.vignette,
        values: {"radius": 0.75, "softness": 0.7}, opacity: 0.5),
    _texture(TextureKind.dust, values: {"specks": 0.2, "scratches": 0.1}),
  ]),
  _look("light-leaks", "Light leaks", [
    _texture(TextureKind.lightLeak),
    _texture(TextureKind.grain, values: {"amount": 0.2}),
  ]),
  _look("matte-bw", "Matte black and white", [
    _adjust(AdjustKind.blackWhite),
    _curve(const [Offset(0, 0.14), Offset(0.6, 0.62), Offset(1, 0.9)]),
    _texture(TextureKind.grain, values: {"amount": 0.35}),
  ]),
  _look("duotone", "Duotone", [
    _adjust(AdjustKind.blackWhite),
    _adjust(AdjustKind.gradientMap,
        colours: _ramp(const [Color(0xFF1B1F5E), Color(0xFFFF6B5A)])),
  ]),

  // ---- Light -------------------------------------------------------------

  // A blurred copy screened over: everything glows, nothing goes soft.
  _look("orton-glow", "Orton glow", [
    _copy(blend: LayerBlend.screen, opacity: 0.55, effects: [_blur(18)]),
    _adjust(AdjustKind.clarity, values: {"clarity": 0.25}),
  ]),
  _look("hdr", "HDR", [
    _adjust(AdjustKind.shadowsHighlights,
        values: {"shadows": 0.7, "highlights": 0.6}),
    _adjust(AdjustKind.clarity, values: {"clarity": 0.7}),
    _adjust(AdjustKind.vibrance, values: {"vibrance": 0.35}),
  ]),
  _look("soft-skin", "Soft skin", [
    _copy(opacity: 0.4, effects: [_blur(5)]),
    _adjust(AdjustKind.temperature, values: {"warmth": 0.06}),
  ]),
  _look("sharpen-web", "Sharpen for the web", [
    _adjust(AdjustKind.sharpen, values: {"amount": 0.7, "radius": 1}),
  ]),
  // The picture dimmed, its edges lit in its own colours, and glowing.
  _look("neon", "Neon glow", [
    _adjust(AdjustKind.exposure, values: {"stops": -1.6}),
    _copy(blend: LayerBlend.screen, effects: [
      const LayerEffect(kind: EffectKind.outerGlow)
          .withValue("size", 24)
          .withValue("opacity", 0.9),
    ]),
    _adjust(AdjustKind.findEdges,
        values: {"strength": 2.5, "colour": 1}, clip: true),
    _adjust(AdjustKind.invert, clip: true),
    _adjust(AdjustKind.vibrance,
        values: {"vibrance": 1, "saturation": 0.6}, clip: true),
  ]),
  // Itself again, flipped, larger, laid over lightly.
  _look("double-exposure", "Double exposure", [
    _copy(
        blend: LayerBlend.screen,
        opacity: 0.6,
        flipX: true,
        shift: const [-0.15, -0.15, 1.3, 1.3]),
    _adjust(AdjustKind.brightness, values: {"contrast": 0.1}),
  ]),

  // ---- Screens -------------------------------------------------------------

  // Red, green and blue pulled apart and laid back over each other.
  _look("glitch", "Glitch", [
    _adjust(AdjustKind.channelMixer, values: {"rr": 0, "bb": 0}),
    _copy(blend: LayerBlend.screen, shift: const [-0.012, 0, 1, 1]),
    _adjust(AdjustKind.channelMixer, values: {"gg": 0, "bb": 0}, clip: true),
    _copy(blend: LayerBlend.screen, shift: const [0.012, 0.004, 1, 1]),
    _adjust(AdjustKind.channelMixer, values: {"rr": 0, "gg": 0}, clip: true),
    _texture(TextureKind.lines, values: {"spacing": 4}, opacity: 0.35),
  ]),
  _look("vhs", "VHS", [
    _adjust(AdjustKind.vibrance, values: {"saturation": 0.25}),
    _adjust(AdjustKind.noise, values: {"amount": 0.12, "colourful": 0.6}),
    _texture(TextureKind.lines, values: {"spacing": 3}, opacity: 0.4),
    _curve(const [Offset(0, 0.06), Offset(1, 0.94)]),
  ], baseEffects: [
    const LayerEffect(kind: EffectKind.fringe).withValue("distance", 5),
    _blur(1.5),
  ]),
  _look("pixel-art", "Pixel art", [
    _adjust(AdjustKind.pixelate, values: {"cell": 14}),
    _adjust(AdjustKind.posterise, values: {"levels": 6}),
  ]),

  // ---- Drawn and printed ---------------------------------------------------

  _look("comic", "Comic", [
    _adjust(AdjustKind.posterise, values: {"levels": 5}),
    _adjust(AdjustKind.vibrance, values: {"vibrance": 0.5}),
    _copy(blend: LayerBlend.multiply),
    _adjust(AdjustKind.findEdges,
        values: {"strength": 2.6, "colour": 0, "width": 1.5}, clip: true),
    _texture(TextureKind.halftone, values: {"cell": 6}, opacity: 0.35),
  ]),
  _look("pencil", "Pencil sketch", [
    _adjust(AdjustKind.blackWhite),
    _adjust(AdjustKind.findEdges, values: {"strength": 1.4, "colour": 0}),
    _adjust(AdjustKind.levels, values: {"inBlack": 0.25}),
    _texture(TextureKind.paper, values: {"amount": 0.6}),
  ]),
  _look("watercolour", "Watercolour", [
    _adjust(AdjustKind.oilPaint, values: {"radius": 22}),
    _adjust(AdjustKind.vibrance, values: {"vibrance": 0.35}),
    _curve(const [Offset(0, 0.1), Offset(0.5, 0.6), Offset(1, 1)]),
    _copy(blend: LayerBlend.multiply, opacity: 0.55),
    _adjust(AdjustKind.findEdges,
        values: {"colour": 1, "strength": 1.6}, clip: true),
    _texture(TextureKind.paper, values: {"amount": 0.7}),
  ]),
  _look("oil-painting", "Oil painting", [
    _adjust(AdjustKind.oilPaint, values: {"radius": 26}),
    _adjust(AdjustKind.emboss,
        values: {"amount": 1.4, "colour": 1, "height": 2}, opacity: 0.55),
    _adjust(AdjustKind.vibrance, values: {"vibrance": 0.25}),
  ]),
  _look("pop-art", "Pop art", [
    _adjust(AdjustKind.blackWhite),
    _adjust(AdjustKind.posterise, values: {"levels": 4}),
    _adjust(AdjustKind.gradientMap,
        colours: _ramp(const [
          Color(0xFF15124A),
          Color(0xFFE6197D),
          Color(0xFF16C2D5),
          Color(0xFFFFE14D),
        ])),
  ]),
];
