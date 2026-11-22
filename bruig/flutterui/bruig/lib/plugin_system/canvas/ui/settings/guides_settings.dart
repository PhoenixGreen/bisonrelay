import 'package:bruig/plugin_system/canvas/ui/timeline/canvas_strip.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_rulers.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_align.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';

// guides_settings.dart is grid, guides, rulers and snapping as a panel off
// the settings bar (set once, so not on it), opening as a line under the
// band, which moves the canvas down rather than cover its top.

/// _guidesSettings is the whole panel: five groups, each foldable
/// (remembered across restarts), so unused ones do not make it scroll.
List<Widget> _guidesSettings(CanvasController controller) => [
      // Rulers first: they are the page's edge, met in the canvas's order.
      _rulersGroup(controller),
      _gridGroup(controller),
      _guidesGroup(controller),
      _snappingGroup(controller),
      _alignGroup(controller),
    ];

/// _set puts [next] in as one change.
void _set(CanvasController controller, CanvasGuides next) =>
    controller.apply(controller.document.copyWith(guides: next));

/// _slide puts [next] in as a step of a number dragged or typed: one
/// change, closed when it is let go.
void _slide(CanvasController controller, CanvasGuides next) {
  controller.beginInteraction();
  controller.apply(controller.document.copyWith(guides: next), transient: true);
}

/// _rulersGroup is which edges carry a ruler, and whether they show. They
/// are the person's, not the canvas's (CanvasController.rulers): setting
/// them is no edit of the canvas.
Widget _rulersGroup(CanvasController controller) {
  var rulers = controller.rulers;
  void set(CanvasRulers next) => controller.rulers = next;
  return CanvasFoldingGroup(
      label: "Rulers",
      remember: "guidesRulers",
      children: [
        for (var (label, on, apply)
            in <(String, bool, CanvasRulers Function(bool))>[
          ("Top", rulers.top, (v) => rulers.copyWith(top: v)),
          ("Left", rulers.left, (v) => rulers.copyWith(left: v)),
          ("Right", rulers.right, (v) => rulers.copyWith(right: v)),
          ("Bottom", rulers.bottom, (v) => rulers.copyWith(bottom: v)),
        ])
          CanvasToggle(
            key: ValueKey("guidesRuler$label"),
            label: label,
            value: on,
            onChanged: (v) => set(apply(v)),
          ),
        // Shown or hidden without forgetting which edges were asked for.
        CanvasToggle(
          key: const ValueKey("guidesShowRulers"),
          label: "Show",
          value: rulers.shown,
          onChanged: (v) => set(rulers.copyWith(shown: v)),
        ),
        const CanvasHint(
            "Rulers sit against the edges of the canvas and are numbered from "
            "its top-left corner, at the spacing the Grid group sets — every few of "
            "them "
            "when the canvas is small on screen. Drag out of one to put a guide "
            "down."),
      ]);
}

/// _gridGroup is the grid: shown or not, its spacing and its divisions.
Widget _gridGroup(CanvasController controller) {
  var guides = controller.document.guides;
  void set(CanvasGuides next) => _set(controller, next);
  void slide(CanvasGuides next) => _slide(controller, next);
  // "Every" sets grid and ruler spacing together, so ruler readings land on
  // grid lines. Named Grid alone so Rulers is not a caption twice.
  return CanvasFoldingGroup(label: "Grid", remember: "guidesGrid", children: [
    CanvasToggle(
      label: "Show a grid",
      value: guides.showGrid,
      onChanged: (v) => set(guides.copyWith(showGrid: v)),
    ),
    CanvasNumberField(
      label: "Every",
      value: guides.gridSize,
      min: CanvasGuides.minGridSize,
      max: CanvasGuides.maxGridSize,
      decimals: 0,
      width: 62,
      onChanged: (v) => slide(guides.copyWith(gridSize: v)),
      onCommit: controller.endInteraction,
    ),
    CanvasNumberField(
      label: "Divided by",
      value: guides.subdivisions.toDouble(),
      min: CanvasGuides.minSubdivisions.toDouble(),
      max: CanvasGuides.maxSubdivisions.toDouble(),
      decimals: 0,
      width: 62,
      onChanged: (v) => slide(guides.copyWith(subdivisions: v.round())),
      onCommit: controller.endInteraction,
    ),
    const CanvasHint(
        "Every sets the spacing for the grid and for the ruler's numbers "
        "together, so a figure on the ruler always has a line under it; "
        "dividing it draws fainter ones between them. Both can be snapped "
        "to, and neither is exported — a grid is for building the design, "
        "not part of it."),
  ]);
}

