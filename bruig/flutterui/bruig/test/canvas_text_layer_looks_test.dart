import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/model/text_looks.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/ui/animation_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_cards.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_text_layer_looks_test.dart is a look laid on one layer of a text
// (MotionDevice.layer): its own words, or one piece, rather than everything
// it draws. A text's type kept a shadow, a glow and an outline of its own
// apart from the Chain's looks; they are read in as looks on their layers,
// so each is kept once and drawn as it was (Ken, 2026-11-11).

const w = 240, h = 160;

/// jsonRoundTrip is [json] as it comes back from a file.
Map<String, dynamic> jsonRoundTrip(Map<String, dynamic> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

/// drawn is [e] painted alone, as an image's bytes.
Future<ByteData> drawn(CanvasElement e) async {
  var recorder = ui.PictureRecorder();
  paintElement(ui.Canvas(recorder), e, 0);
  var image = await recorder.endRecording().toImage(w, h);
  var bytes = (await image.toByteData())!;
  image.dispose();
  return bytes;
}

int alphaAt(ByteData b, int x, int y) => b.getUint8((y * w + x) * 4 + 3);

/// ink is how much is drawn in the rectangle, summed alpha.
int ink(ByteData b, {int x0 = 0, int y0 = 0, int x1 = w, int y1 = h}) {
  var n = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      n += alphaAt(b, x, y);
    }
  }
  return n;
}

