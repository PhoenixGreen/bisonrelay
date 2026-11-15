import 'package:bruig/plugin_system/canvas/media/code_dart_runner.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/code_starters.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_run_element.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_code_run_test.dart is a Run panel's Dart and Flutter, run in the
// app (Ken, 2026-11-15, choosing dart_eval and flutter_eval over DartPad by
// default): a program's print caught, its errors told plainly, a loop that
// never ends stopped, and a Flutter app's own widgets built and drawn.
// (The browser's runs -- a page, Python, Go -- need the app's WebKit, so
// they are tried in the app itself.)

CodeElement starter(String k) => startedFrom(
    codeStarters.firstWhere((s) => s.key == k),
    const CodeElement(ElementBase(id: "c", width: 800, height: 600)));

void main() {
  test("a Dart program's print, line by line", () async {
    var c = starter("dart");
    var seen = <String>[];
    var logs = await runDart(c, c.files.first, onLog: (l) => seen.add(l.text));
    expect(logs.map((l) => l.text),
        ["Bread  £1.45", "Milk   £0.95", "Eggs   £2.30", "Total  £4.70"]);
    expect(seen, logs.map((l) => l.text).toList(), reason: "as they came");
  });

  test("another file of the project, imported", () async {
    var c = starter("dart");
    c = c
        .withFile(const CodeFile(
            id: "f9",
            name: "greet.dart",
            text: "String greet(String n) => 'Hello, \$n!';"))
        .withFileText(
            c.files.first.id,
            "import 'greet.dart';\n"
            "void main() { print(greet('Ken')); }");
    var logs = await runDart(c, c.file(c.files.first.id)!);
    expect(logs.map((l) => l.text), ["Hello, Ken!"]);
  });

  test("a mistake is told, as an error", () async {
    var c = starter("dart").withFileText("f1", "void main() { print(nope); }");
    var logs = await runDart(c, c.files.first);
    expect(logs.single.kind, CodeLogKind.error);
    expect(logs.single.text, contains("nope"));
  });

  test("a loop that never ends is stopped", () async {
    var c = starter("dart")
        .withFileText("f1", "void main() { var i = 0; while (true) { i++; } }");
    var logs =
        await runDart(c, c.files.first, limit: const Duration(seconds: 2));
    expect(logs.last.kind, CodeLogKind.error);
    expect(logs.last.text, startsWith("Stopped after 2 seconds"));
  });

  test("a Flutter app: what runApp is given, handed back to be drawn", () {
    var src = flutterPreviewSource(
        "void main() => runApp(const CounterApp());\nclass X {}");
    expect(src, contains(r"void main() => $$noRunApp(const CounterApp());"));
    expect(src, contains(r"Widget $$previewApp() => const CounterApp();"));
    // Over lines, with a trailing comma.
    expect(
        flutterPreviewSource(
            "void main() {\n  runApp(\n    MyApp(a: f(1)),\n  );\n}"),
        contains(r"Widget $$previewApp() => MyApp(a: f(1));"));
    expect(flutterPreviewSource("void main() {}"), isNull);
  });

  testWidgets("a Flutter app's own widgets, built and drawn", (tester) async {
    var c = starter("flutter");
    var b = buildFlutterApp(c, c.files.first);
    expect(b.error, isNull);
    expect(b.widget, isA<Widget>());
    var png = await tester
        .runAsync(() => pictureOfWidget(b.widget!, const Size(360, 600)));
    expect(png, isNotNull);
    expect(png!.sublist(1, 4), "PNG".codeUnits);
    // One that does not compile says why.
    var broken = c.withFileText("f1",
        "import 'package:flutter/material.dart';\nvoid main() => runApp(Nope());");
    expect(buildFlutterApp(broken, broken.files.first).error, contains("Nope"));
  });
}