/// _guidesGroup is the guides: added, shown, locked and cleared.
Widget _guidesGroup(CanvasController controller) {
  var guides = controller.document.guides;
  void set(CanvasGuides next) => _set(controller, next);
  return CanvasFoldingGroup(
      label: "Guides",
      remember: "guidesGuides",
      children: [
        CanvasIconButton(
          icon: Icons.swap_horiz,
          tooltip: "Add a vertical guide down the middle",
          onPressed: () => set(guides.withGuide(CanvasGuide(
              axis: GuideAxis.vertical,
              at: controller.document.size.size.width / 2))),
        ),
        CanvasIconButton(
          icon: Icons.swap_vert,
          tooltip: "Add a horizontal guide across the middle",
          onPressed: () => set(guides.withGuide(CanvasGuide(
              axis: GuideAxis.horizontal,
              at: controller.document.size.size.height / 2))),
        ),
        CanvasToggle(
          label: "Show",
          value: guides.showGuides,
          onChanged: (v) => set(guides.copyWith(showGuides: v)),
        ),
        CanvasToggle(
          label: "Locked",
          value: guides.lockGuides,
          onChanged: (v) => set(guides.copyWith(lockGuides: v)),
        ),
        CanvasIconButton(
          icon: Icons.layers_clear_outlined,
          tooltip: guides.guides.isEmpty
              ? "There are no guides to clear"
              : "Remove every guide",
          onPressed: guides.guides.isEmpty
              ? null
              : () => set(guides.copyWith(guides: const [])),
        ),
        CanvasHint("A guide is dragged where you want it, and locking stops it "
            "moving by accident — which is the commonest thing to do to a line "
            "you are working against. "
            "${guides.guides.length} at the moment."),
      ]);
}

