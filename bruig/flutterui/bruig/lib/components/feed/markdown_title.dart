import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'dart:ui' as ui;

import 'package:bruig/components/feed/markdown_header.dart';
import 'package:bruig/components/md_elements.dart';
import 'package:flutter/material.dart';

// markdown_title.dart is how a banner's words are set.
//
// A banner's title is branding rather than reading: it is the one piece of a
// site whose look belongs to whoever wrote it, not to whoever is reading. So
// it has fields of its own, and enough of them to be worth a file -- this is
// the half of the header most likely to grow.

/// titleStyleFields is every field that says how a banner's writing is set.
///
/// Listed here rather than in the header, beside the code that reads them:
/// the header only needs to know they are fields so a line with a colon in
/// it is not mistaken for one.
const List<String> titleStyleFields = [
  "titlesize",
  "titleweight",
  "titleitalic",
  "titlecase",
  "titletracking",
  "titlecolor",
  "titlegradient",
  "titleimage",
  "titleoutline",
  "titleoutlinecolor",
  "titleoutlinegradient",
  "titlebackground",
  "titleborder",
  "titlebordercolor",
  "titleradius",
  "titlepadding",
];

/// HeaderTextStyle is how a banner's writing is set.
///
/// A banner's title is branding rather than reading: it is the one piece of
/// a site whose look belongs to whoever wrote it, not to whoever is reading.
/// So these are fields on the block, unlike everything else about a page.
@immutable
class HeaderTextStyle {
  /// size in pixels, or null to be set to the height of the row it is in.
  ///
  /// Null is the usual case now. A row is a fixed height and everything in
  /// it is sized to that, so a title comes out level with the logo beside it
  /// without either being told about the other -- which is what the old
  /// "titlesize: fill" was for, and why it is no longer a thing to write.
  final double? size;
  final bool bold;
  final bool italic;

  /// caps transforms the words themselves rather than drawing them
  /// differently, so what is copied out of the page is what was written.
  final String caps;
  final double tracking;
  final List<Color> gradient;

  /// image fills the letters with a picture, the way a gradient fills them
  /// with colours. Held as the raw embed and decoded where it is drawn,
  /// which is the only place that has anything to build a shader with.
  final String? image;
  final Color? color;
  final Color? background;

  /// outline is a line drawn round the letters themselves, as opposed to
  /// [border], which is a box drawn round the whole title.
  final double outline;
  final Color? outlineColor;
  final List<Color> outlineGradient;

  final Color? border;
  final double borderWidth;
  final double radius;
  final double padding;

  const HeaderTextStyle({
    this.size,
    this.bold = false,
    this.italic = false,
    this.caps = "",
    this.tracking = 0,
    this.gradient = const [],
    this.image,
    this.color,
    this.background,
    this.outline = 0,
    this.outlineColor,
    this.outlineGradient = const [],
    this.border,
    this.borderWidth = 0,
    this.radius = 0,
    this.padding = 0,
  });

  /// none is a title with nothing said about it, which is drawn the way the
  /// rest of the page is.
  bool get plain =>
      size == null &&
      !bold &&
      !italic &&
      caps.isEmpty &&
      tracking == 0 &&
      gradient.isEmpty &&
      image == null &&
      outline == 0 &&
      color == null &&
      background == null &&
      border == null;

  /// apply transforms the words. Only case does anything here; the rest is
  /// drawing.
  String apply(String text) {
    switch (caps) {
      case "upper":
        return text.toUpperCase();
      case "lower":
        return text.toLowerCase();
      default:
        return text;
    }
  }

