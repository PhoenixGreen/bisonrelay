import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Canvas, PictureRecorder, Rect, Offset, Size;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_gltf.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/model_math.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_painter.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/render/model/mannequin.dart';
import 'package:bruig/plugin_system/canvas/render/model/mesh_painter.dart';
import 'package:bruig/plugin_system/canvas/render/model/model_figure.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/character_puppet.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'canvas_model_fixture.dart';

// canvas_model_test.dart is a character's body in 3D: reading glTF, GLB and
// VRM files, posing a model's skeleton from the character's rig, its face
// shapes, the mannequin, and the settings that choose them.

/// _Models hands the painter one model, whatever is asked for.
class _Models implements CanvasImageSource, CanvasModelSource {
  final LoadedModel? model;
  _Models(this.model);
  @override
  LoadedModel? resolveModel(String id) => model;
  @override
  ui.Image? resolve(String assetId, BackgroundRemoval removal) => null;
  @override
  CanvasVector? resolveVector(String assetId) => null;
  @override
  resolveOutline(String a, BackgroundRemoval r) => null;
  @override
  bool get loading => false;
}

CharacterRig _rig(CharacterPose pose) => CharacterRig.of(
    characterCast.first.dna, pose, const Rect.fromLTWH(0, 0, 200, 400));

Future<List<int>> _pixels(void Function(Canvas) paint) async {
  var rec = PictureRecorder();
  paint(Canvas(rec));
  var img = await rec.endRecording().toImage(240, 440);
  return (await img.toByteData())!.buffer.asUint8List();
}

