import 'dart:convert';

import 'package:bruig/components/feed/markdown_preview.dart';
import 'package:bruig/models/composer_sidebar.dart';
import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:bruig/theming_system/theme_preset.dart';
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

// A real 40x20 red PNG. Real rather than contrived: the geometry tests below
// measure what the field does with it, and a header with no body decodes to
// nothing.
const _png =
    "iVBORw0KGgoAAAANSUhEUgAAACgAAAAUCAIAAABwJOjsAAAAJElEQVR4nO3NMQ0AAAwEofdvupVxCwk7uy3RrGKxWCwWi8WJB336HQ594lo5AAAAAElFTkSuQmCC";

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

/// A 300x200 red PNG. Large on purpose: every geometry fault reported here
/// only appears when the picture is taller than a line of text, and a small
/// one fits inside the line and hides all of them.
const _bigPng =
    "iVBORw0KGgoAAAANSUhEUgAAASwAAADICAIAAADdvUsCAAACpElEQVR4nO3OQQ0AMBAEofNvupUxjyVBAPfugFA/gHH9AMb1AxjXD2BcP4Bx/QDG9QMY1w9gXD+Acf0AxvUDGNcPYFw/gHH9AMb1AxjXD2BcP4Bx/QDG9QMY1w9gXD+Acf0AxvUDGNcPYFw/gHH9AMb1AxjXD2BcP4Bx/QDG9QMY1w9gXD+Acf0AxvUDGNcPYFw/gHH9AMb1AxjXD2BcP4Bx/QDG9QMY1w9gXD+Acf0AxvUDGNcPYFw/gHH9AMb1AxjXD2BcP4Bx/QDG9QMY1w9gXD+Acf0AxvUDGNcPYFw/gHH9AMb1AxjXD2BcP4Bx/QDG9QMY1w9gXD+Acf0AxvUDGNcPYFw/gHH9AMb1AxjXD2BcP4Bx/QDG9QMY1w9gXD+Acf0AxvUDGNcPYFw/gHH9AMb1AxjXD2BcP4Bx/QDG9QMY1w9gXD+Acf0AxvUDGNcPYFw/gHH9AMb1AxjXD2BcP4Bx/QDG9QMY1w9gXD+Acf0AxvUDGNcPYFw/gHH9AMb1AxjXD2BcP4Bx/QDG9QMY1w9gXD+Acf0AxvUDGNcPYFw/gHH9AMb1AxjXD2BcP4Bx/QDG9QMY1w9gXD+Acf0AxvUDGNcPYFw/gHH9AMb1AxjXD2BcP4Bx/QDG9QMY1w9gXD+Acf0AxvUDGNcPYFw/gHH9AMb1AxjXD2BcP4Bx/QDG9QMY1w9gXD+Acf0AxvUDGNcPYFw/gHH9AMb1AxjXD2BcP4Bx/QDG9QMY1w9gXD+Acf0AxvUDGNcPYFw/gHH9AMb1AxjXD2BcP4Bx/QDG9QMY1w9gXD+Acf0AxvUDGNcPYFw/gHH9AMb1AxjXD2BcP4Bx/QDG9QMY1w9gXD+Acf0AxvUDGNcPYFw/gHH9AMb1AxjXD2BcP4Bx/QDG9QMY9wFP4oNIvm7wCQAAAABJRU5ErkJggg==";

