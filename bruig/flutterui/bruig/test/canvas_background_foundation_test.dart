import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/procedural_effects.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_palettes.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/presets/background_looks.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/generators.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/procedural_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_background_foundation_test.dart is what every background style
// shares: the effects laid over the pattern, the palettes, and the looks.
//
// The effects are measured off the pixels, because "the middle is kept clear"
// is a claim about pixels and nothing else.

const int _w = 160, _h = 90;
const Rect _page = Rect.fromLTWH(0, 0, 160, 90);

/// _pixels renders [spec] and returns every pixel as 0xRRGGBBAA.
Future<List<int>> _pixels(ProceduralSpec spec) async {
  var recorder = ui.PictureRecorder();
  paintProcedural(ui.Canvas(recorder), _page, spec, time: 1.5, frameRate: 30);
  var picture = recorder.endRecording();
  var image = await picture.toImage(_w, _h);
  var bytes = (await image.toByteData())!;
  var out = [
    for (var i = 0; i < bytes.lengthInBytes; i += 4) bytes.getUint32(i),
  ];
  image.dispose();
  picture.dispose();
  return out;
}

/// _differs is how many pixels inside [r] are not the base colour.
int _differs(List<int> px, Rect r, Color base) {
  var want = (base.toARGB32() & 0xFFFFFF) << 8 | 0xFF;
  var n = 0;
  for (var y = r.top.round(); y < r.bottom.round(); y++) {
    for (var x = r.left.round(); x < r.right.round(); x++) {
      var p = px[y * _w + x];
      var d = [24, 16, 8]
          .map((s) => (((p >> s) & 0xFF) - ((want >> s) & 0xFF)).abs())
          .reduce((a, b) => a + b);
      if (d > 6) n++;
    }
  }
  return n;
}

/// _busy is a dense circuit board in flat colours on a flat base: pattern
/// nearly everywhere, so taking it away somewhere shows.
const _busy = ProceduralSpec(
  style: ProceduralStyle.lineGrid,
  background: Color(0xFF000000),
  foreground: Color(0xFFFFFFFF),
  accent: Color(0xFFFFFFFF),
  intensity: 1,
  scale: 0.03,
  vignette: 0,
);

