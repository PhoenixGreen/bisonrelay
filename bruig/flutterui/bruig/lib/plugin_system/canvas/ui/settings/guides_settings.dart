import 'package:bruig/plugin_system/canvas/ui/canvas_strip.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';

// guides_settings.dart is the grid, the guides, the rulers and the snapping,
// as a panel off the settings bar: a dozen switches set up once and left, so
// not on the bar, which is for what is pressed while working. It opens over
// the canvas, as the canvas settings do, so opening it never moves the design
// or changes the zoom.

/// canvasGuidesSettings is the whole panel: five groups, each of which can be
/// shut (remembered across a restart), so those not in use do not make the
/// strip scroll.
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
    // Rulers first: they are the edge of the page, met in the order the canvas
    // meets them.
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
    // "Every" sets the grid's and the ruler's spacing together: one measurement
    // shown two ways, so a position read off the ruler lands on a grid line. The
    // group is named Grid alone so that Rulers is not a caption twice.
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
          // The lines that matter most: what anybody wants is this heading over that
          // picture, not a grid's regular intervals.
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
          // On a 3D stage there are no lines to land on: what is moved
          // there lands on steps across its floor, and turns in steps --
          // its own switch, since that is every move rather than a catch.
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
    // Lining several things up with each other, which snapping cannot do:
    // snapping catches one thing as it passes another, and these move
    // everything chosen at once and exactly.
    CanvasFoldingGroup(label: "Align", remember: "guidesAlign", children: [
      for (var align in CanvasAlign.values)
        CanvasIconButton(
          key: ValueKey("align${align.name}"),
          icon: align.icon,
          tooltip: align.label,
          // Against the selection's own box, so one thing chosen is already
          // aligned with itself and there is nothing to do.
          onPressed: controller.aligning < 2
              ? null
              : () => controller.alignSelected(align),
        ),
      // No line break before these: this group is drawn in the band over the
      // canvas as well as in the sidebar, and the band is a strip of
      // unbounded width -- a break that asks to be infinitely wide brings the
      // whole layout down there.
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

/// CanvasGuidesPanel is that panel, laid out like the canvas settings it sits
/// beside: one line, scrolling sideways, over the top of the canvas.
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
