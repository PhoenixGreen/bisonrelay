import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// The layer cross-fader of the approved design (Ken, 2026-11-08), in the
// model: one fader blending an element's free layers, pinned layers played
// in full; how much of the motion is seen; and its motion switched off.

MotionClip across(String id, double by, {int layer = 0}) =>
    MotionClip.ofKind(id, MotionKind.action, name: id).copyWith(
        length: 1,
        layer: layer,
        after: ClipHold.last,
        quantise: () => Quantise.off.name,
        keys: {
          MotionProp.x: [
            const MotionKey(0, MotionNumber(0)),
            MotionKey(1, MotionNumber(by)),
          ],
        });

void main() {
  group("crossFade", () {
    test("blends the two free layers it stands between", () {
      expect(crossFade([0, 1, 2], 0, 0), [1, 0, 0]);
      expect(crossFade([0, 1, 2], 0, 0.25), [0.5, 0.5, 0]);
      expect(crossFade([0, 1, 2], 0, 0.5), [0, 1, 0]);
      expect(crossFade([0, 1, 2], 0, 1), [0, 0, 1]);
    });

    test("a pinned layer plays in full; the fader spans the rest", () {
      expect(crossFade([0, 1, 2], 1 << 0, 0), [1, 1, 0]);
      expect(crossFade([0, 1, 2], 1 << 0, 0.5), [1, 0.5, 0.5]);
      expect(crossFade([0, 1, 2], 1 << 0, 1), [1, 0, 1]);
    });

    test("one free layer, or none in use, plays in full", () {
      expect(crossFade([0, 1], 1 << 0, 0.7), [1, 1, 1]);
      expect(crossFade([2], 0, 0.3), [1, 1, 1]);
      expect(crossFade(const [], 0, 0.3), [1, 1, 1]);
    });
  });

  group("ElementMotion", () {
    var two = ElementMotion(
        clips: [across("a", 10), across("b", 20, layer: 1)],
        slots: const ["a", "b"]);

    test("spans the layers in use", () {
      expect(two.layersInUse, [0, 1]);
      expect(two.freeLayers, [0, 1]);
      var m = two.faded(1);
      expect([m.weight(0), m.weight(1)], [0, 1]);
      expect(m.fade, 1);
    });

    test("pinning keeps the weights following, but never every layer", () {
      var m = two.faded(1).pinnedAs(0, true);
      expect(m.isPinned(0), isTrue);
      expect([m.weight(0), m.weight(1)], [1, 1]);
      expect(identical(m.pinnedAs(1, true), m), isTrue,
          reason: "every layer pinned leaves nothing to fade");
      var back = m.pinnedAs(0, false);
      expect([back.weight(0), back.weight(1)], [0, 1]);
    });

    test("amount scales every layer; off is none", () {
      var m = two.faded(0.5).copyWith(amount: 0.5);
      expect([m.weight(0), m.weight(1)], [0.25, 0.25]);
      expect(m.layerWeight(0), 0.5, reason: "the fader's own weight");
      var off = m.copyWith(off: true);
      expect([off.weight(0), off.weight(1)], [0, 0]);
    });

    test("kept, and read back", () {
      var m = two.faded(0.75).pinnedAs(1, true).copyWith(
            amount: 0.4,
            off: true,
          );
      var back = ElementMotion.fromJson(m.toJson());
      expect(back.fade, 0.75);
      expect(back.pins, m.pins);
      expect(back.amount, 0.4);
      expect(back.off, isTrue);
      expect(back.weights, m.weights);
      expect(ElementMotion.fromJson(two.toJson()).toJson().keys,
          isNot(contains("pins")),
          reason: "nothing new written where nothing changed");
    });
  });

  test("switched off, an element is drawn as if it had no motion", () {
    var micros = 0;
    var c = CanvasController(CanvasDocument(
      frames: 24 * 20,
      frameRate: 24,
      audio: const AudioSettings(tempo: 120),
      elements: [
        ShapeElement(ElementBase(
            id: "a",
            width: 10,
            height: 10,
            motion: ElementMotion(
                clips: [across("go", 100)], slots: const ["go"]))),
      ],
    ));
    addTearDown(c.dispose);
    c.clockForTest = () => micros;
    double dx() =>
        poseWithMotion(c.document.elementById("a")!, c.frame, c.document,
                live: c.liveMotion)
            .dx;
    c.pressMotionSlot("a", 0);
    for (var i = 0; i < 48; i++) {
      micros += 1000000 ~/ 24;
      c.tickClockForTest();
    }
    expect(dx(), closeTo(100, 2));
    c.switchMotion("a", false);
    expect(c.document.elementById("a")!.base.motion.off, isTrue);
    expect(dx(), 0);
    c.switchMotion("a", true);
    expect(dx(), closeTo(100, 2));
    c.pause();
  });

  testWidgets("the row's motion button on the timeline switches it",
      (tester) async {
    var c = CanvasController(CanvasDocument(frames: 240, elements: [
      ShapeElement(ElementBase(
          id: "a",
          name: "Coin",
          width: 10,
          height: 10,
          motion:
              ElementMotion(clips: [across("go", 100)], slots: const ["go"]))),
    ]));
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(1400, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: CanvasTimeline(controller: c, height: 400),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("rowMotion-a")));
    await tester.pumpAndSettle();
    expect(c.document.elementById("a")!.base.motion.off, isTrue);
    await tester.tap(find.byKey(const ValueKey("rowMotion-a")));
    await tester.pumpAndSettle();
    expect(c.document.elementById("a")!.base.motion.off, isFalse);
  });
}
