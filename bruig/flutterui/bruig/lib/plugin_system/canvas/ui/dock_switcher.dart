import 'package:bruig/plugin_system/canvas/model/dock_layout.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/transport_controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// dock_switcher.dart is what opens the panels under the canvas, at the play
// bar's right end, as the reader chose (DockLayout.switcher): a button for
// each panel, the layouts alone, or -- with tabs over each place (see
// DockPlaceTabs) -- the layouts. How many places, how they are switched and
// keeping a layout are in the bar's settings: see play_bar_settings.dart.

/// DockSwitcherBar is the switcher on the play bar.
class DockSwitcherBar extends StatelessWidget {
  final CanvasController controller;

  /// compact is the buttons as their icons alone, for a narrow bar: their
  /// names are their hover text.
  final bool compact;

  const DockSwitcherBar(
      {required this.controller, this.compact = false, super.key});

  DockSwitcherBar copyWith({bool? compact}) => DockSwitcherBar(
      key: key, controller: controller, compact: compact ?? this.compact);

  @override
  Widget build(BuildContext context) {
    var dock = controller.dock;
    return TransportGroup(children: [
      if (dock.switcher == DockSwitcher.layouts)
        for (var layout in dock.arrangements)
          TransportButton(
            key: ValueKey("dockLayout-${layout.name}"),
            width: null,
            tooltip: "Show the “${layout.name}” layout",
            on: controller.dockArrangement == layout.name,
            onPressed: () => controller.arrange(layout),
            child: Text(layout.name,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          )
      else if (dock.showLayouts)
        DockLayoutsButton(controller: controller, compact: compact),
      if (dock.switcher == DockSwitcher.buttons)
        for (var panel in DockPanel.values)
          DockPanelButton(
              controller: controller, panel: panel, compact: compact),
    ]);
  }
}

/// DockPanelButton is one panel's button: lit while it is open, with where
/// it opens drawn beside its name. Pressed, it opens or closes; with Shift,
/// it opens on the left. Dragged onto the map that appears, it opens there
/// from then on; its right-click menu says the same.
class DockPanelButton extends StatefulWidget {
  final CanvasController controller;
  final DockPanel panel;

  /// compact is the button as its icon alone, beside where it opens.
  final bool compact;

  const DockPanelButton(
      {required this.controller,
      required this.panel,
      this.compact = false,
      super.key});

  @override
  State<DockPanelButton> createState() => _DockPanelButtonState();
}

class _DockPanelButtonState extends State<DockPanelButton> {
  final OverlayPortalController _map = OverlayPortalController();
  final LayerLink _link = LayerLink();

  CanvasController get controller => widget.controller;
  DockPanel get panel => widget.panel;

  @override
  Widget build(BuildContext context) {
    var dock = controller.dock;
    var place = dock.placeOf(panel);
    var open = controller.dockOpen(panel);
    var movable = dock.places != DockPlaces.one;
    var button = TransportButton(
      key: ValueKey(panel.key),
      width: null,
      tooltip: movable
          ? "${panel.label}: opens ${_where(place)}. Drag to move it, "
              "right-click for more, Shift-click to open it on the left"
          : "${panel.label}: opens full width",
      on: open,
      onPressed: () => controller.toggleDock(panel,
          beside: HardwareKeyboard.instance.isShiftPressed),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        DockPlaceGlyph(places: dock.places, place: place),
        const SizedBox(width: 6),
        if (widget.compact)
          Icon(dockPanelIcon(panel), size: 16)
        else
          Text(panel.label,
              style: const TextStyle(fontWeight: FontWeight.w500)),
      ]),
    );
    var menu = GestureDetector(
      onSecondaryTapDown: (d) => _showMenu(context, d.globalPosition),
      child: button,
    );
    if (!movable) return menu;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _map,
        overlayChildBuilder: (context) => CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.topRight,
          followerAnchor: Alignment.bottomRight,
          offset: const Offset(0, -8),
          child: Align(
            alignment: Alignment.bottomRight,
            child: DockDropMap(controller: controller, panel: panel),
          ),
        ),
        child: Draggable<DockPanel>(
          data: panel,
          onDragStarted: _map.show,
          onDragEnd: (_) => _map.hide(),
          onDraggableCanceled: (_, __) => _map.hide(),
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(opacity: 0.85, child: button),
          ),
          child: menu,
        ),
      ),
    );
  }

  Future<void> _showMenu(BuildContext context, Offset at) async {
    var dock = controller.dock;
    var colors = ThemeNotifier.of(context, listen: false).colors;
    var choice = await showMenu<Object>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        PopupMenuItem<Object>(
          enabled: false,
          height: 28,
          child: Text("${panel.label} opens".toUpperCase(),
              style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.8,
                  color: colors.onSurfaceVariant)),
        ),
        for (var place in DockPlace.values)
          PopupMenuItem<Object>(
            key: ValueKey("dockMove-${panel.name}-${place.name}"),
            value: place,
            height: 32,
            enabled: dock.placesShown.contains(place),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                  width: 22,
                  child: dock.placeOf(panel) == place
                      ? const Icon(Icons.check, size: 15)
                      : null),
              Flexible(
                child: Text(_placeLine(place),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5)),
              ),
            ]),
          ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<Object>(
          value: "toggle",
          height: 32,
          child: Text(controller.dockOpen(panel) ? "Close it" : "Open it",
              style: const TextStyle(fontSize: 12.5)),
        ),
      ],
    );
    if (choice is DockPlace) {
      controller.moveDockPanel(panel, choice);
    } else if (choice == "toggle") {
      controller.toggleDock(panel);
    }
  }
}

