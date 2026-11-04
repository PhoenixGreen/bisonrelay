import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/pitch.dart';
import 'package:flutter/material.dart';

// builtin_presets.dart is the canvases the Presets tab starts you from.
//
// A preset is a whole document copied into the editor with no link back, so
// no saved canvas depends on one. Each shows a different kind of canvas (a
// still design, data, a diagram).

/// CanvasPreset is one starting point.
class CanvasPreset {
  /// id is stable: a saved "last used preset" refers to it, whatever the
  /// label.
  final String id;
  final String label;
  final String description;
  final IconData icon;

  /// build makes a fresh document. A function rather than a value, so each
  /// canvas started from it gets its own element ids.
  final CanvasDocument Function() build;

  const CanvasPreset({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.build,
  });
}

/// builtinPresets is the list, in the order the tab shows them, emptiest
/// first.
final List<CanvasPreset> builtinPresets = [
  CanvasPreset(
    id: "empty",
    label: "Empty canvas",
    description: "A plain background and nothing on it",
    icon: Icons.crop_landscape_outlined,
    build: emptyCanvas,
  ),
  CanvasPreset(
    id: "banner",
    label: "Banner",
    description: "A generated background with a title over it",
    icon: Icons.title_outlined,
    build: bannerCanvas,
  ),
  CanvasPreset(
    id: "chart",
    label: "Bar chart",
    description: "Five bars, axis labels and a grid",
    icon: Icons.bar_chart_outlined,
    build: chartCanvas,
  ),
  CanvasPreset(
    id: "football",
    label: "Football pitch",
    description: "A full pitch with two elevens in a 4-4-2",
    icon: Icons.sports_soccer_outlined,
    build: footballCanvas,
  ),
];

CanvasPreset? presetById(String id) {
  for (var p in builtinPresets) {
    if (p.id == id) return p;
  }
  return null;
}

/// emptyCanvas is a document with a background and nothing else.
CanvasDocument emptyCanvas() => const CanvasDocument(
      title: "Untitled canvas",
      background: CanvasBackground(
        spec: ProceduralSpec(
          style: ProceduralStyle.plain,
          background: Color(0xFF11161D),
          gradient: GradientSpec(to: Color(0xFF1B2530), angle: 210),
          vignette: 0.18,
        ),
      ),
    );

/// bannerCanvas is a generated background with a title centred over it.
CanvasDocument bannerCanvas() {
  const size = CanvasSize(ratio: CanvasRatio.wide, width: 1600);
  var w = size.width.toDouble(), h = size.height.toDouble();

  return CanvasDocument(
    title: "Banner",
    size: size,
    background: const CanvasBackground(
      spec: ProceduralSpec(
        style: ProceduralStyle.flowWaves,
        seed: 7,
        background: Color(0xFF060A10),
        foreground: Color(0xFF2FA6FF),
        accent: Color(0xFF9BE8FF),
        density: 0.55,
        scale: 0.06,
        intensity: 0.85,
        variation: 0.55,
        vignette: 0.4,
      ),
    ),
    elements: [
      TextElement(
        ElementBase(
          id: newElementId(),
          name: "Title",
          x: w * 0.1,
          y: h * 0.34,
          width: w * 0.8,
          height: h * 0.2,
        ),
        text: "Your title here",
        textSpec: const TextSpec(
          fontSize: 96,
          weight: 800,
          letterSpacing: -2,
          align: TextAlignSpec.center,
          color: Color(0xFFFFFFFF),
          shadowBlur: 26,
          shadowColor: Color(0xCC000814),
        ),
        // Grown to the box, so it works as a wide banner or a square.
        autoSize: true,
      ),
      TextElement(
        ElementBase(
          id: newElementId(),
          name: "Subtitle",
          x: w * 0.15,
          y: h * 0.56,
          width: w * 0.7,
          height: h * 0.08,
        ),
        text: "A line of supporting text",
        textSpec: const TextSpec(
          fontSize: 32,
          weight: 400,
          letterSpacing: 3,
          textCase: TextCase.upper,
          align: TextAlignSpec.center,
          color: Color(0xCCBFE6FF),
        ),
      ),
    ],
  );
}

