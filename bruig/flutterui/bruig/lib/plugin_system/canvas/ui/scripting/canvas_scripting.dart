import 'dart:convert';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as path;

import 'package:bruig/plugin_system/canvas/export/canvas_export.dart'
    as exporting;
import 'package:bruig/plugin_system/canvas/export/export_media.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/image_action_file.dart';
import 'package:bruig/plugin_system/canvas/model/image_steps.dart';
import 'package:bruig/plugin_system/canvas/model/image_steps.dart'
    as image_steps show imageReference;
import 'package:bruig/plugin_system/canvas/model/drawn_characters.dart';
import 'package:bruig/plugin_system/canvas/presets/drawn_styles.dart';
import 'package:bruig/plugin_system/canvas/presets/image_looks.dart';
import 'package:bruig/plugin_system/canvas/presets/builtin_presets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_network.dart';
import 'package:bruig/plugin_system/canvas/storage/element_preset_store.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_client.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_sources.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/asset_placing.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/stock_import.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/saved_preset_store.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';

// canvas_scripting.dart is the open canvas read and changed as JSON, for a
// program rather than a pointer: an assistant connected over MCP, a script.
//
// A method that can fail says so in words meant for whoever is driving it.
// One that only does something returns the problem, or null when it worked.
// One that also makes something returns a record with what it made and a
// `problem` field: null when it worked, and set beside a result when the
// thing was made but not everything asked for could be done.
//
// It is Canvas's own answer to "what is on the canvas and how do I change
// it", so whatever drives it needs to know no class of ours. Everything goes
// through the editing session (CanvasController), so a change made here is
// drawn, autosaved and taken back with Undo exactly as one made by hand.
//
// It leans on the document's reader. CanvasDocument.fromJson and
// elementFromJson never refuse and bound everything they read (see
// ARCHITECTURE.md), because a canvas can come from a stranger; JSON written
// by a program is held to the same rule, so nothing it sends can break the
// session -- at worst a field it got wrong falls back to its default.
//
// [describeKind] reads a kind's reader with a probe that records each key it
// asks for, so the list of settings an element understands is the code's own
// and can never fall behind it.

/// CanvasScripting reads and changes [controller]'s document as JSON.
class CanvasScripting {
  final CanvasController controller;
  CanvasScripting(this.controller);

  CanvasDocument get _doc => controller.document;

  /// overview is the canvas in brief: its file, size, scenes, the scene
  /// being edited with its elements in paint order, and what is selected.
  Map<String, Object?> overview() {
    var d = _doc;
    var scenes = d.allScenes;
    return {
      "title": d.title,
      "file": controller.name == null
          ? null
          : "${controller.folder ?? ""}/${controller.name}",
      "kind": d.kind.name,
      "width": d.size.width,
      "height": d.size.height,
      "frameRate": d.frameRate,
      "game": d.game,
      "scenes": [
        for (var i = 0; i < scenes.length; i++)
          {
            "index": i,
            "id": scenes[i].id,
            if (scenes[i].name.isNotEmpty) "name": scenes[i].name,
            "frames": scenes[i].frames,
            "elements": scenes[i].elements.length,
          }
      ],
      "scene": d.at,
      "frame": controller.frame,
      "frames": d.frames,
      "elements": [for (var e in d.elements) summary(e)],
      "selection": controller.selection.toList(),
      "canUndo": controller.canUndo,
    };
  }

  /// summary is one element in a line: what it is, where and how big.
  static Map<String, Object?> summary(CanvasElement e) => {
        "id": e.id,
        "kind": e.kind.name,
        "name": e.name,
        "x": _round(e.x),
        "y": _round(e.y),
        "width": _round(e.width),
        "height": _round(e.height),
        if (e.rotation != 0) "rotation": _round(e.rotation),
        if (!e.visible) "visible": false,
        if (e.locked) "locked": true,
        if (e.track != null) "animated": true,
      };

  static num _round(double v) =>
      v == v.roundToDouble() ? v.round() : (v * 100).round() / 100;

