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

  Widget _nav(ThemeNotifier theme) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (var panel in panels) _icon(theme, panel),
            // Last and set apart: it does not choose a panel, it puts the
            // whole sidebar away.
            _button(
              theme,
              icon: Icons.chevron_left,
              tooltip: "Hide the sidebar",
              selected: false,
              onTap: controller.toggleMinimized,
            ),
          ],
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
        icon: const Icon(Icons.chevron_right, size: 18),
        tooltip: "Show the sidebar",
        onPressed: controller.toggleMinimized,
      );
}
