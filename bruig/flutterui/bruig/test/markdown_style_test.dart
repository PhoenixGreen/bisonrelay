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
    applyGuide(_base(), guide, _role, bodyStyle: _body);

void main() {
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
          const TextRule(scale: 99).applyTo(const TextStyle(fontSize: 10), _role).fontSize,
          30,
          reason: "text that fills the screen is a way of shouting");
      expect(
          const TextRule(scale: 0.01).applyTo(const TextStyle(fontSize: 10), _role).fontSize,
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
      expect(const TextRule().applyTo(_body, _role).color, const Color(0xFF111111));
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
          _role,
          bodyStyle: _body);
      var decoration = sheet.blockquoteDecoration as BoxDecoration;
      expect(decoration.color, const Color(0xFF222222));
      expect(decoration.border?.bottom.color, isNot(const Color(0xFF222222)));
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
      expect(sheet.p?.fontFamily, "SourceCodePro");
    });
  });

  group("the JSON a saved guide is written as", () {
    test("a rule survives the round trip", () {
      var rule = const TextRule(
          scale: 1.5,
          ink: MarkdownInk.of(MarkdownRole.accent),
          font: MarkdownFont.serif,
          bold: true,
          lineHeight: 1.6);
      var back = TextRule.fromJson(rule.toJson());
      expect(back.scale, 1.5);
      expect(back.ink.role, MarkdownRole.accent);
      expect(back.font, MarkdownFont.serif);
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
          widthPercent: 60, cornerRadius: 12, borderWidth: 2,
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
