import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/colour_map.dart';

// camera_element.dart is a Camera: the part of the page shown, played and
// exported, moved by clips. Its box is the frame, in the page's shape; a
// clip's size is how close (2 twice as close). Never drawn into the
// picture; on a 3D stage it is the stage's camera (camera_3d.dart).

/// CameraElement is a Camera, with a lens: depth of field, parallax, a
/// vignette and motion blur, drawn alike in the app, a video and a book.
/// Its roll is its own angle plus its clips' turn. Focus, blur and vignette
/// can be keyed: a keyframe's value of that name (see CameraLook) wins.
class CameraElement extends CanvasElement {
  /// view is where it stands in 3D, or null for the stage's own camera.
  final StageCamera? view;

  /// focus is the depth that is sharp (see ElementBase.depth), nought being
  /// the page; where [focusOn] names an element, that element's depth.
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

  /// aim is a framed chart's id, or ""; [aimAt] what of it ("" all,
  /// "item:Arsenal", "top:3", "leader"); [aimFill] how much of the frame,
  /// 0.2..0.95. A keyed "aim" eases from its framing (0) to the aim (1).
  final String aim;
  final String aimAt;
  final double aimFill;

  const CameraElement(super.base,
      {this.view,
      this.focus = 0,
      this.focusOn = "",
      this.blur = 0,
      this.parallax = 0,
      this.vignette = 0,
      this.vignetteSoft = 0.5,
      this.motionBlur = 0,
      this.aim = "",
      this.aimAt = "",
      this.aimFill = 0.6});

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = CameraElement(ElementBase(id: ""));

  @override
  ElementKind get kind => ElementKind.camera;

  /// mapOwnColours is this: it has no colour of its own.
  @override
  CanvasElement mapOwnColours(ColourMap f) => this;

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
    String? aim,
    String? aimAt,
    double? aimFill,
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
              (motionBlur ?? this.motionBlur).clamp(0.0, 1.0).toDouble(),
          aim: aim ?? this.aim,
          aimAt: aimAt ?? this.aimAt,
          aimFill: (aimFill ?? this.aimFill).clamp(0.2, 0.95).toDouble());

  CameraElement withView(StageCamera? view) =>
      copyWith(view: view, clearView: view == null);

  /// hasLens is whether anything of its lens is set beyond its framing.
  bool get hasLens =>
      blur > 0 || parallax > 0 || vignette > 0 || motionBlur > 0;

  @override
  Map<String, dynamic> props() => {
        if (view case var v?)
          "view": [v.yaw, v.pitch, v.distance, v.lens, v.tx, v.ty, v.tz],
        if (focus != _defaults.focus) "focus": focus,
        if (focusOn.isNotEmpty) "focusOn": focusOn,
        if (blur != _defaults.blur) "blur": blur,
        if (parallax != _defaults.parallax) "parallax": parallax,
        if (vignette != _defaults.vignette) "vignette": vignette,
        if (vignetteSoft != _defaults.vignetteSoft)
          "vignetteSoft": vignetteSoft,
        if (motionBlur != _defaults.motionBlur) "motionBlur": motionBlur,
        if (aim.isNotEmpty) "aim": aim,
        if (aimAt.isNotEmpty) "aimAt": aimAt,
        if (aimFill != _defaults.aimFill) "aimFill": aimFill,
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
      focus: jsonDouble(json["focus"], _defaults.focus),
      focusOn: jsonString(json["focusOn"], _defaults.focusOn),
      blur: jsonDouble(json["blur"], _defaults.blur),
      parallax: jsonDouble(json["parallax"], _defaults.parallax),
      vignette: jsonDouble(json["vignette"], _defaults.vignette),
      vignetteSoft: jsonDouble(json["vignetteSoft"], _defaults.vignetteSoft),
      motionBlur: jsonDouble(json["motionBlur"], _defaults.motionBlur),
      aim: jsonString(json["aim"], _defaults.aim),
      aimAt: jsonString(json["aimAt"], _defaults.aimAt),
      aimFill: jsonDouble(json["aimFill"], _defaults.aimFill),
    );
  }
}