TextElement text(
        {TextSpec spec = const TextSpec(),
        BoxSpec box = const BoxSpec(),
        List<TextItem> items = const [],
        List<MotionDevice> looks = const []}) =>
    TextElement(
      ElementBase(id: "t", x: 40, y: 30, width: 160, height: 100),
      text: "HIDE",
      textSpec: spec.copyWith(fontSize: 28, color: const Color(0xFFFFFFFF)),
      box: box,
      items: items,
    ).withBase(
        motion: const ElementBase(id: "t")
            .motion
            .copyWith(devices: withMotionDeviceIds(looks))) as TextElement;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("read in, a text's type looks become looks on its layers", () {
    const spec = TextSpec(
      outlineWidth: 2,
      outlineColor: Color(0xFF112233),
      glowBlur: 8,
      glowColor: Color(0xFF2ED6A1),
      shadowBlur: 4,
      shadowDistance: 10,
      shadowAngle: 315,
      shadowColor: Color(0x80000000),
    );

    test("the words' and each piece's, kept once", () {
      var old = text(spec: spec, items: [
        const TextItem(id: "kicker", text: "LEDGER", spec: spec),
        const TextItem(id: "plain", text: "no looks"),
      ]);
      var back = elementFromJson(jsonRoundTrip(old.toJson())) as TextElement;
      expect(hasTypeLooks(back.textSpec), isFalse,
          reason: "not kept on the type as well");
      expect(hasTypeLooks(back.items.first.spec), isFalse);
      var looks = back.base.motion.devices;
      expect([
        for (var l in looks) "${l.layer}:${l.kind.name}"
      ], [
        "body:outline", "body:glow", "body:shadow", //
        "kicker:outline", "kicker:glow", "kicker:shadow",
      ]);
      expect(looks.map((l) => l.id).toSet(), hasLength(6),
          reason: "each its own id, to animate it by");
      var shadow = looks[2];
      expect(shadow.value("angle"), 135,
          reason: "lit from the top left, it falls to the bottom right");
      expect(shadow.value("distance"), 10);
      expect(shadow.value("turns"), 1, reason: "turning with the text");
      expect(Color(shadow.colour!), const Color(0x80000000));
      expect(Color(looks[1].colour!), const Color(0xFF2ED6A1));
      expect(looks[0].value("width"), 2);
    });

    test("a text with none comes in as it was", () {
      var plain = text();
      var back = elementFromJson(jsonRoundTrip(plain.toJson()));
      expect(back.base.motion.devices, isEmpty);
    });

    test("drawn as the type drew them", () async {
      var old = text(spec: spec);
      var lifted = textLooksLifted(old);
      var a = await drawn(old), b = await drawn(lifted);
      var inkA = ink(a), inkB = ink(b);
      expect((inkB - inkA).abs() / inkA, lessThan(0.15),
          reason: "about as much drawn: $inkA then $inkB");
      // The shadow still falls down and right: more below the words than
      // above them, in both.
      int below(ByteData d) => ink(d, y0: 95, y1: 140);
      int above(ByteData d) => ink(d, y0: 20, y1: 65);
      expect(below(b) > above(b), below(a) > above(a));
    });
  });

  test("a layer's look is a look in the chain, and saved with its layer", () {
    const d = MotionDevice(MotionDeviceKind.glow, id: "m0", layer: "body");
    var back = MotionDevice.fromJson(jsonRoundTrip(d.toJson()))!;
    expect(back.layer, "body");
    expect(back, d);
    expect(d.withValue("radius", 20).layer, "body",
        reason: "kept through a change");
    expect(const MotionDevice(MotionDeviceKind.glow).toJson(),
        isNot(contains("layer")),
        reason: "nothing saved for all of it");
  });

  test("a look on the words leaves the box alone; on all of it, not", () async {
    // A tall filled box with the words at its top, and a shadow thrown a
    // long way down: on the words it falls inside the box; on all of it the
    // box's own bottom edge casts one below the box.
    const box = BoxSpec(fill: Color(0xFF203040), padding: 6);
    MotionDevice shadow(String layer) => MotionDevice(MotionDeviceKind.shadow,
        values: const {"distance": 24, "blur": 0, "angle": 180, "strength": 1},
        layer: layer);
    var onWords = await drawn(text(
        spec: const TextSpec(verticalAlign: VerticalAlignSpec.top),
        box: box,
        looks: [shadow("body")]));
    var onAll = await drawn(text(
        spec: const TextSpec(verticalAlign: VerticalAlignSpec.top),
        box: box,
        looks: [shadow("")]));
    // Just under the box (it ends at y 130), across its middle.
    expect(ink(onWords, x0: 60, x1: 180, y0: 134, y1: 150), 0);
    expect(ink(onAll, x0: 60, x1: 180, y0: 134, y1: 150), greaterThan(0));
  });

  test("a look on a piece is on that piece, not the others", () async {
    var items = const [
      TextItem(
          id: "a",
          text: "AAAA",
          slot: TextSlot.topLeft,
          spec: TextSpec(fontSize: 12)),
      TextItem(
          id: "b",
          text: "BBBB",
          slot: TextSlot.bottomRight,
          spec: TextSpec(fontSize: 12)),
    ];
    const glow = MotionDevice(MotionDeviceKind.glow,
        values: {"radius": 24, "strength": 1}, colour: 0xFFFF0000, layer: "a");
    var plain = await drawn(text(items: items));
    var glowing = await drawn(text(items: items, looks: [glow]));
    // The top left quarter (piece a) gains a glow; the bottom right (piece
    // b) is as it was.
    expect(ink(glowing, x0: 40, x1: 110, y0: 30, y1: 70),
        greaterThan(ink(plain, x0: 40, x1: 110, y0: 30, y1: 70)));
    expect(ink(glowing, x0: 145, x1: 200, y0: 100, y1: 130),
        ink(plain, x0: 145, x1: 200, y0: 100, y1: 130));
    expect(ink(plain, x0: 145, x1: 200, y0: 100, y1: 130), greaterThan(0),
        reason: "piece b is there to be left alone");
  });

  test("a style's glow is a look on the words, set again, not added again", () {
    var c = CanvasController(const CanvasDocument().addElement(text()));
    addTearDown(c.dispose);
    var name = c.saveTextStyle(c.document.elementById("t") as TextElement);
    for (var blur in [4.0, 8.0, 12.0]) {
      c.updateTextStyle(
          name,
          const TextSpec(glowColor: Color(0xFFFF0000))
              .copyWith(glowBlur: blur));
    }
    var e = c.document.elementById("t") as TextElement;
    expect(hasTypeLooks(e.textSpec), isFalse);
    var glows = [
      for (var d in e.base.motion.devices)
        if (d.kind == MotionDeviceKind.glow) d
    ];
    expect(glows, hasLength(1), reason: "one glow, restyled three times");
    expect(glows.single.layer, MotionDevice.bodyLayer);
    expect(glows.single.value("radius"), closeTo(12 * 1.1547 + 1, 0.01));
  });

  testWidgets("in the Chain, a text's look says what of it it is on",
      (tester) async {
    tester.view.physicalSize = const Size(2400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var t = text(
        items: const [TextItem(id: "kicker", text: "LEDGER")],
        looks: const [MotionDevice(MotionDeviceKind.glow, layer: "body")]);
    var c =
        CanvasController(CanvasDocument(frames: 240, frameRate: 24, elements: [
      t,
      ShapeElement(ElementBase(id: "s", x: 300, y: 30).copyWith(
          motion: const ElementBase(id: "s").motion.copyWith(devices: [
        const MotionDevice(MotionDeviceKind.glow, id: "m0"),
      ]))),
    ]));
    addTearDown(c.dispose);
    Future<void> show(String id) async {
      c.selectOnly(id);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: Align(
                    alignment: Alignment.bottomCenter,
                    child: AnimationPanel(controller: c, height: 360)))),
      ));
      await tester.pumpAndSettle();
    }

    await show("t");
    var id = c.document.elementById("t")!.base.motion.devices.single.id;
    var on = find.byKey(ValueKey("mdevLayer-$id"));
    expect(on, findsOneWidget);
    var drop = tester.widget<StudioDrop<String>>(on);
    expect(drop.value, "body");
    expect([for (var o in drop.options) o.$1], ["", "body", "kicker"]);
    drop.onChanged("kicker");
    await tester.pumpAndSettle();
    expect(c.document.elementById("t")!.base.motion.devices.single.layer,
        "kicker");

    await show("s");
    expect(find.byKey(const ValueKey("mdevLayer-m0")), findsNothing,
        reason: "a shape has no layers to choose from");
  });
}
