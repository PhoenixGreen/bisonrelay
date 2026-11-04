import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';

// camera_element.dart is a Camera: the part of the page that is shown. Added
// to a scene, it takes over from the canvas -- what plays, what is exported
// and what is looked through is its frame, filled out to the page -- and is
// moved by clips as any element is: pushed in on something, following it,
// pulled back, shaken (Ken). Without one, the whole page is shown, as it
// always was.
//
// Its box is the frame, kept to the page's shape: as wide as the page shows
// all of it, half as wide twice as close. A clip's size is how close it is
// -- 2 is twice as close -- rather than how big the frame is; its across and
// down move where it looks, its "on" a place to look at another element.
// Never drawn into the picture: on the canvas it is a frame over the page
// (see StagePainter), and see camera_framing.dart for how it frames.

//
// In a scene on a 3D stage it lives in the scene (Ken): it is the stage's
// camera wherever it is played, exported or looked through, from its own
// [view] -- where it stands, its lens, its height -- moved by its clips: a
// turn orbits round what it looks at, a size dollies it closer, an "on"
// aims it at what stands there. See camera_3d.dart.

class CameraElement extends CanvasElement {
  /// view is where it stands in 3D, or null for the stage's own camera
  /// until it is given one.
  final StageCamera? view;

  const CameraElement(super.base, {this.view});

  @override
  ElementKind get kind => ElementKind.camera;

  @override
  CanvasElement rebase(ElementBase base) => CameraElement(base, view: view);

  CameraElement withView(StageCamera? view) => CameraElement(base, view: view);

  @override
  Map<String, dynamic> props() => {
        if (view case var v?)
          "view": [v.yaw, v.pitch, v.distance, v.lens, v.tx, v.ty, v.tz],
      };

  static CameraElement fromJson(Map<String, dynamic> json, ElementBase base) {
    StageCamera? view;
    if (json["view"] case List v
        when v.length == 7 && v.every((x) => x is num)) {
      var n = [for (var x in v) (x as num).toDouble()];
      view = const StageCamera().copyWith(
          yaw: n[0],
          pitch: n[1],
          distance: n[2],
          lens: n[3],
          tx: n[4],
          ty: n[5],
          tz: n[6]);
    }
    return CameraElement(base, view: view);
  }
}
