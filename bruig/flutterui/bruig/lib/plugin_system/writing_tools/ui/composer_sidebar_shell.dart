import 'package:bruig/components/containers.dart';
import 'package:bruig/plugin_system/writing_tools/composer_sidebar.dart';
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

/// composerNavHeight is what every control in the nav row stands at, and what
/// the composer's own header row matches so the two read as one band across
/// the top of the screen rather than as two rows that nearly line up.
///
/// Below
/// about this, a pointer that moves a few pixels between press and release
/// -- which is most trackpad clicks -- starts landing outside the thing it
/// was aimed at.
const double composerNavHeight = 36;

/// ComposerViewToggle chooses between the source of a post and the rendering
/// of it -- the Raw/Preview pair on the Writing page's top bar.
///
/// Two buttons rather than a switch, because neither state is the "on" one --
/// raw and preview are both ways of looking at the post, and a switch would
/// have to be labelled with only one of them.
///
/// On the writing area rather than in the sidebar, where it started. It is
/// about the post rather than about the panel beside it, and reaching across
/// the screen to a panel that might not even be open is a long way to go to
/// glance at what you have written.
class ComposerViewToggle extends StatelessWidget {
  final ComposerSidebarController controller;
  const ComposerViewToggle({required this.controller, super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => SegmentedButton<bool>(
          // Icons alone. The words were half the width of the title row for
          // a choice made with one glance, and the tooltips say what they
          // are for anyone who has not met them before.
          segments: const [
            ButtonSegment(
                value: false, icon: Icon(Icons.code, size: 16), tooltip: "Raw"),
            ButtonSegment(
                value: true,
                icon: Icon(Icons.visibility_outlined, size: 16),
                tooltip: "Preview"),
          ],
          selected: {controller.preview},
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding:
                WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
          ),
          onSelectionChanged: (chosen) => controller.preview = chosen.first,
        ),
      );
}

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
    // In the collapsed drawer the sidebar is already an overlay you put away
    // by tapping off it, so a control of its own for hiding it is a second
    // route to the same place -- and its chevron points at an edge that is
    // not there.
    var inDrawer = CollapsedSidebarScope.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _nav(theme, inDrawer),
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
  Widget _nav(ThemeNotifier theme, bool inDrawer) => Padding(
        padding: EdgeInsets.fromLTRB(4, 4, inDrawer ? 4 : 0, 4),
        child: Row(children: [
          // Each icon takes an equal share of the row, rather than being
          // sized to itself and spaced apart. Spaced apart, most of the row
          // was gap: four 35px icons across 280px left roughly 140px that
          // looked like part of the control and did nothing when clicked, so
          // aiming slightly wide missed entirely and clicking "took a few
          // tries".
          for (var panel in panels) Expanded(child: _icon(theme, panel)),
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
          child: Container(
            height: composerNavHeight,
            alignment: Alignment.center,
            padding: const EdgeInsets.fromLTRB(8, 0, 10, 0),
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
            // A height rather than padding: the row is what is being aimed
            // at, and a target the size of the glyph inside it is a target
            // you can miss while pointing straight at the button.
            height: composerNavHeight,
            alignment: Alignment.center,
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
