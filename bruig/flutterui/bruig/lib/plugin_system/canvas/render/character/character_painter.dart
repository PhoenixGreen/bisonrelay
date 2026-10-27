import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/render/canvas_perf.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_wardrobe.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_life.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_outline.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_parts.dart';
import 'package:bruig/plugin_system/canvas/render/character/painted_light.dart';
import 'package:bruig/plugin_system/canvas/render/model/human_body.dart';
import 'package:bruig/plugin_system/canvas/render/model/mannequin.dart';
import 'package:bruig/plugin_system/canvas/render/model/mesh_painter.dart';
import 'package:bruig/plugin_system/canvas/render/model/model_figure.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_painter.dart';

// character_painter.dart draws a character: its rig, dressed and given a
// face, in its style.
//
// Back to front, the way a person is put together on paper: long hair behind
// the head, then the legs and shoes, the body and what is worn on it, the
// arms over the body, and the head last. Every shape is filled and then
// edged a shade darker than itself, which is what makes the Feature cartoon
// style read as one drawing rather than coloured shapes laid on top of one
// another.

/// characterSoloOf is the layer of [CharacterElement] soloed while it is
/// edited, set by the editor -- as vectorSoloOf is for a drawing's layers.
/// Null draws every layer.
String? Function(CharacterElement e)? characterSoloOf;

/// _Pass is which of the two drawings of a soloed layer this is: the rest,
/// faint, or the layer alone over them. All for a figure soloing nothing.
enum _Pass { all, others, solo }

/// paintCharacter draws [e] as it is on [frame]: posed, its face set, and
/// blinking and breathing at [frameRate].
/// [editing] is the stage, where a character can be shown bare while it is
/// designed; never in anything made from the canvas.
/// [staged] is where it stands on a 3D stage, when it does: its box is the
/// camera's, it is turned as the camera sees it, and lit by the stage.
void paintCharacter(Canvas canvas, Rect box, CharacterElement e, int frame,
    {int frameRate = 12,
    bool editing = false,
    Staging? staged,
    CanvasImageSource? images}) {
  // A style on twos holds each drawing for two frames, as stop motion does.
  frame = e.style.frameOf(frame);
  var life = lifeAt(e, frame, frameRate);
  var (pose, face) = e.performanceAt(frame, frameRate);
  if (staged != null) {
    pose = pose
        .withTurn(pose.turn + staged.turn)
        .withTilt((pose.tilt + staged.tilt).clamp(-85.0, 85.0));
    if (staged.shadow case var shadow?) {
      canvas.drawPath(shadow, _shadowPaint(e.shadow, box.height));
    }
  } else {
    box = characterBox(e, frame, box);
    if (e.shadow != CharacterShadow.none) {
      // A contact shadow on the ground under the feet, smaller and fainter
      // the higher it jumps.
      var up = 1 / (1 + pose.lift.abs() * 0.8);
      canvas.drawOval(
          Rect.fromCenter(
              center: box.bottomCenter,
              width: box.width * 0.8 * up,
              height: box.height * 0.05 * up),
          _shadowPaint(e.shadow, box.height, strength: up));
    }
  }
  var light = staged == null ? null : lightFilter(staged.light);
  if (light != null) {
    canvas.saveLayer(box.inflate(box.height), Paint()..colorFilter = light);
  }
  paintCharacterFigure(canvas, box, e.dna, pose,
      face: face,
      life: life,
      bare: editing && e.bareView,
      style: e.style,
      body: e.body,
      images: images,
      // What is drawn by hand on the panel it is seen from.
      drawing: e.body.inThreeD || e.drawings.isEmpty
          ? null
          : e.drawingFor(pose.panelTurn, pose.panelTilt).$1,
      // The face as it is set on that panel.
      faceRig: e.body.inThreeD || e.faceRigs.isEmpty
          ? null
          : e.faceRigFor(pose.panelTurn, pose.panelTilt).$1,
      // Its layers as shown -- and, while it is edited, the one soloed.
      layers: e.body.inThreeD
          ? LayerView.all
          : e.layerView(solo: editing ? characterSoloOf?.call(e) : null));
  if (light != null) canvas.restore();
}

Paint _shadowPaint(CharacterShadow kind, double size, {double strength = 1}) {
  var p = Paint()
    ..color = const Color(0xFF000000)
        .withValues(alpha: (kind == CharacterShadow.hard ? 0.32 : 0.24) * strength);
  if (kind == CharacterShadow.soft) {
    p.maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(0.5, size * 0.012));
  }
  return p;
}

/// characterBox is where [e] is drawn in its own [box] on [frame]: as it
/// is, or -- with depth -- nearer and bigger for having moved down the
/// page, further and smaller for having moved up it, about its feet.
Rect characterBox(CharacterElement e, int frame, Rect box) {
  if (e.depth == 0) return box;
  var dy = e.poseAt(frame).dy;
  var f = (1 + e.depth * dy / math.max(1.0, e.height)).clamp(0.25, 4.0);
  if (f == 1) return box;
  return Rect.fromLTWH(box.center.dx - box.width * f / 2,
      box.bottom - box.height * f, box.width * f, box.height * f);
}

/// paintCharacterFigure draws [dna] in [pose], filling the height of [box].
/// What the settings panel's tiles draw, with no element behind them.
void paintCharacterFigure(
    Canvas canvas, Rect box, CharacterDna dna, CharacterPose pose,
    {CharacterFace face = CharacterFace.rest,
    LifeAt life = LifeAt.none,
    bool bare = false,
    CharacterStyle style = CharacterStyle.featureCartoon,
    CharacterBody body = const CharacterBody(),
    CanvasImageSource? images,
    CharacterStyle? bodyStyle,
    CharacterDrawing? drawing,
    FaceRig? faceRig,
    LayerView layers = LayerView.all}) {
  if (box.height <= 0) return;
  // bodyStyle is the style a sculpted body is made for, in place of this
  // one -- for a preview of a style drawn on the body already made, rather
  // than making one of its own.
  var bodyDna = bodyStyle?.dnaOf(dna);
  dna = style.dnaOf(dna);
  // A sketch is drawn in panels -- see CharacterPose.inPanel -- so however
  // it is turned, it is drawn from the nearest one.
  if (!body.inThreeD) pose = pose.inPanel;
  var rig = CharacterRig.of(dna, pose, box, breath: life.breath);
  var look = _Look.of(style);
  // What is drawn by hand -- or taken apart -- on the panel: the
  // character's own and what it wears, each shape on the part of the body
  // under it, all in one order. See CharacterDrawing.order.
  var onPanel = <(double, CharacterDrawing, int, String?)>[];
  // A garment taken apart on the panel is drawn by its shapes alone.
  var replaced = <Garment>{};
  if (!body.inThreeD) {
    if (!bare) {
      for (var (gi, g) in dna.worn.indexed) {
        if (g.drawings.isEmpty) continue;
        // A garment's layer hidden: what is drawn on it too.
        var key = garmentLayer(dna.wardrobe.indexOf(g));
        if (!layers.shows(key)) continue;
        var (d, _) = g.drawingFor(pose.panelTurn, pose.panelTilt);
        if (d.replaces) replaced.add(g);
        for (var i = 0; i < d.shapes.length; i++) {
          onPanel.add((d.orderOf(i, 1e6 + gi * 1e4), d, i, key));
        }
      }
    }
    if (drawing != null) {
      for (var i = 0; i < drawing.shapes.length; i++) {
        // A layer hidden: its shapes too.
        var layer = drawing.layerOf(i);
        if (layer != null && !layers.shows(layer)) continue;
        onPanel.add((drawing.orderOf(i, 2e6), drawing, i, layer));
      }
    }
  }
  // A layer taken apart on the panel is drawn by its shapes, not its own
  // drawing.
  var generated = drawing == null || drawing.hiddenLayers.isEmpty
      ? layers
      : LayerView(hidden: {...layers.hidden, ...drawing.hiddenLayers}, solo: layers.solo);
  // The shapes drawn: all of them, or -- a layer soloed -- the rest's or
  // its own.
  void drawn(Canvas onto, {bool? soloed}) => paintPanelShapes(
      onto,
      rig,
      [
        for (var (o, d, i, layer) in onPanel)
          if (soloed == null || (layer == layers.solo) == soloed) (o, d, i)
      ],
      box.inflate(box.height));

  void drawOn(Canvas onto) {
    if (body.inThreeD) {
      _paintInThreeD(onto, rig, dna, pose, face, life, body, box, images,
          style: style, look: look, modelDna: bodyDna, bodyStyle: bodyStyle);
      return;
    }
    // Painted light: drawn as flat colour and lit -- or, before its shader
    // is loaded, drawn as it is.
    // A layer soloed: everything else faint, then the layer alone over it,
    // as flat colour -- a view for working on it, not the finished look.
    if (layers.solo != null) {
      _Drawing pass(_Pass p) => _Drawing(onto, rig, dna, face, life,
          bare: bare,
          look: look,
          images: images,
          hidden: drawing?.hidden ?? const {},
          faceRig: faceRig ?? FaceRig.none,
          replaced: replaced,
          layers: generated,
          pass: p);
      onto.saveLayer(box.inflate(box.height),
          Paint()..color = const Color(0x2E000000));
      pass(_Pass.others).draw();
      drawn(onto, soloed: false);
      onto.restore();
      pass(_Pass.solo).draw();
      drawn(onto, soloed: true);
      return;
    }
    if (look.shading == _Shading.painted) {
      var unit = box.height / dna.headsTall;
      var lit = paintPainted(
          onto,
          box.inflate(box.height * 0.35),
          PaintedLook(
            line: unit * 0.024 * look.line,
            ink: look.ink ?? const Color(0xFF6B4636),
            reach: unit * 0.09,
          ),
          (flat, buffers) {
            _Drawing(flat, rig, dna, face, life,
                    bare: bare,
                    look: look,
                    images: images,
                    painted: buffers,
                    hidden: drawing?.hidden ?? const {},
                    faceRig: faceRig ?? FaceRig.none,
                    replaced: replaced,
                    layers: generated)
                .draw();
            drawn(flat);
          },
          // A garment's picture print comes from the images, which are not
          // part of this: a figure wearing one is drawn afresh each time.
          key: dna.worn.any((g) => g.printId.isNotEmpty)
              ? null
              : jsonEncode([
                  dna.toJson(),
                  pose.toJson(),
                  face.toJson(),
                  [life.blink, life.breath, life.lookX, life.lookY],
                  style.name,
                  bare,
                  drawing?.toJson(),
                  faceRig?.toJson(),
                  generated.key,
                ]));
      if (lit) return;
    }
    _Drawing(onto, rig, dna, face, life,
            bare: bare,
            look: look,
            images: images,
            hidden: drawing?.hidden ?? const {},
            faceRig: faceRig ?? FaceRig.none,
            replaced: replaced,
            layers: generated)
        .draw();
    // Drawn by hand over it, each shape where its part is.
    drawn(onto);
  }

  void draw(Canvas onto) => CanvasPerf.time("character", () => drawOn(onto));
  // The room the figure is drawn in, arms out and hat on included.
  var room = box.inflate(box.height * 0.35);
  switch (style) {
    case CharacterStyle.noir:
      // A silhouette, lit from behind on one side: the figure in light,
      // moved a little towards the light, and the figure in near-black
      // over it.
      var unit = box.height / dna.headsTall;
      canvas.saveLayer(
          room,
          Paint()
            ..colorFilter = const ColorFilter.mode(
                Color(0xFFF2EEE4), BlendMode.srcIn));
      canvas.translate(-unit * 0.07, -unit * 0.045);
      draw(canvas);
      canvas.restore();
      canvas.saveLayer(
          room,
          Paint()
            ..colorFilter = const ColorFilter.mode(
                Color(0xFF141414), BlendMode.srcIn));
      draw(canvas);
      canvas.restore();
    case CharacterStyle.paperCutout:
      // Pieces of paper laid on the page cast a shadow on it.
      var unit = box.height / dna.headsTall;
      canvas.saveLayer(
          room,
          Paint()
            ..colorFilter = const ColorFilter.mode(
                Color(0x55000000), BlendMode.srcIn));
      canvas.translate(unit * 0.05, unit * 0.06);
      draw(canvas);
      canvas.restore();
      draw(canvas);
    case CharacterStyle.manga:
      canvas.saveLayer(room, Paint()..colorFilter = _greyscale);
      draw(canvas);
      canvas.restore();
    case CharacterStyle.storybook:
      canvas.saveLayer(room, Paint()..colorFilter = _wash);
      draw(canvas);
      canvas.restore();
    case CharacterStyle.kawaii || CharacterStyle.shojo:
      canvas.saveLayer(room, Paint()..colorFilter = _pastel);
      draw(canvas);
      canvas.restore();
    case CharacterStyle.softFilm:
      canvas.saveLayer(room, Paint()..colorFilter = _film);
      draw(canvas);
      canvas.restore();
    case CharacterStyle.pixel:
      // Drawn at a small size and scaled up without smoothing: every pixel
      // of the small drawing a square block.
      var block = math.max(2.0, box.height / 90);
      var w = (room.width / block).ceil(), h = (room.height / block).ceil();
      var recorder = PictureRecorder();
      var small = Canvas(recorder)
        ..scale(1 / block)
        ..translate(-room.left, -room.top);
      draw(small);
      var image = recorder.endRecording().toImageSync(math.max(1, w), math.max(1, h));
      canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          Rect.fromLTWH(room.left, room.top, w * block, h * block),
          Paint()..filterQuality = FilterQuality.none);
      image.dispose();
    default:
      draw(canvas);
  }
}

/// _paintInThreeD draws [dna] as a body in 3D: the model [body] names when
/// it is loaded, and the mannequin until it is -- or when it is the
/// mannequin that is asked for.
///
/// A sculpted body wears its style's face: the eyes, brows and mouth the
/// style draws, laid on the 3D head as it turns -- all but the painterly
/// style, whose eyes are the model's own.
void _paintInThreeD(Canvas canvas, CharacterRig rig, CharacterDna dna,
    CharacterPose pose, CharacterFace face, LifeAt life, CharacterBody body,
    Rect box, CanvasImageSource? images,
    {CharacterStyle style = CharacterStyle.featureCartoon,
    _Look look = const _Look(),
    CharacterDna? modelDna,
    CharacterStyle? bodyStyle}) {
  var drawnFace = body.kind == BodyKind.mannequin && style != CharacterStyle.painterly;
  // Blinking and glancing about, as the drawn face does.
  face = face.withControls({
    if (life.blink > 0)
      FaceControl.eyesOpen: face[FaceControl.eyesOpen] * (1 - life.blink),
    if (life.lookX != 0)
      FaceControl.lookX: face[FaceControl.lookX] + life.lookX,
    if (life.lookY != 0)
      FaceControl.lookY: face[FaceControl.lookY] + life.lookY,
  });
  // A model brought in, or the sculpted body made into this character --
  // the mannequin standing in for either until it is here.
  var model = body.kind == BodyKind.model && body.modelId.isNotEmpty
      ? switch (images) {
          CanvasModelSource source => source.resolveModel(body.modelId),
          _ => null,
        }
      : body.kind == BodyKind.mannequin
          ? HumanBody.instance.modelFor(modelDna ?? dna,
              drawnFace: drawnFace,
              preferHair: _styleHair(bodyStyle ?? style, modelDna ?? dna),
              limbs: _Look.of(bodyStyle ?? style).limbs,
              gloves: _Look.of(bodyStyle ?? style).gloves)
          : null;
  var outline = body.outline ? math.max(1.0, box.height * 0.006) : 0.0;
  // A sculpted body is lit and inked as its style draws: the style is the
  // look, as the drawn body's is.
  if (body.kind == BodyKind.mannequin) {
    var (ink, shading) = _styleInk(look, box);
    if (model != null) {
      var (origin, pieces) =
          model.pieces(rig, face, box, lift: pose.lift * rig.unit);
      if (!paintMeshesInked(canvas, origin, pieces, ink, shading: shading)) {
        paintMeshes(canvas, origin, pieces,
            shading: shading, outline: ink.outline, outlineColor: ink.ink);
      }
      if (drawnFace && dna.kind.person) {
        if (model.faceFrame(rig, face, box, lift: pose.lift * rig.unit) case var f?) {
          _Drawing(canvas, rig, dna, face, life, look: look).faceOn(
              f.eyeL, f.eyeR, f.base, f.top, f.mouth);
        }
      }
      return;
    }
    var lumps = mannequinPieces(rig, dna, face);
    if (!paintMeshesInked(canvas, rig.hips, lumps, ink, shading: shading)) {
      paintMeshes(canvas, rig.hips, lumps, shading: shading, outline: ink.outline);
    }
    return;
  }
  if (model != null) {
    var (origin, pieces) =
        model.pieces(rig, face, box, lift: pose.lift * rig.unit);
    // A toon model's own outline, at its own width, when it has one.
    var own = body.shading == ModelShading.toon && model.outlineWidth > 0
        ? math.max(1.0, model.outlineWidth * box.height / model.height)
        : 0.0;
    if (!paintMeshesInked(canvas, origin, pieces,
        _inkLook(body, box, math.max(outline, own),
            own > outline ? model.outlineColour : null),
        shading: body.shading)) {
      paintMeshes(canvas, origin, pieces,
          shading: body.shading,
          outline: math.max(outline, own),
          outlineColor: own > outline ? model.outlineColour : const Color(0xFF1A1A1A));
    }
    if (drawnFace && dna.kind.person) {
      if (model.faceFrame(rig, face, box, lift: pose.lift * rig.unit) case var f?) {
        _Drawing(canvas, rig, dna, face, life, look: look).faceOn(
            f.eyeL, f.eyeR, f.base, f.top, f.mouth);
      }
    }
    return;
  }
  var lumps = mannequinPieces(rig, dna, face);
  if (paintMeshesInked(canvas, rig.hips, lumps, _inkLook(body, box, outline, null),
      shading: body.shading)) {
    return;
  }
  paintMeshes(canvas, rig.hips, lumps, shading: body.shading, outline: outline);
}

/// _styleHair is the hair a sculpted body wears in [style] where none is
/// chosen: the cut that style draws people with.
String? _styleHair(CharacterStyle style, CharacterDna dna) {
  var female = dna.kind == CharacterType.woman || dna.kind == CharacterType.girl;
  var long = dna.hairStyle == HairStyle.long;
  if (dna.hairStyle == HairStyle.bald || dna.hairStyle == HairStyle.bun ||
      dna.hairStyle == HairStyle.curly) {
    return null;
  }
  return switch (style) {
    CharacterStyle.anime || CharacterStyle.chibi || CharacterStyle.shonen =>
      female ? (long ? "bangs" : "bobcut") : "anime",
    CharacterStyle.shojo => female ? (long ? "bangs" : "bob2") : "anime",
    CharacterStyle.webtoon => female ? (long ? "layered" : "bob2") : "swept",
    CharacterStyle.comic => female ? (long ? "wavy" : "bob1") : "short2",
    CharacterStyle.kawaii => female ? (long ? "cloud" : "bobcut") : "messy",
    _ => null,
  };
}

/// _styleInk is how a style lights and inks a body in 3D: its line as
/// thick and in the colour it draws one, cel bands where it shades in
/// bands -- none at all where it draws flat colour -- soft light where it
/// shades softly, and its shadows tinted as its drawings' are.
(InkLook, ModelShading) _styleInk(_Look look, Rect box) {
  var line = look.line;
  var soft = look.shading == _Shading.soft;
  var flat = look.shading == _Shading.flat;
  return (
    InkLook(
      cel: !soft,
      outline: line > 0 ? math.max(1.0, box.height * 0.0042 * line) : 0,
      inner: line > 0 ? (0.55 + 0.25 * math.min(line, 1.6)).clamp(0.0, 0.95) : 0,
      ink: look.ink ?? const Color(0xFF2A2024),
      // Flat colour: the light falls everywhere, so there is no shadow.
      shift: flat ? 2 : -0.12,
      toony: 0.94,
      rim: soft ? const Color(0x30FFFFFF) : const Color(0x38FFFFFF),
      shade: look.shadowTint == null
          ? null
          : Color.lerp(look.shadowTint, const Color(0xFFFFFFFF), 0.5),
      pattern: switch (look.shading) {
        _Shading.halftone => 1,
        _Shading.screentone => 2,
        _ => 0,
      },
    ),
    soft ? ModelShading.soft : ModelShading.toon,
  );
}

/// _inkLook is how the toon shader draws [body] in [box]: cel bands, an
/// outline and inked lines inside for toon; soft light, and ink only when
/// an outline is asked for, otherwise.
InkLook _inkLook(CharacterBody body, Rect box, double outline, Color? ink) {
  var toon = body.shading == ModelShading.toon;
  var line = outline > 0
      ? outline
      : toon
          ? math.max(1.0, box.height * 0.0035)
          : 0.0;
  return InkLook(
    cel: toon,
    outline: line,
    inner: toon ? 0.85 : (outline > 0 ? 0.45 : 0.0),
    ink: ink ?? const Color(0xFF2A2024),
    rim: toon ? const Color(0x40FFFFFF) : const Color(0x26FFFFFF),
  );
}

/// _greyscale takes the colour out, leaving how light each thing is, a
/// little harder: ink on paper.
const ColorFilter _greyscale = ColorFilter.matrix([
  0.36, 0.71, 0.12, 0, -20, //
  0.36, 0.71, 0.12, 0, -20, //
  0.36, 0.71, 0.12, 0, -20, //
  0, 0, 0, 1, 0,
]);

/// _wash is colour softened and lightened, as watercolour on paper is.
const ColorFilter _wash = ColorFilter.matrix([
  0.72, 0.18, 0.05, 0, 30, //
  0.1, 0.78, 0.07, 0, 30, //
  0.1, 0.15, 0.7, 0, 28, //
  0, 0, 0, 1, 0,
]);

/// _pastel is colour lifted towards white and softened: kawaii and shōjo.
const ColorFilter _pastel = ColorFilter.matrix([
  0.82, 0.06, 0.04, 0, 34, //
  0.05, 0.84, 0.05, 0, 32, //
  0.06, 0.06, 0.82, 0, 36, //
  0, 0, 0, 1, 0,
]);

/// _film is colour warmed and a little muted, as painted film cels are.
const ColorFilter _film = ColorFilter.matrix([
  0.9, 0.1, 0.02, 0, 10, //
  0.06, 0.88, 0.04, 0, 6, //
  0.04, 0.1, 0.78, 0, 0, //
  0, 0, 0, 1, 0,
]);

/// _Shading is how a style shades a shape: not at all, with a band of
/// shadow, with the shadow printed as dots, or lit softly as a rounded
/// thing is.
/// _Shading is how a style shades: flat colour, a cel band, dots of
/// halftone or screentone, a soft gradient -- or painted light, every shape
/// rounded and lit; see painted_light.dart.
enum _Shading { flat, cel, halftone, screentone, soft, painted }

/// _Eyes is how a style draws an eye.
enum _Eyes {
  /// round is the plain cartoon's: white, iris, a highlight, a lid line.
  round,

  /// feature is a feature film's: an almond lifted at the outer corner, a
  /// big layered iris, a heavy upper lid ending in a flick, and a crease.
  feature,

  /// anime is a tall eye with a heavy upper lash line, a layered iris and
  /// two highlights.
  anime,

  /// shojo is bigger, sparkling, with long lashes.
  shojo,

  /// shonen is narrow and sharp, with a small iris.
  shonen,

  /// soft is a small eye that is nearly all iris, under a simple lid.
  soft,

  /// dot is a dark oval with a dot of light.
  dot,

  /// fine is a slim eye with a crease above it, as a webtoon draws it.
  fine,

  /// glossy is a big round eye with a deep shiny iris.
  glossy,

  /// real is an almond eye with a shaded iris, a lid and a crease.
  real,
  pie,
}

/// _Hair is how a style draws hair.
enum _Hair {
  plain,

  /// clumps is anime hair: a fringe of pointed locks and a ring of shine.
  clumps,

  /// spiky is clumps with spikes standing up off the crown.
  spiky,

  /// soft is smooth hair with one soft band of shine.
  soft,

  /// strands is smooth hair with fine strands drawn through it.
  strands,

  /// flowing is a feature film's hair: full at the crown, parted deep to
  /// one side with the fringe sweeping across the brow, and strands
  /// flowing out from the parting.
  flowing,
}

/// _Nose is how a style draws a nose seen from the front.
enum _Nose { shaped, tick, none, shaded, small }

/// _Look is how a style draws: its line, its shading, its eyes, its hair,
/// its nose, its limbs.
class _Look {
  /// line is how thick the outline is, against the usual; nought is none.
  final double line;

  /// ink is the outline's colour, or null for a shade of what it goes
  /// round.
  final Color? ink;
  final _Shading shading;

  /// shadowTint is the colour shadows lean towards, or null for darker.
  final Color? shadowTint;
  final _Eyes eyes;
  final _Hair hair;
  final _Nose nose;

  /// hatch is blush drawn as short lines across the cheeks, as anime does.
  final bool hatch;

  /// limbs is how thick arms and legs are, against the usual.
  final double limbs;

  /// hose is limbs drawn as one bending curve each, with no elbow or knee.
  final bool hose;

  /// gloves is white cartoon gloves on the hands.
  final bool gloves;

  /// heart is a heart-shaped face: a full brow and cheekbones tapering to
  /// a narrow, softly pointed chin, as a feature film draws its heroines.
  final bool heart;

  const _Look(
      {this.line = 1,
      this.ink,
      this.shading = _Shading.flat,
      this.shadowTint,
      this.eyes = _Eyes.round,
      this.hair = _Hair.plain,
      this.nose = _Nose.shaped,
      this.hatch = false,
      this.limbs = 1,
      this.hose = false,
      this.gloves = false,
      this.heart = false});

  static const _black = Color(0xFF151515);

