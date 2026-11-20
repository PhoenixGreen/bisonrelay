import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// plugin_system_layering_test.dart enforces the one rule that holds the
// plugin system's shape together.
//
// lib/plugin_system/ is the machinery: installation, the capability
// vocabulary, nav items, the settings page. lib/plugin_system/writing_tools/,
// lib/plugin_system/link_previews/ and lib/plugin_system/canvas/ are the
// features that can be turned off. The features import the machinery; the
// machinery imports none of them.
//
// Between the features the rule is weaker but still a rule: canvas may import
// writing_tools, creative_ai may import both, and nothing imports creative_ai
// or (but creative_ai) canvas. Canvas publishes into the post
// library -- which is where documents on disk live, and is no plugin's -- so
// that one edge is real and is allowed. The reverse would mean the writing
// tools could not be read without knowing what a keyframe is, and would make
// the pair impossible to separate later.
//
// It is asserted here rather than left to review because it is broken by
// accident, in one line, by anyone reaching for something convenient -- and
// once broken the directory can no longer be read without knowing what a
// wavy underline is, which was the whole reason for the split.

const _root = "lib/plugin_system";
const _features = ["writing_tools", "link_previews", "canvas", "creative_ai"];

/// _mayImport is which features each feature may reach into; a feature not
/// listed may reach into none. canvas reaches into the post library (see the
/// note above). creative_ai sits on top of the two it works in, adding itself
/// through the hooks they offer, and nothing reaches into it -- so turning it
/// off, or taking it out, leaves them as they were.
const _mayImport = {
  "canvas": ["writing_tools"],
  "creative_ai": ["canvas", "writing_tools"],
};

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

  test("features reach across only where allowed, and one way", () {
    var offenders = <String>[];
    for (var file in _dartFilesIn(_root)) {
      var owner =
          _features.where((f) => file.path.contains("$_root/$f/")).firstOrNull;
      if (owner == null) continue;
      var allowed = {owner, ...?_mayImport[owner]};
      for (var line in file.readAsStringSync().split("\n")) {
        var trimmed = line.trimLeft();
        if (!trimmed.startsWith("import ") && !trimmed.startsWith("export ")) {
          continue;
        }
        for (var feature in _features) {
          if (allowed.contains(feature)) continue;
          if (line.contains("plugin_system/$feature/")) {
            offenders.add("${file.path}: ${line.trim()}");
          }
        }
      }
    }
    expect(offenders, isEmpty,
        reason: "canvas may import writing_tools; creative_ai may import "
            "canvas and writing_tools; nothing else crosses:\n"
            "${offenders.join("\n")}");
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
