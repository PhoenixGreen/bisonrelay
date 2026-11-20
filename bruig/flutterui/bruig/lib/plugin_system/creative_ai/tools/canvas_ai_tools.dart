import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/canvas.dart';
import 'package:bruig/plugin_system/creative_ai/creative_ai_model.dart';
import 'package:bruig/plugin_system/creative_ai/engine/json_edit.dart';
import 'package:bruig/plugin_system/creative_ai/mcp/mcp_server.dart';

// canvas_ai_tools.dart is the Canvas tools Claude is given: a small set over
// CanvasAutomation, which reads and changes the open canvas as JSON. A few
// general tools rather than one per control: the controller has hundreds of
// methods, and the saved format already says everything a canvas is.
//
// Every call that changes the canvas is one step of the person's Undo, and
// the first change since they last pressed Keep saves a copy of the canvas
// so the sidebar can put all of Claude's work back at once.

Map<String, Object?> _object(Map<String, Object?> properties,
        {List<String> required = const []}) =>
    {
      "type": "object",
      "properties": properties,
      if (required.isNotEmpty) "required": required,
    };

const _target = {
  "type": "string",
  "description": 'An element\'s id, "scene:<index>" (or "scene" for the one '
      'being edited), or "document" for the canvas as a whole.',
};

const _editProps = {
  "patch": {
    "type": "object",
    "description": "A JSON merge patch: keys to set, objects merged in, "
        "null to remove a key.",
  },
  "set": {
    "type": "array",
    "description": 'Values put at JSON Pointer paths, e.g. {"path": '
        '"/track/keys/1/o", "value": 0.5}; "-" appends to a list.',
    "items": {
      "type": "object",
      "properties": {
        "path": {"type": "string"},
        "value": {},
      },
      "required": ["path", "value"],
    },
  },
  "remove": {
    "type": "array",
    "description": "JSON Pointer paths to take out.",
    "items": {"type": "string"},
  },
};

