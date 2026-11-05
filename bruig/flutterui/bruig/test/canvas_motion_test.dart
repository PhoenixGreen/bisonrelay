import 'dart:convert';
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart';
import 'package:bruig/plugin_system/canvas/render/motion_pose.dart';
import 'package:flutter_test/flutter_test.dart';

// Clips: the model a clip is kept as, where placed clips play once their
// pins are followed, and what an element's clips make of it at a moment --
// layers, holds, carry, a camera's replace, and places worked out as it
// plays. The rules are the prototype's; see render/motion_pose.dart.

MotionKey k(double t, Object v,
        [KeyframeEasing ease = KeyframeEasing.linear]) =>
    MotionKey(t, v is num ? MotionNumber(v.toDouble()) : v as MotionValue,
        ease: ease);

const page = Size(960, 540);
const self = Rect.fromLTWH(400, 300, 100, 100); // middle (450, 350)
const other = Rect.fromLTWH(700, 320, 50, 50); // middle (725, 345)

MotionScene scene({Offset? drawn}) => MotionScene(
      page: page,
      boundsOf: (id) => id == "other" ? other : null,
      drawnAt: drawn == null ? null : (id) => id == "other" ? drawn : null,
    );

MotionTimes timesOf(ElementMotion m,
        {double sceneEnd = 16, Map<String, double> markers = const {}}) =>
    MotionTimes(sceneEnd: sceneEnd, markers: markers, placements: {
      for (var p in m.placed) p.id: (p, m.clip(p.clip)!),
    });

MotionPose at(ElementMotion m, double t,
        {Map<String, double> markers = const {}, bool replaces = false}) =>
    motionPose(m, t, self, timesOf(m, markers: markers), scene(),
        replaces: replaces);

final slideIn = MotionClip.ofKind("slide", MotionKind.arrive, length: 1, keys: {
  MotionProp.x: [k(0, const MotionPlace(MotionPlaceKind.offLeft)), k(1, 0)],
});
final float =
    MotionClip.ofKind("float", MotionKind.loop, length: 2, layer: 1, keys: {
  MotionProp.y: [k(0, 0), k(1, -10), k(2, 0)],
});
final walk = MotionClip.ofKind("walk", MotionKind.action, length: 2, keys: {
  MotionProp.x: [k(0, 0), k(2, 200)],
}).copyWith(after: ClipHold.last);
final jump = MotionClip.ofKind("jump", MotionKind.action, length: 1, keys: {
  MotionProp.y: [k(0, 0), k(0.5, -50), k(1, 0)],
});

