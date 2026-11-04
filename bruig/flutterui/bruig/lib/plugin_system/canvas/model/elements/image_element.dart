import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_warp.dart';

export 'package:bruig/plugin_system/canvas/model/elements/image_warp.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_mask.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_strokes.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

/// RemovalMode is how an image's background is taken out: [chromaKey] and
/// [cornerFlood] for a flat colour behind a logo or screenshot, [luminance]
/// for dark on light (a chart, a scan), [learn] for a photograph. All run on
/// the raw pixels in Dart, offline, with no model.
enum RemovalMode {
  none("None", "Leave the image as it is"),
  chromaKey("Colour key", "Remove everything close to one chosen colour"),
  cornerFlood("Flood from edges",
      "Remove the connected region touching the picture's edges"),
  luminance("By brightness", "Remove everything above or below a brightness"),

  /// learn works from marked examples. See BackgroundRemoval.hints.
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

/// ImageFit is how the picture sits in its box. Our own enum rather than
/// BoxFit, so the model needs only dart:ui and a saved document does not
/// depend on another library's names; render/ maps them.
enum ImageFit {
  cover("Cover"),
  contain("Show whole"),
  stretch("Stretch");

  final String label;
  const ImageFit(this.label);

  static ImageFit fromName(String? name) =>
      values.firstWhere((f) => f.name == name, orElse: () => ImageFit.cover);
}

/// RemovalStroke is one sweep of the background-removal brush.
///
/// Points are fractions of the picture's own width and height, and the
/// radius a fraction of its shorter side, so a stroke stays put when the
/// element is resized, refitted or recropped.
class RemovalStroke {
  final List<Offset> points;
  final double radius;

  /// hardness is how abruptly the stroke stops at its own edge: 1 is a disc
  /// with a cut edge, lower fades out towards the rim.
  final double hardness;

  /// fill makes the stroke a boundary rather than a mark: everything the
  /// picture's own edge can reach without crossing it goes, whatever its
  /// colour.
  final bool fill;

  /// fillInside takes what the boundary encloses rather than what surrounds
  /// it -- for cutting a hole out of something rather than cutting it free.
  final bool fillInside;

  /// snap makes the stroke cling to what is in the picture. Zero paints the
  /// whole disc; above zero, a dab spreads from the pointer only through
  /// pixels close in colour to the one under it.
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
        // Flat pairs: a stroke is hundreds of points.
        "p": [
          for (var p in points) ...[p.dx, p.dy]
        ],
        "r": radius,
        if (keep) "keep": true,
        if (hardness != 0.35) "hard": hardness,
        if (snap > 0) "snap": snap,
        if (fill) "fill": true,
        if (fillInside) "inside": true,
      };

  factory RemovalStroke.fromJson(Map<String, dynamic> json) {
    var points = fractionsFromJson(json["p"]);
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

/// BackgroundRemoval is the recipe, never the result: settings rather than
/// a cut-out bitmap, so the original stays whole, the settings can be changed
/// later, and the document holds no second copy. The cut-out is recomputed
/// when the settings change and cached in memory (see [cacheKey]).
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

  /// hints are the marks that teach [RemovalMode.learn] what is what: keep
  /// false marks background, keep true subject. Unlike [strokes] they remove
  /// nothing themselves; they are examples.
  final List<RemovalStroke> hints;

  /// strokes are the brush's marks, applied after the automatic method so a
  /// stroke always has the last word.
  final List<RemovalStroke> strokes;

  /// edge is how sharp a change has to be to stop the flood, for
  /// [RemovalMode.cornerFlood]; [tolerance] stops it running away. It works
  /// because backgrounds are usually smooth and subjects have crisp outlines.
  /// Low values stop at the faintest change.
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

  /// active is whether anything is being taken out, by a method or by the
  /// brush alone.
  bool get active => mode != RemovalMode.none || strokes.isNotEmpty;

  /// backgroundHints and subjectHints split [hints] by side.
  Iterable<RemovalStroke> get backgroundHints => hints.where((h) => !h.keep);
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

  /// cacheKey identifies the cut-out, so elements giving the same picture
  /// the same treatment share one. The brush marks must be in it or a new
  /// stroke would change nothing on screen; see [_marksKey].
  String cacheKey(String assetId) => "$assetId|${mode.name}|"
      "${colorToJson(keyColor)}|$tolerance|$softness|$threshold|$invert|$edge|"
      "${_marksKey(strokes)}|${_marksKey(hints)}";

  /// _marksKey summarises brush marks by their count and how far the last
  /// one has got: a key holding every point would be longer than the
  /// document.
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
        if (hints.isNotEmpty) "hints": [for (var hint in hints) hint.toJson()],
      };

