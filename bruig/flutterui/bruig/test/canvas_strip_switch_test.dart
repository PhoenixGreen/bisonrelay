import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/chain_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_strip_switch_test.dart is the Chain moved from one strip to
// another: its EQ, compressor and the rest are the new strip's, not the
// first one opened (Ken's systems review, 2026-11-08: open the master's
// chain, then a channel's, and the channel's EQ wrote to the master).

void main() {
  testWidgets("the EQ switched on is the strip's shown, after another's",
      (tester) async {
    var c = CanvasController(
        CanvasDocument(frames: 100, elements: [
          for (var id in ["a", "b"])
            AudioElement(ElementBase(id: id, name: id.toUpperCase()),
                clip: const MediaClip(
                    playlist: [MediaSource(assetId: "t", length: 8)],
                    timed: true)),
        ]),
        audioEngine: FakeEngine({"t": 8}));
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(2000, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    c.openEffects(mixerMasterKey);
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
                          controller: c, height: 360, onResize: (_) {}))))),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    ChannelMix mixOf(String key) =>
        c.timelineChannels.firstWhere((l) => l.key == key).mix;
    var masterOn = c.document.masterMix.eq.on;
    for (var key in [c.timelineChannels[0].key, c.timelineChannels[1].key]) {
      c.openEffects(key);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(find.byKey(const ValueKey("eqOn")));
      await tester.tap(find.byKey(const ValueKey("eqOn")));
      await tester.pump(const Duration(milliseconds: 300));
      expect(mixOf(key).eq.on, isTrue, reason: "$key's own EQ");
    }
    expect(c.document.masterMix.eq.on, masterOn, reason: "the master's kept");
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
  });
}
