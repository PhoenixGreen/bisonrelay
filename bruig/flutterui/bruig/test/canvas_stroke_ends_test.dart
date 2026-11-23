import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_hit_test.dart';

// canvas_stroke_ends_test.dart is a stroke's ends as drawn: a line's and a
// path's are the same stroke (StrokeSpec, drawn by paintStroke), so a path
// draws every kind of end at its size, cut back under it, as a line does;
// an end takes the colour its stroke has there; and the stroke meets each
// end with no gap and shows through no hollow one.

const _page = 240;

/// _tip is where every stroke here ends: on a pixel's centre, so the row
/// through it is the stroke's own middle.
const _tip = Offset(200.5, 120.5);
const _start = Offset(40.5, 120.5);

/// _line is a level line from [_start] to [_tip] drawn with [stroke].
LineElement _line(StrokeSpec stroke) =>
    (const LineElement(ElementBase(id: "l")).withEnds(_start, _tip))
        .withStroke(stroke);

/// _path is a path of two points over the same course as [_line].
PathElement _path(StrokeSpec stroke, {bool closed = false}) =>
    const PathElement(
      ElementBase(id: "p", x: 40.5, y: 110.5, width: 160, height: 20),
      nodes: [PathNode(x: 0, y: 0.5), PathNode(x: 1, y: 0.5, frame: 8)],
    ).copyWith(closed: closed).withStroke(stroke);

const _orange = Color(0xFFFFA726);

/// _plain is a stroke with no ends, flat-capped, [width] wide.
StrokeSpec _plain({double width = 6}) => StrokeSpec(
    color: _orange,
    strokeWidth: width,
    cap: LineStrokeCap.flat,
    startEnd: LineEnd.none,
    endEnd: LineEnd.none,
    endSize: 1,
    dash: 0);

/// _Picture is a page as drawn, to ask which pixels are inked.
class _Picture {
  final Uint8List rgba;
  _Picture(this.rgba);

  int _at(int x, int y) => (y * _page + x) * 4;

  /// inked is whether the pixel at [x], [y] is drawn on, against the
  /// page's own colour in its corner.
  bool inked(int x, int y) {
    if (x < 0 || y < 0 || x >= _page || y >= _page) return false;
    var i = _at(x, y);
    var d = 0;
    for (var c = 0; c < 3; c++) {
      d += (rgba[i + c] - rgba[c]).abs();
    }
    return d > 90;
  }

  /// near is the inked pixels within [radius] of [point].
  List<Offset> near(Offset point, double radius) => [
        for (var y = 0; y < _page; y++)
          for (var x = 0; x < _page; x++)
            if (inked(x, y) &&
                (Offset(x + 0.5, y + 0.5) - point).distance < radius)
              Offset(x + 0.5, y + 0.5),
      ];

  /// red and blue are the average of those channels over [pixels].
  double red(List<Offset> pixels) => _mean(pixels, 0);
  double blue(List<Offset> pixels) => _mean(pixels, 2);

  double _mean(List<Offset> pixels, int channel) {
    if (pixels.isEmpty) return 0;
    var total = 0;
    for (var p in pixels) {
      total += rgba[_at(p.dx.floor(), p.dy.floor()) + channel];
    }
    return total / pixels.length;
  }
}

Future<_Picture> _draw(CanvasElement e) async {
  var doc = CanvasDocument(
      size: const CanvasSize(width: _page, ratio: CanvasRatio.square),
      elements: [e]);
  var recorder = ui.PictureRecorder();
  paintCanvasDocument(ui.Canvas(recorder), doc);
  var image = await recorder.endRecording().toImage(_page, _page);
  var data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return _Picture(data!.buffer.asUint8List());
}

Offset _centre(List<Offset> pixels) =>
    pixels.reduce((a, b) => a + b) / pixels.length.toDouble();

