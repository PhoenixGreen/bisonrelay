import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Offset, Size;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/code_highlight.dart';
import 'package:bruig/plugin_system/canvas/model/code_runners.dart';
import 'package:bruig/plugin_system/canvas/model/code_starters.dart';
import 'package:bruig/plugin_system/canvas/model/code_timing.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_run_element.dart';
import 'package:bruig/plugin_system/canvas/render/code_painter.dart';
import 'package:bruig/plugin_system/canvas/render/code_run_painter.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

// canvas_code_test.dart is the Code and Run panels (Ken, 2026-11-15: "a
// text/coding panel on the canvas and a seperate run panel that shows a
// visual preview and a code output pane ... split screen and a file area to
// show how the code works together"), built to the prototype he approved
// (code-element-prototype/index.html). Set CODE_PNG to a folder for
// pictures of them.

Future<void> _font(String family, List<String> files) async {
  var loader = FontLoader(family);
  for (var f in files) {
    loader.addFont(File("assets/fonts/$f")
        .readAsBytes()
        .then((b) => ByteData.view(Uint8List.fromList(b).buffer)));
  }
  await loader.load();
}

CodeElement starter(String key, {double w = 1150, double h = 840}) =>
    startedFrom(
        codeStarters.firstWhere((s) => s.key == key),
        CodeElement(ElementBase(id: "code", width: w, height: h),
            fontSize: 17));

