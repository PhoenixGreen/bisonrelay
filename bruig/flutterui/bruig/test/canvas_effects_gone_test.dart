import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_effects_gone_test.dart is the effects panel outliving its channel.
//
// Reported: a "Null check operator used on a null value" thrown from the
// compressor's meter thirty times a second. The panel was open on a
// channel whose last sound had gone, and every tick asked the channel --
// no longer there -- for its compressor.

void main() {
  testWidgets("a channel's devices go on ticking after the channel goes",
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var c = CanvasController(const CanvasDocument(frames: 100, elements: [
      AudioElement(ElementBase(id: "a", name: "Voice"),
          clip: MediaClip(
              playlist: [MediaSource(assetId: "x", name: "x", length: 2)],
              timed: true,
              mix: ChannelMix(comp: Dynamics(on: true)))),
    ]));
    addTearDown(c.dispose);
    c.openEffects("a");
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(
            create: (c) => CanvasPreferences()),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: Align(
                  alignment: Alignment.bottomCenter,
                  child: CanvasMixer.effects(
                      controller: c,
                      height: 340,
                      onResize: (_) {},
                      onClose: () {})))),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    // The channel's only sound taken away while its devices are showing.
    c.apply(c.document.removeElement("a"));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
