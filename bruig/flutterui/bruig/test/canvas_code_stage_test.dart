import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/code_runners.dart';
import 'package:bruig/plugin_system/canvas/model/code_starters.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_run_element.dart';
import 'package:bruig/plugin_system/canvas/render/code_painter.dart';
import 'package:bruig/plugin_system/canvas/render/code_run_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/code_editor.dart';
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
    c.addCodeLesson(codeStarters.firstWhere((s) => s.key == starter));
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

  testWidgets("the Code chip puts down a Code panel and its Run panel",
      (tester) async {
    var ctl = CanvasController(const CanvasDocument());
    addTearDown(ctl.dispose);
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(
        SizedBox(width: 400, child: CanvasElementsPanel(controller: ctl))));
    await tester.tap(find.byKey(const ValueKey("addCode")));
    await tester.pumpAndSettle();
    expect(find.text("Python"), findsOneWidget);
    expect(find.text("Flutter app"), findsOneWidget);
    await tester.tap(find.text("Python"));
    await tester.pumpAndSettle();
    var codeEl = ctl.document.elements.whereType<CodeElement>().single;
    var runEl = ctl.document.elements.whereType<CodeRunElement>().single;
    expect(codeEl.files.map((f) => f.name), ["words.py", "main.py"]);
    expect(runEl.code, codeEl.id);
    expect(codeEl.file(runEl.entry)!.name, "main.py");
    expect(runEl.x, greaterThan(codeEl.bounds.right), reason: "beside it");
    expect(ctl.selection, {codeEl.id});
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
}
