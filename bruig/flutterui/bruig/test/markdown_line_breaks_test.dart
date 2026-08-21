import 'package:bruig/markdown_line_breaks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

// markdown_line_breaks_test.dart checks the two things that matter about
// hardening a line break: that the break actually appears in the rendered
// output, and that nothing else in the post moves.
//
// The rendering half is checked against the markdown package itself, with the
// same extension set md_elements.dart configures, rather than against the
// string this produces. What matters is not that two spaces were added -- it
// is that a reader sees a break, and only the parser can say that.

/// _html renders [source] the way the app's renderer parses it.
String _html(String source) => md.markdownToHtml(source,
    extensionSet: md.ExtensionSet(md.ExtensionSet.gitHubFlavored.blockSyntaxes,
        [md.EmojiSyntax(), ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes]));

void main() {
  group("the break reaches the reader", () {
    test("a single newline renders as a break once hardened", () {
      const typed = "line one\nline two";

      expect(_html(typed), isNot(contains("<br")),
          reason: "the bug: markdown joins the two lines into one paragraph");
      expect(_html(hardenSoftLineBreaks(typed)), contains("<br"),
          reason: "which is the whole point of the exercise");
    });

    test("every line of a typed-out list of lines breaks", () {
      var html = _html(hardenSoftLineBreaks("one\ntwo\nthree\nfour"));
      expect("<br".allMatches(html).length, 3);
    });

    test("a paragraph break still makes two paragraphs", () {
      var html = _html(hardenSoftLineBreaks("one\n\ntwo"));
      expect("<p>".allMatches(html).length, 2);
      expect(html, isNot(contains("<br")));
    });
  });

  group("what it leaves alone", () {
    test("text with no newline at all is untouched", () {
      expect(hardenSoftLineBreaks("just one line"), "just one line");
    });

    test("a line already followed by a blank one gains nothing", () {
      expect(hardenSoftLineBreaks("one\n\ntwo"), "one\n\ntwo");
    });

    test("the last line gains nothing, having nothing to join to", () {
      expect(hardenSoftLineBreaks("one\ntwo").endsWith("two"), isTrue);
    });

    // Two spaces inside a fence are two characters of somebody's program.
    test("a fenced code block is left exactly as written", () {
      const code = "text\n\n```dart\nvar a = 1;\nvar b = 2;\n```\n\nmore";
      expect(hardenSoftLineBreaks(code), code);
    });

    test("a tilde fence counts as a fence", () {
      const code = "~~~\nline one\nline two\n~~~";
      expect(hardenSoftLineBreaks(code), code);
    });

    test("an indented code block keeps its lines", () {
      const code = "    var a = 1;\n    var b = 2;";
      expect(hardenSoftLineBreaks(code), code);
    });

    // These already break, so adding the spaces would be invisible noise in
    // somebody's post rather than a change of meaning.
    test("a line before a block that breaks anyway is not padded", () {
      for (var next in [
        "# heading",
        "> quoted",
        "- item",
        "* item",
        "1. item",
        "| a | b |",
        "---",
        "```",
      ]) {
        expect(hardenSoftLineBreaks("text\n$next"), "text\n$next",
            reason: 'padded the line before "$next"');
      }
    });

    test("a setext heading keeps its underline", () {
      expect(hardenSoftLineBreaks("Title\n====="), "Title\n=====");
      var html = _html(hardenSoftLineBreaks("Title\n====="));
      expect(html, contains("<h1>"));
    });

    test("an embed line is not padded, nor the line before one", () {
      const embed = "--embed[type=image/png,data=[content abcdef123456]]--";
      expect(hardenSoftLineBreaks("text\n$embed\nmore"), "text\n$embed\nmore");
    });
  });

  group("running it twice changes nothing", () {
    test("a hard break already there is not doubled", () {
      const already = "one  \ntwo";
      expect(hardenSoftLineBreaks(already), already);
    });

    test("a backslash break is recognised as one", () {
      const already = "one\\\ntwo";
      expect(hardenSoftLineBreaks(already), already);
    });

    test("idempotent over a mixed document", () {
      const source = "# Title\n\nA line\nand another\n\n- one\n- two\n\n"
          "```\ncode\nhere\n```\n\nlast\nline";
      var once = hardenSoftLineBreaks(source);
      expect(hardenSoftLineBreaks(once), once);
    });
  });

  group("the text a writer actually types", () {
    test("an address keeps its shape", () {
      const typed = "Jane Smith\n12 High Street\nCardiff\nCF10 1AA";
      var html = _html(hardenSoftLineBreaks(typed));
      expect("<br".allMatches(html).length, 3);
      expect("<p>".allMatches(html).length, 1,
          reason: "an address is one paragraph with breaks, not four");
    });

    test("a list under a sentence is still a list", () {
      const typed = "Here is the plan:\n- first\n- second";
      var html = _html(hardenSoftLineBreaks(typed));
      expect(html, contains("<li>"));
      expect("<li>".allMatches(html).length, 2);
    });
  });
}
