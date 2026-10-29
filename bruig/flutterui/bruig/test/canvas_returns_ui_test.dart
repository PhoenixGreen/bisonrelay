import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_returns_ui_test.dart is sends and returns on the mixer: a dial per
// return on each channel, the returns' own strips after the channels, adding
// and taking them away, and a return's devices in the effects panel.

void main() {
  CanvasController controller() {
    var c = CanvasController(const CanvasDocument(frames: 100, elements: [
      AudioElement(ElementBase(id: "v", name: "Voice"),
          clip: MediaClip(
              playlist: [MediaSource(assetId: "x", name: "x", length: 4)],
              timed: true)),
    ]));
    addTearDown(c.dispose);
    return c;
  }

  Future<void> show(WidgetTester tester, CanvasController c,
      {bool effects = false}) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
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
                  child: ListenableBuilder(
                    listenable: c,
                    builder: (context, _) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (effects)
                            CanvasMixer.effects(
                                controller: c,
                                height: 340,
                                onResize: (_) {},
                                onClose: () {}),
                          CanvasMixer(
                              controller: c,
                              height: 420,
                              onResize: (_) {},
                              onClose: () {}),
                        ]),
                  )))),
    ));
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets("a channel sends to each return by its dial", (tester) async {
    var c = controller();
    await show(tester, c);
    var dial = find.descendant(
        of: find.byKey(const ValueKey("strip-v")),
        matching: find.byKey(const ValueKey("send-returnA")));
    expect(dial, findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey("strip-v")),
            matching: find.byKey(const ValueKey("send-returnB"))),
        findsOneWidget);
    await tester.drag(dial, const Offset(0, -60));
    await tester.pump(const Duration(milliseconds: 100));
    var sent = c.timelineChannels.single.mix.sendDb("returnA");
    expect(sent, isNotNull);
    expect(sent!, closeTo(-27, 2), reason: "half way up its travel");
    c.undo();
    expect(c.timelineChannels.single.mix.sendDb("returnA"), isNull,
        reason: "one drag, one undo step");
    await tester.drag(dial, const Offset(0, -60));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(dial);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(dial);
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.timelineChannels.single.mix.sendDb("returnA"), isNull,
        reason: "double-clicked: nothing sent");
    expect(tester.takeException(), isNull);
    await done(tester);
  });

  testWidgets("returns are added, renamed and taken away", (tester) async {
    var c = controller();
    await show(tester, c);
    expect(find.byKey(const ValueKey("strip-returnA")), findsOneWidget);
    expect(find.byKey(const ValueKey("strip-returnB")), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("addReturn")));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.document.returns.map((r) => r.id),
        ["returnA", "returnB", "returnC"]);
    expect(c.selectedChannel, "returnC", reason: "picked, to be worked on");
    expect(find.byKey(const ValueKey("strip-returnC")), findsOneWidget);
    // A send dial for it on the channel too.
    expect(find.byKey(const ValueKey("send-returnC")), findsOneWidget);
    c.setReturn(c.returnOf("returnC")!.copyWith(name: "Room"));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text("Room"), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey("strip-returnB")),
        matching: find.byKey(const ValueKey("removeReturn"))));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.document.returns.map((r) => r.id), ["returnA", "returnC"]);
    c.undo();
    expect(c.document.returns.length, 3);
    expect(tester.takeException(), isNull);
    await done(tester);
  });

  testWidgets("a return's devices are in its chain, and can be added",
      (tester) async {
    var c = controller();
    c.openEffects("returnA");
    await show(tester, c, effects: true);
    await tester.pump(const Duration(milliseconds: 300));
    var size = find.byKey(const ValueKey("device-0-size"));
    expect(size, findsOneWidget, reason: "the reverb's knobs");
    await tester.drag(size, const Offset(0, -40));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.returnOf("returnA")!.devices.single.value("size"),
        greaterThan(0.7));
    await tester.tap(find.byKey(const ValueKey("devicePower-0")));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.returnOf("returnA")!.devices.single.on, isFalse);
    var add = find.byKey(const ValueKey("addDevice-delay"));
    await tester.ensureVisible(add);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(add);
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.returnOf("returnA")!.devices.map((d) => d.kind),
        [DeviceKind.reverb, DeviceKind.delay]);
    var remove = find.byKey(const ValueKey("deviceRemove-0"));
    await tester.ensureVisible(remove);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(remove);
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.returnOf("returnA")!.devices.map((d) => d.kind),
        [DeviceKind.delay]);
    expect(tester.takeException(), isNull);
    await done(tester);
  });
}
