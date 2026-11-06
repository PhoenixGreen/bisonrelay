import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/media/mix/mix_graph.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/surround.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_surround_output_test.dart is where a piece's sound goes out: the
// master's Output (its speakers, a meter each, and which are heard here --
// all folded down, or one group alone) and a channel's Centre (how much of
// what is in front its centre speaker carries).

const _l = 0, _r = 1, _c = 2, _lfe = 3, _ls = 4, _rs = 5;

double _rms(Float32List x) {
  var sum = 0.0;
  for (var v in x) {
    sum += v * v;
  }
  return math.sqrt(sum / x.length);
}

/// _run plays a tone on channel "a" with [mix] through a graph for
/// [layout], hearing [hear], and gives each speaker's level, the two heard
/// here, and each speaker's peak as the graph reports it.
(List<double>, double, double, List<double>) _run(
    SpeakerLayout layout, ChannelMix mix,
    {SpeakerGroup hear = SpeakerGroup.all}) {
  var g = MixGraph()
    ..setSpeakers(layout)
    ..setMaster(const MasterMix(limiter: false))
    ..setChannel("a", mix)
    ..hear = hear;
  const n = 2048;
  var tone = Float32List.fromList([
    for (var i = 0; i < n; i++) 0.5 * math.sin(2 * math.pi * 1000 * i / mixRate)
  ]);
  var l = Float32List(n), r = Float32List(n);
  for (var b = 0; b < 8; b++) {
    g.begin(n);
    var (il, ir) = g.input("a", n);
    il.setRange(0, n, tone);
    ir.setRange(0, n, tone);
    g.finish(l, r, n);
  }
  return (
    [for (var s in g.speakers) _rms(s)],
    _rms(l),
    _rms(r),
    [for (var c = 0; c < layout.channels; c++) g.levels(speakerLevelKey(c)).$1],
  );
}

