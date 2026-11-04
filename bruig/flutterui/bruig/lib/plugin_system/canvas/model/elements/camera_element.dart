import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

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

class CameraElement extends CanvasElement {
  const CameraElement(super.base);

  @override
  ElementKind get kind => ElementKind.camera;

  @override
  CanvasElement rebase(ElementBase base) => CameraElement(base);

  @override
  Map<String, dynamic> props() => const {};

  static CameraElement fromJson(Map<String, dynamic> json, ElementBase base) =>
      CameraElement(base);
}
