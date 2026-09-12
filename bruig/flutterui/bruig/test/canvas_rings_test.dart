import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_rings.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/generators.dart';
import 'package:bruig/plugin_system/canvas/render/procedural_cache.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
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
Future<(int, List<int>)> _ink(ProceduralSpec spec, double time,
    {double rate = 0}) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  paintProcedural(canvas, _page, spec, time: time, frameRate: rate);
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

/// _Pictures is a picture store with one drawing in it: a filled square,
/// which is easy to count and easy to see grow.
class _Pictures extends CanvasImageSource {
  _Pictures();

  /// empty is a store with nothing in it: what things look like while a file
  /// is still being read.
  factory _Pictures.empty() = _NoPictures;

  static CanvasVector _drawn(Color color) {
    var recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
        .drawRect(const Rect.fromLTWH(0, 0, 100, 100), Paint()..color = color);
    return CanvasVector(recorder.endRecording(), const Size(100, 100));
  }

  final CanvasVector _square = _drawn(const Color(0xFFFFFFFF));

  /// A second drawing, told apart by its colour: which picture was chosen is
  /// otherwise unanswerable from the pixels. Anything asked for by the name
  /// "red" is this one.
  final CanvasVector _red = _drawn(const Color(0xFFFF0000));

  @override
  ui.Image? resolve(String assetId, BackgroundRemoval removal) => null;

  @override
  CanvasVector? resolveVector(String assetId) => assetId.isEmpty
      ? null
      : assetId == "red"
          ? _red
          : _square;
}

/// _inkWith paints with that store and counts the ink within [within] of the
/// middle of the page.
///
/// Near the middle, because that is where only an icon can be: the rings are
/// circles of at least their starting radius, so nothing they draw lands
/// there.
Future<int> _inkWith(ProceduralSpec spec, double time,
    {double within = 24, double rate = 0}) async {
  var recorder = ui.PictureRecorder();
  paintProcedural(ui.Canvas(recorder), _page, spec,
      time: time, frameRate: rate, images: _Pictures());
  var picture = recorder.endRecording();
  var image = await picture.toImage(400, 300);
  var bytes = (await image.toByteData())!;
  var ink = 0;
  for (var i = 0; i < bytes.lengthInBytes; i += 4) {
    var at = i ~/ 4;
    var away =
        (Offset((at % 400).toDouble(), (at ~/ 400).toDouble()) - _page.center)
            .distance;
    if (away > within) continue;
    if (((bytes.getUint32(i) >> 24) & 0xFF) > 20) ink++;
  }
  image.dispose();
  picture.dispose();
  return ink;
}

/// _NoPictures has read nothing yet.
class _NoPictures extends _Pictures {
  @override
  CanvasVector? resolveVector(String assetId) => null;
}

/// _marks is every pixel an icon drew, as how far it is from the middle of
/// the page, which way round it is, and how strongly it was drawn.
///
/// Rings themselves are kept out of it by giving them no width worth
/// counting -- what is being measured here is the pictures they carry.
Future<List<(double, double, int)>> _marks(ProceduralSpec spec,
    {double time = 3, double rate = 0}) async {
  var recorder = ui.PictureRecorder();
  paintProcedural(ui.Canvas(recorder), _page, spec,
      time: time, frameRate: rate, images: _Pictures());
  var picture = recorder.endRecording();
  var image = await picture.toImage(400, 300);
  var bytes = (await image.toByteData())!;
  var found = <(double, double, int)>[];
  for (var i = 0; i < bytes.lengthInBytes; i += 4) {
    var alpha = (bytes.getUint32(i) >> 8) & 0xFF;
    if (alpha <= 10) continue;
    var at = i ~/ 4;
    var away =
        Offset((at % 400).toDouble(), (at ~/ 400).toDouble()) - _page.center;
    found.add((away.distance, math.atan2(away.dy, away.dx), alpha));
  }
  image.dispose();
  picture.dispose();
  return found;
}

/// _colours is how many pixels of each of the stub's two drawings a picture
/// holds: the white one and the red one. Which picture a place around a ring
/// chose is otherwise unanswerable from the pixels.
Future<(int, int)> _colours(ProceduralSpec spec, {double time = 3}) async {
  // The rings themselves drawn in the colour of the page, so that what is
  // counted is the pictures they carry and not the lines they are on.
  spec = spec.copyWith(
      foreground: const Color(0xFF000000), accent: const Color(0xFF000000));
  var recorder = ui.PictureRecorder();
  paintProcedural(ui.Canvas(recorder), _page, spec,
      time: time, images: _Pictures());
  var picture = recorder.endRecording();
  var image = await picture.toImage(400, 300);
  var bytes = (await image.toByteData())!;
  var white = 0;
  var red = 0;
  for (var i = 0; i < bytes.lengthInBytes; i += 4) {
    var pixel = bytes.getUint32(i);
    // Over an opaque page, so the alpha channel says nothing and the colour
    // is the whole answer: a red picture drawn faintly is a dark red pixel.
    var r = (pixel >> 24) & 0xFF;
    var g = (pixel >> 16) & 0xFF;
    var b = (pixel >> 8) & 0xFF;
    if (r < 40 && g < 40 && b < 40) continue;
    if (r > 40 && g < r ~/ 2) {
      red++;
    } else if (r > 40 && g > 40) {
      white++;
    }
  }
  image.dispose();
  picture.dispose();
  return (white, red);
}

