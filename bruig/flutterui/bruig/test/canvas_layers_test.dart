import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// canvas_layers_test.dart holds the Canvas to the import rules in its
// ARCHITECTURE.md ("Layers"), which are what let a person read one folder
// without knowing the rest: the document knows nothing of drawing, drawing
// knows nothing of widgets, and the app outside reaches the Canvas through
// canvas.dart alone.

const _canvas = "lib/plugin_system/canvas";
const _package = "package:bruig/plugin_system/canvas/";

/// _mayImport is the Canvas folders each folder may import from, besides
/// itself. ui/ may import them all.
const _mayImport = <String, List<String>>{
  "model": [],
  "storage": ["model"],
  "presets": ["model"],
  "render": ["model", "storage"],
  "media": ["model", "storage"],
  "export": ["model", "render", "media", "storage"],
};

/// _noWidgets is the folders that must not import Flutter's widget
/// libraries, so that what is exported is drawn by the code that drew it on
/// screen, whatever the theme.
const _noWidgets = ["model", "storage", "presets", "render", "media", "export"];

const _widgetLibraries = [
  "package:flutter/material.dart",
  "package:flutter/widgets.dart",
  "package:flutter/cupertino.dart",
];

/// _exceptions is the imports that break a rule today, each a debt to pay
/// off. An import is added here only with a reason; one that no longer
/// breaks its rule fails the last test until it is taken out.
const _exceptions = <String>{
  // The film colour tables are data a picture's look is read with, kept
  // with the presets.
  "$_canvas/model/image_steps.dart: ${_package}presets/film_tables.dart",
  "$_canvas/render/adjust_painter.dart: ${_package}presets/film_tables.dart",
  // VectorCanvas is a drawing surface the painters draw to, kept with the
  // export that reads it back.
  "$_canvas/render/chart_cartesian.dart: ${_package}export/vector_canvas.dart",
  "$_canvas/render/chart_notes.dart: ${_package}export/vector_canvas.dart",
  "$_canvas/render/chart_painter.dart: ${_package}export/vector_canvas.dart",
  "$_canvas/render/paint_util.dart: ${_package}export/vector_canvas.dart",
  "$_canvas/render/play_task_painter.dart: "
      "${_package}export/vector_canvas.dart",
  // The stock packs cut tiles and sprites with the painters' own code.
  "$_canvas/storage/stock/kenney_tiles.dart: ${_package}render/tile_terrain.dart",
  "$_canvas/storage/stock/kenney_packs.dart: "
      "${_package}render/sprite_pixels.dart",
  // The preset store lists the built-in presets with the saved ones.
  "$_canvas/storage/element_preset_store.dart: "
      "${_package}presets/builtin_element_presets.dart",
  // Built-in presets that read the library, draw a pitch, or name a
  // Material colour.
  "$_canvas/presets/drawn_styles.dart: ${_package}storage/canvas_library.dart",
  "$_canvas/presets/drawn_styles.dart: ${_package}storage/canvas_media.dart",
  "$_canvas/presets/builtin_presets.dart: ${_package}render/procedural/pitch.dart",
  "$_canvas/presets/builtin_presets.dart: package:flutter/material.dart",
  // The code runners: the host is handed the controller, and the Dart
  // runner builds a widget.
  "$_canvas/media/code_run_host.dart: ${_package}ui/canvas_controller.dart",
  "$_canvas/media/code_dart_runner.dart: package:flutter/widgets.dart",
  // A character asks the preferences whether it may fetch its hair.
  "$_canvas/render/vrm/vrm_character.dart: ${_package}canvas_preferences.dart",
  // The live engine borrows a helper from the video export.
  "$_canvas/media/mix/dart_audio_engine.dart: "
      "${_package}export/video_export.dart",
};

