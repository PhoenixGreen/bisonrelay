import 'package:bruig/plugin_system/canvas/canvas.dart';
import 'package:bruig/plugin_system/creative_ai/creative_ai_model.dart';
import 'package:bruig/plugin_system/creative_ai/mcp/mcp_server.dart';

// library_ai_tools.dart is what Claude can bring onto a canvas besides
// elements it makes: the person's library (pictures, videos, sounds,
// drawings, 3D models), the presets (elements, scenes, canvases), and the
// stock libraries searched with the person's own keys.
//
// Stock follows Canvas's own rules, unchanged: nothing is fetched while
// "Let a canvas fetch data" is off, or behind a proxy, and a result keeps
// who made it and its licence.

List<McpTool> libraryAiTools(CreativeAi ai) {
  bool on() => ai.canvasOn;
  bool fetching() => ai.canvasPrefs().allowFetching;

  /// changing is [body] as one step to undo, after keeping the canvas from
  /// before Claude started (as canvas_ai_tools does).
  Future<McpResult> changing(
      Future<McpResult> Function(CanvasAutomation a) body) async {
    var a = ai.automation;
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
          Map<String, Object?> properties,
          Future<McpResult> Function(Map<String, dynamic> args) run,
          {List<String> required = const []}) =>
      McpTool(
        name: name,
        title: title,
        description: description,
        inputSchema: {
          "type": "object",
          "properties": properties,
          if (required.isNotEmpty) "required": required,
        },
        area: "canvas",
        available: on,
        run: (args, caller) => run(args),
      );

  return [
    tool(
      "canvas_assets",
      "The person's library",
      "Files in the person's Canvas library: pictures, videos, audio, "
          "vectors (drawings) and 3D models, with sizes, lengths and credits. "
          "Use one with canvas_use_asset.",
      {
        "kind": {
          "type": "string",
          "enum": ["picture", "video", "audio", "vector", "model"],
        },
        "query": {"type": "string", "description": "Part of a name."},
      },
      (args) async => McpResult.json(
          await CanvasAutomation.assets(
              kind: args["kind"] as String?, query: "${args["query"] ?? ""}"),
          summary: "Looked through the library"),
    ),
    tool(
      "canvas_use_asset",
      "Use a library file",
      "Puts a library file on the scene being edited, as clicking it in the "
          "Assets panel does: a picture, video, drawing or model as an "
          "element in the middle, a sound as a speaker on the timeline, a "
          "MIDI file as a MIDI channel. Then place it with canvas_update.",
      {
        "id": {"type": "string"}
      },
      (args) async => changing((a) async {
        var (element, problem) = await a.useAsset("${args["id"]}");
        if (problem != null) return McpResult.error(problem);
        return McpResult.json({if (element != null) "element": element},
            summary: "Used ${args["id"]} from the library");
      }),
      required: ["id"],
    ),
    tool(
      "canvas_presets",
      "Presets",
      "What can be started from: element presets (built in and saved), "
          "saved scenes, and canvases (built in and saved). Each has an id "
          "for canvas_use_preset.",
      {
        "query": {"type": "string", "description": "Part of a name."},
      },
      (args) async => McpResult.json(
          await CanvasAutomation.presets(query: "${args["query"] ?? ""}"),
          summary: "Looked through the presets"),
    ),
    tool(
      "canvas_use_preset",
      "Use a preset",
      "Adds a preset to the open canvas: an element preset onto the scene "
          "being edited; a scene or canvas preset as new scenes after it. "
          "Change what it adds afterwards to fit the request.",
      {
        "id": {"type": "string"}
      },
      (args) async => changing((a) async {
        var (added, problem) = await a.usePreset("${args["id"]}");
        if (problem != null) return McpResult.error(problem);
        return McpResult.text("Added $added.",
            summary: "Used the preset ${args["id"]}");
      }),
      required: ["id"],
    ),
    tool(
      "canvas_stock_sources",
      "Stock libraries",
      "The stock libraries (pictures, videos, icons, sounds, music, 3D "
          "models), and whether the person has given each its key (\"ready\")."
          " Keys are added in Canvas's Stock panel.",
      {},
      (args) async => McpResult.json({
        "sources": await CanvasAutomation.stockSources(),
        "fetching": fetching()
            ? "allowed"
            : "switched off: the person turns on Settings > Plugins > "
                "Canvas > Let a canvas fetch data",
      }, summary: "Listed the stock libraries"),
    ),
    tool(
      "canvas_stock_search",
      "Search stock",
      "Searches a stock library for what is described. Results have an id "
          "for canvas_stock_use, a title, credits and a thumbnail address.",
      {
        "source": {"type": "string"},
        "text": {"type": "string"},
        "page": {"type": "integer"},
      },
      (args) async {
        var found = await CanvasAutomation.stockSearch(
            "${args["source"]}", "${args["text"] ?? ""}",
            page: (args["page"] as num?)?.toInt() ?? 1,
            allowFetching: fetching());
        if (found["problem"] case String problem) {
          return McpResult.error(problem);
        }
        return McpResult.json(found,
            summary: "Searched ${args["source"]} for \"${args["text"]}\"");
      },
      required: ["source", "text"],
    ),
    tool(
      "canvas_stock_use",
      "Use a stock result",
      "Fetches a search result into the person's library, keeping who made "
          "it and its licence, and (unless place is false) puts it on the "
          "scene being edited. Pictures, drawings and 3D models; a video or "
          "a sound is added from the Stock panel.",
      {
        "id": {"type": "string"},
        "place": {"type": "boolean"},
      },
      (args) async => changing((a) async {
        var (asset, problem) = await a.stockUse("${args["id"]}",
            place: args["place"] != false, allowFetching: fetching());
        if (asset == null) return McpResult.error(problem!);
        return McpResult.json(
            {...asset, if (problem != null) "warning": problem},
            summary: "Added ${asset["name"]} from stock");
      }),
      required: ["id"],
    ),
    tool(
      "canvas_drawn_styles",
      "Drawn character styles",
      "The styles people can be drawn in, made on this computer from CC0 "
          "drawings: Open Peeps (Pablo Stanley), Notionists (Zoish), Lorelei "
          "(Lisa Wischofsky), Pixel Art. Each with its parts (and their "
          "choices) and colours (and their palettes).",
      {},
      (args) async => McpResult.json(await CanvasAutomation.drawnStyles(),
          summary: "Listed the drawn character styles"),
    ),
    tool(
      "canvas_draw_character",
      "Draw a character",
      "Draws a character in a style from canvas_drawn_styles and puts it on "
          "the scene as a drawing, kept in the person's library. Parts and "
          "colours not given are picked as the style would (seed makes the "
          "same pick again); a part given as null is left out where the "
          "style allows. Colours are six-digit hex.",
      {
        "style": {"type": "string"},
        "parts": {"type": "object"},
        "colours": {"type": "object"},
        "seed": {"type": "integer"},
        "name": {"type": "string"},
      },
      (args) => changing((a) async {
        var (id, problem) = await a.drawCharacter("${args["style"]}",
            parts: args["parts"] is Map
                ? Map<String, Object?>.from(args["parts"] as Map)
                : const {},
            colours: args["colours"] is Map
                ? Map<String, Object?>.from(args["colours"] as Map)
                : const {},
            seed: args["seed"] is int ? args["seed"] as int : null,
            name: "${args["name"] ?? ""}");
        if (id == null) return McpResult.error(problem ?? "Not drawn.");
        return McpResult.text(
            "Drawn: element $id.${problem == null ? "" : " Left as picked: "
                "$problem."}",
            summary: "Drew a ${args["style"]} character");
      }),
      required: ["style"],
    ),
    tool(
      "canvas_draw_svg",
      "Draw a picture",
      "Draws a picture as SVG: an illustration, icon, emblem, pattern, map "
          "or diagram that nothing in the library or stock fits. Give one "
          "self-contained SVG with a viewBox, drawn wholly in shapes, paths, "
          "gradients and text (no scripts, embedded pages or links to "
          "outside files). It is kept in the person's library as a drawing "
          "and, unless place is false, put on the scene being edited: then "
          "place and size it with canvas_update, and render to check it.",
      {
        "name": {"type": "string"},
        "svg": {"type": "string"},
        "place": {"type": "boolean"},
      },
      (args) async => changing((a) async {
        var (id, element, problem) = await a.addSvg(
            "${args["name"] ?? ""}", "${args["svg"] ?? ""}",
            place: args["place"] != false);
        if (id == null) return McpResult.error(problem!);
        return McpResult.json({
          "library": id,
          if (element != null) "element": element,
          if (problem != null) "warning": problem,
        }, summary: "Drew ${args["name"] ?? "a picture"}");
      }),
      required: ["name", "svg"],
    ),
  ];
}