  /// presetsDir is the canvas library's presets folder, where a feature may
  /// keep presets of its own in a folder of its own.
  static Future<String> presetsDir() async =>
      path.join(await CanvasStorage.libraryDir(), presetsFolderName);

  /// kinds are the elements that can be added, by name.
  static List<Map<String, String>> kinds() => [
        for (var k in ElementKind.values)
          // Carried by a background, never added alone.
          if (k != ElementKind.stage && k != ElementKind.parallax)
            {"kind": k.name, "label": k.label}
      ];

  static ElementKind? kindNamed(String name) => ElementKind.fromName(name);

  // ------------------------------------------------------------------------
  // Elements
  // ------------------------------------------------------------------------

  /// sceneOf is the index of the scene holding element [id], or -1.
  int sceneOf(String id) {
    var scenes = _doc.allScenes;
    for (var i = 0; i < scenes.length; i++) {
      if (scenes[i].elements.any((e) => e.id == id)) return i;
    }
    return -1;
  }

  /// elementJson is element [id] as saved, from whichever scene holds it.
  Map<String, dynamic>? elementJson(String id) =>
      _doc.elementInAnyScene(id)?.toJson();

  /// newElementJson is a fresh [kind] as the Add panel makes it, centred on
  /// the canvas, ready to be changed before [addElementJson].
  Map<String, dynamic>? newElementJson(String kind) {
    var k = kindNamed(kind);
    if (k == null) return null;
    return newElement(k, _doc).toJson();
  }

  /// addElementJson puts the element [json] describes on the scene being
  /// edited, with an id of its own if it brings none or a taken one.
  /// Returns its id.
  String addElementJson(Map<String, dynamic> json, {bool select = false}) {
    var copy = Map<String, dynamic>.of(json);
    var id = copy["id"];
    if (id is! String || id.isEmpty || sceneOf(id) >= 0) {
      copy["id"] = newElementId();
    }
    var element = elementFromJson(copy);
    controller.addElement(element, select: select);
    return element.id;
  }

  /// replaceElementJson changes element [id] to what [json] describes,
  /// keeping its id and kind; it goes to the element's scene first. Returns
  /// an error, or null.
  String? replaceElementJson(String id, Map<String, dynamic> json) {
    var at = sceneOf(id);
    if (at < 0) return "There is no element $id.";
    if (at != _doc.at) controller.goToScene(at);
    var old = _doc.elementById(id);
    if (old == null) return "Element $id is not on the scene being edited.";
    var copy = Map<String, dynamic>.of(json)
      ..["id"] = id
      ..["kind"] = old.kind.name;
    controller.replaceElement(elementFromJson(copy));
    return null;
  }

  /// deleteElements takes out those of [ids] on the scene being edited.
  /// Returns how many went.
  int deleteElements(Iterable<String> ids) {
    var next = _doc;
    var gone = 0;
    for (var id in ids) {
      if (next.elementById(id) == null) continue;
      next = next.removeElement(id);
      gone++;
    }
    if (gone > 0) controller.apply(next);
    return gone;
  }

  /// reorder moves element [id] to place [to] in paint order (0 is the
  /// back).
  String? reorder(String id, int to) {
    var from = _doc.indexOf(id);
    if (from < 0) return "Element $id is not on the scene being edited.";
    controller.apply(
        _doc.reorder(from, to.clamp(0, _doc.elements.length - 1).toInt()));
    return null;
  }

  // ------------------------------------------------------------------------
  // The document and its scenes
  // ------------------------------------------------------------------------

  /// documentJson is the whole canvas as saved.
  Map<String, dynamic> documentJson() => _doc.toJson();

  /// replaceDocumentJson makes the canvas what [json] describes, as one
  /// step to undo.
  void replaceDocumentJson(Map<String, dynamic> json) =>
      controller.apply(CanvasDocument.fromJson(json));

  /// sceneJson is scene [index] as saved, its elements given in brief (they
  /// are read and changed one at a time). Null for no such scene.
  Map<String, dynamic>? sceneJson(int index) {
    var scenes = _doc.allScenes;
    if (index < 0 || index >= scenes.length) return null;
    var s = scenes[index];
    return {
      ...s.toJson(),
      "elements": [for (var e in s.elements) summary(e)],
    };
  }

