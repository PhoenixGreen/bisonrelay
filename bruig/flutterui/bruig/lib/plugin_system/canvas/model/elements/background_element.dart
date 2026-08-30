import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';

/// BackgroundElement is a generated pattern in a rectangle.
///
/// The same generators the canvas's own background uses (see
/// procedural_spec.dart), placed as an element instead of covering the
/// document. That is what a panel of matrix rain behind a title is, or a
/// marked pitch occupying the middle two thirds of a wider canvas with a
/// scoreboard beside it.
///
/// It carries no properties of its own beyond the spec and one switch. The
/// generators are the feature; this is where to point them.
class BackgroundElement extends CanvasElement {
  final ProceduralSpec spec;

  /// cornerRadius clips the pattern to a rounded rectangle, so a generated
  /// panel can sit inside a layout rather than always being a hard-edged
  /// block.
  final double cornerRadius;

  const BackgroundElement(
    super.base, {
    this.spec = const ProceduralSpec(),
    this.cornerRadius = 0,
  });

  @override
  ElementKind get kind => ElementKind.background;

  @override
  CanvasElement rebase(ElementBase base) =>
      BackgroundElement(base, spec: spec, cornerRadius: cornerRadius);

  BackgroundElement copyWith({ProceduralSpec? spec, double? cornerRadius}) =>
      BackgroundElement(base,
          spec: spec ?? this.spec,
          cornerRadius: cornerRadius ?? this.cornerRadius);

  @override
  Map<String, dynamic> props() => {
        "spec": spec.toJson(),
        if (cornerRadius > 0) "cr": cornerRadius,
      };

  factory BackgroundElement.fromJson(
          Map<String, dynamic> json, ElementBase b) =>
      BackgroundElement(b,
          spec: jsonSpec(json["spec"], ProceduralSpec.fromJson,
              const ProceduralSpec()),
          cornerRadius: jsonDouble(json["cr"], 0));
}
