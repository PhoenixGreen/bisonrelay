import 'dart:ui';

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/colour_cube.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_decal.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_design.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_look.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_outfit.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_sculpt.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_shape.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_task_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_adjustment.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_effects.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_strokes.dart';
import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/metronome_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/parallax_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/play_task_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sprite_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/elements/tile_map_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/instances.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_layers.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_light.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_rings.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/text_document.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';

// colour_rich.dart is one of every element kind, and a document holding
// them, with every colour it can hold set to a colour of its own: every
// fade, highlight, outline, shadow, glow, layer, stroke, Design key and
// page-shape copy. The readers below take each of those colours back out
// through the model's fields (never the saved form), so a test can map them
// all and see each one reached; [keptColours] are those that must never be
// mapped.

/// colourSentinel is a colour none of the fixture's is.
const Color colourSentinel = Color(0xFF123456);

/// _Colours hands out a new colour each time, none of them the sentinel.
class _Colours {
  int _n = 0;

  Color next() {
    _n++;
    var c = Color(0xFF000000 | ((0x101010 + _n * 0x0A1B2D) & 0xFFFFFF));
    return c == colourSentinel ? next() : c;
  }

  int rgb() => next().toARGB32() & 0xFFFFFF;
  String hex() => rgb().toRadixString(16).padLeft(6, "0");
  double number() => next().toARGB32().toDouble();

  GradientSpec fade() =>
      GradientSpec(to: next(), more: [GradientStop(next(), 0.5)]);
  PaintSpec paint() => PaintSpec(next(), gradient: fade());

  ProceduralSpec plainPattern() =>
      ProceduralSpec(background: next(), foreground: next(), accent: next());

  ProceduralSpec pattern() => ProceduralSpec(
        style: ProceduralStyle.rings,
        background: next(),
        foreground: next(),
        accent: next(),
        gradient: fade(),
        foregroundFade: fade(),
        accentFade: fade(),
        rings: RingSpec(
            icons: [RingIcon(asset: "icon", tinted: true, tint: next())]),
        light: LightSpec(on: true, color: next()),
        layers: [BackgroundLayer(spec: plainPattern())],
      );

  TextFill fill() => TextFill(
        kind: TextFillKind.pattern,
        pattern: plainPattern(),
        overlay: next(),
        blend: OverlayBlend.wash,
        overlayFade: fade(),
      );

  TextSpec type() => TextSpec(
        color: next(),
        fade: fade(),
        fill: fill(),
        outlineWidth: 2,
        outlineColor: next(),
        shadowBlur: 3,
        shadowColor: next(),
        glowBlur: 3,
        glowColor: next(),
      );

  BoxSpec box() => BoxSpec(
        fill: next(),
        painted: fill(),
        borderWidth: 2,
        borderColor: next(),
        fillFade: fade(),
        borderFade: fade(),
      );

  ElementLoop loop() =>
      ElementLoop(preset: LoopPreset.shimmer, colour: paint());

  ElementAnimation arrival() => ElementAnimation(loop: loop());

  PartUnderline underline() =>
      PartUnderline(color: next(), fade: fade(), width: 2);

  PartHighlight highlight() => PartHighlight(color: next(), fade: fade());
}

/// _keptKey and the rest are the colours that are never mapped: they must
/// match footage or pictures, or are the editor's.
const Color _keptKey = Color(0xFF00B141);
const Color _keptRemoval = Color(0xFFFEFEFE);
const Color _keptHandle = Color(0xFF2F80EE);
const Color _keptEraser = Color(0xFFE5484E);
const int _keptRow = 0xFF778899;

