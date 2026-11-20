import 'dart:convert';
import 'dart:io';

import 'package:bruig/plugin_system/canvas/canvas.dart';
import 'package:bruig/plugin_system/creative_ai/creative_ai_model.dart';
import 'package:bruig/plugin_system/creative_ai/creative_ai_preferences.dart';
import 'package:bruig/plugin_system/creative_ai/mcp/mcp_server.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// creative_ai_tools_test.dart drives Creative AI's MCP server as Claude does
// -- initialize, list the tools, call them -- against a real canvas editing
// session and a real composer, and over HTTP to hold its guards: the token,
// and no web page.

const _caller = McpCaller("Test");

class _Rig {
  final CreativeAiPreferences prefs = CreativeAiPreferences();
  final CanvasController canvas = CanvasController(emptyCanvas());
  final CanvasPreferences canvasPrefs = CanvasPreferences();
  final ComposerSidebarController composer = ComposerSidebarController();
  final PostLibraryModel library = PostLibraryModel();
  late final CreativeAi ai = CreativeAi(
    prefs: prefs,
    canvas: () => canvas,
    canvasPrefs: () => canvasPrefs,
    composer: () => composer,
    library: () => library,
  );
  int _id = 0;

  /// on switches Creative AI on (its server starts, and stops with the
  /// test), working in both places.
  Future<void> on() async {
    canvasPrefs.enabled = true;
    prefs.enabled = true;
    prefs.canvas = true;
    prefs.writing = true;
    addTearDown(ai.dispose);
  }

  /// call is a tools/call: the result's text, or a failure.
  Future<Map<String, dynamic>> call(String tool,
      [Map<String, Object?> args = const {}]) async {
    var reply = await ai.server.handle({
      "jsonrpc": "2.0",
      "id": ++_id,
      "method": "tools/call",
      "params": {"name": tool, "arguments": args},
    }, _caller) as Map;
    return Map<String, dynamic>.from(reply["result"] as Map);
  }

