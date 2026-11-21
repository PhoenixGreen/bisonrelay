import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/dock_layout.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer/canvas_mixer.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer/mixer_plugins.dart'
    show dragPointers;
import 'package:bruig/plugin_system/canvas/ui/motion/chain_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/dock_switcher.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/panel_heights.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/play_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline/canvas_timeline.dart';
import 'package:bruig/theming_system/theme_manager.dart';

// canvas_dock.dart is everything under the canvas: the play bar, and the
// panels in their places (dock_layout.dart) -- above, then main with left
// beside it. Each place shows one panel; an empty place takes no room.
// Places keep their dragged heights, shortened to fit the window without
// pushing the settings bar off the page (panel_heights.dart).

/// _lowerDefault, _aboveDefault and _leftDefault are the places'
/// sizes before any is dragged.
const double _lowerDefault = 280,
    _aboveDefault = 220,
    _leftDefault = 420,
    _leftLeast = 220;

/// dockBarHeight is the play bar as drawn in the dock, with its padding and
/// top line.
const double dockBarHeight = playBarHeight + 9;

class CanvasDock extends StatefulWidget {
  final CanvasController controller;

  /// room is how tall the places can be altogether, the bar not counted:
  /// what is under the settings bar, less what of the canvas stays in view.
  final double room;

  /// fill is whether the top place takes the whole room: the canvas away.
  final bool fill;

  /// onCustomiseSidebars opens the sidebars' settings from the panels' menu.
  final VoidCallback? onCustomiseSidebars;

  const CanvasDock({
    required this.controller,
    required this.room,
    this.fill = false,
    this.onCustomiseSidebars,
    super.key,
  });

  @override
  State<CanvasDock> createState() => _CanvasDockState();
}

/// _Band is a strip across the dock: the Above place, or the Main and Left
/// places side by side under it. Each is as tall as it was dragged.
enum _Band { above, lower }

/// _Sized is a band that takes room: the height it was [set] to, the
/// [least] it can be drawn at, and whether it is [fixed] (a line of tabs
/// with nothing open, or the mixer minimised on a band of its own).
typedef _Sized = ({_Band band, double set, double least, bool fixed});

class _CanvasDockState extends State<CanvasDock> {
  CanvasController get controller => widget.controller;
  late final CanvasPreferences _prefs =
      Provider.of<CanvasPreferences>(context, listen: false);

  double _lower = _lowerDefault;
  double _above = _aboveDefault;
  double _left = _leftDefault;

  /// _pull is how far the mixer's edge has been dragged past where it stops
  /// (down at its least, up at its smallest), so a drag must mean it before
  /// the mixer steps size. See _mixerPulled.
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

  List<DockPlace> _placesIn(_Band band) => band == _Band.above
      ? const [DockPlace.above]
      : const [DockPlace.left, DockPlace.main];

  double get _textScale =>
      math.max(1.0, MediaQuery.textScalerOf(context).scale(1));

  double _mixerLeast() => mixerLeastHeight(controller) * _textScale;

  double _panelLeast(DockPanel panel) => switch (panel) {
        DockPanel.timeline || DockPanel.slots => timelineRowsLeast,
        DockPanel.mixer => _mixerLeast(),
        DockPanel.chain => effectsMinHeight,
      };

  List<DockPanel> _open(_Band band) => [
        for (var place in _placesIn(band))
          if (controller.dockShownIn(place) case var p?) p
      ];

  /// _bands are the bands that take room, top to bottom.
  List<_Sized> _bands() => [
        for (var band in _Band.values)
          if (_placesIn(band).any(_shows)) _measure(band),
      ];

  _Sized _measure(_Band band) {
    var tabs = _tabs ? DockPlaceTabs.height : 0.0;
    var open = _open(band);
    if (open.isEmpty) {
      return (band: band, set: tabs, least: tabs, fixed: true);
    }
    var mixerAlone = open.length == 1 && open.single == DockPanel.mixer;
    var minimised = controller.mixerMinimised || controller.mixerSmallest;
    if (mixerAlone && minimised) {
      var h = _mixerLeast() + tabs;
      return (band: band, set: h, least: h, fixed: true);
    }
    var least = open.map(_panelLeast).reduce(math.max) + tabs;
    var set = band == _Band.above ? _above : _lower;
    return (band: band, set: math.max(set, least), least: least, fixed: false);
  }

  /// _shown is each band's height on screen: as set where they fit, else the
  /// top ones shortened first, each to its least, keeping what was set for a
  /// taller window. With the canvas away, the top band that can grow takes
  /// the rest.
  Map<_Band, double> _shown(List<_Sized> bands) {
    var out = fitPanels([for (var r in bands) r.set],
        [for (var r in bands) r.least], widget.room);
    if (widget.fill) {
      var total = out.fold(0.0, (a, b) => a + b);
      var f = bands.indexWhere((r) => !r.fixed);
      if (f >= 0 && total < widget.room) out[f] += widget.room - total;
    }
    return {for (var (k, r) in bands.indexed) r.band: math.max(0.0, out[k])};
  }

