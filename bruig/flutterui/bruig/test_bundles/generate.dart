// generate.dart writes the test bundles: every test file under test/ that
// can share a process, in a few files of their own, so the suite is compiled
// a few times rather than once for every file -- which, one after another,
// was most of the time the suite took.
//
//   dart run test_bundles/generate.dart
//
// The files are shared out by how long each took (test_bundles/timings.json),
// so the bundles finish together: the slowest bundle is the suite's time. A
// file with no timing yet is guessed from its size. After a run made with
// `sh test_bundles/run.sh --reporter json > run.json`, refresh the timings
// and the bundles with
//
//   dart run test_bundles/generate.dart --timings run.json
//
// Run it again after adding or removing a test file:
// test/test_bundles_cover_test.dart fails until it has been.
//
// The whole suite, bundled: test_bundles/run.sh. One file on its own, as
// ever: flutter test test/<file>.
import 'dart:convert';
import 'dart:io';

/// alone are the files that cannot share a process with others: each
/// changes something no test can put back -- a decoder loaded into the
/// process, fonts registered with the engine.
const alone = {
  // Loads the built app's audio decoder into the process.
  "canvas_clip_sound_test.dart",
  // Register real fonts, which every later layout would then use.
  "canvas_font_outlines_test.dart",
  "canvas_render_test.dart",
  "canvas_score_engraver_test.dart",
  "canvas_score_studio_test.dart",
  "canvas_synth_module_test.dart",
  "canvas_metronome_test.dart",
  "canvas_code_test.dart",
  // Needs a process where no look's shader has been loaded yet: once one
  // is, it stays, and an export that forgot to load it would still pass.
  "canvas_document_export_looks_test.dart",
  // Turns Flutter's leak tracker on, which then stays on for the process.
  "canvas_leaks_test.dart",
  // This guard, which reads the bundles themselves.
  "test_bundles_cover_test.dart",
};

/// bundles is how many there are: small enough that no process runs long --
/// a process slows as it goes, and 16 ran the suite 30% faster than 8.
const bundles = 16;

final _bundle = RegExp(r"bundle_\d+_test\.dart$");

void main(List<String> args) {
  if (args.length == 2 && args.first == "--timings") {
    _saveTimings(args.last);
  }
  var timings = _timings();
  var dir = Directory("test");
  var files = [
    for (var f in dir.listSync())
      if (f is File &&
          f.path.endsWith("_test.dart") &&
          !alone.contains(f.uri.pathSegments.last))
        f,
  ];
  // A file not timed yet is guessed from its size, at the rate the timed
  // files ran at.
  var timedBytes = 0, timedSeconds = 0.0;
  for (var f in files) {
    if (timings[_name(f)] case var t?) {
      timedBytes += f.lengthSync();
      timedSeconds += t;
    }
  }
  var perByte = timedBytes == 0 ? 1.0 : timedSeconds / timedBytes;
  double cost(File f) => timings[_name(f)] ?? f.lengthSync() * perByte;
  files.sort((a, b) => cost(b).compareTo(cost(a)));
  // Shared out by time, the longest first, each to the lightest bundle.
  var groups = List.generate(bundles, (_) => <File>[]);
  var weights = List.filled(bundles, 0.0);
  for (var f in files) {
    var i = 0;
    for (var k = 1; k < bundles; k++) {
      if (weights[k] < weights[i]) i = k;
    }
    groups[i].add(f);
    weights[i] += cost(f);
  }
  var out = Directory("test_bundles");
  for (var old in out.listSync()) {
    if (old is File && _bundle.hasMatch(old.path)) old.deleteSync();
  }
  for (var (i, group) in groups.indexed) {
    group.sort((a, b) => a.path.compareTo(b.path));
    var lines = [
      "// Written by test_bundles/generate.dart: do not edit.",
      "import 'package:flutter_test/flutter_test.dart';",
      "",
      "import 'reset.dart';",
      for (var (k, f) in group.indexed)
        "import '../test/${f.uri.pathSegments.last}' as t$k;",
      "",
      "void main() {",
      for (var (k, f) in group.indexed) ...[
        "  group('${f.uri.pathSegments.last}', () {",
        "    setUpAll(betweenFiles);",
        "    t$k.main();",
        "  });",
      ],
      "}",
    ];
    File("test_bundles/bundle_${i + 1}_test.dart")
        .writeAsStringSync("${lines.join("\n")}\n");
  }
  stdout.writeln("${files.length} files in $bundles bundles "
      "(${[for (var w in weights) w.round()].join(", ")} s); "
      "${alone.length} run alone.");
  _writeQuick(files);
}

