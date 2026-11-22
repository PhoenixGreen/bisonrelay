import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_palette.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_design.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_run_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_task_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/metronome_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/object3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/play_task_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sprite_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/synth_module_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/synth_task_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/tile_map_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/layout_presets.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/stage_spot.dart';
import 'package:bruig/plugin_system/canvas/model/synth_patch.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/presets/parallax_looks.dart';
import 'package:bruig/plugin_system/canvas/render/code_task_painter.dart';
import 'package:bruig/plugin_system/canvas/render/play_task_painter.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/render/synth_module_painter.dart';
import 'package:bruig/plugin_system/canvas/render/team_painter.dart';

// element_factory.dart makes a new element of each kind, in one place for
// both the Elements panel's tap and its drag, so the two never differ. Each
// arrives with obvious placeholder content: an empty chart or a blank text
// box looks like a bug.

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
    // Room for words either side of the figure and a live one's buttons.
    ElementKind.counter => Size(wide * 0.34, short * 0.22),
    // A round speaker; its mute switch and volume bar widen it when on.
    ElementKind.audio => Size(short * 0.12, short * 0.12),
    // 16:9, half the canvas across; the box takes the file's own shape when
    // one is added.
    ElementKind.video => Size(wide * 0.5, wide * 0.5 * 9 / 16),
    ElementKind.background => Size(wide * 0.6, short * 0.5),
    // A team, not a player: the box is the half pitch the formation is laid
    // out in.
    ElementKind.player => Size(wide * 0.46, short * 0.86),
    // A route across the design, large enough to be worth curving.
    ElementKind.path => Size(wide * 0.5, short * 0.4),
    // Standing, most of the page's height, arms a little out.
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
    // The whole page, until it is moved or drawn in closer.
    ElementKind.camera => Size(wide, short),
    // A square: a model is fitted whole in it.
    ElementKind.object3d => Size(short * 0.4, short * 0.4),
    ElementKind.synth =>
      synthPanelOf(SynthModuleKind.osc).size * synthUnit(document),
    // A card that fits above the starting rack's keyboard.
    ElementKind.synthTask => const Size(270, 160) * synthUnit(document),
    // As a clockwork one stands: taller than wide.
    ElementKind.metronome => Size(short * 0.22, short * 0.35),
    // An editor's window: most of the page's width, most of its height.
    ElementKind.code => Size(wide * 0.6, short * 0.78),
    // Beside it, narrower: a page or a console is read down.
    ElementKind.codeRun => Size(wide * 0.3, short * 0.78),
    // A card, a third of the page wide; its height is what it says.
    ElementKind.codeTask => Size(wide * 0.32, short * 0.3),
    // Most of the page: a layout is usually the page's own.
    ElementKind.layout => Size(wide * 0.9, short * 0.9),
    // Most of the page's width, under the music; its height is what it says.
    ElementKind.playTask => Size(wide * 0.8, short * 0.2),
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
      // Proportions held, so dragging a corner scales the type with the box.
      // Unlocked, the box changes and its contents keep their size.
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
      // Proportions held, as a picture's are.
      return VectorElement(base.copyWith(lockAspect: true));

    case ElementKind.shape:
      return ShapeElement(base,
          shape: ShapeKind.rectangle,
          cornerRadius: unit * 0.4,
          textSpec: TextSpec(fontSize: unit, weight: 700));

    case ElementKind.line:
      return LineElement(base, strokeWidth: unit * 0.18);

    case ElementKind.chart:
      // Title and axis titles there to fill in, but hidden until shown, so
      // placeholder words never reach a finished chart.
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
      // Counting 0 to 100: the count itself is the placeholder. A page number
      // is a switch in its settings (see positionGroup).
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
      // screen was. Empty, it draws a dark ground of its own.
      return VideoElement(base.copyWith(lockAspect: true));

    case ElementKind.table:
      // In the canvas's colours, not a look to undo cell by cell.
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
      // Dots sized to the half pitch, so eleven players do not overlap.
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
      // Linked to the first pitch where there is one (the canvas's own
      // background first): a team dropped onto a pitch plays on it.
      var pitches = pitchChoices(document);
      if (pitches.isEmpty) return team;
      var p = pitches.first;
      return team.linkedTo(p.link,
          pitch: p.sport, reference: p.reference, area: p.area);

    case ElementKind.sprite:
      return SpriteElement(base.copyWith(lockAspect: true));

    case ElementKind.tileMap:
      return TileMapElement(base.copyWith(name: "Tile map"));

    // Not offered by Add: a stage is a kind of background. Asking for one
    // gives a Background element showing its stage over the whole page.
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

    // A score's first part if there is a score, else the first instrument;
    // with none, it says so in its settings.
    case ElementKind.sheet:
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

    // A box for a model from the library's 3D objects (see elementForAsset).
    case ElementKind.object3d:
      return Object3dElement(base.copyWith(name: "3D object"));

    // An oscillator by itself; the Synth chip puts down a whole rack (see
    // synthRack).
    case ElementKind.synth:
      return SynthModuleElement(base.copyWith(name: "Oscillator"),
          module: SynthModuleKind.osc);

    case ElementKind.metronome:
      return MetronomeElement(base.copyWith(name: "Metronome"));

    // An empty web page, at a size read across the room; its kind is chosen
    // in its settings, and the examples are presets (code_starters.dart).
    case ElementKind.code:
      return CodeElement(base.copyWith(name: "Code"),
              fontSize: codeFontFor(document))
          .startedAs(CodeKind.web);

    case ElementKind.codeTask:
      var code = document.elements.whereType<CodeElement>().firstOrNull;
      var card = CodeTaskElement(base.copyWith(name: "Code task"),
          code: code?.id ?? "",
          textSize: codeFontFor(document) * 0.95,
          checks: const [
            CodeCheck(CodeCheckKind.builds, "It builds and runs")
          ]);
      return card.withBase(height: codeTaskFitHeight(card, card.width));

    // A comic page's three tiers, to be cut and moved; other starts are in
    // its settings (layout_presets.dart).
    case ElementKind.layout:
      return layoutFrom(base.copyWith(name: "Layout"), LayoutPreset.threeTiers);

    // Listening to any instrument, with a first step to change.
    case ElementKind.playTask:
      var task =
          PlayTaskElement(base.copyWith(name: "Play task"), checks: const [
        PlayCheck(PlayCheckKind.keys, "Play Middle C", steps: "C4"),
      ]);
      return task.withBase(height: playTaskFitHeight(task, task.width));

    case ElementKind.codeRun:
      return CodeRunElement(base.copyWith(name: "Run"),
          code:
              document.elements.whereType<CodeElement>().firstOrNull?.id ?? "",
          outputSize: codeFontFor(document) * 0.9);

    case ElementKind.synthTask:
      return SynthTaskElement(base.copyWith(name: "Synth task"),
          speaker: document.elements
                  .whereType<SynthModuleElement>()
                  .where((m) => m.module == SynthModuleKind.out)
                  .firstOrNull
                  ?.id ??
              "");

    case ElementKind.camera:
      // Over the whole page (see CameraElement); on a 3D stage, where the
      // stage's camera is (see camera_3d.dart).
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

    // Only the box: the library places it with its design (see
    // CanvasController.placeCharacter3d).
    case ElementKind.character3d:
      // On the stage where there is one, each new one a step along from the
      // last rather than on top of it.
      var stage =
          stagesIn(document.elements, backdrop: document.drawnBackground)
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