  /// replaceSceneJson changes scene [index]'s own settings (name, length,
  /// transition, background...) to [json]'s; its elements stay as they are.
  String? replaceSceneJson(int index, Map<String, dynamic> json) {
    var scenes = [..._doc.allScenes];
    if (index < 0 || index >= scenes.length) return "There is no scene $index.";
    var old = scenes[index];
    var copy = Map<String, dynamic>.of(json)
      ..["id"] = old.id
      ..["elements"] = [for (var e in old.elements) e.toJson()];
    scenes[index] = CanvasScene.fromJson(copy);
    controller.apply(_doc.withScenes(scenes, at: _doc.at));
    return null;
  }

  /// addScene adds an empty scene after scene [after] (the one being edited
  /// if null) and goes to it. Returns its index.
  int addScene({int? after}) {
    if (after != null) controller.goToScene(after);
    controller.addScene();
    return _doc.at;
  }

  /// goTo shows scene [scene] at [frame], either left as it is when null.
  void goTo({int? scene, int? frame}) {
    if (scene != null) controller.goToScene(scene);
    if (frame != null) controller.frame = frame;
  }

  /// select picks out [ids] on the scene being edited; empty clears it.
  void select(Iterable<String> ids) {
    var on = {
      for (var id in ids)
        if (_doc.elementById(id) != null) id
    };
    if (on.isEmpty) {
      controller.clearSelection();
    } else if (on.length == 1) {
      controller.selectOnly(on.first);
    } else {
      controller.selectMany(on);
    }
  }

  // ------------------------------------------------------------------------
  // Undo, and changes made as one step
  // ------------------------------------------------------------------------

  /// begin and end make everything between them one step to undo.
  void begin() => controller.beginInteraction();
  void end() => controller.endInteraction();

  void undo() => controller.undo();
  void redo() => controller.redo();

  /// snapshot is the document now, to be put back with [restore].
  CanvasDocument snapshot() => _doc;

  /// restore puts [document] back as a new step, so it can itself be undone.
  void restore(CanvasDocument document) => controller.apply(document);

  // ------------------------------------------------------------------------
  // Seeing and hearing it
  // ------------------------------------------------------------------------

  /// renderPng draws scene [scene] (the one being edited if null) at
  /// [frame] (the playhead if null), its longer side at most [maxSide]
  /// pixels. Null if it could not be drawn.
  Future<Uint8List?> renderPng(
      {int? scene, int? frame, double maxSide = 1024}) async {
    var d = _doc;
    var at = (scene ?? d.at).clamp(0, d.allScenes.length - 1).toInt();
    var local = frame ?? (at == d.at ? controller.frame : 0);
    var sceneFrames = d.allScenes[at].frames;
    local = local.clamp(0, math.max(0, sceneFrames - 1)).toInt();
    var global = d.hasScenes ? d.startOfScene(at) + local : local;
    var shown = d.hasScenes ? d : d.goToScene(at);
    var size = d.size.exportSize;
    var longest = math.max(size.width, size.height);
    var scale = longest <= 0 ? 1.0 : math.min(1.0, maxSide / longest);
    var out = await exporting.renderPng(shown,
        frame: global, scale: scale, images: controller.images);
    return out?.data;
  }

  /// measureAudio is how loud the canvas's sound is, mixed as an export
  /// would mix it: integrated loudness (LUFS), range (LU) and true peak
  /// (dBTP). Null without ffmpeg or without sound.
  Future<Map<String, double>?> measureAudio() async {
    var l = await measureMix(_doc);
    if (l == null) return null;
    return {
      "integratedLufs": l.integrated,
      "rangeLu": l.range,
      "truePeakDbtp": l.truePeak,
    };
  }

  // ------------------------------------------------------------------------
  // The timeline's channels and speech
  // ------------------------------------------------------------------------

