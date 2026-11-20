import 'dart:io';

import 'package:bruig/plugin_system/canvas/canvas.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/creative_ai/creative_ai_model.dart';
import 'package:bruig/plugin_system/creative_ai/creative_ai_preferences.dart';
import 'package:bruig/plugin_system/creative_ai/session/ai_chat.dart';
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
}
