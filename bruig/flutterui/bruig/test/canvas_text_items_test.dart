import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/text_items.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/text_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_text_items_test.dart is a text element carrying more than one piece
// of writing.
//
// A card is four of them in one rectangle: a number over a title, a line of
// small print under it, a name against the right-hand edge. That was four
// elements and a shape, which had to be moved together, kept in step and
// built again for the next card.

const _blue = Color(0xFF3D94E8);

TextElement _card({List<TextItem>? items}) => TextElement(
      const ElementBase(id: "c", x: 0, y: 0, width: 400, height: 200),
      text: "Spend or burn",
      textSpec: const TextSpec(
        fontSize: 30,
        color: Color(0xFFFFFFFF),
        verticalAlign: VerticalAlignSpec.middle,
      ),
      box: const BoxSpec(padding: 20),
      items: items ??
          const [
            TextItem(
                id: "n",
                text: "01",
                slot: TextSlot.topLeft,
                spec: TextSpec(fontSize: 14, color: _blue)),
            TextItem(
                id: "p",
                text: "Dash",
                slot: TextSlot.middleRight,
                spec: TextSpec(fontSize: 20, color: _blue)),
          ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("where the pieces go", () {
    test("a slot holds a piece to its own corner of the box", () {
      var e = _card();
      var rects = textItemRects(e, e.bounds);
      var inner = e.box.inner(e.bounds);

      expect(rects[0].left, closeTo(inner.left, 0.01), reason: "top left");
      expect(rects[0].top, closeTo(inner.top, 0.01));
      expect(rects[1].right, closeTo(inner.right, 0.01),
          reason: "and the right-hand edge for the other");
      expect(rects[1].center.dy, closeTo(inner.center.dy, 1.5),
          reason: "middle, down the box");
    });

    test("two pieces in one slot stack rather than overlap", () {
      var e = _card(items: const [
        TextItem(id: "a", text: "One", slot: TextSlot.topLeft),
        TextItem(id: "b", text: "Two", slot: TextSlot.topLeft),
      ]);
      var rects = textItemRects(e, e.bounds);
      expect(rects[0].bottom, closeTo(rects[1].top, 0.01),
          reason: "the second sits under the first, not on it");
      expect(rects[0].top, closeTo(e.box.inner(e.bounds).top, 0.01));
    });

    test("and a stack in a bottom slot ends at the bottom", () {
      var e = _card(items: const [
        TextItem(id: "a", text: "One", slot: TextSlot.bottomLeft),
        TextItem(id: "b", text: "Two", slot: TextSlot.bottomLeft),
      ]);
      var rects = textItemRects(e, e.bounds);
      expect(rects[1].bottom, closeTo(e.box.inner(e.bounds).bottom, 0.01));
      expect(rects[0].bottom, closeTo(rects[1].top, 0.01));
    });

    test("they survive being saved, and cost nothing unused", () {
      var plain = TextElement(const ElementBase(id: "t"), text: "Words");
      expect(plain.toJson().containsKey("items"), isFalse);

      var back =
          CanvasDocument.decode(CanvasDocument(elements: [_card()]).encode())!
              .elements
              .single as TextElement;
      expect(back.items.length, 2);
      expect(back.items.first.text, "01");
      expect(back.items.first.slot, TextSlot.topLeft);
      expect(back.items.last.spec.fontSize, 20);
      expect(back.items.last.id, "p", reason: "its own id, kept");
    });
  });

  group("what is drawn", () {
    /// _ink is where the blue pixels are: the pieces are blue and the
    /// element's own words are white, so this finds the pieces alone.
    Future<List<Offset>> ink(TextElement e) async {
      var recorder = ui.PictureRecorder();
      var canvas = ui.Canvas(recorder);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 400, 200),
          Paint()..color = const Color(0xFF000000));
      paintElement(canvas, e, 0);
      var image = await recorder.endRecording().toImage(400, 200);
      var bytes = (await image.toByteData())!;
      image.dispose();
      return [
        for (var y = 0; y < 200; y++)
          for (var x = 0; x < 400; x++)
            if (((bytes.getUint32((y * 400 + x) * 4) >> 8) & 0xFF) > 0x90 &&
                ((bytes.getUint32((y * 400 + x) * 4) >> 24) & 0xFF) < 0x90)
              Offset(x.toDouble(), y.toDouble()),
      ];
    }

    testWidgets("a piece is drawn in its slot", (tester) async {
      late List<Offset> drawn;
      await tester.runAsync(() async => drawn = await ink(_card()));
      expect(drawn, isNotEmpty, reason: "the pieces are there at all");

      var topLeft = drawn.where((p) => p.dx < 120 && p.dy < 60).length;
      var middleRight = drawn.where((p) => p.dx > 280 && p.dy > 70).length;
      expect(topLeft, greaterThan(10), reason: "the number, top left");
      expect(middleRight, greaterThan(10), reason: "the name, on the right");
      expect(
          drawn.where((p) => p.dx > 150 && p.dx < 250 && p.dy < 60).length, 0,
          reason: "and nothing in the middle of the top");
    });

    testWidgets("moving it to another slot moves what is drawn",
        (tester) async {
      late List<Offset> before;
      late List<Offset> after;
      var e = _card();
      await tester.runAsync(() async {
        before = await ink(e);
        after = await ink(e.copyWith(items: [
          e.items.first.copyWith(slot: TextSlot.bottomRight),
          e.items.last,
        ]));
      });
      expect(before.where((p) => p.dx < 120 && p.dy < 60), isNotEmpty);
      expect(after.where((p) => p.dx < 120 && p.dy < 60), isEmpty,
          reason: "it left the top left corner");
      expect(after.where((p) => p.dx > 280 && p.dy > 140), isNotEmpty,
          reason: "and arrived in the bottom right");
    });
  });

  testWidgets("a piece's row fits a narrow sidebar", (tester) async {
    // 300 is about the narrowest anybody leaves the panel, and the row has
    // more on it than the element's own: the slot it sits in, and a button to
    // take it away. What must not happen is the slot ending up alone on a
    // line, where it reads as belonging to the piece after it.
    tester.view.physicalSize = const Size(700, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var controller = CanvasController(const CanvasDocument().addElement(_card(
        items: const [TextItem(id: "n", text: "01", slot: TextSlot.topLeft)])));
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider(
        create: (_) => ThemeNotifier(doLoad: false),
        child: Scaffold(
          body: SingleChildScrollView(
            child: CanvasControlScope(
              maxWidth: 300,
              child: SizedBox(
                width: 300,
                child: Builder(
                  builder: (context) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: textSettings(
                        context,
                        controller,
                        controller.document.elementById("c") as TextElement,
                        (next) => controller.replaceElement(next),
                        () {},
                        () {}),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    var group = find.ancestor(
        of: find.byKey(const ValueKey("textItemSlot0")),
        matching: find.byType(CanvasMoreGroup));
    var slot = tester.getRect(find.byKey(const ValueKey("textItemSlot0")));
    var face = tester.getRect(find.descendant(
        of: group, matching: find.byType(CanvasDropdown<String>)));
    var size = tester.getRect(
        find.descendant(of: group, matching: find.byType(CanvasNumberField)));

    expect(face.top, closeTo(slot.top, 0.5),
        reason: "the slot and the face are on one line");
    expect(size.top, closeTo(slot.top, 0.5));
    expect(size.right, lessThanOrEqualTo(300));
  });

  group("typing into one", () {
    Future<CanvasStageState> pump(
        WidgetTester tester, CanvasController controller) async {
      var key = GlobalKey<CanvasStageState>();
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 700,
              child: CanvasStage(key: key, controller: controller),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return key.currentState!;
    }

    testWidgets("a second click on a piece types into that piece",
        (tester) async {
      // The words of an item are typed where they are drawn, like every other
      // words on the canvas. A field in the settings panel would be a second
      // place to type, at a size and a face that are not the ones it will be
      // read at.
      var card = _card();
      var controller = CanvasController(CanvasDocument(
        size: const CanvasSize(width: 800, ratio: CanvasRatio.wide),
      ).addElement(card));
      addTearDown(controller.dispose);
      controller.selectOnly("c");
      var stage = await pump(tester, controller);

      var rects = textItemRects(card, card.bounds);
      var at = stage.toStagePoint(rects[1].center);
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tapAt(at);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget,
          reason: "an editor opened over the piece");
      await tester.enterText(find.byType(TextField), "Decred");
      await tester.pumpAndSettle();

      var after = controller.document.elementById("c") as TextElement;
      expect(after.items.last.text, "Decred");
      expect(after.text, "Spend or burn",
          reason: "the element's own words are untouched");
    });

    testWidgets("and a second click anywhere else types into the element",
        (tester) async {
      var card = _card();
      var controller = CanvasController(CanvasDocument(
        size: const CanvasSize(width: 800, ratio: CanvasRatio.wide),
      ).addElement(card));
      addTearDown(controller.dispose);
      controller.selectOnly("c");
      var stage = await pump(tester, controller);

      var at = stage.toStagePoint(const Offset(200, 100));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tapAt(at);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), "Burn it");
      await tester.pumpAndSettle();

      var after = controller.document.elementById("c") as TextElement;
      expect(after.text, "Burn it");
      expect(after.items.last.text, "Dash");
    });
  });
}
