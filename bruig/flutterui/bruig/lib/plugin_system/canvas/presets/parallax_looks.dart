import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/parallax_element.dart';

// parallax_looks.dart is the parallax scenery a background starts from:
// whole scenes, back to front, each layer's scroll a step faster than the
// one behind it so a pan reads as depth from the first frame.

class ParallaxLook {
  final String name;
  final List<ParallaxLayer> layers;
  const ParallaxLook(this.name, this.layers);

  /// scenery is this look as a parallax background's settings.
  ParallaxElement get scenery =>
      ParallaxElement(const ElementBase(id: ""), layers: layers);
}

const List<ParallaxLook> parallaxLooks = [
  ParallaxLook("Green hills", [
    ParallaxLayer(
        kind: SceneryKind.sky,
        color: Color(0xFF7FBCEB),
        color2: Color(0xFFE2F3FB),
        amount: 0.5,
        scrollX: 0,
        scrollY: 0,
        anchor: LayerAnchor.fill),
    ParallaxLayer(
        kind: SceneryKind.clouds,
        color: Color(0xFFFFFFFF),
        color2: Color(0xFFDCE7EF),
        amount: 0.4,
        scrollX: 0.08,
        scrollY: 0.05,
        autoX: -6,
        anchor: LayerAnchor.fill),
    ParallaxLayer(
        kind: SceneryKind.mountains,
        color: Color(0xFF8CA7BF),
        color2: Color(0xFFDDE8F0),
        height: 0.5,
        amount: 0.55,
        seed: 3,
        scrollX: 0.15),
    ParallaxLayer(
        kind: SceneryKind.hills,
        color: Color(0xFF7DAE63),
        color2: Color(0xFFA9CF8E),
        height: 0.34,
        seed: 5,
        scrollX: 0.4),
    ParallaxLayer(
        kind: SceneryKind.hills,
        color: Color(0xFF4F8A3C),
        color2: Color(0xFF6EA552),
        height: 0.22,
        amount: 0.3,
        seed: 8,
        scrollX: 0.7),
    ParallaxLayer(
        kind: SceneryKind.ground,
        color: Color(0xFF3A6A2C),
        color2: Color(0xFF5A8F44),
        height: 0.09,
        scrollX: 1,
        scrollY: 1),
  ]),
  ParallaxLook("Mountain dusk", [
    ParallaxLayer(
        kind: SceneryKind.sky,
        color: Color(0xFF2A2B5E),
        color2: Color(0xFFF4A06E),
        amount: 0.7,
        seed: 2,
        scrollX: 0,
        scrollY: 0,
        anchor: LayerAnchor.fill),
    ParallaxLayer(
        kind: SceneryKind.mountains,
        color: Color(0xFF5B4A7A),
        color2: Color(0xFF9A7FA8),
        height: 0.58,
        amount: 0.7,
        seed: 11,
        scrollX: 0.12),
    ParallaxLayer(
        kind: SceneryKind.mountains,
        color: Color(0xFF3B3157),
        color2: Color(0xFF5D4E7A),
        height: 0.42,
        amount: 0.6,
        seed: 4,
        scrollX: 0.3),
    ParallaxLayer(
        kind: SceneryKind.trees,
        color: Color(0xFF221B33),
        color2: Color(0xFF221B33),
        height: 0.24,
        amount: 0.6,
        scrollX: 0.65),
    ParallaxLayer(
        kind: SceneryKind.ground,
        color: Color(0xFF130F1D),
        color2: Color(0xFF1E1830),
        height: 0.07,
        scrollX: 1,
        scrollY: 1),
  ]),
  ParallaxLook("Night city", [
    ParallaxLayer(
        kind: SceneryKind.sky,
        color: Color(0xFF070B26),
        color2: Color(0xFF2B2F6E),
        amount: 0.25,
        seed: 7,
        scrollX: 0,
        scrollY: 0,
        anchor: LayerAnchor.fill),
    ParallaxLayer(
        kind: SceneryKind.city,
        color: Color(0xFF242A57),
        color2: Color(0xFF6D74B8),
        height: 0.55,
        amount: 0.75,
        seed: 2,
        scrollX: 0.2),
    ParallaxLayer(
        kind: SceneryKind.city,
        color: Color(0xFF12152E),
        color2: Color(0xFFFFD36B),
        height: 0.38,
        amount: 0.45,
        seed: 9,
        scrollX: 0.5),
    ParallaxLayer(
        kind: SceneryKind.ground,
        color: Color(0xFF07080F),
        color2: Color(0xFF1A1C33),
        height: 0.05,
        amount: 0,
        scrollX: 1,
        scrollY: 1),
  ]),
  ParallaxLook("Pine forest", [
    ParallaxLayer(
        kind: SceneryKind.sky,
        color: Color(0xFFB9D4DE),
        color2: Color(0xFFEFF5F1),
        amount: 0,
        scrollX: 0,
        scrollY: 0,
        anchor: LayerAnchor.fill),
    ParallaxLayer(
        kind: SceneryKind.mountains,
        color: Color(0xFF9DB6B4),
        color2: Color(0xFFD5E2E0),
        height: 0.42,
        amount: 0.45,
        seed: 6,
        scrollX: 0.12),
    ParallaxLayer(
        kind: SceneryKind.trees,
        color: Color(0xFF6B9884),
        color2: Color(0xFF6B9884),
        height: 0.38,
        amount: 0.7,
        seed: 1,
        scrollX: 0.3),
    ParallaxLayer(
        kind: SceneryKind.trees,
        color: Color(0xFF34634F),
        color2: Color(0xFF34634F),
        height: 0.3,
        amount: 0.5,
        seed: 2,
        scrollX: 0.55),
    ParallaxLayer(
        kind: SceneryKind.trees,
        color: Color(0xFF173A2C),
        color2: Color(0xFF173A2C),
        height: 0.26,
        amount: 0.3,
        seed: 3,
        scrollX: 0.85),
    ParallaxLayer(
        kind: SceneryKind.ground,
        color: Color(0xFF10261C),
        color2: Color(0xFF1E3D2E),
        height: 0.06,
        scrollX: 1,
        scrollY: 1),
  ]),
  ParallaxLook("Desert", [
    ParallaxLayer(
        kind: SceneryKind.sky,
        color: Color(0xFFF2B866),
        color2: Color(0xFFFCE9C6),
        amount: 0.6,
        seed: 3,
        scrollX: 0,
        scrollY: 0,
        anchor: LayerAnchor.fill),
    ParallaxLayer(
        kind: SceneryKind.hills,
        color: Color(0xFFC9845A),
        color2: Color(0xFFE6B48E),
        height: 0.32,
        amount: 0.25,
        seed: 12,
        scrollX: 0.15),
    ParallaxLayer(
        kind: SceneryKind.hills,
        color: Color(0xFFDDA265),
        color2: Color(0xFFEEC38C),
        height: 0.2,
        amount: 0.2,
        seed: 4,
        scrollX: 0.45),
    ParallaxLayer(
        kind: SceneryKind.ground,
        color: Color(0xFFC0844A),
        color2: Color(0xFFDDA265),
        height: 0.09,
        amount: 0.3,
        scrollX: 1,
        scrollY: 1),
  ]),
];