/// dockPanelIcon is [panel]'s icon: on its button when the bar is short of
/// room, and wherever else it is named small.
IconData dockPanelIcon(DockPanel panel) => switch (panel) {
      DockPanel.timeline => Icons.view_timeline_outlined,
      DockPanel.slots => Icons.grid_view_outlined,
      DockPanel.mixer => Icons.tune,
      DockPanel.chain => Icons.linear_scale,
    };

/// _where is how a place reads in a sentence.
String _where(DockPlace place) => switch (place) {
      DockPlace.main => "in Main",
      DockPlace.left => "on the left, beside Main",
      DockPlace.above => "above",
    };

String _placeLine(DockPlace place) => switch (place) {
      DockPlace.main => "In Main",
      DockPlace.left => "On the left, beside Main",
      DockPlace.above => "Above",
    };

/// DockDropMap is the places, drawn small, to drop a dragged panel button
/// on: where it lands is where the panel opens from then on.
class DockDropMap extends StatelessWidget {
  final CanvasController controller;
  final DockPanel panel;
  const DockDropMap({required this.controller, required this.panel, super.key});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var dock = controller.dock;
    Widget zone(DockPlace place, {required double height}) {
      var open = dock.placesShown.contains(place);
      return DragTarget<DockPanel>(
        key: ValueKey("dockDrop-${place.name}"),
        onWillAcceptWithDetails: (_) => open,
        onAcceptWithDetails: (d) => controller.moveDockPanel(d.data, place),
        builder: (context, over, _) => Container(
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: over.isNotEmpty
                ? colors.primary.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: over.isNotEmpty ? colors.primary : colors.outlineVariant,
                width: 1.5),
          ),
          child: Text(
              open
                  ? place.name[0].toUpperCase() + place.name.substring(1)
                  : "Above (needs three places)",
              style: TextStyle(
                  fontSize: 11.5,
                  color: open
                      ? colors.onSurface
                      : colors.onSurfaceVariant.withValues(alpha: 0.6))),
        ),
      );
    }

    return Material(
      elevation: 8,
      color: colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text("Drop it where ${panel.label} should open",
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
          ),
          const SizedBox(height: 8),
          zone(DockPlace.above, height: 40),
          const SizedBox(height: 5),
          Row(children: [
            Expanded(flex: 1, child: zone(DockPlace.left, height: 64)),
            const SizedBox(width: 5),
            Expanded(flex: 2, child: zone(DockPlace.main, height: 64)),
          ]),
        ]),
      ),
    );
  }
}

/// DockPlaceGlyph is the places drawn small, with [place] filled in: where a
/// panel opens. One place is one box; two, a narrow and a wide side by side;
/// three, a band over them too.
class DockPlaceGlyph extends StatelessWidget {
  final DockPlaces places;

  /// place is the one filled in; with none, every place is.
  final DockPlace? place;

  /// size is how big it is drawn: small on a button, larger on a tile.
  final Size size;

  /// color is what it is drawn in: the text's, unless given.
  final Color? color;

  const DockPlaceGlyph(
      {required this.places,
      this.place,
      this.size = const Size(16, 11),
      this.color,
      super.key});

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: size,
        painter: _GlyphPainter(places, place,
            color ?? DefaultTextStyle.of(context).style.color ?? Colors.white),
      );
}

