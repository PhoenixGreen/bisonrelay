import 'dart:io';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/strip_presets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/saved_preset_store.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/plugin_system/canvas/ui/device_presets.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_strip_presets_test.dart is the Presets ▾ of a strip's own cards --
// its EQ, compressor, the master's limiter, a Ducker -- as every device has
// one in the chain prototype: starting points by name, Default, and the
// ones saved, which the Presets sidebar puts back on a strip too.

CanvasController _make() =>
    CanvasController(const CanvasDocument(frames: 100, elements: [
      AudioElement(ElementBase(id: "v", name: "Voice"),
          clip: MediaClip(
              playlist: [MediaSource(assetId: "x", name: "x", length: 4)],
              timed: true)),
    ]));

ChannelMix _mix(CanvasController c) => c.timelineChannels.single.mix;

void main() {
  test("a saved strip preset goes back on a strip, where it has that part", () {
    var c = _make();
    addTearDown(c.dispose);
    var key = c.timelineChannels.single.key;
    var voice = eqPresets.firstWhere((p) => p.$1 == "Voice clarity").$2;
    expect(
        useDevicePreset(
            c, key, {"strip": StripPart.eq.name, "value": voice.toJson()}),
        isTrue);
    expect(_mix(c).eq.lowCut.on, isTrue);
    expect(_mix(c).eq.lowCut.freq, 80);
    var deep = duckPresets.firstWhere((p) => p.$1 == "Deep").$2;
    expect(
        useDevicePreset(
            c, key, {"strip": StripPart.duck.name, "value": deep.toJson()}),
        isTrue);
    expect(_mix(c).duck.depthDb, -15);
    expect(
        useDevicePreset(c, mixerMasterKey, {
          "strip": StripPart.limiter.name,
          "value": {"ceiling": -0.3, "ahead": 3, "release": 30}
        }),
        isTrue);
    expect(c.document.masterMix.ceilingDb, -0.3);
    expect(
        useDevicePreset(c, key, {
          "strip": StripPart.limiter.name,
          "value": {"ceiling": -2}
        }),
        isFalse,
        reason: "a channel has no limiter");
    c.undo();
    expect(c.document.masterMix.ceilingDb, -1, reason: "one undo step");
  });

  testWidgets("an EQ's Presets ▾ puts a starting point on, and Default back",
      (tester) async {
    var root = Directory.systemTemp.createTempSync("strip-presets");
    addTearDown(() => root.deleteSync(recursive: true));
    CanvasStorage.rootOverride = root.path;
    addTearDown(() => CanvasStorage.rootOverride = null);
    SavedPresetStore.devices.forget();
    var c = _make();
    addTearDown(c.dispose);
    c.openEffects(c.timelineChannels.single.key);
    tester.view.physicalSize = const Size(1800, 900);
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
                      builder: (context, _) => CanvasMixer.effects(
                          controller: c,
                          height: 380,
                          onResize: (_) {},
                          onClose: () {}))))),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    Future<void> open(String id) async {
      await tester.tap(find.byKey(ValueKey("$id-open")));
      for (var i = 0;
          i < 50 && find.byKey(ValueKey("$id-default")).evaluate().isEmpty;
          i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
    }

    await open("stripPreset-eq");
    expect(
        find.byKey(const ValueKey("stripPreset-eq-Telephone")), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("stripPreset-eq-Telephone")));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_mix(c).eq.highCut.on, isTrue);
    expect(_mix(c).eq.highCut.freq, 3400);
    expect(c.presetNameOf(c.timelineChannels.single.key, "eq"), "Telephone");
    await open("stripPreset-eq");
    await tester.tap(find.byKey(const ValueKey("stripPreset-eq-default")));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_mix(c).eq.highCut.on, isFalse, reason: "flat again");
    expect(c.presetNameOf(c.timelineChannels.single.key, "eq"), isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 600));
  });
}
