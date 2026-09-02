import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

/// RemovalMode is how an image's background is taken out.
///
/// Three methods rather than one, because "remove the background" is three
/// different problems wearing the same name and none of the three is right
/// for the other two's pictures:
///
///  - a logo or a screenshot has one flat colour behind it, which is what
///    [chromaKey] and [cornerFlood] are for;
///  - a chart or a scan is dark on light, which is [luminance];
///  - a photograph of a person is none of the above, and no amount of
///    threshold tuning makes it one. There is deliberately no control here
///    pretending otherwise.
///
/// All three run on the raw pixels in Dart. Nothing is uploaded anywhere, and
/// nothing needs a model -- a canvas is edited offline like everything else in
/// this app.
enum RemovalMode {
  none("None", "Leave the image as it is"),
  chromaKey("Colour key", "Remove everything close to one chosen colour"),
  cornerFlood("Flood from edges",
      "Remove the connected region touching the picture's edges"),
  luminance("By brightness", "Remove everything above or below a brightness");

  final String label;
  final String description;
  const RemovalMode(this.label, this.description);

  static RemovalMode fromName(String? name) => values.firstWhere(
        (m) => m.name == name,
        orElse: () => RemovalMode.none,
      );
}

/// ImageFit is how the picture sits in its box.
///
/// Our own three values rather than Flutter's BoxFit, so that the model layer
/// imports nothing from Flutter beyond dart:ui and stays testable without a
/// binding. render/ maps them; there is no reason for a saved document to
/// depend on somebody else's enum.
enum ImageFit {
  cover("Fill the box"),
  contain("Fit inside"),
  stretch("Stretch");

  final String label;
  const ImageFit(this.label);

  static ImageFit fromName(String? name) =>
      values.firstWhere((f) => f.name == name, orElse: () => ImageFit.cover);
}

/// BackgroundRemoval is the recipe, never the result.
///
/// Stored as settings rather than as a cut-out bitmap, for the same reason a
/// procedural background is a seed: the original picture stays whole, the
/// tolerance can be nudged a week later, and the document does not grow a
/// second copy of every image. The cut-out is recomputed when the settings
/// change and cached in memory for as long as they do not.
class BackgroundRemoval {
  final RemovalMode mode;

  /// keyColor is what [RemovalMode.chromaKey] matches against.
  final Color keyColor;

  /// tolerance is how far from the key a pixel may be and still be removed,
  /// 0..1 across the RGB cube's diagonal.
  final double tolerance;

  /// softness feathers the edge, so a cut-out does not have a hard jagged
  /// boundary a pixel wide. In the same 0..1 units as the tolerance.
  final double softness;

  /// threshold is the brightness [RemovalMode.luminance] cuts at.
  final double threshold;

  /// invert keeps what would have been removed and removes what would have
  /// been kept.
  final bool invert;

  /// edge is how sharp a change has to be to stop the flood, for
  /// [RemovalMode.cornerFlood].
  ///
  /// This is the control that does the work on a photograph, and [tolerance]
  /// is the one that stops it running away. A background is usually smooth --
  /// out of focus, or a wall, or a sky -- while the subject has a crisp
  /// outline, so "keep going while the picture changes gently, stop where it
  /// changes suddenly" separates the two far better than any judgement about
  /// colour can. Low values stop at the faintest change; high values push
  /// through soft edges and eventually through the subject's own.
  final double edge;

  const BackgroundRemoval({
    this.mode = RemovalMode.none,
    this.keyColor = const Color(0xFFFFFFFF),
    this.tolerance = 0.45,
    this.softness = 0.04,
    this.edge = 0.09,
    this.threshold = 0.85,
    this.invert = false,
  });

  bool get active => mode != RemovalMode.none;

  BackgroundRemoval copyWith({
    RemovalMode? mode,
    Color? keyColor,
    double? tolerance,
    double? softness,
    double? threshold,
    bool? invert,
    double? edge,
  }) =>
      BackgroundRemoval(
        mode: mode ?? this.mode,
        keyColor: keyColor ?? this.keyColor,
        tolerance: tolerance ?? this.tolerance,
        softness: softness ?? this.softness,
        threshold: threshold ?? this.threshold,
        invert: invert ?? this.invert,
        edge: edge ?? this.edge,
      );

  /// cacheKey identifies a cut-out. Two elements with the same picture and
  /// the same settings share one, which matters on a canvas built from a
  /// dozen copies of the same badge.
  String cacheKey(String assetId) => "$assetId|${mode.name}|"
      "${colorToJson(keyColor)}|$tolerance|$softness|$threshold|$invert";

  Map<String, dynamic> toJson() => {
        "mode": mode.name,
        "key": colorToJson(keyColor),
        "tol": tolerance,
        "soft": softness,
        "thr": threshold,
        if (invert) "invert": true,
        "edge": edge,
      };

