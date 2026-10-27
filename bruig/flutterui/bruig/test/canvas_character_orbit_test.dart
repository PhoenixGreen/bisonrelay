import 'dart:ui' as ui;
import 'dart:ui' show Canvas, Offset, PictureRecorder, Rect, Size, Color, Paint;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_wardrobe.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_painter.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/render/model/mannequin.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/ui/asset_elements.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart' hide Canvas, Offset, Rect, Size, Color, Paint;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_character_orbit_test.dart is going round a character -- its turn
// and tilt, on the page and on a stage, and the globe that drags them --
// the stage's camera orbited the same way, a garment's own shape and its
// picture print, models in the library, and the camera and microphone
// switch.

CharacterRig _rig(CharacterPose pose) => CharacterRig.of(
    characterCast.first.dna, pose, const Rect.fromLTWH(0, 0, 200, 400));

/// _Pictures hands out one picture for every asked-for id.
class _Pictures implements CanvasImageSource {
  final ui.Image picture;
  _Pictures(this.picture);
  @override
  ui.Image? resolve(String assetId, BackgroundRemoval removal) => picture;
  @override
  CanvasVector? resolveVector(String assetId) => null;
  @override
  resolveOutline(String a, BackgroundRemoval r) => null;
  @override
  bool get loading => false;
}

Future<List<int>> _pixels(void Function(Canvas) paint) async {
  var rec = PictureRecorder();
  paint(Canvas(rec));
  var img = await rec.endRecording().toImage(240, 440);
  return (await img.toByteData())!.buffer.asUint8List();
}

Widget _host(CanvasController c) => MultiProvider(
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
    );

