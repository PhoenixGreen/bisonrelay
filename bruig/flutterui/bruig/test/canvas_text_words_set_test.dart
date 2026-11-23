import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/text_flow.dart';
import 'package:bruig/plugin_system/canvas/render/text_items.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_text_editor.dart';

import 'support/canvas_app.dart';

// canvas_text_words_set_test.dart is a text whose fields ask for two ways of
// setting its words at once: on a line and with pieces, fitting or a chain;
// on a line that is not on the page. The fields are all kept, so taking a
// text off its line gives back what it had; what is drawn is decided in one
// order (TextElement.wordsSetIn), and every other reader -- the stage's
// clicks and handles, the editor, the chain -- must agree with what is drawn.

const _viewport = Size(1280, 800);

/// _line is a level line across the lower half of the page, well clear of
/// the text's own box.
const _line =
    LineElement(ElementBase(id: "l", x: 200, y: 600, width: 900, height: 6));

void main() {
  Future<(CanvasController, CanvasStageState)> pump(
      WidgetTester tester, CanvasDocument document) async {
    var c = CanvasController(document);
    addTearDown(c.dispose);
    var key = GlobalKey<CanvasStageState>();
    setTestScreen(tester, _viewport);
    await tester.pumpWidget(canvasApp(SizedBox(
        width: _viewport.width,
        height: _viewport.height,
        child: CanvasStage(key: key, controller: c))));
    await tester.pumpAndSettle();
    return (c, key.currentState!);
  }

  double scaleOf(CanvasStageState s, CanvasController c) =>
      s.pageRect.width / c.document.size.width;

  group("on a line, the words have no box", () {
    testWidgets("so a piece is neither drawn nor pressed", (tester) async {
      // The piece's place in the box is nowhere on the page while the words
      // ride the line: a click there found it all the same, and took the text.
      const text = TextElement(
        ElementBase(id: "t", x: 200, y: 50, width: 800, height: 300),
        text: "Caption",
        curve: TextOnCurve(elementId: "l"),
        items: [
          TextItem(
              id: "note",
              text: "NOTE",
              slot: TextSlot.topLeft,
              spec: TextSpec(fontSize: 60)),
        ],
      );
      var (c, s) = await pump(
          tester, const CanvasDocument().addElement(_line).addElement(text));
      var where = textItemRects(text, text.bounds).single.center;
      await tester.tapAt(s.toStagePoint(where));
      await tester.pumpAndSettle();
      expect(c.selection, isEmpty,
          reason: "nothing is drawn there, so nothing is pressed");
    });

    testWidgets("and the type is not fitted to it", (tester) async {
      // Fit to box sizes the type to the text's own box, which a line does
      // not have: the line draws it at its own size, and the editor opened
      // over it showed it at the fitted one.
      const text = TextElement(
        ElementBase(id: "t", x: 0, y: 0, width: 600, height: 300),
        text: "Hi",
        textSpec: TextSpec(fontSize: 30),
        autoSize: true,
        curve: TextOnCurve(elementId: "l"),
      );
      var (c, s) = await pump(
          tester, const CanvasDocument().addElement(_line).addElement(text));
      var on = s.toStagePoint(const Offset(260, 603));
      await tester.tapAt(on);
      await tester.pumpAndSettle();
      expect(c.selection, {"t"});
      await tester.tapAt(on);
      await tester.pumpAndSettle();
      var field = tester.widget<TextField>(find.descendant(
          of: find.byType(CanvasTextEditor), matching: find.byType(TextField)));
      expect(field.style!.fontSize, closeTo(30 * scaleOf(s, c), 0.01),
          reason: "the size the line draws it at");
    });

    test("and they are in no chain of boxes", () {
      // A line draws all its words; a box after it drew the ones that
      // would not have fitted its box as well, so they showed twice.
      const head = TextElement(
        ElementBase(id: "a", x: 0, y: 0, width: 100, height: 40),
        text: "one two three four five six seven eight nine ten eleven",
        curve: TextOnCurve(elementId: "l"),
        flowTo: "b",
      );
      const next = TextElement(
          ElementBase(id: "b", x: 400, y: 0, width: 600, height: 400),
          text: "Its own");
      var doc = const CanvasDocument()
          .addElement(_line)
          .addElement(head)
          .addElement(next);
      var flow = flowFor(next, doc, next.box.inner(next.bounds), next.textSpec);
      expect(flow.text, "Its own", reason: "the line's words are all its own");
      expect(flow.receiving, isFalse);

      // Nor is one flowed into: it draws its own words along its line, so
      // they are its own to type into.
      var into = const TextElement(
          ElementBase(id: "b", x: 400, y: 0, width: 600, height: 400),
          text: "Riding",
          curve: TextOnCurve(elementId: "l"));
      var box = head.copyWith(clearCurve: true);
      doc = const CanvasDocument()
          .addElement(_line)
          .addElement(box)
          .addElement(into);
      expect(flowSourceOf(into, doc), isNull);
    });
  });

  group("a line not on the page leaves the words in their box", () {
    // Pasted onto a page without the line it rode, a text keeps the line's
    // id, ready for its return, and is drawn in its own box meanwhile: then
    // its box must be what it is everywhere.
    const away = TextOnCurve(elementId: "gone");

    testWidgets("whose slot holds them", (tester) async {
      const text = TextElement(
        ElementBase(id: "t", x: 100, y: 100, width: 800, height: 400),
        text: "WORDS",
        textSpec: TextSpec(fontSize: 40, color: Color(0xFFFF0000)),
        slot: TextSlot.bottomRight,
        curve: away,
      );
      var doc = const CanvasDocument().addElement(text);
      var recorder = ui.PictureRecorder();
      paintCanvasDocument(ui.Canvas(recorder), doc, frame: 0);
      var picture = recorder.endRecording();
      var image = (await tester.runAsync(() =>
          picture.toImage(doc.size.width.round(), doc.size.height.round())))!;
      var bytes = (await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
      // The ink's middle: where the words are.
      var sum = Offset.zero;
      var n = 0;
      for (var y = 100; y < 500; y++) {
        for (var x = 100; x < 900; x++) {
          var i = (y * image.width + x) * 4;
          if (bytes.getUint8(i) > 200 && bytes.getUint8(i + 1) < 60) {
            sum += Offset(x.toDouble(), y.toDouble());
            n++;
          }
        }
      }
      image.dispose();
      picture.dispose();
      expect(n, greaterThan(0));
      var middle = sum / n.toDouble();
      // Set in the middle of the box (the type's own alignment) when the
      // slot was passed over.
      expect(middle.dx, greaterThan(text.bounds.center.dx + 100),
          reason: "held to the right, as the slot says");
      expect(middle.dy, greaterThan(text.bounds.center.dy + 100),
          reason: "and to the bottom");
    });

    testWidgets("whose picture piece is handled by its own box",
        (tester) async {
      const text = TextElement(
        ElementBase(id: "t", x: 200, y: 200, width: 800, height: 400),
        text: "Words",
        box: BoxSpec(padding: 20),
        curve: away,
        items: [
          TextItem(
              id: "pic",
              slot: TextSlot.topRight,
              icon: TextIcon(assetId: "asset1", size: 100)),
        ],
      );
      var (c, s) = await pump(tester, const CanvasDocument().addElement(text));
      c.selectOnly("t");
      c.pickTextLayer("t", "pic");
      await tester.pumpAndSettle();
      TextElement now() => c.document.elementById("t") as TextElement;
      var from = textItemRects(now(), now().bounds).single.center;
      var g = await tester.startGesture(s.toStagePoint(from),
          buttons: kPrimaryButton, kind: PointerDeviceKind.mouse);
      await tester.pump();
      await g.moveBy(const Offset(-30, 20) * scaleOf(s, c));
      await tester.pump();
      await g.moveBy(const Offset(-30, 20) * scaleOf(s, c));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      var moved = textItemRects(now(), now().bounds).single.center - from;
      expect(moved, offsetMoreOrLessEquals(const Offset(-60, 40), epsilon: 1),
          reason: "the picture went with the pointer");
      expect(now().bounds, text.bounds, reason: "the text stayed put");
    });
  });
}
