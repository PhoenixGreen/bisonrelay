import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bruig/components/color_picker.dart';
import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/components/saved_colors.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_outfit.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/metronome_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/colour_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/layers_panel.dart';

import 'support/canvas_app.dart';
import 'support/canvas_sidebar_host.dart';
import 'support/colour_rich.dart';

// canvas_editing_fixes_test.dart is a pass over the editor after a video was
// made with it: several layers picked at once, the Colour section reaching
// every kind of element, a saved colour replaced everywhere, the master's
// music changed from a scene, and the camera seen while scrubbing.

const _teal = Color(0xFF2ED6A1);
const _pink = Color(0xFFFF4FA3);

Future<void> _show(WidgetTester tester, Widget child,
    {bool settle = true}) async {
  setTestScreen(tester, const Size(1400, 1800));
  await tester.pumpWidget(canvasApp(child));
  // A mixer on the panel meters for as long as it is shown, and never
  // settles.
  settle
      ? await tester.pumpAndSettle()
      : await tester.pump(const Duration(milliseconds: 100));
}

ShapeElement _box(String id) => ShapeElement(ElementBase(id: id, name: id));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group("layers", () {
    CanvasController four() {
      var c = CanvasController(const CanvasDocument()
          .addElement(_box("a"))
          .addElement(_box("b"))
          .addElement(_box("c"))
          .addElement(_box("d")));
      addTearDown(c.dispose);
      return c;
    }

    testWidgets("Cmd-click adds a layer, and takes it away again",
        (tester) async {
      var c = four();
      await _show(tester, CanvasLayersPanel(controller: c));
      await tester.tap(find.text("a"));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.tap(find.text("c"));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(c.selection, {"a", "c"});
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.tap(find.text("a"));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(c.selection, {"c"});
    });

    testWidgets("the selected row deletes its layer, for a tablet",
        (tester) async {
      var c = four();
      await _show(tester, CanvasLayersPanel(controller: c));
      expect(find.byKey(const ValueKey("layerDelete-b")), findsNothing,
          reason: "only the selected row has one");
      await tester.tap(find.text("b"));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("layerDelete-b")));
      await tester.pumpAndSettle();
      expect(c.document.elementById("b"), isNull);
      expect(c.selection, isEmpty);
      c.undo();
      expect(c.document.elementById("b"), isNotNull, reason: "undone");
    });

    testWidgets("Shift-click picks the run between", (tester) async {
      var c = four();
      await _show(tester, CanvasLayersPanel(controller: c));
      await tester.tap(find.text("a"));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.text("c"));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(c.selection, {"a", "b", "c"});
    });
  });

  group("the Colour section", () {
    List<String> slots(CanvasElement e) {
      var c = CanvasController(const CanvasDocument().addElement(e));
      addTearDown(c.dispose);
      c.selectOnly(e.id);
      return [for (var s in colourSlotsFor(c)) s.id];
    }

    test("has colours for a chart, a counter, a table and a tinted drawing",
        () {
      expect(
          slots(const ChartElement(ElementBase(id: "x"),
              data: ChartData(categories: [
                "a"
              ], series: [
                ChartSeries(name: "one", color: _teal, values: [1]),
                ChartSeries(name: "two", color: _pink, values: [2]),
              ]))),
          ["series0", "series1"]);
      expect(
          slots(const ChartElement(ElementBase(id: "x"),
              type: ChartType.pie,
              data: ChartData(categories: [
                "a",
                "b",
                "c"
              ], series: [
                ChartSeries(name: "s", color: _teal, values: [1, 2, 3]),
              ]))),
          ["slice0", "slice1", "slice2"]);
      expect(slots(const CounterElement(ElementBase(id: "x"))),
          ["number", "words", "box"]);
      expect(slots(const TableElement(ElementBase(id: "x"))),
          ["header", "headerText", "cellText"]);
      expect(
          slots(const VectorElement(ElementBase(id: "x"),
              assetId: "shield.svg", tint: _teal)),
          ["tint"]);
    });

    test("a chart's series slot sets that series", () {
      var e = const ChartElement(ElementBase(id: "x"),
          data: ChartData(categories: [
            "a"
          ], series: [
            ChartSeries(name: "one", color: _teal, values: [1]),
          ]));
      var c = CanvasController(const CanvasDocument().addElement(e));
      addTearDown(c.dispose);
      c.selectOnly("x");
      colourSlotsFor(c).single.setColour(_pink, transient: false);
      expect(
          (c.document.elements.single as ChartElement).data.series.single.color,
          _pink);
    });
  });

  group("a saved colour replaced everywhere", () {
    test("changes every use on the canvas, as one change", () {
      var c = CanvasController(CanvasDocument(scenes: [
        const CanvasScene(id: "a", elements: [
          ShapeElement(ElementBase(id: "one"), fill: _teal),
        ]),
        CanvasScene(id: "b", elements: [
          ShapeElement(const ElementBase(id: "two"),
              fill: _teal.withValues(alpha: 0.5)),
        ]),
      ]));
      addTearDown(c.dispose);
      c.replaceColour(_teal, _pink);
      var two = c.document.allScenes[1].elements.single as ShapeElement;
      expect((c.document.allScenes[0].elements.single as ShapeElement).fill,
          _pink);
      expect(two.fill.withValues(alpha: 1), _pink);
      expect(two.fill.a, closeTo(0.5, 0.01));
      c.undo();
      expect((c.document.allScenes[0].elements.single as ShapeElement).fill,
          _teal);
    });

    test("a fade's second colour too", () {
      // A fade's colours after its first are the gradient's own, not the
      // shape's: reached through the fade.
      var c = CanvasController(const CanvasDocument().addElement(
          const ShapeElement(ElementBase(id: "a"),
              fill: _teal, fillFade: GradientSpec(to: _teal))));
      addTearDown(c.dispose);
      c.replaceColour(_teal, _pink);
      var shape = c.document.elements.single as ShapeElement;
      expect(shape.fill, _pink);
      expect(shape.fillFade!.to, _pink);
    });

    test("a colour keyed in a Design device too", () {
      var teal = _teal.toARGB32().toDouble();
      var c = CanvasController(const CanvasDocument()
          .addElement(const ShapeElement(ElementBase(id: "a")).withBase(
              motion: ElementMotion(devices: [
        MotionDevice(MotionDeviceKind.design, id: "m0", keys: {
          "fill": [DeviceKey(0, teal), DeviceKey(1, teal)],
        }, values: {
          "strokeColour": teal
        }),
      ]))));
      addTearDown(c.dispose);
      c.replaceColour(_teal, _pink);
      var design = c.document.elements.single.base.motion.devices.single;
      var pink = _pink.toARGB32().toDouble();
      expect([for (var k in design.keys["fill"]!) k.v], [pink, pink]);
      expect(design.values["strokeColour"], pink);
    });

    test("a 3D character's clothes too", () {
      var doc = colourRichDocument();
      Garment top(CanvasDocument d) => d.scene.elements
          .whereType<Character3dElement>()
          .single
          .design
          .outfit[WearSlot.top];
      var c = CanvasController(doc);
      addTearDown(c.dispose);
      c.replaceColour(Color(0xFF000000 | top(doc).colour), _pink);
      expect(top(c.document).colour, _pink.toARGB32() & 0xFFFFFF);
    });

    test("an outline's colour while it is off, seen once it is on", () {
      var c = CanvasController(const CanvasDocument().addElement(
          const TextElement(ElementBase(id: "t"),
              text: "Hi", textSpec: TextSpec(outlineColor: _teal))));
      addTearDown(c.dispose);
      c.replaceColour(_teal, _pink);
      var text = c.document.elements.single as TextElement;
      var on = text.textSpec.copyWith(outlineWidth: 2);
      expect(on.outlineColor, _pink);
    });

    test("a fully clear use too, staying clear", () {
      var c = CanvasController(const CanvasDocument().addElement(ShapeElement(
          const ElementBase(id: "a"),
          fill: _teal.withValues(alpha: 0))));
      addTearDown(c.dispose);
      c.replaceColour(_teal, _pink);
      var fill = (c.document.elements.single as ShapeElement).fill;
      expect(fill, _pink.withValues(alpha: 0));
    });

    test("not a chroma key, a removal key, a handle or a row's colour", () {
      var doc = colourRichDocument();
      var kept = documentKept(doc);
      for (var k in kept) {
        Color colour = switch (k) {
          Color c => c,
          int v => Color(0xFF000000 | (v & 0xFFFFFF)),
          _ => const Color(0x00000000),
        };
        if (colour.a == 0) continue;
        var c = CanvasController(doc);
        c.replaceColour(colour, _pink);
        expect(documentKept(c.document), kept, reason: "$k");
        c.dispose();
      }
    });

    test("a flipped tile's word and a drawn text survive", () {
      var doc = colourRichDocument();
      var kept = documentKept(doc);
      var c = CanvasController(doc);
      addTearDown(c.dispose);
      // A flipped tile from the first set has black's red, green and blue.
      c.replaceColour(const Color(0xFF000000), _pink);
      expect(documentKept(c.document), kept);
      var drawing = c.document.scene.elements.whereType<VectorElement>().single;
      var sig = drawing.shapes!.first.liveText!.signature;
      c.replaceColour(Color(0xFF000000 | (sig & 0xFFFFFF)), _pink);
      drawing = c.document.scene.elements.whereType<VectorElement>().single;
      expect(drawing.shapes!.first.liveText?.signature, sig);
      expect(documentKept(c.document), kept);
    });

    test("a colour that is nowhere changes nothing and makes no step", () {
      var doc = colourRichDocument();
      var c = CanvasController(doc);
      addTearDown(c.dispose);
      var before = c.document;
      c.replaceColour(colourSentinel, _pink);
      expect(identical(c.document, before), isTrue);
      expect(c.canUndo, isFalse);
    });

    test("what is not saved while off keeps its value, and the rest its self",
        () {
      const shadow = Color(0xFF7A3B10);
      var words = TextElement(const ElementBase(id: "t"),
          text: "Hi", textSpec: const TextSpec(shadowColor: shadow));
      var other = MetronomeElement(const ElementBase(id: "m"), body: _pink);
      var c = CanvasController(const CanvasDocument()
          .addElement(words)
          .addElement(other)
          .addElement(const ShapeElement(ElementBase(id: "s"), fill: _teal)));
      addTearDown(c.dispose);
      var untouched = c.document.elementById("t");
      c.replaceColour(_teal, const Color(0xFF101010));
      var text = c.document.elementById("t") as TextElement;
      expect(text.textSpec.shadowColor, shadow,
          reason: "a shadow's colour is not saved while there is no shadow");
      expect(identical(c.document.elementById("t"), untouched), isTrue,
          reason: "an element with no use of the colour is not remade");
    });

    testWidgets("from the picker: Replace, then the saved colour",
        (tester) async {
      await tester.runAsync(() => SavedColors.instance.add(_teal));
      addTearDown(() => SavedColors.instance.remove(_pink));
      (Color, Color)? asked;
      await _show(
          tester,
          SizedBox(
            width: 600,
            child: AppColorPicker(
                color: _pink,
                onChanged: (_) {},
                onReplaceEverywhere: (from, to) => asked = (from, to)),
          ));
      await tester.tap(find.byKey(const ValueKey("replaceColor")));
      await tester.pumpAndSettle();
      await tester.tap(find
          .descendant(
              of: find.byKey(const ValueKey("savedSwatches")),
              matching: byTip("#ff2ed6a1"))
          .first);
      await tester.pumpAndSettle();
      expect(asked, (_teal, _pink));
      expect(SavedColors.instance.has(_pink), isTrue,
          reason: "the saved colour is the new one now");
      expect(SavedColors.instance.has(_teal), isFalse);
    });

    testWidgets("is not offered outside a canvas", (tester) async {
      await tester.runAsync(() => SavedColors.instance.add(_teal));
      addTearDown(() => SavedColors.instance.remove(_teal));
      await _show(
          tester,
          SizedBox(
              width: 600,
              child: AppColorPicker(color: _pink, onChanged: (_) {})));
      expect(find.byKey(const ValueKey("replaceColor")), findsNothing);
    });
  });

  testWidgets("the master's music picked from a scene shows its settings",
      (tester) async {
    AudioElement clip(String id, String channel) =>
        AudioElement(ElementBase(id: id, name: id, visible: false),
            clip: MediaClip(
                timed: true,
                channel: channel,
                playlist: const [MediaSource(assetId: "a.mp3", length: 30)]));
    var c = CanvasController(CanvasDocument(
        masterOn: true,
        master: CanvasScene(
            id: "m", elements: [clip("music", "music"), clip("vo", "voice")]),
        scenes: const [
          CanvasScene(id: "a", frames: 100),
          CanvasScene(id: "b", frames: 100),
        ]));
    addTearDown(c.dispose);
    c.pickClip("music");
    await _show(tester, designSidebar(c), settle: false);
    expect(find.byKey(const ValueKey("strip-music")), findsOneWidget,
        reason: "its channel's mixer");
  });

  group("the camera", () {
    test("is looked through while it is set, and let go of on a press", () {
      var c = CanvasController(const CanvasDocument(scenes: [
        CanvasScene(id: "a", frames: 100),
        CanvasScene(id: "b", frames: 100),
      ]));
      addTearDown(c.dispose);
      expect(c.cameraView, isFalse);
      c.setSceneCamera(0, const SceneCamera(toZoom: 1.2));
      expect(c.cameraView, isTrue, reason: "seen as it is set");
      c.setSceneCamera(0, null);
      expect(c.cameraView, isFalse, reason: "nothing to look through");
    });
  });
}
