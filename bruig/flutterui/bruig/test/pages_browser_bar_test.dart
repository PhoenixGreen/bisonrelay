import 'package:bruig/components/containers.dart';
import 'package:bruig/components/pages_bar.dart';
import 'package:bruig/models/resources.dart';
import 'package:bruig/screens/pages/browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:provider/provider.dart';

// byTooltip finds the Tooltip an IconButton builds, not the button itself,
// so the button is reached through it.
IconButton _button(WidgetTester tester, String tooltip) =>
    tester.widget<IconButton>(find.ancestor(
        of: find.byTooltip(tooltip), matching: find.byType(IconButton)));

void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    required bool sidebarOpen,
    VoidCallback? onToggle,
    bool toggleable = true,
    bool withPage = true,
    int section = -1,
    void Function(int)? onSection,
  }) async {
    var session = withPage ? PagesSession(1) : null;
    await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>.value(
      value: ThemeNotifier(doLoad: false),
      child: MaterialApp(
          home: Scaffold(
              body: PageBrowserBar(
        session: session,
        sectionLabel: "Site Settings",
        section: section,
        onSection: onSection,
        nick: "alice",
        path: "index.md",
        loading: false,
        sidebarOpen: sidebarOpen,
        onToggleSidebar: toggleable ? (onToggle ?? () {}) : null,
        onBack: () {},
        onForward: () {},
        onReload: () {},
        onHome: () {},
      ))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the sidebar toggle fires and says which way it goes',
      (tester) async {
    var toggled = 0;
    await pumpBar(tester, sidebarOpen: false, onToggle: () => toggled++);

    expect(find.byTooltip("Show sidebar"), findsOneWidget);
    await tester.tap(find.byTooltip("Show sidebar"));
    await tester.pumpAndSettle();
    expect(toggled, 1);
    expect(tester.takeException(), isNull);

    // Open, it offers the opposite -- a toggle whose label never changes
    // gives the reader no idea what it will do.
    await pumpBar(tester, sidebarOpen: true);
    expect(find.byTooltip("Hide sidebar"), findsOneWidget);
    expect(find.byTooltip("Show sidebar"), findsNothing);
  });

  testWidgets('the bar is drawn on a section with no page open',
      (tester) async {
    // It carries the sidebar toggle, so a bar that appeared only while
    // reading a page would leave the sidebar shut with no way to reopen it.
    await pumpBar(tester, sidebarOpen: true, withPage: false);

    expect(find.byTooltip("Hide sidebar"), findsOneWidget);
    // The address area names the section instead of a page.
    expect(find.text("Site Settings"), findsOneWidget);
    expect(find.textContaining("alice"), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('navigation greys out with no page rather than moving',
      (tester) async {
    // The buttons keep their places across sections: controls that shift as
    // you cross the section are harder to aim at than controls that grey.
    await pumpBar(tester, sidebarOpen: true, withPage: false);

    for (var t in ["Back", "Forward", "Front page", "Reload"]) {
      expect(find.byTooltip(t), findsOneWidget, reason: t);
      expect(_button(tester, t).onPressed, isNull, reason: t);
    }
  });

  testWidgets('the bar reaches every section, which the sidebar may not',
      (tester) async {
    // The sidebar is the usual way to these and can be shut, so without
    // them here hiding it would put all three out of reach. Visit included:
    // the strip's new-tab button used to cover it, but the strip only
    // exists once a page is open.
    var went = <int>[];
    await pumpBar(tester,
        sidebarOpen: false, withPage: false, onSection: went.add);

    for (var t in ["Visit", "Site Settings", "Store"]) {
      expect(find.byTooltip(t), findsOneWidget, reason: t);
    }

    await tester.tap(find.byTooltip("Store"));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Visit"));
    await tester.pumpAndSettle();
    expect(went, [pagesTabStore, pagesTabVisit]);
  });

  testWidgets('the toggle is left out where it could not work', (tester) async {
    // Below the collapse width the sidebar belongs to the drawer, which only
    // the main navigation's re-tap opens. The toggle used to be drawn there
    // and did nothing when tapped.
    await pumpBar(tester, sidebarOpen: false, toggleable: false);

    expect(find.byTooltip("Show sidebar"), findsNothing);
    expect(find.byTooltip("Hide sidebar"), findsNothing);
    // Everything else still there.
    expect(find.byTooltip("Back"), findsOneWidget);
    expect(find.byTooltip("Reload"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebarIsInDrawer agrees with the width the layout uses',
      (tester) async {
    late bool narrow, wide;
    await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>.value(
      value: ThemeNotifier(doLoad: false),
      child: MaterialApp(home: Builder(builder: (context) {
        narrow = sidebarIsInDrawer(context, kSidebarCollapseWidth - 1);
        wide = sidebarIsInDrawer(context, kSidebarCollapseWidth);
        return const SizedBox();
      })),
    ));

    // The layout branches on "< kSidebarCollapseWidth", so the boundary
    // itself is still wide enough for a column. Getting this off by one
    // would put a dead toggle back at exactly one width.
    expect(narrow, isTrue);
    expect(wide, isFalse);
  });

  testWidgets('the bar lays out without overflowing a narrow window',
      (tester) async {
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpBar(tester, sidebarOpen: false);
    expect(tester.takeException(), isNull);
  });
}
