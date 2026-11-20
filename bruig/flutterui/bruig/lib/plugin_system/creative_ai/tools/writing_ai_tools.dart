import 'package:bruig/plugin_system/creative_ai/creative_ai_model.dart';
import 'package:bruig/plugin_system/creative_ai/mcp/mcp_server.dart';
import 'package:bruig/plugin_system/creative_ai/session/writing_suggestions.dart';

// writing_ai_tools.dart is the Writing tools Claude is given: read the open
// document, and offer changes to it. A change is never typed into the
// document behind the person's back: it waits in the Creative AI panel to be
// accepted, unless they have chosen to have changes put straight in.

List<McpTool> writingAiTools(CreativeAi ai) {
  bool on() => ai.writingOn;

  McpTool tool(
          String name,
          String title,
          String description,
          Map<String, Object?> schema,
          Future<McpResult> Function(Map<String, dynamic> args, McpCaller c)
              run) =>
      McpTool(
        name: name,
        title: title,
        description: description,
        inputSchema: schema,
        area: "writing",
        available: on,
        run: run,
      );

  String? noDocument() => ai.composer().editor == null
      ? "No document is open: the person needs to open one on the Writing "
          "page."
      : null;

  String said(OfferResult r) => r.applied
      ? "Put into the document."
      : "Offered as suggestion ${r.id}: the person will accept or reject it "
          "in the Creative AI panel.";

  return [
    tool(
      "writing_get_document",
      "Read the document",
      "The document open on the Writing page: its title, length, the "
          "selection (start and end are character offsets; equal means just "
          "a cursor) and the selected text, and the text itself (from "
          "offset 'from', at most 'length' characters; all of it by default "
          "up to 60000).",
      {
        "type": "object",
        "properties": {
          "from": {"type": "integer"},
          "length": {"type": "integer"},
        },
      },
      (args, caller) async {
        if (noDocument() case var problem?) return McpResult.error(problem);
        var editor = ai.composer().editor!;
        var text = editor.text;
        var sel = editor.selection;
        var from = ((args["from"] as num?)?.toInt() ?? 0)
            .clamp(0, text.length)
            .toInt();
        var length = ((args["length"] as num?)?.toInt() ?? 60000)
            .clamp(0, 200000)
            .toInt();
        var to = (from + length).clamp(from, text.length).toInt();
        var lib = ai.library();
        return McpResult.json({
          "title": lib.openName ?? "",
          "folder": lib.openFolder,
          "length": text.length,
          "selection": sel.isValid
              ? {
                  "start": sel.start,
                  "end": sel.end,
                  "text": sel.textInside(text),
                }
              : null,
          "from": from,
          "to": to,
          "text": text.substring(from, to),
          "waitingSuggestions": ai.suggestions.items.length,
        }, summary: "Read the document");
      },
    ),
    tool(
      "writing_edit",
      "Change the document",
      "Replaces spans of the document. Each edit names its span by 'find' "
          "(its exact text; 'occurrence' picks which, from 1) or by 'start' "
          "and 'end' offsets (with 'find' as a check if given). Give the "
          "new text as 'replacement' and a short 'note' on why.",
      {
        "type": "object",
        "properties": {
          "edits": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {
                "find": {"type": "string"},
                "occurrence": {"type": "integer"},
                "start": {"type": "integer"},
                "end": {"type": "integer"},
                "replacement": {"type": "string"},
                "note": {"type": "string"},
              },
              "required": ["replacement"],
            },
          },
        },
        "required": ["edits"],
      },
      (args, caller) async {
        if (noDocument() case var problem?) return McpResult.error(problem);
        var edits = args["edits"];
        if (edits is! List || edits.isEmpty) {
          return McpResult.error("Give edits: a list of changes.");
        }
        // Found against the text as it is now, all before any is made, and
        // made from the end back so the offsets hold.
        var text = ai.composer().editor!.text;
        var found = <(int, int, String, String)>[];
        var problems = <String>[];
        for (var (n, e) in edits.indexed) {
          if (e is! Map || e["replacement"] is! String) {
            problems.add("Edit ${n + 1} has no replacement.");
            continue;
          }
          var span = _span(text, e);
          if (span.$3 != null) {
            problems.add("Edit ${n + 1}: ${span.$3}");
            continue;
          }
          found.add((
            span.$1,
            span.$2,
            e["replacement"] as String,
            "${e["note"] ?? ""}"
          ));
        }
        found.sort((a, b) => b.$1.compareTo(a.$1));
        var results = <String>[];
        for (var (start, end, replacement, note) in found) {
          var r = ai.suggestions.offer(
              start: start,
              end: end,
              replacement: replacement,
              note: note,
              source: caller.source);
          results.add(r.error ?? said(r));
        }
        var out = [...results, ...problems].join("\n");
        return McpResult([
          {"type": "text", "text": out}
        ],
            isError: found.isEmpty,
            summary: "Offered ${found.length} "
                "${found.length == 1 ? "change" : "changes"}");
      },
    ),
    tool(
      "writing_insert",
      "Add to the document",
      "Adds text at 'at': \"cursor\" (where the person's cursor is, or after "
          "their selection), \"start\", \"end\", or an offset. Include the "
          "line breaks it needs around it.",
      {
        "type": "object",
        "properties": {
          "text": {"type": "string"},
          "at": {
            "anyOf": [
              {
                "type": "string",
                "enum": ["cursor", "start", "end"]
              },
              {"type": "integer"},
            ]
          },
          "note": {"type": "string"},
        },
        "required": ["text"],
      },
      (args, caller) async {
        if (noDocument() case var problem?) return McpResult.error(problem);
        var editor = ai.composer().editor!;
        var length = editor.text.length;
        var sel = editor.selection;
        var at = switch (args["at"]) {
          "start" => 0,
          "end" => length,
          num n => n.toInt().clamp(0, length).toInt(),
          _ => sel.isValid ? sel.end : length,
        };
        var r = ai.suggestions.offer(
            start: at,
            end: at,
            replacement: "${args["text"] ?? ""}",
            note: "${args["note"] ?? ""}",
            source: caller.source);
        return r.error != null
            ? McpResult.error(r.error!)
            : McpResult.text(said(r), summary: "Offered an addition");
      },
    ),
  ];
}

/// _span is where edit [e] applies in [text]: (start, end, problem).
(int, int, String?) _span(String text, Map e) {
  var find = e["find"] is String ? e["find"] as String : null;
  var start = (e["start"] as num?)?.toInt();
  var end = (e["end"] as num?)?.toInt();
  if (start != null && end != null) {
    if (start < 0 || end < start || end > text.length) {
      return (0, 0, "$start..$end is outside the text (${text.length} long).");
    }
    if (find != null && text.substring(start, end) != find) {
      // Moved: look for it nearby instead.
      var i = text.indexOf(find);
      if (i < 0) return (0, 0, "\"${_short(find)}\" is not in the document.");
      return (i, i + find.length, null);
    }
    return (start, end, null);
  }
  if (find == null || find.isEmpty) {
    return (0, 0, "Give find, or start and end.");
  }
  var occurrence = ((e["occurrence"] as num?)?.toInt() ?? 1).clamp(1, 100000);
  var i = -1;
  for (var n = 0; n < occurrence; n++) {
    i = text.indexOf(find, i + 1);
    if (i < 0) break;
  }
  if (i < 0) {
    return (
      0,
      0,
      "\"${_short(find)}\" is not in the document"
          "${occurrence > 1 ? " $occurrence times" : ""}."
    );
  }
  return (i, i + find.length, null);
}

String _short(String s) => s.length <= 60 ? s : "${s.substring(0, 57)}…";
