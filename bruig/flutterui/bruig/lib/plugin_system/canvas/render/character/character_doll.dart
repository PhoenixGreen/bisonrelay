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
class DollLook {
  final double lens;
  final bool lines;
  const DollLook({this.lens = 0, this.lines = true});
}

/// paintDoll draws the doll as [rig] has the body, made as [dna] is,
/// [opacity] of the way to solid.
void paintDoll(Canvas canvas, CharacterRig rig, CharacterDna dna,
    {double opacity = 1, DollLook look = const DollLook()}) {
  var pieces = dollPieces(rig, dna, lens: look.lens, lines: look.lines);
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
