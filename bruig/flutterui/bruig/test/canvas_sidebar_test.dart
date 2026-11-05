import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/sidebar_layout.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/canvas_sidebar.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/customise_sidebars.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/sidebar_panels.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_sidebar_test.dart is the sidebar set out by the reader: a sidebar
// chosen by its icon, panels moved and hidden from their headings and put
// back from a sidebar's foot, the toggle between full height and above the
// panels, and the sheet that sets out every sidebar at once.

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// shown pumps the sidebar on [layout], keeping what it is set out as.
  Future<ValueNotifier<SidebarLayout>> shown(WidgetTester tester,
      {SidebarLayout layout = const SidebarLayout(current: "design")}) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var c = CanvasController(const CanvasDocument());
    addTearDown(c.dispose);
    var laid = ValueNotifier(layout);
    var bodies = SidebarPanelBodies(
      controller: c,
      onOpen: (_, __) async {},
      onPublish: (_, __) {},
      onNew: (_, __) async {},
      onChoosePreset: (_, __) {},
    );
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(
            create: (c) => CanvasPreferences()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<SidebarLayout>(
            valueListenable: laid,
            builder: (context, l, _) => Row(children: [
              SizedBox(
                width: 320,
                child: CanvasSidebar(
                  controller: c,
                  layout: l,
                  onLayout: (next) => laid.value = next,
                  bodies: bodies,
                  onCustomise: () => showCustomiseSidebars(context,
                      controller: c,
                      read: () => laid.value,
                      write: (next) => laid.value = next),
                ),
              ),
              const Expanded(child: SizedBox()),
            ]),
          ),
        ),
      ),
    ));
    await tester.pump();
    return laid;
  }

  testWidgets("an icon a sidebar; Game only for a game", (tester) async {
    var laid = await shown(tester);
    expect(find.byKey(const ValueKey("sidebarTab-files")), findsOneWidget);
    expect(find.byKey(const ValueKey("sidebarTab-assets")), findsOneWidget);
    expect(find.byKey(const ValueKey("sidebarTab-game")), findsNothing);
    await tester.tap(find.byKey(const ValueKey("sidebarTab-assets")));
    await tester.pump();
    expect(laid.value.current, "assets");
  });

  testWidgets("a panel moved from its heading's menu, and hidden from it",
      (tester) async {
    var laid = await shown(tester);
    await tester.tap(find.byKey(const ValueKey("panelMenu:colour")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Move to Assets"));
    await tester.pumpAndSettle();
    expect(laid.value.sidebarOf("colour")!.id, "assets");

    await tester.tap(find.byKey(const ValueKey("panelMenu:layers")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Hide this panel"));
    await tester.pumpAndSettle();
    expect(laid.value.hidden, ["layers"]);
    expect(find.byKey(const ValueKey("panelMenu:layers")), findsNothing);
  });

  testWidgets("the settings say they cannot be hidden", (tester) async {
    var laid = await shown(tester);
    await tester.tap(find.byKey(const ValueKey("panelMenu:settings")));
    await tester.pumpAndSettle();
    var line = tester.widget<PopupMenuItem<int>>(find.ancestor(
        of: find.textContaining("cannot be hidden"),
        matching: find.byType(PopupMenuItem<int>)));
    expect(line.enabled, isFalse);
    await tester.tapAt(const Offset(900, 900));
    await tester.pumpAndSettle();
    expect(laid.value.hidden, isEmpty);
  });

  testWidgets("a hidden panel leaves no line at the sidebar's foot",
      (tester) async {
    await shown(tester,
        layout: const SidebarLayout(current: "design").hidePanel("colour"));
    expect(find.textContaining("Add a panel"), findsNothing);
    expect(find.byKey(const ValueKey("sidebarAddPanel-design")), findsNothing);
  });

  testWidgets("the row along the top lines up: one height, one middle",
      (tester) async {
    await shown(tester);
    var tab = tester.getRect(find.byKey(const ValueKey("sidebarTab-design")));
    for (var key in ["sidebarModeToggle", "sidebarMenu"]) {
      var r = tester.getRect(find.byKey(ValueKey(key)));
      expect(r.height, closeTo(tab.height, 0.5), reason: key);
      expect(r.center.dy, closeTo(tab.center.dy, 0.5), reason: key);
    }
  });

  testWidgets("the sidebar's menu is in the page's small menu text",
      (tester) async {
    await shown(tester);
    await tester.tap(find.byKey(const ValueKey("sidebarMenu")));
    await tester.pumpAndSettle();
    var line = tester.widget<Text>(find.text("Hide the sidebar"));
    expect(line.style?.fontSize, 12.5);
    await tester.tapAt(const Offset(900, 900));
    await tester.pumpAndSettle();
  });

  testWidgets("the sheet's arrows move a sidebar one place at a time",
      (tester) async {
    var laid = await shown(tester);
    await tester.tap(find.byKey(const ValueKey("sidebarMenu")));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("sidebarCustomise")));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("customiseMove-design-right")));
    await tester.pumpAndSettle();
    expect(laid.value.sidebars[2].id, "design");
    await tester.tap(find.byKey(const ValueKey("customiseMove-design-left")));
    await tester.pumpAndSettle();
    expect(laid.value.sidebars[1].id, "design");
    expect(tester.takeException(), isNull);
  });

  testWidgets("one toggle between full height and over the panels",
      (tester) async {
    var laid = await shown(tester);
    await tester.tap(find.byKey(const ValueKey("sidebarModeToggle")));
    await tester.pump();
    expect(laid.value.mode, SidebarMode.above);
    await tester.tap(find.byKey(const ValueKey("sidebarModeToggle")));
    await tester.pump();
    expect(laid.value.mode, SidebarMode.full);
  });

  testWidgets("no + along the top: sidebars are added in Customise",
      (tester) async {
    await shown(tester);
    expect(find.byKey(const ValueKey("sidebarAdd")), findsNothing);
  });

  testWidgets("the sheet takes a panel out with its ×, and puts it back",
      (tester) async {
    var laid = await shown(tester);
    await tester.tap(find.byKey(const ValueKey("sidebarMenu")));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("sidebarCustomise")));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("customiseHide-stock")));
    await tester.pumpAndSettle();
    expect(laid.value.hidden, ["stock"]);
    expect(find.byKey(const ValueKey("customiseHide-settings")), findsNothing,
        reason: "the settings have no ×");
    await tester
        .ensureVisible(find.byKey(const ValueKey("customisePutBack-stock")));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("customisePutBack-stock")));
    await tester.pumpAndSettle();
    expect(laid.value.sidebarOf("stock")!.id, "assets");

    await tester
        .ensureVisible(find.byKey(const ValueKey("customiseRemove-assets")));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("customiseRemove-assets")));
    await tester.pumpAndSettle();
    expect(laid.value.byId("assets"), isNull);
    await tester.tap(find.byKey(const ValueKey("customiseRestore-assets")));
    await tester.pumpAndSettle();
    expect(laid.value.byId("assets"), isNotNull);

    await tester.ensureVisible(find.byKey(const ValueKey("customiseAdd")));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("customiseAdd")));
    await tester.pumpAndSettle();
    expect(laid.value.sidebars.length, 5);
    await tester.tap(find.byKey(const ValueKey("customiseDone")));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("customiseDone")), findsNothing);
  });
}