List<McpTool> canvasAiTools(CreativeAi ai) {
  bool on() => ai.canvasOn;
  CanvasAutomation auto() => ai.automation;

  /// changing runs [body] as one step to undo, after keeping the canvas
  /// from before Claude started.
  Future<McpResult> changing(
      Future<McpResult> Function(CanvasAutomation a) body) async {
    var a = auto();
    ai.beforeCanvasChange();
    a.begin();
    try {
      return await body(a);
    } finally {
      a.end();
    }
  }

  McpTool tool(
          String name,
          String title,
          String description,
          Map<String, Object?> schema,
          Future<McpResult> Function(Map<String, dynamic> args) run) =>
      McpTool(
        name: name,
        title: title,
        description: description,
        inputSchema: schema,
        area: "canvas",
        available: on,
        run: (args, caller) => run(args),
      );

  return [
    tool(
      "canvas_overview",
      "Canvas overview",
      "The open canvas in brief: its size, frame rate, scenes, the scene "
          "being edited with every element (id, kind, name, place, size) in "
          "paint order (first is at the back), and what is selected. Start "
          "here.",
      _object({}),
      (args) async =>
          McpResult.json(auto().overview(), summary: "Looked at the canvas"),
    ),
    tool(
      "canvas_describe",
      "Describe an element kind",
      "With no kind: the kinds of element that can be added, and the "
          "document's own parts. With a kind: a fresh one as saved "
          "(\"example\") and every key that kind understands (\"keys\", "
          "nested; null means understood but left at its default). Use path "
          "to look inside one part, e.g. \"/textSpec\" or \"/animation\".",
      _object({
        "kind": {
          "type": "string",
          "description": "An element kind, e.g. text."
        },
        "path": {
          "type": "string",
          "description": "A JSON Pointer into the keys, to see one part."
        },
        "document": {
          "type": "boolean",
          "description": "Describe the document's parts instead (masterMix, "
              "audio, session, sheets, size...)."
        },
      }),
      (args) async {
        var a = auto();
        Object? keys;
        Map<String, Object?> out;
        if (args["document"] == true) {
          keys = a.describeDocument();
          out = {"document": true};
        } else if (args["kind"] is String) {
          var d = a.describeKind(args["kind"] as String);
          if (d == null) {
            return McpResult.error("There is no kind ${args["kind"]}. Kinds: "
                "${CanvasAutomation.kinds().map((k) => k["kind"]).join(", ")}.");
          }
          keys = d["keys"];
          out = {
            "kind": d["kind"],
            "label": d["label"],
            "example": d["example"]
          };
        } else {
          return McpResult.json({
            "kinds": CanvasAutomation.kinds(),
            "document": "Call with document: true to see the document's "
                "parts (masterMix, audio, session, sheets, size...).",
          }, summary: "Listed the kinds of element");
        }
        var path = args["path"] is String ? args["path"] as String : "";
        if (path.isNotEmpty) keys = readPointer(keys, path);
        out["keys"] = _trimTree(keys, path.isEmpty ? 2 : 3, path);
        return McpResult.json(compactJson(out, budget: 30000),
            summary: "Read what ${args["kind"] ?? "the document"} can hold");
      },
    ),
    tool(
      "canvas_get",
      "Read part of the canvas",
      "An element, a scene or the document as saved (JSON). A scene's "
          "elements and the document's are given in brief: read each element "
          "by its id. path is a JSON Pointer to read one part, e.g. "
          "\"/textSpec\" of an element or \"/masterMix\" of the document.",
      _object({
        "target": _target,
        "path": {"type": "string", "description": "A JSON Pointer."},
      }, required: [
        "target"
      ]),
      (args) async {
        var a = auto();
        var target = "${args["target"] ?? ""}";
        var path = args["path"] is String ? args["path"] as String : "";
        Object? json;
        if (target == "document") {
          var full = a.documentJson();
          json =
              path.isEmpty ? _briefDocument(a, full) : readPointer(full, path);
        } else if (_sceneIndex(a, target) case var i?) {
          var scene = a.sceneJson(i);
          if (scene == null) return McpResult.error("There is no scene $i.");
          json = path.isEmpty ? scene : readPointer(scene, path);
        } else {
          var element = a.elementJson(target);
          if (element == null) {
            return McpResult.error("There is no element $target: "
                "canvas_overview lists them.");
          }
          json = path.isEmpty ? element : readPointer(element, path);
        }
        return McpResult.json(compactJson(json, budget: 30000),
            summary: "Read $target${path.isEmpty ? "" : path}");
      },
    ),
    tool(
      "canvas_add_element",
      "Add elements",
      "Adds an element of a kind, made as the Add panel makes it (centred) "
          "and then changed by props (merged into it: place, size, words, "
          "colours, animation...). Give elements to add several in one step. "
          "Returns each new element's id and place.",
      _object({
        "kind": {"type": "string"},
        "props": {
          "type": "object",
          "description": "Merged into the fresh element's JSON.",
        },
        "elements": {
          "type": "array",
          "description": "Several at once: each {kind, props}.",
          "items": {
            "type": "object",
            "properties": {
              "kind": {"type": "string"},
              "props": {"type": "object"},
            },
            "required": ["kind"],
          },
        },
        "select": {
          "type": "boolean",
          "description": "Select what was added (the person sees it picked)."
        },
      }),
      (args) async {
        var wanted = <(String, Object?)>[
          if (args["kind"] is String) (args["kind"] as String, args["props"]),
          if (args["elements"] case List list)
            for (var e in list)
              if (e is Map && e["kind"] is String)
                (e["kind"] as String, e["props"]),
        ];
        if (wanted.isEmpty) return McpResult.error("Give a kind, or elements.");
        for (var (kind, _) in wanted) {
          if (auto().newElementJson(kind) == null) {
            return McpResult.error("There is no kind $kind. Kinds: "
                "${CanvasAutomation.kinds().map((k) => k["kind"]).join(", ")}.");
          }
        }
        return changing((a) async {
          var added = <Map<String, Object?>>[];
          for (var (kind, props) in wanted) {
            var json = a.newElementJson(kind)!;
            var merged = props is Map ? mergePatch(json, props) : json;
            var id = a.addElementJson(merged as Map<String, dynamic>);
            var e = a.controller.document.elementById(id);
            if (e != null) added.add(CanvasAutomation.summary(e));
          }
          if (args["select"] == true) {
            a.select([for (var e in added) "${e["id"]}"]);
          }
          return McpResult.json({"added": added},
              summary: "Added ${_count(added.length, "element")}");
        });
      },
    ),
    tool(
      "canvas_update",
      "Change part of the canvas",
      "Changes an element, a scene's own settings (name, frames, transition, "
          "background) or the document's parts (masterMix, audio, session, "
          "size, frameRate...). Send only what changes: patch merges, set "
          "puts values at paths, remove takes paths out. Returns the result.",
      _object({
        "target": _target,
        ..._editProps,
      }, required: [
        "target"
      ]),
      (args) async {
        var target = "${args["target"] ?? ""}";
        var sets = [
          if (args["set"] case List list)
            for (var s in list)
              if (s is Map && s["path"] is String)
                JsonSet(s["path"] as String, s["value"])
        ];
        var removes = [
          if (args["remove"] case List list)
            for (var r in list)
              if (r is String) r
        ];
        var patch = args["patch"];
        if (patch == null && sets.isEmpty && removes.isEmpty) {
          return McpResult.error(
              "Nothing to change: give patch, set or remove.");
        }
        return changing((a) async {
          if (target == "document") {
            for (var p in [
              if (patch is Map) ...patch.keys.map((k) => "/$k"),
              ...sets.map((s) => s.path),
              ...removes,
            ]) {
              if (p.startsWith("/elements") || p.startsWith("/scenes")) {
                return McpResult.error("Change elements with their own ids, "
                    "and scenes with target \"scene:<index>\".");
              }
            }
            var next = applyEdits(a.documentJson(),
                patch: patch, sets: sets, removes: removes);
            a.replaceDocumentJson(next as Map<String, dynamic>);
            return McpResult.json(
                compactJson(_briefDocument(a, a.documentJson()), budget: 8000),
                summary: "Changed the canvas's settings");
          }
          if (_sceneIndex(a, target) case var i?) {
            var scene = a.sceneJson(i);
            if (scene == null) return McpResult.error("There is no scene $i.");
            scene.remove("elements");
            var next =
                applyEdits(scene, patch: patch, sets: sets, removes: removes)
                    as Map<String, dynamic>;
            var problem = a.replaceSceneJson(i, next);
            if (problem != null) return McpResult.error(problem);
            return McpResult.json(compactJson(a.sceneJson(i), budget: 8000),
                summary: "Changed scene ${i + 1}");
          }
          var element = a.elementJson(target);
          if (element == null) {
            return McpResult.error("There is no element $target: "
                "canvas_overview lists them.");
          }
          var next =
              applyEdits(element, patch: patch, sets: sets, removes: removes)
                  as Map<String, dynamic>;
          var problem = a.replaceElementJson(target, next);
          if (problem != null) return McpResult.error(problem);
          var e = a.controller.document.elementById(target);
          return McpResult.json(
              compactJson(a.elementJson(target), budget: 8000),
              summary: "Changed ${e?.name ?? target}");
        });
      },
    ),
    tool(
      "canvas_delete_elements",
      "Delete elements",
      "Takes elements off the scene being edited, by id.",
      _object({
        "ids": {
          "type": "array",
          "items": {"type": "string"},
        }
      }, required: [
        "ids"
      ]),
      (args) async {
        var ids = [
          if (args["ids"] case List list)
            for (var i in list) "$i"
        ];
        return changing((a) async {
          var gone = a.deleteElements(ids);
          return McpResult.text(
              gone == 0
                  ? "None of those are on the scene being edited."
                  : "Deleted ${_count(gone, "element")}.",
              summary: "Deleted ${_count(gone, "element")}");
        });
      },
    ),
    tool(
      "canvas_arrange",
      "Move an element forward or back",
      "Puts an element at a place in paint order: \"front\", \"back\", or an "
          "index (0 is the back).",
      _object({
        "id": {"type": "string"},
        "to": {
          "description": '"front", "back" or an index.',
          "anyOf": [
            {"type": "string"},
            {"type": "integer"}
          ],
        },
      }, required: [
        "id",
        "to"
      ]),
      (args) async => changing((a) async {
        var count = a.controller.document.elements.length;
        var to = switch (args["to"]) {
          "front" => count - 1,
          "back" => 0,
          num n => n.toInt(),
          _ => int.tryParse("${args["to"]}") ?? count - 1,
        };
        var problem = a.reorder("${args["id"]}", to);
        return problem != null
            ? McpResult.error(problem)
            : McpResult.text("Moved.", summary: "Rearranged ${args["id"]}");
      }),
    ),
    tool(
      "canvas_scene",
      "Scenes",
      "go: show scene index (and frame) in the editor; elements are read and "
          "changed on the scene being edited. add: a new empty scene after "
          "index (or the one being edited), which becomes the one edited.",
      _object({
        "action": {
          "type": "string",
          "enum": ["go", "add"]
        },
        "index": {"type": "integer"},
        "frame": {"type": "integer"},
      }, required: [
        "action"
      ]),
      (args) async {
        var index = (args["index"] as num?)?.toInt();
        var frame = (args["frame"] as num?)?.toInt();
        if (args["action"] == "add") {
          return changing((a) async {
            var at = a.addScene(after: index);
            return McpResult.text("Added scene $at; it is the one edited now.",
                summary: "Added a scene");
          });
        }
        var a = auto();
        a.goTo(scene: index, frame: frame);
        return McpResult.json(a.overview(),
            summary:
                "Went to scene ${(index ?? a.controller.document.at) + 1}");
      },
    ),
    tool(
      "canvas_select",
      "Select elements",
      "Picks out elements on the scene being edited, so the person sees "
          "what you mean; an empty list clears the selection.",
      _object({
        "ids": {
          "type": "array",
          "items": {"type": "string"},
        }
      }, required: [
        "ids"
      ]),
      (args) async {
        var ids = [
          if (args["ids"] case List list)
            for (var i in list) "$i"
        ];
        auto().select(ids);
        return McpResult.text("Selected.",
            summary: ids.isEmpty
                ? "Cleared the selection"
                : "Selected ${ids.join(", ")}");
      },
    ),
    tool(
      "canvas_render",
      "See the canvas",
      "A picture (PNG) of a scene at a frame, as it will be published. Give "
          "frames (up to 8) to see motion. Use it to check your work.",
      _object({
        "scene": {
          "type": "integer",
          "description": "Defaults to the one being edited."
        },
        "frame": {
          "type": "integer",
          "description": "Defaults to the playhead."
        },
        "frames": {
          "type": "array",
          "items": {"type": "integer"},
        },
        "maxSide": {
          "type": "integer",
          "description": "Longest side in pixels, 256 to 1600 (768 by default)."
        },
      }),
      (args) async {
        var a = auto();
        var scene = (args["scene"] as num?)?.toInt();
        var frames = <int?>[
          if (args["frames"] case List list)
            for (var f in list.take(8))
              if (f is num) f.toInt(),
        ];
        if (frames.isEmpty) frames.add((args["frame"] as num?)?.toInt());
        var side = ((args["maxSide"] as num?)?.toDouble() ?? 768)
            .clamp(256, 1600)
            .toDouble();
        var pngs = <Uint8List>[];
        for (var f in frames) {
          var png = await a.renderPng(scene: scene, frame: f, maxSide: side);
          if (png != null) pngs.add(png);
        }
        if (pngs.isEmpty) {
          return McpResult.error("The canvas could not be drawn.");
        }
        return McpResult.images(pngs,
            text: frames.length > 1 ? "Frames ${frames.join(", ")}:" : "",
            summary: "Looked at ${_count(pngs.length, "frame")}");
      },
    ),
    tool(
      "canvas_channels",
      "Sound channels",
      "The timeline's channels: key, name and the elements on each. A "
          "channel's mixer settings, effects chain, automation and Speech "
          "device are in its first element's clip > mix.",
      _object({}),
      (args) async => McpResult.json(auto().channels(),
          summary: "Listed the sound channels"),
    ),
    tool(
      "canvas_speak",
      "Speak a channel's script",
      "Makes takes of a channel's Speech device script with its own voice, "
          "for every line with none yet. Runs on in the background.",
      _object({
        "channel": {"type": "string", "description": "The channel's key."}
      }, required: [
        "channel"
      ]),
      (args) async {
        var problem = await auto().speak("${args["channel"]}");
        return problem != null
            ? McpResult.error(problem)
            : McpResult.text("Speaking: the takes will appear on the channel.",
                summary: "Spoke channel ${args["channel"]}");
      },
    ),
    tool(
      "canvas_measure_audio",
      "Measure the mix",
      "How loud the canvas's sound is, mixed as an export mixes it: "
          "integrated loudness (LUFS), loudness range and true peak (dBTP).",
      _object({}),
      (args) async {
        var m = await auto().measureAudio();
        return m == null
            ? McpResult.error("Nothing to measure (no sound), or ffmpeg is "
                "not installed.")
            : McpResult.json(m, summary: "Measured the mix");
      },
    ),
    tool(
      "canvas_undo",
      "Undo or redo",
      "Takes back your last change (or several), or puts it back with redo.",
      _object({
        "steps": {"type": "integer"},
        "redo": {"type": "boolean"},
      }),
      (args) async {
        var a = auto();
        var steps = ((args["steps"] as num?)?.toInt() ?? 1).clamp(1, 50);
        for (var i = 0; i < steps; i++) {
          args["redo"] == true ? a.redo() : a.undo();
        }
        return McpResult.text(args["redo"] == true ? "Redone." : "Undone.",
            summary: "${args["redo"] == true ? "Redid" : "Undid"} "
                "${_count(steps, "step")}");
      },
    ),
  ];
}