/// colourRichElements is one of every kind with every colour set, as (name,
/// element) pairs. The shape also carries a motion chain (a Design device
/// with keyed, phase-keyed and resting colours, a glow, an instance's own
/// colour) and both page-shape copies of its design.
List<(String, CanvasElement)> colourRichElements() {
  var c = _Colours();
  var doc = const CanvasDocument(frames: 96, frameRate: 24);
  CanvasElement fresh(ElementKind k) => newElement(k, doc);

  var text = (fresh(ElementKind.text) as TextElement).copyWith(
    textSpec: c.type(),
    box: c.box(),
    columns: TextColumns(
        count: 2, ruleStyle: ColumnRuleStyle.solid, ruleColor: c.next()),
    animation:
        TextAnimation(draw: TextDrawSpec(color: c.next()), loop: c.loop()),
    items: [
      TextItem(
          id: "i1",
          text: "Piece",
          spec: c.type(),
          box: c.box(),
          icon: TextIcon(
              assetId: "icon",
              color: c.next(),
              outlineWidth: 2,
              outlineColor: c.next(),
              box: c.box(),
              underline: c.underline())),
    ],
    parts: [
      TextPart(
          from: 1,
          to: 2,
          color: c.next(),
          outlineWidth: 1,
          outlineColor: c.next(),
          highlight: c.highlight(),
          underline: c.underline(),
          animation: TextPartAnimation(draw: TextDrawSpec(color: c.next()))),
    ],
    highlight: c.highlight(),
    underline: c.underline(),
    document: TextDocumentRef(
        name: "notes",
        markdown: true,
        allow: MarkdownAllow(
            looks: {MarkdownKind.bold: MarkdownLook(color: c.next())})),
    documentParts: [TextPart(from: 1, color: c.next())],
  );

  var look = ImageElement(const ElementBase(id: "look"),
      assetId: "layer-picture", tint: c.next());
  var image = (fresh(ElementKind.image) as ImageElement).copyWith(
    assetId: "picture",
    box: c.box(),
    removal: const BackgroundRemoval(
        mode: RemovalMode.chromaKey, keyColor: _keptRemoval),
    tint: c.next(),
    outline: ImageOutline(color: c.next(), width: 3),
    overlay: c.next(),
    blend: OverlayBlend.multiply,
    animation: c.arrival(),
    layers: [
      ImageLayer(id: "l1", kind: LayerKind.fill, fill: c.paint()),
      ImageLayer(
          id: "l2",
          kind: LayerKind.adjustment,
          adjust:
              ImageAdjustment(kind: AdjustKind.photoFilter, colour: c.next())),
      ImageLayer(
          id: "l3",
          kind: LayerKind.adjustment,
          adjust:
              ImageAdjustment(kind: AdjustKind.gradientMap, fade: c.paint())),
      ImageLayer(
          id: "l4",
          kind: LayerKind.texture,
          texture: TextureSpec(
              kind: TextureKind.lightLeak, colour: c.next(), second: c.next())),
      ImageLayer(
          id: "l5",
          kind: LayerKind.picture,
          look: look,
          loop: c.loop(),
          effects: [
            LayerEffect(kind: EffectKind.dropShadow, colour: c.next())
          ]),
      ImageLayer(id: "l6", kind: LayerKind.paint, strokes: [
        StrokeMark(
            kind: StrokeKind.paint,
            points: const [Offset(0.1, 0.1)],
            colour: c.next()),
      ]),
      ImageLayer(
          id: "l7",
          kind: LayerKind.adjustment,
          adjust: ImageAdjustment(
              kind: AdjustKind.colourTable, cube: ColourCube.identity(2))),
    ],
    retouch: [
      StrokeMark(
          kind: StrokeKind.paint,
          points: const [Offset(0.2, 0.2)],
          colour: c.next()),
    ],
  );

  ShapeElement shapeLike(ShapeElement s) => s.copyWith(
        fill: c.next(),
        strokeWidth: 2,
        strokeColor: c.next(),
        fillFade: c.fade(),
        strokeFade: c.fade(),
        painted: c.fill(),
        text: "Hi",
        textSpec: c.type(),
        animation: c.arrival(),
      );
  var plainShape = fresh(ElementKind.shape) as ShapeElement;
  Map<String, dynamic> snapshot() => shapeLike(plainShape).toJson()
    ..remove("layouts")
    ..remove("shared");
  var shared = snapshot();
  var own = snapshot();
  var shape = shapeLike(plainShape).withBase(
    rowColour: _keptRow,
    shared: shared,
    layouts: {
      "9:16": ElementLayout(x: 0, y: 0, width: 50, height: 90, own: own),
    },
    motion: ElementMotion(
      devices: [
        MotionDevice(MotionDeviceKind.design, id: "m0", keys: {
          "fill": [DeviceKey(0, c.number()), DeviceKey(1, c.number())],
        }, phaseKeys: {
          MotionPhase.arrive: {
            "strokeColour": [DeviceKey(0.5, c.number())],
          },
        }, values: {
          "borderColour": c.number(),
          "x": 12
        }),
        MotionDevice(MotionDeviceKind.glow,
            id: "m1", colour: c.next().toARGB32()),
      ],
      instances: InstanceSet(items: [
        ElementInstance("a", own: {"dev:m0:fill": c.number(), "size": 2}),
      ]),
    ),
  );

  var line = (fresh(ElementKind.line) as LineElement)
      .copyWith(color: c.next(), fade: c.fade(), animation: c.arrival());

  var chart = (fresh(ElementKind.chart) as ChartElement).copyWith(
    data: ChartData(categories: const [
      "a",
      "b"
    ], series: [
      ChartSeries(
          name: "s",
          color: c.next(),
          values: const [1, 2],
          gradient: c.fade(),
          pointColor: c.next(),
          backdrop: ChartBackdrop(
              on: true, fill: c.next(), border: c.next(), borderWidth: 1)),
    ]),
    animation: ChartAnimation(loop: c.loop()),
    descriptionSpec: c.type(),
    showGrid: true,
    showAxes: true,
    showXLabels: true,
    showYLabels: true,
    xLabelColor: c.next(),
    yLabelColor: c.next(),
    gridColor: c.next(),
    axisColor: c.next(),
    riseColor: c.next(),
    fallColor: c.next(),
    sliceColors: [c.next(), c.next()],
    axisSpec: c.type(),
    box: c.box(),
    titleSpec: c.type(),
    labelSpec: c.type(),
    valueSpec: c.type(),
    showPoints: true,
    pointColor: c.next(),
    highlights: [ChartHighlight(colour: c.next())],
    notes: [ChartNote(colour: c.next())],
    steps: [
      ChartStep(
          highlights: [ChartHighlight(colour: c.next())],
          notes: [ChartNote(colour: c.next())]),
    ],
    panel: c.next(),
  );

  var table = (fresh(ElementKind.table) as TableElement).copyWith(
    headerRow: true,
    cellSpec: c.type(),
    headerSpec: c.type(),
    headerFill: c.next(),
    cellFill: c.next(),
    headerFade: c.fade(),
    cellFade: c.fade(),
    zebra: true,
    zebraFill: c.next(),
    grid: TableGrid.all,
    gridWidth: 1,
    gridColor: c.next(),
    rules: [
      TableRule(
          style: TableCellStyle(
              background: c.next(),
              textColor: c.next(),
              borderColor: c.next(),
              borderWidth: 1)),
    ],
    animation: c.arrival(),
  );

  var button = (fresh(ElementKind.button) as ButtonElement).copyWith(
      textSpec: c.type(),
      box: c.box(),
      hoverFill: c.next(),
      hoverTextColor: c.next(),
      animation: c.arrival());

  StageElement stageOf(StageElement s) => s.copyWith(
      floor: c.next(), wall: true, wallColor: c.next(), sky: c.next());
  ParallaxElement parallaxOf(ParallaxElement p) => p.copyWith(layers: [
        ParallaxLayer(color: c.next(), color2: c.next()),
        ParallaxLayer(
            kind: SceneryKind.pattern,
            color: c.next(),
            color2: c.next(),
            spec: c.plainPattern()),
      ]);

  var background = (fresh(ElementKind.background) as BackgroundElement)
      .copyWith(
          spec: c.pattern(),
          stage: stageOf(const StageElement(ElementBase(id: ""))),
          parallax: parallaxOf(const ParallaxElement(ElementBase(id: ""))));

  var path = (fresh(ElementKind.path) as PathElement)
      .copyWith(color: c.next(), fade: c.fade(), animation: c.arrival());

  var team = (fresh(ElementKind.player) as TeamElement).copyWith(
    keeperColor: c.next(),
    playerColor: c.next(),
    outlineColor: c.next(),
    ringWidth: 2,
    labelSpec: c.type(),
    secondaryColor: c.next(),
    ballLook: BallLook(color: c.next(), second: c.next()),
  );

  var counter = (fresh(ElementKind.counter) as CounterElement).copyWith(
    numberSpec: c.type(),
    affixSpec: c.type(),
    box: c.box(),
    buttons: const [CounterButton.startStop],
    buttonSpec: c.type(),
    buttonBox: c.box(),
    animation: c.arrival(),
  );

  var audio = (fresh(ElementKind.audio) as AudioElement).copyWith(
      iconColor: c.next(),
      accent: c.next(),
      leftAccent: c.next(),
      box: c.box(),
      animation: c.arrival());

  var video = (fresh(ElementKind.video) as VideoElement).copyWith(
    key: const ChromaKey(on: true, color: _keptKey),
    look: ImageElement(const ElementBase(id: ""),
        tint: c.next(), outline: ImageOutline(color: c.next(), width: 1)),
    accent: c.next(),
    animation: c.arrival(),
  );

  var vector = (fresh(ElementKind.vector) as VectorElement).copyWith(
    shapes: [
      VectorShape(
        paths: letterPaths,
        text: VectorText(text: "A", signature: pathSignature(letterPaths)),
        fill: c.next(),
        stroke: c.next(),
        fillFade: c.fade(),
        strokeFade: c.fade(),
        tints: [
          VectorTint(points: const [Offset.zero], paint: c.paint())
        ],
        erasures: [
          const VectorTint(
              points: [Offset.zero],
              paint: PaintSpec(_keptEraser),
              erase: true),
        ],
        animation: c.arrival(),
      ),
    ],
    handleColor: _keptHandle,
    tint: c.next(),
    animation: c.arrival(),
  );

  var character =
      (fresh(ElementKind.character3d) as Character3dElement).copyWith(
    design: CharacterDesign(
      id: "character",
      name: "Character",
      body: "AvatarSample_A",
      shape: CharacterShape(choices: {
        "colour.eyes": c.hex(),
        "colour.hair": c.hex(),
        "colour.skin": c.hex(),
        "hair.style": "bob",
      }),
      outfit: CharacterOutfit.asDesigned.wear(
          WearSlot.top,
          Garment(
              source: WearSource.made,
              kind: "tee",
              colour: c.rgb(),
              patternColour: c.rgb(),
              sole: c.rgb(),
              pattern: "stripes")),
      look: CharacterLook(lineColour: c.rgb(), paperColour: c.rgb()),
      decals: [
        CharacterDecal(
            id: "d1", source: "picture:x", mode: "ink", ink: c.rgb()),
      ],
      paint: [PaintStroke(on: "skin", radius: 0.01, colour: c.rgb())],
      updated: DateTime.utc(2026),
    ),
    animation: c.arrival(),
  );

  // A stage or scenery is made on a background, so made here as itself.
  var stage = stageOf(const StageElement(ElementBase(id: "stage")));

  var sprite =
      (fresh(ElementKind.sprite) as SpriteElement).copyWith(tint: c.next());

  var tiles = (fresh(ElementKind.tileMap) as TileMapElement).copyWith(
    sources: [
      TileSource(
          sheet: "sheet",
          sheetW: 32,
          sheetH: 32,
          tileW: 16,
          tileH: 16,
          terrains: [
            TerrainSet("ground", terrains: [Terrain("grass", c.next())]),
          ]),
    ],
    layers: [
      TileLayer(
          name: "Ground",
          cells: {0: flippedTile.word, 1: TileRef.of(16, 3).word},
          tint: c.next()),
    ],
    light: c.next(),
    lightTo: c.next(),
  );

  var parallax = parallaxOf(const ParallaxElement(ElementBase(id: "scenery")));

  var sheet = (fresh(ElementKind.sheet) as SheetElement)
      .copyWith(paper: c.next(), ink: c.next(), box: c.box());

  var metronome = (fresh(ElementKind.metronome) as MetronomeElement)
      .copyWith(body: c.next(), accent: c.next());

  var code = (fresh(ElementKind.code) as CodeElement).copyWith(
    files: [CodeFile(id: "f1", name: "main.dart", colour: c.next())],
    start: [CodeFile(id: "f1", name: "main.dart", colour: c.next())],
  );

  var codeTask = (fresh(ElementKind.codeTask) as CodeTaskElement)
      .copyWith(accent: c.next());

  var layout = (fresh(ElementKind.layout) as LayoutElement).copyWith(
    gutterColor: c.next(),
    cellStyle: c.box(),
    cells: [LayoutCell(id: "c1", style: c.box())],
  );

  var playTask = (fresh(ElementKind.playTask) as PlayTaskElement).copyWith(
      box: c.box(), titleSpec: c.type(), spec: c.type(), accent: c.next());

  return [
    ("Text", text),
    ("Image", image),
    ("Shape", shape),
    ("Line", line),
    ("Chart", chart),
    ("Table", table),
    ("Button", button),
    ("Background", background),
    ("Path", path),
    ("Team", team),
    ("Counter", counter),
    ("Audio", audio),
    ("Video", video),
    ("Vector", vector),
    ("3D character", character),
    ("3D stage", stage),
    ("Sprite", sprite),
    ("Tile map", tiles),
    ("Parallax", parallax),
    ("Sheet music", sheet),
    ("Camera", fresh(ElementKind.camera)),
    ("3D object", fresh(ElementKind.object3d)),
    ("Synth module", fresh(ElementKind.synth)),
    ("Synth task", fresh(ElementKind.synthTask)),
    ("Metronome", metronome),
    ("Code", code),
    ("Run panel", fresh(ElementKind.codeRun)),
    ("Code task", codeTask),
    ("Layout", layout),
    ("Play task", playTask),
  ];
}

