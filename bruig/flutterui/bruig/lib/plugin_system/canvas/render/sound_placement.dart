import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/surround.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_painter.dart';

// sound_placement.dart is where a placed sound is heard from on a frame:
// worked out from the picture, the same way for the editor and an export.
//
// The listener is the viewer. Across a canvas, the left edge to the right
// is [SoundPlacement.arc] wide, centred straight ahead. On a 3D stage the
// listener stands at the camera: a sound is heard from where it is
// against the way the camera looks, and is quieter the further away it
// is than the middle of the stage -- the point the camera is aimed at --
// and never louder than full.

/// heardAt is where [e]'s sound, placed by [place], is heard from on
/// [frame] -- or null where it is not placed, or what it is placed by is
/// not there.
Heard? heardAt(
    CanvasDocument doc, CanvasElement e, SoundPlacement place, int frame) {
  switch (place.by) {
    case PlaceBy.off:
      return null;
    case PlaceBy.canvas:
      return _across(doc, e, place, frame);
    case PlaceBy.stage:
      return _onStage(doc, place.stage, place.x, place.y, place.z, place,
          frame);
    case PlaceBy.follow:
      var other = doc.elementById(place.follow);
      if (other == null) return null;
      if (other.spotAt(frame) case var spot? when canStand(other)) {
        // Something on a stage is heard from where it stands: a 3D
        // character from its mouth, a flat from its middle.
        var y = other is Character3dElement
            ? spot.lift + 1.5
            : spot.lift + spot.height / 2;
        if (_onStage(doc, spot.stage, spot.x, y, spot.z, place, frame)
            case var heard?) {
          return heard;
        }
      }
      return _across(doc, other, place, frame);
  }
}

/// _across is [e]'s place across the canvas on [frame], as its clips and
/// keyframes move it.
Heard _across(
    CanvasDocument doc, CanvasElement e, SoundPlacement place, int frame) {
  var pose = poseWithMotion(e, frame, doc);
  var centre = e.x + e.width / 2 + pose.dx;
  var width = doc.size.rect.width;
  var u = width <= 0 ? 0.5 : (centre - doc.size.rect.left) / width;
  return Heard(wrapAngle((u.clamp(0.0, 1.0) - 0.5) * place.arc));
}

Heard? _onStage(CanvasDocument doc, String id, double x, double y, double z,
    SoundPlacement place, int frame) {
  var stage = stageNamed(id, doc.elements,
      backdrop: doc.drawnBackground, page: doc.size.rect);
  if (stage == null) return null;
  var view = stageView(stage, frame);
  var (angle, distance) = view.heardFrom(x, y, z);
  var middle = stage.cameraAt(frame).distance;
  var near = place.near > 0 ? place.near : middle;
  // Full at the middle of the stage, and quieter further off.
  var gain = distanceGain(distance, near, place.rolloff);
  return Heard(angle, gain.clamp(0.0, 1.0));
}
