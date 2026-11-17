import 'dart:convert';
import 'dart:io';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/element_samples.dart';

// canvas_element_reading_test.dart is every kind of element read back from
// a file: as it was written, and from a file written to break it.
//
// A canvas can come from anyone (ARCHITECTURE.md, "Saved form"): reading
// never refuses a document, so a mistyped field falls back rather than
// throwing, and what a received file asks for is bounded. One element that
// throws loses the whole canvas.

/// hostileTypes are values of the wrong type for almost any field.
const hostileTypes = <Object>[
  5,
  -1e12,
  1e12,
  "x",
  true,
  <Object>[],
  <String, Object>{}
];

/// keysRead are the keys [file]'s code reads from a map, as json["key"].
Set<String> keysRead(String file) => {
      for (var m in RegExp(r'\b\w+\["(\w+)"\]')
          .allMatches(File(file).readAsStringSync()))
        m.group(1)!,
    };

/// classFile is the file under model/ that declares [className].
final Map<String, String> classFile = () {
  var out = <String, String>{};
  for (var f in Directory("lib/plugin_system/canvas/model")
      .listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith(".dart")) continue;
    for (var m in RegExp(r"^class (\w+)", multiLine: true)
        .allMatches(f.readAsStringSync())) {
      out[m.group(1)!] = f.path;
    }
  }
  return out;
}();

/// maps are every map in [json], up to [depth] levels down, as the map
/// itself: what a hostile file can put a field into.
List<Map<String, dynamic>> maps(Object? json, {int depth = 3}) {
  var out = <Map<String, dynamic>>[];
  void walk(Object? v, int d) {
    if (d > depth) return;
    if (v is Map<String, dynamic>) {
      out.add(v);
      for (var c in v.values) {
        walk(c, d + 1);
      }
    } else if (v is List) {
      for (var c in v.take(4)) {
        walk(c, d);
      }
    }
  }

  walk(json, 0);
  return out;
}

Map<String, dynamic> written(CanvasElement e) =>
    jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>;

void main() {
  for (var (name, element) in elementSamples()) {
    group(name, () {
      test("reads back as it was written", () {
        var json = written(element);
        var back = elementFromJson(json);
        expect(back.kind, element.kind);
        expect(jsonEncode(back.toJson()), jsonEncode(element.toJson()));
      });

      test("a field of the wrong type falls back, never throws", () {
        var root = written(element);
        // The keys its own class reads, at the top, as well as every key
        // written anywhere in it: a field the defaults leave out can still
        // arrive in a received file.
        var own = keysRead(classFile[element.runtimeType.toString()]!);
        var failures = <String>[];
        var places = maps(root);
        for (var (i, map) in places.indexed) {
          var keys = {...map.keys, if (i == 0) ...own};
          for (var key in keys) {
            var had = map.containsKey(key);
            var was = map[key];
            for (var bad in hostileTypes) {
              map[key] = bad;
              try {
                elementFromJson(root);
              } catch (e) {
                failures.add("$key = ${jsonEncode(bad)}: "
                    "${e.toString().split("\n").first}");
              }
            }
            had ? map[key] = was : map.remove(key);
          }
        }
        expect(failures.toSet().toList(), isEmpty);
      });

      test("a received file cannot make it huge", () {
        var root = written(element);
        var long = "x" * 2000000;
        var many = List<String>.filled(400000, "abcd");
        var failures = <String>[];
        for (var map in maps(root)) {
          for (var key in map.keys.toList()) {
            var was = map[key];
            for (var big in <Object>[long, many]) {
              map[key] = big;
              try {
                var size = jsonEncode(elementFromJson(root).toJson()).length;
                if (size > 1200000) {
                  failures.add(
                      "$key: ${big is String ? "a long string" : "a long list"} kept ($size characters)");
                }
              } catch (e) {
                failures.add("$key: threw ${e.toString().split("\n").first}");
              }
            }
            map[key] = was;
          }
        }
        expect(failures.toSet().toList(), isEmpty);
      });
    });
  }
}