  static _Look of(CharacterStyle style) => switch (style) {
        CharacterStyle.illustrated => const _Look(
            line: 0.7,
            ink: Color(0xFF7A5040),
            shading: _Shading.painted,
            eyes: _Eyes.feature,
            hair: _Hair.flowing,
            nose: _Nose.small,
            limbs: 0.92,
            heart: true),
        CharacterStyle.featureCartoon => const _Look(
            shading: _Shading.cel, eyes: _Eyes.feature, hair: _Hair.soft),
        CharacterStyle.anime => const _Look(
            line: 0.75,
            shading: _Shading.cel,
            shadowTint: Color(0xFF6A4A8A),
            eyes: _Eyes.anime,
            hair: _Hair.clumps,
            nose: _Nose.tick,
            hatch: true),
        CharacterStyle.shojo => const _Look(
            line: 0.6,
            shading: _Shading.cel,
            shadowTint: Color(0xFFB06A9A),
            eyes: _Eyes.shojo,
            hair: _Hair.clumps,
            nose: _Nose.tick,
            hatch: true,
            limbs: 0.85),
        CharacterStyle.shonen => const _Look(
            line: 1.3,
            ink: Color(0xFF1E1A22),
            shading: _Shading.cel,
            shadowTint: Color(0xFF3A3A6A),
            eyes: _Eyes.shonen,
            hair: _Hair.spiky,
            nose: _Nose.tick),
        CharacterStyle.softFilm => const _Look(
            line: 0.85,
            ink: Color(0xFF6A4A36),
            shading: _Shading.cel,
            shadowTint: Color(0xFF8A6A5A),
            eyes: _Eyes.soft,
            hair: _Hair.soft,
            nose: _Nose.small),
        CharacterStyle.chibi => const _Look(
            shading: _Shading.cel,
            shadowTint: Color(0xFF7A5A9A),
            eyes: _Eyes.shojo,
            hair: _Hair.clumps,
            nose: _Nose.none,
            hatch: true),
        CharacterStyle.webtoon => const _Look(
            line: 0.5,
            shading: _Shading.soft,
            eyes: _Eyes.fine,
            hair: _Hair.strands,
            nose: _Nose.tick,
            limbs: 0.9),
        CharacterStyle.manga => const _Look(
            line: 1.3,
            ink: _black,
            shading: _Shading.screentone,
            eyes: _Eyes.anime,
            hair: _Hair.clumps,
            nose: _Nose.tick),
        CharacterStyle.feature3d => const _Look(
            line: 0,
            shading: _Shading.soft,
            eyes: _Eyes.glossy,
            hair: _Hair.soft,
            nose: _Nose.shaded),
        CharacterStyle.tvFlat =>
          const _Look(line: 2.2, ink: _black, eyes: _Eyes.dot, nose: _Nose.small),
        CharacterStyle.vectorFlat => const _Look(
            line: 0,
            shading: _Shading.cel,
            shadowTint: Color(0xFF4A3A7A),
            eyes: _Eyes.dot,
            hair: _Hair.soft,
            nose: _Nose.small),
        CharacterStyle.kawaii => const _Look(
            line: 1.1,
            ink: Color(0xFF5A4448),
            eyes: _Eyes.dot,
            hair: _Hair.soft,
            nose: _Nose.none,
            hatch: true),
        CharacterStyle.indie => const _Look(
            line: 1.5,
            ink: Color(0xFF221A18),
            eyes: _Eyes.real,
            hair: _Hair.strands,
            nose: _Nose.shaped),
        CharacterStyle.rubberHose => const _Look(
            line: 2,
            ink: _black,
            eyes: _Eyes.pie,
            limbs: 0.5,
            hose: true,
            gloves: true),
        CharacterStyle.painterly => const _Look(
            line: 0.35,
            shading: _Shading.soft,
            eyes: _Eyes.real,
            hair: _Hair.strands,
            nose: _Nose.shaded),
        CharacterStyle.comic => const _Look(
            line: 1.8,
            ink: _black,
            shading: _Shading.halftone,
            eyes: _Eyes.real,
            hair: _Hair.strands),
        CharacterStyle.storybook =>
          const _Look(line: 0.7, ink: Color(0xFF6B5B4B), hair: _Hair.soft),
        CharacterStyle.clay =>
          const _Look(line: 0, shading: _Shading.soft, eyes: _Eyes.dot),
        CharacterStyle.paperCutout => const _Look(line: 0.5),
        CharacterStyle.pixel => const _Look(line: 1.2, ink: _black),
        CharacterStyle.noir => const _Look(line: 0),
      };
}

class _Drawing {
  /// canvas is what is drawn on -- swapped, a shape at a time, for the
  /// painted light's buffers as it lays shapes into them; see _solid.
  Canvas canvas;
  final CharacterRig rig;
  final CharacterDna dna;
  final CharacterFace face;
  final LifeAt life;

  /// bare is the body without its clothes -- the editor's bare view.
  final bool bare;

  final _Look look;

  /// images is where a garment's picture print comes from.
  final CanvasImageSource? images;

  _Drawing(this.canvas, this.rig, this.dna, this.face, this.life,
      {this.bare = false,
      this.look = const _Look(),
      this.images,
      this.painted,
      this.hidden = const {},
      this.faceRig = FaceRig.none,
      this.replaced = const {},
      this.layers = LayerView.all,
      this.pass = _Pass.all})
      : _real = canvas;

  /// replaced is what it wears that is taken apart on this panel, and drawn
  /// by its shapes instead -- see CharacterDrawing.replaces.
  final Set<Garment> replaced;

  /// faceRig is the face as it is set on the panel drawn -- see
  /// character_face_rig.dart.
  final FaceRig faceRig;

  /// layers is which layers are drawn -- see character_layers.dart -- and
  /// pass, for a layer soloed, which half of the two drawings this is.
  final LayerView layers;
  final _Pass pass;

  /// _real is the canvas the figure is drawn onto; _sink one that keeps
  /// nothing, for what is left out. A layer is drawn onto one or the other
  /// as it is shown, whatever layer it is drawn inside.
  final Canvas _real;
  late final Canvas _sink = Canvas(ui.PictureRecorder());
  final List<String> _layerStack = [];

  bool _drawnHere(String layer) {
    if (!layers.shows(layer)) return false;
    return switch (pass) {
      _Pass.all => true,
      _Pass.others => layer != layers.solo,
      _Pass.solo => layer == layers.solo,
    };
  }

  /// _in draws [draw] as layer [layer]: onto the figure if it is shown,
  /// into nothing if not -- carrying over where the canvas is placed, so a
  /// layer inside one left out is drawn where it would have been.
  void _in(String layer, void Function() draw) {
    if (_layerStack.isNotEmpty && _layerStack.last == layer) return draw();
    var from = canvas;
    var to = _drawnHere(layer) ? _real : _sink;
    var switched = !identical(from, to);
    if (switched) _carry(from, to);
    canvas = to;
    _layerStack.add(layer);
    if (to case CaptureCanvas c) c.layer = layer;
    try {
      draw();
    } finally {
      _layerStack.removeLast();
      if (switched) to.restore();
      canvas = from;
      if (from case CaptureCanvas c) {
        c.layer = _layerStack.isEmpty ? null : _layerStack.last;
      }
    }
  }

  void _inBody(BodyLayer layer, void Function() draw) => _in(layer.name, draw);

  /// _inGarment draws [draw] as garment [g]'s layer.
  void _inGarment(Garment g, void Function() draw) =>
      _in(garmentLayer(dna.wardrobe.indexOf(g)), draw);

  /// _carry places [to] as [from] is placed, from a save to restore after.
  static void _carry(Canvas from, Canvas to) {
    to.save();
    var a = from.getTransform(), b = to.getTransform();
    // b⁻¹ · a, as two-dimensional affine maps.
    var det = b[0] * b[5] - b[1] * b[4];
    if (det.abs() < 1e-12) return;
    var i0 = b[5] / det, i1 = -b[1] / det, i4 = -b[4] / det, i5 = b[0] / det;
    var i12 = -(i0 * b[12] + i4 * b[13]), i13 = -(i1 * b[12] + i5 * b[13]);
    var m = Float64List(16);
    m[0] = i0 * a[0] + i4 * a[1];
    m[1] = i1 * a[0] + i5 * a[1];
    m[4] = i0 * a[4] + i4 * a[5];
    m[5] = i1 * a[4] + i5 * a[5];
    m[12] = i0 * a[12] + i4 * a[13] + i12;
    m[13] = i1 * a[12] + i5 * a[13] + i13;
    m[10] = 1;
    m[15] = 1;
    to.transform(m);
  }

  /// _setAbout sets the canvas for a feature drawn about [pivot], in the
  /// head's own space, as [a] says: moved, turned and sized about it.
  void _setAbout(FaceAdjust a, Offset pivot) {
    if (a.isRest) return;
    canvas.translate(pivot.dx + a.dx * u, pivot.dy + a.dy * u);
    if (a.turn != 0) canvas.rotate(a.turn * math.pi / 180);
    if (a.scale != 1) canvas.scale(math.max(a.scale, 1e-4));
    canvas.translate(-pivot.dx, -pivot.dy);
  }

  /// _setFeature draws [what], the face's [p], about [pivot] as it is set.
  void _setFeature(FacePoint p, Offset pivot, void Function() what) {
    var a = faceRig[p];
    if (a.isRest) return what();
    canvas.save();
    _setAbout(a, pivot);
    what();
    canvas.restore();
  }

  /// noseAt, browAt and the mouth's place are where each feature is set
  /// about -- see facePivots.
  Offset _noseAt(double w) =>
      Offset(_across(0, w), u * 0.12 + _nodShift - _a(Look.noseHeight) * u * 0.05);
  Offset _browAt(Offset eye) => Offset(eye.dx, eye.dy - u * 0.16);
  Offset _mouthPlace(double w) =>
      _mouthAt ??
      Offset(_across(0, w * 0.88), u * 0.3 + _nodShift - _a(Look.mouthHeight) * u * 0.05);

  /// _eyeKit is how much wider and taller the style draws its eyes, and
  /// how much lower, in head units.
  (double, double, double) get _eyeKit => switch (look.eyes) {
        _Eyes.anime => (1.2, 1.45, 0.03),
        _Eyes.shojo => (1.35, 1.6, 0.04),
        _Eyes.shonen => (1.25, 0.85, 0.0),
        _Eyes.soft => (0.8, 0.95, 0.0),
        _Eyes.dot => (0.6, 0.75, 0.0),
        _Eyes.fine => (1.15, 0.75, 0.0),
        _Eyes.glossy => (1.3, 1.35, 0.02),
        _Eyes.real => (1.05, 0.72, 0.0),
        _Eyes.feature => (1.2, 0.92, 0.01),
        _ => (1.0, 1.0, 0.0),
      };

  /// _facePivots is where each feature the face shows is set about, in the
  /// head's own space, before it is set: what the face rig's handles are
  /// drawn from. The corners of the mouth are where the resting mouth's
  /// are, before the mouth itself is set.
  Map<FacePoint, Offset> _facePivots() {
    if (facing <= -0.15 || dna.species.animal) return const {};
    var w = rig.headRadii.width;
    var eyeY = u * 0.06 + _nodShift - _a(Look.eyeHeight) * u * 0.06 + u * _eyeKit.$3;
    var out = <FacePoint, Offset>{};
    if (dna.eyeCount != 1) {
      for (var side in [-1.0, 1.0]) {
        var phi = side * 0.42 * (1 + 0.22 * _a(Look.eyeSpacing));
        if (_toward(phi) < 0.12) continue;
        var c = Offset(_across(phi, w), eyeY);
        out[side > 0 ? FacePoint.eyeL : FacePoint.eyeR] = c;
        out[side > 0 ? FacePoint.browL : FacePoint.browR] = _browAt(c);
      }
    }
    out[FacePoint.nose] = _noseAt(w);
    var mouth = _mouthPlace(w);
    out[FacePoint.mouth] = mouth;
    var smile = (face[FaceControl.smile] + 0.4 * _a(Look.corners)).clamp(-1.0, 1.0);
    var half = u * 0.1 * (1 + 0.4 * face[FaceControl.wide].clamp(-0.6, 1.0));
    var across = (0.35 + 0.65 * facing.clamp(0.0, 1.0)) * (1 + 0.3 * _a(Look.mouthWidth));
    out[FacePoint.cornerR] = mouth + Offset(-half * across, -smile * u * 0.05);
    out[FacePoint.cornerL] = mouth + Offset(half * across, -smile * u * 0.05);
    return out;
  }

  /// _mouthAcross is how far across the mouth is drawn, turned as it is.
  double _mouthAcross = 1;

  /// hidden is where the generated drawing is left out, for a drawing by
  /// hand to take its place. See CharacterDrawing.hidden.
  final Set<CharacterRegion> hidden;

  bool _shows(CharacterRegion r) => !hidden.contains(r);

  CharacterRegion _regionOf(CharacterLimb limb) => switch (limb) {
        CharacterLimb.armL => CharacterRegion.armL,
        CharacterLimb.armR => CharacterRegion.armR,
        CharacterLimb.legL => CharacterRegion.legL,
        CharacterLimb.legR => CharacterRegion.legR,
      };

  /// painted is where, for painted light, each solid shape is laid down as
  /// well as drawn: drawn then as flat colour, with no line, for the shader
  /// to light and line.
  final PaintedBuffers? painted;

  /// _materialOf is what a shape of [colour] is made of.
  PaintedMaterial _materialOf(Color colour) {
    if (colour == dna.skin) return PaintedMaterial.skin;
    if (colour == dna.hair || colour == dna.hair2) return PaintedMaterial.hair;
    if (colour == dna.eyes) return PaintedMaterial.flat;
    return PaintedMaterial.cloth;
  }

  /// _onModel is the turn of a 3D head the face is being drawn on -- see
  /// faceOn -- whose own pose already nods it. Null for a drawn head.
  double? _onModel;

  /// _eyesAt and _mouthAt are where a 3D head's eyes and mouth are, across
  /// the face drawn on it -- see faceOn -- in place of where a ball would
  /// put them: the far eye on a turned head stays on its face.
  Map<double, double>? _eyesAt;
  Offset? _mouthAt;

