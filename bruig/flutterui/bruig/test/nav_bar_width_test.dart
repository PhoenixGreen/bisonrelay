import 'package:bruig/components/nav_bar_width.dart';
import 'package:bruig/storage_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sidebarx/sidebarx.dart';

// nav_bar_width_test.dart is the main navigation remembering whether it was
// left open or collapsed.
//
// It was open on every start whatever it had been left at, so somebody who
// works with it collapsed began each session by collapsing it again.
//
// The width has to be known *before* the bar is built rather than set on it
// afterwards: SidebarX animates between its widths by listening to the
// controller's stream, and its listener ignores what the stream says --
// flipping its animation on every event. An event arriving while that
// animation is still running flips it the wrong way, and the bar is left
// wide with its labels hidden and its icons centred until something rebuilds
// it. That is what these tests are really guarding.

SidebarXController _nav({required bool extended}) =>
    SidebarXController(selectedIndex: 0, extended: extended);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    navBarStartsWide = true;
  });

  test("a nav bar nobody has touched opens wide", () async {
    await loadNavBarWidth();
    expect(navBarStartsWide, isTrue);
  });

  test("collapsing it is remembered, and read back before the bar is built",
      () async {
    await loadNavBarWidth();
    var ctrl = _nav(extended: navBarStartsWide);
    var width = NavBarWidth(ctrl);

    ctrl.toggleExtended();
    expect(ctrl.extended, isFalse);
    await Future<void>.delayed(Duration.zero);
    width.dispose();

    // The next run of the app: the width is known before anything is built,
    // so the controller is created with it and the bar is never told to
    // change.
    navBarStartsWide = true;
    await loadNavBarWidth();
    expect(navBarStartsWide, isFalse, reason: "it did not come back collapsed");
    expect(_nav(extended: navBarStartsWide).extended, isFalse);
  });

  test("opening it again is remembered too", () async {
    SharedPreferences.setMockInitialValues(
        {"flutter.${StorageManager.navExtendedKey}": false});
    await loadNavBarWidth();
    expect(navBarStartsWide, isFalse);

    var ctrl = _nav(extended: navBarStartsWide);
    var width = NavBarWidth(ctrl);
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
    var ctrl = _nav(extended: true);
    var width = NavBarWidth(ctrl);

    await StorageManager.deleteData(StorageManager.navExtendedKey);
    ctrl.selectIndex(3);
    await Future<void>.delayed(Duration.zero);
    expect(await StorageManager.exists(StorageManager.navExtendedKey), isFalse,
        reason: "picking a row wrote the width down again");
    width.dispose();
  });

  test("and it lets go when the bar does", () async {
    var ctrl = _nav(extended: true);
    var width = NavBarWidth(ctrl);
    width.dispose();

    await StorageManager.deleteData(StorageManager.navExtendedKey);
    ctrl.toggleExtended();
    await Future<void>.delayed(Duration.zero);
    expect(await StorageManager.exists(StorageManager.navExtendedKey), isFalse,
        reason: "it went on writing after it was disposed of");
  });

  // The bar itself, built the way the sidebar builds it.
  Widget bar(SidebarXController ctrl) => MaterialApp(
        home: Scaffold(
          body: SidebarX(
            controller: ctrl,
            theme: const SidebarXTheme(width: 70),
            extendedTheme: const SidebarXTheme(width: 200),
            items: const [
              SidebarXItem(icon: Icons.home, label: "Chats"),
              SidebarXItem(icon: Icons.feed, label: "Feed"),
            ],
          ),
        ),
      );

  /// _labelShowing is whether the row labels are visible, which is what the
  /// bar's own animation decides -- and what goes out of step with the
  /// controller when the bar is told its width after it has been built.
  bool labelShowing(WidgetTester tester) => tester
      .widgetList<FadeTransition>(find.ancestor(
          of: find.text("Chats"), matching: find.byType(FadeTransition)))
      .every((f) => f.opacity.value > 0.5);

  testWidgets("built at the width it was left at, the bar is in step",
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {"flutter.${StorageManager.navExtendedKey}": false});
    await loadNavBarWidth();

    var ctrl = _nav(extended: navBarStartsWide);
    await tester.pumpWidget(bar(ctrl));
    await tester.pumpAndSettle();
    expect(labelShowing(tester), isFalse,
        reason: "built collapsed, and showing its labels anyway");

    // And the arrow at the foot of it still works from there.
    ctrl.toggleExtended();
    await tester.pumpAndSettle();
    expect(labelShowing(tester), isTrue,
        reason: "opened, and still hiding its labels");
  });

  testWidgets("told its width after it is built, the bar goes out of step",
      (tester) async {
    // Why the width is read at startup rather than applied afterwards.
    // SidebarX listens to the controller's stream and flips its animation on
    // every event without looking at what the event says:
    //
    //   if (animation.isCompleted) animation.reverse(); else animation.forward();
    //
    // An event arriving while the opening animation is still running flips it
    // the wrong way, and from then on the bar's labels are the opposite of
    // what the controller says -- wide with its labels hidden and its icons
    // centred, until something rebuilds it. Changing the theme did.
    var ctrl = _nav(extended: true);
    await tester.pumpWidget(bar(ctrl));
    await tester.pump(const Duration(milliseconds: 10));

    ctrl.setExtended(false);
    await tester.pumpAndSettle();

    expect(ctrl.extended, isFalse);
    expect(labelShowing(tester), isTrue,
        reason: "the package has been fixed -- the width could be applied "
            "after the bar is built again, and loadNavBarWidth could go");
  });
}
