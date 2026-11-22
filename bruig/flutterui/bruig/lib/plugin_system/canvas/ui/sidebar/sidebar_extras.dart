import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

// sidebar_extras.dart lets a feature outside Canvas give the Canvas sidebar a
// sidebar of its own: an icon in the row along the top and a column under it.
//
// The dependency runs one way. A feature that wants a sidebar here imports
// Canvas and registers one from its own start-up; Canvas never names it. A
// feature switched off says so through [CanvasSidebarExtra.shown], and its
// icon goes, leaving the sidebars exactly as they were without it.
//
// An extra is not part of the saved SidebarLayout: its panels cannot be
// moved into Design or hidden one at a time. It is one column, there while
// its feature is on.

/// CanvasSidebarExtra is one sidebar a feature adds.
class CanvasSidebarExtra {
  /// id names it in SidebarLayout.current while it is the one shown; it must
  /// not be the id of a built-in or custom sidebar.
  final String id;
  final String name;
  final IconData icon;

  /// shown is whether it is there now.
  final ValueListenable<bool> shown;

  /// build is its column, given the editing session.
  final Widget Function(BuildContext context, CanvasController controller)
      build;

  const CanvasSidebarExtra({
    required this.id,
    required this.name,
    required this.icon,
    required this.shown,
    required this.build,
  });
}

/// CanvasSidebarExtras holds the extras registered, in the order they were.
class CanvasSidebarExtras {
  CanvasSidebarExtras._();

  static List<CanvasSidebarExtra> _registered = const [];

  /// _changed tells of an extra registered, and of one coming or going.
  static final _Told _changed = _Told();

  /// forgetForTest takes every extra away, as a new run has none.
  @visibleForTesting
  static void forgetForTest() => _put(const []);

  /// register adds [extra], replacing one of the same id (a hot reload).
  static void register(CanvasSidebarExtra extra) => _put([
        for (var e in _registered)
          if (e.id != extra.id) e,
        extra,
      ]);

  /// _put makes [extras] the ones registered, listening to each for its
  /// coming and going, and tells of the change.
  static void _put(List<CanvasSidebarExtra> extras) {
    for (var e in _registered) {
      e.shown.removeListener(_changed.tell);
    }
    _registered = extras;
    for (var e in extras) {
      e.shown.addListener(_changed.tell);
    }
    _changed.tell();
  }

  /// shown are the extras there now.
  static List<CanvasSidebarExtra> get shown => [
        for (var e in _registered)
          if (e.shown.value) e
      ];

  /// byId is the extra [id] if it is there now.
  static CanvasSidebarExtra? byId(String id) =>
      shown.where((e) => e.id == id).firstOrNull;

  /// changes fires as an extra is registered, or comes or goes. The one
  /// listenable for as long as the app runs, so what listens to it hears
  /// of an extra registered after it began listening.
  static Listenable get changes => _changed;
}

/// _Told is a notifier told from outside.
class _Told extends ChangeNotifier {
  void tell() => notifyListeners();
}