  /// channels are the timeline's channels: each one's key, name and the
  /// elements on it (a channel's mixer settings, its device chain and its
  /// Speech device are in its first element's "clip" > "mix").
  List<Map<String, Object?>> channels() => [
        for (var c in controller.timelineChannels)
          {
            "key": c.key,
            "name": c.name,
            "elements": [for (var l in c.lanes) l.element.id],
            if (c.video) "video": true,
            if (c.mix.speech != null) "speech": true,
          }
      ];

  /// speak makes takes of channel [key]'s Speech device for every line
  /// that has none yet, with the device's own voice. Returns why not, or
  /// null once the lines are queued.
  Future<String?> speak(String key) async {
    if (controller.speechOf(key) == null) {
      return "Channel $key has no Speech device: set one in its first "
          "element's clip > mix > speech.";
    }
    return controller.speakLines(key);
  }

  // ------------------------------------------------------------------------
  // The library: pictures, videos, sounds, drawings and 3D models
  // ------------------------------------------------------------------------

  static Map<String, Object?> _asset(LibraryAsset a) => {
        "id": a.id,
        "kind": a.kind.name,
        "name": a.name,
        if (a.width > 0) "width": a.width,
        if (a.height > 0) "height": a.height,
        if (a.length > 0) "seconds": (a.length * 100).round() / 100,
        if (a.author.isNotEmpty) "author": a.author,
        if (a.license.isNotEmpty) "license": a.license,
        if (a.from.isNotEmpty) "from": a.from,
      };

  /// assets are the library's files, of [kind] (picture, video, audio,
  /// vector, model) if given, matching [query] in their names if given.
  static Future<List<Map<String, Object?>>> assets(
      {String? kind, String query = ""}) async {
    var k = AssetKind.values.where((x) => x.name == kind).firstOrNull;
    var q = query.trim().toLowerCase();
    return [
      for (var a in await CanvasLibrary.list(kind: k))
        if (q.isEmpty || a.name.toLowerCase().contains(q)) _asset(a)
    ];
  }

  /// useAsset puts library file [id] on the scene being edited, as the
  /// Assets panel does when one is clicked (a MIDI file becomes a MIDI
  /// channel, which has no element). Returns the new element's id.
  Future<({String? element, String? problem})> useAsset(String id) async {
    var asset =
        (await CanvasLibrary.list()).where((a) => a.id == id).firstOrNull;
    if (asset == null) {
      return (element: null, problem: "There is no file $id in the library.");
    }
    var element = await placeAsset(controller, asset, select: false);
    return (element: element, problem: null);
  }

  /// addSvg keeps [svg] in the library as a drawing called [name] and,
  /// when [place], puts it on the scene being edited as a Vector element.
  /// Refused if it is not an SVG, is too large, or carries a script or
  /// outside content. Returns its id in the library and the element's.
  Future<({String? asset, String? element, String? problem})> addSvg(
      String name, String svg,
      {bool place = true}) async {
    ({String? asset, String? element, String? problem}) refused(String why) =>
        (asset: null, element: null, problem: why);
    var text = svg.trim();
    var lower = text.toLowerCase();
    if (!lower.contains("<svg")) return refused("That is not an SVG.");
    if (lower.contains("<script") ||
        lower.contains("<foreignobject") ||
        RegExp(r"""(href|src)\s*=\s*["']\s*(https?:|file:|//)""")
            .hasMatch(lower)) {
      return refused(
          "An SVG drawn for a canvas has no scripts, embedded pages or links "
          "to outside files: draw everything in it.");
    }
    var id = await CanvasMedia.saveVector(utf8.encode(text));
    if (id == null) return refused("That drawing is too large.");
    await CanvasLibrary.addVector(id, name.trim().isEmpty ? "Drawing" : name);
    if (!place) return (asset: id, element: null, problem: null);
    var placed = await useAsset(id);
    return (asset: id, element: placed.element, problem: placed.problem);
  }

  // ------------------------------------------------------------------------
  // Drawn characters
  // ------------------------------------------------------------------------

