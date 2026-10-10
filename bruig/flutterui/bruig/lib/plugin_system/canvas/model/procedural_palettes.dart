import 'dart:ui';

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';

// procedural_palettes.dart is sets of colours a background can be given in
// one go.
//
// Three colours that have to agree with each other is three pickers and a
// good eye, and the commonest way a generated background goes wrong is that
// they do not: the default green on near-black was every style's colours,
// and twenty styles in the one pair of colours look like one style. A
// palette is the base, its fade, the main colour and the accent chosen
// together.

/// BackgroundPalette is a base colour, what it fades to, and the pattern's
/// two colours.
class BackgroundPalette {
  final String name;
  final Color base;

  /// baseTo is what the base fades to, top to bottom, or null for a flat
  /// one.
  final Color? baseTo;
  final Color main;
  final Color accent;

  const BackgroundPalette(this.name, this.base, this.main, this.accent,
      {this.baseTo});

  /// colours is the four in order, for drawing a swatch of it.
  List<Color> get colours => [base, if (baseTo != null) baseTo!, main, accent];

  /// on is [spec] in these colours, and nothing else about it changed.
  ProceduralSpec on(ProceduralSpec spec) => spec.copyWith(
        background: base,
        gradient: baseTo == null ? null : GradientSpec(to: baseTo!),
        flatBackground: baseTo == null,
        foreground: main,
        accent: accent,
        flatForeground: true,
        flatAccent: true,
      );

  /// matches is whether [spec] is in these colours already.
  bool matches(ProceduralSpec spec) =>
      spec.background == base &&
      spec.foreground == main &&
      spec.accent == accent &&
      spec.gradient?.to == baseTo;
}

/// backgroundPalettes is every palette offered, darkest first.
const List<BackgroundPalette> backgroundPalettes = [
  BackgroundPalette(
      "Decred", Color(0xFF091440), Color(0xFF2ED6A1), Color(0xFF2970FF),
      baseTo: Color(0xFF041029)),
  BackgroundPalette(
      "Matrix", Color(0xFF020A05), Color(0xFF1FD15E), Color(0xFFCCFFDD)),
  BackgroundPalette(
      "Neon", Color(0xFF0D0221), Color(0xFFFF2A6D), Color(0xFF05D9E8),
      baseTo: Color(0xFF1B0638)),
  BackgroundPalette(
      "Synthwave", Color(0xFF120458), Color(0xFFFF00A0), Color(0xFFFFD319),
      baseTo: Color(0xFF2D0B5A)),
  BackgroundPalette(
      "Midnight", Color(0xFF0B1026), Color(0xFF6C8CFF), Color(0xFFE8ECFF),
      baseTo: Color(0xFF151B3D)),
  BackgroundPalette(
      "Ocean", Color(0xFF02223A), Color(0xFF1FB5C9), Color(0xFFB8F3FF),
      baseTo: Color(0xFF04394F)),
  BackgroundPalette(
      "Forest", Color(0xFF0E1F17), Color(0xFF5FA36A), Color(0xFFE3D58C),
      baseTo: Color(0xFF173126)),
  BackgroundPalette(
      "Ember", Color(0xFF140805), Color(0xFFFF5A1F), Color(0xFFFFD166),
      baseTo: Color(0xFF2B0E06)),
  BackgroundPalette(
      "Gold", Color(0xFF15120C), Color(0xFFC9A54A), Color(0xFFFFF1C1)),
  BackgroundPalette(
      "Graphite", Color(0xFF16181C), Color(0xFF6B7380), Color(0xFFE6E9EE),
      baseTo: Color(0xFF22262C)),
  BackgroundPalette(
      "Mono", Color(0xFF000000), Color(0xFFFFFFFF), Color(0xFF9A9A9A)),
  BackgroundPalette(
      "Sunset", Color(0xFF2A1240), Color(0xFFFF7A59), Color(0xFFFFC25C),
      baseTo: Color(0xFFB2405A)),
  BackgroundPalette(
      "Aurora", Color(0xFF061423), Color(0xFF3CF2B0), Color(0xFFB57BFF),
      baseTo: Color(0xFF0E2A3A)),
  BackgroundPalette(
      "Blueprint", Color(0xFF0F3D7A), Color(0xFFBFD9FF), Color(0xFFFFFFFF),
      baseTo: Color(0xFF0A2E5E)),
  BackgroundPalette(
      "Pastel", Color(0xFFF7F1FF), Color(0xFFB8A4F4), Color(0xFFFFB5C8),
      baseTo: Color(0xFFE8F6FF)),
  BackgroundPalette(
      "Paper", Color(0xFFF4EFE4), Color(0xFF2B2B2B), Color(0xFFC0392B)),
  BackgroundPalette(
      "Comic", Color(0xFFFFE14D), Color(0xFFE6262E), Color(0xFF111111)),
  BackgroundPalette(
      "Snow", Color(0xFFFFFFFF), Color(0xFF9DB4CC), Color(0xFF2D6CDF),
      baseTo: Color(0xFFE9EFF6)),
];

/// paletteNamed is the palette called [name], or null.
BackgroundPalette? paletteNamed(String name) {
  for (var p in backgroundPalettes) {
    if (p.name == name) return p;
  }
  return null;
}
