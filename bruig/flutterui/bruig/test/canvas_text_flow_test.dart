import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/text_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_text_flow_test.dart is one piece of text running through a line of
// boxes.
//
// The words belong to the head of the chain; every box after it draws what
// would not fit in the one before. What is pinned here is that the split is
// clean -- no word drawn twice, none lost between two boxes -- and that a
// ring of boxes cannot be made.

const _lorem =
    "The quick brown fox jumps over the lazy dog while the rain in Spain "
    "falls mainly on the plain and nobody at all is watching it happen "
    "from the window of a small house beside a river in the middle of "
    "somewhere else entirely.";

TextElement _box(String id,
        {String text = "", String flowTo = "", double height = 40}) =>
    TextElement(
      ElementBase(id: id, x: 0, y: 0, width: 300, height: height),
      text: text,
      flowTo: flowTo,
      box: const BoxSpec(padding: 0),
      textSpec: const TextSpec(fontSize: 14, align: TextAlignSpec.left),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const spec = TextSpec(fontSize: 14, align: TextAlignSpec.left);
  const room = Rect.fromLTWH(0, 0, 300, 40);

  group("a box on its own", () {
    test("says when it is hiding words", () {
      // Which is what turns the overflow grip red. Hidden text with nothing
      // saying it is hidden is what people lose work to.
      var small = _box("a", text: _lorem);
      var flow = flowFor(small, CanvasDocument(elements: [small]), room, spec);
      expect(flow.text, _lorem, reason: "it still draws what it has");
      expect(flow.overflows, isTrue);
      expect(flow.receiving, isFalse);

      var short = _box("a", text: "Two words");
      expect(
          flowFor(short, CanvasDocument(elements: [short]), room, spec)
              .overflows,
          isFalse);
    });
  });

  group("a chain of boxes", () {
    CanvasDocument twoBoxes({double first = 40}) {
      var a = _box("a", text: _lorem, flowTo: "b", height: first);
      var b = _box("b", text: "This is not shown");
      return CanvasDocument(elements: [a, b]);
    }

    test("the second box carries on where the first stopped", () {
      var doc = twoBoxes();
      var a = doc.elementById("a") as TextElement;
      var b = doc.elementById("b") as TextElement;

      var first = flowFor(a, doc, room, spec);
      var second = flowFor(b, doc, room, spec);

      expect(first.overflows, isTrue);
      expect(second.receiving, isTrue);
      expect(second.text, isNot(contains("This is not shown")),
          reason: "a box being flowed into does not draw its own words");

      // Nothing lost and nothing drawn twice: the two pieces are the whole
      // text, in order.
      expect(_lorem.startsWith(first.text.trimRight()), isTrue);
      expect(_lorem.contains(second.text.trimRight()), isTrue);
      var shown = first.text.trimRight() + " " + second.text.trimLeft();
      expect(shown.replaceAll(RegExp(r"\s+"), " ").trim(),
          startsWith(_lorem.substring(0, 60)));
    });

    test("the head decides whether a box starts on a blank line", () {
      // A chain is one paragraph flowing through several boxes: how it is
      // broken is a fact about the words, not about each box it lands in, so
      // two boxes cannot disagree about it. And the setting is only on the
      // head, so there is nowhere for them to.
      // One line in the first box, so the break lands exactly on the empty
      // line between the two paragraphs.
      var paragraphs = "First\n\nSecond paragraph, and more of it";
      TextFlow second({required bool tidy}) {
        var a = _box("a", text: paragraphs, flowTo: "b", height: 18)
            .copyWith(columns: TextColumns(noBlankStart: tidy));
        var b = _box("b");
        var doc = CanvasDocument(elements: [a, b]);
        return flowFor(b, doc, room, spec);
      }

      var loose = second(tidy: false);
      var tidied = second(tidy: true);
      expect(loose.tidyStart, isFalse);
      expect(tidied.tidyStart, isTrue,
          reason: "the head's answer, on the box that is receiving");
      expect(loose.text.startsWith("\n"), isTrue,
          reason: "the break landed on the blank line: "
              "${loose.text.substring(0, 12).replaceAll("\n", "|")}");
      expect(tidied.text.startsWith("\n"), isFalse,
          reason: "which is passed over rather than drawn");
    });

    test("and a taller first box keeps more of it", () {
      var short = twoBoxes(first: 40);
      var tall = twoBoxes(first: 120);
      var fromShort = flowFor(short.elementById("a") as TextElement, short,
          const Rect.fromLTWH(0, 0, 300, 40), spec);
      var fromTall = flowFor(tall.elementById("a") as TextElement, tall,
          const Rect.fromLTWH(0, 0, 300, 120), spec);

      var leftShort =
          flowFor(short.elementById("b") as TextElement, short, room, spec);
      var leftTall =
          flowFor(tall.elementById("b") as TextElement, tall, room, spec);

      expect(fromShort.overflows, isTrue);
      expect(fromTall.overflows, isTrue);
      expect(leftTall.text.length, lessThan(leftShort.text.length),
          reason: "the taller box passed on less: "
              "${leftShort.text.length} then ${leftTall.text.length}");
    });

    test("three boxes carry on from each other in order", () {
      var a = _box("a", text: _lorem, flowTo: "b");
      var b = _box("b", flowTo: "c");
      var c = _box("c");
      var doc = CanvasDocument(elements: [a, b, c]);

      var one = flowFor(a, doc, room, spec).text;
      var two = flowFor(b, doc, room, spec).text;
      var three = flowFor(c, doc, room, spec).text;

      expect(two, isNot(one));
      expect(three, isNot(two));
      expect(
          _lorem.indexOf(two.trim()), greaterThan(_lorem.indexOf(one.trim())));
      expect(_lorem.indexOf(three.trim()),
          greaterThan(_lorem.indexOf(two.trim())));
    });

    test("a ring of boxes is refused", () {
      // A ring has no first box, so there is nowhere to start reading.
      var a = _box("a", text: _lorem, flowTo: "b");
      var b = _box("b", flowTo: "c");
      var c = _box("c");
      var doc = CanvasDocument(elements: [a, b, c]);

      expect(wouldLoop(c, "a", doc), isTrue, reason: "back to the head");
      expect(wouldLoop(c, "b", doc), isTrue, reason: "back into the middle");
      expect(wouldLoop(a, "a", doc), isTrue, reason: "into itself");
      expect(wouldLoop(c, "c", doc), isTrue);

      // And a link that does not close a ring is allowed.
      var d = _box("d");
      var wider = CanvasDocument(elements: [a, b, c, d]);
      expect(wouldLoop(c, "d", wider), isFalse);
    });

    test("a document that somehow holds a ring still draws", () {
      // Written by an older build, or edited by hand. The painter must come
      // back rather than walking round for ever.
      var a = _box("a", text: _lorem, flowTo: "b");
      var b = _box("b", flowTo: "a");
      var doc = CanvasDocument(elements: [a, b]);
      expect(() => flowFor(a, doc, room, spec), returnsNormally);
      expect(() => flowFor(b, doc, room, spec), returnsNormally);
    });

    test("the link survives being saved", () {
      var back = elementFromJson(_box("a", text: "x", flowTo: "b").toJson())
          as TextElement;
      expect(back.flowTo, "b");
      expect(_box("a").toJson().containsKey("flowTo"), isFalse);
    });
  });
}