/// synthUnit is a synth module panel unit on [document], so that the
/// seven-module starting rack fits the page.
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

/// synthRack is the starting rack: keyboard, oscillator, envelope, filter,
/// LFO, amp and speaker, with keyboard pitch to oscillator, through the amp
/// to the speaker, and the rest left to patch. Centred on [center]; the
/// speaker plays on [channel].
List<SynthModuleElement> synthRack(CanvasDocument document,
    {Offset? center, required String channel}) {
  var u = synthUnit(document);
  var mid = center ?? document.size.rect.center;
  // Places in rack units (1150 by 760), centred.
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
        // The starting state is what students reset to.
        return e.startHere();
      }(),
  ];
}

/// codeFontFor is code's size on a new Code panel in [document]: about 17
/// on a 1080p page.
double codeFontFor(CanvasDocument document) =>
    (document.size.height.toDouble() * 0.016).clamp(6.0, 120.0);

/// iconForKind is the icon an element of [kind] wears wherever it is
/// listed: on the Add panel, in Layers, on a preset's row.
IconData iconForKind(ElementKind kind) => switch (kind) {
      ElementKind.text => Icons.title,
      ElementKind.image => Icons.image_outlined,
      ElementKind.vector => Icons.draw_outlined,
      ElementKind.shape => Icons.category_outlined,
      ElementKind.line => Icons.timeline,
      ElementKind.chart => Icons.bar_chart,
      ElementKind.table => Icons.table_chart_outlined,
      ElementKind.button => Icons.smart_button_outlined,
      ElementKind.counter => Icons.timer_outlined,
      ElementKind.audio => Icons.volume_up_outlined,
      ElementKind.video => Icons.smart_display_outlined,
      ElementKind.background => Icons.blur_on,
      ElementKind.player => Icons.person_pin_circle_outlined,
      ElementKind.path => Icons.gesture,
      ElementKind.character3d => Icons.view_in_ar_outlined,
      ElementKind.stage => Icons.view_in_ar_outlined,
      ElementKind.sprite => Icons.directions_run,
      ElementKind.tileMap => Icons.grid_view,
      ElementKind.parallax => Icons.landscape_outlined,
      ElementKind.sheet => Icons.queue_music,
      ElementKind.camera => Icons.videocam_outlined,
      ElementKind.object3d => Icons.view_in_ar,
      ElementKind.synth => Icons.cable,
      ElementKind.synthTask => Icons.checklist,
      ElementKind.metronome => Icons.av_timer,
      ElementKind.code => Icons.code,
      ElementKind.codeRun => Icons.play_circle_outline,
      ElementKind.codeTask => Icons.fact_check_outlined,
      ElementKind.playTask => Icons.piano,
      ElementKind.layout => Icons.dashboard_outlined,
    };