/// letterPaths are a drawn letter's runs. Its signature (pathSignature) is
/// a hash, most often a number in a colour's range, and never a colour.
const List<VectorPath> letterPaths = [
  VectorPath([
    VectorNode(0, 10),
    VectorNode(5, 0),
    VectorNode(10, 10),
  ]),
];

/// flippedTile is a tile flipped across from set 0: its word's low 24 bits
/// are black's, so a walk that took it for a colour would rewrite it.
final TileRef flippedTile = TileRef.of(0, 0, flipX: true);

/// colourRichDocument holds [colourRichElements] in a scene with its own
/// backdrop and a transition through a colour, a master, a cast member, a
/// text style and a sheet with colour rules, each set with colours of its
/// own.
CanvasDocument colourRichDocument() {
  var c = _Colours();
  // Far along, so these colours are not the elements'.
  for (var i = 0; i < 5000; i++) {
    c.next();
  }
  var elements = [for (var (_, e) in colourRichElements()) e];
  var line = elements.whereType<LineElement>().first;
  var metronome = elements.whereType<MetronomeElement>().first;
  return CanvasDocument(
    background: CanvasBackground(
      spec: c.pattern(),
      picture: ImageElement(const ElementBase(id: "backdrop"),
          assetId: "backdrop-picture", tint: c.next()),
      drawing: VectorElement(const ElementBase(id: "drawing"),
          tint: c.next(), handleColor: _keptHandle),
    ),
    scenes: [
      CanvasScene(
        id: "s1",
        elements: elements,
        background: CanvasBackground(spec: c.plainPattern()),
        transition: SceneTransition(
            kind: SceneTransitionKind.through, frames: 12, color: c.next()),
      ),
    ],
    master: CanvasScene(id: "master", elements: [
      line.copyWith(color: c.next(), fade: c.fade()).withId("master-line"),
    ]),
    masterOn: true,
    cast: [metronome.copyWith(body: c.next(), accent: c.next())],
    textStyles: [NamedTextStyle("Body", c.type())],
    sheets: [
      DataSheet(
        id: "sheet",
        rules: [
          SheetRule(const CellRange(0, 0, 1, 1), SheetRuleKind.scale,
              colour: c.next(), low: c.next(), high: c.next()),
        ],
        spotlight: "a",
        spotlightColour: c.next(),
      ),
    ],
  );
}

