import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/space_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_timeline_any_scene_test.dart is a clip on the timeline being
// handled wherever it is, while every scene plays.
//
// With Play all scenes on, the timeline shows every scene's sounds at their
// places in the run. They could be seen and picked from any scene, but only
// the open scene's could be deleted, and a clip dragged towards the next
// scene stopped at the end of its own -- so editing one meant first working
// out which scene it was on.

AudioElement _clip(String id, int at, {String channel = "sfx"}) =>
    AudioElement(ElementBase(id: id, visible: false),
        clip: MediaClip(
            timed: true,
            at: at,
            channel: channel,
            channelName: "Effects",
            playlist: const [
              MediaSource(assetId: "click.mp3", name: "click", length: 1)
            ]));

/// _run is two scenes of 100 frames, a clip on each and one on the master,
/// open on the first scene with every scene playing.
CanvasController _run() {
  var c = CanvasController(CanvasDocument(
    frameRate: 24,
    master: CanvasScene(id: "m", elements: [_clip("m1", 5, channel: "bed")]),
    masterOn: true,
  ).withScenes([
    CanvasScene(id: "a", frames: 100, elements: [_clip("a1", 10)]),
    CanvasScene(id: "b", frames: 100, elements: [_clip("b1", 20)]),
  ]));
  c.playAll = true;
  return c;
}

/// _where is the scene each clip is on, -1 for the master, null for gone.
int? _where(CanvasController c, String id) {
  if (c.document.master!.elements.any((e) => e.id == id)) return -1;
  for (var (i, s) in c.document.allScenes.indexed) {
    if (s.elements.any((e) => e.id == id)) return i;
  }
  return null;
}

int _at(CanvasController c, String id) {
  for (var s in [...c.document.allScenes, c.document.master!]) {
    for (var e in s.elements) {
      if (e.id == id) return (e as AudioElement).clip.at;
    }
  }
  throw StateError("no $id");
}

void main() {
  test("every scene's clips are on the timeline to be picked", () {
    var c = _run();
    addTearDown(c.dispose);
    var ids = {for (var l in c.timedLanes) l.element.id};
    expect(ids, containsAll(["a1", "b1", "m1"]));
  });

  test("a clip picked from another scene is deleted", () {
    var c = _run();
    addTearDown(c.dispose);
    c.pickClip("b1");
    c.deleteSelected();
    expect(_where(c, "b1"), isNull);
    expect(_where(c, "a1"), 0, reason: "this scene's is left alone");
  });

  test("and several at once, from every canvas, as one change", () {
    var c = _run();
    addTearDown(c.dispose);
    c.pickClips({"a1", "b1", "m1"});
    c.deleteSelected();
    expect([_where(c, "a1"), _where(c, "b1"), _where(c, "m1")],
        [null, null, null]);
    c.undo();
    expect([_where(c, "a1"), _where(c, "b1"), _where(c, "m1")], [0, 1, -1]);
  });

  test("cut takes it too, and the copy lands on the scene the playhead is in",
      () {
    var c = _run();
    addTearDown(c.dispose);
    c.pickClip("b1");
    c.cutSelected();
    expect(_where(c, "b1"), isNull);
    // Sent back to its own scene at the playhead, it was past that scene's
    // end and never played; it comes where it is wanted.
    c.frame = 30;
    c.paste();
    var pasted =
        c.document.allScenes[0].elements.whereType<AudioElement>().toList();
    expect(pasted.length, 2, reason: "the first scene's own, and the copy");
    expect(pasted.last.clip.at, 30);
  });

  test("dragged past the end of its scene, a clip goes into the next", () {
    var c = _run();
    addTearDown(c.dispose);
    c.pickClip("a1");
    var a1 = c.document.allScenes[0].elements.single as AudioElement;
    expect(c.clipRunStart("a1"), 10);
    c.placeTimedClip(a1, a1.clip, 150);
    expect(_where(c, "a1"), 1, reason: "frame 150 of the run is scene two's");
    expect(_at(c, "a1"), 50);
    expect(c.clipSelection, contains("a1"), reason: "still picked");
    expect(c.clipRunStart("a1"), 150);

    // And back again.
    var moved = c.document.allScenes[1].elements
        .firstWhere((e) => e.id == "a1") as AudioElement;
    c.placeTimedClip(moved, moved.clip, 40);
    expect(_where(c, "a1"), 0);
    expect(_at(c, "a1"), 40);
    expect(c.selection, contains("a1"), reason: "on this canvas again");
  });

  test("the master's goes where it is put, on the run's clock", () {
    var c = _run();
    addTearDown(c.dispose);
    var m1 = c.document.master!.elements.single as AudioElement;
    c.placeTimedClip(m1, m1.clip, 170);
    expect(_where(c, "m1"), -1);
    expect(_at(c, "m1"), 170);
  });

  testWidgets("the Delete key deletes a clip picked from another scene",
      (tester) async {
    var c = _run();
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(
        home: CanvasSpaceBar(
            controller: c,
            child: const Focus(autofocus: true, child: SizedBox.expand()))));
    await tester.pump();
    c.pickClip("b1");
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(_where(c, "b1"), isNull);
  });
}
