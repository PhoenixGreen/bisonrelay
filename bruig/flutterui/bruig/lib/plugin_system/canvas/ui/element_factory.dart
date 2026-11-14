import 'package:bruig/plugin_system/canvas/model/elements/synth_task_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/synth_module_element.dart';
import 'package:bruig/plugin_system/canvas/model/synth_patch.dart';
import 'package:bruig/plugin_system/canvas/render/synth_module_painter.dart';
import 'package:bruig/plugin_system/canvas/model/elements/object3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/presets/parallax_looks.dart';
import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/render/team_painter.dart';
import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/stage_spot.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_palette.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_design.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sprite_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/tile_map_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

// element_factory.dart makes a new element of each kind, in one place for
// both the Design Elements panel's tap and its drag, so the two never
// differ. Every new element arrives with something in it, obviously
// placeholder ("Text", "Week 1"): an empty chart or a blank text box looks
// like a bug.

/// defaultSizeFor is how big a new element starts, sized to the document so
/// it is neither bigger than a small canvas nor a speck on a large one.
Size defaultSizeFor(ElementKind kind, CanvasDocument document) {
  var short = document.size.height.toDouble();
  var wide = document.size.width.toDouble();
  return switch (kind) {
    ElementKind.text => Size(wide * 0.5, short * 0.16),
    ElementKind.image => Size(short * 0.5, short * 0.5),
    ElementKind.vector => Size(short * 0.4, short * 0.4),
    ElementKind.shape => Size(short * 0.28, short * 0.28),
    // Level: a line runs corner to corner of its box, so any depth here is a
    // slope. See LineElement.withEnds.
    ElementKind.line => Size(wide * 0.3, lineSliver),
    ElementKind.chart => Size(wide * 0.6, short * 0.6),
    ElementKind.table => Size(wide * 0.55, short * 0.4),
    ElementKind.button => Size(short * 0.32, short * 0.11),
    // Wide enough for a figure with words either side of it, and tall enough
    // for the row of buttons a live one can carry.
    ElementKind.counter => Size(wide * 0.34, short * 0.22),
    // A round speaker, the size of a thumb on a phone-shaped canvas. Its
    // mute switch and volume bar widen it when they are turned on.
    ElementKind.audio => Size(short * 0.12, short * 0.12),
    // 16:9, half the canvas across -- the shape nearly every video is. The
    // box takes the file's own shape when one is added.
    ElementKind.video => Size(wide * 0.5, wide * 0.5 * 9 / 16),
    ElementKind.background => Size(wide * 0.6, short * 0.5),
    // A team, not a player: the box is the half of the pitch the formation is
    // laid out in, so it wants most of the canvas rather than a dot's worth.
    ElementKind.player => Size(wide * 0.46, short * 0.86),
    // A path is a route across the design rather than an object on it, so it
    // arrives large enough to be worth curving.
    ElementKind.path => Size(wide * 0.5, short * 0.4),
    // Standing, most of the page's height, about as wide as a person with
    // their arms a little out is for their height.
    ElementKind.character3d => Size(short * 0.34, short * 0.7),
    // The whole page: a stage is the set the scene is played on.
    ElementKind.stage => Size(wide, short),
    ElementKind.parallax => Size(wide, short),
    // Two systems of a grand staff, across most of the canvas.
    ElementKind.sheet => Size(wide * 0.7, short * 0.5),
    // A square: a sprite's frames are mostly as wide as they are tall, and
    // the box takes a frame's own shape once there is a sheet.
    ElementKind.sprite => Size(short * 0.3, short * 0.3),
    // Most of the page: a map is the scene, its box a window onto it.
    ElementKind.tileMap => Size(wide * 0.8, short * 0.8),
    // The whole page: shown as it is until it is moved or drawn in closer.
    ElementKind.camera => Size(wide, short),
    // A square, a third of the page high: a model fitted whole in it.
    ElementKind.object3d => Size(short * 0.4, short * 0.4),
    // A module's panel, at the rack's scale.
    ElementKind.synth =>
      synthPanelOf(SynthModuleKind.osc).size * synthUnit(document),
    // A card that fits above the starting rack's keyboard, as the
    // prototype's did.
    ElementKind.synthTask => const Size(270, 160) * synthUnit(document),
  };
}

