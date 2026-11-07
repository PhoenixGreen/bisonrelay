import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart' show dbToGain;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_split_test.dart is a Split: its sound into branches side by side,
// each its own chain of devices, and back together -- in parallel, as its
// middle and sides, its left and right, or its lows and highs.

const int rate = 48000;

MixDevice split(int mode, List<SplitBranch> branches) => MixDevice(
    DeviceKind.split,
    values: {"mode": mode.toDouble(), "crossover": 800}).withBranches(branches);

/// muted is a branch heard not at all.
const SplitBranch muted = SplitBranch(mute: true);

/// run puts half a second of [left] and [right] through [d].
(Float32List, Float32List) run(
    MixDevice d, Float32List left, Float32List right) {
  var p = DeviceProcessor.of(d)!;
  var l = Float32List.fromList(left), r = Float32List.fromList(right);
  for (var at = 0; at < l.length; at += 512) {
    var n = math.min(512, l.length - at);
    p.process(Float32List.sublistView(l, at, at + n),
        Float32List.sublistView(r, at, at + n), n);
  }
  return (l, r);
}

Float32List tone(double hz, [double level = 0.3]) => Float32List.fromList([
      for (var i = 0; i < rate ~/ 2; i++)
        level * math.sin(2 * math.pi * hz * i / rate)
    ]);

double rms(Float32List x) {
  var sum = 0.0;
  for (var i = x.length ~/ 4; i < x.length; i++) {
    sum += x[i] * x[i];
  }
  return math.sqrt(sum / (x.length - x.length ~/ 4));
}

