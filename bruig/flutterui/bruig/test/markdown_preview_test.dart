import 'dart:convert';

import 'package:bruig/components/feed/markdown_preview.dart';
import 'package:bruig/models/composer_sidebar.dart';
import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_support.dart';

// markdown_preview_test.dart covers the composer's preview: markdown styled
// where it is typed, rather than replaced.
//
// The invariant running through all of it is that the text never changes.
// The preview is styling and only styling, because Flutter maps the caret
// onto the characters the field holds -- so a preview that removed the "**"
// around a bold word would put every click after it out of step. The tests
// below check the styling happens and check the text is untouched, and the
// second half is the one that matters.

// A 1x1 red PNG, small enough to write out.
const _png =
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";

/// _styleAt is the style the decorations give one character.
TextStyle _styleAt(List<InlineDecoration> decorations, int offset) {
  var style = const TextStyle();
  for (var d in decorations) {
    if (d.start <= offset && d.end > offset) style = style.merge(d.style);
  }
  return style;
}

bool _hidden(List<InlineDecoration> decorations, int offset) =>
    (_styleAt(decorations, offset).fontSize ?? 14) < 1;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group("markers are hidden, the words they mark are styled", () {
    test("a heading", () {
      const text = "## The plan";
      var d = markdownDecorations(text);
      expect(_hidden(d, 0), isTrue, reason: "the # should be out of sight");
      expect(_hidden(d, 1), isTrue);
      expect(_styleAt(d, 3).fontWeight, FontWeight.w700);
      expect(_styleAt(d, 3).fontSize, greaterThan(14));
    });

    test("bold", () {
      const text = "we ship on **Monday** at noon";
      var d = markdownDecorations(text);
      expect(_hidden(d, text.indexOf("**")), isTrue);
      expect(_styleAt(d, text.indexOf("Monday")).fontWeight, FontWeight.w700);
      expect(_styleAt(d, text.indexOf("at noon")).fontWeight, isNull,
          reason: "the styling has to stop at the closing marker");
    });

    test("italic", () {
      const text = "it was *quite* good";
      var d = markdownDecorations(text);
      expect(_styleAt(d, text.indexOf("quite")).fontStyle, FontStyle.italic);
    });

    test("inline code", () {
      const text = "run the `relay` build";
      var d = markdownDecorations(text);
      expect(_styleAt(d, text.indexOf("relay")).fontFamily, "monospace");
    });

    test("a link keeps its label and loses its target", () {
      const text = "see [the docs](https://example.com) for more";
      var d = markdownDecorations(text);
      expect(_hidden(d, text.indexOf("[")), isTrue);
      expect(_hidden(d, text.indexOf("https")), isTrue,
          reason: "the URL is not what the reader is meant to see");
      expect(_styleAt(d, text.indexOf("the docs")).decoration,
          TextDecoration.underline);
    });

    // A bullet cannot become a round dot without replacing the character, so
    // it is dimmed rather than hidden -- a list with no markers at all reads
    // as loose lines.
    test("a list marker is kept but dimmed", () {
      const text = "- first\n- second";
      var d = markdownDecorations(text, muted: Colors.grey);
      expect(_hidden(d, 0), isFalse);
      expect(_styleAt(d, 0).color, Colors.grey);
    });
  });

  group("embedded images", () {
    String embed(String data) => "--embed[type=image/png,data=$data]--";

    test("an embed becomes a picture on exactly one character", () {
      var text = "before\n${embed("[content abcdefghijkl]")}\nafter";
      var d = markdownDecorations(text, embeds: const {"abcdefghijkl": _png});

      var withWidget = d.where((x) => x.widget != null).toList();
      expect(withWidget, hasLength(1));
      expect(withWidget.single.end - withWidget.single.start, 1,
          reason: "a widget standing for more than one character puts every "
              "caret position after it out of step");
    });

    test("the embed code around it is hidden", () {
      var text = embed("[content abcdefghijkl]");
      var d = markdownDecorations(text, embeds: const {"abcdefghijkl": _png});
      expect(_hidden(d, 0), isTrue);
      expect(_hidden(d, 10), isTrue);
    });

    // Base64 written straight into the text, which is what a draft reopened
    // from the post library holds.
    test("data already in the text is drawn too", () {
      var d = markdownDecorations(embed(_png));
      expect(d.where((x) => x.widget != null), hasLength(1));
    });

    test("an embed with nothing to draw stays readable", () {
      var text = embed("[content missingxxxxx]");
      var d = markdownDecorations(text, muted: Colors.grey);
      expect(d.where((x) => x.widget != null), isEmpty);
      expect(_hidden(d, 5), isFalse,
          reason: "hiding characters that show nothing leaves the caret "
              "walking through an invisible run for no reason");
    });

    test("a type that cannot be drawn is left alone", () {
      var d = markdownDecorations("--embed[type=text/plain,data=$_png]--");
      expect(d.where((x) => x.widget != null), isEmpty);
    });

    test("malformed data does not throw", () {
      expect(
          () =>
              markdownDecorations("--embed[type=image/png,data=not-base64]--"),
          returnsNormally);
    });
  });

  group("in the field", () {
    Future<TextSpan> render(WidgetTester tester, String text,
        {bool preview = true, List<GrammarRule> rules = const []}) async {
      var prefs = WritingPreferences();
      var capability = SpellcheckCapability(
          fetch: (_) async => SpellcheckData(
              const ["the", "payment", "monday"], const [], rules),
          prefs: prefs);
      await capability.update(FakePlugins({PluginCapability.spellcheckData}));

      var controller = WritingTextEditingController(
        text: text,
        decorations: (t) => preview ? markdownDecorations(t) : const [],
      );
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<WritingPreferences>.value(value: prefs),
          ChangeNotifierProvider<SpellcheckCapability>.value(value: capability),
        ],
        child: MaterialApp(
            home: Scaffold(body: TextField(controller: controller))),
      ));
      await tester.pumpAndSettle();
      return tester.allRenderObjects.whereType<RenderEditable>().first.text
          as TextSpan;
    }

    // The whole point, stated as a test.
    testWidgets("the text is never changed by being previewed", (tester) async {
      const text = "## Plan\n\nwe ship on **Monday**, using `relay`.";
      var span = await render(tester, text);
      expect(span.toPlainText(), text);
    });

    testWidgets("raw mode paints nothing extra", (tester) async {
      const text = "## Plan with a **bold** word";
      var span = await render(tester, text, preview: false);
      expect(span.toPlainText(), text);
      // One run, or runs that all share the base style: no heading sizes.
      var sizes = <double?>{};
      span.visitChildren((s) {
        if (s is TextSpan) sizes.add(s.style?.fontSize);
        return true;
      });
      expect(sizes.where((s) => s != null && s > 20), isEmpty);
    });

    testWidgets("an image is drawn inside the editable text", (tester) async {
      var text = "look:\n--embed[type=image/png,data=$_png]--\ndone";
      var span = await render(tester, text);
      expect(find.byType(Image), findsOneWidget);
      // A WidgetSpan counts as one character, and it replaced one, so the
      // field still agrees with the controller about where everything is.
      expect(span.toPlainText().length, text.length);
    });

    // The sidebar flips a flag on a model; the field has to notice. Nothing
    // else in the chain is checked by the tests above, which build the
    // decorations themselves.
    testWidgets("toggling the flag repaints without editing", (tester) async {
      var sidebar = ComposerSidebarController();
      const text = "## Plan";
      var controller = WritingTextEditingController(
        text: text,
        decorations: (t) => sidebar.preview ? markdownDecorations(t) : const [],
      );
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<WritingPreferences>(
              create: (c) => WritingPreferences()),
          ChangeNotifierProvider<ComposerSidebarController>.value(
              value: sidebar),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer<ComposerSidebarController>(
              builder: (context, _, child) => TextField(controller: controller),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      double? biggest() {
        var span = tester.allRenderObjects
            .whereType<RenderEditable>()
            .first
            .text as TextSpan;
        double? found;
        span.visitChildren((s) {
          if (s is TextSpan && (s.style?.fontSize ?? 0) > (found ?? 0)) {
            found = s.style!.fontSize;
          }
          return true;
        });
        return found;
      }

      expect(biggest() ?? 0, lessThan(20), reason: "raw by default");

      sidebar.preview = true;
      await tester.pumpAndSettle();
      expect(biggest(), greaterThan(20), reason: "the heading should grow");
      expect(controller.text, text, reason: "previewing is not an edit");

      sidebar.preview = false;
      await tester.pumpAndSettle();
      expect(biggest() ?? 0, lessThan(20));
      expect(controller.text, text);
    });

    // The marks and the preview paint the same characters, and the marks
    // have to win where they overlap.
    testWidgets("a misspelling keeps its mark inside a heading",
        (tester) async {
      var span = await render(tester, "## the paymnt");
      var marked = <String>[];
      span.visitChildren((s) {
        if (s is TextSpan &&
            s.style?.decoration == TextDecoration.underline &&
            s.text != null) {
          marked.add(s.text!);
        }
        return true;
      });
      expect(marked, contains("paymnt"));
    });
  });
}