  factory BackgroundRemoval.fromJson(Map<String, dynamic> json) =>
      BackgroundRemoval(
        mode: RemovalMode.fromName(jsonStr(json["mode"])),
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

/// ImageFilterPreset is a look applied to the whole picture, each one
/// colour matrix; finer control is in tint, saturation and brightness.
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

/// OverlayBlend is how an overlay colour is laid over the picture. Our own
/// names, so a saved document does not depend on BlendMode's.
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

/// OutlineStyle is where an outline sits relative to the edge it traces.
/// Not dashes: the edge is an alpha channel's, with no path to dash along.
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

/// ImageOutline is a line traced round whatever is left of a picture (the
/// sticker look). It traces the alpha channel, so on a picture with nothing
/// taken out it is a border round the rectangle.
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

  /// on is whether it draws anything; a width of zero is the off switch.
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
        style: OutlineStyle.fromName(jsonStr(json["s"])),
        feather: jsonDouble(json["f"], 0).clamp(0.0, 1.0),
      );
}

/// ImageCrop is which part of the picture is shown, in fractions of it so a
/// crop survives the picture being swapped for a larger copy.
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

/// ImageFraming is where the picture sits inside its frame and how much of
/// it is shown, for [ImageFit.cover] only. A covering picture has slack in
/// one direction; [x] and [y] spend it (0 left or top, 1 right or bottom),
/// and [zoom] above 1 scales up to make slack where there was none.
///
/// Not [ImageCrop]: a crop is about the picture's pixels, framing about the
/// frame. Kept as fractions of the slack, a reframed picture survives its
/// element changing shape without the subject sliding out of shot.
class ImageFraming {
  /// x and y are how the slack is spent, 0.5 being the middle.
  final double x;
  final double y;

  /// zoom is 1 for just filling the frame, capped at 8.
  final double zoom;

  const ImageFraming({this.x = 0.5, this.y = 0.5, this.zoom = 1});

  bool get isDefault => x == 0.5 && y == 0.5 && zoom == 1;

  ImageFraming copyWith({double? x, double? y, double? zoom}) => ImageFraming(
        x: (x ?? this.x).clamp(0.0, 1.0),
        y: (y ?? this.y).clamp(0.0, 1.0),
        zoom: (zoom ?? this.zoom).clamp(1.0, 8.0),
      );

  Map<String, dynamic> toJson() => {"x": x, "y": y, "zoom": zoom};

  factory ImageFraming.fromJson(Map<String, dynamic> json) => ImageFraming(
        x: jsonDouble(json["x"], 0.5).clamp(0.0, 1.0),
        y: jsonDouble(json["y"], 0.5).clamp(0.0, 1.0),
        zoom: jsonDouble(json["zoom"], 1).clamp(1.0, 8.0),
      );
}

/// driftedFraming is [framing] [t] of the way through the Drift loop
/// [preset], which moves [amount] of the picture: how much closer a zoom
/// ends, or how much a pan is zoomed to have room to cross. The frame stays
/// put; the picture moves inside it.
ImageFraming driftedFraming(
    ImageFraming framing, LoopPreset preset, double amount, double t) {
  t = t.clamp(0.0, 1.0);
  var a = amount.clamp(0.0, 1.0);
  double across(double from, double to) => from + (to - from) * t;
  return switch (preset) {
    LoopPreset.driftIn => framing.copyWith(zoom: framing.zoom * (1 + a * t)),
    LoopPreset.driftOut =>
      framing.copyWith(zoom: framing.zoom * (1 + a * (1 - t))),
    // The camera moves left: the picture slides right under it, so the
    // part of it shown runs from its right towards its left.
    LoopPreset.driftLeft =>
      framing.copyWith(zoom: framing.zoom * (1 + a), x: across(1, 0)),
    LoopPreset.driftRight =>
      framing.copyWith(zoom: framing.zoom * (1 + a), x: across(0, 1)),
    LoopPreset.driftUp =>
      framing.copyWith(zoom: framing.zoom * (1 + a), y: across(1, 0)),
    LoopPreset.driftDown =>
      framing.copyWith(zoom: framing.zoom * (1 + a), y: across(0, 1)),
    _ => framing,
  };
}

