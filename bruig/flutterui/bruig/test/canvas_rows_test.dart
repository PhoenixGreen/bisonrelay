import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_rows.dart';
import 'package:bruig/plugin_system/canvas/ui/element_sound.dart';
import 'package:flutter_test/flutter_test.dart';

import 'canvas_audio_fake.dart';

// canvas_rows_test.dart is the one list of rows the timeline, the mixer and
// the slots show (Ken, 2026-11-08: one channel per element): each element
// with its own sound, then the sounds that are nobody's, the master's --
// heard in every scene -- in the All group, last.

AudioElement sound(String id, String name) =>
    AudioElement(ElementBase(id: id, name: name, visible: false),
        clip: MediaClip(timed: true, channelName: name), controls: const []);

void main() {
  test("an element and its own sound are one row; other sounds after", () {
    var c = CanvasController(
        CanvasDocument(frames: 240, elements: [
          sound("m", "Music"),
          ShapeElement(const ElementBase(id: "a", name: "Coin")),
        ]),
        audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    c.ensureElementSound("a");
    var rows = canvasRowsOf(c);
    expect([for (var r in rows) r.key], ["a", "m"],
        reason: "the element first, though the music came first");
    expect(rows.first.hasMotion, isTrue);
    expect(rows.first.channel?.key, elementSoundKey("a"),
        reason: "its own sound is on its row, not a row of its own");
    expect(rows.last.hasMotion, isFalse);
    expect(rows.last.hasSound, isTrue);
    expect(rows.map((r) => r.group).toSet(), {RowGroup.scene});
  });

  test("an element with no sound is a row of motion alone", () {
    var c = CanvasController(
        CanvasDocument(frames: 240, elements: [
          ShapeElement(const ElementBase(id: "a", name: "Camera")),
        ]),
        audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    c.selectOnly("a");
    var rows = canvasRowsOf(c);
    expect(rows.single.key, "a");
    expect(rows.single.hasSound, isFalse);
  });

  test("the master's sounds, heard in every scene, are the All group, last",
      () {
    var c = CanvasController(
        CanvasDocument(
          frames: 240,
          scenes: [
            CanvasScene(id: "one", elements: [
              sound("bed", "Bed"),
              ShapeElement(const ElementBase(id: "a", name: "Coin")),
            ]),
            const CanvasScene(id: "two"),
          ],
          master: CanvasScene(id: "m", elements: [sound("music", "Music")]),
          masterOn: true,
        ),
        audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    c.selectOnly("a");
    var rows = canvasRowsOf(c);
    expect([for (var r in rows) r.key], ["a", "bed", "music"]);
    expect([for (var r in rows) r.group],
        [RowGroup.scene, RowGroup.scene, RowGroup.all]);
  });
}
