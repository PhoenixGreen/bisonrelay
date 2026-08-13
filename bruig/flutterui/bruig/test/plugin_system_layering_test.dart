import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// plugin_system_layering_test.dart enforces the one rule that holds the
// plugin system's shape together.
//
// lib/plugin_system/ is the machinery: installation, the capability
// vocabulary, nav items, the settings page. lib/plugin_system/writing_tools/
// and lib/plugin_system/link_previews/ are the app's side of the two
// built-in plugins. The features import the machinery; the machinery imports
// neither.
//
// It is asserted here rather than left to review because it is broken by
// accident, in one line, by anyone reaching for something convenient -- and
// once broken the directory can no longer be read without knowing what a
// wavy underline is, which was the whole reason for the split.

const _root = "lib/plugin_system";
const _features = ["writing_tools", "link_previews"];

List<File> _dartFilesIn(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith(".dart"))
    .toList();

/// _coreFiles is plugin_system's own machinery -- everything not inside one
/// of the feature directories.
List<File> _coreFiles() => _dartFilesIn(_root)
    .where((f) => !_features.any((d) => f.path.contains("$_root/$d/")))
    .toList();

void main() {
  test("the machinery does not import the features", () {
    var offenders = <String>[];
    for (var file in _coreFiles()) {
      var text = file.readAsStringSync();
      for (var line in text.split("\n")) {
        var trimmed = line.trimLeft();
        if (!trimmed.startsWith("import ") && !trimmed.startsWith("export ")) {
          continue;
        }
        for (var feature in _features) {
          if (line.contains("plugin_system/$feature/")) {
            offenders.add("${file.path}: ${line.trim()}");
          }
        }
      }
    }
    expect(offenders, isEmpty,
        reason: "plugin_system's machinery must not depend on a capability's "
            "implementation:\n${offenders.join("\n")}");
  });

  test("the machinery is still there to be read", () {
    // A guard on the guard: if the directories were renamed and this test
    // silently started checking nothing, that is worse than a failure.
    expect(_coreFiles(), isNotEmpty);
    for (var feature in _features) {
      expect(Directory("$_root/$feature").existsSync(), isTrue,
          reason: "$feature moved; update this test");
    }
  });
}
