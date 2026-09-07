import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
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
List<Widget> canvasGuidesSettings(CanvasController controller) {
  var guides = controller.document.guides;
  void set(CanvasGuides next) =>
      controller.apply(controller.document.copyWith(guides: next));

  return [
    // "Every" sets the spacing for the grid and the ruler together. They are
    // one measurement of the page shown two ways, and when they disagreed --
    // a ruler picking its own round numbers by zoom, a grid on its own
    // spacing -- reading a position off the ruler meant counting squares on
    // the grid to find it.
    CanvasControlGroup(label: "Grid and rulers", children: [
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
      const CanvasHint(
          "Rulers sit against the edges of the canvas and are numbered from "
          "its top-left corner, at the spacing set above — every few of them "
          "when the canvas is small on screen. Drag out of one to put a guide "
          "down."),
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

  /// _scroll is held rather than left to the scroll view, so the line keeps
  /// its position across the rebuild that follows every switch on it.
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_onChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Material(
      // Opaque, and with a shadow: it is sitting on top of the design rather
      // than above it, so it has to read as a thing in front.
      color: theme.colors.surfaceContainerLow,
      elevation: 6,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: theme.colors.outlineVariant, width: 1)),
        ),
        // Sideways rather than wrapping, as the canvas settings do. A group is
        // a column of controls and a row of them is wider than most windows.
        child: Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          thickness: 3,
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var group in canvasGuidesSettings(controller))
                  Padding(
                      padding: const EdgeInsets.only(right: 14), child: group),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
