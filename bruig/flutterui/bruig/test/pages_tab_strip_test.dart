import 'package:bruig/components/pages_bar.dart';
import 'package:bruig/screens/pages/browser.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// pages_tab_strip_test.dart covers how open pages are presented: a single
// page keeps the plain close button in the address bar and gains no chrome,
// and two or more get a strip of tabs the way a browser does it.

List<PageTab> _tabs(int n, {int current = 0, void Function(int)? onClose}) => [
      for (var i = 0; i < n; i++)
        PageTab(
          label: "page$i",
          current: i == current,
          onOpen: () {},
          onClose: () => onClose?.call(i),
        ),
    ];

Widget _host(Widget child, {double width = 800}) =>
    ChangeNotifierProvider<ThemeNotifier>(
      create: (c) => ThemeNotifier(doLoad: false),
      child: MaterialApp(
        home: Scaffold(body: SizedBox(width: width, child: child)),
      ),
    );

void main() {
  group('the strip', () {
    testWidgets('draws a tab per open page, each with its own close',
        (tester) async {
      await tester.pumpWidget(_host(PageTabStrip(tabs: _tabs(3))));
      await tester.pump();

      expect(find.text("page0"), findsOneWidget);
      expect(find.text("page2"), findsOneWidget);
      expect(find.byTooltip("Close page1"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tab closes only itself', (tester) async {
      var closed = <int>[];
      await tester.pumpWidget(
          _host(PageTabStrip(tabs: _tabs(3, onClose: closed.add))));
      await tester.pump();

      await tester.tap(find.byTooltip("Close page1"));
      await tester.pump();
      expect(closed, [1]);
    });

    testWidgets('the new-tab button reaches the contact list', (tester) async {
      // The list is where a page is started from, so with one open there
      // has to be a way back to it that is not closing the page. That is
      // what this button is, and why the strip shows at one tab and not
      // only at two.
      var opened = 0;
      await tester.pumpWidget(_host(PageTabStrip(
          tabs: _tabs(1), onNewTab: () => opened++, newTabSelected: false)));
      await tester.pump();

      await tester.tap(find.byTooltip("Visit another site"));
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets('the close sits before the label, not after it',
        (tester) async {
      // On the right it lands beside the next tab's label, where a reader
      // aiming for that tab can shut this one by mistake -- and there is no
      // undo for a closed page.
      await tester.pumpWidget(_host(PageTabStrip(tabs: _tabs(2))));
      await tester.pump();

      var close = tester.getCenter(find.byTooltip("Close page0"));
      var label = tester.getCenter(find.text("page0"));
      expect(close.dx, lessThan(label.dx));
    });

    testWidgets('many tabs scroll rather than overflowing', (tester) async {
      // A long page name must not be able to push the others off, and eight
      // open pages must not overflow a narrow window.
      await tester.pumpWidget(_host(
          PageTabStrip(tabs: _tabs(8)), width: 400));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
