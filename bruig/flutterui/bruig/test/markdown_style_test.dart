import 'package:bruig/theming_system/model/area_style.dart';
import 'package:bruig/theming_system/model/markdown_guides.dart';
import 'package:bruig/theming_system/model/markdown_style.dart';
import 'package:bruig/theming_system/model/markdown_style_render.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

// markdown_style_test.dart covers a post's style guide: the vocabulary, what
// it is allowed to say, and how it folds onto the reader's theme.
//
// The guide is local, always. A post carries the name of one and never the
// guide itself, so nothing here is reading anything an author sent -- which
// is why the bounds below matter less for safety than they do for taste, and
// why they are still worth having.

const _roles = {
  MarkdownRole.text: Color(0xFF111111),
  MarkdownRole.muted: Color(0xFF777777),
  MarkdownRole.accent: Color(0xFF0055FF),
  MarkdownRole.link: Color(0xFF0077CC),
  MarkdownRole.quote: Color(0xFF444444),
  MarkdownRole.quoteBar: Color(0xFF999999),
  MarkdownRole.raised: Color(0xFFEEEEEE),
  MarkdownRole.outline: Color(0xFFCCCCCC),
};

Color _role(MarkdownRole r) => _roles[r]!;

const _body = TextStyle(fontSize: 14, color: Color(0xFF111111));

MarkdownStyleSheet _base() => MarkdownStyleSheet(
      p: _body,
      h1: const TextStyle(fontSize: 28),
      blockquote: const TextStyle(fontSize: 14),
      blockSpacing: 8,
    );

MarkdownStyleSheet _sheetFor(MarkdownStyleGuide guide) =>
    applyGuide(_base(), guide, _role);