/// chartCanvas is a bar chart on a quiet background.
CanvasDocument chartCanvas() {
  const size = CanvasSize(ratio: CanvasRatio.wide, width: 1400);
  var w = size.width.toDouble(), h = size.height.toDouble();

  return CanvasDocument(
    title: "Chart",
    size: size,
    background: const CanvasBackground(
      spec: ProceduralSpec(
        style: ProceduralStyle.dotGrid,
        seed: 3,
        background: Color(0xFF0D1219),
        foreground: Color(0xFF25415E),
        accent: Color(0xFF3D7EFF),
        density: 0.35,
        scale: 0.02,
        intensity: 0.5,
        variation: 0.2,
        vignette: 0.3,
      ),
    ),
    elements: [
      ChartElement(
        ElementBase(
          id: newElementId(),
          name: "Bar chart",
          x: w * 0.06,
          y: h * 0.07,
          width: w * 0.88,
          height: h * 0.86,
        ),
        type: ChartType.bar,
        title: "Messages sent per week",
        xAxisLabel: "Week",
        yAxisLabel: "Messages",
        showGrid: true,
        showAxes: true,
        showValues: true,
        barRadius: 6,
        data: const ChartData(
          categories: ["Week 1", "Week 2", "Week 3", "Week 4", "Week 5"],
          series: [
            ChartSeries(
              name: "Messages",
              color: Color(0xFF3D7EFF),
              values: [120, 185, 143, 231, 198],
            ),
          ],
        ),
      ),
    ],
  );
}

/// footballCanvas is a marked pitch with two elevens on it.
CanvasDocument footballCanvas() {
  const size = CanvasSize(ratio: CanvasRatio.wide, width: 1600);
  var rect = size.rect;

  const background = CanvasBackground(
    spec: ProceduralSpec(
      style: ProceduralStyle.pitch,
      sport: PitchSport.football,
      seed: 2,
      background: Color(0xFF2E6B2A),
      foreground: Color(0xFFF2F7F2),
      accent: Color(0xFFFFF6D8),
      density: 0.5,
      intensity: 0.85,
      variation: 0.55,
      vignette: 0.3,
    ),
  );

  // The painter's own mapping, so players placed in metres land on the
  // lines it draws.
  var metrics = pitchRect(rect, PitchSport.football);
  var diameter = metrics.m(3.2);

  // Each side is one element covering its own half, the box a formation is
  // laid out against (see TeamFormation), so all are in the same metres.
  var halfWidth = metrics.area.width / 2;
  var squadNames = [
    "GK",
    "RB",
    "CB",
    "CB",
    "LB",
    "RM",
    "CM",
    "CM",
    "LM",
    "ST",
    "ST",
  ];

  TeamElement team({
    required String name,
    required double left,
    required bool mirrored,
    required Color kit,
    required Color keeper,
    required LabelPosition namePosition,
  }) =>
      TeamElement(
        ElementBase(
          id: newElementId(),
          name: name,
          x: left,
          y: metrics.area.top,
          width: halfWidth,
          height: metrics.area.height,
        ),
        playerColor: kit,
        keeperColor: keeper,
        outlineColor: const Color(0xFFFFFFFF),
        dotWidth: diameter,
        dotHeight: diameter,
        ringWidth: diameter * 0.07,
        labelSpec: TextSpec(
          fontSize: diameter * 0.46,
          weight: 700,
          color: const Color(0xFFFFFFFF),
          // Outlined rather than shadowed, to read over both light and dark
          // mowing stripes.
          outlineWidth: diameter * 0.035,
          outlineColor: const Color(0xCC0A1A0A),
        ),
        namePosition: namePosition,
        nameGap: diameter * 0.18,
      )
          .withFormation(TeamFormation.f442, mirror: mirrored)
          // Linked to the pitch, so they follow its camera.
          .linkedTo(teamLinkBackground,
              pitch: PitchSport.football, reference: metrics.scale, area: rect);

  /// named puts the position abbreviations on a freshly laid-out side.
  TeamElement named(TeamElement side) => side.copyWith(players: [
        for (var i = 0; i < side.players.length; i++)
          side.players[i]
              .copyWith(name: i < squadNames.length ? squadNames[i] : ""),
      ]);

  // Home attacks left to right; away is the same formation mirrored.
  var elements = <CanvasElement>[
    named(team(
      name: "Home",
      left: metrics.area.left,
      mirrored: false,
      kit: const Color(0xFFD32F2F),
      keeper: const Color(0xFFF2C230),
      namePosition: LabelPosition.below,
    )),
    named(team(
      name: "Away",
      left: metrics.area.left + halfWidth,
      mirrored: true,
      kit: const Color(0xFF1565C0),
      keeper: const Color(0xFF66E08A),
      namePosition: LabelPosition.above,
    )),
  ];

  return CanvasDocument(
    title: "Football pitch",
    size: size,
    background: background,
    elements: elements,
    // Room to animate: a tactics diagram nearly always becomes an animation.
    frames: 24,
  );
}
