import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/chain_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
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
    // The macros start folded; opened, one is added, and kept in its zone.
    await tester.tap(find.byKey(const ValueKey("deviceFold-macros")));
    await tester.pump();
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
      var help = find.byKey(ValueKey("deviceHelp-${deviceKey("d0")}"));
      await tester.ensureVisible(help);
      await tester.pump();
      await tester.tap(help);
      await tester.pump();
      expect(find.byKey(ValueKey("deviceHelpText-${deviceKey("d0")}")),
          findsOneWidget);
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
