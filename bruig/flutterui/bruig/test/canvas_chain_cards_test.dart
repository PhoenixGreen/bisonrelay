import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/ui/animation_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_chain_cards_test.dart is the Chain's cards in the settings
// panel's style (Ken, 2026-11-12, the approved chain prototype): a look's
// settings in columns, each keyed by its diamond; its A, L, Loop and I; and
// the element's own Design, whose + Setting adds the settings of its panel.

CanvasController make({List<MotionDevice> devices = const []}) {
  var base = const ElementBase(id: "t", width: 400, height: 160);
  var c =
      CanvasController(CanvasDocument(frames: 240, frameRate: 24, elements: [
    TextElement(base.copyWith(motion: base.motion.copyWith(devices: devices)),
        text: "Who sees your records?"),
  ]));
  c.selectOnly("t");
  return c;
}

Future<CanvasController> show(WidgetTester tester, CanvasController c) async {
  addTearDown(c.dispose);
  tester.view.physicalSize = const Size(2400, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
    ],
    child: MaterialApp(
        home: Scaffold(body: AnimationPanel(controller: c, height: 520))),
  ));
  await tester.pumpAndSettle();
  return c;
}

MotionDevice glowOf(CanvasController c) =>
    c.motionDevicesOf("t").firstWhere((d) => d.kind == MotionDeviceKind.glow);

void main() {
  testWidgets("a look's card: its settings, keyed by their diamonds",
      (tester) async {
    var c = await show(tester,
        make(devices: const [MotionDevice(MotionDeviceKind.glow, id: "m0")]));
    expect(find.byKey(const ValueKey("mdevCard-m0")), findsOneWidget);
    expect(find.byKey(const ValueKey("mdev-m0-radius")), findsOneWidget);
    expect(find.byKey(const ValueKey("mdevLayer-m0")), findsOneWidget,
        reason: "a text's look says what it is on");
    c.frame = 24;
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey("mdevKey-m0-strength")));
    await tester.pump();
    expect(glowOf(c).keyAt("strength", 1), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets("A, L, Loop and I: where its keys play", (tester) async {
    var c = await show(tester,
        make(devices: const [MotionDevice(MotionDeviceKind.glow, id: "m0")]));
    expect(glowOf(c).plays, {MotionPhase.free});
    await tester.tap(find.byKey(const ValueKey("phase-m0-arrive")));
    await tester.pump();
    expect(glowOf(c).plays, {MotionPhase.free, MotionPhase.arrive});
    await tester.tap(find.byKey(const ValueKey("phase-m0-free")));
    await tester.pump();
    expect(glowOf(c).plays, {MotionPhase.arrive});
  });

  testWidgets("Design: there before it has a device, made by a change",
      (tester) async {
    var c = await show(tester, make());
    expect(find.byKey(const ValueKey("designCard")), findsOneWidget);
    expect(find.byKey(const ValueKey("designSetting-x")), findsOneWidget);
    expect(c.designOf("t"), isNull);
    c.frame = 48;
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey("mdevKey-design-x")));
    await tester.pump();
    var d = c.designOf("t")!;
    expect(d.keyed("x"), isTrue);
    expect(d.keyAt("x", 2), isTrue);
    c.undo();
    expect(c.designOf("t"), isNull, reason: "one undo, device and all");
  });

  testWidgets("+ Setting adds a text's font size; × takes it off with its keys",
      (tester) async {
    var c = await show(tester, make());
    await tester.tap(find.byKey(const ValueKey("designAdd")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Font size").last);
    await tester.pumpAndSettle();
    expect(c.designOf("t")!.shown, contains("fontSize"));
    expect(
        find.byKey(const ValueKey("designSetting-fontSize")), findsOneWidget);
    // Unkeyed, it changes the text's own font size, as the panel does.
    c.setDesignSetting("t", "fontSize", 30);
    c.endInteraction();
    expect((c.document.elementById("t") as TextElement).textSpec.fontSize, 30);
    c.toggleDesignKey("t", "fontSize");
    expect(c.designOf("t")!.keyed("fontSize"), isTrue);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey("designRemove-fontSize")));
    await tester.pump();
    expect(c.designOf("t")!.shown, isNot(contains("fontSize")));
    expect(c.designOf("t")!.keyed("fontSize"), isFalse);
  });

  testWidgets("the filter shows only what plays in one phase", (tester) async {
    var c = await show(
        tester,
        make(devices: [
          const MotionDevice(MotionDeviceKind.glow, id: "m0"),
          const MotionDevice(MotionDeviceKind.shadow, id: "m1")
              .withPlaying(MotionPhase.arrive, true),
        ]));
    c.chainPhase = MotionPhase.arrive;
    addTearDown(() => c.chainPhase = null);
    await tester.pump();
    expect(find.byKey(const ValueKey("mdevCard-m0")), findsNothing);
    expect(find.byKey(const ValueKey("mdevCard-m1")), findsOneWidget);
  });
}