void main() {
  group("tilt", () {
    test("is kept, keyed and mixed with the rest of the pose", () {
      var p = CharacterElement.restPose.withTilt(30).withTurn(20);
      expect(CharacterPose.fromJson(p.toJson()).tilt, 30);
      expect(p.channels[tiltChannel], 30);
      expect(CharacterPose.rest.lerp(p, 0.5).tilt, 15);
      expect(p.withAngle(CharacterBone.head, 5).tilt, 30,
          reason: "a bone changed keeps the tilt");
    });

    test("seen from above, the feet stay down and the head comes down", () {
      var flat = _rig(CharacterElement.restPose);
      var over = _rig(CharacterElement.restPose.withTilt(50));
      // Tipped about the soles: the ankles, just above them, hardly move.
      expect(over.ankleL.dy, closeTo(flat.ankleL.dy, 10),
          reason: "tipped about the feet");
      expect(over.headCentre.dy, greaterThan(flat.headCentre.dy + 20));
      var under = _rig(CharacterElement.restPose.withTilt(-50));
      expect(under.headCentre.dy, greaterThan(flat.headCentre.dy + 20),
          reason: "shorter from below too");
    });

    test("a 3D body is seen from there", () {
      var dna = characterCast.first.dna;
      var flat = mannequinPieces(
          _rig(CharacterElement.restPose), dna, CharacterFace.rest);
      var over = mannequinPieces(
          _rig(CharacterElement.restPose.withTilt(40)), dna, CharacterFace.rest);
      expect(over.first.points, isNot(flat.first.points));
    });

    test("a character on a stage is seen from the camera's height", () {
      var s = StageElement(
          const ElementBase(id: "st", width: 1280, height: 720),
          camera: const StageCamera(pitch: 30));
      var c = CharacterElement(const ElementBase(id: "c", width: 200, height: 420),
          onStage: const OnStage("st"));
      var at = staging(c, [s, c], 0)!;
      expect(at.tilt, greaterThan(10));
      var level = StageElement(
          const ElementBase(id: "st", width: 1280, height: 720),
          camera: const StageCamera(pitch: 0));
      expect(staging(c, [level, c], 0)!.tilt, lessThan(at.tilt));
    });
  });

  group("a garment's own shape", () {
    var dna = characterCast.first.dna;
    var top = dna.wardrobe.lastIndexWhere((g) =>
        g.kind.slot == GarmentSlot.top || g.kind.slot == GarmentSlot.outer);

    CharacterDna wearing(Garment Function(Garment) change) {
      var w = [...dna.wardrobe];
      w[top] = change(w[top]);
      return dna.copyWith(wardrobe: w);
    }

    test("is kept with the garment, and its print", () {
      var g = dna.wardrobe[top].copyWith(
          outline: outlineShapes.first.$2,
          pattern: GarmentPattern.print,
          printId: "logo.png",
          printSize: 0.8);
      var back = Garment.fromJson(g.toJson())!;
      expect(back.outline, hasLength(outlineShapes.first.$2.length));
      expect(back.outline.first.dx, closeTo(outlineShapes.first.$2.first.dx, 1e-3));
      expect(back.printId, "logo.png");
      expect(back.printSize, 0.8);
      expect(Garment.fromJson(dna.wardrobe[top].toJson())!.outline, isEmpty);
    });

    test("is drawn, and a print shows its picture", () async {
      var logo = await () async {
        var r = PictureRecorder();
        Canvas(r).drawRect(const Rect.fromLTWH(0, 0, 10, 10),
            Paint()..color = const Color(0xFFFF0000));
        return r.endRecording().toImage(10, 10);
      }();
      Future<List<int>> draw(CharacterDna d) => _pixels((c) =>
          paintCharacterFigure(c, const Rect.fromLTWH(20, 20, 200, 400), d,
              CharacterElement.restPose,
              images: _Pictures(logo)));
      var plain = await draw(dna);
      expect(
          await draw(wearing((g) => g.copyWith(outline: outlineShapes[1].$2))),
          isNot(plain));
      expect(
          await draw(wearing((g) =>
              g.copyWith(pattern: GarmentPattern.print, printId: "logo"))),
          isNot(plain));
      expect(
          await draw(wearing((g) => g.copyWith(pattern: GarmentPattern.print))),
          plain,
          reason: "a print with no picture yet is the cloth");
    });
  });

  group("models in the library", () {
    test("one placed is a character made of it", () {
      var e = elementForAsset(
          LibraryAsset(
              id: "abc.glb",
              kind: AssetKind.model,
              name: "Robot",
              added: DateTime(2026)),
          const CanvasDocument());
      expect(e, isA<CharacterElement>());
      var c = e as CharacterElement;
      expect(c.body.kind, BodyKind.model);
      expect(c.body.modelId, "abc.glb");
      expect(c.name, "Robot");
    });
  });

  group("the panel", () {
    setUpAll(() => CanvasSection.openAll = true);
    tearDownAll(() => CanvasSection.openAll = false);

    Future<CanvasController> open(WidgetTester tester, CanvasElement e) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(CanvasDocument(frames: 24).addElement(e));
      addTearDown(c.dispose);
      c.selectOnly(e.id);
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets("the globe goes round the character and over it, in one undo",
        (tester) async {
      var c = await open(
          tester,
          CharacterElement(
              const ElementBase(id: "c", x: 200, y: 50, width: 160, height: 340),
              dna: characterCast.first.dna));
      CharacterElement get() => c.document.elementById("c")! as CharacterElement;
      var pad = find.byKey(const ValueKey("characterOrbitPad"));
      await tester.ensureVisible(pad);
      await tester.pumpAndSettle();
      await tester.drag(pad, const Offset(50, 30));
      await tester.pumpAndSettle();
      expect(get().pose.turn, greaterThan(10));
      expect(get().pose.tilt, greaterThan(5));
      c.undo();
      expect(get().pose.turn, 0, reason: "the whole drag is one step");
      expect(get().pose.tilt, 0);
    });

    testWidgets("a stage's globe orbits its camera", (tester) async {
      var c = await open(
          tester,
          StageElement(const ElementBase(id: "st", width: 1280, height: 720)));
      var pad = find.byKey(const ValueKey("stageOrbitPad"));
      await tester.ensureVisible(pad);
      await tester.pumpAndSettle();
      await tester.drag(pad, const Offset(60, 20));
      await tester.pumpAndSettle();
      var s = c.document.elementById("st")! as StageElement;
      expect(s.camera.yaw, greaterThan(10));
      expect(s.camera.pitch, greaterThan(const StageCamera().pitch));
    });

    testWidgets("a garment's shape is started from one and edited on it",
        (tester) async {
      var c = await open(
          tester,
          CharacterElement(
              const ElementBase(id: "c", x: 200, y: 50, width: 160, height: 340),
              dna: characterCast.first.dna));
      CharacterElement get() => c.document.elementById("c")! as CharacterElement;
      Future<void> tap(String key) async {
        var f = find.byKey(ValueKey(key));
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      // The top picked from its layers.
      var top = get().dna.wardrobe.lastIndexWhere((g) =>
          g.kind.slot == GarmentSlot.top || g.kind.slot == GarmentSlot.outer);
      await tap("layer-${garmentLayer(top)}");
      await tap("characterGarmentShape-Collar");
      var shaped = get().dna.wardrobe[top];
      expect(shaped.outline, hasLength(outlineShapes.first.$2.length));
      // A click on the editor, away from the points, puts one in.
      var editor = find.byKey(const ValueKey("characterGarmentShapeEditor"));
      await tester.ensureVisible(editor);
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getTopLeft(editor) + const Offset(120, 200));
      // A click waits to see that it is not the first of a double click.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(get().dna.wardrobe[top].outline,
          hasLength(outlineShapes.first.$2.length + 1));
      await tap("characterGarmentShapeClear");
      expect(get().dna.wardrobe[top].outline, isEmpty);
    });

    testWidgets("the camera and microphone stay off until allowed",
        (tester) async {
      await open(
          tester,
          CharacterElement(
              const ElementBase(id: "c", x: 200, y: 50, width: 160, height: 340),
              dna: characterCast.first.dna));
      expect(find.byKey(const ValueKey("characterRecordVoice")), findsNothing);
      var allow = find.byKey(const ValueKey("canvasAllowCapture")).first;
      await tester.ensureVisible(allow);
      await tester.pumpAndSettle();
      await tester.tap(allow);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("characterRecordVoice")), findsOneWidget);
    });
  });
}
