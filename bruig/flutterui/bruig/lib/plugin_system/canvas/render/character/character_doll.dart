import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/render/model/mannequin.dart';
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
  const DollLook({this.lens = 0, this.lines = true, this.place, this.opacity});

  DollLook copyWith(
          {double? lens,
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
      );
}

/// paintDoll draws the doll as [rig] has the body, made as [dna] is,
/// [opacity] of the way to solid.
void paintDoll(Canvas canvas, CharacterRig rig, CharacterDna dna,
    {double opacity = 1, DollLook look = const DollLook(), double? feminine}) {
  var pieces = dollPieces(rig, dna,
      lens: look.lens,
      lines: look.lines,
      feminine: feminine ??
          (dna.kind == CharacterType.woman || dna.kind == CharacterType.girl ? 1 : 0));
  var bounds = meshBounds(pieces, rig.hips);
  if (bounds == null) return;
  var faint = opacity < 1;
  if (faint) {
    canvas.saveLayer(bounds.inflate(4),
        Paint()..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0)));
  }
  paintMeshes(canvas, rig.hips, pieces,
      outline: math.max(1.0, rig.unit * 0.014),
      outlineColor: const Color(0xFF4A4C53),
      outlineEach: true);
  if (faint) canvas.restore();
}
