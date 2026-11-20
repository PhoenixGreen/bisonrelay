import 'package:bruig/plugin_system/creative_ai/claude/claude_code.dart';
import 'package:bruig/plugin_system/creative_ai/engine/json_edit.dart';
import 'package:bruig/plugin_system/creative_ai/engine/word_diff.dart';
import 'package:bruig/plugin_system/creative_ai/session/writing_suggestions.dart';
import 'package:flutter_test/flutter_test.dart';

// creative_ai_engine_test.dart pins Creative AI's pure pieces: the three ways
// an assistant edits JSON, the cutting down of a large reply, the word
// difference a suggestion is shown as, the clean-up of a rewrite, and the
// reading of Claude Code's stream.

void main() {
  group("merge patch", () {
    test("sets, merges into objects and removes with null", () {
      var out = mergePatch({
        "a": 1,
        "b": {"c": 2, "d": 3},
        "e": [1, 2],
      }, {
        "a": 5,
        "b": {"d": null, "x": 9},
        "e": [7],
      });
      expect(out, {
        "a": 5,
        "b": {"c": 2, "x": 9},
        "e": [7],
      });
    });

    test("does not change what it was given", () {
      var original = {
        "b": {"c": 2}
      };
      mergePatch(original, {
        "b": {"c": 3}
      });
      expect(original["b"], {"c": 2});
    });
  });

  group("pointers", () {
    var doc = {
      "track": {
        "keys": [
          {"f": 0},
          {"f": 24, "o": 1}
        ]
      },
      "a/b": {"~x": 1},
    };

    test("read into objects and lists, with escapes", () {
      expect(readPointer(doc, "/track/keys/1/f"), 24);
      expect(readPointer(doc, "/a~1b/~0x"), 1);
      expect(readPointer(doc, ""), doc);
    });

    test("say clearly what is not there", () {
      expect(() => readPointer(doc, "/track/keys/5"),
          throwsA(isA<JsonEditError>()));
      expect(() => readPointer(doc, "track"), throwsA(isA<JsonEditError>()));
    });

    test("set replaces, appends with - and makes objects on the way", () {
      var out = setPointer(doc, "/track/keys/1/o", 0.5) as Map;
      expect(readPointer(out, "/track/keys/1/o"), 0.5);
      out = setPointer(out, "/track/keys/-", {"f": 48}) as Map;
      expect((readPointer(out, "/track/keys") as List).length, 3);
      out = setPointer(out, "/new/deep/value", 1) as Map;
      expect(readPointer(out, "/new/deep/value"), 1);
      // The original is untouched.
      expect((readPointer(doc, "/track/keys") as List).length, 2);
    });

    test("remove takes out a key or a place in a list", () {
      var out = removePointer(doc, "/track/keys/0");
      expect(readPointer(out, "/track/keys"), [
        {"f": 24, "o": 1}
      ]);
      expect(
          () => removePointer(doc, "/nothing"), throwsA(isA<JsonEditError>()));
    });

    test("applyEdits does patch, then sets, then removes", () {
      var out = applyEdits({"x": 1, "y": 2},
          patch: {"x": 3}, sets: [const JsonSet("/z", 4)], removes: ["/y"]);
      expect(out, {"x": 3, "z": 4});
    });
  });

  test("compactJson cuts a large reply and says how to see the rest", () {
    var big = {
      "words": "w" * 5000,
      "list": [for (var i = 0; i < 500; i++) i],
    };
    var out = compactJson(big, budget: 2000) as Map;
    expect(out["words"], contains("more characters"));
    expect((out["list"] as List).last, contains("more"));
    var small = {"a": 1};
    expect(compactJson(small), same(small));
  });

  group("word diff", () {
    String side(List<DiffPiece> pieces, DiffKind skip) =>
        pieces.where((p) => p.kind != skip).map((p) => p.text).join();

    test("each side joins back to its text exactly", () {
      for (var (a, b) in [
        ("The quick brown fox jumps.", "The quick red fox leaps."),
        ("Hello, world!\n\nNew para.", "Hi, world.\n\nNew paragraph here."),
        ("", "Something new."),
        ("All of it goes.", ""),
        ("Same.", "Same."),
      ]) {
        var d = wordDiff(a, b);
        expect(side(d, DiffKind.added), a);
        expect(side(d, DiffKind.removed), b);
      }
    });

    test("marks only the words that changed", () {
      var d = wordDiff("The quick brown fox", "The quick red fox");
      expect(d, [
        const DiffPiece(DiffKind.same, "The quick "),
        const DiffPiece(DiffKind.removed, "brown "),
        const DiffPiece(DiffKind.added, "red "),
        const DiffPiece(DiffKind.same, "fox"),
      ]);
    });
  });

  group("a rewrite as it comes back", () {
    test("loses the tags or fence a model wraps it in", () {
      expect(cleanRewrite("<passage>\nNew words.\n</passage>"), "New words.");
      expect(cleanRewrite("```\nNew words.\n```"), "New words.");
      expect(cleanRewrite("Plain."), "Plain.");
    });

    test("keeps the original's breaks before and after", () {
      expect(keepEdges("\n\nOld para.\n", "New para."), "\n\nNew para.\n");
      expect(keepEdges("Old.", "  New.  "), "New.");
    });
  });

  group("Claude Code's stream", () {
    var t = DateTime.now();
    test("reads the session, text, tools and the result", () {
      expect(
          ClaudeCode.parseStreamLine(
                  '{"type":"system","subtype":"init","session_id":"s1","model":"opus"}',
                  t)
              .single,
          isA<ClaudeStarted>().having((e) => e.sessionId, "id", "s1"));
      var said = ClaudeCode.parseStreamLine(
          '{"type":"assistant","message":{"content":['
          '{"type":"text","text":"Done."},'
          '{"type":"tool_use","name":"mcp__bisonrelay__canvas_overview","input":{}}]}}',
          t);
      expect(said, hasLength(2));
      expect(said[0], isA<ClaudeSaid>());
      expect(
          said[1],
          isA<ClaudeUsedTool>()
              .having((e) => e.name, "name", contains("overview")));
      var done = ClaudeCode.parseStreamLine(
              '{"type":"result","subtype":"success","is_error":false,"result":"ok","session_id":"s1"}',
              t)
          .single as ClaudeFinished;
      expect(done.ok, isTrue);
      var failed = ClaudeCode.parseStreamLine(
              '{"type":"result","subtype":"success","is_error":true,"result":"Not logged in"}',
              t)
          .single as ClaudeFinished;
      expect(failed.error, "Not logged in");
    });

    test("ignores what it does not know", () {
      expect(ClaudeCode.parseStreamLine("not json", t), isEmpty);
      expect(ClaudeCode.parseStreamLine('{"type":"user"}', t), isEmpty);
    });

    test("leaves out what would bill an API account", () {
      var env = ClaudeCode.environment();
      expect(env.containsKey("ANTHROPIC_API_KEY"), isFalse);
      expect(env.containsKey("ANTHROPIC_AUTH_TOKEN"), isFalse);
      expect(env.containsKey("CLAUDECODE"), isFalse);
    });
  });
}
