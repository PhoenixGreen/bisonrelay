import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';

// camera_element.dart is a Camera: the part of the page that is shown.
// Added to a scene, its frame, filled out to the page, is what plays, is
// exported and is looked through; it is moved by clips as any element is.
// Without one, the whole page is shown.
//
// Its box is the frame, kept to the page's shape. A clip's size is how
// close it is (2 is twice as close) rather than how big the frame is; its
// across and down move where it looks, its "on" aims it at another element.
// Never drawn into the picture: on the canvas it is a frame over the page
// (see StagePainter), and cameraFrame in motion_document.dart is how it
// frames.
//
// In a scene on a 3D stage it is the stage's camera, from its own [view],
// moved by its clips: a turn orbits round what it looks at, a size dollies
// it closer, an "on" aims it. See camera_3d.dart.

/// CameraElement is a Camera; see the top of this file.
///
/// Its lens (Ken, 2026-11-14): depth of field, parallax, a vignette and
/// motion blur, which the picture is drawn with through it -- in the app,
/// a video and a book alike. Its roll is its own angle (its turn and its
/// clips' turn). Focus, blur and vignette can be keyed: a keyframe's value
/// of that name (see CameraLook) wins over the setting here.
class CameraElement extends CanvasElement {
  /// view is where it stands in 3D, or null for the stage's own camera
  /// until it is given one.
  final StageCamera? view;

  /// focus is the depth that is sharp (see ElementBase.depth): nought, the
  /// page. Where [focusOn] names an element, its depth instead.
  final double focus;
  final String focusOn;

  /// blur is how soft the furthest from the focus is, in the page's units
  /// at a depth of one away: nought, no depth of field.
  final double blur;

  /// parallax is how much less the far moves, and more the near, as it
  /// pans and zooms: nought, flat; one, the far all but still.
  final double parallax;

  /// vignette is how dark the frame's corners go, 0..1; vignetteSoft how
  /// far in the darkening reaches, 0..1.
  final double vignette;
  final double vignetteSoft;

  /// motionBlur is how much of a frame's move the picture is smeared
  /// along, 0..1: a shutter open that share of the frame.
  final double motionBlur;

  const CameraElement(super.base,
      {this.view,
      this.focus = 0,
      this.focusOn = "",
      this.blur = 0,
      this.parallax = 0,
      this.vignette = 0,
      this.vignetteSoft = 0.5,
      this.motionBlur = 0});

  @override
  ElementKind get kind => ElementKind.camera;

  @override
  CanvasElement rebase(ElementBase base) => copyWith(base: base);

  CameraElement copyWith({
    ElementBase? base,
    StageCamera? view,
    bool clearView = false,
    double? focus,
    String? focusOn,
    double? blur,
    double? parallax,
    double? vignette,
    double? vignetteSoft,
    double? motionBlur,
  }) =>
      CameraElement(base ?? this.base,
          view: clearView ? null : view ?? this.view,
          focus: (focus ?? this.focus).clamp(-1.0, 1.0).toDouble(),
          focusOn: focusOn ?? this.focusOn,
          blur: (blur ?? this.blur).clamp(0.0, 200.0).toDouble(),
          parallax: (parallax ?? this.parallax).clamp(0.0, 1.0).toDouble(),
          vignette: (vignette ?? this.vignette).clamp(0.0, 1.0).toDouble(),
          vignetteSoft:
              (vignetteSoft ?? this.vignetteSoft).clamp(0.0, 1.0).toDouble(),
          motionBlur:
              (motionBlur ?? this.motionBlur).clamp(0.0, 1.0).toDouble());

  CameraElement withView(StageCamera? view) =>
      copyWith(view: view, clearView: view == null);

  /// hasLens is whether anything of its lens is set: what the picture
  /// is drawn with through it beyond its framing.
  bool get hasLens =>
      blur > 0 || parallax > 0 || vignette > 0 || motionBlur > 0;

  @override
  Map<String, dynamic> props() => {
        if (view case var v?)
          "view": [v.yaw, v.pitch, v.distance, v.lens, v.tx, v.ty, v.tz],
        if (focus != 0) "focus": focus,
        if (focusOn.isNotEmpty) "focusOn": focusOn,
        if (blur != 0) "blur": blur,
        if (parallax != 0) "parallax": parallax,
        if (vignette != 0) "vignette": vignette,
        if (vignetteSoft != 0.5) "vignetteSoft": vignetteSoft,
        if (motionBlur != 0) "motionBlur": motionBlur,
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
    return CameraElement(base, view: view).copyWith(
      focus: jsonDouble(json["focus"], 0),
      focusOn: jsonString(json["focusOn"], ""),
      blur: jsonDouble(json["blur"], 0),
      parallax: jsonDouble(json["parallax"], 0),
      vignette: jsonDouble(json["vignette"], 0),
      vignetteSoft: jsonDouble(json["vignetteSoft"], 0.5),
      motionBlur: jsonDouble(json["motionBlur"], 0),
    );
  }
}
