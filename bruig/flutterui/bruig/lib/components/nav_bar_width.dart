import 'package:bruig/storage_manager.dart';
import 'package:sidebarx/sidebarx.dart';

// nav_bar_width.dart remembers whether the main navigation is open or
// collapsed.
//
// It was open on every start, whatever it had been left at, so somebody who
// works with it collapsed began each session by collapsing it again.
//
// The awkward part is *when* it is put back rather than whether. SidebarX
// animates between its two widths by listening to the controller's stream --
// and its listener ignores what the stream says, flipping its animation on
// every event:
//
//   extendStream.listen((extended) {
//     if (animation.isCompleted) animation.reverse(); else animation.forward();
//   });
//
// So an event that arrives while that animation is still running flips it the
// wrong way, and the bar is then wide with its labels hidden and its icons
// centred until something rebuilds it -- which is what changing the theme
// did. Reading the setting takes a turn of the event loop, which lands in
// exactly that window.
//
// The answer is not to tell the bar anything after it has been built: the
// width is read once, at startup, and the controller is *created* with it.

/// navBarStartsWide is whether the main navigation opens at its full width.
///
/// Read once at startup -- see loadNavBarWidth -- so that the controller can
/// be built with the right answer rather than told the answer afterwards.
bool navBarStartsWide = true;

/// loadNavBarWidth reads it off the disk. Called from main() before the app
/// is built.
Future<void> loadNavBarWidth() async {
  navBarStartsWide = await StorageManager.readBool(
      StorageManager.navExtendedKey,
      defaultVal: true);
}

/// NavBarWidth writes the width down whenever it changes.
class NavBarWidth {
  final SidebarXController controller;

  /// _written is what was last saved. The controller notifies for its
  /// selected row as well as its width, and most of those notifications say
  /// nothing new about the width.
  bool _written;

  NavBarWidth(this.controller) : _written = controller.extended {
    controller.addListener(_remember);
  }

  /// _remember writes it down again whenever it changes -- by the arrow at
  /// the foot of the bar, or by a window narrow enough that the bar collapses
  /// itself.
  ///
  /// Written when it changes rather than on the way out: the app is closed
  /// from the window's own button, and a State disposed on the way down is
  /// not a promise anybody should rely on.
  void _remember() {
    if (_written == controller.extended) return;
    _written = controller.extended;
    StorageManager.saveBool(StorageManager.navExtendedKey, controller.extended);
  }

  void dispose() => controller.removeListener(_remember);
}
