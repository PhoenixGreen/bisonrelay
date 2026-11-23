import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/element_reading.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';

// canvas_stroke_saved_form_test.dart is what a line and a path save of their
// stroke (its colour, fade, width, cap, the end at each end, end size and
// dash), written out key by key, and what each reads back: from what it
// saves, and from older or hand-made files that leave a key out or hold
// something odd in it. A file saved by any build reads the same in every
// later one, so none of it may change by a key, a value or an omission.
//
// Each keeps defaults of its own: a line is white, 4 wide, flat-capped and
// has no ends; a path is yellow, 3 wide, round-capped, with an arrow at its
// end. A field at its element's default is left out where it is left out at
// all, so each field is set at both elements' defaults and away from them.

const _orange = Color(0xFFFFA726);
const _fade = GradientSpec(to: Color(0xFF3D7EFF), angle: 30);
const _lineBase = ElementBase(id: "l", width: 200, height: 60);
const _pathBase = ElementBase(id: "p", width: 200, height: 120);
const _nodes = [PathNode(x: 0, y: 0), PathNode(x: 1, y: 1, frame: 8)];

/// _saved is what [e] saves of itself, and what it reads back as.
Map<String, dynamic> _saved(CanvasElement e) =>
    jsonDecode(jsonEncode(e.props())) as Map<String, dynamic>;

/// _read is [e] saved, with [changes] made to what was saved (a null
/// removes the key), and read back.
T _read<T extends CanvasElement>(T e, Map<String, Object?> changes) {
  var json = jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>;
  for (var MapEntry(:key, :value) in changes.entries) {
    value == _gone ? json.remove(key) : json[key] = value;
  }
  return elementFromJson(json) as T;
}

/// _gone marks a key taken out of a saved form.
const _gone = "<gone>";