  /// drawnStyles are the styles characters are drawn in: each one's parts
  /// with their choices (and whether one may be left out), and colours with
  /// their palettes.
  static Future<List<Map<String, Object?>>> drawnStyles() async => [
        for (var s in (await DrawnStyles.load()).values)
          {
            "style": s.id,
            "title": s.title,
            "by": s.creator,
            "licence": s.licence,
            "parts": {
              for (var g in s.groups)
                g: {
                  "choices": s.choices(g),
                  if (s.optional(g)) "mayBeNone": true,
                }
            },
            "colours": {
              for (var c in s.colours)
                if (s.palette(c).isNotEmpty) c: s.palette(c)
            },
          }
      ];

  /// drawCharacter draws a character in [style] -- [seed]'s, or a fresh
  /// one's, with [parts] and [colours] as given (a part null for none) --
  /// keeps it with the drawings, and puts it on the scene being edited.
  /// Returns the element's id; a problem beside an id is a part or colour
  /// left as it was.
  Future<({String? element, String? problem})> drawCharacter(String style,
      {Map<String, Object?> parts = const {},
      Map<String, Object?> colours = const {},
      int? seed,
      String name = ""}) async {
    var s = (await DrawnStyles.load())[style];
    if (s == null) {
      return (element: null, problem: "There is no style $style.");
    }
    var character =
        randomCharacter(s, math.Random(seed ?? DateTime.now().microsecond));
    var left = <String>[];
    for (var e in parts.entries) {
      if (!s.groups.contains(e.key)) {
        left.add("no part ${e.key}");
      } else if (e.value == null && s.optional(e.key)) {
        character = character.withPart(e.key, null);
      } else if (s.choices(e.key).contains(e.value)) {
        character = character.withPart(e.key, "${e.value}");
      } else {
        left.add("${e.key} has no ${e.value}");
      }
    }
    for (var e in colours.entries) {
      var hex = "${e.value}".replaceFirst("#", "").toLowerCase();
      if (!s.colours.contains(e.key)) {
        left.add("no colour ${e.key}");
      } else if (RegExp(r"^[0-9a-f]{6}$").hasMatch(hex) ||
          hex == "transparent") {
        character = character.withColour(e.key, hex);
      } else {
        left.add("${e.value} is not a colour");
      }
    }
    var id = await keepDrawnCharacter(s, character, name);
    if (id == null) {
      return (element: null, problem: "The character could not be kept.");
    }
    var placed = await useAsset(id);
    var said =
        [if (placed.problem != null) placed.problem!, ...left].join("; ");
    return (element: placed.element, problem: said.isEmpty ? null : said);
  }

  // ------------------------------------------------------------------------
  // Pictures' actions
  // ------------------------------------------------------------------------

  /// imageActions are the actions a picture can be given: the app's and
  /// the person's, each with its steps.
  static Future<List<Map<String, Object?>>> imageActions() async {
    await SavedPresetStore.looks.load();
    return [
      for (var p in [...builtInLooks, ...SavedPresetStore.looks.presets])
        {
          "id": p.id,
          "name": p.name,
          if (p.id.startsWith(builtInLookPrefix)) "builtIn": true,
          "steps": lookStepNames(p.data),
        }
    ];
  }

  /// imageReference is every step an action can hold (see image_steps.dart).
  static Map<String, Object?> imageReference() => image_steps.imageReference();

  /// _picture is image element [id], brought to its scene, or why not.
  ({ImageElement? picture, String? problem}) _picture(String id) {
    var at = sceneOf(id);
    if (at < 0) return (picture: null, problem: "There is no element $id.");
    if (at != _doc.at) controller.goToScene(at);
    var e = _doc.elementById(id);
    if (e is! ImageElement) {
      return (picture: null, problem: "Element $id is not a picture.");
    }
    return (picture: e, problem: null);
  }