/// _beads is a ring carrying [many] pictures spaced around it, still, so that
/// what moves in a test is only the scatter being asked about.
ProceduralSpec _beads(RingIcon icon, {int many = 6}) => _spec(
      rings: RingSpec(
        count: 1,
        width: 0.0005,
        from: 0.2,
        to: 0.6,
        fadeIn: 0,
        fadeOut: 0,
        edge: RingEdge.hard,
        icons: [icon.copyWith(place: RingIconPlace.around, count: many)],
      ),
      animated: false,
    );

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
    // Four rings, each a quarter of a life behind the last: the first is born
    // when the animation starts and the rest follow it in.
    expect(ring.ageOf(0, 0), 0);
    expect(ring.ageOf(1, 0), -0.25, reason: "not born yet");
    expect(ring.ageOf(1, 0.25), 0);
    expect(ring.ageOf(3, 0.75), 0);

    // And time carries them: the one that was at the start is a tenth of the
    // way out, not back where it began.
    expect(ring.spread(0, 0.1), closeTo(0.1, 0.0001));
    expect(ring.spread(0, 1.05), closeTo(0.05, 0.0001),
        reason: "the one that ran off the end came back at the start");
  });

  test("the set builds up rather than opening on itself", () {
    // Every ring fades in as it is born, and that was always true. What was
    // not is the start: at the first frame the whole set was spread across
    // its life already, so a canvas opened -- and looped -- on nine rings
    // simply being there, which is what "the fade in does not work" was.
    const ring = RingSpec(count: 4);
    expect(ring.buildUp, isTrue);
    var bornAtTheStart = [
      for (var i = 0; i < ring.count; i++)
        if (ring.ageOf(i, 0) >= 0) i,
    ];
    expect(bornAtTheStart, [0]);
    var halfWay = [
      for (var i = 0; i < ring.count; i++)
        if (ring.ageOf(i, 0.5) >= 0) i,
    ];
    expect(halfWay, [0, 1, 2]);
  });

  test("a long fade in is still a fade in", () {
    // The two ends were written as two ifs, and the second overruled the
    // first: a ring set to fade in over the whole of its life *and* out over
    // the whole of it was drawn at one minus its age -- full strength at
    // birth and nothing at death, which is no fade in at all. Turning the
    // fade in up to one was the surest way to switch it off.
    const both = RingSpec(fadeIn: 1, fadeOut: 1);
    expect(both.alphaAt(0), 0, reason: "a ring is born out of nothing");
    expect(both.alphaAt(0.1), lessThan(0.15));
    expect(both.alphaAt(0.5), greaterThan(0.4),
        reason: "and is at its strongest in the middle of its life");
    expect(both.alphaAt(0.9), lessThan(0.15));
    expect(both.alphaAt(1), 0);

    // The same colour at the same age whichever way round the two are.
    const one = RingSpec(fadeIn: 0.8, fadeOut: 0.3);
    const other = RingSpec(fadeIn: 0.3, fadeOut: 0.8);
    expect(one.alphaAt(0.15), closeTo(other.alphaAt(0.85), 0.0001));
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

  testWidgets("an animated background starts on an empty page", (tester) async {
    // Measured off the picture: a line from the middle out to the right, and
    // how many separate rings it crosses.
    Future<int> ringsAcross(double time, {bool buildUp = true}) async {
      var spec = _spec(rings: RingSpec(buildUp: buildUp));
      var recorder = ui.PictureRecorder();
      paintProcedural(ui.Canvas(recorder), _page, spec, time: time);
      var picture = recorder.endRecording();
      var image = await picture.toImage(400, 300);
      var bytes = (await image.toByteData())!;
      var crossed = 0;
      var was = false;
      for (var x = 200; x < 400; x++) {
        var pixel = bytes.getUint32((150 * 400 + x) * 4);
        var on = ((pixel >> 24) & 0xFF) / 255 > 0.02;
        if (on && !was) crossed++;
        was = on;
      }
      image.dispose();
      picture.dispose();
      return crossed;
    }

    late int atTheStart;
    late int later;
    late int withoutBuildUp;
    await tester.runAsync(() async {
      atTheStart = await ringsAcross(0);
      later = await ringsAcross(5);
      withoutBuildUp = await ringsAcross(0, buildUp: false);
    });

    expect(atTheStart, lessThanOrEqualTo(1),
        reason: "the animation opened on a set that was already there");
    expect(later, greaterThan(3), reason: "and it never filled up");
    expect(withoutBuildUp, greaterThan(3),
        reason: "turning it off should give back the set as it was");
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

    // The build-up switch is in the fade section, and reaches the rings.
    await tester.tap(find.text("ARRIVING AND LEAVING"));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("ringBuildUp")));
    await tester.pumpAndSettle();
    expect(spec.rings.buildUp, isFalse);

    await tester.tap(find.text("TEXTURE"));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey("ringGrunge")), "0.6");
    await tester.pumpAndSettle();
    expect(spec.rings.grunge, 0.6);

    // Asking for a number of runs swaps Speed for the number of frames one
    // run takes: a movement that goes round for ever has a speed, and one
    // that is counted is timed against whatever it is under. There is no
    // separate Loop switch -- nought runs is for ever.
    expect(find.byKey(const ValueKey("loop")), findsNothing);
    expect(find.byKey(const ValueKey("speed")), findsOneWidget);
    expect(find.byKey(const ValueKey("passFrames")), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey("loopTimes")));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey("loopTimes")), "1");
    await tester.pumpAndSettle();
    expect(spec.loopTimes, 1);
    expect(find.byKey(const ValueKey("speed")), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey("passFrames")));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey("passFrames")), "90");
    await tester.pumpAndSettle();
    expect(spec.passFrames, 90);

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

  testWidgets("a soft edge rolls the line in, not just its strength",
      (tester) async {
    // A ring is a hairline -- four thousandths of the page, a pixel or two --
    // and a hairline drawn at a fifth of its strength looks very much like a
    // hairline drawn at half of it: what the screen shows either way is one
    // faint line. Rolling the width with the fade is what makes an arrival
    // read as one, and it is what "soft" means as against "hard".
    late int soft;
    late int hard;
    await tester.runAsync(() async {
      // A wide ring, so that what is measured is the width rather than the
      // edges of a hairline, and a moment early in its life.
      const born =
          RingSpec(count: 1, width: 0.05, fadeIn: 0.8, fadeOut: 0.1, from: 0.2);
      (soft, _) = await _ink(_spec(rings: born), 0.6);
      (hard, _) =
          await _ink(_spec(rings: born.copyWith(edge: RingEdge.hard)), 0.6);
    });
    expect(soft, lessThan(hard * 0.9),
        reason: "a soft ring arriving is thinner than a hard one: "
            "$soft against $hard");
  });

  testWidgets("a background that does not loop runs once and stops",
      (tester) async {
    // Told not to loop, the movement runs once in the number of frames it was
    // given and then holds -- and for rings, finished means finished: every
    // ring born, travelled and dissolved, with nothing left on the page.
    late int early;
    late int middling;
    late int atTheEnd;
    late int afterTheEnd;
    await tester.runAsync(() async {
      var once = _spec(rings: const RingSpec(count: 6))
          .copyWith(loopTimes: 1, passFrames: 100);
      // A frame is a frame: the run takes a hundred of them at twenty-five a
      // second, so four seconds.
      Future<int> at(int frame) async {
        var (ink, _) = await _ink(once, frame / 25, rate: 25);
        return ink;
      }

      early = await at(20);
      middling = await at(50);
      atTheEnd = await at(100);
      afterTheEnd = await at(400);
    });

    expect(early, greaterThan(0), reason: "nothing happened at all");
    expect(middling, greaterThan(0));
    expect(atTheEnd, 0,
        reason: "the run was over and there were still rings on the page");
    expect(afterTheEnd, 0, reason: "and it started again afterwards");
  });

  testWidgets("the frames it is given are the frames it takes", (tester) async {
    // The same run, told to take twice as long: half way through the short
    // one and a quarter of the way through the long one are the same moment
    // of the same movement.
    late int quick;
    late int slow;
    await tester.runAsync(() async {
      var rings = const RingSpec(count: 6);
      var short = _spec(rings: rings).copyWith(loopTimes: 1, passFrames: 50);
      var long = _spec(rings: rings).copyWith(loopTimes: 1, passFrames: 100);
      (quick, _) = await _ink(short, 25 / 25, rate: 25);
      (slow, _) = await _ink(long, 50 / 25, rate: 25);
    });
    expect(quick, slow,
        reason: "$quick against $slow: the same moment of the same run");
  });

  test("a pause holds the pattern's clock while the document's runs on", () {
    const spec = ProceduralSpec(
        style: ProceduralStyle.rings,
        animated: true,
        pauseAt: 24,
        pauseFor: 10,
        pauseEase: 6);

    // Before it, frame for frame.
    expect(pausedFrame(0, spec), 0);
    expect(pausedFrame(10, spec), 10);
    expect(pausedFrame(18, spec), 18);

    // Slowing into it: still moving, but not as far as the frames it is
    // spending.
    var slowing = pausedFrame(21, spec);
    expect(slowing, greaterThan(18));
    expect(slowing, lessThan(21));

    // Still, for the frames it was told.
    var atRest = pausedFrame(24, spec);
    expect(pausedFrame(28, spec), atRest);
    expect(pausedFrame(34, spec), atRest);

    // Then moving again, and afterwards running exactly as it would have
    // done -- later by everything the rest cost, which is the pause and the
    // slowing down.
    expect(pausedFrame(37, spec), greaterThan(atRest));
    expect(pausedFrame(60, spec), closeTo(60 - 10 - 6, 0.001));
    expect(pausedFrame(120, spec), closeTo(120 - 10 - 6, 0.001));

    // And nothing anywhere goes backwards: a rest is a rest, not a rewind.
    var was = -1.0;
    for (var f = 0.0; f < 80; f += 0.5) {
      var now = pausedFrame(f, spec);
      expect(now, greaterThanOrEqualTo(was), reason: "went backwards at $f");
      was = now;
    }
  });

  test("no pause asked for is no pause taken", () {
    const none = ProceduralSpec(style: ProceduralStyle.rings, animated: true);
    for (var f = 0.0; f < 50; f += 7) {
      expect(pausedFrame(f, none), f);
    }
  });

  testWidgets("the pause reaches the picture", (tester) async {
    late int during;
    late int later;
    late int without;
    await tester.runAsync(() async {
      var paused = _spec(rings: const RingSpec(count: 6))
          .copyWith(pauseAt: 24, pauseFor: 25, pauseEase: 0);
      // Two moments inside the rest: the same picture, because the pattern's
      // own clock is not running.
      (during, _) = await _ink(paused, 30 / 25, rate: 25);
      (later, _) = await _ink(paused, 45 / 25, rate: 25);
      (without, _) =
          await _ink(_spec(rings: const RingSpec(count: 6)), 45 / 25, rate: 25);
    });
    expect(during, later, reason: "the pattern moved during its rest");
    expect(without, isNot(later),
        reason: "the rest made no difference to the picture");
  });

  testWidgets("a ring carries its icon, and the icon fades with it",
      (tester) async {
    // The whole point of tying a picture to a ring rather than placing it on
    // the canvas: it arrives, swells and dissolves with the ring around it.
    late int early;
    late int later;
    late int none;
    await tester.runAsync(() async {
      var icon = const RingIcon(asset: "badge", ring: 1, size: 0.9);
      var rings =
          const RingSpec(count: 1, from: 0.2, to: 0.9).copyWith(icons: [icon]);
      var spec = _spec(rings: rings);
      // Early in the ring's life it is small and faint; later it is bigger
      // and stronger, and the picture it carries follows both.
      // A window at the middle of the page: an icon tied to a growing ring
      // grows, so how much of that window it covers says how big it has got.
      early = await _inkWith(spec, proceduralPass * 0.15, within: 60);
      later = await _inkWith(spec, proceduralPass * 0.5, within: 60);
      none = await _inkWith(
          _spec(rings: const RingSpec(count: 1)), proceduralPass * 0.5,
          within: 60);
    });

    expect(early, greaterThan(0), reason: "the icon was not drawn at all");
    expect(later, greaterThan(early),
        reason: "the icon did not grow with its ring: $early then $later");
    expect(none, 0, reason: "something was drawn for a ring with no icon");
  });

  test("the icons survive being saved", () {
    var spec = _spec(
        rings: const RingSpec().copyWith(icons: [
      const RingIcon(
          asset: "one",
          ring: 5,
          place: RingIconPlace.around,
          count: 8,
          size: 0.3,
          tinted: true,
          tint: Color(0xFF00FF00),
          turn: 45),
    ]));
    var back = ProceduralSpec.fromJson(spec.toJson()).rings.icons;
    expect(back, hasLength(1));
    expect(back.first.asset, "one");
    expect(back.first.ring, 5);
    expect(back.first.place, RingIconPlace.around);
    expect(back.first.count, 8);
    expect(back.first.tinted, isTrue);
    expect(back.first.tint.toARGB32(), 0xFF00FF00);
    expect(back.first.turn, 45);

    // And a rings background with no icons says nothing about them.
    expect(_spec().toJson()["rings"], isNot(contains("icons")));
  });

  testWidgets("a still background draws its icons too", (tester) async {
    // The bug an SVG icon ran into. A background that does not move is drawn
    // once into a picture and that picture is what gets used from then on --
    // and the cache was rendering it without the pictures, so an icon was
    // missing from every still design. Worse, a file arrives late: the first
    // drawing is made before it has been read, so the answer that was kept
    // was the one without it.
    late ProceduralCache cache;
    late ui.Image? first;
    late ui.Image? second;
    var pictures = _Pictures();
    var spec = _spec(
        animated: false,
        // A set of six and the icon on the second of them: the first ring
        // of a still is at the very start of its life, where a ring is
        // nothing at all, so what it carries is nothing either.
        rings: const RingSpec(count: 6, from: 0.3).copyWith(
            icons: [const RingIcon(asset: "badge", ring: 2, size: 0.9)]));

    await tester.runAsync(() async {
      cache = ProceduralCache();
      // Asking starts it; the answer comes back a moment later.
      expect(cache.imageFor(spec, _page.size, 0, pictures), isNull);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      first = cache.imageFor(spec, _page.size, 0, pictures);

      // And what is kept is keyed on which pictures had arrived, so the
      // drawing made before the file was read is not the drawing that is
      // kept afterwards.
      expect(ProceduralCache.keyFor(spec, _page.size, 0, pictures),
          isNot(ProceduralCache.keyFor(spec, _page.size, 0, _Pictures.empty())),
          reason: "a design draws the same whether its pictures are there "
              "or not");
      second = cache.imageFor(spec, _page.size, 0, pictures);
    });

    expect(first, isNotNull, reason: "nothing was ever drawn");
    // And the icon is in it: a solid square at the middle of a page that
    // otherwise holds one hairline ring.
    late int lit;
    await tester.runAsync(() async {
      var bytes = (await first!.toByteData())!;
      lit = 0;
      for (var i = 0; i < bytes.lengthInBytes; i += 4) {
        var at = i ~/ 4;
        var away = (Offset((at % 400).toDouble(), (at ~/ 400).toDouble()) -
                _page.center)
            .distance;
        if (away < 40 && ((bytes.getUint32(i) >> 24) & 0xFF) > 20) lit++;
      }
    });
    expect(lit, greaterThan(100),
        reason: "the picture that was kept has no icon in it");
    expect(second, isNotNull);
    cache.dispose();
  });

  test("a picture on a ring counts as a picture the document uses", () {
    // The sweep of the picture store deletes anything no saved document names
    // -- so a picture missed here is one that quietly disappears between one
    // session and the next, which is what happened to every ring icon.
    var spec = const ProceduralSpec(style: ProceduralStyle.rings).copyWith(
        rings: const RingSpec().copyWith(icons: [
      const RingIcon(asset: "badge", ring: 2, also: [
        RingPick(asset: "boot"),
        RingPick(asset: "ball", weight: 0),
      ]),
    ]));
    var doc = CanvasDocument(background: CanvasBackground(spec: spec));
    expect(doc.assetIds, contains("badge"));
    // Including the ones an icon is only sometimes drawn as. A picture
    // reached by a roll of the dice is still a picture somebody put there --
    // and one at nought is one they are about to turn back up.
    expect(doc.assetIds, contains("boot"));
    expect(doc.assetIds, contains("ball"));

    // And on a scene that is not the one being edited, which was the other
    // half of it: assetIds read the scene in hand rather than all of them.
    var scenes = const CanvasDocument().withScenes([
      const CanvasScene(id: "a", frames: 10),
      CanvasScene(
          id: "b", frames: 10, background: CanvasBackground(spec: spec)),
    ]);
    expect(scenes.at, 0, reason: "the first scene is the one being edited");
    expect(scenes.assetIds, contains("badge"),
        reason: "a picture in another scene was not counted as used");

    // The shared canvas as well.
    var master = const CanvasDocument().withScenes([
      const CanvasScene(id: "a", frames: 10),
    ]).withMaster(CanvasScene(
        id: "m", frames: 10, background: CanvasBackground(spec: spec)));
    expect(master.assetIds, contains("badge"));
  });

  testWidgets("runs with a gap between them", (tester) async {
    late int firstRun;
    late int inTheGap;
    late int secondRun;
    late int afterTheLast;
    await tester.runAsync(() async {
      // Two runs of forty frames, with twenty frames of stillness between
      // them, at twenty-five frames a second.
      var spec = _spec(rings: const RingSpec(count: 6))
          .copyWith(passFrames: 40, loopTimes: 2, loopGap: 20);
      Future<int> at(int frame) async {
        var (ink, _) = await _ink(spec, frame / 25, rate: 25);
        return ink;
      }

      firstRun = await at(20);
      inTheGap = await at(50);
      secondRun = await at(80);
      afterTheLast = await at(200);
    });

    expect(firstRun, greaterThan(0), reason: "the first run drew nothing");
    expect(inTheGap, 0, reason: "the gap is stillness after a finished run");
    expect(secondRun, greaterThan(0), reason: "the second run never started");
    expect(afterTheLast, 0,
        reason: "it went on running after the last of its runs");
  });

  testWidgets("a movement counted in runs is timed in frames, not speed",
      (tester) async {
    var plain = _spec(rings: const RingSpec());
    expect(plain.inRuns, isFalse, reason: "going round for ever");
    expect(plain.copyWith(loopTimes: 1).inRuns, isTrue);
    expect(plain.copyWith(loopTimes: 3).inRuns, isTrue);
    expect(plain.copyWith(loopGap: 10).inRuns, isTrue);
    // And a still background is not a movement at all.
    expect(plain.copyWith(animated: false, loopTimes: 1).inRuns, isFalse);

    // The settings say the same: Speed while it goes round, Frames once it
    // is counted.
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
                  canvasFrames: 250,
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

    expect(find.byKey(const ValueKey("speed")), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey("loopGap")));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey("loopGap")), "15");
    await tester.pumpAndSettle();
    expect(spec.loopGap, 15);
    expect(find.byKey(const ValueKey("speed")), findsNothing,
        reason: "speed still asked for, on a movement that is counted");
    expect(find.byKey(const ValueKey("passFrames")), findsOneWidget);

    // And the run can be made to fit the canvas, which is otherwise a sum.
    await tester.ensureVisible(find.byKey(const ValueKey("passFramesFit")));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("passFramesFit")));
    await tester.pumpAndSettle();
    expect(spec.passFrames, 250);
  });

  testWidgets("a hard-edged run ends with an empty page", (tester) async {
    // The clearest way to see whether a run has really finished. A hard edge
    // is full strength until the instant a ring dies, so holding the clock
    // exactly at the end of the run left the last ring -- and whatever it
    // was carrying -- on the page for the rest of the canvas.
    late int atTheEnd;
    late int afterwards;
    late int wayAfterwards;
    late int carried;
    var leftOver = 0;
    await tester.runAsync(() async {
      var hard = _spec(
              rings: const RingSpec(
                  count: 6, edge: RingEdge.hard, fadeIn: 1, buildUp: false))
          .copyWith(loopTimes: 1, passFrames: 150);
      Future<int> at(int frame) async {
        var (ink, _) = await _ink(hard, frame / 24, rate: 24);
        return ink;
      }

      atTheEnd = await at(150);
      afterwards = await at(188);
      wayAfterwards = await at(2000);

      // And the picture a ring carries goes with it.
      var withIcon = _spec(
              rings: const RingSpec(count: 6, edge: RingEdge.hard).copyWith(
                  icons: [const RingIcon(asset: "badge", ring: 6, size: 2)]))
          .copyWith(loopTimes: 1, passFrames: 150);
      carried = await _inkWith(withIcon, 188 / 24, within: 80, rate: 24);

      // However the set is spread. Roughened spacing moves where a ring sits
      // in the set, so with some seeds the one at the back is born later
      // again -- and a clock held exactly on the end of the run leaves it
      // there at full strength.
      for (var seed = 1; seed <= 12 && leftOver == 0; seed++) {
        var rough = _spec(
                rings: const RingSpec(
                    count: 6,
                    edge: RingEdge.hard,
                    buildUp: false,
                    to: 0.5,
                    spacingJitter: 1))
            .copyWith(seed: seed, loopTimes: 1, passFrames: 150);
        var (ink, _) = await _ink(rough, 260 / 24, rate: 24);
        leftOver = ink;
      }
    });

    expect(atTheEnd, 0, reason: "the run was over and the page was not empty");
    expect(afterwards, 0, reason: "and it stayed on the page afterwards");
    expect(wayAfterwards, 0);
    expect(carried, 0, reason: "the icon outlived the ring that carried it");
    expect(leftOver, 0, reason: "a roughened set left a ring on the page");
  });

  test("a movement written before there were runs is read as one run", () {
    // The switch it used to be saved with. Not looping meant one run and
    // then hold, which is one time.
    var once = ProceduralSpec.fromJson({
      "style": "rings",
      "animated": true,
      "loop": false,
      "passFrames": 90,
    });
    expect(once.loopTimes, 1);
    expect(once.inRuns, isTrue);
    expect(once.passFrames, 90);
    // And one that did loop still goes round for ever.
    var forever = ProceduralSpec.fromJson(
        {"style": "rings", "animated": true, "loop": true});
    expect(forever.loopTimes, 0);
    expect(forever.inRuns, isFalse);
    // A number that was written wins over the old switch.
    var counted = ProceduralSpec.fromJson({
      "style": "rings",
      "animated": true,
      "loop": false,
      "loopTimes": 3,
    });
    expect(counted.loopTimes, 3);
  });

  testWidgets("the width drags at a thousandth, and shrink says which end",
      (tester) async {
    var spec = _spec(rings: const RingSpec(width: 0.05));
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

    // A width is shown in ten-thousandths, but it runs to a fifth of the
    // page: at the last digit a pixel, dragging the caption across the whole
    // range is two thousand pixels of travel.
    var caption = find.descendant(
        of: find.byKey(const ValueKey("ringWidth")),
        matching: find.text("Width"));
    await tester.ensureVisible(caption);
    await tester.pumpAndSettle();
    await tester.drag(caption, const Offset(50, 0));
    await tester.pumpAndSettle();
    expect(spec.rings.width, closeTo(0.1, 0.0005),
        reason: "fifty pixels should be fifty thousandths");

    // And the two ends of the journey are captioned by which of them a ring
    // sets off from, which shrinking swaps: a field that says "starts at"
    // and is in fact where the ring stops is how a set nobody can see gets
    // built.
    // Opened only if it is shut: the sections remember whether they were,
    // so a test that always taps closes one another test left open.
    if (find.byKey(const ValueKey("ringTo")).evaluate().isEmpty) {
      await tester.ensureVisible(find.text("WHERE THEY RUN"));
      await tester.tap(find.text("WHERE THEY RUN"));
      await tester.pumpAndSettle();
    }
    Finder captionOf(String key, String text) => find.descendant(
        of: find.byKey(ValueKey(key)), matching: find.text(text));
    expect(captionOf("ringFrom", "Starts at"), findsOneWidget);
    expect(captionOf("ringTo", "Ends at"), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey("ringInward")));
    await tester.tap(find.byKey(const ValueKey("ringInward")));
    await tester.pumpAndSettle();
    expect(spec.rings.inward, isTrue);
    expect(captionOf("ringTo", "Starts at"), findsOneWidget,
        reason: "shrinking sets off from the far end");
    expect(captionOf("ringFrom", "Ends at"), findsOneWidget);
    // And the one it starts from is shown first.
    expect(tester.getTopLeft(find.byKey(const ValueKey("ringTo"))).dx,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey("ringFrom"))).dx));
  });

  testWidgets("there are two icons, and they are told apart", (tester) async {
    // Two of them and no more: one in the middle and one set going round.
    // It was a list anybody could add to, which asked a question nobody was
    // asking -- and with only a line break between two of them, the pair read
    // as one icon with a great many settings.
    var spec = _spec(
        rings: const RingSpec(icons: [
      RingIcon(asset: "badge", ring: 1),
      RingIcon(asset: "crest", ring: 2, place: RingIconPlace.around),
    ]));
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
    if (find.byKey(const ValueKey("ringIconRing-middle")).evaluate().isEmpty) {
      await tester.ensureVisible(find.text("ICONS"));
      await tester.tap(find.text("ICONS"));
      await tester.pumpAndSettle();
    }

    // No way to ask for a third.
    expect(find.byKey(const ValueKey("ringIconAdd")), findsNothing);

    // One rule, between the two of them.
    expect(find.byType(CanvasSeparator), findsOneWidget);
    var rule = tester.getTopLeft(find.byType(CanvasSeparator)).dy;
    expect(
        rule,
        greaterThan(tester
            .getTopLeft(find.byKey(const ValueKey("ringIconRing-middle")))
            .dy));
    expect(
        rule,
        lessThan(tester
            .getTopLeft(find.byKey(const ValueKey("ringIconRing-around")))
            .dy));

    // The scatter ranges belong to the set going round; the picture in the
    // middle has nothing to differ from, and what it has instead are the
    // things it may be told rather than inheriting.
    expect(
        find.byKey(const ValueKey("ringIconWhenLeast-around")), findsOneWidget);
    expect(
        find.byKey(const ValueKey("ringIconWhenLeast-middle")), findsNothing);
    expect(
        find.byKey(const ValueKey("ringIconOwnFade-middle")), findsOneWidget);
    expect(find.byKey(const ValueKey("ringIconOwnFade-around")), findsNothing);

    // Taking one away leaves the other where it was, and leaves a way to put
    // a picture back.
    await tester
        .ensureVisible(find.byKey(const ValueKey("ringIconRemove-middle")));
    await tester.tap(find.byKey(const ValueKey("ringIconRemove-middle")));
    await tester.pumpAndSettle();
    expect(spec.rings.icons.length, 1);
    expect(spec.rings.icons.single.place, RingIconPlace.around);
    expect(find.byKey(const ValueKey("ringIconPick-middle")), findsOneWidget);
  });

  testWidgets("pictures around a ring scatter rather than sit on the line",
      (tester) async {
    // Beads on a wire is what they were: same moment, same distance out, same
    // size, same strength, evenly spaced. Each of these says how far one is
    // allowed to differ, and every picture takes its own place in the range.
    late List<(double, double, int)> tidy;
    late List<(double, double, int)> moved;
    late List<(double, double, int)> shifted;
    late List<(double, double, int)> bigger;
    late List<(double, double, int)> turned;
    late List<(double, double, int)> dimmer;
    late List<double> sizes;
    await tester.runAsync(() async {
      const icon = RingIcon(asset: "badge", ring: 1, size: 0.25);
      tidy = await _marks(_beads(icon));

      // Moved through the ring's life: a picture placed at the radius its
      // ring had at another moment is a picture off the line.
      moved = await _marks(_beads(
          icon.copyWith(driftWhen: const RingDrift(least: -0.3, most: 0.3))));

      // Round from where it would have sat. Half a gap, exactly, for every
      // one of them: that lands each picture midway between two of the tidy
      // ones, where there was nothing at all before.
      shifted = await _marks(_beads(
          icon.copyWith(driftWhere: const RingDrift(least: 0.5, most: 0.5))));

      // Half as big again, all of them, which is a quarter more ink across
      // the set and then some.
      bigger = await _marks(_beads(
          icon.copyWith(driftSize: const RingDrift(least: 0.5, most: 0.5))));

      turned = await _marks(_beads(
          icon.copyWith(driftTurn: const RingDrift(least: 45, most: 45))));

      // A share of what the ring is drawn at, so two fifths of it is two
      // fifths. Never more than the ring: the way round it used to be, every
      // number above nought did nothing at all, because a ring already at
      // full strength cannot be made brighter.
      dimmer = await _marks(_beads(
          icon.copyWith(driftFade: const RingDrift(least: 0.4, most: 0.4))));

      // And one picture is not another: asked for a range of sizes, the six
      // of them come out six different sizes rather than all at one end of
      // it. Measured as how much ink each sixth of the page holds.
      var mixed = await _marks(_beads(
          icon.copyWith(driftSize: const RingDrift(least: -0.5, most: 1))));
      sizes = [
        for (var n = 0; n < 6; n++)
          mixed
              .where((m) =>
                  (m.$2 + math.pi * 2) % (math.pi * 2) >= n * math.pi / 3 &&
                  (m.$2 + math.pi * 2) % (math.pi * 2) < (n + 1) * math.pi / 3)
              .length
              .toDouble(),
      ];
    });

    double spread(List<(double, double, int)> marks) =>
        marks.map((m) => m.$1).reduce(math.max) -
        marks.map((m) => m.$1).reduce(math.min);

    expect(tidy, isNotEmpty, reason: "the pictures were not drawn at all");
    // All at one distance out, give or take the width of a picture.
    expect(spread(tidy), lessThan(60));
    expect(spread(moved), greaterThan(spread(tidy) * 1.5),
        reason: "moving them through the ring's life left them on the line");

    // Where the tidy set has nothing -- midway between two of them -- the
    // shifted set has pictures, and the other way about.
    bool near(List<(double, double, int)> marks, double angle) =>
        marks.any((m) => (m.$2 - angle).abs() < 0.12 && (m.$1 - 50).abs() < 25);
    expect(near(tidy, 0), isTrue);
    expect(near(shifted, 0), isFalse,
        reason: "half a gap round is not where they started");
    expect(near(shifted, math.pi / 6), isTrue);

    expect(bigger.length, greaterThan(tidy.length * 1.5));
    expect(dimmer.map((m) => m.$3).reduce(math.max),
        lessThan(tidy.map((m) => m.$3).reduce(math.max) * 0.8),
        reason: "they were drawn at the same strength");
    expect(turned.map((m) => (m.$1, m.$2)).toSet(),
        isNot(tidy.map((m) => (m.$1, m.$2)).toSet()),
        reason: "turning them drew the same picture");

    // Six pictures, six different sizes.
    expect(sizes.toSet().length, greaterThan(4),
        reason: "they all took the same place in the range: $sizes");
  });

  testWidgets("a ring can carry several pictures, some more often than others",
      (tester) async {
    late (int, int) one;
    late (int, int) even;
    late (int, int) lopsided;
    late (int, int) never;
    await tester.runAsync(() async {
      const icon = RingIcon(asset: "badge", ring: 1, size: 0.25);
      one = await _colours(_beads(icon, many: 12));
      even = await _colours(_beads(
          icon.copyWith(also: [const RingPick(asset: "red")]),
          many: 12));
      // Three times as often, so about a quarter of the places take the
      // first picture.
      lopsided = await _colours(_beads(
          icon.copyWith(also: [const RingPick(asset: "red", weight: 3)]),
          many: 12));
      never = await _colours(_beads(
          icon.copyWith(
              weight: 0, also: [const RingPick(asset: "red", weight: 1)]),
          many: 12));
    });

    expect(one.$1, greaterThan(0));
    expect(one.$2, 0, reason: "one picture is the only picture");

    expect(even.$2, greaterThan(0), reason: "the second was never chosen");
    expect(even.$1, greaterThan(0), reason: "the first stopped being chosen");

    double share((int, int) of) => of.$2 / (of.$1 + of.$2);
    expect(share(lopsided), greaterThan(share(even)),
        reason: "a picture at three against one should come up more often");
    expect(share(never), 1.0,
        reason: "a picture at nought should never come up");
  });

  testWidgets("a picture can be told what its ring would have told it",
      (tester) async {
    // Every one of these is off until it is switched on, and off is inherit.
    late int inherited;
    late int ownStrength;
    late int capped;
    late int floored;
    late int arriving;
    late int held;
    late int leaving;
    late int stays;
    late int firstRun;
    late int laterRun;
    await tester.runAsync(() async {
      // Part way into a fade, where what is inherited and what is overruled
      // are plainly different numbers.
      // The rings drawn in the colour of the page, so that what is measured
      // is the picture they carry rather than the lines it is on.
      var young = _spec(
              rings: const RingSpec(
                  count: 1,
                  width: 0.0005,
                  from: 0.5,
                  to: 0.5,
                  fadeIn: 0.5,
                  fadeOut: 0.5,
                  icons: [RingIcon(asset: "badge", ring: 1, size: 0.3)]),
              animated: false)
          .copyWith(
              foreground: const Color(0xFF000000),
              accent: const Color(0xFF000000));
      RingIcon only(ProceduralSpec of) => of.rings.icons.first;
      ProceduralSpec with_(ProceduralSpec of, RingIcon icon) =>
          of.copyWith(rings: of.rings.copyWith(icons: [icon]));

      Future<int> strongest(ProceduralSpec spec, {double time = 0}) async {
        var marks = await _marks(spec, time: time);
        return marks.isEmpty ? 0 : marks.map((m) => m.$3).reduce(math.max);
      }

      // A still ring sits at the very start of its life, where a fade in has
      // barely begun.
      inherited = await strongest(young);
      ownStrength = await strongest(
          with_(young, only(young).copyWith(setOpacity: true, opacity: 0.8)));
      arriving = inherited;
      held = await strongest(with_(young, only(young).copyWith(holdIn: true)));

      // And at the end of one, where the fade out has all but finished.
      var old = young.copyWith(
          animated: true,
          rings: young.rings.copyWith(count: 1, fadeIn: 0, fadeOut: 1));
      leaving = await strongest(with_(old, only(old).copyWith(holdIn: true)),
          time: proceduralPass * 0.98);
      stays = await strongest(
          with_(old, only(old).copyWith(holdIn: true, holdOut: true)),
          time: proceduralPass * 0.98);

      // How big, in fractions of the page rather than of the ring: a picture
      // grows with its ring, and what that means without a limit is that it
      // grows out of the picture.
      var big = with_(young, only(young).copyWith(holdIn: true));
      var ink = await _marks(big);
      inherited = ink.length;
      capped = (await _marks(
              with_(big, only(big).copyWith(setLargest: true, largest: 0.05))))
          .length;
      floored = (await _marks(
              with_(big, only(big).copyWith(setSmallest: true, smallest: 0.5))))
          .length;

      // Said once: drawn on the first run of the movement and not the ones
      // after it. Two runs of sixty frames, and the same moment of each.
      var over = with_(young, only(young).copyWith(holdIn: true))
          .copyWith(animated: true, loopTimes: 3, passFrames: 60);
      var once = with_(over, only(over).copyWith(firstRunOnly: true));
      firstRun = (await _marks(once, time: 20 / 24, rate: 24)).length;
      laterRun = (await _marks(once, time: 80 / 24, rate: 24)).length;
      expect(
          (await _marks(over, time: 80 / 24, rate: 24)).length, greaterThan(0),
          reason: "the second run drew nothing at all, so nothing is proved");
    });

    expect(ownStrength, greaterThan(arriving * 2),
        reason: "its own opacity was ignored in favour of the ring's fade");
    expect(held, greaterThan(arriving * 2),
        reason: "it faded in with the ring after being told not to");
    expect(stays, greaterThan(leaving * 2),
        reason: "it faded out with the ring after being told not to");
    expect(capped, lessThan(inherited),
        reason: "the largest size did not hold it down");
    expect(floored, greaterThan(inherited),
        reason: "the smallest size did not hold it up");
    expect(firstRun, greaterThan(0));
    expect(laterRun, 0, reason: "it was said again on the second run");
  });

  testWidgets("a picture told nothing fades with the ring carrying it",
      (tester) async {
    // Nothing overridden: no opacity of its own, neither fade held, no
    // scatter. What it does is what the ring does.
    late List<int> around;
    late List<int> middle;
    await tester.runAsync(() async {
      Future<List<int>> over(RingIconPlace place) async {
        var spec = _spec(
                rings: RingSpec(
                  count: 1,
                  width: 0.0005,
                  from: 0.4,
                  to: 0.4,
                  fadeIn: 0.4,
                  fadeOut: 0.4,
                  icons: [
                    RingIcon(asset: "badge", ring: 1, size: 0.3, place: place)
                  ],
                ),
                animated: true)
            .copyWith(
                foreground: const Color(0xFF000000),
                accent: const Color(0xFF000000));
        return [
          for (var through in [0.02, 0.5, 0.98])
            await () async {
              var marks = await _marks(spec, time: proceduralPass * through);
              return marks.isEmpty
                  ? 0
                  : marks.map((m) => m.$3).reduce(math.max);
            }(),
        ];
      }

      around = await over(RingIconPlace.around);
      middle = await over(RingIconPlace.middle);
    });

    for (var (what, seen) in [("around", around), ("in the middle", middle)]) {
      expect(seen[1], greaterThan(200),
          reason: "a picture $what was faint in the middle of its life");
      expect(seen[0], lessThan(seen[1] ~/ 2),
          reason: "a picture $what did not fade in: $seen");
      expect(seen[2], lessThan(seen[1] ~/ 2),
          reason: "a picture $what did not fade out: $seen");
    }
  });

  test("a fade that was an offset is not read back as a share", () {
    // It used to be added to one, and the same pair read as a share is a
    // different setting: minus a fifth becomes a fifth of nothing, and the
    // picture never appears again whatever else is done to it.
    var old = RingIcon.fromJson({
      "asset": "badge",
      "ring": 1,
      "driftFade": [-0.5, 0],
    });
    expect(old.driftFade.least, 1);
    expect(old.driftFade.most, 1, reason: "an old fade blanked the picture");

    // And what is written now comes back as it was written.
    var set = const RingIcon(asset: "badge")
        .copyWith(driftFade: const RingDrift(least: 0.2, most: 0.8));
    var back = RingIcon.fromJson(set.toJson());
    expect(back.driftFade.least, 0.2);
    expect(back.driftFade.most, 0.8);

    // Nothing read back can blank a picture outright: a share below nothing
    // is not a share.
    var wild = RingIcon.fromJson({
      "asset": "badge",
      "fadeShare": [-2, 4],
    });
    expect(wild.driftFade.least, 0);
    expect(wild.driftFade.most, 1);
  });

  testWidgets("a colour on a picture is drawn at the picture's strength",
      (tester) async {
    // The tint and the fade are two alphas, and they multiply. With the fade
    // in both of them, a picture at half strength came out a quarter -- and
    // anywhere its ring was faint, colouring a picture switched it off.
    late int plain;
    late int coloured;
    late int fully;
    await tester.runAsync(() async {
      ProceduralSpec at(bool tinted, double opacity) => _spec(
              rings: RingSpec(
            count: 1,
            width: 0.0005,
            from: 0.4,
            to: 0.4,
            fadeIn: 0,
            fadeOut: 0,
            icons: [
              RingIcon(
                asset: "badge",
                ring: 1,
                size: 0.3,
                place: RingIconPlace.around,
                count: 3,
                tinted: tinted,
                tint: const Color(0xFFFFFFFF),
                opacity: opacity,
              )
            ],
          )).copyWith(
              foreground: const Color(0xFF000000),
              accent: const Color(0xFF000000));

      Future<int> strongest(ProceduralSpec spec) async {
        var marks = await _marks(spec);
        return marks.isEmpty ? 0 : marks.map((m) => m.$3).reduce(math.max);
      }

      plain = await strongest(at(false, 0.5));
      coloured = await strongest(at(true, 0.5));
      fully = await strongest(at(true, 1));
    });

    expect(plain, greaterThan(100), reason: "nothing was drawn at all");
    expect(coloured, closeTo(plain, 8),
        reason: "colouring a picture changed how strongly it was drawn");
    expect(fully, greaterThan(coloured + 60),
        reason: "a coloured picture no longer answers to its strength");
  });

  testWidgets("a picture moved through a ring's life still arrives and leaves",
      (tester) async {
    // Held at the two ends of the life instead -- which is what clamping the
    // moment did -- a picture moved earlier sat at the first instant of it
    // for as long as the offset lasted, at whatever strength that instant
    // has. With no fade at that end it is a picture that never arrives: on
    // from the first frame at full strength, however far back it was moved.
    late List<int> ink;
    late List<int> strength;
    await tester.runAsync(() async {
      ProceduralSpec at(double fadeIn, double fadeOut) => _spec(
              rings: RingSpec(
                count: 1,
                width: 0.0005,
                from: 0.4,
                to: 0.4,
                fadeIn: fadeIn,
                fadeOut: fadeOut,
                icons: const [
                  RingIcon(
                    asset: "badge",
                    ring: 1,
                    size: 0.3,
                    place: RingIconPlace.around,
                    count: 8,
                    driftWhen: RingDrift(least: -1, most: -0.1),
                  )
                ],
              ),
              animated: true)
          .copyWith(
              foreground: const Color(0xFF000000),
              accent: const Color(0xFF000000));

      // Nothing to fade in with, so what is on the page at the first instant
      // is whatever has been born by then -- which is almost nothing.
      var blunt = at(0, 0.4);
      ink = [
        for (var through in [0.02, 0.5])
          (await _marks(blunt, time: proceduralPass * through)).length,
      ];
      // And with a fade, the ones that are alive are still fading.
      var soft = at(0.4, 0.4);
      strength = [
        for (var through in [0.5, 0.99])
          await () async {
            var marks = await _marks(soft, time: proceduralPass * through);
            return marks.isEmpty ? 0 : marks.map((m) => m.$3).reduce(math.max);
          }(),
      ];
    });

    expect(ink[1], greaterThan(400),
        reason: "nothing was drawn in the middle of the life: $ink");
    expect(ink[0], lessThan(ink[1] ~/ 4),
        reason: "pictures moved back before the start were drawn anyway: $ink");
    expect(strength[0], greaterThan(150));
    expect(strength[1], lessThan(strength[0] ~/ 2),
        reason: "they were still at full strength at the end: $strength");
  });

  test("a run lasts until the ring at the back has died", () {
    // Whether or not the set builds up, the ring at the back is born very
    // nearly a life after the first and then has its own life to live. A run
    // that allowed only for the spread ended with it still going.
    var building = const ProceduralSpec(style: ProceduralStyle.rings)
        .copyWith(rings: const RingSpec(count: 6));
    var full =
        building.copyWith(rings: const RingSpec(count: 6, buildUp: false));
    expect(proceduralRunSeconds(building),
        closeTo(proceduralPass * (1 + 5 / 6), 0.001));
    expect(proceduralRunSeconds(full),
        closeTo(proceduralPass * (1 + 5 / 6), 0.001));
  });
}