/// _snappingGroup is what snaps to what, how near, and the steps on a 3D
/// stage.
Widget _snappingGroup(CanvasController controller) {
  var guides = controller.document.guides;
  void set(CanvasGuides next) => _set(controller, next);
  void slide(CanvasGuides next) => _slide(controller, next);
  return CanvasFoldingGroup(
      label: "Snapping",
      remember: "guidesSnapping",
      children: [
        CanvasToggle(
          label: "Snap",
          value: guides.snap,
          onChanged: (v) => set(guides.copyWith(snap: v)),
        ),
        CanvasToggle(
          label: "Vertices",
          value: guides.snapTo.vertices,
          onChanged: (v) =>
              set(guides.copyWith(snapTo: guides.snapTo.copyWith(vertices: v))),
        ),
        // The same targets as the bar's snap menu. Other elements are the
        // lines that matter most: this heading over that picture, not a
        // grid's intervals.
        for (var target in SnapTarget.values)
          CanvasToggle(
            key: ValueKey("snapTo${target.name[0].toUpperCase()}"
                "${target.name.substring(1)}"),
            label: target.label,
            value: target.of(guides.snapTo),
            onChanged: (v) =>
                set(guides.copyWith(snapTo: target.set(guides.snapTo, v))),
          ),
        CanvasNumberField(
          label: "Within",
          value: guides.snapWithin,
          min: CanvasGuides.minSnapWithin,
          max: CanvasGuides.maxSnapWithin,
          decimals: 0,
          width: 56,
          suffix: "px",
          onChanged: (v) => slide(guides.copyWith(snapWithin: v)),
          onCommit: controller.endInteraction,
        ),
        // A 3D stage has no lines to land on: moves land on floor steps
        // and turn in steps. Its own switch, as it affects every move.
        CanvasToggle(
          key: const ValueKey("snapStage"),
          label: "Snap on a 3D stage",
          value: guides.stageSnap,
          onChanged: (v) => set(guides.copyWith(stageSnap: v)),
        ),
        CanvasNumberField(
          key: const ValueKey("snapStageStep"),
          label: "3D steps",
          value: guides.stageStep,
          min: CanvasGuides.minStageStep,
          max: CanvasGuides.maxStageStep,
          decimals: 2,
          width: 56,
          suffix: "m",
          onChanged: (v) => slide(guides.copyWith(stageStep: v)),
          onCommit: controller.endInteraction,
        ),
        CanvasNumberField(
          key: const ValueKey("snapStageTurn"),
          label: "3D turns",
          value: guides.stageTurn,
          min: CanvasGuides.minStageTurn,
          max: CanvasGuides.maxStageTurn,
          decimals: 0,
          width: 56,
          suffix: "°",
          onChanged: (v) => slide(guides.copyWith(stageTurn: v)),
          onCommit: controller.endInteraction,
        ),
        const CanvasHint(
            "How near, on screen, before it jumps — so it feels the same at "
            "every zoom. With Other elements on, the sides and middles of "
            "everything else on the canvas are lines too. The canvas's own edges and "
            "middle are always snapped to. Hold Alt while dragging to put "
            "something exactly where the grid does not want it. With Snap "
            "on a 3D stage, what is moved there lands on the 3D steps "
            "across the floor and turns by the 3D turns."),
      ]);
}

/// _alignGroup lines the chosen elements up with each other, or spreads
/// them evenly.
Widget _alignGroup(CanvasController controller) {
  // Aligning several things at once and exactly, which snapping (one
  // thing as it passes another) cannot.
  return CanvasFoldingGroup(label: "Align", remember: "guidesAlign", children: [
    for (var align in CanvasAlign.values)
      CanvasIconButton(
        key: ValueKey("align${align.name}"),
        icon: align.icon,
        tooltip: align.label,
        // Against the selection's own box, so one thing chosen is already
        // aligned.
        onPressed: controller.aligning < 2
            ? null
            : () => controller.alignSelected(align),
      ),
    // No line break: this group draws in a strip that scrolls sideways,
    // where an infinitely wide break brings the layout down.
    CanvasIconButton(
      key: const ValueKey("spreadAcross"),
      icon: Icons.horizontal_distribute,
      tooltip: "Even gaps across",
      onPressed: controller.aligning < 3
          ? null
          : () => controller.spreadSelected(true),
    ),
    CanvasIconButton(
      key: const ValueKey("spreadDown"),
      icon: Icons.vertical_distribute,
      tooltip: "Even gaps down",
      onPressed: controller.aligning < 3
          ? null
          : () => controller.spreadSelected(false),
    ),
    CanvasHint(controller.aligning < 2
        ? "Choose two or more elements to line them up with each other -- "
            "or, with a picture's layers open, two or more of its picture "
            "layers (Shift-click). Three or more to spread them evenly."
        : "Lined up against the box the chosen elements make between them, "
            "so the outermost ones stay where they are."),
  ]);
}

/// CanvasGuidesPanel is that panel, laid out like the canvas settings
/// beside it: one line, scrolling sideways, under the band.
class CanvasGuidesPanel extends StatefulWidget {
  final CanvasController controller;
  const CanvasGuidesPanel({required this.controller, super.key});

  @override
  State<CanvasGuidesPanel> createState() => _CanvasGuidesPanelState();
}

class _CanvasGuidesPanelState extends State<CanvasGuidesPanel> {
  CanvasController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => CanvasSettingsStrip(
        groups: (context) => _guidesSettings(controller),
      );
}