// The readers. Each lists every colour the fixture set, read through the
// model's own fields.

Color _opaque(int rgb) => Color(0xFF000000 | rgb);
Color _number(double v) => Color(v.toInt() & 0xFFFFFFFF);

List<Color> _fade(GradientSpec? g) =>
    g == null ? const [] : [g.to, for (var s in g.more) s.color];
List<Color> _paint(PaintSpec p) => [p.color, ..._fade(p.gradient)];
List<Color> _plainPattern(ProceduralSpec s) =>
    [s.background, s.foreground, s.accent];
List<Color> _pattern(ProceduralSpec s) => [
      ..._plainPattern(s),
      ..._fade(s.gradient),
      ..._fade(s.foregroundFade),
      ..._fade(s.accentFade),
      for (var i in s.rings.icons) i.tint,
      s.light.color,
      for (var l in s.layers) ..._plainPattern(l.spec),
    ];
List<Color> _fill(TextFill f) =>
    [..._plainPattern(f.pattern), f.overlay, ..._fade(f.overlayFade)];
List<Color> _type(TextSpec s) => [
      s.color,
      ..._fade(s.fade),
      ..._fill(s.fill),
      s.outlineColor,
      s.shadowColor,
      s.glowColor,
    ];
List<Color> _box(BoxSpec b) => [
      b.fill,
      ..._fill(b.painted),
      b.borderColor,
      ..._fade(b.fillFade),
      ..._fade(b.borderFade),
    ];
