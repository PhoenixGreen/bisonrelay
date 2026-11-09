import 'package:bruig/plugin_system/canvas/model/dock_layout.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/dock_switcher.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/preset_row.dart';
import 'package:bruig/plugin_system/canvas/ui/transport_controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// play_bar_settings.dart is the play bar's one settings button and the small
// panel it opens: the panels under the canvas -- how many places, how they
// are switched, the layouts -- and the timeline's own -- its tool, what it
// does while playing, what it shows, its zoom, where the bar sits, a marker.
// Pictures where a choice is about a shape, switches where it is on or off,
// so it reads at a glance rather than as a list.

/// PlayBarToggle is one of the timeline's switches: on the bar, lit, while
/// it is on (see CanvasPlayBar), and here.
typedef PlayBarToggle = ({
  String key,
  IconData icon,
  String label,
  bool on,
  VoidCallback toggle,
});

/// PlayBarSettingsButton is the button, and the panel it opens.
class PlayBarSettingsButton extends StatelessWidget {
  final CanvasController controller;

  /// knife is the knife tool's switch; toggles the rest of the timeline's.
  final PlayBarToggle knife;
  final List<PlayBarToggle> toggles;
  final VoidCallback onBarBelow;
  final VoidCallback onAddMarker;
  final VoidCallback? onCustomiseSidebars;

  const PlayBarSettingsButton({
    required this.controller,
    required this.knife,
    required this.toggles,
    required this.onBarBelow,
    required this.onAddMarker,
    this.onCustomiseSidebars,
    super.key,
  });

  @override
  Widget build(BuildContext context) => MenuAnchor(
        menuChildren: [
          _Panel(
            controller: controller,
            knife: knife,
            toggles: toggles,
            onBarBelow: onBarBelow,
            onAddMarker: onAddMarker,
            onCustomiseSidebars: onCustomiseSidebars,
          ),
        ],
        builder: (context, menu, _) => TransportButton(
          key: const ValueKey("playBarSettings"),
          icon: Icons.settings_outlined,
          tooltip: "Settings: the panels, the layouts and the timeline",
          on: menu.isOpen,
          onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        ),
      );
}

class _Panel extends StatelessWidget {
  final CanvasController controller;
  final PlayBarToggle knife;
  final List<PlayBarToggle> toggles;
  final VoidCallback onBarBelow;
  final VoidCallback onAddMarker;
  final VoidCallback? onCustomiseSidebars;

  const _Panel({
    required this.controller,
    required this.knife,
    required this.toggles,
    required this.onBarBelow,
    required this.onAddMarker,
    required this.onCustomiseSidebars,
  });

