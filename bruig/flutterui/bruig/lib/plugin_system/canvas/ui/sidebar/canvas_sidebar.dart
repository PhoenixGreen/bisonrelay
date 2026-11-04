import 'package:bruig/components/containers.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// canvas_sidebar.dart is the panel nav beside the canvas: a row of icons over
// one panel, laid out like the writing composer's sidebar so the two pages
// read the same.

/// CanvasPanel is the panels the sidebar can show. New values go last, so a
/// saved choice keeps pointing at the same tab.
enum CanvasPanel {
  files("Files", Icons.folder_outlined),
  presets("Presets", Icons.grid_view_outlined),

  /// design is what can be added, what is already there, and the settings of
  /// the selection, in one column.
  design("Design", Icons.category_outlined),

  /// assets is the library of added pictures, videos and sounds.
  assets("Assets", Icons.perm_media_outlined),

  /// game is each element's game behaviour and the game's own settings; shown
  /// only while CanvasDocument.game is on.
  game("Game", Icons.sports_esports_outlined);

  final String label;
  final IconData icon;
  const CanvasPanel(this.label, this.icon);
}

/// canvasNavHeight matches the composer's, so the two pages' sidebars line up.
const double canvasNavHeight = 36;

/// CanvasSidebarShell wraps [child] with the panel nav.
class CanvasSidebarShell extends StatelessWidget {
  final CanvasPanel panel;
  final ValueChanged<CanvasPanel> onPanelChanged;
  final Widget child;

  /// panels are the tabs there are: Game only for a game.
  final List<CanvasPanel> panels;

  /// onHide puts the sidebar away, leaving the canvas the whole width, like the
  /// Writing page's control in the same place.
  final VoidCallback onHide;

  const CanvasSidebarShell({
    required this.panel,
    required this.onPanelChanged,
    required this.onHide,
    required this.child,
    this.panels = CanvasPanel.values,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var inDrawer = CollapsedSidebarScope.of(context);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(4, 4, inDrawer ? 4 : 0, 4),
        // Equal shares of the row, so the whole row is clickable rather than
        // gaps between icons.
        child: Row(children: [
          for (var p in panels) Expanded(child: _icon(theme, p)),
          // A drawer is already put away by tapping off it, and the chevron
          // would point at an edge that is not there.
          if (!inDrawer) ...[
            Container(
              width: 1,
              height: 20,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: theme.colors.outlineVariant,
            ),
            _hideButton(theme),
          ],
        ]),
      ),
      const Divider(height: 1),
      Expanded(child: child),
    ]);
  }

  /// _hideButton sits past a rule against the sidebar's outer edge, squared off
  /// on that side, so it does not read as a further panel icon that closes the
  /// panel beside it.
  Widget _hideButton(ThemeNotifier theme) => Tooltip(
        message: "Hide the sidebar",
        child: InkWell(
          onTap: onHide,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(6),
            bottomLeft: Radius.circular(6),
          ),
          child: Container(
            height: canvasNavHeight,
            alignment: Alignment.center,
            padding: const EdgeInsets.fromLTRB(8, 0, 10, 0),
            child: Icon(Icons.chevron_left,
                size: 20, color: theme.colors.onSurfaceVariant),
          ),
        ),
      );

  Widget _icon(ThemeNotifier theme, CanvasPanel p) {
    var selected = p == panel;
    return Tooltip(
      message: p.label,
      child: InkWell(
        onTap: () => onPanelChanged(p),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: canvasNavHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: selected ? theme.colors.secondaryContainer : null,
          ),
          child: Icon(
            p.icon,
            size: 17,
            color: selected
                ? theme.colors.onSecondaryContainer
                : theme.colors.onSurfaceVariant,
          ),
        ),
      ),
    );
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
