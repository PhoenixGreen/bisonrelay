import 'dart:convert';
import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/design_device.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/model/own_motion.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_motion_phases_test.dart is a device's keys in its element's
// arrival, leaving and loop, or independently (Ken, 2026-11-12: "A, L,
// Loop, I"), and the Design device that animates the element's own
// settings.

const glow = MotionDevice(MotionDeviceKind.glow, id: "m0");

// One second in (0-1 s), two seconds of loop, then out (3-4 s).
const spans = PhaseSpans(arrive: (0, 1), leave: (3, 4), loop: (1, 3), cycle: 1);

/// texted is a text arriving over its first second and leaving over 3-4 s
/// of a 5 s scene at 24 a second, with [devices].
(CanvasDocument, TextElement) texted(List<MotionDevice> devices) {
  CanvasElement e =
      TextElement(const ElementBase(id: "t", x: 10, y: 10), text: "Words");
  e = withOwnSpan(e, MotionKind.arrive, 0, 24, 24);
  e = withOwnSpan(e, MotionKind.leave, 72, 96, 24);
  e = e.withBase(motion: e.base.motion.copyWith(devices: devices));
  var doc = CanvasDocument(frames: 120, frameRate: 24, elements: [e]);
  return (doc, doc.elementById("t") as TextElement);
}

