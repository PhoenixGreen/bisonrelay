import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_scenes_test.dart is a document that is more than one canvas.
//
// What is pinned here above all is that nothing changed for a document that
// is one canvas. Every panel in the editor asks a document for its elements,
// its length and its actions; a scene list has to answer those questions for
// the scene being edited without any of those callers knowing there is a
// list. A document of one scene has to save exactly as it did, too, or every
// canvas already on disk is a canvas this build reads differently.

CanvasDocument _twoScenes() => const CanvasDocument().withScenes([
      CanvasScene(
        id: "a",
        name: "Opening",
        frames: 24,
        elements: [
          TextElement(ElementBase(id: "t1", width: 100, height: 40),
              text: "First"),
        ],
      ),
      CanvasScene(
        id: "b",
        frames: 36,
        elements: [
          ShapeElement(ElementBase(id: "s1", width: 100, height: 40)),
        ],
      ),
    ]);

void main() {
  group("a document of one canvas", () {
    test("is what it always was", () {
      var one = CanvasDocument(elements: [
        TextElement(const ElementBase(id: "t", width: 100, height: 40)),
      ], frames: 12);

      expect(one.hasScenes, isFalse);
      expect(one.elements.length, 1);
      expect(one.frames, 12);
      expect(one.allScenes.length, 1, reason: "one canvas is one scene");
    });

    test("and saves the way it always did", () {
      var one = CanvasDocument(elements: [
        TextElement(const ElementBase(id: "t", width: 100, height: 40)),
      ], frames: 12);
      var json = one.toJson();

      expect(json.containsKey("scenes"), isFalse,
          reason: "a canvas made here still opens in a build without scenes");
      expect((json["elements"] as List).length, 1);
      expect(json["frames"], 12);

      var back = CanvasDocument.fromJson(json);
      expect(back.elements.length, 1);
      expect(back.frames, 12);
      expect(back.hasScenes, isFalse);
    });
  });

  group("a document of several", () {
    test("answers for the scene being edited", () {
      // The whole trick: every caller goes on asking the document, and the
      // document answers for the canvas in front of the reader.
      var it = _twoScenes();
      expect(it.hasScenes, isTrue);
      expect(it.at, 0);
      expect(it.elements.single.id, "t1");
      expect(it.frames, 24);

      var later = it.goToScene(1);
      expect(later.at, 1);
      expect(later.elements.single.id, "s1");
      expect(later.frames, 36);
    });

    test("and an edit lands on that scene and no other", () {
      var it = _twoScenes().goToScene(1);
      var next = it.addElement(
          ShapeElement(const ElementBase(id: "s2", width: 10, height: 10)));

      expect(next.elements.length, 2, reason: "the scene being edited");
      expect(next.allScenes.first.elements.length, 1,
          reason: "and not the one before it");
      expect(next.allScenes.first.elements.single.id, "t1");
    });

    test("a length belongs to its own scene", () {
      var it = _twoScenes();
      var longer = it.copyWith(frames: 60);
      expect(longer.frames, 60);
      expect(longer.allScenes[1].frames, 36,
          reason: "the other scene keeps its own length");
    });
  });

  group("arranging them", () {
    test("adding one puts it after the one you were on", () {
      var it = _twoScenes().addScene(after: 0);
      expect(it.allScenes.length, 3);
      expect(it.at, 1, reason: "and goes to it");
      expect(it.allScenes[2].id, "b", reason: "the rest keep their order");
    });

    test("duplicating copies the elements under new ids", () {
      // Two scenes holding one element id would be one element in two places,
      // and editing it in one would edit it in the other.
      var it = _twoScenes().duplicateScene(0);
      expect(it.allScenes.length, 3);
      expect(it.allScenes[1].elements.single.id, isNot("t1"));
      expect((it.allScenes[1].elements.single as TextElement).text, "First");
      expect(it.allScenes[1].name, "Opening copy");
    });

    test("removing one leaves at least a canvas behind", () {
      var it = _twoScenes().removeScene(1);
      expect(it.allScenes.length, 1);
      expect(it.removeScene(0).allScenes.length, 1,
          reason: "a document with no canvas in it is not a document");
    });

    test("moving one changes the order they play in", () {
      var it = _twoScenes().moveScene(1, 0);
      expect([for (var s in it.allScenes) s.id], ["b", "a"]);
    });

    test("a scene says what it is called, or where it is", () {
      var it = _twoScenes();
      expect(it.allScenes[0].saysAt(0), "Opening");
      expect(it.allScenes[1].saysAt(1), "Scene 2");
    });
  });

  group("what happens at the end of one", () {
    test("the next one, unless it is told to hold", () {
      var it = _twoScenes();
      expect(it.allScenes.first.holds, isFalse);
      var held = it.withScene(0, it.allScenes.first.copyWith(holds: true));
      expect(held.allScenes.first.holds, isTrue);
    });

    test("and a cut, unless it has been given a transition", () {
      var it = _twoScenes();
      expect(it.transitionAfter(0).kind, SceneTransitionKind.cut);
      expect(it.allScenes.first.custom, isFalse);

      var faded = it.withScene(
          0,
          it.allScenes.first.copyWith(
              transition: const SceneTransition(
                  kind: SceneTransitionKind.fade, frames: 8)));
      expect(faded.transitionAfter(0).kind, SceneTransitionKind.fade);
      expect(faded.allScenes.first.custom, isTrue);
    });

    test("the master scene sets what the rest of them use", () {
      // A scene with none of its own follows the default, so changing the
      // default changes them -- which is what a default is for.
      var it = _twoScenes().withMaster(CanvasScene(
        id: "master",
        transition:
            const SceneTransition(kind: SceneTransitionKind.through, frames: 6),
      ));
      expect(it.defaultTransition.kind, SceneTransitionKind.through);
      expect(it.transitionAfter(0).kind, SceneTransitionKind.through,
          reason: "a scene with no transition of its own");
      expect(it.transitionAfter(1).frames, 6);
    });
  });

  group("the master canvas", () {
    test("is kept when it is switched off, not thrown away", () {
      var it = _twoScenes().withMaster(CanvasScene(
        id: "master",
        elements: [
          ShapeElement(const ElementBase(id: "logo", width: 40, height: 40)),
        ],
      ));
      expect(it.masterOn, isFalse, reason: "off until it is asked for");
      expect(it.masterScene, isNull, reason: "and not drawn while it is off");

      var on = it.copyWith(masterOn: true);
      expect(on.masterScene!.elements.single.id, "logo");

      var off = on.copyWith(masterOn: false);
      expect(off.masterScene, isNull);
      expect(off.master!.elements.single.id, "logo",
          reason: "switching it off is not the same as emptying it");
    });
  });

  group("the shared canvas's own backdrop", () {
    test("comes and goes with the master", () {
      // Written to the document's background instead, turning the master off
      // left every scene wearing it with nothing to say where it came from.
      var it = _twoScenes()
          .copyWith(
              background: const CanvasBackground(
                  spec: ProceduralSpec(style: ProceduralStyle.dotGrid)))
          .withMaster(CanvasScene(
            id: "master",
            background: const CanvasBackground(
                spec: ProceduralSpec(style: ProceduralStyle.flowWaves)),
          ));

      expect(it.drawnBackground.spec.style, ProceduralStyle.dotGrid,
          reason: "the master is off, so it is the document's");

      var on = it.copyWith(masterOn: true);
      expect(on.drawnBackground.spec.style, ProceduralStyle.flowWaves);

      var off = on.copyWith(masterOn: false);
      expect(off.drawnBackground.spec.style, ProceduralStyle.dotGrid,
          reason: "every scene gets its own back the moment it is switched "
              "off");
      expect(off.master!.background, isNotNull,
          reason: "and the shared one is kept, not thrown away");
    });

    test("and survives being saved", () {
      var it = _twoScenes().withMaster(CanvasScene(
        id: "master",
        background: const CanvasBackground(
            spec: ProceduralSpec(style: ProceduralStyle.flowWaves)),
      ));
      var back = CanvasDocument.fromJson(it.toJson());
      expect(back.master!.background!.spec.style, ProceduralStyle.flowWaves);
    });
  });

  group("a scene's own backdrop", () {
    test("belongs to that scene and not to the next one", () {
      // They share the document's until one of them is given a backdrop of
      // its own -- and writing that shared one is how changing scene one's
      // background changed scene two's.
      var it = _twoScenes().copyWith(
          background: const CanvasBackground(
              spec: ProceduralSpec(style: ProceduralStyle.plain)));

      var painted = it.withScene(
          0,
          it.allScenes.first.copyWith(
              background: const CanvasBackground(
                  spec: ProceduralSpec(style: ProceduralStyle.dotGrid))));

      expect(painted.backgroundOf(0).spec.style, ProceduralStyle.dotGrid);
      expect(painted.backgroundOf(1).spec.style, ProceduralStyle.plain,
          reason: "the other scene keeps the one it had");
      expect(painted.drawnBackground.spec.style, ProceduralStyle.dotGrid,
          reason: "and the canvas shows the scene being edited");
    });

    test("and one edit builds on the last, not on the document's", () {
      // The reported fault: a scene given a new colour went on reporting the
      // old one, because the panel showed the document's background while
      // writing to the scene's -- so every edit was built from the one
      // nobody was looking at, and the second undid the first.
      var it = _twoScenes().copyWith(
          background: const CanvasBackground(
              spec: ProceduralSpec(
                  style: ProceduralStyle.plain,
                  background: Color(0xFF0000FF))));

      // What the panel shows is what the canvas owns.
      expect(it.ownBackground.spec.background, const Color(0xFF0000FF));

      // A colour, then a style, the way somebody changes two things.
      var pink = it.withScene(
          0,
          it.scene.copyWith(
              background: it.ownBackground.copyWith(
                  spec: it.ownBackground.spec
                      .copyWith(background: const Color(0xFFFF69B4)))));
      expect(pink.ownBackground.spec.background, const Color(0xFFFF69B4));

      var dotted = pink.withScene(
          0,
          pink.scene.copyWith(
              background: pink.ownBackground.copyWith(
                  spec: pink.ownBackground.spec
                      .copyWith(style: ProceduralStyle.dotGrid))));
      expect(dotted.ownBackground.spec.style, ProceduralStyle.dotGrid);
      expect(dotted.ownBackground.spec.background, const Color(0xFFFF69B4),
          reason: "the colour set a moment ago is still there");
      expect(dotted.backgroundOf(1).spec.background, const Color(0xFF0000FF),
          reason: "and the other scene is untouched");
    });

    test("and the shared one wins while the master is on", () {
      var it = _twoScenes()
          .withScene(
              0,
              const CanvasScene(
                  id: "a",
                  background: CanvasBackground(
                      spec: ProceduralSpec(style: ProceduralStyle.dotGrid))))
          .withMaster(const CanvasScene(
            id: "master",
            background: CanvasBackground(
                spec: ProceduralSpec(style: ProceduralStyle.flowWaves)),
          ));

      expect(it.backgroundOf(0).spec.style, ProceduralStyle.dotGrid,
          reason: "the master is off");
      var on = it.copyWith(masterOn: true);
      expect(on.backgroundOf(0).spec.style, ProceduralStyle.flowWaves,
          reason: "the shared canvas is the backdrop while it is on");
      expect(on.copyWith(masterOn: false).backgroundOf(0).spec.style,
          ProceduralStyle.dotGrid,
          reason: "and the scene's own comes back when it goes");
    });
  });

  group("the shared backdrop can be switched off", () {
    test("leaving every scene its own, and keeping the shared one", () {
      // A master worth having is often one that carries a logo and a
      // transition and nothing else, and the scenes under it want their own
      // backdrops. Without this the only way to stop the master covering them
      // is to throw its background away.
      var it = _twoScenes()
          .withScene(
              0,
              const CanvasScene(
                  id: "a",
                  background: CanvasBackground(
                      spec: ProceduralSpec(style: ProceduralStyle.dotGrid))))
          .withMaster(const CanvasScene(
            id: "master",
            background: CanvasBackground(
                spec: ProceduralSpec(style: ProceduralStyle.flowWaves)),
          ))
          .copyWith(masterOn: true);

      expect(it.backgroundOf(0).spec.style, ProceduralStyle.flowWaves);

      var quiet = it.withMaster(it.master!.copyWith(backgroundOff: true));
      expect(quiet.backgroundOf(0).spec.style, ProceduralStyle.dotGrid,
          reason: "the scene's own shows through");
      expect(quiet.master!.background, isNotNull,
          reason: "and the shared one is kept, not thrown away");
      expect(quiet.masterOn, isTrue,
          reason: "the rest of the shared canvas is still there");

      var back = CanvasDocument.fromJson(quiet.toJson());
      expect(back.master!.backgroundOff, isTrue);
      expect(back.backgroundOf(0).spec.style, ProceduralStyle.dotGrid);
    });
  });

  group("saved and read back", () {
    test("scenes, their names, lengths and elements", () {
      var back = CanvasDocument.fromJson(_twoScenes().goToScene(1).toJson());
      expect(back.allScenes.length, 2);
      expect(back.allScenes[0].name, "Opening");
      expect(back.allScenes[0].frames, 24);
      expect(back.allScenes[1].elements.single.id, "s1");
      expect(back.at, 1, reason: "and which one was being worked on");
    });

    test("the master canvas and the default transition", () {
      var it = _twoScenes().withMaster(CanvasScene(
        id: "master",
        elements: [
          ShapeElement(const ElementBase(id: "logo", width: 40, height: 40)),
        ],
        transition: const SceneTransition(
            kind: SceneTransitionKind.wipeLeft, frames: 9, overlap: 4),
      ));
      var back = CanvasDocument.fromJson(it.copyWith(masterOn: true).toJson());

      expect(back.masterOn, isTrue);
      expect(back.master!.elements.single.id, "logo");
      expect(back.defaultTransition.kind, SceneTransitionKind.wipeLeft);
      expect(back.defaultTransition.frames, 9);
      expect(back.defaultTransition.overlap, 4);
    });

    test("and a single scene that has been named", () {
      // Naming the first scene of a document must not be what turns it into a
      // list of scenes, or a name would cost the old file format.
      var one = const CanvasDocument()
          .withScenes([const CanvasScene(id: "only", name: "Titles")]);
      var json = one.toJson();
      expect(json.containsKey("scenes"), isFalse);
      expect((json["scene"] as Map)["name"], "Titles");

      var back = CanvasDocument.fromJson(json);
      expect(back.allScenes.single.name, "Titles");
      expect(back.hasScenes, isFalse);
    });

    test("a file written before scenes existed opens as one scene", () {
      var old = {
        "version": 1,
        "title": "An older canvas",
        "frames": 30,
        "frameRate": 12,
        "elements": [
          {"kind": "shape", "id": "s", "x": 0, "y": 0, "w": 10, "h": 10},
        ],
      };
      var back = CanvasDocument.fromJson(old);
      expect(back.hasScenes, isFalse);
      expect(back.frames, 30);
      expect(back.elements.single.id, "s");
      expect(back.allScenes.single.frames, 30);
    });
  });

  group("a button that goes to a scene", () {
    test("finds it by id first, and by name after", () {
      var it = _twoScenes();
      expect(it.sceneIndexNamed("b"), 1);
      expect(it.sceneIndexNamed("Opening"), 0);
      expect(it.sceneIndexNamed("nothing like it"), -1);
    });
  });
}
