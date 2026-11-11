import 'dart:convert';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart'
    show motionModulated;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_look_keys_test.dart is a look's settings animated by keys (Ken,
// 2026-11-11: the settings panel sets how a look rests, and the Chain
// animates the same settings). A glow rising as its words arrive is two
// keys on its strength; the Chain's knob and the panel's row change the
// same keys.

const glow = MotionDevice(MotionDeviceKind.glow, id: "m0");

MotionDevice rising() =>
    glow.withKey("strength", 1, 0).withKey("strength", 2, 0.8);

CanvasController controllerWith(MotionDevice d) {
  var c =
      CanvasController(CanvasDocument(frames: 240, frameRate: 24, elements: [
    ShapeElement(const ElementBase(id: "s", x: 40, y: 40)).withBase(
        motion: const ElementBase(id: "s").motion.copyWith(devices: [d])),
  ]));
  c.selectOnly("s");
  return c;
}

MotionDevice deviceOf(CanvasController c) =>
    c.document.elementById("s")!.base.motion.devices.single;

void main() {
  group("a setting's keys", () {
    test("in a straight line between them, level outside", () {
      var d = rising();
      expect(d.keyed("strength"), isTrue);
      expect(d.keyed("radius"), isFalse);
      expect(d.valueAt("strength", 0), 0, reason: "level before the first");
      expect(d.valueAt("strength", 1.5), closeTo(0.4, 1e-9));
      expect(d.valueAt("strength", 9), 0.8, reason: "level after the last");
      expect(d.valueAt("radius", 1.5), d.value("radius"),
          reason: "a setting with none rests as set");
    });

    test("played, the device is as its keys have it then", () {
      expect(motionModulated(rising(), const [], 1.5).value("strength"),
          closeTo(0.4, 1e-9));
      expect(motionModulated(glow, const [], 1.5).value("strength"),
          glow.value("strength"));
    });

    test("one key moved, not two, at the same moment", () {
      var d = rising().withKey("strength", 2.01, 0.5);
      expect(d.keys["strength"], hasLength(2));
      expect(d.valueAt("strength", 2.01), 0.5);
    });

    test("the last key taken away, it keeps the value it had", () {
      var d = glow.withKey("strength", 1, 0.3).withoutKeyAt("strength", 1);
      expect(d.keyed("strength"), isFalse);
      expect(d.value("strength"), closeTo(0.3, 1e-9));
    });

    test("kept with its device, through its other changes", () {
      var d = rising().withLayer("body").withValue("radius", 20);
      expect(d.keys["strength"], hasLength(2));
      var back = MotionDevice.fromJson(jsonDecode(jsonEncode(d.toJson())))!;
      expect(back, d);
      expect(back.valueAt("strength", 1.5), closeTo(0.4, 1e-9));
      expect(glow.toJson(), isNot(contains("keys")));
    });
  });

  group("changed from the Chain or the panel alike", () {
    test("animated, a change is a key at the playhead", () {
      var c = controllerWith(rising());
      addTearDown(c.dispose);
      c.frame = 36; // 1.5 s
      c.setDeviceSetting("s", "m0", "strength", 1);
      var d = deviceOf(c);
      expect(d.keys["strength"], hasLength(3));
      expect(d.valueAt("strength", 1.5), 1);
      expect(d.value("strength"), glow.value("strength"),
          reason: "how it rests is not what changed");
    });

    test("still, a change is how it rests", () {
      var c = controllerWith(glow);
      addTearDown(c.dispose);
      c.setDeviceSetting("s", "m0", "strength", 0.2);
      expect(deviceOf(c).value("strength"), closeTo(0.2, 1e-9));
      expect(deviceOf(c).animated, isFalse);
    });

    test("keyed here and taken away; stopped, it keeps its value", () {
      var c = controllerWith(glow);
      addTearDown(c.dispose);
      c.frame = 24;
      c.toggleDeviceKey("s", "m0", "strength");
      expect(deviceOf(c).keyAt("strength", 1), isTrue);
      c.toggleDeviceKey("s", "m0", "strength");
      expect(deviceOf(c).animated, isFalse);
      c.setMotionDevices("s", [rising()]);
      c.frame = 36;
      c.stopAnimatingDevice("s", "m0", "strength");
      expect(deviceOf(c).animated, isFalse);
      expect(deviceOf(c).value("strength"), closeTo(0.4, 1e-9));
    });
  });

  testWidgets("the panel's row shows it as it is now, and keys it",
      (tester) async {
    var c = controllerWith(rising());
    addTearDown(c.dispose);
    c.frame = 36;
    tester.view.physicalSize = const Size(800, 1200);
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
          body: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: LooksGroup(
                  controller: c,
                  element: c.document.elementById("s")!,
                  title: "Looks"),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    var main =
        tester.widget<CanvasStepper>(find.byKey(const ValueKey("lookMain-m0")));
    expect(main.value, closeTo(40, 1e-9), reason: "40%, halfway up");
    main.onChanged(90);
    main.onCommit?.call();
    expect(deviceOf(c).valueAt("strength", 1.5), closeTo(0.9, 1e-9));
    expect(deviceOf(c).keys["strength"], hasLength(3), reason: "a key here");
  });

  testWidgets("its Motion says so, and opens the Chain at it", (tester) async {
    var c = controllerWith(rising());
    addTearDown(c.dispose);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
              child: MotionSummary(
                  controller: c, element: c.document.elementById("s")!)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    var line = find.byKey(const ValueKey("motionLine-keys-m0-strength"));
    expect(line, findsOneWidget);
    expect(find.textContaining("2 keys"), findsOneWidget);
    await tester.tap(line);
    expect(c.chainFocus, "m0");
  });
}
