import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/elements/character_outfit.dart';
import 'package:bruig/plugin_system/canvas/ui/character_decal_panel.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_decal.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_decal.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_shape.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_mesh.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_shape.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_wear.dart';
import 'package:bruig/plugin_system/canvas/ui/character_outfit_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/character_shape_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vector_math/vector_math.dart' as vm;

// A new 3D character's clothes: what is worn, what each garment covers, the
// garments made from a body's own skin, the body's own clothes cut shorter,
// the patterns, the skin painted again where clothes come off, and the
// page's clothes settings.

/// The joints the test body is bound to, in its skin's order.
const _joints = [
  'J_Bip_C_Hips', 'J_Bip_C_UpperChest', 'J_Bip_C_Neck', 'J_Bip_L_UpperArm',
  'J_Bip_L_LowerArm', //
  'J_Bip_L_Hand', 'J_Bip_L_UpperLeg', 'J_Bip_L_LowerLeg', 'J_Bip_L_Foot',
];

/// _skeleton is a body standing with its arm out: hips at 0.9 m, the chest
/// at 1.2, the neck at 1.35, and the left arm and leg.
Map<String, VrmRestBone> _skeleton() {
  final out = <String, VrmRestBone>{};
  void b(String n, String? p, double x, double y) => out[n] = VrmRestBone(
      n, p, vm.Vector3(x, y, 0), vm.Quaternion.identity(), vm.Vector3.all(1));
  b('Root', null, 0, 0);
  b(VroidBone.hips, 'Root', 0, 0.9);
  b(VroidBone.spine, VroidBone.hips, 0, 0.1);
  b(VroidBone.chest, VroidBone.spine, 0, 0.1);
  b(VroidBone.upperChest, VroidBone.chest, 0, 0.1);
  b(VroidBone.neck, VroidBone.upperChest, 0, 0.15);
  b(VroidBone.head, VroidBone.neck, 0, 0.08);
  b(VroidBone.upperArm('L'), VroidBone.upperChest, 0.15, 0.0);
  b(VroidBone.lowerArm('L'), VroidBone.upperArm('L'), 0.25, 0);
  b(VroidBone.hand('L'), VroidBone.lowerArm('L'), 0.22, 0);
  b(VroidBone.upperLeg('L'), VroidBone.hips, 0.08, -0.05);
  b(VroidBone.lowerLeg('L'), VroidBone.upperLeg('L'), 0, -0.4);
  b(VroidBone.foot('L'), VroidBone.lowerLeg('L'), 0, -0.4);
  return out;
}

Map<String, vm.Vector3> _bind(Map<String, VrmRestBone> bones) {
  vm.Vector3 at(String n) {
    final b = bones[n]!;
    return b.parent == null
        ? b.translation.clone()
        : at(b.parent!) + b.translation;
  }

  return {for (final n in bones.keys) n: at(n)};
}

