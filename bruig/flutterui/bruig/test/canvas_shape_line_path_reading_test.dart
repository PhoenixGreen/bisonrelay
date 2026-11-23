import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_limits.dart';
import 'package:bruig/plugin_system/canvas/model/element_reading.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';

// canvas_shape_line_path_reading_test.dart is a shape, a line and a path
// read from a received file: every number that sizes what is drawn comes
// back within what the page can use, and every value the panels can set
// comes back as it was saved. The general sweep
// (canvas_element_reading_test.dart) holds them to never throwing and never
// growing huge; this holds the numbers themselves.

const _huge = 1e12;

/// _read is [e] saved, with [changes] made to what was saved, and read back.
T _read<T extends CanvasElement>(T e, Map<String, Object?> changes) {
  var json = jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>;
  json.addAll(changes);
  return elementFromJson(json) as T;
}

/// _again is [e] saved and read back.
T _again<T extends CanvasElement>(T e) => _read(e, const {});

const _shape = ShapeElement(ElementBase(id: "s", width: 200, height: 120));
const _line = LineElement(ElementBase(id: "l", width: 200, height: 60));
final _path = PathElement(const ElementBase(id: "p", width: 200, height: 120),
    nodes: PathElement.defaultNodes());

void main() {
  group("a received shape", () {
    test("its outline, corners and padding are no more than a page can use",
        () {
      for (var far in [_huge, -_huge]) {
        var s = _read(_shape, {
          "sw": far,
          "cr": far,
          "rTL": far,
          "rTR": far,
          "rBR": far,
          "rBL": far,
          "pad": far,
          "padL": far,
          "padT": far,
          "padR": far,
          "padB": far,
        });
        for (var v in [
          s.strokeWidth,
          s.cornerRadius,
          s.radTL!,
          s.radTR!,
          s.radBR!,
          s.radBL!,
          s.padding,
          s.padL!,
          s.padT!,
          s.padR!,
          s.padB!,
        ]) {
          expect(v, inInclusiveRange(0, maxDesignLength), reason: "$far");
        }
      }
    });

    test("a star has the points and depth it is drawn with", () {
      var star = _shape.copyWith(shape: ShapeKind.star);
      var many = _read(star, {"points": _huge, "inner": _huge});
      expect((many.points, many.innerRatio), (24, 0.95));
      var few = _read(star, {"points": -_huge, "inner": -_huge});
      expect((few.points, few.innerRatio), (3, 0.05));
    });

    test("a bubble's tail turns and curls no further than it can be set to",
        () {
      var bubble = _shape.copyWith(
          shape: ShapeKind.speechBubble,
          bubble: const SpeechBubbleSpec(tail: BubbleTail.curved));
      for (var far in [_huge, -_huge]) {
        var b = _read(bubble, {
          "bubble": {"tail": "curved", "angle": far, "curl": far},
        }).bubble;
        expect(b.tailAngle, inInclusiveRange(-360, 360));
        expect(b.curl, inInclusiveRange(-15, 15));
      }
    });

    test("a bubble's tail is held to the length and width it can be set to",
        () {
      // Past what the panel offers, the body gives up all its room to the
      // tail and collapses.
      var bubble = _shape.copyWith(shape: ShapeKind.speechBubble);
      var far = _read(bubble, {
        "bubble": {"length": 2, "width": 2},
      }).bubble;
      expect((far.tailLength, far.tailWidth),
          (SpeechBubbleSpec.maxTailLength, SpeechBubbleSpec.maxTailWidth));
      var near = _read(bubble, {
        "bubble": {"length": 0, "width": 0},
      }).bubble;
      expect((near.tailLength, near.tailWidth),
          (SpeechBubbleSpec.minTailLength, SpeechBubbleSpec.minTailWidth));
    });

    test("every value its panel can set reads back as it was", () {
      for (var s in [
        _shape.copyWith(strokeWidth: 0),
        _shape.copyWith(strokeWidth: 200),
        _shape.copyWith(
            cornerRadius: 400, radTL: 0, radTR: 400, radBR: 0, radBL: 400),
        _shape.copyWith(padding: 400, padL: 0, padT: 400, padR: 0, padB: 400),
        _shape.copyWith(shape: ShapeKind.star, points: 3, innerRatio: 0.05),
        _shape.copyWith(shape: ShapeKind.star, points: 24, innerRatio: 0.95),
        for (var (angle, length, width, curl) in [
          (
            -360.0,
            SpeechBubbleSpec.minTailLength,
            SpeechBubbleSpec.minTailWidth,
            -1.5
          ),
          (
            360.0,
            SpeechBubbleSpec.maxTailLength,
            SpeechBubbleSpec.maxTailWidth,
            1.5
          ),
        ])
          _shape.copyWith(
              shape: ShapeKind.speechBubble,
              bubble: SpeechBubbleSpec(
                  tail: BubbleTail.curved,
                  tailAngle: angle,
                  tailLength: length,
                  tailWidth: width,
                  curl: curl)),
      ]) {
        expect(jsonEncode(_again(s).toJson()), jsonEncode(s.toJson()));
      }
    });
  });

  group("a received line", () {
    test("its width, end size and bow are no more than a page can use", () {
      for (var far in [_huge, -_huge]) {
        var l = _read(_line, {"sw": far, "endSize": far, "curve": far});
        expect(l.strokeWidth, inInclusiveRange(0, maxDesignLength));
        expect(l.endSize, inInclusiveRange(0, StrokeRange.readEndSize));
        expect(l.curvature, inInclusiveRange(-10, 10));
      }
    });

    test("every value its panel can set reads back as it was", () {
      for (var l in [
        _line.copyWith(
            strokeWidth: StrokeRange.minWidth,
            endSize: StrokeRange.minEndSize,
            curvature: -1,
            dash: 0),
        _line.copyWith(
            strokeWidth: StrokeRange.maxWidth,
            endSize: StrokeRange.maxEndSize,
            curvature: 1,
            dash: StrokeRange.maxDash),
      ]) {
        expect(jsonEncode(_again(l).toJson()), jsonEncode(l.toJson()));
      }
    });
  });

  group("a received path", () {
    test("its width and end size are no more than a page can use", () {
      for (var far in [_huge, -_huge]) {
        var p = _read(_path, {"sw": far, "endSize": far});
        expect(p.strokeWidth, inInclusiveRange(0, maxDesignLength));
        expect(p.endSize, inInclusiveRange(0, StrokeRange.readEndSize));
      }
    });

    test("what follows it is named by an id", () {
      var p = _read(_path, {
        "follow": {"id": "x" * 2000000},
      });
      expect(p.follow!.elementId.length, maxIdLength);
    });

    test("its points, handles and timing are no more than a page can use", () {
      for (var far in [_huge, -_huge]) {
        var p = _read(_path, {
          "nodes": [
            {"x": far, "y": far, "ix": far, "iy": far, "ox": far, "oy": far},
            {"x": 0, "y": 0, "f": far},
          ],
        });
        var a = p.nodes.first, b = p.nodes.last;
        for (var v in [a.x, a.y, a.inDx, a.inDy, a.outDx, a.outDy]) {
          expect(v, inInclusiveRange(-maxPathFraction, maxPathFraction));
        }
        expect(b.frame, inInclusiveRange(0, maxFrameCount));
      }
    });

    test("a player who cannot be there is no follower", () {
      for (var player in [-1, maxTeamPlayers, _huge]) {
        var p = _read(_path, {
          "follow": {"id": "t", "player": player},
        });
        expect(p.follow, isNull, reason: "player $player");
      }
      var p = _read(_path, {
        "follow": {"id": "t", "player": maxTeamPlayers - 1},
      });
      expect(p.follow!.playerIndex, maxTeamPlayers - 1);
    });

    test("every point its panel and the stage can set reads back as it was",
        () {
      // A box a unit wide as far out as a box is read, a point as far the
      // other way as the panel's X and Y go, and the last frame there is.
      var tiny = PathElement(
          const ElementBase(id: "p", x: -1e6, y: 1e6, width: 1, height: 1),
          nodes: [
            const PathNode(x: 0, y: 0, frame: 0),
            PathNode(
                x: 1.1e6,
                y: -1.1e6,
                inDx: -2.2e6,
                inDy: 2.2e6,
                outDx: 0.5,
                outDy: -0.5,
                frame: maxFrameCount - 1),
          ],
          follow: const PathFollow(elementId: "t", playerIndex: 0));
      expect(jsonEncode(_again(tiny).toJson()), jsonEncode(tiny.toJson()));
    });

    test("every value its panel can set reads back as it was", () {
      for (var p in [
        _path.copyWith(
            strokeWidth: StrokeRange.minWidth,
            endSize: StrokeRange.minEndSize,
            dash: 0),
        _path.copyWith(
            strokeWidth: StrokeRange.maxWidth,
            endSize: StrokeRange.maxEndSize,
            dash: StrokeRange.maxDash),
      ]) {
        expect(jsonEncode(_again(p).toJson()), jsonEncode(p.toJson()));
      }
    });
  });
}
