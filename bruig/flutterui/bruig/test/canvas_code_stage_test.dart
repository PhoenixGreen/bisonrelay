import 'package:flutter/gestures.dart';
import 'support/canvas_app.dart';
import 'dart:ui' as ui;
import 'package:bruig/plugin_system/canvas/model/pattern_counts.dart';
import 'package:bruig/plugin_system/canvas/export/epub_layers.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/presets/builtin_element_presets.dart';
import 'package:bruig/plugin_system/canvas/model/code_runners.dart';
import 'package:bruig/plugin_system/canvas/model/code_starters.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_lanes.dart'
    show motionRowsOf;
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart';
import 'package:bruig/plugin_system/canvas/model/code_timing.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_run_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_task_element.dart';
import 'package:bruig/plugin_system/canvas/render/code_task_painter.dart';
import 'package:bruig/plugin_system/canvas/render/code_painter.dart';
import 'package:bruig/plugin_system/canvas/render/code_run_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/code_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/code_live_preview.dart';
import 'package:bruig/plugin_system/canvas/ui/code_studio.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/elements_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/canvas_audio_fake.dart';

// canvas_code_stage_test.dart is the Code and Run panels on the stage, as
// the prototype Ken approved has them (2026-11-15): tabs shown, dragged
// along their row or onto another pane; the line between two panes
// dragged; a file in the list opened in the pane last pressed; a pane's
// code opened for typing with a second press; Run pressed. And the Add
// panel's Code chip, putting the two down from an example.

Widget _app(Widget child) => canvasApp(child);

/// _FakeHost runs nothing: it prints what it was given and makes a
/// picture, as a browser would.
class _FakeHost implements CodeRunHost {
  final List<(CodeRunner, String)> ran = [];
  final List<Size> sizes = [];
  @override
  Future<CodeRunOutcome> run(CodeRunner runner, CodeElement code,
      CodeFile entry, Size size, void Function(CodeLog) onLog) async {
    ran.add((runner, entry.name));
    sizes.add(size);
    onLog(const CodeLog("Page ready"));
    return const CodeRunOutcome(
        logs: [CodeLog("Page ready")], picture: [1, 2, 3]);
  }
}

/// _counter is a Flutter app counting presses of its + button, by [adds].
String _counter(String adds) => """
import 'package:flutter/material.dart';

void main() => runApp(const CounterApp());

class CounterApp extends StatefulWidget {
  const CounterApp({super.key});

  @override
  State<CounterApp> createState() => _CounterAppState();
}

class _CounterAppState extends State<CounterApp> {
  int coins = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(child: Text('\$coins')),
        floatingActionButton: FloatingActionButton(
          onPressed: () => setState(() => $adds),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}""";

