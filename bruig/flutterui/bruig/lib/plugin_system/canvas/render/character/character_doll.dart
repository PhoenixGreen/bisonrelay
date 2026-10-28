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

/// paintDoll draws the doll as [rig] has the body, made as [dna] is,
/// [opacity] of the way to solid.
void paintDoll(Canvas canvas, CharacterRig rig, CharacterDna dna, {double opacity = 1}) {
  var pieces = dollPieces(rig, dna);
  var bounds = meshBounds(pieces, rig.hips);
  if (bounds == null) return;
  var faint = opacity < 1;
  if (faint) {
    canvas.saveLayer(bounds.inflate(4),
        Paint()..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0)));
  }
  paintMeshes(canvas, rig.hips, pieces,
      outline: math.max(1.0, rig.unit * 0.018), outlineColor: const Color(0xFF55575E));
  if (faint) canvas.restore();
}
