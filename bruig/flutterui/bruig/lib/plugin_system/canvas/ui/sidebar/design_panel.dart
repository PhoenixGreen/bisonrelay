import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/element_settings_pane.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/elements_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/layers_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/scenes_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/structure_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/vocal_cues_panel.dart';
import 'package:bruig/components/panel_stack.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/colour_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/sidebar_panels.dart';
import 'package:flutter/material.dart';

// design_panel.dart is the three things used to build a canvas, in one
// column: what can be added, what is already there, and the settings of the
// selection. A panel stack (components/panel_stack.dart), so each panel
// opens, shuts, resizes and moves, and all of that is remembered.

class CanvasDesignPanel extends StatefulWidget {
  final CanvasController controller;
  const CanvasDesignPanel({required this.controller, super.key});

  @override
  State<CanvasDesignPanel> createState() => _CanvasDesignPanelState();
}

class _CanvasDesignPanelState extends State<CanvasDesignPanel> {
  CanvasController get controller => widget.controller;

  /// The three bodies, built once and handed to the stack unchanged.
  ///
  /// The stack rebuilds whenever a heading changes, which is every controller
  /// notification (one per pixel of a drag). Handed the same widget instance,
  /// Flutter leaves the subtree alone, so each body listens for what it shows
  /// and rebuilds itself.
  late Widget _add;
  late Widget _scenes;
  late Widget _structure;
  late Widget _cues;
  late Widget _layers;
  late Widget _settings;
  late Widget _colour;

  @override
  void initState() {
    super.initState();
    // Tiles keep their pictures while a control is dragged -- see
    // TileSnapshot.holding.
    TileSnapshot.holding = () => widget.controller.interacting;
    readSettingsLayout();
    _makeBodies();
  }

  @override
  void dispose() {
    // The hook set above held this panel, its editor and its document for
    // the rest of the session.
    TileSnapshot.letGo();
    super.dispose();
  }

  @override
  void didUpdateWidget(CanvasDesignPanel old) {
    super.didUpdateWidget(old);
    // Built once per controller: keeping the old bodies would leave the column
    // bound to a document nobody is looking at.
    if (old.controller != widget.controller) _makeBodies();
  }

  void _makeBodies() {
    _add = CanvasElementsPanel(controller: controller);
    _scenes = CanvasScenesPanel(controller: controller);
    _structure = CanvasStructurePanel(controller: controller);
    _cues = CanvasVocalCuesPanel(controller: controller);
    _layers = CanvasLayersPanel(controller: controller);
    _settings = SettingsPanelBody(controller: controller);
    _colour = ColourPanel(controller: controller);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        // The headings only (two of them describe the document), and the
        // settings' layout, which its heading's icon shows.
        listenable: Listenable.merge([controller, settingsAsMenu]),
        builder: (context, _) => _stack(context),
      );

  Widget _stack(BuildContext context) => PanelStack(
        storageKey: "canvasDesign",
        panels: [
          for (var id in designPanelIds)
            canvasSidebarPanel(id, controller, _body(id))!,
        ],
      );

  Widget _body(String id) => switch (id) {
        "add" => _add,
        "scenes" => controller.document.kind.isAudio ? _structure : _scenes,
        "vocalCues" => _cues,
        "layers" => _layers,
        "colour" => _colour,
        _ => _settings,
      };
}

/// designPanelIds are the Design column's panels, in order.
const designPanelIds = [
  "add",
  "scenes",
  "vocalCues",
  "layers",
  "colour",
  "settings",
];

/// SettingsPanelBody is the settings of whatever is selected: its own widget with
/// its own listener, because it is the most expensive body in the column and
/// must not rebuild when a heading elsewhere changes.
class SettingsPanelBody extends StatefulWidget {
  final CanvasController controller;
  const SettingsPanelBody({required this.controller, super.key});

  @override
  State<SettingsPanelBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<SettingsPanelBody> {
  CanvasController get controller => widget.controller;

  /// _scroll keeps the column where it was, remembered per element, so
  /// clicking between elements does not put the settings back at the top.
  final ScrollController _scroll = ScrollController();

  /// _at is where each element's settings were left, by element id (the panels
  /// are different lengths, so one offset would not do).
  static final Map<String, double> _at = {};

  /// _showing is whose settings are on screen, so the offset is filed under
  /// the right element when the selection changes.
  String? _showing;

  @override
  void initState() {
    super.initState();
    _showing = controller.selected?.id;
    controller.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    _remember();
    controller.removeListener(_onSelectionChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _remember() {
    var id = _showing;
    if (id != null && _scroll.hasClients) _at[id] = _scroll.offset;
  }

  /// _onSelectionChanged files the offset under whoever is leaving and
  /// restores whoever is arriving.
  void _onSelectionChanged() {
    var id = controller.selected?.id;
    if (id == _showing) return;
    _remember();
    _showing = id;

    // After the frame: the new settings are a different height and must be
    // laid out before they can be scrolled.
    var wanted = id == null ? 0.0 : (_at[id] ?? 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(wanted.clamp(0, _scroll.position.maxScrollExtent));
    });
  }

  @override
  Widget build(BuildContext context) => CanvasWatch<int>(
        listenable: controller,
        // Every change except view-only ones (zoom, pan, frame shape, tool):
        // see CanvasController.revision. Keyed on that rather than a list of
        // what the settings read, because such a list goes stale as soon as a
        // control shows something outside the document (the retouch brush, its
        // size, a waiting stroke).
        select: () => controller.revision,
        builder: (context, _) => ScrollConfiguration(
          // No scroll bar: these settings are scrolled with two fingers, and a
          // bar that flashes on each scroll adds nothing.
          behavior: const CanvasNoScrollbar(),
          child: SingleChildScrollView(
            controller: _scroll,
            // A gap under the header so the first row of small captions does not
            // read as the header's second line.
            padding: EdgeInsets.fromLTRB(
                8, (canvasGroupGap + canvasRowGap) / 2, 8, canvasGroupGap - 4),
            child: CanvasControlScope(
              maxWidth: 240,
              child: elementSettingsBody(context, controller),
            ),
          ),
        ),
      );
}
