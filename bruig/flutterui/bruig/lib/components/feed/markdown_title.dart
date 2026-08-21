import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';

// markdown_title.dart is how a banner's words are set.
//
// A banner's title is branding rather than reading: it is the one piece of a
// site whose look belongs to whoever wrote it, not to whoever is reading. So
// it has fields of its own, and enough of them to be worth a file -- this is
// the half of the header most likely to grow.

/// HeaderTextStyle is how a banner's writing is set.
///
/// A banner's title is branding rather than reading: it is the one piece of
/// a site whose look belongs to whoever wrote it, not to whoever is reading.
/// So these are fields on the block, unlike everything else about a page.
@immutable
class HeaderTextStyle {
  /// size in pixels, or null to match the banner -- "titlesize: fill" sets a
  /// title as tall as the space it is in, which is what makes it sit level
  /// with a logo and grow and shrink with it.
  final double? size;
  final bool fill;
  final bool bold;
  final bool italic;

  /// caps transforms the words themselves rather than drawing them
  /// differently, so what is copied out of the page is what was written.
  final String caps;
  final double tracking;
  final List<Color> gradient;
  final Color? color;
  final Color? background;
  final Color? border;
  final double borderWidth;
  final double radius;
  final double padding;

  const HeaderTextStyle({
    this.size,
    this.fill = false,
    this.bold = false,
    this.italic = false,
    this.caps = "",
    this.tracking = 0,
    this.gradient = const [],
    this.color,
    this.background,
    this.border,
    this.borderWidth = 0,
    this.radius = 0,
    this.padding = 0,
  });

  /// none is a title with nothing said about it, which is drawn the way the
  /// rest of the page is.
  bool get plain =>
      size == null &&
      !fill &&
      !bold &&
      !italic &&
      caps.isEmpty &&
      tracking == 0 &&
      gradient.isEmpty &&
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
    return HeaderTextStyle(
      size: double.tryParse(rawSize)?.clamp(8, 200),
      fill: rawSize == "fill",
      bold: (fields["titleweight"] ?? "").trim().toLowerCase() == "bold",
      italic: (fields["titleitalic"] ?? "").trim().toLowerCase() == "yes",
      caps: (fields["titlecase"] ?? "").trim().toLowerCase(),
      tracking:
          (double.tryParse(fields["titletracking"] ?? "") ?? 0).clamp(-5, 40),
      gradient: colours.length > 1 ? colours : const [],
      color: _colour(fields["titlecolor"]) ??
          (colours.length == 1 ? colours.first : null),
      background: _colour(fields["titlebackground"]),
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

/// _HeaderText draws a title.
class HeaderText extends StatelessWidget {
  final String text;
  final HeaderTextStyle style;
  final HeaderRule rule;

  /// within is where the words sit in the room the slot was given, which is
  /// what puts a right-hand title against the right edge rather than
  /// centred in its half of the banner.
  final Alignment within;

  /// fillTo is the height "titlesize: fill" fills, when there is a figure to
  /// fill: the logo's, so the two come out level. Null when the logo has no
  /// height of its own either, where filling means taking the row's -- see
  /// the stretch in slots().
  final double? fillTo;
  const HeaderText(
      {required this.text,
      required this.style,
      required this.rule,
      required this.within,
      this.fillTo});

  /// _stripped removes the heading marks a writer puts in out of habit. How
  /// large a title is set is [HeaderTextStyle.size], not how many hashes
  /// were typed -- three of them in a banner would otherwise be small.
  String get _stripped =>
      style.apply(text.replaceFirst(RegExp(r'^\s*#{1,6}\s*'), "").trim());

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var base = Theme.of(context).textTheme.headlineSmall ??
        const TextStyle(fontSize: 22);

    var painted = base.copyWith(
      fontSize: style.size,
      fontWeight: style.bold ? FontWeight.bold : base.fontWeight,
      fontStyle: style.italic ? FontStyle.italic : base.fontStyle,
      letterSpacing: style.tracking == 0 ? base.letterSpacing : style.tracking,
      // White under a gradient: the shader replaces it, and anything else
      // tints what the shader paints.
      color: style.gradient.isNotEmpty
          ? Colors.white
          : (style.color ?? theme.colors.onSurface),
    );

    Widget out = Text(_stripped, style: painted, softWrap: false);

    if (style.gradient.isNotEmpty) {
      out = ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => LinearGradient(colors: style.gradient)
            .createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
        child: out,
      );
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

    // "fill" sets a title as tall as the room it has, which is what makes it
    // sit level with a logo and grow and shrink with it.
    if (!style.fill) {
      return FittedBox(fit: BoxFit.scaleDown, alignment: within, child: out);
    }

    // Filling needs a height to fill. A FittedBox only ever scales a child
    // down into a box larger than it, and under the loose constraints a slot
    // gets there is no such box -- it simply sized itself to the words,
    // which is why "fill" did nothing at all.
    var filled = FittedBox(fit: BoxFit.contain, alignment: within, child: out);
    return fillTo == null
        // No figure to match: the row is stretched instead, so this is
        // handed a tight height and fills that.
        ? filled
        : SizedBox(height: fillTo, child: filled);
  }
}
