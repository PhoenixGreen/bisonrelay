import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/ui/animation_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_panel_parts_test.dart is the parts every element's settings are
// built from since the panel was rebuilt round tasks (Ken, 2026-11-11): its
// looks as rows that are its Chain's looks, its motion said in lines that
// open the Chain, the place in a box as a picture of the box, and one name
// and one scale for each look's setting.

CanvasController controllerWith(List<MotionDevice> looks) {
  var c =
      CanvasController(CanvasDocument(frames: 240, frameRate: 24, elements: [
    ShapeElement(const ElementBase(id: "s", x: 40, y: 40)).withBase(
        motion: const ElementBase(id: "s")
            .motion
            .copyWith(devices: withMotionDeviceIds(looks))),
  ]));
  c.selectOnly("s");
  return c;
}

Future<void> pump(WidgetTester tester, Widget child,
    {CanvasController? chainOf}) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Column(children: [
          SizedBox(
              width: 360,
              height: 760,
              child: SingleChildScrollView(child: child)),
          if (chainOf != null)
            Expanded(child: AnimationPanel(controller: chainOf, height: 380)),
        ]),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

MotionDevice deviceOf(CanvasController c, MotionDeviceKind kind) => c.document
    .elementById("s")!
    .base
    .motion
    .devices
    .firstWhere((d) => d.kind == kind);

