import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/export/epub_layers.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/presets/builtin_element_presets.dart';
import 'package:bruig/plugin_system/canvas/model/code_runners.dart';
import 'package:bruig/plugin_system/canvas/model/code_starters.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_run_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_task_element.dart';
import 'package:bruig/plugin_system/canvas/render/code_task_painter.dart';
import 'package:bruig/plugin_system/canvas/render/code_painter.dart';
import 'package:bruig/plugin_system/canvas/render/code_run_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/code_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/code_studio.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/elements_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_code_stage_test.dart is the Code and Run panels on the stage, as
// the prototype Ken approved has them (2026-11-15): tabs shown, dragged
// along their row or onto another pane; the line between two panes
// dragged; a file in the list opened in the pane last pressed; a pane's
// code opened for typing with a second press; Run pressed. And the Add
// panel's Code chip, putting the two down from an example.

Widget _app(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(
            create: (c) => CanvasPreferences()),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

/// _FakeHost runs nothing: it prints what it was given and makes a
/// picture, as a browser would.
class _FakeHost implements CodeRunHost {
  final List<(CodeRunner, String)> ran = [];
  @override
  Future<CodeRunOutcome> run(CodeRunner runner, CodeElement code,
      CodeFile entry, Size size, void Function(CodeLog) onLog) async {
    ran.add((runner, entry.name));
    onLog(const CodeLog("Page ready"));
    return const CodeRunOutcome(
        logs: [CodeLog("Page ready")], picture: [1, 2, 3]);
  }
}

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
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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

  testWidgets(
      "the Code chip puts down an empty project and its Run panel; the "
      "examples are its presets", (tester) async {
    var ctl = CanvasController(const CanvasDocument());
    addTearDown(ctl.dispose);
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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

  testWidgets("a second press on a picked panel's code opens it for typing",
      (tester) async {
    await stage(tester, "web");
    var pane = codeBoxes(code(), code().bounds).panes[0].code;
    await tester.tapAt(at(pane.center));
    await tester.pump(const Duration(milliseconds: 100));
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
    expect(runLayer.frame, isNotNull);
    expect(runLayer.frame!.html, contains("#count {"),
        reason: "its stylesheet in it");
    expect(runLayer.frame!.html, isNot(contains("flutter_inappwebview")),
        reason: "no app-only console catcher in a book");
    expect(built.stage.layers.map((l) => l.id), contains(code.id),
        reason: "its typing changes it");
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
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(CodeStudio(
          controller: c, codeId: code().id, onDone: c.closeCodeStudio)));
      await tester.pumpAndSettle();
    }

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
    test("its checks: words found loosely, patterns, files, what was printed",
        () {
      var c = starter0("flutter");
      const has = CodeCheck(CodeCheckKind.has, "Size 72",
          text: "TextStyle(fontSize:72)");
      expect(has.metBy(c, null), isTrue, reason: "spaces don't matter");
      expect(
          const CodeCheck(CodeCheckKind.lacks, "No 72", text: "fontSize: 72")
              .metBy(c, null),
          isFalse);
      expect(
          const CodeCheck(CodeCheckKind.has, "a coin count",
                  text: r"int\s+coins\s*=\s*\d+", pattern: true)
              .metBy(c, null),
          isTrue);
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
}

CodeElement starter0(String key) => startedFrom(
    codeStarters.firstWhere((s) => s.key == key),
    const CodeElement(ElementBase(id: "c", width: 800, height: 600)));
