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
  // The drawn characters are an asset, read through the binding.
  TestWidgetsFlutterBinding.ensureInitialized();
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

  test("Claude draws a character from a drawn style, credited", () async {
    var styles = json(await call("canvas_drawn_styles")) as List;
    var peeps = styles.firstWhere((s) => s["style"] == "open-peeps");
    expect((peeps["parts"] as Map).keys, contains("head"));

    var r = await call("canvas_draw_character", {
      "style": "open-peeps",
      "parts": {"accessories": "sunglasses", "wings": "big"},
      "colours": {"clothing": "#1B4F72"},
      "seed": 4,
    });
    expect(r["isError"], isNot(true), reason: "${r["content"]}");
    expect("${r["content"]}", contains("no part wings"));
    expect(canvas.document.elements.single.kind, ElementKind.vector);
    var drawings = json(await call("canvas_assets", {"kind": "vector"}));
    expect((drawings as List).single["author"] ?? drawings.single["credit"],
        isNotNull);

    var none = await call("canvas_draw_character", {"style": "dragons"});
    expect(none["isError"], isTrue);
  });

  test("Claude draws a picture as SVG, kept in the library", () async {
    const svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
        '<circle cx="50" cy="50" r="40" fill="#E8590C"/></svg>';
    var r = await call("canvas_draw_svg", {"name": "Sun", "svg": svg});
    expect(r["isError"], isNot(true), reason: "${r["content"]}");
    expect(canvas.document.elements.single.kind, ElementKind.vector);
    var drawings =
        json(await call("canvas_assets", {"kind": "vector"})) as List;
    expect(drawings.single["name"], "Sun");

    for (var bad in [
      "not a drawing",
      '<svg><script>alert(1)</script></svg>',
      '<svg><image href="https://example.com/x.png"/></svg>',
    ]) {
      var refused = await call("canvas_draw_svg", {"name": "x", "svg": bad});
      expect(refused["isError"], isTrue, reason: bad);
    }
  });
}