Future<void> picture(
    String name, void Function(ui.Canvas) paint, Size size) async {
  var dir = Platform.environment["CODE_PNG"];
  if (dir == null) return;
  var rec = ui.PictureRecorder();
  paint(ui.Canvas(rec));
  var img =
      await rec.endRecording().toImage(size.width.ceil(), size.height.ceil());
  var png = await img.toByteData(format: ui.ImageByteFormat.png);
  File("$dir/$name.png").writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  setUpAll(() async {
    await _font("Inter",
        ["Inter-Regular.otf", "Inter-Medium.otf", "Inter-SemiBold.otf"]);
    await _font("RobotoMono", ["RobotoMono-VariableFont_wght.ttf"]);
  });

  group("a Code panel", () {
    test("kept: its files, panes, typing and steps", () {
      var e = starter("web");
      var back = elementFromJson(jsonRoundTrip(e.toJson())) as CodeElement;
      expect(
          back.files.map((f) => f.name), ["index.html", "style.css", "app.js"]);
      expect(back.layout, CodeLayout.oneOverTwo);
      expect(back.panes.map((p) => p.tabs), [
        ["f1"],
        ["f2"],
        ["f3"]
      ]);
      expect(back.typing.on, isTrue);
      expect(back.steps.length, 4);
      expect(back.files[1].text, e.files[1].text);
    });

    test("tabs: opened, closed, moved within a pane and to another", () {
      var e = starter("web");
      // app.js into the bottom-left pane, after style.css.
      var moved = e.moveTab("f3", 2, 1, 1);
      expect(moved.panes[1].tabs, ["f2", "f3"]);
      expect(moved.panes[1].active, "f3");
      expect(moved.panes[2].tabs, isEmpty);
      // ...and back in front of it.
      var reordered = moved.moveTab("f3", 1, 1, 0);
      expect(reordered.panes[1].tabs, ["f3", "f2"]);
      // Opened in the top pane too: a file can be open in two.
      var opened = reordered.openTab(0, "f2");
      expect(opened.panes[0].tabs, ["f1", "f2"]);
      expect(opened.panes[0].active, "f2");
      var closed = opened.closeTab(0, "f2");
      expect(closed.panes[0].tabs, ["f1"]);
      expect(closed.panes[0].active, "f1", reason: "the tab beside it shown");
    });

    test("a layout of fewer panes keeps every tab; more takes them back", () {
      var e = starter("web");
      var one = e.withLayout(CodeLayout.one);
      expect(one.panes.single.tabs, ["f1", "f2", "f3"]);
      var three = one.withLayout(CodeLayout.threeSide);
      expect(three.panes.map((p) => p.tabs.length), [1, 1, 1]);
      expect({for (var p in three.panes) ...p.tabs}, {"f1", "f2", "f3"});
      expect(three.columns, [1, 1, 1]);
    });

    test("typing: pane by pane, indents quickly, the pane shows what is typed",
        () {
      var e = starter("web");
      var plan = codePlan(e);
      var html = plan.files["f1"]!,
          css = plan.files["f2"]!,
          js = plan.files["f3"]!;
      expect(html.$1, e.typing.start);
      expect(css.$1, greaterThan(html.$2), reason: "after the page");
      expect(js.$1, greaterThan(css.$2));
      expect(typedCount(e, "f2", css.$1 - 0.01, plan), 0);
      expect(typedCount(e, "f2", css.$2, plan), e.files[1].text.length);
      // Halfway through the stylesheet's time, more than a third typed.
      var half = typedCount(e, "f2", (css.$1 + css.$2) / 2, plan);
      expect(
          half,
          inInclusiveRange(
              e.files[1].text.length * 0.3, e.files[1].text.length * 0.7));
      // All at once: every pane from the start.
      var together =
          codePlan(e.copyWith(typing: e.typing.copyWith(together: true)));
      expect(together.files.values.map((s) => s.$1).toSet(), {e.typing.start});

      // app.js and style.css in one pane: it shows the one being typed.
      var one = e.moveTab("f3", 2, 1, 1);
      var p = codePlan(one);
      expect(shownFile(one, 1, (p.files["f2"]!.$1 + p.files["f2"]!.$2) / 2, p),
          "f2");
      expect(shownFile(one, 1, (p.files["f3"]!.$1 + p.files["f3"]!.$2) / 2, p),
          "f3");
      // A lit step brings its file forward; a tab picked by hand wins.
      var lit =
          one.copyWith(steps: [CodeStep(at: 100, file: "f2", from: 1, to: 2)]);
      expect(shownFile(lit, 1, 101, codePlan(lit)), "f2");
      expect(shownFile(lit, 1, 101, codePlan(lit), picked: "f3"), "f3");
    });

    test("highlighting by role, and other files' names marked", () {
      var html = starter("web").files[0];
      var runs = highlightRuns(html.language, html.text);
      expect(runs.last.end, html.text.length, reason: "every letter covered");
      String said(CodeRole r) => [
            for (var x in runs)
              if (x.role == r) html.text.substring(x.start, x.end)
          ].join("|");
      expect(said(CodeRole.tag), contains("link"));
      expect(said(CodeRole.string), contains('"style.css"'));
      var e = starter("web");
      var linked = withLinks(runs, html.text, linkNames(e, "f1"));
      var named = {
        for (var r in linked)
          if (r.link.isNotEmpty) html.text.substring(r.start, r.end): r.link
      };
      expect(named, {"style.css": "f2", "app.js": "f3"});
      // A Python module by the name its import uses.
      var py = starter("python");
      var main = py.files[1];
      var pyRuns = withLinks(highlightRuns(main.language, main.text), main.text,
          linkNames(py, main.id));
      expect([
        for (var r in pyRuns)
          if (r.link.isNotEmpty) main.text.substring(r.start, r.end)
      ], [
        "words"
      ], reason: "count_words is not words");
      // Go and Dart and CSS and JS all coloured.
      for (var k in ["go", "dart", "flutter"]) {
        var f = starter(k).files.first;
        expect(
            highlightRuns(f.language, f.text)
                .where((r) => r.role == CodeRole.keyword),
            isNotEmpty,
            reason: k);
      }
    });

    test("a line between panes dragged shares them out again", () {
      var e = starter("web").copyWith(showFiles: false, windowBar: false);
      var b = codeBoxes(e, e.bounds);
      var down = b.dividers.firstWhere((d) => !d.columns);
      var lower = codeDividerDragged(e, down, Offset(0, e.height * 0.7));
      expect(
          lower.rows[0] / (lower.rows[0] + lower.rows[1]), closeTo(0.7, 0.01));
      var far = codeDividerDragged(e, down, Offset(0, e.height * 0.99));
      expect(far.rows[1] / (far.rows[0] + far.rows[1]), closeTo(0.125, 0.01),
          reason: "no pane under an eighth");
    });

    test("presses: a tab, its cross, a file, a line, a drop place", () {
      var e = starter("web");
      var b = codeBoxes(e, e.bounds);
      var tab = b.panes[1].tabs.single;
      expect(
          codeHitAt(e, tab.rect.center),
          isA<CodeTabHit>()
              .having((h) => h.file, "file", "f2")
              .having((h) => h.close, "close", isFalse));
      expect(codeHitAt(e, tab.close.center),
          isA<CodeTabHit>().having((h) => h.close, "close", isTrue));
      expect(codeHitAt(e, b.fileRows[2].$2.center),
          isA<CodeFileHit>().having((h) => h.file, "file", "f3"));
      expect(codeHitAt(e, b.dividers.first.hit.center), isA<CodeDividerHit>());
      // Dropped on the bottom-left pane's tab row, past its tab: after it.
      var row = b.panes[1].tabRow;
      expect(codeTabDrop(e, Offset(row.right - 5, row.center.dy)), (1, 1));
      expect(codeTabDrop(e, Offset(row.left + 2, row.center.dy)), (1, 0));
      expect(codeTabDrop(e, b.panes[2].code.center), (2, 1));
    });

    test("drawn: typed part way, then lit with a note", () async {
      var e = starter("web");
      var plan = codePlan(e);
      var mid = (plan.files["f2"]!.$1 + plan.files["f2"]!.$2) / 2;
      Future<ByteData> draw(double t) async {
        var rec = ui.PictureRecorder();
        paintCode(ui.Canvas(rec), e.bounds, e, seconds: t);
        var img =
            await rec.endRecording().toImage(e.width.ceil(), e.height.ceil());
        return (await img.toByteData())!;
      }

      var typing = await draw(mid);
      var lit = await draw(e.steps.first.at + 0.5);
      // The note's marker-yellow is on the page while lit, not while typing:
      // solid, not the edge of a yellow word.
      int marks(ByteData d) {
        var n = 0;
        for (var i = 0; i < d.lengthInBytes; i += 4) {
          if (d.getUint8(i) == 0xF2 &&
              d.getUint8(i + 1) == 0xC1 &&
              d.getUint8(i + 2) == 0x4E) n++;
        }
        return n;
      }

      await picture("code-typing",
          (c) => paintCode(c, e.bounds, e, seconds: mid), e.bounds.size);
      await picture(
          "code-lit",
          (c) => paintCode(c, e.bounds, e, seconds: e.steps.first.at + 0.5),
          e.bounds.size);
      for (var k in ["python", "go", "flutter"]) {
        var s = starter(k);
        await picture(
            "code-$k",
            (c) => paintCode(c, s.bounds, s, seconds: s.steps[1].at + 0.5),
            s.bounds.size);
      }
      for (var t in CodeTheme.values) {
        var s = starter("dart").copyWith(theme: t);
        await picture("code-theme-${t.name}",
            (c) => paintCode(c, s.bounds, s, seconds: 1e6), s.bounds.size);
      }
      // (app.js's own colour is that yellow too: its tab and its square.)
      expect(marks(lit), greaterThan(marks(typing) + 500));
    });
  });

  group("a Run panel", () {
    test("kept, with its run", () {
      var r = CodeRunElement(const ElementBase(id: "run"),
          code: "code",
          entry: "f1",
          when: CodeRunWhen.press,
          result: CodeRunResult(
              runner: "Browser",
              at: DateTime.utc(2026, 11, 15, 12),
              logs: const [
                CodeLog("Page ready"),
                CodeLog("oops", kind: CodeLogKind.error)
              ],
              preview: "0123456789abcdef.png"));
      var back = elementFromJson(jsonRoundTrip(r.toJson())) as CodeRunElement;
      expect(back.when, CodeRunWhen.press);
      expect(back.result!.logs.map((l) => (l.text, l.kind)),
          [("Page ready", CodeLogKind.log), ("oops", CodeLogKind.error)]);
      expect(back.assetIds, {"0123456789abcdef.png"},
          reason: "its picture kept with the canvas");
    });

    test("what runs each example, and from which file", () {
      CodeRunner of(String key) {
        var c = starter(key);
        return runnerOf(
            CodeRunElement(const ElementBase(id: "r"), code: c.id), c);
      }

      expect(of("web"), CodeRunner.web);
      expect(of("python"), CodeRunner.python);
      expect(
          entryFile(const CodeRunElement(ElementBase(id: "r")),
                  starter("python"))!
              .name,
          "main.py");
      expect(of("go"), CodeRunner.go);
      expect(of("dart"), CodeRunner.dart);
      expect(of("flutter"), CodeRunner.flutter);
      var f = starter("flutter");
      expect(
          runnerOf(
              CodeRunElement(const ElementBase(id: "r"), dartpad: true), f),
          CodeRunner.dartpad);
    });

    test("a page with its stylesheet and script put in it, its console caught",
        () {
      var c = starter("web");
      var page = webPage(c, c.files[0]);
      expect(page, contains("#count {"));
      expect(page, contains('getElementById("add")'));
      expect(page, isNot(contains('href="style.css"')));
      expect(page, isNot(contains('src="app.js"')));
      expect(page.indexOf("codeConsole"), lessThan(page.indexOf("<style>")),
          reason: "the console caught before anything runs");
      // A script that says </script> does not end its tag early.
      var tricky = c.withFileText("f3", 'console.log("</script>");');
      expect(webPage(tricky, tricky.files[0]), contains(r'"<\/script>"'));
    });

    test("waits for its time, then shows its run", () async {
      var c = starter("web");
      var r = CodeRunElement(
          const ElementBase(id: "r", width: 560, height: 840),
          code: c.id,
          result: CodeRunResult(
              runner: "Browser",
              at: DateTime.utc(2026),
              logs: const [
                CodeLog("Page ready"),
                CodeLog("Coins: 1"),
                CodeLog("Watch out", kind: CodeLogKind.warn)
              ]));
      var at = runAt(r, c)!;
      expect(at, closeTo(codePlan(c).end + 0.6, 1e-9));
      expect(
          waitingSaid(r, c, at - 1), startsWith("Runs when the typing ends"));
      expect(waitingSaid(r, c, at + 1), isNull);
      expect(
          waitingSaid(
              r.copyWith(clearResult: true, when: CodeRunWhen.press), c, 99),
          "Press Run");
      await picture(
          "run-output",
          (cv) => paintCodeRun(cv, r.bounds, r, c, seconds: at + 1),
          r.bounds.size);
      await picture("run-waiting",
          (cv) => paintCodeRun(cv, r.bounds, r, c, seconds: 0), r.bounds.size);
    });
  });
}

Map<String, dynamic> jsonRoundTrip(Map<String, dynamic> j) =>
    jsonDecode(jsonEncode(j)) as Map<String, dynamic>;
