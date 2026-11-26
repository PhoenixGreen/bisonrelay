import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/metronome_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';

// canvas_parts_reading_test.dart is a counter, a button, a camera, a Layout
// and a metronome read from a received file: every list is counted, every
// id and name cut, and every number that sizes what is drawn comes back
// within what the page can use, while every value the panels and the stage
// can set comes back as it was saved. The general sweep
// (canvas_element_reading_test.dart) holds them to never throwing and never
// growing huge; this holds the values themselves.

const _huge = 1e12;

/// _read is [e] saved, with [changes] made to what was saved, and read back.
T _read<T extends CanvasElement>(T e, Map<String, Object?> changes) {
  var json = jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>;
  json.addAll(changes);
  return elementFromJson(json) as T;
}

/// _again is [e] saved and read back.
T _again<T extends CanvasElement>(T e) => _read(e, const {});

void _same(CanvasElement e) =>
    expect(jsonEncode(_again(e).toJson()), jsonEncode(e.toJson()));

const _counter = CounterElement(ElementBase(id: "n", width: 200, height: 100),
    keyed: false, loose: true, looseButtons: true);
const _button = ButtonElement(ElementBase(id: "b", width: 120, height: 40));
const _camera = CameraElement(ElementBase(id: "c", width: 320, height: 180));
const _metronome =
    MetronomeElement(ElementBase(id: "m", width: 100, height: 160));
const _layout = LayoutElement(ElementBase(id: "L", width: 300, height: 400));

/// _full is a Panels tree [depth] deep with every cut made, so 2^depth
/// cells.
LayoutNode _full(int depth, [String at = "c"]) => depth == 0
    ? LayoutNode.leaf(at)
    : LayoutNode.cut(
        vertical: depth.isEven,
        a: _full(depth - 1, "${at}a"),
        b: _full(depth - 1, "${at}b"));

