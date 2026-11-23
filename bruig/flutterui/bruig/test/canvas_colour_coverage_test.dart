import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/chart_presets.dart';
import 'package:bruig/plugin_system/canvas/model/colour_map.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_styles.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/layout_presets.dart';
import 'package:bruig/plugin_system/canvas/model/page_style.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/table_presets.dart';
import 'package:bruig/plugin_system/canvas/presets/background_looks.dart';
import 'package:bruig/plugin_system/canvas/presets/builtin_element_presets.dart';
import 'package:bruig/plugin_system/canvas/presets/builtin_presets.dart';
import 'package:bruig/plugin_system/canvas/presets/image_looks.dart';
import 'package:bruig/plugin_system/canvas/presets/parallax_looks.dart';

import 'support/colour_rich.dart';
import 'support/element_samples.dart';

// canvas_colour_coverage_test.dart catches a colour that the colour visitor
// (mapColours, colour_map.dart) does not reach. Every colour of every sample,
// of the colour-rich fixture, of every built-in canvas and look, and (with
// CANVAS_LIBRARY naming a folder) of every canvas in that folder, is mapped
// to one sentinel; then the saved form is searched for whole numbers shaped
// like a colour (0x01000000 to 0xFFFFFFFF) that kept their old value.
//
// A failure means one of two things. Either a type's mapColours (for an
// element kind, its mapOwnColours) is missing a colour field: add it there.
// Or a new setting holds a number that large and is not a colour, or is a
// colour left alone on purpose: add a line to _notMapped with the reason.

/// _notMapped are where a colour-shaped number is known to stay as it is,
/// by the keys that lead to it (a pattern over the path's keys, list
/// positions left out), each with the reason.
const _notMapped = <String, String>{
  r"(^|/)cells$": "a tile map layer's cells, three numbers each: column, "
      "row and a word packing the tile set, the tile and its flips",
  r"(^|/)text/sig$": "a drawn text's signature: a hash of its runs, which "
      "says whether the shape is still those letters",
  r"(^|/)removal/key$": "a picture's background-removal key: it must match "
      "the picture's pixels, whatever the design's colours become",
  r"(^|/)key/color$": "a video's chroma key: it must match the footage's "
      "screen",
  r"(^|/)handle$": "a drawing's edit-handle colour: the editor's",
  r"(^|/)rowColour$": "an element's row on the timeline and mixer: the "
      "editor's",
  r"(^|/)rub/c$": "an eraser stroke's paint on a drawing: a mask, never "
      "seen",
  r"(^|/)terrains/terrains/color$": "a tile map terrain's swatch in its "
      "settings: the editor's, never drawn",
};

/// _Subject is a thing a canvas saves: its saved form, and its saved form
/// after its colours went through a map.
class _Subject {
  final String name;
  final Object? Function() json;
  final Object? Function(ColourMap f) mapped;
  _Subject(this.name, this.json, this.mapped);

  _Subject.element(String name, CanvasElement e)
      : this(name, () => e.toJson(), (f) => e.mapColours(f).toJson());

  _Subject.document(String name, CanvasDocument d)
      : this(name, () => d.toJson(), (f) => d.mapColours(f).toJson());

  _Subject.pattern(String name, ProceduralSpec s)
      : this(name, () => s.toJson(), (f) => s.mapColours(f).toJson());
}

/// _toSentinel makes every colour the sentinel's red, green and blue, each
/// keeping its opacity, so nothing is saved that was not before.
Color _toSentinel(Color c, {required bool shown}) =>
    Color((c.toARGB32() & 0xFF000000) | (colourSentinel.toARGB32() & 0xFFFFFF));

bool _colourShaped(Object? v) => v is int && v >= 0x01000000 && v <= 0xFFFFFFFF;

/// _kept hands [visit] every colour-shaped number in [now] that is as it
/// was in [was] at the same place, with the keys that lead to it.
void _kept(Object? was, Object? now, List<String> keys,
    void Function(String keys) visit) {
  if (was is Map && now is Map) {
    for (var e in now.entries) {
      if (was.containsKey(e.key)) {
        _kept(was[e.key], e.value, [...keys, "${e.key}"], visit);
      }
    }
  } else if (was is List && now is List && was.length == now.length) {
    for (var i = 0; i < now.length; i++) {
      _kept(was[i], now[i], keys, visit);
    }
  } else if (_colourShaped(now) &&
      now == was &&
      (now as int) & 0xFFFFFF != colourSentinel.toARGB32() & 0xFFFFFF) {
    visit(keys.join("/"));
  }
}

/// _unreached is every colour-shaped number in [subjects] that mapping
/// every colour left as it was and that is not on [_notMapped]; [known]
/// collects the patterns that excused one.
List<String> _unreached(List<_Subject> subjects, [Set<String>? known]) {
  var patterns = {for (var p in _notMapped.keys) p: RegExp(p)};
  var out = <String>[];
  for (var s in subjects) {
    _kept(s.json(), s.mapped(_toSentinel), const [], (keys) {
      for (var MapEntry(:key, :value) in patterns.entries) {
        if (value.hasMatch(keys)) {
          known?.add(key);
          return;
        }
      }
      out.add("${s.name}: $keys");
    });
  }
  return out;
}

