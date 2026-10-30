import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/export/export_media.dart';
import 'package:bruig/plugin_system/canvas/export/mix_render.dart';
import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/media/mix/mix_graph.dart';
import 'package:bruig/plugin_system/canvas/model/automation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/ui/automation_lanes.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_channels.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart'
    show faderPosition, faderDb;
import 'package:bruig/plugin_system/canvas/ui/timeline_view.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart'
    show kSecondaryMouseButton, PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_automation_test.dart is automation: a channel's settings moved
// along the timeline by lanes of points -- read in straight lines, heard
// while playing without the strip starting again, held by a hand until it
// is handed back, written by a hand while armed, and in the export.

double rms(Float32List x, int from, int to) {
  var s = 0.0;
  for (var i = from; i < to; i++) {
    s += x[i] * x[i];
  }
  return math.sqrt(s / math.max(1, to - from));
}

void main() {
  group("a lane", () {
    test("goes in straight lines, and stays put past its ends", () {
      const lane = AutomationLane("volume", [(1, -20), (3, 0)]);
      expect(lane.valueAt(0), -20);
      expect(lane.valueAt(2), closeTo(-10, 1e-9));
      expect(lane.valueAt(5), 0);
      expect(const AutomationLane("volume").valueAt(1), isNull);
      // A choice steps from one point's value to the next.
      var steps = AutomationLane(
          AutomationTarget.deviceSetting(0, DeviceKind.autoFilter, "type").id,
          const [(0, 0), (2, 2)]);
      expect(steps.valueAt(1.9), 0);
      expect(steps.valueAt(2), 2);
    });

    test("is kept in the channel's file, and only when it is there", () {
      var mix = const ChannelMix(automation: [
        AutomationLane("volume", [(0, -6), (2.5, 0)]),
        AutomationLane("send:returnA", [(1, -12)]),
      ]);
      var back = ChannelMix.fromJson(mix.toJson());
      expect(back.automation, mix.automation);
      expect(const ChannelMix().toJson().containsKey("automation"), isFalse);
      expect(const ChannelMix(automation: [AutomationLane("volume")]).isDefault,
          isFalse);
      // An id it cannot read is left out.
      expect(
          ChannelMix.fromJson({
            "automation": [
              {"target": "nonsense", "points": []}
            ]
          }).automation,
          isEmpty);
    });

    test("each target reads back the height it is drawn at", () {
      var targets = [
        AutomationTarget.volume,
        AutomationTarget.pan,
        AutomationTarget.sendTo("returnA"),
        AutomationTarget.deviceSetting(0, DeviceKind.delay, "time"),
        AutomationTarget.deviceSetting(0, DeviceKind.vocoder, "formant"),
      ];
      for (var t in targets) {
        expect(AutomationTarget.parse(t.id)!.id, t.id);
        for (var h in [0.1, 0.5, 0.9]) {
          expect(t.height(t.valueAt(h)), closeTo(h, 1e-6), reason: t.id);
        }
      }
      // Volume is drawn as the fader has it.
      for (var db in const <double>[-40, -12, 0, 6]) {
        expect(AutomationTarget.volume.height(db),
            closeTo(1 - faderPosition(db), 1e-9));
        expect(faderLevel(1 - AutomationTarget.volume.height(db)),
            closeTo(faderDb(faderPosition(db)), 1e-6));
      }
    });

    test("puts its setting into the mix, but not one held by hand", () {
      var mix = ChannelMix(gainDb: -3, devices: const [
        MixDevice(DeviceKind.delay)
      ], automation: [
        const AutomationLane("volume", [(0, -20), (2, 0)]),
        const AutomationLane("pan", [(0, -1)]),
        const AutomationLane("send:returnB", [(0, -60), (2, 0)]),
        AutomationLane(
            AutomationTarget.deviceSetting(0, DeviceKind.delay, "time").id,
            const [(0, 100), (2, 500)]),
      ]);
      var at = automatedAt(mix, 1);
      expect(at.gainDb, closeTo(-10, 1e-9));
      expect(at.balance, -1);
      expect(at.sendDb("returnB"), closeTo(-30, 1e-9));
      expect(at.devices.single.value("time"), closeTo(300, 1e-9));
      expect(automatedAt(mix, 0).sendDb("returnB"), isNull,
          reason: "at the bottom, nothing is sent");
      var held = automatedAt(mix, 1, except: {"volume"});
      expect(held.gainDb, -3, reason: "held: the channel's own");
      expect(held.balance, -1);
      // A lane whose device is gone moves nothing.
      expect(automatedAt(mix.copyWith(devices: const []), 1).devices, isEmpty);
    });
  });

  group("the engine", () {
    test("a level moved glides over a block rather than jumping", () {
      var strip = StripProcessor(const ChannelMix());
      var l = Float32List(256)..fillRange(0, 256, 1);
      var r = Float32List(256)..fillRange(0, 256, 1);
      strip.level(l, r, 256);
      expect(l.last, 1);
      strip.retune(const ChannelMix(gainDb: -20));
      l.fillRange(0, 256, 1);
      r.fillRange(0, 256, 1);
      strip.level(l, r, 256);
      expect(l.first, greaterThan(0.95), reason: "from where it was");
      expect(l.last, closeTo(0.1, 1e-6), reason: "to where it is going");
    });

    test("a device's settings moved tune it, rather than making it again", () {
      for (var kind in DeviceKind.values) {
        var p = kind.params.where((p) => !p.isChoice).firstOrNull;
        if (p == null) continue;
        var strip = StripProcessor(ChannelMix(devices: [MixDevice(kind)]));
        var running = strip.devices.single;
        strip.retune(ChannelMix(
            devices: [MixDevice(kind).withValue(p.id, (p.min + p.max) / 2)]));
        // The vocoder, auto-tune and the listeners are made again: their
        // bands and windows are what their settings are.
        var tuned = running is Tunable;
        expect(identical(strip.devices.single, running), tuned,
            reason: kind.name);
        if (!const [
          DeviceKind.vocoder,
          DeviceKind.autoTune,
          DeviceKind.tuner,
          DeviceKind.spectrum,
        ].contains(kind)) {
          expect(tuned, isTrue, reason: "${kind.name} tunes in place");
        }
      }
    });

    test("an automated channel is retuned, so its delay rings on", () {
      var mix = const ChannelMix(devices: [
        MixDevice(DeviceKind.delay,
            values: {"time": 50, "feedback": 0.6, "mix": 1})
      ]);
      var g = MixGraph()
        ..setMaster(const MasterMix(limiter: false))
        ..setChannel("a", mix);
      var out = <double>[];
      for (var b = 0; b < 60; b++) {
        g.begin(512);
        var (l, r) = g.input("a", 512);
        if (b == 0) {
          l[0] = 1;
          r[0] = 1;
        }
        // The fader moving every block, as a lane moves it.
        g.setChannel("a", mix.copyWith(gainDb: -b * 0.1));
        var ol = Float32List(512), or = Float32List(512);
        g.finish(ol, or, 512);
        out.addAll(ol);
      }
      // Echoes still coming 0.4 s on: the delay never started over.
      var late =
          out.sublist(19000, 22000).fold(0.0, (m, v) => math.max(m, v.abs()));
      expect(late, greaterThan(1e-3));
    });
  });

  group("the controller", () {
    late CanvasController c;
    TimelineChannel channel() => c.timelineChannels.single;

    setUp(() {
      c = CanvasController(
          CanvasDocument(frames: 300, frameRate: 30, elements: [
            AudioElement(const ElementBase(id: "a", name: "Vocals"),
                clip: const MediaClip(
                    playlist: [MediaSource(assetId: "t", length: 10)],
                    timed: true,
                    mix: ChannelMix(gainDb: -3, automation: [
                      AutomationLane("volume", [(0, -30), (2, 0)]),
                    ]))),
          ]),
          audioEngine: FakeEngine({"t": 10}));
    });
    tearDown(() => c.dispose());

    test("the strip shows the lane where the playhead is", () {
      c.frame = 30;
      expect(c.mixNow(channel()).gainDb, closeTo(-15, 1e-9));
      expect(channel().mix.gainDb, -3, reason: "its own, untouched");
    });

    test("a hand holds a setting until it is handed back", () {
      c.frame = 30;
      var shown = c.mixNow(channel());
      c.changeChannelMix(channel(), shown, shown.copyWith(gainDb: -8));
      expect(c.overridden["a"], {"volume"});
      expect(c.anyOverridden, isTrue);
      expect(channel().mix.gainDb, -8);
      expect(channel().mix.automation.single.points, hasLength(2),
          reason: "the lane itself untouched");
      c.frame = 45;
      expect(c.mixNow(channel()).gainDb, -8, reason: "held where it was put");
      // Pan moved: not automated, so nothing is held for it.
      shown = c.mixNow(channel());
      c.changeChannelMix(channel(), shown, shown.copyWith(balance: 0.5));
      expect(c.overridden["a"], {"volume"});
      expect(channel().mix.gainDb, -8, reason: "not the lane's value");
      c.backToArrangement();
      expect(c.anyOverridden, isFalse);
      expect(c.mixNow(channel()).gainDb, closeTo(-7.5, 1e-9));
    });

    test("armed and playing, a hand writes the lane", () {
      c.frame = 30;
      c.automationArmed = true;
      c.play();
      addTearDown(c.pause);
      var shown = c.mixNow(channel());
      c.changeChannelMix(channel(), shown, shown.copyWith(gainDb: -9));
      var lane = channel().mix.automation.single;
      expect(lane.points, hasLength(3));
      expect(lane.points.where((p) => p.$2 == -9), hasLength(1));
      expect(c.anyOverridden, isFalse, reason: "written, not held");
      // A setting with no lane yet starts one.
      shown = c.mixNow(channel());
      c.changeChannelMix(channel(), shown, shown.copyWith(balance: -0.5));
      expect(channel().mix.automation.map((l) => l.target), ["volume", "pan"]);
    });

    test("a device's knobs show its lane, and taking it out takes the lane",
        () {
      var d = AutomationTarget.deviceSetting(1, DeviceKind.chorus, "rate").id;
      c.setChannelMix(
          channel(),
          channel().mix.copyWith(devices: const [
            MixDevice(DeviceKind.gate),
            MixDevice(DeviceKind.chorus),
          ], automation: [
            AutomationLane(d, const [(0, 1), (2, 3)]),
          ]));
      c.frame = 30;
      expect(c.devicesOf("a")[1].value("rate"), closeTo(2, 1e-9));
      // The gate taken out: the chorus is first now, and so is its lane.
      c.setDevicesOf("a", [c.devicesOf("a")[1]]);
      expect(channel().mix.devices.single.kind, DeviceKind.chorus);
      expect(channel().mix.devices.single.value("rate"), 0.8,
          reason: "its own setting, not the lane's");
      expect(channel().mix.automation.single.target,
          AutomationTarget.deviceSetting(0, DeviceKind.chorus, "rate").id);
    });
  });

  test("an export follows a volume lane", () async {
    var which = await Process.run("which", ["ffmpeg"]);
    if (which.exitCode != 0) {
      markTestSkipped("ffmpeg is not installed");
      return;
    }
    var dir = await Directory.systemTemp.createTemp("canvas-automation");
    addTearDown(() => dir.delete(recursive: true));
    var tone = path.join(dir.path, "tone.wav");
    await Process.run("ffmpeg", [
      "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=3", tone //
    ]);
    var out = path.join(dir.path, "mix.wav");
    // Its scene starts a second in: the lane is counted from there.
    expect(
        await renderMixWav([
          ExportSound(
              path: tone,
              at: 0,
              from: 0,
              length: 3,
              channel: "a",
              clock: 1,
              mix: const ChannelMix(automation: [
                AutomationLane("volume", [(0, -40), (1, 0)]),
              ])),
        ], const MasterMix(limiter: false),
            seconds: 3, ffmpeg: "ffmpeg", out: out),
        isTrue);
    var pcm = (await File(out).readAsBytes()).buffer.asFloat32List(44);
    var left = Float32List.fromList(
        [for (var i = 0; i < pcm.length ~/ 2; i++) pcm[i * 2]]);
    double db(double from, double to) =>
        20 *
        math.log(rms(left, (from * 48000).round(), (to * 48000).round())) /
        math.ln10;
    // ffmpeg's sine is an eighth of full scale: −21.1 dB RMS.
    expect(db(0, 0.9), closeTo(-61.1, 0.5),
        reason: "before its scene: −40, from the very start");
    expect(db(1.45, 1.55), closeTo(-41.1, 1.5), reason: "halfway: −20");
    expect(db(2.2, 2.9), closeTo(-21.1, 0.5), reason: "at the top: 0 dB");
  });

  group("on the timeline", () {
    late CanvasController c;
    TimelineChannel channel() => c.timelineChannels.single;
    List<AutomationPoint> points(String target) =>
        c.automationLaneOf(channel(), target)?.points ?? const [];

    Future<void> open(WidgetTester tester, {double scale = 1}) async {
      c = CanvasController(
          CanvasDocument(frames: 300, frameRate: 30, elements: [
            AudioElement(const ElementBase(id: "a", name: "Vocals"),
                clip: const MediaClip(
                    playlist: [MediaSource(assetId: "t", length: 10)],
                    timed: true)),
          ]),
          audioEngine: FakeEngine({"t": 10}));
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(1000, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ],
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: Scaffold(
                body: Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                        height: 400,
                        child: CanvasChannels(
                            controller: c, view: TimelineView.whole(300)))))),
      ));
      await tester.pump();
    }

    /// at is where [seconds] and height [h] are on lane [i]: 850 wide for
    /// ten seconds, beside a strip 150 wide.
    Offset at(WidgetTester tester, double seconds, double h, [int i = 0]) {
      var body = tester.getRect(find.byKey(ValueKey("autoRow-a-$i")));
      return Offset(body.left + 150 + seconds * 85,
          body.top + 6 + (1 - h) * (automationLaneHeight - 12));
    }

    testWidgets("A opens a lane: points put down, moved and taken out",
        (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey("channelAutomation")));
      await tester.pump();
      expect(find.byKey(const ValueKey("autoRow-a-0")), findsOneWidget);
      expect(
          tester
              .widget<DropdownButton<String>>(
                  find.byKey(const ValueKey("autoTarget-a-0")))
              .value,
          "volume",
          reason: "a channel with none opens on its volume");
      // A click: a point, to the sixteenth, at the height pressed.
      await tester.tapAt(at(tester, 1.01, 0.5), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(points("volume").single.$1, 1.0);
      expect(AutomationTarget.volume.height(points("volume").single.$2),
          closeTo(0.5, 0.02));
      // Dragged a second on and to the top.
      var drag = await tester.startGesture(at(tester, 1, 0.5),
          kind: PointerDeviceKind.mouse);
      for (var i = 0; i < 10; i++) {
        await drag.moveBy(const Offset(8.5, -2.2));
        await tester.pump();
      }
      await drag.up();
      await tester.pump();
      expect(points("volume").single.$1, 2.0);
      expect(points("volume").single.$2, greaterThan(0));
      expect(find.byKey(const ValueKey("autoClear-a-0")), findsOneWidget);
      // Right-clicked, taken out -- and the lane with it.
      var p = points("volume").single;
      await tester.tapAt(at(tester, p.$1, AutomationTarget.volume.height(p.$2)),
          buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(channel().mix.automation, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets("lanes are added, switched and hidden, their points kept",
        (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey("channelAutomation")));
      await tester.pump();
      await tester.tapAt(at(tester, 2, 0.8), kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("autoAdd-a")));
      await tester.pump();
      expect(c.automationRows(channel()), ["volume", "pan"]);
      // Switched to a send: its own lane, empty; the volume's points kept.
      c.showAutomationRow(channel(), 1, "send:returnA");
      await tester.pump();
      expect(find.text("Send A · Reverb"), findsOneWidget);
      expect(points("volume"), hasLength(1));
      // Hidden: still played.
      await tester.tap(find.byKey(const ValueKey("autoHide-a-0")));
      await tester.pump();
      expect(c.automationRows(channel()), ["send:returnA"]);
      expect(points("volume"), hasLength(1));
      // Cleared: gone.
      c.showAutomationRow(channel(), 0, "volume");
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("autoClear-a-0")));
      await tester.pump();
      expect(points("volume"), isEmpty);
      expect(tester.takeException(), isNull);
    });

    for (var scale in [1.0, 1.5]) {
      testWidgets("a lane held by hand says so, and fits, at $scale",
          (tester) async {
        await open(tester, scale: scale);
        c.setAutomationPoints(channel(), "volume", const [(0, -20), (5, 0)]);
        c.toggleAutomation("a");
        await tester.pump();
        var shown = c.mixNow(channel());
        c.changeChannelMix(channel(), shown, shown.copyWith(gainDb: -3));
        await tester.pump();
        expect(find.text("held"), findsOneWidget);
        expect(find.text("−3.0 dB"), findsOneWidget,
            reason: "the lane reads what is heard: the hand's");
        expect(tester.takeException(), isNull);
        c.backToArrangement();
        await tester.pump();
        expect(find.text("held"), findsNothing);
        expect(find.text("−20.0 dB"), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
