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

// canvas_background_light_test.dart is the light thrown over a generated
// background.
//
// Every style in the list is a flat field lit the same from edge to edge,
// which is what makes a generated background read as wallpaper rather than as
// a place. The light is drawn over the finished pattern rather than being
// something each generator knows about -- so it works on all of them, and the
// thing worth pinning is that it lands where it is put, reaches the way it is
// aimed, and leaves an unlit background exactly as it was.
//
// Measured off the pixels, because "brighter over here than over there" is a
// thing about pixels and nothing else.

const int _w = 200, _h = 160;
const Rect _page = Rect.fromLTWH(0, 0, 200, 160);

/// _lum renders the background and returns the brightness of every pixel.
Future<List<double>> _lum(ProceduralSpec spec) async {
  var recorder = ui.PictureRecorder();
  paintProcedural(ui.Canvas(recorder), _page, spec);
  var picture = recorder.endRecording();
  var image = await picture.toImage(_w, _h);
  var bytes = (await image.toByteData())!;
  var out = <double>[];
  for (var i = 0; i < bytes.lengthInBytes; i += 4) {
    var p = bytes.getUint32(i);
    out.add((((p >> 24) & 0xFF) + ((p >> 16) & 0xFF) + ((p >> 8) & 0xFF)) / 3);
  }
  image.dispose();
  picture.dispose();
  return out;
}

double _at(List<double> lum, int x, int y) => lum[y * _w + x];

/// _dark is a plain background with nothing on it, so that what the light
/// does is the whole of the difference between two pictures.
const _dark = ProceduralSpec(
  style: ProceduralStyle.plain,
  background: Color(0xFF101010),
  vignette: 0,
);

