import 'package:bruig/components/containers.dart';
import 'package:bruig/components/panel_stack.dart';
import 'package:bruig/plugin_system/canvas/model/sidebar_layout.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/sidebar_panels.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// canvas_sidebar.dart is the Canvas sidebar: a row of icons, one for each
// sidebar (see sidebar_layout.dart), and the panels of the one chosen, in a
// panel stack of its own. Along the row: the toggle between full height and
// above the panels under the canvas, the menu, and the arrow that hides it. A panel's heading dropped on another
// sidebar's icon moves it there; its ⋯ moves or hides it too. Hidden panels
// come back, and sidebars change places, in Customise sidebars (see
// customise_sidebars.dart).

/// canvasNavHeight matches the composer's, so the two pages' sidebars line up.
const double canvasNavHeight = 36;

/// sidebarIcon is the icon a sidebar wears, by its name in the layout.
IconData sidebarIcon(String name) => switch (name) {
      "folder" => Icons.folder_outlined,
      "design" => Icons.category_outlined,
      "media" => Icons.perm_media_outlined,
      "game" => Icons.sports_esports_outlined,
      "brush" => Icons.brush_outlined,
      "bookmark" => Icons.bookmark_border,
      "bolt" => Icons.bolt,
      "heart" => Icons.favorite_border,
      "chart" => Icons.bar_chart,
      "layers" => Icons.layers_outlined,
      "palette" => Icons.palette_outlined,
      "movie" => Icons.movie_outlined,
      "music" => Icons.music_note_outlined,
      _ => Icons.star_outline,
    };

/// CanvasSidebar is the sidebar: see the top of the file.
class CanvasSidebar extends StatefulWidget {
  final CanvasController controller;
  final SidebarLayout layout;
  final ValueChanged<SidebarLayout> onLayout;
  final SidebarPanelBodies bodies;

  /// onCustomise opens the sidebars' settings.
  final VoidCallback onCustomise;

  /// canSitAbove is whether it may sit above the bottom panels: not with
  /// the canvas away (an audio document's), where the panels fill the
  /// page and would leave the sidebar's column nothing.
  final bool canSitAbove;

  const CanvasSidebar({
    required this.controller,
    required this.layout,
    required this.onLayout,
    required this.bodies,
    required this.onCustomise,
    this.canSitAbove = true,
    super.key,
  });

  @override
  State<CanvasSidebar> createState() => _CanvasSidebarState();
}

class _CanvasSidebarState extends State<CanvasSidebar> {
  CanvasController get controller => widget.controller;
  SidebarLayout get layout => widget.layout;

  /// _seen are the sidebars that have been looked at, kept built so going
  /// back to one is instant (building the design column cold takes over a
  /// hundred milliseconds). Not built before they are wanted.
  final Set<String> _seen = {};

  List<SidebarSet> get _shown => layout.shown(game: controller.document.game);

  SidebarSet get _current =>
      _shown.where((s) => s.id == layout.current).firstOrNull ?? _shown.first;

