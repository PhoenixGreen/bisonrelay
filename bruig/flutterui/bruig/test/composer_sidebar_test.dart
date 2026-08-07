import 'package:bruig/components/composer_sidebar_shell.dart';
import 'package:bruig/components/feed/formatting_sidebar.dart';
import 'package:bruig/components/containers.dart';
import 'package:bruig/models/composer_sidebar.dart';
import 'package:bruig/models/feed.dart';
import 'package:bruig/models/uistate.dart';
import 'package:bruig/screens/feed/feed_posts.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// composer_sidebar_test.dart covers the nav that replaced the buttons under
// the editor, and the formatting panel one of its icons opens.

Future<void> _pump(WidgetTester tester, ComposerSidebarController controller,
    {List<ComposerPanel>? panels}) async {
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<ComposerSidebarController>.value(
          value: controller),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => controller.minimized
              ? Row(children: [
                  ComposerSidebarRestoreButton(controller: controller),
                  const Expanded(child: Text("EDITOR")),
                ])
              : Row(children: [
                  SizedBox(
                    width: 260,
                    child: ComposerSidebarShell(
                      controller: controller,
                      panels: panels ?? ComposerPanel.values,
                      child: Text("PANEL: ${controller.panel.name}"),
                    ),
                  ),
                  const Expanded(child: Text("EDITOR")),
                ]),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  // The order the icons sit in, pinned because nothing else would notice it
  // changing: every other test here walks ComposerPanel.values, so it agrees
  // with whatever the enum currently says rather than with what was wanted.
  //
  // It runs outwards from the post: where you are, what you have written
  // before, the words in front of you, and what you can put around them.
  testWidgets("the panel icons run left to right in a fixed order",
      (tester) async {
    var controller = ComposerSidebarController();
    await _pump(tester, controller);

    var order = [
      ComposerPanel.none,
      ComposerPanel.posts,
      ComposerPanel.writing,
      ComposerPanel.formatting,
    ];
    expect(ComposerPanel.values, order,
        reason: "the Feed builds its row by walking this enum, so the "
            "declaration order is the on-screen order");

    var xs = [
      for (var panel in order) tester.getCenter(find.byIcon(panel.icon)).dx
    ];
    expect(xs, orderedEquals(([...xs]..sort())),
        reason: "left to right: ${order.map((p) => p.label).join(", ")}");
  });

  _navTargetTests();
  _resizeTests();
  _drawerOwnershipTests();
  _collapsedDrawerTests();
  _feedPanelFlagTests();
  _hideButtonTests();
  _titleDecorationTests();
  group("the panel nav", () {
    testWidgets("starts on the screen's own menu", (tester) async {
      var controller = ComposerSidebarController();
      await _pump(tester, controller);
      expect(find.text("PANEL: none"), findsOneWidget);
    });

    testWidgets("an icon switches panels", (tester) async {
      var controller = ComposerSidebarController();
      await _pump(tester, controller);

      await tester.tap(find.byIcon(ComposerPanel.posts.icon));
      await tester.pumpAndSettle();
      expect(find.text("PANEL: posts"), findsOneWidget);

      await tester.tap(find.byIcon(ComposerPanel.formatting.icon));
      await tester.pumpAndSettle();
      expect(find.text("PANEL: formatting"), findsOneWidget);
    });

    // A panel whose feature is unavailable is left out rather than shown
    // disabled: there is nothing the user could do about it from here.
    testWidgets("a panel can be left out", (tester) async {
      var controller = ComposerSidebarController();
      await _pump(tester, controller, panels: [
        ComposerPanel.none,
        ComposerPanel.posts,
      ]);
      expect(find.byIcon(ComposerPanel.writing.icon), findsNothing);
      expect(find.byIcon(ComposerPanel.posts.icon), findsOneWidget);
    });
  });

  group("minimizing", () {
    testWidgets("hides the sidebar and leaves a way back", (tester) async {
      var controller = ComposerSidebarController();
      await _pump(tester, controller);

      await tester.tap(find.byTooltip("Hide the sidebar"));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerSidebarShell), findsNothing);
      expect(find.text("EDITOR"), findsOneWidget);
      expect(find.byTooltip("Show the sidebar"), findsOneWidget,
          reason: "a hidden sidebar with no way back is a trap");

      await tester.tap(find.byTooltip("Show the sidebar"));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerSidebarShell), findsOneWidget);
    });

    // Somebody who minimized while reading their library did not ask to be
    // returned to the feed menu.
    testWidgets("comes back to the panel that was showing", (tester) async {
      var controller = ComposerSidebarController();
      await _pump(tester, controller);

      await tester.tap(find.byIcon(ComposerPanel.posts.icon));
      await tester.pumpAndSettle();
      controller.toggleMinimized();
      await tester.pumpAndSettle();
      controller.toggleMinimized();
      await tester.pumpAndSettle();

      expect(find.text("PANEL: posts"), findsOneWidget);
    });

    test("asking for a panel un-minimizes", () {
      var controller = ComposerSidebarController()..toggleMinimized();
      expect(controller.visible, isFalse);

      controller.show(ComposerPanel.writing);
      expect(controller.visible, isTrue);
      expect(controller.panel, ComposerPanel.writing);
    });
  });

  // Every entry in the formatting panel goes through one routine, so these
  // cover its shapes rather than each button.
  group("formatting", () {
    late TextEditingController editor;
    late ComposerSidebarController controller;

    Future<void> pumpPanel(WidgetTester tester) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
        ],
        child: MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 300,
                  child: FormattingSidebar(controller: controller))),
        ),
      ));
      await tester.pumpAndSettle();
    }

    setUp(() {
      editor = TextEditingController();
      controller = ComposerSidebarController()..attach(editor);
    });
    tearDown(() {
      editor.dispose();
      controller.dispose();
    });

    testWidgets("wrapping keeps the selection so it stays highlighted",
        (tester) async {
      editor.value = const TextEditingValue(
        text: "make this bold",
        selection: TextSelection(baseOffset: 10, extentOffset: 14),
      );
      await pumpPanel(tester);

      await tester.tap(find.byIcon(Icons.format_bold));
      await tester.pumpAndSettle();

      expect(editor.text, "make this **bold**");
      expect(editor.selection.textInside(editor.text), "bold");
    });

    // With nothing selected the placeholder goes in selected, so the next
    // keystroke replaces it rather than landing beside it.
    testWidgets("an empty selection leaves the placeholder selected",
        (tester) async {
      await pumpPanel(tester);
      await tester.tap(find.byIcon(Icons.link));
      await tester.pumpAndSettle();

      expect(editor.text, "[text](https://)");
      expect(editor.selection.textInside(editor.text), "text");
    });

    testWidgets("a line prefix applies to every selected line", (tester) async {
      editor.value = const TextEditingValue(
        text: "one\ntwo\nthree",
        selection: TextSelection(baseOffset: 0, extentOffset: 13),
      );
      await pumpPanel(tester);

      await tester.tap(find.byIcon(Icons.format_list_bulleted));
      await tester.pumpAndSettle();
      expect(editor.text, "- one\n- two\n- three");
    });

    // Pressing the same button twice is not a way to write "## ## ".
    testWidgets("a line prefix is not doubled", (tester) async {
      editor.value = const TextEditingValue(
        text: "> quoted",
        selection: TextSelection.collapsed(offset: 3),
      );
      await pumpPanel(tester);

      await tester.tap(find.byIcon(Icons.format_quote));
      await tester.pumpAndSettle();
      expect(editor.text, "> quoted");
    });

    // A table dropped into the middle of a paragraph is not a table.
    testWidgets("a block is separated from what surrounds it", (tester) async {
      editor.value = const TextEditingValue(
        text: "some text",
        selection: TextSelection.collapsed(offset: 9),
      );
      await pumpPanel(tester);

      await tester.tap(find.byIcon(Icons.horizontal_rule));
      await tester.pumpAndSettle();
      expect(editor.text, "some text\n\n---");
    });

    testWidgets("a block does not pile up blank lines", (tester) async {
      editor.value = const TextEditingValue(
        text: "some text\n\n",
        selection: TextSelection.collapsed(offset: 11),
      );
      await pumpPanel(tester);

      await tester.tap(find.byIcon(Icons.horizontal_rule));
      await tester.pumpAndSettle();
      expect(editor.text, "some text\n\n---");
    });

    // The panel is built before a composer attaches, and again for the frame
    // or two while one is being rebuilt.
    testWidgets("no composer means the buttons are simply disabled",
        (tester) async {
      controller = ComposerSidebarController();
      await pumpPanel(tester);
      expect(
          tester
              .widget<OutlinedButton>(find.ancestor(
                  of: find.byIcon(Icons.format_bold),
                  matching: find.byType(OutlinedButton)))
              .onPressed,
          isNull);
    });
  });
}

