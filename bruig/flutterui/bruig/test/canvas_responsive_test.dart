import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/model/responsive_layout.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_responsive_test.dart is one design laid out for several shapes.
//
// The bargain: the elements are one set -- the same words, the same colours,
// the same arrivals -- and each carries a place and a size per shape. The
// shape being looked at is live on the element, so nothing downstream had to
// change; the others are put away in its layouts. What these pin is that
// switching back and forth loses nothing, that the first visit to a shape is
// seeded rather than empty, and that the two halves of "one design" stay
// joined.

/// _Let is a small "and then" for reading a chain of document changes.
extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

void main() {
  CanvasSize sizeOf(CanvasRatio ratio) =>
      CanvasSize(ratio: ratio, width: 1000);

  CanvasDocument documentAt(CanvasRatio ratio) => CanvasDocument(
        size: sizeOf(ratio),
        elements: [
          ShapeElement(
              const ElementBase(id: "s", x: 100, y: 50, width: 400, height: 200)),
        ],
      );

  ShapeElement shapeIn(CanvasDocument d) =>
      d.elements.single as ShapeElement;

  group("switching shape", () {
    test("keeps the shape being left, and seeds the one being opened", () {
      // 1000x1250 (4:5) to 1000x562 (16:9). The page kept its width and lost
      // more than half its height, so the design is carried at that share --
      // it looks like itself, smaller, rather than filling a page it was not
      // laid out for.
      var tall = documentAt(CanvasRatio.feedAd);
      var wide = tall.forShape(sizeOf(CanvasRatio.wide));
      var by = sizeOf(CanvasRatio.wide).height /
          sizeOf(CanvasRatio.feedAd).height;

      expect(shapeIn(wide).width, closeTo(400 * by, 1));
      expect(shapeIn(wide).height, closeTo(200 * by, 1));
      // And where it sat: its middle was a fifth of the way down the tall
      // page, so it is a fifth of the way down the wide one.
      var middle = shapeIn(wide).y + shapeIn(wide).height / 2;
      expect(middle / sizeOf(CanvasRatio.wide).height,
          closeTo(150 / 1250, 0.02));
      expect(shapeIn(wide).base.layouts.keys, contains("feedAd"),
          reason: "and the 4:5 is put away, not thrown away");
    });

    test("and smaller still where even that does not fit", () {
      // A block hanging off two edges is worse than a small one.
      var doc = CanvasDocument(
        size: const CanvasSize(ratio: CanvasRatio.wide, width: 2000),
        elements: [
          ShapeElement(const ElementBase(
              id: "s", x: 0, y: 0, width: 1900, height: 1000)),
        ],
      );
      var tall = doc.forShape(
          const CanvasSize(ratio: CanvasRatio.feedAd, width: 1000));

      expect(shapeIn(tall).width, lessThanOrEqualTo(1000));
      expect(shapeIn(tall).height, lessThanOrEqualTo(1250));
    });

    test("and never larger, however much room the new page has", () {
      var doc = CanvasDocument(
        size: const CanvasSize(ratio: CanvasRatio.wide, width: 500),
        elements: [
          ShapeElement(const ElementBase(
              id: "s", x: 10, y: 10, width: 100, height: 50)),
        ],
      );
      var big = doc
          .forShape(const CanvasSize(ratio: CanvasRatio.feedAd, width: 2000));
      expect(shapeIn(big).width, 100, reason: "type nobody chose is not type");
      expect(shapeIn(big).height, 50);
    });

    test("what covers the page goes on covering it", () {
      // A photograph behind everything is the page rather than something on
      // it: scaled with the design it would leave a band of nothing down the
      // side of the new shape.
      var doc = CanvasDocument(
        size: sizeOf(CanvasRatio.feedAd),
        elements: [
          ShapeElement(ElementBase(
              id: "back",
              width: sizeOf(CanvasRatio.feedAd).width.toDouble(),
              height: sizeOf(CanvasRatio.feedAd).height.toDouble())),
          ShapeElement(const ElementBase(
              id: "card", x: 100, y: 900, width: 800, height: 300)),
        ],
      );

      var wide = doc.forShape(sizeOf(CanvasRatio.wide));
      var back = wide.elementById("back")!;
      expect(back.width, sizeOf(CanvasRatio.wide).width);
      expect(back.height, sizeOf(CanvasRatio.wide).height);
      expect(back.x, 0);
      expect(back.y, 0);

      // And the card is not shrunk to the page's ratio because the backdrop
      // is large: the backdrop is left out of the design's own block.
      var card = wide.elementById("card")!;
      var by = sizeOf(CanvasRatio.wide).height /
          sizeOf(CanvasRatio.feedAd).height;
      expect(card.width, closeTo(800 * by, 1),
          reason: "carried at the share the page changed by");
      // It sat near the bottom of the tall page and sits near the bottom of
      // the wide one.
      expect((card.y + card.height / 2) / sizeOf(CanvasRatio.wide).height,
          closeTo(1050 / 1250, 0.02));
    });

    test("and gives it back untouched on the way home", () {
      var tall = documentAt(CanvasRatio.feedAd);
      var wide = tall.forShape(sizeOf(CanvasRatio.wide));

      // Worked on, at 16:9.
      wide = wide.withElement(
          shapeIn(wide).withBase(x: 7, y: 9, width: 111, height: 22));

      var back = wide.forShape(sizeOf(CanvasRatio.feedAd));
      expect(shapeIn(back).x, 100, reason: "the 4:5 is as it was left");
      expect(shapeIn(back).width, 400);

      var again = back.forShape(sizeOf(CanvasRatio.wide));
      expect(shapeIn(again).x, 7, reason: "and so is the 16:9");
      expect(shapeIn(again).width, 111);
    });

    test("a third shape is seeded from the one being left, not the first", () {
      var doc = documentAt(CanvasRatio.feedAd)
          .forShape(sizeOf(CanvasRatio.wide));
      doc = doc.withElement(shapeIn(doc).withBase(x: 10, y: 10, width: 100));

      var square = doc.forShape(sizeOf(CanvasRatio.square));
      var by = canvasScale(sizeOf(CanvasRatio.wide), sizeOf(CanvasRatio.square));
      expect(shapeIn(square).width, closeTo(100 * by, 0.5));
      expect(shapeIn(square).base.layouts.keys,
          containsAll(["feedAd", "wide"]));
    });

    test("what an element *is* is one thing across every shape", () {
      // The whole bargain: layout per shape, everything else shared.
      var doc = CanvasDocument(
        size: sizeOf(CanvasRatio.feedAd),
        elements: [
          TextElement(const ElementBase(id: "t", width: 400, height: 100),
              text: "Spend or burn"),
        ],
      ).forShape(sizeOf(CanvasRatio.wide));

      var words = doc.elements.single as TextElement;
      doc = doc.withElement(words.copyWith(text: "Burn it"));
      var back = doc.forShape(sizeOf(CanvasRatio.feedAd));
      expect((back.elements.single as TextElement).text, "Burn it",
          reason: "fixed on one shape is fixed on all of them");
    });

    test("the master canvas is laid out with the rest", () {
      var doc = CanvasDocument(
        size: sizeOf(CanvasRatio.feedAd),
        scenes: [const CanvasScene(id: "a")],
        master: CanvasScene(id: "m", elements: [
          ShapeElement(const ElementBase(
              id: "logo", x: 40, y: 40, width: 200, height: 200)),
        ]),
        masterOn: true,
      );

      var wide = doc.forShape(sizeOf(CanvasRatio.wide));
      var logo = wide.master!.elements.single;
      expect(logo.base.layouts.keys, contains("feedAd"),
          reason: "put away like everything else");
      expect(logo.base.layouts["feedAd"]!.x, 40, reason: "as it was left");
    });

    test("a width change is not a shape change", () {
      // The width is the document's resolution rather than its shape, so
      // publishing wider must not re-lay-out anything.
      var doc = documentAt(CanvasRatio.wide);
      var bigger = doc.forShape(doc.size.copyWith(width: 2000));
      expect(shapeIn(bigger).width, 400);
      expect(shapeIn(bigger).base.layouts, isEmpty);
    });
  });

  group("the document's targets", () {
    test("are the shapes it has been designed at", () {
      var controller = CanvasController(documentAt(CanvasRatio.feedAd));
      addTearDown(controller.dispose);
      expect(controller.document.targets, isEmpty,
          reason: "one shape is not a responsive document");

      controller.setShape(sizeOf(CanvasRatio.wide));
      expect(controller.document.targets, ["feedAd", "wide"]);

      controller.setShape(sizeOf(CanvasRatio.square));
      expect(controller.document.targets, ["feedAd", "wide", "square"]);
    });

    test("and a new element is laid out for every one of them", () {
      var controller = CanvasController(documentAt(CanvasRatio.feedAd));
      addTearDown(controller.dispose);
      controller.setShape(sizeOf(CanvasRatio.wide));

      controller.addElement(ShapeElement(
          const ElementBase(id: "new", x: 0, y: 0, width: 200, height: 100)));

      var made = controller.document.elements.last;
      expect(made.base.layouts.keys, contains("feedAd"),
          reason: "added on the 16:9, it is on the 4:5 too");
      var by = canvasScale(sizeOf(CanvasRatio.wide), sizeOf(CanvasRatio.feedAd));
      expect(made.base.layouts["feedAd"]!.width, closeTo(200 * by, 0.5));
    });

    test("a shape can be given up, and its layouts go with it", () {
      var controller = CanvasController(documentAt(CanvasRatio.feedAd));
      addTearDown(controller.dispose);
      controller.setShape(sizeOf(CanvasRatio.wide));
      controller.setShape(sizeOf(CanvasRatio.square));

      controller.forgetShape("feedAd");
      expect(controller.document.targets, ["wide", "square"]);
      expect(shapeIn(controller.document).base.layouts.keys,
          isNot(contains("feedAd")));

      // The shape being looked at is not one that can be given up.
      controller.forgetShape("square");
      expect(controller.document.targets, ["wide", "square"]);
    });

    test("and a shape can be laid out again from another", () {
      // The same seeding a first visit gets -- the block measured, scaled by
      // how much the page changed, put where it sat. Anything else and the
      // way back from a mess would be a third arrangement nobody asked for.
      var controller = CanvasController(documentAt(CanvasRatio.feedAd));
      addTearDown(controller.dispose);
      controller.setShape(sizeOf(CanvasRatio.wide));
      var seeded = shapeIn(controller.document);

      // Dragged into a mess on the 16:9.
      controller.replaceElement(
          shapeIn(controller.document).withBase(x: 900, y: 900, width: 20));
      controller.resetShape("feedAd");

      var back = shapeIn(controller.document);
      expect(back.x, closeTo(seeded.x, 0.5));
      expect(back.y, closeTo(seeded.y, 0.5));
      expect(back.width, closeTo(seeded.width, 0.5));
      expect(back.height, closeTo(seeded.height, 0.5));
      expect(back.base.typeScale, closeTo(seeded.base.typeScale, 0.01));
    });
  });

  test("a custom shape is one shape, whatever it is set to", () {
    // Keyed by the numbers, typing a new aspect would leave the document
    // pointing at a shape nothing is laid out for.
    var custom = const CanvasSize(
        ratio: CanvasRatio.custom, width: 1000, customRatio: 1.5);
    expect(shapeKey(custom), shapeKey(custom.copyWith(customRatio: 0.8)));
    expect(shapeKey(sizeOf(CanvasRatio.wide)),
        shapeKey(sizeOf(CanvasRatio.wide).copyWith(width: 4000)),
        reason: "and the width is the resolution, not the shape");
  });

  group("the design inside the box", () {
    TextElement wordsIn(CanvasDocument d) => d.elements.single as TextElement;

    CanvasDocument headline(CanvasRatio ratio) => CanvasDocument(
          size: sizeOf(ratio),
          elements: [
            TextElement(
              const ElementBase(id: "t", x: 0, y: 0, width: 800, height: 200),
              text: "Spend or burn",
              textSpec: const TextSpec(fontSize: 60),
            ),
          ],
        );

    test("comes down with the box", () {
      // Scaled without this a headline keeps the size it had on the page
      // before and runs out of its frame.
      var doc = headline(CanvasRatio.feedAd);
      var wide = doc.forShape(sizeOf(CanvasRatio.wide));
      var by = sizeOf(CanvasRatio.wide).height /
          sizeOf(CanvasRatio.feedAd).height;

      expect(wordsIn(wide).textSpec.fontSize, closeTo(60 * by, 0.5));
      expect(wordsIn(wide).base.typeScale, closeTo(by, 0.01));
    });

    test("and is left alone where the page kept its shape", () {
      var doc = headline(CanvasRatio.feedAd);
      var same = doc.forShape(
          const CanvasSize(ratio: CanvasRatio.feedAd, width: 2000));
      expect(wordsIn(same).textSpec.fontSize, 60,
          reason: "a width is a resolution, not a shape");
    });

    test("and each shape keeps its own", () {
      var doc = headline(CanvasRatio.feedAd).forShape(sizeOf(CanvasRatio.wide));
      // Pulled down a notch on the wide one, the way the panel does it.
      var here = wordsIn(doc);
      doc = doc.withElement(here
          .scaledBy(0.5 / here.base.typeScale)
          .withBase(typeScale: 0.5) as TextElement);

      var back = doc.forShape(sizeOf(CanvasRatio.feedAd));
      expect(wordsIn(back).textSpec.fontSize, closeTo(60, 0.5),
          reason: "the 4:5 is as it was");
      expect(wordsIn(back).base.typeScale, 1);

      var again = back.forShape(sizeOf(CanvasRatio.wide));
      expect(again.elements.single.base.typeScale, 0.5);
      expect(wordsIn(again).textSpec.fontSize, closeTo(30, 0.5),
          reason: "and the 16:9 is as it was left");
    });
  });

  group("words", () {
    TextElement wordsIn(CanvasDocument d) => d.elements.single as TextElement;

    CanvasDocument headline(String text) => CanvasDocument(
          size: sizeOf(CanvasRatio.feedAd),
          elements: [
            TextElement(
              const ElementBase(id: "t", width: 800, height: 200),
              text: text,
            ),
          ],
        );

    test("are shared until a shape is given its own", () {
      var doc = headline("The long headline")
          .forShape(sizeOf(CanvasRatio.wide));
      expect(wordsIn(doc).text, "The long headline");

      // Typed on the 16:9, where this element has no words of its own: every
      // other shape is saying the same thing, so they all take it.
      doc = doc.withElement(wordsIn(doc).copyWith(text: "A better headline"));
      var back = doc.forShape(sizeOf(CanvasRatio.feedAd));
      expect(wordsIn(back).text, "A better headline");
    });

    test("and a shape with its own keeps them, and leaves the rest alone", () {
      var doc = headline("The long headline")
          .forShape(sizeOf(CanvasRatio.wide));

      // Own words on the 16:9.
      doc = doc.withElement(wordsIn(doc)
          .withBase(ownText: true)
          .let((e) => (e as TextElement).copyWith(text: "Short")));

      var tall = doc.forShape(sizeOf(CanvasRatio.feedAd));
      expect(wordsIn(tall).text, "The long headline",
          reason: "the shapes that share go on sharing");
      expect(wordsIn(tall).base.ownText, isFalse);

      var wide = tall.forShape(sizeOf(CanvasRatio.wide));
      expect(wordsIn(wide).text, "Short", reason: "and this one keeps its own");
      expect(wordsIn(wide).base.ownText, isTrue);

      // Editing the shared words does not touch the one with its own.
      var edited = wide
          .forShape(sizeOf(CanvasRatio.feedAd))
          .let((d) => d.withElement(wordsIn(d).copyWith(text: "Longer still")))
          .forShape(sizeOf(CanvasRatio.wide));
      expect(wordsIn(edited).text, "Short");
      expect(
          wordsIn(edited.forShape(sizeOf(CanvasRatio.feedAd))).text,
          "Longer still");
    });

    test("a new shape follows the shared words, not one shape's own", () {
      var doc = headline("The long headline")
          .forShape(sizeOf(CanvasRatio.wide));
      doc = doc.withElement(wordsIn(doc)
          .withBase(ownText: true)
          .let((e) => (e as TextElement).copyWith(text: "Short")));

      var square = doc.forShape(sizeOf(CanvasRatio.square));
      expect(wordsIn(square).text, "The long headline");
      expect(wordsIn(square).base.ownText, isFalse);
    });
  });

  test("a shape's short name tells the files apart", () {
    // What names one file per shape when a canvas is published at all of
    // them: "card-16x9.png" beside "card-4x5.png".
    expect(shapeTag("wide"), "16x9");
    expect(shapeTag("feedAd"), "4x5", reason: "the words after it are dropped");
    expect(shapeTag("square"), "1x1");
    expect(shapeTag("a4"), "A4");
  });

  group("resizing on one shape", () {
    TextElement wordsOf(CanvasDocument d) => d.elements.single as TextElement;

    CanvasDocument card(CanvasRatio ratio) => CanvasDocument(
          size: sizeOf(ratio),
          elements: [
            TextElement(
              const ElementBase(
                  id: "t", x: 100, y: 100, width: 400, height: 200),
              text: "Spend or burn",
              textSpec: const TextSpec(fontSize: 60),
            ),
          ],
        );

    test("does not reach the other shapes", () {
      // Scaling the design on one shape used to leave typeScale describing
      // the design as it was before, so going to another shape undid the
      // scaling by the wrong amount -- elements resized together came back
      // at different sizes. Reported with screenshots of a table and a badge
      // at two different scales.
      var doc = card(CanvasRatio.feedAd).forShape(sizeOf(CanvasRatio.wide));
      var onWide = wordsOf(doc);
      var seeded = onWide.textSpec.fontSize;

      // Scaled up on the 16:9, the way the stage does it: the design and the
      // number that says how much it has been scaled by, together.
      doc = doc.withElement(onWide
          .scaledBy(2)
          .withBase(typeScale: onWide.base.typeScale * 2) as TextElement);
      expect(wordsOf(doc).textSpec.fontSize, closeTo(seeded * 2, 0.5));

      // The 4:5 is exactly as it was left.
      var back = doc.forShape(sizeOf(CanvasRatio.feedAd));
      expect(wordsOf(back).textSpec.fontSize, closeTo(60, 0.5));
      expect(wordsOf(back).width, 400);

      // And the 16:9 still has what was done to it.
      var again = back.forShape(sizeOf(CanvasRatio.wide));
      expect(wordsOf(again).textSpec.fontSize, closeTo(seeded * 2, 0.5));
    });

    test("and two elements scaled together stay in step", () {
      var doc = CanvasDocument(
        size: sizeOf(CanvasRatio.feedAd),
        elements: [
          TextElement(
            const ElementBase(id: "a", width: 400, height: 200),
            text: "One",
            textSpec: const TextSpec(fontSize: 60),
          ),
          TextElement(
            const ElementBase(id: "b", x: 500, width: 200, height: 100),
            text: "Two",
            textSpec: const TextSpec(fontSize: 30),
          ),
        ],
      ).forShape(sizeOf(CanvasRatio.wide));

      // Both scaled by the same amount on the wide shape.
      for (var id in ["a", "b"]) {
        var e = doc.elementById(id)! as TextElement;
        doc = doc.withElement(
            e.scaledBy(1.5).withBase(typeScale: e.base.typeScale * 1.5)
                as TextElement);
      }
      var sizes = [
        for (var e in doc.elements) (e as TextElement).textSpec.fontSize,
      ];

      var back = doc
          .forShape(sizeOf(CanvasRatio.feedAd))
          .forShape(sizeOf(CanvasRatio.wide));
      expect([
        for (var e in back.elements) (e as TextElement).textSpec.fontSize,
      ], [
        closeTo(sizes[0], 0.5),
        closeTo(sizes[1], 0.5),
      ]);
    });
  });

  group("the file", () {
    test("carries the layouts and the targets through a save", () {
      var controller = CanvasController(documentAt(CanvasRatio.feedAd));
      addTearDown(controller.dispose);
      controller.setShape(sizeOf(CanvasRatio.wide));

      var back = CanvasDocument.decode(controller.document.encode())!;
      expect(back.targets, ["feedAd", "wide"]);
      var layouts = (back.elements.single).base.layouts;
      expect(layouts.keys, ["feedAd"]);
      expect(layouts["feedAd"]!.x, 100);
      expect(layouts["feedAd"]!.width, 400);
    });

    test("and a document saved before any of this reads as one shape", () {
      var old = CanvasDocument.decode(
          '{"elements":[{"kind":"shape","id":"s","x":1,"y":2,"w":3,"h":4}]}')!;
      expect(old.targets, isEmpty);
      expect(old.elements.single.base.layouts, isEmpty);
    });
  });
}