void main() {
  group("effects", () {
    test("are not saved while they are off, and come back as they went", () {
      expect(_busy.toJson().containsKey("effects"), isFalse);
      var on = _busy.copyWith(
          effects: const EffectsSpec(
              grain: 0.4, glow: 1.2, clear: ClearArea.left, hue: 30));
      var back = ProceduralSpec.fromJson(on.toJson());
      expect(back.effects.grain, 0.4);
      expect(back.effects.glow, 1.2);
      expect(back.effects.clear, ClearArea.left);
      expect(back.effects.hue, 30);
      // Only what differs from the default is written.
      expect((on.toJson()["effects"] as Map).length, 4);
    });

    testWidgets("keeping the middle clear takes the pattern out of it",
        (tester) async {
      late List<int> plain, cleared;
      await tester.runAsync(() async {
        plain = await _pixels(_busy);
        cleared = await _pixels(_busy.copyWith(
            effects: const EffectsSpec(
                clear: ClearArea.centre, clearSize: 0.5, clearSoftness: 0)));
      });
      var middle = Rect.fromCenter(center: _page.center, width: 30, height: 16);
      var corner = const Rect.fromLTWH(0, 0, 20, 12);
      expect(_differs(plain, middle, _busy.background), greaterThan(20));
      expect(_differs(cleared, middle, _busy.background), 0);
      // And only the middle: the corners keep their lines.
      expect(_differs(cleared, corner, _busy.background),
          _differs(plain, corner, _busy.background));
    });

    testWidgets("keeping a side clear empties that side and not the other",
        (tester) async {
      late List<int> px;
      await tester.runAsync(() async {
        px = await _pixels(_busy.copyWith(
            effects: const EffectsSpec(
                clear: ClearArea.left, clearSize: 0.4, clearSoftness: 0)));
      });
      expect(_differs(px, const Rect.fromLTWH(0, 0, 50, 90), _busy.background),
          0);
      expect(
          _differs(px, const Rect.fromLTWH(110, 0, 50, 90), _busy.background),
          greaterThan(50));
    });

    testWidgets("a focus fades the pattern away from it", (tester) async {
      late List<int> px;
      await tester.runAsync(() async {
        px = await _pixels(_busy.copyWith(
            effects: const EffectsSpec(
                focus: 1, focusX: 0, focusY: 0, focusSize: 0.05)));
      });
      // Bright lines near the corner it is focused on; none at all at the
      // far one, where it has faded to nothing.
      expect(_differs(px, const Rect.fromLTWH(0, 0, 30, 20), _busy.background),
          greaterThan(20));
      expect(
          _differs(
              px, const Rect.fromLTWH(140, 70, 20, 20), _busy.background),
          0);
    });

    testWidgets("the pattern's opacity leaves the base showing through it",
        (tester) async {
      late List<int> full, none;
      await tester.runAsync(() async {
        full = await _pixels(_busy);
        none = await _pixels(
            _busy.copyWith(effects: const EffectsSpec(opacity: 0)));
      });
      expect(_differs(full, _page, _busy.background), greaterThan(500));
      expect(_differs(none, _page, _busy.background), 0);
    });

    testWidgets("grain marks a flat background, and moves only when asked",
        (tester) async {
      const flat = ProceduralSpec(
          background: Color(0xFF808080), vignette: 0, animated: true);
      late List<int> a, b, still;
      await tester.runAsync(() async {
        var grainy = flat.copyWith(effects: const EffectsSpec(grain: 1));
        a = await _pixels(grainy);
        var recorder = ui.PictureRecorder();
        paintProcedural(ui.Canvas(recorder), _page, grainy,
            time: 2, frameRate: 30);
        var image = await recorder.endRecording().toImage(_w, _h);
        var bytes = (await image.toByteData())!;
        b = [
          for (var i = 0; i < bytes.lengthInBytes; i += 4) bytes.getUint32(i)
        ];
        still = await _pixels(flat.copyWith(
            effects: const EffectsSpec(grain: 1, grainMoves: false)));
      });
      expect(_differs(a, _page, flat.background), greaterThan(1000));
      expect(a, isNot(b), reason: "a later frame is a new draw of the grain");
      expect(still, isNot(a),
          reason: "still grain is a different draw from the moving one");
    });

    testWidgets("a colour grade changes the whole frame, base and all",
        (tester) async {
      const red = ProceduralSpec(background: Color(0xFFFF0000), vignette: 0);
      late List<int> px;
      await tester.runAsync(() async {
        px = await _pixels(
            red.copyWith(effects: const EffectsSpec(saturation: -1)));
      });
      var p = px[45 * _w + 80];
      var r = (p >> 24) & 0xFF, g = (p >> 16) & 0xFF, b = (p >> 8) & 0xFF;
      expect((r - g).abs(), lessThan(3), reason: "no saturation is grey");
      expect((g - b).abs(), lessThan(3));
    });
  });

  group("palettes", () {
    test("put all of the colours on at once, and are recognised after", () {
      var p = paletteNamed("Neon")!;
      var s = p.on(_busy);
      expect(s.background, p.base);
      expect(s.gradient?.to, p.baseTo);
      expect(s.foreground, p.main);
      expect(s.accent, p.accent);
      expect(p.matches(s), isTrue);
      expect(paletteNamed("Mono")!.on(s).gradient, isNull,
          reason: "a palette with a flat base takes a fade away");
    });
  });

  group("looks", () {
    test("every style that has them gives each one a different name", () {
      for (var style in ProceduralStyle.values) {
        var names = looksFor(style).map((l) => l.name).toList();
        expect(names.toSet().length, names.length, reason: style.label);
        for (var look in looksFor(style)) {
          expect(look.spec.style, style, reason: look.name);
        }
      }
    });

    test("a look keeps the document's timing and is recognised after", () {
      var look = looksFor(ProceduralStyle.circuit)[1];
      var mine = const ProceduralSpec(
          animated: true, passFrames: 300, loopTimes: 2, pauseFor: 10);
      var s = withLook(mine, look);
      expect(s.style, ProceduralStyle.circuit);
      expect(s.animated, isTrue);
      expect(s.passFrames, 300);
      expect(s.loopTimes, 2);
      expect(s.pauseFor, 10);
      expect(lookMatching(s), same(look));
      expect(lookMatching(s.copyWith(density: 0.123)), isNull);
    });
  });

  group("the settings", () {
    Future<ProceduralSpec Function()> pump(
        WidgetTester tester, ProceduralSpec start) async {
      var current = start;
      // Tall enough for the whole list of styles to be on screen at once.
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider(
          create: (_) => ThemeNotifier(doLoad: false),
          child: Scaffold(
            body: SingleChildScrollView(
              child: CanvasControlScope(
                maxWidth: 300,
                child: SizedBox(
                  width: 300,
                  child: StatefulBuilder(
                    builder: (context, setState) => ProceduralSettings(
                      spec: current,
                      onChanged: (s) => setState(() => current = s),
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
      return () => current;
    }

    testWidgets("choosing a style starts from its first look",
        (tester) async {
      var spec = await pump(tester, const ProceduralSpec());
      await tester.tap(find.byKey(const ValueKey("backgroundStyle")));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Circuit").last);
      await tester.pumpAndSettle();
      expect(spec().style, ProceduralStyle.circuit);
      expect(lookMatching(spec())?.name,
          looksFor(ProceduralStyle.circuit).first.name);
    });

    testWidgets("a look is chosen by clicking its picture", (tester) async {
      var spec = await pump(tester, looksFor(ProceduralStyle.bokeh).first.spec);
      var other = looksFor(ProceduralStyle.bokeh)[2];
      await tester.tap(find.byKey(ValueKey("look-${other.name}")));
      await tester.pumpAndSettle();
      expect(lookMatching(spec()), same(other));
    });

    testWidgets("a palette recolours the background in one go",
        (tester) async {
      var spec = await pump(tester, const ProceduralSpec());
      await tester.tap(find.byKey(const ValueKey("backgroundPalette")));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Sunset").last);
      await tester.pumpAndSettle();
      expect(paletteNamed("Sunset")!.matches(spec()), isTrue);
    });

    testWidgets("the effects are behind a heading and set from there",
        (tester) async {
      var spec = await pump(tester, const ProceduralSpec());
      expect(find.byKey(const ValueKey("fx-grain")), findsNothing);
      await tester.tap(find.text("EFFECTS"));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(
              of: find.byKey(const ValueKey("fx-grain")),
              matching: find.byType(EditableText)),
          "0.5");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(spec().effects.grain, 0.5);
      // And the size only once there is grain to size.
      expect(find.byKey(const ValueKey("fx-grainSize")), findsOneWidget);
    });
  });
}
