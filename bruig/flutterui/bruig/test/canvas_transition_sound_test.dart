import 'dart:io';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/transition_sound.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'canvas_audio_fake.dart';

// canvas_transition_sound_test.dart is a transition's Sound row: the sound
// picked can be heard on its own first, to see it is the one wanted (Ken,
// 2026-11-08: "a preview button so that I can sample the sound").

const whoosh = "a1b2c3d4e5f60718.mp3";

/// settle lets the library's read land: real file work, off the test's clock.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}

/// framed is [child] with what the canvas controls look for above it.
Widget framed(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  late Directory root;
  late Future<String?> Function(String) pathWas;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp("canvas_transition_sound");
    CanvasStorage.rootOverride = root.path;
    CanvasLibrary.resetForTest();
    await CanvasLibrary.add(LibraryAsset(
        id: whoosh,
        kind: AssetKind.audio,
        name: "Whoosh",
        added: DateTime(2026, 11, 8),
        length: 1.5));
    pathWas = CanvasController.takePath;
    CanvasController.takePath = (id) async => "/library/$id";
  });

  tearDown(() async {
    CanvasController.takePath = pathWas;
    CanvasStorage.rootOverride = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets("the sound picked is heard on its own, and stopped",
      (tester) async {
    var engine = FakeEngine(const {whoosh: 1.5});
    var c = CanvasController(CanvasDocument(), audioEngine: engine);
    addTearDown(c.dispose);
    var t = const SceneTransition(kind: SceneTransitionKind.fade).copyWith(
        sound: whoosh, soundName: "Whoosh", soundLength: 1.5, soundVolume: 0.5);
    await tester.pumpWidget(framed(ListenableBuilder(
        listenable: c,
        builder: (context, _) => CanvasTransitionSound(
              value: t,
              onChanged: (_) {},
              onEvery: (_) {},
              hearing: c.hearingSound(t.sound),
              onHear: () => c.hearSound(t.sound, volume: t.soundVolume),
            ))));
    // The library read, off the test's clock.
    await settle(tester);
    expect(find.text("Whoosh"), findsWidgets, reason: "the library read");
    var hear = find.byKey(const ValueKey("transitionSoundHear"));
    expect(hear, findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    await tester.tap(hear);
    await tester.pump();
    expect(c.hearingSound(whoosh), isTrue);
    expect(engine.last.track.path, whoosh);
    expect(engine.last.volume, 0.5, reason: "as loud as the transition has it");
    expect(find.byIcon(Icons.stop), findsOneWidget);

    await tester.tap(hear);
    await tester.pump();
    expect(c.hearingSound(whoosh), isFalse);
    expect(engine.last.alive, isFalse, reason: "stopped");
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    // Played to its end, the button is Play again by itself.
    await tester.tap(hear);
    await tester.pump();
    expect(c.hearingSound(whoosh), isTrue);
    engine.last.alive = false;
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.hearingSound(whoosh), isFalse);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets("no sound picked, nothing to hear", (tester) async {
    await tester.pumpWidget(framed(CanvasTransitionSound(
        value: const SceneTransition(kind: SceneTransitionKind.fade),
        onChanged: (_) {},
        onEvery: (_) {},
        onHear: () {})));
    await settle(tester);
    expect(find.byKey(const ValueKey("transitionSoundHear")), findsNothing);
  });

  for (var scale in const [0.65, 1.0, 1.5]) {
    testWidgets("the row fits a card 400 wide, at text $scale", (tester) async {
      var c = CanvasController(CanvasDocument(),
          audioEngine: FakeEngine(const {whoosh: 1.5}));
      addTearDown(c.dispose);
      var t = const SceneTransition(kind: SceneTransitionKind.fade)
          .copyWith(sound: whoosh, soundName: "Whoosh", soundLength: 1.5);
      await tester.pumpWidget(framed(MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                  width: 400,
                  child: CanvasTransitionSound(
                      value: t,
                      onChanged: (_) {},
                      onEvery: (_) {},
                      onHear: () {}))))));
      await settle(tester);
      expect(find.byKey(const ValueKey("transitionSoundHear")), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
