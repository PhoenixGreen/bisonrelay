import 'dart:io';
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/responsive_layout.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:flutter_test/flutter_test.dart';

// What a canvas keeps through a save and a reopen, and what a canvas sent
// by someone else cannot do to the one who opens it.

CanvasDocument again(CanvasDocument d) => CanvasDocument.decode(d.encode())!;

/// box is a plain element [id] with [motion].
ShapeElement box(String id, [ElementMotion motion = ElementMotion.none]) =>
    ShapeElement(ElementBase(id: id, width: 100, height: 100, motion: motion));

/// arriving is [id] with one arrival clip placed at [at] seconds.
ShapeElement arriving(String id, {double at = 0}) => box(
    id,
    ElementMotion(
      clips: [MotionClip.ofKind("$id-c", MotionKind.arrive, length: 1)],
      placed: [ClipPlacement(id: "$id-p", clip: "$id-c", start: at)],
    ));

void main() {
  group("saved and opened again", () {
    test("one scene keeps its own camera", () {
      var c = CanvasController(CanvasDocument(elements: [box("a")]));
      addTearDown(c.dispose);
      c.setSceneCamera(0, const SceneCamera(toZoom: 1.5));
      expect(again(c.document).scene.camera?.toZoom, 1.5);
    });

    test("rulers switched off stay off", () {
      var d = const CanvasDocument(guides: CanvasGuides(showRulers: false));
      expect(again(d).guides.showRulers, isFalse);
    });

    test("an element's design kept for a page shape holds no earlier ones", () {
      const seed = ShapeSeed(
          by: 1,
          block: Rect.fromLTWH(0, 0, 100, 100),
          at: Offset.zero,
          page: Size(400, 400));
      CanvasElement e = detachedHere(box("a"));
      // Back and forth between two shapes, keeping its own design in each.
      for (var i = 0; i < 6; i++) {
        e = movedTo(e, i.isEven ? "wide" : "tall", i.isEven ? "tall" : "wide",
            seed: seed, covers: false);
        e = detachedHere(e);
      }
      bool nested(Object? json, int depth) => switch (json) {
            Map m => (depth > 0 && m.containsKey("layouts")) ||
                m.values.any((v) => nested(v, depth + 1)),
            List l => l.any((v) => nested(v, depth + 1)),
            _ => false,
          };
      expect(nested(e.toJson(), 0), isFalse);
    });
  });

  group("sent by somebody else", () {
    test("numbers no field can hold do not lose the canvas", () {
      var text = '{"version": 1, "frames": 1e999, "elements": ['
          '{"kind": "shape", "id": "a", "x": 1e999, "w": -1e999, '
          '"rotation": 1e999}]}';
      var d = CanvasDocument.decode(text)!;
      expect(d.elements.single.x, 0);
      expect(() => d.encode(), returnsNormally);
    });

    test("a field of the wrong type is read as missing", () {
      var d = CanvasDocument.decode('{"version": 1, "size": {"ratio": 5}, '
          '"elements": [{"kind": "shape", "id": "a", "name": 7}]}');
      expect(d, isNotNull);
      expect(d!.elements.single.id, "a");
    });

    test("on the master with no master is on the scene", () {
      var d = CanvasDocument.decode('{"version": 1, "onMaster": true, '
          '"elements": []}')!;
      expect(d.editingMaster, isFalse);
      var edited = d.addElement(box("a"));
      expect(edited.elements.map((e) => e.id), ["a"]);
    });
  });

  group("clips", () {
    test("a copy's placements are its own, pins and all", () {
      var m = const ElementMotion(
        clips: [MotionClip(id: "c")],
        placed: [
          ClipPlacement(id: "p0", clip: "c"),
          ClipPlacement(
              id: "p1",
              clip: "c",
              startPin: ClipPin(PinKind.after, target: "p0")),
        ],
      );
      var copy = box("a", m).withId("b");
      var placed = copy.base.motion.placed;
      expect(placed.map((p) => p.id), ["b-p0", "b-p1"]);
      expect(placed[1].startPin?.target, "b-p0");
    });

    test("moving a word cue moves the clips tied to it", () {
      var c = CanvasController(CanvasDocument(
          frames: 240, frameRate: 24, elements: [arriving("a", at: 1)]));
      addTearDown(c.dispose);
      var cue = c.addCue(frame: 24);
      c.cueTo("a", cue.id);
      expect(c.document.elementById("a")!.base.motion.placed.single.start, 1);
      c.moveCue(cue.id, 48);
      expect(c.document.elementById("a")!.base.motion.placed.single.start,
          closeTo(2, 1e-9));
    });

    test("a pin to a marker follows the marker", () {
      var c = CanvasController(
          CanvasDocument(frames: 240, frameRate: 24, elements: [box("a")]));
      addTearDown(c.dispose);
      c.setMotion("a", const ElementMotion(clips: [MotionClip(id: "c")]));
      var p = c.placeClip("a", "c", seconds: 0);
      var marker = c.addMarker(24);
      c.pinPlacement("a", p, ClipPin(PinKind.marker, target: marker));
      expect(motionTimesOf(c.document).span(p)!.start, 1);
      c.apply(c.document.copyWith(actions: [
        for (var a in c.document.actions) a.copyWith(frame: 48),
      ]));
      expect(motionTimesOf(c.document).span(p)!.start, 2,
          reason: "the same elements, a different marker");
    });

    test("the master's clips are timed under a scene", () {
      var d = CanvasDocument(
        scenes: [
          CanvasScene(id: "s", frames: 48, elements: [box("a")]),
        ],
        master: CanvasScene(id: "m", elements: [arriving("w")]),
        masterOn: true,
      );
      expect(motionTimesOf(d).span("w-p"), isNotNull);
    });

    test("a canvas opens with its arrival clips played", () {
      var c = CanvasController(const CanvasDocument());
      addTearDown(c.dispose);
      c.load(CanvasDocument(
          frames: 240, frameRate: 24, elements: [arriving("a", at: 2)]));
      expect(c.frame, 72, reason: "two seconds in, and one to arrive");
    });

    test("Delete with a placed clip picked takes only that placing", () {
      var c = CanvasController(CanvasDocument(elements: [arriving("a")]));
      addTearDown(c.dispose);
      c.pickMotion("a", "a-c", placement: "a-p");
      c.deleteSelected();
      var a = c.document.elementById("a");
      expect(a, isNotNull, reason: "the element stays");
      expect(a!.base.motion.placed, isEmpty);
      expect(a.base.motion.clips, hasLength(1), reason: "and so does its clip");
    });
  });

  test("an edit made while saving is still to be saved", () async {
    var root = await Directory.systemTemp.createTemp("canvas_keeping");
    CanvasStorage.rootOverride = root.path;
    addTearDown(() async {
      CanvasStorage.rootOverride = null;
      await root.delete(recursive: true);
    });
    var c = CanvasController(CanvasDocument(elements: [box("a")]));
    addTearDown(c.dispose);
    c.name = "Saving";
    c.apply(c.document.addElement(box("b")));
    var saving = c.save();
    c.apply(c.document.addElement(box("c")));
    expect(await saving, isTrue);
    expect(c.dirty, isTrue, reason: "c was added after the save began");
  });

  test("a formation with nobody up the court still spreads its own half", () {
    for (var (x, y)
        in TeamFormation.tennisBack.spots(spread: FormationSpread.ownHalf)) {
      expect(x.isFinite && y.isFinite, isTrue);
    }
  });
}