  factory BackgroundRemoval.fromJson(Map<String, dynamic> json) =>
      BackgroundRemoval(
        mode: RemovalMode.fromName(json["mode"] as String?),
        keyColor: colorFromJson(json["key"]),
        tolerance: jsonDouble(json["tol"], 0.12).clamp(0.0, 1.0),
        softness: jsonDouble(json["soft"], 0.04).clamp(0.0, 1.0),
        threshold: jsonDouble(json["thr"], 0.85).clamp(0.0, 1.0),
        invert: jsonBool(json["invert"], false),
        edge: jsonDouble(json["edge"], 0.09),
      );
}

/// ImageFilter is a look applied to the whole picture.
///
/// Presets rather than a pile of sliders, because these are the handful of
/// looks anybody actually reaches for and each is one colour matrix -- the
/// sliders for hue, contrast and the rest are already there as tint,
/// saturation and brightness for when a preset is not enough.
enum ImageFilterPreset {
  none("None"),
  greyscale("Greyscale"),
  sepia("Sepia"),
  noir("Noir"),
  invert("Invert"),
  cool("Cool"),
  warm("Warm"),
  faded("Faded");

  final String label;
  const ImageFilterPreset(this.label);

  static ImageFilterPreset fromName(String? name) => values.firstWhere(
        (f) => f.name == name,
        orElse: () => ImageFilterPreset.none,
      );
}

/// OverlayBlend is how an overlay colour is laid over the picture.
///
/// Our own names rather than Flutter's BlendMode, for the reason every other
/// enum here is: a saved document must not depend on the index or the spelling
/// of a value in somebody else's library.
enum OverlayBlend {
  none("None", BlendMode.dstIn),
  wash("Wash", BlendMode.srcOver),
  multiply("Multiply", BlendMode.multiply),
  screen("Screen", BlendMode.screen),
  overlay("Overlay", BlendMode.overlay),
  softLight("Soft light", BlendMode.softLight),
  hardLight("Hard light", BlendMode.hardLight),
  colour("Colour", BlendMode.color),
  luminosity("Luminosity", BlendMode.luminosity);

  final String label;
  final BlendMode flutter;
  const OverlayBlend(this.label, this.flutter);

  static OverlayBlend fromName(String? name) => values.firstWhere(
        (b) => b.name == name,
        orElse: () => OverlayBlend.none,
      );
}

/// ImageCrop is which part of the picture is shown, in fractions of it.
///
/// Fractions rather than pixels, so a crop survives the picture being swapped
/// for a larger copy of the same thing -- and so the same crop means the same
/// framing whatever the source happens to be.
class ImageCrop {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const ImageCrop({
    this.left = 0,
    this.top = 0,
    this.right = 1,
    this.bottom = 1,
  });

  bool get isWhole => left == 0 && top == 0 && right == 1 && bottom == 1;

  double get width => (right - left).clamp(0.01, 1);
  double get height => (bottom - top).clamp(0.01, 1);

  ImageCrop copyWith({
    double? left,
    double? top,
    double? right,
    double? bottom,
  }) =>
      ImageCrop(
        left: left ?? this.left,
        top: top ?? this.top,
        right: right ?? this.right,
        bottom: bottom ?? this.bottom,
      );

  Map<String, dynamic> toJson() =>
      {"l": left, "t": top, "r": right, "b": bottom};

  factory ImageCrop.fromJson(Map<String, dynamic> json) => ImageCrop(
        left: jsonDouble(json["l"], 0).clamp(0.0, 0.99),
        top: jsonDouble(json["t"], 0).clamp(0.0, 0.99),
        right: jsonDouble(json["r"], 1).clamp(0.01, 1.0),
        bottom: jsonDouble(json["b"], 1).clamp(0.01, 1.0),
      );
}

/// ImageElement is a picture on the canvas.
///
/// It holds an [assetId], not the bytes. The bytes live once in the canvas
/// asset store beside the document (see storage/canvas_assets.dart), exactly
/// as the post library keeps a draft's embeds beside the draft -- so a canvas
/// with the same logo on it eight times is one copy of the logo, and a saved
/// document stays a small readable file.
class ImageElement extends CanvasElement {
  final String assetId;
  final ImageFit fit;
  final BoxSpec box;
  final BackgroundRemoval removal;

  /// tint multiplies the image's colours. Transparent means no tint, which is
  /// the normal case.
  final Color tint;

  /// saturation and brightness are 1 for "as it came in".
  final double saturation;
  final double brightness;

  /// crop is which part of the picture is shown. See [ImageCrop].
  final ImageCrop crop;

  /// frame is a shape the picture is cut to -- a circle, a star, a speech
  /// bubble. Null leaves it rectangular.
  ///
  /// The shape is the one every other element draws, so a picture can be cut
  /// to anything a shape element can be, and a shape added later is a frame
  /// for free.
  final ShapeKind? frame;