class _GlyphPainter extends CustomPainter {
  final DockPlaces places;
  final DockPlace? place;
  final Color color;
  const _GlyphPainter(this.places, this.place, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    var r = size.height > 20 ? 3.0 : 1.0;
    void box(Rect rect, DockPlace here) => canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(r)),
        Paint()
          ..color = color.withValues(
              alpha: place == null || place == here ? 1 : 0.3));
    var w = size.width, h = size.height;
    // In proportion however big it is drawn: the gap a sixteenth, the left a
    // third, the band above a third.
    var gap = (w / 16).clamp(1.0, 4.0);
    if (places == DockPlaces.one) {
      box(Offset.zero & size, DockPlace.main);
      return;
    }
    var top = places == DockPlaces.three ? h * 0.36 : 0.0;
    if (top > 0) box(Rect.fromLTWH(0, 0, w, top - gap), DockPlace.above);
    var left = w * 0.32;
    box(Rect.fromLTWH(0, top, left, h - top), DockPlace.left);
    box(Rect.fromLTWH(left + gap, top, w - left - gap, h - top),
        DockPlace.main);
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.places != places || old.place != place || old.color != color;
}

/// DockLayoutsButton is the layouts as a dropdown: the one chosen named on
/// it while nothing has changed since.
class DockLayoutsButton extends StatelessWidget {
  final CanvasController controller;

  /// compact is the button as its icon alone.
  final bool compact;

  const DockLayoutsButton(
      {required this.controller, this.compact = false, super.key});

  @override
  Widget build(BuildContext context) {
    var chosen = controller.dockArrangement;
    return MenuAnchor(
      menuChildren: [
        for (var layout in controller.dock.arrangements)
          MenuItemButton(
            key: ValueKey("dockLayoutItem-${layout.name}"),
            leadingIcon: SizedBox(
                width: 16,
                child: chosen == layout.name
                    ? const Icon(Icons.check, size: 15)
                    : null),
            onPressed: () => controller.arrange(layout),
            child: Text(layout.name, style: const TextStyle(fontSize: 12.5)),
          ),
      ],
      builder: (context, menu, _) => TransportButton(
        key: const ValueKey("dockLayouts"),
        width: null,
        tooltip: "Layouts: several panels at once",
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.dashboard_outlined, size: 15),
          if (!compact) ...[
            const SizedBox(width: 5),
            Text(chosen ?? "Layouts",
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
          const Icon(Icons.expand_more, size: 15),
        ]),
      ),
    );
  }
}

/// DockPlaceTabs is a row of tabs over [place], one for each panel that
/// opens there, for the tabs switcher: pressed, a tab shows its panel (or,
/// shown, closes it). A tab dragged onto another place's row moves its panel
/// there.
class DockPlaceTabs extends StatelessWidget {
  final CanvasController controller;
  final DockPlace place;
  const DockPlaceTabs(
      {required this.controller, required this.place, super.key});

  /// height is the row's.
  static const double height = 26;

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var dock = controller.dock;
    var here = [
      for (var p in DockPanel.values)
        if (dock.placeOf(p) == place) p
    ];
    var movable = dock.places != DockPlaces.one;
    Widget tab(DockPanel panel) {
      var on = controller.dockOpen(panel);
      var face = InkWell(
        key: ValueKey("dockTab-${panel.name}"),
        onTap: () => controller.toggleDock(panel),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: on ? colors.primary : Colors.transparent,
                      width: 2))),
          child: Text(panel.label,
              style: TextStyle(
                  fontSize: 11.5,
                  color: on ? colors.onSurface : colors.onSurfaceVariant)),
        ),
      );
      if (!movable) return face;
      return Draggable<DockPanel>(
        data: panel,
        feedback: Material(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(5),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text(panel.label, style: const TextStyle(fontSize: 11.5)),
          ),
        ),
        child: face,
      );
    }

    return DragTarget<DockPanel>(
      onWillAcceptWithDetails: (d) => movable && dock.placeOf(d.data) != place,
      onAcceptWithDetails: (d) => controller.moveDockPanel(d.data, place),
      builder: (context, over, _) => Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: over.isNotEmpty
              ? colors.primary.withValues(alpha: 0.12)
              : colors.surfaceContainer,
          border: Border(bottom: BorderSide(color: colors.outlineVariant)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var p in here) tab(p),
          const Spacer(),
          if (movable)
            PopupMenuButton<DockPanel>(
              key: ValueKey("dockTabsAdd-${place.name}"),
              tooltip: "Bring a panel here",
              iconSize: 15,
              padding: EdgeInsets.zero,
              icon: Icon(Icons.add, size: 15, color: colors.onSurfaceVariant),
              itemBuilder: (context) => [
                for (var p in DockPanel.values)
                  if (dock.placeOf(p) != place)
                    PopupMenuItem(
                        value: p,
                        height: 32,
                        child: Text(p.label,
                            style: const TextStyle(fontSize: 12.5))),
              ],
              onSelected: (p) => controller.moveDockPanel(p, place),
            ),
        ]),
      ),
    );
  }
}