List<Color> _loop(ElementLoop l) => _paint(l.colour);
List<Color> _underline(PartUnderline? u) =>
    u == null ? const [] : [if (u.color case var x?) x, ..._fade(u.fade)];
List<Color> _highlight(PartHighlight? h) =>
    h == null ? const [] : [h.color, ..._fade(h.fade)];
List<Color> _part(TextPart p) => [
      if (p.color case var x?) x,
      if (p.outlineColor case var x?) x,
      ..._highlight(p.highlight),
      ..._underline(p.underline),
      if (p.animation.draw.color case var x?) x,
    ];

List<Color> _base(ElementBase b) => [
      for (var d in b.motion.devices) ...[
        if (d.colour case var c?) Color(c),
        for (var ks in d.keys.values)
          for (var k in ks) _number(k.v),
        for (var phase in d.phaseKeys.values)
          for (var ks in phase.values)
            for (var k in ks) _number(k.v),
        for (var MapEntry(:key, :value) in d.values.entries)
          if (d.colourSetting(key)) _number(value),
      ],
      for (var copy in b.motion.instances?.items ?? const <ElementInstance>[])
        for (var MapEntry(:key, :value) in copy.own.entries)
          if (key.startsWith("dev:")) _number(value),
      if (b.shared case var s?) ...elementColours(elementFromJson(s)),
      for (var l in b.layouts.values)
        if (l.own case var o?) ...elementColours(elementFromJson(o)),
    ];

