import 'package:bruig/components/containers.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// canvas_sidebar.dart is which panel the sidebar beside the canvas is showing.
//
// The same arrangement as the writing composer's sidebar next door -- a row of
// icons over one panel -- because the two pages sit beside each other in the
// navigation and a reader who has used one should not have to work out the
// other. What differs is only the three panels.

/// CanvasPanel is the three things the sidebar can show.
enum CanvasPanel {
  files("Files", Icons.folder_outlined),
  presets("Presets", Icons.grid_view_outlined),

  /// design is what you add, what is already there, and the settings of
  /// whichever of it is selected -- three panels in one column rather than
  /// three tabs. Last, because it is the tab a document ends up on: the two
  /// before it are ways of starting, and this is where the rest of the work
  /// happens.
  design("Design", Icons.category_outlined);

  final String label;
  final IconData icon;
  const CanvasPanel(this.label, this.icon);
}

/// canvasNavHeight matches the composer's, so the two pages' sidebars line up
/// with each other and with the header rows beside them.
const double canvasNavHeight = 36;

/// CanvasSidebarShell wraps [child] with the panel nav.
class CanvasSidebarShell extends StatelessWidget {
  final CanvasPanel panel;
  final ValueChanged<CanvasPanel> onPanelChanged;
  final Widget child;

  /// onHide puts the sidebar away, leaving the canvas the whole width.
  ///
  /// The same control the Writing page has, in the same place and with the
  /// same shape, because it is the same thing: a canvas being looked at rather
  /// than built on wants the room, and a laptop screen has none to spare.
  final VoidCallback onHide;

  const CanvasSidebarShell({
    required this.panel,
    required this.onPanelChanged,
    required this.onHide,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var inDrawer = CollapsedSidebarScope.of(context);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(4, 4, inDrawer ? 4 : 0, 4),
        // Each icon takes an equal share of the row rather than being sized to
        // itself. Spaced apart, most of the row is gap that looks like part of
        // the control and does nothing when clicked.
        child: Row(children: [
          for (var p in CanvasPanel.values) Expanded(child: _icon(theme, p)),
          // In the collapsed drawer the sidebar is already an overlay you put
          // away by tapping off it, so a control of its own for hiding it is a
          // second route to the same place -- and its chevron points at an edge
          // that is not there.
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

  /// _hideButton is not one of the panel icons, and is set apart so it does
  /// not read as a fifth.
  ///
  /// Pushed against the sidebar's outer edge, past a rule, and squared off on
  /// the side it touches, so the shape finishes where the sidebar does. As a
  /// plain fifth icon it looked like it closed the panel beside it -- which is
  /// what people read it as on the Writing page before it was moved out.
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
/// hidden: the one control that brings it back.
///
/// It has to be somewhere, and somewhere predictable. A hidden sidebar with no
/// way back is a trap, and a keyboard shortcut alone is a trap for everyone
/// who does not know it.
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
            // The same weight as the control that hid it, so the pair reads as
            // one thing in two states rather than two unrelated buttons.
            child: Icon(Icons.chevron_right,
                size: 18,
                color: ThemeNotifier.of(context).colors.onSurfaceVariant),
          ),
        ),
      );
}