void main() {
  var fadeJson = jsonDecode(jsonEncode(_fade.toJson()));

  group("a line saves its stroke", () {
    // Every case: the line, and what it saves, key by key and in order.
    var cases = <(String, LineElement, Map<String, dynamic>)>[
      (
        "as made",
        const LineElement(_lineBase),
        {"color": 0xFFFFFFFF, "sw": 4.0, "strokeCap": "flat"},
      ),
      (
        "with every part away from a line's own",
        const LineElement(_lineBase,
            color: _orange,
            fade: _fade,
            strokeWidth: 2.5,
            cap: LineStrokeCap.round,
            startEnd: LineEnd.circle,
            endEnd: LineEnd.hollowArrow,
            endSize: 1.8,
            dash: 9),
        {
          "color": 0xFFFFA726,
          "fade": fadeJson,
          "sw": 2.5,
          "strokeCap": "round",
          "startEnd": "circle",
          "endEnd": "hollowArrow",
          "endSize": 1.8,
          "dash": 9.0,
        },
      ),
      (
        "at a path's own",
        const LineElement(_lineBase,
            color: Color(0xFFFFD166),
            strokeWidth: 3,
            cap: LineStrokeCap.round,
            endEnd: LineEnd.arrow),
        {
          "color": 0xFFFFD166,
          "sw": 3.0,
          "strokeCap": "round",
          "endEnd": "arrow",
        },
      ),
      (
        "square-capped, no width, an end at the start only",
        const LineElement(_lineBase,
            strokeWidth: 0,
            cap: LineStrokeCap.square,
            startEnd: LineEnd.bar,
            endSize: 0.5),
        {
          "color": 0xFFFFFFFF,
          "sw": 0.0,
          "strokeCap": "square",
          "startEnd": "bar",
          "endSize": 0.5,
        },
      ),
      (
        "with a long dash, and a bow and flip beside it",
        const LineElement(_lineBase,
            dash: 400, endSize: 80, curvature: 0.4, flipped: true),
        {
          "color": 0xFFFFFFFF,
          "sw": 4.0,
          "strokeCap": "flat",
          "endSize": 80.0,
          "dash": 400.0,
          "curve": 0.4,
          "flipped": true,
        },
      ),
    ];
    for (var (what, line, saved) in cases) {
      test(what, () {
        expect(jsonEncode(_saved(line)), jsonEncode(saved));
        var back = _read(line, const {});
        expect(jsonEncode(back.toJson()), jsonEncode(line.toJson()),
            reason: "read back as it was");
      });
    }
  });

  group("a path saves its stroke", () {
    var cases = <(String, PathElement, Map<String, dynamic>)>[
      (
        "as made",
        const PathElement(_pathBase, nodes: _nodes),
        {
          "nodes": [
            {"x": 0.0, "y": 0.0, "f": 0},
            {"x": 1.0, "y": 1.0, "f": 8},
          ],
          "color": 0xFFFFD166,
          "sw": 3.0,
          "strokeCap": "round",
        },
      ),
      (
        "with every part away from a path's own",
        const PathElement(_pathBase,
            nodes: _nodes,
            color: _orange,
            fade: _fade,
            strokeWidth: 5,
            cap: LineStrokeCap.square,
            startEnd: LineEnd.diamond,
            endEnd: LineEnd.openArrow,
            endSize: 2.5,
            dash: 14),
        {
          "nodes": [
            {"x": 0.0, "y": 0.0, "f": 0},
            {"x": 1.0, "y": 1.0, "f": 8},
          ],
          "color": 0xFFFFA726,
          "fade": fadeJson,
          "sw": 5.0,
          "strokeCap": "square",
          "startEnd": "diamond",
          "endEnd": "openArrow",
          "endSize": 2.5,
          "dash": 14.0,
        },
      ),
      (
        "at a line's own",
        const PathElement(_pathBase,
            nodes: _nodes,
            color: Color(0xFFFFFFFF),
            strokeWidth: 4,
            cap: LineStrokeCap.flat,
            endEnd: LineEnd.none),
        {
          "nodes": [
            {"x": 0.0, "y": 0.0, "f": 0},
            {"x": 1.0, "y": 1.0, "f": 8},
          ],
          "color": 0xFFFFFFFF,
          "sw": 4.0,
          "strokeCap": "flat",
          "endEnd": "none",
        },
      ),
      (
        "closed, a guide and followed, with a dash its panel allows",
        const PathElement(_pathBase,
            nodes: _nodes,
            strokeWidth: 0,
            startEnd: LineEnd.hollowCircle,
            endSize: 0.2,
            dash: 200,
            closed: true,
            guide: true,
            follow: PathFollow(elementId: "f", playerIndex: 2)),
        {
          "nodes": [
            {"x": 0.0, "y": 0.0, "f": 0},
            {"x": 1.0, "y": 1.0, "f": 8},
          ],
          "color": 0xFFFFD166,
          "sw": 0.0,
          "strokeCap": "round",
          "startEnd": "hollowCircle",
          "endSize": 0.2,
          "dash": 200.0,
          "closed": true,
          "guide": true,
          "follow": {"id": "f", "player": 2},
        },
      ),
    ];
    for (var (what, path, saved) in cases) {
      test(what, () {
        expect(jsonEncode(_saved(path)), jsonEncode(saved));
        var back = _read(path, const {});
        expect(jsonEncode(back.toJson()), jsonEncode(path.toJson()),
            reason: "read back as it was");
      });
    }
  });

  group("a stroke read from a file that leaves keys out or holds odd ones", () {
    const line = LineElement(_lineBase,
        color: _orange,
        fade: _fade,
        strokeWidth: 2.5,
        cap: LineStrokeCap.round,
        startEnd: LineEnd.circle,
        endEnd: LineEnd.hollowArrow,
        endSize: 1.8,
        dash: 9);
    const path = PathElement(_pathBase,
        nodes: _nodes,
        color: _orange,
        fade: _fade,
        strokeWidth: 5,
        cap: LineStrokeCap.square,
        startEnd: LineEnd.diamond,
        endEnd: LineEnd.openArrow,
        endSize: 2.5,
        dash: 14);
    const every = [
      "color",
      "fade",
      "sw",
      "strokeCap",
      "startEnd",
      "endEnd",
      "endSize",
      "dash",
    ];

    test("a line with every key left out is a line as made", () {
      var back = _read(line, {for (var k in every) k: _gone});
      expect(jsonEncode(_saved(back)),
          jsonEncode(_saved(const LineElement(_lineBase))));
    });

    test("a path with every key left out is a path as made", () {
      var back = _read(path, {for (var k in every) k: _gone});
      expect(jsonEncode(_saved(back)),
          jsonEncode(_saved(const PathElement(_pathBase, nodes: _nodes))));
    });

    /// read is what [e] reads back as with [changes], each part of its
    /// stroke in turn.
    List<Object?> read(CanvasElement e, Map<String, Object?> changes) {
      var back = _read(e, changes);
      return switch (back) {
        LineElement l => [
            l.color,
            l.fade,
            l.strokeWidth,
            l.cap,
            l.startEnd,
            l.endEnd,
            l.endSize,
            l.dash,
          ],
        PathElement p => [
            p.color,
            p.fade,
            p.strokeWidth,
            p.cap,
            p.startEnd,
            p.endEnd,
            p.endSize,
            p.dash,
          ],
        _ => throw StateError("not a stroke"),
      };
    }

    // Each odd value, and what a line and a path read it as.
    const odd = <String, Object?>{
      "color": "orange",
      "fade": "a fade",
      "sw": -3,
      "strokeCap": 5,
      "startEnd": 7,
      "endEnd": null,
      "endSize": 1000,
      "dash": -1,
    };

    test("a line reads odd values as a line does", () {
      expect(read(line, odd), [
        const Color(0xFFFFFFFF),
        null,
        0.0,
        LineStrokeCap.flat,
        LineEnd.none,
        LineEnd.none,
        80.0,
        0.0,
      ]);
      expect(
          read(line, const {
            "strokeCap": "bogus",
            "startEnd": "bogus",
            "endEnd": "bogus",
            "sw": 1e999,
            "endSize": -2,
          }),
          [
            _orange,
            _fade,
            4.0,
            LineStrokeCap.flat,
            LineEnd.none,
            LineEnd.none,
            0.0,
            9.0,
          ]);
    });

    test("a path reads odd values as a path does", () {
      expect(read(path, odd), [
        const Color(0xFFFFD166),
        null,
        0.0,
        // Not a name at all: the round cap a path starts with.
        LineStrokeCap.round,
        LineEnd.none,
        // Written, though empty: no end, not the arrow a path starts with.
        LineEnd.none,
        80.0,
        0.0,
      ]);
      expect(
          read(path, const {
            "strokeCap": "bogus",
            "startEnd": "bogus",
            "endEnd": "bogus",
            "sw": 1e999,
            "endSize": -2,
          }),
          [
            _orange,
            _fade,
            3.0,
            // A name, but none of the caps': flat, as a line reads it.
            LineStrokeCap.flat,
            LineEnd.none,
            LineEnd.none,
            0.0,
            14.0,
          ]);
    });
  });
}
