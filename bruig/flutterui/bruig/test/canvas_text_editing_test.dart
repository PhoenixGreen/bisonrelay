import 'dart:math' as math;
import 'dart:ui' as ui;

import 'support/canvas_app.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/text_items.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_text_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_text_editing_test.dart is typing into a text element on the canvas:
// what opening the editor leaves on the page. Ken found three faults: a
// heading piece folded onto two lines with an underline under it as soon as
// it was opened; opening the paragraph hid the element's box and every other
// piece; and the words opened all selected rather than with a caret where
// the click was.

const _box = Color(0xFF123456);

/// _card is a header like Learn Flutter's: a filled box, its paragraph at
/// the bottom, and a title piece whose own box is an underline.
TextElement _card() => const TextElement(
      ElementBase(id: "t", x: 100, y: 100, width: 1100, height: 214),
      text: "A profile card, from everything so far.",
      textSpec: TextSpec(fontSize: 22, verticalAlign: VerticalAlignSpec.bottom),
      box: BoxSpec(fill: _box, padding: 34),
      items: [
        TextItem(
          id: "title",
          text: "Putting It Together",
          slot: TextSlot.topLeft,
          gap: 12,
          box: BoxSpec(
              borderColor: Color(0xFF4F7DF8), bwB: 4, padding: 0, padB: 10),
          spec: TextSpec(fontSize: 46, weight: 800, lineHeight: 1.12),
        ),
      ],
    );

