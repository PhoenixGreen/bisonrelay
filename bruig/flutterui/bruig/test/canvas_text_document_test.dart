import 'dart:ui' show Color;
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/text_document.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_text_document_test.dart is a text element whose words come from the
// Writing library.
//
// What is pinned here is the reading: what a markdown file turns into, and
// what each switch does to it. The words are the point -- a canvas that
// mangles somebody's document is worse than one that cannot read it.

void main() {
  group("reading a document", () {
    test("plain text is the default, and every mark is stripped", () {
      // "Initially only plain text": a headline reading "## Title" is not
      // markdown being ignored, it is markdown showing.
      var (text, parts) = readDocument("""
# A title

Some **bold** and *italic* and a [link](https://example.com).

- a list item
> a quotation
""");
      expect(text, contains("A title"));
      expect(text, isNot(contains("#")));
      expect(text, isNot(contains("**")));
      expect(text, isNot(contains("[")));
      expect(text, contains("Some bold and italic and a link."));
      expect(text, contains("a list item"));
      expect(text, isNot(contains("-")));
      expect(text, contains("a quotation"));
      expect(parts, isEmpty, reason: "no styling comes in with the words");
    });

    test("with markdown on, the pieces become parts", () {
      var (text, parts) = readDocument("A **strong** word.", markdown: true);
      expect(text, "A strong word.");
      expect(parts.length, 1);
      expect(parts.single.weight, 700);
      expect(parts.single.from, 2, reason: "the second word");
      expect(parts.single.to, 2);
    });

    test("and each piece can be turned off on its own", () {
      const source = "# Heading\n**bold** *slanted* __lined__ [link](x)";

      var all =
          readDocument(source, markdown: true, allow: const MarkdownAllow()).$2;
      expect(all.length, 5, reason: "a heading and four inline marks");

      var some = readDocument(source,
          markdown: true,
          allow: const MarkdownAllow(looks: {
            MarkdownKind.bold: MarkdownLook(on: false),
            MarkdownKind.link: MarkdownLook(on: false),
          })).$2;
      expect(some.length, 3);
      expect([for (var p in some) p.scale != null], contains(true),
          reason: "the heading is still there");
      expect([
        for (var p in some) p.scale == null && p.weight == 700
      ], isNot(contains(true)), reason: "and no inline bold is");

      // Turned off, the mark is still stripped: the words are what is left.
      var text = readDocument(source,
          markdown: true,
          allow: const MarkdownAllow(
              looks: {MarkdownKind.bold: MarkdownLook(on: false)})).$1;
      expect(text, isNot(contains("*")));
      expect(text, contains("bold"));
    });

    test("a heading is bigger than what is around it", () {
      var parts = readDocument("# Big\nordinary", markdown: true).$2;
      expect(parts.single.scale, greaterThan(1));
      expect(parts.single.from, 1);
      expect(parts.single.to, 1, reason: "the words of that line only");

      var second = readDocument("## Less big", markdown: true).$2;
      expect(second.single.scale, lessThan(parts.single.scale!));
      expect(second.single.scale, greaterThan(1));
    });

    test("a link is coloured and underlined", () {
      var parts = readDocument("see [the page](x) now", markdown: true).$2;
      expect(parts.single.underline, isNotNull);
      expect(parts.single.color, isNotNull);
      expect(parts.single.from, 2);
      expect(parts.single.to, 3, reason: "both words of the link's text");
    });

    test("an unclosed mark is left as words", () {
      // Half a mark is somebody's asterisk, not a formatting instruction.
      var (text, parts) = readDocument("2 * 3 is not italic", markdown: true);
      expect(text, "2 * 3 is not italic");
      expect(parts, isEmpty);
    });
  });

  group("the element that reads it", () {
    test("keeps the reference beside the words", () {
      // The words are copied in, so the canvas draws the same on a machine
      // that has never seen the library -- and the reference is kept so the
      // document can be read again when it changes.
      var element = TextElement(
        const ElementBase(id: "t", width: 400, height: 200),
        text: "Whatever was read last",
        document: const TextDocumentRef(
            folder: "Plans", name: "Launch", markdown: true),
      );
      var back = elementFromJson(element.toJson()) as TextElement;
      expect(back.text, "Whatever was read last");
      expect(back.document.name, "Launch");
      expect(back.document.folder, "Plans");
      expect(back.document.markdown, isTrue);
      expect(back.document.says, "Plans / Launch");

      // And an element that reads nothing writes nothing.
      expect(
          TextElement(const ElementBase(id: "t", width: 10, height: 10))
              .toJson()
              .containsKey("document"),
          isFalse);
    });

    test("each piece of markdown is drawn the way it was set", () {
      // A switch on its own could only ever make headings look like the one
      // thing this code happened to choose. Everything is an override: left
      // alone, a piece follows the element's own type settings.
      var allow = const MarkdownAllow().withLook(
          MarkdownKind.heading1,
          const MarkdownLook(
              scale: 3,
              color: Color(0xFFFF0000),
              weight: 900,
              family: "Inter"));
      var (_, parts) =
          readDocument("# Title\n\nWords", markdown: true, allow: allow);
      var heading = parts.first;
      expect(heading.scale, 3);
      expect(heading.color, const Color(0xFFFF0000));
      expect(heading.weight, 900);
      expect(heading.family, "Inter");

      // And the default look is the kind's own, so the switch alone is
      // already useful.
      var (_, plain) =
          readDocument("# Title", markdown: true, allow: const MarkdownAllow());
      expect(plain.single.scale, MarkdownKind.heading1.scale);
      expect(plain.single.weight, 700);

      // Switched off, the mark is stripped and there is no part at all.
      var (text, none) = readDocument("# Title",
          markdown: true,
          allow: const MarkdownAllow()
              .withLook(MarkdownKind.heading1, const MarkdownLook(on: false)));
      expect(none, isEmpty);
      expect(text, "Title", reason: "stripped, not shown");
    });

    test("the looks survive being saved, and an old file still reads", () {
      var allow = const MarkdownAllow()
          .withLook(MarkdownKind.bold, const MarkdownLook(scale: 1.2))
          .withLook(MarkdownKind.link, const MarkdownLook(on: false));
      var back = MarkdownAllow.fromJson(allow.toJson());
      expect(back.lookFor(MarkdownKind.bold).scale, 1.2);
      expect(back.allows(MarkdownKind.link), isFalse);
      expect(back.allows(MarkdownKind.bold), isTrue);

      // Saved when this was six switches.
      var old = MarkdownAllow.fromJson({"b": false, "h2": false});
      expect(old.allows(MarkdownKind.bold), isFalse);
      expect(old.allows(MarkdownKind.heading2), isFalse);
      expect(old.allows(MarkdownKind.heading1), isTrue);
    });

    test("it remembers the words the document took over", () {
      // Turning the switch off has to give them back: left showing the
      // document's words, the switch would be off and the element would still
      // say what the document says, with nothing to say what was there.
      var typed = TextElement(
        const ElementBase(id: "t", width: 400, height: 200),
        text: "A headline of my own",
      );

      // What the settings do when the switch goes on, and then what the
      // reader of the library does to it.
      var reading = typed.copyWith(
          document: const TextDocumentRef(name: "Launch")
              .copyWith(wasText: typed.text));
      var read = reading.copyWith(text: "Whatever the document says");
      expect(read.text, "Whatever the document says");

      // And off again.
      var back = read.copyWith(
          text: read.document.wasText, document: const TextDocumentRef());
      expect(back.text, "A headline of my own");
      expect(back.document.on, isFalse);

      // It survives being saved, or a canvas reopened would have lost them.
      var reloaded = elementFromJson(read.toJson()) as TextElement;
      expect(reloaded.document.wasText, "A headline of my own");
    });

    test("the document's own runs are kept apart from the reader's", () {
      // They are rewritten from scratch every time the document is read, and
      // a part somebody added by hand has to survive that.
      var element = TextElement(
        const ElementBase(id: "t", width: 400, height: 200),
        text: "one two three",
        documentParts: const [TextPart(from: 1, to: 1, weight: 700)],
        parts: const [TextPart(from: 3, to: 3, italic: true)],
      );
      expect(element.drawnParts.length, 2);
      expect(element.drawnParts.first.weight, 700);
      expect(element.drawnParts.last.italic, isTrue,
          reason: "the reader's own parts come last, so they win");

      var back = elementFromJson(element.toJson()) as TextElement;
      expect(back.documentParts.single.weight, 700);
      expect(back.parts.single.italic, isTrue);
    });
  });
}
