import 'dart:math' as math;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The settings as a menu: the settings panel's icon swaps the sections down
// the panel for a bar of their names, one shown at a time, with the
// picture's layers a switch of their own at the start of the bar.

const _picture = ImageElement(
    ElementBase(id: "i", x: 100, y: 100, width: 200, height: 200),
    assetId: "abcdefghij123456",
    fit: ImageFit.stretch);

const _shape = ShapeElement(ElementBase(id: "s", width: 100, height: 100));

void main() {
  Future<CanvasController> pumpPanel(WidgetTester tester,
      {String? select = "i", double height = 4000}) async {
    SharedPreferences.setMockInitialValues({});
    var c = CanvasController(
        const CanvasDocument().addElement(_picture).addElement(_shape));
    addTearDown(c.dispose);
    addTearDown(() => settingsAsMenu.value = false);
    if (select != null) c.selectOnly(select);
    tester.view.physicalSize = Size(900, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
              body: SizedBox(
                  width: 420, child: CanvasDesignPanel(controller: c)))),
    ));
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    var found = find.byKey(ValueKey(key));
    await tester.ensureVisible(found);
    await tester.tap(found);
    await tester.pumpAndSettle();
  }

  Finder body(String remember) => find.byKey(ValueKey("sectionBody-$remember"));

  /// shownBodies is the remember names of the section bodies on screen.
  List<String> shownBodies(WidgetTester tester) => [
        for (var w in tester.widgetList(find.byWidgetPredicate((w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith("sectionBody-"))))
          (w.key as ValueKey<String>).value.substring("sectionBody-".length)
      ];

  testWidgets("the settings icon swaps sections for a menu, and back",
      (tester) async {
    await pumpPanel(tester);
    expect(find.byKey(const ValueKey("settingsMenu")), findsNothing);
    expect(find.byKey(const ValueKey("section-image.picture.mask")),
        findsOneWidget,
        reason: "sections down the panel to begin with");
    await tapKey(tester, "panelIcon:settings");
    expect(settingsAsMenu.value, isTrue);
    expect(find.byKey(const ValueKey("settingsMenu")), findsOneWidget);
    expect(
        find.byKey(const ValueKey("section-image.picture.mask")), findsNothing,
        reason: "no fold headings in the menu");
    expect(find.byKey(const ValueKey("menuTab-image.picture.mask")),
        findsOneWidget);
    await tapKey(tester, "panelIcon:settings");
    expect(settingsAsMenu.value, isFalse);
    expect(find.byKey(const ValueKey("settingsMenu")), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets("one section at a time, the one picked from the bar",
      (tester) async {
    settingsAsMenu.value = true;
    await pumpPanel(tester);
    expect(shownBodies(tester), hasLength(1));
    await tapKey(tester, "menuTab-image.picture.mask");
    expect(shownBodies(tester), ["image.picture.mask"]);
    expect(find.byKey(const ValueKey("imageTool-crop")), findsOneWidget);
    await tapKey(tester, "menuTab-image.frame");
    expect(shownBodies(tester), ["image.frame"]);
    expect(body("image.picture.mask"), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets("the layers sit over the bar, not in it", (tester) async {
    settingsAsMenu.value = true;
    await pumpPanel(tester);
    var layers = tester.getRect(find.byKey(const ValueKey("imageLayers")));
    var bar = tester.getRect(find.byKey(const ValueKey("settingsMenu")));
    expect(layers.bottom, lessThanOrEqualTo(bar.top + 0.5));
    expect(
        find.descendant(
            of: find.byKey(const ValueKey("settingsMenu")),
            matching: find.textContaining("Layers")),
        findsNothing);
    // Whichever section is picked.
    await tapKey(tester, "menuTab-image.picture.mask");
    expect(find.byKey(const ValueKey("imageLayers")), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("the first setting sits close under the bar", (tester) async {
    settingsAsMenu.value = true;
    await pumpPanel(tester);
    await tapKey(tester, "menuTab-image.picture.mask");
    var bar = tester.getRect(find.descendant(
        of: find.byKey(const ValueKey("settingsMenu")),
        matching: find.byType(SingleChildScrollView)));
    var first = tester.getRect(find
        .descendant(of: body("image.picture.mask"), matching: find.byType(Text))
        .first);
    expect(first.top - bar.bottom, lessThan(30),
        reason: "no heading between the bar and the section");
    expect(find.text("Mask"), findsWidgets, reason: "named Mask now");
    expect(find.text("Mask & crop"), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets("the section picked carries to another element by its name",
      (tester) async {
    settingsAsMenu.value = true;
    var c = await pumpPanel(tester);
    await tapKey(tester, "menuTab-image.picture.animation");
    expect(shownBodies(tester), ["image.picture.animation"]);
    c.selectOnly("s");
    await tester.pumpAndSettle();
    expect(shownBodies(tester).single, endsWith("animation"),
        reason: "the shape's Animation, picked by the same name");
    expect(tester.takeException(), isNull);
  });

  testWidgets("the background's sections are found, deep as they are",
      (tester) async {
    settingsAsMenu.value = true;
    await pumpPanel(tester, select: null);
    expect(find.byKey(const ValueKey("menuTab-canvasBackground.pattern")),
        findsOneWidget);
    expect(find.byKey(const ValueKey("menuTab-canvasBackground.presets")),
        findsOneWidget);
    await tapKey(tester, "menuTab-canvasBackground.presets");
    expect(shownBodies(tester), ["canvasBackground.presets"]);
    expect(tester.takeException(), isNull);
  });

  testWidgets("the bar stays at the top as the settings scroll",
      (tester) async {
    settingsAsMenu.value = true;
    await pumpPanel(tester, height: 1100);
    await tapKey(tester, "menuTab-image.picture.colour");
    var menu = find.byKey(const ValueKey("settingsMenu"));
    var panel = find
        .ancestor(of: menu, matching: find.byType(SingleChildScrollView))
        .first;
    var view = tester.getRect(panel);
    var scroll = tester.widget<SingleChildScrollView>(panel).controller!;
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(tester.getRect(menu).top, greaterThan(view.top + 5),
        reason: "in its own place at the top of the settings");
    scroll.jumpTo(math.min(300.0, scroll.position.maxScrollExtent));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(100));
    expect(tester.getRect(menu).top, closeTo(view.top, 1),
        reason: "held at the top of the settings");
    // Still a menu up there: a tab pressed there works -- its line
    // scrolled back to the start, where Mask is.
    tester
        .widget<SingleChildScrollView>(find.descendant(
            of: menu, matching: find.byType(SingleChildScrollView)))
        .controller!
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("menuTab-image.picture.mask")));
    await tester.pumpAndSettle();
    expect(shownBodies(tester), ["image.picture.mask"]);
    expect(tester.takeException(), isNull);
  });
}
