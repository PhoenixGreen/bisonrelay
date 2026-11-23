import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/colour_map.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_decal.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_look.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_outfit.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_sculpt.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_shape.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_data.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_highlight.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_adjustment.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_effects.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_strokes.dart';
import 'package:bruig/plugin_system/canvas/model/elements/metronome_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/parallax_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/elements/tile_map_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/instances.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_layers.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_light.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_rings.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/presets/builtin_presets.dart';

import 'support/colour_rich.dart';
import 'support/element_samples.dart';

// canvas_colour_map_test.dart holds the colour visitor (colour_map.dart) to
// its promises: a map that changes nothing changes nothing, down to the
// object; every colour a thing holds is reached and those that must not be
// are not; each is told truly whether it shows; and nothing else is
// disturbed on the way.

Color _same(Color c, {required bool shown}) => c;
Color _sentinel(Color c, {required bool shown}) => colourSentinel;

/// _flip changes every colour, and changes it back when done twice.
Color _flip(Color c, {required bool shown}) => Color(c.toARGB32() ^ 0x00010101);

String _json(Object o) => jsonEncode(o);

List<(String, CanvasElement)> _allElements() => [
      ...elementSamples(),
      ...filledSamples(),
      for (var (name, e) in colourRichElements()) ("Rich $name", e),
    ];

List<(String, CanvasDocument)> _allDocuments() => [
      ("empty document", const CanvasDocument()),
      for (var p in builtinPresets) ("built-in ${p.id}", p.build()),
      ("colour-rich document", colourRichDocument()),
    ];

/// _shownOf is what the map was told of [probe]: whether it shows, or null
/// if it was never handed it.
bool? _shownOf(Color probe, void Function(ColourMap f) run) {
  bool? out;
  run((c, {required bool shown}) {
    if (c == probe) out = shown;
    return c;
  });
  return out;
}

