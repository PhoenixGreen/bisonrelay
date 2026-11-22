import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_rulers.dart';
import 'package:bruig/plugin_system/canvas/model/dock_layout.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/sidebar_layout.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/canvas_screen.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline/timeline_view.dart';

import 'support/canvas_app.dart';
import 'support/canvas_audio_fake.dart';

// canvas_screen_kept_test.dart is what the Canvas page remembers from one
// run of the app to the next (ui/screen/kept_view.dart), tested on the page
// itself: how it was left, whatever canvas is open, and how each saved
// canvas was looked at.

CanvasDocument _document() =>
    CanvasDocument(frames: 200, frameRate: 25, elements: [
      for (var (id, n) in [("a", "Narrator"), ("b", "Music")])
        AudioElement(ElementBase(id: id, name: n),
            clip: const MediaClip(
                playlist: [MediaSource(assetId: "t", length: 2)], timed: true)),
    ]);

CanvasController _controller() =>
    CanvasController(_document(), audioEngine: FakeEngine({"t": 2}));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CanvasScreen.framedForTest = (page) => page;
  });
  tearDown(() => CanvasScreen.framedForTest = null);

  // The sidebar put away: it sits in the app's side menu, which needs the
  // chat client.
  CanvasPreferences preferences() => CanvasPreferences()
    ..sidebars = const SidebarLayout(mode: SidebarMode.hidden);

  /// show puts the page up for [controller]; leave puts another in its
  /// place, as going to another part of the app does.
  Future<void> show(WidgetTester tester, CanvasController controller,
      CanvasPreferences prefs) async {
    setTestScreen(tester, const Size(1600, 1000));
    await tester
        .pumpWidget(canvasApp(const CanvasScreen(), prefs: prefs, extra: [
      ChangeNotifierProvider<CanvasController>.value(value: controller),
    ]));
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> leave(WidgetTester tester, CanvasController controller,
      CanvasPreferences prefs) async {
    await tester.pumpWidget(canvasApp(const SizedBox(), prefs: prefs, extra: [
      ChangeNotifierProvider<CanvasController>.value(value: controller),
    ]));
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// leaveIt changes everything the page keeps about how it was left.
  void leaveIt(CanvasController c) {
    c.fit = CanvasFit.width;
    c.cuesShown = false;
    c.setMixerSection(MixerSection.devices, BandState.minimised);
    c.returnsShown = true;
    c.motionSlots = BandState.hidden;
    c.dock = c.dock.copyWith(switcher: DockSwitcher.tabs);
    c.mixerOpen = true;
    c.mixerSize = MixerSize.minimised;
    c.headerWidth = 210;
    c.rulers = const CanvasRulers(top: true, bottom: true);
  }

  void expectLeft(CanvasController c) {
    expect(c.fit, CanvasFit.width);
    expect(c.cuesShown, isFalse);
    expect(c.bandState(MixerSection.devices), BandState.minimised);
    expect(c.returnsShown, isTrue);
    expect(c.motionSlots, BandState.hidden);
    expect(c.dock.switcher, DockSwitcher.tabs);
    expect(c.mixerOpen, isTrue);
    expect(c.mixerSize, MixerSize.minimised);
    expect(c.headerWidth, 210);
    expect(c.rulers, const CanvasRulers(top: true, bottom: true));
  }

  testWidgets("how the page was left is written down a moment after a change",
      (tester) async {
    var c = _controller();
    addTearDown(c.dispose);
    var prefs = preferences();
    await show(tester, c, prefs);

    leaveIt(c);
    await tester.pump(const Duration(seconds: 1));
    expect(prefs.fit, CanvasFit.width);
    expect(prefs.cuesShown, isFalse);
    expect(prefs.mixerBands, c.mixerBandNames);
    expect(prefs.returnsShown, isTrue);
    expect(prefs.mixerLook, c.mixerLook);
    expect(prefs.dock.switcher, DockSwitcher.tabs);
    expect(prefs.panels, c.panelState);
    expect(prefs.rulers, const CanvasRulers(top: true, bottom: true));
    await leave(tester, c, prefs);
  });

  testWidgets("and as the page is left, without the wait", (tester) async {
    var c = _controller();
    addTearDown(c.dispose);
    var prefs = preferences();
    await show(tester, c, prefs);

    leaveIt(c);
    await tester.pumpWidget(canvasApp(const SizedBox(), prefs: prefs, extra: [
      ChangeNotifierProvider<CanvasController>.value(value: c),
    ]));
    expect(prefs.fit, CanvasFit.width);
    expect(prefs.dock.switcher, DockSwitcher.tabs);
    expect(prefs.panels, c.panelState);
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets("the next run of the app opens as the last was left",
      (tester) async {
    var c = _controller();
    addTearDown(c.dispose);
    var prefs = preferences();
    await show(tester, c, prefs);
    leaveIt(c);
    await leave(tester, c, prefs);

    // Another session, with the same preferences.
    var next = _controller();
    addTearDown(next.dispose);
    await show(tester, next, prefs);
    expectLeft(next);
    await leave(tester, next, prefs);
  });

  testWidgets("coming back to the page in the same run changes nothing",
      (tester) async {
    // The session outlives the page and holds how things were left. What
    // changed while the page was away (a script, another part of the app)
    // is not undone by coming back.
    var c = _controller();
    addTearDown(c.dispose);
    var prefs = preferences();
    await show(tester, c, prefs);
    await leave(tester, c, prefs);

    leaveIt(c);
    await show(tester, c, prefs);
    expectLeft(c);
    await leave(tester, c, prefs);
  });

  testWidgets(
      "the rulers set on the guides panel are drawn at once and kept as the "
      "person's", (tester) async {
    var c = _controller();
    addTearDown(c.dispose);
    var prefs = preferences();
    await show(tester, c, prefs);

    StagePainter painter() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<StagePainter>()
        .single;
    expect(painter().inputs.guides.rulers.drawn, isFalse);

    await tester.tap(find.byTooltip("Grid, guides, rulers and snapping"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // The panel's strip scrolls sideways.
    Future<void> tap(String key) async {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pump();
    }

    await tap("guidesRulerLeft");
    expect(painter().inputs.guides.rulers, const CanvasRulers(left: true),
        reason: "drawn at once");
    await tester.pump(const Duration(seconds: 1));
    expect(prefs.rulers, const CanvasRulers(left: true), reason: "and kept");

    await tap("guidesShowRulers");
    expect(painter().inputs.guides.rulers.drawn, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(prefs.rulers, const CanvasRulers(left: true, shown: false));
    await tap("guidesShowRulers");

    // Another canvas, saved or new, opens with them as they were.
    c.load(_document(), folder: "Films", name: "One");
    await tester.pump(const Duration(seconds: 1));
    c.load(_document());
    await tester.pump(const Duration(seconds: 1));
    expect(painter().inputs.guides.rulers, const CanvasRulers(left: true));
    expect(prefs.rulers, const CanvasRulers(left: true));
    await leave(tester, c, prefs);

    // And so does the next run of the app.
    var next = _controller();
    addTearDown(next.dispose);
    await show(tester, next, prefs);
    expect(painter().inputs.guides.rulers, const CanvasRulers(left: true));
    await leave(tester, next, prefs);
  });

  group("how one canvas was looked at", () {
    /// lookAt sets the open canvas's view: a channel's height, a narrow
    /// strip, the stretch of timeline in view.
    void lookAt(CanvasController c) {
      c.setLaneHeight("a", 88);
      c.toggleNarrow("b");
      c.timelineView = const TimelineView(12, 50);
    }

    void expectLookedAt(CanvasController c) {
      expect(c.laneHeights, {"a": 88.0});
      expect(c.narrowStrips, {"b"});
      expect((c.timelineView?.first, c.timelineView?.span), (12.0, 50.0));
    }

    void expectFresh(CanvasController c) {
      expect(c.laneHeights, isEmpty);
      expect(c.narrowStrips, isEmpty);
      expect(c.timelineView, isNull);
    }

    testWidgets("is put back when it is opened again", (tester) async {
      var c = _controller();
      addTearDown(c.dispose);
      var prefs = preferences();
      await show(tester, c, prefs);

      c.load(_document(), folder: "Films", name: "One");
      await tester.pump();
      lookAt(c);
      await tester.pump(const Duration(seconds: 1));

      c.load(_document(), folder: "Films", name: "Two");
      await tester.pump();
      expectFresh(c);
      await tester.pump(const Duration(seconds: 1));

      c.load(_document(), folder: "Films", name: "One");
      await tester.pump();
      expectLookedAt(c);
      await leave(tester, c, prefs);
    });

    testWidgets("even when another is opened straight after a change",
        (tester) async {
      var c = _controller();
      addTearDown(c.dispose);
      var prefs = preferences();
      await show(tester, c, prefs);

      c.load(_document(), folder: "Films", name: "One");
      await tester.pump();
      lookAt(c);
      // No wait: the next canvas opens before the change is written down.
      c.load(_document(), folder: "Films", name: "Two");
      await tester.pump();
      c.load(_document(), folder: "Films", name: "One");
      await tester.pump();
      expectLookedAt(c);
      await leave(tester, c, prefs);
    });

    testWidgets("and in the next run of the app", (tester) async {
      var c = _controller();
      addTearDown(c.dispose);
      var prefs = preferences();
      await show(tester, c, prefs);
      c.load(_document(), folder: "Films", name: "One");
      await tester.pump();
      lookAt(c);
      await leave(tester, c, prefs);

      var next = _controller();
      addTearDown(next.dispose);
      await show(tester, next, prefs);
      next.load(_document(), folder: "Films", name: "One");
      await tester.pump();
      expectLookedAt(next);
      await leave(tester, next, prefs);
    });

    testWidgets("one never saved keeps its view while the page is away",
        (tester) async {
      var c = _controller();
      addTearDown(c.dispose);
      var prefs = preferences();
      await show(tester, c, prefs);
      lookAt(c);
      await leave(tester, c, prefs);
      await show(tester, c, prefs);
      expectLookedAt(c);
      await leave(tester, c, prefs);
    });
  });
}
