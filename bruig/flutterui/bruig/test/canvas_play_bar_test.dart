import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_dock.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_play_bar_test.dart is the play bar as Ken redesigned it (2026-11-08):
// the panels on the left, play and the timer in the middle, Back to the
// timeline beside them on the right only when something has left the
// timeline -- with a list to send back one thing at a time -- and no hover
// tips: a "?" explains.

CanvasController make() => CanvasController(
    CanvasDocument(frames: 240, elements: [
      AudioElement(const ElementBase(id: "m", name: "Music", visible: false),
          clip: const MediaClip(timed: true, channelName: "Music"),
          controls: const []),
    ]),
    audioEngine: FakeEngine(const {}));

Future<void> pumpBar(WidgetTester tester, CanvasController c,
    {double width = 2400}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
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
                child: CanvasDock(controller: c, room: 700)))),
  ));
  await tester.pump();
  await tester.pump();
}

/// holdByHand holds a setting of channel [key] off its lane, as a hand moving
/// it while its lane plays does.
void holdByHand(CanvasController c, String key) {
  c.overridden[key] = {"gain"};
  c.frame = c.frame == 0 ? 1 : 0; // something the bar listens for
}

void main() {
  testWidgets("play and the timer are in the middle of the bar",
      (tester) async {
    var c = make();
    addTearDown(c.dispose);
    await pumpBar(tester, c);
    var play = tester.getRect(find.byKey(const ValueKey("play")));
    var marker = tester.getRect(find.byKey(const ValueKey("markerMenu")));
    var middle = (play.left + marker.right) / 2;
    expect(middle, closeTo(1200, 40), reason: "centred on the bar");
    var panels = tester.getRect(find.byKey(const ValueKey("rowsToggle")));
    var settings =
        tester.getRect(find.byKey(const ValueKey("playBarSettings")));
    expect(panels.right, lessThan(play.left), reason: "the panels on the left");
    expect(settings.left, greaterThan(marker.right),
        reason: "the settings on the right");
    expect(tester.takeException(), isNull);
  });

  // Ken, 2026-11-09: the settings and the buttons by them were not on the
  // panel's far right.
  testWidgets("the settings sit at the panel's right edge", (tester) async {
    var c = make();
    addTearDown(c.dispose);
    for (var width in [1200.0, 2400.0]) {
      await pumpBar(tester, c, width: width);
      var settings =
          tester.getRect(find.byKey(const ValueKey("playBarSettings")));
      expect(width - settings.right, lessThan(24),
          reason: "against the right edge at $width");
    }
    // With Back to the timeline showing too.
    holdByHand(c, "m");
    await tester.pump();
    var settings =
        tester.getRect(find.byKey(const ValueKey("playBarSettings")));
    expect(1200 - settings.right, lessThan(24));
  });

  // Ken, 2026-11-09: the timing menu as the prototype's -- the length, its
  // frames a second and how long it runs; the tempo, time and quantise;
  // and the loop, switched on there too -- for any canvas.
  testWidgets("the timing: length, rate, tempo, time, quantise and the loop",
      (tester) async {
    var c = make();
    addTearDown(c.dispose);
    await pumpBar(tester, c);
    await tester.tap(find.byKey(const ValueKey("timingMenu")));
    await tester.pumpAndSettle();
    for (var key in [
      "canvasFrames",
      "canvasFrameRate",
      "timingRuns",
      "audioTempo",
      "audioSignature",
      "audioQuantise",
      "metronome",
      "timingLoop",
      "loopFrom",
      "loopLength",
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
    expect(find.text("Timing"), findsOneWidget);
    expect(c.looping, isFalse);
    await tester.tap(find.byKey(const ValueKey("timingLoop")));
    await tester.pumpAndSettle();
    expect(c.looping, isTrue);
    await tester.tap(find.byKey(const ValueKey("timingClose")));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("timingLoop")), findsNothing);
  });

  // The prototype's transport starts with To the start.
  testWidgets("To the start puts the playhead on the first frame",
      (tester) async {
    var c = make();
    addTearDown(c.dispose);
    await pumpBar(tester, c);
    c.frame = 50;
    await tester.pump();
    var start = tester.getRect(find.byKey(const ValueKey("toStart")));
    expect(
        start.right,
        lessThanOrEqualTo(
            tester.getRect(find.byKey(const ValueKey("play"))).left),
        reason: "first, before play");
    await tester.tap(find.byKey(const ValueKey("toStart")));
    await tester.pump();
    expect(c.frame, 0);
  });

  testWidgets("no hover tips; the ? opens its note and closes it again",
      (tester) async {
    var c = make();
    addTearDown(c.dispose);
    await pumpBar(tester, c);
    var tips = tester.widget<TooltipVisibility>(find
        .ancestor(
            of: find.byKey(const ValueKey("play")),
            matching: find.byType(TooltipVisibility))
        .first);
    expect(tips.visible, isFalse);
    await tester.tap(find.byKey(const ValueKey("help-playBar")));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("helpText-playBar")), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("help-playBar")));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("helpText-playBar")), findsNothing);
  });

  testWidgets("Back to the timeline: only when needed, with a count and a list",
      (tester) async {
    var c = make();
    addTearDown(c.dispose);
    await pumpBar(tester, c);
    expect(find.byKey(const ValueKey("backToTimeline")), findsNothing,
        reason: "nothing has left the timeline");

    holdByHand(c, "m");
    await tester.pump();
    expect(find.byKey(const ValueKey("backToTimeline")), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey("backToTimelineCount")),
            matching: find.text("1")),
        findsOneWidget);
    // Beside the middle, on the right.
    expect(
        tester.getRect(find.byKey(const ValueKey("backToTimeline"))).left,
        greaterThan(
            tester.getRect(find.byKey(const ValueKey("markerMenu"))).right));

    await tester.tap(find.byKey(const ValueKey("backToTimelineList")));
    await tester.pumpAndSettle();
    expect(find.text("HELD BY HAND"), findsOneWidget);
    expect(find.text("PLAYING FROM SLOTS"), findsNothing);
    expect(find.byKey(const ValueKey("offTimeline-held-m")), findsOneWidget);
    expect(find.text("1 setting"), findsOneWidget);

    // Sent back alone, from its own row.
    await tester.tap(find.byKey(const ValueKey("backToTimeline-m")));
    await tester.pumpAndSettle();
    expect(c.anyOverridden, isFalse);
    expect(find.byKey(const ValueKey("backToTimeline")), findsNothing,
        reason: "gone once nothing is off the timeline");
  });

  test("the list names each thing once, and sends one back alone", () {
    var c = make();
    addTearDown(c.dispose);
    holdByHand(c, "m");
    holdByHand(c, "other");
    var items = c.offTimelineItems;
    expect([for (var i in items) (i.key, i.isHeld)],
        [("m", true), ("other", true)]);
    expect(items.first.name, "Music");
    c.backToTimelineFor(items.first);
    expect([for (var i in c.offTimelineItems) i.key], ["other"]);
    expect(c.anyOverridden, isTrue, reason: "the other still held");
  });
}
