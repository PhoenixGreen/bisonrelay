import 'package:bruig/plugin_system/creative_ai/creative_ai_model.dart';
import 'package:bruig/plugin_system/creative_ai/engine/json_edit.dart';
import 'package:bruig/plugin_system/creative_ai/engine/style_facts.dart';
import 'package:bruig/plugin_system/creative_ai/mcp/mcp_server.dart';
import 'package:bruig/plugin_system/creative_ai/session/style_library.dart';

// style_ai_tools.dart is the style profile tools: list the styles kept, read
// one (its guide, measured facts and sample elements) to work in it, and
// save the open canvas as one. Saving measures the canvas itself; Claude's
// part is the written guide, which says what the measurements mean.

List<McpTool> styleAiTools(CreativeAi ai) {
  bool on() => ai.canvasOn;

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
      "canvas_styles",
      "List style profiles",
      "The style profiles kept on this computer: each one's name, what it "
          "is for, its main colours and fonts. Read one with "
          "canvas_style_get before working in it.",
      {"type": "object", "properties": {}},
      (args) async {
        var styles = await ai.styles.refresh();
        return McpResult.json({
          "styles": [for (var s in styles) s.brief()],
          if (ai.styles.active case var a?) "active": a.slug,
        }, summary: "Listed the styles");
      },
    ),
    tool(
      "canvas_style_get",
      "Read a style profile",
      "A style's guide (its rules in words), and the facts measured from "
          "the canvas it came from: palette (the colours in front, each with the integer to use), "
          "the background's colours, type from headline down, text styles, backgrounds, how "
          "things arrive, scene lengths, the master mix and voices, and "
          "sample elements to copy from (change their id, place and words). "
          "Follow the guide; use the facts for exact values.",
      {
        "type": "object",
        "properties": {
          "style": {"type": "string", "description": "Its name or id."},
        },
        "required": ["style"],
      },
      (args) async {
        var style = await ai.styles.byName("${args["style"] ?? ""}");
        if (style == null) {
          return McpResult.error("There is no style ${args["style"]}: "
              "canvas_styles lists them.");
        }
        return McpResult.json(
            compactJson({
              "style": style.slug,
              "name": style.name,
              "description": style.description,
              "guide": style.guide,
              "facts": style.facts,
            }, budget: 40000),
            summary: "Read the style ${style.name}");
      },
    ),
    tool(
      "canvas_style_save",
      "Save the canvas as a style",
      "Keeps the open canvas's style as a profile to make new work from: its "
          "palette, type, backgrounds, motion, timing and sound are measured, "
          "and a picture is kept. Give it a name, a one-line description, "
          "and a guide: Markdown saying what makes the style (mood, what "
          "each colour is for, the role of each size of type, layout and "
          "spacing, how things move, what to avoid). Look at the canvas "
          "(canvas_render) before writing the guide. A style of the same "
          "name is replaced.",
      {
        "type": "object",
        "properties": {
          "name": {"type": "string"},
          "description": {"type": "string"},
          "guide": {"type": "string"},
          "scene": {
            "type": "integer",
            "description": "The scene to picture (the one being edited by "
                "default)."
          },
        },
        "required": ["name"],
      },
      (args) async {
        var name = "${args["name"] ?? ""}".trim();
        if (name.isEmpty) return McpResult.error("Give the style a name.");
        var style = await saveCanvasStyle(ai,
            name: name,
            description: "${args["description"] ?? ""}".trim(),
            guide: "${args["guide"] ?? ""}",
            scene: (args["scene"] as num?)?.toInt());
        return McpResult.json(style.brief(),
            summary: "Saved the style ${style.name}");
      },
    ),
  ];
}

/// saveCanvasStyle keeps the open canvas's style as [name]: measured, with a
/// picture of [scene] and [guide] (or, without one, a guide of the facts).
Future<StyleProfile> saveCanvasStyle(CreativeAi ai,
    {required String name,
    String description = "",
    String guide = "",
    int? scene}) async {
  var a = ai.automation;
  var doc = a.controller.document;
  var facts = styleFactsOf(a.documentJson(),
      width: doc.size.width.toDouble(), height: doc.size.height.toDouble());
  var at = (scene ?? doc.at).clamp(0, doc.allScenes.length - 1).toInt();
  // Part way in, when what arrives has arrived.
  var frames = doc.allScenes[at].frames;
  var preview =
      await a.renderPng(scene: at, frame: (frames * 0.6).floor(), maxSide: 480);
  var c = a.controller;
  return ai.styles.save(
    name: name,
    description: description,
    guide: guide.trim().isEmpty ? factualGuide(name, facts) : guide,
    facts: facts,
    from: c.name == null ? doc.title : "${c.folder ?? ""}/${c.name}",
    preview: preview,
  );
}
