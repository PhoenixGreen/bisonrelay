import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/track_marks.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_key_props_test.dart is keyframes split by property (Ken,
// 2026-11-25: the Keys strip's one row said only "Keyframes, its own"; it
// should say what each key is -- location, rotation, scale -- and a
// location should be one key, not an across and a down). Each property
// moves between the keyframes that pin it; a mark moves, goes or is copied
// by itself; a keyframe saved before the split pins everything, as before.

const _loc = KeyProp.location;

void main() {
  group("evaluation", () {
    test("a keyframe from before pins everything, and plays as it did", () {
      var t = ElementTrack(const [
        Keyframe(frame: 0),
        Keyframe(frame: 10, dx: 100, scale: 2),
      ]);
      expect(t.at(5).dx, 50);
      expect(t.at(5).scale, 1.5);
      var back = Keyframe.fromJson(t.keys[1].toJson());
      expect(back.pins, KeyProp.all);
      expect(t.keys[1].toJson().containsKey("p"), isFalse);
    });

    test("each property between the keyframes that pin it", () {
      var t = ElementTrack([
        const Keyframe(frame: 0),
        Keyframe(frame: 10, dx: 100, pins: _loc.bit),
        Keyframe(frame: 20, rotate: 90, pins: KeyProp.rotation.bit),
      ]);
      // Location from 0 to 10, then held; rotation from 0 to 20.
      expect(t.at(5).dx, 50);
      expect(t.at(15).dx, 100);
      expect(t.at(10).rotate, 45);
      expect(t.at(20).rotate, 90);
      expect(t.at(20).dx, 100,
          reason: "the rotation key leaves it where it is");
    });

    test("pins survive a save", () {
      var k = Keyframe(frame: 4, dx: 3, dy: 2, pins: _loc.bit);
      var back = Keyframe.fromJson(k.toJson());
      expect(back.pins, _loc.bit);
      expect(back.dx, 3);
      expect(k.toJson()["p"], ["location"]);
    });

    test("a drag keys the location alone, beside what is there", () {
      var t = ElementTrack(const [
        Keyframe(frame: 0),
        Keyframe(frame: 20, scale: 2),
      ]);
      var next = t.posed(10, [_loc], (p) => p.copyWith(dx: 40, dy: 8));
      var k = next.keyAt(10)!;
      expect(k.pins, _loc.bit);
      expect(next.at(10).scale, 1.5, reason: "the scale still runs 0 to 20");
      expect(next.at(10).dx, 40);
      // On a keyframe that pins everything, it changes only the location.
      var on = t.posed(20, [_loc], (p) => p.copyWith(dx: 5));
      expect(on.keyAt(20)!.pins, KeyProp.all);
      expect(on.keyAt(20)!.scale, 2);
    });
  });

  group("rows", () {
    test("a row for each property that changes, and each channel", () {
      var t = ElementTrack([
        const Keyframe(frame: 0),
        const Keyframe(frame: 10, dx: 5, opacity: 0.5),
        const Keyframe(frame: 12, values: {"reveal": 1}),
      ]);
      expect(t.rows, ["location", "opacity", "v:reveal"]);
      expect(rowLabel("location"), "Location");
      expect(rowLabel("v:reveal"), "Reveal");
    });

    test("keyframes that change nothing yet are one row", () {
      var t = ElementTrack(const [Keyframe(frame: 0), Keyframe(frame: 9)]);
      expect(t.rows, [allRow]);
      expect(t.marksOn(allRow), [0, 9]);
    });
  });

  group("marks", () {
    // Location 0 -> 10 -> 20, rotation 0 -> 20, on keyframes from before.
    var t = ElementTrack(const [
      Keyframe(frame: 0),
      Keyframe(frame: 10, dx: 50),
      Keyframe(frame: 20, dx: 100, rotate: 90),
    ]);

    test("a location mark moves by itself", () {
      var moved = t.moveMarks([(row: "location", frame: 20)], 5, last: 40)!;
      expect(moved.at(25).dx, 100);
      expect(moved.at(20).rotate, 90, reason: "the rotation stayed on 20");
      expect(moved.keyAt(20)!.pinsProp(_loc), isFalse);
      expect(moved.keyAt(25)!.pins, _loc.bit);
    });

    test("every row of a keyframe picked moves it whole", () {
      var moved = t.moveMarks([
        (row: "location", frame: 20),
        (row: "rotation", frame: 20),
      ], 5, last: 40)!;
      expect(moved.keyAt(20), isNull);
      expect(moved.keyAt(25)!.pins, KeyProp.all);
    });

    test("never onto a mark of its own row, nor off the scene", () {
      expect(t.moveMarks([(row: "location", frame: 10)], 10, last: 40), isNull);
      expect(t.moveMarks([(row: "location", frame: 20)], 30, last: 40), isNull);
      // Onto a keyframe pinning something else: joined to it.
      var onto = ElementTrack([
        Keyframe(frame: 0, dx: 0, pins: _loc.bit),
        Keyframe(frame: 10, dx: 50, pins: _loc.bit),
        Keyframe(frame: 20, rotate: 90, pins: KeyProp.rotation.bit),
      ]).moveMarks([(row: "location", frame: 10)], 10, last: 40)!;
      expect(onto.keyAt(20)!.pins, _loc.bit | KeyProp.rotation.bit);
      expect(onto.keyAt(20)!.rotate, 90);
      expect(onto.keyAt(20)!.dx, 50);
    });

    test("a mark taken off leaves the rest of its keyframe", () {
      var less = t.withoutMarks([(row: "rotation", frame: 20)]);
      expect(less.keyAt(20)!.dx, 100);
      expect(less.keyAt(20)!.rotate, 0);
      expect(less.rows, ["location"]);
    });

    test("copied and pasted onto another track, over what is there", () {
      var copied = t.copyMarks([
        (row: "location", frame: 10),
        (row: "location", frame: 20),
      ]);
      expect([for (var (o, _) in copied) o], [0, 10]);
      var other = ElementTrack(const [
        Keyframe(frame: 30, dx: 7, scale: 3),
      ]);
      var pasted = other.pasted(copied, 30);
      expect(pasted.keyAt(30)!.dx, 50, reason: "the location replaced");
      expect(pasted.keyAt(30)!.scale, 3, reason: "the scale kept");
      expect(pasted.keyAt(40)!.pins, _loc.bit);
      expect(pasted.keyAt(40)!.dx, 100);
    });

    test("toggled on a row: the value it shows there, pinned", () {
      var on = t.toggled("rotation", 5);
      expect(on.keyAt(5)!.pins, KeyProp.rotation.bit);
      expect(on.at(5).rotate, closeTo(t.at(5).rotate, 1e-9));
      expect(on.toggled("rotation", 5).keyAt(5), isNull);
      // A keyframe from before pins it already: toggled, it lets it go.
      expect(t.toggled("rotation", 10).keyAt(10)!.pinsProp(KeyProp.rotation),
          isFalse);
    });

    test("a keyed path shifted whole", () {
      var s = t.shiftLocations([0, 10, 20], 30, -4);
      expect(s.at(15).dx, t.at(15).dx + 30);
      expect(s.at(15).dy, -4);
    });
  });
}