// Reported: the post title looked like an input, with a border at rest and
// an underline on focus, on a page whose job is to get out of the way of the
// writing.
//
// Worth a test rather than an eyeball, because the cause was not in the
// widget: the app's InputDecorationTheme sets enabledBorder and
// focusedBorder, and those win over the `border` the field cleared. Anything
// added to that theme later would come back the same way.
void _titleDecorationTests() {
  testWidgets("a heading-styled field shows no border, focused or not",
      (tester) async {
    var controller = TextEditingController();
    var focus = FocusNode();

    await tester.pumpWidget(MaterialApp(
      // The same shape as the app's theme: borders declared per state
      // rather than on `border`.
      theme: ThemeData(
        inputDecorationTheme: const InputDecorationTheme(
          enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFFFFF00))),
          focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFFFFF00), width: 2)),
        ),
      ),
      home: Scaffold(
        body: TextField(
          controller: controller,
          focusNode: focus,
          decoration: const InputDecoration(
            hintText: "Untitled post",
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            filled: false,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    ));

    InputDecorator decorator() =>
        tester.widget<InputDecorator>(find.byType(InputDecorator));

    var resting = decorator().decoration;
    expect(resting.border, InputBorder.none);
    expect(resting.enabledBorder, InputBorder.none);
    expect(resting.focusedBorder, InputBorder.none);

    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(decorator().isFocused, isTrue,
        reason: "the field has to actually be focused for this to mean "
            "anything");
    expect(decorator().decoration.focusedBorder, InputBorder.none,
        reason: "the underline came back on focus");

    controller.dispose();
    focus.dispose();
  });
}

