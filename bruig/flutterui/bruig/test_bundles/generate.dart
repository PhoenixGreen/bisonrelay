// generate.dart writes the test bundles: every test file under test/ that
// can share a process, in a few files of their own, so the suite is compiled
// a few times rather than once for every file -- which, one after another,
// was most of the time the suite took.
//
//   dart run test_bundles/generate.dart
//
// Run it again after adding or removing a test file:
// test/test_bundles_cover_test.dart fails until it has been.
//
// The whole suite, bundled: test_bundles/run.sh. One file on its own, as
// ever: flutter test test/<file>.
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
  // Needs a process where no look's shader has been loaded yet: once one
  // is, it stays, and an export that forgot to load it would still pass.
  "canvas_document_export_looks_test.dart",
  // This guard, which reads the bundles themselves.
  "test_bundles_cover_test.dart",
};

/// bundles is how many there are: about one for each core the machine
/// runs them on.
const bundles = 8;

final _bundle = RegExp(r"bundle_\d+_test\.dart$");

void main() {
  var dir = Directory("test");
  var files = [
    for (var f in dir.listSync())
      if (f is File &&
          f.path.endsWith("_test.dart") &&
          !alone.contains(f.uri.pathSegments.last))
        f,
  ]..sort((a, b) => b.lengthSync().compareTo(a.lengthSync()));
  // Shared out by size, the largest first, each to the lightest bundle.
  var groups = List.generate(bundles, (_) => <File>[]);
  var weights = List.filled(bundles, 0);
  for (var f in files) {
    var i = 0;
    for (var k = 1; k < bundles; k++) {
      if (weights[k] < weights[i]) i = k;
    }
    groups[i].add(f);
    weights[i] += f.lengthSync();
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
  stdout.writeln("${files.length} files in $bundles bundles; "
      "${alone.length} run alone.");
}
