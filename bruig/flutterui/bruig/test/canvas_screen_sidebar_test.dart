import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/sidebar_layout.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/canvas_screen.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/sidebar_extras.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/canvas_app.dart';
import 'support/canvas_audio_fake.dart';

// canvas_screen_sidebar_test.dart is which sidebar the Canvas page shows,
// and when: tested on the page, which decides it.

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CanvasScreen.framedForTest = (page) => page;
  });
  tearDown(() => CanvasScreen.framedForTest = null);

  Future<void> show(WidgetTester tester, CanvasController controller,
      CanvasPreferences prefs) async {
    setTestScreen(tester, const Size(1600, 1000));
    await tester
        .pumpWidget(canvasApp(const CanvasScreen(), prefs: prefs, extra: [
      ChangeNotifierProvider<CanvasController>.value(value: controller),
    ]));
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> leave(WidgetTester tester, CanvasController controller,
      CanvasPreferences prefs) async {
    await tester.pumpWidget(canvasApp(const SizedBox(), prefs: prefs, extra: [
      ChangeNotifierProvider<CanvasController>.value(value: controller),
    ]));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets(
      "a feature's sidebar switched off no longer holds the column: a "
      "selection goes to the settings again", (tester) async {
    // While a feature's own sidebar shows, selecting something leaves it
    // showing (an assistant picking what it works on). Switched off, the
    // feature's sidebar is gone, but it was still asked for by name, and
    // a selection went on being ignored.
    var on = ValueNotifier(true);
    CanvasSidebarExtras.register(CanvasSidebarExtra(
        id: "helper",
        name: "Helper",
        icon: Icons.star,
        shown: on,
        build: (context, controller) => const Text("the helper's column")));
    addTearDown(CanvasSidebarExtras.forgetForTest);
    var c = CanvasController(
        const CanvasDocument()
            .addElement(const ShapeElement(ElementBase(id: "a")))
            .addElement(const ShapeElement(ElementBase(id: "b"))),
        audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    // Above the panels: the sidebar is then the page's own, where beside
    // everything it sits in the app's side menu, which needs the chat
    // client.
    var prefs = CanvasPreferences()
      ..sidebars =
          const SidebarLayout(mode: SidebarMode.above, current: "design");
    await show(tester, c, prefs);

    await tester.tap(find.byKey(const ValueKey("sidebarTab-helper")));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("the helper's column"), findsOneWidget);
    c.selectOnly("a");
    await tester.pump(const Duration(milliseconds: 300));
    expect(prefs.sidebars.current, "helper",
        reason: "its own sidebar keeps the column while it is there");

    on.value = false;
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("the helper's column"), findsNothing);
    c.selectOnly("b");
    await tester.pump(const Duration(milliseconds: 300));
    expect(prefs.sidebars.current, "design");
    await leave(tester, c, prefs);
  });
}
