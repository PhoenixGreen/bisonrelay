import 'package:bruig/components/md_elements.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// markdown_render_test.dart covers what flutter_markdown actually builds for
// a post, as opposed to what the stylesheet says it should.
//
// The two came apart badly enough to be worth pinning: every fenced code
// block in the app was being rendered by the builder registered for attached
// text files, because a fenced block and an attached text file both parse to
// <pre>. Nothing in the stylesheet was wrong; the block never reached it.

const _mono = "RobotoMono";

MarkdownStyleSheet _sheet() => MarkdownStyleSheet(
      p: const TextStyle(fontSize: 14, color: Color(0xFF00FF00)),
      code: const TextStyle(fontFamily: _mono, fontSize: 12),
      codeblockDecoration: const BoxDecoration(color: Color(0xFF101010)),
    );

/// _spans is every styled run on screen, flattened.
List<(String, TextStyle?)> _spans(WidgetTester tester) {
  var out = <(String, TextStyle?)>[];
  void walk(InlineSpan span) {
    if (span is TextSpan) {
      if (span.text != null) out.add((span.text!, span.style));
      for (var c in span.children ?? const <InlineSpan>[]) {
        walk(c);
      }
    }
  }

  for (var r in tester.widgetList<RichText>(find.byType(RichText))) {
    walk(r.text);
  }
  return out;
}

TextStyle? _styleOf(WidgetTester tester, String text) {
  for (var (t, s) in _spans(tester)) {
    if (t.contains(text)) return s;
  }
  return null;
}

Future<void> _pump(WidgetTester tester, String data,
        {Map<String, MarkdownElementBuilder> builders = const {}}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MarkdownBody(
          data: data,
          styleSheet: _sheet(),
          builders: builders,
          codeBlockMaxHeight: 200,
          extensionSet: md.ExtensionSet.gitHubFlavored,
        ),
      ),
    ));

/// _Claim stands for any builder registered on "pre" -- in the app, the one
/// that renders an attached text file.
class _Claim extends MarkdownElementBuilder {
  @override
  Widget visitText(md.Text text, TextStyle? preferredStyle) =>
      const Text("claimed");
}

