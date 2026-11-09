import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/dock_layout.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart';
import 'package:bruig/plugin_system/canvas/ui/chain_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/dock_switcher.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart'
    show dragPointers;
import 'package:bruig/plugin_system/canvas/ui/panel_heights.dart';
import 'package:bruig/plugin_system/canvas/ui/play_bar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// canvas_dock.dart is everything under the canvas: the play bar, and the
// panels in their places (see dock_layout.dart) -- above, then main with
// left beside it. Each place shows one panel; a place with none takes no
// room. The places are as tall as they were dragged, kept in the
// preferences, and made shorter where the window is, never pushing the
// settings bar off the page (see panel_heights.dart).

/// dockLowerDefault, dockAboveDefault and dockLeftDefault are the places'
/// sizes before any is dragged.
const double dockLowerDefault = 280,
    dockAboveDefault = 220,
    dockLeftDefault = 420,
    dockLeftLeast = 220;

/// dockBarHeight is the play bar as the dock draws it: with its padding and
/// the line along its top.
const double dockBarHeight = playBarHeight + 9;

/// CanvasDock is the panels under the canvas, and the play bar.
class CanvasDock extends StatefulWidget {
  final CanvasController controller;

  /// room is how tall the places can be altogether, the bar not counted:
  /// what is under the settings bar, less what of the canvas stays in view.
  final double room;

  /// fill is whether the top place takes the whole room: the canvas put
  /// away.
  final bool fill;

  /// onCustomiseSidebars opens the sidebars' settings, from the panels'
  /// menu.
  final VoidCallback? onCustomiseSidebars;

  const CanvasDock({
    required this.controller,
    required this.room,
    this.fill = false,
    this.onCustomiseSidebars,
    super.key,
  });

  @override
  State<CanvasDock> createState() => CanvasDockState();
}

/// _Row is one band of places across the dock.
enum _Row { above, lower }

class CanvasDockState extends State<CanvasDock> {
  CanvasController get controller => widget.controller;
  late final CanvasPreferences _prefs =
      Provider.of<CanvasPreferences>(context, listen: false);

  double _lower = dockLowerDefault;
  double _above = dockAboveDefault;
  double _left = dockLeftDefault;

  /// _pull is how far the mixer's edge has been dragged past where it stops
  /// (down at its least, or up at its smallest), so a drag has to mean it
  /// before the mixer changes size step. See _mixerPulled.
  double _pull = 0;

  @override
  void initState() {
    super.initState();
    if (_prefs.dockLower > 0) _lower = _prefs.dockLower;
    if (_prefs.dockAbove > 0) _above = _prefs.dockAbove;
    if (_prefs.dockLeft > 0) _left = _prefs.dockLeft;
  }

  bool get _tabs => controller.dock.switcher == DockSwitcher.tabs;

  /// _homed is whether any panel opens in [place]: with tabs, a place shows
  /// its row of tabs whether or not one is open.
  bool _homed(DockPlace place) =>
      DockPanel.values.any((p) => controller.dock.placeOf(p) == place);

  /// _shows is whether [place] takes room: a panel open in it, or its tabs.
  bool _shows(DockPlace place) =>
      controller.dock.placesShown.contains(place) &&
      (controller.dockShownIn(place) != null || (_tabs && _homed(place)));

  List<DockPlace> _placesIn(_Row row) => row == _Row.above
      ? const [DockPlace.above]
      : const [DockPlace.left, DockPlace.main];

  double get _textScale =>
      math.max(1.0, MediaQuery.textScalerOf(context).scale(1));

  double _mixerLeast() => mixerLeastHeight(controller) * _textScale;

  /// _panelLeast is the shortest [panel] goes.
  double _panelLeast(DockPanel panel) => switch (panel) {
        DockPanel.timeline || DockPanel.slots => timelineRowsLeast,
        DockPanel.mixer => _mixerLeast(),
        DockPanel.chain => effectsMinHeight,
      };

  /// _open are the panels showing in [row].
  List<DockPanel> _open(_Row row) => [
        for (var place in _placesIn(row))
          if (controller.dockShownIn(place) case var p?) p
      ];

  /// _rows are the bands that take room, top to bottom, each as it was set,
  /// its least, and whether it is fixed: a row of tabs with nothing open, or
  /// the mixer minimised on a band of its own.
  List<(_Row, double, double, bool)> _rows() => [
        for (var row in _Row.values)
          if (_placesIn(row).any(_shows)) _measure(row),
      ];