/// _writeQuick writes quick.dart: every file with no widget test in it, in
/// one compile, for a check in about half a minute while working (quick.sh).
/// Not named _test.dart, so run.sh, which runs this folder, does not run it
/// twice.
void _writeQuick(List<File> files) {
  var quick = [
    for (var f in files)
      if (!f.readAsStringSync().contains("testWidgets(")) f,
  ]..sort((a, b) => a.path.compareTo(b.path));
  var lines = [
    "// Written by test_bundles/generate.dart: do not edit. The model tests",
    "// alone, no widgets: sh test_bundles/quick.sh",
    "import 'package:flutter_test/flutter_test.dart';",
    "",
    "import 'reset.dart';",
    for (var (k, f) in quick.indexed)
      "import '../test/${f.uri.pathSegments.last}' as t$k;",
    "",
    "void main() {",
    for (var (k, f) in quick.indexed) ...[
      "  group('${f.uri.pathSegments.last}', () {",
      "    setUpAll(betweenFiles);",
      "    t$k.main();",
      "  });",
    ],
    "}",
  ];
  File("test_bundles/quick.dart").writeAsStringSync("${lines.join("\n")}\n");
  stdout.writeln("${quick.length} model-only files in quick.dart.");
}

String _name(File f) => f.uri.pathSegments.last;

const _timingsFile = "test_bundles/timings.json";

/// _timings is how many seconds each test file's tests took, by file name.
Map<String, double> _timings() {
  var f = File(_timingsFile);
  if (!f.existsSync()) return {};
  return {
    for (var MapEntry(:key, :value)
        in (jsonDecode(f.readAsStringSync()) as Map).entries)
      key as String: (value as num).toDouble(),
  };
}

/// _saveTimings writes timings.json from a run's json report: the tests'
/// time summed for each file -- the bundle's group a file is wrapped in, or
/// the file run alone.
void _saveTimings(String report) {
  var suites = <int, String>{}, groups = <int, String>{};
  var started = <int, (int, String)>{};
  var seconds = <String, double>{};
  for (var line in File(report).readAsLinesSync()) {
    if (!line.startsWith("{")) continue;
    Map<String, dynamic> e;
    try {
      e = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      continue;
    }
    switch (e["type"]) {
      case "suite":
        suites[e["suite"]["id"]] = (e["suite"]["path"] as String).split("/").last;
      case "group":
        groups[e["group"]["id"]] = e["group"]["name"] ?? "";
      case "testStart":
        var t = e["test"];
        var file = suites[t["suiteID"]] ?? "";
        for (var g in (t["groupIDs"] as List? ?? const [])) {
          var name = (groups[g] ?? "").split(" ").first;
          if (name.endsWith("_test.dart")) {
            file = name;
            break;
          }
        }
        started[t["id"]] = (e["time"] as int, file);
      case "testDone":
        if (started.remove(e["testID"]) case (var at, var file)?) {
          if (e["hidden"] == true || _bundle.hasMatch(file)) break;
          seconds[file] =
              (seconds[file] ?? 0) + ((e["time"] as int) - at) / 1000;
        }
    }
  }
  var sorted = Map.fromEntries(seconds.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key)));
  File(_timingsFile).writeAsStringSync(
      "${const JsonEncoder.withIndent(" ").convert({
    for (var MapEntry(:key, :value) in sorted.entries)
      key: double.parse(value.toStringAsFixed(1)),
  })}\n");
  stdout.writeln("timings for ${seconds.length} files written");
}
