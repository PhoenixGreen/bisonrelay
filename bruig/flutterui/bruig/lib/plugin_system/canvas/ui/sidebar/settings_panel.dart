import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/element_settings_pane.dart';
import 'package:flutter/material.dart';

// settings_panel.dart is the Settings panel of the sidebar: the settings of
// whatever is selected. What they are for each selection (one element,
// several, a clip, the background) is in element_settings_pane.dart, and
// each kind's own panel is in ui/settings/.

/// SettingsPanelBody is the Settings panel's body: the selection's
/// settings, scrolled. It listens for itself, since it is the sidebar's
/// most expensive body and must not be built again when a heading
/// elsewhere changes.
class SettingsPanelBody extends StatefulWidget {
  final CanvasController controller;
  const SettingsPanelBody({required this.controller, super.key});

  @override
  State<SettingsPanelBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<SettingsPanelBody> {
  CanvasController get controller => widget.controller;

  /// _scroll keeps the column where it was, per element, so clicking between
  /// elements does not put the settings back at the top.
  final ScrollController _scroll = ScrollController();

  /// _at is where each element's settings were left, by element id (the
  /// panels are different lengths, so one offset would not do).
  static final Map<String, double> _at = {};

  /// _showing is whose settings are on screen, so the offset is filed under
  /// the right element when the selection changes.
  String? _showing;

  /// _hold keeps the sections not being touched as they were while a
  /// pointer is held in a gesture (a drag on the canvas, a scrubbed
  /// number), so each step builds only what it changes: see PanelHold. Its
  /// epoch moves with every change that is not a step, and the whole panel
  /// is built again when the pointer lifts.
  late final PanelHold _hold = PanelHold(
    gesturing: () => controller.interacting,
    onRelease: () {
      _hold.epoch++;
      if (mounted) setState(() {});
    },
  );

  void _settled() => _hold.epoch++;

  @override
  void initState() {
    super.initState();
    // Sections or a menu, as it was left.
    readSettingsLayout();
    // Tiles keep their pictures during a control drag: TileSnapshot.holding.
    TileSnapshot.holding = () => controller.interacting;
    _showing = controller.selected?.id;
    controller.addListener(_onSelectionChanged);
    controller.chrome.addListener(_settled);
  }

  @override
  void dispose() {
    // The hook above would hold this panel and its document for the session.
    TileSnapshot.letGo();
    _remember();
    controller.removeListener(_onSelectionChanged);
    controller.chrome.removeListener(_settled);
    _hold.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _remember() {
    var id = _showing;
    if (id != null && _scroll.hasClients) _at[id] = _scroll.offset;
  }

  /// _onSelectionChanged files the offset of who leaves, restores who comes.
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
        // what the settings read, which goes stale as soon as a control
        // shows something outside the document (the retouch brush, say).
        select: () => controller.revision,
        builder: (context, _) => ScrollConfiguration(
          // No scroll bar: these settings are scrolled with two fingers,
          // and a bar that flashes on each scroll adds nothing.
          behavior: const CanvasNoScrollbar(),
          child: SingleChildScrollView(
            controller: _scroll,
            // A gap under the header so the first row of small captions
            // does not read as the header's second line.
            padding: const EdgeInsets.fromLTRB(
                8, (canvasGroupGap + canvasRowGap) / 2, 8, canvasGroupGap - 4),
            child: PanelHoldScope(
              hold: _hold,
              child: CanvasControlScope(
                maxWidth: 240,
                child: elementSettingsBody(context, controller),
              ),
            ),
          ),
        ),
      );
}