// The hide control is not a fifth panel. It sits past the panel icons,
// against the sidebar's outer edge and larger than they are, because a
// control that read as one of them invited the reading that it closed the
// panel beside it -- which is what it looked like it did.
void _hideButtonTests() {
  testWidgets("the hide control sits apart from the panel icons",
      (tester) async {
    var controller = ComposerSidebarController();
    await _pump(tester, controller);

    var hide = tester.getRect(find.byIcon(Icons.chevron_left));
    for (var panel in ComposerPanel.values) {
      var icon = tester.getRect(find.byIcon(panel.icon));
      expect(hide.left, greaterThan(icon.right),
          reason: "the hide control should be past every panel icon");
      expect(hide.width, greaterThan(icon.width),
          reason: "and read as heavier than one of them");
    }

    // Against the sidebar's outer edge rather than floating in the row.
    var shell = tester.getRect(find.byType(ComposerSidebarShell));
    expect(shell.right - hide.right, lessThan(12),
        reason: "the hide control drifted away from the sidebar's edge");
  });
}

// Reported: turning "Feed side panel" on left the composer's Feed tab
// showing the plain tab list, so the composer was the one place in the Feed
// the setting did not reach.
//
// The panel is placed inside a sidebar that has already drawn the chrome and
// beside somebody writing rather than browsing, so it needs to render bare
// and without its search field. These cover those two flags, which is what
// the fix rests on.
void _feedPanelFlagTests() {
  Future<void> pumpPanel(WidgetTester tester,
      {required bool framed, required bool showSearch}) async {
    var search = TextEditingController();
    addTearDown(search.dispose);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            child: FeedSidePanel(
              view: FeedView.all,
              sort: FeedSort.newest,
              unreadOnly: false,
              searchController: search,
              showSearch: showSearch,
              framed: framed,
              showBookmarks: false,
              showHidden: false,
              showDrafts: false,
              currentTabIndex: 3,
              onView: (_) {},
              onSort: (_) {},
              onUnreadOnly: (_) {},
              onSearch: (_) {},
              onYourPosts: () {},
              onSubscriptions: () {},
              onNewPost: () {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets("the panel keeps its search and frame by default",
      (tester) async {
    await pumpPanel(tester, framed: true, showSearch: true);
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byType(SecondarySideMenu), findsOneWidget);
    expect(find.text("All posts"), findsOneWidget);
  });

  testWidgets("beside a composer it drops both, keeping the navigation",
      (tester) async {
    await pumpPanel(tester, framed: false, showSearch: false);

    expect(find.byIcon(Icons.search), findsNothing,
        reason: "searching posts is not what a writer came here for");
    expect(find.byType(SecondarySideMenu), findsNothing,
        reason: "nesting the frame inside a sidebar draws every border "
            "twice");
    // The point of using this panel at all.
    expect(find.text("All posts"), findsOneWidget);
    expect(find.text("Your Posts"), findsOneWidget);
    expect(find.text("New Post"), findsOneWidget);
  });
}

// Reported: in the collapsed drawer -- on mobile, or with the sidebar style
// set to collapsed -- the panel icons did nothing, and the hide control was
// offered where it makes no sense.
void _collapsedDrawerTests() {
  Future<void> pumpInDrawer(
      WidgetTester tester, ComposerSidebarController controller) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: CollapsedSidebarScope(
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => SizedBox(
                width: 260,
                child: ComposerSidebarShell(
                  controller: controller,
                  panels: ComposerPanel.values,
                  child: Text("PANEL: ${controller.panel.name}"),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets("the drawer offers no hide control", (tester) async {
    var controller = ComposerSidebarController();
    await pumpInDrawer(tester, controller);

    expect(find.byTooltip("Hide the sidebar"), findsNothing,
        reason: "the drawer is put away by tapping off it, and its chevron "
            "would point at an edge that is not there");
    // Everything else is still there.
    for (var panel in ComposerPanel.values) {
      expect(find.byIcon(panel.icon), findsOneWidget);
    }
  });

  testWidgets("the panel icons still switch panels there", (tester) async {
    var controller = ComposerSidebarController();
    await pumpInDrawer(tester, controller);

    await tester.tap(find.byIcon(ComposerPanel.posts.icon));
    await tester.pumpAndSettle();
    expect(find.text("PANEL: posts"), findsOneWidget);
  });

  // The drawer redraws only when the model tells it to, and the model
  // ignores a new builder on its own -- a fresh closure every build could
  // never compare equal, so notifying on it would wake the drawer once per
  // frame. A revision is how a sidebar that does change says so.
  // testWidgets rather than test: the model defers its notification past
  // the frame, since it is called from a screen's build and waking
  // listeners there would throw. Nothing fires without a frame to end.
  testWidgets("the drawer is told when the sidebar's contents change",
      (tester) async {
    await tester.pumpWidget(const SizedBox());

    // The model defers its notification to the end of a frame, and the test
    // binding produces one only when a frame has actually been asked for --
    // pumping a settled tree does not schedule one, so the callback would
    // sit there unfired and every assertion below would pass vacuously.
    Future<void> endFrame() async {
      tester.binding.scheduleFrame();
      await tester.pump();
    }

    var model = CollapsedSidebarModel();
    var woken = 0;
    model.addListener(() => woken++);

    model.register((_) => const SizedBox(), 200, revision: "none");
    await endFrame();
    expect(model.available, isTrue);
    expect(woken, 1, reason: "the first registration is a real change");
    var afterFirst = woken;

    // Same revision, new closure: not worth waking anyone for. A closure is
    // fresh on every build and can never compare equal, so notifying on it
    // would wake the drawer once a frame for no visible change.
    model.register((_) => const SizedBox(), 200, revision: "none");
    await endFrame();
    expect(woken, afterFirst);

    model.register((_) => const SizedBox(), 200, revision: "posts");
    await endFrame();
    expect(woken, greaterThan(afterFirst),
        reason: "the drawer kept rendering the panel that was replaced");
  });
}

// Reported: on mobile and with the sidebar collapsed, the composer's panel
// turned up in the drawer over Realtime Chat, the LN screens and Pages.
//
// A screen registers its sidebar from its build. Screens that never register
// one have nothing to clear it, so a registration nobody takes back follows
// the user to whatever they open next.
void _drawerOwnershipTests() {
  test("a screen's sidebar goes when the screen does", () {
    var model = CollapsedSidebarModel();
    var feed = Object();

    model.register((_) => const SizedBox(), 200, owner: feed);
    expect(model.available, isTrue);

    model.unregister(owner: feed);
    expect(model.available, isFalse,
        reason: "the sidebar followed the user off the screen that owned it");
  });

  // On a navigation the arriving screen registers before the departing one
  // is disposed, so an unscoped clear in dispose would wipe the sidebar that
  // had just arrived and leave the new screen with none at all.
  test("a departing screen cannot take the arriving one's sidebar", () {
    var model = CollapsedSidebarModel();
    var leaving = Object();
    var arriving = Object();

    model.register((_) => const SizedBox(), 200, owner: leaving);
    model.register((_) => const SizedBox(), 200, owner: arriving);

    model.unregister(owner: leaving);
    expect(model.available, isTrue,
        reason: "the screen being torn down cleared its replacement");

    model.unregister(owner: arriving);
    expect(model.available, isFalse);
  });

  // Callers that clear it on their own account -- the wide layout handing
  // the drawer back -- pass no owner and clear whatever is there.
  test("an unowned unregister still clears", () {
    var model = CollapsedSidebarModel();
    model.register((_) => const SizedBox(), 200, owner: Object());
    model.unregister();
    expect(model.available, isFalse);
  });
}

// Reported: at one particular window size the writing tools' nav stopped
// responding, and a hot restart at the same size fixed it.
//
// That is the signature of stale state in the drawer rather than anything
// about the size itself. Crossing a width where the layout above switches
// branches rebuilds the registering screen into a new State, and its
// predecessor's output is defunct -- it still paints, because the drawer
// keeps whatever it last built, but nothing in it is wired to anything
// live, so taps land on widgets that are no longer there.
void _resizeTests() {
  testWidgets("a new registrant always redraws the drawer", (tester) async {
    await tester.pumpWidget(const SizedBox());
    Future<void> endFrame() async {
      tester.binding.scheduleFrame();
      await tester.pump();
    }

    var model = CollapsedSidebarModel();
    var woken = 0;
    model.addListener(() => woken++);

    var before = Object();
    model.register((_) => const SizedBox(), 325,
        revision: "same", owner: before);
    await endFrame();
    var afterFirst = woken;

    // The same screen re-registering: nothing to redraw for.
    model.register((_) => const SizedBox(), 325,
        revision: "same", owner: before);
    await endFrame();
    expect(woken, afterFirst);

    // A new State at the same size showing the same thing. Width and
    // revision are identical, which is exactly why neither could catch it.
    model.register((_) => const SizedBox(), 325,
        revision: "same", owner: Object());
    await endFrame();
    expect(woken, greaterThan(afterFirst),
        reason: "the drawer kept rendering the tree that was replaced, and "
            "every tap in it went nowhere");
  });
}

// Reported: the nav icons "sometimes click properly and other times it takes
// a few tries".
//
// They were sized to the glyph inside them and spaced apart, so most of the
// row they appeared to occupy was gap -- it looked like part of the control
// and did nothing when clicked. Aiming slightly wide missed entirely.
void _navTargetTests() {
  Rect targetOf(WidgetTester tester, IconData icon) => tester.getRect(
        find.ancestor(of: find.byIcon(icon), matching: find.byType(InkWell)),
      );

  testWidgets("the panel icons tile the row, leaving no dead gaps",
      (tester) async {
    var controller = ComposerSidebarController();
    await _pump(tester, controller);

    var targets = [
      for (var panel in ComposerPanel.values) targetOf(tester, panel.icon),
    ]..sort((a, b) => a.left.compareTo(b.left));

    for (var i = 1; i < targets.length; i++) {
      expect(targets[i].left - targets[i - 1].right, lessThan(1),
          reason: "a gap between two icons that looks like part of the row "
              "and does nothing when clicked");
    }
  });

  // A pointer that moves a few pixels between press and release -- which is
  // most trackpad clicks -- has to stay inside the thing it was aimed at.
  testWidgets("every control in the row is comfortably tall", (tester) async {
    var controller = ComposerSidebarController();
    await _pump(tester, controller);

    for (var panel in ComposerPanel.values) {
      expect(targetOf(tester, panel.icon).height, greaterThanOrEqualTo(32),
          reason: "${panel.label} is a small thing to hit");
    }
    expect(
        targetOf(tester, Icons.chevron_left).height, greaterThanOrEqualTo(32));
  });
}
