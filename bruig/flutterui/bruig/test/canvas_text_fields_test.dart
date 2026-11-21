import 'support/canvas_app.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/text_fields.dart';
import 'package:bruig/plugin_system/canvas/render/text_items.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/canvas_settings_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_text_fields_test.dart is the fields a text may hold, filled in by
// the page it is drawn on (text_fields.dart). Ken wanted the piano book's
// header on the master canvas, reading "Lesson # of 10" there and the
// lesson's number on each page, and asked for three ways to get the number:
// the page number, the words of a text on the page, and a value the page is
// given.

/// book is a front cover and three pages, each page's title piece named
/// "Lesson number" and the second page given a chapter.
CanvasDocument book({Map<String, String> secondValues = const {}}) =>
    CanvasDocument(
      kind: CanvasKind.pages,
      size: const CanvasSize(ratio: CanvasRatio.a4, width: a4PageWidth),
      masterOn: true,
      master: CanvasScene(id: "m", elements: [
        const TextElement(ElementBase(id: "head"), text: "Lesson {page} of 10"),
        ShapeElement(const ElementBase(id: "rule")),
      ]),
      scenes: [
        const CanvasScene(id: "cover", cover: PageCover.front),
        for (var i = 1; i <= 3; i++)
          CanvasScene(
            id: "p$i",
            values: i == 2 ? secondValues : const {},
            elements: [
              TextElement(ElementBase(id: "t$i", name: "Title"),
                  text: "Lesson title",
                  items: [
                    TextItem(
                        id: "n$i", name: "Lesson number", text: "${i * 2}"),
                  ]),
            ],
          ),
      ],
    );

