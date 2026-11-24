import 'dart:io';

import 'support/canvas_app.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_text_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_text_editor_scale_test.dart is the typing field over a paragraph
// keeping to the words the canvas draws when the app's text is made larger
// (Ken, 2026-11-24: in Absolute Beginners Piano, a double-click on "under"
// lit "bers und", a line low). The canvas draws its words at their own size
// whatever the reader's text setting; the field took the setting, so its
// words were larger than the ones drawn and drifted off them down the
// paragraph. In a real typeface, the page zoomed out.

const _words = "Each lesson is one page: a little to read, a short piece of "
    "music, and a piano under it. Press on the music's bar to hear it -- each "
    "key lights as it plays, the right hand's in amber and the left hand's "
    "in teal. The numbers under the notes are which finger to use (thumb 1 "
    "to little finger 5), or the beats to count.";

const _spec = TextSpec(
    fontFamily: "Inter",
    fontSize: 24,
    weight: 500,
    lineHeight: 1.55,
    align: TextAlignSpec.left,
    verticalAlign: VerticalAlignSpec.top);

void main() {
  setUpAll(() async {
    var inter = FontLoader("Inter")
      ..addFont(File("assets/fonts/Inter-V.ttf")
          .readAsBytes()
          .then((b) => ByteData.view(Uint8List.fromList(b).buffer)));
    await inter.load();
  });

  testWidgets("a double-click picks the word drawn under it, text made larger",
      (tester) async {
    const e = TextElement(
      ElementBase(id: "t", x: 80, y: 100, width: 1080, height: 400),
      text: _words,
      textSpec: _spec,
      box: BoxSpec(padding: 0, padL: 40, padR: 40, padT: 40),
    );
    var controller = CanvasController(const CanvasDocument().addElement(e));
    addTearDown(controller.dispose);
    var key = GlobalKey<CanvasStageState>();
    // A window narrower than the page: the page drawn at about half size.
    const viewport = Size(700, 600);
    setTestScreen(tester, viewport);
    // The app's text made larger, as Ken has it.
    await tester.pumpWidget(canvasApp(MediaQuery(
        data: const MediaQueryData(
            size: viewport, textScaler: TextScaler.linear(1.25)),
        child: SizedBox(
            width: viewport.width,
            height: viewport.height,
            child: CanvasStage(key: key, controller: controller)))));
    await tester.pumpAndSettle();
    var stage = key.currentState!;
    var scale = stage.pageRect.width / controller.document.size.width;
    expect(scale, lessThan(0.7), reason: "zoomed out, small type on screen");

    // Where the canvas draws the second "under": laid out at the document's
    // size, as the painter lays it out.
    var painter = TextPainter(
        text: TextSpan(text: _words, style: textStyleOf(_spec)),
        textDirection: TextDirection.ltr)
      ..layout(maxWidth: 1000);
    var at = _words.indexOf("under", _words.indexOf("numbers"));
    var box = painter
        .getBoxesForSelection(
            TextSelection(baseOffset: at, extentOffset: at + 5))
        .first;
    Offset onPage(Offset d) => stage.pageRect.topLeft + d * scale;
    var word = onPage(Offset(80 + 40 + (box.left + box.right) / 2,
        100 + 40 + (box.top + box.bottom) / 2));

    // Opened with a double-click (select, then type), then a double-click
    // on the word.
    await tester.tapAt(word);
    await tester.pumpAndSettle();
    await tester.tapAt(word);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    for (var i = 0; i < 2; i++) {
      var g = await tester.startGesture(word, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 30));
      await g.up();
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pump(const Duration(milliseconds: 500));
    var field = tester.widget<TextField>(find.descendant(
        of: find.byType(CanvasTextEditor), matching: find.byType(TextField)));
    var sel = field.controller!.selection;
    expect(sel.textInside(_words), "under");
    painter.dispose();
  });
}
