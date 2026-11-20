import 'dart:convert';
import 'dart:io';

import 'package:bruig/plugin_system/canvas/canvas.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_adjustment.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/saved_preset_store.dart';
import 'package:bruig/plugin_system/creative_ai/creative_ai_model.dart';
import 'package:bruig/plugin_system/creative_ai/creative_ai_preferences.dart';
import 'package:bruig/plugin_system/creative_ai/mcp/mcp_server.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// creative_ai_image_test.dart covers what Claude can do to a picture: do an
// action, write its own as steps, and keep a look as an action -- each a
// step of the person's Undo, every step a layer they can change.

void main() {
  late Directory root;
  late CanvasController canvas;
  late CreativeAi ai;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp("creative_ai_image");
    CanvasStorage.rootOverride = root.path;
    SavedPresetStore.looks.forget();
    canvas = CanvasController(emptyCanvas().addElement(const ImageElement(
        ElementBase(id: "pic", x: 0, y: 0, width: 400, height: 300),
        assetId: "photo")));
    var canvasPrefs = CanvasPreferences()..enabled = true;
    ai = CreativeAi(
      prefs: CreativeAiPreferences()..enabled = true,
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
    SavedPresetStore.looks.forget();
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

  String text(Map<String, dynamic> r) =>
      ((r["content"] as List).first as Map)["text"] as String;

  ImageElement pic() => canvas.document.elementById("pic")! as ImageElement;

  test("the reference names every kind, and the actions are listed", () async {
    var ref = jsonDecode(text(await call("image_reference"))) as Map;
    expect((ref["adjustments"] as Map).keys,
        containsAll(["colourTable", "oilPaint", "colourMixer"]));
    expect(ref["filmTables"], isNotEmpty);
    var actions = jsonDecode(text(await call("image_actions"))) as List;
    var glow = actions.firstWhere((a) => a["name"] == "Orton glow");
    expect(glow["steps"], contains("Copy of the picture"));
  });

  test("an action is done to a picture, and undone in one step", () async {
    var r =
        await call("image_do_action", {"id": "pic", "action": "Orton glow"});
    expect(r["isError"], isNot(true), reason: text(r));
    expect(pic().stack.where((l) => isPictureCopy(pic(), l)), hasLength(1));
    expect(ai.hasCheckpoint, isTrue);
    canvas.undo();
    expect(pic().stack, hasLength(1));

    var missing =
        await call("image_do_action", {"id": "pic", "action": "Nope"});
    expect(missing["isError"], isTrue);
  });

  test("steps are made, and what cannot be is named", () async {
    var r = await call("image_add_steps", {
      "id": "pic",
      "steps": [
        {
          "step": "adjust",
          "kind": "colourBalance",
          "values": {"shadowsBlue": 0.5}
        },
        {
          "step": "copy",
          "blend": "screen",
          "opacity": 0.5,
          "effects": [
            {
              "kind": "blur",
              "values": {"amount": 20}
            }
          ]
        },
        {"step": "adjust", "kind": "findEdges", "clip": true},
        {"step": "adjust", "kind": "colourTable", "table": "sepia"},
        {"step": "texture", "kind": "grain"},
        {"step": "adjust", "kind": "sparkles"},
      ],
    });
    expect(r["isError"], isNot(true), reason: text(r));
    expect(text(r), contains("Made 5 steps"));
    expect(text(r), contains("sparkles"));
    var stack = pic().stack;
    expect(stack[1].adjust.kind, AdjustKind.colourBalance);
    expect(isPictureCopy(pic(), stack[2]), isTrue);
    expect(stack[2].blend, LayerBlend.screen);
    expect(stack[3].clip, isTrue);
    expect(stack[4].adjust.table, "sepia");

    var layers = jsonDecode(text(await call("image_layers", {"id": "pic"})));
    expect((layers["layers"] as List).first["step"], "Film grain");

    var bad = await call("image_add_steps", {
      "id": "pic",
      "steps": [
        {"step": "adjust", "kind": "sparkles"}
      ]
    });
    expect(bad["isError"], isTrue);
  });

  test("a look made is kept as an action", () async {
    await call("image_add_steps", {
      "id": "pic",
      "steps": [
        {"step": "adjust", "kind": "sharpen"},
      ],
    });
    var r = await call("image_save_action", {"id": "pic", "name": "Crisp"});
    expect(r["isError"], isNot(true), reason: text(r));
    expect(SavedPresetStore.looks.presets.single.name, "Crisp");
    var actions = jsonDecode(text(await call("image_actions"))) as List;
    expect(actions.last["name"], "Crisp");
  });
}