/// driftPerStrength is how much of the picture a drift moves at a loop
/// strength of 1.
const double driftPerStrength = 0.15;

/// _driftAsLoop reads an older save's "drift" ({"kind": "zoomIn", "amount":
/// 0.15}) into [animation] as a loop, where it has no loop of its own.
ElementAnimation _driftAsLoop(ElementAnimation animation, Object? drift) {
  if (drift is! Map<String, dynamic> || animation.loop.on) return animation;
  var preset = switch (drift["kind"]) {
    "zoomIn" => LoopPreset.driftIn,
    "zoomOut" => LoopPreset.driftOut,
    "panLeft" => LoopPreset.driftLeft,
    "panRight" => LoopPreset.driftRight,
    "panUp" => LoopPreset.driftUp,
    "panDown" => LoopPreset.driftDown,
    _ => LoopPreset.none,
  };
  if (preset == LoopPreset.none) return animation;
  return animation.copyWith(
      loop: ElementLoop(
          preset: preset,
          strength: jsonDouble(drift["amount"], driftPerStrength) /
              driftPerStrength));
}

/// ImageElement is a picture on the canvas. It holds an [assetId], not the
/// bytes, which live once in the canvas asset store beside the document (see
/// storage/canvas_assets.dart).
class ImageElement extends CanvasElement {
  final String assetId;
  final ImageFit fit;
  final BoxSpec box;
  final BackgroundRemoval removal;

  /// tint multiplies the image's colours; transparent is none.
  final Color tint;

  /// saturation and brightness are 1 for unchanged.
  final double saturation;
  final double brightness;

  final ImageCrop crop;
  final ImageFraming framing;
  final ImageWarp warp;

  /// frame is the shape the picture is cut to (any a shape element can
  /// draw), or null for a rectangle.
  final ShapeKind? frame;

  final ImageFilterPreset filter;

  final ImageOutline outline;

  /// overlay is a colour laid over the picture, and [blend] is how.
  final Color overlay;

  final OverlayBlend blend;

  final ElementAnimation animation;

  /// layers are what the picture is composited from, back to front (see
  /// image_layers.dart). The fields above are the base layer; with no
  /// layers, the base layer is drawn alone.
  final List<ImageLayer> layers;

  /// mask is what of the picture is shown, applied after [removal]. See
  /// image_mask.dart.
  final ImageMask mask;

  /// retouch is the retouching strokes done to the picture, in order, under
  /// its mask. See image_strokes.dart.
  final List<StrokeMark> retouch;

  /// scaleContent makes resizing the frame scale its layers with it. Off,
  /// the frame is resized round them and each stays where it is on the page
  /// (see keptInPlace).
  final bool scaleContent;