void main() {
  group("a received counter", () {
    test("offers each of its buttons once, in the order first given", () {
      var c = _read(_counter, {
        "buttons": [
          "reset",
          "input",
          "reset",
          ...List.filled(1000000, "startStop"),
          "input",
        ],
      });
      expect(c.buttons,
          [CounterButton.reset, CounterButton.input, CounterButton.startStop]);
    });

    test("places no more buttons than it can have", () {
      var c = _read(_counter, {
        "buttons": ["reset"],
        "buttonAt": List.filled(1000000, [0.1, 0.2]),
      });
      expect(c.buttonAt.length, lessThanOrEqualTo(CounterButton.values.length));
    });

    test("names the game count it shows by an id", () {
      var c = _read(_counter, {"gameCount": "x" * 2000000});
      expect(c.gameCount.length, maxIdLength);
    });

    test("its gap, rate, places and button size are what its panel offers", () {
      for (var far in [_huge, -_huge]) {
        var c = _read(_counter, {
          "gap": far,
          "rate": far,
          "beforeAt": [far, far],
          "afterAt": [far, -far],
          "buttons": ["reset"],
          "buttonAt": [
            [far, -far]
          ],
          "buttonSize": [far, far],
        });
        expect(c.gap, inInclusiveRange(0, CounterElement.maxGap));
        expect(c.rate, inInclusiveRange(0, CounterElement.maxRate));
        for (var at in [c.beforeAt, c.afterAt, ...c.buttonAt]) {
          expect(at.dx, inInclusiveRange(-1, 1), reason: "$far");
          expect(at.dy, inInclusiveRange(-1, 1), reason: "$far");
        }
        for (var side in [c.buttonSize.width, c.buttonSize.height]) {
          expect(
              side,
              inInclusiveRange(
                  CounterElement.minButtonSize, CounterElement.maxButtonSize));
        }
      }
    });

    test("every value its panel and the stage can set reads back as it was",
        () {
      for (var c in [
        _counter.copyWith(gap: 0, rate: 0, buttonSize: const Size(0.05, 0.05)),
        _counter.copyWith(
            gap: CounterElement.maxGap,
            rate: CounterElement.maxRate,
            buttonSize: const Size(1, 1)),
        _counter.copyWith(
            beforeAt: const Offset(-1, 1),
            afterAt: const Offset(1, -1),
            buttons: const [CounterButton.input, CounterButton.startStop],
            buttonAt: const [Offset(-1, -1), Offset(1, 1)]),
        _counter.copyWith(
            buttons: CounterButton.values,
            buttonAt: const [Offset(0.2, 0.3), Offset(-0.4, 0.5), Offset.zero]),
        _counter.copyWith(
            source: CounterSource.game, gameCount: "g" * maxIdLength),
        _counter.copyWith(
            source: CounterSource.run,
            from: -1000000000,
            to: 1000000000,
            numberStyle: "Big figures",
            wordStyle: "Small words"),
      ]) {
        _same(c);
      }
    });
  });

  group("a received game count", () {
    test("is named by an id, and called by a label", () {
      var g = GameCount.fromJson({"id": "x" * 2000000, "name": "n" * 2000000})!;
      expect(g.id.length, maxIdLength);
      expect(g.name.length, maxLabelLength);
      expect(GameCount.fromJson({"id": "coins", "name": "Coins"}),
          const GameCount("coins", "Coins"));
    });
  });

  group("a received button", () {
    test("goes to a frame a scene can have", () {
      for (var kind in ButtonActionKind.values.where((k) => k.needsFrame)) {
        for (var far in [_huge, -_huge]) {
          var b = _read(_button, {
            "action": {"kind": kind.name, "frame": far},
          });
          expect(b.action.frame, inInclusiveRange(0, maxFrameCount - 1));
        }
      }
    });

    test("names what it acts on by an id, or a scene by its name", () {
      // goToScene finds its scene by id, then by name: as long as a name.
      for (var kind in ButtonActionKind.values
          .where((k) => k.needsElement || k.needsScene)) {
        var b = _read(_button, {
          "action": {"kind": kind.name, "element": "x" * 2000000},
        });
        expect(b.action.elementId.length, maxLabelLength);
      }
    });

    test("every value its panel can set reads back as it was", () {
      for (var action in [
        const ButtonAction(kind: ButtonActionKind.playToFrame, frame: 0),
        const ButtonAction(
            kind: ButtonActionKind.goToFrame, frame: maxFrameCount - 1),
        ButtonAction(
            kind: ButtonActionKind.goToScene, elementId: "s" * maxLabelLength),
        ButtonAction(
            kind: ButtonActionKind.playSound, elementId: "a" * maxIdLength),
        ButtonAction(
            kind: ButtonActionKind.openLink,
            url: "https://example.com/${"p" * 5000}"),
      ]) {
        _same(_button.copyWith(action: action));
      }
    });
  });

  group("a received camera", () {
    test("names what it focuses on and aims at by an id", () {
      var c = _read(_camera, {
        "focusOn": "x" * 2000000,
        "aim": "x" * 2000000,
        "aimAt": "item:${"x" * 2000000}",
      });
      expect(c.focusOn.length, maxIdLength);
      expect(c.aim.length, maxIdLength);
      expect(c.aimAt.length, lessThanOrEqualTo(maxLabelLength + 5));
    });

    // A camera's focus, blur and vignette can be keyed: what a key holds is
    // read as any keyframe value is, so the lens is held where the keyed
    // value meets it.
    test("a keyed blur, focus or vignette is held to what a page can draw", () {
      for (var far in [_huge, -_huge]) {
        var keyed = _camera.withBase(
            track: ElementTrack([
          const Keyframe(frame: 0)
              .withValue("blur", far)
              .withValue("focus", far)
              .withValue("vignette", far)
              .withValue("aim", far),
        ])) as CameraElement;
        var doc = CanvasDocument(elements: [keyed], frames: 10);
        var look = cameraLookAt(keyed, 0, doc);
        expect(look.blur, inInclusiveRange(0, CameraElement.readBlur),
            reason: "$far");
        expect(
            look.focus,
            inInclusiveRange(
                -CameraElement.maxKeyedFocus, CameraElement.maxKeyedFocus),
            reason: "$far");
        expect(look.vignette, inInclusiveRange(0, 1), reason: "$far");
      }
    });

    // A stage camera can be swung round and round by dragging, so its turn
    // is not one turn's worth; but not without end.
    test("its view's turn is held to ten turns either way", () {
      for (var far in [_huge, -_huge]) {
        var c = _read(_camera, {
          "view": [far, 0, 8, 35, 0, 0, 0],
        });
        expect(c.view!.yaw.abs(), StageCamera.maxYaw, reason: "$far");
        expect(const StageCamera().copyWith(yaw: far).yaw.abs(),
            StageCamera.maxYaw);
      }
      expect(const StageCamera().copyWith(yaw: 725).yaw, 725,
          reason: "two turns and a bit, as a drag leaves it");
    });

    test("what its keys hold within the panel's range, it is drawn with", () {
      // Within the panel's ranges, and a little past them where an easing
      // overshoots between two keys, a keyed lens is drawn as keyed.
      for (var (blur, focus) in [(0.0, -1.2), (60.0, 1.2), (75.0, 0.0)]) {
        var keyed = _camera.withBase(
            track: ElementTrack([
          const Keyframe(frame: 0)
              .withValue("blur", blur)
              .withValue("focus", focus),
        ])) as CameraElement;
        var doc = CanvasDocument(elements: [keyed], frames: 10);
        var look = cameraLookAt(keyed, 0, doc);
        expect((look.blur, look.focus), (blur, focus));
      }
    });

    test("every value its panel can set reads back as it was", () {
      for (var c in [
        _camera.copyWith(
            focus: -1,
            blur: 0,
            parallax: 0,
            vignette: 0,
            vignetteSoft: 0,
            motionBlur: 0,
            aimFill: 0.2),
        _camera.copyWith(
            focus: 1,
            blur: 60,
            parallax: 1,
            vignette: 1,
            vignetteSoft: 1,
            motionBlur: 1,
            aimFill: 0.95),
        _camera.copyWith(
            focusOn: "f" * maxIdLength,
            aim: "a" * maxIdLength,
            aimAt: "item:${"x" * maxLabelLength}"),
        _camera.copyWith(aim: "chart", aimAt: "top:3"),
      ]) {
        _same(c);
      }
    });
  });

  group("a received Layout", () {
    test("orders any cell it can hold, by its id", () {
      var id = "c" * maxIdLength;
      var l = _read(
          _layout
              .copyWith(root: LayoutNode.leaf(id), cells: [LayoutCell(id: id)]),
          {
            "order": [id],
            "unread": [id],
          });
      expect(l.order, [id]);
      expect(l.unread, [id]);
      var long = _read(_layout, {
        "order": ["x" * 2000000],
      });
      expect(long.order.single.length, maxIdLength);
      var many = _read(_layout, {
        "order": List.filled(1000000, "x"),
      });
      expect(many.order.length, lessThanOrEqualTo(LayoutElement.maxCells));
    });

    test("a Panels tree has no more cells than a layout can hold", () {
      var deep = _layout.copyWith(root: _full(12));
      expect(deep.root.cells.length, 4096, reason: "as sent");
      var l = _again(deep);
      expect(l.root.cells.length, lessThanOrEqualTo(LayoutElement.maxCells));
      expect(l.root.cells.toSet().length, l.root.cells.length,
          reason: "each cell once");
    });

    test("a cell's place and turn are held as a received one's are", () {
      var c =
          const LayoutCell(id: "c").copyWith(x: _huge, y: -_huge, turn: _huge);
      expect((c.x, c.y, c.turn), (10, -10, 360));
      var read = LayoutCell.fromJson(const {
        "id": "c",
        "x": _huge,
        "y": -_huge,
        "turn": _huge,
      });
      expect((read.x, read.y, read.turn), (c.x, c.y, c.turn));
    });

    test("every value its panel and the stage can set reads back as it was",
        () {
      var leaves = [for (var i = 0; i < LayoutElement.maxCells; i++) "c$i"];
      LayoutNode chain(int from) => from == leaves.length - 1
          ? LayoutNode.leaf(leaves[from])
          : LayoutNode.cut(
              vertical: from.isEven,
              a: LayoutNode.leaf(leaves[from]),
              b: chain(from + 1));
      // The tree's depth stops at twelve; a layout of the most cells is
      // made of cuts down twelve and across.
      LayoutNode wide(List<String> ids) => ids.length == 1
          ? LayoutNode.leaf(ids.single)
          : LayoutNode.cut(
              vertical: ids.length.isEven,
              at: 0.02,
              tilt: -60,
              gutter: 400,
              a: wide(ids.sublist(0, ids.length ~/ 2)),
              b: wide(ids.sublist(ids.length ~/ 2)));
      expect(chain(0).cells.length, LayoutElement.maxCells);
      for (var l in [
        _layout.copyWith(
            root: wide(leaves),
            cells: [for (var id in leaves) LayoutCell(id: id)],
            order: leaves.reversed.toList(),
            unread: leaves.take(3).toList(),
            gutter: 400,
            rowGutter: 0,
            margin: 400),
        _layout.copyWith(mode: LayoutMode.free, cells: [
          const LayoutCell(
              id: "a", x: -10, y: 10, turn: -180, width: 10, height: 10),
          const LayoutCell(id: "b", x: 10, y: -10, turn: 180),
        ]),
        _layout.copyWith(
            root: const LayoutNode.cut(
                vertical: true,
                at: 0.98,
                tilt: 60,
                gutter: 0,
                a: LayoutNode.leaf("a"),
                b: LayoutNode.leaf("b")),
            cells: const [LayoutCell(id: "a"), LayoutCell(id: "b")]),
      ]) {
        _same(l);
      }
    });
  });

  group("a received metronome", () {
    test("goes at whole beats a minute, as its panel sets them", () {
      var m = _read(_metronome, {"bpm": 100.4, "beats": 5.7});
      expect((m.bpm, m.beats), (100, 5));
    });

    test("goes no slower or faster than a clockwork one, with a bar it has",
        () {
      for (var far in [_huge, -_huge]) {
        var m = _read(_metronome, {"bpm": far, "beats": far});
        expect(m.bpm, inInclusiveRange(metronomeSlowest, metronomeFastest));
        expect(m.beats, inInclusiveRange(1, 12));
      }
    });

    test("every value its panel and buttons can set reads back as it was", () {
      for (var bpm = metronomeSlowest; bpm <= metronomeFastest; bpm++) {
        _same(_metronome.copyWith(bpm: bpm));
      }
      for (var beats = 1; beats <= 12; beats++) {
        _same(_metronome.copyWith(beats: beats));
      }
    });
  });
}