/// _body is a skin of rings: the torso from the hips to the chest, the
/// neck, the left arm out along x, and the left leg down to the sole --
/// each ring bound to the bone it is on -- with the body's own top over
/// the torso and the arm.
VrmMeshData _body() {
  final bones = _skeleton(), bind = _bind(bones);
  final pos = <double>[],
      nrm = <double>[],
      joints = <double>[],
      weights = <double>[];
  final skinTris = <int>[], topTris = <int>[];
  const around = 8;
  // A tube is rings along a line, stitched one to the next.
  void tube(List<(vm.Vector3, int)> rings, vm.Vector3 axis, double r,
      {bool top = false}) {
    final first = pos.length ~/ 3;
    final u = axis.x.abs() > 0.5 ? vm.Vector3(0, 1, 0) : vm.Vector3(1, 0, 0),
        v = axis.cross(u);
    for (final (c, joint) in rings) {
      for (var k = 0; k < around; k++) {
        final a = 2 * math.pi * k / around;
        final n = u * math.cos(a) + v * math.sin(a);
        final p = c + n * r;
        pos.addAll([p.x, p.y, p.z]);
        nrm.addAll([n.x, n.y, n.z]);
        joints.addAll([joint.toDouble(), 0, 0, 0]);
        weights.addAll([1, 0, 0, 0]);
      }
    }
    for (var r = 0; r + 1 < rings.length; r++) {
      for (var k = 0; k < around; k++) {
        final a = first + r * around + k,
            b = first + r * around + (k + 1) % around;
        final tri = [a, b, a + around, b, b + around, a + around];
        skinTris.addAll(tri);
        if (top) topTris.addAll(tri);
      }
    }
  }

  tube([
    for (var r = 0; r <= 28; r++)
      (vm.Vector3(0, 0.8 + 0.02 * r, 0), r < 10 ? 0 : (r < 26 ? 1 : 2))
  ], vm.Vector3(0, 1, 0), 0.12, top: true);
  tube([
    for (var r = 0; r <= 12; r++)
      (vm.Vector3(0.15 + 0.04 * r, 1.2, 0), r < 7 ? 3 : (r < 12 ? 4 : 5))
  ], vm.Vector3(1, 0, 0), 0.04, top: true);
  tube([
    for (var r = 0; r <= 21; r++)
      (vm.Vector3(0.08, 0.86 - 0.04 * r, 0), r <= 10 ? 6 : (r < 20 ? 7 : 8)),
    (vm.Vector3(0.08, 0.005, 0), 8)
  ], vm.Vector3(0, -1, 0), 0.05);
  final n = pos.length ~/ 3;
  final vs = VrmVertices(
    positions: Float32List.fromList(pos),
    normals: Float32List.fromList(nrm),
    uv0: Float32List.fromList([
      for (var i = 0; i < n; i++) ...[(i % around) / around, i / n]
    ]),
    uv1: Float32List(n * 2),
    colors: Float32List(n * 4)..fillRange(0, n * 4, 1),
    tangents: Float32List(n * 4),
    joints: Float32List.fromList(joints),
    weights: Float32List.fromList(weights),
    skinned: true,
  );
  return VrmMeshData([
    VrmMeshNode(
        'Body',
        [
          VrmPrimitive(
              material: 'F00_002_02_Body_00_SKIN',
              vertices: vs,
              indices: Uint32List.fromList(skinTris),
              indices32: true),
          VrmPrimitive(
              material: 'F00_002_01_Tops_01_CLOTH',
              vertices: vs,
              indices: Uint32List.fromList(topTris),
              indices32: true),
        ],
        _joints),
  ], bones, bind);
}

Set<int> _verts(GarmentMesh g) => g.indices.toSet();
double _lowest(GarmentMesh g, {bool Function(int)? only}) => _verts(g)
    .where(only ?? (_) => true)
    .map((i) => g.vertices.positions[i * 3 + 1])
    .reduce(math.min);