  /// clip cuts everything in the picture to its frame. Off, nothing is cut
  /// and the frame grows to take in what is drawn past it (see grownToFit).
  final bool clip;

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
    this.framing = const ImageFraming(),
    this.warp = const ImageWarp(),
    this.frame,
    this.filter = ImageFilterPreset.none,
    this.outline = const ImageOutline(),
    this.overlay = const Color(0x00000000),
    this.blend = OverlayBlend.none,
    this.animation = const ElementAnimation(),
    this.layers = const [],
    this.mask = const ImageMask(),
    this.retouch = const [],
    this.scaleContent = false,
    this.clip = false,
  });

  @override
  ElementKind get kind => ElementKind.image;

  @override
  Set<String> get assetIds => {
        if (assetId.isNotEmpty) assetId,
        ...box.assetIds,
        for (var layer in layers) ...?layer.look?.assetIds,
        // The mask's subject is a stored picture too.
        if (mask.subject.isNotEmpty) mask.subject,
      };

  /// stack is every layer, back to front, with exactly one base layer: if
  /// [layers] has none or several, one is put at the bottom.
  List<ImageLayer> get stack {
    if (layers.isEmpty) return const [ImageLayer.base];
    var bases = layers.where((l) => l.isBase).length;
    if (bases == 1) return layers;
    var others = [
      for (var l in layers)
        if (!l.isBase) l
    ];
    var base =
        layers.firstWhere((l) => l.isBase, orElse: () => ImageLayer.base);
    return [base, ...others];
  }

  /// layered is whether there is more to draw than the plain base picture.
  bool get layered => layers.any((l) => !l.plain);

  ImageLayer? layerById(String id) {
    for (var l in stack) {
      if (l.id == id) return l;
    }
    return null;
  }

  ImageElement withLayers(List<ImageLayer> next) => copyWith(layers: next);

  /// withLayer is this element with the layer [id] changed by [edit].
  ImageElement withLayer(String id, ImageLayer Function(ImageLayer) edit) =>
      withLayers([for (var l in stack) l.id == id ? edit(l) : l]);

  /// croppedTo is this element with [next] as its crop and its box trimmed
  /// to match, so what is left of the picture stays where it was on the
  /// canvas. A crop alone would refit the rest to the same box: a zoom.
  ///
  /// With layers, the base layer's place is trimmed, not the frame, which
  /// holds the other layers too. [flipX] and [flipY] say a mirrored layer's
  /// left is on its right; for the base picture its own layer's are used.
  ImageElement croppedTo(ImageCrop next,
      {bool flipX = false, bool flipY = false}) {
    var was = crop;
    if (was.width <= 0 || was.height <= 0) {
      return copyWith(crop: next);
    }
    var base = layered ? stack.firstWhere((l) => l.isBase) : null;
    if (base != null) {
      flipX = base.flipX;
      flipY = base.flipY;
    }
    var box = base?.place ?? Rect.fromLTWH(x, y, width, height);
    var perX = box.width / was.width;
    var perY = box.height / was.height;

    // How far each side of the picture comes in, and on which side of the
    // box that side is.
    var inL = (next.left - was.left) * perX;
    var inR = (was.right - next.right) * perX;
    var inT = (next.top - was.top) * perY;
    var inB = (was.bottom - next.bottom) * perY;
    if (flipX) (inL, inR) = (inR, inL);
    if (flipY) (inT, inB) = (inB, inT);
    var trimmed = Rect.fromLTRB(
        box.left + inL, box.top + inT, box.right - inR, box.bottom - inB);

    // Never inside out, and never too small to grab: 8 canvas units, or
    // the same in a layer's units.
    var least = base == null
        ? 8.0
        : 8.0 * layerUnits / math.max(1e-9, math.min(width, height));
    if (trimmed.width < least || trimmed.height < least) {
      return copyWith(crop: next);
    }
    if (base != null) {
      return copyWith(crop: next)
          .withLayer(base.id, (l) => l.copyWith(basePlace: trimmed));
    }
    return copyWith(crop: next).withBase(
      x: trimmed.left,
      y: trimmed.top,
      width: trimmed.width,
      height: trimmed.height,
    ) as ImageElement;
  }

  /// withProportionsKept is this picture with its proportions held as it is
  /// resized, or let go. Let go, a covering picture becomes stretched, so
  /// pulling a side squashes it rather than trimming it. Held again, the fit
  /// is left alone.
  ImageElement withProportionsKept(bool keep) {
    var next = withBase(lockAspect: keep) as ImageElement;
    if (!keep && fit == ImageFit.cover) {
      return next.copyWith(fit: ImageFit.stretch);
    }
    return next;
  }

  /// hasImage is whether there is a picture; without one a placeholder is
  /// drawn so it can still be selected.
  bool get hasImage => assetId.isNotEmpty;

  @override
  CanvasElement rebase(ElementBase base) {
    var next = _rebased(base);
    return scaleContent ? next : keptInPlace(this, next);
  }

  ImageElement _rebased(ElementBase base) => ImageElement(base,
      assetId: assetId,
      fit: fit,
      box: box,
      removal: removal,
      tint: tint,
      saturation: saturation,
      brightness: brightness,
      crop: crop,
      framing: framing,
      warp: warp,
      frame: frame,
      filter: filter,
      outline: outline,
      overlay: overlay,
      blend: blend,
      animation: animation,
      layers: layers,
      mask: mask,
      retouch: retouch,
      scaleContent: scaleContent,
      clip: clip);

  ImageElement copyWith({
    String? assetId,
    ImageFit? fit,
    BoxSpec? box,
    BackgroundRemoval? removal,
    Color? tint,
    double? saturation,
    double? brightness,
    ImageCrop? crop,
    ImageFraming? framing,
    ImageWarp? warp,
    ShapeKind? frame,
    bool clearFrame = false,
    ImageFilterPreset? filter,
    ImageOutline? outline,
    Color? overlay,
    OverlayBlend? blend,
    ElementAnimation? animation,
    List<ImageLayer>? layers,
    ImageMask? mask,
    List<StrokeMark>? retouch,
    bool? scaleContent,
    bool? clip,
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
          framing: framing ?? this.framing,
          warp: warp ?? this.warp,
          frame: clearFrame ? null : (frame ?? this.frame),
          filter: filter ?? this.filter,
          outline: outline ?? this.outline,
          overlay: overlay ?? this.overlay,
          blend: blend ?? this.blend,
          animation: animation ?? this.animation,
          layers: layers ?? this.layers,
          mask: mask ?? this.mask,
          retouch: retouch ?? this.retouch,
          scaleContent: scaleContent ?? this.scaleContent,
          clip: clip ?? this.clip);

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
        if (!framing.isDefault) "framing": framing.toJson(),
        if (warp.active || warp.cols != 4 || warp.rows != 4)
          "warp": warp.toJson(),
        if (frame != null) "frame": frame!.name,
        if (filter != ImageFilterPreset.none) "filter": filter.name,
        if (outline.on) "outline": outline.toJson(),
        if (blend != OverlayBlend.none) "overlay": colorToJson(overlay),
        if (blend != OverlayBlend.none) "blend": blend.name,
        if (animation.any) "anim": animation.toJson(),
        // Only when layered, so a plain picture saves without layers.
        if (layered) "layers": [for (var l in stack) l.toJson()],
        if (!mask.empty) "mask": mask.toJson(),
        if (retouch.isNotEmpty) "retouch": [for (var s in retouch) s.toJson()],
        if (scaleContent) "scaleContent": true,
        if (clip != _clippedBefore(frame, box)) "clip": clip,
      };

  factory ImageElement.fromJson(Map<String, dynamic> json, ElementBase b) =>
      ImageElement(
          // A save with no "aspect" key predates element-wide proportions,
          // when pictures were locked unless "lockAspect" said otherwise.
          json.containsKey("aspect")
              ? b
              : b.copyWith(lockAspect: jsonBool(json["lockAspect"], true)),
          assetId: jsonString(json["asset"], ""),
          fit: ImageFit.fromName(jsonStr(json["fit"])),
          box: jsonSpec(
              json["box"], BoxSpec.fromJson, const BoxSpec(padding: 0)),
          removal: jsonSpec(json["removal"], BackgroundRemoval.fromJson,
              const BackgroundRemoval()),
          tint: colorFromJson(json["tint"], const Color(0x00000000)),
          saturation: jsonDouble(json["sat"], 1),
          brightness: jsonDouble(json["bri"], 1),
          crop: jsonSpec(json["crop"], ImageCrop.fromJson, const ImageCrop()),
          framing: jsonSpec(
              json["framing"], ImageFraming.fromJson, const ImageFraming()),
          warp: jsonSpec(json["warp"], ImageWarp.fromJson, const ImageWarp()),
          frame: json["frame"] is String
              ? ShapeKind.fromName(jsonStr(json["frame"]))
              : null,
          filter: ImageFilterPreset.fromName(jsonStr(json["filter"])),
          outline: jsonSpec(
              json["outline"], ImageOutline.fromJson, const ImageOutline()),
          overlay: colorFromJson(json["overlay"], const Color(0x00000000)),
          blend: OverlayBlend.fromName(jsonStr(json["blend"])),
          animation: _driftAsLoop(
              jsonSpec(json["anim"], ElementAnimation.fromJson,
                  const ElementAnimation()),
              json["drift"]),
          layers: [
            if (json["layers"] case List raw)
              for (var l in raw)
                if (l is Map<String, dynamic>)
                  if (ImageLayer.fromJson(l) case var layer?) layer,
          ],
          mask: jsonSpec(json["mask"], ImageMask.fromJson, const ImageMask()),
          retouch: strokesFromJson(json["retouch"]),
          scaleContent: jsonBool(json["scaleContent"], false),
          clip: json.containsKey("clip")
              ? jsonBool(json["clip"], false)
              : _clippedBefore(
                  json["frame"] is String ? ShapeKind.rectangle : null,
                  jsonSpec(json["box"], BoxSpec.fromJson,
                      const BoxSpec(padding: 0))));

  /// grownToFit is this picture with its frame grown to take in everything
  /// drawn in it, each layer kept where it is on the page. Never smaller (a
  /// shrinking frame would move under the pointer); unchanged when it clips.
  ImageElement grownToFit() {
    if (clip || !layered) return this;
    var inner = box.inner(bounds);
    var content = contentRectOf(this, inner);
    if (content == null) return this;
    var need = inner.expandToInclude(content);
    // A hair over is a rounding error, not a stroke past the edge.
    if (need.left >= inner.left - 0.01 &&
        need.top >= inner.top - 0.01 &&
        need.right <= inner.right + 0.01 &&
        need.bottom <= inner.bottom + 0.01) {
      return this;
    }
    return _framedTo(need, inner);
  }

  /// fittedToContent is this picture with its frame exactly round what is
  /// drawn in it, smaller or larger, everything kept where it is.
  ImageElement fittedToContent() {
    if (!layered) return this;
    var inner = box.inner(bounds);
    var content = contentRectOf(this, inner);
    if (content == null || content.isEmpty) return this;
    return _framedTo(content, inner);
  }

  /// _framedTo is this picture with its inner frame, now [inner], made [to],
  /// padding kept and every layer where it was on the page.
  ImageElement _framedTo(Rect to, Rect inner) {
    var b = bounds;
    var next = Rect.fromLTRB(
        b.left - (inner.left - to.left),
        b.top - (inner.top - to.top),
        b.right + (to.right - inner.right),
        b.bottom + (to.bottom - inner.bottom));
    var resized = keptInPlace(
        this,
        _rebased(base.copyWith(
            x: next.left,
            y: next.top,
            width: next.width,
            height: next.height)));
    if (rotation == 0) return resized;
    // A turned picture turns about its middle, which has moved: shift it
    // back by the difference so the layers stay where they were seen.
    var moved = next.center - b.center;
    var t = rotation * math.pi / 180;
    var turned = Offset(moved.dx * math.cos(t) - moved.dy * math.sin(t),
        moved.dx * math.sin(t) + moved.dy * math.cos(t));
    var d = turned - moved;
    return resized._rebased(resized.base
        .copyWith(x: resized.base.x + d.dx, y: resized.base.y + d.dy));
  }
}

/// _clippedBefore is the clip default for a save with no "clip" key: on for
/// a picture cut to a shape or with rounded corners.
bool _clippedBefore(ShapeKind? frame, BoxSpec box) =>
    frame != null || box.isRounded;

/// fitToPicture gives an element the proportions of the picture in it. The
/// box shrinks to the picture's shape within the space it had, keeping its
/// centre; it never grows, which could push a tall photograph off the canvas.
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

  var fitted = e.rebase(box.copyWith(
    x: box.x + (box.width - width) / 2,
    y: box.y + (box.height - height) / 2,
    width: width,
    height: height,
  )) as ImageElement;
  // The frame took the picture's shape, so the base layer fills it.
  return fitted.layered
      ? fitted.withLayer(baseLayerId, (l) => l.copyWith(clearBasePlace: true))
      : fitted;
}
