import 'dart:ui' show Size;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/element_preset.dart';
import 'package:bruig/plugin_system/canvas/model/code_timing.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';

// code_starters.dart is the examples a Code panel can start from, as its
// built-in presets (Ken, 2026-11-15: "the current options should probably
// be presets as they already have pre-built animations and code"): a small
// project in each language, laid out in panes, typing itself in, with a few
// lines lit to explain it.

/// CodeStarter is one of them.
class CodeStarter {
  final String key;
  final String title;
  final String about;
  final String project;
  final CodeKind kind;
  final List<(String, String)> files;
  final CodeLayout layout;

  /// panes is each pane's tabs, by the files' places in [files].
  final List<List<int>> panes;

  /// steps are (file, from, to, note, seconds after the typing ends,
  /// length).
  final List<(int, int, int, String, double, double)> steps;

  /// entry is the file a Run panel starts from, by its place.
  final int entry;
  const CodeStarter(
      {required this.key,
      required this.title,
      required this.about,
      required this.project,
      required this.kind,
      required this.files,
      required this.layout,
      required this.panes,
      this.steps = const [],
      this.entry = 0});
}

const _html = '''<!doctype html>
<html>
<head>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <h1>Coins saved</h1>
  <p id="count">0</p>
  <button id="add">Add a coin</button>
  <script src="app.js"></script>
</body>
</html>''';

const _css = '''body {
  margin: 0;
  min-height: 100vh;
  display: grid;
  place-content: center;
  text-align: center;
  font-family: system-ui, sans-serif;
  background: #10202b;
  color: #f1f5f9;
}

#count {
  font-size: 72px;
  margin: 0 0 16px;
}

button {
  font: inherit;
  padding: 10px 18px;
  border: 0;
  border-radius: 8px;
  background: #2ed6a1;
}''';

const _js = '''const count = document.getElementById("count");
const add = document.getElementById("add");
let coins = 0;

add.addEventListener("click", () => {
  coins = coins + 1;
  count.textContent = coins;
  console.log("Coins:", coins);
});

console.log("Page ready");''';

const _words = '''def count_words(text):
    """Count how often each word appears."""
    counts = {}
    for word in text.split():
        counts[word] = counts.get(word, 0) + 1
    return counts''';

const _main = '''from words import count_words

sentence = "the cat sat on the mat with the hat"
counts = count_words(sentence)

for word, n in sorted(counts.items(), key=lambda p: -p[1]):
    print(f"{word:>5} {'#' * n}")

print("Different words:", len(counts))''';

const _goMain = 'package main\n'
    '\n'
    'import "fmt"\n'
    '\n'
    'func main() {\n'
    '\tfor i := 0; i < 10; i++ {\n'
    '\t\tfmt.Print(fib(i), " ")\n'
    '\t}\n'
    '\tfmt.Println()\n'
    '\tfmt.Println("Ten numbers, no recursion.")\n'
    '}';

const _goFib = 'package main\n'
    '\n'
    '// fib returns the nth Fibonacci number, counting from 0.\n'
    'func fib(n int) int {\n'
    '\ta, b := 0, 1\n'
    '\tfor i := 0; i < n; i++ {\n'
    '\t\ta, b = b, a+b\n'
    '\t}\n'
    '\treturn a\n'
    '}';

const _dart = r'''class Item {
  final String name;
  final int pence;
  const Item(this.name, this.pence);
}

String pounds(int pence) => '£${(pence / 100).toStringAsFixed(2)}';

void main() {
  const basket = [Item('Bread', 145), Item('Milk', 95), Item('Eggs', 230)];
  for (final item in basket) {
    print('${item.name.padRight(6)} ${pounds(item.pence)}');
  }
  final total = basket.fold(0, (sum, item) => sum + item.pence);
  print('Total  ${pounds(total)}');
}''';

const _flutter = r'''import 'package:flutter/material.dart';

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
        appBar: AppBar(title: const Text('Coins saved')),
        body: Center(
          child: Text('$coins', style: const TextStyle(fontSize: 72)),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => setState(() => coins++),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}''';