void main() {
  group("reading a file", () {
    test("a GLB's skeleton, mesh, skin and face shapes", () {
      var g = parseGltf(humanoidGlb());
      expect(g.nodes, hasLength(fixtureBoneCount + 1));
      expect(g.meshes.single.primitives.single.vertexCount, fixtureBoneCount * 8);
      expect(g.meshes.single.primitives.single.targets, hasLength(2));
      expect(g.skins.single.joints, hasLength(fixtureBoneCount));
      expect(g.vrm, isNull);
      expect(g.materials.single.color, [0.8, 0.5, 0.3, 1]);
      // Found by Mixamo's names, "mixamorig:" and all.
      expect(g.humanoid[HumanBone.hips], 0);
      expect(g.humanoid[HumanBone.leftUpperArm], 4);
      expect(g.humanoid[HumanBone.rightFoot], 15);
      // Face shapes found by their ARKit names.
      expect(g.expressions["happy"]!.single.target, 0);
      expect(g.expressions["aa"]!.single.target, 1);
      // A node knows its parent.
      expect(g.nodes[5].parent, 4);
    });

    test("a VRM's own humanoid and expressions", () {
      var g = parseGltf(humanoidGlb(vrm: true));
      expect(g.vrm, 1);
      expect(g.title, "Fixture");
      expect(g.nodes[4].name, "bone4", reason: "names that say nothing");
      expect(g.humanoid[HumanBone.leftUpperArm], 4);
      expect(g.humanoid[HumanBone.head], 3);
      expect(g.expressions["happy"]!.single, (mesh: 0, target: 0, weight: 1.0));
    });

    test("a .gltf with its data inside, and a node placed by a matrix", () {
      var json = {
        "asset": {"version": "2.0"},
        "nodes": [
          {
            "name": "Hips",
            // Moved by (1, 2, 3) and turned a quarter round y.
            "matrix": [0, 0, -1, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 2, 3, 1],
          }
        ],
        "buffers": [
          {"byteLength": 4, "uri": "data:application/octet-stream;base64,AAAAAA=="}
        ],
      };
      var g = parseGltf(Uint8List.fromList(utf8.encode(jsonEncode(json))));
      var n = g.nodes.single;
      expect(n.translation, [1, 2, 3]);
      var turned = n.rotation.rotate(const [1, 0, 0]);
      expect(turned[2], closeTo(-1, 1e-9));
      expect(g.humanoid[HumanBone.hips], 0);
    });

    test("what is not glTF is turned away", () {
      expect(() => parseGltf(Uint8List.fromList(utf8.encode("hello"))),
          throwsA(isA<GltfError>()));
      var outside = {
        "asset": {"version": "2.0"},
        "buffers": [
          {"byteLength": 4, "uri": "body.bin"}
        ],
      };
      expect(
          () => parseGltf(Uint8List.fromList(utf8.encode(jsonEncode(outside)))),
          throwsA(isA<GltfError>().having(
              (e) => e.message, "message", contains("single .glb"))));
    });
  });

  group("the 3D arithmetic", () {
    test("a turn from one direction to another, and back", () {
      var q = Quat.between(const [0, 1, 0], const [1, 0, 0]);
      var v = q.rotate(const [0, 1, 0]);
      expect(v[0], closeTo(1, 1e-9));
      expect(v[1], closeTo(0, 1e-9));
      var opposite = Quat.between(const [0, 1, 0], const [0, -1, 0]);
      expect(opposite.rotate(const [0, 1, 0])[1], closeTo(-1, 1e-9));
    });

    test("a matrix undone by its inverse", () {
      var m = Mat4.trs(const [1, 2, 3], Quat.between(const [0, 1, 0], const [1, 1, 0]),
          const [2, 2, 2]);
      var p = m.inverted().point(1, 2, 3);
      var back = m.point(p[0], p[1], p[2]);
      expect(back[0], closeTo(1, 1e-9));
      expect(back[1], closeTo(2, 1e-9));
      expect(back[2], closeTo(3, 1e-9));
    });
  });

  group("posing a model", () {
    late LoadedModel model;
    setUpAll(() async => model = await loadModel(humanoidGlb()));

    test("it stands in the box, as tall as it", () {
      var (origin, pieces) = model.pieces(
          _rig(CharacterElement.restPose),
          CharacterFace.rest,
          const Rect.fromLTWH(0, 0, 200, 400));
      expect(origin, const Offset(100, 400));
      var b = meshBounds(pieces, origin)!;
      expect(b.bottom, closeTo(400, 1));
      expect(b.top, closeTo(0, 400 * 0.05));
      expect(b.center.dx, closeTo(100, 10));
    });

    test("made standing in a T, its arms hang where the rig's do", () {
      var rest = _rig(CharacterElement.restPose);
      for (var hand in [HumanBone.leftHand, HumanBone.rightHand]) {
        var h = model.boneAt(rest, CharacterFace.rest, hand)!;
        var neck = model.boneAt(rest, CharacterFace.rest, HumanBone.neck)!;
        expect(h[1], lessThan(neck[1] - 0.4), reason: "$hand hangs down");
      }
    });

    test("the rig's left is the page's left, which is the model's right", () {
      var wave = _rig(posePresets[1].pose);
      var head = model.boneAt(wave, CharacterFace.rest, HumanBone.head)!;
      // The wave raises the arm on the page's right.
      var left = model.boneAt(wave, CharacterFace.rest, HumanBone.leftHand)!;
      var right = model.boneAt(wave, CharacterFace.rest, HumanBone.rightHand)!;
      expect(left[1], greaterThan(head[1]));
      expect(left[0], greaterThan(0));
      expect(right[1], lessThan(head[1]));
    });

    test("one made facing away is turned round first", () async {
      var back = await loadModel(humanoidGlb(facesBack: true));
      var wave = _rig(posePresets[1].pose);
      var a = model.boneAt(wave, CharacterFace.rest, HumanBone.leftHand)!;
      var b = back.boneAt(wave, CharacterFace.rest, HumanBone.leftHand)!;
      for (var k = 0; k < 3; k++) {
        expect(b[k], closeTo(a[k], 1e-6));
      }
    });

    test("a face moves its face shapes", () {
      var rig = _rig(CharacterElement.restPose);
      var box = const Rect.fromLTWH(0, 0, 200, 400);
      List<double> head(CharacterFace face) {
        var (_, pieces) = model.pieces(rig, face, box);
        return pieces.single.points.toList();
      }

      var plain = head(CharacterFace.rest);
      expect(head(expressionPresets[1].face), isNot(plain), reason: "a smile");
      expect(head(CharacterFace.rest.withMouth(MouthShape.wide)), isNot(plain),
          reason: "a mouth for speech");
      expect(head(CharacterFace.rest.withMouth(MouthShape.closed)), plain);
    });

    test("expressions are made from the face's controls and mouths", () {
      expect(expressionsOf(CharacterFace.rest), isEmpty);
      var happy = expressionsOf(expressionPresets[1].face);
      expect(happy["happy"], greaterThan(0.5));
      expect(expressionsOf(CharacterFace.rest.withMouth(MouthShape.pucker))["ou"], 1);
      expect(
          expressionsOf(CharacterFace.rest
              .withControl(FaceControl.eyesOpen, 0))["blink"],
          1);
    });

    test("turned with the body", () async {
      var src = _Models(model);
      Future<List<int>> draw(double turn) => _pixels((c) => paintCharacterFigure(
          c,
          const Rect.fromLTWH(20, 20, 200, 400),
          characterCast.first.dna,
          CharacterElement.restPose.withTurn(turn),
          body: const CharacterBody(kind: BodyKind.model, modelId: "m"),
          images: src));
      expect(await draw(0), isNot(await draw(90)));
    });
  });

  group("pins on a model", () {
    late LoadedModel model;
    setUpAll(() async => model = await loadModel(humanoidGlb()));

    CharacterElement who(CharacterPose pose) => CharacterElement(
        const ElementBase(id: "c", x: 100, y: 50, width: 160, height: 340),
        dna: characterCast.first.dna,
        pose: pose,
        life: CharacterLife.still,
        body: const CharacterBody(kind: BodyKind.model, modelId: "m"));

    test("sit on the model's joints, not the rig's", () {
      var e = who(CharacterElement.restPose);
      var drawn = CharacterPlacement.of(e, 0);
      var placed = CharacterPlacement.of(e, 0, models: _Models(model));
      expect(placed.model, isNotEmpty);
      expect(placed.pin(CharacterPin.handR),
          isNot(drawn.pin(CharacterPin.handR)));
      expect(placed.pin(CharacterPin.handR),
          placed.model[RigJoint.wristR]!.page);
    });

    test("a hand dragged lands the model's hand where it was dropped", () {
      var e = who(CharacterElement.restPose);
      var placed = CharacterPlacement.of(e, 0, models: _Models(model));
      var shoulder = placed.model[RigJoint.shoulderR]!.page;
      var hand = placed.pin(CharacterPin.handR);
      // Half way up towards the shoulder, out to the side: in reach.
      var target = shoulder + Offset((hand - shoulder).distance * 0.6, -20);
      var pose = placed.posedBy(CharacterPin.handR, target);
      var after = CharacterPlacement.of(who(pose), 0, models: _Models(model));
      expect((after.pin(CharacterPin.handR) - target).distance, lessThan(4));
    });
  });

  group("drawing a model again", () {
    test("the same posing is not worked out twice", () async {
      var model = await loadModel(humanoidGlb());
      var rig = _rig(CharacterElement.restPose);
      var box = const Rect.fromLTWH(0, 0, 200, 400);
      var a = model.pieces(rig, CharacterFace.rest, box);
      expect(identical(model.pieces(rig, CharacterFace.rest, box).$2, a.$2),
          isTrue);
      expect(
          identical(
              model.pieces(_rig(posePresets[1].pose), CharacterFace.rest, box).$2,
              a.$2),
          isFalse);
    });
  });

  group("the mannequin", () {
    test("it is built from the rig, and turns with it", () {
      var front = mannequinPieces(
          _rig(CharacterElement.restPose), characterCast.first.dna, CharacterFace.rest);
      expect(front, isNotEmpty);
      var turned = mannequinPieces(_rig(CharacterElement.restPose.withTurn(90)),
          characterCast.first.dna, CharacterFace.rest);
      expect(turned.first.points, isNot(front.first.points));
    });

    test("its eyes are hidden by its head from behind", () {
      var dna = characterCast.first.dna;
      int eyes(double turn) => mannequinPieces(
              _rig(CharacterElement.restPose.withTurn(turn)), dna, CharacterFace.rest)
          .where((p) => p.color == dna.eyes)
          .length;
      expect(eyes(0), 2);
      expect(eyes(180), 0);
    });

    test("coloured by what is worn", () {
      var dna = characterCast.first.dna;
      var colors = mannequinPieces(_rig(CharacterElement.restPose), dna,
              CharacterFace.rest)
          .map((p) => p.color)
          .toSet();
      for (var g in dna.worn) {
        if (g.kind.slot.name == "base") continue;
        expect(colors, contains(g.color), reason: "${g.kind} is seen");
      }
    });

    test("it stands in while a model is read, and differs from the drawing",
        () async {
      Future<List<int>> draw(CharacterBody body) => _pixels((c) =>
          paintCharacterFigure(c, const Rect.fromLTWH(20, 20, 200, 400),
              characterCast.first.dna, CharacterElement.restPose,
              body: body, images: _Models(null)));
      var mannequin = await draw(const CharacterBody(kind: BodyKind.mannequin));
      expect(await draw(const CharacterBody(kind: BodyKind.model, modelId: "m")),
          mannequin);
      expect(await draw(const CharacterBody()), isNot(mannequin));
      expect(
          await draw(const CharacterBody(
              kind: BodyKind.mannequin, shading: ModelShading.toon, outline: true)),
          isNot(mannequin));
    });
  });

  group("the element", () {
    test("its body is saved, and its model kept from the sweep", () {
      var e = CharacterElement(const ElementBase(id: "c", width: 100, height: 200),
          body: const CharacterBody(
              kind: BodyKind.model,
              modelId: "abc.glb",
              modelName: "Robot",
              shading: ModelShading.toon,
              outline: true));
      var back = elementFromJson(e.toJson()) as CharacterElement;
      expect(back.body, e.body);
      expect(back.mediaIds, {"abc.glb"});
      var drawn = elementFromJson(CharacterElement(
              const ElementBase(id: "d", width: 100, height: 200))
          .toJson()) as CharacterElement;
      expect(drawn.body, const CharacterBody());
      expect(drawn.mediaIds, isEmpty);
    });
  });

  group("the panel", () {
    setUpAll(() => CanvasSection.openAll = true);
    tearDownAll(() => CanvasSection.openAll = false);

    testWidgets("chooses what the body is made of, and how it is lit",
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(CanvasDocument(frames: 24).addElement(
          CharacterElement(
              const ElementBase(id: "c", x: 200, y: 50, width: 160, height: 340),
              dna: characterCast.first.dna)));
      addTearDown(c.dispose);
      c.selectOnly("c");
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(
              create: (c) => CanvasPreferences()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: SizedBox(
                    width: 420, child: CanvasDesignPanel(controller: c)))),
      ));
      await tester.pumpAndSettle();
      CharacterElement get() => c.document.elementById("c")! as CharacterElement;
      Future<void> tap(String key) async {
        var f = find.byKey(ValueKey(key));
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      expect(find.byKey(const ValueKey("characterShading-toon")), findsNothing,
          reason: "drawn has no 3D lighting");
      await tap("characterBody-mannequin");
      expect(get().body.kind, BodyKind.mannequin);
      await tap("characterShading-toon");
      expect(get().body.shading, ModelShading.toon);
      await tap("characterOutline");
      expect(get().body.outline, isTrue);
      expect(find.byKey(const ValueKey("characterModelPick")), findsNothing);
      await tap("characterBody-model");
      expect(get().body.kind, BodyKind.model);
      expect(find.byKey(const ValueKey("characterModelPick")), findsOneWidget);
      expect(find.textContaining("No model yet"), findsOneWidget);
      c.undo();
      expect(get().body.kind, BodyKind.mannequin, reason: "one undo step");
    });
  });
}
