import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/media/synth/part_render.dart';
import 'package:bruig/plugin_system/canvas/media/synth/sampler.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/midi_effects.dart';
import 'package:bruig/plugin_system/canvas/model/session.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/plugin_system/canvas/ui/piano_roll.dart';
import 'package:bruig/plugin_system/canvas/media/midi_input.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_piano_roll_test.dart is the piano roll -- notes drawn, moved,
// stretched, quantised, their velocities -- and the controllers' curves in
// the lane under it: expression, the mod wheel, pitch bend and the rest,
// heard both when a part is played into a file and live from a keyboard.

/// loudness is how much sound there is in [l] from [from] to [to].
double loudness(Float32List l, int from, int to) {
  var sum = 0.0;
  for (var i = from; i < math.min(to, l.length); i++) {
    sum += l[i] * l[i];
  }
  return sum;
}

void main() {
  group("controllers", () {
    test("a curve goes in straight lines between its points", () {
      const points = [(1.0, 0.0), (3.0, 1.0)];
      expect(controlAt(points, 0, 0.5), 0, reason: "before: the first");
      expect(controlAt(points, 2, 0.5), closeTo(0.5, 1e-9));
      expect(controlAt(points, 9, 0.5), 1, reason: "after: the last");
      expect(controlAt(const [], 2, 0.7), 0.7, reason: "none: at rest");
    });

    test("a part's curves are saved, and change what is played", () {
      var part = const InstrumentPart(notes: [
        MidiNote(60, 0, 1)
      ], controls: {
        MidiControl.expression: [(0.0, 0.5), (1.0, 1.0)],
        MidiControl.pitchBend: [(0.5, 0.75)],
      });
      var back = InstrumentPart.fromJson(part.toJson());
      expect(back.controls[MidiControl.expression], [(0.0, 0.5), (1.0, 1.0)]);
      expect(back.controls[MidiControl.pitchBend], [(0.5, 0.75)]);
      expect(part.signature,
          isNot(const InstrumentPart(notes: [MidiNote(60, 0, 1)]).signature));
    });

    test("expression turns a part down, to nothing at nought", () {
      const note = [MidiNote(60, 0, 1)];
      var (full, _) = renderPart(const InstrumentPart(notes: note), null);
      var (quiet, _) = renderPart(
          const InstrumentPart(notes: note, controls: {
            MidiControl.expression: [(0.0, 0.0)],
          }),
          null);
      expect(loudness(full, 0, mixRate), greaterThan(0));
      expect(loudness(quiet, 0, mixRate), lessThan(1e-9));
    });

    test("the sustain pedal holds a note past its end", () {
      // A note of a tenth of a second, the pedal down for the first half
      // second: heard on after the note has ended.
      const note = [MidiNote(60, 0, 0.1)];
      var (dry, _) = renderPart(const InstrumentPart(notes: note), null);
      var (held, _) = renderPart(
          const InstrumentPart(notes: note, controls: {
            MidiControl.sustain: [(0.0, 1.0), (0.5, 1.0), (0.51, 0.0)],
          }),
          null);
      var after = (0.3 * mixRate).round(), until = (0.45 * mixRate).round();
      expect(loudness(held, after, until),
          greaterThan(loudness(dry, after, until) * 4));
    });

    test("pitch bend raises the pitch, and the mod wheel swings it", () {
      // The piano's pitch, as how often it crosses nought.
      int crossings(Float32List l) {
        var n = 0;
        for (var i = 1; i < mixRate ~/ 4; i++) {
          if ((l[i - 1] < 0) != (l[i] < 0)) n++;
        }
        return n;
      }

      var plain = Sampler(), bent = Sampler();
      bent.control(MidiControl.pitchBend, 1);
      var a = Float32List(mixRate ~/ 4), b = Float32List(mixRate ~/ 4);
      plain.noteOn(57, 100);
      bent.noteOn(57, 100);
      for (var at = 0; at < a.length; at += 256) {
        var n = math.min(256, a.length - at);
        var x = Float32List(n), y = Float32List(n);
        plain.render(x, x, n);
        bent.render(y, y, n);
        a.setRange(at, at + n, x);
        b.setRange(at, at + n, y);
      }
      // Two semitones up: about an eighth more crossings.
      expect(crossings(b) / crossings(a), closeTo(math.pow(2, 2 / 12), 0.06));
    });
  });

  group("live", () {
    test("a keyboard's controllers reach the channels that hear it", () async {
      var engine = FakeEngine({});
      var c = CanvasController(
          CanvasDocument(frames: 100, elements: [
            AudioElement(const ElementBase(id: "p"),
                clip: const MediaClip(timed: true),
                instrument: const InstrumentPart(monitor: MidiMonitor.input)),
          ]),
          audioEngine: engine);
      addTearDown(c.dispose);
      c.midiNote(60, 100); // the engine started, as the first note does
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      c.midiControl(MidiControl.modulation, 0.6);
      expect(engine.controls, [("p", MidiControl.modulation, 0.6)]);
    });

    test("recorded, the controllers moved go into the part", () async {
      var c = CanvasController(
          CanvasDocument(frames: 2000, frameRate: 100, elements: [
            AudioElement(const ElementBase(id: "p"),
                clip: const MediaClip(timed: true),
                instrument: const InstrumentPart()),
          ]),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      c.recording = true;
      c.midiControl(MidiControl.expression, 0.2);
      c.tickForTest();
      c.midiControl(MidiControl.expression, 0.9);
      c.recording = false;
      var part = (c.document.elements.single as AudioElement).instrument!;
      expect(
          part.controls[MidiControl.expression]!.map((p) => p.$2), [0.2, 0.9]);
      c.pause();
    });

    test("pitch bend and the mod wheel are read from the keyboard", () {
      var got = <(MidiControl, double)>[];
      var input = MidiInput()..onControl = (c, v) => got.add((c, v));
      input.handle(Uint8List.fromList([0xE0, 0x00, 0x60])); // bent up
      input.handle(Uint8List.fromList([0xB0, 1, 127])); // mod wheel full
      expect(got.first.$1, MidiControl.pitchBend);
      expect(got.first.$2, closeTo(0.75, 0.01));
      expect(got.last, (MidiControl.modulation, 1.0));
    });
  });

  group("the piano roll", () {
    late CanvasController c;

    Future<void> open(WidgetTester tester,
        {int? row,
        double height = 760,
        double bars = 2,
        double scale = 1}) async {
      c = CanvasController(
          CanvasDocument(
              frames: 100,
              audio: const AudioSettings(tempo: 120),
              elements: [
                AudioElement(const ElementBase(id: "p", name: "Keys"),
                    clip: const MediaClip(timed: true),
                    instrument: const InstrumentPart()),
              ],
              session: const SessionGrid().put(
                  "p",
                  0,
                  SessionClip(
                      id: "clip",
                      name: "Chords",
                      midi: true,
                      bars: bars,
                      notes: const [
                        MidiNote(60, 0.1, 1),
                        MidiNote(64, 1.05, 1),
                      ]))),
          audioEngine: FakeEngine({}));
      c.openPianoRoll("p", row: row);
      // Tall enough that the keys the tests press are in view, in the
      // editor in the effects strip.
      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ],
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: Scaffold(
                body: Align(
                    alignment: Alignment.bottomCenter,
                    child: ListenableBuilder(
                        listenable: c,
                        builder: (context, _) => CanvasMixer.effects(
                            controller: c,
                            height: height,
                            onResize: (_) {},
                            onClose: () {}))))),
      ));
      await tester.pump();
      await tester.pump();
      // Any scroll to the editor done: a scroll view takes no presses while
      // it moves.
      await tester.pump(const Duration(milliseconds: 450));
    }

    Future<void> done(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }

    /// at is where beat [beat] of key [key] is on the screen: a beat is 48
    /// wide, a key 12 high, the top row key 127.
    Offset at(WidgetTester tester, double beat, int key) =>
        tester.getTopLeft(find.byKey(const ValueKey("rollGrid"))) +
        Offset(beat * 48 + 3, (127 - key) * 12 + 6);

    List<MidiNote> notes() => c.session.at("p", 0)!.notes;

    testWidgets("opens on a clip's notes, from its slot's menu too",
        (tester) async {
      await open(tester, row: 0);
      expect(find.byKey(const ValueKey("rollGrid")), findsOneWidget);
      expect(find.text("Chords"), findsOneWidget);
      expect(c.rollContent!.beats, 8, reason: "two bars of four");
      // In the clip's editor, first in the channel's effects strip; closed
      // from its bar.
      expect(find.byKey(const ValueKey("device-clip")), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("editorClose")));
      await tester.pump();
      expect(c.clipEditorShown, isFalse);
      expect(find.byKey(const ValueKey("rollGrid")), findsNothing);
      await done(tester);
    });

    testWidgets("a press draws a note a grid step long, on its key",
        (tester) async {
      await open(tester, row: 0);
      await tester.tapAt(at(tester, 4, 67));
      await tester.pump();
      var n = notes().last;
      expect(n.key, 67);
      expect(n.start, 4);
      expect(n.length, 0.25, reason: "a sixteenth: the grid");
      c.undo();
      expect(notes(), hasLength(2), reason: "one change to undo");
      await done(tester);
    });

    testWidgets("drawn by dragging, a note is as long as the drag",
        (tester) async {
      await open(tester, row: 0);
      var g = await tester.startGesture(at(tester, 2, 62));
      await g.moveBy(const Offset(20, 0));
      await g.moveTo(at(tester, 3.5, 62));
      await g.up();
      await tester.pump();
      var n = notes().last;
      expect((n.key, n.start), (62, 2));
      expect(n.length, closeTo(1.5, 0.26));
      c.undo();
      expect(notes(), hasLength(2), reason: "the whole drag, one undo");
      await done(tester);
    });

    testWidgets("a note dragged moves on the grid, and Delete takes it out",
        (tester) async {
      await open(tester, row: 0);
      var g = await tester.startGesture(at(tester, 0.3, 60));
      await g.moveBy(const Offset(10, 0));
      await g.moveTo(at(tester, 2.3, 62));
      await g.up();
      await tester.pump();
      var n = notes().first;
      expect(n.key, 62);
      expect(n.start, closeTo(2.1, 0.001),
          reason: "moved two beats, kept "
              "where it was within one");
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(notes(), hasLength(1));
      await done(tester);
    });

    testWidgets("Quantise puts them on the grid", (tester) async {
      await open(tester, row: 0);
      await tester.tap(find.byKey(const ValueKey("rollQuantise")));
      await tester.pump();
      expect(notes().map((n) => n.start), [0, 1]);
      await done(tester);
    });

    testWidgets("the velocity lane sets how hard a note is played",
        (tester) async {
      await open(tester, row: 0);
      var lane = find.byKey(const ValueKey("rollVelocity"));
      var box = tester.getRect(lane);
      // The first note's bar, near the top: hard.
      await tester.tapAt(Offset(box.left + 0.1 * 48 + 2, box.top + 8));
      await tester.pump();
      expect(notes().first.velocity, greaterThan(115));
      await done(tester);
    });

    testWidgets("a controller's lane takes points", (tester) async {
      await open(tester, row: 0);
      tester
          .widget<DropdownButton<RollLane>>(
              find.byKey(const ValueKey("rollLane")))
          .onChanged!(const RollLane(MidiControl.expression));
      await tester.pump();
      var lane = find.byKey(const ValueKey("rollLane-expression"));
      expect(lane, findsOneWidget);
      var box = tester.getRect(lane);
      await tester.tapAt(Offset(box.left + 96, box.bottom - 6));
      await tester.pump();
      var points = c.session.at("p", 0)!.controls[MidiControl.expression]!;
      expect(points.single.$1, closeTo(2, 0.01));
      expect(points.single.$2, lessThan(0.1));
      await done(tester);
    });

    // Ken's log: a drag on an empty stretch of a controller's lane threw
    // a RangeError -- its first move came before the frame showing the
    // point its press had put down.
    testWidgets("a drag on an empty lane puts a point down and moves it",
        (tester) async {
      await open(tester, row: 0);
      tester
          .widget<DropdownButton<RollLane>>(
              find.byKey(const ValueKey("rollLane")))
          .onChanged!(const RollLane(MidiControl.modulation));
      await tester.pump();
      var box =
          tester.getRect(find.byKey(const ValueKey("rollLane-modulation")));
      var g = await tester.startGesture(Offset(box.left + 48, box.bottom - 10));
      // Moves with no frame between them.
      await g.moveBy(const Offset(0, -20));
      await g.moveBy(const Offset(10, -20));
      await g.moveBy(const Offset(10, -20));
      await g.up();
      await tester.pump();
      expect(tester.takeException(), isNull);
      var points = c.session.at("p", 0)!.controls[MidiControl.modulation]!;
      expect(points, hasLength(1));
      expect(points.single.$2, greaterThan(0.5), reason: "dragged up");
      c.undo();
      expect(c.session.at("p", 0)!.controls[MidiControl.modulation], isNull,
          reason: "one change to undo");
      await done(tester);
    });

    // Ken's log: the clip editor's piano roll overflowed, short.
    testWidgets("short, its lanes fold to a bar, never overflowing",
        (tester) async {
      // In the mixer's effects at any height: never an overflow.
      for (var h in [200.0, 240.0, 300.0, 760.0]) {
        await open(tester, row: 0, height: h);
        expect(tester.takeException(), isNull, reason: "at $h");
        await done(tester);
      }
      // As short as Ken's log had it: 117 high, the lanes folded away.
      await open(tester, row: 0);
      for (var (h, lanes) in [(117.0, false), (400.0, true)]) {
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeNotifier>(
                create: (c) => ThemeNotifier(doLoad: false)),
            ChangeNotifierProvider<SnackBarModel>(
                create: (c) => SnackBarModel()),
          ],
          child: MaterialApp(
              home: Scaffold(
                  body: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                          width: 574,
                          height: h,
                          child:
                              PianoRoll(controller: c, inClipEditor: true))))),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: "$h high");
        expect(find.byKey(const ValueKey("rollVelocity")),
            lanes ? findsOneWidget : findsNothing,
            reason: "$h high");
        // Folded, a bar naming them.
        expect(find.byKey(const ValueKey("rollLaneHeading-0")),
            lanes ? findsOneWidget : findsNothing);
        expect(find.byKey(const ValueKey("rollLanesFolded")),
            lanes ? findsNothing : findsOneWidget);
      }
      await done(tester);
    });

    // Ken: the lanes folded, chosen in the lane itself, and a second one.
    testWidgets(
        "the lanes fold, are chosen in their panels, and a second is "
        "added", (tester) async {
      await open(tester, row: 0);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey("rollLaneHeading-0")),
              matching: find.byKey(const ValueKey("rollLane"))),
          findsOneWidget,
          reason: "the lane's choice in its panel, not the toolbar");
      await tester.tap(find.byKey(const ValueKey("rollLanesOpen-0")));
      await tester.pump();
      expect(find.byKey(const ValueKey("rollVelocity")), findsNothing);
      await tester.tap(find.byKey(const ValueKey("rollLanesOpen-0")));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("rollLaneAdd")));
      await tester.pump();
      expect(find.byKey(const ValueKey("rollLaneHeading-1")), findsOneWidget);
      expect(find.byKey(const ValueKey("rollVelocity")), findsOneWidget);
      expect(find.byKey(const ValueKey("rollLane-expression")), findsOneWidget,
          reason: "the second lane: the first controller");
      expect(find.byKey(const ValueKey("rollLaneAdd")), findsNothing,
          reason: "two at most");
      await tester.tap(find.byKey(const ValueKey("rollLaneRemove")));
      await tester.pump();
      expect(find.byKey(const ValueKey("rollLaneHeading-1")), findsNothing);
      expect(tester.takeException(), isNull);
      await done(tester);
    });

    // Ken: two fingers on a trackpad scroll, and drew notes.
    testWidgets("a two-finger swipe over the notes draws none", (tester) async {
      await open(tester, row: 0);
      var before = notes().length;
      var swipe = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      var from = at(tester, 3, 70);
      await swipe.panZoomStart(from);
      for (var i = 1; i <= 6; i++) {
        await swipe.panZoomUpdate(from, pan: Offset(i * 12.0, i * 6.0));
        await tester.pump();
      }
      await swipe.panZoomEnd();
      await tester.pump();
      expect(notes(), hasLength(before));
      await done(tester);
    });

    // Ken: at its far end the zoom shows every bar -- 32 of them.
    testWidgets("zoomed all the way out, the whole clip is in view",
        (tester) async {
      await open(tester, row: 0, bars: 32);
      tester
          .widget<Slider>(find.byKey(const ValueKey("rollZoom")))
          .onChanged!(1);
      await tester.pump();
      var grid = tester.getSize(find.byKey(const ValueKey("rollGrid")));
      // The width beside the keys -- and the lanes' panels under them.
      var view = tester.getSize(find.byType(PianoRoll)).width -
          tester.getSize(find.byKey(const ValueKey("rollLaneHeading-0"))).width;
      expect(grid.width, lessThanOrEqualTo(view),
          reason: "32 bars in the width there is");
      tester
          .widget<Slider>(find.byKey(const ValueKey("rollZoom")))
          .onChanged!(0);
      await tester.pump();
      expect(tester.getSize(find.byKey(const ValueKey("rollGrid"))).width,
          closeTo(32 * 4 * 160.0, 0.01),
          reason: "closest: a beat 160 wide");
      await done(tester);
    });

    // Ken: a lane's settings in its panel at the left, not along its top.
    for (var scale in [1.0, 1.5]) {
      testWidgets("a lane's settings are in its panel at its left, at $scale",
          (tester) async {
        await open(tester, row: 0, scale: scale);
        expect(tester.takeException(), isNull);
        var panel =
            tester.getRect(find.byKey(const ValueKey("rollLaneHeading-0")));
        var lane = tester.getRect(find.byKey(const ValueKey("rollVelocity")));
        expect(panel.right, lessThanOrEqualTo(lane.left + 0.5));
        expect(panel.top, closeTo(lane.top, 0.5), reason: "beside it");
        expect(
            find.descendant(
                of: find.byKey(const ValueKey("rollLaneHeading-0")),
                matching: find.byKey(const ValueKey("rollLane"))),
            findsOneWidget);
        await tester.tap(find.byKey(const ValueKey("rollLaneAdd")));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey("rollLaneHeading-1")), findsOneWidget);
        await done(tester);
      });
    }

    // Ken: the lanes made taller or shorter.
    testWidgets("the lanes' edge is dragged to make them taller or shorter",
        (tester) async {
      await open(tester, row: 0);
      double lane() =>
          tester.getSize(find.byKey(const ValueKey("rollVelocity"))).height;
      var was = lane();
      var edge = find.byKey(const ValueKey("rollLanesEdge"));
      var drag = await tester.startGesture(tester.getCenter(edge),
          kind: PointerDeviceKind.mouse);
      for (var i = 0; i < 6; i++) {
        await drag.moveBy(const Offset(0, -10));
        await tester.pump();
      }
      await drag.up();
      await tester.pump();
      expect(lane(), closeTo(was + 60, 1));
      // Down past its least: no shorter than that.
      await tester.drag(edge, const Offset(0, 400),
          kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(lane(), 48);
      expect(tester.takeException(), isNull);
      await done(tester);
    });

    // Ken: the playhead dragged, for notes copied to be pasted there.
    testWidgets("the ruler's playhead is dragged, and notes paste at it",
        (tester) async {
      await open(tester, row: 0);
      var ruler = tester.getTopLeft(find.byKey(const ValueKey("rollRuler")));
      var drag = await tester.startGesture(ruler + const Offset(10, 10),
          kind: PointerDeviceKind.mouse);
      for (var i = 0; i < 10; i++) {
        await drag.moveBy(const Offset(18.2, 0));
        await tester.pump();
      }
      await drag.up();
      await tester.pump();
      expect(c.rollCursor, 4, reason: "to the grid, from where it was pressed");
      // The first note picked, copied, pasted at it -- picked in its place.
      await tester.tapAt(at(tester, 0.3, 60));
      await tester.pump();
      // Along the toolbar, scrolled to in an editor this narrow.
      for (var k in ["rollCopy", "rollPaste"]) {
        await tester.ensureVisible(find.byKey(ValueKey(k)));
        await tester.pump();
        await tester.tap(find.byKey(ValueKey(k)));
      }
      await tester.pump();
      expect(notes(), hasLength(3));
      expect(notes().last.key, 60);
      expect(notes().last.start, 4);
      expect(c.rollSelected, {2});
      expect(c.rollCursor, 5, reason: "on past it: the next follows on");
      // And by the keys.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(notes(), hasLength(4));
      expect(notes().last.start, 5);
      await done(tester);
    });

    // Ken: a part's piano roll had no settings beside it, and no Play.
    testWidgets("a part's roll has its settings beside it, and Play",
        (tester) async {
      await open(tester);
      c.setRollContent(notes: const [MidiNote(60, 0, 1)]);
      await tester.pump();
      expect(find.byKey(const ValueKey("device-roll")), findsOneWidget);
      expect(find.byKey(const ValueKey("partColumn")), findsOneWidget);
      // The columns a slot's clip has: Clip, Launch, Notes.
      expect(find.byKey(const ValueKey("clipShow-2")), findsOneWidget);
      // Its notes' tools, as a clip's.
      await tester.tap(find.byKey(const ValueKey("clipShow-2")));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("noteTool-up")));
      await tester.pump();
      expect(c.rollContent!.notes.single.key, 61);
      await tester.tap(find.byKey(const ValueKey("clipShow-0")));
      await tester.pump();
      // Moved along the timeline a bar: four beats at 120.
      var bar = (4 * 0.5 * c.document.frameRate).round();
      await tester.tap(find.byKey(const ValueKey("partStart-up")));
      await tester.pump();
      var part = c.document.elements.single as AudioElement;
      expect(part.clip.at, bar);
      await tester.tap(find.byKey(const ValueKey("partStart-down")));
      await tester.pump();
      // The playhead, dragged along the ruler, is the timeline's.
      var ruler = tester.getTopLeft(find.byKey(const ValueKey("rollRuler")));
      await tester.tapAt(ruler + const Offset(48 * 2 + 1, 10),
          kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(c.frame, (2 * 0.5 * c.document.frameRate).round());
      expect(c.rollCursor, closeTo(2, 1e-9));
      // Play, from there; and Stop.
      await tester.tap(find.byKey(const ValueKey("partPlay")));
      await tester.pump();
      expect(c.playing, isTrue);
      await tester.tap(find.byKey(const ValueKey("partPlay")));
      await tester.pump();
      expect(c.playing, isFalse);
      // Launched only from a slot: copied into the first empty one, and
      // opened there.
      await tester.tap(find.byKey(const ValueKey("clipShow-1")));
      await tester.pump();
      expect(find.byKey(const ValueKey("launchColumn")), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("partToSlot")));
      await tester.pump(const Duration(milliseconds: 450));
      // Slot 1 held the test's clip already: the part went into slot 2.
      var copy = c.session.at("p", 1)!;
      expect(copy.midi, isTrue);
      expect(copy.notes.single.key, 61);
      expect(c.clipEditing?.row, 1);
      expect(find.byKey(const ValueKey("device-clip")), findsOneWidget);
      expect(tester.takeException(), isNull);
      await done(tester);
    });

    for (var scale in [1.0, 1.25, 1.5]) {
      testWidgets("a part's editor fits, narrow and wide, at $scale",
          (tester) async {
        await open(tester, scale: scale);
        expect(tester.takeException(), isNull, reason: "narrow");
        c.toggleEditorWide();
        await tester.pump(const Duration(milliseconds: 450));
        expect(tester.takeException(), isNull, reason: "wide");
        expect(find.byKey(const ValueKey("partColumn")), findsOneWidget);
        expect(find.byKey(const ValueKey("notesColumn")), findsOneWidget);
        await done(tester);
      });
    }

    testWidgets("Fold shows only the keys with notes", (tester) async {
      await open(tester, row: 0);
      var tall = tester.getSize(find.byKey(const ValueKey("rollGrid"))).height;
      await tester.tap(find.byKey(const ValueKey("rollFold")));
      await tester.pump();
      expect(tester.getSize(find.byKey(const ValueKey("rollGrid"))).height,
          lessThan(tall / 10));
      await done(tester);
    });

    testWidgets("a part is edited in beats, written back in seconds",
        (tester) async {
      await open(tester);
      expect(c.rollContent!.clip, isFalse);
      await tester.tapAt(at(tester, 2, 60));
      await tester.pump();
      var part = (c.document.elements.single as AudioElement).instrument!;
      expect(part.notes.single.start, closeTo(1, 1e-9),
          reason: "two beats at 120 is a second");
      expect(part.notes.single.length, closeTo(0.125, 1e-9));
      await done(tester);
    });

    testWidgets("an empty MIDI slot makes a clip to draw into", (tester) async {
      await open(tester, row: 0);
      c.newMidiClip("p", 1);
      c.openPianoRoll("p", row: 1);
      await tester.pump();
      expect(c.rollContent!.notes, isEmpty);
      expect(c.rollContent!.beats, 4);
      await done(tester);
    });
  });

  // Ken's log also had the panel a few pixels too short: a MIDI channel's
  // chain and the piano roll, at every height and text size.
  testWidgets("a MIDI channel's chain and piano roll fit, at every size",
      (tester) async {
    var failures = <String>[];
    for (var scale in [1.0, 1.15, 1.25, 1.5]) {
      for (var roll in [false, true]) {
        for (var h = 200.0; h <= 620; h += 20) {
          var c = CanvasController(
              CanvasDocument(frames: 100, elements: [
                AudioElement(const ElementBase(id: "p", name: "Keys"),
                    clip: const MediaClip(timed: true),
                    instrument: const InstrumentPart(effects: [
                      MidiEffect(MidiEffectKind.arpeggiator),
                      MidiEffect(MidiEffectKind.chord),
                    ])),
              ]),
              audioEngine: FakeEngine({}));
          roll ? c.openPianoRoll("p") : c.openEffects("p");
          tester.view.physicalSize = const Size(1600, 900);
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeNotifier>(
                  create: (c) => ThemeNotifier(doLoad: false)),
              ChangeNotifierProvider<SnackBarModel>(
                  create: (c) => SnackBarModel()),
            ],
            child: MaterialApp(
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!),
                home: Scaffold(
                    body: Align(
                        alignment: Alignment.bottomCenter,
                        child: CanvasMixer.effects(
                            controller: c,
                            height: h,
                            onResize: (_) {},
                            onClose: () {})))),
          ));
          await tester.pump();
          if (tester.takeException() case var e?) {
            failures.add("${roll ? "roll" : "chain"} $h ${scale}x: "
                "${e.toString().split("\n").first}");
          }
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pumpWidget(const SizedBox());
          c.dispose();
        }
      }
    }
    tester.view.reset();
    expect(failures, isEmpty);
  });
}
