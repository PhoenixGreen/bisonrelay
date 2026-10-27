import 'dart:ui' show Canvas, PictureRecorder;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/character_hair_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/character_hair_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_character_hair_test.dart is a sketch's hair made of strokes: each
// growing from the scalp and turning with the head, in front of the face
// or behind it as it grows, in groups, saved, and shaped in its layers.

CharacterElement _sketch({HairRig? hair, double turn = 0}) {
  var e = CharacterElement(
      const ElementBase(id: "c", x: 20, y: 20, width: 160, height: 340),
      dna: characterCast.first.dna.copyWith(hairRig: hair),
      views: CharacterView.all);
  return e.copyWith(pose: e.pose.withTurn(turn));
}

Future<List<int>> _pixels(CharacterElement e) async {
  var rec = PictureRecorder();
  paintElement(Canvas(rec), e, 0);
  var img = await rec.endRecording().toImage(200, 380);
  return (await img.toByteData())!.buffer.asUint8List();
}

void main() {
  var messy = hairPresets.firstWhere((p) => p.name == "Messy");

  test("strokes in groups, saved, added, taken away and mirrored", () {
    for (var p in hairPresets) {
      for (var g in HairGroup.values) {
        expect(p.inGroup(g), isNotEmpty, reason: "${p.name} has ${g.label}");
      }
    }
    var rig = messy.withGroup(HairGroup.back, const HairGroupLook(length: 2, curl: 0.3));
    var back = HairRig.fromJson(rig.toJson())!;
    expect(back.strokes.length, rig.strokes.length);
    expect(back.lookOf(HairGroup.back).length, 2);
    expect(back.strokes.first.toJson(), rig.strokes.first.toJson());
    var (added, at) = rig.withAdded(0);
    expect(added.strokes.length, rig.strokes.length + 1);
    expect(added.strokes[at].lon, rig.strokes[0].lon + 9);
    expect(added.without(at).strokes.length, rig.strokes.length);
    var s = const HairStroke(HairGroup.sides, 80, 20, lean: 0.3, curl: 0.2);
    expect(s.mirrored.lon, -80);
    expect(s.mirrored.lean, -0.3);
    var dna = characterCast.first.dna.copyWith(hairRig: rig);
    expect(CharacterDna.fromJson(dna.toJson()).hairRig?.strokes.length, rig.strokes.length);
    expect(CharacterStyle.chibi.dnaOf(dna).hairRig, isNotNull, reason: "a style keeps them");
    expect(dna.copyWith(noHairRig: true).hairRig, isNull);
  });

  test("drawn in front of the face and behind it, turning with the head", () async {
    var plain = await _pixels(_sketch());
    var strokes = await _pixels(_sketch(hair: messy));
    expect(strokes, isNot(plain));
    // Front hair hidden: the fringe goes; back hair hidden: the back.
    var e = _sketch(hair: messy);
    var noFront = await _pixels(e.withLayerShown(BodyLayer.hairFront.name, false));
    expect(noFront, isNot(strokes));
    var turned = _sketch(hair: messy, turn: 180);
    var noBackTurned = await _pixels(turned.withLayerShown(BodyLayer.hairBack.name, false));
    var noFrontTurned = await _pixels(turned.withLayerShown(BodyLayer.hairFront.name, false));
    // From behind, what grows on the back is nearest: it is the front's.
    expect(noFrontTurned, isNot(await _pixels(turned)));
    expect(noBackTurned, isNot(noFrontTurned));
    // Longer strokes draw further.
    var longer = _sketch(
        hair: messy.withGroup(HairGroup.back, const HairGroupLook(length: 3)), turn: 180);
    expect(await _pixels(longer), isNot(await _pixels(turned)));
  });

  group("the hair layer's settings", () {
    setUpAll(() => CanvasSection.openAll = true);
    tearDownAll(() => CanvasSection.openAll = false);

    testWidgets("made of strokes, shaped, added to and taken from", (tester) async {
      SharedPreferences.setMockInitialValues({});
      HairStrokesEditor.group = HairGroup.fringe;
      HairStrokesEditor.stroke = 0;
      var c = CanvasController(CanvasDocument(frames: 24).addElement(_sketch()));
      addTearDown(c.dispose);
      c.selectOnly("c");
      c.pickCharacterLayer(BodyLayer.hairFront.name);
      tester.view.physicalSize = const Size(900, 14000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(create: (c) => CanvasPreferences()),
        ],
        child: MaterialApp(
            home: Scaffold(body: SizedBox(width: 420, child: CanvasDesignPanel(controller: c)))),
      ));
      await tester.pumpAndSettle();
      CharacterElement get() => c.document.elementById("c") as CharacterElement;
      Future<void> tap(String key) async {
        var f = find.byKey(ValueKey(key));
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      tester.widget<CanvasDropdown<String>>(find.byKey(const ValueKey("characterHairPreset")))
          .onChanged("Messy");
      await tester.pumpAndSettle();
      expect(get().dna.hairRig?.name, "Messy");
      var fringe = get().dna.hairRig!.inGroup(HairGroup.fringe);

      var length = tester.widget<CanvasSlider>(find.byKey(const ValueKey("characterHairLength")));
      length.onChanged(1.2);
      length.onCommit!();
      await tester.pumpAndSettle();
      expect(get().dna.hairRig!.strokes[fringe.first.$1].length, 1.2);

      await tap("characterHairAdd");
      expect(get().dna.hairRig!.inGroup(HairGroup.fringe).length, fringe.length + 1);
      await tap("characterHairRemove");
      expect(get().dna.hairRig!.inGroup(HairGroup.fringe).length, fringe.length);
      await tap("characterHairMirror");
      expect(get().dna.hairRig!.inGroup(HairGroup.fringe).length, fringe.length + 1);

      tester.widget<CanvasDropdown<HairGroup>>(find.byKey(const ValueKey("characterHairGroupPick")))
          .onChanged(HairGroup.back);
      await tester.pumpAndSettle();
      var vol = tester.widget<CanvasSlider>(find.byKey(const ValueKey("characterHairGroupVolume")));
      vol.onChanged(2);
      vol.onCommit!();
      await tester.pumpAndSettle();
      expect(get().dna.hairRig!.lookOf(HairGroup.back).volume, 2);

      tester.widget<CanvasDropdown<String>>(find.byKey(const ValueKey("characterHairPreset")))
          .onChanged("");
      await tester.pumpAndSettle();
      expect(get().dna.hairRig, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  group("shaped on the canvas", () {
    test("the tip goes where it is dragged; the root round the scalp", () {
      var e = _sketch(hair: messy);
      var view = HairView.of(e, 0)!;
      var i = messy.inGroup(HairGroup.fringe)[2].$1;
      var tip = view.page(view.shapes[i].tip);
      expect(view.under(tip, 3, 1.5, picked: i)?.grab, HairGrab.tip);
      var to = tip + const Offset(3, 6);
      var next = view.dragged(HairHold(i, HairGrab.tip), tip, to);
      var after = HairView.of(next, 0)!;
      expect((after.page(after.shapes[i].tip) - to).distance, lessThan(0.5));
      expect(next.dna.hairRig!.strokes[i].length, greaterThan(messy.strokes[i].length));

      var root = view.page(view.shapes[i].root);
      var moved = view.dragged(HairHold(i, HairGrab.root), root, root + const Offset(4, 0));
      expect(moved.dna.hairRig!.strokes[i].lon, isNot(messy.strokes[i].lon));
      var r2 = HairView.of(moved, 0)!;
      expect((r2.page(r2.shapes[i].root) - (root + const Offset(4, 0))).distance, lessThan(1));
    });

    test("a ring makes it wider; the bare scalp grows a new one, not the face", () {
      var e = _sketch(hair: messy);
      var view = HairView.of(e, 0)!;
      var i = messy.inGroup(HairGroup.back)[0].$1;
      var (c, r) = view.ringAt(i, 0, 3);
      var from = view.page(c + Offset(r, 0)), to = view.page(c + Offset(r * 2, 0));
      var wider = view.dragged(HairHold(i, HairGrab.ring0), from, to);
      expect(wider.dna.hairRig!.strokes[i].w0, closeTo(messy.strokes[i].w0 * 2, 1e-6));
      // On the crown: the top. On the cheek: nothing.
      var r0 = e.dna.hairRig;
      expect(r0, isNotNull);
      var crown = view.page(Offset(0, -view.head.h * 0.97));
      expect(view.grownAt(crown)?.group, HairGroup.top);
      var cheek = view.page(Offset(view.head.w * 0.3, view.head.h * 0.3));
      expect(view.grownAt(cheek), isNull);
    });

    testWidgets("picked by a click; a stroke grown on the scalp; Delete takes it",
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      // Big, so the strokes are apart.
      var c = CanvasController(const CanvasDocument().addElement(CharacterElement(
          const ElementBase(id: "c", x: 300, y: 20, width: 380, height: 1040),
          dna: characterCast.first.dna.copyWith(hairRig: messy))));
      addTearDown(c.dispose);
      c.selectOnly("c");
      c.editHair = true;
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(create: (c) => CanvasPreferences()),
        ],
        child: MaterialApp(
            home: Scaffold(body: CanvasStage(key: const ValueKey("stage"), controller: c))),
      ));
      await tester.pumpAndSettle();
      var stage = tester.state<CanvasStageState>(find.byKey(const ValueKey("stage")));
      var page = stage.pageRect;
      var scale = page.width / c.document.size.size.width;
      Offset onScreen(Offset doc) =>
          tester.getTopLeft(find.byKey(const ValueKey("stage"))) + page.topLeft + doc * scale;
      CharacterElement get() => c.document.elementById("c") as CharacterElement;
      var view = HairView.of(get(), 0)!;
      var i = messy.inGroup(HairGroup.fringe)[3].$1;
      var mid = view.page(view.shapes[i].middle[12]);
      await tester.tapAt(onScreen(mid));
      await tester.pumpAndSettle();
      expect(c.hairPick, isNotNull);
      var count = get().dna.hairRig!.strokes.length;
      // Grown on the bare scalp and drawn out.
      c.pickHair(null);
      await tester.pump();
      Offset? crown;
      for (var y = -0.95; y < 0.2 && crown == null; y += 0.05) {
        for (var x = -0.9; x <= 0.9 && crown == null; x += 0.05) {
          var at = view.page(Offset(view.head.w * x, view.head.h * y));
          if (view.grownAt(at) != null && view.under(at, scale, 12 / scale) == null) crown = at;
        }
      }
      expect(crown, isNotNull, reason: "somewhere bare on the scalp");
      await tester.dragFrom(onScreen(crown!), const Offset(10, -12));
      await tester.pumpAndSettle();
      expect(get().dna.hairRig!.strokes.length, count + 1);
      expect(c.hairPick, count);
      c.undo();
      expect(get().dna.hairRig!.strokes.length, count, reason: "grown and drawn out: one step");
      c.pickHair(i);
      c.deleteSelected();
      await tester.pump();
      expect(get().dna.hairRig!.strokes.length, count - 1);
      expect(c.document.elementById("c"), isNotNull);
      expect(tester.takeException(), isNull);
    });
  });
}