  factory HeaderTextStyle.parse(Map<String, String> fields) {
    var rawSize = (fields["titlesize"] ?? "").trim().toLowerCase();
    var colours = _colourList(fields["titlegradient"]);
    var outlineColours = _colourList(fields["titleoutlinegradient"]);
    return HeaderTextStyle(
      size: double.tryParse(rawSize)?.clamp(8, 200),
      bold: (fields["titleweight"] ?? "").trim().toLowerCase() == "bold",
      italic: (fields["titleitalic"] ?? "").trim().toLowerCase() == "yes",
      caps: (fields["titlecase"] ?? "").trim().toLowerCase(),
      tracking:
          (double.tryParse(fields["titletracking"] ?? "") ?? 0).clamp(-5, 40),
      gradient: colours.length > 1 ? colours : const [],
      image: (fields["titleimage"] ?? "").isEmpty ? null : fields["titleimage"],
      color: _colour(fields["titlecolor"]) ??
          (colours.length == 1 ? colours.first : null),
      background: _colour(fields["titlebackground"]),
      outline:
          (double.tryParse(fields["titleoutline"] ?? "") ?? 0).clamp(0, 12),
      outlineColor: _colour(fields["titleoutlinecolor"]) ??
          (outlineColours.length == 1 ? outlineColours.first : null),
      outlineGradient: outlineColours.length > 1 ? outlineColours : const [],
      border: _colour(fields["titlebordercolor"]),
      borderWidth:
          (double.tryParse(fields["titleborder"] ?? "") ?? 0).clamp(0, 16),
      radius: (double.tryParse(fields["titleradius"] ?? "") ?? 0).clamp(0, 64),
      padding:
          (double.tryParse(fields["titlepadding"] ?? "") ?? 0).clamp(0, 64),
    );
  }
}

/// _colour reads #rgb, #rrggbb or #rrggbbaa. Anything else is nothing, which
/// leaves whatever it would have replaced in place.
///
/// Deliberately not colorFromHex from the theming system, which looks like
/// the same function and is not: that one reads #AARRGGBB, the order Flutter
/// stores a colour in, because it reads back what the app itself wrote, and
/// it throws on anything it cannot parse. This reads what a person typed
/// into a page, in the order CSS writes it, and treats a mistake as nothing
/// said. Merging the two would either start throwing at a typo in a page or
/// start misreading every saved theme.
Color? _colour(String? raw) {
  var t = (raw ?? "").trim();
  if (!t.startsWith("#")) return null;
  var hex = t.substring(1);

  if (hex.length == 3) {
    hex = hex.split("").map((c) => "$c$c").join();
  }
  if (hex.length == 8) {
    // Written the way CSS writes it -- #rrggbbaa -- and read the way Flutter
    // wants it, with the alpha first. Only here: a six-digit colour has no
    // alpha to move, and rotating it after adding one turned #f00 into a
    // fully transparent yellow.
    hex = hex.substring(6) + hex.substring(0, 6);
  } else if (hex.length == 6) {
    hex = "ff$hex";
  } else {
    return null;
  }

  var v = int.tryParse(hex, radix: 16);
  return v == null ? null : Color(v);
}

List<Color> _colourList(String? raw) => [
      for (var part in (raw ?? "").split(","))
        if (_colour(part) != null) _colour(part)!,
    ];

/// HeaderText draws a title.
///
/// Set to the height of the row it is in, and condensed rather than shrunk
/// when it is too wide for the room. Those are the same decision: a row is a
/// fixed height, so anything that changed the size of the letters would
/// change how tall the writing looks and undo the point of fixing it.
/// Squeezing the letters keeps the cap height and loses only the width.
class HeaderText extends StatefulWidget {
  final String text;
  final HeaderTextStyle style;

  /// fitTo is the height to set the writing to -- the row's.
  final double fitTo;

  /// within is which way it runs out of room, so a right-hand title
  /// condenses towards the edge it is against.
  final Alignment within;

  const HeaderText({
    super.key,
    required this.text,
    required this.style,
    required this.fitTo,
    required this.within,
  });

  @override
  State<HeaderText> createState() => _HeaderTextState();
}

class _HeaderTextState extends State<HeaderText> {
  String get text => widget.text;
  HeaderTextStyle get style => widget.style;
  double get fitTo => widget.fitTo;
  Alignment get within => widget.within;