  void _set(SidebarLayout next) => widget.onLayout(next);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: sidebarListenable(controller),
        builder: (context, _) {
          var theme = ThemeNotifier.of(context);
          var current = _current;
          _seen.add(current.id);
          var shown = _shown;
          // Squeezed to a sliver -- the Chain filling the window, a panel
          // dragged over it -- it shows nothing rather than spilling.
          return LayoutBuilder(builder: (context, box) {
            if (box.maxHeight < 60) return const SizedBox.shrink();
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(context, theme, shown, current),
                  const Divider(height: 1),
                  Expanded(
                    child: RepaintBoundary(
                      child: Stack(children: [
                        for (var s in shown)
                          if (_seen.contains(s.id))
                            Offstage(
                              key: ValueKey("sidebar-${s.id}"),
                              offstage: s.id != current.id,
                              // Nothing hidden should be animating: an offstage
                              // spinner would go on scheduling frames.
                              child: TickerMode(
                                enabled: s.id == current.id,
                                child: _column(context, s, s.id == current.id),
                              ),
                            ),
                      ]),
                    ),
                  ),
                ]);
          });
        },
      );

  Widget _header(BuildContext context, ThemeNotifier theme,
      List<SidebarSet> shown, SidebarSet current) {
    var inDrawer = CollapsedSidebarScope.of(context);
    var colors = theme.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(4, 4, inDrawer ? 4 : 0, 4),
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (var s in shown) _icon(theme, s, s.id == current.id),
            ]),
          ),
        ),
        if (widget.canSitAbove) _modeToggle(theme),
        _menu(theme),
        // A drawer is already put away by tapping off it, and the chevron
        // would point at an edge that is not there.
        if (!inDrawer) ...[
          Container(
            width: 1,
            height: 20,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: colors.outlineVariant,
          ),
          Tooltip(
            message: "Hide the sidebar",
            child: InkWell(
              key: const ValueKey("sidebarHide"),
              onTap: () => _set(layout.withMode(SidebarMode.hidden)),
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6), bottomLeft: Radius.circular(6)),
              child: Container(
                height: canvasNavHeight,
                alignment: Alignment.center,
                padding: const EdgeInsets.fromLTRB(8, 0, 10, 0),
                child: Icon(Icons.chevron_left,
                    size: 20, color: colors.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  /// _icon is one sidebar's icon: pressed, it is shown; a panel's heading
  /// dropped on it moves the panel there.
  Widget _icon(ThemeNotifier theme, SidebarSet s, bool selected) {
    var colors = theme.colors;
    var face = DragTarget<PanelDrag>(
      onWillAcceptWithDetails: (d) =>
          SidebarLayout.canGoIn(d.data.id, s) && !s.panels.contains(d.data.id),
      onAcceptWithDetails: (d) =>
          _set(layout.movePanel(d.data.id, s.id).copyWith(current: s.id)),
      builder: (context, over, _) => Tooltip(
        message: s.name,
        child: InkWell(
          key: ValueKey("sidebarTab-${s.id}"),
          onTap: () => _set(layout.copyWith(current: s.id)),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 36,
            height: canvasNavHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: selected ? colors.secondaryContainer : null,
              border: over.isNotEmpty
                  ? Border.all(color: colors.primary, width: 2)
                  : null,
            ),
            child: Icon(sidebarIcon(s.icon),
                size: 17,
                color: selected
                    ? colors.onSecondaryContainer
                    : colors.onSurfaceVariant),
          ),
        ),
      ),
    );
    return face;
  }

  /// _modeToggle switches between full height and over the panels under the
  /// canvas; the arrow beside it hides the sidebar.
  Widget _modeToggle(ThemeNotifier theme) {
    var above = layout.mode == SidebarMode.above;
    return Tooltip(
      message: above
          ? "Above the bottom panels: press for full height"
          : "Full height: press to sit above the bottom panels",
      child: InkWell(
        key: const ValueKey("sidebarModeToggle"),
        borderRadius: BorderRadius.circular(6),
        onTap: () =>
            _set(layout.withMode(above ? SidebarMode.full : SidebarMode.above)),
        child: _face(
            theme,
            above
                ? Icons.vertical_split_outlined
                : Icons.view_sidebar_outlined),
      ),
    );
  }

  /// _face is a button in the row along the top, the same size as a
  /// sidebar's icon, so the whole row lines up.
  Widget _face(ThemeNotifier theme, IconData icon) => Container(
        width: 36,
        height: canvasNavHeight,
        alignment: Alignment.center,
        child: Icon(icon, size: 17, color: theme.colors.onSurfaceVariant),
      );

  Widget _menu(ThemeNotifier theme) => PopupMenuButton<String>(
        key: const ValueKey("sidebarMenu"),
        tooltip: "The sidebars",
        padding: EdgeInsets.zero,
        child: _face(theme, Icons.more_horiz),
        itemBuilder: (context) => [
          _line("customise", "Customise sidebars…",
              key: const ValueKey("sidebarCustomise")),
          _line("customise", "Show hidden panels (${layout.hidden.length})",
              enabled: layout.hidden.isNotEmpty),
          const PopupMenuDivider(height: 8),
          if (widget.canSitAbove)
            for (var m in [SidebarMode.full, SidebarMode.above])
              _line(m.name, m.label, ticked: layout.mode == m),
          _line("hide", "Hide the sidebar"),
        ],
        onSelected: (v) => switch (v) {
          "customise" => widget.onCustomise(),
          "hide" => _set(layout.withMode(SidebarMode.hidden)),
          _ => _set(layout.withMode(SidebarMode.fromName(v))),
        },
      );

  /// _line is one line of the sidebar's menus, in the size the rest of the
  /// page's menus are: a tick before it where [ticked] says.
  PopupMenuItem<String> _line(String value, String text,
          {Key? key, bool enabled = true, bool? ticked}) =>
      PopupMenuItem<String>(
        key: key,
        value: value,
        enabled: enabled,
        height: 32,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (ticked != null)
            SizedBox(
                width: 22,
                child: ticked ? const Icon(Icons.check, size: 15) : null),
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5)),
          ),
        ]),
      );

  /// _column is sidebar [s]: its panels, and at its foot the panels that
  /// could go back in it.
  Widget _column(BuildContext context, SidebarSet s, bool showing) {
    var panels = [
      for (var id in s.panels)
        if (canvasSidebarPanel(
                id, controller, widget.bodies.body(id, showing: showing),
                menu: _panelMenu(id, s))
            case var panel?)
          panel
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: panels.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: CanvasHint("Nothing in this sidebar yet. Drop a panel's "
                    "heading on its icon, or put one in it from Customise "
                    "sidebars."),
              )
            : PanelStack(
                key: ValueKey("sidebarStack-${s.id}"),
                storageKey: "canvasSidebar-${s.id}",
                panels: panels),
      ),
    ]);
  }

  /// _panelMenu is the ⋯ on panel [id]'s heading, in sidebar [s].
  List<PanelAction> _panelMenu(String id, SidebarSet s) {
    var name = sidebarPanelLabel(id, controller);
    var hide = PanelAction(
        requiredPanels.contains(id)
            ? "$name stays: it cannot be hidden"
            : "Hide this panel",
        requiredPanels.contains(id) ? null : () => _set(layout.hidePanel(id)));
    if (s.fixed) return s.gameOnly ? const [] : [hide];
    return [
      for (var other in _shown)
        if (other.id != s.id && SidebarLayout.canGoIn(id, other))
          PanelAction("Move to ${other.name}",
              () => _set(layout.movePanel(id, other.id))),
      PanelAction(
          "A new sidebar of its own",
          layout.sidebars.length < maxSidebars
              ? () => _set(layout.addSidebar(name: name, panel: id))
              : null),
      hide,
    ];
  }
}

/// CanvasSidebarRestoreButton is what is left on the page once the sidebar is
/// hidden: the one visible way back, since a shortcut alone is undiscoverable.
class CanvasSidebarRestoreButton extends StatelessWidget {
  final VoidCallback onShow;
  const CanvasSidebarRestoreButton({required this.onShow, super.key});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: "Show the sidebar",
        child: InkWell(
          onTap: onShow,
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            width: 26,
            height: 26,
            // The same weight as the hide control, so the pair reads as one thing.
            child: Icon(Icons.chevron_right,
                size: 18,
                color: ThemeNotifier.of(context).colors.onSurfaceVariant),
          ),
        ),
      );
}