/// parallaxLayerStart is a new layer of [kind]: something to see at once,
/// to be changed from there.
ParallaxLayer parallaxLayerStart(SceneryKind kind) => switch (kind) {
      SceneryKind.sky => const ParallaxLayer(
          kind: SceneryKind.sky,
          color: Color(0xFF7FBCEB),
          color2: Color(0xFFE2F3FB),
          scrollX: 0,
          scrollY: 0,
          anchor: LayerAnchor.fill),
      SceneryKind.clouds => const ParallaxLayer(
          kind: SceneryKind.clouds,
          color: Color(0xFFFFFFFF),
          color2: Color(0xFFDCE7EF),
          amount: 0.4,
          scrollX: 0.1,
          scrollY: 0.05,
          autoX: -6,
          anchor: LayerAnchor.fill),
      SceneryKind.mountains => const ParallaxLayer(
          kind: SceneryKind.mountains,
          color: Color(0xFF8CA7BF),
          color2: Color(0xFFDDE8F0),
          height: 0.5,
          scrollX: 0.2),
      SceneryKind.trees => const ParallaxLayer(
          kind: SceneryKind.trees,
          color: Color(0xFF34634F),
          color2: Color(0xFF34634F),
          height: 0.3,
          scrollX: 0.6),
      SceneryKind.city => const ParallaxLayer(
          kind: SceneryKind.city,
          color: Color(0xFF242A57),
          color2: Color(0xFFFFD36B),
          height: 0.45,
          scrollX: 0.4),
      SceneryKind.ground => const ParallaxLayer(
          kind: SceneryKind.ground,
          color: Color(0xFF3A6A2C),
          color2: Color(0xFF5A8F44),
          height: 0.09,
          scrollX: 1,
          scrollY: 1),
      SceneryKind.picture => const ParallaxLayer(
          kind: SceneryKind.picture, scrollX: 0.5, anchor: LayerAnchor.bottom),
      SceneryKind.pattern => const ParallaxLayer(
          kind: SceneryKind.pattern,
          scrollX: 0.3,
          scrollY: 0.3,
          anchor: LayerAnchor.fill),
      SceneryKind.hills => const ParallaxLayer(),
    };