void main() {
  group("Centre", () {
    test("kept, and only where it is not all", () {
      const pan = SurroundPan(angle: 20, width: 40, centre: 0.25);
      expect(SurroundPan.fromJson(pan.toJson()), pan);
      expect(const SurroundPan().toJson().containsKey("centre"), isFalse);
      expect(const SurroundPan(centre: 0.5).isDefault, isFalse);
      expect(const SurroundPan().copyWith(centre: 3).centre, 1);
    });

    test("straight ahead: all on the centre, or none, or shared", () {
      const layout = SpeakerLayout.surround51;
      var all = panGains(layout, 0);
      expect(all[_c], closeTo(1, 1e-9));
      var none = panGains(layout, 0, centre: 0);
      expect(none[_c], 0);
      expect(none[_l], closeTo(math.sqrt1_2, 1e-9));
      expect(none[_r], closeTo(math.sqrt1_2, 1e-9));
      for (var centre in [0.0, 0.3, 0.5, 0.9]) {
        var g = panGains(layout, 12, centre: centre);
        var power = g.fold(0.0, (a, x) => a + x * x);
        expect(power, closeTo(1, 1e-9), reason: "centre $centre");
      }
      expect(panGains(layout, 0, centre: 0.5)[_c], closeTo(math.sqrt1_2, 1e-9));
      // Behind, there is no centre to take from.
      expect(panGains(layout, 160, centre: 0), panGains(layout, 160));
      // Stereo has none either.
      expect(panGains(SpeakerLayout.stereo, 0, centre: 0),
          panGains(SpeakerLayout.stereo, 0));
    });

    test("a channel's Centre at nought leaves its centre speaker silent", () {
      var (on, _, _, _) = _run(SpeakerLayout.surround51,
          const ChannelMix().withSurround(const SurroundPan(width: 0)));
      var (off, _, _, _) = _run(
          SpeakerLayout.surround51,
          const ChannelMix()
              .withSurround(const SurroundPan(width: 0, centre: 0)));
      expect(on[_c], greaterThan(0.3));
      expect(off[_c], lessThan(1e-4));
      expect(off[_l], closeTo(off[_r], 1e-4));
      expect(off[_l], greaterThan(0.2));
    });
  });

  group("heard here", () {
    test("each group alone: on its own side, the centre and LFE on both", () {
      const half = 0.7071067811865476;
      var front = hearFold(SpeakerLayout.surround51, SpeakerGroup.front);
      expect(front[_l], (1.0, 0.0));
      expect(front[_r], (0.0, 1.0));
      expect([front[_c], front[_lfe], front[_ls], front[_rs]],
          everyElement((0.0, 0.0)));
      var back = hearFold(SpeakerLayout.surround51, SpeakerGroup.surround);
      expect(back[_ls], (1.0, 0.0));
      expect(back[_rs], (0.0, 1.0));
      expect(back[_l], (0.0, 0.0));
      // 7.1's sides and backs share their side.
      var seven = hearFold(SpeakerLayout.surround71, SpeakerGroup.surround);
      expect([for (var g in seven) g].where((g) => g.$1 > 0).toList(),
          [(half, 0.0), (half, 0.0)]);
      expect(hearFold(SpeakerLayout.surround51, SpeakerGroup.lfe)[_lfe],
          (half, half));
      expect(hearFold(SpeakerLayout.surround51, SpeakerGroup.all),
          foldDown(SpeakerLayout.surround51));
    });

    test("a sound behind: heard with the surrounds, silent with the fronts",
        () {
      var behind = const ChannelMix()
          .withSurround(const SurroundPan(angle: 180, width: 0));
      var (speakers, l, r, _) =
          _run(SpeakerLayout.surround51, behind, hear: SpeakerGroup.surround);
      expect(l, greaterThan(0.1));
      expect(r, greaterThan(0.1));
      var (same, fl, fr, _) =
          _run(SpeakerLayout.surround51, behind, hear: SpeakerGroup.front);
      expect(fl + fr, lessThan(1e-4));
      // What is heard changes; the speakers do not.
      for (var c = 0; c < speakers.length; c++) {
        expect(same[c], closeTo(speakers[c], 1e-6));
      }
    });

    test("each speaker's peak is reported, for its meter", () {
      var (_, _, _, peaks) = _run(
          SpeakerLayout.surround51,
          const ChannelMix()
              .withSurround(const SurroundPan(angle: 110, width: 0)));
      expect(peaks[_rs], greaterThan(0.3));
      expect(peaks[_l], lessThan(1e-3));
      var (_, _, _, stereo) = _run(SpeakerLayout.stereo, const ChannelMix());
      expect(stereo, hasLength(2));
      expect(stereo[0], greaterThan(0.3));
    });

    test("the controller hands what is heard to the engine", () {
      var engine = FakeEngine({});
      var c = CanvasController(
          const CanvasDocument(
              audio: AudioSettings(speakers: SpeakerLayout.surround51)),
          audioEngine: engine);
      addTearDown(c.dispose);
      c.hearSpeakers(SpeakerGroup.lfe);
      expect(c.hear, SpeakerGroup.lfe);
    });
  });

  group("the master's Output", () {
    Future<CanvasController> show(WidgetTester tester,
        {SpeakerLayout speakers = SpeakerLayout.surround51,
        double scale = 1,
        double height = 420}) async {
      var c = CanvasController(
          CanvasDocument(
              frames: 100,
              audio: AudioSettings(speakers: speakers),
              elements: [
                AudioElement(const ElementBase(id: "a", name: "Music"),
                    clip: const MediaClip(timed: true)),
              ]),
          audioEngine: FakeEngine({}));
      c.openEffects(mixerMasterKey);
      tester.view.physicalSize = const Size(1600, 900);
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
                    alignment: Alignment.bottomCenter,
                    child: ListenableBuilder(
                        listenable: c,
                        builder: (context, _) => CanvasMixer.effects(
                            controller: c,
                            height: height,
                            onResize: (_) {},
                            onClose: () {}))))),
      ));
      await tester.pump();
      return c;
    }

    testWidgets("its speakers, a meter each, and what is heard",
        (tester) async {
      var c = await show(tester);
      addTearDown(c.dispose);
      expect(find.byKey(const ValueKey("outputMeters")), findsOneWidget,
          reason: "last in the master's chain");
      var hear = find.byKey(const ValueKey("outputHear"));
      expect(hear, findsOneWidget);
      var options = tester
          .widget<CanvasDropdown<SpeakerGroup>>(hear)
          .options
          .map((o) => o.$1);
      expect(options, SpeakerGroup.values, reason: "5.1 has every group");
      tester
          .widget<CanvasDropdown<SpeakerGroup>>(hear)
          .onChanged(SpeakerGroup.surround);
      await tester.pump();
      expect(c.hear, SpeakerGroup.surround);
      // Back to stereo: nothing to pick from.
      tester
          .widget<CanvasDropdown<SpeakerLayout>>(
              find.byKey(const ValueKey("outputSpeakers")))
          .onChanged(SpeakerLayout.stereo);
      await tester.pump();
      expect(c.document.audio.speakers, SpeakerLayout.stereo);
      expect(find.byKey(const ValueKey("outputHear")), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("it fits, at every text size", (tester) async {
      var failures = <String>[];
      for (var scale in [1.0, 1.25, 1.5]) {
        for (var speakers in [SpeakerLayout.stereo, SpeakerLayout.surround71]) {
          for (var height in [220.0, 320.0, 460.0]) {
            var c = await show(tester,
                speakers: speakers, scale: scale, height: height);
            if (tester.takeException() case var e?) {
              failures.add("$speakers $height ${scale}x: "
                  "${e.toString().split("\n").first}");
            }
            await tester.pumpWidget(const SizedBox());
            c.dispose();
          }
        }
      }
      expect(failures, isEmpty);
    });
  });
}