  final ImageFilterPreset filter;

  /// overlay is a colour laid over the picture, and blend is how. Together
  /// they are the difference between a photograph and a photograph that goes
  /// with the rest of the design.
  final Color overlay;

  /// lockAspect keeps the frame's proportions while it is resized.
  ///
  /// On to begin with, and only for pictures. Every other element is a shape
  /// that can be any proportion it likes; a photograph dragged out of its own
  /// is a photograph that looks wrong, and putting it back by hand means
  /// finding the original numbers.
  final bool lockAspect;
  final OverlayBlend blend;

  const ImageElement(
    super.base, {
    this.assetId = "",
    this.fit = ImageFit.cover,
    this.box = const BoxSpec(padding: 0),
    this.removal = const BackgroundRemoval(),
    this.tint = const Color(0x00000000),
    this.saturation = 1,
    this.brightness = 1,
    this.crop = const ImageCrop(),
    this.frame,
    this.filter = ImageFilterPreset.none,
    this.overlay = const Color(0x00000000),
    this.lockAspect = true,
    this.blend = OverlayBlend.none,
  });

  @override
  ElementKind get kind => ElementKind.image;

  @override
  bool get keepsAspect => lockAspect;

  /// hasImage is whether there is anything to draw. An element with no
  /// picture yet is drawn as a placeholder rather than as nothing, so it can
  /// still be selected and given one.
  bool get hasImage => assetId.isNotEmpty;

  @override
  CanvasElement rebase(ElementBase base) => ImageElement(base,
      assetId: assetId,
      fit: fit,
      box: box,
      removal: removal,
      tint: tint,
      saturation: saturation,
      brightness: brightness,
      crop: crop,
      frame: frame,
      filter: filter,
      overlay: overlay,
      lockAspect: lockAspect,
      blend: blend);

  ImageElement copyWith({
    String? assetId,
    ImageFit? fit,
    BoxSpec? box,
    BackgroundRemoval? removal,
    Color? tint,
    double? saturation,
    double? brightness,
    ImageCrop? crop,
    ShapeKind? frame,
    bool clearFrame = false,
    ImageFilterPreset? filter,
    Color? overlay,
    bool? lockAspect,
    OverlayBlend? blend,
  }) =>
      ImageElement(base,
          assetId: assetId ?? this.assetId,
          fit: fit ?? this.fit,
          box: box ?? this.box,
          removal: removal ?? this.removal,
          tint: tint ?? this.tint,
          saturation: saturation ?? this.saturation,
          brightness: brightness ?? this.brightness,
          crop: crop ?? this.crop,
          frame: clearFrame ? null : (frame ?? this.frame),
          filter: filter ?? this.filter,
          overlay: overlay ?? this.overlay,
          lockAspect: lockAspect ?? this.lockAspect,
          blend: blend ?? this.blend);

  @override
  Map<String, dynamic> props() => {
        "asset": assetId,
        "fit": fit.name,
        "box": box.toJson(),
        if (removal.active) "removal": removal.toJson(),
        if (tint.a > 0) "tint": colorToJson(tint),
        if (saturation != 1) "sat": saturation,
        if (brightness != 1) "bri": brightness,
        if (!crop.isWhole) "crop": crop.toJson(),
        if (frame != null) "frame": frame!.name,
        if (filter != ImageFilterPreset.none) "filter": filter.name,
        if (blend != OverlayBlend.none) "overlay": colorToJson(overlay),
        if (!lockAspect) "lockAspect": false,
        if (blend != OverlayBlend.none) "blend": blend.name,
      };

  factory ImageElement.fromJson(Map<String, dynamic> json, ElementBase b) =>
      ImageElement(b,
          assetId: jsonString(json["asset"], ""),
          fit: ImageFit.fromName(json["fit"] as String?),
          box: jsonSpec(json["box"], BoxSpec.fromJson,
              const BoxSpec(padding: 0)),
          removal: jsonSpec(json["removal"], BackgroundRemoval.fromJson,
              const BackgroundRemoval()),
          tint: colorFromJson(json["tint"], const Color(0x00000000)),
          saturation: jsonDouble(json["sat"], 1),
          brightness: jsonDouble(json["bri"], 1),
          crop: jsonSpec(json["crop"], ImageCrop.fromJson, const ImageCrop()),
          frame: json["frame"] is String
              ? ShapeKind.fromName(json["frame"] as String?)
              : null,
          filter: ImageFilterPreset.fromName(json["filter"] as String?),
          overlay: colorFromJson(json["overlay"], const Color(0x00000000)),
          lockAspect: jsonBool(json["lockAspect"], true),
          blend: OverlayBlend.fromName(json["blend"] as String?));
}
