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
      // 1000x1250 (4:5) to 1000x562 (16:9): the smaller ratio is the height,
      // so the design comes down by 562/1250.
      var tall = documentAt(CanvasRatio.feedAd);
      var wide = tall.forShape(sizeOf(CanvasRatio.wide));

      var by = sizeOf(CanvasRatio.wide).height / sizeOf(CanvasRatio.feedAd).height;
      expect(shapeIn(wide).width, closeTo(400 * by, 0.5),
          reason: "seeded by scaling what was left behind");
      expect(shapeIn(wide).x, closeTo(100 * by, 0.5));
      expect(shapeIn(wide).base.layouts.keys, contains("feedAd"),
          reason: "and the 4:5 is put away, not thrown away");
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
      var by = canvasScale(sizeOf(CanvasRatio.feedAd), sizeOf(CanvasRatio.wide));
      expect(logo.width, closeTo(200 * by, 0.5));
      expect(logo.base.layouts.keys, contains("feedAd"));
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
      var controller = CanvasController(documentAt(CanvasRatio.feedAd));
      addTearDown(controller.dispose);
      controller.setShape(sizeOf(CanvasRatio.wide));

      // Dragged into a mess on the 16:9.
      controller.replaceElement(
          shapeIn(controller.document).withBase(x: 900, y: 900, width: 20));
      controller.resetShape("feedAd");

      var by = canvasScale(sizeOf(CanvasRatio.feedAd), sizeOf(CanvasRatio.wide));
      expect(shapeIn(controller.document).x, closeTo(100 * by, 0.5));
      expect(shapeIn(controller.document).width, closeTo(400 * by, 0.5));
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

    test("comes down with the box when a shape is seeded", () {
      // Seeded without this, a headline keeps the size it had on the larger
      // page and runs out of the frame -- which is the whole complaint
      // presets had, arriving here by another door.
      var doc = headline(CanvasRatio.feedAd);
      var wide = doc.forShape(sizeOf(CanvasRatio.wide));
      var by = canvasScale(sizeOf(CanvasRatio.feedAd), sizeOf(CanvasRatio.wide));

      expect(wordsIn(wide).textSpec.fontSize, closeTo(60 * by, 0.5));
      expect(wordsIn(wide).base.typeScale, closeTo(by, 0.001));
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
