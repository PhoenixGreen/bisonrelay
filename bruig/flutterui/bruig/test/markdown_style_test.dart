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
    });

    test("a chosen guide survives being saved and read back", () {
      var style = const AreaStyle().copyWith(markdownGuideId: "article");
      var back = AreaStyle.fromJson(style.toJson());
      expect(back.markdownGuideId, "article");
    });

    // A theme saved before this existed has neither field, and has to read
    // back as the defaults rather than as an empty guide name.
    test("a theme saved before the area existed reads as the default", () {
      var back = AreaStyle.fromJson(const {});
      expect(back.markdownGuideId, defaultGuideId);
    });

    // The defaults write nothing, so an untouched theme file is unchanged
    // by the feature existing.
    test("the defaults are not written out", () {
      var json = const AreaStyle().toJson();
      expect(json.containsKey("markdownGuideId"), isFalse);
    });

    test("a guide that no longer ships falls back rather than breaking", () {
      var style = const AreaStyle().copyWith(markdownGuideId: "removed-guide");
      expect(builtInGuideFor(style.markdownGuideId), isNull,
          reason: "the editor and the renderer both fall back to Default "
              "when the named guide is not one this app has");
    });
  });

  group("the guide that changes nothing", () {
    // Default leaves the body exactly as the theme has it and states the
    // heading ladder the app has always drawn -- 24 points against a
    // 14-point body, and so on down.
    //
    // It has to state it rather than leave it unsaid, because every size in
    // a guide is a share of the body: an unsaid heading size means "the same
    // size as the body", which is what a reader who changed one unrelated
    // thing about Default used to get.
    test("Default keeps the body and states the customary ladder", () {
      var sheet = _sheetFor(builtInGuideFor(defaultGuideId)!);
      expect(sheet.p?.fontSize, 14);
      expect(sheet.h1?.fontSize, closeTo(24, 0.001));
      expect(sheet.h5?.fontSize, closeTo(14, 0.001));
      expect(sheet.h6?.fontSize, closeTo(12, 0.001));
    });

    // The sizes the editor's sliders read out are the sizes that come out
    // the other end. A guide is written against the body -- "H1: 190%" --
    // and used to be applied to whatever size the theme gave that element,
    // so Article's 1.9 landed on a 24-point h1 and came out at 45.
    test("a heading is a share of the body, not of the theme's own heading",
        () {
      var sheet = _sheetFor(const MarkdownStyleGuide(
        id: "x",
        name: "X",
        headings: [
          TextRule(scale: 1.9),
          TextRule(),
          TextRule(),
          TextRule(),
          TextRule(),
          TextRule(),
        ],
      ));
      expect(sheet.h1?.fontSize, closeTo(14 * 1.9, 0.001),
          reason: "the base sheet's own h1 is 28, which is not the body");
    });

    // A link, a bold word and an italic one are runs inside a line, and
    // flutter_markdown builds them by merging their style onto the style of
    // whatever they sit in. A size stated here replaces the surrounding
    // text's, so at 100% none is stated -- otherwise a link in a heading and
    // a bold word in a heading both came out at 14 points.
    test("an inline run at 100% keeps the size around it", () {
      var sheet = applyGuide(
          MarkdownStyleSheet(
              p: const TextStyle(fontSize: 20, color: Color(0xFF111111)),
              a: const TextStyle(color: Color(0xFF0077CC)),
              strong: const TextStyle(fontWeight: FontWeight.w700)),
          const MarkdownStyleGuide(id: "x", name: "X"),
          _role);
      expect(sheet.a?.fontSize, isNull);
      expect(sheet.strong?.fontSize, isNull);
      expect(sheet.strong?.fontWeight, FontWeight.w700,
          reason: "saying nothing about size says nothing about weight");
    });

    test("an inline run that asks for a size gets a share of the body", () {
      var sheet = applyGuide(
          MarkdownStyleSheet(
              p: const TextStyle(fontSize: 20, color: Color(0xFF111111)),
              a: const TextStyle(color: Color(0xFF0077CC))),
          const MarkdownStyleGuide(
              id: "x", name: "X", link: TextRule(scale: 1.5)),
          _role);
      expect(sheet.a?.fontSize, closeTo(30, 0.001));
    });

    // An underline with no colour of its own is drawn in whatever
    // decorationColor the style carries, and flutter_markdown builds a link
    // by merging `a` onto the paragraph's style -- so an underlined link
    // came out with its letters in one colour and the line under them in
    // the body's.
    test("an underline is the colour of the text it underlines", () {
      var sheet = _sheetFor(const MarkdownStyleGuide(
        id: "x",
        name: "X",
        link: TextRule(ink: MarkdownInk.of(MarkdownRole.link), underline: true),
      ));
      expect(sheet.a?.decoration, TextDecoration.underline);
      expect(sheet.a?.decorationColor, sheet.a?.color);
      expect(sheet.a?.color, _role(MarkdownRole.link));
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

  // Code, which is drawn twice over: once as the block's decoration and once
  // as a background behind the letters themselves.
  //
  // MarkdownStyleSheet.fromTheme gives `code` a backgroundColor of the card
  // colour and nothing in the app cleared it, so a code block came out with a
  // second, differently coloured shape folded tightly around its text and
  // broken between the lines. Reported from the settings preview, where the
  // block was blue and the shape behind the words was not.
  group("code has one background, not two", () {
    test("the letters are painted in the block's own colour", () {
      var sheet = applyGuide(
          _base().copyWith(
              code: const TextStyle(backgroundColor: Color(0xFF333333))),
          const MarkdownStyleGuide(
            id: "x",
            name: "X",
            codeBackground: MarkdownInk.of(MarkdownRole.raised),
          ),
          _role);
      expect(sheet.code?.backgroundColor, _role(MarkdownRole.raised));
      expect((sheet.codeblockDecoration! as BoxDecoration).color,
          sheet.code?.backgroundColor,
          reason: "the same colour twice over is the same colour once");
    });

    test("with no colour named nothing is painted behind the letters", () {
      var sheet = applyGuide(
          _base().copyWith(
              code: const TextStyle(backgroundColor: Color(0xFF333333))),
          const MarkdownStyleGuide(id: "x", name: "X"),
          _role);
      expect(sheet.code?.backgroundColor, const Color(0x00000000),
          reason: "a TextStyle field cannot be un-set, so it is transparent");
    });
  });

  group("quotations", () {
    test("the padding is the guide's", () {
      var sheet = _sheetFor(
          const MarkdownStyleGuide(id: "x", name: "X", quotePadding: 20));
      expect(sheet.blockquotePadding, const EdgeInsets.all(20));
    });

    test("the padding survives being saved and read back", () {
      var guide = const MarkdownStyleGuide(id: "x", name: "X")
          .copyWith(quotePadding: 24);
      expect(MarkdownStyleGuide.fromJson(guide.toJson()).quotePadding, 24);
    });

    test("the padding is bounded", () {
      var sheet = _sheetFor(
          const MarkdownStyleGuide(id: "x", name: "X", quotePadding: 400));
      expect(sheet.blockquotePadding, const EdgeInsets.all(40));
    });
  });

  // The design a table needs to be read across as well as down: a header row
  // told apart from the body, every other row tinted, cells with room in
  // them, and a choice about how the width is divided.
  group("tables", () {
    test("the header row gets a background of its own", () {
      var sheet = _sheetFor(const MarkdownStyleGuide(
        id: "x",
        name: "X",
        tableHeadBackground: MarkdownInk.of(MarkdownRole.raised),
      ));
      expect(sheet.tableHeadDecoration?.color, _role(MarkdownRole.raised));
    });

    test("alternating rows get theirs", () {
      var sheet = _sheetFor(const MarkdownStyleGuide(
        id: "x",
        name: "X",
        tableStripeInk: MarkdownInk.of(MarkdownRole.raised),
      ));
      expect((sheet.tableCellsDecoration! as BoxDecoration).color,
          _role(MarkdownRole.raised));
    });

    // Naming neither leaves a table exactly as the theme draws one, which is
    // what a guide that says nothing has to mean.
    test("naming neither paints nothing", () {
      var sheet = _sheetFor(const MarkdownStyleGuide(id: "x", name: "X"));
      expect(sheet.tableHeadDecoration, isNull);
      expect(sheet.tableCellsDecoration, isNull);
    });

    test("cell padding is wider than it is tall", () {
      var sheet = _sheetFor(
          const MarkdownStyleGuide(id: "x", name: "X", tableCellPadding: 10));
      expect(sheet.tableCellsPadding?.top, 10);
      expect(sheet.tableCellsPadding?.left, greaterThan(10),
          reason: "a cell needs more room beside its text than above it");
    });

    test("the columns divide the width or fit their contents", () {
      expect(
          _sheetFor(const MarkdownStyleGuide(id: "x", name: "X"))
              .tableColumnWidth,
          isA<FlexColumnWidth>());
      expect(
          _sheetFor(const MarkdownStyleGuide(
                  id: "x", name: "X", tableFit: MarkdownTableFit.fitContent))
              .tableColumnWidth,
          isA<IntrinsicColumnWidth>());
    });

    test("every table setting survives being saved", () {
      var guide = const MarkdownStyleGuide(id: "x", name: "X").copyWith(
        tableHeadBackground: const MarkdownInk.of(MarkdownRole.accent),
        tableStripeInk: const MarkdownInk.of(MarkdownRole.raised),
        tableCellPadding: 12,
        tableFit: MarkdownTableFit.fitContent,
      );
      var back = MarkdownStyleGuide.fromJson(guide.toJson());
      expect(back.tableHeadBackground.role, MarkdownRole.accent);
      expect(back.tableStripeInk.role, MarkdownRole.raised);
      expect(back.tableCellPadding, 12);
      expect(back.tableFit, MarkdownTableFit.fitContent);
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
  // Two gaps, and every block gets the one that belongs to it.
  //
  // Upstream flutter_markdown has a single figure and puts it between every
  // pair of block children, list items included. This used to set it to the
  // smaller of the two and have paragraphs make up the difference with
  // padding of their own -- but only a paragraph can do that. There is no
  // such padding for a quotation, a code block, a table or a rule, so
  // everything except prose sat hard against whatever came before it and
  // the blank line the writer left produced no space at all. The vendored
  // copy takes both figures.
  group("paragraphs and list items are spaced separately", () {
    test("blocks get the block gap and list items get their own", () {
      var guide = const MarkdownStyleGuide(
          id: "x", name: "X", blockGap: 16, listItemGap: 4);
      var sheet = applyGuide(_base(), guide, _role);
      expect(sheet.blockSpacing, 16,
          reason: "what goes between a heading and the quotation under it");
      expect(sheet.listItemSpacing, 4, reason: "what goes between bullets");
    });

    // The padding is what the old workaround was made of, and a paragraph
    // carrying it as well would now be spaced twice over.
    test("paragraphs no longer carry a gap of their own", () {
      var guide = const MarkdownStyleGuide(
          id: "x", name: "X", blockGap: 16, listItemGap: 4);
      var sheet = applyGuide(_base(), guide, _role);
      expect(sheet.pPadding, EdgeInsets.zero);
    });

    test("both are bounded", () {
      var guide = const MarkdownStyleGuide(
          id: "x", name: "X", blockGap: 400, listItemGap: 400);
      var sheet = applyGuide(_base(), guide, _role);
      expect(sheet.blockSpacing, 48);
      expect(sheet.listItemSpacing, 48);
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

  // Reported as "bold, italic and underline do nothing for links", and it
  // was true of every setting on the page.
  //
  // The renderer resolved a guide by looking its name up among the
  // built-ins. A reader who has edited theirs has a guide that is not among
  // them -- it is a fork, saved on the theme -- so every change was stored
  // correctly and then drawn by the built-in it had been forked from.
  group("a theme's own guide is what gets rendered", () {
    test("an edited guide is not findable among the built-ins", () {
      var forked = builtInGuideFor("default")!
          .forked("custom")
          .copyWith(link: const TextRule(bold: true, underline: true));
      expect(builtInGuideFor(forked.id), isNull,
          reason: "which is why looking it up by name lost every edit");
    });

    test("the theme hands back the fork, not the name beside it", () {
      var forked = builtInGuideFor("default")!
          .forked("custom")
          .copyWith(link: const TextRule(bold: true, underline: true));
      var style = const AreaStyle().copyWith(
          markdownGuideId: defaultGuideId,
          markdownCustomGuide: forked.toJson());

      var rendered = style.markdownGuide(builtInGuideFor(defaultGuideId));
      expect(rendered.link.bold, isTrue);
      expect(rendered.link.underline, isTrue);
    });

    test("the edits reach the stylesheet", () {
      var forked = builtInGuideFor("default")!.forked("custom").copyWith(
          link: const TextRule(bold: true, italic: true, underline: true));
      var sheet = applyGuide(_base(), forked, _role);
      expect(sheet.a?.fontWeight, FontWeight.w700);
      expect(sheet.a?.fontStyle, FontStyle.italic);
      expect(sheet.a?.decoration, TextDecoration.underline);
    });

    // Default is skipped as an optimisation, and that skip must not throw
    // away the work of somebody who edited Default itself.
    test("an edited Default still carries its edits", () {
      var edited = const MarkdownStyleGuide(id: defaultGuideId, name: "Default")
          .copyWith(blockGap: 30);
      var style =
          const AreaStyle().copyWith(markdownCustomGuide: edited.toJson());
      expect(style.markdownGuide(null).blockGap, 30);
    });
  });

  group("saving and deleting a guide of your own", () {
    var mine = const MarkdownStyleGuide(id: "guide-1", name: "Mine")
        .copyWith(blockGap: 21);

    test("a saved guide joins the built-ins in the picker", () {
      var style = const AreaStyle()
          .copyWith(markdownSavedGuides: {"guide-1": mine.toJson()});
      var choices = style.markdownGuideChoices(builtInGuides);
      expect(choices.length, builtInGuides.length + 1);
      expect(choices.last.name, "Mine");
    });

    test("choosing a saved guide renders it", () {
      var style = const AreaStyle().copyWith(
          markdownSavedGuides: {"guide-1": mine.toJson()},
          markdownGuideId: "guide-1");
      expect(style.markdownGuide(null).blockGap, 21);
    });

    // The working copy is what is in use until it is saved, so it has to
    // win over whatever name is selected beside it.
    test("unsaved changes are what renders", () {
      var style = const AreaStyle().copyWith(
        markdownSavedGuides: {"guide-1": mine.toJson()},
        markdownGuideId: "guide-1",
        markdownCustomGuide: mine.copyWith(blockGap: 44).toJson(),
      );
      expect(style.markdownGuide(null).blockGap, 44);
    });

    test("deleting one takes it out of the picker", () {
      var style = const AreaStyle()
          .copyWith(markdownSavedGuides: {"guide-1": mine.toJson()});
      var after = style.copyWith(
          markdownSavedGuides: {...style.markdownSavedGuides}
            ..remove("guide-1"),
          markdownGuideId: defaultGuideId);
      expect(after.markdownGuideChoices(builtInGuides).length,
          builtInGuides.length);
    });

    test("the library survives being saved and read back", () {
      var style = const AreaStyle()
          .copyWith(markdownSavedGuides: {"guide-1": mine.toJson()});
      var back = AreaStyle.fromJson(style.toJson());
      expect(back.markdownSavedGuides.keys, ["guide-1"]);
      expect(back.markdownGuideChoices(builtInGuides).last.blockGap, 21);
    });

    test("a theme with no guides of its own writes none", () {
      expect(const AreaStyle().toJson().containsKey("markdownSavedGuides"),
          isFalse);
    });
  });

  // Reported: setting a quote's bar width did nothing, and setting its
  // background removed the bar. The decoration was rebuilt only when the
  // guide named a colour, and that branch wrote a null border whenever no
  // bar colour had been given.
  group("quote decoration", () {
    MarkdownStyleSheet baseWithBar() => _base().copyWith(
        blockquoteDecoration: const BoxDecoration(
            color: Color(0xFF222222),
            border:
                Border(left: BorderSide(color: Color(0xFF888888), width: 2))));

    test("a width on its own widens the theme's bar", () {
      var sheet = applyGuide(
          baseWithBar(),
          const MarkdownStyleGuide(id: "x", name: "X", quoteBarWidth: 8),
          _role);
      var border =
          (sheet.blockquoteDecoration as BoxDecoration).border as Border;
      expect(border.left.width, 8);
      expect(border.left.color, const Color(0xFF888888),
          reason: "the colour was never mentioned, so it stays");
    });

    test("a background on its own keeps the bar", () {
      var sheet = applyGuide(
          baseWithBar(),
          const MarkdownStyleGuide(
              id: "x",
              name: "X",
              quoteBackground: MarkdownInk.of(MarkdownRole.raised)),
          _role);
      var decoration = sheet.blockquoteDecoration as BoxDecoration;
      expect(decoration.color, _roles[MarkdownRole.raised]);
      expect((decoration.border as Border).left.width, 2,
          reason: "setting the background used to delete the bar entirely");
    });

    test("a width of zero removes the bar", () {
      var sheet = applyGuide(
          baseWithBar(),
          const MarkdownStyleGuide(id: "x", name: "X", quoteBarWidth: 0),
          _role);
      expect((sheet.blockquoteDecoration as BoxDecoration).border, isNull);
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
      expect(families, {"Inter", "PTSerif", "RobotoMono"},
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
