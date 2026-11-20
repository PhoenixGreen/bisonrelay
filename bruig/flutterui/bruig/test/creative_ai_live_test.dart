import 'dart:io';

import 'package:bruig/plugin_system/canvas/canvas.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/image_action_file.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/saved_preset_store.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/creative_ai/creative_ai_model.dart';
import 'package:bruig/plugin_system/creative_ai/creative_ai_preferences.dart';
import 'package:bruig/plugin_system/creative_ai/session/ai_chat.dart';
import 'package:bruig/plugin_system/creative_ai/tools/guide.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// creative_ai_live_test.dart runs the real thing: Claude Code on this
// computer, signed in to a Claude plan, given Creative AI's MCP server, asked
// from the Canvas sidebar's conversation to change a canvas. It uses a little
// of the plan, so it runs only when asked:
//
//   CREATIVE_AI_LIVE=1 flutter test test/creative_ai_live_test.dart

void main() {
  // The app's bundled assets (drawn characters, film tables) are read
  // through the binding, as they are in the app.
  TestWidgetsFlutterBinding.ensureInitialized();
  var live = Platform.environment["CREATIVE_AI_LIVE"] == "1";

  test("Claude Code adds to the canvas through the sidebar", () async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    var prefs = CreativeAiPreferences();
    await prefs.load();
    prefs.port = 47915;
    prefs.chatModel = ClaudeModel.haiku;
    var canvasPrefs = CanvasPreferences()..enabled = true;
    var canvas = CanvasController(emptyCanvas());
    var ai = CreativeAi(
      prefs: prefs,
      canvas: () => canvas,
      canvasPrefs: () => canvasPrefs,
      composer: () => ComposerSidebarController(),
      library: () => PostLibraryModel(),
    );
    addTearDown(ai.dispose);
    prefs.enabled = true;
    for (var i = 0; i < 50 && !ai.server.running; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    expect(ai.server.running, isTrue, reason: ai.serverError);
    expect(await ai.findClaude(), isNotNull,
        reason: "Claude Code is not installed here");

    await ai.canvasChat
        .send("Add one text element that says Hello Bison, then reply with one "
            "short sentence.");
    for (var e in ai.canvasChat.entries) {
      // ignore: avoid_print
      print("${e.role.name}: ${e.text}");
    }
    expect(
        ai.canvasChat.entries.where((e) => e.role == ChatRole.error), isEmpty);
    expect(ai.canvasChat.entries.where((e) => e.role == ChatRole.tool),
        isNotEmpty);
    var texts = canvas.document.elements.whereType<TextElement>();
    expect(texts.map((t) => t.text).join(" "), contains("Hello Bison"));
    expect(ai.activity.calls.map((c) => c.caller.source),
        contains("Canvas sidebar"));
    expect(ai.hasCheckpoint, isTrue);
  },
      skip: live ? false : "Set CREATIVE_AI_LIVE=1 to run against Claude Code",
      timeout: const Timeout(Duration(minutes: 4)));

  test("Claude studies a canvas and saves its style with a guide", () async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    var dir = await Directory.systemTemp.createTemp("styles");
    addTearDown(() => dir.delete(recursive: true));
    var prefs = CreativeAiPreferences();
    await prefs.load();
    prefs.port = 47925;
    prefs.chatModel = ClaudeModel.haiku;
    var canvasPrefs = CanvasPreferences()..enabled = true;
    var canvas = CanvasController(emptyCanvas());
    var a = CanvasAutomation(canvas);
    a.addElementJson(Map<String, dynamic>.from(a.newElementJson("text")!)
      ..addAll({
        "text": "QUARTERLY REPORT",
        "textSpec": {
          "font": "PT Serif",
          "size": 72,
          "weight": 700,
          "color": 0xFFE8590C
        },
      }));
    var ai = CreativeAi(
      prefs: prefs,
      canvas: () => canvas,
      canvasPrefs: () => canvasPrefs,
      composer: () => ComposerSidebarController(),
      library: () => PostLibraryModel(),
      stylesRoot: () async => dir.path,
    );
    addTearDown(ai.dispose);
    prefs.enabled = true;
    for (var i = 0; i < 50 && !ai.server.running; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    await ai.canvasChat.send(saveStylePrompt("Orange Report", ""));
    for (var e in ai.canvasChat.entries) {
      // ignore: avoid_print
      print("${e.role.name}: ${e.text}");
    }
    var style = await ai.styles.byName("Orange Report");
    expect(style, isNotNull);
    // ignore: avoid_print
    print("GUIDE:\n${style!.guide}");
    expect(style.guide.length, greaterThan(200));
    expect(
        style.guide,
        isNot(startsWith("# Orange Report\n\nA Bison Relay "
            "canvas style, measured")),
        reason: "Claude wrote it, not the facts");
    expect(style.colours, contains(0xFFE8590C));
  },
      skip: live ? false : "Set CREATIVE_AI_LIVE=1 to run against Claude Code",
      timeout: const Timeout(Duration(minutes: 4)));

  test("Claude draws a picture with SVG", () async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    var root = await Directory.systemTemp.createTemp("live_draw");
    addTearDown(() => root.delete(recursive: true));
    CanvasStorage.rootOverride = root.path;
    addTearDown(() => CanvasStorage.rootOverride = null);
    var prefs = CreativeAiPreferences();
    await prefs.load();
    prefs.port = 47935;
    prefs.chatModel = ClaudeModel.haiku;
    var canvasPrefs = CanvasPreferences()..enabled = true;
    var canvas = CanvasController(emptyCanvas());
    var ai = CreativeAi(
      prefs: prefs,
      canvas: () => canvas,
      canvasPrefs: () => canvasPrefs,
      composer: () => ComposerSidebarController(),
      library: () => PostLibraryModel(),
    );
    addTearDown(ai.dispose);
    prefs.enabled = true;
    for (var i = 0; i < 50 && !ai.server.running; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    await ai.canvasChat.send("Draw a bison's head as a simple flat icon and "
        "put it in the top right corner, about 200 pixels across.");
    for (var e in ai.canvasChat.entries) {
      // ignore: avoid_print
      print("${e.role.name}: ${e.text}");
    }
    expect(
        canvas.document.elements.map((e) => e.kind.name), contains("vector"));
  },
      skip: live ? false : "Set CREATIVE_AI_LIVE=1 to run against Claude Code",
      timeout: const Timeout(Duration(minutes: 4)));

  test("Claude grades a photograph and keeps the look as an action", () async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    var root = await Directory.systemTemp.createTemp("live_image");
    addTearDown(() => root.delete(recursive: true));
    CanvasStorage.rootOverride = root.path;
    addTearDown(() => CanvasStorage.rootOverride = null);
    // A real photograph: the one given in CREATIVE_AI_PHOTO.
    var bytes =
        File(Platform.environment["CREATIVE_AI_PHOTO"]!).readAsBytesSync();
    var id = (await CanvasAssets.save(bytes))!;
    await CanvasLibrary.addPicture(id, "Ballot box", bytes);
    var prefs = CreativeAiPreferences();
    await prefs.load();
    prefs.port = 47945;
    prefs.chatModel = ClaudeModel.opus;
    var canvasPrefs = CanvasPreferences()..enabled = true;
    var canvas = CanvasController(emptyCanvas().addElement(ImageElement(
        const ElementBase(id: "photo", x: 160, y: 90, width: 960, height: 640),
        assetId: id)));
    var ai = CreativeAi(
      prefs: prefs,
      canvas: () => canvas,
      canvasPrefs: () => canvasPrefs,
      composer: () => ComposerSidebarController(),
      library: () => PostLibraryModel(),
    );
    addTearDown(ai.dispose);
    prefs.enabled = true;
    for (var i = 0; i < 50 && !ai.server.running; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    var before = await CanvasAutomation(canvas).renderPng(frame: 0);
    File("${Platform.environment["CREATIVE_AI_OUT"]}/live_before.png")
        .writeAsBytesSync(before!);
    await ai.canvasChat.send("Give the photograph a moody cinematic look: "
        "teal shadows, warm highlights, a little film grain and a soft "
        "vignette. Look at it as you go. When it looks right, keep the look "
        "as an action called Moody Teal.");
    for (var e in ai.canvasChat.entries) {
      // ignore: avoid_print
      print("${e.role.name}: ${e.text}");
    }
    var after = await CanvasAutomation(canvas).renderPng(frame: 0);
    File("${Platform.environment["CREATIVE_AI_OUT"]}/live_after.png")
        .writeAsBytesSync(after!);
    var e = canvas.document.elementById("photo")! as ImageElement;
    // ignore: avoid_print
    print("LAYERS: ${[for (var l in e.stack) stepLabel(e, l)]}");
    expect(e.stack.where((l) => inLook(e, l)), isNotEmpty);
    await SavedPresetStore.looks.load();
    expect(SavedPresetStore.looks.presets.map((p) => p.name),
        contains("Moody Teal"));
  },
      skip: live ? false : "Set CREATIVE_AI_LIVE=1 to run against Claude Code",
      timeout: const Timeout(Duration(minutes: 10)));

  test("Claude draws a character to a description", () async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    var root = await Directory.systemTemp.createTemp("live_character");
    addTearDown(() => root.delete(recursive: true));
    CanvasStorage.rootOverride = root.path;
    addTearDown(() => CanvasStorage.rootOverride = null);
    var prefs = CreativeAiPreferences();
    await prefs.load();
    prefs.port = 47955;
    prefs.chatModel = ClaudeModel.haiku;
    var canvasPrefs = CanvasPreferences()..enabled = true;
    var canvas = CanvasController(emptyCanvas());
    var ai = CreativeAi(
      prefs: prefs,
      canvas: () => canvas,
      canvasPrefs: () => canvasPrefs,
      composer: () => ComposerSidebarController(),
      library: () => PostLibraryModel(),
    );
    addTearDown(ai.dispose);
    prefs.enabled = true;
    for (var i = 0; i < 50 && !ai.server.running; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    await ai.canvasChat.send("Add a pixel-art character wearing a red hat "
        "and glasses to the canvas.");
    for (var e in ai.canvasChat.entries) {
      // ignore: avoid_print
      print("${e.role.name}: ${e.text}");
    }
    var png = await CanvasAutomation(canvas).renderPng(frame: 0);
    File("${Platform.environment["CREATIVE_AI_OUT"]}/live_character.png")
        .writeAsBytesSync(png!);
    expect(ai.activity.calls.map((c) => c.tool.name),
        contains("canvas_draw_character"));
    expect(
        canvas.document.elements.map((e) => e.kind.name), contains("vector"));
  },
      skip: live ? false : "Set CREATIVE_AI_LIVE=1 to run against Claude Code",
      timeout: const Timeout(Duration(minutes: 4)));
}
