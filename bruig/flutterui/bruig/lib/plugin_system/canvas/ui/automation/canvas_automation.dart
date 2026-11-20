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
import 'package:bruig/plugin_system/canvas/presets/builtin_presets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_network.dart';
import 'package:bruig/plugin_system/canvas/storage/element_preset_store.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_client.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_sources.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/asset_elements.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/stock_import.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/saved_preset_store.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';

// canvas_automation.dart is the open canvas read and changed as JSON, for a
// program rather than a pointer: an assistant connected over MCP, a script.
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

/// CanvasAutomation works on [controller]'s document.
class CanvasAutomation {
  final CanvasController controller;
  CanvasAutomation(this.controller);

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

  static ElementKind? kindNamed(String name) =>
      ElementKind.values.where((k) => k.name == name).firstOrNull;

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
  Map<String, dynamic>? elementJson(String id) {
    for (var s in _doc.allScenes) {
      for (var e in s.elements) {
        if (e.id == id) return e.toJson();
      }
    }
    return null;
  }

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
  /// channel). Returns the new element's id, or an error.
  Future<(String?, String?)> useAsset(String id) async {
    var asset =
        (await CanvasLibrary.list()).where((a) => a.id == id).firstOrNull;
    if (asset == null) return (null, "There is no file $id in the library.");
    if (isMidiId(asset.id)) {
      await controller.addMidiChannelFrom(asset.source);
      return (null, null);
    }
    var element = elementForAsset(asset, _doc);
    controller.addElement(element, select: false);
    return (element.id, null);
  }

  /// addSvg keeps [svg] in the library as a drawing called [name] and,
  /// when [place], puts it on the scene being edited as a Vector element.
  /// Refused if it is not an SVG, is too large, or carries a script or
  /// outside content. Returns (library id, element id), or an error.
  Future<(String?, String?, String?)> addSvg(String name, String svg,
      {bool place = true}) async {
    var text = svg.trim();
    var lower = text.toLowerCase();
    if (!lower.contains("<svg")) return (null, null, "That is not an SVG.");
    if (lower.contains("<script") ||
        lower.contains("<foreignobject") ||
        RegExp(r"""(href|src)\s*=\s*["']\s*(https?:|file:|//)""")
            .hasMatch(lower)) {
      return (
        null,
        null,
        "An SVG drawn for a canvas has no scripts, embedded pages or links "
            "to outside files: draw everything in it."
      );
    }
    var id = await CanvasMedia.saveVector(utf8.encode(text));
    if (id == null) return (null, null, "That drawing is too large.");
    await CanvasLibrary.addVector(id, name.trim().isEmpty ? "Drawing" : name);
    if (!place) return (id, null, null);
    var (element, problem) = await useAsset(id);
    return (id, element, problem);
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
  /// scenes after it. Returns what was added, or an error.
  Future<(String?, String?)> usePreset(String id) async {
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
        return ("element ${e.id}", null);
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
        return ("${scenes.length} scene${scenes.length == 1 ? "" : "s"}", null);
    }
    return (null, "There is no preset $id: list them first.");
  }

  // ------------------------------------------------------------------------
  // Stock libraries
  // ------------------------------------------------------------------------

  /// _found are stock results by "source:id", from the last searches, so
  /// one can be used by its id.
  static final Map<String, StockItem> _found = {};

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
      _found["${s.name}:${i.id}"] = i;
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
  /// Returns the library file, or an error.
  Future<(Map<String, Object?>?, String?)> stockUse(String id,
      {bool place = true, required bool allowFetching}) async {
    var item = _found[id];
    if (item == null) {
      return (null, "Search for it first: $id is not among the results.");
    }
    var (asset, problem) = await importStockItem(item,
        allowFetching: allowFetching, proxied: await networkIsProxied());
    if (asset == null) return (null, problem ?? "It could not be added.");
    var out = _asset(asset);
    if (place) {
      var (element, why) = await useAsset(asset.id);
      if (why != null) return (out, why);
      if (element != null) out["element"] = element;
    }
    return (out, null);
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