  (_Row, double, double, bool) _measure(_Row row) {
    var tabs = _tabs ? DockPlaceTabs.height : 0.0;
    var open = _open(row);
    if (open.isEmpty) return (row, tabs, tabs, true);
    var mixerAlone = open.length == 1 && open.single == DockPanel.mixer;
    var minimised = controller.mixerMinimised || controller.mixerSmallest;
    if (mixerAlone && minimised) {
      var h = _mixerLeast() + tabs;
      return (row, h, h, true);
    }
    var least = open.map(_panelLeast).reduce(math.max) + tabs;
    var set = row == _Row.above ? _above : _lower;
    return (row, math.max(set, least), least, false);
  }

  /// _shown is each row's height on screen: as set, where they fit; where
  /// not, the top ones made shorter first, each to its least. What was set
  /// is kept, for a window made taller again. With the canvas put away, the
  /// top row that can grow takes the rest.
  Map<_Row, double> _shown(List<(_Row, double, double, bool)> rows) {
    var out = fitPanels(
        [for (var r in rows) r.$2], [for (var r in rows) r.$3], widget.room);
    if (widget.fill) {
      var total = out.fold(0.0, (a, b) => a + b);
      var f = rows.indexWhere((r) => !r.$4);
      if (f >= 0 && total < widget.room) out[f] += widget.room - total;
    }
    return {for (var (k, r) in rows.indexed) r.$1: math.max(0.0, out[k])};
  }

  /// _resize is [row]'s top edge dragged so it would be [h] tall: taking
  /// free room, then the room of the row over it, and never past the
  /// settings bar.
  void _resize(_Row row, double h) => setState(() {
        var open = _open(row);
        if (open.length == 1 &&
            open.single == DockPanel.mixer &&
            !_mixerPulled(h)) {
          return;
        }
        var rows = _rows();
        var i = rows.indexWhere((r) => r.$1 == row);
        if (i < 0) return;
        var shown = _shown(rows);
        var out = resizePanel(
          [for (var r in rows) shown[r.$1]!],
          [for (var r in rows) r.$3],
          i,
          h,
          widget.room,
          fixed: {
            for (var (k, r) in rows.indexed)
              if (r.$4) k
          },
        );
        for (var (k, r) in rows.indexed) {
          if (r.$4 || (widget.fill && k == 0)) continue;
          if (r.$1 == _Row.above) {
            _above = out[k];
            _prefs.dockAbove = out[k];
          } else {
            _lower = out[k];
            _prefs.dockLower = out[k];
          }
        }
      });

  /// _mixerPulled steps the mixer between its sizes as its edge is dragged to
  /// [h], on a band of its own: down past its least to its smallest (no
  /// names, no rail) and up again; minimised, up out to its least. Returns
  /// whether the drag goes on to size it.
  bool _mixerPulled(double h) {
    var tabs = _tabs ? DockPlaceTabs.height : 0.0;
    var least = mixerLeastHeight(controller, bare: false) * _textScale + tabs;
    if (controller.mixerSmallest) {
      var smallest =
          mixerLeastHeight(controller, bare: true) * _textScale + tabs;
      _pull = h > smallest ? _pull + (h - smallest) : 0;
      if (_pull < 16) return false;
      _pull = 0;
      controller.mixerSmallest = false;
      controller.mixerMinimised = true;
      return false;
    }
    if (h < least) {
      _pull += least - h;
      if (_pull < 24) return !controller.mixerMinimised;
      _pull = 0;
      controller.mixerMinimised = true;
      controller.mixerSmallest = true;
      return false;
    }
    _pull = 0;
    if (controller.mixerMinimised) {
      if (h <= least + 2) return false;
      controller.mixerMinimised = false;
      _lower = least;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          var theme = ThemeNotifier.of(context);
          var rows = _rows();
          var shown = _shown(rows);
          var bar = _bar(theme);
          return Column(mainAxisSize: MainAxisSize.min, children: [
            if (!controller.barBelow) bar,
            for (var r in rows)
              SizedBox(
                key: ValueKey("dockRow-${r.$1.name}"),
                height: shown[r.$1],
                child: r.$1 == _Row.above
                    ? _place(theme, DockPlace.above, shown[r.$1]!, _Row.above)
                    : _lowerRow(theme, shown[r.$1]!),
              ),
            if (controller.barBelow) bar,
          ]);
        },
      );