  /// _done closes the panel: after something that is done once, not a
  /// switch, which stays to be seen.
  void _done(BuildContext context) => MenuController.maybeOf(context)?.close();

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var dock = controller.dock;
    var muted = TextStyle(fontSize: 11, color: colors.onSurfaceVariant);
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(2, 12, 2, 6),
          child: Text(text.toUpperCase(),
              style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurfaceVariant)),
        );
    Widget caption(String text) => Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Text(text, style: muted),
        );
    return Material(
      key: const ValueKey("playBarSettingsPanel"),
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: DefaultTextStyle.merge(
            style: const TextStyle(fontSize: 12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  heading("Panels"),
                  caption("Open in"),
                  Row(children: [
                    for (var p in DockPlaces.values)
                      Expanded(
                        child: _Tile(
                          key: ValueKey("dockPlaces-${p.name}"),
                          label: switch (p) {
                            DockPlaces.one => "One place",
                            DockPlaces.two => "Side by side",
                            DockPlaces.three => "And above",
                          },
                          tooltip: p.label,
                          on: dock.places == p,
                          onTap: () =>
                              controller.dock = dock.copyWith(places: p),
                          picture: DockPlaceGlyph(
                              places: p,
                              size: const Size(56, 34),
                              color: dock.places == p
                                  ? colors.primary
                                  : colors.onSurfaceVariant),
                        ),
                      ),
                  ]),
                  caption("Switch with"),
                  Row(children: [
                    for (var w in DockSwitcher.values)
                      Expanded(
                        child: _Tile(
                          key: ValueKey("dockSwitcher-${w.name}"),
                          label: switch (w) {
                            DockSwitcher.buttons => "Buttons",
                            DockSwitcher.tabs => "Tabs",
                            DockSwitcher.layouts => "Layouts",
                          },
                          tooltip: w.label,
                          on: dock.switcher == w,
                          onTap: () =>
                              controller.dock = dock.copyWith(switcher: w),
                          picture: CustomPaint(
                            size: const Size(56, 34),
                            painter: _SwitcherPicture(
                                w,
                                dock.switcher == w
                                    ? colors.primary
                                    : colors.onSurfaceVariant),
                          ),
                        ),
                      ),
                  ]),
                  heading("Layouts"),
                  Wrap(spacing: 5, runSpacing: 5, children: [
                    for (var layout in dock.arrangements)
                      InputChip(
                        key: ValueKey("dockLayoutMenu-${layout.name}"),
                        label: Text(layout.name,
                            style: const TextStyle(fontSize: 11.5)),
                        selected: controller.dockArrangement == layout.name,
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onPressed: () => controller.arrange(layout),
                        onDeleted: layout.builtIn
                            ? null
                            : () => controller.removeArrangement(layout.name),
                        deleteButtonTooltipMessage: "Forget this layout",
                      ),
                    ActionChip(
                      key: const ValueKey("dockSaveLayout"),
                      avatar: const Icon(Icons.add, size: 14),
                      label: const Text("Keep this layout",
                          style: TextStyle(fontSize: 11.5)),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onPressed: () async {
                        _done(context);
                        var name = await askForPresetName(
                            context, "Keep this layout",
                            initial: "My layout ${dock.saved.length + 1}");
                        if (name == null || name.trim().isEmpty) return;
                        controller.saveArrangement(name.trim());
                      },
                    ),
                  ]),
                  _Switch(
                    key: const ValueKey("dockShowLayouts"),
                    label: dock.switcher == DockSwitcher.layouts
                        ? "On the play bar: they are the switcher"
                        : "On the play bar",
                    on: dock.layoutsOnBar,
                    onChanged: dock.switcher == DockSwitcher.layouts
                        ? null
                        : (v) =>
                            controller.dock = dock.copyWith(showLayouts: v),
                  ),
                  heading("Timeline"),
                  Row(children: [
                    Expanded(
                      child: _Tile(
                        key: const ValueKey("toolSelect"),
                        label: "Select",
                        tooltip: "Select and move clips",
                        on: !knife.on,
                        onTap: () {
                          if (knife.on) knife.toggle();
                        },
                        picture: Icon(Icons.near_me_outlined,
                            size: 20,
                            color: !knife.on
                                ? colors.primary
                                : colors.onSurfaceVariant),
                      ),
                    ),
                    Expanded(
                      child: _Tile(
                        key: const ValueKey("toolKnifeItem"),
                        label: "Knife",
                        tooltip: knife.label,
                        on: knife.on,
                        onTap: () {
                          if (!knife.on) knife.toggle();
                        },
                        picture: Icon(Icons.content_cut,
                            size: 20,
                            color: knife.on
                                ? colors.primary
                                : colors.onSurfaceVariant),
                      ),
                    ),
                    const Expanded(child: SizedBox()),
                  ]),
                  for (var t in toggles)
                    _Switch(
                      key: ValueKey("${t.key}-item"),
                      icon: t.icon,
                      label: t.label,
                      on: t.on,
                      onChanged: (_) => t.toggle(),
                    ),
                  _Switch(
                    key: const ValueKey("barBelow"),
                    icon: Icons.vertical_align_bottom,
                    label: "The play bar under the panels",
                    on: controller.barBelow,
                    onChanged: (_) => onBarBelow(),
                  ),
                  caption("Show"),
                  Wrap(spacing: 5, children: [
                    for (var kind in TimelineShow.values)
                      ChoiceChip(
                        key: ValueKey("show-${kind.name}"),
                        label: Text(kind.label,
                            style: const TextStyle(fontSize: 11.5)),
                        selected: controller.timelineShow == kind,
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onSelected: (_) => controller.timelineShow = kind,
                      ),
                  ]),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey("addMarkerItem"),
                      onPressed: () {
                        onAddMarker();
                        _done(context);
                      },
                      icon: const Icon(Icons.flag_outlined, size: 15),
                      label: const Text("Add a marker",
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  if (onCustomiseSidebars != null) ...[
                    const Divider(height: 18),
                    TextButton.icon(
                      key: const ValueKey("customiseSidebars"),
                      style:
                          TextButton.styleFrom(alignment: Alignment.centerLeft),
                      onPressed: () {
                        _done(context);
                        onCustomiseSidebars!();
                      },
                      icon: const Icon(Icons.view_sidebar_outlined, size: 16),
                      label: const Text("Customise sidebars…",
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ]),
          ),
        ),
      ),
    );
  }
}

