import 'dart:convert';
import 'dart:io';

import 'package:bruig/plugin_system/canvas/canvas.dart';
import 'package:bruig/plugin_system/creative_ai/creative_ai_model.dart';
import 'package:bruig/plugin_system/creative_ai/creative_ai_preferences.dart';
import 'package:bruig/plugin_system/creative_ai/engine/style_facts.dart';
import 'package:bruig/plugin_system/creative_ai/mcp/mcp_server.dart';
import 'package:bruig/plugin_system/creative_ai/session/style_library.dart';
import 'package:bruig/plugin_system/creative_ai/ui/canvas_ai_sidebar.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/canvas_app.dart';

// creative_ai_styles_test.dart covers style profiles: what is measured from a
// canvas, the folder each is kept in (laid out as a Claude skill), the tools
// Claude uses to list, read and save them, and the Styles panel's controls.

const _headline = 0xFFE8590C, _paper = 0xFF101820;

/// _styled is a canvas with a headline, a smaller line and a shape, two
/// seconds long, the shape arriving with fadeUp.
CanvasController _styled() {
  var c = CanvasController(emptyCanvas());
  var a = CanvasAutomation(c);
  Map<String, dynamic> made(String kind, Map<String, dynamic> props) =>
      Map<String, dynamic>.from(a.newElementJson(kind)!)..addAll(props);
  a.addElementJson(made("text", {
    "text": "Big news",
    "textSpec": {
      "font": "PT Serif",
      "size": 80,
      "weight": 700,
      "color": _headline
    },
  }));
  a.addElementJson(made("text", {
    "text": "The detail underneath",
    "textSpec": {"font": "Inter", "size": 30, "weight": 400, "color": _paper},
  }));
  a.addElementJson(made("shape", {
    "fill": _headline,
    "anim": {"preset": "fadeUp", "length": 12},
  }));
  var doc = a.documentJson()..["frames"] = 48;
  a.replaceDocumentJson(doc);
  return c;
}

Map<String, Object?> _facts(CanvasController c) =>
    styleFactsOf(CanvasAutomation(c).documentJson(),
        width: c.document.size.width.toDouble(),
        height: c.document.size.height.toDouble());

class _Rig {
  final Directory dir;
  final prefs = CreativeAiPreferences();
  final canvasPrefs = CanvasPreferences();
  final CanvasController canvas;
  late final CreativeAi ai = CreativeAi(
    prefs: prefs,
    canvas: () => canvas,
    canvasPrefs: () => canvasPrefs,
    composer: () => ComposerSidebarController(),
    library: () => PostLibraryModel(),
    serve: false,
    locateClaude: (_) async => null,
    stylesRoot: () async => dir.path,
  );
  _Rig(this.dir, this.canvas) {
    canvasPrefs.enabled = true;
    prefs.enabled = true;
  }

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

  static Object? text(Map<String, dynamic> r) =>
      jsonDecode(((r["content"] as List).first as Map)["text"] as String);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group("measuring a style", () {
    test("palette, type from the headline down, motion and samples", () {
      var facts = _facts(_styled());
      var palette = facts["palette"] as List;
      expect(palette.first["argb"], _headline, reason: "used most");
      expect(palette.map((c) => c["hex"]), contains("#E8590C"));
      expect(palette.map((c) => c["argb"]), contains(_paper));

      var type = facts["type"] as List;
      expect(type[0]["role"], "headline");
      expect(type[0]["font"], "PT Serif");
      expect(type[0]["size"], 80);
      expect(type[0]["example"], "Big news");
      expect(type[1]["font"], "Inter");

      var motion = facts["motion"] as Map;
      expect(motion["arrivals"], {"fadeUp": 1});
      expect(motion["sceneSeconds"], 2.0);

      var samples = facts["samples"] as List;
      expect(samples.map((s) => s["kind"]), containsAll(["text", "shape"]));
      expect(samples.first["text"], "Big news");
    });

    test("the factual guide says what was measured", () {
      var guide = factualGuide("Orange news", _facts(_styled()));
      expect(guide, contains("# Orange news"));
      expect(guide, contains("#E8590C"));
      expect(guide, contains("PT Serif"));
      expect(guide, contains("fadeUp"));
    });
  });

