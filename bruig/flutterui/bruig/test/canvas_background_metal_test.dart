import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/procedural_light.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/generators.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/procedural_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_background_metal_test.dart is the Metal texture background.
//
// It is the one style in the list that is a surface rather than a pattern --
// every other one is marks on a ground, and this is the ground. Which means
// the things worth pinning are not "is there ink on the page" but the four
// questions anybody actually has about a sheet of metal: how coarse the
// brushing is, how far the rust has got, how badly it is knocked about, and
// whether it is polished or dull. Each is measured off the picture.

const int _w = 200, _h = 160;
const Rect _page = Rect.fromLTWH(0, 0, 200, 160);

const _steel = ProceduralSpec(
  style: ProceduralStyle.metal,
  background: Color(0xFF6E7378),
  foreground: Color(0xFFDFE6EC),
  accent: Color(0xFFB4561E),
  vignette: 0,
  intensity: 0.8,
);

/// _pixels renders the sheet, as ARGB.
Future<List<int>> _pixels(ProceduralSpec spec) async {
  var recorder = ui.PictureRecorder();
  paintProcedural(ui.Canvas(recorder), _page, spec);
  var picture = recorder.endRecording();
  var image = await picture.toImage(_w, _h);
  var bytes = (await image.toByteData())!;
  var out = <int>[];
  for (var i = 0; i < bytes.lengthInBytes; i += 4) {
    var p = bytes.getUint32(i);
    out.add((p >> 8) | ((p & 0xFF) << 24));
  }
  image.dispose();
  picture.dispose();
  return out;
}

int _r(int argb) => (argb >> 16) & 0xFF;
int _g(int argb) => (argb >> 8) & 0xFF;
int _b(int argb) => argb & 0xFF;

/// _rusty counts the pixels that have gone orange: warm, and well off the
/// grey the sheet is.
int _rusty(List<int> px) =>
    px.where((p) => _r(p) > _b(p) + 30 && _r(p) > 60).length;

/// _grain is how much one row differs from the row under it.
///
/// The measure of brushing specifically, rather than of unevenness in
/// general: the brushing runs across the sheet, so it is the thing that makes
/// neighbouring rows differ. The unevenness in the metal itself and the sheen
/// along it are both smooth, and contribute almost nothing here -- which is
/// what makes this a test of the roughness setting and not of the picture.
double _grain(List<int> px) {
  double lum(int p) => (_r(p) + _g(p) + _b(p)) / 3;
  var sum = 0.0;
  for (var y = 0; y < _h - 1; y++) {
    for (var x = 0; x < _w; x++) {
      sum += (lum(px[y * _w + x]) - lum(px[(y + 1) * _w + x])).abs();
    }
  }
  return sum / (_w * (_h - 1));
}

/// _fineness is how much of the sheet's unevenness is happening from one row
/// to the next, against how much of it happens over three.
///
/// A measure of how *often* the grain repeats rather than of how strong it
/// is, which is what the Size control changes. Brightness differences alone
/// say both at once, and a count of how many times the surface turns over
/// saturates: past a few cycles a column crosses the middle on nearly every
/// row whatever the frequency is. Coarse grain is smooth from row to row and
/// only differs over several, so this comes out low; fine grain differs as
/// much over one row as over three, so it comes out near one.
double _fineness(List<int> px) {
  double lum(int p) => (_r(p) + _g(p) + _b(p)) / 3;
  var near = 0.0, far = 0.0;
  for (var y = 0; y < _h - 3; y++) {
    for (var x = 0; x < _w; x++) {
      var here = lum(px[y * _w + x]);
      near += (here - lum(px[(y + 1) * _w + x])).abs();
      far += (here - lum(px[(y + 3) * _w + x])).abs();
    }
  }
  return far == 0 ? 0 : near / far;
}