  /// imageLayers are picture [id]'s layers, top first: each one's id, kind,
  /// and name as a step, and whether an action would keep it.
  Map<String, Object?>? imageLayers(String id) {
    var e = _doc.elementInAnyScene(id);
    if (e is! ImageElement) return null;
    return {
      "picture": e.assetId,
      "layers": [
        for (var l in e.stack.reversed)
          {
            "id": l.id,
            "kind": l.kind.name,
            "step": l.isBase ? "the picture" : stepLabel(e, l),
            if (inLook(e, l)) "inAction": true,
            if (l.blend != LayerBlend.normal) "blend": l.blend.name,
            if (l.opacity != 1) "opacity": l.opacity,
            if (l.clip) "clip": true,
            if (l.effects.isNotEmpty)
              "effects": [for (var f in l.effects) f.kind.name],
          }
      ],
    };
  }

  /// doImageAction does action [action] (as imageActions lists it) to
  /// picture [id]: added to what it has, or [replace]ing its look.
  Future<String?> doImageAction(String id, String action,
      {bool replace = false}) async {
    await SavedPresetStore.looks.load();
    var p = [...builtInLooks, ...SavedPresetStore.looks.presets]
        .where((p) => p.id == action || p.name == action)
        .firstOrNull;
    if (p == null) return "There is no action $action.";
    var (:picture, :problem) = _picture(id);
    if (picture == null) return problem;
    controller
        .replaceElement(withLookApplied(picture, p.data, replace: replace));
    return null;
  }

  /// addImageSteps does [steps] (see imageStepsFrom) to picture [id], added
  /// to what it has or [replace]ing its look. Returns how many steps were
  /// made and why each of the others was skipped; the problem is why none
  /// was made.
  ({int made, List<String> skipped, String? problem}) addImageSteps(
      String id, Object? steps,
      {bool replace = false}) {
    var read = imageStepsFrom(steps);
    if (read.count == 0) {
      return (
        made: 0,
        skipped: read.problems,
        problem: "None of the steps could be made."
      );
    }
    var (:picture, :problem) = _picture(id);
    if (picture == null) {
      return (made: 0, skipped: read.problems, problem: problem);
    }
    controller
        .replaceElement(withLookApplied(picture, read.data, replace: replace));
    return (made: read.count, skipped: read.problems, problem: null);
  }

  /// saveImageAction keeps picture [id]'s look as the action [name]: the
  /// layers [layers] names, or every one an action keeps. Returns the
  /// action's id.
  Future<({String? action, String? problem})> saveImageAction(
      String id, String name,
      {List<String>? layers}) async {
    var e = _doc.elementInAnyScene(id);
    if (e is! ImageElement) {
      return (action: null, problem: "Element $id is not a picture.");
    }
    var data = lookData(e, only: layers?.toSet());
    if (lookSteps(data) == 0) {
      return (action: null, problem: "That picture has no steps yet.");
    }
    var store = SavedPresetStore.looks;
    await store.load();
    for (var p in store.presets.where((p) => p.name == name.trim()).toList()) {
      await store.remove(p);
    }
    var kept = await store.save(name, data);
    return kept == null
        ? (action: null, problem: "Could not save it.")
        : (action: kept.id, problem: null);
  }

  // ------------------------------------------------------------------------
  // Presets
  // ------------------------------------------------------------------------

  /// presets are what can be started from: elements (built in and saved),
  /// saved scenes, and canvases (built in and saved), matching [query].
  static Future<List<Map<String, Object?>>> presets({String query = ""}) async {
    await ElementPresetStore.instance.load();
    await SavedPresetStore.scenes.load();
    await SavedPresetStore.canvases.load();
    var q = query.trim().toLowerCase();
    bool shows(String name) => q.isEmpty || name.toLowerCase().contains(q);
    return [
      for (var p in ElementPresetStore.instance.presets)
        if (shows(p.name))
          {
            "id": "element:${p.id}",
            "name": p.name,
            "kind": p.kind.name,
            if (p.builtIn) "builtIn": true,
          },
      for (var p in SavedPresetStore.scenes.presets)
        if (shows(p.name)) {"id": "scene:${p.id}", "name": p.name},
      for (var p in builtinPresets)
        if (shows(p.label))
          {
            "id": "canvas:${p.id}",
            "name": p.label,
            "about": p.description,
            "builtIn": true,
          },
      for (var p in SavedPresetStore.canvases.presets)
        if (shows(p.name)) {"id": "canvas:${p.id}", "name": p.name},
    ];
  }

