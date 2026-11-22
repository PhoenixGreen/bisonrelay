import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/sidebar_layout.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/canvas_sidebar.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/customise_sidebars.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/sidebar_panels.dart';
import 'package:bruig/storage_manager.dart';

import 'support/canvas_app.dart';

// canvas_sidebar_test.dart is the sidebar set out by the reader: a sidebar
// chosen by its icon, panels moved and hidden from their headings, the
// toggle between full height and above the panels, and the sheet that sets
// out every sidebar at once and puts hidden panels back.

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// hides counts the presses that asked for the sidebar to be put away.
  var hides = 0;
  setUp(() => hides = 0);

  /// shown pumps the sidebar on [layout], keeping what it is set out as.
  Future<ValueNotifier<SidebarLayout>> shown(WidgetTester tester,
      {SidebarLayout layout = const SidebarLayout(current: "design"),
      bool canSitAbove = true,
      CanvasController? controller}) async {
    setTestScreen(tester, const Size(1200, 1000));
    var c = controller ?? CanvasController(const CanvasDocument());
    if (controller == null) addTearDown(c.dispose);
    var laid = ValueNotifier(layout);
    var bodies = SidebarPanelBodies(
      controller: c,
      onOpen: (_, __) async {},
      onPublish: (_, __) {},
      onNew: (_, __) async {},
      onChoosePreset: (_) {},
    );
    await tester.pumpWidget(canvasApp(ValueListenableBuilder<SidebarLayout>(
        valueListenable: laid,
        builder: (context, l, _) => Row(children: [
              SizedBox(
                  width: 320,
                  child: CanvasSidebar(
                      controller: c,
                      layout: l,
                      onLayout: (next) => laid.value = next,
                      onHide: () => hides++,
                      bodies: bodies,
                      canSitAbove: canSitAbove,
                      onCustomise: () => showCustomiseSidebars(context,
                          layout: laid.value,
                          write: (next) => laid.value = next))),
              const Expanded(child: SizedBox())
            ]))));
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
    expect(laid.value.sidebarOf(SidebarPanel.colour)!.id, "assets");

    await tester.tap(find.byKey(const ValueKey("panelMenu:layers")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Hide this panel"));
    await tester.pumpAndSettle();
    expect(laid.value.hidden, [SidebarPanel.layers]);
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

  testWidgets("a sidebar of a panel's own is named for the panel",
      (tester) async {
    // Not for what its heading says at the time: the settings are headed
    // for whatever is selected, and the sidebar was named "Background
    // settings".
    var laid = await shown(tester);
    await tester.tap(find.byKey(const ValueKey("panelMenu:settings")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("A new sidebar of its own"));
    await tester.pumpAndSettle();
    expect(laid.value.sidebars.last.name, "Settings");
    expect(laid.value.sidebars.last.panels, [SidebarPanel.settings]);
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

  testWidgets("with the canvas away it cannot sit over the panels",
      (tester) async {
    // An audio document's: its panels fill the page.
    await shown(tester, canSitAbove: false);
    expect(find.byKey(const ValueKey("sidebarModeToggle")), findsNothing);
    await tester.tap(find.byKey(const ValueKey("sidebarMenu")));
    await tester.pumpAndSettle();
    expect(find.text(SidebarMode.above.label), findsNothing);
    expect(find.text("Hide the sidebar"), findsOneWidget);
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
    expect(laid.value.hidden, [SidebarPanel.stock]);
    expect(find.byKey(const ValueKey("customiseHide-settings")), findsNothing,
        reason: "the settings have no ×");
    await tester
        .ensureVisible(find.byKey(const ValueKey("customisePutBack-stock")));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("customisePutBack-stock")));
    await tester.pumpAndSettle();
    expect(laid.value.sidebarOf(SidebarPanel.stock)!.id, "assets");

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

  testWidgets("hiding is asked for, not set out as a layout", (tester) async {
    // A piece of sound's sidebar is put away for the visit, and the design
    // sidebar's kept layout left alone, so the page has to be told "hide"
    // and not handed a layout whose mode is hidden: with the kept mode
    // already hidden, every change looked like one, and the first press in
    // a piece of sound's sidebar put it away.
    var laid = await shown(tester,
        layout:
            const SidebarLayout(mode: SidebarMode.hidden, current: "design"));
    await tester.tap(find.byKey(const ValueKey("sidebarTab-assets")));
    await tester.pump();
    expect(laid.value.current, "assets");
    expect(hides, 0, reason: "choosing another sidebar is not hiding it");

    await tester.tap(find.byKey(const ValueKey("sidebarHide")));
    await tester.pump();
    expect(hides, 1);
    await tester.tap(find.byKey(const ValueKey("sidebarMenu")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Hide the sidebar"));
    await tester.pumpAndSettle();
    expect(hides, 2);
    expect(laid.value.mode, SidebarMode.hidden,
        reason: "the layout is as it was: where it goes is the page's to say");
    expect(laid.value.current, "assets");
  });

  group("what the settings panel needs of the sidebar it is in", () {
    // Both were once done by a widget the app had stopped mounting, and so
    // were done only in tests.
    testWidgets("settings as a menu is as it was left", (tester) async {
      await tester
          .runAsync(() => StorageManager.saveData("canvasSettingsMenu", true));
      forgetPanelsForTest();
      addTearDown(forgetPanelsForTest);
      await shown(tester);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(settingsAsMenu.value, isTrue);
    });

    testWidgets("tiles keep their pictures while a control is dragged",
        (tester) async {
      var c = CanvasController(const CanvasDocument());
      addTearDown(c.dispose);
      await shown(tester, controller: c);
      expect(TileSnapshot.holding(), isFalse);
      c.beginInteraction();
      expect(TileSnapshot.holding(), isTrue);
      c.endInteraction();

      // And the hook goes with the panel: it would hold the document.
      await tester.pumpWidget(const SizedBox());
      c.beginInteraction();
      expect(TileSnapshot.holding(), isFalse);
      c.endInteraction();
    });
  });
}
