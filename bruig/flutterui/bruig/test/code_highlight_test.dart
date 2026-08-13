import 'package:bruig/components/feed/code_highlight.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// code_highlight_test.dart covers the fenced-block highlighter.
//
// It is deliberately language-agnostic (a fenced block reaches the renderer
// as plain text, with the language after the backticks already consumed by
// the parser), so what is worth pinning is that it never mistakes one kind
// of run for another -- a keyword inside a string, a quote inside a comment.

const _ink = CodeInk(
  text: Color(0xFF000001),
  comment: Color(0xFF000002),
  string: Color(0xFF000003),
  number: Color(0xFF000004),
  keyword: Color(0xFF000005),
);

/// _kindOf is which colour the run containing [needle] came out.
Color? _colourOf(String code, String needle) {
  for (var span in highlightCode(code, _ink, null)) {
    if ((span.text ?? "").contains(needle)) return span.style?.color;
  }
  return null;
}

String _joined(String code) =>
    highlightCode(code, _ink, null).map((s) => s.text ?? "").join();

void main() {
  test("nothing is lost", () {
    var code = 'var x = "hi"; // note\n/* block */ return 42;';
    expect(_joined(code), code);
  });

  test("the four kinds are told apart", () {
    expect(_colourOf('// a note', 'a note'), _ink.comment);
    expect(_colourOf('x = "text"', '"text"'), _ink.string);
    expect(_colourOf('x = 42', '42'), _ink.number);
    expect(_colourOf('return x', 'return'), _ink.keyword);
  });

  test("a keyword inside a string stays part of the string", () {
    // The mistake that makes naive highlighting look broken.
    expect(_colourOf('var s = "return true";', '"return true"'), _ink.string);
  });

  test("a quote inside a comment stays part of the comment", () {
    expect(_colourOf('// it\'s fine\nx = 1', "it's fine"), _ink.comment);
  });

  test("an unclosed quote colours its line, not the rest of the block", () {
    var out = highlightCode('x = "oops\nreturn 1', _ink, null);
    // `return` on the next line is still found as a keyword.
    expect(out.any((s) => s.text == "return" && s.style?.color == _ink.keyword),
        isTrue);
  });

  test("a hash is a comment only at the start of a line", () {
    expect(_colourOf('# a python comment', 'a python comment'), _ink.comment);
    // ...so a colour literal is not swallowed.
    expect(_colourOf('c = "#ff0000"', '"#ff0000"'), _ink.string);
  });

  test("an unterminated block comment is still a comment", () {
    expect(_colourOf('/* never closed', 'never closed'), _ink.comment);
  });

  test("an ordinary identifier is left alone", () {
    expect(_colourOf('channels = 1', 'channels'), _ink.text);
  });

  test("empty code produces nothing", () {
    expect(highlightCode("", _ink, null), isEmpty);
  });

  group("the guide carries the new code settings", () {
    test("they round-trip through JSON", () {
      var g = const MarkdownStyleGuide(
        id: "g",
        name: "G",
        codePadding: 20,
        codeLineNumbers: true,
        codeHighlight: true,
      );
      var back = MarkdownStyleGuide.fromJson(g.toJson());
      expect(back.codePadding, 20);
      expect(back.codeLineNumbers, isTrue);
      expect(back.codeHighlight, isTrue);
    });

    test("an untouched guide writes none of them", () {
      var json = const MarkdownStyleGuide(id: "g", name: "G").toJson();
      expect(json.containsKey("codePadding"), isFalse);
      expect(json.containsKey("codeLineNumbers"), isFalse);
      expect(json.containsKey("codeHighlight"), isFalse);
      var back = MarkdownStyleGuide.fromJson(json);
      expect(back.codePadding, isNull, reason: "null means the built-in 8");
      expect(back.codeLineNumbers, isFalse);
      expect(back.codeHighlight, isFalse);
    });

    test("a card's button role round-trips", () {
      var g = const MarkdownStyleGuide(
          id: "g", name: "G", cards: CardRule(button: ButtonRole.outlined));
      expect(MarkdownStyleGuide.fromJson(g.toJson()).cards.button,
          ButtonRole.outlined);
      // Plain is the default and stays out of the file.
      expect(
          const MarkdownStyleGuide(id: "g", name: "G").cards.button,
          ButtonRole.plain);
      expect(const CardRule().toJson().containsKey("button"), isFalse);
    });
  });
}
