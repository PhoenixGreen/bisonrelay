import 'dart:io';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_leaving_saves_test.dart is what happens to unsaved work when
// somebody opens a different canvas.
//
// A saved canvas writes itself out three seconds after the editing stops, so
// the only way to be asked about it was to move between canvases inside those
// three seconds -- which is exactly what somebody arranging a document does
// all afternoon. Asking then is asking whether to throw away work nobody
// meant to throw away.

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp("canvas_leaving");
    CanvasStorage.rootOverride = root.path;
  });

  tearDown(() async {
    CanvasStorage.rootOverride = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  CanvasController editing(CanvasDocument document) {
    var controller = CanvasController(document);
    addTearDown(controller.dispose);
    return controller;
  }

  CanvasDocument withShape(String id) => CanvasDocument(
        title: "Funding Models",
        elements: [ShapeElement(ElementBase(id: id, width: 10, height: 10))],
      );

  test("a canvas with a file of its own is saved, not asked about", () async {
    // What CanvasScreen._confirmDiscard does: save where there is somewhere
    // to save to, and only ask where there is not.
    await CanvasStorage.save("", "Funding Models", withShape("a"));

    var controller = editing(withShape("a"));
    controller.name = "Funding Models";
    controller.folder = "";

    // An edit, and no waiting for the autosave.
    controller.replaceElement(
        ShapeElement(const ElementBase(id: "a", width: 99, height: 10)));
    expect(controller.dirty, isTrue);

    expect(await controller.save(), isTrue);
    expect(controller.dirty, isFalse, reason: "nothing left to ask about");

    var back = await CanvasStorage.load("", "Funding Models");
    expect((back!.elements.single as ShapeElement).width, 99,
        reason: "and the edit is the thing on disk");
  });

  test("one that has never been saved has nowhere to put it", () async {
    // Which is the case still worth a question: walking away really does
    // lose it.
    var controller = editing(withShape("a"));
    expect(controller.name, isNull);

    controller.replaceElement(
        ShapeElement(const ElementBase(id: "a", width: 99, height: 10)));
    expect(controller.dirty, isTrue);
    expect(await controller.save(), isFalse,
        reason: "no file, so no save, so the question is the only option");
    expect(controller.dirty, isTrue);
  });

  test("and a canvas nobody has touched is not saved on the way out", () async {
    await CanvasStorage.save("", "Funding Models", withShape("a"));
    var controller = editing(withShape("a"));
    controller.name = "Funding Models";
    controller.folder = "";
    expect(controller.dirty, isFalse,
        reason: "there is nothing to write, and nothing to ask");
  });
}
