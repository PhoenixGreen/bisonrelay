import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';

// guides_settings.dart is the grid, the guides, the rulers and the snapping,
// as a panel that opens off the settings bar.
//
// A panel rather than a row of buttons on the bar itself. There are a dozen
// switches here and they are all set up once and then left alone -- the bar is
// for what gets pressed while working, and this is what gets arranged before
// the work starts.

/// canvasGuidesSettings is the whole panel.
List<Widget> canvasGuidesSettings(CanvasController controller) {
  var guides = controller.document.guides;
  void set(CanvasGuides next) =>
      controller.apply(controller.document.copyWith(guides: next));

  return [
    CanvasControlGroup(label: "Grid", children: [
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
        onChanged: (v) => set(guides.copyWith(gridSize: v)),
      ),
      CanvasNumberField(
        label: "Divided by",
        value: guides.subdivisions.toDouble(),
        min: 1,
        max: 10,
        decimals: 0,
        width: 62,
        onChanged: (v) => set(guides.copyWith(subdivisions: v.round())),
      ),
      const CanvasHint(
          "The strong lines are the grid; dividing it draws fainter ones "
          "between them. Both can be snapped to, and neither is exported — a "
          "grid is for building the design, not part of it."),
    ]),
    CanvasControlGroup(label: "Guides", children: [
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
    CanvasControlGroup(label: "Snapping", children: [
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
      CanvasToggle(
        label: "Edges",
        value: guides.snapTo.edges,
        onChanged: (v) =>
            set(guides.copyWith(snapTo: guides.snapTo.copyWith(edges: v))),
      ),
      CanvasToggle(
        label: "Centres",
        value: guides.snapTo.centres,
        onChanged: (v) =>
            set(guides.copyWith(snapTo: guides.snapTo.copyWith(centres: v))),
      ),
      CanvasNumberField(
        label: "Within",
        value: guides.snapWithin,
        min: 1,
        max: 40,
        decimals: 0,
        width: 56,
        suffix: "px",
        onChanged: (v) => set(guides.copyWith(snapWithin: v)),
      ),
      const CanvasHint(
          "How near, on screen, before it jumps — so it feels the same at "
          "every zoom. The canvas's own edges and middle are always snapped "
          "to. Hold Alt while dragging to put something exactly where the "
          "grid does not want it."),
    ]),
    CanvasControlGroup(label: "Rulers", children: [
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
      const CanvasHint("Drag out of a ruler to put a guide down."),
    ]),
  ];
}