  /// json is a successful call's JSON.
  Future<dynamic> json(String tool,
      [Map<String, Object?> args = const {}]) async {
    var r = await call(tool, args);
    expect(r["isError"], isNot(true), reason: "${r["content"]}");
    return jsonDecode(((r["content"] as List).first as Map)["text"] as String);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group("the protocol", () {
    test("initialize, list and a notification", () async {
      var rig = _Rig();
      await rig.on();
      var init = await rig.ai.server.handle({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {"protocolVersion": "2025-06-18", "capabilities": {}},
      }, _caller) as Map;
      var result = init["result"] as Map;
      expect(result["protocolVersion"], "2025-06-18");
      expect(result["serverInfo"]["name"], "bison-relay");
      expect(result["instructions"], contains("CANVAS"));

      expect(
          await rig.ai.server.handle(
              {"jsonrpc": "2.0", "method": "notifications/initialized"},
              _caller),
          isNull);

      var list = await rig.ai.server.handle(
          {"jsonrpc": "2.0", "id": 2, "method": "tools/list"}, _caller) as Map;
      var names = [
        for (var t in (list["result"] as Map)["tools"] as List) t["name"]
      ];
      expect(names, containsAll(["canvas_overview", "writing_get_document"]));
    });

    test("tools of an area switched off are not offered or run", () async {
      var rig = _Rig();
      await rig.on();
      rig.prefs.canvas = false;
      var list = await rig.ai.server.handle(
          {"jsonrpc": "2.0", "id": 2, "method": "tools/list"}, _caller) as Map;
      var names = [
        for (var t in (list["result"] as Map)["tools"] as List) t["name"]
      ];
      expect(names.where((n) => "$n".startsWith("canvas_")), isEmpty);
      var r = await rig.call("canvas_overview");
      expect(r["isError"], isTrue);
    });

    test("an unknown method is an error", () async {
      var rig = _Rig();
      var r = await rig.ai.server.handle(
          {"jsonrpc": "2.0", "id": 9, "method": "nope"}, _caller) as Map;
      expect((r["error"] as Map)["code"], -32601);
    });
  });

  group("canvas tools", () {
    test("add, read, change and see the result", () async {
      var rig = _Rig();
      await rig.on();
      var added = await rig.json("canvas_add_element", {
        "kind": "text",
        "props": {
          "text": "Hello",
          "x": 40,
          "y": 50,
          "textSpec": {"size": 64}
        },
      }) as Map;
      var id = ((added["added"] as List).single as Map)["id"] as String;
      var overview = await rig.json("canvas_overview") as Map;
      var row = (overview["elements"] as List).single as Map;
      expect(row["kind"], "text");
      expect(row["x"], 40);

      var element = await rig.json("canvas_get", {"target": id}) as Map;
      expect(element["text"], "Hello");
      expect((element["textSpec"] as Map)["size"], 64);
      // The rest of the text spec survives a patch of one key.
      expect((element["textSpec"] as Map)["font"], isNotNull);

      await rig.json("canvas_update", {
        "target": id,
        "patch": {
          "textSpec": {"size": 80}
        },
        "set": [
          {
            "path": "/track/keys",
            "value": [
              {"f": 0, "o": 0},
              {"f": 12, "o": 1}
            ]
          }
        ],
      });
      var after = await rig.json("canvas_get", {"target": id}) as Map;
      expect((after["textSpec"] as Map)["size"], 80);
      expect((after["track"] as Map)["keys"], hasLength(2));
      expect(rig.canvas.document.elementById(id)!.track!.keys, hasLength(2));
    });

    test("several elements are one step to undo", () async {
      var rig = _Rig();
      await rig.on();
      await rig.json("canvas_add_element", {
        "elements": [
          {"kind": "shape"},
          {
            "kind": "text",
            "props": {"text": "A"}
          },
        ]
      });
      expect(rig.canvas.document.elements, hasLength(2));
      rig.canvas.undo();
      expect(rig.canvas.document.elements, isEmpty);
    });

    test("undo all puts the canvas back as it was before Claude", () async {
      var rig = _Rig();
      await rig.on();
      var before = rig.canvas.document;
      await rig.json("canvas_add_element", {"kind": "shape"});
      await rig.json("canvas_add_element", {"kind": "text"});
      expect(rig.ai.hasCheckpoint, isTrue);
      rig.ai.undoCanvas();
      expect(rig.canvas.document.elements, isEmpty);
      expect(rig.ai.hasCheckpoint, isFalse);
      // Itself a step: Undo brings Claude's work back.
      rig.canvas.undo();
      expect(rig.canvas.document.elements, hasLength(2));
      expect(identical(before, rig.canvas.document), isFalse);
    });

    test("describe gives the keys a kind's reader asks for", () async {
      var rig = _Rig();
      await rig.on();
      var kinds = await rig.json("canvas_describe") as Map;
      expect([for (var k in kinds["kinds"] as List) k["kind"]],
          containsAll(["text", "shape", "chart", "audio"]));
      var text = await rig.json("canvas_describe", {"kind": "text"}) as Map;
      expect((text["example"] as Map)["kind"], "text");
      expect(text["keys"] as Map, containsPair("text", isNotNull));
      expect((text["keys"] as Map).keys,
          containsAll(["textSpec", "animation", "track"]));
      var spec = await rig.json(
          "canvas_describe", {"kind": "text", "path": "/textSpec"}) as Map;
      expect(
          (spec["keys"] as Map).keys, containsAll(["size", "font", "color"]));
      var doc = await rig.json("canvas_describe", {"document": true}) as Map;
      expect((doc["keys"] as Map).keys, containsAll(["masterMix", "session"]));
    });

    test("the document's own settings change; its elements do not that way",
        () async {
      var rig = _Rig();
      await rig.on();
      await rig.json("canvas_update", {
        "target": "document",
        "patch": {"frameRate": 30, "frames": 96},
      });
      expect(rig.canvas.document.frameRate, 30);
      expect(rig.canvas.document.frames, 96);
      var r = await rig.call("canvas_update", {
        "target": "document",
        "patch": {"elements": []},
      });
      expect(r["isError"], isTrue);
    });

    test("scenes are added and named; delete and arrange work by id", () async {
      var rig = _Rig();
      await rig.on();
      var a = ((await rig.json("canvas_add_element", {"kind": "shape"})
              as Map)["added"] as List)
          .single["id"];
      var b = ((await rig.json("canvas_add_element", {"kind": "text"})
              as Map)["added"] as List)
          .single["id"];
      var moved = await rig.call("canvas_arrange", {"id": b, "to": "back"});
      expect(moved["isError"], isNot(true));
      expect(rig.canvas.document.elements.first.id, b);
      await rig.call("canvas_delete_elements", {
        "ids": [a]
      });
      expect(rig.canvas.document.elements.map((e) => e.id), [b]);

      await rig.call("canvas_scene", {"action": "add"});
      expect(rig.canvas.document.allScenes, hasLength(2));
      await rig.json("canvas_update", {
        "target": "scene",
        "patch": {"name": "Ending"},
      });
      expect(rig.canvas.document.scene.name, "Ending");
      // The first scene's element is still there.
      expect(
          rig.canvas.document.allScenes.first.elements.map((e) => e.id), [b]);
    });

    test("errors say what to do", () async {
      var rig = _Rig();
      await rig.on();
      var r = await rig.call("canvas_add_element", {"kind": "unicorn"});
      expect(r["isError"], isTrue);
      expect("${r["content"]}", contains("Kinds:"));
      r = await rig.call("canvas_get", {"target": "nope"});
      expect(r["isError"], isTrue);
      r = await rig
          .call("canvas_get", {"target": "document", "path": "/nothing"});
      expect(r["isError"], isTrue);
    });

    test("render gives a picture", () async {
      var rig = _Rig();
      await rig.on();
      await rig.json("canvas_add_element", {"kind": "shape"});
      var r = await rig.call("canvas_render", {"maxSide": 256});
      expect(r["isError"], isNot(true));
      var image =
          (r["content"] as List).firstWhere((c) => c["type"] == "image");
      expect(image["mimeType"], "image/png");
      expect(base64Decode(image["data"] as String).sublist(1, 4),
          utf8.encode("PNG"));
    });
  });

  group("writing tools", () {
    _Rig withText(String text) {
      var rig = _Rig();
      rig.composer.attach(TextEditingController(text: text)
        ..selection = const TextSelection(baseOffset: 4, extentOffset: 9));
      return rig;
    }

    test("read the document and the selection", () async {
      var rig = withText("The quick brown fox.");
      await rig.on();
      var doc = await rig.json("writing_get_document") as Map;
      expect(doc["text"], "The quick brown fox.");
      expect((doc["selection"] as Map)["text"], "quick");
    });

    test("an edit waits to be accepted, then goes in", () async {
      var rig = withText("The quick brown fox.");
      await rig.on();
      var r = await rig.call("writing_edit", {
        "edits": [
          {"find": "brown", "replacement": "red", "note": "colour"}
        ]
      });
      expect(r["isError"], isNot(true));
      expect(rig.composer.editor!.text, "The quick brown fox.");
      var s = rig.ai.suggestions.items.single;
      expect(s.original, "brown");
      expect(rig.ai.suggestions.accept(s.id), isNull);
      expect(rig.composer.editor!.text, "The quick red fox.");
    });

    test("a waiting edit follows its text when the writer types before it",
        () async {
      var rig = withText("The quick brown fox.");
      await rig.on();
      await rig.call("writing_insert", {"text": " Jumps.", "at": "end"});
      await rig.call("writing_edit", {
        "edits": [
          {"find": "fox", "replacement": "cat"}
        ]
      });
      var editor = rig.composer.editor!;
      editor.text = "Look: ${editor.text}";
      expect(rig.ai.suggestions.acceptAll(), 0);
      expect(editor.text, "Look: The quick brown cat. Jumps.");
    });

    test("a short edit is found by the words around it, not the first match",
        () async {
      var rig = withText("A cat sat. The cat ran.");
      await rig.on();
      await rig.call("writing_edit", {
        "edits": [
          {"find": "cat", "occurrence": 2, "replacement": "dog"}
        ]
      });
      var editor = rig.composer.editor!;
      editor.text = "Here: ${editor.text}";
      expect(rig.ai.suggestions.acceptAll(), 0);
      expect(editor.text, "Here: A cat sat. The dog ran.");
    });

    test("an edit whose text is gone is refused, not pasted elsewhere",
        () async {
      var rig = withText("The quick brown fox.");
      await rig.on();
      await rig.call("writing_edit", {
        "edits": [
          {"find": "brown", "replacement": "red"}
        ]
      });
      rig.composer.editor!.text = "Something else entirely.";
      var s = rig.ai.suggestions.items.single;
      expect(rig.ai.suggestions.accept(s.id), isNotNull);
      expect(rig.composer.editor!.text, "Something else entirely.");
    });

    test("with changes put straight in, an edit goes in at once", () async {
      var rig = withText("The quick brown fox.");
      await rig.on();
      rig.prefs.applyEdits = true;
      await rig.call("writing_edit", {
        "edits": [
          {"start": 4, "end": 9, "find": "quick", "replacement": "slow"}
        ]
      });
      expect(rig.composer.editor!.text, "The slow brown fox.");
      expect(rig.ai.suggestions.items, isEmpty);
    });

    test("with no document open, the tools say so", () async {
      var rig = _Rig();
      await rig.on();
      var r = await rig.call("writing_get_document");
      expect(r["isError"], isTrue);
      expect("${r["content"]}", contains("Writing page"));
    });
  });

  group("over HTTP", () {
    setUp(() => HttpOverrides.global = null);

    test("needs the token, and refuses a web page", () async {
      var rig = _Rig();
      await rig.prefs.load();
      var server = McpServer(
        tools: () => rig.ai.tools,
        instructions: () => "",
        callerFor: (t) => t == "good" ? _caller : null,
      );
      var port = await server.start(48715);
      addTearDown(server.stop);
      var client = HttpClient();
      addTearDown(client.close);

      Future<HttpClientResponse> post(Map<String, String> headers) async {
        var req = await client.postUrl(Uri.parse("http://127.0.0.1:$port/mcp"));
        headers.forEach(req.headers.set);
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode({"jsonrpc": "2.0", "id": 1, "method": "ping"}));
        return req.close();
      }

      expect((await post({})).statusCode, HttpStatus.unauthorized);
      expect((await post({"Authorization": "Bearer bad"})).statusCode,
          HttpStatus.unauthorized);
      expect(
          (await post({
            "Authorization": "Bearer good",
            "Origin": "https://evil.example"
          }))
              .statusCode,
          HttpStatus.forbidden);
      var ok = await post({"Authorization": "Bearer good"});
      expect(ok.statusCode, HttpStatus.ok);
      var body = jsonDecode(await utf8.decodeStream(ok)) as Map;
      expect(body["result"], {});
    });
  });
}
