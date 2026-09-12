import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/procedural_rings.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/generators.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/procedural_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_rings_test.dart is the Rings background: where a ring is at a given
// moment, and what the settings do to it.
//
// Measured off the picture rather than off the code that draws it: what is
// being checked is that a ring reaches the edge of the page and leaves,
// which is a thing about pixels.

const Rect _page = Rect.fromLTWH(0, 0, 400, 300);

/// _ink renders the background and counts the pixels that are not the
/// backdrop, by row and in total.
Future<(int, List<int>)> _ink(ProceduralSpec spec, double time) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  paintProcedural(canvas, _page, spec, time: time);
  var picture = recorder.endRecording();
  var image = await picture.toImage(400, 300);
  var bytes = (await image.toByteData())!;
  var rows = List<int>.filled(300, 0);
  var total = 0;
  var back = spec.background.toARGB32();
  for (var i = 0; i < bytes.lengthInBytes; i += 4) {
    var pixel = bytes.getUint32(i);
    // The recorded image is RGBA; the spec's colour is ARGB.
    var argb = (pixel >> 8) | ((pixel & 0xFF) << 24);
    if (argb == back) continue;
    rows[(i ~/ 4) ~/ 400]++;
    total++;
  }
  image.dispose();
  picture.dispose();
  return (total, rows);
}

/// _runs is how many separate marks a row of the picture crosses, which is
/// the honest measure of how big the pattern's own unit is: a zoomed-in
/// pattern draws fewer, larger things, while the ink it lays down can stay
/// much the same.
Future<int> _runs(ProceduralSpec spec, List<int> rows) async {
  var recorder = ui.PictureRecorder();
  paintProcedural(ui.Canvas(recorder), _page, spec);
  var picture = recorder.endRecording();
  var image = await picture.toImage(400, 300);
  var bytes = (await image.toByteData())!;
  var runs = 0;
  for (var row in rows) {
    var was = false;
    for (var x = 0; x < 400; x++) {
      var pixel = bytes.getUint32((row * 400 + x) * 4);
      var argb = (pixel >> 8) | ((pixel & 0xFF) << 24);
      var on = argb != spec.background.toARGB32();
      if (on && !was) runs++;
      was = on;
    }
  }
  image.dispose();
  picture.dispose();
  return runs;
}

