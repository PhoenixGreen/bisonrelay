import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/pitch.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_pitch_test.dart is about the one thing that makes a tactics diagram
// worth anything: the markings being where the laws say they are.
//
// The pitch is drawn to scale and letterboxed inside whatever rectangle it is
// given, and the presets place players in metres through the same mapping. If
// the mapping and the painter ever disagreed, every player on the pitch would
// be in the wrong place by however much -- and nothing about the picture would
// look obviously broken.

void main() {
  test("the pitch keeps its proportions in a wide frame", () {
    var metrics =
        pitchRect(const Rect.fromLTWH(0, 0, 2000, 600), PitchSport.football);
    expect(metrics.area.width / metrics.area.height, closeTo(105 / 68, 0.001));
    // Letterboxed rather than stretched: the frame is far wider than a pitch,
    // so the pitch cannot have used all of it.
    expect(metrics.area.width, lessThan(2000));
  });

  test("the pitch keeps its proportions in a tall frame", () {
    var metrics =
        pitchRect(const Rect.fromLTWH(0, 0, 600, 2000), PitchSport.football);
    expect(metrics.area.width / metrics.area.height, closeTo(105 / 68, 0.001));
    expect(metrics.area.height, lessThan(2000));
  });

  test("the pitch is centred in its frame", () {
    var rect = const Rect.fromLTWH(0, 0, 1600, 900);
    var metrics = pitchRect(rect, PitchSport.football);
    expect(metrics.area.center.dx, closeTo(rect.center.dx, 0.001));
    expect(metrics.area.center.dy, closeTo(rect.center.dy, 0.001));
  });

  test("the pitch never touches the edge of the frame", () {
    // A pitch drawn hard against the edge has its touchline markings half cut
    // off, and a player on the touchline has nowhere to be.
    var rect = const Rect.fromLTWH(0, 0, 1000, 1000);
    var metrics = pitchRect(rect, PitchSport.football);
    expect(metrics.area.left, greaterThan(rect.left));
    expect(metrics.area.right, lessThan(rect.right));
    expect(metrics.area.top, greaterThan(rect.top));
    expect(metrics.area.bottom, lessThan(rect.bottom));
  });

  test("metres map onto the markings", () {
    var metrics =
        pitchRect(const Rect.fromLTWH(0, 0, 1600, 900), PitchSport.football);

    // The corners.
    expect(metrics.at(0, 0), _near(metrics.area.bottomLeft));
    expect(metrics.at(105, 68), _near(metrics.area.topRight));

    // The halfway line and the centre spot.
    expect(metrics.at(52.5, 34).dx, closeTo(metrics.area.center.dx, 0.5));
    expect(metrics.at(52.5, 34).dy, closeTo(metrics.area.center.dy, 0.5));

    // y runs up the pitch, not down the screen, which is the axis flip most
    // easily got backwards.
    expect(metrics.at(0, 68).dy, lessThan(metrics.at(0, 0).dy));
  });

  test("one scale serves both axes, so a circle is a circle", () {
    var metrics =
        pitchRect(const Rect.fromLTWH(0, 0, 1600, 900), PitchSport.football);
    var horizontal = (metrics.at(10, 0) - metrics.at(0, 0)).distance;
    var vertical = (metrics.at(0, 10) - metrics.at(0, 0)).distance;
    expect(horizontal, closeTo(vertical, 0.001));
    expect(metrics.m(10), closeTo(horizontal, 0.001));
  });

  test("every sport has its own shape and none is degenerate", () {
    for (var sport in PitchSport.values) {
      var metrics = pitchRect(const Rect.fromLTWH(0, 0, 1200, 800), sport);
      expect(metrics.area.width, greaterThan(0), reason: sport.name);
      expect(metrics.area.height, greaterThan(0), reason: sport.name);
      expect(metrics.area.width / metrics.area.height,
          closeTo(sport.aspect, 0.001),
          reason: sport.name);
      expect(metrics.scale, greaterThan(0), reason: sport.name);
      expect(metrics.widthMetres, greaterThan(0), reason: sport.name);
    }
  });

  test("a tiny frame does not produce a negative pitch", () {
    // Reachable from a background element dragged very small, and a negative
    // rectangle draws nothing while still being selectable, which is a way to
    // lose an element.
    var metrics =
        pitchRect(const Rect.fromLTWH(0, 0, 12, 8), PitchSport.football);
    expect(metrics.area.width, greaterThanOrEqualTo(0));
    expect(metrics.area.height, greaterThanOrEqualTo(0));
  });
}

Matcher _near(Offset expected) => predicate<Offset>(
    (actual) =>
        (actual.dx - expected.dx).abs() < 0.5 &&
        (actual.dy - expected.dy).abs() < 0.5,
    "within half a pixel of $expected");