/// _Tile is a choice drawn as a picture over its name, outlined when it is
/// the one chosen.
class _Tile extends StatelessWidget {
  final String label;
  final String tooltip;
  final bool on;
  final VoidCallback onTap;
  final Widget picture;
  const _Tile(
      {required this.label,
      required this.tooltip,
      required this.on,
      required this.onTap,
      required this.picture,
      super.key});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
            decoration: BoxDecoration(
              color: on ? colors.primary.withValues(alpha: 0.10) : null,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: on ? colors.primary : colors.outlineVariant,
                  width: on ? 1.5 : 1),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(height: 34, child: Center(child: picture)),
              const SizedBox(height: 5),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                      color: on ? colors.onSurface : colors.onSurfaceVariant)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// _Switch is one setting that is on or off: its icon, its name, a switch.
class _Switch extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool on;
  final ValueChanged<bool>? onChanged;
  const _Switch(
      {this.icon,
      required this.label,
      required this.on,
      required this.onChanged,
      super.key});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!on),
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 32,
        child: Row(children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: colors.onSurfaceVariant),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    color: onChanged == null
                        ? colors.onSurfaceVariant
                        : colors.onSurface)),
          ),
          Transform.scale(
            scale: 0.7,
            child: Switch(value: on, onChanged: onChanged),
          ),
        ]),
      ),
    );
  }
}

/// _SwitcherPicture draws a way of switching the panels, small: a row of
/// buttons on a bar, tabs over a place, or a few layout buttons.
class _SwitcherPicture extends CustomPainter {
  final DockSwitcher kind;
  final Color color;
  const _SwitcherPicture(this.kind, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    var w = size.width, h = size.height;
    var faint = Paint()..color = color.withValues(alpha: 0.28);
    var full = Paint()..color = color;
    RRect r(double x, double y, double ww, double hh) =>
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, ww, hh), const Radius.circular(2));
    switch (kind) {
      case DockSwitcher.buttons:
        // The bar, a row of buttons on it, and the panel under it.
        canvas.drawRRect(r(0, 0, w, 10), faint);
        for (var i = 0; i < 4; i++) {
          canvas.drawRRect(r(w * 0.30 + i * w * 0.17, 2, w * 0.14, 6),
              i == 1 ? full : faint);
        }
        canvas.drawRRect(r(0, 13, w, h - 13), faint);
      case DockSwitcher.tabs:
        // A row of tabs, one underlined, over the panel.
        for (var i = 0; i < 3; i++) {
          canvas.drawRRect(r(i * w * 0.27, 2, w * 0.23, 5), faint);
        }
        canvas.drawRect(Rect.fromLTWH(w * 0.27, 9, w * 0.23, 2), full);
        canvas.drawRRect(r(0, 13, w, h - 13), faint);
      case DockSwitcher.layouts:
        // Two wide layout buttons on the bar, the panels under it.
        canvas.drawRRect(r(0, 0, w, 10), faint);
        canvas.drawRRect(r(w * 0.40, 2, w * 0.26, 6), full);
        canvas.drawRRect(r(w * 0.70, 2, w * 0.26, 6), faint);
        canvas.drawRRect(r(0, 13, w * 0.32, h - 13), faint);
        canvas.drawRRect(r(w * 0.35, 13, w * 0.65, h - 13), faint);
    }
  }

  @override
  bool shouldRepaint(_SwitcherPicture old) =>
      old.kind != kind || old.color != color;
}
