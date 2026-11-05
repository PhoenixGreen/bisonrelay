import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The bundles (test_bundles/) run the suite a few compiles at a time: every
// test file has to be in one, or be one generate.dart runs alone, or the
// bundled run would leave it out without a word.

void main() {
  test("every test file is in a bundle, or runs alone", () {
    var generator = File("test_bundles/generate.dart").readAsStringSync();
    var alone = {
      for (var m in RegExp(r'^\s*"([a-z0-9_]+_test\.dart)",', multiLine: true)
          .allMatches(generator))
        m.group(1)!,
    };
    var bundled = <String>{};
    for (var f in Directory("test_bundles").listSync()) {
      if (f is! File || !RegExp(r"bundle_\d+_test\.dart$").hasMatch(f.path)) {
        continue;
      }
      for (var m in RegExp(r"import '\.\./test/([a-z0-9_]+_test\.dart)'")
          .allMatches(f.readAsStringSync())) {
        bundled.add(m.group(1)!);
      }
    }
    var files = [
      for (var f in Directory("test").listSync())
        if (f is File && f.path.endsWith("_test.dart")) f.uri.pathSegments.last,
    ];
    var missing = [
      for (var f in files)
        if (!bundled.contains(f) && !alone.contains(f)) f,
    ];
    var gone = [
      for (var f in bundled)
        if (!files.contains(f)) f,
    ];
    expect([...missing, ...gone], isEmpty,
        reason:
            "the bundles are out of date: dart run test_bundles/generate.dart");
  });
}
