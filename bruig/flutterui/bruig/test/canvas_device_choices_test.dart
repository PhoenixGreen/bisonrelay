import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/chain_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_cards.dart'
    show StudioDrop;
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_device_choices_test.dart is a sound device's settings that are one
// of a few -- a filter's type, a wobble's shape, a saturator's character --
// chosen from a list, as the prototype's dropdowns, not turned on a knob.

void main() {
  for (var scale in [1.0, 1.5]) {
    for (var height in [300.0, 170.0]) {
      testWidgets("a device's choices are lists, at $scale, $height high",
          (tester) async {
        var c = CanvasController(
            CanvasDocument(
                frames: 600,
                frameRate: 60,
                audio: const AudioSettings(tempo: 120),
                elements: [
                  AudioElement(const ElementBase(id: "m", name: "Vox"),
                      clip: const MediaClip(playlist: [
                        MediaSource(assetId: "vox.wav", name: "Vox", length: 4)
                      ], timed: true)),
                ]),
            audioEngine: FakeEngine({"vox.wav": 4}));
        addTearDown(c.dispose);
        c.setDevicesOf("m", const [
          MixDevice(DeviceKind.autoFilter),
          MixDevice(DeviceKind.autoPan),
          MixDevice(DeviceKind.saturator),
        ]);
        c.openEffects("m");
        tester.view.physicalSize = const Size(2400, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeNotifier>(
                create: (c) => ThemeNotifier(doLoad: false)),
            ChangeNotifierProvider<SnackBarModel>(
                create: (c) => SnackBarModel()),
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
                          builder: (context, _) => ChainPanel(
                              controller: c,
                              height: height,
                              onResize: (_) {}))))),
        ));
        await tester.pump(const Duration(milliseconds: 300));

        for (var (i, id, names) in [
          (0, "type", ["Low-pass", "High-pass", "Band-pass"]),
          (1, "shape", ["Sine", "Triangle", "Square"]),
          (2, "type", ["Soft", "Warm", "Hard"]),
        ]) {
          var drop = find.byKey(ValueKey("device-$i-$id"));
          expect(drop, findsOneWidget, reason: "$i $id");
          var list = tester.widget(drop);
          expect(list, isA<StudioDrop<int>>(), reason: "a list, not a knob");
          expect(
              [for (var o in (list as StudioDrop<int>).options) o.$2], names);
        }
        tester
            .widget<StudioDrop<int>>(
                find.byKey(const ValueKey("device-0-type")))
            .onChanged(2);
        await tester.pump();
        expect(c.devicesOf("m").first.value("type"), 2);
        expect(
            find.descendant(
                of: find.byKey(const ValueKey("device-0-type")),
                matching: find.text("Band-pass")),
            findsOneWidget);
        c.undo();
        expect(c.devicesOf("m").first.value("type"), 0, reason: "one step");
        expect(tester.takeException(), isNull);
      });
    }
  }
}
