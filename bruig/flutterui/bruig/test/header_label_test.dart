import 'package:bruig/models/menus.dart';
import 'package:bruig/screens/address_book_screen.dart';
import 'package:bruig/screens/feed.dart';
import 'package:bruig/screens/ln_management.dart';
import 'package:bruig/screens/manage_content_screen.dart';
import 'package:bruig/screens/viewpage_screen.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// header_label_test.dart renders the page headings themselves, rather than
// asking MainMenuModel what they ought to say.
//
// menu_icons_test.dart already covers headerLabel, and it passed while the
// Chat heading went on saying "Chat" after the item had been renamed -- the
// heading is built from a hardcoded string at its own call site, and a test
// of the model can't see that. Only rendering the widget can.
//
// The Chat, Realtime Chat and Settings headings are not here: they read
// ClientModel/RealtimeChatModel, whose construction loads golib.dylib, which
// a unit test has no way to provide (see composer_resume_test.dart). Their
// call sites were fixed by hand and checked in the running app.
//
// SecondarySideMenuLayout is out of reach for the same reason -- it resolves
// a ClientModel to hand its sidebar to the collapsed drawer -- so the file
// preview's collapseSidebar is checked in the app rather than here.

Widget _host(Widget title, MainMenuModel menu) => MultiProvider(
      providers: [
        ChangeNotifierProvider<MainMenuModel>.value(value: menu),
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
      ],
      child: MaterialApp(home: Scaffold(body: title)),
    );

/// _titles are the headings that can be built without a running client, each
/// with the route it belongs to and the name it shows when untouched.
final _titles = <String, (Widget, String, String)>{
  'Feed': (const FeedScreenTitle(), FeedScreen.routeName, 'Feed'),
  // "LN", not the menu's longer "LN Management" -- the heading has always
  // been the short form.
  'LN': (const LNScreenTitle(), LNScreen.routeName, 'LN'),
  'Manage Content': (
    const ManageContentScreenTitle(),
    ManageContentScreen.routeName,
    'Manage Content'
  ),
  'Pages': (const ViewPagesScreenTitle(), ViewPageScreen.routeName, 'Pages'),
  'Address Book': (
    const AddressBookScreenTitle(),
    AddressBookScreen.routeName,
    'Address Book'
  ),
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  _titles.forEach((name, spec) {
    var (widget, route, builtIn) = spec;

    testWidgets('$name keeps its own heading until it is renamed',
        (tester) async {
      await tester.pumpWidget(_host(widget, MainMenuModel()));
      expect(find.textContaining(builtIn), findsOneWidget);
    });

    testWidgets('$name follows a rename', (tester) async {
      // A name sharing nothing with the built-in one, so the assertion
      // below really does prove the old name is gone.
      var menu = MainMenuModel()..renameItem(route, 'Zephyr');
      await tester.pumpWidget(_host(widget, menu));

      expect(find.textContaining('Zephyr'), findsOneWidget);
      // The old name is gone rather than sitting alongside the new one --
      // a heading built by pasting a hardcoded name in front of the
      // sub-page would still show it.
      expect(find.textContaining(builtIn), findsNothing);
    });

    testWidgets('$name updates live when the rename happens', (tester) async {
      var menu = MainMenuModel();
      await tester.pumpWidget(_host(widget, menu));
      expect(find.textContaining(builtIn), findsOneWidget);

      menu.renameItem(route, 'Quorum');
      await tester.pump();

      expect(find.textContaining('Quorum'), findsOneWidget);
      expect(find.textContaining(builtIn), findsNothing);
    });
  });
}