  /// usePreset adds preset [id] (as [presets] names it) to the open canvas:
  /// an element on the scene being edited, or a scene's or a canvas's
  /// scenes after it. Returns what was added, in words.
  Future<({String? added, String? problem})> usePreset(String id) async {
    var page = _doc.size.size;
    var colon = id.indexOf(":");
    var kind = colon < 0 ? "" : id.substring(0, colon);
    var key = colon < 0 ? id : id.substring(colon + 1);
    switch (kind) {
      case "element":
        await ElementPresetStore.instance.load();
        var p = ElementPresetStore.instance.presets
            .where((x) => x.id == key)
            .firstOrNull;
        if (p == null) break;
        var e = p.buildFor(page);
        controller.addElement(e, select: false);
        return (added: "element ${e.id}", problem: null);
      case "scene" || "canvas":
        var store = kind == "scene"
            ? SavedPresetStore.scenes
            : SavedPresetStore.canvases;
        await store.load();
        var saved = store.presets.where((x) => x.id == key).firstOrNull;
        List<CanvasScene>? scenes = saved?.buildScenes(on: page);
        if (scenes == null && kind == "canvas") {
          var builtIn = builtinPresets.where((x) => x.id == key).firstOrNull;
          scenes = builtIn?.build().allScenes;
        }
        if (scenes == null || scenes.isEmpty) break;
        controller.addScenes(scenes);
        return (
          added: "${scenes.length} scene${scenes.length == 1 ? "" : "s"}",
          problem: null
        );
    }
    return (added: null, problem: "There is no preset $id: list them first.");
  }

  // ------------------------------------------------------------------------
  // Stock libraries
  // ------------------------------------------------------------------------

  /// _found are stock results by "source:id", from the last searches, so
  /// one can be used by its id. Only the latest [_foundKept] are kept.
  static final Map<String, StockItem> _found = {};
  static const _foundKept = 500;

  /// stockSources are the stock libraries, and whether a key is given for
  /// each (one is needed; they are added in Canvas's Stock panel).
  static Future<List<Map<String, Object?>>> stockSources() async => [
        for (var s in StockSource.values)
          {
            "source": s.name,
            "label": s.label,
            "kind": s.kind.name,
            "ready": await StockKeys.has(s),
          }
      ];

  /// stockSearch searches stock library [source] for [text]. Refused while
  /// [allowFetching] is off (Canvas's own setting) or behind a proxy.
  static Future<Map<String, Object?>> stockSearch(String source, String text,
      {int page = 1, required bool allowFetching}) async {
    var s = StockSource.values.where((x) => x.name == source).firstOrNull;
    if (s == null) return {"problem": "There is no stock library $source."};
    var result = await StockClient.instance.search(
        StockQuery(s, text: text, page: page),
        allowFetching: allowFetching,
        proxied: await networkIsProxied());
    if (result.problem != null) return {"problem": result.problem};
    for (var i in result.items) {
      var id = "${s.name}:${i.id}";
      // Put in again at the end, so the oldest results are the ones dropped.
      _found.remove(id);
      _found[id] = i;
    }
    while (_found.length > _foundKept) {
      _found.remove(_found.keys.first);
    }
    return {
      "results": [
        for (var i in result.items)
          {
            "id": "${s.name}:${i.id}",
            "title": i.title,
            if (i.author.isNotEmpty) "author": i.author,
            if (i.license.isNotEmpty) "license": i.license,
            if (i.width > 0) "width": i.width,
            if (i.height > 0) "height": i.height,
            if (i.length > 0) "seconds": i.length,
            if (i.thumb.isNotEmpty) "thumb": i.thumb,
          }
      ],
      "more": result.more,
    };
  }

