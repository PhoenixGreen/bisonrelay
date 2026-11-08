import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/ui/animation_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart' hide Canvas, Paint;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_chain_helpers.dart';

// canvas_motion_bake_test.dart is the prototype's "Bake into keys": what a
// move device does to an element made keys in a clip of its own -- the same
// motion, frame by frame -- and the device switched off, for an EPUB, which
// plays keys.

CanvasController _with(List<MotionDevice> devices, {int frames = 96}) =>
    CanvasController(CanvasDocument(frames: frames, frameRate: 24, elements: [
      ShapeElement(
          ElementBase(
              id: "a",
              x: 100,
              y: 100,
              width: 40,
              height: 40,
              motion: ElementMotion(clips: const [
                MotionClip(id: "go", kind: MotionKind.action, length: 4, keys: {
                  MotionProp.x: [
                    MotionKey(0, MotionNumber(0)),
                    MotionKey(4, MotionNumber(200)),
                  ],
                }),
              ], placed: const [
                ClipPlacement(id: "p", clip: "go", length: 4)
              ], devices: devices)),
          fill: const Color(0xFF000000)),
    ]));

void main() {
  test("a steady line is two keys; a bend keeps the key at it", () {
    expect(keptSamples([0, 1, 2, 3, 4], 0.01), [0, 4]);
    expect(keptSamples([0, 1, 2, 1, 0], 0.01), [0, 2, 4]);
  });

  for (var kind in [MotionDeviceKind.wiggle, MotionDeviceKind.oscillate]) {
    test("a ${kind.label} baked moves it the same, its device off", () {
      var c = _with([MotionDevice(kind, id: "m")]);
      addTearDown(c.dispose);
      var e = c.document.elementById("a")!;
      var was = [
        for (var f = 0; f < 96; f += 5) poseWithMotion(e, f, c.document)
      ];
      expect(c.bakeMotionDevice("a", "m"), isNull);
      var now = c.document.elementById("a")!;
      expect(now.base.motion.devices.single.on, isFalse);
      var baked = now.base.motion.clips.firstWhere((x) => x.id != "go");
      expect(baked.name, "Baked ${kind.label.toLowerCase()}");
      expect(now.base.motion.placed.where((p) => p.clip == baked.id),
          hasLength(1));
      for (var (i, f) in [for (var f = 0; f < 96; f += 5) f].indexed) {
        var p = poseWithMotion(now, f, c.document);
        expect(p.dx, closeTo(was[i].dx, 0.25), reason: "frame $f across");
        expect(p.dy, closeTo(was[i].dy, 0.25), reason: "frame $f down");
        expect(p.rotate, closeTo(was[i].rotate, 0.25), reason: "frame $f turn");
        expect(p.scale, closeTo(was[i].scale, 0.01), reason: "frame $f size");
      }
      c.undo();
      expect(c.document.elementById("a")!.base.motion.devices.single.on, isTrue,
          reason: "one undo step");
    });
  }

  test("nothing to bake, or no room, says why", () {
    var c = _with(const [
      MotionDevice(MotionDeviceKind.oscillate, id: "m", values: {"amount": 0})
    ]);
    addTearDown(c.dispose);
    expect(c.bakeMotionDevice("a", "m"), contains("nothing"));
    expect(c.bakeMotionDevice("a", "nope"), isNotNull);
    var full = c.document.elementById("a")!;
    c.setMotion(
        "a",
        full.base.motion.copyWith(placed: [
          for (var l = 0; l < motionLayers; l++)
            ClipPlacement(id: "p$l", clip: "go", layer: l, length: 4),
        ]));
    c.setMotionDevices(
        "a", const [MotionDevice(MotionDeviceKind.wiggle, id: "m")]);
    expect(c.bakeMotionDevice("a", "m"), contains("Every layer"));
  });

  testWidgets("a move device's ⋯ bakes it", (tester) async {
    var c = _with(const [MotionDevice(MotionDeviceKind.wiggle, id: "m")]);
    addTearDown(c.dispose);
    c.selectOnly("a");
    c.pickMotion("a", "go", placement: "p");
    tester.view.physicalSize = const Size(3000, 420);
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
              body: ListenableBuilder(
                  listenable: c,
                  builder: (context, _) =>
                      AnimationPanel(controller: c, height: 400)))),
    ));
    await tester.pumpAndSettle();
    var id = c.motionDevicesOf("a").single.id;
    await revealInMenu(tester, "mdevBake-$id");
    await tester.tap(find.byKey(ValueKey("mdevBake-$id")));
    await tester.pumpAndSettle();
    expect(c.motionDevicesOf("a").single.on, isFalse);
    expect(c.motionOf("a").clips, hasLength(2));
    expect(tester.takeException(), isNull);
  });
}