void main() {
  // A bare URL is drawn by the link-card plugin rather than by the markdown
  // stylesheet, and it used to draw its own way: the raw Material accent,
  // and an underline added regardless of what the style guide asked for.
  //
  // That is the mismatch between the settings preview and a real post --
  // the preview shows a written-out [text](url) link, which under Default
  // has no underline, and the post shows a bare URL, which had one always.
  group("a bare URL", () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test("is set exactly as a written-out link is", () {
      var theme = ThemeNotifier(doLoad: false);
      var style = theme.markdownLinkStyle(const TextStyle(fontSize: 14));
      expect(style.color, theme.markdownRoleColor(MarkdownRole.link));
      expect(style.decorationColor, style.color,
          reason: "the underline is the colour of the text it underlines");
      expect(style.fontSize, 14, reason: "it keeps the size around it");
    });

    test("is underlined only when the guide asks", () {
      var theme = ThemeNotifier(doLoad: false);
      expect(theme.markdownGuide.id, defaultGuideId);
      expect(theme.markdownLinkStyle(const TextStyle()).decoration,
          isNot(TextDecoration.underline),
          reason: "Default asks for no underline, so a bare URL has none");
    });
  });

  // Reported: an unknown purple on the download-file text and behind a
  // quotation. Both were Material's stock seed colours showing through --
  // the tertiary container pair is derived from the seed's own tonal ramp
  // and is not a palette colour at all, so no amount of editing the palette
  // moved it.
  group("nothing is drawn in a colour the palette does not hold", () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test("a quotation is set on a palette surface", () async {
      // Switched and waited on, because the markdown sheet is built when a
      // theme is applied rather than in the constructor, and applying one
      // writes the choice to storage on the way.
      var theme = ThemeNotifier(doLoad: false)..switchTheme(defaultThemeName);
      await pumpEventQueue();
      var sheet = theme.mdStyleSheet;
      expect((sheet.blockquoteDecoration! as BoxDecoration).color,
          theme.surfaceColor(SurfaceColor.surfaceContainerHigh));
      expect((sheet.blockquoteDecoration! as BoxDecoration).color,
          isNot(theme.colors.tertiaryContainer));
    });

    test("the quote colour role is a palette colour", () {
      var theme = ThemeNotifier(doLoad: false);
      expect(theme.markdownRoleColor(MarkdownRole.quote),
          isNot(theme.colors.onTertiaryContainer));
    });

    testWidgets("a download link is set as a link", (tester) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
        ],
        child: Builder(builder: (context) {
          var theme = ThemeNotifier.of(context);
          return MaterialApp(
            theme: theme.theme,
            home: Scaffold(
              body: MarkdownBody(
                data: "--embed[type=text/plain,download="
                    "${"a" * 64},alt=A file]--",
                styleSheet: _sheet(),
                builders: MarkdownAreaModel("/tmp").builders,
                inlineSyntaxes: MarkdownAreaModel("/tmp").inlineSyntaxes,
              ),
            ),
          );
        }),
      ));
      await tester.pump();

      var link = tester
          .widgetList<Text>(find.byType(Text))
          .firstWhere((t) => t.data == "A file");
      expect(link.style?.color, isNotNull,
          reason: "with no style it fell through to Material's own purple");
    });
  });

  group("a fenced code block", () {
    // The bug, stated as the thing that caused it: a builder registered for
    // "pre" is asked for the block before flutter_markdown reaches its own
    // code-block rendering, so the block is built by whatever that builder
    // does and the sheet's `code` style is never consulted.
    test("an attached text file no longer claims the code block's tag", () {
      var model = MarkdownAreaModel("/tmp");
      expect(model.builders.containsKey("pre"), isFalse,
          reason: "a fenced code block parses to <pre> as well, and a "
              "builder here takes over every code block in the app");
      expect(model.builders.containsKey("embedtext"), isTrue);
    });

    testWidgets("is set in the code face", (tester) async {
      await _pump(tester, "```\nthe code\n```");
      expect(_styleOf(tester, "the code")?.fontFamily, _mono);
      expect(_styleOf(tester, "the code")?.fontSize, 12);
    });

    testWidgets("is drawn on the block background", (tester) async {
      await _pump(tester, "```\nthe code\n```");
      var decorated = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .where((d) => d.decoration == _sheet().codeblockDecoration);
      expect(decorated, isNotEmpty);
    });

    // What it looked like before: a builder for "pre" is handed the block
    // and renders it however it likes -- for the attached-text-file builder
    // that meant the body face and a "View" button under every code block,
    // belonging to a file that was not there.
    testWidgets("a pre builder is what used to break it", (tester) async {
      await _pump(tester, "```\nthe code\n```", builders: {"pre": _Claim()});
      expect(find.text("claimed"), findsOneWidget,
          reason: "this is the interception the fix avoids");
      expect(_styleOf(tester, "the code"), isNull);
    });
  });

  // Reported: line breaks stopped working in the post preview.
  //
  // isolate() splits a line around a plugin's standalone matches, and the
  // line it hands back for a line with no match at all was the *trimmed*
  // one -- so the two trailing spaces that are how markdown spells a line
  // break were deleted before the parser ever saw them. Only with a plugin
  // registered, since with none isolate returns early, which is why it
  // survived every test here: link previews supplies one and ships enabled,
  // so in the running app it was every post and in the tests it was none.
  group("isolate keeps the text it is not splitting", () {
    MarkdownAreaModel withStandalone() {
      var model = MarkdownAreaModel("/tmp");
      model.setPluginExtensions([
        MarkdownExtension(
            tag: "probe",
            builder: _Claim(),
            standalone: RegExp(r'(?<![(\]<])https?://\S+')),
      ]);
      return model;
    }

    test("a hard line break survives a registered standalone pattern", () {
      expect(withStandalone().isolate("one  \ntwo"), "one  \ntwo");
    });

    test("and survives when no plugin is registered either", () {
      expect(MarkdownAreaModel("/tmp").isolate("one  \ntwo"), "one  \ntwo");
    });

    test("a line that really is split is still split", () {
      var out = withStandalone().isolate("see https://example.com now");
      expect(out.split("\n").where((l) => l.trim().isNotEmpty).length, 3,
          reason: "the URL is pulled into a paragraph of its own");
      expect(out, contains("https://example.com"));
    });

    test("a line inside a fence is untouched", () {
      const code = "```\n  indented  \n```";
      expect(withStandalone().isolate(code), code);
    });
  });

  // Quotes. flutter_markdown upstream folds the blockquote style *underneath*
  // the paragraph's, and TextStyle.merge lets the argument win -- so
  // styleSheet.blockquote was dead in any sheet that fully specifies `p`,
  // which is every sheet built from a theme. A quote could be given a
  // colour, a size, a face or italics and none of it reached the screen.
  // The vendored copy at ../packages/flutter_markdown swaps the order.
  group("a quotation", () {
    testWidgets("is set in the quote style, not the paragraph's",
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MarkdownBody(
            data: "> quoted line one\n> quoted line two",
            styleSheet: _sheet().copyWith(
              blockquote: const TextStyle(
                  fontSize: 20,
                  color: Color(0xFFFF0000),
                  fontStyle: FontStyle.italic),
            ),
            extensionSet: md.ExtensionSet.gitHubFlavored,
          ),
        ),
      ));
      var quoted = _styleOf(tester, "quoted line one");
      expect(quoted?.color, const Color(0xFFFF0000));
      expect(quoted?.fontSize, 20);
      expect(quoted?.fontStyle, FontStyle.italic);
    });

    // Both lines are one quotation and one span, so the styling has to reach
    // the whole of it rather than the first line.
    testWidgets("carries across every line of it", (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MarkdownBody(
            data: "> quoted line one\n> quoted line two",
            styleSheet: _sheet().copyWith(
              blockquote: const TextStyle(color: Color(0xFFFF0000)),
            ),
            extensionSet: md.ExtensionSet.gitHubFlavored,
          ),
        ),
      ));
      expect(
          _styleOf(tester, "quoted line two")?.color, const Color(0xFFFF0000));
    });
  });

  // The blank line a writer leaves between blocks. Reported as line breaks
  // not being rendered: a heading sat hard on top of the quotation under it,
  // two quotations touched, and a list ran straight into the next heading.
  //
  // Only paragraphs could be given a gap of their own, so setting the one
  // shared figure to the list's left everything that is not prose with
  // almost none. These measure the gap where it was missing.
  group("the space between blocks", () {
    Future<double> gapBetween(WidgetTester tester, String data) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MarkdownBody(
            data: data,
            styleSheet: _sheet().copyWith(
              blockSpacing: 24,
              listItemSpacing: 2,
              pPadding: EdgeInsets.zero,
              h1Padding: EdgeInsets.zero,
              blockquotePadding: EdgeInsets.zero,
            ),
            extensionSet: md.ExtensionSet.gitHubFlavored,
          ),
        ),
      ));
      var boxes = tester
          .widgetList<SizedBox>(find.byType(SizedBox))
          .map((b) => b.height)
          .whereType<double>()
          .toList();
      return boxes.isEmpty ? 0 : boxes.reduce((a, b) => a > b ? a : b);
    }

    testWidgets("a heading is separated from the quotation under it",
        (tester) async {
      expect(await gapBetween(tester, "# Quotes\n\n> a quotation"), 24);
    });

    testWidgets("two quotations are separated from each other", (tester) async {
      expect(await gapBetween(tester, "> one\n\n> two"), 24);
    });

    testWidgets("a code block is separated from the prose above it",
        (tester) async {
      expect(await gapBetween(tester, "before\n\n```\ncode\n```"), 24);
    });

    // The other half of the bargain: bullets keep their own tighter gap, so
    // a list does not fall apart into unrelated lines.
    testWidgets("bullets keep their own tighter gap", (tester) async {
      expect(await gapBetween(tester, "- one\n- two\n- three"), 2);
    });
  });

  // Tables do reach the stylesheet, and are pinned here so the two halves of
  // "not rendering" stay told apart: the grid is built, the header row is
  // styled from tableHead and the body rows from tableBody.
  group("a table", () {
    testWidgets("is built as a grid, with its rows styled apart",
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MarkdownBody(
            data: "| a | b |\n| --- | --- |\n| one | two |",
            styleSheet: _sheet().copyWith(
              tableHead: const TextStyle(fontWeight: FontWeight.w700),
              tableBody: const TextStyle(fontSize: 13),
              tableBorder: TableBorder.all(color: const Color(0xFF888888)),
            ),
            extensionSet: md.ExtensionSet.gitHubFlavored,
          ),
        ),
      ));
      expect(find.byType(Table), findsOneWidget);
      expect(_styleOf(tester, "a")?.fontWeight, FontWeight.w700);
      expect(_styleOf(tester, "one")?.fontSize, 13);
    });
  });
}