void main() {
  group("the model", () {
    test("its branches are kept, each device with its id", () {
      var d = split(0, [
        const SplitBranch(
            devices: [MixDevice(DeviceKind.delay)], gainDb: -3, mute: true),
        const SplitBranch(devices: [MixDevice(DeviceKind.reverb)]),
      ]);
      var back = MixDevice.fromJson(d.toJson())!;
      expect(back, d);
      expect(back.branches[0].gainDb, -3);
      expect(back.branches[0].mute, isTrue);
      expect(back.branches[1].devices.single.id, isNotEmpty);
      expect(back.switched(false).branches, d.branches);
    });

    test("no split in a split", () {
      var json = split(0, const [SplitBranch()]).toJson()
        ..["branches"] = [
          {
            "devices": [
              {"kind": "split"},
              {"kind": "delay"}
            ]
          }
        ];
      expect(
          MixDevice.fromJson(json)!.branches.single.devices.map((d) => d.kind),
          [DeviceKind.delay]);
    });

    test("its branches' names, by how it splits", () {
      expect(splitBranchNames(0, 3), ["Branch A", "Branch B", "Branch C"]);
      expect(splitBranchNames(1, 0), ["Mid", "Side"]);
      expect(splitBranchNames(3, 5), ["Low", "High"]);
    });
  });

  group("the sound", () {
    test("in parallel, the branches summed", () {
      var x = tone(440);
      var (l, _) = run(split(0, const [SplitBranch(), SplitBranch()]), x, x);
      expect(rms(l), closeTo(2 * rms(x), 1e-4), reason: "two of it");
      (l, _) = run(split(0, const [SplitBranch(), muted]), x, x);
      expect(rms(l), closeTo(rms(x), 1e-4), reason: "one muted");
      (l, _) = run(split(0, const []), x, x);
      expect(rms(l), closeTo(rms(x), 1e-6), reason: "none: as it was");
    });

    test("mid and side: the sides taken away leaves it mono", () {
      var a = tone(440), b = tone(660);
      var (l, r) = run(split(1, const [SplitBranch(), muted]), a, b);
      for (var i = 0; i < l.length; i += 97) {
        expect(l[i], closeTo(r[i], 1e-6));
        expect(l[i], closeTo((a[i] + b[i]) / 2, 1e-6));
      }
      // Nothing taken away: as it was.
      (l, r) = run(split(1, const [SplitBranch(), SplitBranch()]), a, b);
      expect(l[1234], closeTo(a[1234], 1e-6));
      expect(r[1234], closeTo(b[1234], 1e-6));
    });

    test("left and right, each its own", () {
      var a = tone(440), b = tone(660);
      var (l, r) = run(split(2, const [SplitBranch(), muted]), a, b);
      expect(rms(l), closeTo(rms(a), 1e-4));
      expect(rms(r), 0);
    });

    test("lows and highs part at the crossover and sum back flat", () {
      var low = tone(100), high = tone(6000);
      var both = split(3, const [SplitBranch(), SplitBranch()]);
      expect(rms(run(both, low, low).$1), closeTo(rms(low), rms(low) * 0.02));
      expect(
          rms(run(both, high, high).$1), closeTo(rms(high), rms(high) * 0.02));
      var lowsOnly = split(3, const [SplitBranch(), muted]);
      expect(rms(run(lowsOnly, low, low).$1), greaterThan(rms(low) * 0.95));
      expect(rms(run(lowsOnly, high, high).$1), lessThan(rms(high) * 0.02),
          reason: "its highs taken away");
    });

    test("a branch's device runs, and a setting moved is retuned in place", () {
      var d = split(0, const [
        SplitBranch(devices: [
          MixDevice(DeviceKind.utility, id: "d0", values: {"gain": -6})
        ]),
      ]);
      var x = tone(440);
      var (l, _) = run(d, x, x);
      expect(rms(l), closeTo(rms(x) * dbToGain(-6), 1e-4));
      var p = DeviceProcessor.of(d)! as Tunable;
      var louder = d.withBranches([
        SplitBranch(devices: [
          d.branches[0].devices[0].withValue("gain", 0),
        ]),
      ]);
      p.tune(louder);
      var l2 = Float32List.fromList(x), r2 = Float32List.fromList(x);
      (p as DeviceProcessor).process(l2, r2, l2.length);
      expect(rms(l2), closeTo(rms(x), 1e-3));
    });
  });

  testWidgets("its branches on its card: added, filled and taken away",
      (tester) async {
    var c = CanvasController(
        CanvasDocument(frames: 100, elements: [
          AudioElement(const ElementBase(id: "a", name: "Pad"),
              clip: const MediaClip(
                  playlist: [MediaSource(assetId: "t", length: 2)],
                  timed: true)),
        ]),
        audioEngine: FakeEngine({"t": 2}));
    addTearDown(c.dispose);
    c.setDevicesOf("a", [const MixDevice(DeviceKind.split)]);
    c.openEffects("a");
    tester.view.physicalSize = const Size(2200, 1000);
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
                  builder: (context, _) => Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            CanvasMixer.effects(
                                controller: c,
                                height: 520,
                                onResize: (_) {},
                                onClose: () {}),
                          ])))),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    for (var n = 0; n < 2; n++) {
      await tester.ensureVisible(find.byKey(const ValueKey("splitAddBranch")));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("splitAddBranch")));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(c.devicesOf("a").single.branches.length, 2);
    await tester.ensureVisible(find.byKey(const ValueKey("splitAdd-1")));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey("splitAdd-1")));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text("Delay").last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.devicesOf("a").single.branches[1].devices.single.kind,
        DeviceKind.delay);
    expect(find.byKey(const ValueKey("splitDevice-1-0")), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey("splitRemove-0")));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey("splitRemove-0")));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.devicesOf("a").single.branches.single.devices.single.kind,
        DeviceKind.delay);
    // Ken: the prototype's rows, one branch open beside them.
    await tester.ensureVisible(find.byKey(const ValueKey("splitAddBranch")));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey("splitAddBranch")));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey("splitEditor-1")), findsOneWidget,
        reason: "a branch added is opened");
    await tester.tap(find.byKey(const ValueKey("splitBranch-0")));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey("splitEditor-0")), findsOneWidget);
    expect(find.byKey(const ValueKey("splitDevice-0-0")), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("splitMode-3")));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.devicesOf("a").single.value("mode"), 3);
    expect(find.byKey(const ValueKey("splitCrossover")), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
