import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_publish_scenes_test.dart is publishing part of a document rather
// than all of it.
//
// The choice is made once, in the sheet, and comes out as a shorter document
// -- see CanvasDocument.scenesFrom. Nothing downstream learns a new argument:
// the GIF, the video, the PDF, the estimate and the bundle all ask the
// document how long it runs for and what is on it at a given moment, and a
// four-scene document answers for four scenes.

void main() {
  /// _five is a document of five scenes, two frames each, named so a trimmed
  /// one can be told apart from the whole.
  CanvasDocument five() {
    var document = const CanvasDocument(frames: 2);
    for (var i = 1; i < 5; i++) {
      document = document.addScene(name: "Scene ${i + 1}");
    }
    return document.withScenes([
      for (var i = 0; i < document.allScenes.length; i++)
        document.allScenes[i].copyWith(name: "Scene ${i + 1}", frames: 2),
    ], at: 0);
  }

  test("five scenes to start with", () {
    expect(five().allScenes.length, 5);
    expect(five().hasScenes, isTrue);
  });

  test("all of them is the document itself", () {
    var document = five();
    expect(identical(document.scenesFrom(0, 4), document), isTrue,
        reason: "no copy, so publishing everything is exactly what it was");
  });

  test("one scene is a document of that scene", () {
    var only = five().scenesFrom(2, 2);
    expect(only.allScenes.length, 1);
    expect(only.allScenes.single.name, "Scene 3");
    expect(only.at, 0);
  });

  test("a range is the scenes between, in order", () {
    var some = five().scenesFrom(1, 3);
    expect(
        some.allScenes.map((s) => s.name), ["Scene 2", "Scene 3", "Scene 4"]);
  });

  test("and it runs for as long as those scenes do", () {
    // What the GIF and the video actually walk. A range of three two-frame
    // scenes is six frames, not the whole document's ten.
    var whole = five();
    var some = whole.scenesFrom(1, 3);
    expect(some.playFrames, lessThan(whole.playFrames));
    expect(some.playFrames, whole.startOfScene(4) - whole.startOfScene(1));
  });

  test("the document's own settings come with it", () {
    // The size, the frame rate, the guides and the shared canvas belong to
    // the document and not to any scene.
    var whole = five()
        .copyWith(frameRate: 24, masterOn: true)
        .withMaster(CanvasScene(id: newSceneId(), name: "Master"));
    var some = whole.scenesFrom(1, 2);
    expect(some.frameRate, 24);
    expect(some.size, whole.size);
    expect(some.masterOn, isTrue);
    expect(some.master?.name, "Master");
  });

  test("an upside-down or out-of-range pair still answers with scenes", () {
    // The sheet keeps the two in order, but nothing downstream should depend
    // on that: a document with no scenes in it is not a document.
    var document = five();
    expect(document.scenesFrom(3, 1).allScenes.length, 1);
    expect(document.scenesFrom(-4, 99).allScenes.length, 5);
    expect(document.scenesFrom(9, 9).allScenes.length, 1);
  });
}
