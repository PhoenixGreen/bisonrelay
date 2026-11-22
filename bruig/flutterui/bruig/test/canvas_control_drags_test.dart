import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'support/canvas_app.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/code_starters.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/code_runners.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_run_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/synth_module_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/synth_patch.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/render/code_painter.dart';
import 'package:bruig/plugin_system/canvas/render/code_run_painter.dart';
import 'package:bruig/plugin_system/canvas/render/counter_painter.dart';
import 'package:bruig/plugin_system/canvas/render/synth_module_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_text_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline/marker_note.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/canvas_audio_fake.dart';

// canvas_control_drags_test.dart is a drag on an element's own controls, as
// the person doing it sees it: a chart's label, a table's column rule, a
// counter's loose piece, a team's player, a synth module's key, knob,
// screen and cable, a Code panel's playbar, divider and tab, the held
// marker's note on the page, and the retouching brush's stroke. Each is
// held two ways: let go, it does what it does; cancelled by the system
// partway, what it did so far is kept (or, where it finishes by dropping
// something, nothing is dropped). Either way nothing of the press is left
// behind: no gesture under way and no undo step open.

const _viewport = Size(1600, 1000);

/// _FakeHost runs nothing: it says the page is ready and makes a picture,
/// as a browser would.
class _FakeHost implements CodeRunHost {
  @override
  Future<CodeRunOutcome> run(CodeRunner runner, CodeElement code,
          CodeFile entry, Size size, void Function(CodeLog) onLog) async =>
      const CodeRunOutcome(logs: [CodeLog("Page ready")], picture: [1, 2, 3]);
}

