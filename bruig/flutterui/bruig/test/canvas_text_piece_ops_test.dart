import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/model/text_looks.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';

// canvas_text_piece_ops_test.dart is a text's piece taken out or copied:
// the element each makes (withoutPiece, withPieceCopied), on its own, and
// the controller's one way of doing each, which every place that removes or
// copies a piece calls (removeTextPiece, duplicateTextPiece): one undo
// step, and where the pick in the text's Layers goes.

const _a = TextItem(id: "a", name: "Kicker", text: "LEDGER");
const _b = TextItem(
    id: "b",
    name: "Badge",
    slot: TextSlot.bottomRight,
    side: 12,
    down: -4,
    locked: true,
    icon: TextIcon(assetId: "pic", size: 40, turn: 30));
const _c = TextItem(id: "c", text: "small print", slot: TextSlot.bottomLeft);

/// _text is a text with pieces a, b and c, and a look on each layer: all of
/// it, its words, and each piece.
TextElement _text() => const TextElement(
      ElementBase(id: "t", x: 10, y: 10, width: 400, height: 200),
      text: "Words",
      items: [_a, _b, _c],
    ).withBase(
        motion: const ElementBase(id: "t").motion.copyWith(
                devices: withMotionDeviceIds(const [
              MotionDevice(MotionDeviceKind.shadow, layer: ""),
              MotionDevice(MotionDeviceKind.glow,
                  layer: MotionDevice.bodyLayer),
              MotionDevice(MotionDeviceKind.outline, layer: "a"),
              MotionDevice(MotionDeviceKind.glow, layer: "b"),
              MotionDevice(MotionDeviceKind.shadow, layer: "b"),
              MotionDevice(MotionDeviceKind.glow, layer: "c"),
            ]))) as TextElement;

List<String> _layers(TextElement e) =>
    [for (var d in e.base.motion.devices) d.layer];

void main() {
  group("withoutPiece", () {
    test("takes the piece out, and its looks with it", () {
      var e = _text();
      var next = withoutPiece(e, "b");
      expect(next.items, [_a, _c]);
      expect(_layers(next), ["", MotionDevice.bodyLayer, "a", "c"]);
      expect(next.text, e.text);
      expect(next.bounds, e.bounds);
    });

    test("the other looks keep their ids", () {
      var e = _text();
      var ids = {
        for (var d in e.base.motion.devices)
          if (d.layer != "b") d.id
      };
      expect(
          {for (var d in withoutPiece(e, "b").base.motion.devices) d.id}, ids);
    });

    test("a piece with no looks of its own", () {
      var e = const TextElement(ElementBase(id: "t"), items: [_a, _c]);
      expect(withoutPiece(e, "a").items, [_c]);
    });

    test("no such piece: the same pieces and looks", () {
      var e = _text();
      var next = withoutPiece(e, "z");
      expect(next.items, e.items);
      expect(next.base.motion.devices, e.base.motion.devices);
    });

    test("the last piece", () {
      var e = const TextElement(ElementBase(id: "t"), items: [_a]);
      expect(withoutPiece(e, "a").items, isEmpty);
    });
  });

  group("withPieceCopied", () {
    test("the copy goes just after the piece, all but its id the same", () {
      var e = _text();
      var next = withPieceCopied(e, "b", copyId: "b2");
      expect(next.items.map((i) => i.id), ["a", "b", "b2", "c"]);
      var copy = next.items[2];
      expect(copy.toJson()..remove("id"), _b.toJson()..remove("id"),
          reason: "name, slot, place, picture, lock and all");
      expect(copy.name, "Badge", reason: "called what the piece is called");
      expect(copy.locked, isTrue);
    });

    test("the piece's looks are copied onto the copy, each after its own", () {
      var e = _text();
      var next = withPieceCopied(e, "b", copyId: "b2");
      expect(_layers(next),
          ["", MotionDevice.bodyLayer, "a", "b", "b2", "b", "b2", "c"]);
      var devices = next.base.motion.devices;
      expect(devices[4].kind, MotionDeviceKind.glow);
      expect(devices[6].kind, MotionDeviceKind.shadow);
      expect(devices.map((d) => d.id).toSet(), hasLength(devices.length),
          reason: "each look an id of its own");
      var was = {for (var d in e.base.motion.devices) d.id};
      expect({
        for (var d in devices)
          if (d.layer != "b2") d.id
      }, was, reason: "the looks there were keep their ids");
    });

    test("the last piece is copied to the end", () {
      var next = withPieceCopied(_text(), "c", copyId: "c2");
      expect(next.items.map((i) => i.id), ["a", "b", "c", "c2"]);
    });

    test("no such piece: the very same element", () {
      var e = _text();
      expect(withPieceCopied(e, "z", copyId: "z2"), same(e));
    });
  });

  group("the controller", () {
    CanvasController opened() {
      var c = CanvasController(const CanvasDocument().addElement(_text()));
      addTearDown(c.dispose);
      c.selectOnly("t");
      return c;
    }

    TextElement text(CanvasController c) =>
        c.document.elementById("t") as TextElement;

    test("removeTextPiece: one step, and the words are picked", () {
      var c = opened();
      c.pickTextLayer("t", "b");
      c.removeTextPiece("t", "b");
      expect(text(c).items.map((i) => i.id), ["a", "c"]);
      expect(_layers(text(c)), ["", MotionDevice.bodyLayer, "a", "c"]);
      expect(c.textLayer(text(c)), isNull);
      expect(c.interacting, isFalse);
      c.undo();
      expect(text(c).items.map((i) => i.id), ["a", "b", "c"]);
      expect(c.canUndo, isFalse, reason: "it was one step");
    });

    test("duplicateTextPiece: one step, and the copy is picked", () {
      var c = opened();
      c.pickTextLayer("t", "a");
      c.duplicateTextPiece("t", "a");
      var ids = text(c).items.map((i) => i.id).toList();
      expect(ids, hasLength(4));
      expect(ids[0], "a");
      expect(ids.sublist(2), ["b", "c"]);
      var copy = text(c).items[1];
      expect(copy.id, isNot("a"));
      expect(copy.name, "Kicker");
      expect(c.textLayer(text(c))?.id, copy.id);
      expect(_layers(text(c)).where((l) => l == copy.id), hasLength(1));
      expect(c.interacting, isFalse);
      c.undo();
      expect(text(c).items.map((i) => i.id), ["a", "b", "c"]);
      expect(c.canUndo, isFalse, reason: "it was one step");
    });

    test("duplicateTextPiece of no such piece: no step, the pick stays", () {
      var c = opened();
      c.pickTextLayer("t", "a");
      c.duplicateTextPiece("t", "z");
      expect(text(c).items, _text().items);
      expect(c.textLayer(text(c))?.id, "a");
      expect(c.canUndo, isFalse);
    });

    test("each joins a step already open, as the panel's writes do", () {
      var c = opened();
      c.beginInteraction();
      c.replaceElement(text(c).copyWith(text: "Typed"), transient: true);
      c.removeTextPiece("t", "c");
      expect(c.interacting, isFalse);
      c.undo();
      expect(text(c).text, "Words");
      expect(text(c).items, hasLength(3));
      expect(c.canUndo, isFalse);
    });
  });
}
