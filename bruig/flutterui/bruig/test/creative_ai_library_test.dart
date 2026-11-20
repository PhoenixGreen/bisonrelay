import 'dart:convert';
import 'dart:io';

import 'package:bruig/plugin_system/canvas/canvas.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_network.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/creative_ai/creative_ai_model.dart';
import 'package:bruig/plugin_system/creative_ai/creative_ai_preferences.dart';
import 'package:bruig/plugin_system/creative_ai/mcp/mcp_server.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// creative_ai_library_test.dart covers what Claude can bring onto a canvas
// besides what it makes: the person's library, the presets, and stock --
// which keeps to Canvas's own rule that nothing is fetched unless allowed.

const picture = "0123456789abcdef.png";

void main() {
  late Directory root;
  late CanvasController canvas;
  late CanvasPreferences canvasPrefs;
  late CreativeAi ai;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp("creative_ai_library");
    CanvasStorage.rootOverride = root.path;
    CanvasLibrary.resetForTest();
    proxiedForTest = false;
    await CanvasLibrary.add(LibraryAsset(
        id: picture,
        kind: AssetKind.picture,
        name: "Club badge",
        added: DateTime(2026, 11, 20),
        width: 200,
        height: 100));
    canvas = CanvasController(emptyCanvas());
    canvasPrefs = CanvasPreferences()..enabled = true;
    var prefs = CreativeAiPreferences()..enabled = true;
    ai = CreativeAi(
      prefs: prefs,
      canvas: () => canvas,
      canvasPrefs: () => canvasPrefs,
      composer: () => ComposerSidebarController(),
      library: () => PostLibraryModel(),
      serve: false,
    );
  });

  tearDown(() async {
    ai.dispose();
    CanvasStorage.rootOverride = null;
    proxiedForTest = null;
    await root.delete(recursive: true);
  });

  Future<Map<String, dynamic>> call(String tool,
      [Map<String, Object?> args = const {}]) async {
    var r = await ai.server.handle({
      "jsonrpc": "2.0",
      "id": 1,
      "method": "tools/call",
      "params": {"name": tool, "arguments": args},
    }, const McpCaller("Test")) as Map;
    return Map<String, dynamic>.from(r["result"] as Map);
  }

  Object? json(Map<String, dynamic> r) =>
      jsonDecode(((r["content"] as List).first as Map)["text"] as String);

  test("the library is listed and a file put on the canvas", () async {
    var list = json(await call("canvas_assets", {"kind": "picture"})) as List;
    expect(list.single["name"], "Club badge");
    expect(list.single["width"], 200);

    var used = await call("canvas_use_asset", {"id": picture});
    expect(used["isError"], isNot(true), reason: "${used["content"]}");
    expect(canvas.document.elements.single.kind, ElementKind.image);
    // One step to undo, and Claude's to undo all at once.
    expect(ai.hasCheckpoint, isTrue);
    canvas.undo();
    expect(canvas.document.elements, isEmpty);

    var missing = await call("canvas_use_asset", {"id": "nope.png"});
    expect(missing["isError"], isTrue);
  });

  test("presets are listed and used: an element, a canvas's scenes", () async {
    var list = json(await call("canvas_presets")) as List;
    var element = list.firstWhere((p) => "${p["id"]}".startsWith("element:"));
    var aCanvas = list.firstWhere((p) => "${p["id"]}".startsWith("canvas:"));

    var used = await call("canvas_use_preset", {"id": element["id"]});
    expect(used["isError"], isNot(true), reason: "${used["content"]}");
    expect(canvas.document.elements, hasLength(1));

    var scenes = canvas.document.allScenes.length;
    used = await call("canvas_use_preset", {"id": aCanvas["id"]});
    expect(used["isError"], isNot(true), reason: "${used["content"]}");
    expect(canvas.document.allScenes.length, greaterThan(scenes));

    var missing = await call("canvas_use_preset", {"id": "element:nope"});
    expect(missing["isError"], isTrue);
  });

  test("stock keeps Canvas's rule: nothing is fetched unless allowed",
      () async {
    var sources = json(await call("canvas_stock_sources")) as Map;
    expect((sources["sources"] as List).map((s) => s["source"]),
        contains("pixabayPictures"));
    expect(sources["fetching"], contains("switched off"));

    var r = await call(
        "canvas_stock_search", {"source": "pixabayPictures", "text": "bison"});
    expect(r["isError"], isTrue);
    expect("${r["content"]}", contains("Fetching is switched off"));

    canvasPrefs.allowFetching = true;
    proxiedForTest = true;
    r = await call(
        "canvas_stock_search", {"source": "pixabayPictures", "text": "bison"});
    expect("${r["content"]}", contains("proxy"));

    r = await call("canvas_stock_use", {"id": "pixabayPictures:1"});
    expect(r["isError"], isTrue);
    expect("${r["content"]}", contains("Search for it first"));
  });
}