/// _importsOf is the URI of each import and export in [file].
Iterable<String> _importsOf(File file) sync* {
  var directive = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''');
  for (var line in file.readAsLinesSync()) {
    var uri = directive.firstMatch(line)?.group(1);
    if (uri != null) yield uri;
  }
}

List<File> _dartFilesIn(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith(".dart"))
    .toList();

/// _folderOf is the Canvas folder a canvas import [uri] points into, or
/// null for a file outside the Canvas. A file at the top of the Canvas
/// (canvas.dart, the preferences) is in "top": those import ui/, so nothing
/// beneath ui/ may import them.
String? _folderOf(String uri) {
  if (!uri.startsWith(_package)) return null;
  var rest = uri.substring(_package.length);
  return rest.contains("/") ? rest.split("/").first : "top";
}

/// _broken is each import that breaks a layer rule, as "file: uri".
List<String> _broken() {
  var found = <String>[];
  for (var folder in _mayImport.keys) {
    var allowed = {folder, ..._mayImport[folder]!};
    for (var file in _dartFilesIn("$_canvas/$folder")) {
      for (var uri in _importsOf(file)) {
        var into = _folderOf(uri);
        var wrongFolder = into != null && !allowed.contains(into);
        var widgets =
            _noWidgets.contains(folder) && _widgetLibraries.contains(uri);
        if (wrongFolder || widgets) found.add("${file.path}: $uri");
      }
    }
  }
  return found;
}

void main() {
  test("each Canvas folder imports only the folders beneath it", () {
    var offenders = _broken().where((b) => !_exceptions.contains(b)).toList();
    expect(offenders, isEmpty,
        reason: "see Layers in $_canvas/ARCHITECTURE.md:\n"
            "${offenders.join("\n")}");
  });

  test("the app outside reaches the Canvas through canvas.dart alone", () {
    // Creative AI is the one feature built on the Canvas; it too comes in
    // through canvas.dart (see plugin_system_layering_test.dart for which
    // feature may import which).
    var offenders = <String>[];
    for (var file in _dartFilesIn("lib")) {
      if (file.path.startsWith("$_canvas/")) continue;
      for (var uri in _importsOf(file)) {
        if (uri.startsWith(_package) && uri != "${_package}canvas.dart") {
          offenders.add("${file.path}: $uri");
        }
      }
    }
    expect(offenders, isEmpty,
        reason: "import ${_package}canvas.dart, and export from it what is "
            "missing:\n${offenders.join("\n")}");
  });

  test("the controls do not import the panels built from them", () {
    // ui/controls.dart is the kit; ui/settings/ is built from it. When the
    // kit imported the panel kit too, neither could be read alone.
    var offenders = [
      for (var uri in _importsOf(File("$_canvas/ui/controls.dart")))
        if (uri.startsWith("${_package}ui/settings/")) uri,
    ];
    expect(offenders, isEmpty);
  });

  test("the stage's own libraries do not import the stage", () {
    // The keys, the hit test, the picked parts, the view and its scrolling,
    // what is edited in place, the rulers, what the painter draws from and
    // each subject of its drawing are read by the stage; when one of them
    // imported the stage back, neither could be read or changed alone.
    var own = [
      "ui/stage/stage_keys.dart",
      "ui/stage/stage_hit_test.dart",
      "ui/stage/picked_parts.dart",
      "ui/stage/stage_transform.dart",
      "ui/stage/stage_scroll.dart",
      "ui/stage/in_place_edit.dart",
      "ui/stage/stage_rulers.dart",
      "ui/stage/stage_painter_inputs.dart",
      "ui/stage/stage_paint_kit.dart",
      "ui/stage/stage_paint_page.dart",
      "ui/stage/stage_paint_selection.dart",
      "ui/stage/stage_paint_elements.dart",
      "ui/stage/stage_paint_tools.dart",
      "ui/stage/stage_paint_retouch.dart",
      "ui/stage/stage_paint_guides.dart",
    ];
    var offenders = [
      for (var path in own)
        if (File("$_canvas/$path").existsSync())
          for (var uri in _importsOf(File("$_canvas/$path")))
            if (uri == "${_package}ui/stage/canvas_stage.dart") "$path: $uri",
    ];
    expect(offenders, isEmpty);
    for (var path in own) {
      expect(File("$_canvas/$path").existsSync(), isTrue,
          reason: "$path moved; update this test");
    }
  });

  test("every exception is still needed, and the folders are still there", () {
    var broken = _broken().toSet();
    expect(_exceptions.difference(broken), isEmpty,
        reason: "these no longer break a rule; take them out of _exceptions");
    for (var folder in [..._mayImport.keys, "ui"]) {
      expect(Directory("$_canvas/$folder").existsSync(), isTrue,
          reason: "$folder moved; update this test and ARCHITECTURE.md");
    }
  });
}
