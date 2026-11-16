import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:flutter/painting.dart';

// data_styles.dart is the six styles a table or chart can be given at once
// (Ken, 2026-11-17: they replace the Looks in the Data Studio's Table and
// Charts tabs; prototype v7). Each is a family of choices from the
// research on infographics, explainer video and data journalism: its
// ground and inks, one accent, a palette, its typefaces, how round its
// shapes are. Giving one keeps the data and the words; a preset (layout,
// labels, emphasis) is separate, so the two can be mixed freely.
//
// Faces are ones the app bundles or every desktop has (see canvasFonts):
// Georgia for a newspaper's headline, Oswald for a broadcast caption.

class DataStyle {
  final String name, note;

  /// ground is its page: the panel behind a chart, a table's cells.
  final Color ground;
  final Color ink, dim, grid, axis, accent, muted;
  final List<Color> palette;
  final Color rise, fall;
  final String headFont, bodyFont;
  final int headWeight;
  final double round;

  /// headFill and headInk are a table's header row.
  final Color headFill, headInk;

  const DataStyle(this.name, this.note,
      {required this.ground,
      required this.ink,
      required this.dim,
      required this.grid,
      required this.axis,
      required this.accent,
      required this.muted,
      required this.palette,
      required this.rise,
      required this.fall,
      required this.headFont,
      required this.bodyFont,
      required this.headWeight,
      required this.round,
      required this.headFill,
      required this.headInk});

  bool get dark => ground.computeLuminance() < 0.25;
}

const dataStyles = [
  DataStyle(
      "Editorial", "Newspaper analysis: hairlines, one accent, direct labels",
      ground: Color(0xFFFBF6EF),
      ink: Color(0xFF1B1B1B),
      dim: Color(0xFF6C665F),
      grid: Color(0xFFDDD5C9),
      axis: Color(0xFF1B1B1B),
      accent: Color(0xFFC8102E),
      muted: Color(0xFFCDC4B8),
      palette: [
        Color(0xFF0F5499), Color(0xFFC8102E), Color(0xFFE8A33D), //
        Color(0xFF5F8D3B), Color(0xFF7C5CA8), Color(0xFF2C9CA6),
      ],
      rise: Color(0xFF0F5499),
      fall: Color(0xFFC8102E),
      headFont: "Georgia",
      bodyFont: "Inter",
      headWeight: 700,
      round: 0,
      headFill: Color(0xFFFBF6EF),
      headInk: Color(0xFF6C665F)),
  DataStyle("Broadcast",
      "Dark explainer and sports TV: big numbers, saturated accents",
      ground: Color(0xFF0B1022),
      ink: Color(0xFFF4F6FF),
      dim: Color(0xFF8D96BB),
      grid: Color(0x17FFFFFF),
      axis: Color(0xFF3A4466),
      accent: Color(0xFFFFD21F),
      muted: Color(0xFF2B3456),
      palette: [
        Color(0xFF2FD3FF), Color(0xFFFFD21F), Color(0xFFFF4F8B), //
        Color(0xFF7CFF6B), Color(0xFFA78BFA), Color(0xFFFF9F43),
      ],
      rise: Color(0xFF7CFF6B),
      fall: Color(0xFFFF4F8B),
      headFont: "Oswald",
      bodyFont: "Inter",
      headWeight: 700,
      round: 4,
      headFill: Color(0xFF121A33),
      headInk: Color(0xFFF4F6FF)),
  DataStyle(
      "Poster", "Flat infographic: every number printed, thick shapes, no grid",
      ground: Color(0xFFEEF3F8),
      ink: Color(0xFF16243A),
      dim: Color(0xFF5E6B80),
      grid: Color(0x1416243A),
      axis: Color(0xFF16243A),
      accent: Color(0xFFFF5A36),
      muted: Color(0xFFCFD8E3),
      palette: [
        Color(0xFF2667FF), Color(0xFFFF5A36), Color(0xFF18C29C), //
        Color(0xFFFFBE0B), Color(0xFF8F5CFF), Color(0xFFFF8FAB),
      ],
      rise: Color(0xFF18C29C),
      fall: Color(0xFFFF5A36),
      headFont: "Inter",
      bodyFont: "Inter",
      headWeight: 800,
      round: 8,
      headFill: Color(0xFF2667FF),
      headInk: Color(0xFFFFFFFF)),
  DataStyle(
      "Minimal", "Analytical, after Tufte and Few: greys, one accent, dense",
      ground: Color(0xFFFFFFFF),
      ink: Color(0xFF222222),
      dim: Color(0xFF777777),
      grid: Color(0xFFECECEC),
      axis: Color(0xFF999999),
      accent: Color(0xFFD1495B),
      muted: Color(0xFFC9C9C9),
      palette: [
        Color(0xFF444444), Color(0xFFD1495B), Color(0xFF8A8A8A), //
        Color(0xFFB8B8B8), Color(0xFF2E6F95), Color(0xFF6A6A6A),
      ],
      rise: Color(0xFF444444),
      fall: Color(0xFFD1495B),
      headFont: "Georgia",
      bodyFont: "Inter",
      headWeight: 600,
      round: 0,
      headFill: Color(0xFFFFFFFF),
      headInk: Color(0xFF777777)),
  DataStyle(
      "Playful", "Rounded, educational explainer: chunky, saturated, friendly",
      ground: Color(0xFF1D1846),
      ink: Color(0xFFFFF8EC),
      dim: Color(0xFFB4A9E6),
      grid: Color(0x12FFFFFF),
      axis: Color(0xFF5B4FA8),
      accent: Color(0xFFFFB703),
      muted: Color(0xFF3D3478),
      palette: [
        Color(0xFFFFB703), Color(0xFFFB5607), Color(0xFF3DDBD9), //
        Color(0xFFFF006E), Color(0xFF8AC926), Color(0xFF9B5DE5),
      ],
      rise: Color(0xFF8AC926),
      fall: Color(0xFFFB5607),
      headFont: "Inter",
      bodyFont: "Inter",
      headWeight: 800,
      round: 12,
      headFill: Color(0xFF272058),
      headInk: Color(0xFFFFB703)),
  DataStyle("Report", "Corporate and finance: actuals dark, variance coloured",
      ground: Color(0xFFFFFFFF),
      ink: Color(0xFF1F2933),
      dim: Color(0xFF66788A),
      grid: Color(0xFFE1E6EB),
      axis: Color(0xFF1F2933),
      accent: Color(0xFF2F6FDE),
      muted: Color(0xFFC3CCD5),
      palette: [
        Color(0xFF334155), Color(0xFF2F6FDE), Color(0xFF94A3B8), //
        Color(0xFF16A34A), Color(0xFFDC2626), Color(0xFFCBD5E1),
      ],
      rise: Color(0xFF16A34A),
      fall: Color(0xFFDC2626),
      headFont: "Inter",
      bodyFont: "Inter",
      headWeight: 700,
      round: 2,
      headFill: Color(0xFFF1F4F7),
      headInk: Color(0xFF1F2933)),
];

