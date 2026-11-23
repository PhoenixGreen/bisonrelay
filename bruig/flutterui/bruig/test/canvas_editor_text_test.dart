import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'support/canvas_app.dart';
import 'support/canvas_sidebar_host.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/text_document.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/canvas_panel_helpers.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart';

// canvas_editor_text_test.dart is a text element's settings.
//
// Built as widgets and used, rather than tested through the controller: a
// control drawn but wired to nothing passes every model test there is. So
// these tap the thing and look at the document.

void main() {
  // What the controls do, not where they are folded: every section open.
  setUpAll(() => CanvasSection.openAll = true);
  tearDownAll(() => CanvasSection.openAll = false);

  Future<void> pump(WidgetTester tester, Widget child,
          {CanvasPreferences? prefs}) =>
      pumpCanvasApp(tester, child, size: const Size(1400, 900), prefs: prefs);

  group("the text settings", () {
    /// panel builds a text element's settings the way the Layers sidebar does.
    Future<CanvasController> panel(WidgetTester tester,
        {TextElement? element}) async {
      var text = element ??
          TextElement(
            ElementBase(id: newElementId(), width: 400, height: 200),
            text: "You come across an idea",
          );
      var controller =
          CanvasController(const CanvasDocument().addElement(text));
      addTearDown(controller.dispose);
      controller.selectOnly(text.id);
      await pump(tester, designSidebar(controller));
      await tester.pumpAndSettle();
      return controller;
    }

    TextElement textIn(CanvasController c) =>
        c.document.elements.whereType<TextElement>().single;

    /// pickLayer picks the layer [id] -- a piece's id, or "body" for the
    /// element's own words -- in the Layers over the sections.
    Future<void> pickLayer(WidgetTester tester, String id) async {
      var layer = find.byKey(ValueKey("textLayer-$id"));
      await tester.ensureVisible(layer);
      await tester.pumpAndSettle();
      await tester.tap(layer);
      await tester.pumpAndSettle();
    }

    /// addLayer adds a piece from the Layers' Add: "text" or "picture".
    Future<void> addTextLayer(WidgetTester tester, String what) async {
      if (find.byKey(const ValueKey("textAddTiles")).evaluate().isEmpty) {
        var add = find.byKey(const ValueKey("textLayersAdd"));
        await tester.ensureVisible(add);
        await tester.pumpAndSettle();
        await tester.tap(add);
        await tester.pumpAndSettle();
      }
      var tile = find.byKey(ValueKey("textLayersAdd-$what"));
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
    }

    /// inType is [f] among the type settings: the quick strip's face, size
    /// and colour, and the rest in the Look.
    Finder inType(Finder f) => find.descendant(
        of: find.byKey(const ValueKey("elementSections")), matching: f);

    testWidgets("are sections, in the order the work happens", (tester) async {
      // Where it is, how it is set, its box, the line it follows, which
      // words are different, how it arrives -- and the designs saved of its
      // kind, as every element's panel ends. No Words section: where the
      // words come from is a card at the foot of Position, and the named
      // styles a card under the presets.
      await panel(tester);
      var found = [
        for (var element in find.byType(CanvasSection).evaluate())
          (
            tester.getTopLeft(find.byWidget(element.widget)).dy,
            (element.widget as CanvasSection).title,
          ),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      expect([
        for (var (_, title) in found) title
      ], [
        "Content",
        "Look",
        "Layout",
        "Motion",
        "More",
      ]);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey("elementSection-content")),
              matching: find.byKey(const ValueKey("textWords"))),
          findsOneWidget);
      for (var key in ["textFromDocument", "textWrap"]) {
        expect(
            find.descendant(
                of: find.byKey(const ValueKey("textWords")),
                matching: find.byKey(ValueKey(key))),
            findsOneWidget,
            reason: key);
      }
      expect(
          find.descendant(
              of: find.byKey(const ValueKey("elementSection-more")),
              matching: find.byKey(const ValueKey("textStyleSave"))),
          findsOneWidget);
      expect(find.byKey(const ValueKey("elementSection-words")), findsNothing);
    });

    testWidgets("the colour settings are in the type card, not behind a button",
        (tester) async {
      // In a card, everything at once: the Type section already folds, and
      // a button inside it was a setting found twice over.
      await panel(tester);
      // The words' outline, shadow and glow are looks in the Chain now, kept
      // in one place (text_looks.dart): not in the type card as well.
      expect(find.text("Outline"), findsNothing);
      expect(byTip("Spacing, alignment and case"), findsNothing);
      expect(find.byType(CanvasColorButton), findsWidgets);
    });

    testWidgets("but a shape's label keeps a colour row of its own",
        (tester) async {
      var shape = ShapeElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "Labelled",
      );
      var controller =
          CanvasController(const CanvasDocument().addElement(shape));
      addTearDown(controller.dispose);
      controller.selectOnly(shape.id);
      await pump(tester, designSidebar(controller));
      await tester.pumpAndSettle();

      expect(find.text("COLOUR"), findsWidgets,
          reason: "one thing to colour, and the swatch is worth seeing");
    });

    testWidgets("a piece is added, placed and taken away from the panel",
        (tester) async {
      // From the Layers: Add, then Text. The new piece is picked, so the
      // panel is its settings, where it sits among them.
      var controller = await panel(tester);
      expect(textIn(controller).items, isEmpty);
      expect(find.byKey(const ValueKey("textLayer-body")), findsOneWidget,
          reason: "the element's own words are the first layer");

      await addTextLayer(tester, "text");
      expect(textIn(controller).items.length, 1);
      var first = textIn(controller).items.first;
      expect(first.text, "Text",
          reason: "something to see and to click on the canvas");
      expect(controller.textLayer(textIn(controller))?.id, first.id,
          reason: "the piece added is picked");

      // Its place, as a picture of the box: the middle of its right side.
      var slot = find.descendant(
          of: find.byKey(const ValueKey("textItemSlot0")),
          matching: find.byKey(const ValueKey("slot-middleRight")));
      await tester.ensureVisible(slot);
      await tester.pumpAndSettle();
      await tester.tap(slot);
      await tester.pumpAndSettle();
      expect(textIn(controller).items.first.slot, TextSlot.middleRight);

      // A second one goes to a free slot rather than on top of the first.
      await addTextLayer(tester, "text");
      expect(textIn(controller).items.length, 2);
      expect(textIn(controller).items.last.slot,
          isNot(textIn(controller).items.first.slot));

      // The first picked again and deleted from the Layers' heading.
      await pickLayer(tester, first.id);
      var delete = find.byKey(const ValueKey("textLayersDelete"));
      await tester.ensureVisible(delete);
      await tester.pumpAndSettle();
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(textIn(controller).items.length, 1);
      expect(textIn(controller).items.first.slot, isNot(TextSlot.middleRight),
          reason: "the one that was moved is the one that went");
      expect(controller.textLayer(textIn(controller)), isNull,
          reason: "back to the element's own words");
      expect(tester.takeException(), isNull);
    });

    testWidgets("and each piece's settings are the same control the words get",
        (tester) async {
      // Face, size, weight and the rest -- not a second set of controls that
      // happen to do the same things -- shown in Type when the piece is
      // picked in the Layers.
      var element = TextElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "Spend or burn",
        items: const [
          TextItem(id: "n", text: "01", slot: TextSlot.topLeft),
        ],
      );
      var controller = await panel(tester, element: element);
      await pickLayer(tester, "n");
      expect(inType(find.byType(CanvasColorButton)), findsWidgets,
          reason: "the piece has its own colour");

      // And changing it writes to the piece, not to the element.
      var size = inType(find.byType(CanvasNumberField));
      await tester.ensureVisible(size.first);
      await tester.pumpAndSettle();
      await enterValue(tester, size.first, "11");
      await tester.pumpAndSettle();
      expect(textIn(controller).items.first.spec.fontSize, 11);
      expect(textIn(controller).textSpec.fontSize, isNot(11));
    });

    testWidgets("picking a layer shows that layer's settings", (tester) async {
      // The element's own words have a slot, marks and parts; a piece of
      // writing has a place in the box; a picture has a picture's settings
      // and no type at all.
      var element = TextElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "Spend or burn",
        items: const [
          TextItem(id: "n", text: "01", slot: TextSlot.topLeft),
          TextItem(id: "p", icon: TextIcon(), slot: TextSlot.bottomRight),
        ],
      );
      var controller = await panel(tester, element: element);
      expect(find.byKey(const ValueKey("textBodySlot")), findsOneWidget);
      expect(find.byKey(const ValueKey("expander-textParts")), findsOneWidget);

      await pickLayer(tester, "n");
      expect(find.byKey(const ValueKey("textBodySlot")), findsNothing);
      expect(find.byKey(const ValueKey("textItemSlot0")), findsOneWidget);
      expect(find.byKey(const ValueKey("expander-textParts")), findsNothing,
          reason: "a piece has no parts of its own");

      await pickLayer(tester, "p");
      expect(find.byKey(const ValueKey("typeFont")), findsNothing,
          reason: "a picture has no type");
      expect(find.byKey(const ValueKey("textItemPicture1")), findsOneWidget);

      await pickLayer(tester, "body");
      expect(controller.textLayer(textIn(controller)), isNull);
      expect(find.byKey(const ValueKey("textBodySlot")), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets("a piece can be hidden and locked from its layer",
        (tester) async {
      var element = TextElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "Spend or burn",
        items: const [
          TextItem(id: "n", text: "01", slot: TextSlot.topLeft),
        ],
      );
      var controller = await panel(tester, element: element);
      if (find.byKey(const ValueKey("textLayersRows")).evaluate().isEmpty) {
        await tester.tap(find.byKey(const ValueKey("textLayersOpen")));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey("textLayerShow-n")));
      await tester.pumpAndSettle();
      expect(textIn(controller).items.single.hidden, isTrue);
      await tester.tap(find.byKey(const ValueKey("textLayerLock-n")));
      await tester.pumpAndSettle();
      expect(textIn(controller).items.single.locked, isTrue);
      // Saved and read back as they were.
      var back = TextItem.fromJson(textIn(controller).items.single.toJson());
      expect((back.hidden, back.locked), (true, true));
      // The element's own words have neither: they are the element.
      expect(find.byKey(const ValueKey("textLayerShow-body")), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets("a piece is offered where it sits, not an alignment",
        (tester) async {
      // Reported: the alignment dropdowns were there on a piece and did
      // nothing. They could not: a piece is held to the corner of the box its
      // slot names, so its place is the slot's to decide. A control that does
      // nothing is worse than no control.
      var element = TextElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "Spend or burn",
        items: const [
          TextItem(id: "n", text: "01", slot: TextSlot.topLeft),
        ],
      );
      await panel(tester, element: element);
      await pickLayer(tester, "n");

      var quick = find.byKey(const ValueKey("quickStrip"));
      expect(
          find.descendant(of: quick, matching: find.byType(CanvasSlotPicker)),
          findsOneWidget);
      expect(find.byKey(const ValueKey("typeAlign")), findsNothing);
      expect(find.byKey(const ValueKey("typeVertical")), findsNothing);
    });

    testWidgets("the element's own words can be given a slot too",
        (tester) async {
      // Which is what lets a title and the paragraph under it stack instead
      // of being drawn over each other.
      var controller = await panel(tester);
      expect(textIn(controller).slot, isNull, reason: "the box, by default");

      var where = find.byKey(const ValueKey("textBodySlot"));
      if (where.evaluate().isEmpty) {
        var button = byTip("Spacing, alignment and case");
        await tester.ensureVisible(button.first);
        await tester.pumpAndSettle();
        await tester.tap(button.first);
        await tester.pumpAndSettle();
      }

      await tester.ensureVisible(where);
      await tester.pumpAndSettle();
      await tester.tap(where);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Top left").last);
      await tester.pumpAndSettle();
      expect(textIn(controller).slot, TextSlot.topLeft);

      await tester.ensureVisible(where);
      await tester.pumpAndSettle();
      await tester.tap(where);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Fills the box").last);
      await tester.pumpAndSettle();
      expect(textIn(controller).slot, isNull);
    });

    testWidgets("a piece keeps two numbers for where it sits, side by side",
        (tester) async {
      // Gap down the box and Left/right across it. Both go either way from
      // zero, so four of them -- one per side -- was four fields saying what
      // two say, and a switch to hide them was a switch over nothing.
      var element = TextElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "Spend or burn",
        items: const [
          TextItem(id: "n", text: "01", slot: TextSlot.topLeft, gap: 8),
        ],
      );
      var controller = await panel(tester, element: element);
      await pickLayer(tester, "n");

      var gap = find.byKey(const ValueKey("textItemGap0"));
      var side = find.byKey(const ValueKey("textItemSide0"));
      expect(gap, findsOneWidget);
      expect(side, findsOneWidget, reason: "not behind a switch of its own");
      expect(tester.getRect(side).top, closeTo(tester.getRect(gap).top, 0.5),
          reason: "side by side");

      await tester.ensureVisible(side);
      await tester.pumpAndSettle();
      await enterValue(tester, side, "14");
      await tester.pumpAndSettle();
      expect(textIn(controller).items.first.side, 14);
    });

    testWidgets("the layers start with the element's own words",
        (tester) async {
      // In the order the pieces stack, the element's own words first and
      // held there; the pieces after them in the order they were added.
      var element = TextElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "Spend or burn",
        items: const [
          TextItem(id: "a", text: "01", slot: TextSlot.topLeft),
          TextItem(id: "b", text: "02", slot: TextSlot.topLeft),
        ],
      );
      var controller = await panel(tester, element: element);
      double left(String id) =>
          tester.getRect(find.byKey(ValueKey("textLayer-$id"))).left;
      double top(String id) =>
          tester.getRect(find.byKey(ValueKey("textLayer-$id"))).top;
      if (find.byKey(const ValueKey("textLayersRows")).evaluate().isEmpty) {
        expect(left("body"), lessThan(left("a")));
        expect(left("a"), lessThan(left("b")));
        await tester.tap(find.byKey(const ValueKey("textLayersOpen")));
        await tester.pumpAndSettle();
      }
      expect(top("body"), lessThan(top("a")));
      expect(top("a"), lessThan(top("b")));

      // Moved down from its row, the first piece stacks after the second.
      await pickLayer(tester, "a");
      await tester.tap(find.byKey(const ValueKey("textLayerDown-a")));
      await tester.pumpAndSettle();
      expect([for (var i in textIn(controller).items) i.id], ["b", "a"]);
      expect(tester.takeException(), isNull);
    });

    testWidgets("the colour is in the quick strip and the switches in Look",
        (tester) async {
      // What colour the words are is the first thing anybody changes about
      // them and the last thing that should be behind a button: it is in the
      // quick strip over the sections, with the face and the size. Italic is
      // set once, with the rest of the letters, in Look.
      await panel(tester);
      var quick = find.byKey(const ValueKey("quickStrip"));
      expect(
          find.descendant(
              of: quick, matching: find.byKey(const ValueKey("typeColour"))),
          findsOneWidget);
      expect(
          find.descendant(
              of: quick, matching: find.byKey(const ValueKey("typeFont"))),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey("elementSection-look")),
              matching: find.byKey(const ValueKey("typeItalic"))),
          findsOneWidget);
    });

    testWidgets("and there is one underline, not two", (tester) async {
      // The face's own underline and a drawn one under the words are two
      // switches called Underline on one panel. The one that can do more --
      // a colour, a width, a distance under the letters -- is the one kept.
      await panel(tester);
      var type = find.byKey(const ValueKey("elementSection-look"));
      expect(
          find.descendant(
              of: type, matching: find.byIcon(Icons.format_underlined)),
          findsNothing);
      expect(find.descendant(of: type, matching: find.text("Underline")),
          findsOneWidget);
    });

    testWidgets("a part is there to fill in before anything is added",
        (tester) async {
      // Pressing a plus to be shown the controls, and only then being able to
      // use them, is a step that exists because the list is empty -- which is
      // not a thing the reader did. The row is there in its own default
      // state, and setting something on it is what adds it.
      var controller = await panel(tester);
      expect(textIn(controller).parts, isEmpty);

      // Under More, in a fold of its own.
      await openFold(tester, "textParts",
          shows: find.byKey(const ValueKey("partBold0")));

      var bold = find.byKey(const ValueKey("partBold0"));
      expect(bold, findsOneWidget, reason: "a row, before the plus was used");
      expect(textIn(controller).parts, isEmpty,
          reason: "and nothing written until it is");

      await tester.ensureVisible(bold);
      await tester.pumpAndSettle();
      await tester.tap(bold);
      await tester.pumpAndSettle();
      expect(textIn(controller).parts.length, 1);
      var part = textIn(controller).parts.first;
      expect(part.weight, isNotNull);
      expect(
          part.weight! >= 600, isNot(textIn(controller).textSpec.weight >= 600),
          reason: "the switch turned, whichever way it was pointing");
    });

    testWidgets("and its switches are buttons, so the row is one line",
        (tester) async {
      // Bold, italic, an outline and the two marks: five words in a column is
      // a column, and five buttons is a line.
      var element = TextElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "Spend or burn",
        parts: const [TextPart(from: 1, to: 2)],
      );
      await panel(tester, element: element);

      // Under More, in a fold of its own.
      await openFold(tester, "textParts",
          shows: find.byKey(const ValueKey("partBold0")));

      var tops = <double>[];
      for (var key in [
        "partBold0",
        "partItalic0",
        "partOutline0",
        "part0HighlightOn",
        "part0UnderlineOn",
      ]) {
        var button = find.byKey(ValueKey(key));
        expect(button, findsOneWidget, reason: key);
        tops.add(tester.getRect(button).top);
      }
      for (var top in tops) {
        expect(top, closeTo(tops.first, 0.5),
            reason: "all five on one line: $tops");
      }
    });

    testWidgets("a part that arrives as a highlight shows its mark's look",
        (tester) async {
      // The band's colour, its room round the words and its corners: what a
      // drawn highlight is made of, and nowhere else to set them.
      var element = TextElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "Spend or burn",
        parts: const [
          TextPart(
              from: 1,
              to: 2,
              animation:
                  TextPartAnimation(preset: TextAnimationPreset.highlight)),
        ],
      );
      await panel(tester, element: element);
      await openFold(tester, "textParts",
          shows: find.byKey(const ValueKey("partBold0")));
      expect(find.byKey(const ValueKey("textMarkRadius")), findsOneWidget);
      expect(find.byKey(const ValueKey("textDrawStart")), findsOneWidget);
    });

    testWidgets("a face a received canvas names is shown, not a blank",
        (tester) async {
      // As the chart and table panels do: the face is offered as it is,
      // first, so the dropdown says what the words are set in.
      var element = TextElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "Spend or burn",
        textSpec: const TextSpec(fontFamily: "Comic Sans MS"),
      );
      await panel(tester, element: element);
      var font = find.byKey(const ValueKey("typeFont")).first;
      expect(find.descendant(of: font, matching: find.text("Comic Sans MS")),
          findsOneWidget);
    });

    testWidgets("a layer's picture is in the weight the canvas draws",
        (tester) async {
      // A weight typed between the hundreds: the canvas draws the hundred
      // below, so the layer's "Aa" must too, not the nearest.
      var element = TextElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "Spend or burn",
        textSpec: const TextSpec(weight: 650),
      );
      await panel(tester, element: element);
      var face = find.descendant(
          of: find.byKey(const ValueKey("textLayersList")),
          matching: find.text("Aa"));
      expect(face, findsWidgets);
      expect(tester.widget<Text>(face.first).style!.fontWeight,
          const TextSpec(weight: 650).fontWeight);
      expect(const TextSpec(weight: 650).fontWeight, FontWeight.w600);
    });

    testWidgets("a style changed later leaves a size typed by hand alone",
        (tester) async {
      // The size typed here is this text's own. The text keeps the style's
      // name, so "Change the style to this text's type" is still there to
      // push the edit into the style; until then the style leaves it be.
      var text = TextElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "A heading",
        style: "Heading",
        textSpec: const TextSpec(fontSize: 30),
      );
      var controller = CanvasController(CanvasDocument(
          textStyles: const [NamedTextStyle("Heading", TextSpec(fontSize: 30))],
          elements: [text]));
      addTearDown(controller.dispose);
      controller.selectOnly(text.id);
      await pump(tester, designSidebar(controller));
      await tester.pumpAndSettle();
      var size = find.byKey(const ValueKey("typeSize")).first;
      await tester.ensureVisible(size);
      await tester.pumpAndSettle();
      await enterValue(tester, size, "50");
      await tester.pumpAndSettle();
      expect(textIn(controller).textSpec.fontSize, 50);

      controller.updateTextStyle(
          "Heading", const TextSpec(fontSize: 30, color: Color(0xFFFF0000)));
      expect(textIn(controller).textSpec.fontSize, 50);
      expect(textIn(controller).textSpec.color, const Color(0xFFFFFFFF),
          reason: "edited by hand, so the style leaves all of it alone");
      expect(textIn(controller).style, "Heading");
      expect(find.byKey(const ValueKey("textStyleUpdate")), findsOneWidget,
          reason: "still linked, so its type can still be made the style's");
    });

    testWidgets(
        "a style updated from one text restyles those still on it, not one "
        "edited by hand", (tester) async {
      const heading = TextSpec(fontSize: 30);
      TextElement text(String id, TextSpec spec) =>
          TextElement(ElementBase(id: id, width: 400, height: 200),
              text: id, style: "Heading", textSpec: spec);
      var controller = CanvasController(CanvasDocument(textStyles: const [
        NamedTextStyle("Heading", heading)
      ], elements: [
        text("edited", heading.copyWith(fontSize: 50)),
        text("follows", heading),
        text("source", heading),
      ]));
      addTearDown(controller.dispose);
      // The source's colour changed by hand, then pushed into the style
      // with the panel's Update.
      var source = controller.document.elementById("source") as TextElement;
      controller.replaceElement(source.copyWith(
          textSpec: heading.copyWith(color: const Color(0xFFFF0000))));
      controller.selectOnly("source");
      await pump(tester, designSidebar(controller));
      await tester.pumpAndSettle();
      var update = find.byKey(const ValueKey("textStyleUpdate"));
      await tester.ensureVisible(update);
      await tester.pumpAndSettle();
      await tester.tap(update);
      await tester.pumpAndSettle();

      TextSpec specOf(String id) =>
          (controller.document.elementById(id) as TextElement).textSpec;
      expect(controller.textStyles.single.spec.color, const Color(0xFFFF0000));
      expect(specOf("source").color, const Color(0xFFFF0000));
      expect(specOf("follows").color, const Color(0xFFFF0000),
          reason: "the same type as the style was, so it follows");
      expect(specOf("edited").color, const Color(0xFFFFFFFF),
          reason: "its own size makes it its own: left alone");
      expect(specOf("edited").fontSize, 50);
      expect((controller.document.elementById("edited") as TextElement).style,
          "Heading");
    });

    testWidgets(
        "a picture's own controls sit with the choice that asked for it",
        (tester) async {
      // Choosing a picture is the next thing anybody does after saying "a
      // picture", so the two buttons are on the line with Painted with -- not
      // two lines down under the outline. And the outline starts a line of
      // its own either way, so the first line is always "what are these
      // letters painted with".
      var controller = await panel(tester);
      var own = find.ancestor(
          of: find.byWidgetPredicate(
              (w) => w is CanvasDropdown<String> && w.label == "Font"),
          matching: find.byType(CanvasMoreGroup));
      var button = find.descendant(of: own, matching: find.byIcon(Icons.tune));
      if (button.evaluate().isNotEmpty) {
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      var kind = find.byKey(const ValueKey("textFillKind"));
      await tester.ensureVisible(kind);
      await tester.pumpAndSettle();
      await tester.tap(kind);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Picture").last);
      await tester.pumpAndSettle();
      expect(textIn(controller).textSpec.fill.kind, TextFillKind.image);

      var choose = find.byKey(const ValueKey("textFillPicture"));
      expect(choose, findsOneWidget);
      expect(tester.getRect(choose).top, closeTo(tester.getRect(kind).top, 0.5),
          reason: "on the line with the choice that asked for it");
    });

    testWidgets("a picture showing through gets a picture element's Look",
        (tester) async {
      // The same two settings, under the same two names and in the same
      // order: Filter and Overlay. A Look that was named differently and had
      // half of it missing was a second answer to a question that has one.
      var element = TextElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "Spend or burn",
        textSpec: const TextSpec(
            fill: TextFill(kind: TextFillKind.image, assetId: "abcdefghij12")),
      );
      var controller = await panel(tester, element: element);
      var own = find.ancestor(
          of: find.byWidgetPredicate(
              (w) => w is CanvasDropdown<String> && w.label == "Font"),
          matching: find.byType(CanvasMoreGroup));
      var button = find.descendant(of: own, matching: find.byIcon(Icons.tune));
      if (button.evaluate().isNotEmpty) {
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      var filter = find.byKey(const ValueKey("textFillLook"));
      var overlay = find.byKey(const ValueKey("textFillBlend"));
      expect(tester.widget<CanvasDropdown<ImageFilterPreset>>(filter).label,
          "Filter");
      expect(tester.widget<CanvasDropdown<OverlayBlend>>(overlay).label,
          "Overlay");
      // And no colour to choose until there is something to lay it with.
      expect(find.byKey(const ValueKey("textFillOverlay")), findsNothing);

      await tester.ensureVisible(overlay);
      await tester.pumpAndSettle();
      await tester.tap(overlay);
      await tester.pumpAndSettle();
      await tester.tap(find.text(OverlayBlend.multiply.label).last);
      await tester.pumpAndSettle();
      expect(textIn(controller).textSpec.fill.blend, OverlayBlend.multiply);
      expect(find.byKey(const ValueKey("textFillOverlay")), findsOneWidget,
          reason: "and now a colour to lay");
      expect(
          tester
              .widget<CanvasColorButton>(
                  find.byKey(const ValueKey("textFillOverlay")))
              .onGradientChanged,
          isNotNull,
          reason: "and two to fade between, like every other swatch");

      // And how much of the picture lands at all, which a colour does not
      // need -- its alpha is in the picker -- and a photograph has no other
      // way to get.
      var opacity = find.byKey(const ValueKey("textFillOpacity"));
      await tester.ensureVisible(opacity);
      await tester.pumpAndSettle();
      await enterValue(tester, opacity, "0.25");
      await tester.pumpAndSettle();
      expect(textIn(controller).textSpec.fill.opacity, 0.25);

      // And slid inside its frame, as a share of it -- the same fields a
      // picture in a Layout cell has (Ken, 2026-11-18: a face moved to the
      // middle of its panel).
      for (var (key, percent) in [
        ("textFillPanX", "30"),
        ("textFillPanY", "-20")
      ]) {
        var field = find.byKey(ValueKey(key));
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        await enterValue(tester, field, percent);
        await tester.pumpAndSettle();
      }
      expect(textIn(controller).textSpec.fill.panX, closeTo(0.3, 1e-9));
      expect(textIn(controller).textSpec.fill.panY, closeTo(-0.2, 1e-9));
      var middle = find.byKey(const ValueKey("textFillPanReset"));
      await tester.ensureVisible(middle);
      await tester.pumpAndSettle();
      await tester.tap(middle);
      await tester.pumpAndSettle();
      expect(textIn(controller).textSpec.fill.panX, 0);
      expect(textIn(controller).textSpec.fill.panY, 0);
    });

    testWidgets("the box can be painted with a picture or a pattern too",
        (tester) async {
      // The same question of a different shape, so the same three answers --
      // behind the box's own button, where a thing chosen once belongs.
      var controller = await panel(tester);
      var kind = find.byKey(const ValueKey("textBoxFillKind"));
      if (kind.evaluate().isEmpty) {
        var button = find.byKey(const ValueKey("more-textBox"));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      await tester.ensureVisible(kind);
      await tester.pumpAndSettle();
      await tester.tap(kind);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Pattern").last);
      await tester.pumpAndSettle();

      expect(textIn(controller).box.painted.kind, TextFillKind.pattern);
      expect(find.byKey(const ValueKey("textBoxFillPattern")), findsOneWidget,
          reason: "and what that answer needs is on the line with it");

      // A picture, which is *not* on until one has been chosen -- and the
      // buttons that choose one are these, so they cannot wait for it.
      await tester.tap(kind);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Picture").last);
      await tester.pumpAndSettle();
      expect(textIn(controller).box.painted.on, isFalse,
          reason: "nothing named yet");
      expect(find.byKey(const ValueKey("textBoxFillPicture")), findsOneWidget);
      expect(find.byKey(const ValueKey("textBoxFillLibrary")), findsOneWidget);
    });

    testWidgets("and its colour goes away while a picture is over it",
        (tester) async {
      // A picture or a pattern is drawn across the whole box, so the swatch
      // beside it changed nothing anybody could see -- which reads as a
      // broken control rather than as one that has been overruled.
      var controller = await panel(tester);
      var fill = find.byWidgetPredicate(
          (w) => w is CanvasColorButton && w.label == "Fill");
      expect(fill, findsOneWidget, reason: "a colour to begin with");

      var kind = find.byKey(const ValueKey("textBoxFillKind"));
      if (kind.evaluate().isEmpty) {
        var button = find.byKey(const ValueKey("more-textBox"));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(kind);
      await tester.pumpAndSettle();
      await tester.tap(kind);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Pattern").last);
      await tester.pumpAndSettle();

      expect(textIn(controller).box.painted.kind, TextFillKind.pattern);
      expect(fill, findsNothing, reason: "the pattern decides now");

      // And back again when the colour is what decides.
      await tester.tap(kind);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Colour").last);
      await tester.pumpAndSettle();
      expect(fill, findsOneWidget);
    });

    testWidgets("a middle slot says why its block moves as the words change",
        (tester) async {
      // Reported as the gap growing when text was taken out: a middle slot
      // centres the stack, so half of whatever the words lose is given back
      // above it. The setting is doing what it says, and the panel is where
      // that can be said.
      var centredHint = find.byWidgetPredicate((w) =>
          w is CanvasHint && w.message.contains("keeps this block centred"));
      var middle = TextElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "Spend or burn",
        items: const [
          TextItem(
              id: "n", text: "Master Block Vote", slot: TextSlot.middleLeft),
        ],
      );
      var controller = await panel(tester, element: middle);
      await pickLayer(tester, "n");
      // In a card, the piece's settings are all out: no button to open.
      expect(find.byKey(const ValueKey("more-textItemnType")), findsNothing);
      // A hint is a question mark with a tooltip, so it is found by what it
      // has to say rather than by what is written on the panel.
      expect(centredHint, findsOneWidget);

      // And nothing to say about a slot that holds it to an edge, where the
      // gap means what somebody setting a gap expects.
      controller.replaceElement(textIn(controller).copyWith(items: [
        middle.items.single.copyWith(slot: TextSlot.topLeft),
      ]));
      await tester.pumpAndSettle();
      expect(centredHint, findsNothing);
    });

    testWidgets("a piece is offered a background once it has a colour",
        (tester) async {
      // The colour is the switch: with nothing painted behind the words there
      // is no shape to round and no room to keep inside it.
      var element = TextElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "Spend or burn",
        items: const [
          TextItem(id: "n", text: "01", slot: TextSlot.topLeft),
        ],
      );
      var controller = await panel(tester, element: element);
      await pickLayer(tester, "n");

      expect(find.byKey(const ValueKey("textItemFill0")), findsOneWidget);
      expect(find.byKey(const ValueKey("textItem0Radius")), findsNothing,
          reason: "nothing to round until something is painted");

      // Painted, and the rest comes with it: the corners and the room
      // inside, evenly and one at a time.
      controller.replaceElement(element.copyWith(items: [
        element.items.first
            .copyWith(box: const BoxSpec(fill: Color(0xFF223344))),
      ]));
      await tester.pumpAndSettle();

      // The same controls every other box gets, from the same place: one
      // number for the corners and one for the room, each with a link that
      // splits it into one each.
      expect(find.byKey(const ValueKey("textItem0Radius")), findsOneWidget);
      expect(find.byKey(const ValueKey("textItem0Padding")), findsOneWidget);
      expect(find.byKey(const ValueKey("textItem0Radius↖")), findsNothing);
      for (var link in ["textItem0RadiusLink", "textItem0PaddingLink"]) {
        await tester.ensureVisible(find.byKey(ValueKey(link)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey(link)));
        await tester.pumpAndSettle();
      }
      for (var key in ["textItem0Radius↖", "textItem0PadLeft"]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
    });

    testWidgets("a pattern can be put back to how it started", (tester) async {
      // A pattern nobody likes any more is quicker to start again than to
      // put back a colour, a density, a size and a turn at a time.
      var controller = await panel(tester);
      var own = find.ancestor(
          of: find.byWidgetPredicate(
              (w) => w is CanvasDropdown<String> && w.label == "Font"),
          matching: find.byType(CanvasMoreGroup));
      var button = find.descendant(of: own, matching: find.byIcon(Icons.tune));
      if (button.evaluate().isNotEmpty) {
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      var kind = find.byKey(const ValueKey("textFillKind"));
      await tester.ensureVisible(kind);
      await tester.pumpAndSettle();
      await tester.tap(kind);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Pattern").last);
      await tester.pumpAndSettle();

      var seed = find.byKey(const ValueKey("textFillSeed"));
      await tester.ensureVisible(seed);
      await tester.pumpAndSettle();
      await tester.tap(seed);
      await tester.tap(seed);
      await tester.pumpAndSettle();
      var stirred = textIn(controller).textSpec.fill.pattern;
      expect(stirred.seed, isNot(const ProceduralSpec().seed));

      var reset = find.byKey(const ValueKey("textFillReset"));
      await tester.ensureVisible(reset);
      await tester.pumpAndSettle();
      await tester.tap(reset);
      await tester.pumpAndSettle();

      var back = textIn(controller).textSpec.fill.pattern;
      expect(back.seed, const ProceduralSpec().seed);
      expect(back.style, stirred.style, reason: "the style it was, though");
    });

    testWidgets("a piece can be given a name to find it by", (tester) async {
      // Every picture piece said "Picture", so a card with three of them had
      // three layers called the same thing.
      var element = TextElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "Spend or burn",
        items: const [
          TextItem(id: "p", icon: TextIcon(assetId: "a")),
        ],
      );
      var controller = await panel(tester, element: element);
      var layer = find.byKey(const ValueKey("textLayer-p"));
      expect(find.descendant(of: layer, matching: find.text("Picture")),
          findsOneWidget,
          reason: "before it is named");

      await pickLayer(tester, "p");
      var name = find.byKey(const ValueKey("textItemName0"));
      await tester.ensureVisible(name);
      await tester.pumpAndSettle();
      await enterValue(tester, name, "Leeds badge");
      await tester.pumpAndSettle();

      expect(textIn(controller).items.single.name, "Leeds badge");
      expect(find.descendant(of: layer, matching: find.text("Leeds badge")),
          findsOneWidget);
    });

    testWidgets("a shape can be painted with a picture or a pattern",
        (tester) async {
      // The same three answers the letters and a box have, cut to a third
      // shape -- behind the button, where a thing chosen once belongs.
      var shape = ShapeElement(
        ElementBase(id: newElementId(), width: 300, height: 200),
      );
      var controller =
          CanvasController(const CanvasDocument().addElement(shape));
      addTearDown(controller.dispose);
      controller.selectOnly(shape.id);
      await pump(tester, designSidebar(controller));
      await tester.pumpAndSettle();

      var kind = find.byKey(const ValueKey("shapeFillKind"));
      if (kind.evaluate().isEmpty) {
        var button = find.byKey(const ValueKey("more-shapeMore"));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      await tester.ensureVisible(kind);
      await tester.pumpAndSettle();
      await tester.tap(kind);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Picture").last);
      await tester.pumpAndSettle();

      var after = controller.document.elements.whereType<ShapeElement>().single;
      expect(after.painted.kind, TextFillKind.image);
      expect(find.byKey(const ValueKey("shapeFillPicture")), findsOneWidget,
          reason: "and the buttons that name one are with the choice");
    });

    testWidgets("the type settings are out on the panel, not in a section",
        (tester) async {
      // They were behind a heading that was open every time anybody looked.
      var controller = await panel(tester);
      expect(find.text("Fit to box"), findsOneWidget);
      expect(find.text("Font"), findsOneWidget);
      expect(find.byKey(const ValueKey("elementSection-look")), findsOneWidget);

      // Scrolled to first: with four panels in the column the settings can
      // start below the fold, and a tap outside the viewport hits nothing.
      await tester.ensureVisible(find.text("Fit to box"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Fit to box"));
      await tester.pumpAndSettle();
      expect(textIn(controller).autoSize, isTrue);
    });

    testWidgets(
        "No blank first line is offered without columns, and only "
        "on the box the words belong to", (tester) async {
      // A chain of boxes asks the same question of boxes that columns ask of
      // columns, so it is not a columns-only setting -- and every box in a
      // chain follows what the head says, so there is nowhere else to ask it.
      var head = TextElement(
        const ElementBase(id: "head", width: 400, height: 60),
        text: "A long paragraph",
        flowTo: "tail",
      );
      var tail = TextElement(
        const ElementBase(id: "tail", width: 400, height: 200),
      );
      var controller = CanvasController(
          const CanvasDocument().addElement(head).addElement(tail));
      addTearDown(controller.dispose);

      controller.selectOnly("head");
      await pump(tester, designSidebar(controller));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text("No blank first line"));
      await tester.pumpAndSettle();

      expect(find.text("No blank first line"), findsOneWidget,
          reason: "one column, and still the box the words belong to");
      // On to begin with -- a column top that starts with a blank line is a
      // fault every time, so the switch is there to turn the tidying off --
      // and pressing it turns it off.
      expect(
          (controller.document.elementById("head") as TextElement)
              .columns
              .noBlankStart,
          isTrue);
      await tester.tap(find.text("No blank first line"));
      await tester.pumpAndSettle();
      expect(
          (controller.document.elementById("head") as TextElement)
              .columns
              .noBlankStart,
          isFalse);

      controller.selectOnly("tail");
      await tester.pumpAndSettle();
      expect(find.text("No blank first line"), findsNothing);
    });

    testWidgets("the presets section offers to save this one", (tester) async {
      // A section that lists things and does nothing when they are pressed is
      // what a model-only test cannot see.
      var controller = await panel(tester);
      expect(controller.document.elements.length, 1);

      // In More, under a name in small capitals as the prototype's groups
      // are: the list and its save.
      var list = find.descendant(
          of: find.byKey(const ValueKey("elementSection-more")),
          matching: find.byKey(const ValueKey("elementPresets")));
      expect(list, findsOneWidget);
      await tester.ensureVisible(list);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey("elementPresetSave")), findsOneWidget);
      // Nothing chosen, so there is nothing to rename or throw away.
      expect(find.byKey(const ValueKey("elementPresetRename")), findsNothing);
      expect(find.byKey(const ValueKey("elementPresetRemove")), findsNothing);
      // With nothing saved the list says what the button next to it is for
      // rather than sitting there empty.
      expect(find.text("Save this design"), findsOneWidget);
      expect(find.text("THIS ONE"), findsNothing,
          reason: "a caption over a button that already says what it does");
    });

    testWidgets("turning off From a document gives back what was typed",
        (tester) async {
      // Left showing the document's words, the switch would be off and the
      // element would still say what the document says, with nothing on
      // screen to say what was there before.
      var reading = TextElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "Whatever the document said",
        document: const TextDocumentRef(
            name: "Launch", wasText: "A headline of my own"),
      );
      var controller = await panel(tester, element: reading);

      expect(find.text("From document"), findsOneWidget);
      // Below the fold now that the presets are above it, and a tap at a
      // point outside the viewport hits nothing.
      await tester.ensureVisible(find.text("From document"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("From document"));
      await tester.pumpAndSettle();

      expect(textIn(controller).document.on, isFalse);
      expect(textIn(controller).text, "A headline of my own");
    });

    testWidgets("and a box being flowed into is not offered one",
        (tester) async {
      // Its words belong to the box in front of it, so a document chosen here
      // would be read, stored and never seen -- and the most confusing
      // version of that is a chain already carrying a document, where every
      // box in it looks like somewhere to attach another.
      var head = TextElement(
        const ElementBase(id: "head", width: 400, height: 60),
        text: "A long paragraph",
        flowTo: "tail",
      );
      var tail = TextElement(
        const ElementBase(id: "tail", width: 400, height: 200),
      );
      var controller = CanvasController(
          const CanvasDocument().addElement(head).addElement(tail));
      addTearDown(controller.dispose);

      controller.selectOnly("head");
      await pump(tester, designSidebar(controller));
      await tester.pumpAndSettle();
      expect(find.text("From document"), findsOneWidget,
          reason: "the box the words belong to still chooses");

      controller.selectOnly("tail");
      await tester.pumpAndSettle();
      expect(find.text("From document"), findsNothing);
    });

    testWidgets("and the columns section still works once it is opened",
        (tester) async {
      // A section that shuts its controls away is a section that can hide a
      // dead one, which is what a model-only test cannot see.
      var controller = await panel(tester);
      // Out on the panel rather than behind a heading: one number and a
      // switch is not a section.
      var field = find.byKey(const ValueKey("textColumns"));
      expect(field, findsOneWidget);
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();

      await enterValue(tester, field, "3");
      await tester.pumpAndSettle();
      expect(textIn(controller).columns.count, 3);
      // And the rest of them arrive once there is a gutter to put them in.
      expect(find.text("Gap"), findsOneWidget);
      expect(find.text("Rule"), findsOneWidget);
    });
  });
}