/// _imageIn digs the picture out of whatever the embed was wrapped in.
///
/// By walking rather than by casting through each layer: the wrappers
/// change as the style guide gains rules -- a border adds a Container, a
/// radius adds a ClipRRect -- and a test that spells the chain out fails
/// every time one is added without anything actually being wrong.
Image _imageIn(Widget widget) {
  Image? found;
  void walk(Widget w) {
    if (found != null) return;
    if (w is Image) {
      found = w;
      return;
    }
    if (w is SingleChildRenderObjectWidget && w.child != null) walk(w.child!);
    if (w is Padding && w.child != null) walk(w.child!);
    if (w is Container) walk(w.child!);
    if (w is ClipRRect && w.child != null) walk(w.child!);
  }

  walk(widget);
  return found!;
}

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
      expect(_styleAt(d, text.indexOf("relay")).fontFamily, "RobotoMono");
    });

    test("a link keeps its label and loses its target", () {
      const text = "see [the docs](https://example.com) for more";
      var d = markdownDecorations(text, link: const Color(0xFF0077CC));
      expect(_hidden(d, text.indexOf("[")), isTrue);
      expect(_hidden(d, text.indexOf("https")), isTrue,
          reason: "the URL is not what the reader is meant to see");
      expect(
          _styleAt(d, text.indexOf("the docs")).color, const Color(0xFF0077CC));
    });

    // Reported: the composer underlined links and the rendered post did not,
    // so a post looked one way while it was being written and another
    // afterwards. The preview is supposed to be the post.
    test("a link is not underlined unless a guide asks", () {
      const text = "see [the docs](https://example.com) for more";
      expect(
          _styleAt(markdownDecorations(text), text.indexOf("the docs"))
              .decoration,
          isNull);

      var article = markdownDecorations(text,
          guide: builtInGuideFor("article"),
          roleColor: (_) => const Color(0xFF0077CC));
      expect(_styleAt(article, text.indexOf("the docs")).decoration,
          TextDecoration.underline,
          reason: "Article asks for one explicitly");
    });

    // Reported as part of the same thing: a guide that says nothing about an
    // element was stripping that element back to plain text, because its
    // empty rule replaced the preview's own styling instead of adjusting it.
    test("a guide that says nothing keeps the element's own styling", () {
      const text = "the `relay` command";
      var article = markdownDecorations(text,
          guide: builtInGuideFor("article"),
          roleColor: (_) => const Color(0xFF0077CC));
      expect(_styleAt(article, text.indexOf("relay")).fontFamily, "RobotoMono",
          reason: "Article says nothing about code, so code stays code");
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

    // Reported twice, and the second report found the cause.
    //
    // First: the picture had no size when the line was measured, because an
    // Image is decoded after layout and answered zero. Fixed by reading the
    // size out of the header.
    //
    // Then: a *tall* picture still sat over the text above it, or off the
    // top of the page entirely. The line had not grown to hold it -- 72
    // pixels of line for 200 pixels of image -- because a TextField's strut
    // forces every line to one height, which is what it is for and exactly
    // wrong here. The composer disables it while previewing.
    //
    // The three arrangements below are the ones that were wrong, measured
    // rather than asserted: "does not overlap what is above it" is a
    // statement about geometry, and nothing else would notice it failing.
    Future<({double field, double top, double bottom})> place(
        WidgetTester tester, String text) async {
      var controller = WritingTextEditingController(
          text: text, decorations: (t) => markdownDecorations(t));
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<WritingPreferences>(
              create: (c) => WritingPreferences()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: SizedBox(
                    width: 500,
                    child: TextField(
                        controller: controller,
                        maxLines: null,
                        // As the composer builds it while previewing.
                        strutStyle: StrutStyle.disabled)))),
      ));
      await tester.pumpAndSettle();
      var field = tester.renderObject<RenderBox>(find.byType(TextField));
      var image = tester.renderObject<RenderBox>(find.byType(Image));
      expect(image.size, const Size(300, 200),
          reason: "sized from the header before anything is laid out");
      var top = image.localToGlobal(Offset.zero).dy -
          field.localToGlobal(Offset.zero).dy;
      return (field: field.size.height, top: top, bottom: top + 200);
    }

    const embed = "--embed[type=image/png,data=$_bigPng]--";

    testWidgets("an image at the very top stays on the page", (tester) async {
      var at = await place(tester, "$embed\nafter the picture");
      expect(at.top, greaterThanOrEqualTo(0),
          reason: "a negative top is the picture hanging off the page");
      expect(at.bottom, lessThanOrEqualTo(at.field));
    });

    testWidgets("an image after text does not cover it", (tester) async {
      var at = await place(tester, "before the picture $embed");
      expect(at.top, greaterThanOrEqualTo(0));
      expect(at.bottom, lessThanOrEqualTo(at.field));
    });

    testWidgets("an image on its own line sits below the line above",
        (tester) async {
      var at = await place(tester, "before\n$embed\nafter");
      expect(at.top, greaterThan(0));
      expect(at.bottom, lessThanOrEqualTo(at.field));
    });

    // Without this the three above pass on a field that merely gained a line
    // of text, which is how the first attempt at them passed while the bug
    // was still there.
    testWidgets("the field grows by the height of the image", (tester) async {
      var withImage = await place(tester, "before\n$embed\nafter");
      expect(withImage.field, greaterThan(200),
          reason: "three lines of text alone come to under 100 pixels");
    });

    // Reported: the pictures flickered on every keystroke.
    //
    // The field rebuilds on every edit, and each rebuild decoded the base64
    // again. MemoryImage compares equal only when it holds the same bytes
    // *object* -- Uint8List defines no equality, so it falls back to
    // identity -- which meant every keystroke handed Flutter a provider it
    // had never seen, and it threw the decoded frame away and started over.
    testWidgets("editing does not re-decode the images", (tester) async {
      var text = "before\n--embed[type=image/png,data=$_bigPng]--\nafter";
      var controller = WritingTextEditingController(
          text: text, decorations: (t) => markdownDecorations(t));
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<WritingPreferences>(
              create: (c) => WritingPreferences()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: SizedBox(
                    width: 500,
                    child: TextField(
                        controller: controller,
                        maxLines: null,
                        strutStyle: StrutStyle.disabled)))),
      ));
      await tester.pumpAndSettle();
      var before = tester.widget<Image>(find.byType(Image)).image;

      // An edit somewhere else in the post: the picture is untouched, so
      // nothing about it should change.
      controller.text = "$text and more";
      await tester.pumpAndSettle();
      var after = tester.widget<Image>(find.byType(Image)).image;

      expect(after, equals(before),
          reason: "an unequal provider is a fresh decode, which is the "
              "flicker");
    });

    // Two embeds of the same picture are one decode, and two of different
    // pictures stay different.
    test("the byte cache is keyed by the data", () {
      var one = markdownDecorations("--embed[type=image/png,data=$_bigPng]--")
          .firstWhere((d) => d.widget != null);
      var two = markdownDecorations("--embed[type=image/png,data=$_bigPng]--")
          .firstWhere((d) => d.widget != null);
      expect(_imageIn(one.widget!).image, equals(_imageIn(two.widget!).image));
    });

    // The composer paints from the guide the writer picked, so that what
    // they see is what a reader with that guide will see.
    group("the writer's chosen guide", () {
      TextStyle headingStyle(MarkdownStyleGuide? guide) {
        var decorations = markdownDecorations("# A heading",
            guide: guide, roleColor: (_) => const Color(0xFF00FF00));
        // The heading's own run, not the hidden "# " before it.
        return decorations
            .firstWhere((d) => d.style.fontSize != null && d.start == 0)
            .style;
      }

      test("no guide keeps the preview's own styling", () {
        expect(headingStyle(null).fontSize, 26);
      });

      test("a guide decides the heading size", () {
        var article = builtInGuideFor("article")!;
        // Article's h1 is 1.9x the body, which the preview bases on 14.
        expect(headingStyle(article).fontSize, closeTo(14 * 1.9, 0.01));
      });

      test("a guide's colour role is resolved", () {
        var guide = const MarkdownStyleGuide(id: "x", name: "X", headings: [
          TextRule(ink: MarkdownInk.of(MarkdownRole.accent)),
          TextRule(),
          TextRule(),
          TextRule(),
          TextRule(),
          TextRule(),
        ]);
        expect(headingStyle(guide).color, const Color(0xFF00FF00));
      });
    });

    // Reported: a list item running to a second line went back to the
    // margin instead of hanging under the first line's text.
    //
    // A rendered post already does this -- flutter_markdown builds a list
    // item as a bullet beside a flexible column, so every line of that
    // column is indented. The composer cannot, for a line the field wrapped
    // by itself: Flutter's editable text has no hanging indent and where a
    // line breaks is not known until it is laid out. A line the writer broke
    // themselves has real whitespace at the front, and that is made exactly
    // as wide as the bullet.
    group("a list item continued on the next line", () {
      const text = "- the first line\n  continued here\n\nnot a list";

      test("the leading space carries the indent", () {
        var d = markdownDecorations(text, indent: 20);
        var at = text.indexOf("  continued") + 1;
        var carrier = d.firstWhere((x) => x.start == at && x.widget != null);
        expect((carrier.widget as SizedBox).width, 20);
      });

      test("the rest of the leading space is hidden", () {
        var d = markdownDecorations(text, indent: 20);
        expect(_hidden(d, text.indexOf("  continued")), isTrue);
      });

      test("a line after the list is left alone", () {
        var d = markdownDecorations("- item\n\n  not a continuation");
        expect(d.where((x) => x.widget != null), isEmpty,
            reason: "the blank line ended the list");
      });

      test("a line with no leading space is left alone", () {
        var d = markdownDecorations("- item\nplain text");
        expect(d.where((x) => x.widget != null), isEmpty);
      });
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
