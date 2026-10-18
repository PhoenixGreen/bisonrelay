import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_cues.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/transitions_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_cues_test.dart is the run's named moments, and the elements timed
// against them.

/// _arriving is a shape whose arrival runs from [from] to [from] + 10.
ShapeElement _arriving(String id, int from) => ShapeElement(ElementBase(
    id: id,
    track: ElementTrack([
      Keyframe(frame: from, values: const {KeyframeChannel.reveal: 0}),
      Keyframe(frame: from + 10, values: const {KeyframeChannel.reveal: 1}),
    ])));

/// _two is two scenes of 100 frames, with no transition, a shape on each.
CanvasDocument _two() => CanvasDocument(scenes: [
      CanvasScene(id: "a", frames: 100, elements: [_arriving("one", 20)]),
      CanvasScene(id: "b", frames: 100, elements: [_arriving("two", 20)]),
    ]);

int _firstKey(CanvasController c, String id) {
  for (var s in c.document.allScenes) {
    for (var e in s.elements) {
      if (e.id == id) return e.base.track!.keys.first.frame;
    }
  }
  throw StateError("no $id");
}

void main() {
  // What the controls do, not where they are folded: every section open.
  setUpAll(() => CanvasSection.openAll = true);
  tearDownAll(() => CanvasSection.openAll = false);
  group("finding lines in a voice", () {
    test("a line starts where a pause ends", () {
      // Ten seconds in a hundred points: sound, half a second of quiet,
      // sound, a tenth of a second of quiet (a breath), sound.
      var peaks = Float32List(100);
      for (var i = 0; i < 100; i++) {
        peaks[i] = (i >= 30 && i < 35) || i == 70 ? 0.0 : 0.8;
      }
      expect(speechStarts(peaks, 10), [0.0, 3.5],
          reason: "the start, and after the half second -- not the breath");
    });

    test("silence finds nothing", () {
      expect(speechStarts(Float32List(50), 5), isEmpty);
    });
  });

  test("cues and what is tied to them are saved", () {
    var d = _two().copyWith(cues: const [
      TimelineCue(id: "c2", name: "two", frame: 150),
      TimelineCue(id: "c1", name: "one", frame: 30),
    ]);
    var back = CanvasDocument.decode(d.encode())!;
    expect([for (var c in back.cues) c.name], ["one", "two"],
        reason: "read back in order");
    var tied = const ElementBase(id: "x", cue: "c1");
    expect(ElementBase.fromJson(tied.toJson(), "").cue, "c1");
  });

  group("the controller", () {
    test("tying an element puts its arrival on the cue, in its own scene", () {
      var c = CanvasController(_two());
      addTearDown(c.dispose);
      var cue = c.addCue(name: "line", frame: 160);
      c.cueTo("two", cue.id);
      expect(_firstKey(c, "two"), 60, reason: "160 of the run, scene b's 60");
      expect(c.document.allScenes[1].elements.single.base.cue, cue.id);
    });

    test("moving the cue moves everything tied to it, in every scene", () {
      var c = CanvasController(_two());
      addTearDown(c.dispose);
      var cue = c.addCue(frame: 40);
      c.cueTo("one", cue.id);
      c.cueTo("two", cue.id); // before its scene; held at its first frame
      var one = _firstKey(c, "one"), two = _firstKey(c, "two");
      c.moveCue(cue.id, 52);
      expect(_firstKey(c, "one"), one + 12);
      expect(_firstKey(c, "two"), two + 12);
      expect(c.cues.single.frame, 52);
    });

    test("removing a cue lets go of what was tied to it", () {
      var c = CanvasController(_two());
      addTearDown(c.dispose);
      var cue = c.addCue(frame: 40);
      c.cueTo("one", cue.id);
      c.removeCue(cue.id);
      expect(c.cues, isEmpty);
      expect(c.document.allScenes.first.elements.single.base.cue, "");
    });

    test("finding cues puts one at each line of the voice", () async {
      var peaks = Float32List(100);
      for (var i = 0; i < 100; i++) {
        peaks[i] = i >= 30 && i < 40 ? 0.0 : 0.6;
      }
      CanvasController.seedWaveform("vo.mp3", peaks);
      var voice = AudioElement(const ElementBase(id: "vo", visible: false),
          clip: const MediaClip(
              timed: true,
              at: 72,
              playlist: [MediaSource(assetId: "vo.mp3", length: 10)]));
      var doc = _two().copyWith(
          masterOn: true, master: CanvasScene(id: "m", elements: [voice]));
      var c = CanvasController(doc);
      addTearDown(c.dispose);
      var hand = c.addCue(name: "by hand", frame: 5);
      expect(await c.findCues(voice), 2);
      expect([for (var x in c.cues) x.frame], [5, 72, 72 + 96],
          reason: "the clip starts at 72; the second line 4s in");
      // Found again, they replace what was found before -- not the one
      // added by hand.
      await c.findCues(voice);
      expect(c.cues.length, 3);
      expect(c.cues.first.id, hand.id);
    });
  });

  testWidgets("the panel adds a cue, and an element can be tied to it",
      (tester) async {
    var c = CanvasController(_two());
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(600, 1400);
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
              body: SizedBox(
                  width: 280, child: CanvasTransitionsPanel(controller: c)))),
    ));
    await tester.pumpAndSettle();
    // The cues are shown on the ruler, or not, from the end of this line.
    var shown = find.byKey(const ValueKey("cuesShown"));
    expect(tester.getCenter(shown).dy,
        tester.getCenter(find.byKey(const ValueKey("cueAdd"))).dy);
    expect(tester.getCenter(shown).dx,
        greaterThan(tester.getCenter(find.byKey(const ValueKey("cueAdd"))).dx));
    await tester.tap(shown);
    await tester.pumpAndSettle();
    expect(c.cuesShown, isFalse);
    expect(find.byTooltip("Show the cues on the timeline"), findsOneWidget);
    await tester.tap(shown);
    await tester.pumpAndSettle();
    expect(c.cuesShown, isTrue);
    await tester.tap(find.byKey(const ValueKey("cueAdd")));
    await tester.pumpAndSettle();
    expect(c.cues, hasLength(1));
    var id = c.cues.single.id;
    expect(find.byKey(ValueKey("cueName-$id")), findsOneWidget);
    tester
        .widget<CanvasNumberField>(find.byKey(ValueKey("cueAt-$id")))
        .onChanged(2.0);
    tester
        .widget<CanvasNumberField>(find.byKey(ValueKey("cueAt-$id")))
        .onCommit!();
    expect(c.cues.single.frame, 48, reason: "two seconds at 24 a second");
    await tester.tap(find.byKey(ValueKey("cueRemove-$id")));
    await tester.pumpAndSettle();
    expect(c.cues, isEmpty);
  });

  testWidgets("an element's settings tie it to a cue", (tester) async {
    var c = CanvasController(_two());
    addTearDown(c.dispose);
    var cue = c.addCue(name: "line", frame: 50);
    c.selectOnly("one");
    tester.view.physicalSize = const Size(1400, 1600);
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
      child:
          MaterialApp(home: Scaffold(body: CanvasDesignPanel(controller: c))),
    ));
    await tester.pumpAndSettle();
    var dropdown = find.descendant(
        of: find.byKey(const ValueKey("elementCue")),
        matching: find.byType(CanvasDropdown<String>));
    expect(dropdown, findsOneWidget);
    tester.widget<CanvasDropdown<String>>(dropdown).onChanged(cue.id);
    await tester.pumpAndSettle();
    expect(_firstKey(c, "one"), 50);
  });
}