void main() {
  group("a light over a background", () {
    testWidgets("leaves it alone until it is switched on", (tester) async {
      late List<double> off, on;
      await tester.runAsync(() async {
        off = await _lum(_dark);
        on = await _lum(_dark.copyWith(light: const LightSpec(on: true)));
      });
      expect(off.reduce((a, b) => a + b), lessThan(on.reduce((a, b) => a + b)),
          reason: "a light that is on is light that was not there before");

      // And an unlit background is not merely dim -- it is untouched.
      var bare = await tester.runAsync(
          () => _lum(_dark.copyWith(light: const LightSpec(brightness: 2))));
      expect(bare!, off, reason: "off is off, however bright it would be");
    });

    testWidgets("lands where it is put", (tester) async {
      late List<double> lum;
      await tester.runAsync(() async {
        lum = await _lum(_dark.copyWith(
            light: const LightSpec(on: true, x: 0.2, y: 0.25, size: 0.25)));
      });
      // Brightest at the light, and dark in the far corner.
      expect(_at(lum, 40, 40), greaterThan(_at(lum, 160, 130) + 20));
      expect(_at(lum, 40, 40), greaterThan(_at(lum, 120, 40)),
          reason: "and it falls off across the frame, not just into a corner");
    });

    testWidgets("gets brighter when it is turned up", (tester) async {
      late double dim, bright;
      await tester.runAsync(() async {
        dim = _at(
            await _lum(_dark.copyWith(
                light: const LightSpec(on: true, brightness: 0.3))),
            100,
            48);
        bright = _at(
            await _lum(_dark.copyWith(
                light: const LightSpec(on: true, brightness: 1))),
            100,
            48);
      });
      expect(bright, greaterThan(dim + 20));
    });

    testWidgets("reaches further when it is made bigger", (tester) async {
      late double small, large;
      await tester.runAsync(() async {
        // Out at the edge of the frame, which a small pool does not get to.
        small = _at(
            await _lum(_dark.copyWith(
                light: const LightSpec(on: true, size: 0.15, y: 0.5))),
            190,
            80);
        large = _at(
            await _lum(_dark.copyWith(
                light: const LightSpec(on: true, size: 1.2, y: 0.5))),
            190,
            80);
      });
      expect(large, greaterThan(small + 10));
    });

    testWidgets("holds its edge harder as the falloff goes up", (tester) async {
      late double soft, hard;
      await tester.runAsync(() async {
        // Most of the way out to the edge of the pool: a soft light has
        // almost nothing left there and a hard-edged one is still at full.
        soft = _at(
            await _lum(_dark.copyWith(
                light: const LightSpec(
                    on: true, x: 0.5, y: 0.5, size: 0.3, falloff: 0))),
            140,
            80);
        hard = _at(
            await _lum(_dark.copyWith(
                light: const LightSpec(
                    on: true, x: 0.5, y: 0.5, size: 0.3, falloff: 0.95))),
            140,
            80);
      });
      expect(hard, greaterThan(soft + 20));
    });

    testWidgets("is thrown the way it is aimed, once it rakes", (tester) async {
      late List<double> straight, down, up;
      await tester.runAsync(() async {
        const from = LightSpec(on: true, x: 0.5, y: 0.5, size: 0.3);
        straight = await _lum(_dark.copyWith(light: from));
        // 180 on a compass is down the page; 0 is up it.
        down = await _lum(
            _dark.copyWith(light: from.copyWith(direction: 180, reach: 0.9)));
        up = await _lum(
            _dark.copyWith(light: from.copyWith(direction: 0, reach: 0.9)));
      });

      expect(_at(down, 100, 150), greaterThan(_at(straight, 100, 150) + 10),
          reason: "aimed down the page, the pool reaches the bottom");
      expect(_at(up, 100, 10), greaterThan(_at(straight, 100, 10) + 10));
      expect(_at(down, 100, 150), greaterThan(_at(up, 100, 150) + 20),
          reason: "and the two aims are opposite, not the same long blur");
    });

    test("direction does nothing on its own, which is what reach is for", () {
      // Said here as well as in the panel's hint, because it is the one thing
      // about this control that surprises: a light shone straight at a
      // surface lands as a circle whichever way it was pointed.
      const straight = LightSpec(on: true, reach: 0);
      expect(straight.reach, 0);
    });
  });

  group("what is saved", () {
    test("is nothing at all until there is a light", () {
      expect(const ProceduralSpec().toJson().containsKey("light"), isFalse,
          reason: "nine numbers in every document that has a background");
      var lit = const ProceduralSpec(light: LightSpec(on: true));
      expect(lit.toJson().containsKey("light"), isTrue);
    });

    test("and comes back as it went in", () {
      var lit = const ProceduralSpec(
        light: LightSpec(
          on: true,
          color: Color(0xFF80C0FF),
          brightness: 1.4,
          size: 0.8,
          falloff: 0.7,
          x: 0.1,
          y: 0.9,
          direction: 220,
          reach: 0.6,
        ),
      );
      var back = ProceduralSpec.fromJson(lit.toJson());
      expect(back.light.on, isTrue);
      expect(back.light.color, const Color(0xFF80C0FF));
      expect(back.light.brightness, 1.4);
      expect(back.light.size, 0.8);
      expect(back.light.falloff, 0.7);
      expect(back.light.x, 0.1);
      expect(back.light.y, 0.9);
      expect(back.light.direction, 220);
      expect(back.light.reach, 0.6);
    });

    test("a background saved before there were lights has none", () {
      var old = ProceduralSpec.fromJson({"style": "plain", "seed": 4});
      expect(old.light.on, isFalse);
    });
  });

  group("the panel", () {
    Future<ProceduralSpec> show(WidgetTester tester, ProceduralSpec spec,
        {ValueChanged<ProceduralSpec>? onChanged}) async {
      var current = spec;
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
                  child: StatefulBuilder(
                    builder: (context, setState) => ProceduralSettings(
                      spec: current,
                      onChanged: (s) => setState(() {
                        current = s;
                        onChanged?.call(s);
                      }),
                      onBegin: () {},
                      onCommit: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return current;
    }

    /// openLights opens the section if it is shut. Only if: an expander
    /// remembers whether it was open, and that memory outlives one test, so
    /// tapping the heading blindly shuts it for the test after.
    Future<void> openLights(WidgetTester tester) async {
      if (find.byKey(const ValueKey("lightOn")).evaluate().isNotEmpty) return;
      var heading = find.text("LIGHTS");
      await tester.ensureVisible(heading);
      await tester.pumpAndSettle();
      await tester.tap(heading);
      await tester.pumpAndSettle();
    }

    testWidgets("offers the light on every style, not just one",
        (tester) async {
      // It is drawn over the finished pattern, so there is no style it cannot
      // be used on -- and a section that appeared and disappeared with the
      // style would read as one that only works on some of them.
      for (var style in [
        ProceduralStyle.plain,
        ProceduralStyle.rain,
        ProceduralStyle.metal,
      ]) {
        await show(tester, ProceduralSpec(style: style));
        expect(find.text("LIGHTS"), findsOneWidget, reason: style.name);
      }
    });

    testWidgets("keeps its settings behind the switch", (tester) async {
      await show(tester, const ProceduralSpec());
      await openLights(tester);
      expect(find.byKey(const ValueKey("lightOn")), findsOneWidget);
      expect(find.byKey(const ValueKey("lightBrightness")), findsNothing,
          reason: "seven numbers for a light nobody has switched on");
    });

    testWidgets("and puts them out once it is on", (tester) async {
      await show(tester, const ProceduralSpec(light: LightSpec(on: true)));
      await openLights(tester);
      for (var key in [
        "lightColour",
        "lightBrightness",
        "lightSize",
        "lightFalloff",
        "lightX",
        "lightY",
        "lightDirection",
        "lightReach",
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
    });

    testWidgets("and the switch actually writes one", (tester) async {
      ProceduralSpec? wrote;
      await show(tester, const ProceduralSpec(), onChanged: (s) => wrote = s);
      await openLights(tester);
      await tester.tap(find.byKey(const ValueKey("lightOn")));
      await tester.pumpAndSettle();
      expect(wrote?.light.on, isTrue);
    });
  });
}