void main() {
  group("filling a field", () {
    PageFields on({int? page, bool master = false}) => PageFields(
        page: page,
        pages: 10,
        values: const {"Chapter": "Two"},
        master: master,
        textOf: (name) => name == "Lesson number" ? "7" : null);

    test("each kind", () {
      expect(fillFields("Lesson {page} of {pages}", on(page: 3)),
          "Lesson 3 of 10");
      expect(
          fillFields("Lesson {text:Lesson number}", on(page: 3)), "Lesson 7");
      expect(fillFields("Chapter {value:Chapter}", on(page: 3)), "Chapter Two");
    });

    test("on the master, each that depends on the page is #", () {
      expect(
          fillFields("Lesson {page} of {pages} · {text:X} {value:Y}",
              on(master: true)),
          "Lesson # of 10 · # #");
    });

    test("what is not a field, or not on the page, is left alone or blank", () {
      expect(fillFields("A {curly} brace", on(page: 1)), "A {curly} brace");
      expect(fillFields("{text:Missing}!", on(page: 1)), "!");
      expect(fillFields("Page {page}", on()), "Page ",
          reason: "an unnumbered page has no number to show");
      expect(hasFields("No fields here"), isFalse);
      expect(hasFields("{page}"), isTrue);
    });
  });

  group("on the pages of a book", () {
    test("the page number, with the cover not counted", () {
      var doc = book().goToScene(2);
      expect(doc.pageFields.page, 2);
      expect(doc.pageFields.pages, 3);
      var head =
          textWithFields(doc.masterScene!.elements.first as TextElement, doc);
      expect(head.text, "Lesson 2 of 10");
    });

    test("the words of a text on the page", () {
      var doc = book().goToScene(3);
      expect(doc.pageFields.textOf("Lesson number"), "6");
      expect(doc.pageFields.textOf("Title"), "Lesson title");
    });

    test("a value set on the page", () {
      var doc = book(secondValues: {"Lesson": "Two"}).goToScene(2);
      var e = const TextElement(ElementBase(id: "x"),
          text: "Lesson {value:Lesson}");
      expect(textWithFields(e, doc).text, "Lesson Two");
      expect(textWithFields(e, book().goToScene(1)).text, "Lesson ",
          reason: "another page has no such value");
    });

    test("pieces are filled too", () {
      var doc = book().goToScene(1);
      var e = const TextElement(ElementBase(id: "x"), text: "Head", items: [
        TextItem(id: "i", text: "{page}"),
      ]);
      expect(textWithFields(e, doc).items.single.text, "1");
      expect(
          identical(textWithFields(doc.elements.first as TextElement, doc),
              doc.elements.first),
          isTrue,
          reason: "a text with no fields is drawn as it is");
    });

    test("on the master itself, #", () {
      var doc = book().goToScene(2).copyWith(onMaster: true);
      expect(doc.editingMaster, isTrue);
      var head = textWithFields(doc.elements.first as TextElement, doc);
      expect(head.text, "Lesson # of 10");
    });
  });

  group("the master on a cover", () {
    test("keeps its backdrop but not its elements", () {
      var doc = book().goToScene(0);
      expect(doc.masterScene, isNotNull,
          reason: "its backdrop still reaches the cover");
      expect(doc.masterScene!.elements, isEmpty);
      expect(book().goToScene(1).masterScene!.elements, hasLength(2));
    });

    test("unless Master on covers is on", () {
      var doc = book()
          .copyWith(pages: const PagesSpec(masterOnCovers: true))
          .goToScene(0);
      expect(doc.masterScene!.elements, hasLength(2));
    });

    test("a cover's master is the same one each time it is asked", () {
      var doc = book().goToScene(0);
      expect(identical(doc.masterScene, doc.masterScene), isTrue);
    });
  });

  group("written down and read back", () {
    test("page values and Master on covers", () {
      var doc = book(secondValues: {"Lesson": "Two"})
          .copyWith(pages: const PagesSpec(masterOnCovers: true));
      var back = CanvasDocument.fromJson(doc.toJson());
      expect(back.allScenes[2].values, {"Lesson": "Two"});
      expect(back.pages.masterOnCovers, isTrue);
    });

    test("a page with only values is still written as a page", () {
      var doc = CanvasDocument(scenes: [
        const CanvasScene(id: "a", values: {"x": "1"}),
      ]);
      expect(CanvasDocument.fromJson(doc.toJson()).allScenes.single.values,
          {"x": "1"});
    });
  });

  group("the controls", () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<void> show(WidgetTester tester, Widget child) async {
      setTestScreen(tester, const Size(1400, 1200));
      await tester.pumpWidget(canvasApp(child));
      await tester.pumpAndSettle();
    }

    testWidgets("a page is given a value in its settings", (tester) async {
      var controller = CanvasController(book().goToScene(2));
      addTearDown(controller.dispose);
      await show(tester, CanvasSettingsPanel(controller: controller));

      await tester.ensureVisible(find.byKey(const ValueKey("pageValueAdd")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("pageValueAdd")));
      await tester.pumpAndSettle();
      expect(controller.document.scene.values, {"Value": ""});

      await tester.enterText(
          find.descendant(
              of: find.byKey(const ValueKey("pageValueName0")),
              matching: find.byType(TextField)),
          "Lesson");
      await tester.enterText(
          find.descendant(
              of: find.byKey(const ValueKey("pageValue0")),
              matching: find.byType(TextField)),
          "Two");
      await tester.pumpAndSettle();
      expect(controller.document.scene.values, {"Lesson": "Two"});

      var remove = find.byKey(const ValueKey("pageValueRemove0"));
      await tester.ensureVisible(remove);
      await tester.pumpAndSettle();
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(controller.document.scene.values, isEmpty);
    });

    testWidgets("Master on covers is a switch with the pages", (tester) async {
      var controller = CanvasController(book());
      addTearDown(controller.dispose);
      await show(tester, CanvasSettingsPanel(controller: controller));
      await tester
          .ensureVisible(find.byKey(const ValueKey("pagesMasterOnCovers")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("pagesMasterOnCovers")));
      await tester.pumpAndSettle();
      expect(controller.document.pages.masterOnCovers, isTrue);
    });

    testWidgets("a field is added to the words from the text's settings",
        (tester) async {
      var doc = book().goToScene(1);
      var controller = CanvasController(doc);
      addTearDown(controller.dispose);
      controller.selectOnly("t1");
      setTestScreen(tester, const Size(1400, 1200));
      await tester
          .pumpWidget(canvasApp(CanvasDesignPanel(controller: controller)));
      await tester.pumpAndSettle();

      // Content may be folded shut: opened by its heading.
      if (find.byKey(const ValueKey("textWords")).evaluate().isEmpty) {
        await tester.tap(find.text("Content").first);
        await tester.pumpAndSettle();
      }
      var field = find.byKey(const ValueKey("textAddField"));
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text(TextFieldKind.page.label).last);
      await tester.pumpAndSettle();
      expect((controller.document.elementById("t1") as TextElement).text,
          "Lesson title {page}");
    });
  });
}