ProceduralSpec _spec(
        {RingSpec rings = const RingSpec(), bool animated = true}) =>
    ProceduralSpec(
      style: ProceduralStyle.rings,
      seed: 3,
      background: const Color(0xFF000000),
      foreground: const Color(0xFFFFFFFF),
      accent: const Color(0xFFFF0000),
      density: 1,
      intensity: 1,
      vignette: 0,
      animated: animated,
      rings: rings,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("a ring's travel runs from its start to its end and starts again", () {
    const ring = RingSpec(count: 4);
    // Four rings evenly through one life, and each of them a quarter of a
    // life behind the last.
    expect(ring.spread(0, 0), 0);
    expect(ring.spread(1, 0), 0.25);
    expect(ring.spread(3, 0), 0.75);
    // And time carries them: the one that was at the start is a tenth of the
    // way out, not back where it began.
    expect(ring.spread(0, 0.1), closeTo(0.1, 0.0001));
    expect(ring.spread(3, 0.3), closeTo(0.05, 0.0001),
        reason: "the one that ran off the end came back at the start");
  });

  test("the edges say how a ring arrives and leaves", () {
    const soft = RingSpec(fadeIn: 0.2, fadeOut: 0.2);
    expect(soft.alphaAt(0), 0);
    expect(soft.alphaAt(0.1), greaterThan(0));
    expect(soft.alphaAt(0.1), lessThan(0.6));
    expect(soft.alphaAt(0.5), 1);
    expect(soft.alphaAt(1), 0);

    const hard = RingSpec(fadeIn: 0.2, fadeOut: 0.2, edge: RingEdge.hard);
    expect(hard.alphaAt(0.1), 1, reason: "hard is on or off, not a roll");
    expect(hard.alphaAt(0), 0);
  });

  test("a new ring arrives faintly rather than appearing", () {
    // A ring spends the start of its life small and near the middle, where a
    // few per cent of its travel is a few pixels of radius. Fading in over a
    // tenth of the travel, it was already at three quarters of its strength
    // by the time it was big enough to notice, and what anybody saw was a
    // ring appearing rather than arriving.
    const ring = RingSpec();
    var born = ring.spread(0, 0);
    expect(ring.alphaAt(born), 0);

    // By the time the next one is born behind it -- one twelfth of a life --
    // the first is still faint.
    expect(ring.alphaAt(1 / ring.count), lessThan(0.3),
        reason: "a ring is at ${(ring.alphaAt(1 / ring.count) * 100).round()}"
            "% by the time the next one starts");
    // And it is at its full strength well before it leaves.
    expect(ring.alphaAt(0.5), 1);
  });

  testWidgets("the rings reach the edge of the page and leave it",
      (tester) async {
    // The bug this was written for: the rings expanded a little and snapped
    // back, because every ring was drawn at one of a handful of radii and the
    // only thing that moved was the offset between them.
    late List<int> early;
    late List<int> later;
    await tester.runAsync(() async {
      // One ring, so what is measured is that ring.
      var spec = _spec(
          rings: const RingSpec(
              count: 1, from: 0, to: 1, fadeIn: 0, fadeOut: 0, width: 0.01));
      (_, early) = await _ink(spec, 0.5);
      (_, later) = await _ink(spec, 3.5);
    });

    // How far down the page the topmost ink is: a growing ring reaches the
    // top of the page, and a ring that has left it has none there at all.
    int topmost(List<int> rows) {
      var at = rows.indexWhere((count) => count > 0);
      return at < 0 ? 999 : at;
    }

    expect(topmost(early), greaterThan(0),
        reason: "a young ring is still around the middle");
    expect(topmost(later), lessThan(topmost(early)),
        reason: "an older ring has grown out towards the edge");
  });

  testWidgets("shrinking is a ring born at the outside", (tester) async {
    // Not the same journey with the clock run backwards: doing both -- the
    // time and the travel -- cancelled out, and shrinking drew exactly the
    // picture expanding did.
    late List<int> growing;
    late List<int> shrinking;
    await tester.runAsync(() async {
      // One ring, a little way into its life. Growing, it is still small and
      // around the middle; shrinking, it is large and near the edges.
      const born = RingSpec(count: 1, from: 0.05, to: 1, fadeIn: 0, fadeOut: 0);
      (_, growing) = await _ink(_spec(rings: born), 1.0);
      (_, shrinking) =
          await _ink(_spec(rings: born.copyWith(inward: true)), 1.0);
    });

    int topmost(List<int> rows) {
      var at = rows.indexWhere((count) => count > 0);
      return at < 0 ? 999 : at;
    }

    expect(topmost(shrinking), lessThan(topmost(growing)),
        reason: "a shrinking ring starts wide: it reaches further up the "
            "page at the same moment than a growing one does");
  });

  testWidgets("how many, how wide, and where from", (tester) async {
    late int few;
    late int many;
    late int wide;
    late List<int> corner;
    await tester.runAsync(() async {
      (few, _) = await _ink(
          _spec(rings: const RingSpec(count: 2), animated: false), 0);
      (many, _) = await _ink(
          _spec(rings: const RingSpec(count: 10), animated: false), 0);
      (wide, _) = await _ink(
          _spec(rings: const RingSpec(count: 2, width: 0.02), animated: false),
          0);
      (_, corner) = await _ink(
          _spec(
              rings: const RingSpec(count: 3, centreX: 0, centreY: 0),
              animated: false),
          0);
    });

    expect(many, greaterThan(few), reason: "more rings is more ink");
    expect(wide, greaterThan(few), reason: "a wider ring is more ink");
    // Rings coming out of the top left corner leave the bottom of the page
    // emptier than the top.
    var top = corner.take(80).fold<int>(0, (a, b) => a + b);
    var bottom = corner.skip(220).fold<int>(0, (a, b) => a + b);
    expect(top, greaterThan(bottom),
        reason: "the rings did not come from the corner they were told to");
  });

  testWidgets("texture changes the picture without changing the rings",
      (tester) async {
    late int plain;
    var textured = <String, int>{};
    await tester.runAsync(() async {
      (plain, _) = await _ink(
          _spec(rings: const RingSpec(count: 6), animated: false), 0);
      for (var (name, spec) in [
        ("noise", const RingSpec(count: 6, noise: 1)),
        ("glitch", const RingSpec(count: 6, glitch: 1)),
        ("distortion", const RingSpec(count: 6, distortion: 1)),
        ("grunge", const RingSpec(count: 6, grunge: 1)),
      ]) {
        var (ink, _) = await _ink(_spec(rings: spec, animated: false), 0);
        textured[name] = ink;
      }
    });

    for (var entry in textured.entries) {
      expect(entry.value, isNot(plain),
          reason: "${entry.key} drew the same picture as a plain ring");
      expect(entry.value, greaterThan(0),
          reason: "${entry.key} drew nothing at all");
    }
    // Grunge eats the line away, so it is the one that draws less.
    expect(textured["grunge"]!, lessThan(plain));
  });

  test("the settings survive being saved", () {
    var spec = _spec(
        rings: const RingSpec(
      count: 7,
      width: 0.02,
      from: 0.2,
      to: 1.4,
      centreX: 0.1,
      centreY: 0.9,
      inward: true,
      spacing: 0.3,
      spacingJitter: 0.4,
      widthJitter: 0.5,
      colorJitter: 0.6,
      accentEvery: 3,
      fadeIn: 0.3,
      fadeOut: 0.4,
      edge: RingEdge.hard,
      noise: 0.7,
      glitch: 0.8,
      distortion: 0.9,
      grunge: 1,
    ));
    var back = ProceduralSpec.fromJson(spec.toJson()).rings;
    expect(back.count, 7);
    expect(back.to, 1.4);
    expect(back.inward, isTrue);
    expect(back.edge, RingEdge.hard);
    expect(back.grunge, 1);
    expect(back.centreY, 0.9);

    // And a background that is not rings does not carry them about.
    var plain = ProceduralSpec(style: ProceduralStyle.bokeh, rings: spec.rings);
    expect(plain.toJson().containsKey("rings"), isFalse);
  });

  testWidgets("turning a background does not zoom into it", (tester) async {
    // The pattern is drawn in a rectangle grown to cover the corners, so
    // that turning it does not sweep an empty wedge into view -- and every
    // generator sizes its cell, its glyph or its disc as a fraction of the
    // shorter side of what it is given. Grown by half the width plus half
    // the height, as it was, that fraction was several times bigger: turning
    // a background by one degree zoomed a long way into it.
    late int straight;
    late int turned;
    await tester.runAsync(() async {
      var spec = ProceduralSpec(
        style: ProceduralStyle.dotGrid,
        seed: 5,
        background: const Color(0xFF000000),
        foreground: const Color(0xFFFFFFFF),
        accent: const Color(0xFFFFFFFF),
        density: 1,
        intensity: 1,
        vignette: 0,
      );
      // A dozen rows down the page rather than one: which dots happen to be
      // bright on any single row is the noise field's business.
      var rows = [for (var y = 40; y < 280; y += 20) y];
      straight = await _runs(spec, rows);
      turned = await _runs(spec.copyWith(rotation: 1), rows);
    });

    // A degree of turn is not a change of size: a line across the middle
    // crosses about as many dots as it did.
    expect(straight, greaterThan(4), reason: "nothing to measure");
    expect(turned, greaterThan(straight * 0.7),
        reason: "a row crossed $straight dots, and $turned after a degree "
            "of turn");
  });

  testWidgets("the settings panel drives the rings", (tester) async {
    // The controls exist only for this style, and each of them reaches the
    // ring settings rather than the handful every generator shares.
    var spec = _spec(rings: const RingSpec());
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => CanvasControlScope(
                maxWidth: 240,
                child: ProceduralSettings(
                  spec: spec,
                  onBegin: () {},
                  onCommit: () {},
                  onChanged: (next) => setState(() => spec = next),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey("ringCount")), "24");
    await tester.pumpAndSettle();
    expect(spec.rings.count, 24);

    // The four sections after the first are shut until they are wanted, and
    // what is shut is not built: seventeen number fields is seventeen text
    // fields with their own state, and building them all is forty
    // milliseconds of every build of this panel.
    expect(find.byKey(const ValueKey("ringTo")), findsNothing);
    expect(find.byKey(const ValueKey("ringGrunge")), findsNothing);

    await tester.tap(find.text("WHERE THEY RUN"));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey("ringTo")), "1.5");
    await tester.pumpAndSettle();
    expect(spec.rings.to, 1.5);

    await tester.tap(find.byKey(const ValueKey("ringInward")));
    await tester.pumpAndSettle();
    expect(spec.rings.inward, isTrue);

    await tester.tap(find.text("TEXTURE"));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey("ringGrunge")), "0.6");
    await tester.pumpAndSettle();
    expect(spec.rings.grunge, 0.6);

    // And the two shared controls the rings say in their own words are not
    // offered twice: Size and Variation did nothing at all on this style.
    expect(find.text("Size"), findsNothing);
    expect(find.text("Variation"), findsNothing);

    // And they are not offered for a style that has no rings in it.
    spec = spec.copyWith(style: ProceduralStyle.bokeh);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CanvasControlScope(
              maxWidth: 240,
              child: ProceduralSettings(
                spec: spec,
                onBegin: () {},
                onCommit: () {},
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("ringCount")), findsNothing);
  });
}