  /// _resize drags [band]'s top edge to make it [h] tall: taking free room,
  /// then the room of the band over it, never past the settings bar.
  void _resize(_Band band, double h) => setState(() {
        var open = _open(band);
        if (open.length == 1 &&
            open.single == DockPanel.mixer &&
            !_mixerPulled(band, h)) {
          return;
        }
        var bands = _bands();
        var i = bands.indexWhere((r) => r.band == band);
        if (i < 0) return;
        var shown = _shown(bands);
        var out = resizePanel(
          [for (var r in bands) shown[r.band]!],
          [for (var r in bands) r.least],
          i,
          h,
          widget.room,
          fixed: {
            for (var (k, r) in bands.indexed)
              if (r.fixed) k
          },
        );
        for (var (k, r) in bands.indexed) {
          if (r.fixed || (widget.fill && k == 0)) continue;
          if (r.band == _Band.above) {
            _above = out[k];
            _prefs.dockAbove = out[k];
          } else {
            _lower = out[k];
            _prefs.dockLower = out[k];
          }
        }
      });

  /// _mixerPulled steps the mixer's size as its edge is dragged to [h] on
  /// [band], a band of its own: down past its least to its smallest and back
  /// up; minimised, up to its least. Returns whether the drag goes on to
  /// size it.
  bool _mixerPulled(_Band band, double h) {
    var tabs = _tabs ? DockPlaceTabs.height : 0.0;
    var least = mixerLeastHeight(controller, bare: false) * _textScale + tabs;
    if (controller.mixerSmallest) {
      var smallest =
          mixerLeastHeight(controller, bare: true) * _textScale + tabs;
      _pull = h > smallest ? _pull + (h - smallest) : 0;
      if (_pull < 16) return false;
      _pull = 0;
      controller.mixerSize = MixerSize.minimised;
      return false;
    }
    if (h < least) {
      _pull += least - h;
      if (_pull < 24) return !controller.mixerMinimised;
      _pull = 0;
      controller.mixerSize = MixerSize.smallest;
      return false;
    }
    _pull = 0;
    if (controller.mixerMinimised) {
      if (h <= least + 2) return false;
      controller.mixerSize = MixerSize.full;
      // The band the mixer is on, which need not be the lower one.
      if (band == _Band.above) {
        _above = least;
      } else {
        _lower = least;
      }
    }
    return true;
  }

  /// build lays the panels out again on [CanvasController.chrome] only:
  /// each panel listens for itself, so a frame of play redraws what moves
  /// with it and not the dock round it.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller.chrome,
        builder: (context, _) {
          var theme = ThemeNotifier.of(context);
          var bands = _bands();
          var shown = _shown(bands);
          var bar = _bar(theme);
          return Column(mainAxisSize: MainAxisSize.min, children: [
            if (!controller.barBelow) bar,
            for (var r in bands)
              SizedBox(
                key: ValueKey("dockRow-${r.band.name}"),
                height: shown[r.band],
                child: r.band == _Band.above
                    ? _place(
                        theme, DockPlace.above, shown[r.band]!, _Band.above)
                    : _lowerRow(theme, shown[r.band]!),
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
                _panel(DockPanel.timeline, box.maxHeight, _Band.lower),
          ),
        ),
      ]);
    }
    if (left && main) {
      return LayoutBuilder(builder: (context, box) {
        var width = _left
            .clamp(_leftLeast, math.max(_leftLeast, box.maxWidth - 320))
            .toDouble();
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
              width: width,
              child: _place(theme, DockPlace.left, height, _Band.lower)),
          _widthGrip(theme, box.maxWidth),
          Expanded(child: _place(theme, DockPlace.main, height, _Band.lower)),
        ]);
      });
    }
    return _place(
        theme, left ? DockPlace.left : DockPlace.main, height, _Band.lower);
  }

  /// _widthGrip is the line between left and main, dragged to resize left.
  Widget _widthGrip(ThemeNotifier theme, double room) => MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          supportedDevices: dragPointers,
          key: const ValueKey("dockLeftGrip"),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) => setState(() {
            _left = (_left + d.delta.dx)
                .clamp(_leftLeast, math.max(_leftLeast, room - 320))
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

  /// _place is [place]: its tabs and switcher over the panel open in it.
  Widget _place(
      ThemeNotifier theme, DockPlace place, double height, _Band band) {
    var panel = controller.dockShownIn(place);
    var tabs = _tabs ? DockPlaceTabs.height : 0.0;
    return Column(key: ValueKey("dockPlace-${place.name}"), children: [
      if (_tabs) DockPlaceTabs(controller: controller, place: place),
      if (panel != null)
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => _panel(panel,
                math.max(0.0, math.min(box.maxHeight, height - tabs)), band),
          ),
        ),
    ]);
  }

  /// _panel is [panel] drawn [height] tall, its top edge resizing [band].
  Widget _panel(DockPanel panel, double height, _Band band) {
    void resize(double h) =>
        _resize(band, h + (_tabs ? DockPlaceTabs.height : 0));
    return RepaintBoundary(
      key: ValueKey("dockPanel-${panel.name}"),
      child: switch (panel) {
        // The timeline, slots and mixer in the studio palette, or the app's
        // theme, as chosen in Settings.
        DockPanel.timeline => StudioScope(
            child: CanvasTimeline(
              controller: controller,
              height: height,
              onResize: resize,
              showBar: false,
            ),
          ),
        // A clip launcher of its own, not the timeline's rows with slots.
        DockPanel.slots => StudioScope(
            child: CanvasSlotsPanel(
              controller: controller,
              height: height,
              onResize: resize,
            ),
          ),
        DockPanel.mixer => StudioScope(
            child: CanvasMixer(
              controller: controller,
              height: height,
              onResize: resize,
              onClose: () => controller.mixerOpen = false,
            ),
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