const codeStarters = [
  CodeStarter(
      key: "web",
      kind: CodeKind.web,
      title: "Web page",
      about: "HTML, CSS and JavaScript",
      project: "coins-page",
      files: [("index.html", _html), ("style.css", _css), ("app.js", _js)],
      layout: CodeLayout.oneOverTwo,
      panes: [
        [0],
        [1],
        [2]
      ],
      steps: [
        (0, 4, 4, "The page pulls in style.css", 0.8, 3.2),
        (0, 10, 10, "…and runs app.js", 4.2, 3),
        (1, 12, 15, "#count styles <p id=\"count\">", 7.4, 3),
        (2, 5, 9, "Runs on every click", 10.6, 3.4),
      ]),
  CodeStarter(
      key: "python",
      kind: CodeKind.python,
      title: "Python",
      about: "Two files, one import",
      project: "word-count",
      files: [("words.py", _words), ("main.py", _main)],
      layout: CodeLayout.twoSide,
      panes: [
        [0],
        [1]
      ],
      entry: 1,
      steps: [
        (1, 1, 1, "count_words comes from words.py", 0.8, 3),
        (0, 4, 5, "One pass: add one per word", 4, 3.2),
        (1, 6, 7, "Most common first, as a bar", 7.4, 3.4),
      ]),
  CodeStarter(
      key: "go",
      kind: CodeKind.go,
      title: "Go",
      about: "One package, two files",
      project: "fibonacci",
      files: [("main.go", _goMain), ("fib.go", _goFib)],
      layout: CodeLayout.twoSide,
      panes: [
        [0],
        [1]
      ],
      steps: [
        (0, 7, 7, "fib is in fib.go: same package", 0.8, 3.4),
        (1, 5, 8, "Keep two numbers; slide them along", 4.4, 3.4),
      ]),
  CodeStarter(
      key: "dart",
      kind: CodeKind.dart,
      title: "Dart",
      about: "A class and a list",
      project: "basket",
      files: [("main.dart", _dart)],
      layout: CodeLayout.one,
      panes: [
        [0]
      ],
      steps: [
        (0, 1, 5, "A class: a name and a price in pence", 0.8, 3.2),
        (0, 11, 13, "Print each item, padded into columns", 4.2, 3.2),
        (0, 14, 14, "fold adds them up", 7.6, 3),
      ]),
  CodeStarter(
      key: "flutter",
      kind: CodeKind.flutter,
      title: "Flutter app",
      about: "Widgets, drawn in the preview",
      project: "counter_app",
      files: [("main.dart", _flutter)],
      layout: CodeLayout.one,
      panes: [
        [0]
      ],
      steps: [
        (0, 3, 3, "Start the app", 0.8, 3),
        (0, 13, 13, "The state: one number", 4, 3),
        (0, 23, 26, "Tap: add one, then redraw", 7.2, 3.4),
      ]),
  CodeStarter(
      key: "blank",
      kind: CodeKind.web,
      title: "Blank",
      about: "One empty web page",
      project: "project",
      files: [("index.html", "")],
      layout: CodeLayout.one,
      panes: [
        [0]
      ]),
];

/// startedFrom is a Code panel set up as [s]: its files, panes and steps, on
/// [base] (whose box it keeps), typing itself in unless it is blank.
CodeElement startedFrom(CodeStarter s, CodeElement base) {
  var files = [
    for (var (i, (name, text)) in s.files.indexed)
      CodeFile(
          id: "f${i + 1}",
          name: name,
          text: text,
          colour: codeFileColours[i % codeFileColours.length]),
  ];
  var e = base.copyWith(
    title: s.project,
    project: s.kind,
    files: files,
    layout: s.layout,
    panes: [
      for (var p in s.panes)
        CodePane(
            tabs: [for (var i in p) files[i].id], active: files[p.first].id),
    ],
    columns: s.layout.evenColumns,
    rows: s.layout.evenRows,
    typing: CodeTyping(on: s.files.any((f) => f.$2.isNotEmpty)),
  );
  var end = codePlan(e).end;
  return e.copyWith(steps: [
    for (var (file, from, to, note, after, length) in s.steps)
      CodeStep(
          at: double.parse((end + after).toStringAsFixed(1)),
          length: length,
          file: files[file].id,
          from: from,
          to: to,
          note: note),
  ]);
}

/// codeExamplePresets are the examples as built-in presets of a Code panel,
/// designed on a 1080p page (and scaled to the page they are used on).
List<ElementPreset> get codeExamplePresets => [
      for (var s in codeStarters)
        if (s.key != "blank")
          ElementPreset(
            id: "code-${s.key}",
            name: "${s.title}: ${s.project}",
            kind: ElementKind.code,
            builtIn: true,
            madeOn: const Size(1920, 1080),
            element: startedFrom(
                    s,
                    const CodeElement(
                        ElementBase(id: "example", width: 1152, height: 842.4),
                        fontSize: 17.28))
                .toJson(),
          ),
    ];
