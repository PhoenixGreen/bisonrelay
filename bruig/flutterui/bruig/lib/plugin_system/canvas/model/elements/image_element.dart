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
  luminance("By brightness", "Remove everything above or below a brightness"),

  /// learn is the one to reach for on a photograph. See
  /// BackgroundRemoval.hints.
  learn("Show it what to remove",
      "Mark some background and some subject, and it works out the rest");

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
/// RemovalStroke is one sweep of the retouching brush.
///
/// Points are fractions of the picture's own width and height, not canvas
/// coordinates, so a stroke stays on the shoulder it was painted on when the
/// element is later resized, refitted or recropped. The radius is a fraction
/// of the picture's shorter side for the same reason.
///
/// This is the part of background removal that always works. Every automatic
/// method has photographs it cannot do -- a subject whose outline is as soft
/// as what is behind it has no edge to find, and no threshold separates a
/// white shirt from a bright highlight when the two touch -- and on those the
/// brush is not a refinement, it is the tool.
class RemovalStroke {
  final List<Offset> points;
  final double radius;

  /// hardness is how abruptly the stroke stops at its own edge: 1 is a disc
  /// with a cut edge, lower fades out towards the rim.
  ///
  /// A hard brush is the wrong tool for a photograph. Everything in one has a
  /// soft boundary -- hair most of all -- and a cut-out with a hard edge reads
  /// as a sticker whatever else is right about it.
  final double hardness;

  /// fill makes the stroke a boundary rather than a mark.
  ///
  /// Draw a rough line around the subject, let go, and everything the picture's
  /// own edge can reach without crossing that line goes. It is the tool for the
  /// job the brush was being asked to do and is bad at -- taking out a large,
  /// awkward, many-coloured area -- because it does not care what colour any of
  /// it is. Only where the line is.
  final bool fill;

  /// fillInside takes what the boundary encloses rather than what surrounds
  /// it -- for cutting a hole out of something rather than cutting it free.
  final bool fillInside;

  /// snap makes the stroke cling to what is already in the picture.
  ///
  /// Zero paints the whole disc. Above zero, the dab spreads outwards from
  /// where the pointer is only through pixels close in colour to the one under
  /// it, so brushing along a shoulder takes the sky and stops at the coat
  /// without the pointer having to trace the line. It is the difference
  /// between painting a mask and pointing at what should go.
  final double snap;

  /// keep is true for a stroke that puts the picture back and false for one
  /// that takes it away.
  final bool keep;

  const RemovalStroke({
    required this.points,
    required this.radius,
    required this.keep,
    this.hardness = 0.35,
    this.snap = 0,
    this.fill = false,
    this.fillInside = false,
  });

  RemovalStroke copyWith({List<Offset>? points}) => RemovalStroke(
        points: points ?? this.points,
        radius: radius,
        keep: keep,
        hardness: hardness,
        snap: snap,
        fill: fill,
        fillInside: fillInside,
      );

  Map<String, dynamic> toJson() => {
        // Flat pairs rather than a list of objects: a stroke is hundreds of
        // points and {"x":..,"y":..} triples the size of a saved canvas for
        // nothing a reader of the file would thank us for.
        "p": [for (var p in points) ...[p.dx, p.dy]],
        "r": radius,
        if (keep) "keep": true,
        if (hardness != 0.35) "hard": hardness,
        if (snap > 0) "snap": snap,
        if (fill) "fill": true,
        if (fillInside) "inside": true,
      };

