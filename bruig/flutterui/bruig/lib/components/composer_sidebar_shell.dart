import 'package:bruig/models/composer_sidebar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// composer_sidebar_shell.dart is the row of icons at the top of a composer's
// sidebar, and whatever panel they choose between.
//
// The nav lives in the sidebar rather than on the page because that is where
// what it switches lives, and because a composer wants its page for writing.
// The buttons that used to sit under the editor -- Writing Tools, My Posts,
// Add Embed -- were three things competing with the text for the reader's
// attention, all of them about the tools rather than about the post.

/// ComposerSidebarShell wraps [child] with the panel nav.
class ComposerSidebarShell extends StatelessWidget {
  final ComposerSidebarController controller;

  /// panels is which of them to offer. A panel whose feature is unavailable
  /// -- the writing tools with no plugin enabled -- is left out rather than
  /// shown disabled, since there is nothing the user could do about it.
  final List<ComposerPanel> panels;

  /// child is the chosen panel's contents.
  final Widget child;

  const ComposerSidebarShell({
    required this.controller,
    required this.panels,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _nav(theme),
      const Divider(height: 1),
      Expanded(child: child),
    ]);
  }

  /// _nav is the panel icons, and the control that puts the sidebar away.
  ///
  /// The second is not one of the first. It does not choose a panel, and a
  /// control that read as a fifth panel invited the reading that it closed
  /// the panel it sat beside -- which is what it looked like it did. So it
  /// is set apart: pushed hard against the sidebar's outer edge, past a
  /// rule, larger than the icons, and squared off on the side it touches so
  /// it reads as part of the frame rather than as something in the list.
  Widget _nav(ThemeNotifier theme) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
        child: Row(children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [for (var panel in panels) _icon(theme, panel)],
            ),
          ),
          Container(
            width: 1,
            height: 20,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: theme.colors.outlineVariant,
          ),
          _hideButton(theme),
        ]),
      );

  Widget _hideButton(ThemeNotifier theme) => Tooltip(
        message: "Hide the sidebar",
        child: InkWell(
          onTap: controller.toggleMinimized,
          // Rounded away from the edge and square against it, so the shape
          // finishes where the sidebar does.
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(6),
            bottomLeft: Radius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 10, 7),
            child: Icon(
              Icons.chevron_left,
              size: 20,
              color: theme.colors.onSurfaceVariant,
            ),
          ),
        ),
      );

  Widget _icon(ThemeNotifier theme, ComposerPanel panel) => _button(
        theme,
        icon: panel.icon,
        tooltip: panel.label,
        selected: panel == controller.panel,
        onTap: () => controller.show(panel),
      );

  Widget _button(
    ThemeNotifier theme, {
    required IconData icon,
    required String tooltip,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: selected ? theme.colors.secondaryContainer : null,
            ),
            child: Icon(
              icon,
              size: 17,
              color: selected
                  ? theme.colors.onSecondaryContainer
                  : theme.colors.onSurfaceVariant,
            ),
          ),
        ),
      );
}

/// ComposerSidebarRestoreButton is what is left on the page once the sidebar
/// is hidden: the one control that brings it back.
///
/// It has to be somewhere, and somewhere predictable. A hidden sidebar with
/// no way back is a trap, and a keyboard shortcut alone is a trap for
/// everyone who does not know it.
class ComposerSidebarRestoreButton extends StatelessWidget {
  final ComposerSidebarController controller;
  const ComposerSidebarRestoreButton({required this.controller, super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        // The same weight as the control that hid it, so the pair reads as
        // one thing in two states rather than two unrelated buttons.
        icon: const Icon(Icons.chevron_right, size: 20),
        tooltip: "Show the sidebar",
        onPressed: controller.toggleMinimized,
      );
}