DataStyle? dataStyleNamed(String name) {
  for (var s in dataStyles) {
    if (s.name == name) return s;
  }
  return null;
}

/// chartInStyle is [e] in style [s]: its words, grid and axes, its series
/// and slices from the palette, a highlight in the accent, its corners,
/// and -- unless [panel] is false -- its own ground behind it.
ChartElement chartInStyle(ChartElement e, DataStyle s, {bool panel = true}) {
  TextSpec face(TextSpec t, Color colour, String font, [int? weight]) =>
      t.copyWith(color: colour, fontFamily: font, weight: weight);
  return e.copyWith(
    style: s.name,
    panel: panel ? s.ground : const Color(0x00000000),
    titleSpec: face(e.titleSpec, s.ink, s.headFont, s.headWeight),
    labelSpec: face(e.labelSpec, s.dim, s.bodyFont),
    valueSpec: face(e.valueSpec, s.ink, s.bodyFont),
    descriptionSpec: face(e.descriptionText, s.dim, s.bodyFont),
    axisSpec: e.axisSpec == null ? null : face(e.axisSpec!, s.dim, s.bodyFont),
    gridColor: s.grid,
    axisColor: s.axis,
    riseColor: s.rise,
    fallColor: s.fall,
    pointColor: s.palette.first,
    // A colour per part only where the parts are the chart (a pie, a
    // waffle, a treemap); bars and lines keep one colour a series.
    sliceColors: e.type.isCircular ? s.palette : const [],
    barRadius: s.round,
    highlights: [
      for (var h in e.highlights) h.copyWith(colour: s.accent),
    ],
    data: e.data.copyWith(series: [
      for (var (i, x) in e.data.series.indexed)
        x.copyWith(color: s.palette[i % s.palette.length]),
    ]),
  );
}

/// tableInStyle is [t] in style [s]: its header and cells, rules, stripes,
/// corners and type.
TableElement tableInStyle(TableElement t, DataStyle s) => t.copyWith(
      style: s.name,
      flatHeader: true,
      flatCells: true,
      headerFill: s.headFill,
      cellFill: s.ground,
      headerSpec: t.headerSpec
          .copyWith(color: s.headInk, fontFamily: s.headFont, weight: 700),
      cellSpec: t.cellSpec.copyWith(color: s.ink, fontFamily: s.bodyFont),
      gridColor: s.dark ? s.axis : s.grid,
      zebraFill: s.dark
          ? s.ink.withValues(alpha: 0.05)
          : s.axis.withValues(alpha: 0.05),
      cornerRadius: s.round,
    );