  factory RemovalStroke.fromJson(Map<String, dynamic> json) {
    var flat = json["p"];
    var points = <Offset>[];
    if (flat is List) {
      for (var i = 0; i + 1 < flat.length; i += 2) {
        var x = flat[i], y = flat[i + 1];
        if (x is num && y is num) {
          points.add(Offset(x.toDouble(), y.toDouble()));
        }
      }
    }
    return RemovalStroke(
      points: points,
      radius: jsonDouble(json["r"], 0.05),
      keep: jsonBool(json["keep"], false),
      hardness: jsonDouble(json["hard"], 0.35),
      snap: jsonDouble(json["snap"], 0),
      fill: jsonBool(json["fill"], false),
      fillInside: jsonBool(json["inside"], false),
    );
  }
}

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

  /// hints are the marks that teach [RemovalMode.learn] what is what.
  ///
  /// A stroke with keep false is an example of background; keep true is an
  /// example of subject. Nothing is removed where they are drawn -- they are
  /// evidence rather than instructions, which is what separates them from
  /// [strokes].
  ///
  /// This exists because the three settings above cannot be dialled in on a
  /// real photograph. Every one of them asks the reader to guess a number that
  /// stands for a property of the picture they cannot see: how far apart two
  /// colours are, how sharply an edge changes. Marking two areas asks instead
  /// for the one thing they can see perfectly well -- which part is the
  /// background -- and lets the arithmetic work backwards from that.
  final List<RemovalStroke> hints;

  /// strokes are the retouching brush's marks. See [RemovalStroke].
  ///
  /// Applied after whatever the automatic method did, so a stroke is always
  /// the last word: the reader can put back a hand it ate and take out a patch
  /// it missed without either changing the settings or losing the other.
  final List<RemovalStroke> strokes;

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
    this.strokes = const [],
    this.hints = const [],
    this.threshold = 0.85,
    this.invert = false,
  });

  /// active is whether anything is being taken out at all -- by a method, or
  /// by the brush on its own. The brush alone is a legitimate way to use this:
  /// on a picture no automatic method can do, the reader paints the background
  /// out by hand and never touches the dropdown.
  bool get active => mode != RemovalMode.none || strokes.isNotEmpty;

  /// backgroundHints and subjectHints are the two sides of the evidence.
  Iterable<RemovalStroke> get backgroundHints =>
      hints.where((h) => !h.keep);
  Iterable<RemovalStroke> get subjectHints => hints.where((h) => h.keep);

  BackgroundRemoval copyWith({
    RemovalMode? mode,
    Color? keyColor,
    double? tolerance,
    double? softness,
    double? threshold,
    bool? invert,
    double? edge,
    List<RemovalStroke>? strokes,
    List<RemovalStroke>? hints,
  }) =>
      BackgroundRemoval(
        mode: mode ?? this.mode,
        keyColor: keyColor ?? this.keyColor,
        tolerance: tolerance ?? this.tolerance,
        softness: softness ?? this.softness,
        threshold: threshold ?? this.threshold,
        invert: invert ?? this.invert,
        edge: edge ?? this.edge,
        strokes: strokes ?? this.strokes,
        hints: hints ?? this.hints,
      );

  /// cacheKey identifies a cut-out. Two elements with the same picture and
  /// the same settings share one, which matters on a canvas built from a
  /// dozen copies of the same badge.
  /// cacheKey identifies the *result*, so two elements asking for the same
  /// treatment of the same picture share one copy of it.
  ///
  /// The brush has to be in here. Left out, a stroke changed nothing on screen
  /// -- the store would hand back the picture it had already made and go on
  /// doing so however much was painted. The strokes are summarised by their
  /// count and their last point rather than in full: a key holding every point
  /// of every stroke would be longer than the document.
  String cacheKey(String assetId) => "$assetId|${mode.name}|"
      "${colorToJson(keyColor)}|$tolerance|$softness|$threshold|$invert|$edge|"
      "${_marksKey(strokes)}|${_marksKey(hints)}";