  Widget _bar(ThemeNotifier theme) => Container(
        height: dockBarHeight,
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
        decoration: BoxDecoration(
          color: theme.colors.surfaceContainerLow,
          border: Border(
              top: BorderSide(color: theme.colors.outlineVariant, width: 1)),
        ),
        child: RepaintBoundary(
          child: CanvasPlayBar(
            controller: controller,
            switcher: DockSwitcherBar(controller: controller),
            onCustomiseSidebars: widget.onCustomiseSidebars,
          ),
        ),
      );

  /// _lowerRow is main, with left beside it where it shows. The timeline in
  /// main with the slots on the left is drawn as one: each row of slots
  /// level with its row of the timeline.
  Widget _lowerRow(ThemeNotifier theme, double height) {
    var left = _shows(DockPlace.left);
    var main = _shows(DockPlace.main);
    if (controller.slotsWithRows) {
      return Column(children: [
        if (_tabs)
          Row(children: [
            SizedBox(
                width: controller.leftWidth + 10,
                child: DockPlaceTabs(
                    controller: controller, place: DockPlace.left)),
            Expanded(
                child: DockPlaceTabs(
                    controller: controller, place: DockPlace.main)),
          ]),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) =>
                _panel(DockPanel.timeline, box.maxHeight, _Row.lower),
          ),
        ),
      ]);
    }
    if (left && main) {
      return LayoutBuilder(builder: (context, box) {
        var width = _left
            .clamp(dockLeftLeast, math.max(dockLeftLeast, box.maxWidth - 320))
            .toDouble();
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
              width: width,
              child: _place(theme, DockPlace.left, height, _Row.lower)),
          _widthGrip(theme, box.maxWidth),
          Expanded(child: _place(theme, DockPlace.main, height, _Row.lower)),
        ]);
      });
    }
    return _place(
        theme, left ? DockPlace.left : DockPlace.main, height, _Row.lower);
  }

  /// _widthGrip is the line between left and main: dragged, left is wider
  /// or narrower.
  Widget _widthGrip(ThemeNotifier theme, double room) => MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          supportedDevices: dragPointers,
          key: const ValueKey("dockLeftGrip"),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) => setState(() {
            _left = (_left + d.delta.dx)
                .clamp(dockLeftLeast, math.max(dockLeftLeast, room - 320))
                .toDouble();
          }),
          onHorizontalDragEnd: (_) => _prefs.dockLeft = _left,
          child: Container(
            width: 5,
            decoration: BoxDecoration(
                border: Border(
                    left: BorderSide(color: theme.colors.outlineVariant))),
          ),
        ),
      );

  /// _place is [place]: its tabs, with the tabs switcher, over the panel
  /// open in it.
  Widget _place(ThemeNotifier theme, DockPlace place, double height, _Row row) {
    var panel = controller.dockShownIn(place);
    var tabs = _tabs ? DockPlaceTabs.height : 0.0;
    return Column(key: ValueKey("dockPlace-${place.name}"), children: [
      if (_tabs) DockPlaceTabs(controller: controller, place: place),
      if (panel != null)
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => _panel(panel,
                math.max(0.0, math.min(box.maxHeight, height - tabs)), row),
          ),
        ),
    ]);
  }

  /// _panel is [panel] drawn [height] tall, its top edge resizing [row].
  Widget _panel(DockPanel panel, double height, _Row row) {
    void resize(double h) =>
        _resize(row, h + (_tabs ? DockPlaceTabs.height : 0));
    return RepaintBoundary(
      key: ValueKey("dockPanel-${panel.name}"),
      child: switch (panel) {
        DockPanel.timeline => CanvasTimeline(
            controller: controller,
            height: height,
            onResize: resize,
            showBar: false,
          ),
        // A clip launcher of its own (the approved design), not the
        // timeline's rows with slots beside them.
        DockPanel.slots => CanvasSlotsPanel(
            controller: controller,
            height: height,
            onResize: resize,
          ),
        DockPanel.mixer => CanvasMixer(
            controller: controller,
            height: height,
            onResize: resize,
            onClose: () => controller.mixerOpen = false,
          ),
        DockPanel.chain => ChainPanel(
            controller: controller,
            height: height,
            onResize: resize,
          ),
      },
    );
  }
}