void main() {
  group("nothing in, nothing out", () {
    test("every element comes back the very same object", () {
      for (var (name, e) in _allElements()) {
        expect(identical(e.mapColours(_same), e), isTrue, reason: name);
      }
    });

    test("every document comes back the very same object", () {
      for (var (name, d) in _allDocuments()) {
        expect(identical(d.mapColours(_same), d), isTrue, reason: name);
      }
    });

    test("a colour handed back equal but not the same changes nothing", () {
      Color copy(Color c, {required bool shown}) => Color(c.toARGB32());
      var doc = colourRichDocument();
      expect(identical(doc.mapColours(copy), doc), isTrue);
    });
  });

  group("every colour is reached", () {
    test("each kind's colours all become the one sentinel", () {
      for (var (name, e) in colourRichElements()) {
        var before = elementColours(e);
        var after = elementColours(e.mapColours(_sentinel));
        expect(before, isNot(contains(colourSentinel)), reason: name);
        expect(after.length, before.length, reason: name);
        expect(after.every((c) => c == colourSentinel), isTrue,
            reason: "$name: ${after.where((c) => c != colourSentinel)}");
      }
    });

    test("every kind with colours has them read", () {
      const none = {
        ElementKind.camera,
        ElementKind.object3d,
        ElementKind.synth,
        ElementKind.synthTask,
        ElementKind.codeRun,
      };
      var kinds = {for (var (_, e) in colourRichElements()) e.kind};
      expect(kinds, ElementKind.values.toSet());
      for (var (name, e) in colourRichElements()) {
        if (none.contains(e.kind)) {
          expect(elementColours(e), isEmpty, reason: name);
          expect(identical(e.mapColours(_sentinel), e), isTrue, reason: name);
        } else {
          expect(elementColours(e), isNotEmpty, reason: name);
        }
      }
    });

    test("the whole document's colours all become the sentinel", () {
      var doc = colourRichDocument();
      var before = documentColours(doc);
      var after = documentColours(doc.mapColours(_sentinel));
      expect(before, isNot(contains(colourSentinel)));
      expect(after.length, before.length);
      expect(after.every((c) => c == colourSentinel), isTrue);
    });

    test("what is not to be mapped is left as it was", () {
      for (var (name, e) in colourRichElements()) {
        var kept = keptColours(e);
        expect(keptColours(e.mapColours(_sentinel)), kept, reason: name);
      }
      var doc = colourRichDocument();
      expect(documentKept(doc), isNotEmpty);
      expect(documentKept(doc.mapColours(_sentinel)), documentKept(doc));
    });

    test("the fixture holds every colour that is never mapped", () {
      var kept = [
        for (var (_, e) in colourRichElements()) ...keptColours(e),
      ];
      // A row colour, the two keys, the handles, an eraser's paint, a
      // colour table, a terrain's swatch and two tile words.
      expect(kept.length, greaterThanOrEqualTo(9));
    });
  });

  group("shown or not", () {
    void expectShown(String what, Color probe,
        void Function(ColourMap f) whenOff, void Function(ColourMap f) whenOn) {
      expect(_shownOf(probe, whenOff), isFalse, reason: "$what, off");
      expect(_shownOf(probe, whenOn), isTrue, reason: "$what, on");
    }

    const p = Color(0xFF5A6B7C);

    test("type: outline, shadow and glow only while on", () {
      expectShown("outline", p, (f) => TextSpec(outlineColor: p).mapColours(f),
          (f) => TextSpec(outlineColor: p, outlineWidth: 1).mapColours(f));
      expectShown("shadow", p, (f) => TextSpec(shadowColor: p).mapColours(f),
          (f) => TextSpec(shadowColor: p, shadowDistance: 2).mapColours(f));
      expectShown("glow", p, (f) => TextSpec(glowColor: p).mapColours(f),
          (f) => TextSpec(glowColor: p, glowBlur: 2).mapColours(f));
      expectShown("fill overlay", p, (f) => TextFill(overlay: p).mapColours(f),
          (f) => TextFill(overlay: p, blend: OverlayBlend.wash).mapColours(f));
      expectShown(
          "fill pattern",
          p,
          (f) => TextFill(pattern: ProceduralSpec(accent: p)).mapColours(f),
          (f) => TextFill(
                  kind: TextFillKind.pattern,
                  pattern: ProceduralSpec(accent: p))
              .mapColours(f));
    });

    test("box: border only with a width, painting only while painted", () {
      expectShown("border", p, (f) => BoxSpec(borderColor: p).mapColours(f),
          (f) => BoxSpec(borderColor: p, borderWidth: 1).mapColours(f));
      expectShown(
          "painted",
          p,
          (f) =>
              BoxSpec(painted: TextFill(pattern: ProceduralSpec(background: p)))
                  .mapColours(f),
          (f) => BoxSpec(
                  painted: TextFill(
                      kind: TextFillKind.pattern,
                      pattern: ProceduralSpec(background: p)))
              .mapColours(f));
    });

    test("pattern: light, rings and layers", () {
      expectShown("light", p, (f) => LightSpec(color: p).mapColours(f),
          (f) => LightSpec(on: true, color: p).mapColours(f));
      var icon = RingIcon(tinted: true, tint: p);
      expectShown(
          "ring tint",
          p,
          (f) => ProceduralSpec(rings: RingSpec(icons: [icon])).mapColours(f),
          (f) => ProceduralSpec(
              style: ProceduralStyle.rings,
              rings: RingSpec(icons: [icon])).mapColours(f));
      expectShown("untinted ring", p, (f) => RingIcon(tint: p).mapColours(f),
          (f) => icon.mapColours(f));
      var layer = BackgroundLayer(spec: ProceduralSpec(background: p));
      expectShown(
          "hidden layer",
          p,
          (f) => layer.copyWith(visible: false).mapColours(f),
          (f) => layer.mapColours(f));
    });

    test("loops, looks and motion", () {
      expectShown(
          "loop",
          p,
          (f) => ElementLoop(colour: PaintSpec(p)).mapColours(f),
          (f) => ElementLoop(preset: LoopPreset.shimmer, colour: PaintSpec(p))
              .mapColours(f));
      var glow = MotionDevice(MotionDeviceKind.glow, colour: p.toARGB32());
      expectShown("glow device", p, (f) => glow.switched(false).mapColours(f),
          (f) => glow.mapColours(f));
      expectShown(
          "motion off",
          p,
          (f) => ElementMotion(devices: [glow], off: true).mapColours(f),
          (f) => ElementMotion(devices: [glow]).mapColours(f));
      expectShown(
          "a colour on a device that draws none",
          p,
          (f) => MotionDevice(MotionDeviceKind.blur, colour: p.toARGB32())
              .mapColours(f),
          (f) => glow.mapColours(f));
    });

    test("pictures", () {
      var base = const ElementBase(id: "i");
      const clear = Color(0x005A6B7C);
      expect(
          _shownOf(
              clear, (f) => ImageElement(base, tint: clear).mapOwnColours(f)),
          isFalse,
          reason: "transparent tint");
      expect(_shownOf(p, (f) => ImageElement(base, tint: p).mapOwnColours(f)),
          isTrue,
          reason: "tint");
      expectShown(
          "overlay",
          p,
          (f) => ImageElement(base, overlay: p).mapOwnColours(f),
          (f) => ImageElement(base, overlay: p, blend: OverlayBlend.screen)
              .mapOwnColours(f));
      expectShown("outline", p, (f) => ImageOutline(color: p).mapColours(f),
          (f) => ImageOutline(color: p, width: 1).mapColours(f));
      expectShown(
          "effect",
          p,
          (f) => LayerEffect(kind: EffectKind.blur, colour: p).mapColours(f),
          (f) => LayerEffect(kind: EffectKind.dropShadow, colour: p)
              .mapColours(f));
      expectShown(
          "stroke",
          p,
          (f) => StrokeMark(kind: StrokeKind.erase, points: [], colour: p)
              .mapColours(f),
          (f) => StrokeMark(kind: StrokeKind.paint, points: [], colour: p)
              .mapColours(f));
      expectShown(
          "adjustment",
          p,
          (f) => ImageAdjustment(kind: AdjustKind.hueSaturation, colour: p)
              .mapColours(f),
          (f) => ImageAdjustment(kind: AdjustKind.photoFilter, colour: p)
              .mapColours(f));
      var fill = ImageLayer(id: "l", kind: LayerKind.fill, fill: PaintSpec(p));
      expectShown(
          "hidden layer",
          p,
          (f) => fill.copyWith(visible: false).mapColours(f),
          (f) => fill.mapColours(f));
      expectShown(
          "fill on another kind of layer",
          p,
          (f) => ImageLayer(id: "l", kind: LayerKind.paint, fill: PaintSpec(p))
              .mapColours(f),
          (f) => fill.mapColours(f));
    });

    test("charts, tables and sheets", () {
      expectShown("backdrop", p, (f) => ChartBackdrop(fill: p).mapColours(f),
          (f) => ChartBackdrop(on: true, fill: p).mapColours(f));
      expectShown(
          "highlight",
          p,
          (f) => ChartHighlight(colour: p, off: true).mapColours(f),
          (f) => ChartHighlight(colour: p).mapColours(f));
      expect(
          _shownOf(
              const Color(0x00ABCDEF),
              (f) => TableCellStyle(background: const Color(0x00ABCDEF))
                  .mapColours(f)),
          isFalse,
          reason: "transparent cell");
      expect(
          _shownOf(
              const Color(0x80ABCDEF),
              (f) => TableCellStyle(background: const Color(0x80ABCDEF))
                  .mapColours(f)),
          isTrue,
          reason: "cell");
      var style = TableCellStyle(textColor: p);
      expectShown(
          "rule",
          p,
          (f) => TableRule(style: style, off: true).mapColours(f),
          (f) => TableRule(style: style).mapColours(f));
      expectShown(
          "scale's ends",
          p,
          (f) =>
              SheetRule(const CellRange(0, 0, 0, 0), SheetRuleKind.bars, low: p)
                  .mapColours(f),
          (f) => SheetRule(const CellRange(0, 0, 0, 0), SheetRuleKind.scale,
                  low: p)
              .mapColours(f));
      expectShown(
          "spotlight",
          p,
          (f) => DataSheet(id: "s", spotlightColour: p).mapColours(f),
          (f) => DataSheet(id: "s", spotlight: "a", spotlightColour: p)
              .mapColours(f));
      var table = TableElement(const ElementBase(id: "t"), zebraFill: p);
      expectShown(
          "stripes",
          p,
          (f) => table.copyWith(zebra: false).mapOwnColours(f),
          (f) => table.copyWith(zebra: true).mapOwnColours(f));
    });

    test("drawings and shapes", () {
      var shape = VectorShape(paths: const [], fill: p);
      expectShown(
          "hidden shape",
          p,
          (f) => shape.copyWith(hidden: true).mapColours(f),
          (f) => shape.mapColours(f));
      expectShown(
          "line with no width",
          p,
          (f) => VectorShape(paths: const [], stroke: p, strokeWidth: 0)
              .mapColours(f),
          (f) => VectorShape(paths: const [], stroke: p).mapColours(f));
      var s = ShapeElement(const ElementBase(id: "s"), strokeColor: p);
      expectShown("outline", p, (f) => s.mapOwnColours(f),
          (f) => s.copyWith(strokeWidth: 2).mapOwnColours(f));
      var item = TextItem(id: "i", spec: TextSpec(color: p));
      expectShown(
          "hidden piece",
          p,
          (f) => item.copyWith(hidden: true).mapColours(f),
          (f) => item.mapColours(f));
      var columns = TextColumns(ruleColor: p);
      expectShown(
          "column rule",
          p,
          (f) => columns.mapColours(f),
          (f) =>
              columns.copyWith(ruleStyle: ColumnRuleStyle.solid).mapColours(f));
    });

    test("scenery, tiles and characters", () {
      var hills = ParallaxLayer(color: p);
      expectShown(
          "hidden scenery",
          p,
          (f) => hills.copyWith(visible: false).mapColours(f),
          (f) => hills.mapColours(f));
      expectShown(
          "a picture layer's colour",
          p,
          (f) =>
              ParallaxLayer(kind: SceneryKind.picture, color: p).mapColours(f),
          (f) => hills.mapColours(f));
      var tiles = TileLayer(tint: p);
      expectShown(
          "hidden tiles",
          p,
          (f) => tiles.copyWith(visible: false).mapColours(f),
          (f) => tiles.mapColours(f));
      var made =
          Garment(source: WearSource.made, kind: "tee", colour: 0x5a6b7c);
      expectShown(
          "the body's own clothes",
          p,
          (f) => made.copyWith(source: WearSource.own).mapColours(f),
          (f) => made.mapColours(f));
      expectShown(
          "ink with no lines",
          p,
          (f) => CharacterLook(lineStyle: "none", lineColour: 0x5a6b7c)
              .mapColours(f),
          (f) => CharacterLook(lineColour: 0x5a6b7c).mapColours(f));
      var decal = CharacterDecal(id: "d", source: "x", ink: 0x5a6b7c);
      expectShown("printed decal", p, (f) => decal.mapColours(f),
          (f) => decal.copyWith(mode: "ink").mapColours(f));
      expectShown(
          "paint rubbed out",
          p,
          (f) => PaintStroke(
                  on: "skin",
                  radius: 1,
                  tool: PaintTool.rubOut,
                  colour: 0x5a6b7c)
              .mapColours(f),
          (f) => PaintStroke(on: "skin", radius: 1, colour: 0x5a6b7c)
              .mapColours(f));
    });

    test("a page shape's copy of the design is not what shows", () {
      var plain = ShapeElement(const ElementBase(id: "s"), fill: p);
      Map<String, dynamic> snapshot() => plain.toJson()
        ..remove("layouts")
        ..remove("shared");
      var told = <bool>[];
      plain.withBase(shared: snapshot(), layouts: {
        "1:1": ElementLayout(x: 0, y: 0, width: 1, height: 1, own: snapshot()),
      }).mapColours((c, {required bool shown}) {
        if (c == p) told.add(shown);
        return c;
      });
      // The element's own fill shows; the shared copy's and the page
      // shape's are for other shapes of page.
      expect(told..sort((a, b) => a == b ? 0 : (a ? -1 : 1)),
          [true, false, false]);
    });

    test("scenes and the document", () {
      expectShown(
          "transition",
          p,
          (f) => SceneTransition(color: p).mapColours(f),
          (f) => SceneTransition(
                  kind: SceneTransitionKind.through, frames: 10, color: p)
              .mapColours(f));
      var metronome = MetronomeElement(const ElementBase(id: "m"), body: p);
      var scene = CanvasScene(id: "m", elements: [metronome]);
      expectShown(
          "master off",
          p,
          (f) => CanvasDocument(master: scene).mapColours(f),
          (f) => CanvasDocument(master: scene, masterOn: true).mapColours(f));
      expectShown(
          "cast member",
          p,
          (f) => CanvasDocument(cast: [metronome]).mapColours(f),
          (f) => CanvasDocument(elements: [metronome]).mapColours(f));
      expectShown(
          "text style",
          p,
          (f) => CanvasDocument(
                  textStyles: [NamedTextStyle("Body", TextSpec(color: p))])
              .mapColours(f),
          (f) => CanvasDocument(elements: [
                TextElement(const ElementBase(id: "t"),
                    textSpec: TextSpec(color: p))
              ]).mapColours(f));
    });
  });

  group("nothing but colours is touched", () {
    test("an element mapped through a map that changes nothing saves alike",
        () {
      for (var (name, e) in _allElements()) {
        expect(_json(e.mapColours(_same).toJson()), _json(e.toJson()),
            reason: name);
      }
    });

    test("every element mapped there and back saves as it did", () {
      for (var (name, e) in _allElements()) {
        var there = e.mapColours(_flip);
        // Any with a colour came back a new object, so its copy was made.
        if (elementColours(e).isNotEmpty) {
          expect(identical(there, e), isFalse, reason: name);
        }
        expect(_json(there.mapColours(_flip).toJson()), _json(e.toJson()),
            reason: name);
      }
    });

    test("every document mapped there and back saves as it did", () {
      for (var (name, d) in _allDocuments()) {
        expect(_json(d.mapColours(_flip).mapColours(_flip).toJson()),
            _json(d.toJson()),
            reason: name);
      }
    });
  });

  group("the awkward forms", () {
    const from = Color(0xFF112233), to = Color(0xFFAABBCC);
    Color swap(Color c, {required bool shown}) =>
        c.toARGB32() & 0xFFFFFF == 0x112233 ? to : c;

    test("a Design key, phase key, resting value and copy's own value", () {
      var number = from.toARGB32().toDouble();
      var design = MotionDevice(MotionDeviceKind.design, id: "m0", keys: {
        "fill": [DeviceKey(0, number)],
        "x": [DeviceKey(0, 12)],
      }, phaseKeys: {
        MotionPhase.loop: {
          "accent": [DeviceKey(0.5, number)],
        },
      }, values: {
        "ink": number,
        "fontSize": 48
      });
      var motion = ElementMotion(
          devices: [design],
          instances: InstanceSet(items: [
            ElementInstance("a",
                own: {"dev:m0:fill": number, "dev:m0:x": 30, "size": 2}),
          ]));
      var next = motion.mapColours(swap);
      var d = next.devices.single;
      var want = to.toARGB32().toDouble();
      expect(d.keys["fill"]!.single.v, want);
      expect(d.keys["x"]!.single.v, 12);
      expect(d.phaseKeys[MotionPhase.loop]!["accent"]!.single.v, want);
      expect(d.values["ink"], want);
      expect(d.values["fontSize"], 48);
      var own = next.instances!.items.single.own;
      expect(own["dev:m0:fill"], want);
      expect(own["dev:m0:x"], 30);
      expect(own["size"], 2);
    });

    test("a 0xRRGGBB colour is handed over opaque, its alpha dropped back", () {
      var seen = <Color>[];
      var g = Garment(source: WearSource.made, kind: "tee", colour: 0x112233);
      var next = g.mapColours((c, {required bool shown}) {
        seen.add(c);
        return c == from ? const Color(0x80AABBCC) : c;
      });
      expect(seen, contains(from));
      expect(next.colour, 0xAABBCC);
    });

    test("a hex colour choice is read and written as six digits", () {
      var shape = CharacterShape(choices: {
        "colour.eyes": "112233",
        "colour.hair": "not a colour",
        "hair.style": "112233",
      });
      var next = shape.mapColours(swap);
      expect(next.choices["colour.eyes"], "aabbcc");
      expect(next.choices["colour.hair"], "not a colour");
      expect(next.choices["hair.style"], "112233");
      expect(identical(shape.mapColours(_same), shape), isTrue);
    });

    test("the one scene's elements stay its own while the master is edited",
        () {
      var mine = MetronomeElement(const ElementBase(id: "a"), body: from);
      var theirs = MetronomeElement(const ElementBase(id: "b"), body: from);
      var doc = CanvasDocument(
          elements: [mine],
          master: CanvasScene(id: "m", elements: [theirs]),
          masterOn: true,
          onMaster: true);
      var next = doc.mapColours(swap);
      expect(next.onMaster, isTrue);
      expect(next.scene.elements.map((e) => e.id), ["a"]);
      expect((next.scene.elements.single as MetronomeElement).body, to);
      expect(next.master!.elements.map((e) => e.id), ["b"]);
      expect((next.master!.elements.single as MetronomeElement).body, to);
    });

    test("a page shape's copy of the design is mapped in its own form", () {
      var plain = ShapeElement(const ElementBase(id: "s"), fill: from);
      Map<String, dynamic> snapshot() => plain.toJson()
        ..remove("layouts")
        ..remove("shared");
      var shared = snapshot(), own = snapshot();
      var shape = plain.withBase(shared: shared, layouts: {
        "1:1": ElementLayout(x: 0, y: 0, width: 1, height: 1, own: own),
      });
      expect(identical(shape.mapColours(_same), shape), isTrue);
      var next = shape.mapColours(swap);
      expect((next as ShapeElement).fill, to);
      expect(next.base.shared!["fill"], to.toARGB32());
      expect(next.base.layouts["1:1"]!.own!["fill"], to.toARGB32());
      expect(next.base.shared!["id"], "s");
      // Everything else in the copies is as it was.
      expect(_json({...next.base.shared!}..remove("fill")),
          _json({...shared}..remove("fill")));
    });
  });
}
