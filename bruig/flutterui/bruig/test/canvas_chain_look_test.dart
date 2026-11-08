import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/modulation.dart';
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/chain_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:bruig/plugin_system/canvas/ui/phrasing_editor.dart';
import 'package:bruig/plugin_system/canvas/model/session.dart';
import 'package:bruig/plugin_system/canvas/ui/pitch_editing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';
import 'canvas_chain_helpers.dart';

// canvas_chain_look_test.dart is the Chain drawn as the prototype draws it:
// one header row -- what it shows, its sound or motion, its views, its
// heights and filling the window -- and every device one kind of card, its
// knobs' values typed in when double-clicked.

CanvasController make() => CanvasController(
    CanvasDocument(frames: 100, elements: [
      AudioElement(const ElementBase(id: "m", name: "Music"),
          clip: const MediaClip(
              playlist: [MediaSource(assetId: "t", length: 8)],
              timed: true,
              mix: ChannelMix(devices: [
                MixDevice(DeviceKind.chorus, id: "d0"),
                MixDevice(DeviceKind.reverb, id: "d1"),
              ]))),
    ]),
    audioEngine: FakeEngine({"t": 8}));

Future<void> show(WidgetTester tester, CanvasController c,
    {double height = 370, ValueChanged<double>? onResize}) async {
  tester.view.physicalSize = const Size(1400, 600);
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
            body: Align(
                alignment: Alignment.bottomCenter,
                child: ListenableBuilder(
                    listenable: c,
                    builder: (context, _) => ChainPanel(
                        controller: c,
                        height: height,
                        onResize: onResize ?? (_) {}))))),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group("a value typed", () {
    test("read in the knob's own terms, held to its range", () {
      expect(typedValue("40", "50%", 0, 1), closeTo(0.4, 1e-9));
      expect(typedValue("40%", "50%", 0, 1), closeTo(0.4, 1e-9));
      expect(typedValue("1.2k", "800 Hz", 20, 20000), 1200);
      expect(typedValue("2", "1.8 kHz", 20, 20000), 2000,
          reason: "a kilohertz knob takes kilohertz");
      expect(typedValue("−6", "0.0 dB", -24, 24), -6);
      expect(typedValue("99", "0.0 dB", -24, 24), 24);
      expect(typedValue("loud", "0.0 dB", -24, 24), isNull);
    });

    testWidgets("its value double-clicked takes a number; Escape leaves it",
        (tester) async {
      var c = make();
      addTearDown(c.dispose);
      c.openEffects("m");
      await show(tester, c);
      var depth = find.descendant(
          of: find.byKey(const ValueKey("device-0-depth")),
          matching: find.byKey(const ValueKey("knobValue-Depth")));
      await tester.ensureVisible(depth);
      await tester.pump();
      await tester.tap(depth);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(depth);
      await tester.pump(const Duration(milliseconds: 300));
      var field = find.byKey(const ValueKey("knobTyped-Depth"));
      expect(field, findsOneWidget);
      await tester.enterText(field, "35");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(c.devicesOf("m").first.value("depth"), closeTo(0.35, 1e-9));
      expect(find.byKey(const ValueKey("knobTyped-Depth")), findsNothing);
      // Escape: as it was -- a moment later, as a hand would.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(depth);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(depth);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
          find.byKey(const ValueKey("knobTyped-Depth")), "90");
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(c.devicesOf("m").first.value("depth"), closeTo(0.35, 1e-9));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  // Ken: scrolling through the chain with two fingers changed settings.
  testWidgets("a trackpad's scroll over a knob scrolls; a drag turns it",
      (tester) async {
    var c = make();
    addTearDown(c.dispose);
    c.openEffects("m");
    await show(tester, c);
    var depth = find.byKey(const ValueKey("device-0-depth"));
    await tester.ensureVisible(depth);
    await tester.pump();
    double now() => c.devicesOf("m").first.value("depth");
    var was = now();
    var pan = await tester.startGesture(tester.getCenter(depth),
        kind: PointerDeviceKind.trackpad);
    for (var i = 0; i < 6; i++) {
      await pan.panZoomUpdate(tester.getCenter(depth),
          pan: Offset(0, -12.0 * (i + 1)));
      await tester.pump();
    }
    await pan.panZoomEnd();
    await tester.pump();
    expect(now(), was, reason: "a scroll, not a turn");
    // Pressed and dragged, it turns.
    await tester.drag(depth, const Offset(0, -40),
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(now(), greaterThan(was));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("an audio chain starts with its Clips: its level and fades",
      (tester) async {
    var c = make();
    addTearDown(c.dispose);
    c.openEffects("m");
    await show(tester, c);
    double x(String key) => tester.getTopLeft(find.byKey(ValueKey(key))).dx;
    expect(x("chainZone-Macros"), lessThan(x("chainZone-Source")));
    expect(x("chainZone-Source"), lessThan(x("chainZone-Effects")));
    MediaClip clip() => (c.document.elements.single as AudioElement).clip;
    var level = find.byKey(const ValueKey("audioClipsGain"));
    await tester.ensureVisible(level);
    await tester.pump();
    var was = clip().volume;
    await tester.drag(level, const Offset(0, -30),
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(clip().volume, greaterThan(was));
    await tester.drag(
        find.byKey(const ValueKey("audioClipsFadeIn")), const Offset(0, -30),
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    // The timeline's own fade: the same one the clip editor sets.
    expect(clip().fadeIn, greaterThan(0));
    c.undo();
    expect(clip().fadeIn, 0, reason: "one undo step a turn");
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
  });

  // Ken: the Clips device was missing much of the prototype's.
  testWidgets(
      "Clips: a chip a sound, its slot clips launched, transposed, warped",
      (tester) async {
    var c = make();
    addTearDown(c.dispose);
    for (var (i, n) in ["Bed A", "Sting"].indexed) {
      c.clipFromSound("m", i, MediaSource(assetId: "t", length: 8, name: n));
    }
    c.openEffects("m");
    await show(tester, c, height: 400);
    // The timeline's sound and the two slots.
    for (var k in [
      "audioClipsChip--1",
      "audioClipsChip-0",
      "audioClipsChip-1"
    ]) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
    // A timeline sound is a clip as a slot's is: transposed too.
    expect(find.byKey(const ValueKey("audioClipsTranspose")), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("audioClipsChip-0")));
    await tester.pump();
    var transpose = find.byKey(const ValueKey("audioClipsTranspose"));
    await tester.ensureVisible(transpose);
    await tester.pump();
    await tester.drag(transpose, const Offset(0, -40),
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(c.session.at("m", 0)!.pitch, greaterThan(0));
    // Warped, in Tones; its Warp page says so.
    var tones = find.byKey(const ValueKey("audioClipsWarp-tones"));
    await tester.ensureVisible(tones);
    await tester.pump();
    await tester.tap(tones);
    await tester.pump();
    expect(c.session.at("m", 0)!.warp, isTrue);
    expect(c.session.at("m", 0)!.warpMode, WarpMode.tones);
    await tester.tap(find.byKey(const ValueKey("audioClipsPageWarp")));
    await tester.pump();
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey("audioClipsWarpReadout")))
            .data,
        contains("Tones"));
    // Launched from its chip.
    await tester.tap(find.byKey(const ValueKey("audioClipsLaunch-1")));
    await tester.pump();
    expect(c.clipState("m", 1), anyOf(ClipState.playing, ClipState.queued));
    c.stopAllClips();
    c.pause();
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("Auto-tune: its notes, its key and scale as buttons, Live",
      (tester) async {
    var c = make();
    addTearDown(c.dispose);
    c.setDevicesOf("m", const [MixDevice(DeviceKind.autoTune, id: "d0")]);
    pitchTrackSeed("t", [
      for (var i = 0; i < 100; i++) i % 25 > 20 ? null : 60.3 + (i ~/ 25) * 2,
    ]);
    c.openEffects("m");
    await show(tester, c, height: 420);
    expect(find.byKey(const ValueKey("autoTuneNotesView-0")), findsOneWidget,
        reason: "a recording: its notes first");
    await tester.pump(const Duration(milliseconds: 100));
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey("autoTuneCaption-0")))
            .data,
        contains("corrected"));
    // D, then minor.
    var d = find.byKey(const ValueKey("autoTuneKey-0-2"));
    await tester.ensureVisible(d);
    await tester.pump();
    await tester.tap(d);
    await tester.pump();
    expect(c.devicesOf("m").single.value("key"), 2);
    await tester.tap(find.byKey(const ValueKey("autoTuneScale-0-2")));
    await tester.pump();
    expect(c.devicesOf("m").single.value("scale"), 2);
    await tester.tap(find.byKey(const ValueKey("autoTuneLive-0")));
    await tester.pump();
    expect(find.byKey(const ValueKey("autoTuneHeard-0")), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
  });

  test("a channel's devices keep what they move when another is turned", () {
    var c = make();
    addTearDown(c.dispose);
    c.setDevicesOf("m", [
      ...c.devicesOf("m"),
      const MixDevice(DeviceKind.lfo,
          id: "d2", mods: [ModTarget("d0", "depth")]),
      const MixDevice(DeviceKind.macro, id: "d3", variations: [
        {"m1": 0.5}
      ]),
    ]);
    c.setDevicesOf("m", [
      for (var d in c.devicesOf("m"))
        d.kind == DeviceKind.chorus ? d.withValue("depth", 0.2) : d
    ]);
    var now = c.devicesOf("m");
    expect(now.firstWhere((d) => d.kind == DeviceKind.lfo).mods,
        [const ModTarget("d0", "depth")]);
    expect(now.firstWhere((d) => d.kind == DeviceKind.macro).variations,
        hasLength(1));
    expect(now.first.value("depth"), 0.2);
  });

  // Ken, 2026-11-08: "Macro 1 -- what is it set to, what can it be set
  // to, and how can it be set?"
  testWidgets("each macro says what it turns, and is given knobs to turn",
      (tester) async {
    var c = make();
    addTearDown(c.dispose);
    c.setDevicesOf("m", [
      ...c.devicesOf("m"),
      const MixDevice(DeviceKind.macro, id: "d2"),
    ]);
    c.openEffects("m");
    await show(tester, c);
    MixDevice macro() =>
        c.devicesOf("m").firstWhere((d) => d.kind == DeviceKind.macro);
    var index = c.devicesOf("m").indexOf(macro());
    expect(find.text("Not set"), findsNWidgets(8));
    // Macro 2 picked, given the reverb's size.
    var pick = find.byKey(ValueKey("macroPick-$index-1"));
    await tester.ensureVisible(pick);
    await tester.pump();
    await tester.tapAt(tester.getBottomLeft(pick) + const Offset(28, -4));
    await tester.pump();
    expect(find.text("MACRO 2 TURNS"), findsOneWidget);
    await tester.tap(find.byKey(ValueKey("macroAdd-$index")));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey("macroAddDevice-$index-Reverb")));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey("macroAddKnob-$index-d1-size")));
    await tester.pump();
    await tester.pump();
    expect(macro().mods, [const ModTarget("d1", "size", 0.5, 1)]);
    expect(find.text("Size"), findsWidgets,
        reason: "under Macro 2, what it turns");
    expect(find.text("Reverb · Size"), findsOneWidget);
    // Taken off again.
    await tester.tap(find.byKey(ValueKey("macroRemove-$index-0")));
    await tester.pump();
    expect(macro().mods, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("the macros are eight, set at random, kept as variations",
      (tester) async {
    var c = make();
    addTearDown(c.dispose);
    c.setDevicesOf("m", [
      ...c.devicesOf("m"),
      const MixDevice(DeviceKind.macro, id: "d2"),
    ]);
    c.openEffects("m");
    await show(tester, c);
    MixDevice macro() =>
        c.devicesOf("m").firstWhere((d) => d.kind == DeviceKind.macro);
    var index = c.devicesOf("m").indexOf(macro());
    expect(find.byKey(ValueKey("device-$index-m8")), findsOneWidget);
    var random = find.byKey(ValueKey("macroRandom-$index"));
    await tester.ensureVisible(random);
    await tester.pump();
    await tester.tap(random);
    await tester.pump();
    var set = {for (var i = 1; i <= 8; i++) "m$i": macro().value("m$i")};
    expect(set.values.where((v) => v > 0), isNotEmpty);
    // Kept as Variation 1; turned elsewhere; brought back.
    Future<void> menu(String key) async {
      await tester.tap(find.byKey(ValueKey("macroVariation-$index")));
      await tester.pump();
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pump();
      await tester.pump();
    }

    await menu("macroVariationSave-$index");
    expect(macro().variations, hasLength(1));
    await tester.ensureVisible(random);
    await tester.pump();
    await tester.tap(random);
    await tester.pump();
    await menu("macroVariation-$index-0");
    expect({for (var i = 1; i <= 8; i++) "m$i": macro().value("m$i")}, set);
    c.undo();
    expect(
        {for (var i = 1; i <= 8; i++) "m$i": macro().value("m$i")}, isNot(set),
        reason: "a recall is one undo step");
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
  });

  // Ken: the Ducker, the compressor and the EQ taken out as any device is.
  testWidgets("the EQ, compressor and Ducker are taken out and put back",
      (tester) async {
    var c = make();
    addTearDown(c.dispose);
    c.openEffects("m");
    await show(tester, c);
    ChannelMix mix() => c.timelineChannels.single.mix;
    for (var (key, part) in [
      ("deviceRemove-eq", chainEq),
      ("deviceRemove-comp", chainComp),
      ("deviceRemove-duck", stripDuck),
    ]) {
      await revealInMenu(tester, key);
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pump();
      await tester.pump();
      expect(c.partRemoved("m", part), isTrue, reason: part);
    }
    expect(find.byKey(const ValueKey("device-eq")), findsNothing);
    expect(find.byKey(const ValueKey("device-comp")), findsNothing);
    expect(find.byKey(const ValueKey("device-duck")), findsNothing);
    expect((mix().eq.on, mix().comp.on, mix().duck.on), (false, false, false));
    // Put back from the "+", with what they had.
    await openAdd(tester, find.byKey(const ValueKey("addDeviceOpen")));
    await tester.tap(find.byKey(ValueKey("addPart-$chainComp")));
    await tester.pump();
    await tester.pump();
    expect(c.partRemoved("m", chainComp), isFalse);
    expect(mix().comp.on, isTrue);
    expect(find.byKey(const ValueKey("device-comp")), findsOneWidget);
    c.undo();
    expect(c.partRemoved("m", chainComp), isTrue, reason: "one undo step");
    expect(ChannelMix.fromJson(mix().toJson()).removed,
        containsAll([chainEq, chainComp, stripDuck]));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
  });

  // Ken: the first Ducker -- the one a channel shows when another ducks it
  // -- taken out too.
  testWidgets("a channel ducked by another takes its Ducker card out",
      (tester) async {
    var c = CanvasController(
        CanvasDocument(frames: 100, elements: [
          AudioElement(const ElementBase(id: "m", name: "Music"),
              clip: const MediaClip(
                  playlist: [MediaSource(assetId: "t", length: 8)],
                  timed: true)),
          AudioElement(const ElementBase(id: "v", name: "Voice"),
              clip: const MediaClip(
                  playlist: [MediaSource(assetId: "t", length: 8)],
                  timed: true,
                  mix: ChannelMix(duck: Ducking(on: true)))),
        ]),
        audioEngine: FakeEngine({"t": 8}));
    addTearDown(c.dispose);
    c.openEffects("m");
    await show(tester, c);
    expect(find.byKey(const ValueKey("device-ducked")), findsOneWidget);
    await revealInMenu(tester, "deviceRemove-ducked");
    await tester.tap(find.byKey(const ValueKey("deviceRemove-ducked")));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey("device-ducked")), findsNothing);
    var voice = c.timelineChannels.firstWhere((l) => l.key == "v").mix.duck;
    expect(voice.except, contains("m"), reason: "not turned down");
    // Put back from the "+": ducked again.
    await openAdd(tester, find.byKey(const ValueKey("addDeviceOpen")));
    await tester.tap(find.byKey(ValueKey("addPart-$stripDucked")));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey("device-ducked")), findsOneWidget);
    expect(c.timelineChannels.firstWhere((l) => l.key == "v").mix.duck.except,
        isNot(contains("m")));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
  });

  // Ken: no Pitch tab, as the prototype has none -- a voice's pitch is its
  // Speech's Phrasing button.
  testWidgets("there is no Pitch tab; a voice's pitch is its Phrasing",
      (tester) async {
    var c = make();
    addTearDown(c.dispose);
    c.setSpeech("m", const SpeechSpec(script: "Hello there."));
    c.openEffects("m");
    await show(tester, c);
    expect(find.byKey(const ValueKey("chainTabPitch")), findsNothing);
    await tester.tap(find.byKey(const ValueKey("chainTabSpeech")));
    await tester.pump();
    expect(find.byKey(const ValueKey("speechPhrasing")), findsOneWidget,
        reason: "its pitch: Phrasing, on the Speech itself");
    await tester.tap(find.byKey(const ValueKey("speechPhrasing")));
    await tester.pump();
    await tester.pump();
    expect(c.phrasing?.channel, "m", reason: "Ken: Phrasing did nothing");
    expect(find.byType(PhrasingLanes), findsOneWidget);
    // Taken off: back to the chain, not left on "Speak a script".
    c.setSpeech("m", null);
    await tester.pump();
    expect(c.speechShown, isFalse);
    expect(c.phrasing, isNull);
    expect(find.byKey(const ValueKey("speechStart")), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
  });

  // Ken: each channel's chain where he left it, switching channels.
  testWidgets("each channel's chain is scrolled where it was left",
      (tester) async {
    var c = CanvasController(
        CanvasDocument(frames: 100, elements: [
          AudioElement(const ElementBase(id: "m", name: "Music"),
              clip: MediaClip(
                  playlist: const [MediaSource(assetId: "t", length: 8)],
                  timed: true,
                  mix: ChannelMix(devices: [
                    for (var i = 0; i < 8; i++)
                      MixDevice(DeviceKind.chorus, id: "d$i"),
                  ]))),
          AudioElement(const ElementBase(id: "b", name: "Beat"),
              clip: const MediaClip(
                  playlist: [MediaSource(assetId: "t", length: 8)],
                  timed: true)),
        ]),
        audioEngine: FakeEngine({"t": 8}));
    addTearDown(c.dispose);
    c.openEffects("m");
    await show(tester, c);
    ScrollPosition position() => tester
        .state<ScrollableState>(find
            .descendant(
                of: find.byKey(const ValueKey("effectsChain")),
                matching: find.byType(Scrollable))
            .first)
        .position;
    position().jumpTo(700);
    await tester.pump();
    c.openEffects("b");
    await tester.pump();
    await tester.pump();
    expect(position().pixels, 0, reason: "another chain, from its start");
    c.openEffects("m");
    await tester.pump();
    await tester.pump();
    expect(position().pixels, 700, reason: "back where it was left");
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
  });

  group("freezing", () {
    test("a frozen chain is kept, and unfrozen puts everything back", () {
      var c = make();
      addTearDown(c.dispose);
      var frozen = FrozenChain(upTo: "d0", wasOn: const {
        "d0": true
      }, playlists: {
        "m": [const MediaSource(assetId: "t", length: 8).toJson()],
      });
      expect(FrozenChain.fromJson(frozen.toJson())!.steps, {"d0"});
      // As freezeChain leaves it: a rendered copy playing, the chorus off.
      var lane = c.timelineChannels.single;
      c.setTimedClip(
          lane.first.element,
          lane.first.clip.copyWith(
              playlist: const [MediaSource(assetId: "frozen", length: 8)]));
      lane = c.timelineChannels.single;
      c.setChannelMix(
          lane,
          lane.mix.copyWith(frozen: frozen, devices: [
            lane.mix.devices.first.switched(false),
            lane.mix.devices[1],
          ]));
      expect(c.frozenSteps("m"), {"d0"});
      expect(c.canFreeze("m"), isNotNull, reason: "already frozen");
      c.unfreezeChain("m");
      var clip = (c.document.elements.single as AudioElement).clip;
      expect(clip.playlist.single.assetId, "t");
      expect(clip.mix.frozen, isNull);
      expect(clip.mix.devices.first.on, isTrue);
      c.undo();
      expect(c.frozenSteps("m"), {"d0"}, reason: "one undo step");
    });

    testWidgets("its ⋯ freezes up to it; frozen, it is shown and unfrozen",
        (tester) async {
      var c = make();
      addTearDown(c.dispose);
      c.openEffects("m");
      await show(tester, c);
      var id = deviceKey("d0");
      await revealInMenu(tester, "deviceFreeze-$id");
      expect(find.byKey(ValueKey("deviceFreeze-$id")), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      var lane = c.timelineChannels.single;
      c.setChannelMix(
          lane,
          lane.mix.copyWith(
              frozen: const FrozenChain(
                  upTo: "d0", wasOn: {"d0": true}, playlists: {})));
      await tester.pump();
      expect(find.byKey(ValueKey("deviceFrozen-$id")), findsOneWidget);
      await revealInMenu(tester, "deviceUnfreeze-$id");
      await tester.tap(find.byKey(ValueKey("deviceUnfreeze-$id")));
      await tester.pump();
      await tester.pump();
      expect(c.frozenSteps("m"), isEmpty);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox());
    });
  });

  // Ken: no "Note clips" for MIDI, no macros for MIDI.
  testWidgets("a MIDI chain starts with its Macros and its Note clips",
      (tester) async {
    var c = CanvasController(
        CanvasDocument(frames: 100, elements: [
          AudioElement(const ElementBase(id: "p", name: "Piano"),
              clip: const MediaClip(timed: true),
              instrument: const InstrumentPart(notes: [
                MidiNote(60, 0, 0.5, 100),
                MidiNote(64, 0.5, 0.5, 100),
              ])),
        ]),
        audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    c.openEffects("p");
    await show(tester, c);
    double x(String key) => tester.getTopLeft(find.byKey(ValueKey(key))).dx;
    expect(x("chainZone-Macros"), lessThan(x("chainZone-Source")));
    expect(x("chainZone-Source"), lessThan(x("chainZone-Before")));
    expect(find.byKey(const ValueKey("noteClipsRoll")), findsOneWidget);
    expect(find.text("2 notes, 1 bar"), findsOneWidget);
    // Ken: with none, the macros are a narrow "+"; pressed, one is added,
    // and kept in its zone.
    expect(tester.getSize(find.byKey(const ValueKey("macrosAdd"))).width,
        lessThan(40));
    await tester.tap(find.byKey(const ValueKey("macrosAdd")));
    await tester.pump();
    expect(c.devicesOf("p").single.kind, DeviceKind.macro);
    expect(x("device-${deviceKey(c.devicesOf("p").single.id)}"),
        lessThan(x("chainZone-Source")));
    // Its notes, pressed open: the piano roll.
    await tester.tap(find.byKey(const ValueKey("noteClipsEdit")));
    await tester.pump();
    expect(c.pianoRollShown, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
  });

  group("the header", () {
    testWidgets("one row: what it shows, its views, its heights",
        (tester) async {
      var c = make();
      addTearDown(c.dispose);
      c.openEffects("m");
      double asked = 0;
      await show(tester, c, onResize: (h) => asked = h);
      expect(
          tester.widget<Text>(find.byKey(const ValueKey("chainWhoName"))).data,
          "Music");
      expect(find.text("Audio"), findsOneWidget);
      expect(find.byKey(const ValueKey("chainTabDevices")), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey("chainTier"))).data,
          "Large · 370 px");
      await tester.tap(find.byKey(const ValueKey("chainHeight-S")));
      await tester.pump();
      expect(asked, 178);
      // Filling the window puts the canvas away; again, it comes back.
      await tester.tap(find.byKey(const ValueKey("chainMax")));
      await tester.pump();
      expect(c.chainFull, isTrue);
      await tester.tap(find.byKey(const ValueKey("chainMax")));
      await tester.pump();
      expect(c.chainFull, isFalse);
      // Picked from its list: another channel, or an element's motion.
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("an editor opened from a tab makes a short panel taller",
        (tester) async {
      var c = make();
      addTearDown(c.dispose);
      c.setSpeech("m", const SpeechSpec());
      c.openEffects("m");
      var asked = <double>[];
      await show(tester, c, height: 210, onResize: asked.add);
      await tester.tap(find.byKey(const ValueKey("chainTabSpeech")));
      await tester.pump();
      expect(asked.last, 380);
      expect(c.speechShown, isTrue);
      await tester.tap(find.byKey(const ValueKey("chainTabDevices")));
      await tester.pump();
      expect(asked.last, 210, reason: "back to the height it had");
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group("the cards", () {
    testWidgets("no tips on hover; what it does behind its \"?\"",
        (tester) async {
      var c = make();
      addTearDown(c.dispose);
      c.openEffects("m");
      await show(tester, c);
      var hidden = tester.widget<TooltipVisibility>(find
          .ancestor(
              of: find.byKey(const ValueKey("chainPanel")),
              matching: find.byType(TooltipVisibility))
          .first);
      expect(hidden.visible, isFalse);
      // Its "?" where its bar has room; its ⋯ "What it does" always.
      var help = find.byKey(ValueKey("deviceHelp-${deviceKey("d0")}"));
      if (help.evaluate().isNotEmpty) {
        await tester.ensureVisible(help);
        await tester.pump();
        await tester.tap(help);
        await tester.pump();
        expect(find.byKey(ValueKey("deviceHelpText-${deviceKey("d0")}")),
            findsOneWidget);
      } else {
        var more = find.byKey(ValueKey("deviceMore-${deviceKey("d0")}"));
        await tester.ensureVisible(more);
        await tester.pump();
        await tester.tap(more);
        await tester.pump();
        await tester
            .tap(find.byKey(ValueKey("deviceAbout-${deviceKey("d0")}")));
        await tester.pump();
      }
      expect(find.textContaining("Thickens the sound"), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    // Ken's log: the master's meter, folded, overflowed its fold by 6.
    for (var scale in [1.0, 1.5]) {
      testWidgets("every card folded fits its fold, text at ${scale}x",
          (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        var c = CanvasController(
            CanvasDocument(frames: 100, elements: [
              AudioElement(const ElementBase(id: "m", name: "Music"),
                  clip: MediaClip(
                      playlist: const [MediaSource(assetId: "t", length: 8)],
                      timed: true,
                      mix: ChannelMix(devices: [
                        for (var (i, k) in DeviceKind.values.indexed)
                          MixDevice(k, id: "d$i"),
                      ]))),
            ]),
            audioEngine: FakeEngine({"t": 8}));
        addTearDown(c.dispose);
        for (var shown in ["m", mixerMasterKey]) {
          c.openEffects(shown);
          await show(tester, c);
          var folds = find.byWidgetPredicate((w) =>
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith("deviceFold-"));
          for (var e in folds.evaluate().toList()) {
            var id = (e.widget.key as ValueKey<String>)
                .value
                .substring("deviceFold-".length);
            c.foldDevice(id, true);
          }
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull, reason: "$shown folded");
        }
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets("its ⋯ duplicates it and resets it, as the prototype's",
        (tester) async {
      var c = make();
      addTearDown(c.dispose);
      c.openEffects("m");
      c.setDevicesOf("m", [
        c.devicesOf("m").first.withValue("depth", 0.9),
        c.devicesOf("m")[1],
      ]);
      await show(tester, c);
      var id = deviceKey("d0");
      await revealInMenu(tester, "deviceDuplicate-$id");
      expect(find.text("Move right"), findsOneWidget);
      expect(find.text("What it does"), findsOneWidget);
      await tester.tap(find.byKey(ValueKey("deviceDuplicate-$id")));
      await tester.pump();
      await tester.pump();
      var now = c.devicesOf("m");
      expect(now.map((d) => d.kind),
          [DeviceKind.chorus, DeviceKind.chorus, DeviceKind.reverb]);
      expect(now[1].value("depth"), 0.9, reason: "a copy, settings and all");
      expect(now.map((d) => d.id).toSet(), hasLength(3), reason: "own ids");
      await revealInMenu(tester, "deviceReset-$id");
      await tester.tap(find.byKey(ValueKey("deviceReset-$id")));
      await tester.pump();
      await tester.pump();
      expect(c.devicesOf("m").first.value("depth"),
          DeviceKind.chorus.param("depth").initial);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("the header's ⋯ folds every card, and copies a chain",
        (tester) async {
      var c = make();
      addTearDown(c.dispose);
      c.openEffects("m");
      await show(tester, c);
      Future<void> menu(String key) async {
        await tester.tap(find.byKey(const ValueKey("chainMore")));
        await tester.pump();
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pump();
        await tester.pump();
      }

      await menu("chainFoldAll");
      expect(c.foldedDevices, containsAll([deviceKey("d0"), deviceKey("d1")]));
      await menu("chainUnfoldAll");
      expect(c.foldedDevices, isNot(contains(deviceKey("d0"))));
      await menu("chainCopy");
      c.openEffects(mixerMasterKey);
      await tester.pump();
      var before = c.devicesOf(mixerMasterKey).length;
      await menu("chainPaste");
      expect(c.devicesOf(mixerMasterKey).length, before + 2);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("one kind of card: its dot, its name, the rest behind ⋯",
        (tester) async {
      var c = make();
      addTearDown(c.dispose);
      c.openEffects("m");
      await show(tester, c);
      expect(find.text("CHORUS"), findsOneWidget);
      expect(find.byKey(const ValueKey("deviceRemove-0")), findsNothing,
          reason: "behind its ⋯");
      await revealInMenu(tester, "deviceRemove-0");
      await tester.tap(find.byKey(const ValueKey("deviceRemove-0")));
      await tester.pump();
      await tester.pump();
      expect(c.devicesOf("m").map((d) => d.kind), [DeviceKind.reverb]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
