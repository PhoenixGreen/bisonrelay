import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/chain_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart';
import 'package:bruig/theming_system/theme_manager.dart';
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