  /// _fill is the picture the letters are filled with, once it has been
  /// decoded. A shader has to be built in a paint callback, which cannot
  /// wait for anything -- so the decoding happens here and the letters are
  /// drawn in their plain colour until it lands.
  ui.Image? _fill;

  @override
  void initState() {
    super.initState();
    _loadFill();
  }

  @override
  void didUpdateWidget(HeaderText old) {
    super.didUpdateWidget(old);
    if (old.style.image != style.image) {
      _fill?.dispose();
      _fill = null;
      _loadFill();
    }
  }

  @override
  void dispose() {
    _fill?.dispose();
    super.dispose();
  }

  Future<void> _loadFill() async {
    var raw = style.image;
    if (raw == null) return;
    var image = embedImage(raw);
    if (image == null || isSvgMime(image.mime)) {
      // A vector has no pixels to pour into the letters. Left unfilled
      // rather than failing: the title still reads.
      return;
    }
    try {
      var codec = await ui.instantiateImageCodec(image.bytes);
      var frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _fill = frame.image);
    } catch (_) {
      // Not a picture this machine can read; the title is drawn plainly.
    }
  }

  /// _stripped removes the heading marks a writer puts in out of habit. How
  /// large a title is set is the row's height, not how many hashes were
  /// typed -- three of them in a banner would otherwise be small.
  String get _stripped =>
      style.apply(text.replaceFirst(RegExp(r'^\s*#{1,6}\s*'), "").trim());

  /// minCondense is as narrow as the letters may be squeezed.
  ///
  /// Past this it stops being condensed type and starts being unreadable, so
  /// what is still too long is cut with an ellipsis instead. Losing the end
  /// of a title beats keeping all of it illegibly.
  static const double minCondense = 0.6;

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var inset = style.padding * 2;
    var lineHeight = (fitTo - inset).clamp(8.0, 400.0);
    var fontSize = style.size ?? lineHeight * 0.72;

    // Measured and drawn in the same style, which is not the same as the
    // style handed to Text.
    //
    // A TextStyle inherits by default, so what a Text actually paints is the
    // surrounding DefaultTextStyle merged with this -- and the surrounding
    // one is the Markdown guide's, which sets a family. Measuring the bare
    // style measured the wrong font: the guide's is wider, so a title was
    // found to fit and then drawn too wide, and ran off the edge of the
    // banner. Never visible in a test, where every glyph is the same width
    // in every font.
    var painted = TextStyle(
      fontSize: fontSize,
      height: 1.0,
      fontWeight: style.bold ? FontWeight.bold : FontWeight.w500,
      fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
      letterSpacing: style.tracking == 0 ? null : style.tracking,
      // White under a shader: it replaces the colour, and anything else
      // tints what the shader paints.
      color: style.gradient.isNotEmpty || style.image != null
          ? Colors.white
          : (style.color ?? theme.colors.onSurface),
    );

    var effective = DefaultTextStyle.of(context).style.merge(painted);

    return LayoutBuilder(builder: (context, constraints) {
      var available = constraints.maxWidth - inset;
      var painter = TextPainter(
        text: TextSpan(text: _stripped, style: effective),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      var natural = painter.width;
      painter.dispose();

      // How far the letters have to be squeezed to fit. Never widened: a
      // short title stays the size it was set rather than being stretched.
      var squeeze = natural <= 0 || available <= 0 || natural <= available
          ? 1.0
          : available / natural;
      var clipped = squeeze < minCondense;
      if (clipped) squeeze = minCondense;

      Widget words(TextStyle style) => Text(
            _stripped,
            style: style,
            maxLines: 1,
            softWrap: false,
            overflow: clipped ? TextOverflow.ellipsis : TextOverflow.visible,
          );

      /// squeezed applies the condensing to one layer.
      ///
      /// Each layer separately, rather than the two of them together, so
      /// that what fills the letters is handed the bounds it is painted
      /// into. Filling the pair as one meant the picture covered the
      /// outline as well and the outline stopped being one; filling before
      /// the squeeze meant the shader was measured against a box the
      /// squeeze then changed. This is the arrangement that is neither.
      Widget squeezed(Widget layer) {
        if (squeeze >= 1) return layer;
        // Clipped as well as sized: a Transform does not clip, and the box
        // inside it is deliberately wider than the room.
        return ClipRect(
          child: SizedBox(
            width: available,
            child: Transform(
              alignment: within,
              transform: Matrix4.diagonal3Values(squeeze, 1, 1),
              child: SizedBox(width: available / squeeze, child: layer),
            ),
          ),
        );
      }

      var shader = _shaderFor(style, _fill);
      Widget fill = squeezed(words(painted));
      if (shader != null) {
        fill = ShaderMask(
            blendMode: BlendMode.srcIn, shaderCallback: shader, child: fill);
      }

      Widget out = fill;

      if (style.outline > 0) {
        // Drawn underneath rather than over: a stroke sits half inside the
        // letter, so painting it on top would eat into the fill and thin
        // everything out. Underneath, only the outer half shows, which is
        // what an outline is.
        var strokeStyle = painted.copyWith(
          color: null,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = style.outline
            ..strokeJoin = StrokeJoin.round
            ..color = style.outlineGradient.isNotEmpty
                ? Colors.white
                : (style.outlineColor ?? theme.colors.onSurface),
        );
        Widget stroke = words(strokeStyle);
        if (style.outlineGradient.isNotEmpty) {
          stroke = ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => LinearGradient(
                    colors: style.outlineGradient)
                .createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
            child: stroke,
          );
        }
        out = Stack(children: [squeezed(stroke), fill]);
      }

      if (style.background != null ||
          (style.border != null && style.borderWidth > 0) ||
          style.padding > 0) {
        out = Container(
          padding: EdgeInsets.symmetric(
              horizontal: style.padding, vertical: style.padding / 2),
          decoration: BoxDecoration(
            color: style.background,
            borderRadius: BorderRadius.circular(style.radius),
            border: style.border != null && style.borderWidth > 0
                ? Border.all(color: style.border!, width: style.borderWidth)
                : null,
          ),
          child: out,
        );
      }

      // Deliberately not wrapped in an Align: an Align fills the room it is
      // given, and a cell that did that took the whole of its half of the
      // row -- which put the gap after it wherever the half ended rather
      // than beside the words. Where a title sits is the row's business;
      // this only decides how wide the words are.
      return out;
    });
  }
}