void main() {
  // The Markdown theme area: which guide posts are read in, and whether a
  // post may ask for a different one. Both travel with a theme, because how
  // text is set is part of how the app looks.
  group("the theme area's settings", () {
    test("out of the box nothing is changed and a post may ask", () {
      var style = const AreaStyle();
      expect(style.markdownGuideId, defaultGuideId);
      expect(style.markdownHonourPostGuide, isTrue);
    });

    test("a chosen guide survives being saved and read back", () {
      var style = const AreaStyle()
          .copyWith(markdownGuideId: "article", markdownHonourPostGuide: false);
      var back = AreaStyle.fromJson(style.toJson());
      expect(back.markdownGuideId, "article");
      expect(back.markdownHonourPostGuide, isFalse);
    });

    // A theme saved before this existed has neither field, and has to read
    // back as the defaults rather than as an empty guide name.
    test("a theme saved before the area existed reads as the default", () {
      var back = AreaStyle.fromJson(const {});
      expect(back.markdownGuideId, defaultGuideId);
      expect(back.markdownHonourPostGuide, isTrue);
    });

    // The defaults write nothing, so an untouched theme file is unchanged
    // by the feature existing.
    test("the defaults are not written out", () {
      var json = const AreaStyle().toJson();
      expect(json.containsKey("markdownGuideId"), isFalse);
      expect(json.containsKey("markdownHonourPostGuide"), isFalse);
    });

    test("a guide that no longer ships falls back rather than breaking", () {
      var style = const AreaStyle().copyWith(markdownGuideId: "removed-guide");
      expect(builtInGuideFor(style.markdownGuideId), isNull,
          reason: "the editor and the renderer both fall back to Default "
              "when the named guide is not one this app has");
    });
  });

  group("the guide that changes nothing", () {
    test("Default leaves the theme's own sizes alone", () {
      var sheet = _sheetFor(builtInGuideFor(defaultGuideId)!);
      expect(sheet.p?.fontSize, 14);
      expect(sheet.h1?.fontSize, 28);
    });

    // The point of Default existing as a named thing rather than as an
    // absence: "use the plain one" is a choice a writer can make.
    test("Default is a built-in and is first in the list", () {
      expect(builtInGuides.first.id, defaultGuideId);
      expect(builtInGuideFor(defaultGuideId)!.builtIn, isTrue);
    });
  });

  group("sizes are a multiple of the theme's, not a replacement", () {
    // A guide written against a 14-point body still reads correctly for
    // someone who has set their text larger, which is the whole reason
    // scale is not a point size.
    test("a scale multiplies whatever the reader has", () {
      var rule = const TextRule(scale: 2.0);
      expect(rule.applyTo(const TextStyle(fontSize: 10), _role).fontSize, 20);
      expect(rule.applyTo(const TextStyle(fontSize: 20), _role).fontSize, 40);
    });

    test("a scale is bounded at both ends", () {
      expect(
          const TextRule(scale: 99)
              .applyTo(const TextStyle(fontSize: 10), _role)
              .fontSize,
          30,
          reason: "text that fills the screen is a way of shouting");
      expect(
          const TextRule(scale: 0.01)
              .applyTo(const TextStyle(fontSize: 10), _role)
              .fontSize,
          6,
          reason: "text scaled to nothing is a way of hiding");
    });

    test("a line height is bounded", () {
      expect(const TextRule(lineHeight: 99).applyTo(_body, _role).height, 3.0);
      expect(const TextRule(lineHeight: 0.1).applyTo(_body, _role).height, 0.9,
          reason: "lines that overlap the one above are unreadable");
    });
  });

  group("colours", () {
    test("a role resolves against the reader's theme", () {
      var style = const TextRule(ink: MarkdownInk.of(MarkdownRole.accent))
          .applyTo(_body, _role);
      expect(style.color, const Color(0xFF0055FF));
    });

    test("a literal is used as given", () {
      var style = const TextRule(ink: MarkdownInk.literal(Color(0xFFAABBCC)))
          .applyTo(_body, _role);
      expect(style.color, const Color(0xFFAABBCC));
    });

    test("saying nothing leaves the theme's colour", () {
      expect(const TextRule().applyTo(_body, _role).color,
          const Color(0xFF111111));
    });
  });

  group("what a guide says nothing about is left alone", () {
    // The reason a guide can be short: it is a departure from the theme
    // rather than a full specification.
    test("an unmentioned element keeps the theme's style", () {
      var guide = const MarkdownStyleGuide(
          id: "x", name: "X", body: TextRule(scale: 2));
      var sheet = _sheetFor(guide);
      expect(sheet.p?.fontSize, 28);
      expect(sheet.h1?.fontSize, 28, reason: "h1 was never mentioned");
    });

    // The bar and the background are one decoration, so setting one must
    // not wipe the other.
    test("setting only the quote bar keeps the theme's quote background", () {
      var base = _base().copyWith(
          blockquoteDecoration: const BoxDecoration(color: Color(0xFF222222)));
      var sheet = applyGuide(
          base,
          const MarkdownStyleGuide(
              id: "x",
              name: "X",
              quoteBarInk: MarkdownInk.of(MarkdownRole.accent)),
          _role);
      var decoration = sheet.blockquoteDecoration as BoxDecoration;
      expect(decoration.color, const Color(0xFF222222));
      expect(decoration.border?.bottom.color, isNot(const Color(0xFF222222)));
    });
  });

  // Reported: paragraphs came out dark purple under every guide but
  // Default, and links lost their styling the same way.
  //
  // The app's stylesheet names only the few things it overrides and leaves
  // the rest null; MarkdownBody fills those from the Material theme. A guide
  // writing into a null field therefore replaced a value that had not been
  // worked out yet -- and it was working from DefaultTextStyle, which is
  // near-black with a purple cast while the theme's own text is near-white.
  group("a guide does not invent what it was not told", () {
    test("an unset colour stays unset", () {
      var sparse = MarkdownStyleSheet(p: const TextStyle(fontSize: 14));
      var sheet = applyGuide(sparse, builtInGuideFor("article")!, _role);
      expect(sheet.p?.color, isNull,
          reason: "inventing one here is what painted every paragraph in "
              "whatever colour the guide happened to be working from");
    });

    test("a colour that was set is kept", () {
      var sheet = applyGuide(_base(), builtInGuideFor("article")!, _role);
      expect(sheet.p?.color, const Color(0xFF111111));
    });

    // Article does change the line height, so the test above is not passing
    // merely because nothing was applied.
    test("the rest of the rule still applies", () {
      var sheet = applyGuide(_base(), builtInGuideFor("article")!, _role);
      expect(sheet.p?.height, 1.6);
    });
  });

  group("underlining a link", () {
    test("a guide can ask for one", () {
      var sheet = applyGuide(_base(), builtInGuideFor("article")!, _role);
      expect(sheet.a?.decoration, TextDecoration.underline);
    });

    // Saying nothing has to leave whatever the theme does, which is what
    // Default is.
    test("saying nothing leaves the theme's own", () {
      var base = _base()
          .copyWith(a: const TextStyle(decoration: TextDecoration.underline));
      var sheet =
          applyGuide(base, const MarkdownStyleGuide(id: "x", name: "X"), _role);
      expect(sheet.a?.decoration, TextDecoration.underline);
    });

    test("a guide can ask for none", () {
      var base = _base()
          .copyWith(a: const TextStyle(decoration: TextDecoration.underline));
      var sheet = applyGuide(
          base,
          const MarkdownStyleGuide(
              id: "x", name: "X", link: TextRule(underline: false)),
          _role);
      expect(sheet.a?.decoration, TextDecoration.none);
    });
  });

  // Reported: Article's lists were too airy. flutter_markdown puts one
  // spacing figure between every pair of blocks -- paragraphs and list items
  // alike -- so the gap that made the prose read well pulled the bullets
  // apart.
  group("paragraphs and list items are spaced separately", () {
    test("the shared figure is the list's, and paragraphs add their own", () {
      var guide = const MarkdownStyleGuide(
          id: "x", name: "X", blockGap: 16, listItemGap: 4);
      var sheet = applyGuide(_base(), guide, _role);
      expect(sheet.blockSpacing, 4, reason: "what goes between list items");
      expect(sheet.pPadding?.bottom, 12,
          reason: "paragraphs make up the difference to 16 themselves");
    });

    test("a guide that wants them equal adds no padding", () {
      var guide = const MarkdownStyleGuide(
          id: "x", name: "X", blockGap: 8, listItemGap: 8);
      var sheet = applyGuide(_base(), guide, _role);
      expect(sheet.pPadding?.bottom, 0);
    });

    test("Article no longer spaces its bullets like paragraphs", () {
      var article = builtInGuideFor("article")!;
      expect(article.listItemGap, lessThan(article.blockGap));
    });
  });

  // Reported: the image options were described on the page but could not be
  // changed. They are settings of the theme now, layered over whichever
  // guide is chosen.
  group("the theme's own picture settings", () {
    test("an untouched theme follows the guide exactly", () {
      var article = builtInGuideFor("article")!;
      var image = const AreaStyle().markdownImage(article.image);
      expect(image.widthPercent, article.image.widthPercent);
      expect(image.cornerRadius, article.image.cornerRadius);
      expect(image.gap, article.image.gap);
    });

    // Changing one thing must not drag the rest off the guide with it.
    test("only what was touched is overridden", () {
      var article = builtInGuideFor("article")!;
      var style = const AreaStyle().copyWith(markdownImageRadius: 24);
      var image = style.markdownImage(article.image);
      expect(image.cornerRadius, 24);
      expect(image.widthPercent, article.image.widthPercent,
          reason: "the guide's width was never touched");
      expect(image.gap, article.image.gap);
    });

    test("switching guide changes what an untouched setting follows", () {
      var style = const AreaStyle().copyWith(markdownImageRadius: 24);
      var underArticle = style.markdownImage(builtInGuideFor("article")!.image);
      var underCompact = style.markdownImage(builtInGuideFor("compact")!.image);
      expect(underArticle.cornerRadius, 24);
      expect(underCompact.cornerRadius, 24);
      expect(underCompact.widthPercent, isNot(underArticle.widthPercent));
    });

    test("the settings survive being saved and read back", () {
      var style = const AreaStyle().copyWith(
        markdownImageWidthPercent: 60,
        markdownImageRadius: 12,
        markdownImageBorderWidth: 2,
        markdownImageBorderColor: const Color(0xFF445566),
        markdownImageBorderColorIndex: 3,
        markdownImageGap: 20,
        markdownImageAlign: MarkdownAlign.center,
      );
      var back = AreaStyle.fromJson(style.toJson());
      expect(back.markdownImageWidthPercent, 60);
      expect(back.markdownImageRadius, 12);
      expect(back.markdownImageBorderWidth, 2);
      expect(back.markdownImageBorderColor, const Color(0xFF445566));
      expect(back.markdownImageBorderColorIndex, 3);
      expect(back.markdownImageGap, 20);
      expect(back.markdownImageAlign, MarkdownAlign.center);
    });

    test("an untouched theme writes none of them out", () {
      var json = const AreaStyle().toJson();
      expect(json.keys.where((k) => k.startsWith("markdownImage")), isEmpty);
    });

    test("a border colour can be taken back off", () {
      var style = const AreaStyle()
          .copyWith(markdownImageBorderColor: const Color(0xFF445566))
          .copyWith(clearMarkdownImageBorderColor: true);
      expect(style.markdownImageBorderColor, isNull);
      expect(style.markdownImageBorderColorIndex, isNull);
    });
  });

  // A built-in is what a published post names, so it has to mean the same
  // thing on every device. Editing one therefore cannot change it.
  group("editing a built-in makes a guide of your own", () {
    test("a fork is no longer built in and has its own id", () {
      var forked = builtInGuideFor("article")!.forked("custom");
      expect(forked.builtIn, isFalse);
      expect(forked.id, "custom");
      expect(forked.name, "Article (edited)");
    });

    test("the built-in it came from is untouched", () {
      var article = builtInGuideFor("article")!;
      article.forked("custom").copyWith(blockGap: 99);
      expect(builtInGuideFor("article")!.blockGap, article.blockGap);
      expect(builtInGuideFor("article")!.builtIn, isTrue);
    });

    test("a fork keeps everything it was forked from", () {
      var article = builtInGuideFor("article")!;
      var forked = article.forked("custom");
      expect(forked.blockGap, article.blockGap);
      expect(forked.body.lineHeight, article.body.lineHeight);
      expect(forked.headings[0].scale, article.headings[0].scale);
      expect(forked.image.cornerRadius, article.image.cornerRadius);
    });

    test("a whole guide survives being saved and read back", () {
      var guide = builtInGuideFor("article")!
          .forked("custom")
          .copyWith(blockGap: 22, listItemGap: 3);
      var back = MarkdownStyleGuide.fromJson(guide.toJson());
      expect(back.id, "custom");
      expect(back.name, "Article (edited)");
      expect(back.blockGap, 22);
      expect(back.listItemGap, 3);
      expect(back.body.lineHeight, guide.body.lineHeight);
      expect(back.headings[0].scale, guide.headings[0].scale);
      expect(back.link.underline, guide.link.underline);
      expect(back.image.cornerRadius, guide.image.cornerRadius);
    });

    test("the theme renders with the fork once there is one", () {
      var custom =
          builtInGuideFor("compact")!.forked("custom").copyWith(blockGap: 40);
      var style = const AreaStyle().copyWith(
          markdownGuideId: "article", markdownCustomGuide: custom.toJson());
      expect(style.markdownGuide(builtInGuideFor("article")).blockGap, 40,
          reason: "the reader's own guide wins over the name beside it");
    });

    test("choosing a guide again starts from that one", () {
      var style = const AreaStyle().copyWith(markdownCustomGuide: {
        "id": "custom",
        "name": "Mine"
      }).copyWith(markdownGuideId: "compact", clearMarkdownCustomGuide: true);
      expect(style.markdownCustomGuide, isNull);
      expect(style.markdownGuide(builtInGuideFor("compact")).id, "compact");
    });
  });

  group("the built-ins", () {
    // These are the ones a post can rely on, because every device has them.
    test("each has a distinct id and a name", () {
      var ids = builtInGuides.map((g) => g.id).toSet();
      expect(ids.length, builtInGuides.length);
      for (var guide in builtInGuides) {
        expect(guide.name, isNotEmpty);
        expect(guide.builtIn, isTrue);
        expect(guide.headings, hasLength(6));
      }
    });

    test("an unknown name is nobody's guide", () {
      expect(builtInGuideFor("no-such-guide"), isNull);
    });

    test("Article reads more loosely than Compact", () {
      var article = _sheetFor(builtInGuideFor("article")!);
      var compact = _sheetFor(builtInGuideFor("compact")!);
      expect(article.blockSpacing, greaterThan(compact.blockSpacing!));
      expect(article.p!.height!, greaterThan(compact.p!.height!));
    });

    test("Terminal sets the body in the monospaced face", () {
      var sheet = _sheetFor(builtInGuideFor("terminal")!);
      expect(sheet.p?.fontFamily, "RobotoMono");
    });
  });

  // Reported: choosing a font changed nothing. The list named families the
  // app does not bundle -- "SourceCodePro" and "serif" -- and a missing
  // family falls back silently rather than failing, so the setting looked
  // broken while behaving exactly as asked.
  group("every font on offer is one the app ships", () {
    test("only Inter and RobotoMono, plus inheriting", () {
      var families = MarkdownFont.values
          .map((f) => f.family)
          .where((f) => f != null)
          .toSet();
      expect(families, {"Inter", "RobotoMono"},
          reason: "anything else falls back to a different face on every "
              "device, which is the thing a style guide is for avoiding");
    });

    test("the default is to leave the theme's font alone", () {
      expect(MarkdownFont.inherit.family, isNull);
      expect(
          const TextRule()
              .applyTo(const TextStyle(fontFamily: "Inter"),
                  (_) => const Color(0xFF000000))
              .fontFamily,
          "Inter");
    });

    test("a chosen font is applied", () {
      var style = const TextRule(font: MarkdownFont.mono).applyTo(
          const TextStyle(fontFamily: "Inter"), (_) => const Color(0xFF000000));
      expect(style.fontFamily, "RobotoMono");
    });
  });

  group("the JSON a saved guide is written as", () {
    test("a rule survives the round trip", () {
      var rule = const TextRule(
          scale: 1.5,
          ink: MarkdownInk.of(MarkdownRole.accent),
          font: MarkdownFont.mono,
          bold: true,
          lineHeight: 1.6);
      var back = TextRule.fromJson(rule.toJson());
      expect(back.scale, 1.5);
      expect(back.ink.role, MarkdownRole.accent);
      expect(back.font, MarkdownFont.mono);
      expect(back.bold, isTrue);
      expect(back.lineHeight, 1.6);
    });

    test("a rule that says nothing writes nothing", () {
      expect(const TextRule().toJson(), isEmpty);
    });

    // The file is one the user can edit, so every field has to survive
    // being wrong.
    test("nonsense in the file reads as saying nothing", () {
      expect(MarkdownInk.fromJson("not-a-role").isInherit, isTrue);
      expect(MarkdownInk.fromJson("#zzzzzz").isInherit, isTrue);
      expect(MarkdownInk.fromJson(null).isInherit, isTrue);
      expect(TextRule.fromJson({"scale": "big"}).scale, 1.0);
    });

    test("an image rule survives the round trip", () {
      var rule = const ImageRule(
          widthPercent: 60,
          cornerRadius: 12,
          borderWidth: 2,
          align: MarkdownAlign.center);
      var back = ImageRule.fromJson(rule.toJson());
      expect(back.widthPercent, 60);
      expect(back.cornerRadius, 12);
      expect(back.align, MarkdownAlign.center);
    });

    test("an image is bounded too", () {
      expect(const ImageRule(widthPercent: 400).boundedWidth, 100);
      expect(const ImageRule(widthPercent: 1).boundedWidth, 10);
      expect(const ImageRule(cornerRadius: 900).boundedRadius, 48);
    });
  });
}