  group("the folder", () {
    test("a slug is a folder name", () {
      expect(slugOf("Noir Report — 2026!"), "noir-report-2026");
      expect(slugOf("  "), "style");
    });

    test("SKILL.md is a Claude skill, and reads back to its guide", () {
      var md = skillMarkdown(
          slug: "noir",
          name: "Noir",
          description: "Dark reports",
          guide: "Use black.");
      expect(md, startsWith("---\nname: bisonrelay-style-noir\ndescription: "));
      expect(md, contains("Dark reports"));
      expect(guideOf(md), "Use black.");
    });

    test("saved, listed, found, edited, copied to skills and deleted",
        () async {
      var dir = await Directory.systemTemp.createTemp("styles");
      addTearDown(() => dir.delete(recursive: true));
      var lib = StyleLibrary(() async => dir.path);
      var s = await lib.save(
          name: "Noir Report",
          description: "Dark",
          guide: "Black and gold.",
          facts: _facts(_styled()));
      expect(s.slug, "noir-report");
      expect(s.colours.first, _headline);
      expect(s.fonts, ["PT Serif", "Inter"]);

      var again = StyleLibrary(() async => dir.path);
      await again.refresh();
      expect(again.styles.single.guide, "Black and gold.");
      expect(await again.byName("Noir Report"), isNotNull);
      expect(await again.byName("noir-report"), isNotNull);

      await again.updateGuide(again.styles.single,
          guide: "Black, gold, and nothing else.", description: "Darker");
      expect(again.styles.single.guide, "Black, gold, and nothing else.");
      expect(again.styles.single.description, "Darker");

      var skills = await Directory.systemTemp.createTemp("skills");
      addTearDown(() => skills.delete(recursive: true));
      var into =
          await again.copyToSkills(again.styles.single, skillsDir: skills.path);
      expect(File("$into/SKILL.md").readAsStringSync(),
          contains("name: bisonrelay-style-noir-report"));
      expect(File("$into/style.json").existsSync(), isTrue);

      await again.delete(again.styles.single);
      expect(again.styles, isEmpty);
    });
  });

  group("tools", () {
    test("save the canvas, list, and read it back", () async {
      var dir = await Directory.systemTemp.createTemp("styles");
      addTearDown(() => dir.delete(recursive: true));
      var rig = _Rig(dir, _styled());
      addTearDown(rig.ai.dispose);

      var saved = await rig.call("canvas_style_save",
          {"name": "Orange News", "description": "Bold headlines"});
      expect(saved["isError"], isNot(true), reason: "${saved["content"]}");
      expect(File("${dir.path}/styles/orange-news/preview.png").existsSync(),
          isTrue);

      var list = _Rig.text(await rig.call("canvas_styles")) as Map;
      expect((list["styles"] as List).single["name"], "Orange News");

      var got = _Rig.text(
          await rig.call("canvas_style_get", {"style": "Orange News"})) as Map;
      expect(got["guide"], contains("PT Serif"), reason: "the factual guide");
      expect(
          ((got["facts"] as Map)["palette"] as List).first["argb"], _headline);

      // A guide written by Claude replaces it.
      await rig.call("canvas_style_save",
          {"name": "Orange News", "guide": "Orange for what matters."});
      got = _Rig.text(
          await rig.call("canvas_style_get", {"style": "orange-news"})) as Map;
      expect(got["guide"], "Orange for what matters.");

      var missing = await rig.call("canvas_style_get", {"style": "nope"});
      expect(missing["isError"], isTrue);
    });
  });

  group("the Styles panel", () {
    /// idle lets real file I/O finish inside a widget test: see
    /// flutter_test_real_io in the notes.
    Future<void> idle(WidgetTester tester) async {
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 4)));
        await tester.pump();
      }
    }

    testWidgets("use a style in the conversation, restyle, and save",
        (tester) async {
      var dir = (await tester
          .runAsync(() => Directory.systemTemp.createTemp("styles")))!;
      addTearDown(() => dir.deleteSync(recursive: true));
      var canvas = _styled();
      var rig = _Rig(dir, canvas);
      await tester.runAsync(() => rig.ai.styles.save(
          name: "Noir",
          description: "Dark",
          guide: "Black.",
          facts: _facts(canvas)));

      setTestScreen(tester, const Size(420, 1400));
      await tester.pumpWidget(canvasApp(
          SizedBox(width: 400, child: CanvasAiSidebar(controller: canvas)),
          prefs: rig.canvasPrefs,
          extra: [ChangeNotifierProvider<CreativeAi>.value(value: rig.ai)]));
      await idle(tester);

      expect(find.byKey(const ValueKey("style-noir")), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("styleUse-noir")));
      await tester.pump();
      expect(rig.ai.styles.active?.slug, "noir");
      expect(find.byKey(const ValueKey("styleInUse")), findsOneWidget);

      // Restyle asks Claude, in the conversation.
      await tester.tap(find.byKey(const ValueKey("styleRestyle-noir")));
      await idle(tester);
      expect(rig.ai.canvasChat.entries.first.text,
          contains('Restyle this canvas in the style "Noir"'));

      // The chip takes the style back out of use.
      await tester.tap(find.byTooltip("Stop using this style"));
      await tester.pump();
      expect(rig.ai.styles.active, isNull);

      // Saved with Claude: asked in the conversation.
      rig.ai.canvasChat.newConversation();
      await tester.tap(find.byKey(const ValueKey("stylesSave")));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey("styleName")), "Orange");
      await tester.tap(find.byKey(const ValueKey("styleSaveConfirm")));
      await idle(tester);
      expect(rig.ai.canvasChat.entries.first.text,
          contains('save its style as a profile named "Orange"'));
      expect(tester.takeException(), isNull);
    });
  });
}
