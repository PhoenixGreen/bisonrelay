import 'package:bruig/components/manage_bar.dart';
import 'package:bruig/models/menus.dart';
import 'package:flutter_test/flutter_test.dart';

// manage_bar_test.dart holds the Files section's two lists of tabs against
// each other.
//
// There are two, and only one of them is the sidebar. manageContentScreenSub
// names the tabs for the header -- "Files / Downloads" -- and
// manageContentBarItems is what somebody actually clicks. Adding a tab to
// the first alone gives it a name it can never be reached by, which is
// exactly what happened to Purchases: the screen was built, the tab was
// wired, and there was no way in.

void main() {
  test('every tab in the sub-menu is in the sidebar', () {
    var sidebar = manageContentBarItems((_) {}, 0);
    expect(sidebar, hasLength(manageContentScreenSub.length));

    for (var i = 0; i < manageContentScreenSub.length; i++) {
      expect(sidebar[i].label, manageContentScreenSub[i].label,
          reason: "tab $i is named differently in the two lists");
    }
  });

  test('the sidebar marks the tab it was given', () {
    for (var i = 0; i < manageContentScreenSub.length; i++) {
      var items = manageContentBarItems((_) {}, i);
      expect(items[i].selected, isTrue, reason: "tab $i");
      expect(items.where((e) => e.selected), hasLength(1), reason: "tab $i");
    }
  });

  test('each tab opens its own', () {
    var opened = <int>[];
    var items = manageContentBarItems(opened.add, 0);
    for (var item in items) {
      item.onTap();
    }
    expect(opened, [for (var i = 0; i < items.length; i++) i]);
  });
}