  /// stockUse fetches result [id] (from a search) into the library, with
  /// its author and licence, and puts it on the canvas when [place].
  /// Returns the library file as [assets] lists one, with the element's id
  /// when it was placed; and with it, a notice that came with the file and
  /// is to be passed on to whoever asked (NASA's rules for its pictures, a
  /// model's warning), null when there is none.
  Future<({Map<String, Object?>? asset, String? problem, String? notice})>
      stockUse(String id,
          {bool place = true, required bool allowFetching}) async {
    var item = _found[id];
    if (item == null) {
      return (
        asset: null,
        problem: "Search for it first: $id is not among the results.",
        notice: null,
      );
    }
    var (:asset, :problem, :notice) = await importStockItem(item,
        allowFetching: allowFetching, proxied: await networkIsProxied());
    if (asset == null) {
      return (
        asset: null,
        problem: problem ?? "It could not be added.",
        notice: null,
      );
    }
    var out = _asset(asset);
    if (place) {
      var placed = await useAsset(asset.id);
      if (placed.problem != null) {
        return (asset: out, problem: placed.problem, notice: notice);
      }
      if (placed.element != null) out["element"] = placed.element;
    }
    return (asset: out, problem: null, notice: notice);
  }

  // ------------------------------------------------------------------------
  // Describing what can be set
  // ------------------------------------------------------------------------

  /// describeKind is what a [kind] element understands: a fresh one as
  /// saved, and every key its reader asks for, nested. A key whose value is
  /// null was asked for but is left out while it holds its default.
  Map<String, Object?>? describeKind(String kind, {int depth = 4}) {
    var json = newElementJson(kind);
    if (json == null) return null;
    var probe = _KeyProbe(json, depth);
    try {
      elementFromJson(probe);
    } catch (_) {
      // The reader never throws on a wrong type; a probe is one, so this
      // is belt and braces.
    }
    return {
      "kind": kind,
      "label": kindNamed(kind)!.label,
      "example": json,
      "keys": probe.tree(),
    };
  }

  /// describeDocument is every key the document's reader asks for at the
  /// top: the parts (mix, audio, session, sheets...) and what each holds.
  Map<String, Object?> describeDocument({int depth = 3}) {
    var json = _doc.toJson()
      ..remove("elements")
      ..remove("scenes");
    var probe = _KeyProbe(json, depth, skip: const {"elements", "scenes"});
    try {
      CanvasDocument.fromJson(probe);
    } catch (_) {}
    return probe.tree();
  }
}

/// _KeyProbe is a map that records every key read from it, answering from
/// [seed] where it can and with another probe where it cannot, so a reader
/// asking after a nested setting shows that setting's keys too.
class _KeyProbe extends MapBase<String, dynamic> {
  final Map<String, dynamic> seed;
  final int depth;
  final Set<String> skip;
  final Map<String, _KeyProbe> _children = {};
  final Set<String> _asked = {};

  _KeyProbe(this.seed, this.depth, {this.skip = const {}});

  @override
  dynamic operator [](Object? key) {
    if (key is! String) return null;
    _asked.add(key);
    if (skip.contains(key)) return null;
    var v = seed[key];
    if (v is Map<String, dynamic>) {
      return depth > 0
          ? _children.putIfAbsent(key, () => _KeyProbe(v, depth - 1))
          : v;
    }
    if (v != null) return v;
    if (depth <= 0) return null;
    return _children.putIfAbsent(
        key, () => _KeyProbe(const <String, dynamic>{}, depth - 1));
  }

  @override
  bool containsKey(Object? key) {
    if (key is String) _asked.add(key);
    return seed.containsKey(key);
  }

  @override
  void operator []=(String key, dynamic value) {}

  @override
  void clear() {}

  @override
  Iterable<String> get keys => seed.keys;

  @override
  dynamic remove(Object? key) => null;

  /// tree is what was asked for: a key with a child that was itself read
  /// holds that child's tree; one present in the seed holds its value;
  /// anything else holds null.
  Map<String, Object?> tree() {
    var out = <String, Object?>{};
    for (var k in _asked.toList()..sort()) {
      var child = _children[k];
      if (child != null && child._asked.isNotEmpty) {
        out[k] = child.tree();
      } else {
        out[k] = seed[k];
      }
    }
    return out;
  }
}
