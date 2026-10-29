import 'package:bruig/plugin_system/canvas/ui/sidebar/structure_panel.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_channels.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline_view.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_structure_test.dart is a piece of sound laid out in bars: its
// sections, the grid its sounds land on, the fine steps its time is counted
// in, and the Structure panel where a document of scenes has its Scenes.

const song = "aaaaaaaaaaaaaaaa.mp3";

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test("sections follow one another, and are saved", () {
    const a = AudioSettings(sections: [
      SongSection("i", name: "Intro", bars: 4),
      SongSection("v", name: "Verse", bars: 16, color: 1),
      SongSection("c", name: "Chorus", bars: 8, color: 2),
    ], quantise: Quantise.eighth);
    expect(a.totalBars, 28);
    expect([for (var i = 0; i < 3; i++) a.startBar(i)], [0, 4, 20]);
    var back = AudioSettings.fromJson(a.toJson());
    expect(back.toJson(), a.toJson());
    expect(back.quantise, Quantise.eighth);
  });

  test("the grid is the tempo's", () {
    const four = AudioSettings(tempo: 120);
    expect(four.gridSeconds(Quantise.bar), 2);
    expect(four.gridSeconds(Quantise.quarter), 0.5);
    expect(four.gridSeconds(Quantise.sixteenth), 0.125);
    expect(four.gridSeconds(Quantise.eighthTriplet), closeTo(1 / 6, 1e-9));
    expect(four.gridSeconds(Quantise.off), isNull);
    const sixEight = AudioSettings(tempo: 120, beatsPerBar: 6, beatUnit: 8);
    expect(sixEight.gridSeconds(Quantise.eighth), 0.25);
    expect(sixEight.gridSeconds(Quantise.bar), 1.5);
  });

  test("a piece of sound counts in fine steps, unless it has timing", () {
    var c = CanvasController(const CanvasDocument(frames: 48, frameRate: 24));
    addTearDown(c.dispose);
    c.setKind(CanvasKind.audio);
    expect(c.document.frameRate, audioFrameRate);
    expect(c.document.frames, 240, reason: "the same two seconds");
    c.setKind(CanvasKind.scenes);
    expect((c.document.frameRate, c.document.frames), (24, 48),
        reason: "back to a picture's rate, the same two seconds");
    var timed = CanvasController(const CanvasDocument(
        frames: 48,
        frameRate: 24,
        elements: [
          AudioElement(ElementBase(id: "a"),
              clip: MediaClip(
                  playlist: [MediaSource(assetId: song, name: song)],
                  timed: true,
                  at: 12)),
        ]));
    addTearDown(timed.dispose);
    timed.setKind(CanvasKind.audio);
    expect(timed.document.frameRate, 24,
        reason: "changing the rate would move the sound at frame 12");
  });

  test("the timeline holds the structure, and a section is gone to", () {
    var c = CanvasController(const CanvasDocument(frames: 10));
    addTearDown(c.dispose);
    c.setKind(CanvasKind.audio);
    c.addSection("Intro");
    c.addSection("Verse");
    var a = c.document.audio;
    expect(a.sections.map((s) => s.name), ["Intro", "Verse"]);
    expect(a.sections.map((s) => s.color), [0, 1]);
    // Sixteen bars at 120 in 4/4: thirty-two seconds.
    expect(c.document.frames, greaterThanOrEqualTo(32 * audioFrameRate));
    c.goToSection(1);
    expect(c.frame, 16 * audioFrameRate, reason: "bar 9, eight bars in");
  });

  testWidgets("a piece of sound has Structure where scenes would be",
      (tester) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var c = CanvasController(const CanvasDocument());
    addTearDown(c.dispose);
    c.setKind(CanvasKind.audio);
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
              body: SizedBox(
                  width: 420, child: CanvasDesignPanel(controller: c)))),
    ));
    await tester.pumpAndSettle();
    // Panel headings are drawn in capitals.
    expect(find.text("STRUCTURE"), findsWidgets);
    expect(find.text("SCENES"), findsNothing);
    if (find.byKey(const ValueKey("masterStructure")).evaluate().isEmpty) {
      await tester.tap(find.text("STRUCTURE").first);
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey("masterStructure")), findsOneWidget);
    var verse = find.byKey(const ValueKey("addSection-Verse"));
    await tester.ensureVisible(verse);
    await tester.tap(verse);
    await tester.pumpAndSettle();
    expect(c.document.audio.sections.single.name, "Verse");
    expect(find.byKey(const ValueKey("masterStructure")), findsNothing);
    var more = find.byKey(const ValueKey("sectionBars-0-more"));
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(c.document.audio.sections.single.bars, 9);
    await tester.tap(find.byKey(const ValueKey("sectionDelete-0")));
    await tester.pumpAndSettle();
    expect(c.document.audio.sections, isEmpty);
    c.undo();
    expect(c.document.audio.sections.single.bars, 9);
    expect(tester.takeException(), isNull);
  });

  // Ken's log: in a short sidebar the panel is given about a hundred pixels,
  // and its column overflowed by 345.
  testWidgets("a short Structure panel scrolls rather than overflowing",
      (tester) async {
    var c = CanvasController(const CanvasDocument());
    addTearDown(c.dispose);
    c.setKind(CanvasKind.audio);
    Future<void> show() async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                        width: 344,
                        height: 106,
                        child: CanvasStructurePanel(controller: c))))),
      ));
      await tester.pumpAndSettle();
    }

    await show();
    expect(tester.takeException(), isNull, reason: "the master structure");
    for (var name in ["Intro", "Verse", "Chorus", "Verse", "Chorus", "Outro"]) {
      c.addSection(name);
    }
    await show();
    expect(tester.takeException(), isNull, reason: "six sections");
    var last = find.byKey(const ValueKey("sectionName-5"));
    await tester.scrollUntilVisible(last, 40,
        scrollable: find.byType(Scrollable).first);
    expect(last, findsOneWidget);
  });

  // Ken's log: a section's row ran thirteen pixels off a narrow sidebar --
  // and he runs a larger text size. Tried at sidebar widths and every text
  // size the app offers.
  testWidgets("a section row fits any sidebar, at any text size",
      (tester) async {
    var failures = <String>[];
    var c = CanvasController(const CanvasDocument());
    addTearDown(c.dispose);
    c.setKind(CanvasKind.audio);
    for (var name in ["Intro", "Pre-chorus", "Middle 8"]) {
      c.addSection(name);
    }
    for (var scale in [0.85, 1.0, 1.15, 1.25, 1.5]) {
      for (var width in [180.0, 220.0, 260.0, 300.0, 344.0, 420.0]) {
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeNotifier>(
                create: (c) => ThemeNotifier(doLoad: false)),
          ],
          child: MaterialApp(
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: Scaffold(
                  body: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                          width: width,
                          height: 500,
                          child: CanvasStructurePanel(controller: c))))),
        ));
        await tester.pump();
        if (tester.takeException() case var e?) {
          failures.add("${width}px at ${scale}x: "
              "${e.toString().split("\n").first}");
        }
      }
    }
    expect(failures, isEmpty);
    expect(find.byKey(const ValueKey("sectionBars-0")), findsOneWidget);
  });

  testWidgets("a sound dragged lands on the beat", (tester) async {
    // 120 BPM in 4/4 at 120 steps a second: a beat every sixty steps.
    var c = CanvasController(const CanvasDocument(
        kind: CanvasKind.audio,
        hasCanvas: false,
        frames: 1200,
        frameRate: 120,
        elements: [
          AudioElement(ElementBase(id: "a", name: "Loop"),
              clip: MediaClip(
                  playlist: [MediaSource(assetId: song, name: song, length: 2)],
                  timed: true)),
        ]));
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(1000, 300);
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
                  child: SizedBox(
                      height: 120,
                      child: CanvasChannels(
                          controller: c,
                          view: TimelineView.whole(c.document.frames)))))),
    ));
    await tester.pumpAndSettle();
    var lane = find.byKey(const ValueKey("lane-a"));
    var box = tester.getRect(lane);
    // Low in the bar, clear of its volume line, which a press in the middle
    // takes hold of instead.
    await tester.dragFrom(Offset(box.left + 40, box.top + box.height * 0.85),
        const Offset(104, 0));
    await tester.pumpAndSettle();
    var at = (c.document.elements.single as AudioElement).clip.at;
    expect(at, greaterThan(0), reason: "it moved");
    expect(at % 60, 0, reason: "onto a beat: $at");
    expect(tester.takeException(), isNull);
  });
}