/// _marksKey summarises a list of brush marks for the cache key: how many
/// there are, and how far the last one has got. A key holding every point of
/// every stroke would be longer than the document.
static String _marksKey(List<RemovalStroke> marks) => marks.isEmpty
    ? "0"
    : "${marks.length}:${marks.last.points.length}:"
        "${marks.last.points.isEmpty ? "" : marks.last.points.last}:"
        "${marks.last.keep}";

  Map<String, dynamic> toJson() => {
        "mode": mode.name,
        "key": colorToJson(keyColor),
        "tol": tolerance,
        "soft": softness,
        "thr": threshold,
        if (invert) "invert": true,
        "edge": edge,
        if (strokes.isNotEmpty)
          "strokes": [for (var stroke in strokes) stroke.toJson()],
        if (hints.isNotEmpty)
          "hints": [for (var hint in hints) hint.toJson()],
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
        strokes: [
          if (json["strokes"] case List raw)
            for (var stroke in raw)
              if (stroke is Map<String, dynamic>)
                RemovalStroke.fromJson(stroke),
        ],
        hints: [
          if (json["hints"] case List raw)
            for (var hint in raw)
              if (hint is Map<String, dynamic>) RemovalStroke.fromJson(hint),
        ],
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

/// OutlineStyle is where an outline sits relative to the shape it traces.
///
/// Not solid/dashed/dotted. Those are the choices for a border around a box,
/// where there is a path to walk; what is being traced here is the edge of an
/// alpha channel -- a silhouette with holes in it and hair round the top --
/// and it has no path anybody could put dashes along. What does vary, and
/// what a cut-out actually needs, is which side of that edge the band falls
/// on and how hard it is.
enum OutlineStyle {
  outside("Outside", "The band sits outside the subject"),
  centred("Centred", "Half outside the edge and half in"),
  inside("Inside", "The band eats into the subject's own edge"),
  glow("Glow", "A soft halo rather than a line");

  final String label;
  final String description;
  const OutlineStyle(this.label, this.description);

  static OutlineStyle fromName(String? name) => values.firstWhere(
        (s) => s.name == name,
        orElse: () => OutlineStyle.outside,
      );
}

/// ImageOutline is a line traced around whatever is left of a picture.
///
/// The sticker look, and the reason to want it is legibility rather than
/// decoration: a subject cut out of a photograph and dropped on a busy canvas
/// has nothing separating it from what is behind it, and a dark player on a
/// dark background reads as a smudge until something draws the boundary.
///
/// It traces the alpha channel, so it needs no help from the removal that
/// produced it and does not care which method or how many brush strokes got
/// there. On a picture with nothing taken out it traces the rectangle, which
/// is a border and is a perfectly reasonable thing to ask for too.
class ImageOutline {
  final Color color;

  /// width is in canvas units, like every other thickness here, so an outline
  /// stays the same weight when the element is resized.
  final double width;

  final OutlineStyle style;

  /// feather fades the band out as it goes, 0 for a hard line and 1 for one
  /// that is transparent by the time it reaches its own edge.
  final double feather;

  const ImageOutline({
    this.color = const Color(0xFFFFFFFF),
    this.width = 0,
    this.style = OutlineStyle.outside,
    this.feather = 0,
  });

  /// on is whether it draws anything. A width of zero is the default and the
  /// off switch: there is no separate toggle to get out of step with it.
  bool get on => width > 0 && color.a > 0;

  ImageOutline copyWith({
    Color? color,
    double? width,
    OutlineStyle? style,
    double? feather,
  }) =>
      ImageOutline(
        color: color ?? this.color,
        width: width ?? this.width,
        style: style ?? this.style,
        feather: feather ?? this.feather,
      );

  Map<String, dynamic> toJson() => {
        "c": colorToJson(color),
        "w": width,
        "s": style.name,
        if (feather > 0) "f": feather,
      };

  factory ImageOutline.fromJson(Map<String, dynamic> json) => ImageOutline(
        color: colorFromJson(json["c"]),
        width: jsonDouble(json["w"], 0).clamp(0.0, 400.0),
        style: OutlineStyle.fromName(json["s"] as String?),
        feather: jsonDouble(json["f"], 0).clamp(0.0, 1.0),
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

  /// outline traces what is left of the picture. See [ImageOutline].
  final ImageOutline outline;

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
    this.outline = const ImageOutline(),
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
      outline: outline,
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
    ImageOutline? outline,
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
          outline: outline ?? this.outline,
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
        if (outline.on) "outline": outline.toJson(),
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
          outline: jsonSpec(json["outline"], ImageOutline.fromJson,
              const ImageOutline()),
          overlay: colorFromJson(json["overlay"], const Color(0x00000000)),
          lockAspect: jsonBool(json["lockAspect"], true),
          blend: OverlayBlend.fromName(json["blend"] as String?));
}

/// fitToPicture gives an element the proportions of the picture in it.
///
/// The picture is contained rather than covered: the box shrinks to the
/// picture's shape inside the space it already had, keeping its centre, and
/// never grows. Growing is the tempting version -- keep the width, work out
/// the height -- and it puts a tall photograph's bottom half off the bottom of
/// the canvas, which is a worse first impression than a small picture.
ImageElement fitToPicture(ImageElement e, Size picture) {
  if (picture.width <= 0 || picture.height <= 0) return e;
  var box = e.base;
  if (box.width <= 0 || box.height <= 0) return e;

  var aspect = picture.width / picture.height;
  var width = box.width;
  var height = width / aspect;
  if (height > box.height) {
    height = box.height;
    width = height * aspect;
  }

  return e.rebase(box.copyWith(
    x: box.x + (box.width - width) / 2,
    y: box.y + (box.height - height) / 2,
    width: width,
    height: height,
  )) as ImageElement;
}
