import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/character_appearance_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_character_appearance_rig_test.dart is the Appearance editor with
// what the canvas shapes a sketch with: something picked there opens its
// part here, the face rig of the panel seen is set by sliders as well as
// handles, and the limb point picked has its own.

CharacterElement _sketch({double turn = 0, BodyKind body = BodyKind.drawn}) {
  var e = CharacterElement(
      const ElementBase(id: "c", x: 100, y: 40, width: 160, height: 340),
      dna: characterCast.first.dna,
      body: CharacterBody(kind: body));
  // Every view, for the panels at three-quarters and above.
  return e.copyWith(pose: e.pose.withTurn(turn), views: CharacterView.all);
}

void main() {
  Widget host(CanvasController c) => MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(
              create: (c) => CanvasPreferences()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: SizedBox(width: 420, child: CanvasDesignPanel(controller: c)))),
      );

  setUpAll(() => CanvasSection.openAll = true);
  tearDownAll(() => CanvasSection.openAll = false);
  setUp(() => AppearanceEditor.tab = AppearanceGroup.body);

  Future<CanvasController> open(WidgetTester tester, CharacterElement e) async {
    SharedPreferences.setMockInitialValues({});
    var c = CanvasController(CanvasDocument(frames: 24).addElement(e));
    addTearDown(c.dispose);
    c.selectOnly("c");
    tester.view.physicalSize = const Size(1000, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(c));
    await tester.pumpAndSettle();
    return c;
  }

  CharacterElement get(CanvasController c) =>
      c.document.elementById("c")! as CharacterElement;

  CanvasSlider slider(WidgetTester tester, String key) =>
      tester.widget<CanvasSlider>(find.byKey(ValueKey(key)));

  testWidgets("Part sits under the body types it chooses between", (tester) async {
    // A body in 3D's Appearance; a sketch's parts are its layers.
    await open(tester, _sketch(body: BodyKind.mannequin));
    var tiles = tester.getRect(find.byKey(const ValueKey("appearancePreset-body-Slim")).first);
    var part = tester.getRect(find.byKey(const ValueKey("appearancePart")));
    expect(part.top, greaterThan(tiles.bottom));
  });

  testWidgets("a feature picked on the canvas opens its part; its sliders set this panel",
      (tester) async {
    var c = await open(tester, _sketch(turn: 45));
    c.editFace = true;
    c.pickFacePoint(FacePoint.browL);
    await tester.pumpAndSettle();
    expect(c.pickedCharacterLayer, BodyLayer.brows.name, reason: "its layer, picked");
    expect(find.byKey(const ValueKey("appearanceFace-browL")), findsOneWidget);
    expect(find.byKey(const ValueKey("appearanceFace-nose")), findsNothing);

    slider(tester, "appearanceFace-browL-down").onChanged(-12);
    slider(tester, "appearanceFace-browL-down").onCommit!();
    await tester.pumpAndSettle();
    expect(get(c).faceRigFor(45, 0).$1[FacePoint.browL].dy, closeTo(-0.12, 1e-9));
    expect(get(c).faceRigFor(0, 0).$1.isEmpty, isTrue, reason: "this panel only");
    expect(get(c).faceRigFor(-45, 0).$2, isTrue, reason: "the other side mirrors it");
    c.undo();
    expect(get(c).faceRigs, isEmpty, reason: "one undo step");

    // The mouth has its corners, which only move.
    c.pickFacePoint(FacePoint.cornerR);
    await tester.pumpAndSettle();
    expect(c.pickedCharacterLayer, BodyLayer.mouth.name);
    expect(find.byKey(const ValueKey("appearanceFace-cornerR-across")), findsOneWidget);
    expect(find.byKey(const ValueKey("appearanceFace-cornerR-size")), findsNothing);
    expect(find.byKey(const ValueKey("appearanceFace-mouth-size")), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("a limb's point picked on the canvas has its own sliders", (tester) async {
    var c = await open(tester, _sketch());
    AppearanceEditor.tab = AppearanceGroup.eyes;
    c.editRig = true;
    c.pickRigPoint(CharacterLimb.armR, RigPoint.middle);
    await tester.pumpAndSettle();
    expect(c.pickedCharacterLayer, BodyLayer.armR.name);
    expect(find.text("Right arm: elbow"), findsOneWidget);
    slider(tester, "appearanceRigPoint-scale").onChanged(50);
    slider(tester, "appearanceRigPoint-scale").onCommit!();
    await tester.pumpAndSettle();
    var p = get(c).dna.rigPoints.of("armR").firstWhere((p) => p.sameSpot(RigPoint.middle));
    expect(p.scale, closeTo(0.5, 1e-9));
    var back = find.byKey(const ValueKey("appearanceRigPoint-delete"));
    await tester.ensureVisible(back);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(get(c).dna.rigPoints.isEmpty, isTrue);
    expect(find.byKey(const ValueKey("appearanceRigPoint")), findsNothing);
  });

  testWidgets("a body in 3D has none of it", (tester) async {
    await open(tester, _sketch(body: BodyKind.mannequin));
    expect(find.byKey(const ValueKey("appearanceBodyCanvas")), findsNothing);
  });
}
