import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/edge_mask.dart';
import 'package:bruig/plugin_system/canvas/model/elements/parallax_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/colour_map.dart';

/// BackgroundElement is a generated pattern (see procedural_spec.dart) as
/// an element, or, by [backdrop], a 3D stage ([staged]) or scenery
/// ([parallaxed]).
class BackgroundElement extends CanvasElement {
  final ProceduralSpec spec;

  /// cornerRadius clips the pattern to a rounded rectangle.
  final double cornerRadius;

  /// mask softens its edges and fades it out. See EdgeMask.
  final EdgeMask mask;

  /// backdrop is whether this draws its pattern, its stage or its scenery.
  final BackdropKind backdrop;

  /// stage is the stage's settings, or null for none made; kept while the
  /// pattern shows, so switching back keeps the set. See [staged].
  final StageElement? stage;

  /// parallax is its parallax scenery, kept the same way, its camera's keys
  /// on this element's track. See [parallaxed].
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

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = BackgroundElement(ElementBase(id: ""));

  @override
  ElementKind get kind => ElementKind.background;

  bool get isStage => backdrop == BackdropKind.stage;
  bool get isParallax => backdrop == BackdropKind.parallax;

  @override
  Set<String> get assetIds => {...?parallax?.assetIds};

  /// parallaxed is the scenery in this element's box, on its track: the
  /// parallax counterpart of [staged].
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
  /// element's box, under this element's id (what a character standing on
  /// it names), on this element's track (where the camera's keys are).
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

  /// mapOwnColours maps the pattern, the stage and the scenery, each shown
  /// only while it is the one drawn. The stage and scenery are kept without
  /// a base of their own (this element's stands for theirs), so only their
  /// own colours are mapped.
  @override
  BackgroundElement mapOwnColours(ColourMap f) {
    var p = ColourPass(f);
    var spec = p.part(this.spec,
        (s) => s.mapColours(f.shownOnlyIf(backdrop == BackdropKind.flat)));
    var stage = p.partOrNone(
        this.stage, (s) => s.mapOwnColours(f.shownOnlyIf(isStage)));
    var parallax = p.partOrNone(
        this.parallax, (s) => s.mapOwnColours(f.shownOnlyIf(isParallax)));
    if (!p.changed) return this;
    return copyWith(spec: spec, stage: stage, parallax: parallax);
  }

  @override
  Map<String, dynamic> props() => {
        "spec": spec.toJson(),
        if (cornerRadius > 0) "cr": cornerRadius,
        if (mask.on) "mask": mask.toJson(),
        if (backdrop != _defaults.backdrop) "backdrop": backdrop.name,
        if (stage != null) "stage": stage!.props(),
        if (parallax != null) "parallax": parallax!.props(),
      };

  factory BackgroundElement.fromJson(
          Map<String, dynamic> json, ElementBase b) =>
      BackgroundElement(b,
          spec: jsonSpec(
              json["spec"], ProceduralSpec.fromJson, _defaults.spec),
          cornerRadius: jsonDouble(json["cr"], _defaults.cornerRadius),
          mask: jsonSpec(json["mask"], EdgeMask.fromJson, _defaults.mask),
          backdrop: BackdropKind.fromName(jsonStr(json["backdrop"])),
          stage: json["stage"] is Map<String, dynamic>
              ? StageElement.fromJson(json["stage"] as Map<String, dynamic>,
                  const ElementBase(id: ""))
              : null,
          parallax: json["parallax"] is Map<String, dynamic>
              ? ParallaxElement.fromJson(json["parallax"] as Map<String, dynamic>,
                  const ElementBase(id: ""))
              : null);
}