void main() {
  group('the outfit', () {
    test('as designed is the body\'s own, with underwear made under it', () {
      const o = CharacterOutfit.asDesigned;
      expect(o[WearSlot.top].source, WearSource.own);
      expect(o[WearSlot.underwear].made, isTrue);
      expect(o[WearSlot.gloves].source, WearSource.none);
      expect(WearSlot.values.any(o.changed), isFalse);
    });

    test('the quick changes', () {
      final under = CharacterOutfit.asDesigned.underwearOnly(male: true);
      for (final s in [
        WearSlot.top,
        WearSlot.bottom,
        WearSlot.shoes,
        WearSlot.legwear,
        WearSlot.gloves
      ]) {
        expect(under[s].source, WearSource.none, reason: s.name);
      }
      expect(under[WearSlot.underwear].kind, 'set',
          reason: 'underwear already on is kept as it is');
      final swim = CharacterOutfit.asDesigned.swimwear(male: false);
      expect((swim[WearSlot.underwear].kind, swim[WearSlot.top].source),
          ('swim', WearSource.none));
      final casual = CharacterOutfit.asDesigned.casual(male: true);
      expect((
        casual[WearSlot.top].kind,
        casual[WearSlot.bottom].kind,
        casual[WearSlot.legwear].made
      ), (
        'tee',
        'trousers',
        true
      ));
    });

    test('kept and read back the same, and junk is dropped', () {
      final o = CharacterOutfit.asDesigned.wear(
          WearSlot.top,
          CharacterOutfit.defaults[WearSlot.top]!.copyWith(
              source: WearSource.made,
              kind: 'crop',
              pattern: 'dots',
              colour: 0x123456));
      expect(
          CharacterOutfit.fromJson(
              jsonDecode(jsonEncode(o.toJson())) as Map<String, dynamic>),
          o);
      final junk = CharacterOutfit.fromJson({
        'top': {
          'source': 'made',
          'kind': 'skirt',
          'hem': 7,
          'colour': 'red',
          'pattern': 'paisley'
        },
      });
      expect(junk[WearSlot.top].kind, 'tee', reason: 'a skirt is not a top');
      expect(junk[WearSlot.top].hem, 1);
      expect(junk[WearSlot.top].colour,
          CharacterOutfit.defaults[WearSlot.top]!.colour);
      expect(junk[WearSlot.top].pattern, 'solid');
    });
  });

  group('made to fit', () {
    final wardrobe = VrmWardrobe.of(VrmShapeRig(_body()))!;
    final lines = wardrobe.lines();
    Garment made(WearSlot s, String kind) => CharacterOutfit.defaults[s]!
        .copyWith(source: WearSource.made, kind: kind);
    bool onTorso(GarmentMesh g, int i) =>
        wardrobe.groupAt(i) == BodyGroup.torso;

    test('the body knows its own clothes and where each point is on it', () {
      expect(wardrobe.hasOwn(WearSlot.top), isTrue);
      expect(wardrobe.hasOwn(WearSlot.shoes), isFalse);
      expect(wardrobe.hasOwnBottom, isFalse);
      // The ring at the elbow is two-fifths down the arm, and a foot at the
      // end of its leg.
      final elbow = List.generate(wardrobe.skin.count, (i) => i)
          .firstWhere((i) => wardrobe.groupAt(i) == BodyGroup.armF);
      expect(wardrobe.along[elbow], closeTo(0.27 / 0.47, 0.05));
      expect(
          BodyGroup.values.where((g) => wardrobe.group.contains(g.index)),
          containsAll([
            BodyGroup.torso,
            BodyGroup.neck,
            BodyGroup.armU,
            BodyGroup.hand,
            BodyGroup.legU,
            BodyGroup.foot
          ]));
    });

    test(
        'a T-shirt covers the body and some of the arm, and stands off the skin',
        () {
      final tee =
          wardrobe.make(WearSlot.top, made(WearSlot.top, 'tee'), lines)!;
      final used = _verts(tee);
      expect(used.where((i) => wardrobe.groupAt(i) == BodyGroup.torso),
          isNotEmpty);
      expect(
          used.where((i) =>
              wardrobe.groupAt(i) == BodyGroup.legL ||
              wardrobe.groupAt(i) == BodyGroup.hand),
          isEmpty);
      final reach = used
          .where((i) => wardrobe.groupAt(i) == BodyGroup.armF)
          .map((i) => wardrobe.along[i]);
      expect(reach.isEmpty || reach.reduce(math.max) < 0.45, isTrue,
          reason: 'short sleeves');
      // Stood off the skin by its layer and how loose it is.
      final i = used.firstWhere(
          (i) => onTorso(tee, i) && wardrobe.skin.positions[i * 3 + 1] > 1.15);
      final p = tee.vertices.positions;
      expect(math.sqrt(p[i * 3] * p[i * 3] + p[i * 3 + 2] * p[i * 3 + 2]),
          closeTo(0.12 + 0.0068 + 0.2 * 0.022, 1e-4));
    });

    test('the hem is cut along its line, not along the triangles', () {
      final g = made(WearSlot.top, 'tee');
      final tee = wardrobe.make(WearSlot.top, g, lines)!;
      final hem = lines.waist +
          0.08 -
          g.hem * (lines.waist + 0.08 - (lines.crotch - 0.03));
      expect(_lowest(tee, only: (i) => onTorso(tee, i)), closeTo(hem, 0.012));
      final crop =
          wardrobe.make(WearSlot.top, g.copyWith(kind: 'crop'), lines)!;
      expect(_lowest(crop, only: (i) => onTorso(crop, i)),
          greaterThan(hem + 0.05));
    });

    test('shorts are shorter than trousers, and shoes have a sole', () {
      final trousers = wardrobe.make(
          WearSlot.bottom, made(WearSlot.bottom, 'trousers'), lines)!;
      final shorts = wardrobe.make(
          WearSlot.bottom, made(WearSlot.bottom, 'shorts'), lines)!;
      expect(_lowest(shorts), greaterThan(_lowest(trousers) + 0.2));
      final shoes = wardrobe.make(
          WearSlot.shoes, made(WearSlot.shoes, 'trainers'), lines)!;
      final u = _verts(shoes).map((i) => shoes.vertices.uv0[i * 2]).toSet();
      expect(u, {0.25, 0.75},
          reason: 'the upper and the sole, each its own colour');
      expect(
          wardrobe.make(
              WearSlot.gloves, made(WearSlot.gloves, 'fingerless'), lines),
          isNotNull);
    });

    test('nothing worn, nothing made', () {
      expect(
          wardrobe.make(
              WearSlot.top, CharacterOutfit.defaults[WearSlot.top]!, lines),
          isNull,
          reason: 'the body\'s own');
      expect(
          wardrobe.make(WearSlot.legwear,
              CharacterOutfit.defaults[WearSlot.legwear]!, lines),
          isNull);
    });

    test('a skirt falls clear of the body, seen from inside as well', () {
      final skirt = wardrobe.make(
          WearSlot.bottom, made(WearSlot.bottom, 'skirt'), lines)!;
      expect(skirt.doubleSided, isTrue);
      final p = skirt.vertices.positions;
      for (var i = 0; i < skirt.vertices.count; i++) {
        final x = p[i * 3], z = p[i * 3 + 2];
        // Clear of the torso and of the leg under it.
        expect(math.sqrt(x * x + z * z), greaterThan(0.12),
            reason: 'vertex $i');
      }
      final w = skirt.vertices.weights;
      for (var i = 0; i < skirt.vertices.count; i++) {
        expect(w[i * 4] + w[i * 4 + 1], closeTo(1, 1e-6));
      }
    });

    test('inside shoes, the feet and socks are not drawn', () {
      final skinTris = Uint32List.fromList([
        for (final p in wardrobe.body.primitives)
          if (p.part == VrmPart.skin) ...p.indices
      ]);
      final bare = wardrobe.withoutFeet(skinTris);
      expect(bare.length, lessThan(skinTris.length));
      bool foot(int i) => wardrobe.groupAt(i) == BodyGroup.foot;
      for (var k = 0; k < bare.length; k += 3) {
        expect(
            foot(bare[k]) && foot(bare[k + 1]) && foot(bare[k + 2]), isFalse);
      }
      final socks = made(WearSlot.legwear, 'knee');
      final open = wardrobe.make(WearSlot.legwear, socks, lines)!;
      final shod = wardrobe.make(WearSlot.legwear, socks, lines, shod: true)!;
      expect(shod.indices.length, lessThan(open.indices.length));
    });

    test('the body\'s own sleeves are cut shorter', () {
      final top =
          wardrobe.body.primitives.firstWhere((p) => p.part == VrmPart.top);
      expect(wardrobe.cut(top, 1), same(top.indices));
      final short = wardrobe.cut(top, 0.1);
      expect(short.length, lessThan(top.indices.length));
      for (final i in short) {
        if (wardrobe.groupAt(i).index >= BodyGroup.armU.index &&
            wardrobe.groupAt(i).index <= BodyGroup.finger.index) {
          expect(wardrobe.along[i], lessThanOrEqualTo(0.06 + 0.91 * 0.1));
        }
      }
    });
  });

  group('pictures', () {
    int at(Uint8List px, int w, int x, int y) =>
        (px[(y * w + x) * 4] << 16) |
        (px[(y * w + x) * 4 + 1] << 8) |
        px[(y * w + x) * 4 + 2];

    test('stripes, and a shoe\'s upper beside its sole', () {
      final g = CharacterOutfit.defaults[WearSlot.top]!.copyWith(
          pattern: 'stripes', colour: 0x112233, patternColour: 0xaabbcc);
      final (px, w, h) = garmentPicture(WearSlot.top, g);
      expect((w, h), (128, 128));
      expect(at(px, w, 5, 10), 0xaabbcc);
      expect(at(px, w, 5, 40), 0x112233);
      final shoe = CharacterOutfit.defaults[WearSlot.shoes]!
          .copyWith(colour: 0x9c3a32, sole: 0xf4f1ea);
      final (sp, sw, _) = garmentPicture(WearSlot.shoes, shoe);
      expect((at(sp, sw, 3, 3), at(sp, sw, 60, 3)), (0x9c3a32, 0xf4f1ea));
    });

    test('painted clothes come off the skin, and only where the clothes have',
        () {
      final wardrobe = VrmWardrobe.of(VrmShapeRig(_body()))!;
      const w = 64, h = 64;
      // Skin everywhere, and a painted blue suit over the bottom half of the
      // picture, where the leg's rings are laid out.
      final px = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final a = (y * w + x) * 4;
          final blue = y > h * 0.62;
          px.setAll(a, blue ? [40, 50, 120, 255] : [240, 200, 180, 255]);
        }
      }
      final legs = bareSkin(px, w, h, wardrobe, upper: false, lower: true);
      expect(legs.sublist((60 * w + 30) * 4, (60 * w + 30) * 4 + 3),
          [240, 200, 180]);
      final kept = bareSkin(px, w, h, wardrobe, upper: true, lower: false);
      expect(
          kept.sublist((60 * w + 30) * 4, (60 * w + 30) * 4 + 3), [40, 50, 120],
          reason: 'the shoes are still on');
      // Where the neck and hands are painted too, the face says what skin is.
      final suit = Uint8List.fromList(px)..fillRange(0, px.length, 0);
      for (var i = 0; i < w * h; i++) {
        suit.setAll(i * 4, [40, 50, 120, 255]);
      }
      final face = bareSkin(suit, w, h, wardrobe,
          upper: true, lower: true, face: const [240, 200, 180]);
      expect(face.sublist((10 * w + 30) * 4, (10 * w + 30) * 4 + 3),
          [240, 200, 180]);
    });
  });

  group('the clothes settings', () {
    Future<CharacterOutfit Function()> show(WidgetTester tester, String part,
        {CharacterOutfit start = CharacterOutfit.asDesigned,
        Set<WearSlot> own = const {WearSlot.top, WearSlot.shoes},
        double scale = 1}) async {
      var o = start;
      await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
        create: (_) => ThemeNotifier(doLoad: false),
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
                size: const Size(1000, 800),
                textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Row(children: [
                SizedBox(
                  width: 300,
                  child: StatefulBuilder(
                      builder: (context, set) => CharacterOutfitControls(
                          part: part,
                          outfit: o,
                          bodyName: 'Vivi',
                          own: own,
                          onChanged: (n) => set(() => o = n))),
                ),
              ]),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return () => o;
    }

    StudioPills<String> pills(WidgetTester tester, String key) =>
        tester.widget<StudioPills<String>>(find.byKey(ValueKey(key)));
    Future<void> tap(WidgetTester tester, String key) async {
      final f = find.byKey(ValueKey(key));
      // From the top of the settings down to it: the list builds only what
      // is near the screen.
      await tester.drag(find.byType(Scrollable).last, const Offset(0, 3000));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(f, 80);
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    testWidgets(
        'a piece is the body\'s own, none, or made, and made has its cut and colours',
        (tester) async {
      final now = await show(tester, wearPartId(WearSlot.top));
      final wearing = pills(tester, 'wear-top-wearing');
      expect(wearing.value, 'own');
      expect(wearing.options.map((e) => e.$2), contains("Vivi's"));
      expect(find.byKey(const ValueKey('wear-top-ownCut')), findsOneWidget);
      await tap(tester, 'studioPill-wear-top-wearing-made:tee');
      expect((now()[WearSlot.top].source, now()[WearSlot.top].kind),
          (WearSource.made, 'tee'));
      expect(find.byKey(const ValueKey('wear-top-sleeves')), findsOneWidget);
      tester
          .widget<StudioSlider>(find.byKey(const ValueKey('wear-top-hem')))
          .onChanged(0.25);
      await tester.pumpAndSettle();
      expect(now()[WearSlot.top].hem, 0.25);
      await tap(tester, 'wear-top-colour-9c3a32');
      expect(now()[WearSlot.top].colour, 0x9c3a32);
      expect(find.byKey(const ValueKey('wear-top-patternColour-f4f1ea')),
          findsNothing);
      await tap(tester, 'studioPill-wear-top-pattern-checks');
      expect(find.byKey(const ValueKey('wear-top-patternColour-f4f1ea')),
          findsOneWidget);
      // A tank top has no sleeves to set.
      await tap(tester, 'studioPill-wear-top-wearing-made:tank');
      expect(find.byKey(const ValueKey('wear-top-sleeves')), findsNothing);
      await tap(tester, 'studioPartReset');
      expect(now(), CharacterOutfit.asDesigned);
    });

    testWidgets('a body without its own trousers does not offer them',
        (tester) async {
      await show(tester, wearPartId(WearSlot.bottom));
      final wearing = pills(tester, 'wear-bottom-wearing');
      expect(wearing.value, 'none',
          reason: 'its own, which it has none of, is nothing');
      expect(wearing.options.map((e) => e.$1), isNot(contains('own')));
    });

    testWidgets('shoes have a sole colour and no pattern', (tester) async {
      final now = await show(tester, wearPartId(WearSlot.shoes),
          start: CharacterOutfit.asDesigned.wear(
              WearSlot.shoes,
              CharacterOutfit.defaults[WearSlot.shoes]!
                  .copyWith(source: WearSource.made)));
      expect(pills(tester, 'wear-shoes-wearing').options.first.$2, 'Bare feet');
      expect(find.byKey(const ValueKey('wear-shoes-pattern')), findsNothing);
      await tap(tester, 'wear-shoes-sole-9c3a32');
      expect(now()[WearSlot.shoes].sole, 0x9c3a32);
    });

    testWidgets('the outfit changes everything at once', (tester) async {
      final now = await show(tester, outfitPartId);
      await tester.tap(find.byKey(const ValueKey('wearQuick-swim')));
      await tester.pumpAndSettle();
      expect(now()[WearSlot.underwear].kind, 'swim');
      expect(find.byKey(const ValueKey('studioPartReset')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('wearQuick-designed')));
      await tester.pumpAndSettle();
      expect(now(), CharacterOutfit.asDesigned);
    });

    testWidgets('the list has the clothes, the changed ones marked',
        (tester) async {
      String? picked;
      await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
        create: (_) => ThemeNotifier(doLoad: false),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 180,
              child: CharacterShapeList(
                  shape: const CharacterShape(),
                  outfit: CharacterOutfit.asDesigned.swimwear(male: false),
                  selected: 'age',
                  onSelect: (id) => picked = id),
            ),
          ),
        ),
      ));
      await tester.scrollUntilVisible(
          find.byKey(ValueKey('shapePart-${wearPartId(WearSlot.shoes)}')), 60);
      expect(find.byKey(const ValueKey('shapeChanged-outfit')), findsOneWidget);
      expect(find.byKey(ValueKey('shapeChanged-${wearPartId(WearSlot.shoes)}')),
          findsOneWidget);
      expect(
          find.byKey(ValueKey('shapeChanged-${wearPartId(WearSlot.gloves)}')),
          findsNothing);
      final shoes =
          find.byKey(ValueKey('shapePart-${wearPartId(WearSlot.shoes)}'));
      await tester.ensureVisible(shoes);
      await tester.pumpAndSettle();
      await tester.tap(shoes);
      expect(picked, 'wear-shoes');
    });

    testWidgets('at every text size, nothing overflows', (tester) async {
      final skirt = CharacterOutfit.asDesigned.wear(
          WearSlot.bottom,
          CharacterOutfit.defaults[WearSlot.bottom]!.copyWith(
              source: WearSource.made, kind: 'skirt', pattern: 'plaid'));
      for (final scale in const [0.65, 0.85, 1.0, 1.15, 1.25, 1.5]) {
        for (final part in [
          outfitPartId,
          wearPartId(WearSlot.bottom),
          wearPartId(WearSlot.top)
        ]) {
          await show(tester, part, start: skirt, scale: scale);
          expect(tester.takeException(), isNull, reason: '$part at ${scale}x');
        }
      }
    });
  });

  group('decals', () {
    final wardrobe = VrmWardrobe.of(VrmShapeRig(_body()))!;
    final skin = DecalSurface(
        wardrobe.skin,
        Uint32List.fromList([
          for (final p in wardrobe.body.primitives)
            if (p.part == VrmPart.skin) ...p.indices
        ]));
    const d =
        CharacterDecal(id: 'a', source: 'picture:x', along: 0.6, size: 0.1);

    test(
        'a decal on the front of the body covers the front, with the picture across it',
        () {
      final m = makeDecal(wardrobe, d, skin)!;
      final used = m.indices.toSet();
      expect(used.every((i) => wardrobe.groupAt(i) == BodyGroup.torso), isTrue);
      for (final i in used) {
        expect(wardrobe.skin.normals[i * 3 + 2], greaterThan(0),
            reason: 'facing front');
        expect(m.vertices.uv0[i * 2], inInclusiveRange(-0.1, 1.1));
        expect(m.vertices.uv0[i * 2 + 1], inInclusiveRange(-0.1, 1.1));
      }
      // Lifted off the skin a hair, along its normal.
      final i = used.first;
      final lift = math.sqrt([0, 1, 2].fold<double>(0, (s, c) {
        final dd = m.vertices.positions[i * 3 + c] -
            wardrobe.skin.positions[i * 3 + c];
        return s + dd * dd;
      }));
      expect(lift, closeTo(0.0008, 1e-6));
    });

    test('round the back, and on one arm only', () {
      final back = makeDecal(wardrobe, d.copyWith(around: 1), skin)!;
      expect(back.indices.every((i) => wardrobe.skin.normals[i * 3 + 2] < 0),
          isTrue);
      final arm = makeDecal(
          wardrobe, d.copyWith(area: DecalArea.leftArm, along: 0.4), skin)!;
      final used = arm.indices.toSet();
      expect(
          used.every((i) =>
              wardrobe.groupAt(i).index >= BodyGroup.armU.index &&
              wardrobe.groupAt(i).index <= BodyGroup.finger.index),
          isTrue);
      expect(used.every((i) => wardrobe.skin.positions[i * 3] > 0), isTrue,
          reason: 'the left, at +x');
      expect(makeDecal(wardrobe, d.copyWith(area: DecalArea.rightArm), skin),
          isNull,
          reason: 'the test body has no right arm');
    });

    test('on a garment, over it', () {
      final tee = wardrobe.make(
          WearSlot.top,
          CharacterOutfit.defaults[WearSlot.top]!
              .copyWith(source: WearSource.made, kind: 'tee'),
          wardrobe.lines())!;
      // Wide enough to take in whole triangles of the test body's coarse
      // shirt.
      final m = makeDecal(wardrobe, d.copyWith(size: 0.16),
          DecalSurface(tee.vertices, tee.indices, lift: 0.0009))!;
      final i = m.indices.first;
      final r = math.sqrt(m.vertices.positions[i * 3] *
              m.vertices.positions[i * 3] +
          m.vertices.positions[i * 3 + 2] * m.vertices.positions[i * 3 + 2]);
      expect(r, greaterThan(0.12 + 0.0068), reason: 'outside the shirt');
    });

    test('its picture as each look draws it, with a clear edge', () {
      final px = Uint8List.fromList([
        0, 0, 0, 255, 255, 255, 255, 255, //
        200, 40, 40, 255, 10, 10, 10, 0,
      ]);
      final (print, w, h) = decalPicture(px, 2, 2, d);
      expect((w, h), (6, 6));
      expect(print.sublist(0, 4), [0, 0, 0, 0], reason: 'the clear edge');
      final at = ((2 * w) + 2) * 4;
      expect(print.sublist(at, at + 4), [0, 0, 0, 255]);
      final (ink, _, _) =
          decalPicture(px, 2, 2, d.copyWith(mode: 'ink', ink: 0x263552));
      expect(ink.sublist(at, at + 4), [0x26, 0x35, 0x52, 255],
          reason: 'the dark, inked');
      expect(ink[at + 7], 0, reason: 'the white, clear');
      final (faded, _, _) = decalPicture(px, 2, 2, d.copyWith(mode: 'faded'));
      expect(faded[at + 3], lessThan(160));
      final (half, _, _) = decalPicture(px, 2, 2, d.copyWith(opacity: 0.5));
      expect(half[at + 3], 128);
    });

    test('kept and read back the same, junk dropped', () {
      final x = d.copyWith(
          area: DecalArea.rightLeg,
          mode: 'tattoo',
          around: -0.25,
          name: 'Rose');
      expect(
          CharacterDecal.fromJson(
              jsonDecode(jsonEncode(x.toJson())) as Map<String, dynamic>),
          x);
      expect(CharacterDecal.fromJson({'id': 'a'}), isNull);
      final junk = CharacterDecal.fromJson({
        'id': 'a',
        'source': 'picture:y',
        'area': 'tail',
        'size': 9,
        'mode': 'glow'
      })!;
      expect(
          (junk.area, junk.size, junk.mode), (DecalArea.torso, 0.5, 'print'));
    });

    testWidgets('a picture from the library is added, placed and taken off',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var decals = <CharacterDecal>[];
      String? open;
      await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
        create: (_) => ThemeNotifier(doLoad: false),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 330,
              child: StatefulBuilder(
                builder: (context, set) => CharacterDecalControls(
                  decals: decals,
                  open: open,
                  outfit: CharacterOutfit.asDesigned,
                  library: () async => [
                    LibraryAsset(
                        id: 'rose.png',
                        kind: AssetKind.picture,
                        name: 'Rose',
                        added: DateTime(2026)),
                  ],
                  onChanged: (d, o) => set(() {
                    decals = d;
                    open = o;
                  }),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('decalAdd-rose.png')));
      await tester.pumpAndSettle();
      expect((decals.single.source, decals.single.name, open),
          ('picture:rose.png', 'Rose', decals.single.id));
      await tester.tap(find
          .byKey(const ValueKey('studioPill-decal-area-DecalArea.leftArm')));
      await tester.pumpAndSettle();
      expect(decals.single.area, DecalArea.leftArm);
      expect(
          find.byKey(const ValueKey('studioPill-decal-on-top')), findsOneWidget,
          reason: 'its own top is worn');
      expect(find.byKey(const ValueKey('studioPill-decal-on-gloves')),
          findsNothing,
          reason: 'no gloves are worn');
      tester
          .widget<StudioSlider>(find.byKey(const ValueKey('decal-size')))
          .onChanged(0.2);
      await tester.pumpAndSettle();
      expect(decals.single.size, 0.2);
      await tester.tap(find.byKey(const ValueKey('decalRemove')));
      await tester.pumpAndSettle();
      expect(decals, isEmpty);
    });
  });
}