  /// faceOn draws the face alone on a head in 3D, where the eyes [eyeL]
  /// and [eyeR], the bottom of the skull [base] and the middle of the head
  /// [top] are on the page (x, y and nearness, in pixels): the same
  /// features as on a drawn head, on a ball as big as the eyes are far
  /// apart, turned, tipped and nodded as that head is -- its eyes and its
  /// [mouth], where that is known, put where the head's are.
  void faceOn(List<double> eyeL, List<double> eyeR, List<double> base,
      List<double> top, List<double>? mouth) {
    List<double> minus(List<double> a, List<double> b) =>
        [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
    double len(List<double> a) => math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
    var across = minus(eyeL, eyeR);
    var gap = len(across);
    // Up the face: from the mouth to the eyes, square to the line between
    // them, where the mouth is known -- the head's bone leans forward of
    // the face -- and up the head otherwise.
    var mid3 = [for (var c = 0; c < 3; c++) (eyeL[c] + eyeR[c]) / 2];
    var up = mouth == null ? minus(top, base) : minus(mid3, mouth);
    if (gap < 1e-6) return;
    var along = (up[0] * across[0] + up[1] * across[1] + up[2] * across[2]) / (gap * gap);
    up = [for (var c = 0; c < 3; c++) up[c] - across[c] * along];
    var ul = len(up);
    if (ul < 1e-6) return;
    up = [for (var c in up) c / ul];
    // Which way the face looks: square to the eyes and the head's length.
    var f = [
      up[1] * across[2] - up[2] * across[1],
      up[2] * across[0] - up[0] * across[2],
      up[0] * across[1] - up[1] * across[0],
    ];
    var fl = len(f);
    if (fl < 1e-6) return;
    f = [for (var c in f) c / fl];
    _onModel = math.atan2(-f[0], f[2]);
    if (facing < -0.15) return;
    // How the head leans on the page, and how far it nods away.
    var roll = math.atan2(up[0], -up[1]);
    var nod = math.sqrt(up[0] * up[0] + up[1] * up[1]).clamp(0.25, 1.0);
    // The drawn head's ball, as big as puts its eyes where these are.
    var w = rig.headRadii.width;
    var phi = 0.42 * (1 + 0.22 * _a(Look.eyeSpacing));
    var ball = gap / (2 * math.sin(phi));
    var k = ball / w;
    // The drawn eyes' middle, where the model's is.
    var eyeY = u * 0.06 - _a(Look.eyeHeight) * u * 0.06;
    var mid = Offset(-w * math.sin(yaw) * math.cos(phi), eyeY);
    var cr = math.cos(roll), sr = math.sin(roll);
    var placed = Offset(mid.dx * k, mid.dy * k * nod);
    var turned = Offset(placed.dx * cr - placed.dy * sr, placed.dx * sr + placed.dy * cr);
    var centre = Offset((eyeL[0] + eyeR[0]) / 2, (eyeL[1] + eyeR[1]) / 2) - turned;
    // Where the eyes and the mouth are on the face, back in the drawn
    // head's own measure: the face keeps its proportions, and its mouth
    // goes where the head's is.
    Offset local(List<double> p) {
      var d = Offset(p[0], p[1]) - centre;
      return Offset((d.dx * cr + d.dy * sr) / k, (-d.dx * sr + d.dy * cr) / (k * nod));
    }

    var l = local(eyeL).dx, r = local(eyeR).dx;
    _eyesAt = {-1.0: math.min(l, r), 1.0: math.max(l, r)};
    if (mouth != null) _mouthAt = local(mouth);
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(roll);
    canvas.scale(k, k * nod);
    _face(w, onModel: true);
    canvas.restore();
  }

  double get u => rig.unit;

  /// _a is how far the Appearance control [l] is set: nought at rest.
  double _a(Look l) => rig.look[l];

  /// _seed is a fixed number for [k], so freckles land in the same places
  /// in every frame and every export.
  double _seed(int k) {
    var h = (k * 0x9E3779B1 + 0x632BE5AB) & 0xFFFFFFFF;
    h = ((h ^ (h >> 15)) * 0x85EBCA6B) & 0xFFFFFFFF;
    h = ((h ^ (h >> 13)) * 0xC2B2AE35) & 0xFFFFFFFF;
    return (h ^ (h >> 16)) / 0xFFFFFFFF;
  }

  /// edge is how thick every outline is.
  double get edge => math.max(0.6, u * 0.022) * look.line;

  /// lined is whether outlines are drawn at all.
  bool get lined => look.line > 0;

  /// armWidth and legWidth are how thick the limbs are drawn, in this style.
  double get armWidth => rig.limbWidth * look.limbs;
  double get legWidth => rig.legWidth * look.limbs;

  /// _inkFor is the outline round [colour].
  Color _inkFor(Color colour) => look.ink ?? _shade(colour);

  /// _solid draws something in [colour] by way of [draw], shaded as the
  /// style shades: a shadow on the side away from the light, which is above
  /// and to the left -- a band of darker colour, or dots.
  void _solid(Rect bounds, Color colour, void Function(Paint) draw) {
    var base = Paint()..color = colour;
    if (painted case var buffers? when !identical(canvas, _sink)) {
      // Laid into the light's buffers, drawing on each in turn, and drawn
      // as flat colour for it to light.
      var main = canvas;
      buffers.add(main.getTransform(), bounds, _materialOf(colour), u * 0.11,
          (onto, p) {
        canvas = onto;
        draw(p);
        canvas = main;
      });
      canvas = main;
      draw(base);
      return;
    }
    if (look.shading == _Shading.flat || look.shading == _Shading.painted) {
      draw(base);
      return;
    }
    var room = bounds.inflate(u * 0.3);
    canvas.saveLayer(room, Paint());
    draw(base);
    if (look.shading == _Shading.soft) {
      // Lit from above on the left: lighter there, darker away from it,
      // and a little light caught on the far edge.
      var r = math.max(bounds.width, bounds.height);
      canvas.drawRect(
          room,
          Paint()
            ..blendMode = BlendMode.srcATop
            ..shader = ui.Gradient.radial(
                bounds.topLeft + Offset(bounds.width * 0.3, bounds.height * 0.25),
                r * 1.05,
                [
                  const Color(0x33FFFFFF),
                  const Color(0x00FFFFFF),
                  Color.lerp(colour, const Color(0xFF1A1030), 0.55)!
                      .withValues(alpha: 0.42),
                ],
                const [0, 0.45, 1]));
      canvas.restore();
      return;
    }
    var shadow = look.shadowTint == null
        ? Color.lerp(colour, const Color(0xFF000000), 0.24)!
        : Color.lerp(colour, look.shadowTint, 0.3)!;
    switch (look.shading) {
      case _Shading.cel:
        canvas.drawRect(room,
            Paint()
              ..color = shadow
              ..blendMode = BlendMode.srcATop);
      case _Shading.halftone || _Shading.screentone:
        var tone = look.shading == _Shading.screentone;
        var dot = Paint()
          ..color = tone ? const Color(0x99000000) : const Color(0xCC151515)
          ..blendMode = BlendMode.srcATop;
        var step = u * (tone ? 0.045 : 0.07);
        var r = step * (tone ? 0.22 : 0.3);
        var row = 0;
        for (var y = room.top; y < room.bottom; y += step, row++) {
          for (var x = room.left + (row.isOdd ? step / 2 : 0);
              x < room.right;
              x += step) {
            canvas.drawCircle(Offset(x, y), r, dot);
          }
        }
      case _Shading.flat || _Shading.soft || _Shading.painted:
        break;
    }
    // The lit part: the same thing again, moved towards the light, in its
    // own colour -- what is left showing of the shadow is a crescent on the
    // far side.
    canvas.save();
    var d = u * 0.07;
    canvas.translate(-d, -d * 0.6);
    draw(Paint()
      ..color = colour
      ..blendMode = BlendMode.srcATop);
    canvas.restore();
    canvas.restore();
  }

  /// _outline edges [path] as the style edges things.
  void _outline(Path path, Color colour) {
    // Painted light draws its own line.
    if (!lined || painted != null) return;
    canvas.drawPath(path, _edgePaint(colour));
  }

  /// garments is what is drawn on the body, innermost first: nothing in
  /// the bare view, and not a garment drawn by hand alone -- see
  /// Garment.drawnOnly.
  late final List<Garment> garments = bare
      ? const []
      : [
          for (var g in dna.worn)
            if (!g.drawnOnly && !replaced.contains(g)) g
        ];

  Iterable<(int, Garment)> _wearing(bool Function(Garment) which) sync* {
    for (var (i, g) in garments.indexed) {
      if (which(g)) yield (i, g);
    }
  }

  /// bodyFacing is how much of the body's front is towards the reader.
  double get bodyFacing => math.cos(rig.yaw * math.pi / 180);

  void draw() {
    // Long hair hangs behind the head, until the head turns away and it is
    // the thing in front -- see _head.
    var head = _shows(CharacterRegion.head);
    if (head && _hangingHair && facing >= -0.3) {
      _inBody(BodyLayer.hairBack, () => _inHead(_backHair));
    }
    // A cape hangs behind the body, until the body turns away from the
    // reader and it is the thing in front.
    if (bodyFacing >= -0.2) _capes();
    // A tail and wings grow from the back: behind the body, until the body
    // turns away from the reader.
    if (bodyFacing >= -0.2) {
      _inBody(BodyLayer.extras, () {
        _wings();
        _tail();
      });
    }
    // An arm turned away goes behind the body, an arm towards the reader in
    // front of it. Facing the reader both are a hair in front.
    var near = -u * 0.01;
    if (_oneSkin) {
      // A person's skin is one shape -- neck, body and legs -- with one
      // line round it, so nothing joins at a seam.
      _arms(far: true, near: near);
      _bodySkin();
      _legs();
      if (_shows(CharacterRegion.torso)) {
        _skirts();
        _inBody(BodyLayer.torso, _torso);
      }
    } else {
      _legs();
      _skirts();
      _arms(far: true, near: near);
      _inBody(BodyLayer.neck, _neck);
      _inBody(BodyLayer.torso, _torso);
    }
    if (_shows(CharacterRegion.torso)) _neckwear();
    if (head) _inBody(BodyLayer.hairFront, _frontHair);
    _arms(far: false, near: near);
    if (bodyFacing < -0.2) {
      _capes();
      _inBody(BodyLayer.extras, () {
        _wings();
        _tail();
      });
    }
    if (head) _inBody(BodyLayer.head, () => _inHead(_head));
  }

  // ---- the body ----

  /// _oneSkin is whether the body is drawn as one skin -- a person's, with
  /// joints, not a creature's or a rubber hose's.
  bool get _oneSkin =>
      !dna.fourLegs &&
      !dna.species.legless &&
      dna.species != Species.bird &&
      !look.hose;

  /// _bodySkin is the neck, the body and both legs as one shape.
  void _bodySkin() {
    var parts = <(BodyLayer, Path)>[
      if (_shows(CharacterRegion.torso)) ...[
        (BodyLayer.torso, _torsoPath(skin: true)),
        (BodyLayer.neck, _neckPath()),
      ],
      for (var limb in [CharacterLimb.legL, CharacterLimb.legR])
        if (_shows(_regionOf(limb)))
          (_legLayer(limb), _limbShape(_along(limb, 0, 1), legWidth, leg: true, limb: limb)),
    ];
    if (parts.isEmpty) return;
    // Each part its own where a layer is picked out -- hidden or soloed --
    // so one can go without the rest.
    if (!layers.isAll) {
      for (var (layer, path) in parts) {
        _inBody(layer, () => _fill(path, dna.skin));
      }
      return;
    }
    var skin = parts.first.$2;
    for (var (_, p) in parts.skip(1)) {
      skin = Path.combine(PathOperation.union, skin, p);
    }
    _inBody(BodyLayer.torso, () => _fill(skin, dna.skin));
  }

  BodyLayer _legLayer(CharacterLimb limb) =>
      limb == CharacterLimb.legL ? BodyLayer.legL : BodyLayer.legR;
  BodyLayer _footLayer(CharacterLimb limb) =>
      limb == CharacterLimb.legL ? BodyLayer.footL : BodyLayer.footR;
  BodyLayer _armLayer(CharacterLimb limb) =>
      limb == CharacterLimb.armL ? BodyLayer.armL : BodyLayer.armR;
  BodyLayer _handLayer(CharacterLimb limb) =>
      limb == CharacterLimb.armL ? BodyLayer.handL : BodyLayer.handR;

  double get _leg => rig.thigh + rig.shin;

  /// _along is the stretch of [limb] from [from] to [to] of its length,
  /// as the joints it passes through.
  /// _points is [limb]'s points as they are reshaped -- see
  /// character_rig_points.dart -- or null where it is as it was made.
  List<PlacedRigPoint>? _points(CharacterLimb limb) => _placed.putIfAbsent(
      limb,
      () => dna.rigPoints.edited(limb.name)
          ? placedRigPoints(rig, limb, dna.rigPoints)
          : null);
  final Map<CharacterLimb, List<PlacedRigPoint>?> _placed = {};

  /// _curve is the line down the middle of a reshaped [limb], finely, each
  /// step with how far down the limb it is: through its points, smoothly
  /// along each bone and turning at the joint between as it always has.
  List<(double, Offset)>? _curve(CharacterLimb limb) => _curves.putIfAbsent(limb, () {
        var pts = _points(limb);
        if (pts == null) return null;
        var line = <(double, Offset)>[(pts.first.t, pts.first.at)];
        // Bone by bone: its joints and the points between.
        var start = 0;
        for (var i = 1; i < pts.length; i++) {
          if (!pts[i].point.isJoint) continue;
          var run = pts.sublist(start, i + 1);
          for (var j = 0; j + 1 < run.length; j++) {
            var p0 = run[j].at, p1 = run[j + 1].at;
            // Square to the curve at the points between, and along the
            // bone at its joints.
            var m0 = j == 0 ? p1 - p0 : (p1 - run[j - 1].at) / 2;
            var m1 = j + 2 == run.length ? p1 - p0 : (run[j + 2].at - p0) / 2;
            const steps = 8;
            for (var k = 1; k <= steps; k++) {
              var x = k / steps;
              var x2 = x * x, x3 = x2 * x;
              var p = p0 * (2 * x3 - 3 * x2 + 1) +
                  m0 * (x3 - 2 * x2 + x) +
                  p1 * (-2 * x3 + 3 * x2) +
                  m1 * (x3 - x2);
              line.add((run[j].t + (run[j + 1].t - run[j].t) * x, p));
            }
          }
          start = i;
        }
        return line;
      });
  final Map<CharacterLimb, List<(double, Offset)>?> _curves = {};

  /// _end is where [limb] ends -- the wrist or the ankle -- and _beforeEnd
  /// the point before it, which says the way it ends.
  Offset _end(CharacterLimb limb) => _points(limb)?.last.at ?? rig.end(limb);
  Offset _beforeEnd(CharacterLimb limb) => switch (_points(limb)) {
        var pts? => pts[pts.length - 2].at,
        null => rig.middle(limb),
      };

  /// _profile is [of] of [limb]'s points at [t] down it, eased from one
  /// point to the next.
  double _profile(List<PlacedRigPoint> pts, double t, double Function(RigPoint) of) {
    for (var i = 0; i + 1 < pts.length; i++) {
      var p = pts[i], q = pts[i + 1];
      if (t <= q.t || i + 2 == pts.length) {
        var k = q.t == p.t ? 0.0 : ((t - p.t) / (q.t - p.t)).clamp(0.0, 1.0);
        k = k * k * (3 - 2 * k);
        return of(p.point) + (of(q.point) - of(p.point)) * k;
      }
    }
    return of(pts.last.point);
  }

  List<Offset> _along(CharacterLimb limb, double from, double to) {
    // Reshaped: through every point, curving through those between the
    // joints -- a bend, not a break.
    if (_curve(limb) case var line?) {
      Offset at(double t) {
        for (var i = 0; i + 1 < line.length; i++) {
          var (ta, a) = line[i];
          var (tb, b) = line[i + 1];
          if (t <= tb || i + 2 == line.length) {
            var k = tb == ta ? 0.0 : ((t - ta) / (tb - ta)).clamp(0.0, 1.0);
            return Offset.lerp(a, b, k)!;
          }
        }
        return line.last.$2;
      }

      var hi = math.max(from, to);
      return [
        at(from),
        for (var (t, p) in line)
          if (t > from + 1e-6 && t < hi - 1e-6) p,
        at(hi),
      ];
    }
    var a = rig.root(limb), b = rig.middle(limb), c = rig.end(limb);
    var (upper, lower) = rig.lengths(limb);
    var whole = upper + lower;
    Offset at(double t) {
      var d = t * whole;
      return d <= upper
          ? Offset.lerp(a, b, upper == 0 ? 0 : d / upper)!
          : Offset.lerp(b, c, lower == 0 ? 0 : (d - upper) / lower)!;
    }

    var split = upper / whole;
    return [
      at(from),
      if (from < split && to > split) b,
      at(math.max(from, to)),
    ];
  }

  void _legs() {
    if (dna.species.legless) return;
    // The far leg first, so the near one crosses in front of it.
    var legs = [CharacterLimb.legL, CharacterLimb.legR]
      ..sort((a, b) => rig.depths[a]!.compareTo(rig.depths[b]!));
    var seated = <(int, Garment)>[];
    for (var limb in legs) {
      if (!_shows(_regionOf(limb))) continue;
      if (dna.species == Species.bird) {
        // Thin legs and three toes, in the beak's colour.
        _inBody(_legLayer(limb), () {
          _stroke(_along(limb, 0.45, 1), legWidth * 0.32, dna.fur2);
          _toes(limb);
        });
        continue;
      }
      // The leg's skin is drawn already, with the body's, as one person.
      if (!_oneSkin) {
        _inBody(_legLayer(limb),
            () => _limb(_along(limb, 0, 1), legWidth, dna.skin, leg: true, limb: limb));
      }
      // A bare foot, unless a shoe covers it all -- one drawn by hand as
      // well: what is drawn is the shoe.
      if (!_wearing((g) =>
                  g.kind.shape == GarmentShape.shoes && g.kind != GarmentKind.sandals)
              .isNotEmpty &&
          !(!bare &&
              dna.worn.any((g) =>
                  (g.drawnOnly && g.drawings.isNotEmpty || replaced.contains(g)) &&
                  g.kind.shape == GarmentShape.shoes))) {
        _inBody(_footLayer(limb), () => _foot(limb, dna.skin, bareFoot: true));
      }
      for (var (i, g) in _wearing((g) => g.kind.coversLegs)) {
        var from = g.kind.from, to = math.max(from + 0.02, g.lengthOr);
        _cloth(null, g, i,
            line: _along(limb, from, math.min(1, to)),
            width: legWidth * 1.12 * g.fitOr,
            part: limb.index,
            hem: true,
            span: (from, math.min(1, to)),
            leg: true,
            limb: limb);
        if (g.kind == GarmentKind.socks) {
          _inGarment(g, () => _foot(limb, g.color));
        }
        if (from == 0 && !dna.fourLegs && !seated.any((s) => s.$1 == i)) {
          seated.add((i, g));
        }
      }
      for (var (i, g) in _wearing((g) => g.kind.shape == GarmentShape.shoes)) {
        _inGarment(g, () => _shoe(limb, g, i));
      }
    }
    // The seat, so trousers meet between the legs instead of leaving the
    // background showing where two round-ended legs part.
    for (var (i, g) in seated) {
      var seat = Path()
        ..addRRect(RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: rig.hips + Offset(0, rig.legWidth * 0.2),
                width: (rig.hipL - rig.hipR).distance +
                    rig.legWidth * 1.12 * g.fitOr,
                height: rig.legWidth * 1.3),
            Radius.circular(rig.legWidth * 0.4)));
      _cloth(seat, g, i, part: 9);
    }
  }

  void _skirts() {
    // Nothing hangs from the waist of a body carried level.
    if (dna.fourLegs || dna.species.legless) return;
    // A fitted dress is one piece from the chest to the hem -- see _torso
    // -- not a top with a skirt under it.
    for (var (i, g) in _wearing((g) =>
        g.kind.shape == GarmentShape.skirt ||
        (g.kind.shape == GarmentShape.dress && !_fitted(g)))) {
      _cloth(_skirt(g.lengthOr * _leg, g.kind.flare, g.fitOr), g, i,
          part: 10, hem: true);
    }
  }

  /// _fitted is whether [g] is a dress cut close, with hardly a flare: one
  /// shape with the body, rather than a top and a skirt.
  bool _fitted(Garment g) =>
      g.kind.shape == GarmentShape.dress && g.kind.flare < 1.2;

  /// _skirt is a flared skirt from the waist, [length] long and [flare]
  /// times as wide at the hem as at the waist.
  Path _skirt(double length, double flare, double fit) {
    var top = rig.hips.dy - rig.legWidth * 0.3;
    var turned = bodyFacing.abs() + 0.75 * math.sin(rig.yaw * math.pi / 180).abs();
    var half = rig.hipHalf * 1.05 * fit * turned;
    var hem = top + length;
    var hemHalf = half * flare;
    var cx = rig.hips.dx;
    return Path()
      ..moveTo(cx - half, top)
      ..lineTo(cx + half, top)
      ..lineTo(cx + hemHalf, hem)
      ..quadraticBezierTo(cx, hem + length * 0.1, cx - hemHalf, hem)
      ..close();
  }

  /// _footBox is where a foot is drawn: its middle, how it tips, and how
  /// long it is -- longer side on, where it points the way the body faces.
  (Offset, double, double, double) _footBox(CharacterLimb limb) {
    var ankle = _end(limb);
    var shinTurn = turnOf(_end(limb) - _beforeEnd(limb));
    var drop = rig.below * CharacterRig.footDrop;
    var outward = limb.onLeft ? -1.0 : 1.0;
    var turned = rig.yaw * math.pi / 180;
    var across = math.cos(turned).abs(), side = math.sin(turned);
    var centre = ankle +
        Offset(outward * rig.legWidth * 0.22 * across - side * rig.legWidth * 0.55,
            drop * 0.45);
    // A foot keeps flat to the floor however the shin is turned, only
    // tipping a little with it, or a kick would point the sole at the sky.
    // As wide as the ankle makes it from the front, and longer from the
    // side: a slender ankle stands on a small foot.
    var slender = 0.75 + 0.25 * (1 + 0.45 * _a(Look.ankles));
    return (
      centre,
      shinTurn * 0.25 * math.pi / 180,
      rig.legWidth * (1.45 * across + 2.5 * side.abs()) * slender * (1 + 0.25 * _a(Look.feet)),
      drop
    );
  }

  void _foot(CharacterLimb limb, Color colour, {bool bareFoot = false}) {
    var (centre, tip, length, drop) = _footBox(limb);
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(tip);
    var scale = bareFoot ? 0.86 : 0.95;
    _fill(
        Path()
          ..addOval(Rect.fromCenter(
              center: Offset.zero,
              width: length * scale,
              height: drop * 1.0 * scale)),
        colour);
    canvas.restore();
  }

  void _shoe(CharacterLimb limb, Garment g, int i) {
    var (centre, tip, length, drop) = _footBox(limb);
    var colour = faded(g.color, g.condition.fade);
    if (g.kind == GarmentKind.boots) {
      // A boot comes up the shin as far as its length says.
      _cloth(null, g, i,
          line: _along(limb, 1 - g.lengthOr * 0.5, 1),
          width: legWidth * 1.2,
          part: 20 + limb.index,
          span: (1 - g.lengthOr * 0.5, 1),
          leg: true,
          limb: limb);
    }
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(tip);
    switch (g.kind) {
      case GarmentKind.sandals:
        // Straps over the foot, which shows between them.
        var strap = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = drop * 0.28
          ..color = colour;
        for (var x in [-0.18, 0.15]) {
          canvas.drawLine(Offset(length * x, -drop * 0.45),
              Offset(length * x, drop * 0.45), strap);
        }
        canvas.drawLine(Offset(-length * 0.45, drop * 0.48),
            Offset(length * 0.45, drop * 0.48), strap..strokeWidth = drop * 0.18);
      case GarmentKind.heels:
        // Where the ankle is in the foot's own frame, and how wide.
        var d = _end(limb) - centre;
        var c = math.cos(-tip), sn = math.sin(-tip);
        var ankle = Offset(d.dx * c - d.dy * sn, d.dx * sn + d.dy * c);
        _heel(length, drop, colour, ankle,
            legWidth * 0.52 * (1 + 0.45 * _a(Look.ankles)) / 2);
      default:
        var shoe = Path()
          ..addOval(Rect.fromCenter(
              center: Offset.zero, width: length, height: drop * 1.15));
        _fill(shoe, colour);
        if (g.kind == GarmentKind.trainers) {
          // The sole, in the second colour.
          canvas.save();
          canvas.clipPath(shoe);
          canvas.drawRect(
              Rect.fromLTWH(-length, drop * 0.22, length * 2, drop),
              Paint()..color = g.color2);
          canvas.restore();
          _outline(shoe, colour);
        }
    }
    canvas.restore();
  }

  /// _heel is a court shoe on a raised heel, about the foot's centre: from
  /// the front a pointed toe with the top of the foot showing above it,
  /// from the side the heel lifted on a stiletto and the sole sloping down
  /// to the toe.
  void _heel(double length, double drop, Color colour,
      [Offset ankle = Offset.zero, double ankleHalf = 0]) {
    var side = math.sin(rig.yaw * math.pi / 180);
    if (side.abs() < 0.5) {
      // From the front: the foot pointed down in the shoe, so the instep is
      // long, the toe a point below it, the vamp curving across, and the
      // stiletto showing behind on the outer side.
      var w = length * 0.42;
      // Under the ankle, the instep running down from it.
      canvas.translate(ankle.dx, 0);
      var top = ankle.dy;
      var half = ankleHalf > 0 ? ankleHalf : w * 0.28;
      var heel = Paint()
        ..color = _shade(colour, 0.12)
        ..strokeWidth = math.max(0.8, w * 0.1)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(w * 0.32, drop * 0.05), Offset(w * 0.3, drop * 1.0), heel);
      var instep = Path()
        ..moveTo(-half, top)
        ..quadraticBezierTo(-half * 1.25, drop * 0.25, -w * 0.18, drop * 0.75)
        ..lineTo(w * 0.18, drop * 0.75)
        ..quadraticBezierTo(half * 1.25, drop * 0.25, half, top)
        ..close();
      // Skin only: no line where it comes down out of the leg.
      _solid(instep.getBounds(), dna.skin, (p) => canvas.drawPath(instep, p));
      _fill(
          Path()
            ..moveTo(-w * 0.46, drop * 0.05)
            ..quadraticBezierTo(-w * 0.52, drop * 0.8, 0, drop * 1.12)
            ..quadraticBezierTo(w * 0.52, drop * 0.8, w * 0.46, drop * 0.05)
            ..quadraticBezierTo(0, drop * 0.55, -w * 0.46, drop * 0.05)
            ..close(),
          colour);
      return;
    }
    // The toe the way the body faces: the page's left as it turns.
    var dir = side > 0 ? -1.0 : 1.0;
    var l = length;
    _fill(
        Path()
          ..moveTo(-dir * l * 0.36, drop * 0.1)
          ..lineTo(-dir * l * 0.33, drop * 1.0)
          ..lineTo(-dir * l * 0.29, drop * 1.0)
          ..lineTo(-dir * l * 0.27, drop * 0.2)
          ..close(),
        colour);
    _fill(
        Path()
          ..moveTo(-dir * l * 0.42, -drop * 0.3)
          ..quadraticBezierTo(-dir * l * 0.46, drop * 0.15, -dir * l * 0.36, drop * 0.18)
          ..quadraticBezierTo(dir * l * 0.05, drop * 0.3, dir * l * 0.28, drop * 0.92)
          ..lineTo(dir * l * 0.56, drop * 0.95)
          ..quadraticBezierTo(dir * l * 0.6, drop * 0.7, dir * l * 0.45, drop * 0.55)
          ..quadraticBezierTo(dir * l * 0.15, drop * 0.25, -dir * l * 0.05, drop * 0.05)
          ..quadraticBezierTo(-dir * l * 0.25, -drop * 0.05, -dir * l * 0.42, -drop * 0.3)
          ..close(),
        colour);
  }

  /// _neck is slim under the head and flares into the shoulders, with the
  /// curve of the muscle running down to them.
  void _neck() => _fill(_neckPath(), dna.skin);

  Path _neckPath() {
    var top = rig.neck + Offset(0, -u * 0.1), base = rig.chest;
    var w = rig.limbWidth * 0.58 * (1 + 0.35 * _a(Look.neckWidth));
    var d = base - top;
    var len = d.distance;
    if (len < 1e-6) return Path();
    var along = d / len;
    var across = Offset(-along.dy, along.dx);
    var flare = w * 1.9;
    var path = Path()
      ..moveTo((top + across * w).dx, (top + across * w).dy);
    var lowR = base + across * flare + along * (u * 0.02);
    var lowL = base - across * flare + along * (u * 0.02);
    var midR = top + d * 0.7 + across * (w * 1.02);
    var midL = top + d * 0.7 - across * (w * 1.02);
    path
      ..quadraticBezierTo(midR.dx, midR.dy, lowR.dx, lowR.dy)
      ..lineTo(lowL.dx, lowL.dy)
      ..quadraticBezierTo(midL.dx, midL.dy, (top - across * w).dx, (top - across * w).dy)
      ..close();
    return path;
  }

  /// _torsoFrame is the body's own directions on the page: across it, up
  /// it, and how wide it is drawn turned the way it is.
  (Offset, Offset, double, double) get _torsoFrame {
    var spine = rig.bodyTurn * math.pi / 180;
    var across = Offset(math.cos(spine), math.sin(spine));
    var up = Offset(math.sin(spine), -math.cos(spine));
    // Turned, the body is an oval seen from round the side: as wide as it
    // is deep, side on -- about six tenths of its width -- and never wider
    // than straight on.
    var turned = rig.yaw * math.pi / 180;
    double seen(double deep) => math.sqrt(
        math.pow(math.cos(turned), 2) + math.pow(deep * math.sin(turned), 2));
    return (
      across,
      up,
      rig.shoulderHalf * seen(0.6),
      rig.hipHalf * 1.12 * seen(0.75)
    );
  }

  /// _torsoPath is the body, or a garment over it [fit] loose and coming
  /// [length] down: 1 is to the hips, more is on down the legs.
  ///
  /// The body is a stack of ovals -- the shoulders, the chest, the waist,
  /// the belly, the hips -- each as wide as it is and as deep in front and
  /// behind, so a full chest or a round belly stands out in front and
  /// nowhere else. Turned, the outline is where each oval reaches furthest
  /// to either side, so the body turns as a body does: no wider than it is,
  /// its front leading.
  Path _torsoPath(
      {double fit = 1,
      double length = 1,
      double from = 0,
      double? hang,
      bool skin = false}) {
    var spine = rig.bodyTurn * math.pi / 180;
    var across = Offset(math.cos(spine), math.sin(spine));
    var top = rig.chest, hips = rig.hips;
    var drop = hips - top;
    var turned = rig.yaw * math.pi / 180;
    var cy = math.cos(turned), sy = math.sin(turned);
    var chest = _a(Look.chest), waist = _a(Look.waist), belly = _a(Look.belly);
    var muscle = _a(Look.muscle);
    var s = rig.shoulderHalf, h = rig.hipHalf;
    // The shoulders come out to meet the arms, however thick they are.
    var shoulder = s * 0.86 + armWidth * 0.42;
    var deep = s * 0.5;
    // A woman's hips are about as wide as her shoulders, a man's narrower;
    // the waist between them is what makes the shape.
    var female = dna.kind == CharacterType.woman || dna.kind == CharacterType.girl;
    // The hips as wide as the tops of the thighs below them, so the line
    // runs on down the leg -- a little wider in a woman.
    var thighSpan = h * 0.55 + legWidth * (female ? 1.34 : 1.2) * 0.55;
    var hipsWide = thighSpan * (female ? 1.12 : 1.04) * (1 + 0.22 * _a(Look.hips));
    var waistWide = math.min(s * (female ? 0.68 : 0.78), hipsWide * (female ? 0.8 : 0.92)) *
        (1 + 0.18 * waist) *
        (1 + 0.1 * belly);
    // Each oval: how far down (0 the shoulders, 1 the hips), half its width,
    // and how deep it is in front and behind.
    var rings = <(double, double, double, double)>[
      (0.0, shoulder, deep * 0.55, deep * 0.6 * (1 + 0.2 * muscle)),
      (0.14, s * 0.9 * (1 + 0.04 * chest), deep * (0.95 + 0.25 * chest),
          deep * (0.85 + 0.15 * muscle)),
      (0.32, s * ((female ? 0.86 : 0.84) + 0.05 * chest), deep * (1.0 + 0.55 * chest),
          deep * (0.8 + 0.12 * muscle)),
      (0.58, waistWide, deep * (0.8 + 0.45 * belly), deep * 0.72),
      (0.8, waistWide + (hipsWide - waistWide) * 0.72, deep * (0.88 + 0.6 * belly),
          deep * 0.82),
      (1.0, hipsWide, deep * (0.9 + 0.25 * belly), deep * 0.95),
    ];
    // How far down it comes.
    var hemT = length <= 1
        ? 0.14 + (1.06 - 0.14) * length
        : 1.06 + (length - 1) * _leg / math.max(1e-6, drop.distance);
    // Past the hips: a coat hangs a little wider round both legs; [hang]
    // says how much wider, where a garment says.
    var flare = length > 1 ? (hang ?? 1 + 0.35 * math.min(1, length - 1)) : 1.0;
    var used = [
      for (var r in rings)
        if (r.$1 < hemT) r,
    ];
    // The last oval at the hem, between the ones either side of it -- or
    // past the hips, hanging round both legs.
    (double, double, double, double) at(double t) {
      if (t >= 1) {
        var last = rings.last;
        return (t, last.$2 * flare, last.$3, last.$4);
      }
      for (var i = 0; i + 1 < rings.length; i++) {
        var a = rings[i], b = rings[i + 1];
        if (t <= b.$1) {
          var f = (t - a.$1) / (b.$1 - a.$1);
          double mix(double x, double y) => x + (y - x) * f;
          return (t, mix(a.$2, b.$2), mix(a.$3, b.$3), mix(a.$4, b.$4));
        }
      }
      return rings.last;
    }

    if (from > 0) {
      used = [at(from), for (var r in used) if (r.$1 > from) r];
    }
    if (skin) {
      // The skin narrows from the hips into the tops of the thighs, so the
      // outline runs on down the legs without a ledge.
      var thighs = h * 0.55 + legWidth * 0.62;
      var hips = at(hemT);
      var thighDeep = legWidth * 0.62;
      used.add((
        hemT + 0.1,
        math.min(hips.$2, hips.$2 * 0.45 + thighs * 0.55),
        math.min(hips.$3, thighDeep * 1.1),
        math.min(hips.$4, thighDeep * 1.3),
      ));
    } else {
      used.add(at(hemT));
    }
    // Each oval's furthest left and right, seen as the body is turned:
    // across its width, and its front or back brought round towards the
    // reader's left as it turns.
    var left = <Offset>[], right = <Offset>[];
    for (var (t, w, front, back) in used) {
      w *= fit;
      front *= fit;
      back *= fit;
      var lo = double.infinity, hi = -double.infinity;
      for (var k = 0; k < 24; k++) {
        var phi = k * math.pi / 12;
        var x = w * math.cos(phi);
        var z = math.sin(phi) * (math.sin(phi) > 0 ? front : back);
        var seen = x * cy - z * sy;
        lo = math.min(lo, seen);
        hi = math.max(hi, seen);
      }
      var centre = top + drop * t;
      left.add(centre + across * lo);
      right.add(centre + across * hi);
    }
    // The hips' own tilt, which the lower body follows: the line across
    // the body turns from the shoulders' to the hips' on the way down.
    var hipLine = rig.hipR - rig.hipL;
    var hipAcross = hipLine.distance < 1e-6
        ? across
        : hipLine / hipLine.distance * (hipLine.dx * across.dx + hipLine.dy * across.dy >= 0 ? 1.0 : -1.0);
    for (var i = 0; i < used.length; i++) {
      var t = (used[i].$1 / 1.0).clamp(0.0, 1.0);
      var k = math.pow(t, 1.5).toDouble();
      var dir = Offset.lerp(across, hipAcross, k)!;
      var centre = top + drop * used[i].$1;
      // The point at each side, re-placed along the turned line.
      var lo = (left[i] - centre).dx * across.dx + (left[i] - centre).dy * across.dy;
      var hi = (right[i] - centre).dx * across.dx + (right[i] - centre).dy * across.dy;
      left[i] = centre + dir * lo;
      right[i] = centre + dir * hi;
    }
    // A smooth line through the points down each side.
    void through(Path path, List<Offset> pts) {
      for (var i = 0; i + 1 < pts.length; i++) {
        var p0 = pts[math.max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1];
        var p3 = pts[math.min(pts.length - 1, i + 2)];
        var c1 = p1 + (p2 - p0) / 6, c2 = p2 - (p3 - p1) / 6;
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
      }
    }

    var up = Offset(math.sin(spine), -math.cos(spine));
    var path = Path()..moveTo(right.first.dx, right.first.dy);
    through(path, right);
    // Across the bottom: round under the seat, or a hem straight across.
    var bottom = top + drop * (skin ? hemT + 0.1 : hemT);
    var dip = skin
        ? -drop.distance * 0.06
        : hemT <= 1.06 && length >= 1
            ? drop.distance * 0.05
            : drop.distance * 0.015;
    path.quadraticBezierTo(bottom.dx - up.dx * dip, bottom.dy - up.dy * dip,
        left.last.dx, left.last.dy);
    through(path, left.reversed.toList());
    // Over the top: the shoulders sloping up to the neck -- or, cut across
    // the chest, a line dipping a little at the middle.
    if (from > 0) {
      // A sweetheart: up over each side of the bust, dipping between.
      var edge = top + drop * from;
      var dip = edge - up * (u * 0.06);
      var lp = left.first, rp = right.first;
      Offset over(Offset side) =>
          Offset.lerp(side, dip, 0.5)! + up * (u * 0.12);
      path
        ..quadraticBezierTo(over(lp).dx, over(lp).dy, dip.dx, dip.dy)
        ..quadraticBezierTo(over(rp).dx, over(rp).dy, rp.dx, rp.dy);
      return path..close();
    }
    // The shoulders sloping up from where the arms join to the neck.
    var neck = rig.limbWidth * 0.62 + u * 0.08;
    var neckL = top + up * (u * 0.12) - across * neck;
    var neckR = top + up * (u * 0.12) + across * neck;
    var lp = left.first, rp = right.first;
    path
      ..quadraticBezierTo(lp.dx * 0.35 + neckL.dx * 0.65, lp.dy * 0.2 + neckL.dy * 0.8,
          neckL.dx, neckL.dy)
      ..lineTo(neckR.dx, neckR.dy)
      ..quadraticBezierTo(rp.dx * 0.35 + neckR.dx * 0.65, rp.dy * 0.2 + neckR.dy * 0.8,
          rp.dx, rp.dy);
    return path..close();
  }

  void _torso() {
    if (dna.species.legless) {
      _fishBody();
      return;
    }
    if (dna.species == Species.bird && !dna.fourLegs) {
      // A round body, lighter down the front.
      var egg = Path()
        ..addOval(Rect.fromCenter(
            center: Offset.lerp(rig.chest, rig.hips, 0.55)!,
            width: rig.shoulderHalf * 2.3,
            height: (rig.hips - rig.chest).distance * 1.5));
      _fill(egg, dna.skin);
      canvas.save();
      canvas.clipPath(egg);
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset.lerp(rig.chest, rig.hips, 0.65)! +
                  Offset(-math.sin(rig.yaw * math.pi / 180) * rig.shoulderHalf * 0.4, 0),
              width: rig.shoulderHalf * 1.3 * (0.4 + 0.6 * bodyFacing.abs()),
              height: (rig.hips - rig.chest).distance * 1.1),
          Paint()..color = Color.lerp(dna.skin, const Color(0xFFFFFFFF), 0.55)!);
      canvas.restore();
      return;
    }
    if (dna.fourLegs) {
      // A body carried level: a thick band from the hips to the shoulders,
      // with the lighter fur of the belly along its underside.
      var thick = rig.hipHalf * 2.1;
      _stroke([rig.hips, rig.chest], thick, dna.skin);
      // A top on a body carried level is a coat along it, from the
      // shoulders back as far as it is long.
      for (var (i, g) in _wearing((g) =>
          g.kind.shape == GarmentShape.torso ||
          g.kind.shape == GarmentShape.dress ||
          g.kind.shape == GarmentShape.cape)) {
        var back = Offset.lerp(rig.chest, rig.hips, math.min(1, g.lengthOr))!;
        _cloth(null, g, i,
            line: [rig.chest, back], width: thick * 1.06 * g.fitOr, part: 30);
      }
      if (bodyFacing.abs() < 0.8 && garments.every((g) => g.kind.shape != GarmentShape.torso)) {
        var belly = Offset(0, thick * 0.22);
        canvas.save();
        canvas.clipPath(_capsule([rig.hips, rig.chest], thick));
        _stroke([rig.hips + belly * 1.6, rig.chest + belly * 1.6], thick * 0.5,
            dna.fur2);
        canvas.restore();
      }
    } else if (!_oneSkin) {
      _fill(_torsoPath(), dna.skin);
    }
    for (var (i, g) in garments.indexed) {
      _inGarment(g, () {
      switch (g.kind.shape) {
        case GarmentShape.torso:
          _cloth(_torsoPath(fit: g.fitOr, length: g.lengthOr), g, i,
              part: 30, hem: true);
          _frontOf(g);
        case GarmentShape.dress:
          _cloth(
              _torsoPath(
                  fit: g.fitOr,
                  // Fitted, it goes on down over the hips as far as it is
                  // long, hugging them.
                  length: _fitted(g) ? 1 + g.lengthOr * 0.9 : 1,
                  from: g.kind.strapless ? 0.2 : 0,
                  hang: g.kind.flare),
              g,
              i,
              part: 30,
              hem: _fitted(g));
          _frontOf(g);
        case GarmentShape.legs when g.kind == GarmentKind.overalls:
          // The bib and the straps.
          var (across, up, half, low) = _torsoFrame;
          var top = Offset.lerp(rig.chest, rig.hips, 0.35)!;
          var bib = Path()
            ..moveTo(top.dx + across.dx * half * 0.5, top.dy)
            ..lineTo(top.dx - across.dx * half * 0.5, top.dy)
            ..lineTo(rig.hips.dx - low * g.fitOr, rig.hips.dy + rig.legWidth * 0.2)
            ..lineTo(rig.hips.dx + low * g.fitOr, rig.hips.dy + rig.legWidth * 0.2)
            ..close();
          _cloth(bib, g, i, part: 31);
          var strap = Paint()
            ..strokeWidth = rig.limbWidth * 0.35
            ..strokeCap = StrokeCap.round
            ..color = faded(g.color, g.condition.fade);
          for (var s in [-1.0, 1.0]) {
            canvas.drawLine(top + across * (s * half * 0.4),
                rig.chest + across * (s * half * 0.62), strap);
          }
        default:
          break;
      }
      // A shape of the garment's own, laid on over it.
      if (g.outline.length >= 3) _cloth(_outlinePath(g.outline), g, i, part: 32);
          });
    }
  }

  /// _outlinePath is a garment's own outline -- see Garment.outline -- on
  /// the body as it stands and turns: a smooth curve through its points.
  Path _outlinePath(List<Offset> points) {
    var (across, _, half, low) = _torsoFrame;
    Offset at(Offset p) {
      var width = half + (low - half) * p.dy.clamp(0.0, 1.0);
      return Offset.lerp(rig.chest, rig.hips, p.dy)! + across * (width * p.dx);
    }

    var pts = [for (var p in points) at(p)];
    var path = Path();
    Offset mid(int k) =>
        Offset.lerp(pts[k % pts.length], pts[(k + 1) % pts.length], 0.5)!;
    path.moveTo(mid(0).dx, mid(0).dy);
    for (var k = 1; k <= pts.length; k++) {
      var c = pts[k % pts.length], m = mid(k);
      path.quadraticBezierTo(c.dx, c.dy, m.dx, m.dy);
    }
    return path..close();
  }

  /// _frontOf is what is on the front of a garment -- a hood and pocket, a
  /// collar and buttons, a front left open -- going round with the body,
  /// and not there from behind, except a hood, which hangs down the back.
  void _frontOf(Garment g) => _inGarment(g, () => _frontOfIn(g));

  void _frontOfIn(Garment g) {
    var (across, up, half, _) = _torsoFrame;
    var colour = faded(g.color, g.condition.fade);
    var line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = edge * 1.4
      ..color = _shade(colour);
    var front = bodyFacing;
    if (front < 0.35) {
      if (g.kind == GarmentKind.hoodie && front < -0.3) {
        _fill(
            Path()
              ..addOval(Rect.fromCenter(
                  center: rig.chest - up * (u * 0.05),
                  width: half * 1.1,
                  height: u * 0.55)),
            Color.lerp(colour, const Color(0xFF000000), 0.12)!);
      }
      return;
    }
    var side = math.sin(rig.yaw * math.pi / 180);
    canvas.save();
    canvas.translate(-side * half * 0.4, 0);
    var collar = rig.chest + up * (u * 0.02);
    Offset off(double a, double b) => collar + across * (half * a) - up * (u * b);
    var hem = rig.chest.dy + (rig.hips.dy - rig.chest.dy) * g.lengthOr;
    switch (g.kind) {
      case GarmentKind.hoodie:
        canvas.drawPath(
            Path()
              ..moveTo(off(0.55, 0).dx, off(0.55, 0).dy)
              ..quadraticBezierTo(off(0, 0.35).dx, off(0, 0.35).dy,
                  off(-0.55, 0).dx, off(-0.55, 0).dy),
            line..strokeWidth = edge * 2.2);
        var pocket = Offset.lerp(rig.chest, rig.hips, 0.72)!;
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: pocket, width: half * 0.95, height: u * 0.3),
                Radius.circular(u * 0.08)),
            line..strokeWidth = edge * 1.2);
        var string = Paint()
          ..strokeWidth = edge * 1.3
          ..strokeCap = StrokeCap.round
          ..color = g.color2.withValues(alpha: 0.85);
        for (var s in [-1.0, 1.0]) {
          var from = off(s * 0.18, 0.12);
          canvas.drawLine(from, from - up * (u * 0.38), string);
        }
      case GarmentKind.shirt || GarmentKind.polo:
        canvas.drawPath(
            Path()
              ..moveTo(off(0.3, 0).dx, off(0.3, 0).dy)
              ..lineTo(off(0, 0.3).dx, off(0, 0.3).dy)
              ..lineTo(off(-0.3, 0).dx, off(-0.3, 0).dy),
            line);
        var dot = Paint()..color = _shade(colour);
        var buttons = g.kind == GarmentKind.polo ? 2 : 4;
        for (var b = 1; b <= buttons; b++) {
          canvas.drawCircle(
              Offset.lerp(off(0, 0.3), Offset(rig.chest.dx, hem), b / (buttons + 1.5))!,
              edge * 1.3,
              dot);
        }
      case GarmentKind.jacket ||
            GarmentKind.blazer ||
            GarmentKind.coat ||
            GarmentKind.cardigan:
        // Open down the front, with lapels.
        canvas.drawLine(off(0, 0.25), Offset(rig.chest.dx, hem), line);
        if (g.kind != GarmentKind.cardigan) {
          for (var s in [-1.0, 1.0]) {
            var lapel = Path()
              ..moveTo(off(s * 0.4, 0).dx, off(s * 0.4, 0).dy)
              ..lineTo(off(s * 0.05, 0.6).dx, off(s * 0.05, 0.6).dy)
              ..lineTo(off(s * 0.28, 0.25).dx, off(s * 0.28, 0.25).dy)
              ..close();
            _fill(lapel, Color.lerp(colour, g.color2, 0.25)!);
          }
        }
      case GarmentKind.sweater:
        canvas.drawLine(Offset(rig.chest.dx - half, hem - u * 0.05),
            Offset(rig.chest.dx + half, hem - u * 0.05), line);
        continue neckline;
      neckline:
      default:
        var deep = g.kind == GarmentKind.tank ||
                g.kind == GarmentKind.vest ||
                g.kind == GarmentKind.blouse ||
                g.kind == GarmentKind.swimsuit
            ? 0.24
            : 0.16;
        if (g.kind == GarmentKind.braTop) break;
        canvas.drawPath(
            Path()
              ..moveTo(off(0.32, 0).dx, off(0.32, 0).dy)
              ..quadraticBezierTo(off(0, deep).dx, off(0, deep).dy,
                  off(-0.32, 0).dx, off(-0.32, 0).dy),
            line);
    }
    canvas.restore();
  }

  void _capes() {
    for (var (i, g) in _wearing((g) => g.kind.shape == GarmentShape.cape)) {
      var (across, _, half, _) = _torsoFrame;
      var top = rig.chest;
      var hemY = rig.hips.dy + g.lengthOr * _leg;
      var hemHalf = half * g.kind.flare;
      var cape = Path()
        ..moveTo((top + across * half).dx, (top + across * half).dy)
        ..lineTo((top - across * half).dx, (top - across * half).dy)
        ..lineTo(rig.hips.dx - hemHalf, hemY)
        ..quadraticBezierTo(rig.hips.dx, hemY + u * 0.2, rig.hips.dx + hemHalf, hemY)
        ..close();
      _cloth(cape, g, i, part: 40, hem: true);
    }
  }

  void _neckwear() {
    var (across, up, half, _) = _torsoFrame;
    if (bodyFacing < 0.2) return;
    var side = math.sin(rig.yaw * math.pi / 180);
    canvas.save();
    canvas.translate(-side * half * 0.4, 0);
    var collar = dna.fourLegs
        ? Offset.lerp(rig.neck, rig.chest, 0.4)!
        : rig.chest + up * (u * 0.02);
    for (var (i, g) in _wearing((g) => g.kind.shape == GarmentShape.neck)) {
      _inGarment(g, () {
      var colour = faded(g.color, g.condition.fade);
      switch (g.kind) {
        case GarmentKind.tie:
          var knot = collar - up * (u * 0.14);
          var tip = Offset.lerp(rig.chest, rig.hips, 0.62)!;
          var tie = Path()
            ..moveTo(knot.dx - u * 0.05, knot.dy)
            ..lineTo(knot.dx + u * 0.05, knot.dy)
            ..lineTo(tip.dx + u * 0.07, tip.dy - u * 0.08)
            ..lineTo(tip.dx, tip.dy)
            ..lineTo(tip.dx - u * 0.07, tip.dy - u * 0.08)
            ..close();
          _cloth(tie, g, i, part: 50);
        case GarmentKind.bowTie:
          var c = collar - up * (u * 0.1);
          for (var s in [-1.0, 1.0]) {
            _fill(
                Path()
                  ..moveTo(c.dx, c.dy)
                  ..lineTo(c.dx + s * u * 0.13, c.dy - u * 0.07)
                  ..lineTo(c.dx + s * u * 0.13, c.dy + u * 0.07)
                  ..close(),
                colour);
          }
          _fill(Path()..addOval(Rect.fromCircle(center: c, radius: u * 0.035)),
              colour);
        case GarmentKind.scarf:
          var band = Path()
            ..addRRect(RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: collar - up * (u * 0.06),
                    width: half * 1.1,
                    height: u * 0.2),
                Radius.circular(u * 0.08)));
          _cloth(band, g, i, part: 51);
          var tail = Path()
            ..addRRect(RRect.fromRectAndRadius(
                Rect.fromLTWH(collar.dx + half * 0.15, collar.dy, u * 0.16, u * 0.6),
                Radius.circular(u * 0.05)));
          _cloth(tail, g, i, part: 52, hem: true);
        case GarmentKind.necklace:
          var chain = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = edge * 1.2
            ..color = colour;
          var low = collar + up * (-u * 0.25);
          canvas.drawPath(
              Path()
                ..moveTo((collar + across * (half * 0.35)).dx,
                    (collar + across * (half * 0.35)).dy)
                ..quadraticBezierTo(low.dx, low.dy,
                    (collar - across * (half * 0.35)).dx,
                    (collar - across * (half * 0.35)).dy),
              chain);
          _fill(
              Path()
                ..addOval(Rect.fromCircle(
                    center: low + up * (u * 0.11), radius: u * 0.04)),
              g.color2);
        default:
          break;
      }
          });
    }
    canvas.restore();
  }

  /// _arms draws the arms turned away from the reader with [far], and the
  /// rest without -- [near] being how far behind the middle of the body an
  /// arm can be and still count as in front -- each with its sleeves.
  void _arms({required bool far, required double near}) {
    for (var limb in [CharacterLimb.armL, CharacterLimb.armR]) {
      if (!_shows(_regionOf(limb))) continue;
      if ((rig.depths[limb]! < near) != far) continue;
      var shoulder = rig.root(limb), elbow = rig.middle(limb);
      var wrist = rig.end(limb);
      if (dna.species == Species.bird) {
        _inBody(_armLayer(limb),
            () => _birdWing(shoulder, elbow, wrist, limb.onLeft ? -1 : 1));
        continue;
      }
      if (dna.species.legless) {
        _inBody(_armLayer(limb), () => _fin(shoulder, elbow));
        continue;
      }
      _inBody(_armLayer(limb),
          () => _limb(_along(limb, 0, 1), armWidth, dna.skin, limb: limb));
      // The hand where the arm ends, reshaped or not.
      elbow = _beforeEnd(limb);
      wrist = _end(limb);
      if (dna.fourLegs) {
        // Front legs: whatever is worn on the legs is worn on these too.
        for (var (i, g) in _wearing((g) => g.kind.coversLegs)) {
          var from = g.kind.from, to = math.max(from + 0.02, g.lengthOr);
          _cloth(null, g, i,
              line: _along(limb, from, math.min(1, to)),
              width: armWidth * 1.12 * g.fitOr,
              part: 70 + limb.index,
              hem: true);
        }
      }
      _inBody(_handLayer(limb), () {
      var forward = wrist - elbow;
      var hand = wrist +
          (forward.distance == 0
              ? Offset.zero
              : forward / forward.distance * rig.handRadius * 0.5);
      if (look.gloves) {
        // A white cartoon glove, a size up, with a cuff.
        var cuff = wrist - (forward.distance == 0
            ? Offset.zero
            : forward / forward.distance * rig.handRadius * 0.2);
        _fill(Path()..addOval(Rect.fromCircle(center: hand, radius: rig.handRadius * 1.35)),
            const Color(0xFFFAFAFA));
        _fill(Path()..addOval(Rect.fromCircle(center: cuff, radius: rig.handRadius * 0.75)),
            const Color(0xFFFAFAFA));
      } else if (dna.species.animal || dna.fourLegs) {
        _fill(Path()..addOval(Rect.fromCircle(center: hand, radius: rig.handRadius)),
            dna.skin);
      } else {
        // A hand: a palm longer than it is wide, along the forearm, and a
        // thumb on the side towards the body.
        var r = rig.handRadius;
        var along = forward.distance == 0 ? 0.0 : math.atan2(forward.dy, forward.dx);
        var inward = limb.onLeft ? 1.0 : -1.0;
        canvas.save();
        canvas.translate(hand.dx, hand.dy);
        canvas.rotate(along - math.pi / 2);
        // A slim hand, the fingers together and tapering to their tips.
        var palm = Path()
          ..moveTo(-r * 0.62, -r * 0.7)
          ..quadraticBezierTo(-r * 0.78, r * 0.4, -r * 0.42, r * 1.25)
          ..quadraticBezierTo(0, r * 1.75, r * 0.38, r * 1.3)
          ..quadraticBezierTo(r * 0.72, r * 0.4, r * 0.6, -r * 0.7)
          ..quadraticBezierTo(0, -r * 0.95, -r * 0.62, -r * 0.7)
          ..close();
        var thumb = Path()
          ..addOval(Rect.fromCenter(
              center: Offset(inward * r * 0.62, r * 0.05), width: r * 0.48, height: r * 1.05));
        _fill(Path.combine(PathOperation.union, palm, thumb), dna.skin);
        canvas.restore();
      }
      });
      for (var (i, g) in _wearing((g) => g.kind.hasSleeves)) {
        var sleeve = g.sleeveOr;
        if (sleeve <= 0) continue;
        _cloth(null, g, i,
            line: _along(limb, 0, math.min(0.97, sleeve)),
            width: armWidth * 1.14 * g.fitOr,
            part: 60 + limb.index,
            hem: true,
            span: (0, math.min(0.97, sleeve)),
            limb: limb);
      }
    }
  }

  // ---- what is worn on the head ----

  void _glasses(double w) {
    for (var (_, g) in _wearing((g) => g.kind.shape == GarmentShape.glasses)) {
      _inGarment(g, () {
      var frame = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.025
        ..color = g.color;
      var eyeY = u * 0.06 + _nodShift;
      var lenses = <Rect>[];
      for (var s in [-1.0, 1.0]) {
        var toward = _toward(s * 0.42);
        if (toward < 0.15) continue;
        var c = Offset(_across(s * 0.42, w), eyeY);
        lenses.add(Rect.fromCenter(
            center: c, width: u * 0.24 * toward, height: u * 0.2));
      }
      for (var r in lenses) {
        if (g.kind == GarmentKind.sunglasses) {
          canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(u * 0.06)),
              Paint()..color = const Color(0xE0151515));
        }
        if (g.kind == GarmentKind.roundGlasses) {
          canvas.drawOval(r, frame);
        } else {
          canvas.drawRRect(
              RRect.fromRectAndRadius(r, Radius.circular(u * 0.04)), frame);
        }
      }
      if (lenses.length == 2) {
        canvas.drawLine(Offset(lenses[0].right, eyeY - u * 0.02),
            Offset(lenses[1].left, eyeY - u * 0.02), frame);
      }
          });
    }
  }

  void _hats(double w, double h) {
    for (var (i, g) in _wearing((g) => g.kind.shape == GarmentShape.hat)) {
      _inGarment(g, () {
      var colour = faded(g.color, g.condition.fade);
      var shift = _across(0, w) * 0.3;
      switch (g.kind) {
        case GarmentKind.cap:
          var dome = Path()
            ..addArc(
                Rect.fromCenter(
                    center: Offset(0, -h * 0.35), width: w * 2.1, height: h * 1.5),
                math.pi,
                math.pi)
            ..close();
          _cloth(dome, g, i, part: 70);
          // The peak sticks out the way the face points.
          var peak = Path()
            ..addOval(Rect.fromCenter(
                center: Offset(shift * 2.2, -h * 0.36),
                width: w * (1.2 + 0.6 * (1 - facing.abs())),
                height: h * 0.18));
          _fill(peak, Color.lerp(colour, g.color2, 0.3)!);
        case GarmentKind.beanie:
          var dome = Path()
            ..addArc(
                Rect.fromCenter(
                    center: Offset(0, -h * 0.3), width: w * 2.12, height: h * 1.7),
                math.pi,
                math.pi)
            ..close();
          _cloth(dome, g, i, part: 70);
          _fill(
              Path()
                ..addRRect(RRect.fromRectAndRadius(
                    Rect.fromLTWH(-w * 1.07, -h * 0.42, w * 2.14, h * 0.24),
                    Radius.circular(h * 0.08))),
              Color.lerp(colour, const Color(0xFF000000), 0.12)!);
        case GarmentKind.topHat:
          _fill(
              Path()
                ..addOval(Rect.fromCenter(
                    center: Offset(0, -h * 0.72), width: w * 2.4, height: h * 0.3)),
              colour);
          _cloth(
              Path()
                ..addRect(Rect.fromLTWH(-w * 0.75, -h * 1.75, w * 1.5, h * 1.05)),
              g,
              i,
              part: 70);
          canvas.drawRect(Rect.fromLTWH(-w * 0.75, -h * 0.95, w * 1.5, h * 0.16),
              Paint()..color = g.color2);
        case GarmentKind.sunHat:
          _fill(
              Path()
                ..addOval(Rect.fromCenter(
                    center: Offset(0, -h * 0.55), width: w * 3.2, height: h * 0.55)),
              colour);
          _cloth(
              Path()
                ..addArc(
                    Rect.fromCenter(
                        center: Offset(0, -h * 0.55), width: w * 1.6, height: h * 1.3),
                    math.pi,
                    math.pi)
                ..close(),
              g,
              i,
              part: 70);
        case GarmentKind.crown:
          var crown = Path()..moveTo(-w * 0.7, -h * 0.75);
          for (var k = 0; k <= 4; k++) {
            var x = -w * 0.7 + w * 1.4 * k / 4;
            crown.lineTo(x, k.isEven ? -h * 1.35 : -h * 1.0);
          }
          crown
            ..lineTo(w * 0.7, -h * 0.75)
            ..close();
          _fill(crown, colour);
        default:
          break;
      }
          });
    }
  }

  // ---- cloth ----

  /// _capsule is a round-ended band [width] thick through [points]: an arm,
  /// a leg, a sleeve -- as a shape, so it can be cut and patterned.
  Path _capsule(List<Offset> points, double width) {
    var r = width / 2;
    // Each piece joined to the last, so there is one outline round the
    // whole of it: pieces merely added together keep their own outlines,
    // and every elbow and knee showed a circle.
    var out = Path()..addOval(Rect.fromCircle(center: points.first, radius: r));
    for (var i = 0; i + 1 < points.length; i++) {
      var a = points[i], b = points[i + 1];
      var d = b - a;
      var piece = Path()..addOval(Rect.fromCircle(center: b, radius: r));
      if (d.distance >= 1e-6) {
        var n = Offset(-d.dy, d.dx) / d.distance * r;
        piece.addPolygon([a + n, b + n, b - n, a - n], true);
        piece = Path.combine(PathOperation.union, piece, Path());
      }
      out = Path.combine(PathOperation.union, out, piece);
    }
    return out;
  }

  /// _stroke is a round-ended band [width] thick through [points], edged
  /// the way [_fill] edges a shape. Drawn as a stroke rather than a shape
  /// because a stroke has no seams: a band made of pieces showed a sliver
  /// at every elbow and knee.
  /// _limb is an arm or a leg through [points]: thicker at the root than at
  /// the end, a little fuller near the top where the muscle is, rounded at
  /// every joint -- as a figure is drawn, rather than a tube.
  void _limb(List<Offset> points, double width, Color colour,
      {bool leg = false, CharacterLimb? limb}) {
    if (look.hose || points.length < 2) {
      _stroke(points, width, colour);
      return;
    }
    var shape = _limbShape(points, width, leg: leg, limb: limb);
    _solid(shape.getBounds(), colour, (p) => canvas.drawPath(shape, p));
    // No line where it joins the body: the shoulder or the hip and the
    // limb are one form, not a limb stuck on.
    canvas.save();
    canvas.clipPath(Path.combine(
        PathOperation.difference,
        Path()..addRect(shape.getBounds().inflate(width)),
        Path()..addOval(Rect.fromCircle(center: points.first, radius: width * 0.7))));
    _outline(shape, colour);
    canvas.restore();
  }

  /// _limbShape is the outline of a limb through [points] [width] across
  /// at the usual -- or of the stretch of it from [t0] to [t1] of its
  /// length, for a sleeve or a trouser leg, which narrows as the limb does.
  Path _limbShape(List<Offset> points, double width,
      {double t0 = 0, double t1 = 1, bool leg = false, CharacterLimb? limb}) {
    // Reshaped point by point: thicker or thinner, its cross-section
    // turned, where each point says.
    var pts = limb == null ? null : _points(limb);
    var lengths = <double>[0];
    for (var i = 1; i < points.length; i++) {
      lengths.add(lengths.last + (points[i] - points[i - 1]).distance);
    }
    var total = lengths.last;
    if (total < 1e-6) return _capsule(points, width);
    // Thick at the root, a swell of muscle, in at the elbow or the knee,
    // a swell again, and in to the wrist or the ankle -- as far as the
    // Appearance says.
    var m = _a(Look.muscle);
    var j = leg ? 0.5 : 0.52;
    var female = dna.kind == CharacterType.woman || dna.kind == CharacterType.girl;
    var profile = leg
        ? [
            (0.0, female ? 1.34 : 1.2),
            (0.3 * j, 1.16 + 0.08 * m),
            (j, 0.74),
            (j + 0.32 * (1 - j), 0.84 + 0.08 * m),
            (1.0, 0.52 * (1 + 0.45 * _a(Look.ankles))),
          ]
        : [
            (0.0, 1.08),
            (0.4 * j, 1.12 + 0.12 * m),
            (j, 0.8),
            (j + 0.3 * (1 - j), 0.86 + 0.06 * m),
            (1.0, 0.58 * (1 + 0.45 * _a(Look.wrists))),
          ];
    double widthAt(double f) {
      var t = t0 + (t1 - t0) * f;
      for (var i = 0; i + 1 < profile.length; i++) {
        var (ta, wa) = profile[i];
        var (tb, wb) = profile[i + 1];
        if (t <= tb || i + 2 == profile.length) {
          var k = ((t - ta) / (tb - ta)).clamp(0.0, 1.0);
          k = k * k * (3 - 2 * k);
          return width *
              (wa + (wb - wa) * k) *
              (pts == null ? 1 : _profile(pts, t, (p) => p.scale));
        }
      }
      return width;
    }

    // Down its middle, finely, then out each side square to the way it
    // runs there -- turning smoothly round an elbow or a knee rather than
    // in a kink.
    var middle = <Offset>[], at = <double>[];
    for (var i = 0; i + 1 < points.length; i++) {
      var a = points[i], b = points[i + 1];
      var len = (b - a).distance;
      if (len < 1e-6) continue;
      const steps = 12;
      for (var k = 0; k <= steps; k++) {
        if (k == 0 && middle.isNotEmpty) continue;
        middle.add(Offset.lerp(a, b, k / steps)!);
        at.add((lengths[i] + len * k / steps) / total);
      }
    }
    if (middle.length < 2) return _capsule(points, width);
    var left = <Offset>[], right = <Offset>[];
    for (var k = 0; k < middle.length; k++) {
      // Its direction averaged over a little way either side.
      var back = middle[math.max(0, k - 3)], ahead = middle[math.min(middle.length - 1, k + 3)];
      var d = ahead - back;
      var len = d.distance;
      if (len < 1e-6) d = middle.last - middle.first;
      len = d.distance == 0 ? 1.0 : d.distance;
      var n = Offset(-d.dy / len, d.dx / len);
      if (pts != null) {
        var turn = _profile(pts, t0 + (t1 - t0) * at[k], (p) => p.turn) * math.pi / 180;
        if (turn != 0) {
          var c = math.cos(turn), sn = math.sin(turn);
          n = Offset(n.dx * c - n.dy * sn, n.dx * sn + n.dy * c);
        }
      }
      var w = widthAt(at[k]) / 2;
      left.add(middle[k] + n * w);
      right.add(middle[k] - n * w);
    }
    var shape = Path()..addPolygon([...left, ...right.reversed], true);
    // Round at the root and the end; round at the joint on the outside of
    // the bend.
    for (var i in [
      0,
      points.length - 1,
      if (points.length == 3 && pts == null) 1,
      // Reshaped, at its own points -- not every step of the curve.
      if (pts != null)
        for (var j = 1; j < points.length - 1; j++)
          if (pts.any((p) => (p.at - points[j]).distance < 1e-6)) j,
    ]) {
      var w = widthAt(lengths[i] / total) / 2;
      shape = Path.combine(PathOperation.union, shape,
          Path()..addOval(Rect.fromCircle(center: points[i], radius: w)));
    }
    return shape;
  }

  void _stroke(List<Offset> points, double width, Color colour) {
    var path = Path()..moveTo(points.first.dx, points.first.dy);
    if (look.hose && points.length == 3) {
      // A rubber hose limb bends all the way along, with no joint in it.
      var through = points[1] * 2 - (points[0] + points[2]) / 2;
      path.quadraticBezierTo(through.dx, through.dy, points[2].dx, points[2].dy);
    } else {
      for (var p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
    }
    Paint stroke() => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (lined) {
      canvas.drawPath(
          path,
          stroke()
            ..strokeWidth = width + edge * 2
            ..color = _inkFor(colour));
    }
    var bounds = path.getBounds().inflate(width);
    _solid(bounds, colour, (p) {
      canvas.drawPath(
          path,
          stroke()
            ..strokeWidth = width
            ..color = p.color
            ..blendMode = p.blendMode);
    });
  }

  /// _cloth draws garment [g] -- the [i]th worn -- as [shape], or as a band
  /// [width] wide along [line] (a sleeve, a trouser leg): its colour washed
  /// out as much as it is faded, its pattern, dirt and patches, and cut
  /// through where it is ripped, so what is under it shows. [part] keeps
  /// two pieces of one garment from wearing the same way; [hem] says its
  /// lower edge is a hem, which frays.
  void _cloth(Path? shape, Garment g, int i,
          {List<Offset>? line,
          double width = 0,
          int part = 0,
          bool hem = false,
          (double, double)? span,
          bool leg = false,
          CharacterLimb? limb}) =>
      _inGarment(
          g,
          () => _clothIn(shape, g, i,
              line: line,
              width: width,
              part: part,
              hem: hem,
              span: span,
              leg: leg,
              limb: limb));

  void _clothIn(Path? shape, Garment g, int i,
      {List<Offset>? line,
      double width = 0,
      int part = 0,
      bool hem = false,
      (double, double)? span,
      bool leg = false,
      CharacterLimb? limb}) {
    // Down a limb, as the limb narrows.
    if (shape == null && line != null && span != null && !look.hose) {
      shape = _limbShape(line, width, t0: span.$1, t1: span.$2, leg: leg, limb: limb);
    }
    var c = g.condition;
    var seed = g.seed + i * 7919 + g.kind.index * 104729 + part * 31337;
    var colour = faded(g.color, c.fade);
    // What the pattern is kept inside, and where rips may fall.
    var area = shape ?? _capsule(line!, width);
    var bounds = area.getBounds();
    var cut = c.rips > 0 || (hem && c.frays > 0);
    if (cut) canvas.saveLayer(bounds.inflate(edge * 3 + width), Paint());
    if (shape case var piece?) {
      _solid(bounds, colour, (p) => canvas.drawPath(piece, p));
    } else {
      _stroke(line!, width, colour);
    }
    canvas.save();
    canvas.clipPath(area);
    _pattern(bounds, g, seed, part);
    _wear(area, bounds, g, colour, seed);
    canvas.restore();
    if (shape != null) _outline(shape, colour);
    if (cut) {
      canvas.drawPath(_holes(area, bounds, c, seed, hem),
          Paint()..blendMode = BlendMode.clear);
      canvas.restore();
    }
  }

  /// _holes is where [c]'s rips go through a piece of cloth, and the bites
  /// a frayed hem takes out of its bottom edge.
  Path _holes(Path area, Rect bounds, GarmentCondition c, int seed, bool hem) {
    var holes = Path();
    var rips = (c.rips * 4).round();
    for (var k = 0, placed = 0; k < 24 && placed < rips; k++) {
      var at = Offset(bounds.left + bounds.width * wearUnit(seed, k * 2),
          bounds.top + bounds.height * (0.25 + 0.7 * wearUnit(seed, k * 2 + 1)));
      if (!area.contains(at)) continue;
      placed++;
      var size = u * (0.03 + 0.05 * c.rips) * (0.6 + 0.8 * wearUnit(seed, 100 + k));
      holes.addPolygon([
        for (var p = 0; p < 7; p++)
          at +
              Offset(math.cos(p / 7 * 2 * math.pi), math.sin(p / 7 * 2 * math.pi)) *
                  (size * (0.55 + 0.45 * wearUnit(seed, 200 + k * 7 + p)))
                  .toDouble()
                  .clamp(0.0, double.infinity),
      ], true);
    }
    if (hem && c.frays > 0) {
      var bites = 6 + (c.frays * 10).round();
      for (var k = 0; k < bites; k++) {
        var x = bounds.left + bounds.width * (k + wearUnit(seed, 300 + k)) / bites;
        var deep = u * 0.05 * c.frays * (0.4 + wearUnit(seed, 400 + k));
        holes.addPolygon([
          Offset(x - deep * 0.6, bounds.bottom + edge * 2),
          Offset(x, bounds.bottom - deep),
          Offset(x + deep * 0.6, bounds.bottom + edge * 2),
        ], true);
      }
    }
    return holes;
  }

  /// _wear is the dirt and the patches on a piece of cloth.
  void _wear(Path area, Rect bounds, Garment g, Color colour, int seed) {
    var c = g.condition;
    if (c.dirt > 0) {
      var dirt = Paint()
        ..color = const Color(0xFF6B4E2E).withValues(alpha: 0.3 + 0.2 * c.dirt);
      var blots = (c.dirt * 10).round();
      for (var k = 0; k < blots; k++) {
        // Lower down more than higher up: dirt is splashed up from the
        // ground.
        var y = bounds.top +
            bounds.height * (1 - math.pow(wearUnit(seed, 500 + k), 2.2));
        var at = Offset(bounds.left + bounds.width * wearUnit(seed, 600 + k), y);
        canvas.drawOval(
            Rect.fromCenter(
                center: at,
                width: u * (0.04 + 0.08 * wearUnit(seed, 700 + k)),
                height: u * (0.03 + 0.05 * wearUnit(seed, 800 + k))),
            dirt);
      }
    }
    if (c.patches > 0) {
      var patches = (c.patches * 3).round();
      for (var k = 0, placed = 0; k < 20 && placed < patches; k++) {
        var at = Offset(bounds.left + bounds.width * wearUnit(seed, 900 + k),
            bounds.top + bounds.height * wearUnit(seed, 1000 + k));
        if (!area.contains(at)) continue;
        placed++;
        canvas.save();
        canvas.translate(at.dx, at.dy);
        canvas.rotate((wearUnit(seed, 1100 + k) - 0.5) * 0.6);
        var size = u * (0.09 + 0.05 * wearUnit(seed, 1200 + k));
        var patch = Rect.fromCenter(
            center: Offset.zero, width: size, height: size * 0.85);
        canvas.drawRect(
            patch, Paint()..color = Color.lerp(colour, g.color2, 0.55)!);
        canvas.drawRect(
            patch.deflate(size * 0.1),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = edge * 0.7
              ..color = _shade(colour, 0.5));
        canvas.restore();
      }
    }
  }

  /// _pattern prints [g]'s pattern over [bounds], in its second colour.
  void _pattern(Rect bounds, Garment g, int seed, [int part = 0]) {
    var ink = Paint()..color = g.color2.withValues(alpha: 0.85);
    var step = u * 0.1;
    switch (g.pattern) {
      case GarmentPattern.plain:
        return;
      case GarmentPattern.print:
        // On the front of the body only -- not down each sleeve -- and not
        // from behind.
        if (part != 30 && part != 31) return;
        if (bodyFacing < 0.2 || g.printId.isEmpty) return;
        var picture = images?.resolve(g.printId, const BackgroundRemoval());
        if (picture == null) return;
        var w = bounds.width * g.printSize * bodyFacing;
        var h = w * picture.height / math.max(1, picture.width);
        var centre = Offset(bounds.center.dx, bounds.top + bounds.height * 0.4);
        canvas.drawImageRect(
            picture,
            Rect.fromLTWH(
                0, 0, picture.width.toDouble(), picture.height.toDouble()),
            Rect.fromCenter(center: centre, width: w, height: h),
            Paint()..filterQuality = FilterQuality.medium);
      case GarmentPattern.stripes:
        for (var y = bounds.top; y < bounds.bottom; y += step) {
          canvas.drawRect(
              Rect.fromLTWH(bounds.left, y, bounds.width, step * 0.45), ink);
        }
      case GarmentPattern.pinstripe:
        var line = Paint()
          ..strokeWidth = math.max(0.5, u * 0.008)
          ..color = g.color2.withValues(alpha: 0.7);
        for (var x = bounds.left; x < bounds.right; x += step * 0.6) {
          canvas.drawLine(Offset(x, bounds.top), Offset(x, bounds.bottom), line);
        }
      case GarmentPattern.check:
        var soft = Paint()..color = g.color2.withValues(alpha: 0.4);
        for (var y = bounds.top; y < bounds.bottom; y += step * 1.4) {
          canvas.drawRect(Rect.fromLTWH(bounds.left, y, bounds.width, step * 0.6), soft);
        }
        for (var x = bounds.left; x < bounds.right; x += step * 1.4) {
          canvas.drawRect(Rect.fromLTWH(x, bounds.top, step * 0.6, bounds.height), soft);
        }
      case GarmentPattern.dots:
        var row = 0;
        for (var y = bounds.top; y < bounds.bottom; y += step) {
          var x0 = bounds.left + (row.isEven ? 0 : step / 2);
          row++;
          for (var x = x0; x < bounds.right; x += step) {
            canvas.drawCircle(Offset(x, y), u * 0.018, ink);
          }
        }
      case GarmentPattern.camo:
        var dark = Paint()..color = Color.lerp(g.color2, const Color(0xFF000000), 0.35)!;
        var blobs = (bounds.width * bounds.height / (u * u * 0.03)).ceil().clamp(4, 60);
        for (var k = 0; k < blobs; k++) {
          var at = Offset(bounds.left + bounds.width * wearUnit(seed, 1300 + k),
              bounds.top + bounds.height * wearUnit(seed, 1400 + k));
          canvas.drawOval(
              Rect.fromCenter(
                  center: at,
                  width: u * (0.08 + 0.1 * wearUnit(seed, 1500 + k)),
                  height: u * (0.05 + 0.06 * wearUnit(seed, 1600 + k))),
              k.isEven ? ink : dark);
        }
    }
  }

  Paint _edgePaint(Color colour) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = edge
    ..color = _inkFor(colour);

  /// _inHead draws [what] in the head's own space: the middle of the head
  /// at the origin, tilted with it.
  void _inHead(void Function() what) {
    canvas.save();
    canvas.translate(rig.headCentre.dx, rig.headCentre.dy);
    canvas.rotate(rig.headTurn * math.pi / 180);
    // The whole head together, face and all, so it keeps its proportions.
    if (rig.headScale != 1) canvas.scale(rig.headScale);
    what();
    canvas.restore();
  }

  /// yaw is how far the head is turned from the reader, in radians:
  /// towards the page's left as it grows.
  double get yaw => _onModel ?? (face[FaceControl.turn] + rig.yaw) * math.pi / 180;

  /// facing is how much of the face is towards the reader: 1 straight on,
  /// 0 side on, below 0 turned away.
  double get facing => math.cos(yaw);

  /// _across is where a feature [phi] round the head from the front of the
  /// face is, across a head [w] wide: a point on a turning ball, seen from
  /// the front.
  double _across(double phi, double w) => w * math.sin(phi - yaw);

  /// _toward is how far a feature [phi] round the head faces the reader.
  double _toward(double phi) => math.cos(phi - yaw);

  /// _nodShift is how far down the face's features move as the head nods.
  double get _nodShift => _onModel != null
      ? 0
      : rig.headRadii.height * 0.35 * math.sin(face[FaceControl.nod] * math.pi / 180);

  /// _hangingHair is whether the hair is long enough to hang behind the
  /// head: long hair, or any hair grown out past the chin.
  bool get _hangingHair =>
      (dna.hairStyle == HairStyle.long && _a(Look.hairLength) > -0.6) ||
      (dna.hairStyle != HairStyle.bald &&
          dna.hairStyle != HairStyle.long &&
          _a(Look.hairLength) > 0.35);

  void _backHair() {
    var r = rig.headRadii;
    var len = _a(Look.hairLength);
    // Long hair is to the shoulders and more; grown-out short hair is a
    // bob at the chin.
    // Long hair is to the shoulders, and grown out down the back as far as
    // the thighs; grown-out short hair is a bob at the chin.
    var bottom = dna.hairStyle == HairStyle.long
        ? 1.9 + (len > 0 ? 5.0 : 1.3) * len
        : 1.0 + 1.6 * (len - 0.35);
    var wide = 1 + 0.15 * _a(Look.hairVolume);
    // Flowing hair stands out from the head, full at the sides.
    var full = look.hair == _Hair.flowing ? 1.22 : 1.1;
    var w = r.width * full * wide, top = r.height * (full - 0.04);
    var low = r.height * bottom;
    // Below the neck, long hair spreads over the back to the shoulders'
    // width, so it shows either side of the body.
    var hs = rig.headScale == 0 ? 1.0 : rig.headScale;
    var shoulderY = (rig.chest.dy - rig.headCentre.dy) / hs;
    var spread = math.max(w, rig.shoulderHalf / hs * 0.95 * wide);
    var flares = low > shoulderY * 1.2;
    // Over the crown, falling either side wider than the head, and ending
    // in rounded locks rather than a cut line.
    var back = Path()
      ..moveTo(-w, -r.height * 0.15)
      ..arcToPoint(Offset(w, -r.height * 0.15),
          radius: Radius.elliptical(w, top), largeArc: false);
    if (flares) {
      back
        ..quadraticBezierTo(w * 1.05, shoulderY * 0.7, spread, shoulderY * 1.15)
        ..quadraticBezierTo(spread * 1.08, (shoulderY + low) / 2, spread * 0.86, low);
    } else {
      back.quadraticBezierTo(w * 1.14, low * 0.55, w * 0.86, low);
    }
    var bottomHalf = flares ? spread * 0.86 : w * 0.86;
    const locks = 5;
    for (var i = 0; i < locks; i++) {
      var x0 = bottomHalf - (bottomHalf * 2) * i / locks;
      var x1 = bottomHalf - (bottomHalf * 2) * (i + 1) / locks;
      var dip = low + r.height * (0.12 + 0.05 * ((i * 7) % 3));
      back.quadraticBezierTo((x0 + x1) / 2, dip, x1, low);
    }
    if (flares) {
      back
        ..quadraticBezierTo(-spread * 1.08, (shoulderY + low) / 2, -spread, shoulderY * 1.15)
        ..quadraticBezierTo(-w * 1.05, shoulderY * 0.7, -w, -r.height * 0.15);
    } else {
      back.quadraticBezierTo(-w * 1.14, low * 0.55, -w, -r.height * 0.15);
    }
    back.close();
    _fill(back, dna.hair);
    if (look.hair == _Hair.flowing) {
      // Strands falling from the crown, waving as they go.
      canvas.save();
      canvas.clipPath(back);
      var dark = _feature(math.max(0.5, u * 0.012), _shade(dna.hair, 0.28).withValues(alpha: 0.5));
      for (var k = 0; k < 9; k++) {
        var x = -bottomHalf * 0.9 + bottomHalf * 1.8 * k / 8;
        var strand = Path()..moveTo(x * 0.3, -r.height * 0.9);
        for (var j = 1; j <= 6; j++) {
          var y = -r.height * 0.9 + (low + r.height * 0.9) * j / 6;
          var wave = math.sin(j * 1.3 + k) * r.width * 0.08 * j / 6;
          strand.lineTo(x * (0.3 + 0.7 * j / 6) + wave, y);
        }
        canvas.drawPath(strand, dark);
      }
      canvas.restore();
    }
    _highlights(back, r.width, low);
  }

  /// _frontHair is long hair fallen forward over the shoulders: a lock each
  /// side, from the side of the head over the shoulder and down the front,
  /// in a gentle wave, with strands drawn through it. Drawn over the body
  /// and under the arms. Turned, only the lock on the near side shows.
  void _frontHair() {
    var len = _a(Look.hairLength);
    if (dna.hairStyle != HairStyle.long || len < 0.2 || facing < 0) return;
    var hs = rig.headScale == 0 ? 1.0 : rig.headScale;
    var r = rig.headRadii;
    var w = r.width * hs, hh = r.height * hs;
    var hc = rig.headCentre;
    var bottom = hc.dy + hh * (1.9 + 5.0 * len) * 0.92;
    var wide = 1 + 0.15 * _a(Look.hairVolume);
    var spin = math.sin(yaw);
    for (var (side, inset, thin, short) in [
      (-1.0, 0.86, 0.7, 0.86),
      (1.0, 0.86, 0.7, 0.86),
      (-1.0, 1.0, 1.0, 1.0),
      (1.0, 1.0, 1.0, 1.0),
    ]) {
      // The far side's lock is behind the head and shoulder once turned.
      if (side * spin > 0.35) continue;
      var lean = (1 - (side * spin).abs() * 0.6) * inset;
      List<Offset> line = [
        Offset(hc.dx + side * w * 0.92 * lean, hc.dy + hh * 0.1),
        Offset(rig.chest.dx + side * rig.shoulderHalf * 0.78 * lean,
            rig.chest.dy - hh * 0.02),
        Offset(rig.chest.dx + side * rig.shoulderHalf * 0.98 * lean,
            (rig.chest.dy + bottom) / 2),
        Offset(rig.chest.dx + side * rig.shoulderHalf * 0.92 * lean,
            hc.dy + (bottom - hc.dy) * short),
      ];
      var thick = w * (look.hair == _Hair.flowing ? 0.56 : 0.42) * wide * thin;
      var left = <Offset>[], right = <Offset>[];
      const steps = 36;
      Offset at(double t) {
        var seg = math.min(line.length - 2, (t * (line.length - 1)).floor());
        var f = t * (line.length - 1) - seg;
        var p0 = line[math.max(0, seg - 1)], p1 = line[seg], p2 = line[seg + 1];
        var p3 = line[math.min(line.length - 1, seg + 2)];
        // Catmull-Rom through the points.
        var f2 = f * f, f3 = f2 * f;
        return (p1 * 2 + (p2 - p0) * f + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * f2 +
                (p1 * 3 - p0 - p2 * 3 + p3) * f3) *
            0.5;
      }

      for (var k = 0; k <= steps; k++) {
        var t = k / steps;
        var p = at(t), q = at(math.min(1, t + 1 / steps));
        var d = q - p;
        if (k == steps) d = p - at(t - 1 / steps);
        var l = d.distance == 0 ? 1.0 : d.distance;
        var n = Offset(-d.dy / l, d.dx / l);
        // A wave down it, and narrowing to the tip.
        // Waves down it, growing towards the ends, as long hair falls.
        var wave = math.sin(t * math.pi * 3.4 + side + inset * 2) * w * 0.26 * t;
        var half = thick * (0.55 + 0.45 * math.sin(math.min(1, t * 1.6) * math.pi / 2)) *
            (1 - 0.75 * math.pow(t, 3)) / 2;
        left.add(p + n * (half + wave));
        right.add(p - n * (half - wave));
      }
      var lock = Path()..addPolygon([...left, ...right.reversed], true);
      _fill(lock, dna.hair);
      _highlights(lock, w, bottom - hc.dy);
      // Strands down it.
      var strand = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.5, u * 0.012)
        ..strokeCap = StrokeCap.round
        ..color = _shade(dna.hair, 0.22);
      for (var j = 1; j <= 2; j++) {
        var f = j / 3;
        var strandPath = Path();
        for (var k = 2; k < steps - 3; k++) {
          var p = Offset.lerp(left[k], right[k], f)!;
          if (k == 2) {
            strandPath.moveTo(p.dx, p.dy);
          } else {
            strandPath.lineTo(p.dx, p.dy);
          }
        }
        canvas.drawPath(strandPath, strand);
      }
    }
  }

  /// _highlights are streaks of the second hair colour through [hair].
  void _highlights(Path hair, double w, double h) {
    var amount = _a(Look.highlights);
    if (amount <= 0) return;
    canvas.save();
    canvas.clipPath(hair);
    var streak = _feature(u * 0.05, dna.hair2.withValues(alpha: 0.35 + 0.45 * amount));
    for (var k = 0; k < 3 + (amount * 3).round(); k++) {
      var x = (_seed(k * 3) - 0.5) * w * 1.8;
      canvas.drawPath(
          Path()
            ..moveTo(x, -h * 1.2)
            ..quadraticBezierTo(x + w * 0.25 * (_seed(k * 3 + 1) - 0.5), 0,
                x + w * 0.2 * (_seed(k * 3 + 2) - 0.5), h * 1.2),
          streak);
    }
    canvas.restore();
  }

  /// _headPath is the shape of the head [w] by [h] across its middle: an
  /// oval, made squarer at the jaw, sharper at the chin, higher at the
  /// brow, fuller at the cheeks, as the Head controls say.
  Path _headPath(double w, double h) {
    var jaw = _a(Look.jaw), chin = _a(Look.chin);
    var chinLong = _a(Look.chinLength), forehead = _a(Look.forehead);
    var bones = _a(Look.cheekbones), cheeks = _a(Look.cheeks);
    var heart = look.heart;
    if (!heart && jaw == 0 && chin == 0 && chinLong == 0 && forehead == 0 &&
        bones == 0 && cheeks == 0) {
      return Path()
        ..addOval(Rect.fromCenter(center: Offset.zero, width: w * 2, height: h * 2));
    }
    double bump(double d, double at, double spread) {
      var t = (d - at) / spread;
      return math.exp(-t * t);
    }

    double smooth(double a, double b, double d) {
      var t = ((d - a) / (b - a)).clamp(0.0, 1.0);
      return t * t * (3 - 2 * t);
    }

    var pts = <Offset>[];
    const n = 96;
    for (var k = 0; k < n; k++) {
      var t = 2 * math.pi * k / n;
      var x = math.sin(t), y = -math.cos(t);
      if (y < 0) {
        y *= 1 + 0.12 * forehead;
        if (heart) x *= 1.03;
      } else {
        var widen = 1 +
            0.07 * bones * bump(y, 0.15, 0.2) +
            0.1 * cheeks * bump(y, 0.45, 0.25) +
            0.2 * jaw * bump(y, 0.78, 0.18);
        widen *= 1 - 0.3 * chin * smooth(0.7, 1, y);
        if (heart) {
          // Full at the cheekbones, then a long taper to a narrow chin.
          widen *= (1 + 0.05 * bump(y, 0.12, 0.18)) * (1 - 0.22 * smooth(0.3, 1.05, y));
        }
        x *= widen;
        y *= 1 + 0.16 * chinLong * smooth(0.5, 1, y);
        if (heart) y *= 1 + 0.04 * smooth(0.8, 1, y) * (1 - x.abs());
      }
      pts.add(Offset(x * w, y * h));
    }
    return Path()..addPolygon(pts, true);
  }

  void _head() {
    var r = rig.headRadii;
    var w = r.width, h = r.height;
    // Ears turned away go behind the head, ears turned towards the reader
    // in front of it, so a head in profile shows one ear on its cheek.
    var ears = [-math.pi / 2, math.pi / 2];
    void ear(double phi) {
      var size = 1 + 0.35 * _a(Look.earSize);
      var out = 1 + 0.45 * _a(Look.earAngle);
      var at = Offset(_across(phi, w * 0.98),
          u * 0.06 - _nodShift * 0.4 - _a(Look.earHeight) * u * 0.07);
      // Taller than it is wide, and as wide as it is turned towards the
      // reader: seen edge on from the front, whole from the side.
      var seen = 0.45 + 0.55 * _toward(phi).abs();
      var ew = u * 0.15 * size * out * seen, eh = u * 0.22 * size;
      var outward = phi < 0 ? -1.0 : 1.0;
      var shape = Path()
        ..moveTo(at.dx, at.dy - eh / 2)
        ..cubicTo(at.dx + outward * ew * 0.95, at.dy - eh / 2,
            at.dx + outward * ew * 0.75, at.dy + eh * 0.35, at.dx, at.dy + eh / 2)
        ..cubicTo(at.dx - outward * ew * 0.35, at.dy + eh * 0.2,
            at.dx - outward * ew * 0.3, at.dy - eh * 0.4, at.dx, at.dy - eh / 2)
        ..close();
      var point = _a(Look.earPoint);
      if (point > 0) {
        // An elf's ear: drawn up and out to a point.
        var dir = phi < 0 ? -1.0 : 1.0;
        shape = Path.combine(
            PathOperation.union,
            shape,
            Path()
              ..addPolygon([
                at + Offset(-u * 0.07 * size, -u * 0.02),
                at + Offset(dir * u * 0.14 * point * size, -u * 0.24 * point * size),
                at + Offset(u * 0.07 * size, -u * 0.02),
              ], true));
      }
      _fill(shape, dna.skin);
      // The curl inside it, in the skin's shadow rather than ink.
      if (seen > 0.6) {
        canvas.drawPath(
            Path()
              ..moveTo(at.dx, at.dy - eh * 0.3)
              ..quadraticBezierTo(at.dx + outward * ew * 0.55, at.dy - eh * 0.25,
                  at.dx + outward * ew * 0.2, at.dy + eh * 0.25),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(0.5, u * 0.018)
              ..strokeCap = StrokeCap.round
              ..color = _shade(dna.skin, 0.25));
      }
    }
    if (dna.spikes) _inBody(BodyLayer.extras, () => _spikes(w, h));
    if (dna.species.animal) {
      _inBody(BodyLayer.ears, () => _animalEars(w, h));
    } else {
      for (var phi in ears) {
        if (_toward(phi) < 0.3) _inBody(BodyLayer.ears, () => ear(phi));
      }
    }
    var head = _headPath(w, h);
    _fill(head, dna.skin);
    // The hair going round the back of the head, bounded by a hairline that
    // curves round the head as it turns: a sliver at each side straight on,
    // half the head side on, all of it from behind.
    if (dna.hairStyle != HairStyle.bald) {
      if (_backOfHead(w, h) case var back?) {
        _inBody(BodyLayer.hairBack, () {
          _solid(back.getBounds(), dna.hair, (p) => canvas.drawPath(back, p));
          canvas.drawPath(
              head,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = edge
                ..color = _shade(dna.hair));
        });
      }
    }
    if (facing > -0.2 && !dna.species.animal) {
      _inBody(BodyLayer.nose,
          () => _setFeature(FacePoint.nose, _noseAt(w), () => _nose(w, front: false)));
    }
    if (!dna.species.animal) {
      for (var phi in ears) {
        if (_toward(phi) >= 0.3) _inBody(BodyLayer.ears, () => ear(phi));
      }
    }
    _inBody(BodyLayer.hairFront, () => _hair(r));
    _inBody(BodyLayer.extras, () => _horns(w, h));
    if (facing > -0.15) {
      // Kept on the face: an eye turned to the far side of the head goes
      // round it, not off its edge.
      canvas.save();
      canvas.clipPath(Path()
        ..addOval(Rect.fromCenter(
            center: Offset.zero, width: w * 2.08, height: rig.headRadii.height * 2.2)));
      _face(w);
      canvas.restore();
      _glasses(w);
    }
    if (_hangingHair && facing < -0.3) _inBody(BodyLayer.hairBack, _backHair);
    _hats(w, h);
  }

  /// _backOfHead is the part of a head [w] by [h] the hair covers, seen
  /// from the front as it turns: everything further round the head than
  /// [_hairline] from the middle of the face. Null when none of it shows.
  Path? _backOfHead(double w, double h) {
    // The hair is everything further round the head from the face than
    // the hairline, which is high at the temples and comes down behind
    // the ears: so a head seen from the side has hair above the ear, and
    // skin only in front of it and below. Each side of the head is done
    // apart -- straight on, both show, a sliver each side of the face.
    double from(double y) {
      var f = y / h;
      // Well forward over the top of the head, at the temples above the
      // ears, and behind them below.
      if (f < -0.1) {
        var t = ((f + 0.6) / 0.5).clamp(0.0, 1.0);
        return 0.55 + (1.2 - 0.55) * t;
      }
      var t = ((f + 0.1) / 0.35).clamp(0.0, 1.0);
      return 1.2 + (_hairline - 1.2) * t;
    }

    Path? side(double sign) {
      var left = <Offset>[], right = <Offset>[];
      var any = false;
      for (var k = 0; k <= 40; k++) {
        var y = -h + 2 * h * k / 40;
        var across = w * math.sqrt(math.max(0.0, 1 - (y / h) * (y / h)));
        double? lo, hi;
        var a0 = from(y);
        // From the hairline round to the back of the head, on this side.
        for (var j = 0; j <= 24; j++) {
          var a = sign * (a0 + (math.pi - a0) * j / 24) - yaw;
          if (math.cos(a) <= 0) continue;
          var v = math.sin(a);
          lo = lo == null ? v : math.min(lo, v);
          hi = hi == null ? v : math.max(hi, v);
        }
        if (lo == null || hi == null) {
          // None of it shows at this height: a point on the edge, so the
          // outline carries on round.
          var edge = math.sin(sign * math.pi / 2 - yaw) >= 0 ? 1.0 : -1.0;
          lo = hi = edge;
        } else {
          any = true;
        }
        left.add(Offset(lo * across, y));
        right.add(Offset(hi * across, y));
      }
      if (!any) return null;
      return Path()..addPolygon([...left, ...right.reversed], true);
    }

    var a = side(1), b = side(-1);
    if (a == null) return b;
    if (b == null) return a;
    return Path.combine(PathOperation.union, a, b);
  }

  /// _hairline is how far round the head from the middle of the face the
  /// skin goes before the hair starts, in radians: a little past the ears.
  static const double _hairline = 1.85;

  void _hair(Size r) {
    if (dna.hairStyle == HairStyle.bald) return;
    var w = r.width, h = r.height;
    var behind = Rect.fromCenter(
        center: Offset.zero, width: w * 2.16, height: h * 2.16);
    // The crown: the top of the head is hair whichever way it is turned,
    // or a three-quarter view shows a bald patch between the fringe and
    // the hair going round the back.
    canvas.save();
    canvas.clipPath(Path()
      ..addOval(Rect.fromCenter(center: Offset.zero, width: w * 2, height: h * 2)));
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(0, -h * 1.25), width: w * 2.8, height: h * 1.4),
        Paint()..color = dna.hair);
    canvas.restore();
    var shift = _across(0, w) * 0.45;
    var volume = 1 + 0.12 * _a(Look.hairVolume);
    if (dna.hairStyle == HairStyle.bun) {
      _fill(
          Path()
            ..addOval(Rect.fromCircle(
                center: Offset(-shift * 0.6, -h * 1.08), radius: u * 0.21)),
          dna.hair);
    }
    if (dna.hairStyle == HairStyle.curly) {
      // Curls round the top of the head, laid by a fixed rule so the same
      // character has the same curls in every frame and every export.
      for (var i = 0; i <= 8; i++) {
        var a = math.pi * (1.05 + i * 0.9 / 8);
        _fill(
            Path()
              ..addOval(Rect.fromCircle(
                  center: Offset(math.cos(a) * w * 0.98 * volume,
                      math.sin(a) * h * 0.92 * volume),
                  radius: u * 0.13 * (1 + 0.25 * _a(Look.hairVolume)))),
            dna.hair);
      }
    }
    if (facing < -0.3) return;
    // The fringe goes round with the face: lower for a longer fringe or a
    // lower hairline, its low point moved to where the hair parts.
    var down = h * (0.3 * _a(Look.fringe) + 0.12 * _a(Look.hairline));
    var part = w * 0.5 * _a(Look.parting);
    if (look.hair == _Hair.spiky) _crownSpikes(w, h, volume);
    var cap = _capPath(w, h, down, part);
    canvas.save();
    if (look.hair != _Hair.spiky && look.hair != _Hair.clumps) {
      canvas.clipPath(Path()..addOval(behind));
    }
    canvas.translate(shift, 0);
    canvas.scale((0.55 + 0.45 * facing.clamp(0.0, 1.0)) * volume, volume);
    _fill(cap, dna.hair);
    _shine(cap, w, h);
    if (look.hair == _Hair.flowing) {
      var p = Offset(_parting(w), -h * 0.8);
      _flowStrands(cap, p, [
        for (var k = 0; k < 9; k++)
          Offset(-w * 1.05 + w * 0.55 * k / 8, -h * 0.9 + h * 1.0 * k / 8),
        for (var k = 0; k < 4; k++)
          Offset(w * 0.95 + w * 0.08 * k / 3, -h * 0.75 + h * 0.75 * k / 3),
      ]);
    }
    _highlights(cap, w, h);
    canvas.restore();
  }

  /// _capPath is the hair over the top of the head down to the fringe:
  /// [down] lower for a longer fringe, its low point moved [part] to the
  /// parting -- its edge smooth, or pointed locks in a style that clumps.
  Path _capPath(double w, double h, double down, double part) {
    if (look.hair == _Hair.flowing) return _flowingCap(w, h, down, part);
    var a0 = Offset(w * 1.04, h * 0.12);
    var c1 = Offset(w * 0.86, -h * 0.4 + down);
    var c2 = Offset(w * 0.2 + part, -h * 0.62 + down);
    var m = Offset(-w * 0.12 + part, -h * 0.5 + down);
    var c3 = Offset(-w * 0.5 + part, -h * 0.3 + down);
    var c4 = Offset(-w * 0.84, -h * 0.2 + down);
    var a1 = Offset(-w * 1.04, h * 0.12);
    var cap = Path()
      ..moveTo(a1.dx, a1.dy)
      ..cubicTo(-w * 1.08, -h * 1.28, w * 1.08, -h * 1.28, a0.dx, a0.dy);
    if (look.hair != _Hair.clumps && look.hair != _Hair.spiky) {
      return cap
        ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, m.dx, m.dy)
        ..cubicTo(c3.dx, c3.dy, c4.dx, c4.dy, a1.dx, a1.dy)
        ..close();
    }
    // Locks: the same edge, cut into points that hang down between.
    Offset bez(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
      var s = 1 - t;
      return p0 * (s * s * s) +
          p1 * (3 * s * s * t) +
          p2 * (3 * s * t * t) +
          p3 * (t * t * t);
    }

    var edge = <Offset>[
      for (var k = 0; k <= 5; k++) bez(a0, c1, c2, m, k / 5),
      for (var k = 1; k <= 5; k++) bez(m, c3, c4, a1, k / 5),
    ];
    var spike = h * (look.hair == _Hair.spiky ? 0.26 : 0.18);
    for (var i = 0; i + 1 < edge.length; i++) {
      var a = edge[i], b = edge[i + 1];
      var long = 0.7 + 0.5 * _seed(i + 40);
      var tip = Offset.lerp(a, b, 0.55)! + Offset(0, spike * long);
      cap.quadraticBezierTo(a.dx, a.dy + spike * 0.4, tip.dx, tip.dy);
      cap.quadraticBezierTo(b.dx, b.dy + spike * 0.2, b.dx, b.dy);
    }
    return cap..close();
  }

  /// _parting is where flowing hair parts, across the head: deep to one
  /// side, further as the Appearance says.
  double _parting(double w) => w * (0.38 + 0.4 * _a(Look.parting));

  /// _flowingCap is flowing hair over the top of the head: fuller than the
  /// head at the crown, its edge rising from the near temple to a parting
  /// well to one side, then sweeping down across the brow to the far
  /// temple -- the fringe framing the face.
  Path _flowingCap(double w, double h, double down, double part) {
    var p = Offset(_parting(w) + part * 0.3, -h * 0.8 + down * 0.4);
    var near = Offset(w * 1.04, h * 0.05);
    var far = Offset(-w * 1.04, h * 0.12);
    return Path()
      ..moveTo(far.dx, far.dy)
      // Over the crown, standing up off the head.
      ..cubicTo(-w * 1.26, -h * 1.56, w * 1.26, -h * 1.56, near.dx, near.dy)
      // Up the near side to the parting.
      ..cubicTo(w * 0.98, -h * 0.4, p.dx + w * 0.2, p.dy - h * 0.02, p.dx, p.dy)
      // And swept down across the brow, low over the far temple.
      ..cubicTo(p.dx - w * 0.35, p.dy + h * 0.06, -w * 0.45, -h * 0.5 + down,
          -w * 0.72, -h * 0.22 + down)
      ..quadraticBezierTo(-w * 0.95, -h * 0.02 + down * 0.5, far.dx, far.dy)
      ..close();
  }

  /// _flowStrands draws fine strands through [hair], flowing out from
  /// [from] along [to]: darker lines, and a few of light.
  void _flowStrands(Path hair, Offset from, List<Offset> to) {
    canvas.save();
    canvas.clipPath(hair);
    var dark = _feature(math.max(0.5, u * 0.011), _shade(dna.hair, 0.3).withValues(alpha: 0.55));
    var light = _feature(math.max(0.5, u * 0.009),
        Color.lerp(dna.hair, const Color(0xFFFFFFFF), 0.45)!.withValues(alpha: 0.5));
    for (var (i, end) in to.indexed) {
      var mid = Offset.lerp(from, end, 0.5)! + Offset((end - from).dy * 0.12, -(end - from).dx * 0.06);
      canvas.drawPath(
          Path()
            ..moveTo(from.dx, from.dy)
            ..quadraticBezierTo(mid.dx, mid.dy, end.dx, end.dy),
          i % 3 == 1 ? light : dark);
    }
    canvas.restore();
  }

  /// _crownSpikes are hair standing up off the crown, in spiky hair.
  void _crownSpikes(double w, double h, double volume) {
    // Wide at the root and swept a little back, each overlapping the next.
    var spikes = Path();
    for (var k = 0; k < 8; k++) {
      var a = math.pi * (1.02 + k * 0.137);
      var spread = 0.42;
      var root = Offset(math.cos(a - spread / 2) * w, math.sin(a - spread / 2) * h);
      var out = Offset(math.cos(a + spread / 2) * w, math.sin(a + spread / 2) * h);
      // Longest at the top of the head, shorter down the sides.
      var top = math.sin(a).abs();
      var reach = 1.12 + 0.28 * top + 0.1 * _seed(k + 70) + 0.6 * (volume - 1);
      var tip = Offset(math.cos(a + 0.1) * w * reach, math.sin(a + 0.1) * h * reach);
      spikes = Path.combine(
          PathOperation.union,
          spikes,
          Path()
            ..moveTo(root.dx * 0.85, root.dy * 0.85)
            ..quadraticBezierTo(
                (root.dx + tip.dx) / 2, (root.dy + tip.dy) / 2 - h * 0.04, tip.dx, tip.dy)
            ..lineTo(out.dx * 0.85, out.dy * 0.85)
            ..close());
    }
    _fill(spikes, dna.hair);
  }

  /// _shine is the light on hair, as the style draws it: a ring of shine
  /// round the crown, a soft band, or fine strands.
  void _shine(Path hair, double w, double h) {
    if (look.hair == _Hair.plain) return;
    canvas.save();
    canvas.clipPath(hair);
    var light = Color.lerp(dna.hair, const Color(0xFFFFFFFF), 0.4)!;
    switch (look.hair) {
      case _Hair.clumps || _Hair.spiky:
        // The ring of shine anime draws round a head of hair.
        // Broken into short arcs, as it is painted, rather than a band.
        var ring = Rect.fromCenter(
            center: Offset(-w * 0.08, h * 0.02), width: w * 1.55, height: h * 1.25);
        var shineColour = Color.lerp(dna.hair, const Color(0xFFFFFFFF), 0.22)!;
        for (var k = 0; k < 3; k++) {
          var start = math.pi * (1.22 + k * 0.2);
          canvas.drawArc(ring, start, math.pi * 0.13, false,
              _feature(u * (0.03 - k * 0.004), shineColour.withValues(alpha: 0.7)));
        }
      case _Hair.soft || _Hair.flowing:
        canvas.drawOval(
            Rect.fromCenter(
                center: Offset(-w * 0.3, -h * 0.72), width: w * 0.9, height: h * 0.32),
            Paint()
              ..shader = ui.Gradient.radial(Offset(-w * 0.3, -h * 0.72), w * 0.45,
                  [light.withValues(alpha: 0.55), light.withValues(alpha: 0)]));
      case _Hair.strands:
        var dark = _shade(dna.hair, 0.35).withValues(alpha: 0.6);
        for (var k = 0; k < 7; k++) {
          var x = -w * 0.9 + w * 1.8 * k / 6;
          canvas.drawPath(
              Path()
                ..moveTo(x * 0.3, -h * 1.05)
                ..quadraticBezierTo(x * 0.9, -h * 0.8, x, -h * 0.25),
              _feature(u * 0.012, k.isEven ? dark : light.withValues(alpha: 0.5)));
        }
      case _Hair.plain:
        break;
    }
    canvas.restore();
  }

  /// _nose is the nose: a hook straight on, and turned past a ¾ view a
  /// point standing out from the side of the face.
  void _nose(double w, {required bool front}) {
    var side = math.sin(yaw);
    var y = u * 0.12 + _nodShift - _a(Look.noseHeight) * u * 0.05;
    var nw = 1 + 0.5 * _a(Look.noseWidth);
    var nl = 1 + 0.45 * _a(Look.noseLength);
    if (side.abs() < 0.55) {
      if (!front) return;
      var x = _across(0, w * 0.95);
      var ink = _shade(dna.skin, 0.45);
      switch (look.nose) {
        case _Nose.none:
          return;
        case _Nose.tick:
          // Anime's nose: a short tick, or a hint of shadow under it.
          canvas.drawLine(Offset(x + u * 0.004, y + u * 0.05 * nl),
              Offset(x - u * 0.014 * nw, y + u * 0.085 * nl),
              _feature(u * 0.022, ink.withValues(alpha: 0.8)));
          return;
        case _Nose.small:
          canvas.drawPath(
              Path()
                ..moveTo(x - u * 0.005, y + u * 0.04 * nl)
                ..quadraticBezierTo(x - u * 0.03 * nw, y + u * 0.085 * nl,
                    x + u * 0.01 * nw, y + u * 0.085 * nl),
              _feature(u * 0.022, ink));
          return;
        case _Nose.shaded:
          // Lit from the left: a shadow down the right of the nose and
          // under it, and light on its tip.
          canvas.drawOval(
              Rect.fromCenter(
                  center: Offset(x + u * 0.03 * nw, y + u * 0.05 * nl),
                  width: u * 0.05 * nw,
                  height: u * 0.12 * nl),
              Paint()
                ..color = _shade(dna.skin, 0.2).withValues(alpha: 0.5)
                ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 0.02));
          canvas.drawOval(
              Rect.fromCenter(
                  center: Offset(x, y + u * 0.1 * nl),
                  width: u * 0.1 * nw,
                  height: u * 0.03),
              Paint()
                ..color = _shade(dna.skin, 0.25).withValues(alpha: 0.45)
                ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 0.012));
          canvas.drawCircle(Offset(x - u * 0.01, y + u * 0.07 * nl), u * 0.018,
              Paint()..color = const Color(0x40FFFFFF));
          return;
        case _Nose.shaped:
          break;
      }
      canvas.drawPath(
          Path()
            ..moveTo(x, y - u * 0.06 * (nl - 1))
            ..quadraticBezierTo(
                x + u * 0.05 * nw * (side >= 0 ? -1 : 1).toDouble() * -1,
                y + u * 0.07 * nl,
                x - u * 0.01 * nw,
                y + u * 0.08 * nl),
          _feature(u * 0.03, ink));
      var bridge = _a(Look.noseBridge);
      if (bridge > 0) {
        // A prominent bridge, a line down from between the eyes.
        canvas.drawLine(
            Offset(x - u * 0.012, y - u * 0.1),
            Offset(x - u * 0.01, y + u * 0.02),
            _feature(u * 0.016, ink.withValues(alpha: 0.2 + 0.5 * bridge)));
      }
      var tip = _a(Look.noseTip);
      if (tip > 0) {
        // A rounder tip: the curve under it.
        canvas.drawArc(
            Rect.fromCircle(
                center: Offset(x, y + u * 0.07 * nl),
                radius: u * 0.035 * (1 + tip) * nw),
            math.pi * 0.15,
            math.pi * 0.7,
            false,
            _feature(u * 0.02, ink.withValues(alpha: 0.6)));
      }
      var nostrils = _a(Look.nostrils);
      if (nostrils > 0) {
        for (var s in [-1.0, 1.0]) {
          canvas.drawOval(
              Rect.fromCenter(
                  center: Offset(x + s * u * 0.035 * nw, y + u * 0.085 * nl),
                  width: u * 0.022 * (1 + nostrils * 0.5),
                  height: u * 0.014 * (1 + nostrils * 0.5)),
              Paint()..color = ink.withValues(alpha: 0.35 + 0.5 * nostrils));
        }
      }
      return;
    }
    if (front) return;
    // In profile: a point past the outline, which way the face is turned.
    var dir = side > 0 ? -1.0 : 1.0;
    var x = _across(0, w * 0.97);
    var out = u * 0.13 * (side.abs() - 0.45).clamp(0.0, 0.55) / 0.55 *
        (1 + 0.5 * _a(Look.noseBridge)) * nl;
    var tip = Path()
      ..moveTo(x, y - u * 0.04 * nl)
      ..lineTo(x + dir * out, y + u * 0.1 * nl)
      ..lineTo(x, y + u * 0.13 * nl)
      ..close();
    _fill(tip, dna.skin);
  }

  void _face(double w, {bool onModel = false}) {
    var dy = _nodShift;
    var eyeY = u * 0.06 + dy - _a(Look.eyeHeight) * u * 0.06;
    var lid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = edge
      ..color = _shade(dna.skin);
    var lookX = (face[FaceControl.lookX] + life.lookX).clamp(-1.0, 1.0);
    var lookY = (face[FaceControl.lookY] + life.lookY).clamp(-1.0, 1.0);
    var open = face[FaceControl.eyesOpen] * (1 - life.blink);
    var squint = face[FaceControl.squint];
    var eyeSides = switch (dna.eyeCount) {
      1 => [0.0],
      3 => [-1.0, 0.0, 1.0],
      _ => [-1.0, 1.0],
    };
    for (var side in eyeSides) {
      // One eye is in the middle and big; a third sits above the other two.
      var cyclops = dna.eyeCount == 1;
      var phi = side * 0.42 * (1 + 0.22 * _a(Look.eyeSpacing));
      var toward = _toward(phi);
      if (toward < 0.12) continue;
      var c = Offset(_eyesAt?[side] ?? _across(phi, w), eyeY);
      if (side == 0 && !cyclops) c = c + Offset(0, -u * 0.14);
      var size = 1 + 0.3 * _a(Look.eyeSize);
      var shape = _a(Look.eyeShape);
      var ew = u * 0.17 * toward * size * (1 + 0.12 * shape);
      var eh = u * 0.21 * size * (1 - 0.3 * shape);
      if (cyclops) {
        ew *= 1.8;
        eh *= 1.6;
      }
      // Each style's eye its own size and shape.
      var (kw, kh, drop) = _eyeKit;
      ew *= kw;
      eh *= kh;
      c = c + Offset(0, u * drop);
      _inBody(BodyLayer.eyes, () {
      // Set as the panel's face has it.
      canvas.save();
      if (side != 0) _setAbout(faceRig[side > 0 ? FacePoint.eyeL : FacePoint.eyeR], c);
      // Tipped up or down at the outer corner.
      canvas.save();
      if (_a(Look.eyeTilt) != 0 && side != 0) {
        canvas.translate(c.dx, c.dy);
        canvas.rotate(-side * _a(Look.eyeTilt) * 0.22);
        canvas.translate(-c.dx, -c.dy);
      }
      var height = eh * open * (1 - 0.45 * squint);
      if (height < eh * 0.14) {
        // Shut: a curve where the lid meets.
        canvas.drawPath(
            Path()
              ..moveTo(c.dx - ew / 2, c.dy)
              ..quadraticBezierTo(c.dx, c.dy + eh * 0.22, c.dx + ew / 2, c.dy),
            _feature(u * 0.028, _shade(dna.skin, 0.55)));
      } else {
        // A squint pushes up from below, so the eye keeps its top.
        var box = Rect.fromLTWH(c.dx - ew / 2,
            c.dy - eh / 2 + (eh - height) * (squint > 0 ? 0.25 : 0.5), ew, height);
        _eye(box, c, side, toward, lookX, lookY, lid);
      }
      canvas.restore();
      canvas.restore();
      });
      if (side != 0) {
        _inBody(
            BodyLayer.brows,
            () => _setFeature(side > 0 ? FacePoint.browL : FacePoint.browR, _browAt(c),
                () => _brow(c, side, toward)));
      }
      if (toward > 0.3) {
        canvas.drawOval(
            Rect.fromCenter(
                center: Offset(_across(side * 0.62, w), u * 0.24 + dy),
                width: u * 0.14 * toward,
                height: u * 0.08),
            Paint()
              ..color = const Color(0xFFFF7B7B).withValues(
                  alpha: (0.22 + 0.2 * face[FaceControl.smile] + 0.35 * _a(Look.blush))
                      .clamp(0.0, 0.65)));
        if (look.hatch) {
          // Anime's blush: short strokes across the cheek.
          var at = Offset(_across(side * 0.62, w), u * 0.24 + dy);
          var stroke = _feature(u * 0.011, const Color(0xFFD9485A).withValues(alpha: 0.6));
          for (var k = -1; k <= 1; k++) {
            var o = at + Offset(k * u * 0.035 * toward, 0);
            canvas.drawLine(o + Offset(u * 0.012, -u * 0.02),
                o + Offset(-u * 0.012, u * 0.02), stroke);
          }
        }
      }
    }
    // On a head in 3D, its own nose, skin and beard are already there.
    if (onModel) {
      _inBody(BodyLayer.mouth, () => _mouth(w));
      return;
    }
    if (!dna.species.animal) _skinMarks(w);
    if (dna.species.animal) {
      _muzzle(w);
    } else {
      _inBody(BodyLayer.nose,
          () => _setFeature(FacePoint.nose, _noseAt(w), () => _nose(w, front: true)));
    }
    if (!dna.species.animal) _beard(w);
    // A beak is a bird's mouth.
    if (dna.species != Species.bird) _inBody(BodyLayer.mouth, () => _mouth(w));
    if (!dna.species.animal) _moustache(w);
    if (dna.fangs) _inBody(BodyLayer.mouth, () => _fangs(w));
  }

  /// _skinMarks are freckles, the lines of age and the shine on the skin.
  void _skinMarks(double w) {
    var dy = _nodShift;
    var freckles = _a(Look.freckles);
    if (freckles > 0) {
      var dot = Paint()
        ..color = Color.lerp(dna.skin, const Color(0xFF6B3A1E), 0.5)!
            .withValues(alpha: 0.75);
      var n = (freckles * 26).round();
      for (var k = 0; k < n; k++) {
        // Across the nose and over the cheeks, under the eyes.
        var phi = (_seed(k * 2) - 0.5) * 1.5;
        if (_toward(phi) < 0.25) continue;
        var y = u * (0.15 + 0.12 * _seed(k * 2 + 1)) + dy;
        canvas.drawCircle(Offset(_across(phi, w * 0.95), y),
            u * (0.008 + 0.006 * _seed(k + 99)), dot);
      }
    }
    var age = _a(Look.age);
    if (age > 0) {
      var line = _feature(u * 0.013, _shade(dna.skin, 0.4).withValues(alpha: 0.35 + 0.5 * age));
      // From the side of the nose down to the corners of the mouth.
      for (var s in [-1.0, 1.0]) {
        var phi = s * 0.32;
        if (_toward(phi) < 0.2) continue;
        var top = Offset(_across(phi * 0.7, w * 0.95), u * 0.16 + dy);
        var bottom = Offset(_across(phi * 1.15, w * 0.93), u * 0.32 + dy);
        canvas.drawPath(
            Path()
              ..moveTo(top.dx, top.dy)
              ..quadraticBezierTo(
                  top.dx + s * u * 0.04 * math.cos(yaw), (top.dy + bottom.dy) / 2,
                  bottom.dx, bottom.dy),
            line);
        // Lines at the outer corners of the eyes.
        var eye = Offset(_across(s * 0.62, w), u * 0.06 + dy);
        if (_toward(s * 0.62) > 0.2) {
          for (var k = -1; k <= 1; k++) {
            canvas.drawLine(eye + Offset(s * u * 0.02, k * u * 0.025),
                eye + Offset(s * u * 0.07, k * u * 0.04), line);
          }
        }
      }
      // Across the forehead.
      if (facing > 0.3) {
        for (var k = 0; k < 2; k++) {
          var y = -u * (0.17 + 0.06 * k) + dy;
          var x = _across(0, w);
          canvas.drawPath(
              Path()
                ..moveTo(x - u * 0.18 * facing, y)
                ..quadraticBezierTo(x, y - u * 0.03, x + u * 0.18 * facing, y),
              line);
        }
      }
    }
    var shine = _a(Look.shine);
    if (shine > 0 && facing > 0.2) {
      var glint = Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.18 + 0.3 * shine);
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(_across(-0.25, w), -u * 0.3 + dy),
              width: u * 0.16 * facing,
              height: u * 0.07),
          glint);
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(_across(-0.55, w), u * 0.18 + dy),
              width: u * 0.08 * facing,
              height: u * 0.05),
          glint);
    }
  }

  /// _beard is stubble and a beard: hair over the lower face, longer down
  /// the chin, with the mouth drawn over it.
  void _beard(double w) {
    var stubble = _a(Look.stubble), beard = _a(Look.beard);
    if (stubble <= 0 && beard <= 0) return;
    var r = rig.headRadii;
    var dy = _nodShift;
    var face = _headPath(w, r.height);
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(-w * 3, u * 0.18 + dy, w * 3, r.height * 4));
    if (stubble > 0) {
      canvas.save();
      canvas.clipPath(face);
      canvas.drawRect(Rect.fromLTRB(-w * 2, u * 0.18 + dy, w * 2, r.height * 2),
          Paint()..color = dna.hair.withValues(alpha: 0.12 + 0.3 * stubble));
      canvas.restore();
    }
    if (beard > 0) {
      var long = 1.05 + 0.55 * _a(Look.beardLength);
      // Little beard is a goatee on the chin; more of it reaches round the
      // jaw to the ears.
      var spread = (0.35 + 0.65 * beard).clamp(0.0, 1.0);
      var cx = _across(0, w * 0.88);
      var half = w * spread * 1.02;
      var top = u * 0.2 + dy;
      var shape = Path()
        ..moveTo(cx - half, top - u * 0.1 * spread)
        ..quadraticBezierTo(cx - half * 1.02, r.height * long * 0.95,
            cx, r.height * long + dy)
        ..quadraticBezierTo(cx + half * 1.02, r.height * long * 0.95,
            cx + half, top - u * 0.1 * spread)
        ..lineTo(cx + half * 0.5, top + u * 0.04)
        ..quadraticBezierTo(cx, top + u * 0.02, cx - half * 0.5, top + u * 0.04)
        ..close();
      _fill(shape, dna.hair);
      _highlights(shape, w, r.height * long);
    }
    canvas.restore();
  }

  /// _moustache is over the top lip, drawn after the mouth.
  void _moustache(double w) {
    var m = _a(Look.moustache);
    if (m <= 0 || facing < 0.1) return;
    var at = Offset(_across(0, w * 0.88),
        u * 0.255 + _nodShift - _a(Look.mouthHeight) * u * 0.05);
    var across = 0.35 + 0.65 * facing.clamp(0.0, 1.0);
    var half = u * (0.08 + 0.07 * m) * across;
    var thick = u * (0.02 + 0.04 * m);
    var shape = Path()
      ..moveTo(at.dx - half, at.dy + thick * 0.6)
      ..quadraticBezierTo(at.dx - half * 0.5, at.dy - thick, at.dx, at.dy - thick * 0.6)
      ..quadraticBezierTo(at.dx + half * 0.5, at.dy - thick, at.dx + half, at.dy + thick * 0.6)
      ..quadraticBezierTo(at.dx, at.dy + thick * 0.3, at.dx - half, at.dy + thick * 0.6)
      ..close();
    _fill(shape, dna.hair);
  }

  // ---- what a creature has that a person does not ----

  /// _animalEars are a species' ears, on top of the head, going round with
  /// it: pointed for a cat or a fox, floppy for a dog, round for a bear or
  /// a mouse, long for a rabbit.
  void _animalEars(double w, double h) {
    for (var side in [-1.0, 1.0]) {
      var phi = side * 0.6;
      if (_toward(phi) < -0.5) continue;
      var x = _across(phi, w * 0.9);
      var base = Offset(x, -h * 0.72);
      var ear = Path();
      var inner = Path();
      switch (dna.species) {
        case Species.cat || Species.fox || Species.monster || Species.horse:
          var tall = dna.species == Species.fox
              ? 0.75
              : dna.species == Species.horse
                  ? 0.7
                  : 0.6;
          ear.addPolygon([
            base + Offset(-w * 0.32, h * 0.15),
            base + Offset(side * w * 0.12, -h * tall),
            base + Offset(w * 0.32, h * 0.15),
          ], true);
          inner.addPolygon([
            base + Offset(-w * 0.17, h * 0.08),
            base + Offset(side * w * 0.08, -h * tall * 0.7),
            base + Offset(w * 0.17, h * 0.08),
          ], true);
        case Species.dog:
          // Hanging down the side of the head.
          var at = Offset(_across(side * 1.25, w), -h * 0.35);
          ear.addOval(Rect.fromCenter(
              center: at + Offset(0, h * 0.45), width: w * 0.42, height: h * 1.0));
        case Species.bear || Species.mouse || Species.hedgehog:
          var r = switch (dna.species) {
            Species.mouse => w * 0.42,
            Species.hedgehog => w * 0.2,
            _ => w * 0.3,
          };
          ear.addOval(Rect.fromCircle(center: base + Offset(side * w * 0.12, 0), radius: r));
          inner.addOval(Rect.fromCircle(center: base + Offset(side * w * 0.12, 0), radius: r * 0.55));
        case Species.rabbit:
          ear.addOval(Rect.fromCenter(
              center: base + Offset(side * w * 0.08, -h * 0.75), width: w * 0.42, height: h * 1.5));
          inner.addOval(Rect.fromCenter(
              center: base + Offset(side * w * 0.08, -h * 0.7), width: w * 0.2, height: h * 1.1));
        case Species.pig:
          ear.addPolygon([
            base + Offset(-w * 0.28, h * 0.1),
            base + Offset(side * w * 0.38, -h * 0.4),
            base + Offset(w * 0.28, h * 0.1),
          ], true);
        case Species.human || Species.bird || Species.fish:
          break;
      }
      if (ear.getBounds().isEmpty) continue;
      _fill(ear, dna.skin);
      if (!inner.getBounds().isEmpty) {
        canvas.drawPath(inner, Paint()..color = dna.fur2);
      }
    }
  }

  /// _muzzle is a creature's muzzle -- lighter fur round its nose and mouth,
  /// longer on a dog or a fox -- its nose, and whiskers where it has them.
  void _muzzle(double w) {
    var sp = dna.species;
    if (sp == Species.fish) return;
    if (sp == Species.bird) {
      // A beak, pointing the way the face does.
      var side = math.sin(yaw);
      var at = Offset(_across(0, w * 0.92), u * 0.16 + _nodShift);
      var long = u * (0.14 + 0.16 * side.abs());
      var beak = Path()
        ..moveTo(at.dx - u * 0.09 * (1 - 0.5 * side.abs()), at.dy - u * 0.05)
        ..lineTo(at.dx - side * long, at.dy + u * 0.06)
        ..lineTo(at.dx + u * 0.09 * (1 - 0.5 * side.abs()), at.dy - u * 0.05)
        ..quadraticBezierTo(at.dx, at.dy + u * 0.12, at.dx - u * 0.09 * (1 - 0.5 * side.abs()), at.dy - u * 0.05)
        ..close();
      _fill(beak, dna.fur2);
      return;
    }
    var cx = _across(0, w * 0.9);
    var y = u * 0.2 + _nodShift;
    var long = sp == Species.dog ||
        sp == Species.fox ||
        sp == Species.bear ||
        sp == Species.horse ||
        sp == Species.hedgehog;
    var mw = u * (long ? 0.42 : 0.32) * (0.6 + 0.4 * facing.abs());
    var mh = u * (long ? 0.3 : 0.22);
    // Side on, a long muzzle sticks out past the face.
    var out = math.sin(yaw) * (long ? -u * 0.18 : -u * 0.08);
    var at = Offset(cx + out, y);
    if (sp == Species.pig) {
      // A snout: a disc with two nostrils.
      var disc = Rect.fromCenter(center: at, width: u * 0.26, height: u * 0.18);
      _fill(Path()..addOval(disc), Color.lerp(dna.skin, const Color(0xFFE07A8A), 0.4)!);
      for (var s in [-1.0, 1.0]) {
        canvas.drawOval(
            Rect.fromCenter(center: at + Offset(s * u * 0.05, 0), width: u * 0.04, height: u * 0.07),
            Paint()..color = const Color(0xFF5A2A2A));
      }
      return;
    }
    _fill(Path()..addOval(Rect.fromCenter(center: at, width: mw, height: mh)), dna.fur2);
    var nose = Path()
      ..moveTo(at.dx - u * 0.06, at.dy - mh * 0.32)
      ..lineTo(at.dx + u * 0.06, at.dy - mh * 0.32)
      ..quadraticBezierTo(at.dx, at.dy - mh * 0.02, at.dx - u * 0.06, at.dy - mh * 0.32)
      ..close();
    _fill(nose, const Color(0xFF2A1A16));
    if (sp == Species.cat || sp == Species.mouse || sp == Species.rabbit || sp == Species.fox) {
      var whisker = _feature(u * 0.012, const Color(0xAA2A1A16));
      for (var s in [-1.0, 1.0]) {
        for (var k = 0; k < 2; k++) {
          var from = at + Offset(s * mw * 0.3, k * u * 0.03);
          canvas.drawLine(from, from + Offset(s * u * 0.28, (k - 0.5) * u * 0.08), whisker);
        }
      }
    }
  }

  /// _fangs are two teeth hanging from the top lip at the mouth's corners.
  void _fangs(double w) {
    var at = Offset(_across(0, w * 0.88), u * 0.3 + _nodShift);
    var white = Paint()..color = const Color(0xFFFAFAF2);
    for (var s in [-1.0, 1.0]) {
      var x = at.dx + s * u * 0.06 * (0.4 + 0.6 * facing.abs());
      var fang = Path()
        ..moveTo(x - u * 0.025, at.dy - u * 0.005)
        ..lineTo(x + u * 0.025, at.dy - u * 0.005)
        ..lineTo(x, at.dy + u * 0.07)
        ..close();
      canvas.drawPath(fang, white);
      _outline(fang, const Color(0xFFFAFAF2));
    }
  }

  /// _horns are on top of the head, in the lighter colour: two short
  /// points, a ram's curls, or antlers.
  void _horns(double w, double h) {
    if (dna.horns == HornKind.none) return;
    for (var side in [-1.0, 1.0]) {
      var phi = side * 0.45;
      if (_toward(phi) < -0.4) continue;
      var base = Offset(_across(phi, w * 0.85), -h * 0.78);
      switch (dna.horns) {
        case HornKind.small:
          var horn = Path()
            ..moveTo(base.dx - w * 0.14, base.dy + h * 0.08)
            ..quadraticBezierTo(base.dx + side * w * 0.05, base.dy - h * 0.25,
                base.dx + side * w * 0.2, base.dy - h * 0.48)
            ..quadraticBezierTo(base.dx + side * w * 0.12, base.dy - h * 0.1,
                base.dx + w * 0.14, base.dy + h * 0.08)
            ..close();
          _fill(horn, dna.fur2);
        case HornKind.ram:
          // A curl round the side of the head.
          var curl = Path()..moveTo(base.dx, base.dy);
          for (var k = 1; k <= 24; k++) {
            var a = k / 24 * math.pi * 1.7;
            var r = w * (0.45 - 0.012 * k);
            curl.lineTo(base.dx + side * (r * math.sin(a)),
                base.dy + h * 0.35 - r * math.cos(a));
          }
          canvas.drawPath(
              curl,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeCap = StrokeCap.round
                ..strokeWidth = w * 0.2
                ..color = dna.fur2);
          canvas.drawPath(curl, _edgePaint(dna.fur2)..strokeWidth = edge);
        case HornKind.antlers:
          var stem = [base, base + Offset(side * w * 0.25, -h * 0.7)];
          _stroke(stem, w * 0.1, dna.fur2);
          _stroke([base + Offset(side * w * 0.1, -h * 0.3), base + Offset(side * w * 0.45, -h * 0.5)],
              w * 0.08, dna.fur2);
          _stroke([base + Offset(side * w * 0.2, -h * 0.55), base + Offset(-side * w * 0.05, -h * 0.85)],
              w * 0.08, dna.fur2);
        case HornKind.none:
          break;
      }
    }
  }

  /// _spikes are a row of points along the top of the head, behind it.
  void _spikes(double w, double h) {
    for (var k = 0; k < 5; k++) {
      var a = math.pi * (1.15 + k * 0.7 / 4);
      var at = Offset(math.cos(a) * w * 0.95, math.sin(a) * h * 0.95);
      var dir = Offset(math.cos(a), math.sin(a));
      var side = Offset(-dir.dy, dir.dx);
      _fill(
          Path()
            ..addPolygon([
              at + side * (w * 0.13),
              at + dir * (h * 0.38),
              at - side * (w * 0.13),
            ], true),
          dna.fur2);
    }
  }

  /// _tail grows from the back of the hips, out the way the body is not
  /// facing -- to the side, facing the reader.
  void _tail() {
    if (dna.species == Species.bird && dna.tail == TailKind.none) {
      _tailFeathers();
      return;
    }
    if (dna.tail == TailKind.none) return;
    var side = math.sin(rig.yaw * math.pi / 180);
    var back = side.abs() < 0.3 ? 1.0 : side.sign;
    var root = rig.hips + Offset(back * rig.hipHalf * 0.6, -legWidth * 0.2);
    var t = u;
    switch (dna.tail) {
      case TailKind.long:
        _strokeCurve(root, root + Offset(back * t * 0.9, -t * 0.2),
            root + Offset(back * t * 1.3, -t * 0.9), legWidth * 0.32, dna.skin);
      case TailKind.bushy:
        var tip = root + Offset(back * t * 1.1, -t * 0.9);
        var tail = Path()
          ..moveTo(root.dx, root.dy - t * 0.1)
          ..quadraticBezierTo(root.dx + back * t * 1.4, root.dy + t * 0.1, tip.dx, tip.dy)
          ..quadraticBezierTo(root.dx + back * t * 0.4, root.dy - t * 0.5, root.dx, root.dy + t * 0.12)
          ..close();
        _fill(tail, dna.skin);
        canvas.save();
        canvas.clipPath(tail);
        canvas.drawCircle(tip, t * 0.3, Paint()..color = dna.fur2);
        canvas.restore();
      case TailKind.curly:
        var curl = Path()..moveTo(root.dx, root.dy);
        for (var k = 1; k <= 30; k++) {
          var a = k / 30 * math.pi * 3;
          var r = t * 0.1 * (1 - k / 40);
          curl.lineTo(root.dx + back * (t * 0.15 + r * math.cos(a)), root.dy - t * 0.1 - r * math.sin(a));
        }
        canvas.drawPath(
            curl,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = t * 0.05
              ..color = dna.skin);
      case TailKind.stub:
        _fill(Path()..addOval(Rect.fromCircle(center: root, radius: t * 0.16)), dna.fur2);
      case TailKind.dragon:
        var end = root + Offset(back * t * 1.6, t * 0.1);
        _strokeCurve(root, root + Offset(back * t * 0.8, t * 0.5), end, legWidth * 0.5, dna.skin);
        _fill(
            Path()
              ..addPolygon([
                end + Offset(0, -t * 0.14),
                end + Offset(back * t * 0.3, 0),
                end + Offset(0, t * 0.14),
              ], true),
            dna.fur2);
      case TailKind.none:
        break;
    }
  }

  /// _wings grow from the shoulders, behind the body: feathers in fans, or
  /// a bat's stretched between long fingers.
  void _wings() {
    if (dna.wings == WingKind.none) return;
    var side = math.sin(rig.yaw * math.pi / 180);
    for (var s in [-1.0, 1.0]) {
      // Side on, only the far wing shows, behind.
      if (side.abs() > 0.7 && s != side.sign) continue;
      var root = rig.chest + Offset(s * rig.shoulderHalf * 0.5, 0);
      var span = rig.shoulderHalf * 2.6;
      var out = side.abs() > 0.7 ? -side.sign : s;
      // Raised as far as the flap says, about where it grows from.
      canvas.save();
      canvas.translate(root.dx, root.dy);
      canvas.rotate(-out * rig.wingFlap * 0.8 * math.pi / 180);
      canvas.translate(-root.dx, -root.dy);
      if (dna.wings == WingKind.feathered) {
        for (var k = 0; k < 3; k++) {
          var a = -0.9 + k * 0.45;
          var tip = root + Offset(out * span * math.cos(a) * (1 - k * 0.15), span * math.sin(a) * 0.8);
          _fill(
              Path()
                ..addOval(Rect.fromPoints(root, tip).inflate(u * 0.05)),
              Color.lerp(dna.fur2, dna.skin, k * 0.2)!);
        }
      } else {
        var top = root + Offset(out * span * 0.6, -span * 0.75);
        var tip = root + Offset(out * span, -span * 0.2);
        var membrane = Path()
          ..moveTo(root.dx, root.dy)
          ..lineTo(top.dx, top.dy)
          ..lineTo(tip.dx, tip.dy)
          ..quadraticBezierTo(root.dx + out * span * 0.75, root.dy + span * 0.05,
              root.dx + out * span * 0.55, root.dy + span * 0.25)
          ..quadraticBezierTo(root.dx + out * span * 0.35, root.dy + span * 0.05,
              root.dx + out * span * 0.2, root.dy + span * 0.3)
          ..close();
        _fill(membrane, Color.lerp(dna.skin, const Color(0xFF000000), 0.18)!);
        _stroke([root, top, tip], u * 0.05, dna.skin);
      }
      canvas.restore();
    }
  }

  /// _birdWing is a bird's arm drawn as a wing: feathers fanned along it,
  /// longest at the tip, lighter at the edge.
  void _birdWing(Offset shoulder, Offset elbow, Offset wrist, double side) {
    var along = wrist - shoulder;
    if (along.distance < 1e-6) return;
    var out = Offset(-along.dy, along.dx) / along.distance;
    // The feathers hang below the arm, whichever way it points.
    if (out.dy < 0) out = -out;
    var width = rig.shoulderHalf * 0.9;
    var wing = Path()
      ..moveTo(shoulder.dx, shoulder.dy)
      ..quadraticBezierTo(elbow.dx, elbow.dy, wrist.dx, wrist.dy);
    for (var k = 4; k >= 0; k--) {
      var at = Offset.lerp(shoulder, wrist, k / 4)!;
      var reach = width * (0.6 + 0.5 * k / 4);
      wing.lineTo(at.dx + out.dx * reach, at.dy + out.dy * reach);
    }
    wing.close();
    _fill(wing, dna.skin);
    canvas.save();
    canvas.clipPath(wing);
    var tips = Paint()..color = Color.lerp(dna.skin, dna.fur2, 0.45)!;
    for (var k = 0; k <= 4; k++) {
      var at = Offset.lerp(shoulder, wrist, k / 4)!;
      var reach = width * (0.6 + 0.5 * k / 4);
      canvas.drawCircle(at + out * reach, width * 0.28, tips);
    }
    canvas.restore();
  }

  /// _toes are a bird's three toes, spread on the ground.
  void _toes(CharacterLimb limb) {
    var ankle = _end(limb);
    var drop = rig.below * CharacterRig.footDrop;
    var side = math.sin(rig.yaw * math.pi / 180);
    var forward = side.abs() > 0.5 ? -side.sign : 0.0;
    var toe = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = legWidth * 0.18
      ..color = dna.fur2;
    for (var k = -1; k <= 1; k++) {
      var dir = Offset(k * 0.6 + forward * 0.8, 1).scale(1, 1);
      var tip = ankle + Offset(dir.dx * legWidth * 0.9, drop * 0.9);
      if (lined) {
        canvas.drawLine(ankle, tip,
            Paint()
              ..strokeCap = StrokeCap.round
              ..strokeWidth = legWidth * 0.18 + edge * 2
              ..color = _inkFor(dna.fur2));
      }
      canvas.drawLine(ankle, tip, toe);
    }
  }

  /// _fin is a small fin from a fish's side, pointing as the arm would.
  void _fin(Offset shoulder, Offset elbow) {
    var d = elbow - shoulder;
    if (d.distance < 1e-6) return;
    var dir = d / d.distance;
    var across = Offset(-dir.dy, dir.dx);
    var len = rig.shoulderHalf * 1.1;
    _fill(
        Path()
          ..addPolygon([
            shoulder + across * (len * 0.25),
            shoulder + dir * len,
            shoulder - across * (len * 0.25),
          ], true),
        Color.lerp(dna.skin, dna.fur2, 0.5)!);
  }

  /// _fishBody is a fish: a long rounded body from its tail to its head,
  /// lighter underneath, and a forked tail fin that flicks as it sways.
  void _fishBody() {
    var thick = rig.hipHalf * 3.2;
    var tail = rig.hips, front = rig.neck;
    var along = front - tail;
    var dir = along.distance < 1e-6 ? const Offset(1, 0) : along / along.distance;
    var across = Offset(-dir.dy, dir.dx);
    // The tail fin, behind the body.
    var fin = tail - dir * (thick * 0.25);
    var flick = across * (thick * 0.2 * math.sin(rig.bodyTurn * math.pi / 30));
    _fill(
        Path()
          ..addPolygon([
            fin,
            fin - dir * thick * 0.9 + across * thick * 0.65 + flick,
            fin - dir * thick * 0.55 + flick,
            fin - dir * thick * 0.9 - across * thick * 0.65 + flick,
          ], true),
        Color.lerp(dna.skin, dna.fur2, 0.35)!);
    _stroke([tail, front], thick, dna.skin);
    var belly = Path()
      ..addOval(Rect.fromCenter(
          center: Offset.lerp(tail, front, 0.55)! + Offset(0, thick * 0.22),
          width: along.distance * 0.9,
          height: thick * 0.4));
    canvas.save();
    canvas.clipPath(_capsule([tail, front], thick));
    canvas.drawPath(belly, Paint()..color = dna.fur2);
    canvas.restore();
  }

  /// _tailFeathers are a bird's tail: a short fan from the back of the hips.
  void _tailFeathers() {
    var side = math.sin(rig.yaw * math.pi / 180);
    var back = side.abs() < 0.3 ? 0.0 : side.sign;
    var root = rig.hips + Offset(back * rig.hipHalf * 0.5, 0);
    for (var k = -1; k <= 1; k++) {
      var tip = root + Offset(back * u * 0.55 + k * u * 0.18, u * 0.35 + (back == 0 ? u * 0.15 : 0));
      _fill(
          Path()
            ..addOval(Rect.fromPoints(root, tip).inflate(u * 0.05)),
          Color.lerp(dna.skin, const Color(0xFF000000), 0.1 + 0.05 * k.abs())!);
    }
  }

  /// _strokeCurve is a band [width] wide along a curve from [a] through
  /// [mid] to [b].
  void _strokeCurve(Offset a, Offset mid, Offset b, double width, Color colour) {
    var path = Path()
      ..moveTo(a.dx, a.dy)
      ..quadraticBezierTo(mid.dx, mid.dy, b.dx, b.dy);
    Paint stroke(double w, Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w
      ..color = c;
    if (lined) canvas.drawPath(path, stroke(width + edge * 2, _inkFor(colour)));
    canvas.drawPath(path, stroke(width, colour));
  }

  /// _pieEye is a 1930s cartoon eye: a black oval with a slice cut out of
  /// it for the shine, the slice moving with where it looks.
  void _pieEye(Rect box, double lookX, double lookY, double toward) {
    var eye = Rect.fromCenter(
        center: box.center + Offset(lookX * u * 0.02, -lookY * u * 0.02),
        width: box.width * 0.75,
        height: box.height * 1.05);
    canvas.drawOval(eye, Paint()..color = const Color(0xFF151515));
    if (toward > 0.4) {
      canvas.drawArc(eye.deflate(eye.width * 0.08), -math.pi * 0.45,
          math.pi * 0.28, true, Paint()..color = const Color(0xFFFAFAFA));
    }
  }

  /// _eye draws an open eye in [box], centred on [c], on [side] of the
  /// face, turned [toward] the reader, looking [lookX] across and [lookY]
  /// up -- as the style's kit draws eyes.
  void _eye(Rect box, Offset c, double side, double toward, double lookX,
      double lookY, Paint lid) {
    const dark = Color(0xFF1B1512);
    var white = Paint()..color = const Color(0xFFFFFFFF);
    var kind = look.eyes;
    if (kind == _Eyes.pie) {
      _pieEye(box, lookX, lookY, toward);
      return;
    }
    var outer = side == 0 ? 1.0 : side;
    var shift = Offset(lookX * box.width * 0.2, -lookY * box.height * 0.16);
    if (kind == _Eyes.dot) {
      // A dark oval with a dot of light.
      var dot = Rect.fromCenter(
          center: c + shift * 0.6, width: box.width * 0.62, height: box.height);
      canvas.drawOval(dot, Paint()..color = dark);
      canvas.drawCircle(
          dot.center + Offset(-dot.width * 0.2, -dot.height * 0.22),
          dot.width * 0.2,
          white);
      _lashes(box, outer, toward);
      return;
    }

    // The white of the eye: an oval, or an almond with its corners.
    var almond = kind == _Eyes.shonen ||
        kind == _Eyes.fine ||
        kind == _Eyes.real ||
        kind == _Eyes.feature;
    Path whites;
    if (almond) {
      var lift = box.height * 0.08 * outer;
      whites = Path()
        ..moveTo(box.left, box.center.dy + lift)
        ..quadraticBezierTo(box.center.dx - box.width * 0.05,
            box.top - box.height * 0.22, box.right, box.center.dy - lift)
        ..quadraticBezierTo(box.center.dx + box.width * 0.05,
            box.bottom + box.height * 0.12, box.left, box.center.dy + lift)
        ..close();
    } else {
      var narrow = kind == _Eyes.soft ? 0.7 : 1.0;
      whites = Path()
        ..addOval(Rect.fromCenter(
            center: box.center,
            width: box.width * narrow,
            height: box.height));
    }
    canvas.drawPath(whites, white);
    canvas.save();
    canvas.clipPath(whites);

    // The iris: how much of the eye, and how it is coloured.
    var irisK = 1 + 0.35 * _a(Look.iris);
    var (fw, fh) = switch (kind) {
      _Eyes.anime => (0.66, 0.92),
      _Eyes.shojo => (0.74, 0.98),
      _Eyes.shonen => (0.46, 0.72),
      _Eyes.soft => (0.62, 0.9),
      _Eyes.fine => (0.5, 0.78),
      _Eyes.glossy => (0.64, 0.82),
      _Eyes.real => (0.46, 0.66),
      _Eyes.feature => (0.56, 0.9),
      _ => (0.73 * toward, 0.6),
    };
    var iris = Rect.fromCenter(
        center: c + shift + Offset(0, box.height * 0.04),
        width: box.width * fw * irisK,
        height: box.height * fh * irisK);
    if (kind == _Eyes.round) {
      // The feature cartoon's, as it has always been sized.
      iris = Rect.fromCenter(
          center: c + Offset(lookX * u * 0.04 * toward, -lookY * u * 0.035 + u * 0.015),
          width: u * 0.124 * irisK * toward,
          height: u * 0.124 * irisK);
    }
    var layered = kind != _Eyes.round && kind != _Eyes.soft && kind != _Eyes.shonen;
    var irisPaint = Paint()..color = dna.eyes;
    if (layered) {
      irisPaint.shader = ui.Gradient.linear(iris.topCenter, iris.bottomCenter, [
        Color.lerp(dna.eyes, dark, 0.6)!,
        dna.eyes,
        Color.lerp(dna.eyes, const Color(0xFFFFFFFF), 0.35)!,
      ], const [
        0.05,
        0.55,
        1,
      ]);
    }
    canvas.drawOval(iris, irisPaint);
    if (layered) {
      canvas.drawOval(
          iris,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(0.5, iris.width * 0.07)
            ..color = Color.lerp(dna.eyes, dark, 0.65)!);
    }
    var pupilK = kind == _Eyes.shonen ? 0.38 : 0.5;
    canvas.drawOval(
        Rect.fromCenter(
            center: iris.center,
            width: iris.width * pupilK,
            height: iris.height * pupilK * (kind == _Eyes.round ? 1 : 1.05)),
        Paint()..color = dark);

    // Light: where it catches, by the style.
    void glint(double ax, double ay, double r) => canvas.drawCircle(
        iris.center + Offset(iris.width * ax, iris.height * ay),
        iris.width * r,
        white);
    switch (kind) {
      case _Eyes.anime:
        glint(-0.22, -0.24, 0.2);
        glint(0.2, 0.22, 0.09);
      case _Eyes.shojo:
        glint(-0.22, -0.26, 0.22);
        glint(0.22, -0.18, 0.11);
        glint(-0.12, 0.26, 0.07);
        _sparkle(iris.center + Offset(iris.width * 0.16, iris.height * 0.2),
            iris.width * 0.16);
      case _Eyes.glossy:
        glint(-0.2, -0.22, 0.26);
        glint(0.22, 0.18, 0.1);
        // A soft reflection across the bottom of the eye.
        canvas.drawOval(
            Rect.fromLTRB(iris.left, iris.center.dy, iris.right, iris.bottom + iris.height * 0.2),
            Paint()..color = const Color(0x33FFFFFF));
      case _Eyes.round:
        canvas.drawCircle(iris.center + Offset(-u * 0.022, -u * 0.035) * irisK,
            u * 0.017 * irisK, white);
      case _Eyes.feature:
        glint(-0.2, -0.26, 0.2);
        glint(0.24, 0.18, 0.08);
      default:
        glint(-0.2, -0.24, 0.16);
    }
    // The upper lid's shadow on the white, for the styles that draw one.
    if (kind == _Eyes.anime ||
        kind == _Eyes.shojo ||
        kind == _Eyes.glossy ||
        kind == _Eyes.feature) {
      canvas.drawRect(
          Rect.fromLTRB(box.left, box.top, box.right, box.top + box.height * 0.2),
          Paint()..color = _shade(dna.skin, 0.15).withValues(alpha: 0.45));
    }
    var heavy = _a(Look.lids);
    if (heavy > 0) {
      // A heavy lid comes down over the top of the eye.
      canvas.drawRect(
          Rect.fromLTRB(box.left, box.top - box.height * 0.2, box.right,
              box.top + box.height * 0.4 * heavy),
          Paint()..color = dna.skin);
    }
    canvas.restore();

    // The lines round it.
    var ink = look.ink ?? dark;
    switch (kind) {
      case _Eyes.round:
        canvas.drawPath(whites, lid);
      case _Eyes.anime || _Eyes.shojo:
        var heavyLine = kind == _Eyes.shojo ? 0.042 : 0.036;
        canvas.drawArc(box.inflate(box.width * 0.02), math.pi * 1.08,
            math.pi * 0.84, false, _feature(u * heavyLine, ink));
        // A flick out at the outer corner, and a fine lower lid.
        var corner = Offset(box.center.dx + outer * box.width * 0.5,
            box.center.dy - box.height * 0.12);
        canvas.drawLine(corner,
            corner + Offset(outer * u * 0.04, -u * 0.03), _feature(u * 0.028, ink));
        canvas.drawArc(box, math.pi * (outer > 0 ? 0.1 : 0.55), math.pi * 0.35,
            false, _feature(u * 0.012, ink.withValues(alpha: 0.7)));
        if (kind == _Eyes.shojo) {
          for (var k = 0; k < 3; k++) {
            var a = -math.pi / 2 + outer * (0.6 + k * 0.28);
            var from = box.center +
                Offset(math.cos(a) * box.width / 2, math.sin(a) * box.height / 2);
            canvas.drawLine(from,
                from + Offset(math.cos(a), math.sin(a) - 0.6) * (u * 0.06),
                _feature(u * 0.016, ink));
          }
        }
      case _Eyes.shonen:
        // Sharp: straight lines meeting at a peak.
        var top = Offset(box.center.dx - outer * box.width * 0.1,
            box.top - box.height * 0.12);
        canvas.drawPath(
            Path()
              ..moveTo(box.center.dx - outer * box.width * 0.5,
                  box.center.dy + box.height * 0.08)
              ..lineTo(top.dx, top.dy)
              ..lineTo(box.center.dx + outer * box.width * 0.55,
                  box.center.dy - box.height * 0.1),
            _feature(u * 0.034, ink));
        canvas.drawLine(
            Offset(box.center.dx, box.bottom),
            Offset(box.center.dx + outer * box.width * 0.45, box.center.dy + box.height * 0.18),
            _feature(u * 0.014, ink));
      case _Eyes.soft:
        // A simple lid over a nearly all-iris eye.
        canvas.drawArc(box.inflate(box.width * 0.05), math.pi * 1.1,
            math.pi * 0.8, false, _feature(u * 0.026, ink));
      case _Eyes.fine || _Eyes.real:
        canvas.drawPath(
            Path()
              ..moveTo(box.left, box.center.dy + box.height * 0.08 * outer)
              ..quadraticBezierTo(box.center.dx - box.width * 0.05,
                  box.top - box.height * 0.22, box.right,
                  box.center.dy - box.height * 0.08 * outer),
            _feature(u * (kind == _Eyes.fine ? 0.026 : 0.022), ink));
        // The crease of the lid above it.
        canvas.drawArc(
            Rect.fromCenter(
                center: box.center - Offset(0, box.height * 0.45),
                width: box.width * 0.85,
                height: box.height * 0.6),
            math.pi * 1.15,
            math.pi * 0.7,
            false,
            _feature(u * 0.012, _shade(dna.skin, 0.4).withValues(alpha: 0.7)));
        canvas.drawArc(box, math.pi * 0.15, math.pi * 0.7, false,
            _feature(u * 0.01, _shade(dna.skin, 0.4).withValues(alpha: 0.6)));
      case _Eyes.glossy:
        canvas.drawArc(box.inflate(box.width * 0.04), math.pi * 1.05,
            math.pi * 0.9, false, _feature(u * 0.03, _shade(dna.skin, 0.55)));
      case _Eyes.feature:
        // The upper lid along the top of the almond, heavy, and on past the
        // outer corner in a flick.
        var lift = box.height * 0.08 * outer;
        var inner = Offset(box.left, box.center.dy + lift);
        var far = Offset(box.right, box.center.dy - lift);
        var (a, b) = outer > 0 ? (inner, far) : (far, inner);
        var flick = b + Offset(outer * box.width * 0.16, -box.height * 0.22);
        canvas.drawPath(
            Path()
              ..moveTo(a.dx, a.dy)
              ..quadraticBezierTo(box.center.dx - box.width * 0.05,
                  box.top - box.height * 0.24, b.dx, b.dy)
              ..lineTo(flick.dx, flick.dy),
            _feature(u * 0.034, ink));
        // A fine lower lid, under the outer half.
        canvas.drawPath(
            Path()
              ..moveTo(box.center.dx - outer * box.width * 0.1, box.bottom + box.height * 0.02)
              ..quadraticBezierTo(box.center.dx + outer * box.width * 0.35,
                  box.bottom - box.height * 0.02, b.dx, b.dy + box.height * 0.04),
            _feature(u * 0.011, ink.withValues(alpha: 0.55)));
        // The crease above.
        canvas.drawArc(
            Rect.fromCenter(
                center: box.center - Offset(0, box.height * 0.5),
                width: box.width * 0.9,
                height: box.height * 0.55),
            math.pi * 1.15,
            math.pi * 0.7,
            false,
            _feature(u * 0.012, _shade(dna.skin, 0.35).withValues(alpha: 0.7)));
      case _Eyes.dot || _Eyes.pie:
        break;
    }
    _lashes(box, outer, toward);
  }

  /// _lashes are lashes on the outer half of the upper lid, as long as the
  /// Appearance says.
  void _lashes(Rect box, double outer, double toward) {
    var lashes = _a(Look.lashes);
    if (lashes <= 0 || toward < 0.35) return;
    var ink = look.ink ?? const Color(0xFF1B1512);
    if (look.eyes == _Eyes.feature) {
      // Fine, curling out from the outer end of the lid line.
      var fine = _feature(u * 0.011 * (1 + 0.4 * lashes), ink);
      for (var k = 0; k < 3; k++) {
        var a = -math.pi / 2 + outer * (0.75 + k * 0.22);
        var from = box.center +
            Offset(math.cos(a) * box.width / 2, math.sin(a) * box.height * 0.62);
        var to = from + Offset(outer * u * 0.035, -u * 0.03) * lashes;
        canvas.drawPath(
            Path()
              ..moveTo(from.dx, from.dy)
              ..quadraticBezierTo(from.dx + outer * u * 0.005, to.dy, to.dx, to.dy),
            fine);
      }
      return;
    }
    var lash = _feature(u * 0.014 * (1 + lashes), ink);
    for (var k = 0; k < 3; k++) {
      var a = -math.pi / 2 + outer * (0.35 + k * 0.32);
      var from = box.center +
          Offset(math.cos(a) * box.width / 2, math.sin(a) * box.height / 2);
      var dir = Offset(math.cos(a), math.sin(a) - 0.4);
      canvas.drawLine(from, from + dir * (u * 0.05 * lashes), lash);
    }
  }

  /// _sparkle is a four-pointed star of light, [r] across.
  void _sparkle(Offset at, double r) {
    var star = Path()
      ..moveTo(at.dx, at.dy - r)
      ..quadraticBezierTo(at.dx, at.dy, at.dx + r, at.dy)
      ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy + r)
      ..quadraticBezierTo(at.dx, at.dy, at.dx - r, at.dy)
      ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy - r)
      ..close();
    canvas.drawPath(star, Paint()..color = const Color(0xFFFFFFFF));
  }

  /// _brow is the brow over the eye at [c]: raised, squeezed together and
  /// down in a frown, its inner end lifted in worry.
  void _brow(Offset c, double side, double toward) {
    var raise = face[FaceControl.browRaise];
    var squeeze = face[FaceControl.browSqueeze];
    var worry = face[FaceControl.browWorry];
    var y = c.dy - u * 0.16 - raise * u * 0.055 - _a(Look.browHeight) * u * 0.05;
    var long = 1 + 0.3 * _a(Look.browLength);
    var angle = _a(Look.browAngle);
    var inner = Offset(
        c.dx - side * (u * 0.08 + squeeze * u * 0.02) * toward * long,
        y + u * 0.01 + squeeze * u * 0.06 - worry * u * 0.07 + angle * u * 0.04);
    var outer = Offset(c.dx + side * u * 0.09 * toward * long,
        y + u * 0.01 - squeeze * u * 0.01 + worry * u * 0.03 - angle * u * 0.03);
    var mid = Offset((inner.dx + outer.dx) / 2,
        math.min(inner.dy, outer.dy) -
            u * 0.04 * (1 - squeeze * 0.6) * (1 + _a(Look.browArch)));
    canvas.drawPath(
        Path()
          ..moveTo(inner.dx, inner.dy)
          ..quadraticBezierTo(mid.dx, mid.dy, outer.dx, outer.dy),
        _feature(u * 0.035 * (1 + 0.6 * _a(Look.browThickness)),
            dna.hairStyle == HairStyle.bald ? _shade(dna.skin) : dna.hair));
  }

  /// _mouth is a mouth shape when one is set -- speech -- or else the mouth
  /// the face's own controls make.
  void _mouth(double w) {
    var at = _mouthPlace(w);
    var across = (0.35 + 0.65 * facing.clamp(0.0, 1.0)) *
        (1 + 0.3 * _a(Look.mouthWidth));
    _mouthAcross = across;
    canvas.save();
    canvas.translate(at.dx, at.dy);
    // Set as the panel's face has it, about its middle.
    _setAbout(faceRig[FacePoint.mouth], Offset.zero);
    canvas.scale(across, 1);
    if (face.mouth == MouthShape.rest) {
      _restMouth();
    } else {
      // The shapes are drawn about 22 units across; a mouth is about a
      // fifth of a head.
      var k = u * 0.0095 * (1 + 0.25 * face[FaceControl.wide]);
      canvas.scale(k, k);
      _shape(face.mouth);
    }
    canvas.restore();
  }

  static const _lips = Color(0xFF5A2A22);
  static const _tongue = Color(0xFFE0707A);

  void _restMouth() {
    var smile = (face[FaceControl.smile] + 0.4 * _a(Look.corners)).clamp(-1.0, 1.0);
    var jaw = face[FaceControl.jaw];
    var wide = face[FaceControl.wide];
    var half = u * 0.1 * (1 + 0.4 * wide.clamp(-0.6, 1.0));
    var corner = -smile * u * 0.05;
    // Each corner where the panel's face puts it: the character's right on
    // the reader's left. Across in head units, through the mouth's narrowing.
    var cr = faceRig[FacePoint.cornerR], cl = faceRig[FacePoint.cornerL];
    var k = _mouthAcross == 0 ? 1.0 : _mouthAcross;
    var lc = Offset(-half + cr.dx * u / k, corner + cr.dy * u);
    var rc = Offset(half + cl.dx * u / k, corner + cl.dy * u);
    var midX = (lc.dx + rc.dx) / 2, midY = (lc.dy + rc.dy) / 2 - corner;
    if (jaw < 0.06) {
      if (wide < -0.5) {
        // Pursed.
        canvas.drawOval(
            Rect.fromCenter(
                center: Offset.zero, width: u * 0.07, height: u * 0.06),
            _feature(u * 0.03, _lips));
        return;
      }
      _lipsOver(half, corner, smile);
      // Thinner lips are a finer line.
      var lips = (_a(Look.upperLip) + _a(Look.lowerLip)) / 2;
      canvas.drawPath(
          Path()
            ..moveTo(lc.dx, lc.dy)
            ..quadraticBezierTo(midX, smile * u * 0.1 + midY, rc.dx, rc.dy),
          _feature(u * 0.032 * (1 + 0.45 * math.min(0.0, lips)), _lips));
      return;
    }
    var top = smile > 0 ? smile * u * 0.02 : smile * u * 0.03;
    var bottom = top + jaw * u * 0.24 + math.max(0, smile) * u * 0.05;
    var mouth = Path()
      ..moveTo(lc.dx, lc.dy)
      ..quadraticBezierTo(midX, top + midY, rc.dx, rc.dy)
      ..quadraticBezierTo(midX, bottom * 1.3 + midY, lc.dx, lc.dy)
      ..close();
    canvas.drawPath(mouth, Paint()..color = _lips);
    canvas.save();
    canvas.clipPath(mouth);
    if (smile > 0.3) {
      canvas.drawRect(Rect.fromLTRB(-half, top - u * 0.05, half, top + u * 0.025),
          Paint()..color = const Color(0xFFFFFFFF));
    }
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(0, bottom * 1.05),
            width: half * 1.1,
            height: bottom * 0.5),
        Paint()..color = _tongue);
    canvas.restore();
    canvas.drawPath(mouth, _feature(edge, _shade(_lips, 0.2)));
  }

  /// _lipsOver draws the lips round a shut mouth [half] wide, when they are
  /// fuller, thinner or coloured than the line alone.
  void _lipsOver(double half, double corner, double smile) {
    var upper = _a(Look.upperLip), lower = _a(Look.lowerLip);
    var colour = _a(Look.lipColour);
    if (upper <= 0 && lower <= 0 && colour <= 0) return;
    var tint = Color.lerp(Color.lerp(dna.skin, const Color(0xFF9A4A4A), 0.35)!,
        const Color(0xFFC23B55), colour)!;
    var mid = smile * u * 0.05;
    var up = u * 0.03 * (1 + upper.clamp(-0.8, 1.0));
    var down = u * 0.04 * (1 + lower.clamp(-0.8, 1.0));
    // The upper lip with a dip in the middle, the lower a curve under.
    var lips = Path()
      ..moveTo(-half, corner)
      ..quadraticBezierTo(-half * 0.45, mid - up * 1.1, 0, mid - up * 0.7)
      ..quadraticBezierTo(half * 0.45, mid - up * 1.1, half, corner)
      ..quadraticBezierTo(0, mid + down * 1.6, -half, corner)
      ..close();
    canvas.drawPath(lips, Paint()..color = tint);
  }

  /// _shape draws [m] in units about 22 across, centred on the mouth.
  void _shape(MouthShape m) {
    var dark = Paint()..color = _lips;
    var teeth = Paint()..color = const Color(0xFFFFFFFF);
    var tongue = Paint()..color = _tongue;
    Rect oval(double cx, double cy, double rx, double ry) =>
        Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2);
    RRect bar(double l, double t, double w, double h, double r) =>
        RRect.fromRectAndRadius(Rect.fromLTWH(l, t, w, h), Radius.circular(r));
    switch (m) {
      case MouthShape.rest:
        return;
      case MouthShape.closed:
        canvas.drawLine(const Offset(-9, 0), const Offset(9, 0),
            _feature(3.6, _lips));
      case MouthShape.teeth:
        canvas.drawRRect(bar(-10, -4, 20, 8, 4), dark);
        canvas.drawRRect(bar(-8, -3, 16, 3, 1.5), teeth);
      case MouthShape.open:
        canvas.drawOval(oval(0, 0, 11, 6.5), dark);
        canvas.drawRRect(bar(-8, -6, 16, 3, 1.5), teeth);
        canvas.drawOval(oval(0, 3.5, 6, 2.5), tongue);
      case MouthShape.wide:
        canvas.drawOval(oval(0, 1, 12, 11), dark);
        canvas.drawRRect(bar(-8, -9, 16, 3, 1.5), teeth);
        canvas.drawOval(oval(0, 7, 7, 3.5), tongue);
      case MouthShape.round:
        canvas.drawOval(oval(0, 0, 8, 8), dark);
        canvas.drawOval(oval(0, 4, 4.5, 2), tongue);
      case MouthShape.pucker:
        canvas.drawOval(oval(0, 0, 5, 6), dark);
        canvas.drawOval(oval(0, 0, 5, 6),
            _feature(2, const Color(0xFFC9605C)));
      case MouthShape.lip:
        canvas.drawRRect(bar(-10, -3, 20, 7, 3.5), dark);
        canvas.drawRRect(bar(-8, -4, 16, 4, 1.5), teeth);
        canvas.drawPath(
            Path()
              ..moveTo(-9, 4)
              ..quadraticBezierTo(0, 1, 9, 4),
            _feature(2.4, const Color(0xFFC9605C)));
      case MouthShape.tongue:
        canvas.drawOval(oval(0, 0, 10, 8), dark);
        canvas.drawOval(oval(0, -2, 5, 3.5), tongue);
    }
  }

  Paint _feature(double width, Color colour) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = width
    ..color = colour;

  // ---- drawing helpers ----

  /// _fill fills [path] with [colour] and edges it a shade darker.
  void _fill(Path path, Color colour) {
    _solid(path.getBounds(), colour, (p) => canvas.drawPath(path, p));
    _outline(path, colour);
  }

}

