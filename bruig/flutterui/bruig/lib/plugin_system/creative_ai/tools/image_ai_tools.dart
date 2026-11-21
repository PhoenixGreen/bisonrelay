import 'package:bruig/plugin_system/canvas/canvas.dart';
import 'package:bruig/plugin_system/creative_ai/creative_ai_model.dart';
import 'package:bruig/plugin_system/creative_ai/mcp/mcp_server.dart';

// image_ai_tools.dart is what Claude can do to a picture as a photo editor's
// actions do: do one of the app's or the person's actions, write its own as
// plain steps (adjustments, textures, colour, copies of the picture,
// effects), and keep a look it made as an action for later. Every step is a
// layer the person can change afterwards, and each call is one step of
// their Undo.

List<McpTool> imageAiTools(CreativeAi ai) {
  bool on() => ai.canvasOn;

  Future<McpResult> changing(
      Future<McpResult> Function(CanvasScripting a) body) async {
    var a = ai.scripting;
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

  const replace = {
    "type": "boolean",
    "description": "True takes the place of the picture's look (its "
        "adjustments, textures, colour layers and copies); false (the "
        "usual) adds to it.",
  };

  return [
    tool(
      "image_reference",
      "What a picture's steps can be",
      "Every step image_add_steps can make: the adjustments (with each "
          "setting's key, range and default), textures, effects, blends and "
          "film colour tables. Read it before writing steps.",
      {},
      (args) async => McpResult.json(CanvasScripting.imageReference(),
          summary: "Read what a picture's steps can be"),
    ),
    tool(
      "image_actions",
      "Picture actions",
      "The actions a picture can be given -- the app's (film, light, "
          "screens, drawn and printed looks) and the person's own -- each "
          "with its steps.",
      {},
      (args) async => McpResult.json(await CanvasScripting.imageActions(),
          summary: "Listed the picture actions"),
    ),
    tool(
      "image_layers",
      "A picture's layers",
      "A picture element's layers, top first: what each is, and which an "
          "action keeps.",
      {
        "id": {"type": "string", "description": "The picture element's id."},
      },
      (args) async {
        var layers = ai.scripting.imageLayers("${args["id"]}");
        return layers == null
            ? McpResult.error("Element ${args["id"]} is not a picture.")
            : McpResult.json(layers, summary: "Read a picture's layers");
      },
      required: ["id"],
    ),
    tool(
      "image_do_action",
      "Do an action to a picture",
      "Does an action (by id or name, from image_actions) to a picture "
          "element. Then canvas_render to see it.",
      {
        "id": {"type": "string", "description": "The picture element's id."},
        "action": {"type": "string"},
        "replace": replace,
      },
      (args) => changing((a) async {
        var problem = await a.doImageAction(
            "${args["id"]}", "${args["action"]}",
            replace: args["replace"] == true);
        return problem == null
            ? McpResult.text("Done.", summary: "Did ${args["action"]}")
            : McpResult.error(problem);
      }),
      required: ["id", "action"],
    ),
    tool(
      "image_add_steps",
      "Edit a picture in steps",
      "Does steps to a picture element, in order, bottom to top, each a "
          "layer the person can change later: {\"step\": \"adjust\", \"kind\": "
          "\"colourBalance\", \"values\": {...}}, {\"step\": \"texture\", "
          "\"kind\": \"grain\"}, {\"step\": \"copy\", \"blend\": \"screen\", "
          "\"effects\": [{\"kind\": \"blur\", \"values\": {\"amount\": 18}}]}, "
          "{\"step\": \"effect\", ...}, {\"step\": \"fill\", ...}, {\"step\": "
          "\"curve\", \"points\": [[0, 0.1], [1, 0.9]]}. An adjustment with "
          "\"clip\": true works on the layer just under it only (a copy, "
          "say). See image_reference for every kind and setting.",
      {
        "id": {"type": "string", "description": "The picture element's id."},
        "steps": {
          "type": "array",
          "items": {"type": "object"},
        },
        "replace": replace,
      },
      (args) => changing((a) async {
        var (:made, skipped: problems, :problem) = a.addImageSteps(
            "${args["id"]}", args["steps"],
            replace: args["replace"] == true);
        if (problem != null) {
          return McpResult.error([problem, ...problems].join("\n"));
        }
        return McpResult.text(
            "Made $made step${made == 1 ? "" : "s"}."
            "${problems.isEmpty ? "" : "\nNot made:\n${problems.join("\n")}"}",
            summary: "Edited a picture in $made steps");
      }),
      required: ["id", "steps"],
    ),
    tool(
      "image_save_action",
      "Keep a look as an action",
      "Keeps a picture's steps as an action of the person's, to do to other "
          "pictures (from the picture's Actions, or image_do_action). The "
          "same name again replaces that action. Look at it first.",
      {
        "id": {"type": "string", "description": "The picture element's id."},
        "name": {"type": "string"},
        "layers": {
          "type": "array",
          "items": {"type": "string"},
          "description": "Only these layers (ids from image_layers; the "
              "picture's own id is \"base\", for its effects). All if left "
              "out.",
        },
      },
      (args) async {
        var (action: id, :problem) = await ai.scripting.saveImageAction(
            "${args["id"]}", "${args["name"] ?? ""}",
            layers: args["layers"] is List
                ? [for (var l in args["layers"] as List) "$l"]
                : null);
        return id == null
            ? McpResult.error(problem ?? "Could not save it.")
            : McpResult.text("Kept as ${args["name"]}.",
                summary: "Kept the action ${args["name"]}");
      },
      required: ["id", "name"],
    ),
  ];
}
