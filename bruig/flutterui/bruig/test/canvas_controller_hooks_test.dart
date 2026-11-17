import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/render/sheet_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/vector_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/canvas_audio_fake.dart';

// canvas_controller_hooks_test.dart is the painters' hooks a controller puts
// up (vectorSoloOf, sheetMarksOf) coming down again: when what they answer
// for ends, and when the controller goes.
//
// They are set to a method of one of the controller's extensions, and such
// a method torn off is a new closure each time, never equal to the one put
// up. Compared that way, the hook was never recognised as this controller's,
// and stayed: a sheet painted after it was marked from a controller already
// gone.

void main() {
  tearDown(() {
    vectorSoloOf = null;
    sheetMarksOf = null;
  });

  test("a drawing's Solo takes its hook down when turned off", () {
    var c = CanvasController(const CanvasDocument());
    addTearDown(c.dispose);
    c.vectorSolo = true;
    expect(vectorSoloOf, isNotNull);
    c.vectorSolo = false;
    expect(vectorSoloOf, isNull);
  });

  test("and a controller that goes takes its hooks with it", () {
    var piano = newInstrument(const CanvasDocument());
    var sheet = SheetElement(const ElementBase(id: "sheet"), follows: piano.id);
    var c = CanvasController(
        CanvasDocument(frames: 240, frameRate: 24, elements: [piano, sheet]),
        audioEngine: FakeEngine({}));
    c.vectorSolo = true;
    c.startPractice(sheet);
    expect(vectorSoloOf, isNotNull);
    expect(sheetMarksOf, isNotNull);
    c.dispose();
    expect(vectorSoloOf, isNull);
    expect(sheetMarksOf, isNull);
  });
}