/// _marks counts how many pixels one sheet differs from another by enough to
/// see. What a scratch or a dent is, measured against the same sheet without
/// them.
int _marks(List<int> a, List<int> b) {
  var n = 0;
  for (var i = 0; i < a.length; i++) {
    double lum(int p) => (_r(p) + _g(p) + _b(p)) / 3;
    if ((lum(a[i]) - lum(b[i])).abs() > 10) n++;
  }
  return n;
}

void main() {
  group("a sheet of metal", () {
    testWidgets("is rougher when the roughness goes up", (tester) async {
      late double smooth, ground;
      await tester.runAsync(() async {
        smooth = _grain(await _pixels(_steel.copyWith(
            metal: const MetalSpec(roughness: 0, damage: 0, shine: 0.5))));
        ground = _grain(await _pixels(_steel.copyWith(
            metal: const MetalSpec(roughness: 1, damage: 0, shine: 0.5))));
      });
      expect(ground, greaterThan(smooth * 2),
          reason: "brushing is what roughness is, and brushing is grain");
    });

    testWidgets("rusts where it is told to", (tester) async {
      late int clean, rusted, gone;
      await tester.runAsync(() async {
        clean = _rusty(await _pixels(
            _steel.copyWith(metal: const MetalSpec(rust: 0, damage: 0))));
        rusted = _rusty(await _pixels(
            _steel.copyWith(metal: const MetalSpec(rust: 0.4, damage: 0))));
        gone = _rusty(await _pixels(
            _steel.copyWith(metal: const MetalSpec(rust: 1, damage: 0))));
      });
      expect(clean, lessThan(_w * _h ~/ 100), reason: "a clean sheet is clean");
      expect(rusted, greaterThan(clean + 200));
      expect(gone, greaterThan(rusted),
          reason: "and it spreads, rather than being on or off");
    });

    testWidgets("takes the accent colour as its rust", (tester) async {
      // The sheet is the base colour, the sheen is the main one and the rust
      // is the accent -- so a brass plate and a galvanised panel are the same
      // four numbers with different swatches.
      late int orange, green;
      await tester.runAsync(() async {
        var spec =
            _steel.copyWith(metal: const MetalSpec(rust: 0.6, damage: 0));
        orange = _rusty(await _pixels(spec));
        green = _rusty(
            await _pixels(spec.copyWith(accent: const Color(0xFF2F8F4F))));
      });
      expect(orange, greaterThan(green + 200),
          reason: "the corrosion followed the swatch");
    });

    testWidgets("rusts in the colour it was given, whatever that is",
        (tester) async {
      // Darkened towards the middle of a patch, because the middle of one is
      // scale rather than fresh oxide -- but darkened, not mixed towards a
      // brown. Mixed towards a brown, a grey accent came back brown, which is
      // not the colour anybody chose.
      late int warm, cool;
      await tester.runAsync(() async {
        var grey = _steel.copyWith(
            accent: const Color(0xFF9A9A9A),
            metal: const MetalSpec(rust: 0.7, damage: 0));
        var px = await _pixels(grey);
        warm = px.where((p) => _r(p) > _b(p) + 25).length;
        cool = px.where((p) => _b(p) > _r(p) + 25).length;
      });
      expect(warm, lessThan(_w * _h ~/ 200),
          reason: "a grey sheet rusting grey has no warm in it anywhere");
      expect(cool, lessThan(_w * _h ~/ 200));
    });

    testWidgets("is finer grained the smaller the features are asked for",
        (tester) async {
      // Size is the one shared control that decides how big anything on the
      // sheet is, and it has to keep meaning that all the way down: turning
      // it to its smallest is how a blasted, granular finish is reached.
      late double coarse, granular;
      await tester.runAsync(() async {
        const finish = MetalSpec(roughness: 0.6, damage: 0, shine: 0.5);
        coarse = _fineness(
            await _pixels(_steel.copyWith(scale: 0.25, metal: finish)));
        granular = _fineness(
            await _pixels(_steel.copyWith(scale: 0.006, metal: finish)));
      });
      expect(granular, greaterThan(coarse * 1.4));
    });

    testWidgets("is marked up when it is damaged", (tester) async {
      late int few, many;
      await tester.runAsync(() async {
        var kept = await _pixels(
            _steel.copyWith(metal: const MetalSpec(roughness: 0.2, damage: 0)));
        few = _marks(
            await _pixels(_steel.copyWith(
                metal: const MetalSpec(roughness: 0.2, damage: 0.2))),
            kept);
        many = _marks(
            await _pixels(_steel.copyWith(
                metal: const MetalSpec(roughness: 0.2, damage: 1))),
            kept);
      });
      expect(few, greaterThan(50), reason: "a knock is a mark on the sheet");
      expect(many, greaterThan(few * 1.6),
          reason: "and more damage is more of them, not the same few harder");
    });

    testWidgets("catches the light harder when it is polished", (tester) async {
      // A mirror has a narrow bright band along it; a bead-blasted panel has
      // almost none. So the brightest part of a polished sheet is brighter
      // than the brightest part of a matt one.
      late int matt, mirror;
      await tester.runAsync(() async {
        int brightest(List<int> px) => px
            .map((p) => (_r(p) + _g(p) + _b(p)) ~/ 3)
            .reduce((a, b) => a > b ? a : b);
        matt = brightest(await _pixels(_steel.copyWith(
            metal: const MetalSpec(shine: 0, roughness: 0.3, damage: 0))));
        mirror = brightest(await _pixels(_steel.copyWith(
            metal: const MetalSpec(shine: 1, roughness: 0.3, damage: 0))));
      });
      expect(mirror, greaterThan(matt + 10));
    });

    testWidgets("puts the highlight on what is standing at an angle",
        (tester) async {
      // The point of building the sheet as a height field and shining a light
      // across it rather than drawing a bright band over it: a highlight is
      // light coming back off a slope, so it lands on the edges of the dents
      // and along the ridges of the brushing without any of that being
      // arranged. A flat sheet has nothing to catch it with.
      late int flat, relief;
      await tester.runAsync(() async {
        int brightest(List<int> px) => px
            .map((p) => (_r(p) + _g(p) + _b(p)) ~/ 3)
            .reduce((a, b) => a > b ? a : b);
        // Density is how deep the relief goes. At nought the sheet is a
        // photograph of one -- the same noise, lying perfectly flat.
        flat = brightest(await _pixels(_steel.copyWith(
            density: 0,
            metal: const MetalSpec(roughness: 0.6, shine: 0.9, damage: 0.4))));
        relief = brightest(await _pixels(_steel.copyWith(
            density: 0.8,
            metal: const MetalSpec(roughness: 0.6, shine: 0.9, damage: 0.4))));
      });
      expect(relief, greaterThan(flat + 20));
    });

    testWidgets("and takes it off the rust, which scatters", (tester) async {
      // Matt is not a darker colour, it is light going back in every
      // direction instead of one. So the same sheet at the same shine has its
      // highlight put out wherever the rust has taken hold -- which is the
      // thing the old flat band across the sheet could not do, and what makes
      // the edge of a rust patch read as an edge.
      // On the same sheet, in the same picture, at the same setting: the
      // glints are on the metal and not on the rust. Two pictures compared
      // would only say the rusted one came out dimmer, which a darker colour
      // would do just as well.
      late int onMetal, onRust, rustArea;
      await tester.runAsync(() async {
        var px = await _pixels(_steel.copyWith(
            metal: const MetalSpec(roughness: 0.5, shine: 1, rust: 0.6)));
        bool warm(int p) => _r(p) > _b(p) + 30;
        bool glint(int p) => (_r(p) + _g(p) + _b(p)) / 3 > 200;
        onMetal = px.where((p) => !warm(p) && glint(p)).length;
        onRust = px.where((p) => warm(p) && glint(p)).length;
        rustArea = px.where(warm).length;
      });
      expect(rustArea, greaterThan(500), reason: "there is rust to look at");
      expect(onMetal, greaterThan(200), reason: "a polished sheet glints");
      expect(onRust, lessThan(onMetal ~/ 20),
          reason: "and rust scatters, so it has no glint of its own");
    });

    testWidgets("is the same sheet at any size", (tester) async {
      // Every generator here is a pure function of the seed, which is what
      // lets the stage draw at 400px what the export draws at 2400. A Random
      // walked in paint order would give a different sheet every render.
      late List<int> once, twice;
      await tester.runAsync(() async {
        once =
            await _pixels(_steel.copyWith(metal: const MetalSpec(rust: 0.3)));
        twice =
            await _pixels(_steel.copyWith(metal: const MetalSpec(rust: 0.3)));
      });
      expect(once, twice);
    });

    testWidgets("and a different seed is a different sheet", (tester) async {
      late List<int> one, two;
      await tester.runAsync(() async {
        one = await _pixels(_steel.copyWith(seed: 1));
        two = await _pixels(_steel.copyWith(seed: 2));
      });
      expect(one, isNot(two));
    });

    testWidgets("and the light falls on it like anything else", (tester) async {
      late List<int> unlit, lit;
      await tester.runAsync(() async {
        unlit = await _pixels(_steel);
        lit = await _pixels(_steel.copyWith(
            light: const LightSpec(on: true, x: 0.5, y: 0.5, size: 0.3)));
      });
      double lum(List<int> px, int x, int y) {
        var p = px[y * _w + x];
        return (_r(p) + _g(p) + _b(p)) / 3;
      }

      expect(lum(lit, 100, 80), greaterThan(lum(unlit, 100, 80) + 10));
    });
  });

  group("what is saved", () {
    test("is the sheet, and only for a sheet", () {
      expect(const ProceduralSpec().toJson().containsKey("metal"), isFalse);
      expect(
          const ProceduralSpec(style: ProceduralStyle.metal)
              .toJson()
              .containsKey("metal"),
          isTrue);
    });

    test("and comes back as it went in", () {
      var sheet = const ProceduralSpec(
        style: ProceduralStyle.metal,
        metal: MetalSpec(roughness: 0.9, rust: 0.4, damage: 0.7, shine: 0.2),
      );
      var back = ProceduralSpec.fromJson(sheet.toJson());
      expect(back.style, ProceduralStyle.metal);
      expect(back.metal.roughness, 0.9);
      expect(back.metal.rust, 0.4);
      expect(back.metal.damage, 0.7);
      expect(back.metal.shine, 0.2);
    });

    test("and it does not animate", () {
      // Nothing in a sheet of metal moves when the frame advances, and a
      // switch that does nothing is indistinguishable from a broken one.
      expect(ProceduralStyle.metal.canAnimate, isFalse);
    });
  });

  group("the panel", () {
    Future<void> show(WidgetTester tester, ProceduralSpec spec) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider(
          create: (_) => ThemeNotifier(doLoad: false),
          child: Scaffold(
            body: SingleChildScrollView(
              child: CanvasControlScope(
                maxWidth: 320,
                child: SizedBox(
                  width: 320,
                  child: ProceduralSettings(
                    spec: spec,
                    onChanged: (_) {},
                    onBegin: () {},
                    onCommit: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets("asks the four questions a sheet of metal raises",
        (tester) async {
      await show(tester, const ProceduralSpec(style: ProceduralStyle.metal));
      for (var key in [
        "metalRoughness",
        "metalShine",
        "metalRust",
        "metalDamage",
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
    });

    testWidgets("and asks none of them about anything else", (tester) async {
      await show(tester, const ProceduralSpec(style: ProceduralStyle.rain));
      expect(find.byKey(const ValueKey("metalRust")), findsNothing);
    });
  });
}