void main() {
  group("kept", () {
    test("a clip, its keys and its places read back the same", () {
      var c = walk.copyWith(
        name: "Walk to it",
        keys: {
          MotionProp.x: [
            k(0, 0),
            k(2, const MotionPlace(MotionPlaceKind.beside, target: "other"),
                KeyframeEasing.easeInOut),
          ],
          MotionProp.opacity: [k(0, 0), k(0.3, 1)],
        },
        triggers: const [ClipTrigger(ClipTriggerKind.clicked, target: "a")],
        then: ClipThen.play,
        thenClip: "float",
        inside: const {"words": 0.12},
        quantise: () => "beat",
      );
      var back = MotionClip.fromJson(jsonDecode(jsonEncode(c.toJson())))!;
      expect(back.toJson(), c.toJson());
      expect(back.keys[MotionProp.x]![1].value,
          const MotionPlace(MotionPlaceKind.beside, target: "other"));
      expect(back.after, ClipHold.last);
    });

    test("an element's motion reads back, dropping what names no clip", () {
      var m = ElementMotion(
        clips: [slideIn, float],
        slots: const ["slide", "", "float"],
        placed: const [
          ClipPlacement(
              id: "p1",
              clip: "slide",
              startPin: ClipPin(PinKind.marker, target: "m1")),
          ClipPlacement(id: "p2", clip: "gone"),
        ],
        weights: const [1, 0.5, 1],
      );
      var back = ElementMotion.fromJson(jsonDecode(jsonEncode(m.toJson())));
      expect(back.clips.map((c) => c.id), ["slide", "float"]);
      expect(back.slots, ["slide", "", "float"]);
      expect(back.placed.map((p) => p.id), ["p1"]);
      expect(back.placed.single.startPin,
          const ClipPin(PinKind.marker, target: "m1"));
      expect(back.weights, [1, 0.5, 1]);
      expect(ElementMotion.none.toJson(), isEmpty);
    });

    test("a marker keeps its id", () {
      const a =
          TimelineAction(id: "m1", frame: 48, kind: TimelineActionKind.stop);
      var b = TimelineAction.fromJson(a.copyWith(frame: 60).toJson());
      expect(b.id, "m1", reason: "moved, it is still the same marker");
    });

    test("a retimed clip takes its keys with it", () {
      var r = walk.retimed(4);
      expect(r.keys[MotionProp.x]!.map((k) => k.t), [0, 4]);
    });
  });

  group("on the timeline", () {
    test("pins follow markers, the scene and other clips", () {
      var m = ElementMotion(clips: [
        slideIn,
        walk,
        jump
      ], placed: const [
        ClipPlacement(
            id: "a",
            clip: "slide",
            startPin: ClipPin(PinKind.marker, target: "m")),
        ClipPlacement(
            id: "b",
            clip: "walk",
            startPin: ClipPin(PinKind.after, target: "a")),
        ClipPlacement(
            id: "c",
            clip: "jump",
            startPin: ClipPin(PinKind.after, target: "b"),
            endPin: ClipPin(PinKind.sceneEnd)),
      ]);
      var times = timesOf(m, markers: {"m": 2});
      expect(times.span("a")!.start, 2);
      expect(times.span("b")!.start, 3, reason: "after the slide's end");
      var c = times.span("c")!;
      expect((c.start, c.end), (5, 16));
      expect(c.speed, closeTo(1 / 11, 1e-9),
          reason: "a one-shot is retimed to fill its place");
      // Moved, the marker takes everything after it along.
      expect(timesOf(m, markers: {"m": 4}).span("b")!.start, 5);
    });

    test("a loop repeats to fill its place, at its own pace", () {
      var m = ElementMotion(clips: [
        float
      ], placed: const [
        ClipPlacement(id: "f", clip: "float", layer: 1, start: 0, length: 5),
      ]);
      var s = timesOf(m).span("f")!;
      expect(s.speed, 1);
      expect(s.clipTime(float, 3), closeTo(1, 1e-9), reason: "round again");
      expect(at(m, 3).dy, closeTo(-10, 1e-9));
    });

    test("pins that go round in a circle stop", () {
      var m = ElementMotion(clips: [
        walk,
        jump
      ], placed: const [
        ClipPlacement(
            id: "a",
            clip: "walk",
            startPin: ClipPin(PinKind.after, target: "b")),
        ClipPlacement(
            id: "b",
            clip: "jump",
            startPin: ClipPin(PinKind.after, target: "a")),
      ]);
      expect(timesOf(m).span("a"), isNotNull);
    });

    test("an arrival waits at its first frame, unseen until it starts", () {
      var m = ElementMotion(clips: [
        slideIn
      ], placed: const [
        ClipPlacement(id: "a", clip: "slide", start: 2),
      ]);
      expect(at(m, 0).dx, -self.right - 14, reason: "off the left edge");
      expect(at(m, 2.5).dx, closeTo((-self.right - 14) / 2, 1e-9));
      expect(at(m, 3).dx, 0);
      expect(at(m, 9).isRest, isTrue, reason: "then at rest");
    });

    test("a held end lasts until the next clip on its layer, carried on", () {
      var m = ElementMotion(clips: [
        walk,
        jump
      ], placed: const [
        ClipPlacement(id: "w", clip: "walk", start: 0),
        ClipPlacement(id: "j", clip: "jump", start: 3),
      ]);
      expect(at(m, 2.5).dx, 200, reason: "the walk's end held");
      var mid = at(m, 3.5);
      expect((mid.dx, mid.dy), (200, -50),
          reason: "the jump goes on from where the walk left it");
      expect(at(m, 5).dx, 200, reason: "and the walk's end is still held");
    });

    test("a camera's next move replaces the last, rather than adding", () {
      var push = MotionClip.ofKind("push", MotionKind.camera, length: 1, keys: {
        MotionProp.x: [k(0, 0), k(1, 100)],
      });
      var back = MotionClip.ofKind("back", MotionKind.camera, length: 1, keys: {
        MotionProp.x: [k(0, 100), k(1, 0)],
      });
      var m = ElementMotion(clips: [
        push,
        back
      ], placed: const [
        ClipPlacement(id: "p", clip: "push", start: 0),
        ClipPlacement(id: "b", clip: "back", start: 2),
      ]);
      expect(at(m, 1.5, replaces: true).dx, 100);
      expect(at(m, 2, replaces: true).dx, 100, reason: "not 200");
      expect(at(m, 3.5, replaces: true).dx, 0);
    });

    test("layers add, each weighed", () {
      var m = ElementMotion(clips: [
        walk,
        float
      ], placed: const [
        ClipPlacement(id: "w", clip: "walk", start: 0),
        ClipPlacement(id: "f", clip: "float", layer: 1, start: 0, length: 4),
      ], weights: const [
        1,
        0.5,
        1
      ]);
      var p = at(m, 1);
      expect(p.dx, 100);
      expect(p.dy, -5, reason: "the float at half");
      expect(p.sources.map((s) => s.clip.id), ["walk", "float"]);
    });

    test("a cut clip plays its own stretch", () {
      var m = ElementMotion(clips: [
        walk
      ], placed: const [
        ClipPlacement(id: "a", clip: "walk", start: 0, to: 1),
        ClipPlacement(id: "b", clip: "walk", layer: 1, start: 5, from: 1),
      ]);
      var times = timesOf(m);
      expect(times.span("a")!.end, 1);
      expect(at(m, 0.5).dx, 50);
      expect(at(m, 5).dx, closeTo(100 + 100, 1e-9),
          reason: "the first part held at its end, the second from 100");
    });
  });

  group("places", () {
    test("off an edge is just out of sight, whatever the page", () {
      var c = MotionClip.ofKind("x", MotionKind.arrive);
      double v(MotionPlaceKind kind, MotionProp p, [Size size = page]) =>
          motionValue(c, p, MotionPlace(kind), self,
              MotionScene(page: size, boundsOf: (_) => null));
      expect(self.right + v(MotionPlaceKind.offLeft, MotionProp.x), -14);
      expect(self.left + v(MotionPlaceKind.offRight, MotionProp.x), 960 + 14);
      expect(
          self.left +
              v(MotionPlaceKind.offRight, MotionProp.x, const Size(540, 960)),
          540 + 14,
          reason: "a tall page");
      expect(self.bottom + v(MotionPlaceKind.offTop, MotionProp.y), -14);
    });

    test("beside, on the ground of, and on another element", () {
      var c = MotionClip.ofKind("x", MotionKind.action);
      double v(MotionPlaceKind kind, MotionProp p, {Offset? drawn}) =>
          motionValue(c, p, MotionPlace(kind, target: "other"), self,
              scene(drawn: drawn));
      // Beside it, on the side it is on: the two boxes just apart.
      expect(self.center.dx + v(MotionPlaceKind.beside, MotionProp.x),
          other.center.dx - other.width / 2 - self.width / 2 - 4);
      expect(
          self.bottom + v(MotionPlaceKind.ground, MotionProp.y), other.bottom);
      expect(self.center.dx + v(MotionPlaceKind.on, MotionProp.x),
          other.center.dx);
      expect(
          self.center.dx +
              v(MotionPlaceKind.on, MotionProp.x, drawn: const Offset(800, 0)),
          800,
          reason: "where it is drawn now, moving");
    });

    test("set places are the page's, not moves", () {
      var c =
          MotionClip.ofKind("x", MotionKind.action).copyWith(absolute: true);
      expect(
          motionValue(c, MotionProp.x, const MotionNumber(100), self, scene()),
          100 - self.center.dx);
    });
  });

  group("from slots", () {
    test("plays from its start on the clock, and carries what is left", () {
      var m = ElementMotion(clips: [walk, jump]);
      var live = MotionLive(
          plays: const [LivePlay("jump", 10), null, null, null],
          carry: const [MotionPose(dx: 200), null, null, null]);
      var p =
          motionPose(m, 0, self, timesOf(m), scene(), live: live, clock: 10.5);
      expect((p.dx, p.dy), (200, -50));
      var waiting =
          motionPose(m, 0, self, timesOf(m), scene(), live: live, clock: 9);
      expect(waiting.dx, 200, reason: "queued: where it was left");
    });
  });

  group("in a document", () {
    CanvasDocument doc() =>
        CanvasDocument(frames: 96, frameRate: 24, actions: const [
          TimelineAction(id: "m", frame: 24, kind: TimelineActionKind.stop),
        ], elements: [
          ShapeElement(ElementBase(
              id: "a",
              x: 100,
              y: 100,
              width: 50,
              height: 50,
              motion: ElementMotion(clips: [
                walk
              ], placed: const [
                ClipPlacement(
                    id: "w",
                    clip: "walk",
                    startPin: ClipPin(PinKind.marker, target: "m")),
              ]))),
        ]);

    test("its placed clips move it, from the marker they are pinned to", () {
      var d = doc();
      var a = d.elementById("a")!;
      expect(poseWithMotion(a, 0, d).dx, 0);
      expect(poseWithMotion(a, 48, d).dx, closeTo(100, 1e-9),
          reason: "a second into the walk, which starts at the marker");
      expect(poseWithMotion(a, 47, d).dx, closeTo(200 * 23 / 48, 1e-9));
      expect(poseWithMotion(a, 36, null).dx, 0,
          reason: "drawn alone, it has no scene to play in");
    });

    test("and they are kept with it", () {
      var d = doc();
      var back = CanvasDocument.decode(d.encode())!;
      var a = back.elementById("a")!;
      expect(a.base.motion.placed.single.startPin,
          const ClipPin(PinKind.marker, target: "m"));
      expect(poseWithMotion(a, 48, back).dx, closeTo(100, 1e-9));
    });
  });

  group("ready-made", () {
    test("each writes keys, and is listed by what it is for", () {
      expect(presetsFor(MotionKind.arrive).map((p) => p.name),
          ["Slide in", "Fade up", "Pop", "Drop in"]);
      for (var p in motionPresets) {
        var c = p.clip("c", target: "other");
        expect(c.keys, isNotEmpty, reason: p.name);
        expect(c.kind, p.kind);
        for (var keys in c.keys.values) {
          expect(keys.last.t, lessThanOrEqualTo(c.length + 1e-9),
              reason: "${p.name}'s keys are inside it");
        }
      }
    });

    test("a slide comes from the edge it is asked to", () {
      var c = presetNamed("Slide in")!.clip("c", way: MotionWay.bottom);
      expect(c.keys[MotionProp.y]!.first.value,
          const MotionPlace(MotionPlaceKind.offBottom));
      expect(c.before, ClipHold.first, reason: "an arrival waits unseen");
    });

    test("rewritten as another, a clip keeps its own name and id", () {
      var c = presetNamed("Pop")!.clip("c").copyWith(name: "Hello");
      var f = presetNamed("Float")!.onto(c);
      expect((f.id, f.name, f.kind, f.loop),
          ("c", "Hello", MotionKind.loop, true));
      expect(presetNamed("Follow…")!.clip("f", target: "a").loop, isTrue);
      expect(
          presetNamed("Go to…")!.clip("g", target: "a").after, ClipHold.last);
    });
  });

  test("Inside it: an arrival of its own runs across the clip", () {
    var c = MotionClip.ofKind("in", MotionKind.arrive, name: "In")
        .copyWith(length: 2, inside: {
      "own": true,
      "count": [0, 10]
    });
    expect(insideAt(c, 0), {"reveal": 0.0, "count": 0.0});
    expect(insideAt(c, 1), {"reveal": 0.5, "count": 5.0});
    var out = c.copyWith(kind: MotionKind.leave);
    expect(insideAt(out, 2), {"close": 1.0, "count": 10.0});
    var back = MotionClip.fromJson(c.toJson())!;
    expect(back.inside["count"], [0, 10]);
  });

  test("placed, its own arrival hides it before and shows it after", () {
    var clip = MotionClip.ofKind("in", MotionKind.arrive, name: "In")
        .copyWith(length: 1, inside: {"own": true});
    var e = ShapeElement(ElementBase(
        id: "s",
        width: 10,
        height: 10,
        motion: ElementMotion(clips: [
          clip
        ], placed: const [
          ClipPlacement(id: "p", clip: "in", layer: 0, start: 1),
        ])));
    var doc = CanvasDocument(frames: 96, frameRate: 24, elements: [e]);
    double? reveal(int f) =>
        poseWithMotion(e, f, doc).values[KeyframeChannel.reveal];
    expect(reveal(0), 0, reason: "an arrival holds its first frame before");
    expect(reveal(36), closeTo(0.5, 1e-9));
    expect(reveal(72), isNull,
        reason: "after, nothing set: all of it there, as at rest");
  });
}