/// _shade is [c] darkened by [by], for the edge drawn round it.
Color _shade(Color c, [double by = 0.32]) =>
    Color.lerp(c, const Color(0xFF000000), by)!;

/// facePivots is where each feature of [dna]'s face -- drawn as [style]
/// draws it, making [face] -- is set about, in the head's own space: see
/// character_face_rig.dart. [rig] is built from [dna] as the style has it.
Map<FacePoint, Offset> facePivots(
        CharacterRig rig, CharacterDna dna, CharacterFace face, CharacterStyle style) =>
    _Drawing(Canvas(ui.PictureRecorder()), rig, dna, face, LifeAt.none,
            look: _Look.of(style))
        ._facePivots();

/// captureFigure is [dna] -- as [style] draws it, in [rig], making [face] --
/// taken apart into its shapes, in the order they are drawn: see
/// character_outline.dart. As it is drawn without painted light, which
/// lights the shapes rather than adding any.
List<CapturedShape> captureFigure(CharacterRig rig, CharacterDna dna,
    CharacterFace face, LifeAt life, CharacterStyle style,
    {FaceRig faceRig = FaceRig.none}) {
  var c = CaptureCanvas();
  _Drawing(c, rig, dna, face, life, look: _Look.of(style), faceRig: faceRig)
      .draw();
  return c.shapes;
}
