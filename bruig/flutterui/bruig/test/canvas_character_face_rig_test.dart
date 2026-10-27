import 'dart:ui' show PictureRecorder;
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/character_face_rig_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/character_rig_editor.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_character_face_rig_test.dart is a sketch's face set feature by
// feature, panel by panel: each feature goes where it is dragged, sized
// by its ring and turned by its knob; a panel's face is its own, the other
// side's mirrors it, and it is drawn, kept and saved.

CharacterElement _sketch({double turn = 0}) {
  var e = CharacterElement(
      const ElementBase(id: "c", x: 100, y: 40, width: 160, height: 340),
      dna: characterCast.first.dna);
  return e.copyWith(pose: e.pose.withTurn(turn));
}

const _scale = 3.0;

Future<List<int>> _pixels(CharacterElement e) async {
  var rec = PictureRecorder();
  paintElement(Canvas(rec), e, 0);
  var img = await rec.endRecording().toImage(400, 420);
  return (await img.toByteData())!.buffer.asUint8List();
}

void main() {
  for (var p in FacePoint.values) {
    test("${p.label} goes where it is dragged", () {
      var e = _sketch();
      var view = FaceRigView.of(e, 0);
      expect(view.pivots, contains(p), reason: "shown face on");
      var at = view.placed.toPage(view.handle(p));
      var to = at + const Offset(1.5, -1);
      var next = faceDragged(e, FaceHold(p, RigGrab.centre), at, to, 0, _scale);
      var after = FaceRigView.of(next, 0);
      expect(
          (after.placed.toPage(after.handle(p)) - to).distance, lessThan(0.01));
    });
  }

  test("a corner goes with the mouth as it is set", () {
    var e = _sketch().withFaceRig(
        0,
        0,
        FaceRig.none
            .withPoint(FacePoint.mouth, const FaceAdjust(dy: 0.05, turn: 20)));
    var view = FaceRigView.of(e, 0);
    var at = view.placed.toPage(view.handle(FacePoint.cornerL));
    var to = at + const Offset(0, -2);
    var next = faceDragged(e, const FaceHold(FacePoint.cornerL, RigGrab.centre),
        at, to, 0, _scale);
    var after = FaceRigView.of(next, 0);
    expect((after.placed.toPage(after.handle(FacePoint.cornerL)) - to).distance,
        lessThan(0.01));
  });

  test("the ring sizes a feature and the knob turns it", () {
    var e = _sketch();
    var view = FaceRigView.of(e, 0);
    var c = view.placed.toPage(view.handle(FacePoint.eyeL));
    var r = view.ring(FacePoint.eyeL, _scale);
    var edge = view.placed.toPage(view.handle(FacePoint.eyeL) + Offset(0, r));
    expect(view.under(edge, _scale, 0.8)?.grab, RigGrab.ring);
    var big = faceDragged(e, const FaceHold(FacePoint.eyeL, RigGrab.ring), edge,
        c + (edge - c) * 1.5, 0, _scale);
    expect(big.faceRigFor(0, 0).$1[FacePoint.eyeL].scale, closeTo(1.5, 0.01));

    var k = view.placed.toPage(view.knob(FacePoint.browR, _scale));
    expect(view.under(k, _scale, 0.8)?.grab, RigGrab.knob);
    var bc = view.placed.toPage(view.handle(FacePoint.browR));
    var d = k - bc;
    var turned = faceDragged(e, const FaceHold(FacePoint.browR, RigGrab.knob),
        k, bc + Offset(d.dy, -d.dx), 0, _scale);
    expect(turned.faceRigFor(0, 0).$1[FacePoint.browR].turn, closeTo(-90, 0.5));
    // The mouth's knob is clear of its corners.
    for (var corner in [FacePoint.cornerL, FacePoint.cornerR]) {
      var at = view.placed.toPage(view.handle(corner));
      expect(view.under(at, _scale, 0.8)?.point, corner);
    }
  });

  test("a panel's face is its own; the other side's mirrors it", () {
    var rig = FaceRig.none.withPoint(
        FacePoint.browL, const FaceAdjust(dx: 0.02, dy: -0.05, turn: 10));
    var e = _sketch().withFaceRig(45, 0, rig);
    expect(e.faceRigFor(0, 0).$1.isEmpty, isTrue);
    expect(e.faceRigFor(90, 0).$1.isEmpty, isTrue);
    var (other, mirrored) = e.faceRigFor(-45, 0);
    expect(mirrored, isTrue);
    expect(other[FacePoint.browR],
        const FaceAdjust(dx: -0.02, dy: -0.05, turn: -10));
    // Set on the mirror, it is that side's own.
    var view = FaceRigView.of(e.copyWith(pose: e.pose.withTurn(-45)), 0);
    expect(view.mirrored, isTrue);
    var at = view.placed.toPage(view.handle(FacePoint.nose));
    var next = view.dragged(const FaceHold(FacePoint.nose, RigGrab.centre), at,
        at + const Offset(0, 1), _scale);
    var (own, isMirror) = next.faceRigFor(-45, 0);
    expect(isMirror, isFalse);
    expect(own[FacePoint.browR], other[FacePoint.browR],
        reason: "the mirror kept");
  });

  test("drawn, put back, kept when moved, and saved", () async {
    var e = _sketch().withFaceRig(0, 0,
        FaceRig.none.withPoint(FacePoint.cornerL, const FaceAdjust(dy: -0.08)));
    expect(await _pixels(e), isNot(await _pixels(_sketch())),
        reason: "a lopsided smile");
    var back = withFacePointBack(e, FacePoint.cornerL, 0);
    expect(back.faceRigs, isEmpty);
    expect(await _pixels(back), await _pixels(_sketch()));
    expect((e.withBase(x: 10) as CharacterElement).faceRigs, e.faceRigs);
    var saved = elementFromJson(e.toJson()) as CharacterElement;
    expect(saved.faceRigs, e.faceRigs);
  });

  test("turned away, the face has nothing to set", () {
    expect(FaceRigView.of(_sketch(turn: 180), 0).pivots, isEmpty);
  });

  group("on the stage", () {
    Future<(CanvasController, Offset Function(Offset))> stage(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      // Big, so the face's handles are apart.
      var c = CanvasController(const CanvasDocument().addElement(CharacterElement(
          const ElementBase(id: "c", x: 300, y: 20, width: 380, height: 1040),
          dna: characterCast.first.dna)));
      addTearDown(c.dispose);
      c.selectOnly("c");
      c.editFace = true;
      tester.view.physicalSize = const Size(1600, 1200);
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
                body: CanvasStage(key: const ValueKey("stage"), controller: c))),
      ));
      await tester.pumpAndSettle();
      var view = tester.state<CanvasStageState>(find.byKey(const ValueKey("stage")));
      var page = view.pageRect;
      var scale = page.width / c.document.size.size.width;
      return (
        c,
        (Offset doc) =>
            tester.getTopLeft(find.byKey(const ValueKey("stage"))) +
            page.topLeft +
            doc * scale
      );
    }

    CharacterElement get(CanvasController c) =>
        c.document.elementById("c")! as CharacterElement;

    testWidgets("a corner of the mouth dragged up, in one undo; Delete puts it back",
        (tester) async {
      var (c, onScreen) = await stage(tester);
      var view = FaceRigView.of(get(c), 0);
      var corner = view.placed.toPage(view.handle(FacePoint.cornerL));
      await tester.dragFrom(onScreen(corner), const Offset(0, -6));
      await tester.pumpAndSettle();
      expect(get(c).faceRigFor(0, 0).$1[FacePoint.cornerL].dy, lessThan(0));
      expect(c.facePick, FacePoint.cornerL);
      expect(c.selection, {"c"});
      c.deleteSelected();
      await tester.pump();
      expect(get(c).faceRigs, isEmpty);
      expect(c.document.elementById("c"), isNotNull);
      c.undo();
      expect(get(c).faceRigs, isNotEmpty, reason: "the drag, undone by itself");
      c.undo();
      expect(get(c).faceRigs, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets("put away, the face is not taken hold of", (tester) async {
      var (c, onScreen) = await stage(tester);
      c.editFace = false;
      await tester.pump();
      var view = FaceRigView.of(get(c), 0);
      var nose = view.placed.toPage(view.handle(FacePoint.nose));
      await tester.dragFrom(onScreen(nose), const Offset(0, 6));
      await tester.pumpAndSettle();
      expect(get(c).faceRigs, isEmpty);
    });
  });
}
