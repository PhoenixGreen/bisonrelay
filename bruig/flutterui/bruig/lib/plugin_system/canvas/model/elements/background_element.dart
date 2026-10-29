import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/edge_mask.dart';
import 'package:bruig/plugin_system/canvas/model/elements/parallax_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';

/// BackgroundElement is a generated pattern in a rectangle.
///
/// The same generators the canvas's own background uses (see
/// procedural_spec.dart), placed as an element instead of covering the
/// document. That is what a panel of matrix rain behind a title is, or a
/// marked pitch occupying the middle two thirds of a wider canvas with a
/// scoreboard beside it.
///
/// Or a 3D stage in that rectangle, where [backdrop] says so: see [staged].
class BackgroundElement extends CanvasElement {
  final ProceduralSpec spec;

  /// cornerRadius clips the pattern to a rounded rectangle, so a generated
  /// panel can sit inside a layout rather than always being a hard-edged
  /// block.
  final double cornerRadius;

  /// mask softens its edges and fades it out. See EdgeMask.
  final EdgeMask mask;

  /// backdrop is whether this draws its pattern or its stage.
  final BackdropKind backdrop;

  /// stage is the stage's settings -- its camera, its set, its light -- or
  /// null for one never made. Kept while the pattern is shown, so trying
  /// the flat background and coming back does not lose the set.
  ///
  /// Only the settings: where it is, and the keys its camera moves on, are
  /// this element's own. See [staged].
  final StageElement? stage;

  /// parallax is its parallax scenery, kept the same way, with its camera's
  /// keys on this element's track too. See [parallaxed].
  final ParallaxElement? parallax;

  const BackgroundElement(
    super.base, {
    this.spec = const ProceduralSpec(),
    this.cornerRadius = 0,
    this.mask = const EdgeMask(),
    this.backdrop = BackdropKind.flat,
    this.stage,
    this.parallax,
  });

  @override
  ElementKind get kind => ElementKind.background;

  bool get isStage => backdrop == BackdropKind.stage;
  bool get isParallax => backdrop == BackdropKind.parallax;

  @override
  Set<String> get assetIds => {...?parallax?.assetIds};

  /// parallaxed is the scenery as this element draws it: in its box, on its
  /// track. The parallax's [staged].
  ParallaxElement get parallaxed =>
      (parallax ?? const ParallaxElement(ElementBase(id: ""))).rebase(base)
          as ParallaxElement;

  /// withParallax is this element drawing [next], its camera keys taken
  /// onto this element's own track.
  BackgroundElement withParallax(ParallaxElement next) {
    var kept = next.rebase(const ElementBase(id: "")) as ParallaxElement;
    var self = next.track == null ? this : withBase(track: next.track);
    return (self as BackgroundElement)
        .copyWith(backdrop: BackdropKind.parallax, parallax: kept);
  }

  /// staged is the stage as this element draws it: its settings in this
  /// element's box, under this element's id, moving on this element's
  /// track. That id is what a character standing on it names, and the
  /// track is where the camera's keys are -- so everything that worked on
  /// a stage of its own works on this one unchanged.
  StageElement get staged =>
      (stage ?? const StageElement(ElementBase(id: ""))).rebase(base)
          as StageElement;

  /// withStage is this element drawing [next]: its settings kept, and its
  /// camera keys taken onto this element's own track.
  BackgroundElement withStage(StageElement next) {
    var kept = next.rebase(const ElementBase(id: "")) as StageElement;
    var self = next.track == null ? this : withBase(track: next.track);
    return (self as BackgroundElement)
        .copyWith(backdrop: BackdropKind.stage, stage: kept);
  }

  @override
  CanvasElement rebase(ElementBase base) => BackgroundElement(base,
      spec: spec,
      cornerRadius: cornerRadius,
      mask: mask,
      backdrop: backdrop,
      stage: stage,
      parallax: parallax);

  BackgroundElement copyWith(
          {ProceduralSpec? spec,
          double? cornerRadius,
          EdgeMask? mask,
          BackdropKind? backdrop,
          StageElement? stage,
          ParallaxElement? parallax}) =>
      BackgroundElement(base,
          spec: spec ?? this.spec,
          cornerRadius: cornerRadius ?? this.cornerRadius,
          mask: mask ?? this.mask,
          backdrop: backdrop ?? this.backdrop,
          stage: stage ?? this.stage,
          parallax: parallax ?? this.parallax);

  @override
  Map<String, dynamic> props() => {
        "spec": spec.toJson(),
        if (cornerRadius > 0) "cr": cornerRadius,
        if (mask.on) "mask": mask.toJson(),
        if (backdrop != BackdropKind.flat) "backdrop": backdrop.name,
        if (stage != null) "stage": stage!.props(),
        if (parallax != null) "parallax": parallax!.props(),
      };

  factory BackgroundElement.fromJson(
          Map<String, dynamic> json, ElementBase b) =>
      BackgroundElement(b,
          spec: jsonSpec(
              json["spec"], ProceduralSpec.fromJson, const ProceduralSpec()),
          cornerRadius: jsonDouble(json["cr"], 0),
          mask: jsonSpec(json["mask"], EdgeMask.fromJson, const EdgeMask()),
          backdrop: BackdropKind.fromName(json["backdrop"] as String?),
          stage: json["stage"] is Map<String, dynamic>
              ? StageElement.fromJson(json["stage"] as Map<String, dynamic>,
                  const ElementBase(id: ""))
              : null,
          parallax: json["parallax"] is Map<String, dynamic>
              ? ParallaxElement.fromJson(json["parallax"] as Map<String, dynamic>,
                  const ElementBase(id: ""))
              : null);

  /// fromStage is a stage saved when it was an element of its own, read as
  /// what it is now: a background showing it, in the same place, under the
  /// same id -- so the characters standing on it still are -- with its
  /// camera keys on the same track.
  factory BackgroundElement.fromStage(
          Map<String, dynamic> json, ElementBase b) =>
      BackgroundElement(b,
          backdrop: BackdropKind.stage,
          stage: StageElement.fromJson(json, const ElementBase(id: "")));
}