/// newInstrument makes an instrument -- an Audio element playing a part,
/// drawn as its keyboard: two octaves from the C below middle C, on its own
/// channel, its part on the timeline. See instrument.dart.
AudioElement newInstrument(CanvasDocument document, {Offset? center}) {
  var r = document.size.rect;
  var size = Size(r.width * 0.46, r.width * 0.46 * 0.3);
  var at = center ?? r.center;
  return AudioElement(
    ElementBase(
      id: newElementId(),
      name: "Piano",
      x: at.dx - size.width / 2,
      y: at.dy - size.height / 2,
      width: size.width,
      height: size.height,
    ),
    instrument: const InstrumentPart(),
    clip: const MediaClip(timed: true),
    controls: const [],
    // Amber, not the speaker's blue: blue is the key a practice take is
    // waiting for, and the two have to be told apart.
    accent: const Color(0xFFF2B33D),
  );
}

/// newElement makes one of [kind], centred on [center] in document space.
CanvasElement newElement(
  ElementKind kind,
  CanvasDocument document, {
  Offset? center,
}) {
  var size = defaultSizeFor(kind, document);
  var at = center ?? document.size.rect.center;
  var base = ElementBase(
    id: newElementId(),
    x: at.dx - size.width / 2,
    y: at.dy - size.height / 2,
    width: size.width,
    height: size.height,
  );

  // The type sizes are worked from the document's height so that text on a
  // small canvas is not enormous and text on a large one is not unreadable.
  var unit = document.size.height / 24;

  switch (kind) {
    case ElementKind.text:
      // Proportions held to begin with, so dragging a corner scales the type,
      // spacing and pieces with the box, as a card should. Let go of, the box
      // changes and its contents keep their size.
      return TextElement(base.copyWith(lockAspect: true),
          text: "Text",
          textSpec: TextSpec(
            fontSize: unit * 1.6,
            weight: 700,
            align: TextAlignSpec.center,
          ),
          autoSize: true);

    case ElementKind.image:
      // Proportions locked to begin with: a photograph dragged out of shape
      // looks wrong.
      return ImageElement(base.copyWith(lockAspect: true));

    case ElementKind.vector:
      // Proportions held, as a picture's are: a drawing pulled out of shape
      // looks wrong the same way.
      return VectorElement(base.copyWith(lockAspect: true));

    case ElementKind.shape:
      return ShapeElement(base,
          shape: ShapeKind.rectangle,
          cornerRadius: unit * 0.4,
          textSpec: TextSpec(fontSize: unit, weight: 700));

    case ElementKind.line:
      return LineElement(base, strokeWidth: unit * 0.18);

    case ElementKind.chart:
      // Its title and axis titles there to fill in, but hidden until they
      // are: a new chart said "Chart title", "Value" and "Category" until
      // each was turned off (Ken's privacy video, 2026-11-11).
      return ChartElement(base,
          title: "Chart title",
          titleBox: const ChartLabel(show: false),
          xAxisLabel: "Category",
          yAxisLabel: "Value",
          showXTitle: false,
          showYTitle: false,
          titleSpec: TextSpec(fontSize: unit * 0.9, weight: 700),
          labelSpec: TextSpec(fontSize: unit * 0.52),
          valueSpec: TextSpec(fontSize: unit * 0.45, weight: 600),
          data: const ChartData(
            categories: ["One", "Two", "Three", "Four", "Five"],
            series: [
              ChartSeries(
                name: "Series 1",
                color: Color(0xFF3D7EFF),
                values: [8, 14, 11, 19, 15],
              ),
            ],
          ));

    case ElementKind.counter:
      // A hundred, counting up from nothing, written plainly: the count itself
      // is the placeholder that shows what this is. Making it a page number is
      // a switch in its settings (see positionGroup).
      return CounterElement(base,
          from: 0,
          to: 100,
          numberSpec: TextSpec(
              fontSize: unit * 2.4, weight: 700, align: TextAlignSpec.center),
          affixSpec:
              TextSpec(fontSize: unit * 0.9, align: TextAlignSpec.center),
          buttonSpec: TextSpec(
              fontSize: unit * 0.5, weight: 600, align: TextAlignSpec.center),
          box: BoxSpec(padding: unit * 0.6));

    case ElementKind.audio:
      // Empty, and it says so: the settings open on "Add a sound file".
      return AudioElement(base,
          box: BoxSpec(
              fill: const Color(0xFF223046),
              borderRadius: size.shortestSide,
              padding: size.shortestSide * 0.12));

    case ElementKind.video:
      // No background of its own: a keyed video must be see-through where the
      // screen was. The empty element draws its own dark ground until a video
      // is in it.
      return VideoElement(base.copyWith(lockAspect: true));

    case ElementKind.table:
      // In the colours the canvas is already in, rather than a look of its
      // own that has to be undone cell by cell.
      return tableInColours(
          TableElement(base,
              cellSpec:
                  TextSpec(fontSize: unit * 0.55, align: TextAlignSpec.left),
              headerSpec: TextSpec(
                  fontSize: unit * 0.55,
                  weight: 700,
                  align: TextAlignSpec.left),
              cellPadding: unit * 0.35,
              rows: const [
                ["Name", "Value", "Change"],
                ["First", "120", "+4%"],
                ["Second", "185", "+11%"],
                ["Third", "143", "-2%"],
              ]),
          canvasColours(
              document.background.spec.background, document.elements));

    case ElementKind.button:
      return ButtonElement(base,
          label: "Next",
          textSpec: TextSpec(fontSize: unit * 0.7, weight: 600),
          box: BoxSpec(
            fill: const Color(0xFF3D7EFF),
            borderRadius: unit * 0.4,
            padding: unit * 0.35,
          ),
          hoverFill: const Color(0xFF5C95FF));

    case ElementKind.background:
      return BackgroundElement(base,
          spec: const ProceduralSpec(
            style: ProceduralStyle.rain,
            seed: 5,
            background: Color(0xFF00120A),
            foreground: Color(0xFF19C46B),
            accent: Color(0xFFD8FFEA),
            density: 0.6,
            scale: 0.045,
            intensity: 0.9,
            variation: 0.5,
            vignette: 0.35,
          ),
          cornerRadius: unit * 0.4);

    case ElementKind.path:
      return PathElement(
        base.copyWith(name: "Path"),
        nodes: PathElement.defaultNodes(frames: document.frames),
        strokeWidth: math.max(2, size.shortestSide * 0.012),
        dash: size.shortestSide * 0.04,
      );

    case ElementKind.player:
      // Sized to cover half a pitch, which a formation is laid out against; at
      // the usual size eleven players would sit on top of each other.
      var dot = size.height * 0.16;
      var team = TeamElement(
        base.copyWith(name: "Team"),
        dotWidth: dot,
        dotHeight: dot,
        ringWidth: dot * 0.09,
        labelSpec: TextSpec(
          fontSize: dot * 0.5,
          weight: 700,
          outlineWidth: dot * 0.04,
          outlineColor: const Color(0xCC0A1A0A),
        ),
        nameGap: dot * 0.2,
      ).withFormation(TeamFormation.f442);
      // Standing on the pitch straight away where there is one -- the
      // first, which is the canvas's own background where that is one. A
      // team dropped onto a pitch is a team for that pitch.
      var pitches = pitchChoices(document);
      if (pitches.isEmpty) return team;
      var p = pitches.first;
      return team.linkedTo(p.link,
          pitch: p.sport, reference: p.reference, area: p.area);

    case ElementKind.sprite:
      return SpriteElement(base.copyWith(lockAspect: true));

    case ElementKind.tileMap:
      return TileMapElement(base.copyWith(name: "Tile map"));

    // Not offered by Add any more: a stage is a kind of background. Kept so
    // that asking for one still gives one -- a Background element showing
    // its stage, over the whole page.
    case ElementKind.stage:
      return BackgroundElement(
          base.copyWith(
              name: "3D stage",
              x: 0,
              y: 0,
              width: size.width,
              height: size.height),
          backdrop: BackdropKind.stage,
          stage: const StageElement(ElementBase(id: "")));

    // A score of the first instrument there is, if there is one; with none,
    // it says so in its settings.
    case ElementKind.sheet:
      // A score's first part if there is a score, else the first
      // instrument.
      for (var s in document.scores) {
        for (var p in s.parts) {
          if (document.elementById(p.channel) is! AudioElement) continue;
          return SheetElement(base.copyWith(name: "Sheet music"),
              follows: p.channel,
              score: s.id,
              part: p.id,
              title: s.title,
              key: s.fifths);
        }
      }
      var first = document.elements
          .whereType<AudioElement>()
          .where((e) => e.instrument != null)
          .firstOrNull;
      return SheetElement(base.copyWith(name: "Sheet music"),
          follows: first?.id ?? "", title: first?.name ?? "");

    // A box for a model: given one from the library's 3D objects -- see
    // elementForAsset.
    case ElementKind.object3d:
      return Object3dElement(base.copyWith(name: "3D object"));

    // An oscillator by itself; the Synth chip puts down a whole rack (see
    // synthRack).
    case ElementKind.synth:
      return SynthModuleElement(base.copyWith(name: "Oscillator"),
          module: SynthModuleKind.osc);

    case ElementKind.synthTask:
      return SynthTaskElement(base.copyWith(name: "Synth task"),
          speaker: document.elements
                  .whereType<SynthModuleElement>()
                  .where((m) => m.module == SynthModuleKind.out)
                  .firstOrNull
                  ?.id ??
              "");

    case ElementKind.camera:
      // On the whole page, where it shows everything, to be drawn in and
      // moved from there (see CameraElement); on a 3D stage, where the stage's
      // camera is (see camera_3d.dart).
      var drawn = document.drawnBackground;
      return CameraElement(
          base.copyWith(
              name: "Camera",
              x: 0,
              y: 0,
              width: size.width,
              height: size.height),
          view: drawn.isStage
              ? drawn.stageOn(document.size.rect).ownCameraAt(0)
              : document.elements
                  .whereType<BackgroundElement>()
                  .where((b) => b.isStage)
                  .firstOrNull
                  ?.staged
                  .ownCameraAt(0));

    // The same for parallax scenery: a Background element showing it.
    case ElementKind.parallax:
      return BackgroundElement(
          base.copyWith(
              name: "Parallax",
              x: 0,
              y: 0,
              width: size.width,
              height: size.height),
          backdrop: BackdropKind.parallax,
          parallax: parallaxLooks.first.scenery);

    // Placed from the library with its design; this is only the box -- see
    // CanvasController.placeCharacter3d.
    case ElementKind.character3d:
      // On the stage, where there is one: a scene with a set is played on
      // it. Each new one a step along from the last, not on top of it.
      var stage = stagesIn(document.elements,
              backdrop: document.drawnBackground)
          .firstOrNull
          ?.$1;
      var already = stage == null
          ? 0
          : document.elements.where((e) => e.base.spot?.stage == stage).length;
      var x = (already.isEven ? 1 : -1) * (already + 1) ~/ 2 * 1.2;
      return Character3dElement(
          base.copyWith(
              lockAspect: true,
              spot: stage == null ? null : StageSpot(stage, x: x.toDouble())),
          design: CharacterDesign(
              id: "", name: "", body: "Vivi", updated: DateTime(2026)));
  }
}