void main() {
  const viewport = Size(1000, 800);

  Future<(CanvasController, CanvasStageState)> pump(
      WidgetTester tester, TextElement element,
      {int? frames}) async {
    var document = frames == null
        ? const CanvasDocument()
        : CanvasDocument(frames: frames);
    var controller = CanvasController(document.addElement(element));
    addTearDown(controller.dispose);
    var key = GlobalKey<CanvasStageState>();
    setTestScreen(tester, viewport);
    await tester.pumpWidget(canvasApp(SizedBox(
        width: viewport.width,
        height: viewport.height,
        child: CanvasStage(key: key, controller: controller))));
    await tester.pumpAndSettle();
    return (controller, key.currentState!);
  }

  /// doubleClick presses twice at document point [at], as a person opening
  /// the words does.
  Future<void> doubleClick(WidgetTester tester, CanvasStageState stage,
      CanvasController controller, Offset at) async {
    var scale = stage.pageRect.width / controller.document.size.width;
    var point = stage.pageRect.topLeft + at * scale;
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    await tester.tapAt(point);
    await tester.pumpAndSettle();
  }

  RenderEditable editable(WidgetTester tester) => tester
      .state<EditableTextState>(find.descendant(
          of: find.byType(CanvasTextEditor),
          matching: find.byType(EditableText)))
      .renderEditable;

  int linesIn(RenderEditable r) {
    var boxes = r.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: r.plainText.length));
    return {for (var b in boxes) b.top.round()}.length;
  }

  testWidgets("a heading piece opens on the line it is drawn on",
      (tester) async {
    // The field was exactly as wide as the words, and a TextField keeps room
    // for its caret out of the width it wraps in: the last word fell onto a
    // second line.
    var e = _card();
    var (controller, stage) = await pump(tester, e);
    var title = textItemRects(e, e.bounds).single;
    await doubleClick(tester, stage, controller, title.center);

    expect(find.byType(CanvasTextEditor), findsOneWidget);
    expect(tester.widget<CanvasTextEditor>(find.byType(CanvasTextEditor)).item,
        isNotNull,
        reason: "the click opened the title piece");
    expect(linesIn(editable(tester)), 1, reason: "not folded onto two lines");
  });

  testWidgets("a locked piece is not opened, nor the words under it",
      (tester) async {
    // The click lands on the piece, which is locked: it is not the element's
    // own words, so they are not opened in its place.
    var e = _card();
    e = e.copyWith(items: [e.items.single.copyWith(locked: true)]);
    var (controller, stage) = await pump(tester, e);
    await doubleClick(
        tester, stage, controller, textItemRects(e, e.bounds).single.center);
    expect(find.byType(CanvasTextEditor), findsNothing);
    expect(controller.textLayer(e), isNull, reason: "nor is it picked");
    expect(controller.isOnlySelected("t"), isTrue,
        reason: "the click still selects the text");
  });

  testWidgets("the field has no underline or fill of its own", (tester) async {
    // The app's theme gives every field an underline, drawn here on the page.
    var e = _card();
    var (controller, stage) = await pump(tester, e);
    await doubleClick(
        tester, stage, controller, textItemRects(e, e.bounds).single.center);

    var decorator = tester.widget<InputDecorator>(find.descendant(
        of: find.byType(CanvasTextEditor),
        matching: find.byType(InputDecorator)));
    var d = decorator.decoration;
    for (var border in [d.border, d.enabledBorder, d.focusedBorder]) {
      expect(border == null || border == InputBorder.none, isTrue,
          reason: "$border");
    }
    expect(d.filled, isNot(true));
  });

  testWidgets("opened words stay drawn by the canvas, the field see-through",
      (tester) async {
    // So nothing changes on the page when it opens: same size, same style,
    // the box and the other pieces where they were. Only the caret shows.
    var e = _card();
    var (controller, stage) = await pump(tester, e);
    var body = e.box.inner(e.bounds);
    await doubleClick(
        tester, stage, controller, Offset(body.left + 60, body.bottom - 10));

    var editor = tester.widget<CanvasTextEditor>(find.byType(CanvasTextEditor));
    expect(editor.item, isNull, reason: "the paragraph was opened");
    expect(editor.showWords, isFalse);
    var field = tester.widget<TextField>(find.descendant(
        of: find.byType(CanvasTextEditor), matching: find.byType(TextField)));
    expect(field.style!.color!.a, 0, reason: "the field's own words are clear");
  });

  testWidgets("words opened elsewhere keep their box and the other pieces",
      (tester) async {
    // Where the field must show the words itself (here, text set in two
    // columns), the canvas leaves out those words alone.
    var e = _card();
    var recorder = ui.PictureRecorder();
    var doc = const CanvasDocument().addElement(e);
    paintCanvasDocument(ui.Canvas(recorder), doc,
        frame: 0, skipTextItem: textBodyWords);
    var picture = recorder.endRecording();
    var image = await tester.runAsync(
        () => picture.toImage(doc.size.width.round(), doc.size.height.round()));
    var bytes = await tester
        .runAsync(() => image!.toByteData(format: ui.ImageByteFormat.rawRgba));
    Color at(Offset p) {
      var i = (p.dy.round() * image!.width + p.dx.round()) * 4;
      return Color.fromARGB(bytes!.getUint8(i + 3), bytes.getUint8(i),
          bytes.getUint8(i + 1), bytes.getUint8(i + 2));
    }

    // A corner of the box, clear of every word.
    expect(at(e.bounds.bottomRight - const Offset(8, 8)), _box,
        reason: "the box is still drawn");
    var title = textItemRects(e, e.bounds).single;
    expect(at(Offset(title.left + 3, title.bottom - 2)), isNot(_box),
        reason: "the title's underline is still drawn");
    image!.dispose();
    picture.dispose();
  });

  testWidgets("the caret goes where the click was", (tester) async {
    var e = const TextElement(
      ElementBase(id: "t", x: 100, y: 100, width: 1200, height: 120),
      text: "Hello wonderful world",
      textSpec: TextSpec(
          fontSize: 40,
          align: TextAlignSpec.left,
          verticalAlign: VerticalAlignSpec.top),
      box: BoxSpec(padding: 0),
    );
    var (controller, stage) = await pump(tester, e);
    // Test fonts draw every letter a square as wide as the type is tall:
    // between the sixth and seventh letters.
    await doubleClick(
        tester, stage, controller, const Offset(100 + 6 * 40, 120));
    await tester.pump();

    var field = tester.widget<TextField>(find.descendant(
        of: find.byType(CanvasTextEditor), matching: find.byType(TextField)));
    var selection = field.controller!.selection;
    expect(selection.isCollapsed, isTrue, reason: "a caret, nothing selected");
    expect(selection.baseOffset, inInclusiveRange(5, 7));
  });

  testWidgets(
    "and where the click was among words of another size",
    (tester) async {
      // The field lays the words out in one style; the canvas draws the first
      // word at twice the size, so a click on the second word lands in the
      // field's first.
      var e = const TextElement(
        ElementBase(id: "t", x: 100, y: 100, width: 1200, height: 120),
        text: "Hello wonderful world",
        textSpec: TextSpec(
            fontSize: 40,
            align: TextAlignSpec.left,
            verticalAlign: VerticalAlignSpec.top),
        box: BoxSpec(padding: 0),
        parts: [TextPart(from: 1, to: 1, scale: 2)],
      );
      var (controller, stage) = await pump(tester, e);
      // "Hello" drawn 80 a letter, the space 40, then three letters of
      // "wonderful": between its "n" and "d", the ninth character.
      await doubleClick(
          tester, stage, controller, const Offset(100 + 440 + 3 * 40, 140));
      await tester.pump();

      var field = tester.widget<TextField>(find.descendant(
          of: find.byType(CanvasTextEditor), matching: find.byType(TextField)));
      expect(field.controller!.selection.baseOffset, inInclusiveRange(8, 10));
    },
    skip: true, // The field cannot lay out a part's size until the
    // paragraph is laid out in one place for the painter and the editor.
  );

  testWidgets("a turned editor is turned as the element is on this frame",
      (tester) async {
    // The see-through field sat at the element's resting turn while the
    // drawing was turned by its keys, so the caret was off the words.
    var e = TextElement(
      ElementBase(
          id: "t",
          x: 200,
          y: 200,
          width: 400,
          height: 120,
          track: ElementTrack(const [
            Keyframe(frame: 0),
            Keyframe(frame: 20, rotate: 30),
          ])),
      text: "Turning words",
      textSpec: const TextSpec(fontSize: 40),
      box: const BoxSpec(padding: 0),
    );
    var (controller, stage) = await pump(tester, e, frames: 24);
    controller.frame = 10;
    await tester.pumpAndSettle();
    await doubleClick(tester, stage, controller, e.bounds.center);
    await tester.pump();

    expect(find.byType(CanvasTextEditor), findsOneWidget);
    var turn = tester
        .widget<Transform>(find
            .descendant(
                of: find.byType(CanvasTextEditor),
                matching: find.byType(Transform))
            .first)
        .transform;
    var angle = math.atan2(turn.entry(1, 0), turn.entry(0, 0));
    var drawn = controller.document
            .elementById("t")!
            .movedRotationAt(10, controller.document) *
        math.pi /
        180;
    expect(drawn, isNot(0), reason: "otherwise this test asks nothing");
    expect(angle, closeTo(drawn, 0.001));
  });

  testWidgets("a new element's Text still opens selected", (tester) async {
    var e = const TextElement(
      ElementBase(id: "t", x: 100, y: 100, width: 600, height: 120),
      text: "Text",
    );
    var (controller, stage) = await pump(tester, e);
    await doubleClick(tester, stage, controller, e.bounds.center);
    await tester.pump();

    var field = tester.widget<TextField>(find.descendant(
        of: find.byType(CanvasTextEditor), matching: find.byType(TextField)));
    var selection = field.controller!.selection;
    expect(selection.start, 0);
    expect(selection.end, 4, reason: "typing replaces it");
  });

  group("a picture in a text", () {
    // Ken: "selecting an icon hides the icon and shows an empty text editor;
    // ideally, double clicking on an icon should allow you to remove, move,
    // rotate and resize the icon by placing an edit box around it."
    TextElement withPicture() => const TextElement(
          ElementBase(id: "t", x: 200, y: 200, width: 800, height: 400),
          text: "Words",
          box: BoxSpec(padding: 20),
          items: [
            TextItem(
                id: "pic",
                slot: TextSlot.topRight,
                icon: TextIcon(assetId: "asset1", size: 100)),
          ],
        );

    Rect picture(CanvasController c) {
      var e = c.document.elementById("t") as TextElement;
      return textItemRects(e, e.bounds).single;
    }

    Future<(CanvasController, CanvasStageState)> opened(
        WidgetTester tester) async {
      var e = withPicture();
      var (c, s) = await pump(tester, e);
      await doubleClick(tester, s, c, picture(c).center);
      return (c, s);
    }

    TextItem pic(CanvasController c) =>
        (c.document.elementById("t") as TextElement).items.single;

    testWidgets("a double-click picks it, with no editor", (tester) async {
      var (c, s) = await opened(tester);
      expect(find.byType(CanvasTextEditor), findsNothing);
      var e = c.document.elementById("t") as TextElement;
      expect(c.textLayer(e)?.id, "pic");
      var scale = s.pageRect.width / c.document.size.width;
      expect(
          s.handleAt(StageHandle.bottomRight),
          offsetMoreOrLessEquals(
              s.pageRect.topLeft + picture(c).bottomRight * scale,
              epsilon: 1),
          reason: "the box is round the picture, not the text");
    });

    testWidgets("dragged inside its box it moves, alone", (tester) async {
      var (c, s) = await opened(tester);
      var scale = s.pageRect.width / c.document.size.width;
      var before = picture(c);
      await tester.timedDragFrom(s.toStagePoint(before.center),
          const Offset(-60, 40) * scale, const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(picture(c).center - before.center,
          offsetMoreOrLessEquals(const Offset(-60, 40), epsilon: 1));
      expect(c.document.elementById("t")!.bounds, withPicture().bounds,
          reason: "the text stays where it was");
    });

    testWidgets("a corner sizes it and the ring turns it", (tester) async {
      var (c, s) = await opened(tester);
      var scale = s.pageRect.width / c.document.size.width;
      // Pulled to twice as far from its middle: twice the size.
      var corner = s.handleAt(StageHandle.bottomRight);
      await tester.timedDragFrom(corner, const Offset(50, 50) * scale,
          const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(pic(c).icon!.size, closeTo(200, 2));

      // From above its middle round to its right: a quarter turn.
      var mid = s.toStagePoint(picture(c).center);
      var ring = s.handleAt(StageHandle.rotate);
      var to = mid + Offset((ring - mid).distance, 0);
      await tester.timedDragFrom(
          ring, to - ring, const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(pic(c).icon!.turn, closeTo(90, 1));
      expect(c.document.elementById("t")!.rotation, 0,
          reason: "the text itself is not turned");
    });

    testWidgets("Delete takes the picture out, not the text", (tester) async {
      var (c, _) = await opened(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      var e = c.document.elementById("t") as TextElement?;
      expect(e, isNotNull);
      expect(e!.items, isEmpty);
    });

    testWidgets("a press elsewhere on the text is the text's again",
        (tester) async {
      var (c, s) = await opened(tester);
      var e = c.document.elementById("t") as TextElement;
      await tester
          .tapAt(s.toStagePoint(e.bounds.bottomLeft + const Offset(60, -60)));
      await tester.pumpAndSettle();
      expect(c.textLayer(c.document.elementById("t") as TextElement), isNull);
      expect(c.selection, {"t"});
    });

    testWidgets("the arrows move it alone, Shift by ten", (tester) async {
      // Ken: "move it using the arrows to do smaller more specific
      // movement" -- they moved the whole text.
      var (c, _) = await opened(tester);
      var before = picture(c);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(picture(c).topLeft - before.topLeft,
          offsetMoreOrLessEquals(const Offset(2, -1)));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(picture(c).topLeft - before.topLeft,
          offsetMoreOrLessEquals(const Offset(2, 9)));
      expect(c.document.elementById("t")!.bounds, withPicture().bounds,
          reason: "the text stays where it was");
      c.undo();
      expect(picture(c).topLeft - before.topLeft,
          offsetMoreOrLessEquals(const Offset(2, -1)),
          reason: "each press its own step");
    });

    test("in a turned text, the way the arrow points", () {
      var e = withPicture().withBase(rotation: 90) as TextElement;
      var c = CanvasController(const CanvasDocument().addElement(e));
      addTearDown(c.dispose);
      c.selectOnly("t");
      c.pickTextLayer("t", "pic");
      c.nudgeSelected(10, 0);
      var item = (c.document.elementById("t") as TextElement).items.single;
      // A quarter turn clockwise: the page's right is the text's up.
      expect(item.down, closeTo(-10, 1e-9));
      expect(item.side, closeTo(0, 1e-9));
    });

    test("in a text whose turn is keyed, the way the arrow points now", () {
      // The stage drags it in the turn the text is drawn at; the arrows
      // go the same way, not by the turn it rests at.
      var e = withPicture().withBase(
              track: ElementTrack(const [Keyframe(frame: 0, rotate: 90)]))
          as TextElement;
      var c = CanvasController(const CanvasDocument(frames: 24).addElement(e));
      addTearDown(c.dispose);
      c.selectOnly("t");
      c.pickTextLayer("t", "pic");
      c.nudgeSelected(10, 0);
      var item = (c.document.elementById("t") as TextElement).items.single;
      expect(item.down, closeTo(-10, 1e-9));
      expect(item.side, closeTo(0, 1e-9));
    });

    test("a picture piece with no picture yet leaves the arrows to the text",
        () {
      // The canvas shows it no box to drag, so the arrows are the text's,
      // as a press on it is.
      var e = withPicture().copyWith(items: const [
        TextItem(id: "pic", slot: TextSlot.topRight, icon: TextIcon()),
      ]);
      var c = CanvasController(const CanvasDocument().addElement(e));
      addTearDown(c.dispose);
      c.selectOnly("t");
      c.pickTextLayer("t", "pic");
      c.nudgeSelected(10, 0);
      var moved = c.document.elementById("t") as TextElement;
      expect(moved.items.single.side, 0);
      expect(moved.bounds.left, e.bounds.left + 10);
    });

    test("its move and turn are kept", () {
      var item = const TextItem(
          id: "p",
          side: 900,
          down: -30,
          icon: TextIcon(assetId: "a", turn: 45));
      var back = TextItem.fromJson(item.toJson());
      expect(back.side, 900, reason: "further than the old 400 cap");
      expect(back.down, -30);
      expect(back.icon!.turn, 45);
    });
  });
}
