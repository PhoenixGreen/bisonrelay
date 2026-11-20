import 'package:bruig/plugin_system/writing_tools/composer_sidebar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// composer_sidebar_extras.dart lets a feature outside the writing tools add
// to the Writing page: a panel of its own in the sidebar, after Library,
// Writing Tools and Formatting, and entries on the right-click menu of the
// text.
//
// The dependency runs one way, as it does for Canvas (see
// canvas/ui/sidebar/sidebar_extras.dart): the feature imports this module
// and registers from its own start-up, and nothing here names it. Switched
// off, it says so through [ComposerSidebarExtra.shown] and its icon goes.

/// ComposerSidebarExtra is one panel a feature adds to the Writing sidebar.
class ComposerSidebarExtra {
  final String id;
  final String label;
  final IconData icon;

  /// shown is whether it is there now.
  final ValueListenable<bool> shown;

  /// build is the panel, given the sidebar's controller (which holds the
  /// text being written).
  final Widget Function(
      BuildContext context, ComposerSidebarController controller) build;

  const ComposerSidebarExtra({
    required this.id,
    required this.label,
    required this.icon,
    required this.shown,
    required this.build,
  });
}

/// WritingContextMenuItems is what a feature adds to the right-click menu
/// of the text: given the field, the entries to show (none when it has
/// nothing to offer there).
typedef WritingContextMenuItems = List<ContextMenuButtonItem> Function(
    BuildContext context, EditableTextState field);

/// ComposerSidebarExtras holds what features have registered.
class ComposerSidebarExtras {
  ComposerSidebarExtras._();

  static final ValueNotifier<List<ComposerSidebarExtra>> _panels =
      ValueNotifier(const []);
  static final Map<String, WritingContextMenuItems> _menus = {};

  /// register adds [extra], replacing one of the same id (a hot reload).
  static void register(ComposerSidebarExtra extra) {
    _panels.value = [
      for (var e in _panels.value)
        if (e.id != extra.id) e,
      extra,
    ];
  }

  /// registerMenu adds [items] to the text's right-click menu under [name].
  static void registerMenu(String name, WritingContextMenuItems items) =>
      _menus[name] = items;

  /// shown are the panels there now.
  static List<ComposerSidebarExtra> get shown => [
        for (var e in _panels.value)
          if (e.shown.value) e
      ];

  static ComposerSidebarExtra? byId(String? id) =>
      id == null ? null : shown.where((e) => e.id == id).firstOrNull;

  /// menuItems are every feature's entries for [field].
  static List<ContextMenuButtonItem> menuItems(
          BuildContext context, EditableTextState field) =>
      [for (var items in _menus.values) ...items(context, field)];

  /// changes fires as a panel is registered, or comes or goes.
  static Listenable get changes =>
      Listenable.merge([_panels, for (var e in _panels.value) e.shown]);
}