/// synthUnit is how big a synth module's panel unit is on [document]: a
/// rack of the prototype's seven fits the page.
double synthUnit(CanvasDocument document) =>
    math.min(document.size.width / 1150, document.size.height / 760);

/// synthModule makes a module of [kind] with its top left at [at], at
/// the rack's scale.
SynthModuleElement synthModule(
    CanvasDocument document, SynthModuleKind kind, Offset at,
    {String? id, Map<String, double> values = const {}}) {
  var size = synthPanelOf(kind).size * synthUnit(document);
  return SynthModuleElement(
      ElementBase(
          id: id ?? newElementId(),
          name: kind.label,
          x: at.dx,
          y: at.dy,
          width: size.width,
          height: size.height),
      module: kind,
      values: values);
}

/// synthRack is the prototype's starting rack (Ken approved, 2026-11-14):
/// a keyboard, an oscillator, an envelope, a filter, an LFO, an amp and a
/// speaker, the keyboard's pitch patched into the oscillator, through the
/// amp to the speaker -- the rest there to be patched in. Centred on
/// [center]; the speaker's channel [channel].
List<SynthModuleElement> synthRack(CanvasDocument document,
    {Offset? center, required String channel}) {
  var u = synthUnit(document);
  var mid = center ?? document.size.rect.center;
  // The prototype's places, in its rack's units (1150 by 760), centred.
  var origin = mid - const Offset(575, 380) * u;
  Offset at(double x, double y) => origin + Offset(x, y) * u;
  var ids = {
    for (var k in ["k", "o", "e", "f", "l", "a", "s"]) k: newElementId()
  };
  SynthPlug plug(String id, String port) => (module: ids[id]!, port: port);
  var mods = [
    synthModule(document, SynthModuleKind.keys, at(24, 470), id: ids["k"]),
    synthModule(document, SynthModuleKind.osc, at(320, 30), id: ids["o"]),
    synthModule(document, SynthModuleKind.env, at(320, 420), id: ids["e"]),
    synthModule(document, SynthModuleKind.filter, at(600, 30),
        id: ids["f"], values: {"cutoff": 6000}),
    synthModule(document, SynthModuleKind.lfo, at(600, 420),
        id: ids["l"], values: {"rate": 0.6}),
    synthModule(document, SynthModuleKind.amp, at(880, 30), id: ids["a"]),
    synthModule(document, SynthModuleKind.out, at(880, 400), id: ids["s"]),
  ];
  var inputs = {
    ids["o"]!: {"pitch": plug("k", "pitch")},
    ids["a"]!: {"in": plug("o", "out")},
    ids["s"]!: {"in": plug("a", "out")},
  };
  return [
    for (var m in mods)
      () {
        var e = m.copyWith(
            inputs: inputs[m.id] ?? const {},
            channel: m.module == SynthModuleKind.out ? channel : null);
        // Where students reset to: as it starts.
        return e.startHere();
      }(),
  ];
}
