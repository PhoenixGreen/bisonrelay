import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_new_scene_background_test.dart is what is behind a canvas nobody has
// put anything behind yet.
//
// Reported: a new scene arrived wearing a background from earlier in the
// document's life -- one the reader had since changed away from, with nothing
// on screen to explain it. A scene with no backdrop of its own falls back to
// the document's, and the document's is whatever the background was while
// there was only one canvas to put it on. So the fallback was doing exactly
// what it says, and what it says is wrong for a canvas that is meant to be
// empty.

void main() {
  /// _busy is a document whose own background is something nobody would
  /// mistake for empty.
  CanvasDocument busy() => const CanvasDocument(
        background: CanvasBackground(
          spec: ProceduralSpec(
            style: ProceduralStyle.dotGrid,
            background: Color(0xFF204060),
          ),
        ),
      );

  test("a new scene is plain, whatever the document is wearing", () {
    var document = busy().addScene();
    var made = document.allScenes[document.at];
    expect(made.background, isNotNull,
        reason: "its own, so it cannot fall back to the document's");
    expect(made.background!.spec.style, ProceduralStyle.plain);
    expect(
        document.backgroundOf(document.at).spec.style, ProceduralStyle.plain);
  });

  test("and so is the one after that", () {
    var document = busy().addScene().addScene();
    expect(document.allScenes.length, greaterThanOrEqualTo(2));
    for (var i = 1; i < document.allScenes.length; i++) {
      expect(document.backgroundOf(i).spec.style, ProceduralStyle.plain,
          reason: "scene ${i + 1}");
    }
  });

  test("the canvas that was already there keeps what it had", () {
    // Adding a scene must not change how anything already on screen looks.
    var before = busy();
    var was = before.backgroundOf(0);
    var after = before.addScene();
    expect(after.backgroundOf(0), was);
  });

  test("and takes a copy of it, so it stops being a fallback", () {
    // The document's own background is what a scene with none falls back to,
    // and it is whatever the backdrop was while there was one canvas. Handed
    // to the canvases that were relying on it, it stops reaching forward to
    // every scene added afterwards.
    var after = busy().addScene();
    expect(after.allScenes.first.background, isNotNull);
    expect(
        after.allScenes.first.background!.spec.style, ProceduralStyle.dotGrid);

    // Which is the whole point: the next one is plain too.
    var third = after.addScene();
    expect(third.backgroundOf(third.at).spec.style, ProceduralStyle.plain);
  });

  test("a copy of a scene still copies its background", () {
    // Duplicate is not new: it is this canvas again.
    var document = busy().addScene();
    var painted = document.withScene(
        document.at,
        document.allScenes[document.at].copyWith(
            background: const CanvasBackground(
                spec: ProceduralSpec(style: ProceduralStyle.hexGrid))));
    var copied = painted.duplicateScene(painted.at);
    expect(copied.backgroundOf(copied.at).spec.style, ProceduralStyle.hexGrid);
  });

  test("the shared canvas still covers a new scene", () {
    // A backdrop on the master is drawn in front of every scene's, and that
    // is what the master is for -- giving a new scene its own must not stop
    // it.
    var document = busy().addScene().copyWith(masterOn: true);
    document = document.withMaster(
      (document.master ?? CanvasScene(id: newSceneId(), name: "Master"))
          .copyWith(
              background: const CanvasBackground(
                  spec: ProceduralSpec(style: ProceduralStyle.contours))),
    );
    expect(document.backgroundOf(document.at).spec.style,
        ProceduralStyle.contours);
  });
}
