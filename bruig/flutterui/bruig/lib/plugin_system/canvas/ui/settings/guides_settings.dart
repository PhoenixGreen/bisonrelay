import 'package:bruig/plugin_system/canvas/ui/timeline/canvas_strip.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';

// guides_settings.dart is grid, guides, rulers and snapping as a panel off
// the settings bar (set once, so not on it), opening over the canvas so the
// design and zoom never move.

/// canvasGuidesSettings is the whole panel: five groups, each foldable
/// (remembered across restarts), so unused ones do not make it scroll.
List<Widget> canvasGuidesSettings(CanvasController controller) {
  var guides = controller.document.guides;
  void set(CanvasGuides next) =>
      controller.apply(controller.document.copyWith(guides: next));
  // A number dragged or typed: one change, closed when it is let go.
  void slide(CanvasGuides next) {
    controller.beginInteraction();
    controller.apply(controller.document.copyWith(guides: next),
        transient: true);
  }

  return [
    // Rulers first: they are the page's edge, met in the canvas's order.
    CanvasFoldingGroup(label: "Rulers", remember: "guidesRulers", children: [
      for (var (label, on, apply)
          in <(String, bool, CanvasRulers Function(bool))>[
        ("Top", guides.rulers.top, (v) => guides.rulers.copyWith(top: v)),
        ("Left", guides.rulers.left, (v) => guides.rulers.copyWith(left: v)),
        ("Right", guides.rulers.right, (v) => guides.rulers.copyWith(right: v)),
        (
          "Bottom",
          guides.rulers.bottom,
          (v) => guides.rulers.copyWith(bottom: v)
        ),
      ])
        CanvasToggle(
          label: label,
          value: on,
          onChanged: (v) => set(guides.copyWith(rulers: apply(v))),
        ),
      // Shown or hidden without forgetting which edges were asked for.
      CanvasToggle(
        key: const ValueKey("guidesShowRulers"),
        label: "Show",
        value: guides.showRulers,
        onChanged: (v) => set(guides.copyWith(showRulers: v)),
      ),
      const CanvasHint(
          "Rulers sit against the edges of the canvas and are numbered from "
          "its top-left corner, at the spacing the Grid group sets — every few of "
          "them "
          "when the canvas is small on screen. Drag out of one to put a guide "
          "down."),
    ]),
    // "Every" sets grid and ruler spacing together, so ruler readings land on
    // grid lines. Named Grid alone so Rulers is not a caption twice.
    CanvasFoldingGroup(label: "Grid", remember: "guidesGrid", children: [
      CanvasToggle(
        label: "Show a grid",
        value: guides.showGrid,
        onChanged: (v) => set(guides.copyWith(showGrid: v)),
      ),
      CanvasNumberField(
        label: "Every",
        value: guides.gridSize,
        min: 2,
        max: 1000,
        decimals: 0,
        width: 62,
        onChanged: (v) => slide(guides.copyWith(gridSize: v)),
        onCommit: controller.endInteraction,
      ),
      CanvasNumberField(
        label: "Divided by",
        value: guides.subdivisions.toDouble(),
        min: 1,
        max: 10,
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
    ]),
    CanvasFoldingGroup(label: "Guides", remember: "guidesGuides", children: [
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
    ]),
    CanvasFoldingGroup(
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
            onChanged: (v) => set(
                guides.copyWith(snapTo: guides.snapTo.copyWith(vertices: v))),
          ),
          CanvasToggle(
            label: "Edges",
            value: guides.snapTo.edges,
            onChanged: (v) =>
                set(guides.copyWith(snapTo: guides.snapTo.copyWith(edges: v))),
          ),
          CanvasToggle(
            label: "Centres",
            value: guides.snapTo.centres,
            onChanged: (v) => set(
                guides.copyWith(snapTo: guides.snapTo.copyWith(centres: v))),
          ),
          // The lines that matter most: this heading over that picture, not
          // a grid's intervals.
          CanvasToggle(
            key: const ValueKey("snapToObjects"),
            label: "Elements",
            value: guides.snapTo.objects,
            onChanged: (v) => set(
                guides.copyWith(snapTo: guides.snapTo.copyWith(objects: v))),
          ),
          CanvasNumberField(
            label: "Within",
            value: guides.snapWithin,
            min: 1,
            max: 40,
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
            min: 0.01,
            max: 10,
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
            min: 1,
            max: 90,
            decimals: 0,
            width: 56,
            suffix: "°",
            onChanged: (v) => slide(guides.copyWith(stageTurn: v)),
            onCommit: controller.endInteraction,
          ),
          const CanvasHint(
              "How near, on screen, before it jumps — so it feels the same at "
              "every zoom. With Elements on, the sides and middles of everything "
              "else on the canvas are lines too. The canvas's own edges and "
              "middle are always snapped to. Hold Alt while dragging to put "
              "something exactly where the grid does not want it. With Snap "
              "on a 3D stage, what is moved there lands on the 3D steps "
              "across the floor and turns by the 3D turns."),
        ]),
    // Aligning several things at once and exactly, which snapping (one
    // thing as it passes another) cannot.
    CanvasFoldingGroup(label: "Align", remember: "guidesAlign", children: [
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
      // No line break: this group also draws in the unbounded band over the
      // canvas, where an infinitely wide break brings the layout down.
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
    ]),
  ];
}

/// CanvasGuidesPanel is that panel, laid out like the canvas settings
/// beside it: one line, scrolling sideways, over the canvas.
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
        groups: (context) => canvasGuidesSettings(controller),
      );
}