void main() {
  /// pump shows [controller] on a stage and hands back its state.
  Future<CanvasStageState> pump(
      WidgetTester tester, CanvasController controller) async {
    var key = GlobalKey<CanvasStageState>();
    setTestScreen(tester, _viewport);
    await tester.pumpWidget(canvasApp(SizedBox(
        width: _viewport.width,
        height: _viewport.height,
        child: CanvasStage(key: key, controller: controller))));
    await tester.pumpAndSettle();
    return key.currentState!;
  }

  /// steps presses at [from] and takes the pointer [by] in [count] even
  /// steps, then lets go there or, with [cancel], has the system take it.
  /// [settle] is how the frames after are pumped.
  Future<void> steps(WidgetTester tester, Offset from, Offset by,
      {bool cancel = false,
      int count = 4,
      Future<void> Function()? settle}) async {
    var g = await tester.startGesture(from);
    await tester.pump();
    for (var i = 0; i < count; i++) {
      await g.moveBy(by / count.toDouble());
      await tester.pump();
    }
    if (cancel) {
      await g.cancel();
    } else {
      await g.up();
    }
    await (settle?.call() ?? tester.pumpAndSettle());
  }

  /// settled is that nothing of the last press is left: no gesture under
  /// way and no undo step open.
  void settled(CanvasStageState stage, CanvasController c, String how) {
    expect(stage.gestureUnderWay, isFalse, reason: "$how: no gesture left");
    expect(c.interacting, isFalse, reason: "$how: no undo step left open");
  }

  String how(bool cancel) => cancel ? "cancelled" : "let go";

  group("a chart's label", () {
    CanvasController titled() => CanvasController(CanvasDocument(
            size: const CanvasSize(width: 800, ratio: CanvasRatio.wide),
            elements: [
              ChartElement(
                const ElementBase(
                    id: "c", x: 40, y: 40, width: 600, height: 340),
                title: "Title",
                titleBox:
                    const ChartLabel(x: 0.05, y: 0.05, width: 0.3, height: 0.1),
                floatingLabels: true,
                data: ChartData.parse(
                    "Cat\tOne\tTwo\n2019\t10\t200\n2020\t20\t400"),
              ),
            ]));

    for (var cancel in [false, true]) {
      testWidgets("its title dragged and ${how(cancel)}: moved, one undo step",
          (tester) async {
        var c = titled();
        addTearDown(c.dispose);
        c.selectOnly("c");
        var stage = await pump(tester, c);
        ChartElement now() => c.document.elementById("c")! as ChartElement;
        var title =
            chartLabelPlaces(now(), now().bounds)[ChartLabelPart.title]!;

        await steps(
            tester, stage.toStagePoint(title.center), const Offset(80, 40),
            cancel: cancel);
        expect(now().titleBox.x, greaterThan(0.06), reason: "the title moved");
        expect(now().x, 40, reason: "the chart did not");
        settled(stage, c, how(cancel));
        c.undo();
        expect(now().titleBox.x, 0.05, reason: "one undo takes it back");
      });
    }

    CanvasController keyed({bool placed = false}) {
      var e = ChartElement(
        const ElementBase(id: "c", x: 40, y: 40, width: 600, height: 340),
        showLegend: true,
        data: ChartData.parse("Cat\tOne\tTwo\n2019\t10\t200\n2020\t20\t400"),
      );
      if (placed) {
        var block = chartLegendBlock(e, e.bounds);
        e = e.copyWith(
            legend: e.legend.copyWith(
          x: (block.left - e.bounds.left) / e.bounds.width,
          y: (block.top - e.bounds.top) / e.bounds.height,
        ));
      }
      return CanvasController(CanvasDocument(
          size: const CanvasSize(width: 800, ratio: CanvasRatio.wide),
          elements: [e]));
    }

    testWidgets("its placed key dragged and cancelled: moved, no switch",
        (tester) async {
      var c = keyed(placed: true);
      addTearDown(c.dispose);
      c.selectOnly("c");
      var stage = await pump(tester, c);
      ChartElement now() => c.document.elementById("c")! as ChartElement;
      var was = now().legend.x;
      var at = stage
          .toStagePoint(chartLegendRects(now(), now().bounds)[1].$2.center);

      await steps(tester, at, const Offset(60, 0), cancel: true);
      expect(now().legend.x, greaterThan(was), reason: "the key moved");
      expect(now().data.series[1].hidden, isFalse, reason: "no switch");
      expect(now().x, 40);
      settled(stage, c, "cancelled");
      c.undo();
      expect(now().legend.x, was);
    });

    testWidgets(
        "its key held, then dragged: the press takes the key, one undo step",
        (tester) async {
      // The hold hands the move it began over to a drag of the key, in the
      // same undo step.
      var c = keyed();
      addTearDown(c.dispose);
      c.selectOnly("c");
      var stage = await pump(tester, c);
      ChartElement now() => c.document.elementById("c")! as ChartElement;
      var at = stage
          .toStagePoint(chartLegendRects(now(), now().bounds)[1].$2.center);

      var g = await tester.startGesture(at);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(now().legend.hasPlace, isTrue, reason: "the hold took the key");
      var placed = now().legend.x;
      for (var i = 0; i < 3; i++) {
        await g.moveBy(const Offset(20, 0));
        await tester.pump();
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(now().legend.x, greaterThan(placed), reason: "the key moved");
      expect(now().x, 40, reason: "the chart did not");
      expect(now().data.series[1].hidden, isFalse, reason: "no switch");
      settled(stage, c, "let go");
      c.undo();
      expect(now().legend.hasPlace, isFalse,
          reason: "one undo takes back the hold and the drag");
    });
  });

  group("a table's column rule", () {
    for (var cancel in [false, true]) {
      testWidgets("dragged and ${how(cancel)}: widths changed, one undo step",
          (tester) async {
        const table = TableElement(
          ElementBase(id: "t", x: 200, y: 150, width: 600, height: 300),
          rows: [
            ["Team", "Points"],
            ["Hull City", "6"],
          ],
          columnWidths: [0.5, 0.5],
        );
        var c = CanvasController(const CanvasDocument().addElement(table));
        addTearDown(c.dispose);
        c.selectOnly("t");
        var stage = await pump(tester, c);
        TableElement now() => c.document.elementById("t")! as TableElement;

        await steps(tester, stage.toStagePoint(const Offset(500, 300)),
            const Offset(60, 0),
            cancel: cancel);
        expect(now().columnWidths.first, greaterThan(0.5));
        expect(now().x, table.x, reason: "the table did not move");
        settled(stage, c, how(cancel));
        c.undo();
        expect(now().columnWidths, [0.5, 0.5]);
      });
    }
  });

  group("a counter's loose piece", () {
    testWidgets("dragged and cancelled: moved, no button pressed",
        (tester) async {
      const e = CounterElement(
          ElementBase(id: "n", x: 400, y: 200, width: 300, height: 160),
          keyed: false,
          buttons: [CounterButton.input],
          looseButtons: true,
          buttonAt: [Offset(0.3, 0.2)]);
      var c = CanvasController(const CanvasDocument().addElement(e));
      addTearDown(c.dispose);
      c.selectOnly("n");
      var stage = await pump(tester, c);
      CounterElement now() => c.document.elementById("n")! as CounterElement;
      var at =
          stage.toStagePoint(counterButtonRects(e, e.bounds).single.center);

      await steps(tester, at, const Offset(-40, 0), cancel: true);
      expect(now().placedButton(0).dx, lessThan(0.3), reason: "moved");
      expect(find.byType(CounterInput), findsNothing);
      settled(stage, c, "cancelled");
      c.undo();
      expect(now().placedButton(0).dx, 0.3);
    });
  });

  group("a team's player", () {
    for (var cancel in [false, true]) {
      testWidgets("dragged and ${how(cancel)}: moved, one undo step",
          (tester) async {
        var document = const CanvasDocument();
        var team = TeamElement(
          ElementBase(
            id: "team",
            x: 0,
            y: 0,
            width: document.size.width.toDouble(),
            height: document.size.height.toDouble(),
          ),
          dotWidth: 60,
          dotHeight: 60,
        ).withFormation(TeamFormation.f442);
        var c = CanvasController(document.addElement(team));
        addTearDown(c.dispose);
        c.selectOnly(team.id);
        var stage = await pump(tester, c);
        TeamElement now() => c.document.elementById("team")! as TeamElement;
        var before = team.players[5];

        await steps(tester, stage.toStagePoint(team.centreOf(before)),
            const Offset(40, -30),
            cancel: cancel);
        expect(now().players[5].dx, isNot(before.dx), reason: "moved");
        expect(now().x, team.x, reason: "the team's box did not");
        expect(c.focusedPlayer, 5, reason: "the timeline points at him");
        settled(stage, c, how(cancel));
        c.undo();
        expect(now().players[5].dx, before.dx);
      });
    }
  });

  group("a synth module's controls", () {
    /// of is the module of [kind] in [c]'s document, as it is now.
    SynthModuleElement of(CanvasController c, SynthModuleKind kind) =>
        c.document.elements
            .whereType<SynthModuleElement>()
            .firstWhere((e) => e.module == kind);

    /// on is panel point [q] of [e], in document space.
    Offset on(SynthModuleElement e, Offset q) {
      var (s, at) = synthPanelFit(e.bounds, synthPanelFor(e));
      return at + q * s;
    }

    /// rack is a synth rack on a stage, nothing picked.
    Future<(CanvasController, CanvasStageState)> rack(
        WidgetTester tester) async {
      var c = CanvasController(const CanvasDocument(frames: 240),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      c.addSynthRack();
      c.clearSelection();
      var stage = await pump(tester, c);
      return (c, stage);
    }

    // The rack ticks while it shows: frames are pumped for a while rather
    // than until nothing moves.
    Future<void> Function() settle(WidgetTester tester) =>
        () => tester.pump(const Duration(milliseconds: 400));

    for (var cancel in [false, true]) {
      testWidgets("a key held, moved and ${how(cancel)}: it stops sounding",
          (tester) async {
        var (c, stage) = await rack(tester);
        var keys = of(c, SynthModuleKind.keys);
        var ch = c.synthChannel(of(c, SynthModuleKind.out))!;
        var white = synthPanelOf(SynthModuleKind.keys).keys!;
        var g = await tester.startGesture(stage
            .toStagePoint(on(keys, Offset(white.left + 3, white.bottom - 4))));
        await tester.pump();
        expect(c.heldKeys(ch.id), {60});
        await g.moveBy(const Offset(2, 0));
        await tester.pump();
        if (cancel) {
          await g.cancel();
        } else {
          await g.up();
        }
        await tester.pump(const Duration(milliseconds: 400));
        expect(c.heldKeys(ch.id), isEmpty);
        settled(stage, c, how(cancel));
      });

      testWidgets("a knob turned and ${how(cancel)}: one undo step",
          (tester) async {
        var (c, stage) = await rack(tester);
        var osc = of(c, SynthModuleKind.osc);
        var level = synthPanelOf(SynthModuleKind.osc).dials[2].center;
        await steps(
            tester, stage.toStagePoint(on(osc, level)), const Offset(0, 30),
            cancel: cancel, count: 6, settle: settle(tester));
        expect(of(c, SynthModuleKind.osc).value("level"), lessThan(0.8));
        expect(of(c, SynthModuleKind.osc).base.y, osc.base.y);
        settled(stage, c, how(cancel));
        c.undo();
        expect(of(c, SynthModuleKind.osc).value("level"), 0.8);
      });

      testWidgets("a digital screen dragged and ${how(cancel)}: one undo step",
          (tester) async {
        var (c, stage) = await rack(tester);
        c.lookAllSynths(SynthLook.digital);
        await tester.pump();
        var env = of(c, SynthModuleKind.env);
        var screen = synthPanelOf(SynthModuleKind.env).screen!;
        var was = env.value("a");
        await steps(
            tester,
            stage.toStagePoint(on(env, synthEnvPoints(env, screen).a)),
            const Offset(40, 0),
            cancel: cancel,
            settle: settle(tester));
        expect(of(c, SynthModuleKind.env).value("a"), greaterThan(was));
        expect(of(c, SynthModuleKind.env).base.x, env.base.x);
        settled(stage, c, how(cancel));
        c.undo();
        expect(of(c, SynthModuleKind.env).value("a"), was);
      });

      testWidgets(
          "a cable carried to a jack and ${how(cancel)}: "
          "${cancel ? "not plugged" : "plugged"}", (tester) async {
        var (c, stage) = await rack(tester);
        var env = of(c, SynthModuleKind.env), amp = of(c, SynthModuleKind.amp);
        var from = stage.toStagePoint(
            on(env, synthPanelOf(SynthModuleKind.env).outs["env"]!));
        var to = stage.toStagePoint(
            on(amp, synthPanelOf(SynthModuleKind.amp).ins["gain"]!));
        await steps(tester, from, to - from,
            cancel: cancel, count: 5, settle: settle(tester));
        expect(of(c, SynthModuleKind.amp).inputs["gain"],
            cancel ? isNull : (module: env.id, port: "env"));
        settled(stage, c, how(cancel));
      });
    }

    testWidgets("a cable lifted from its jack and cancelled stays plugged",
        (tester) async {
      var (c, stage) = await rack(tester);
      var osc = of(c, SynthModuleKind.osc);
      var plugged = osc.inputs["pitch"];
      expect(plugged, isNotNull);
      await steps(
          tester,
          stage.toStagePoint(
              on(osc, synthPanelOf(SynthModuleKind.osc).ins["pitch"]!)),
          const Offset(0, 120),
          cancel: true,
          count: 5,
          settle: settle(tester));
      expect(of(c, SynthModuleKind.osc).inputs["pitch"], plugged);
      settled(stage, c, "cancelled");
    });
  });

  group("a Code panel's controls", () {
    /// lesson is a Code lesson on a stage, nothing picked.
    Future<(CanvasController, CanvasStageState)> lesson(
        WidgetTester tester) async {
      var c = CanvasController(
          const CanvasDocument(frames: 2400, frameRate: 24),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      c.addCodeLesson(starter: codeStarters.firstWhere((s) => s.key == "web"));
      c.clearSelection();
      var stage = await pump(tester, c);
      return (c, stage);
    }

    CodeElement code(CanvasController c) =>
        c.document.elements.whereType<CodeElement>().single;

    for (var cancel in [false, true]) {
      testWidgets("its playbar scrubbed and ${how(cancel)}: the playhead moved",
          (tester) async {
        var (c, stage) = await lesson(tester);
        var e = code(c);
        var track =
            codePlaybar(e, codeBoxes(e, e.bounds).bar)[CodePlayPart.track]!;
        var from = stage.toStagePoint(
            Offset(track.left + track.width / 4, track.center.dy));
        var g = await tester.startGesture(from);
        await tester.pump();
        var pressed = c.frame;
        expect(pressed, greaterThan(0), reason: "pressed, the playhead goes");
        for (var i = 0; i < 4; i++) {
          await g.moveBy(Offset(track.width / 8, 0) *
              (stage.pageRect.width / c.document.size.width));
          await tester.pump();
        }
        if (cancel) {
          await g.cancel();
        } else {
          await g.up();
        }
        await tester.pumpAndSettle();
        expect(c.frame, greaterThan(pressed), reason: "and follows the drag");
        expect(code(c).x, e.x, reason: "the panel did not move");
        settled(stage, c, how(cancel));
      });

      testWidgets("a pane divider dragged and ${how(cancel)}: one undo step",
          (tester) async {
        var (c, stage) = await lesson(tester);
        var d = codeBoxes(code(c), code(c).bounds)
            .dividers
            .firstWhere((d) => !d.columns);
        await steps(
            tester, stage.toStagePoint(d.hit.center), const Offset(0, 120),
            cancel: cancel);
        var rows = code(c).rows;
        expect(rows[0] / (rows[0] + rows[1]), greaterThan(0.55));
        settled(stage, c, how(cancel));
        c.undo();
        expect(code(c).rows, [1, 1]);
      });

      testWidgets(
          "a tab carried to another pane and ${how(cancel)}: "
          "${cancel ? "left where it was" : "moved there"}", (tester) async {
        var (c, stage) = await lesson(tester);
        var b = codeBoxes(code(c), code(c).bounds);
        var before = [for (var p in code(c).panes) p.tabs];
        var from = stage.toStagePoint(b.panes[2].tabs.single.rect.center);
        var row = b.panes[1].tabRow;
        var to = stage.toStagePoint(Offset(row.right - 10, row.center.dy));
        await steps(tester, from, to - from, cancel: cancel, count: 8);
        var after = [for (var p in code(c).panes) p.tabs];
        if (cancel) {
          expect(after, before);
        } else {
          expect(after[2], isEmpty);
        }
        settled(stage, c, how(cancel));
      });
    }
  });

  group("the held marker's note on the page", () {
    for (var cancel in [false, true]) {
      testWidgets("dragged and ${how(cancel)}: moved, one undo step",
          (tester) async {
        var c = CanvasController(
            const CanvasDocument(frames: 40, actions: [
              TimelineAction(
                  frame: 3,
                  kind: TimelineActionKind.stop,
                  label: "Press to jump"),
            ]),
            audioEngine: FakeEngine({}));
        addTearDown(c.dispose);
        var stage = await pump(tester, c);
        c.play();
        for (var i = 0; i < 3; i++) {
          c.tickForTest();
        }
        await tester.pumpAndSettle();
        var note = c.holdingMarker!;
        var was = note.noteAt;
        var box = markerNoteLayout(c.document.size.size, note).box;

        await steps(
            tester, stage.toStagePoint(box.center), const Offset(60, -40),
            cancel: cancel);
        expect(c.holdingMarker!.noteAt, isNot(was), reason: "moved");
        settled(stage, c, how(cancel));
        c.undo();
        expect(c.holdingMarker!.noteAt, was);
      });
    }
  });

  group("a press on a Code run's live preview", () {
    for (var cancel in [false, true]) {
      testWidgets("moved and ${how(cancel)}: left to the preview",
          (tester) async {
        // The press lands before the preview is drawn over the page, so the
        // stage hears it: it is the preview's, and nothing on the page moves.
        CanvasController.codeRunHost = _FakeHost();
        var save = CanvasController.saveCodePicture;
        CanvasController.saveCodePicture =
            (png) async => "0123456789abcdef.png";
        addTearDown(() {
          CanvasController.codeRunHost = null;
          CanvasController.saveCodePicture = save;
        });
        var c = CanvasController(
            const CanvasDocument(frames: 2400, frameRate: 24),
            audioEngine: FakeEngine({}));
        addTearDown(c.dispose);
        c.addCodeLesson(
            starter: codeStarters.firstWhere((s) => s.key == "web"));
        c.clearSelection();
        var stage = await pump(tester, c);
        CodeRunElement run() =>
            c.document.elements.whereType<CodeRunElement>().single;
        var boxes = codeRunBoxes(run(), run().bounds, runner: CodeRunner.web);
        await tester.tapAt(stage.toStagePoint(boxes.runButton.center));
        await tester.pumpAndSettle();
        expect(c.codeLive, run().id, reason: "live once it has run");
        c.codeLiveSnap = null;
        await c.endLiveCode();
        await tester.pumpAndSettle();
        var x = run().x;
        // Not picked: a press the page took would pick the panel and move it.
        c.clearSelection();

        c.liveCode(run());
        var g = await tester
            .startGesture(stage.toStagePoint(boxes.preview!.center));
        await tester.pump();
        for (var i = 0; i < 4; i++) {
          await g.moveBy(const Offset(15, 0));
          await tester.pump();
        }
        if (cancel) {
          await g.cancel();
        } else {
          await g.up();
        }
        await tester.pumpAndSettle();
        expect(c.codeLive, run().id, reason: "still live");
        expect(run().x, x, reason: "the panel under it did not move");
        expect(c.selection, isEmpty, reason: "nor was it picked");
        settled(stage, c, how(cancel));
        c.codeLiveSnap = null;
        await c.endLiveCode();
      });
    }
  });

  group("a retouching stroke", () {
    /// seed puts a decoded picture into the store, which the brush needs.
    Future<void> seed(WidgetTester tester, CanvasController c) async {
      var pixels = Uint8List(64 * 64 * 4);
      for (var i = 0; i < 64 * 64; i++) {
        pixels.setRange(i * 4, i * 4 + 4, const [200, 200, 200, 255]);
      }
      await tester.runAsync(() async {
        var done = Completer<ui.Image>();
        ui.decodeImageFromPixels(
            pixels, 64, 64, ui.PixelFormat.rgba8888, done.complete);
        c.images.putForTest("abcdefghijklmnop", await done.future);
      });
    }

    for (var cancel in [false, true]) {
      testWidgets("drawn and ${how(cancel)}: held whole, the step closed",
          (tester) async {
        // A cancel ends the stroke as a release does: what was drawn is
        // held to be applied.
        var document = const CanvasDocument();
        var c = CanvasController(document.addElement(ImageElement(
          ElementBase(
              id: "i",
              x: 0,
              y: 0,
              width: document.size.width.toDouble(),
              height: document.size.height.toDouble()),
          assetId: "abcdefghijklmnop",
        )));
        addTearDown(c.dispose);
        c.selectOnly("i");
        c.retouch = RetouchBrush.erase;
        var stage = await pump(tester, c);
        await seed(tester, c);

        await steps(tester, stage.pageRect.center, const Offset(48, 0),
            cancel: cancel);
        expect(c.hasPendingStroke, isTrue);
        expect(c.pendingStroke!.length, greaterThan(3));
        settled(stage, c, how(cancel));
      });
    }
  });
}