void main() {
  group("where the stroke stops under an end", () {
    StrokeSpec stroke(LineStrokeCap cap) =>
        _plain(width: 4).copyWith(cap: cap, endSize: 2);

    test("under every end but none and a bar, short of the end", () {
      for (var end in LineEnd.values) {
        var cut = stroke(LineStrokeCap.flat).cutBack(end);
        if (end == LineEnd.none || end == LineEnd.bar) {
          expect(cut, 0, reason: end.name);
        } else {
          expect(cut, greaterThan(0), reason: end.name);
        }
      }
    });

    test("a cap's reach is cut too, so its ink stops where a flat one's does",
        () {
      for (var end in LineEnd.values) {
        if (end == LineEnd.none || end == LineEnd.bar) continue;
        var flat = stroke(LineStrokeCap.flat).cutBack(end);
        for (var cap in [LineStrokeCap.round, LineStrokeCap.square]) {
          expect(stroke(cap).cutBack(end), flat + 2, reason: end.name);
        }
      }
    });

    test("an open arrow's stroke reaches into its notch", () {
      var notch = EndShape.openArrowBarb * EndShape.openArrowNotch;
      expect(LineEnd.openArrow.cover, lessThan(notch));
      expect(LineEnd.openArrow.cover, greaterThan(notch * 0.8));
    });

    test("a hollow end's stroke stops at its back edge", () {
      expect(LineEnd.hollowArrow.cover, EndShape.arrowBase);
      expect(LineEnd.hollowDiamond.cover, EndShape.diamondLength);
      expect(LineEnd.hollowCircle.cover, EndShape.circleRadius);
    });

    test("a solid arrow's stroke stops just inside its base", () {
      expect(LineEnd.arrow.cover, lessThan(EndShape.arrowBase));
      expect(LineEnd.arrow.cover, greaterThan(EndShape.arrowBase * 0.8));
    });
  });

  group("a path's ends", () {
    test("a hollow end leaves its middle empty", () async {
      var hollow =
          (await _draw(_path(_plain().copyWith(endEnd: LineEnd.hollowCircle))))
              .near(_tip, 2);
      var solid =
          (await _draw(_path(_plain().copyWith(endEnd: LineEnd.circle))))
              .near(_tip, 2);
      expect(solid, isNotEmpty, reason: "a solid circle is filled");
      expect(hollow.length, lessThan(solid.length / 4),
          reason: "the middle of a hollow one shows the page");
    });

    test("a bigger end size puts more ink on the end", () async {
      var arrow = _plain(width: 4).copyWith(endEnd: LineEnd.arrow);
      var small = (await _draw(_path(arrow))).near(_tip, 70);
      var large =
          (await _draw(_path(arrow.copyWith(endSize: 4)))).near(_tip, 70);
      expect(large.length, greaterThan(small.length * 1.4));
    });

    test("a thick round-capped stroke stops at its arrow's point", () async {
      var picture = await _draw(_path(_plain(width: 12)
          .copyWith(cap: LineStrokeCap.round, endEnd: LineEnd.arrow)));
      var past = [
        for (var y = 110; y < 131; y++)
          for (var x = (_tip.dx + 2).ceil(); x < _page; x++)
            if (picture.inked(x, y)) Offset(x.toDouble(), y.toDouble()),
      ];
      expect(past, isEmpty, reason: "nothing is drawn beyond the tip");
    });

    test("every end is drawn as on a line over the same course", () async {
      for (var end in LineEnd.values) {
        for (var (what, stroke) in [
          ("at the end", _plain().copyWith(endEnd: end, endSize: 1.5)),
          ("at the start", _plain().copyWith(startEnd: end, endSize: 1.5)),
          (
            "dashed, round-capped",
            _plain().copyWith(
                endEnd: end, dash: 14, cap: LineStrokeCap.round, endSize: 1.5)
          ),
        ]) {
          var at = what == "at the start" ? _start : _tip;
          var onLine = (await _draw(_line(stroke))).near(at, 40);
          var onPath = (await _draw(_path(stroke))).near(at, 40);
          var reason = "${end.name} $what";
          expect(onLine, isNotEmpty, reason: reason);
          expect(onPath.length, closeTo(onLine.length, onLine.length * 0.03),
              reason: reason);
          var shift = _centre(onPath) - _centre(onLine);
          expect(shift.distance, lessThan(0.75), reason: reason);
        }
      }
    });

    test("a dashed path is dashed as a line is", () async {
      var dashed = _plain().copyWith(dash: 14);
      var onLine = (await _draw(_line(dashed))).near(_tip, 200);
      var onPath = (await _draw(_path(dashed))).near(_tip, 200);
      expect(onPath.length, closeTo(onLine.length, onLine.length * 0.03));
    });

    test("a path reads as long a dash as a line does", () {
      for (var e in <StrokedElement>[_line(_plain()), _path(_plain())]) {
        var json = jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>;
        json["dash"] = 300;
        expect((elementFromJson(json) as StrokedElement).dash, 300,
            reason: e.kind.name);
      }
    });

    test("a closed path's box does not grow for ends it does not draw", () {
      var ended =
          _plain().copyWith(startEnd: LineEnd.arrow, endEnd: LineEnd.diamond);
      expect(visualBoundsOf(_path(ended, closed: true), null, 0),
          visualBoundsOf(_path(_plain(), closed: true), null, 0));
      expect(visualBoundsOf(_path(ended), null, 0).width,
          greaterThan(visualBoundsOf(_path(_plain()), null, 0).width),
          reason: "an open path's box grows for its ends");
    });
  });

  group("an end on a faded stroke", () {
    // Red at the start, running to blue at the end.
    const fade = GradientSpec(to: Color(0xFF2040FF), angle: 90);
    var faded = _plain(width: 6).copyWith(
        color: const Color(0xFFFF2020),
        fade: fade,
        startEnd: LineEnd.square,
        endEnd: LineEnd.arrow,
        endSize: 2);

    // A little off level: a fade across a stroke whose curve has no height
    // at all has nowhere to run, and is drawn in its first colour.
    const from = Offset(40.5, 100.5);
    var line = const LineElement(ElementBase(id: "l"))
        .withEnds(from, _tip)
        .withStroke(faded);
    var path = const PathElement(
      ElementBase(id: "p", x: 40.5, y: 100.5, width: 160, height: 20),
      nodes: [PathNode(x: 0, y: 0), PathNode(x: 1, y: 1, frame: 8)],
    ).withStroke(faded);
    for (var (kind, element) in <(String, StrokedElement)>[
      ("line", line),
      ("path", path),
    ]) {
      test("on a $kind is the colour the stroke has there", () async {
        var picture = await _draw(element);
        var atEnd = picture.near(_tip, 12);
        var atStart = picture.near(from, 8);
        expect(picture.blue(atEnd), greaterThan(picture.red(atEnd)),
            reason: "the arrow is where the stroke is blue");
        expect(picture.red(atStart), greaterThan(picture.blue(atStart)),
            reason: "the square is where the stroke is red");
      });
    }
  });

  group("a stroke meets its end", () {
    // Along the stroke's middle (the row through the tip), from the body
    // towards the tip: the ink runs unbroken into the end, a hollow end's
    // middle is empty from its back edge on, and nothing is drawn further
    // past the tip than the end itself reaches. Each end's size is read from
    // EndShape, the proportions it is drawn with.
    const row = 120, tipColumn = 200;
    const spread = EndShape.arrowSpread;

    /// _Reach is where an end's ink is along the stroke's middle, in
    /// pixels back from the tip: [hollowFrom] where a hollow middle begins
    /// (null for none), and [front] how far past the tip it is drawn.
    for (var end in LineEnd.values) {
      for (var width in [2.0, 8.0]) {
        for (var size in [0.5, 1.0, 2.5]) {
          for (var cap in LineStrokeCap.values) {
            var what = "${end.name}, $width wide, size $size, ${cap.name}";
            test(what, () async {
              var stroke = _plain(width: width)
                  .copyWith(endEnd: end, endSize: size, cap: cap);
              var picture = await _draw(_line(stroke));
              bool inkedBack(int d) => picture.inked(tipColumn - d, row);

              var w = width * size, h = width / 2;
              var capReach = cap == LineStrokeCap.flat ? 0.0 : h;
              var diamond =
                  math.atan2(EndShape.diamondWidth, EndShape.diamondLength);
              // How far its outline's corner reaches past a point, and in
              // from it, at a corner of half-angle [half] (a miter join).
              double miter(double half) => h / math.sin(half);
              var (double? hollowFrom, double front) = switch (end) {
                LineEnd.none => (null, capReach),
                LineEnd.bar => (null, math.max(h, capReach)),
                LineEnd.arrow || LineEnd.openArrow => (null, 0.0),
                LineEnd.hollowArrow => (
                    w * EndShape.arrowBarb * math.cos(spread) - h,
                    miter(spread)
                  ),
                LineEnd.diamond => (null, w * EndShape.diamondLength),
                LineEnd.hollowDiamond => (
                    w * EndShape.diamondLength - miter(diamond),
                    w * EndShape.diamondLength + miter(diamond)
                  ),
                LineEnd.circle => (null, w * EndShape.circleRadius),
                LineEnd.hollowCircle => (
                    w * EndShape.circleRadius - h,
                    w * EndShape.circleRadius + h
                  ),
                LineEnd.square => (null, w * EndShape.squareSide / 2),
              };
              // A hollow end too small to have a middle is drawn solid.
              var hollowTo = switch (end) {
                LineEnd.hollowArrow => miter(spread),
                LineEnd.hollowDiamond || LineEnd.hollowCircle => -hollowFrom!,
                _ => 0.0,
              };
              if (hollowFrom != null && hollowFrom - hollowTo < 2) {
                hollowFrom = null;
              }

              // The first pixel not drawn on, walking from the body to the
              // tip.
              var firstBlank = -1000;
              for (var d = 150; d > -40; d--) {
                if (!inkedBack(d)) {
                  firstBlank = d;
                  break;
                }
              }
              if (hollowFrom == null) {
                expect(firstBlank, lessThanOrEqualTo(2),
                    reason: "$what: the ink runs on to the tip");
              } else {
                expect(firstBlank, lessThanOrEqualTo(hollowFrom.floor() + 1),
                    reason: "$what: no gap before the end's back edge");
                expect(firstBlank, greaterThanOrEqualTo(hollowFrom.floor() - 1),
                    reason: "$what: the stroke shows inside the end");
              }

              var beyond = (front + 2).ceil();
              for (var d = beyond; d < beyond + 4; d++) {
                expect(inkedBack(-d), isFalse,
                    reason: "$what: drawn $d px past the tip");
              }
            });
          }
        }
      }
    }
  });

  group("a thick stroke or outline is pressed where it is drawn", () {
    bool pressed(CanvasElement e, Offset at) => StageHitTest(
            document: CanvasDocument(
                size: const CanvasSize(width: _page, ratio: CanvasRatio.square),
                elements: [e]),
            frame: 0,
            scale: 1)
        .contains(e, at);

    test("a shape's outline, on its outer half outside the box", () {
      // A 20-wide outline centred on the box's edge reaches 10 outside it.
      var shape = const ShapeElement(
          ElementBase(id: "s", x: 60, y: 60, width: 120, height: 80),
          strokeWidth: 20,
          strokeColor: _orange);
      expect(pressed(shape, const Offset(53, 100)), isTrue,
          reason: "7 outside the left edge, on the outline");
      expect(pressed(shape, const Offset(120, 147)), isTrue,
          reason: "7 below the bottom edge, on the outline");
      expect(pressed(shape, const Offset(120, 156)), isFalse,
          reason: "past the outline, on nothing");
      var turned = shape.withBase(rotation: 90);
      // Turned a quarter about its middle (120, 100), its left edge is at
      // the top, at y 40.
      expect(pressed(turned, const Offset(120, 33)), isTrue,
          reason: "turned, 7 outside its edge");
      expect(pressed(shape.copyWith(strokeWidth: 0), const Offset(53, 100)),
          isFalse,
          reason: "with no outline, nothing is drawn there");
    });

    test("a line's stroke, on its half outside its box", () {
      var line = _line(_plain(width: 20));
      expect(pressed(line, const Offset(120.5, 128.5)), isTrue);
      expect(pressed(line, const Offset(120.5, 112.5)), isTrue);
    });

    test("a path's stroke, on its half outside its box", () {
      // The path's box is 20 deep about its stroke; a 30-wide stroke
      // reaches 5 past it either side.
      var path = _path(_plain(width: 30));
      expect(pressed(path, const Offset(120.5, 133.5)), isTrue);
      expect(pressed(path, const Offset(120.5, 107.5)), isTrue);
    });
  });
}