String _count(int n, String what) => "$n $what${n == 1 ? "" : "s"}";

/// _sceneIndex reads `scene:<n>` (or "scene", the one being edited).
int? _sceneIndex(CanvasAutomation a, String target) {
  if (target == "scene") return a.controller.document.at;
  if (!target.startsWith("scene:")) return null;
  return int.tryParse(target.substring(6));
}

/// _briefDocument is the document with its elements and scenes in brief.
Map<String, dynamic> _briefDocument(
    CanvasAutomation a, Map<String, dynamic> full) {
  var d = a.controller.document;
  return {
    ...full,
    "elements": [for (var e in d.elements) CanvasAutomation.summary(e)],
    if (full.containsKey("scenes"))
      "scenes": [
        for (var i = 0; i < d.allScenes.length; i++)
          {
            "index": i,
            "name": d.allScenes[i].name,
            "frames": d.allScenes[i].frames,
            "elements": d.allScenes[i].elements.length,
            "read": "canvas_get scene:$i",
          }
      ],
  };
}

/// _trimTree is a key tree cut at [depth], deeper parts said in a word.
Object? _trimTree(Object? tree, int depth, String path) {
  if (tree is! Map) return tree;
  if (depth <= 0) {
    return "{${tree.length} keys: describe with path \"$path\"}";
  }
  return {
    for (var e in tree.entries)
      "${e.key}": _trimTree(e.value, depth - 1, "$path/${e.key}")
  };
}