/// _shaderFor is what fills the letters: a run of colours, a picture, or
/// nothing, in that order of preference.
Shader Function(Rect)? _shaderFor(HeaderTextStyle style, ui.Image? fill) {
  if (style.gradient.isNotEmpty) {
    return (bounds) => LinearGradient(colors: style.gradient)
        .createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height));
  }
  var picture = fill;
  if (picture == null || picture.width == 0 || picture.height == 0) {
    return null;
  }
  return (bounds) {
    // Covered, not stretched: the larger of the two ratios, so the picture
    // fills the words on both axes whatever shape it is, and the overspill
    // is centred rather than falling off one side.
    //
    // Scaling each axis to its own ratio distorts the picture, and any
    // scaling that leaves a gap shows through as nothing at all -- srcIn
    // keeps only what the shader paints, so a letter over an uncovered
    // patch disappears rather than falling back to a colour.
    var scale = (bounds.width / picture.width)
        .clamp(bounds.height / picture.height, double.infinity);
    var dx = (bounds.width - picture.width * scale) / 2;
    var dy = (bounds.height - picture.height * scale) / 2;
    return ImageShader(
      picture,
      TileMode.clamp,
      TileMode.clamp,
      (Matrix4.identity()
            ..translateByDouble(dx, dy, 0, 1)
            ..scaleByDouble(scale, scale, 1, 1))
          .storage,
    );
  };
}