void main() {
  late CanvasController c;
  late GlobalKey<CanvasStageState> key;

  Future<void> stage(WidgetTester tester, String starter) async {
    c = CanvasController(const CanvasDocument(frames: 2400, frameRate: 24),
        audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    c.addCodeLesson(starter: codeStarters.firstWhere((s) => s.key == starter));
    c.clearSelection();
    key = GlobalKey<CanvasStageState>();
    setTestScreen(tester, const Size(1600, 1000));
    await tester.pumpWidget(_app(SizedBox(
        width: 1600,
        height: 1000,
        child: CanvasStage(key: key, controller: c))));
    await tester.pumpAndSettle();
  }

  CodeElement code() => c.document.elements.whereType<CodeElement>().single;
  CodeRunElement run() =>
      c.document.elements.whereType<CodeRunElement>().single;
  Offset at(Offset doc) {
    var page = key.currentState!.pageRect;
    return page.topLeft + doc * (page.width / c.document.size.width);
  }

  // A received canvas carries its sender's last run: a picture, until Run
  // is pressed here. Opening it live would run the sender's code with
  // nobody having asked (security review, 2026-11-17).
  test("a run that came with the canvas is not opened live", () {
    var made = CanvasController(const CanvasDocument());
    addTearDown(made.dispose);
    made.addCodeLesson(starter: codeStarters.firstWhere((s) => s.key == "web"));
    var sent = made.document.elements.whereType<CodeRunElement>().single;
    made.replaceElement(sent.copyWith(
        result: CodeRunResult(
            runner: "Web", at: DateTime.utc(2026), logs: const [])));
    var received = CanvasController(made.document);
    addTearDown(received.dispose);
    var r = received.document.elements.whereType<CodeRunElement>().single;
    received.liveCode(r);
    expect(received.codeLive, isNull);
  });

  testWidgets(
      "the Code chip puts down an empty project and its Run panel; the "
      "examples are its presets", (tester) async {
    var ctl = CanvasController(const CanvasDocument());
    addTearDown(ctl.dispose);
    setTestScreen(tester, const Size(600, 1400));
    await tester.pumpWidget(_app(
        SizedBox(width: 400, child: CanvasElementsPanel(controller: ctl))));
    await tester.tap(find.byKey(const ValueKey("addCode")));
    await tester.pumpAndSettle();
    var codeEl = ctl.document.elements.whereType<CodeElement>().single;
    var runEl = ctl.document.elements.whereType<CodeRunElement>().single;
    expect(codeEl.project, CodeKind.web);
    expect(codeEl.files.map((f) => (f.name, f.text)),
        [("index.html", ""), ("style.css", ""), ("app.js", "")]);
    expect(codeEl.typing.on, isFalse, reason: "nothing to type in");
    expect(runEl.code, codeEl.id);
    expect(runEl.x, greaterThan(codeEl.bounds.right), reason: "beside it");
    expect(ctl.selection, {codeEl.id});
    // The examples, as presets of a Code panel.
    var names = [
      for (var p in builtinElementPresets)
        if (p.kind == ElementKind.code) p.name
    ];
    expect(names, hasLength(5));
    expect(names.first, startsWith("Web page"));
  });

  testWidgets("a tab carried onto another pane moves there; pressed, shown",
      (tester) async {
    await stage(tester, "web");
    var b = codeBoxes(code(), code().bounds);
    var from = at(b.panes[2].tabs.single.rect.center);
    var row = b.panes[1].tabRow;
    var to = at(Offset(row.right - 10, row.center.dy));
    var g = await tester.startGesture(from);
    await tester.pump();
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 8)!);
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(code().panes[1].tabs, ["f2", "f3"]);
    expect(code().panes[2].tabs, isEmpty);
    expect(c.selection, {code().id});

    // Pressed, style.css is shown in its pane, by hand.
    var tab = codeBoxes(code(), code().bounds).panes[1].tabs.first;
    await tester.tapAt(at(tab.rect.center));
    await tester.pumpAndSettle();
    expect(c.codeShowFor(code()).picked[1], "f2");
    // Its cross closes it.
    tab = codeBoxes(code(), code().bounds).panes[1].tabs.first;
    await tester.tapAt(at(tab.close.center));
    await tester.pumpAndSettle();
    expect(code().panes[1].tabs, ["f3"]);
    // A file in the list opens in the pane last pressed.
    var file = codeBoxes(code(), code().bounds)
        .fileRows
        .firstWhere((r) => r.$1 == "f2")
        .$2;
    await tester.tapAt(at(file.center));
    await tester.pumpAndSettle();
    expect(code().panes[1].tabs, ["f3", "f2"]);
  });

  testWidgets("the line between two panes, dragged, resizes them",
      (tester) async {
    await stage(tester, "web");
    var d =
        codeBoxes(code(), code().bounds).dividers.firstWhere((d) => !d.columns);
    await tester.dragFrom(at(d.hit.center), const Offset(0, 120));
    await tester.pumpAndSettle();
    var rows = code().rows;
    expect(rows[0] / (rows[0] + rows[1]), greaterThan(0.55));
    // One change to undo.
    c.undo();
    expect(code().rows, [1, 1]);
  });

  testWidgets("one click on a panel's code opens it for typing",
      (tester) async {
    await stage(tester, "web");
    var pane = codeBoxes(code(), code().bounds).panes[0].code;
    // Dragged from its code, the panel moves and nothing opens.
    var x = code().x;
    await tester.timedDragFrom(at(pane.center), const Offset(60, 0),
        const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(code().x, greaterThan(x + 10));
    expect(find.byType(CodePaneEditor), findsNothing);
    // Clicked, it opens (Ken: two clicks "doesn't feel like a very good
    // user experience").
    pane = codeBoxes(code(), code().bounds).panes[0].code;
    await tester.tapAt(at(pane.center));
    await tester.pumpAndSettle();
    expect(find.byType(CodePaneEditor), findsOneWidget);
    expect(c.codeEditing, (code().id, 0));
    // Typed into, the file changes; Escape shuts it, one change to undo.
    var field = find.byKey(ValueKey("codeEditor-${code().id}-f1"));
    await tester.enterText(field, "<p>Hi</p>");
    await tester.pump();
    expect(code().file("f1")!.text, "<p>Hi</p>");
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CodePaneEditor), findsNothing);
    c.undo();
    expect(code().file("f1")!.text, startsWith("<!doctype html>"));
  });

  testWidgets(
      "a Flutter app is laid out the same in its run's picture and live, at "
      "any zoom and text size", (tester) async {
    var host = _FakeHost();
    CanvasController.codeRunHost = host;
    var save = CanvasController.saveCodePicture;
    CanvasController.saveCodePicture = (png) async => "0123456789abcdef.png";
    addTearDown(() {
      CanvasController.codeRunHost = null;
      CanvasController.saveCodePicture = save;
    });
    // Ken runs a larger text size: the live app grew when pressed.
    setTestTextScale(tester, 1.4);
    await stage(tester, "flutter");
    c.replaceElement(run().copyWith(appWidth: 360));
    var boxes = codeRunBoxes(run(), run().bounds, runner: CodeRunner.flutter);
    await tester.tapAt(at(boxes.runButton.center));
    await tester.pumpAndSettle();
    var preview = boxes.preview!;
    var want = Size(360, preview.height * 360 / preview.width);
    expect(host.sizes.single.width, closeTo(want.width, 1e-6));
    expect(host.sizes.single.height, closeTo(want.height, 1e-6));
    for (var zoom in [0.5, 1.5]) {
      c.zoom = zoom;
      await tester.pumpAndSettle();
      c.selectOnly(run().id);
      c.liveCode(run());
      await tester.pumpAndSettle();
      var live = tester.widget<CodeLivePreview>(find.byType(CodeLivePreview));
      expect(live.appSize.width, closeTo(want.width, 1e-6), reason: "$zoom");
      expect(live.appSize.height, closeTo(want.height, 1e-6));
      var media = tester.widget<MediaQuery>(find
          .descendant(
              of: find.byType(CodeLivePreview),
              matching: find.byType(MediaQuery))
          .first);
      expect(media.data.textScaler, TextScaler.noScaling);
      // Shut without its picture: taking one needs the real clock.
      c.codeLiveSnap = null;
      await c.endLiveCode();
      await tester.pumpAndSettle();
    }
    // Fitting the panel: its width on the page, at least a phone's.
    c.replaceElement(run().copyWith(appWidth: 0));
    expect(run().appSize(preview.size).width,
        closeTo(preview.width < 360 ? 360 : preview.width, 1e-6));
    expect(
        CodeRunElement.fromJson({"appWidth": 768.0}, const ElementBase(id: "r"))
            .appWidth,
        768);
  });

  testWidgets(
      "Reset, on the bar once the code is typed into, puts it back as it "
      "began", (tester) async {
    await stage(tester, "web");
    var began = code().file("f1")!.text;
    expect(code().start, isNull);
    expect(codePlaybar(code(), codeBoxes(code(), code().bounds).bar),
        isNot(contains(CodePlayPart.reset)),
        reason: "nothing to reset yet");
    var pane = codeBoxes(code(), code().bounds).panes[0].code;
    await tester.tapAt(at(pane.center));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(ValueKey("codeEditor-${code().id}-f1")), "<p>Oops</p>");
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(code().start!.firstWhere((f) => f.id == "f1").text, began);
    expect(code().changedFromStart, isTrue);
    // Kept in the canvas, so a student's copy can go back too.
    var saved = CodeElement.fromJson(code().props(), code().base);
    expect(saved.start!.firstWhere((f) => f.id == "f1").text, began);
    var reset = codePlaybar(
        code(), codeBoxes(code(), code().bounds).bar)[CodePlayPart.reset]!;
    await tester.tapAt(at(reset.center));
    await tester.pumpAndSettle();
    expect(code().file("f1")!.text, began);
    expect(code().changedFromStart, isFalse);
    expect(codePlaybar(code(), codeBoxes(code(), code().bounds).bar),
        isNot(contains(CodePlayPart.reset)));
    // One change: Undo brings the student's code back.
    c.undo();
    expect(code().file("f1")!.text, "<p>Oops</p>");
    // Kept as the start, Reset has nothing to do.
    c.keepCodeAsStart(code());
    expect(code().changedFromStart, isFalse);
    expect(code().reset.file("f1")!.text, "<p>Oops</p>");
  });

  testWidgets(
      "Run pressed: the app live at once, so the next press is its own; "
      "a press that opens it presses it too", (tester) async {
    var host = _FakeHost();
    CanvasController.codeRunHost = host;
    var save = CanvasController.saveCodePicture;
    CanvasController.saveCodePicture = (png) async => "0123456789abcdef.png";
    addTearDown(() {
      CanvasController.codeRunHost = null;
      CanvasController.saveCodePicture = save;
    });
    await stage(tester, "flutter");
    c.replaceElement(
        code().withFileText(code().files.first.id, _counter("coins++")));
    var boxes = codeRunBoxes(run(), run().bounds, runner: CodeRunner.flutter);
    await tester.tapAt(at(boxes.runButton.center));
    await tester.pumpAndSettle();
    expect(find.byType(CodeLivePreview), findsOneWidget,
        reason: "live once it has run");
    // Shut untouched: as its run left it, nothing to undo.
    var before = c.document;
    await c.endLiveCode();
    await tester.pumpAndSettle();
    expect(identical(c.document, before), isTrue);
    // Pressed on its + (the panel picked): opened live, and pressed.
    c.liveCode(run());
    await tester.pumpAndSettle();
    var plus = tester.getCenter(find.byType(FloatingActionButton));
    await c.endLiveCode();
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.tapAt(plus);
    await tester.pumpAndSettle();
    expect(find.byType(CodeLivePreview), findsOneWidget);
    expect(find.text("1"), findsOneWidget,
        reason: "the press that opened it counted (Ken: it took two)");
    // Pressed again: its own.
    await tester.tapAt(plus);
    await tester.pumpAndSettle();
    expect(find.text("2"), findsOneWidget);
    c.codeLiveSnap = null;
    await c.endLiveCode();
  });

  testWidgets("Run pressed: run by the host, its output and picture kept",
      (tester) async {
    var host = _FakeHost();
    CanvasController.codeRunHost = host;
    var save = CanvasController.saveCodePicture;
    CanvasController.saveCodePicture = (png) async => "0123456789abcdef.png";
    addTearDown(() {
      CanvasController.codeRunHost = null;
      CanvasController.saveCodePicture = save;
    });
    await stage(tester, "web");
    var button =
        codeRunBoxes(run(), run().bounds, runner: CodeRunner.web).runButton;
    await tester.tapAt(at(button.center));
    await tester.pumpAndSettle();
    expect(host.ran, [(CodeRunner.web, "index.html")]);
    expect(run().result!.logs.single.text, "Page ready");
    expect(run().result!.preview, "0123456789abcdef.png");
    expect(run().result!.runner, "Browser");
    expect(c.codeRunning(run().id), isFalse);
    // Run by hand before the typing ends: shown now, not "Runs when the
    // typing ends" (Ken, 2026-11-15) -- until the playhead moves.
    expect(c.frame, 0);
    expect(c.codeRunShowFor(run()).now, isTrue);
    c.frame = 5;
    expect(c.codeRunShowFor(run()).now, isFalse);
    // Its Code panel showing the whole of its code: shown now too.
    c.toggleCodeFull(code());
    expect(c.codeRunShowFor(run()).now, isTrue);
  });

  test("in a book: the code its own layer, the page run live over its picture",
      () async {
    var c = CanvasController(const CanvasDocument(frames: 2400, frameRate: 24));
    addTearDown(c.dispose);
    c.addCodeLesson(starter: codeStarters.first);
    var code = c.document.elements.whereType<CodeElement>().single;
    var run = c.document.elements.whereType<CodeRunElement>().single;
    c.replaceElement(run.copyWith(
        result: CodeRunResult(runner: "Browser", at: DateTime.utc(2026))));
    var built = (await buildEpubStage(c.document, 0,
        pixels: 1, width: 1280, height: 720))!;
    var runLayer = built.stage.layers.firstWhere((l) => l.id == run.id);
    expect(runLayer.frames, hasLength(1));
    expect(runLayer.frames.single.html, contains("#count {"),
        reason: "its stylesheet in it");
    expect(runLayer.frames.single.html, isNot(contains("flutter_inappwebview")),
        reason: "no app-only console catcher in a book");
    // The code: a frame over each pane, its file whole, to be scrolled.
    var codeLayer = built.stage.layers.firstWhere((l) => l.id == code.id);
    expect(codeLayer.frames, hasLength(3));
    var page = codeLayer.frames.first.html;
    expect(page, contains("overflow:auto"));
    expect(page, contains("&lt;/html&gt;"), reason: "the whole of index.html");
    expect(page, contains("The page pulls in style.css"),
        reason: "its lit steps' notes");
  });

  test("a project begun again as another kind: its files, empty", () {
    var e = const CodeElement(ElementBase(id: "c", width: 900, height: 600))
        .startedAs(CodeKind.web);
    expect(e.layout, CodeLayout.oneOverTwo);
    expect(e.panes.map((p) => p.tabs.length), [1, 1, 1]);
    var py = e.startedAs(CodeKind.python);
    expect(py.files.map((f) => f.name), ["main.py"]);
    expect(py.layout, CodeLayout.one);
    var flutter = e.startedAs(CodeKind.flutter);
    // An empty Flutter project's Dart is still an app to draw.
    expect(
        runnerOf(
            CodeRunElement(const ElementBase(id: "r"), code: "c"), flutter),
        CodeRunner.flutter);
    // Kept, and read back from files alone for one saved before kinds.
    var back = CodeElement.fromJson(
        {...py.props(), "projectKind": null}, const ElementBase(id: "c"));
    expect(back.project, CodeKind.python);
  });

  group("the Code Studio", () {
    late _FakeHost host;
    late Future<String?> Function(List<int>) save;
    setUp(() {
      host = _FakeHost();
      CanvasController.codeRunHost = host;
      save = CanvasController.saveCodePicture;
      CanvasController.saveCodePicture = (png) async => "0123456789abcdef.png";
    });
    tearDown(() {
      CanvasController.codeRunHost = null;
      CanvasController.saveCodePicture = save;
    });

    Future<void> studio(WidgetTester tester, String starter) async {
      c = CanvasController(const CanvasDocument(frames: 2400, frameRate: 24),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      c.addCodeLesson(
          starter: codeStarters.firstWhere((s) => s.key == starter));
      c.openCodeStudio(code().id);
      setTestScreen(tester, const Size(1600, 1000));
      await tester.pumpWidget(_app(CodeStudio(
          controller: c, codeId: code().id, onDone: c.closeCodeStudio)));
      await tester.pumpAndSettle();
    }

    testWidgets(
        "Run, then Restart with the code as it is now, and Stop "
        "(Ken: no way to test new code while the old ran)", (tester) async {
      await studio(tester, "flutter");
      var f = code().files.first.id;
      c.replaceElement(code().withFileText(f, _counter("coins++")));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("codeStudioStop")), findsNothing);
      await tester.tap(find.byKey(const ValueKey("codeStudioRun")));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text("1"), findsOneWidget);
      // Changed and run again: the new code, its count from nothing.
      c.replaceElement(code().withFileText(f, _counter("coins += 5")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("codeStudioRun")));
      await tester.pumpAndSettle();
      expect(find.text("0"), findsOneWidget);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text("5"), findsOneWidget);
      // Stopped: the app gone, Run to start it again.
      await tester.tap(find.byKey(const ValueKey("codeStudioStop")));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byKey(const ValueKey("codeStudioStop")), findsNothing);
    });

    testWidgets("typed in: the panel's file, one change to undo",
        (tester) async {
      await studio(tester, "python");
      var field = find.byKey(ValueKey("codeEditor-${code().id}-f1"));
      expect(field, findsOneWidget);
      await tester.enterText(field, "def f():\n    return 1");
      await tester.pump();
      await tester.enterText(field, "def f():\n    return 2");
      await tester.pump();
      expect(code().file("f1")!.text, "def f():\n    return 2");
      await tester.tap(find.byKey(const ValueKey("codeStudioDone")));
      await tester.pumpAndSettle();
      expect(c.codeStudio.value, isNull);
      c.undo();
      expect(code().file("f1")!.text, startsWith("def count_words"));
    });

    testWidgets("a file picked opens in the pane last used; Run runs it",
        (tester) async {
      await studio(tester, "python");
      // main.py into the left pane, beside words.py.
      await tester.tap(find.byKey(const ValueKey("codeStudioFile-f2")));
      await tester.pumpAndSettle();
      expect(code().panes[0].tabs, ["f1", "f2"]);
      expect(code().panes[0].active, "f2");
      await tester.tap(find.byKey(const ValueKey("codeStudioRun")));
      await tester.pumpAndSettle();
      expect(host.ran, [(CodeRunner.python, "main.py")]);
      // Kept by its Run panel, and shown here.
      expect(run().result!.logs.single.text, "Page ready");
      expect(
          find.descendant(
              of: find.byKey(const ValueKey("codeStudioOutput")),
              matching: find.text("Page ready")),
          findsOneWidget);
    });

    testWidgets("a tab dragged onto another pane moves there", (tester) async {
      await studio(tester, "python");
      var from =
          tester.getCenter(find.byKey(const ValueKey("codeStudioTab-1-f2")));
      // Past words.py, on the rest of its row: after it.
      var row =
          tester.getTopRight(find.byKey(const ValueKey("codeStudioTab-0-f1")));
      var to = row + const Offset(80, 17);
      var g = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 1; i <= 10; i++) {
        await g.moveTo(Offset.lerp(from, to, i / 10)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(code().panes[0].tabs, ["f1", "f2"]);
      expect(code().panes[1].tabs, isEmpty);
      // Dropped on words.py: before it.
      var back =
          tester.getCenter(find.byKey(const ValueKey("codeStudioTab-0-f2")));
      var onto =
          tester.getCenter(find.byKey(const ValueKey("codeStudioTab-0-f1")));
      g = await tester.startGesture(back);
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 1; i <= 10; i++) {
        await g.moveTo(Offset.lerp(back, onto, i / 10)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(code().panes[0].tabs, ["f2", "f1"]);
    });
  });

  group("a Code task card", () {
    testWidgets(
        "a check set in its settings: The code changes, Before and After, "
        "and how many times", (tester) async {
      // At Ken's larger text size: the file and the count share a row.
      setTestTextScale(tester, 1.25);
      await stage(tester, "flutter");
      c.addCodeTask(code());
      var card = c.document.elements.whereType<CodeTaskElement>().single;
      c.selectOnly(card.id);
      CodeTaskElement task() =>
          c.document.elements.whereType<CodeTaskElement>().single;
      await tester.pumpWidget(_app(ListenableBuilder(
        listenable: c,
        builder: (context, _) => SingleChildScrollView(
          child: SizedBox(
            width: 340,
            child: CanvasControlScope(
              maxWidth: 300,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: elementSettings(context, c, c.selected!)),
            ),
          ),
        ),
      )));
      await tester.pumpAndSettle();
      var k = task().checks.length;
      await tester
          .ensureVisible(find.byKey(const ValueKey("codeTaskAddCheck")));
      await tester.tap(find.byKey(const ValueKey("codeTaskAddCheck")));
      await tester.pumpAndSettle();
      expect(task().checks.length, k + 1);
      // No Before until it is a change; a count for "has".
      expect(find.byKey(ValueKey("codeCheckBefore-$k")), findsNothing);
      expect(find.byKey(ValueKey("codeCheckCount-$k")), findsOneWidget);
      tester
          .widget<CanvasDropdown<CodeCheckKind>>(
              find.byKey(ValueKey("codeCheckKind-$k")))
          .onChanged(CodeCheckKind.changes);
      await tester.pumpAndSettle();
      Future<void> type(String key, String text) async {
        var field = find.descendant(
            of: find.byKey(ValueKey(key)), matching: find.byType(TextField));
        await tester.ensureVisible(field);
        await tester.enterText(field, text);
        await tester.pump();
      }

      await type("codeCheckBefore-$k", "coins++");
      await type("codeCheckText-$k", "coins += 2\ncoins = coins + 2");
      var check = task().checks[k];
      expect(check.kind, CodeCheckKind.changes);
      expect(check.before, "coins++");
      expect(check.answers, ["coins += 2", "coins = coins + 2"]);
      expect(find.byKey(ValueKey("codeCheckCount-$k")), findsNothing,
          reason: "a count is for The code has");
    });

    test(
        "checks without patterns: answers one a line, whole words, how "
        "many times, and a change from Before to After", () {
      CodeElement saying(String t) => const CodeElement(ElementBase(id: "c"))
          .startedAs(CodeKind.flutter)
          .withFileText("f1", t);
      // Ken: "Pattern: coins\s*(\+=\s*2|...)" is "not easy to remember".
      const adds = CodeCheck(CodeCheckKind.changes, "It adds two",
          before: "coins++", text: "coins += 2\ncoins = coins + 2");
      expect(adds.metBy(saying("setState(() => coins++);"), null), isFalse);
      expect(adds.metBy(saying("setState(() => coins+=2);"), null), isTrue,
          reason: "spaces don't matter");
      expect(adds.metBy(saying("coins = coins + 2;"), null), isTrue,
          reason: "either answer");
      expect(adds.metBy(saying("coins += 2; coins++;"), null), isFalse,
          reason: "Before still there");
      // Whole words: 48 is not in 480.
      const size = CodeCheck(CodeCheckKind.has, "48", text: "fontSize: 48");
      expect(size.metBy(saying("fontSize: 480"), null), isFalse);
      expect(size.metBy(saying("fontSize:48)"), null), isTrue);
      // How many times.
      const stars = CodeCheck(CodeCheckKind.has, "three stars",
          text: "Icon(Icons.star)", count: 3);
      var two = "Icon(Icons.star), Icon( Icons.star )";
      expect(stars.metBy(saying(two), null), isFalse);
      expect(stars.metBy(saying("$two, Icon(Icons.star)"), null), isTrue);
      expect(stars.metBy(saying("$two, Icon(Icons.starHalf)"), null), isFalse,
          reason: "a whole word");
      // Kept.
      var back = CodeCheck.fromJson(adds.toJson())!;
      expect((back.kind, back.before, back.text),
          (adds.kind, adds.before, adds.text));
      expect(CodeCheck.fromJson(stars.toJson())!.count, 3);
    });

    test("its checks: words found loosely, patterns, files, what was printed",
        () async {
      var c = starter0("flutter");
      const has = CodeCheck(CodeCheckKind.has, "Size 72",
          text: "TextStyle(fontSize:72)");
      expect(has.metBy(c, null), isTrue, reason: "spaces don't matter");
      expect(
          const CodeCheck(CodeCheckKind.lacks, "No 72", text: "fontSize: 72")
              .metBy(c, null),
          isFalse);
      const coins = CodeCheck(CodeCheckKind.has, "a coin count",
          text: r"int\s+coins\s*=\s*\d+", pattern: true);
      expect(coins.metBy(c, null), isNull, reason: "being counted");
      await PatternCounts.settled();
      expect(coins.metBy(c, null), isTrue);
      expect(
          const CodeCheck(CodeCheckKind.has, "not there",
                  file: "other.dart", text: "coins")
              .metBy(c, null),
          isFalse,
          reason: "only in the file named");
      var run = CodeRunElement(const ElementBase(id: "r"),
          result: CodeRunResult(
              runner: "",
              at: DateTime.utc(2026),
              logs: const [CodeLog("Hi Ken")]));
      expect(
          const CodeCheck(CodeCheckKind.prints, "says hi", text: "Hi")
              .metBy(c, run),
          isTrue);
      expect(
          const CodeCheck(CodeCheckKind.builds, "builds").metBy(c, run), isNull,
          reason: "known only by checking");
    });

    // A pattern comes with the canvas, and so does the code it is tried
    // on: one that never finishes must not freeze the app as the card is
    // drawn (security review, 2026-11-17).
    test("a pattern that never finishes is given up on, off the UI isolate",
        () async {
      var c = CodeElement(const ElementBase(id: "x"),
          files: [CodeFile(id: "f", name: "main.dart", text: "${"a" * 60}!")]);
      const evil =
          CodeCheck(CodeCheckKind.has, "evil", text: r"(a+)+$", pattern: true);
      var w = Stopwatch()..start();
      expect(evil.metBy(c, null), isNull);
      expect(w.elapsedMilliseconds, lessThan(200), reason: "not counted here");
      await PatternCounts.settled();
      expect(evil.metBy(c, null), isFalse, reason: "ran over: counts nothing");
      expect(w.elapsed, lessThan(PatternCounts.limit * 3));
    });

    testWidgets(
        "Check pressed: built, ticked, and passed -- until the code changes",
        (tester) async {
      await stage(tester, "flutter");
      c.addCodeTask(code());
      var card = c.document.elements.whereType<CodeTaskElement>().single;
      c.setCodeTask(card.copyWith(checks: const [
        CodeCheck(CodeCheckKind.has, "Count by two", text: "coins += 2"),
        CodeCheck(CodeCheckKind.builds, "It builds and runs"),
      ], passed: "Passed! On to Lesson 9."));
      card = c.document.elements.whereType<CodeTaskElement>().single;
      expect(card.height, closeTo(codeTaskFitHeight(card, card.width), 0.01));
      await tester.pumpAndSettle();
      await tester.tapAt(at(codeTaskLayout(card, card.width)
          .button
          .shift(card.bounds.topLeft)
          .center));
      await tester.pumpAndSettle();
      var show = c.codeTaskShowFor(card);
      expect(show.checked, isTrue);
      expect(show.built, isTrue);
      expect(codeTaskResult(card, c.document, show)!.$2, isFalse,
          reason: "it still counts by one");
      // Changed to count by two: checked again, it passes.
      c.replaceElement(code().withFileText(
          "f1", code().file("f1")!.text.replaceFirst("coins++", "coins += 2")));
      expect(c.codeTaskShowFor(card).checked, isFalse,
          reason: "a check holds only for the code it was made against");
      await c.checkCodeTask(card);
      expect(codeTaskResult(card, c.document, c.codeTaskShowFor(card)),
          ("Passed! On to Lesson 9.", true));
    });
  });

  group("playing a lesson", () {
    test("its span, moved together, and typed faster or slower", () {
      var e = starter0("web");
      var span = lessonSpan(e)!;
      expect(span.$1, e.typing.start);
      expect(span.$2, closeTo(e.steps.last.at + e.steps.last.length, 1e-9));
      var later = lessonMoved(e, 2);
      expect(later.typing.start, e.typing.start + 2);
      expect(later.steps.first.at, closeTo(e.steps.first.at + 2, 1e-9));
      expect(lessonMoved(e, -99).typing.start, 0,
          reason: "never before the scene starts");
      // Typed in by half the time: twice as fast, the lit lines after it.
      var end = codePlan(e).end;
      var half = e.typing.start + (end - e.typing.start) / 2;
      var quick = lessonTypedBy(e, half);
      expect(codePlan(quick).end, closeTo(half, 0.05));
      expect(quick.steps.first.at - codePlan(quick).end,
          closeTo(e.steps.first.at - end, 0.05),
          reason: "lit as long after the typing as before");
    });

    testWidgets(
        "the playbar: play to the lesson's end, back, and along its track",
        (tester) async {
      await stage(tester, "web");
      var e = code();
      var bar = codePlaybar(e, codeBoxes(e, e.bounds).bar);
      // Every part but Reset, which waits for the code to change.
      expect(
          bar.keys, CodePlayPart.values.where((p) => p != CodePlayPart.reset));
      c.frame = 100;
      await tester.tapAt(at(bar[CodePlayPart.restart]!.center));
      await tester.pump();
      expect(c.frame, 0);
      // Along its track: the playhead where it was pressed.
      var track = bar[CodePlayPart.track]!;
      await tester
          .tapAt(at(Offset(track.left + track.width / 2, track.center.dy)));
      await tester.pump();
      expect(c.frame / 24, closeTo(lessonSpan(e)!.$2 / 2, 0.1));
      // Off in Look: none.
      expect(
          codePlaybar(e.copyWith(playbar: false), codeBoxes(e, e.bounds).bar),
          isEmpty);
      // Played: to its end, from the start if it was there already.
      c.frame = c.document.frames - 1;
      c.playCode(e);
      expect(c.playing, isTrue);
      expect(c.frame, 0);
      c.pause();
    });

    testWidgets(
        "on the timeline: its lesson a bar in its row, moved and stretched",
        (tester) async {
      // A scene the lesson's length: shown whole.
      var ctl = CanvasController(
          const CanvasDocument(frames: 24, frameRate: 24),
          audioEngine: FakeEngine({}));
      addTearDown(ctl.dispose);
      ctl.addCodeLesson(starter: codeStarters.first);
      ctl.clearSelection();
      var e = ctl.document.elements.whereType<CodeElement>().single;
      expect(motionRowsOf(ctl).map((r) => r.id), contains(e.id),
          reason: "a row of its own, picked or not");
      setTestScreen(tester, const Size(1400, 800));
      await tester.pumpWidget(_app(Align(
          alignment: Alignment.bottomCenter,
          child: CanvasTimeline(controller: ctl, height: 400))));
      await tester.pumpAndSettle();
      var box =
          tester.getRect(find.byKey(ValueKey("motionLanesPaint-${e.id}")));
      double xOf(double s) =>
          box.left + box.width * s * 24 / ctl.document.frames;
      var span = lessonSpan(e)!;
      var y = box.center.dy;
      // The bar, dragged two seconds on: typing and lit lines together.
      var from = Offset(xOf((span.$1 + codePlan(e).end) / 2), y);
      await tester.timedDragFrom(
          from, Offset(xOf(2) - xOf(0), 0), const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      var moved = ctl.document.elementById(e.id) as CodeElement;
      expect(moved.typing.start, closeTo(e.typing.start + 2, 0.3));
      expect(moved.steps.first.at - moved.typing.start,
          closeTo(e.steps.first.at - e.typing.start, 0.01));
      // Its typing's end, dragged in: typed faster.
      var end = codePlan(moved).end;
      await tester.timedDragFrom(Offset(xOf(end), y),
          Offset(xOf(0) - xOf(4), 0), const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      var quick = ctl.document.elementById(e.id) as CodeElement;
      expect(quick.typing.speed, greaterThan(moved.typing.speed));
      expect(codePlan(quick).end, lessThan(end - 3));
    });
  });

  group("reading the code", () {
    testWidgets(
        "over a pane, the wheel and two fingers scroll it, not the page",
        (tester) async {
      await stage(tester, "flutter");
      var e = code();
      var pane = codeBoxes(e, e.bounds).panes[0].code;
      var p = at(pane.center);
      var pan = c.pan;
      var mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: p);
      await mouse.moveTo(p);
      await tester.pump();
      // Only the stage drawn again for it, not the editor round it: a
      // trackpad sends many a second (Ken: seconds behind the fingers).
      var told = 0, ticks = c.keysHeld.value;
      void count() => told++;
      c.addListener(count);
      tester.binding.handlePointerEvent(
          PointerScrollEvent(position: p, scrollDelta: const Offset(0, 120)));
      await tester.pump();
      c.removeListener(count);
      expect(told, 0, reason: "nothing round the stage rebuilt");
      expect(c.keysHeld.value, greaterThan(ticks), reason: "the stage redrawn");
      var scrolled = c.codeShowFor(code()).scroll[0];
      expect(scrolled, greaterThan(0), reason: "the pane scrolled down");
      expect(c.pan, pan, reason: "the page did not move");
      // Two fingers up: back towards the top.
      var pad = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      await pad.panZoomStart(p);
      await pad.panZoomUpdate(p, pan: const Offset(0, 40));
      await pad.panZoomEnd();
      await tester.pump();
      expect(c.codeShowFor(code()).scroll[0], lessThan(scrolled!));
      // No further than its last line.
      for (var i = 0; i < 20; i++) {
        tester.binding.handlePointerEvent(
            PointerScrollEvent(position: p, scrollDelta: const Offset(0, 400)));
      }
      await tester.pump();
      expect(c.codeShowFor(code()).scroll[0],
          closeTo(codeScrollRoom(code(), 0, "f1"), 1e-6));
      // Played, it goes back to the scene's own.
      c.frame = 10;
      expect(c.codeShowFor(code()).scroll, isEmpty);
      await mouse.removePointer();
    });

    testWidgets("open for typing, the wheel and two fingers scroll the editor",
        (tester) async {
      // At Ken's larger text size the field outgrew the scroll view and
      // scrolled inside it: the top couldn't be reached.
      setTestTextScale(tester, 1.4);
      await stage(tester, "flutter");
      var e = code();
      var pane = codeBoxes(e, e.bounds).panes[0].code;
      var p = at(pane.center);
      await tester.tapAt(p);
      await tester.pumpAndSettle();
      expect(find.byType(CodePaneEditor), findsOneWidget);
      ScrollPosition down() => tester
          .stateList<ScrollableState>(find.descendant(
              of: find.byType(CodePaneEditor),
              matching: find.byType(Scrollable)))
          .firstWhere((s) => s.widget.axisDirection == AxisDirection.down)
          .position;
      var mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: p);
      await mouse.moveTo(p);
      await tester.pump();
      for (var i = 0; i < 30; i++) {
        tester.binding.handlePointerEvent(
            PointerScrollEvent(position: p, scrollDelta: const Offset(0, 200)));
        await tester.pump();
      }
      expect(down().pixels, closeTo(down().maxScrollExtent, 1));
      for (var i = 0; i < 30; i++) {
        tester.binding.handlePointerEvent(PointerScrollEvent(
            position: p, scrollDelta: const Offset(0, -200)));
        await tester.pump();
      }
      expect(down().pixels, 0, reason: "the wheel goes back to the top");
      var pad = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      await pad.panZoomStart(p);
      for (var i = 0; i < 10; i++) {
        await pad.panZoomUpdate(p, pan: Offset(0, -60.0 * (i + 1)));
        await tester.pump();
      }
      await pad.panZoomEnd();
      await tester.pumpAndSettle();
      var low = down().pixels;
      expect(low, greaterThan(0));
      await pad.panZoomStart(p);
      for (var i = 0; i < 20; i++) {
        await pad.panZoomUpdate(p, pan: Offset(0, 60.0 * (i + 1)));
        await tester.pump();
      }
      await pad.panZoomEnd();
      await tester.pumpAndSettle();
      expect(down().pixels, 0, reason: "two fingers go back to the top");
      await mouse.removePointer();
    });

    testWidgets("Full code: the whole of it, and every lit step, by no clock",
        (tester) async {
      await stage(tester, "web");
      var e = code();
      c.frame = 0;
      var full = codePlaybar(e, codeBoxes(e, e.bounds).bar)[CodePlayPart.full]!;
      // Drawn again at once, by the stage alone (Ken: the full code came
      // late, when the playhead next moved).
      var told = 0, ticks = c.keysHeld.value;
      void count() => told++;
      c.addListener(count);
      await tester.tapAt(at(full.center));
      await tester.pump();
      c.removeListener(count);
      expect(told, 0, reason: "nothing round the stage rebuilt");
      expect(c.keysHeld.value, greaterThan(ticks), reason: "the stage redrawn");
      expect(c.codeFull(e.id), isTrue);
      expect(c.codeShowFor(e).full, isTrue);
      // Drawn so: everything typed though the scene has typed nothing, and
      // a note beside each of a file's lit steps.
      Future<int> marks(CodeShow show) async {
        var rec = ui.PictureRecorder();
        paintCode(ui.Canvas(rec), e.bounds.shift(-e.bounds.topLeft), e,
            seconds: 0, show: show);
        var img =
            await rec.endRecording().toImage(e.width.ceil(), e.height.ceil());
        var d = (await img.toByteData())!;
        var n = 0;
        for (var i = 0; i < d.lengthInBytes; i += 4) {
          if (d.getUint8(i) == 0xF2 &&
              d.getUint8(i + 1) == 0xC1 &&
              d.getUint8(i + 2) == 0x4E) {
            n++;
          }
        }
        return n;
      }

      var shown = await tester.runAsync(() => marks(c.codeShowFor(e)));
      var plain = await tester.runAsync(() => marks(const CodeShow()));
      expect(shown!, greaterThan(plain! + 300), reason: "the notes are there");
      // Played, it goes back to the scene's moment.
      c.playCode(e);
      expect(c.codeFull(e.id), isFalse);
      c.pause();
    });
  });
}

CodeElement starter0(String key) => startedFrom(
    codeStarters.firstWhere((s) => s.key == key),
    const CodeElement(ElementBase(id: "c", width: 800, height: 600)));
