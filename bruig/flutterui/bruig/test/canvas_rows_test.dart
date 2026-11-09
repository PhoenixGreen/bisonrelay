import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_rows.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart';
import 'package:bruig/plugin_system/canvas/ui/element_sound.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_rows_test.dart is the one list of rows the timeline, the mixer and
// the slots show (Ken, 2026-11-08: one channel per element): each element
// with its own sound, then the sounds that are nobody's, the master's --
// heard in every scene -- in the All group, last.

AudioElement sound(String id, String name) =>
    AudioElement(ElementBase(id: id, name: name, visible: false),
        clip: MediaClip(timed: true, channelName: name), controls: const []);

void main() {
  test("an element and its own sound are one row; other sounds after", () {
    var c = CanvasController(
        CanvasDocument(frames: 240, elements: [
          sound("m", "Music"),
          ShapeElement(const ElementBase(id: "a", name: "Coin")),
        ]),
        audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    c.ensureElementSound("a");
    var rows = canvasRowsOf(c);
    expect([for (var r in rows) r.key], ["a", "m"],
        reason: "the element first, though the music came first");
    expect(rows.first.hasMotion, isTrue);
    expect(rows.first.channel?.key, elementSoundKey("a"),
        reason: "its own sound is on its row, not a row of its own");
    expect(rows.last.hasMotion, isFalse);
    expect(rows.last.hasSound, isTrue);
    expect(rows.map((r) => r.group).toSet(), {RowGroup.scene});
  });

  test("an element with no sound is a row of motion alone", () {
    var c = CanvasController(
        CanvasDocument(frames: 240, elements: [
          ShapeElement(const ElementBase(id: "a", name: "Camera")),
        ]),
        audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    c.selectOnly("a");
    var rows = canvasRowsOf(c);
    expect(rows.single.key, "a");
    expect(rows.single.hasSound, isFalse);
  });

  test("the master's sounds, heard in every scene, are the All group, last",
      () {
    var c = CanvasController(
        CanvasDocument(
          frames: 240,
          scenes: [
            CanvasScene(id: "one", elements: [
              sound("bed", "Bed"),
              ShapeElement(const ElementBase(id: "a", name: "Coin")),
            ]),
            const CanvasScene(id: "two"),
          ],
          master: CanvasScene(id: "m", elements: [sound("music", "Music")]),
          masterOn: true,
        ),
        audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    c.selectOnly("a");
    var rows = canvasRowsOf(c);
    expect([for (var r in rows) r.key], ["a", "bed", "music"]);
    expect([for (var r in rows) r.group],
        [RowGroup.scene, RowGroup.scene, RowGroup.all]);
  });

  // Ken, 2026-11-08: the All group under its own heading, folding away.
  testWidgets("on the timeline, the All group is under a heading that folds",
      (tester) async {
    var c = CanvasController(
        CanvasDocument(
          frames: 240,
          scenes: [
            CanvasScene(id: "one", elements: [sound("bed", "Bed")]),
            const CanvasScene(id: "two"),
          ],
          master: CanvasScene(id: "m", elements: [
            sound("music", "Music"),
            sound("rain", "Rain"),
          ]),
          masterOn: true,
        ),
        audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1.0;
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
            child: CanvasTimeline(controller: c, height: 500),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    var heading = find.byKey(const ValueKey("allGroupHeading"));
    expect(heading, findsOneWidget);
    expect(find.text("All scenes"), findsOneWidget);
    expect(
        tester.widget<Text>(find.byKey(const ValueKey("allGroupCount"))).data,
        "2");
    Rect strip(String key) =>
        tester.getRect(find.byKey(ValueKey("channelStrip-$key")));
    var bed =
        strip(c.timelineChannels.firstWhere((ch) => ch.name == "Bed").key);
    var music =
        strip(c.timelineChannels.firstWhere((ch) => ch.name == "Music").key);
    expect(tester.getRect(heading).top, greaterThanOrEqualTo(bed.bottom - 0.5),
        reason: "after the scene's own");
    expect(
        music.top, greaterThanOrEqualTo(tester.getRect(heading).bottom - 0.5),
        reason: "its rows under it");
    expect(find.text("All"), findsNWidgets(2), reason: "each tagged All");

    await tester.tap(find.byKey(const ValueKey("allGroupFold")));
    await tester.pumpAndSettle();
    expect(c.allFolded, isTrue);
    expect(heading, findsOneWidget, reason: "the heading stays");
    expect(find.text("All"), findsNothing, reason: "its rows folded away");
    expect(
        find.byKey(ValueKey(
            "channelStrip-${c.timelineChannels.firstWhere((ch) => ch.name == "Bed").key}")),
        findsOneWidget,
        reason: "the scene's own stay");

    await tester.tap(find.byKey(const ValueKey("allGroupFold")));
    await tester.pumpAndSettle();
    expect(find.text("All"), findsNWidgets(2));
  });

  // Ken, 2026-11-08: the All group folds away in the mixer too, with the
  // timeline's heading.
  testWidgets("in the mixer, the All group folds away behind its tab",
      (tester) async {
    var c = CanvasController(
        CanvasDocument(
          frames: 240,
          scenes: [
            CanvasScene(id: "one", elements: [sound("bed", "Bed")]),
            const CanvasScene(id: "two"),
          ],
          master: CanvasScene(id: "m", elements: [
            sound("music", "Music"),
            sound("rain", "Rain"),
          ]),
          masterOn: true,
        ),
        audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(1800, 700);
    tester.view.devicePixelRatio = 1.0;
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
            child: CanvasMixer(
                controller: c, height: 520, onResize: (_) {}, onClose: () {}),
          ),
        ),
      ),
    ));
    await tester.pump();
    String keyOf(String name) =>
        c.timelineChannels.firstWhere((ch) => ch.name == name).key;
    var fold = find.byKey(const ValueKey("mixerAllFold"));
    expect(fold, findsOneWidget);
    expect(find.descendant(of: fold, matching: find.text("2")), findsOneWidget);
    var music = find.byKey(ValueKey("strip-${keyOf("Music")}"));
    expect(music, findsOneWidget);
    expect(tester.getRect(fold).right,
        lessThanOrEqualTo(tester.getRect(music).left),
        reason: "the tab before the group");
    expect(tester.getRect(find.byKey(ValueKey("strip-${keyOf("Bed")}"))).right,
        lessThanOrEqualTo(tester.getRect(fold).left),
        reason: "the scene's own first");

    await tester.tap(fold);
    await tester.pump();
    expect(c.allFolded, isTrue, reason: "the timeline's fold too");
    expect(music, findsNothing);
    expect(find.byKey(ValueKey("strip-${keyOf("Bed")}")), findsOneWidget);
    await tester.tap(fold);
    await tester.pump();
    expect(music, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 500));
  });
}
