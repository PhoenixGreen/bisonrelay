import 'package:bruig/components/nav_bar_width.dart';
import 'package:bruig/storage_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sidebarx/sidebarx.dart';

// nav_bar_width_test.dart is the main navigation remembering whether it was
// left open or collapsed.
//
// It was open on every start whatever it had been left at, so somebody who
// works with it collapsed began each session by collapsing it again.

SidebarXController _nav({bool extended = true}) =>
    SidebarXController(selectedIndex: 0, extended: extended);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test("a nav bar nobody has touched opens wide", () async {
    var ctrl = _nav();
    var width = NavBarWidth(ctrl);
    await width.restore();
    expect(ctrl.extended, isTrue);
    width.dispose();
  });

  test("collapsing it is remembered, and put back next time", () async {
    var ctrl = _nav();
    var width = NavBarWidth(ctrl);
    await width.restore();

    ctrl.toggleExtended();
    expect(ctrl.extended, isFalse);
    // Written straight away rather than on the way out: the app is closed
    // from the window's own button, and a State that is disposed on the way
    // down is not a promise anybody should rely on.
    await Future<void>.delayed(Duration.zero);
    expect(
        await StorageManager.readBool(StorageManager.navExtendedKey,
            defaultVal: true),
        isFalse);
    width.dispose();

    // The next run of the app: a fresh controller, opening wide as it always
    // does, put back the way it was left.
    var next = _nav();
    var later = NavBarWidth(next);
    expect(next.extended, isTrue, reason: "it starts wide before it is told");
    await later.restore();
    expect(next.extended, isFalse, reason: "it did not come back collapsed");
    later.dispose();
  });

  test("opening it again is remembered too", () async {
    SharedPreferences.setMockInitialValues(
        {"flutter.${StorageManager.navExtendedKey}": false});
    var ctrl = _nav();
    var width = NavBarWidth(ctrl);
    await width.restore();
    expect(ctrl.extended, isFalse);

    ctrl.setExtended(true);
    await Future<void>.delayed(Duration.zero);
    expect(
        await StorageManager.readBool(StorageManager.navExtendedKey,
            defaultVal: false),
        isTrue);
    width.dispose();
  });

  test("choosing a row says nothing about the width", () async {
    // The controller notifies for its selected row as well, and a width
    // written on every one of those is a write per click.
    var ctrl = _nav(extended: false);
    var width = NavBarWidth(ctrl);
    await width.restore();
    expect(ctrl.extended, isTrue, reason: "restored to the default");

    await StorageManager.deleteData(StorageManager.navExtendedKey);
    ctrl.selectIndex(3);
    await Future<void>.delayed(Duration.zero);
    expect(await StorageManager.exists(StorageManager.navExtendedKey), isFalse,
        reason: "picking a row wrote the width down again");
    width.dispose();
  });

  test("and it lets go when the bar does", () async {
    var ctrl = _nav();
    var width = NavBarWidth(ctrl);
    await width.restore();
    width.dispose();

    await StorageManager.deleteData(StorageManager.navExtendedKey);
    ctrl.toggleExtended();
    await Future<void>.delayed(Duration.zero);
    expect(await StorageManager.exists(StorageManager.navExtendedKey), isFalse,
        reason: "it went on writing after it was disposed of");
  });
}
