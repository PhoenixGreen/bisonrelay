import 'package:bruig/components/containers.dart';
import 'package:bruig/models/resources.dart';
import 'package:bruig/screens/pages/browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:provider/provider.dart';

void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    required bool sidebarOpen,
    VoidCallback? onToggle,
    VoidCallback? onClose,
    bool toggleable = true,
    bool closeable = true,
  }) async {
    var session = PagesSession(1);
    await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>.value(
      value: ThemeNotifier(doLoad: false),
      child: MaterialApp(
          home: Scaffold(
              body: PageBrowserBar(
        session: session,
        nick: "alice",
        path: "index.md",
        loading: false,
        sidebarOpen: sidebarOpen,
        onToggleSidebar: toggleable ? (onToggle ?? () {}) : null,
        onClose: closeable ? (onClose ?? () {}) : null,
        onBack: () {},
        onForward: () {},
        onReload: () {},
        onHome: () {},
      ))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('close is an icon in the bar, not a labelled button',
      (tester) async {
    var closed = 0;
    await pumpBar(tester, sidebarOpen: false, onClose: () => closed++);

    // It used to sit above the bar as a TextButton.icon reading "Close
    // page". The words are now only the tooltip.
    expect(find.text("Close page"), findsNothing);
    expect(find.byTooltip("Close page"), findsOneWidget);

    await tester.tap(find.byTooltip("Close page"));
    await tester.pumpAndSettle();
    expect(closed, 1);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('the close button gives way to the tab strip', (tester) async {
    // With two or more pages open every tab carries its own close, so the
    // one in the bar would be a second way to shut the same page.
    await pumpBar(tester, sidebarOpen: false, closeable: false);

    expect(find.byTooltip("Close page"), findsNothing);
    // The rest of the bar is untouched.
    expect(find.byTooltip("Back"), findsOneWidget);
    expect(find.byTooltip("Reload"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the toggle is left out where it could not work', (tester) async {
    // Below the collapse width the sidebar belongs to the drawer, which only
    // the main navigation's re-tap opens. The toggle used to be drawn there
    // and did nothing when tapped.
    await pumpBar(tester, sidebarOpen: false, toggleable: false);

    expect(find.byTooltip("Show sidebar"), findsNothing);
    expect(find.byTooltip("Hide sidebar"), findsNothing);
    // Everything else still there -- close especially.
    expect(find.byTooltip("Close page"), findsOneWidget);
    expect(find.byTooltip("Back"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebarIsInDrawer agrees with the width the layout uses',
      (tester) async {
    late bool narrow, wide;
    await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>.value(
      value: ThemeNotifier(doLoad: false),
      child: MaterialApp(
          home: Builder(builder: (context) {
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