/// elementColours is every colour [colourRichElements] set on [e], its
/// base's included, read through the model.
List<Color> elementColours(CanvasElement e) => [
      ..._base(e.base),
      ..._ownColours(e),
    ];

List<Color> _ownColours(CanvasElement e) => switch (e) {
      TextElement t => [
          ..._type(t.textSpec),
          ..._box(t.box),
          t.columns.ruleColor,
          if (t.animation.draw.color case var x?) x,
          ..._loop(t.animation.loop),
          for (var i in t.items) ...[
            ..._type(i.spec),
            ..._box(i.box),
            if (i.icon case var icon?) ...[
              if (icon.color case var x?) x,
              icon.outlineColor,
              ..._box(icon.box),
              ..._underline(icon.underline),
            ],
          ],
          for (var p in t.parts) ..._part(p),
          ..._highlight(t.highlight),
          ..._underline(t.underline),
          for (var l in t.document.allow.looks.values)
            if (l.color case var x?) x,
          for (var p in t.documentParts) ..._part(p),
        ],
      ImageElement i => _image(i),
      ShapeElement s => [
          s.fill,
          s.strokeColor,
          ..._fade(s.fillFade),
          ..._fade(s.strokeFade),
          ..._fill(s.painted),
          ..._type(s.textSpec),
          ..._loop(s.animation.loop),
        ],
      LineElement l => [l.color, ..._fade(l.fade), ..._loop(l.animation.loop)],
      ChartElement c => [
          for (var s in c.data.series) ...[
            s.color,
            ..._fade(s.gradient),
            if (s.pointColor case var x?) x,
            if (s.backdrop case var b?) ...[b.fill, b.border],
          ],
          ..._loop(c.animation.loop),
          if (c.descriptionSpec case var d?) ..._type(d),
          if (c.xLabelColor case var x?) x,
          if (c.yLabelColor case var x?) x,
          c.gridColor,
          c.axisColor,
          c.riseColor,
          c.fallColor,
          ...c.sliceColors,
          if (c.axisSpec case var a?) ..._type(a),
          ..._box(c.box),
          ..._type(c.titleSpec),
          ..._type(c.labelSpec),
          ..._type(c.valueSpec),
          c.pointColor,
          for (var h in c.highlights) h.colour,
          for (var n in c.notes) n.colour,
          for (var s in c.steps) ...[
            for (var h in s.highlights) h.colour,
            for (var n in s.notes) n.colour,
          ],
          c.panel,
        ],
      TableElement t => [
          ..._type(t.cellSpec),
          ..._type(t.headerSpec),
          t.headerFill,
          t.cellFill,
          ..._fade(t.headerFade),
          ..._fade(t.cellFade),
          t.zebraFill,
          t.gridColor,
          for (var r in t.rules) ...[
            r.style.background,
            r.style.textColor,
            r.style.borderColor,
          ],
          ..._loop(t.animation.loop),
        ],
      ButtonElement b => [
          ..._type(b.textSpec),
          ..._box(b.box),
          b.hoverFill,
          b.hoverTextColor,
          ..._loop(b.animation.loop),
        ],
      BackgroundElement b => [
          ..._pattern(b.spec),
          if (b.stage case var s?) ..._ownColours(s),
          if (b.parallax case var p?) ..._ownColours(p),
        ],
      PathElement p => [p.color, ..._fade(p.fade), ..._loop(p.animation.loop)],
      TeamElement t => [
          t.keeperColor,
          t.playerColor,
          t.outlineColor,
          ..._type(t.labelSpec),
          t.secondaryColor,
          t.ballLook.color,
          t.ballLook.second,
        ],
      CounterElement c => [
          ..._type(c.numberSpec),
          ..._type(c.affixSpec),
          ..._box(c.box),
          ..._type(c.buttonSpec),
          ..._box(c.buttonBox),
          ..._loop(c.animation.loop),
        ],
      AudioElement a => [
          a.iconColor,
          a.accent,
          a.leftAccent,
          ..._box(a.box),
          ..._loop(a.animation.loop),
        ],
      VideoElement v => [
          v.look.tint,
          v.look.outline.color,
          v.accent,
          ..._loop(v.animation.loop),
        ],
      VectorElement v => [
          for (var s in v.shapes ?? const <VectorShape>[]) ...[
            if (s.fill case var x?) x,
            if (s.stroke case var x?) x,
            ..._fade(s.fillFade),
            ..._fade(s.strokeFade),
            for (var t in s.tints) ..._paint(t.paint),
            if (s.animation case var a?) ..._loop(a.loop),
          ],
          if (v.tint case var x?) x,
          ..._loop(v.animation.loop),
        ],
      Character3dElement c => [
          for (var MapEntry(:key, :value) in c.design.shape.choices.entries)
            if (key.startsWith("colour.")) _opaque(int.parse(value, radix: 16)),
          for (var s in WearSlot.values)
            if (c.design.outfit.changed(s)) ...[
              _opaque(c.design.outfit[s].colour),
              _opaque(c.design.outfit[s].patternColour),
              _opaque(c.design.outfit[s].sole),
            ],
          _opaque(c.design.look.lineColour),
          _opaque(c.design.look.paperColour),
          for (var d in c.design.decals) _opaque(d.ink),
          for (var p in c.design.paint) _opaque(p.colour),
          ..._loop(c.animation.loop),
        ],
      StageElement s => [s.floor, s.wallColor, s.sky],
      SpriteElement s => [if (s.tint case var x?) x],
      TileMapElement t => [
          for (var l in t.layers)
            if (l.tint case var x?) x,
          if (t.light case var x?) x,
          if (t.lightTo case var x?) x,
        ],
      ParallaxElement p => [
          for (var l in p.layers) ...[
            l.color,
            l.color2,
            if (l.kind == SceneryKind.pattern) ..._plainPattern(l.spec),
          ],
        ],
      SheetElement s => [s.paper, s.ink, ..._box(s.box)],
      MetronomeElement m => [m.body, m.accent],
      CodeElement c => [
          for (var f in c.files) f.colour,
          for (var f in c.start ?? const <CodeFile>[]) f.colour,
        ],
      CodeTaskElement c => [c.accent],
      LayoutElement l => [
          l.gutterColor,
          ..._box(l.cellStyle),
          for (var cell in l.cells)
            if (cell.style case var s?) ..._box(s),
        ],
      PlayTaskElement p => [
          ..._box(p.box),
          ..._type(p.titleSpec),
          ..._type(p.spec),
          p.accent,
        ],
      _ => const [],
    };