// The subjects.

const _weeks = [
  ["Week", "Club", "Pts", "GD", "Won", "Drawn", "Lost"],
  ["1", "Arsenal", "3", "2", "1", "0", "0"],
  ["1", "Chelsea", "1", "0", "0", "1", "0"],
  ["2", "Arsenal", "6", "4", "2", "0", "0"],
  ["2", "Chelsea", "4", "1", "1", "1", "0"],
];

List<_Subject> _samples() => [
      for (var (name, e) in elementSamples()) _Subject.element(name, e),
      for (var (name, e) in filledSamples())
        _Subject.element("filled $name", e),
      for (var (name, e) in colourRichElements())
        _Subject.element("rich $name", e),
      _Subject.document("rich document", colourRichDocument()),
    ];

List<_Subject> _builtIn() {
  var sheet = const DataSheet(id: "s", cells: _weeks);
  var picks = picksOf(sheet, const CellRange(0, 0, 4, 6), [0, 1, 2, 3, 4, 5, 6],
      const [2, 3, 4, 5, 6], const [0], const [1]);
  const like = ChartElement(ElementBase(id: "c", width: 480, height: 300));
  const table =
      TableElement(ElementBase(id: "t", width: 600, height: 300), rows: [
    ["Club", "Form", "Live", "Cover", "Moved", "Trend", "Pts"],
    ["Arsenal", "W W D", "yes", "4", "+2", "3, 5, 8", "46"],
    ["Chelsea", "L W W", "no", "2", "-1", "4, 4, 6", "40"],
  ]);
  const picture = ImageElement(ElementBase(id: "p", width: 100, height: 100),
      assetId: "picture");
  const words =
      TextElement(ElementBase(id: "x", width: 400, height: 80), text: "Words");
  return [
    _Subject.document("empty document", const CanvasDocument()),
    for (var p in builtinPresets)
      _Subject.document("canvas ${p.id}", p.build()),
    for (var style in ProceduralStyle.values)
      for (var look in looksFor(style))
        _Subject.pattern("background ${style.name}: ${look.name}", look.spec),
    for (var look in parallaxLooks)
      _Subject.element("scenery ${look.name}", look.scenery),
    for (var look in builtInLooks)
      _Subject.element(
          "picture look ${look.name}", withLookApplied(picture, look.data)),
    for (var p in builtinElementPresets)
      _Subject.element("element preset ${p.name}", elementFromJson(p.element)),
    for (var k in chartKinds)
      for (var (i, p) in k.presets.indexed)
        if (presetChart(k, p, picks, like) case var chart?) ...[
          _Subject.element("chart ${k.name}: ${p.name}", chart),
          if (i == 0)
            for (var st in dataStyles)
              _Subject.element(
                  "chart ${k.name} in ${st.name}", chartInStyle(chart, st)),
        ],
    for (var k in tableKinds)
      for (var p in k.presets)
        _Subject.element("table ${k.name}: ${p.name}", presetTable(p, table)),
    for (var st in dataStyles) ...[
      _Subject.element("table in ${st.name}", tableInStyle(table, st)),
      _Subject.element("text in ${st.name}", textInStyle(words, st, 48)),
    ],
    for (var p in LayoutPreset.values)
      _Subject.element("layout ${p.name}",
          layoutFrom(const ElementBase(id: "l", width: 600, height: 400), p)),
  ];
}

/// _libraryRoot is the folder of canvases CANVAS_LIBRARY names, if any.
final String? _libraryRoot = switch (Platform.environment["CANVAS_LIBRARY"]) {
  var root? when root.isNotEmpty => root,
  _ => null,
};

List<_Subject> _library(String root) => [
      for (var f in Directory(root).listSync(recursive: true))
        if (f is File && f.path.endsWith(".bcanvas"))
          _Subject.document(
              "library ${f.path.substring(root.length)}",
              CanvasDocument.fromJson(
                  jsonDecode(f.readAsStringSync()) as Map<String, dynamic>)),
    ];

void main() {
  test("every colour of the samples and the colour-rich fixture is reached",
      () {
    var known = <String>{};
    expect(_unreached(_samples(), known), isEmpty);
    // Each line on the list is there for something the fixture holds; a
    // drawn text's signature is a hash, only some runs in a colour's range.
    expect(_notMapped.keys.toSet().difference(known),
        anyOf(isEmpty, {r"(^|/)text/sig$"}));
  });

  test("every colour of the built-in canvases and looks is reached", () {
    expect(_unreached(_builtIn()), isEmpty);
  });

  test("every colour of the canvases in CANVAS_LIBRARY is reached", () {
    expect(_unreached(_library(_libraryRoot!)), isEmpty);
  },
      skip: _libraryRoot == null
          ? "CANVAS_LIBRARY names no folder of canvases"
          : false);
}
