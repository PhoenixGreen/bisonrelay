import 'package:flutter/material.dart';

import 'package:bruig/components/containers.dart';
import 'package:bruig/components/panel_stack.dart';
import 'package:bruig/plugin_system/canvas/model/sidebar_layout.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/sidebar_extras.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/sidebar_panels.dart';
import 'package:bruig/theming_system/theme_manager.dart';

// canvas_sidebar.dart is the Canvas sidebar: a row of icons, a sidebar each
// (sidebar_layout.dart), and the chosen one's panels in a panel stack, with
// the height toggle, menu and hide arrow. A panel's heading dropped on an
// icon moves it there; hidden panels return in customise_sidebars.dart.
// After the sidebars come any a feature has added (sidebar_extras.dart).

/// canvasNavHeight matches the composer's, so the pages' sidebars line up.
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

/// CanvasSidebar is the sidebar: the row of sidebars' icons, and under it
/// the panels of the one chosen. It holds nothing of how it is set out:
/// [layout] is the page's, and every change is asked for through
/// [onLayout].
class CanvasSidebar extends StatefulWidget {
  final CanvasController controller;
  final SidebarLayout layout;
  final ValueChanged<SidebarLayout> onLayout;

  /// onHide puts the sidebar away. Its own callback, not a layout whose
  /// mode is hidden: where it goes is the page's to say (a piece of sound's
  /// sidebar is put away for the visit, and the kept layout is not touched).
  final VoidCallback onHide;
  final SidebarPanelBodies bodies;

  final VoidCallback onCustomise;

  /// canSitAbove is whether it may sit above the bottom panels: not with
  /// the canvas away (an audio document's), where the panels fill the
  /// page and would leave the sidebar's column nothing.
  final bool canSitAbove;

  const CanvasSidebar({
    required this.controller,
    required this.layout,
    required this.onLayout,
    required this.onHide,
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
  /// hundred milliseconds); none is built before it is wanted.
  final Set<String> _seen = {};

  List<SidebarSet> get _shown => layout.shown(game: controller.document.game);

  SidebarSet get _current =>
      _shown.where((s) => s.id == layout.current).firstOrNull ?? _shown.first;

  /// _extra is the feature's sidebar shown instead of one of ours, if the
  /// current one is that and it is still there.
  CanvasSidebarExtra? get _extra => CanvasSidebarExtras.byId(layout.current);

  void _set(SidebarLayout next) => widget.onLayout(next);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge(
            [sidebarListenable(controller), CanvasSidebarExtras.changes]),
        builder: (context, _) {
          var theme = ThemeNotifier.of(context);
          var extra = _extra;
          var extras = CanvasSidebarExtras.shown;
          var current = _current;
          var currentId = extra?.id ?? current.id;
          _seen.add(currentId);
          var shown = _shown;
          // Squeezed to a sliver (the Chain filling the window, a panel
          // dragged over it), it shows nothing rather than spilling.
          return LayoutBuilder(builder: (context, box) {
            if (box.maxHeight < 60) return const SizedBox.shrink();
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(context, theme, shown, extras, currentId),
                  const Divider(height: 1),
                  Expanded(
                    child: RepaintBoundary(
                      child: Stack(children: [
                        for (var s in shown)
                          if (_seen.contains(s.id))
                            Offstage(
                              key: ValueKey("sidebar-${s.id}"),
                              offstage: s.id != currentId,
                              // Nothing hidden may animate: an offstage
                              // spinner would go on scheduling frames.
                              child: TickerMode(
                                enabled: s.id == currentId,
                                child: _column(context, s, s.id == currentId),
                              ),
                            ),
                        for (var x in extras)
                          if (_seen.contains(x.id))
                            Offstage(
                              key: ValueKey("sidebar-${x.id}"),
                              offstage: x.id != currentId,
                              child: TickerMode(
                                enabled: x.id == currentId,
                                child: x.build(context, controller),
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
      List<SidebarSet> shown, List<CanvasSidebarExtra> extras, String current) {
    var inDrawer = CollapsedSidebarScope.of(context);
    var colors = theme.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(4, 4, inDrawer ? 4 : 0, 4),
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (var s in shown) _icon(theme, s, s.id == current),
              for (var x in extras) _extraIcon(theme, x, x.id == current),
            ]),
          ),
        ),
        if (widget.canSitAbove) _modeToggle(theme),
        _menu(theme),
        // A drawer is put away by tapping off it; a chevron would mislead.
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
              onTap: widget.onHide,
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
      // A heading drags as its stack's id for it, which is the panel's name.
      onWillAcceptWithDetails: (d) =>
          switch (SidebarPanel.fromName(d.data.id)) {
        var panel? =>
          SidebarLayout.canGoIn(panel, s) && !s.panels.contains(panel),
        null => false,
      },
      onAcceptWithDetails: (d) {
        if (SidebarPanel.fromName(d.data.id) case var panel?) {
          _set(layout.movePanel(panel, s.id).copyWith(current: s.id));
        }
      },
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

  /// _extraIcon is a feature's sidebar's icon: pressed, it is shown. Nothing
  /// is dropped on it, since its column holds no panels of ours.
  Widget _extraIcon(ThemeNotifier theme, CanvasSidebarExtra x, bool selected) {
    var colors = theme.colors;
    return Tooltip(
      message: x.name,
      child: InkWell(
        key: ValueKey("sidebarTab-${x.id}"),
        onTap: () => _set(layout.copyWith(current: x.id)),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 36,
          height: canvasNavHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: selected ? colors.secondaryContainer : null,
          ),
          child: Icon(x.icon,
              size: 17,
              color: selected
                  ? colors.onSecondaryContainer
                  : colors.onSurfaceVariant),
        ),
      ),
    );
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
          "hide" => widget.onHide(),
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

  /// _column is sidebar [s]: its panels in a stack.
  Widget _column(BuildContext context, SidebarSet s, bool showing) {
    var panels = [
      for (var panel in s.panels)
        canvasSidebarPanel(
            panel, controller, widget.bodies.body(panel, showing: showing),
            menu: _panelMenu(panel, s))
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

  /// _panelMenu is the ⋯ on [panel]'s heading, in sidebar [s].
  List<PanelAction> _panelMenu(SidebarPanel panel, SidebarSet s) {
    var hide = PanelAction(
        panel.canHide
            ? "Hide this panel"
            : "${panel.title} stays: it cannot be hidden",
        panel.canHide ? () => _set(layout.hidePanel(panel)) : null);
    if (s.fixed) return s.gameOnly ? const [] : [hide];
    return [
      for (var other in _shown)
        if (other.id != s.id && SidebarLayout.canGoIn(panel, other))
          PanelAction("Move to ${other.name}",
              () => _set(layout.movePanel(panel, other.id))),
      PanelAction(
          "A new sidebar of its own",
          layout.sidebars.length < maxSidebars
              // Named for the panel, not for what its heading says now (the
              // settings are headed for whatever is selected).
              ? () => _set(layout.addSidebar(name: panel.title, panel: panel))
              : null),
      hide,
    ];
  }
}

/// CanvasSidebarRestoreButton is what is left once the sidebar is hidden:
/// the one visible way back, since a shortcut alone is undiscoverable.
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
            // The same weight as the hide control, so the pair reads as one.
            child: Icon(Icons.chevron_right,
                size: 18,
                color: ThemeNotifier.of(context).colors.onSurfaceVariant),
          ),
        ),
      );
}