void main() {
  group("a look's setting reads the same in the panel and the Chain", () {
    LookParamView view(MotionDeviceKind k, String p) =>
        lookParamView(k, k.param(p));

    test("a share as a percentage", () {
      var strength = view(MotionDeviceKind.glow, "strength");
      expect(strength.suffix, "%");
      expect(strength.shown(0.6), closeTo(60, 1e-9));
      expect(strength.stored(45), closeTo(0.45, 1e-9));
      expect(view(MotionDeviceKind.colour, "saturation").suffix, "%",
          reason: "a 0-2 multiplier is a percentage too: 100% is as it was");
      expect(view(MotionDeviceKind.colour, "brightness").shown(-0.5), -50);
    });

    test("the shadow's angle is the way it falls", () {
      var falls = view(MotionDeviceKind.shadow, "angle");
      expect(falls.label, "Falls");
      expect(falls.shown(135), 135);
    });

    test("sizes stay sizes, and a rate is not a share", () {
      expect(view(MotionDeviceKind.blur, "amount").suffix, " px");
      expect(view(MotionDeviceKind.lens, "zoom").suffix, "×");
      expect(view(MotionDeviceKind.lens, "laps").suffix, isNot("%"));
    });
  });

  group("looks as rows", () {
    testWidgets("a row is its Chain's look: changed here, changed there",
        (tester) async {
      var c = controllerWith(const [MotionDevice(MotionDeviceKind.glow)]);
      addTearDown(c.dispose);
      await pump(
          tester,
          LooksGroup(
              controller: c,
              element: c.document.elementById("s")!,
              title: "Looks"));
      var id = deviceOf(c, MotionDeviceKind.glow).id;
      expect(find.byKey(ValueKey("lookRow-$id")), findsOneWidget);
      var main =
          tester.widget<CanvasStepper>(find.byKey(ValueKey("lookMain-$id")));
      expect(main.value, closeTo(60, 1e-9), reason: "60%, not 0.6");
      main.onChanged(80);
      main.onCommit?.call();
      await tester.pumpAndSettle();
      expect(deviceOf(c, MotionDeviceKind.glow).value("strength"),
          closeTo(0.8, 1e-9));
      // And one undo puts it back, as any change.
      c.undo();
      expect(deviceOf(c, MotionDeviceKind.glow).value("strength"),
          closeTo(0.6, 1e-9));
    });

    testWidgets("its switch, its other settings, and Show in the Chain",
        (tester) async {
      var c = controllerWith(const [MotionDevice(MotionDeviceKind.shadow)]);
      addTearDown(c.dispose);
      Future<void> again() => pump(
          tester,
          LooksGroup(
              controller: c,
              element: c.document.elementById("s")!,
              title: "Looks"));
      await again();
      var id = deviceOf(c, MotionDeviceKind.shadow).id;
      await tester.tap(find.byKey(ValueKey("lookOn-$id")));
      await tester.pumpAndSettle();
      expect(deviceOf(c, MotionDeviceKind.shadow).on, isFalse);

      await again();
      await tester.tap(find.byKey(ValueKey("lookOpen-$id")));
      await tester.pumpAndSettle();
      expect(find.text("Falls"), findsOneWidget);
      expect(find.byKey(ValueKey("lookColour-$id")), findsOneWidget);
      await tester.tap(find.byKey(ValueKey("lookInChain-$id")));
      await tester.pumpAndSettle();
      expect(c.animationOpen, isTrue);
      expect(c.chainFocus, id);
    });

    testWidgets("a look added here is added to its Chain, on its layer",
        (tester) async {
      var c = controllerWith(const [
        MotionDevice(MotionDeviceKind.glow),
        MotionDevice(MotionDeviceKind.outline, layer: "body"),
      ]);
      addTearDown(c.dispose);
      await pump(
          tester,
          LooksGroup(
              controller: c,
              element: c.document.elementById("s")!,
              layer: "body",
              title: "On the words"));
      // Only those on its layer.
      expect(
          find.byKey(
              ValueKey("lookRow-${deviceOf(c, MotionDeviceKind.glow).id}")),
          findsNothing);
      expect(find.byKey(const ValueKey("lookAdd-body-outline")), findsNothing,
          reason: "it has one");
      await tester.tap(find.byKey(const ValueKey("lookAdd-body-shadow")));
      await tester.pumpAndSettle();
      var shadow = deviceOf(c, MotionDeviceKind.shadow);
      expect(shadow.layer, "body");
      expect(shadow.id, isNotEmpty);
    });
  });

  testWidgets("a line of motion opens the Chain at its clip", (tester) async {
    var c = controllerWith(const []);
    addTearDown(c.dispose);
    c.applyElementAnimation(
        c.document.elementById("s")!, ElementAnimationPreset.fadeIn,
        length: 12);
    var e = c.document.elementById("s")!;
    await pump(tester, MotionSummary(controller: c, element: e));
    var p = e.base.motion.placed.single;
    var line = find.byKey(ValueKey("motionLine-${p.id}"));
    expect(line, findsOneWidget);
    expect(find.textContaining("Arrives"), findsWidgets);
    await tester.tap(line);
    await tester.pumpAndSettle();
    expect(c.animationOpen, isTrue);
    expect(c.pickedMotion, p.clip);
    expect(c.chainFocus, "clips");
  });

  testWidgets("still, it says so, and still opens the Chain", (tester) async {
    var c = controllerWith(const []);
    addTearDown(c.dispose);
    await pump(tester,
        MotionSummary(controller: c, element: c.document.elementById("s")!));
    expect(find.byKey(const ValueKey("motionLine-none")), findsOneWidget);
  });

  testWidgets("the Chain brings the card asked for into view, and lets go",
      (tester) async {
    var c = controllerWith(const [
      MotionDevice(MotionDeviceKind.glow),
      MotionDevice(MotionDeviceKind.shadow),
      MotionDevice(MotionDeviceKind.outline),
      MotionDevice(MotionDeviceKind.blur),
      MotionDevice(MotionDeviceKind.colour),
      MotionDevice(MotionDeviceKind.wear),
      MotionDevice(MotionDeviceKind.edges),
    ]);
    addTearDown(c.dispose);
    var last = deviceOf(c, MotionDeviceKind.edges).id;
    c.showInChain("s", last);
    await pump(tester, const SizedBox(), chainOf: c);
    expect(c.chainFocus, isNull, reason: "shown, and let go of");
    var card = tester.getRect(find.byKey(ValueKey("mdevCard-$last")));
    expect(card.right, lessThanOrEqualTo(1600 + 1),
        reason: "scrolled into view");
    expect(card.left, greaterThanOrEqualTo(-1));
  });

  testWidgets("the place in a box, as a picture of the box", (tester) async {
    TextSlot? picked;
    await pump(
        tester,
        CanvasSlotPicker(
            value: TextSlot.topLeft, onChanged: (s) => picked = s));
    await tester.tap(find.byKey(const ValueKey("slot-bottomRight")));
    expect(picked, TextSlot.bottomRight);
  });
}
