import 'package:bruig/plugin_system/canvas/ui/canvas_strip.dart';
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
//
// It opens over the top of the canvas rather than pushing it down, which is
// what the canvas settings beside it do and for the same reason: opening a
// panel must not move the design or change the zoom under whatever is being
// looked at. Closing it gets the strip back.

/// canvasGuidesSettings is the whole panel.
///
/// Five groups, each of which can be shut -- they are set up once and then
/// left alone, and the three you are not using are what makes the strip
/// scroll. What is shut is remembered across a restart.
List<Widget> canvasGuidesSettings(CanvasController controller) {
  var guides = controller.document.guides;
  void set(CanvasGuides next) =>
      controller.apply(controller.document.copyWith(guides: next));

  return [
    // Rulers first, because they are the edge of the page: everything else
    // here is drawn inside the frame they make, and a reader going along the
    // strip meets them in the order the canvas does.
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
      // Shown or hidden without forgetting which edges were asked for, which
      // is the whole of what this is for. It was in the bar and nowhere else,
      // so a canvas saved with the rulers hidden had no way back to them once
      // the bar stopped carrying switches.
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
    // "Every" sets the spacing for the grid and the ruler together. They are
    // one measurement of the page shown two ways, and when they disagreed --
    // a ruler picking its own round numbers by zoom, a grid on its own
    // spacing -- reading a position off the ruler meant counting squares on
    // the grid to find it.
    //
    // Named for the grid all the same. It was "Grid and rulers", which put
    // the word Rulers on two captions a group apart and read as though the
    // ruler edges were in here somewhere.
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
          // The lines that matter most of the time, and the ones that were
          // missing: a grid catches a design at regular intervals, and what
          // anybody actually wants is this heading over that picture.
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
            onChanged: (v) => set(guides.copyWith(snapWithin: v)),
          ),
          const CanvasHint(
              "How near, on screen, before it jumps — so it feels the same at "
              "every zoom. With Elements on, the sides and middles of everything "
              "else on the canvas are lines too. The canvas's own edges and "
              "middle are always snapped to. Hold Alt while dragging to put "
              "something exactly where the grid does not want it."),
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
          onPressed: controller.selection.length < 2
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
        onPressed: controller.selection.length < 3
            ? null
            : () => controller.spreadSelected(true),
      ),
      CanvasIconButton(
        key: const ValueKey("spreadDown"),
        icon: Icons.vertical_distribute,
        tooltip: "Even gaps down",
        onPressed: controller.selection.length < 3
            ? null
            : () => controller.spreadSelected(false),
      ),
      CanvasHint(controller.selection.length < 2
          ? "Choose two or more elements to line them up with each other. "
              "Three or more to spread them evenly."
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