void main() {
  group("phase spans", () {
    test("which clip is playing, and how far through", () {
      expect(spans.phaseAt(0.5), MotionPhase.arrive);
      expect(spans.phaseAt(2), MotionPhase.loop);
      expect(spans.phaseAt(3.5), MotionPhase.leave);
      expect(spans.phaseAt(4.5), MotionPhase.free);
      expect(spans.shareIn(MotionPhase.arrive, 0.25), closeTo(0.25, 1e-9));
      expect(spans.shareIn(MotionPhase.loop, 2.5), closeTo(0.5, 1e-9),
          reason: "a share of one go round, every go round");
      expect(spans.timeOf(MotionPhase.leave, 0.5), closeTo(3.5, 1e-9));
    });

    test("from the element's own clips and loop", () {
      var (doc, e) = texted([glow.withPlaying(MotionPhase.arrive, true)]);
      var s = phaseSpansOf(e, doc);
      expect(s.arrive, (0.0, 1.0));
      expect(s.leave, (3.0, 4.0));
      expect(s.loop, (1.0, 3.0), reason: "between arriving and leaving");
      expect(s.cycle, 2, reason: "two seconds where it has no loop");
    });

    test("none where nothing plays in a clip", () {
      var (doc, e) = texted([glow.withKey("strength", 1, 0.2)]);
      expect(phaseSpansOf(e, doc), PhaseSpans.none);
    });
  });

  group("keys in a phase", () {
    var arriving = glow.withPlaying(MotionPhase.arrive, true);

    test("a key made in the arrival goes in it, as a share of it", () {
      var d = arriving
          .withKey("strength", 0, 0, spans: spans)
          .withKey("strength", 0.5, 1, spans: spans);
      expect(d.keyedIn("strength", MotionPhase.arrive), isTrue);
      expect(d.keys, isEmpty, reason: "nothing independent");
      expect(d.phaseKeys[MotionPhase.arrive]!["strength"]!.last.t, 0.5);
      expect(d.valueAt("strength", 0.25, spans: spans), closeTo(0.5, 1e-9));
    });

    test("they stretch with the clip", () {
      var d = arriving
          .withKey("strength", 0, 0, spans: spans)
          .withKey("strength", 1, 1, spans: spans);
      const longer = PhaseSpans(arrive: (0, 2));
      expect(d.valueAt("strength", 1, spans: longer), closeTo(0.5, 1e-9));
    });

    test("outside its clips, the independent keys play", () {
      var d = arriving
          .withKey("strength", 0.5, 0.9, spans: spans)
          .withKey("strength", 4.5, 0.1, spans: spans);
      expect(d.keyedIn("strength", MotionPhase.free), isTrue);
      expect(d.valueAt("strength", 0.5, spans: spans), 0.9);
      expect(d.valueAt("strength", 4.5, spans: spans), 0.1);
    });

    test("a phase switched off keeps its keys, unplayed", () {
      var d = arriving
          .withKey("strength", 0.5, 0.9, spans: spans)
          .withPlaying(MotionPhase.arrive, false);
      expect(d.keyedIn("strength", MotionPhase.arrive), isTrue);
      expect(d.valueAt("strength", 0.5, spans: spans), d.value("strength"));
    });

    test("the loop's keys play every go round", () {
      var d = glow
          .withPlaying(MotionPhase.loop, true)
          .withKey("radius", 1, 0, spans: spans)
          .withKey("radius", 1.5, 40, spans: spans);
      expect(d.valueAt("radius", 1.5, spans: spans), 40);
      expect(d.valueAt("radius", 2.5, spans: spans), 40,
          reason: "the second go round");
      expect(d.valueAt("radius", 2.25, spans: spans), closeTo(20, 1e-9));
    });

    test("with no spans, every key plays independently, as before", () {
      var d = glow.withKey("strength", 1, 0).withKey("strength", 2, 0.8);
      expect(d.valueAt("strength", 1.5), closeTo(0.4, 1e-9));
      expect(d.at(1.5).value("strength"), closeTo(0.4, 1e-9));
    });

    test("eased into the next key", () {
      var d = glow.withKey("strength", 0, 0).withKey("strength", 1, 1);
      var eased = d.withKeysOf("strength", MotionPhase.free, [
        const DeviceKey(0, 0, ease: KeyEase.hold),
        const DeviceKey(1, 1),
      ]);
      expect(eased.valueAt("strength", 0.9), 0);
      expect(d.valueAt("strength", 0.9), closeTo(0.9, 1e-9));
    });

    test("kept, phases, plays, shown and easing", () {
      var d = glow
          .withPlaying(MotionPhase.loop, true)
          .withKey("radius", 1.5, 40, spans: spans)
          .withKeysOf("strength", MotionPhase.free, [
        const DeviceKey(0, 0.2, ease: KeyEase.easeOut)
      ]).withShown(["radius"]);
      var back = MotionDevice.fromJson(jsonDecode(jsonEncode(d.toJson())))!;
      expect(back, d);
      expect(back.plays, {MotionPhase.free, MotionPhase.loop});
      expect(back.keys["strength"]!.single.ease, KeyEase.easeOut);
    });

    test("an old device reads as before: independent keys only", () {
      var back = MotionDevice.fromJson({
        "kind": "glow",
        "keys": {
          "strength": [
            [1, 0],
            [2, 0.8]
          ]
        },
      })!;
      expect(back.plays, {MotionPhase.free});
      expect(back.valueAt("strength", 1.5), closeTo(0.4, 1e-9));
    });
  });

  group("Design", () {
    const design = MotionDevice(MotionDeviceKind.design, id: "d0");

    test("offers a text's letters and box, and every element its place", () {
      var (_, e) = texted(const []);
      var all = [for (var (_, ids) in designChoices(e)) ...ids];
      expect(all, containsAll(["x", "opacity", "fontSize", "fill", "pad"]));
      var shape = const TextElement(ElementBase(id: "x"));
      expect(designChoices(shape).length, 3);
      for (var id in all) {
        expect(design.kind.param(id).id, id);
      }
    });

    test("its place moves the pose, after the pose devices", () {
      var d = design.withValue("x", 30).withValue("opacity", 0.5);
      var (doc, e) = texted([d]);
      var pose = poseWithMotion(e, 60, doc);
      var plain = poseWithMotion(texted(const []).$2, 60, doc);
      expect(pose.dx, closeTo(plain.dx + 30, 1e-9));
      expect(pose.opacity, closeTo(plain.opacity * 0.5, 1e-9));
    });

    test("its keys in the arrival slide it in", () {
      var d = design
          .withPlaying(MotionPhase.arrive, true)
          .withKey("x", 0, -90, spans: spans)
          .withKey("x", 1, 0, spans: spans);
      var (doc, e) = texted([d]);
      var plain = texted(const []).$2;
      double moved(int f) =>
          poseWithMotion(e, f, doc).dx - poseWithMotion(plain, f, doc).dx;
      expect(moved(0), closeTo(-90, 1e-6));
      expect(moved(12), closeTo(-45, 1e-6));
      expect(moved(60), closeTo(0, 1e-6), reason: "arrived, it rests");
    });

    test("the element's own settings rest as its panel has them", () {
      var (doc, e) = texted([design]);
      expect(designRest(e, design, "fontSize"), e.textSpec.fontSize);
      expect(identical(designedNow(e, 60, doc), e), isTrue,
          reason: "nothing keyed, nothing changed");
    });

    test("keyed, the text is drawn with them", () {
      var red = const Color(0xFFFF0000).toARGB32().toDouble();
      var blue = const Color(0xFF0000FF).toARGB32().toDouble();
      var d = design
          .withKey("fontSize", 0, 20)
          .withKey("fontSize", 2, 60)
          .withKey("colour", 0, red)
          .withKey("colour", 2, blue);
      var (doc, e) = texted([d]);
      var now = designedNow(e, 24, doc) as TextElement;
      expect(now.textSpec.fontSize, closeTo(40, 1e-9));
      var c = now.textSpec.color;
      expect((c.r * 255).round(), closeTo(128, 1));
      expect((c.b * 255).round(), closeTo(128, 1));
      expect(e.textSpec.fontSize, isNot(40), reason: "the element is kept");
    });

    test("skew joins the element's own", () {
      var (doc, e) = texted([design.withValue("skewX", 10)]);
      expect(designedNow(e, 0, doc).base.skewX, closeTo(10, 1e-9));
    });

    test("a colour's key reads as its hex", () {
      expect(
          design.kind.param("fill").reading(0xFF00FF00.toDouble()), "#00FF00");
    });
  });

  // Ken, 2026-11-12: "+ Setting" offers each element's whole list.
  group("every element's own settings", () {
    const base = ElementBase(id: "e", width: 200, height: 100);
    for (var e in <CanvasElement>[
      const TextElement(base),
      ShapeElement(base),
      const LineElement(base),
      const PathElement(base),
      const ButtonElement(base),
      const CounterElement(base),
      ChartElement(base),
      const TableElement(base),
      // Every other kind, as it is first added -- all but the camera, whose
      // view is read where the stage is filmed.
      for (var kind in ElementKind.values)
        if (!const {
          ElementKind.text,
          ElementKind.shape,
          ElementKind.line,
          ElementKind.path,
          ElementKind.button,
          ElementKind.counter,
          ElementKind.chart,
          ElementKind.table,
          ElementKind.camera,
          ElementKind.stage,
          ElementKind.parallax,
        }.contains(kind))
          newElement(kind, const CanvasDocument()),
      // A stage and scenery are added as a background carrying them.
      newElement(ElementKind.stage, const CanvasDocument()),
      newElement(ElementKind.parallax, const CanvasDocument()),
    ]) {
      test(
          "${e.kind.label}"
          "${e is BackgroundElement ? " (${e.backdrop.name})" : ""}: "
          "offered, read and written", () {
        var table = designTable(e);
        expect(table, isNotEmpty);
        var offered = [for (var (_, ids) in designChoices(e)) ...ids];
        for (var s in table) {
          expect(offered, contains(s.id));
          var p = MotionDeviceKind.design.param(s.id);
          // A value of its range other than where it rests.
          var v = p.unit == "argb"
              ? 0xFF336699.toDouble()
              : (p.min + (p.max - p.min) * 0.37).roundToDouble();
          var next = designWritten(e, s.id, v);
          expect(
              s.read(next),
              closeTo(p.unit == "#" ? v.roundToDouble() : v,
                  p.id == "weight" ? 50 : 1e-6),
              reason: "${s.id} written and read back");
        }
      });
    }

    test("keyed, a shape's fill is drawn as its keys have it", () {
      var red = 0xFFFF0000.toDouble(), blue = 0xFF0000FF.toDouble();
      var d = const MotionDevice(MotionDeviceKind.design, id: "d0")
          .withKey("fill", 0, red)
          .withKey("fill", 2, blue);
      var now = designed(ShapeElement(base), d, 1) as ShapeElement;
      expect((now.fill.r * 255).round(), closeTo(128, 1));
    });
  });
}
