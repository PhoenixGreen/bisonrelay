import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/render/model/mannequin.dart';
import 'package:bruig/plugin_system/canvas/render/model/human_body.dart';
import 'package:bruig/plugin_system/canvas/render/model/mesh_painter.dart';

// character_doll.dart is the guide figure a sketch is posed and drawn
// over in the editor, as a drawing figure is in a paint program: a grey
// doll in 3D, built from the character's own rig, so it is as tall, as
// big-headed and as posed as the character is -- see dollPieces. Never in
// anything made from the canvas.

/// DollGuide is where the doll is drawn: not at all, under the character
/// -- to draw over, for one drawn from nothing -- or faintly over it, to
/// see the pose through the drawing.
enum DollGuide { none, under, over }

/// DollKind is which doll: a human body, sculpted -- the smooth doll
/// standing in until that is here -- or an artist's wooden doll, its
/// joints plain to see.
enum DollKind {
  human("Human"),
  wooden("Wooden doll");

  final String label;
  const DollKind(this.label);
}

/// DollLook is how the doll is seen: [lens] how strongly in perspective,
/// nought for not at all; [lines] whether its guide lines are drawn.
///
/// [place] is where it is drawn -- null for under a character drawn from
/// nothing and over any other -- and [opacity] how solid, null for solid
/// under and faint over.
class DollLook {
  final double lens;
  final bool lines;
  final DollGuide? place;
  final double? opacity;
  final DollKind kind;
  const DollLook(
      {this.lens = 0,
      this.lines = true,
      this.place,
      this.opacity,
      this.kind = DollKind.human});

  DollLook copyWith(
          {double? lens,
          DollKind? kind,
          bool? lines,
          DollGuide? place,
          bool autoPlace = false,
          double? opacity,
          bool autoOpacity = false}) =>
      DollLook(
        lens: lens ?? this.lens,
        lines: lines ?? this.lines,
        place: autoPlace ? null : (place ?? this.place),
        opacity: autoOpacity ? null : (opacity ?? this.opacity),
        kind: kind ?? this.kind,
      );
}

/// paintDoll draws the doll as [rig] has the body, made as [dna] is, in
/// [box], [opacity] of the way to solid -- [feminine] how much a woman's
/// figure, from its type when not given.
void paintDoll(Canvas canvas, CharacterRig rig, CharacterDna dna,
    {double opacity = 1,
    DollLook look = const DollLook(),
    double? feminine,
    Rect? box,
    double lift = 0}) {
  var she = feminine ??
      (dna.kind == CharacterType.woman || dna.kind == CharacterType.girl ? 1.0 : 0.0);
  var faint = opacity < 1;
  void begin(Rect? bounds) {
    if (faint && bounds != null) {
      canvas.saveLayer(bounds.inflate(6),
          Paint()..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0)));
    }
  }

  void end(Rect? bounds) {
    if (faint && bounds != null) canvas.restore();
  }

  var line = math.max(1.0, rig.unit * 0.014);
  if (look.kind == DollKind.human && box != null) {
    if (_humanPieces(rig, dna, she, box, lift) case (var origin, var pieces)) {
      var bounds = meshBounds(pieces, origin);
      begin(bounds);
      var ink = InkLook(
        cel: false,
        outline: line,
        inner: 0.55,
        ink: const Color(0xFF4A4C53),
        rim: const Color(0x30FFFFFF),
      );
      if (!paintMeshesInked(canvas, origin, pieces, ink, shading: ModelShading.soft)) {
        paintMeshes(canvas, origin, pieces, outline: line, outlineColor: const Color(0xFF4A4C53));
      }
      end(bounds);
      return;
    }
  }
  var pieces = look.kind == DollKind.wooden
      ? woodenPieces(rig, dna, lens: look.lens, feminine: she)
      : dollPieces(rig, dna, lens: look.lens, lines: look.lines, feminine: she);
  var bounds = meshBounds(pieces, rig.hips);
  if (bounds == null) return;
  begin(bounds);
  paintMeshes(canvas, rig.hips, pieces,
      outline: line,
      outlineColor: look.kind == DollKind.wooden ? const Color(0xFF6B4B2E) : const Color(0xFF4A4C53),
      outlineEach: true);
  end(bounds);
}

/// _humanPieces is the human body made as [dna] is -- bare, bald, its face
/// plain -- posed as [rig] has it in [box], grey: or null while that body
/// is not here, for the smooth doll to stand in.
(Offset, List<MeshPiece>)? _humanPieces(
    CharacterRig rig, CharacterDna dna, double feminine, Rect box, double lift) {
  var person = dna.kind == CharacterType.empty
      ? dna.copyWith(type: feminine >= 0.5 ? CharacterType.woman : CharacterType.man)
      : dna;
  var model = HumanBody.instance.modelFor(
      person.copyWith(wardrobe: const [], hairStyle: HairStyle.bald),
      drawnFace: true,
      gender: 1 - feminine);
  if (model == null) return null;
  var (origin, pieces) = model.pieces(rig, CharacterFace.rest, box, lift: lift);
  return (
    origin,
    [
      for (var p in pieces)
        MeshPiece(
          points: p.points,
          indices: p.indices,
          normals: p.normals,
          color: dollColour,
          doubleSided: p.doubleSided,
          depth: p.depth,
        ),
    ]
  );
}
