import 'package:bruig/storage_manager.dart';
import 'package:sidebarx/sidebarx.dart';

// nav_bar_width.dart remembers whether the main navigation is open or
// collapsed.
//
// It was open on every start, whatever it had been left at, so somebody who
// works with it collapsed began each session by collapsing it again. There is
// nothing else to the setting: it is one bool, and the only reason it is a
// class rather than two lines in the sidebar's State is that a bool written
// on every notification and read back at the wrong moment is exactly the sort
// of thing that quietly stops working.

/// NavBarWidth keeps a [SidebarXController]'s width in step with what was
/// last left on disk.
class NavBarWidth {
  final SidebarXController controller;

  /// _writing guards the listener while the saved width is being put back,
  /// so restoring it does not write it out again.
  bool _writing = false;

  /// _written is what was last saved. The controller notifies for its
  /// selected row as well as its width, and most of those notifications say
  /// nothing new about the width.
  bool? _written;

  NavBarWidth(this.controller) {
    controller.addListener(_remember);
  }

  /// restore puts the bar back the width it was left at. Open unless
  /// something says otherwise: a nav bar nobody has touched should look like
  /// the one in the screenshots.
  Future<void> restore() async {
    var wide = await StorageManager.readBool(StorageManager.navExtendedKey,
        defaultVal: true);
    _written = wide;
    if (wide == controller.extended) return;
    _writing = true;
    controller.setExtended(wide);
    _writing = false;
  }

  /// _remember writes it down again whenever it changes -- by the arrow at
  /// the foot of the bar, or by a window narrow enough that the bar collapses
  /// itself.
  void _remember() {
    if (_writing || _written == controller.extended) return;
    _written = controller.extended;
    StorageManager.saveBool(StorageManager.navExtendedKey, controller.extended);
  }

  void dispose() => controller.removeListener(_remember);
}