List<Color> _image(ImageElement i) => [
      ..._box(i.box),
      i.tint,
      i.outline.color,
      i.overlay,
      ..._loop(i.animation.loop),
      for (var l in i.layers) ...[
        if (l.kind == LayerKind.fill) ..._paint(l.fill),
        if (l.kind == LayerKind.adjustment &&
            l.adjust.kind == AdjustKind.photoFilter)
          l.adjust.colour,
        if (l.kind == LayerKind.adjustment &&
            l.adjust.kind == AdjustKind.gradientMap)
          ..._paint(l.adjust.fade),
        if (l.kind == LayerKind.texture) ...[
          l.texture.colour,
          l.texture.second,
        ],
        if (l.look case var look?) ..._image(look),
        if (l.kind == LayerKind.picture) ..._loop(l.loop),
        for (var fx in l.effects) fx.colour,
        for (var s in l.strokes) s.colour,
      ],
      for (var s in i.retouch) s.colour,
    ];

/// keptColours are the colours on [e] that are never mapped (a terrain's
/// swatch among them, the editor's like a handle colour), with the numbers
/// beside them that look like colours and are not (a flipped tile's word, a
/// drawn text's signature, a colour table).
List<Object> keptColours(CanvasElement e) => [
      if (e.base.rowColour case var x?) x,
      ...switch (e) {
        ImageElement i => [
            i.removal.keyColor,
            for (var l in i.layers)
              if (l.adjust.cube case var cube?) cube.rgb.join(","),
          ],
        VideoElement v => [v.key.color],
        VectorElement v => [
            v.handleColor,
            for (var s in v.shapes ?? const <VectorShape>[]) ...[
              for (var t in s.erasures) ..._paint(t.paint),
              if (s.text case var t?) t.signature,
            ],
          ],
        TileMapElement t => [
            for (var s in t.sources)
              for (var set in s.terrains)
                for (var terrain in set.terrains) terrain.color,
            for (var l in t.layers) ...l.cells.values,
          ],
        _ => const <Object>[],
      },
    ];

/// documentColours is every colour [colourRichDocument] set, its elements'
/// included, read through the model.
List<Color> documentColours(CanvasDocument d) => [
      ..._pattern(d.background.spec),
      if (d.background.picture case var p?) ...elementColours(p),
      if (d.background.drawing?.tint case var x?) x,
      for (var s in [...d.scenes, if (d.master case var m?) m]) ...[
        for (var e in s.elements) ...elementColours(e),
        if (s.background case var b?) ..._plainPattern(b.spec),
        if (s.transition case var t?) t.color,
      ],
      for (var e in d.cast) ...elementColours(e),
      for (var s in d.textStyles) ..._type(s.spec),
      for (var s in d.sheets) ...[
        for (var r in s.rules) ...[r.colour, r.low, r.high],
        s.spotlightColour,
      ],
    ];

/// documentKept is [keptColours] across [d].
List<Object> documentKept(CanvasDocument d) => [
      if (d.background.drawing case var v?) v.handleColor,
      for (var s in [...d.scenes, if (d.master case var m?) m])
        for (var e in s.elements) ...keptColours(e),
    ];
