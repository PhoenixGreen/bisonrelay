import 'package:bruig/theming_system/model/area_sides.dart';
import 'package:bruig/theming_system/model/button_style.dart';
import 'package:bruig/theming_system/model/markdown_style.dart';
import 'package:flutter/material.dart';

// markdown_rules.dart is what a Markdown guide says about each kind of thing
// on a page: its text, its pictures, its columns, its galleries, its
// banners, its navigation bars and its cards.
//
// One rule per kind, each a plain value with its own JSON. Split out of
// markdown_style.dart, which held them alongside the guide that collects
// them and had grown past fourteen hundred lines -- and the banner's rules
// are the ones still growing.
//
// Re-exported by markdown_style.dart, so nothing importing that has to know
// this file exists.

/// The bounds every number in a guide is held to.
///
/// Public because the rules that enforce them live here and the guide that
/// collects those rules lives next door.
///
/// These are what stop a guide being a way to shout or to hide. Text cannot
/// be scaled to nothing or to a size that pushes the rest of a conversation
/// off the screen, and a line cannot be crushed to overlap the one above it.
/// asDouble reads a number out of stored JSON, and null out of anything
/// else -- a guide saved by an older version, or edited by hand.
double? asDouble(Object? v) => v is num ? v.toDouble() : null;

const minScale = 0.6;
const maxScale = 3.0;
const minLineHeight = 0.9;
const maxLineHeight = 3.0;

/// TextRule is one element's text: everything a TextStyle can carry, in the
/// bounded form a guide is allowed to say it.
class TextRule {
  /// scale multiplies the theme's own size for this element rather than
  /// replacing it. A guide written against a 14-point body still reads
  /// correctly for someone who has set their text larger.
  final double scale;
  final MarkdownInk ink;
  final MarkdownFont font;
  final bool? bold;
  final bool? italic;

  /// lineHeight is a multiple of the font size, or null to leave it alone.
  /// The single largest lever on whether a long post is comfortable.
  final double? lineHeight;
  final double? letterSpacing;
  final bool? underline;

  const TextRule({
    this.scale = 1.0,
    this.ink = MarkdownInk.inherit,
    this.font = MarkdownFont.inherit,
    this.bold,
    this.italic,
    this.lineHeight,
    this.letterSpacing,
    this.underline,
  });

  TextRule copyWith({
    double? scale,
    MarkdownInk? ink,
    MarkdownFont? font,
    bool? bold,
    bool? italic,
    double? lineHeight,
    double? letterSpacing,
    bool? underline,
  }) =>
      TextRule(
        scale: scale ?? this.scale,
        ink: ink ?? this.ink,
        font: font ?? this.font,
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        lineHeight: lineHeight ?? this.lineHeight,
        letterSpacing: letterSpacing ?? this.letterSpacing,
        underline: underline ?? this.underline,
      );

  /// applyTo folds this rule onto the theme's own style for the element.
  ///
  /// Onto rather than instead of: anything the guide says nothing about is
  /// left as the reader's theme had it.
  TextStyle applyTo(TextStyle base, Color Function(MarkdownRole) roleColor,
      {Color? Function(int)? paletteColor}) {
    // Resolved once and used for the underline as well as the text.
    //
    // An underline with no colour of its own is drawn in whatever
    // decorationColor the style carries, and Material's own text styles set
    // that to the body colour. flutter_markdown builds a link's style by
    // merging the `a` style onto the paragraph's, so a link that named a
    // colour got that colour for its letters and the body's for the line
    // under them -- an underline in a visibly different colour from the text
    // it underlines.
    var color =
        ink.resolve(roleColor, paletteColor: paletteColor) ?? base.color;
    return base.copyWith(
      // A rule that asks for no change in size, applied to a style that
      // names none, states none either -- so an inline run left at 100%
      // stays whatever the text around it is. Anything else would give a
      // bold word inside a heading a size of its own.
      fontSize: base.fontSize == null && scale == 1.0
          ? null
          : (base.fontSize ?? 14) * scale.clamp(minScale, maxScale),
      color: color,
      decorationColor: color,
      fontFamily: font.family ?? base.fontFamily,
      fontWeight: bold == null
          ? base.fontWeight
          : (bold! ? FontWeight.w700 : FontWeight.w400),
      fontStyle: italic == null
          ? base.fontStyle
          : (italic! ? FontStyle.italic : FontStyle.normal),
      height: lineHeight?.clamp(minLineHeight, maxLineHeight) ?? base.height,
      letterSpacing: letterSpacing?.clamp(-1.0, 4.0) ?? base.letterSpacing,
      decoration: underline == null
          ? base.decoration
          : (underline! ? TextDecoration.underline : TextDecoration.none),
    );
  }

  Map<String, Object?> toJson() => {
        if (scale != 1.0) "scale": scale,
        if (!ink.isInherit) "ink": ink.toJson(),
        if (font != MarkdownFont.inherit) "font": font.name,
        if (bold != null) "bold": bold,
        if (italic != null) "italic": italic,
        if (lineHeight != null) "lineHeight": lineHeight,
        if (letterSpacing != null) "letterSpacing": letterSpacing,
        if (underline != null) "underline": underline,
      };

  static TextRule fromJson(Map<String, Object?> json) => TextRule(
        scale: asDouble(json["scale"]) ?? 1.0,
        ink: MarkdownInk.fromJson(json["ink"]),
        font: MarkdownFont.values.firstWhere((f) => f.name == json["font"],
            orElse: () => MarkdownFont.inherit),
        bold: json["bold"] as bool?,
        italic: json["italic"] as bool?,
        lineHeight: asDouble(json["lineHeight"]),
        letterSpacing: asDouble(json["letterSpacing"]),
        underline: json["underline"] as bool?,
      );
}

/// ImageRule is how an embedded picture is drawn.
///
/// Not part of MarkdownStyleSheet, which has nothing to say about pictures --
/// its `img` entry styles the alt text. These are read by the embed builder
/// this app supplies itself.
class ImageRule {
  /// widthPercent of the column, 10 to 100.
  final double widthPercent;
  final double cornerRadius;
  final double borderWidth;
  final MarkdownInk borderInk;
  final MarkdownAlign align;

  /// gap above and below, in logical pixels.
  final double gap;

  const ImageRule({
    this.widthPercent = 100,
    this.cornerRadius = 0,
    this.borderWidth = 0,
    this.borderInk = const MarkdownInk.of(MarkdownRole.outline),
    this.align = MarkdownAlign.left,
    this.gap = 8,
  });

  ImageRule copyWith({
    double? widthPercent,
    double? cornerRadius,
    double? borderWidth,
    MarkdownInk? borderInk,
    MarkdownAlign? align,
    double? gap,
  }) =>
      ImageRule(
        widthPercent: widthPercent ?? this.widthPercent,
        cornerRadius: cornerRadius ?? this.cornerRadius,
        borderWidth: borderWidth ?? this.borderWidth,
        borderInk: borderInk ?? this.borderInk,
        align: align ?? this.align,
        gap: gap ?? this.gap,
      );

  double get boundedWidth => widthPercent.clamp(10, 100);
  double get boundedRadius => cornerRadius.clamp(0, 48);
  double get boundedBorder => borderWidth.clamp(0, 8);

  // Compared by value, not by identity.
  //
  // MarkdownArea decides whether a piece of markdown needs a guide at all by
  // asking whether the rules differ from the plain ones, and chat relies on
  // the answer being no. Without this, two ImageRules holding identical
  // numbers were never equal -- and AreaStyle.markdownGuide rebuilds the
  // rule every time it is read, so the answer was always "different" and
  // chat was quietly being drawn with a post's picture rules.
  @override
  bool operator ==(Object other) =>
      other is ImageRule &&
      other.widthPercent == widthPercent &&
      other.cornerRadius == cornerRadius &&
      other.borderWidth == borderWidth &&
      other.borderInk.toJson() == borderInk.toJson() &&
      other.align == align &&
      other.gap == gap;

  @override
  int get hashCode =>
      Object.hash(widthPercent, cornerRadius, borderWidth, align, gap);

  Map<String, Object?> toJson() => {
        "widthPercent": widthPercent,
        "cornerRadius": cornerRadius,
        "borderWidth": borderWidth,
        if (!borderInk.isInherit) "borderInk": borderInk.toJson(),
        "align": align.name,
        "gap": gap,
      };

  static ImageRule fromJson(Map<String, Object?> json) => ImageRule(
        widthPercent: asDouble(json["widthPercent"]) ?? 100,
        cornerRadius: asDouble(json["cornerRadius"]) ?? 0,
        borderWidth: asDouble(json["borderWidth"]) ?? 0,
        borderInk: MarkdownInk.fromJson(json["borderInk"]),
        align: MarkdownAlign.values.firstWhere((a) => a.name == json["align"],
            orElse: () => MarkdownAlign.left),
        gap: asDouble(json["gap"]) ?? 8,
      );
}

/// ColumnRule is how a run of columns is laid out.
///
/// Markdown has no columns of its own, so they are a block syntax this app
/// adds -- see ColumnsBlockSyntax. What a guide gets to say about them is the
/// space between them and the width below which they stop being columns at
/// all, which are the only two decisions that are about the page rather than
/// about the writing.
class ColumnRule {
  /// gap is the space between one column and the next.
  final double gap;

  /// stackBelow is the narrowest a column may be before the run gives up and
  /// stacks them one above another.
  ///
  /// Not optional and not a screen size: the same post is read in a window a
  /// third the width of somebody else's, and three columns of nine
  /// characters each is not a layout. Below this width they become what they
  /// would have been without the markup, which is the one reading that is
  /// always legible.
  final double stackBelow;

  /// The box the run of columns is drawn in: space inside it, space around
  /// it, and the line between the two.
  ///
  /// Around the run as a whole, not around each column. A border on every
  /// column is a row of boxes; a border round the outside is a block with
  /// columns in it, which is what columns are. What separates one column
  /// from the next is [dividerWidth], and it is deliberately a different
  /// setting -- a rule down the middle usually reads better when it is not
  /// the same weight as the frame, and most of the time there is no frame at
  /// all.
  ///
  /// Each is a single figure with an optional per-side split beside it,
  /// which is the form every other spacing setting in the theme editor
  /// takes. Null means "not split", so a guide that never touched the four
  /// is stored as small as it was before they existed.
  final double padding;
  final SideValues? paddingSides;
  final double margin;
  final SideValues? marginSides;
  final double borderWidth;
  final SideValues? borderWidthSides;
  final MarkdownInk borderInk;
  final double radius;
  final SideValues? radiusSides;

  /// dividerWidth is the rule drawn down the middle of the gap between one
  /// column and the next, or zero for none.
  ///
  /// One line between each pair, not a border on each column: two adjacent
  /// borders make a double line with a channel down the middle of it, which
  /// is the thing that looked wrong.
  final double dividerWidth;
  final MarkdownInk dividerInk;

  const ColumnRule({
    this.gap = 16,
    this.stackBelow = 220,
    this.padding = 0,
    this.paddingSides,
    this.margin = 0,
    this.marginSides,
    this.borderWidth = 0,
    this.borderWidthSides,
    this.borderInk = const MarkdownInk.of(MarkdownRole.outline),
    this.radius = 0,
    this.radiusSides,
    this.dividerWidth = 0,
    this.dividerInk = const MarkdownInk.of(MarkdownRole.outline),
  });

  double get boundedGap => gap.clamp(0, 64);
  double get boundedStackBelow => stackBelow.clamp(80, 480);

  /// The four resolved values for each setting: the split when there is one,
  /// otherwise the single figure all round.
  SideValues get paddings =>
      paddingSides ?? SideValues.all(padding.clamp(0, 64));
  SideValues get margins => marginSides ?? SideValues.all(margin.clamp(0, 64));
  SideValues get borderWidths =>
      borderWidthSides ?? SideValues.all(borderWidth.clamp(0, 12));
  SideValues get radii => radiusSides ?? SideValues.all(radius.clamp(0, 48));
  double get boundedDivider => dividerWidth.clamp(0, 12);

  ColumnRule copyWith({
    double? gap,
    double? stackBelow,
    double? padding,
    SideValues? paddingSides,
    bool clearPaddingSides = false,
    double? margin,
    SideValues? marginSides,
    bool clearMarginSides = false,
    double? borderWidth,
    SideValues? borderWidthSides,
    bool clearBorderWidthSides = false,
    MarkdownInk? borderInk,
    double? radius,
    SideValues? radiusSides,
    bool clearRadiusSides = false,
    double? dividerWidth,
    MarkdownInk? dividerInk,
  }) =>
      ColumnRule(
        gap: gap ?? this.gap,
        stackBelow: stackBelow ?? this.stackBelow,
        padding: padding ?? this.padding,
        paddingSides:
            clearPaddingSides ? null : (paddingSides ?? this.paddingSides),
        margin: margin ?? this.margin,
        marginSides:
            clearMarginSides ? null : (marginSides ?? this.marginSides),
        borderWidth: borderWidth ?? this.borderWidth,
        borderWidthSides: clearBorderWidthSides
            ? null
            : (borderWidthSides ?? this.borderWidthSides),
        borderInk: borderInk ?? this.borderInk,
        radius: radius ?? this.radius,
        radiusSides:
            clearRadiusSides ? null : (radiusSides ?? this.radiusSides),
        dividerWidth: dividerWidth ?? this.dividerWidth,
        dividerInk: dividerInk ?? this.dividerInk,
      );

  Map<String, Object?> toJson() => {
        "gap": gap,
        "stackBelow": stackBelow,
        if (padding != 0) "padding": padding,
        if (paddingSides != null) "paddingSides": paddingSides!.toJson(),
        if (margin != 0) "margin": margin,
        if (marginSides != null) "marginSides": marginSides!.toJson(),
        if (borderWidth != 0) "borderWidth": borderWidth,
        if (borderWidthSides != null)
          "borderWidthSides": borderWidthSides!.toJson(),
        if (!borderInk.isInherit) "borderInk": borderInk.toJson(),
        if (radius != 0) "radius": radius,
        if (radiusSides != null) "radiusSides": radiusSides!.toJson(),
        if (dividerWidth != 0) "dividerWidth": dividerWidth,
        if (!dividerInk.isInherit) "dividerInk": dividerInk.toJson(),
      };

  static ColumnRule fromJson(Map<String, Object?> json) => ColumnRule(
        gap: asDouble(json["gap"]) ?? 16,
        stackBelow: asDouble(json["stackBelow"]) ?? 220,
        padding: asDouble(json["padding"]) ?? 0,
        paddingSides: SideValues.fromJson(json["paddingSides"]),
        margin: asDouble(json["margin"]) ?? 0,
        marginSides: SideValues.fromJson(json["marginSides"]),
        borderWidth: asDouble(json["borderWidth"]) ?? 0,
        borderWidthSides: SideValues.fromJson(json["borderWidthSides"]),
        borderInk: json.containsKey("borderInk")
            ? MarkdownInk.fromJson(json["borderInk"])
            : const MarkdownInk.of(MarkdownRole.outline),
        radius: asDouble(json["radius"]) ?? 0,
        radiusSides: SideValues.fromJson(json["radiusSides"]),
        dividerWidth: asDouble(json["dividerWidth"]) ?? 0,
        dividerInk: json.containsKey("dividerInk")
            ? MarkdownInk.fromJson(json["dividerInk"])
            : const MarkdownInk.of(MarkdownRole.outline),
      );

  @override
  bool operator ==(Object other) =>
      other is ColumnRule &&
      other.gap == gap &&
      other.stackBelow == stackBelow &&
      other.padding == padding &&
      other.paddingSides == paddingSides &&
      other.margin == margin &&
      other.marginSides == marginSides &&
      other.borderWidth == borderWidth &&
      other.borderWidthSides == borderWidthSides &&
      other.borderInk.toJson() == borderInk.toJson() &&
      other.radius == radius &&
      other.radiusSides == radiusSides &&
      other.dividerWidth == dividerWidth &&
      other.dividerInk.toJson() == dividerInk.toJson();

  @override
  int get hashCode => Object.hash(
      gap,
      stackBelow,
      padding,
      paddingSides,
      margin,
      marginSides,
      borderWidth,
      borderWidthSides,
      radius,
      radiusSides,
      dividerWidth);
}

/// GridRule is how a gallery is laid out -- see GridBlockSyntax.
///
/// Deliberately its own rule rather than borrowing ColumnRule. The two look
/// alike and are not: a run of columns is one piece of writing shared out,
/// where the gap is a reading gutter, while a gallery is separate pictures
/// side by side, where the gap is the space between two things. Setting one
/// should not move the other.
///
/// Only the decisions that are about the page rather than the writing: how
/// far apart the cells sit, how many across when the writer did not say, and
/// the width below which side-by-side stops being a layout.
class GridRule {
  /// gap is the space between one cell and the next, across and down.
  final double gap;

  /// columns is how many across a bare --grid-- is, when the writer did not
  /// write --grid[n]--.
  final int columns;

  /// stackBelow is the narrowest a cell may be before the gallery gives up
  /// and stacks the pictures one above another.
  ///
  /// The same reasoning as ColumnRule.stackBelow: the same page is read in a
  /// window a third the width of somebody else's, and four pictures across
  /// at thumbnail size is not a gallery.
  final double stackBelow;

  const GridRule({
    this.gap = 12,
    this.columns = 2,
    this.stackBelow = 180,
  });

  /// boundedGap keeps a guide from setting a gap that swallows the page.
  double get boundedGap => gap.clamp(0, 96);

  /// boundedColumns keeps the default inside what GridBlockSyntax accepts.
  int get boundedColumns => columns.clamp(1, 4);

  double get boundedStackBelow => stackBelow.clamp(0, 600);

  GridRule copyWith({double? gap, int? columns, double? stackBelow}) =>
      GridRule(
        gap: gap ?? this.gap,
        columns: columns ?? this.columns,
        stackBelow: stackBelow ?? this.stackBelow,
      );

  Map<String, Object?> toJson() => {
        "gap": gap,
        "columns": columns,
        "stackBelow": stackBelow,
      };

  static GridRule fromJson(Map<String, Object?> json) => GridRule(
        gap: (json["gap"] as num?)?.toDouble() ?? 12,
        columns: (json["columns"] as num?)?.toInt() ?? 2,
        stackBelow: (json["stackBelow"] as num?)?.toDouble() ?? 180,
      );

  @override
  int get hashCode => Object.hash(gap, columns, stackBelow);

  @override
  bool operator ==(Object other) =>
      other is GridRule &&
      other.gap == gap &&
      other.columns == columns &&
      other.stackBelow == stackBelow;
}

/// HeaderRule is how a page's banner is drawn -- see HeaderBlockSyntax.
///
/// Only what is about the page rather than the writing: how tall a banner is
/// when the writer did not say, how far its contents sit from its edges, how
/// rounded it is, and how much the picture behind is muted so writing on top
/// stays readable.
class HeaderRule {
  /// height is the tallest a header is when the writer did not say.
  final double height;

  /// padding is the space between the banner's edge and what is in it.
  final double padding;
  final double radius;

  /// gap separates the rows inside a banner -- the bar from the title, the
  /// title from the description.
  final double gap;

  /// scrim is how much of the surface colour is laid over the picture, from
  /// 0 for none to 1 for opaque.
  ///
  /// A background chosen for how it looks is rarely chosen for how legible
  /// white text is on it, and the writer cannot know what colour the reader
  /// reads in. This is the reader's answer to that.
  final double scrim;

  /// fullSizeAt is the width a banner is drawn at the sizes it was written
  /// with. Narrower than this and the whole banner scales down together.
  ///
  /// Everything in a banner is sized from its rows, so scaling the rows
  /// scales the writing and the pictures with them -- which is what keeps a
  /// logo and a title looking the size they were meant to be. Without it the
  /// rows stayed the height they were asked for however little room there
  /// was, and a title had to absorb the whole difference by condensing until
  /// it was cut.
  ///
  /// Only ever down. A banner on a wide screen is the size it was written,
  /// not a bigger one.
  final double fullSizeAt;

  /// smallestScale is as far down as that goes. Past it a banner has stopped
  /// being legible rather than being smaller.
  final double smallestScale;

  const HeaderRule({
    this.height = 220,
    this.fullSizeAt = 800,
    this.smallestScale = 0.5,
    this.padding = 20,
    this.radius = 8,
    this.gap = 12,
    this.scrim = 0.35,
  });

  double get boundedHeight => height.clamp(40, 600);
  double get boundedPadding => padding.clamp(0, 64);
  double get boundedRadius => radius.clamp(0, 48);
  double get boundedGap => gap.clamp(0, 48);
  double get boundedFullSizeAt => fullSizeAt.clamp(200, 2000);
  double get boundedSmallestScale => smallestScale.clamp(0.2, 1);

  /// scaleFor is how much of its written size a banner is drawn at, in the
  /// room it has.
  double scaleFor(double available) =>
      (available / boundedFullSizeAt).clamp(boundedSmallestScale, 1.0);

  HeaderRule copyWith({
    double? height,
    double? fullSizeAt,
    double? smallestScale,
    double? padding,
    double? radius,
    double? gap,
    double? scrim,
  }) =>
      HeaderRule(
        height: height ?? this.height,
        fullSizeAt: fullSizeAt ?? this.fullSizeAt,
        smallestScale: smallestScale ?? this.smallestScale,
        padding: padding ?? this.padding,
        radius: radius ?? this.radius,
        gap: gap ?? this.gap,
        scrim: scrim ?? this.scrim,
      );

  Map<String, Object?> toJson() => {
        "height": height,
        "fullSizeAt": fullSizeAt,
        "smallestScale": smallestScale,
        "padding": padding,
        "radius": radius,
        "gap": gap,
        "scrim": scrim,
      };

  static HeaderRule fromJson(Map<String, Object?> json) => HeaderRule(
        height: (json["height"] as num?)?.toDouble() ?? 220,
        padding: (json["padding"] as num?)?.toDouble() ?? 20,
        radius: (json["radius"] as num?)?.toDouble() ?? 8,
        gap: (json["gap"] as num?)?.toDouble() ?? 12,
        scrim: (json["scrim"] as num?)?.toDouble() ?? 0.35,
      );

  @override
  int get hashCode =>
      Object.hash(height, padding, radius, gap, scrim, fullSizeAt,
          smallestScale);

  @override
  bool operator ==(Object other) =>
      other is HeaderRule && other.toJson().toString() == toJson().toString();
}

/// NavRule is how a bar of links is drawn -- see NavBlockSyntax.
///
/// The look is the reader's, the shape is the writer's: --nav[pills]-- says
/// what kind of bar it is, and this says what that kind looks like here.
class NavRule {
  final double gap;

  /// padding is inside each link, which is what gives a pill or a box its
  /// size. Zero for a plain bar, where the links are just words.
  final double padding;
  final double radius;

  /// borderWidth is the line around a boxed link, or under an underlined
  /// one.
  final double borderWidth;

  /// ink is the colour of a link in the bar.
  ///
  /// Inherit by default, which means the guide's own link colour -- so a bar
  /// looks like the rest of the writing until somebody says otherwise, and
  /// the setting reads "Theme default" rather than a colour nobody chose.
  final MarkdownInk ink;

  /// hover is what a link becomes under the pointer, and [active] what the
  /// link to the page already being read looks like. Both inherit by
  /// default, which leaves a bar that does neither.
  final MarkdownInk hover;
  final MarkdownInk active;

  /// background fills the bar itself, behind the links.
  final MarkdownInk background;

  /// fullWidth runs that background the whole width of the banner rather
  /// than only under the links. Only meaningful in a row flush to an edge,
  /// where a bar is being used as a strip across the top or bottom.
  final bool fullWidth;

  const NavRule({
    this.gap = 14,
    this.padding = 8,
    this.radius = 6,
    this.borderWidth = 1,
    this.ink = MarkdownInk.inherit,
    this.hover = MarkdownInk.inherit,
    this.active = MarkdownInk.inherit,
    this.background = MarkdownInk.inherit,
    this.fullWidth = true,
  });

  double get boundedGap => gap.clamp(0, 48);
  double get boundedPadding => padding.clamp(0, 32);
  double get boundedRadius => radius.clamp(0, 32);
  double get boundedBorder => borderWidth.clamp(0, 8);

  NavRule copyWith({
    double? gap,
    double? padding,
    double? radius,
    double? borderWidth,
    MarkdownInk? ink,
    MarkdownInk? hover,
    MarkdownInk? active,
    MarkdownInk? background,
    bool? fullWidth,
  }) =>
      NavRule(
        gap: gap ?? this.gap,
        padding: padding ?? this.padding,
        radius: radius ?? this.radius,
        borderWidth: borderWidth ?? this.borderWidth,
        ink: ink ?? this.ink,
        hover: hover ?? this.hover,
        active: active ?? this.active,
        background: background ?? this.background,
        fullWidth: fullWidth ?? this.fullWidth,
      );

  Map<String, Object?> toJson() => {
        "gap": gap,
        "padding": padding,
        "radius": radius,
        "borderWidth": borderWidth,
        "ink": ink.toJson(),
        "hover": hover.toJson(),
        "active": active.toJson(),
        "background": background.toJson(),
        "fullWidth": fullWidth,
      };

  static NavRule fromJson(Map<String, Object?> json) => NavRule(
        gap: (json["gap"] as num?)?.toDouble() ?? 14,
        padding: (json["padding"] as num?)?.toDouble() ?? 8,
        radius: (json["radius"] as num?)?.toDouble() ?? 6,
        borderWidth: (json["borderWidth"] as num?)?.toDouble() ?? 1,
        ink: _ink(json["ink"]),
        hover: _ink(json["hover"]),
        active: _ink(json["active"]),
        background: _ink(json["background"]),
        fullWidth: json["fullWidth"] as bool? ?? true,
      );

  /// _ink reads one saved colour.
  ///
  /// Handed straight to MarkdownInk, which knows all three shapes it takes:
  /// a map for a colour picked out of the palette, a string for one of the
  /// guide's own roles, and nothing at all for inherit. Guarding on the map
  /// alone -- which is what this did -- threw away every role, so a bar
  /// whose colour was a role came back as though nothing had been set.
  static MarkdownInk _ink(Object? v) => MarkdownInk.fromJson(v);

  @override
  int get hashCode => Object.hash(
      gap, padding, radius, borderWidth, ink, hover, active, background,
      fullWidth);

  @override
  bool operator ==(Object other) =>
      other is NavRule && other.toJson().toString() == toJson().toString();
}

/// CardRule is how a callout or a card is drawn.
///
/// A callout and a card are the same thing with a different amount filled in:
/// a title, some text, an icon and a button, any of which may be left out. So
/// there is one set of rules for both rather than two that would drift apart.
class CardRule {
  /// gap is the space between one card and the next in a grid of them.
  final double gap;

  final double padding;
  final SideValues? paddingSides;
  final MarkdownInk background;
  final double borderWidth;
  final MarkdownInk borderInk;
  final double radius;

  /// iconSize is the icon itself; iconBackground is the disc behind it, or
  /// inherit for no disc at all.
  final double iconSize;
  final MarkdownInk iconInk;
  final MarkdownInk iconBackground;

  final TextRule title;
  final TextRule text;

  /// button is which of the app's five button designs a card's button is
  /// drawn as -- see ButtonRole and the Buttons theme area.
  ///
  /// A choice rather than its own set of colours: a card sits in a post, in
  /// the same app as every other button, and a button that looked like
  /// nothing else in it would read as part of the writing rather than as
  /// something to press. Plain is the default because that is the button
  /// this was hardcoded to before it could be chosen.
  final ButtonRole button;

  const CardRule({
    this.gap = 16,
    this.padding = 16,
    this.paddingSides,
    this.background = const MarkdownInk.of(MarkdownRole.raised),
    this.borderWidth = 0,
    this.borderInk = const MarkdownInk.of(MarkdownRole.outline),
    this.radius = 12,
    this.iconSize = 28,
    this.iconInk = const MarkdownInk.of(MarkdownRole.accent),
    this.iconBackground = MarkdownInk.inherit,
    this.title = const TextRule(scale: 1.3, bold: true),
    this.text = const TextRule(ink: MarkdownInk.of(MarkdownRole.muted)),
    this.button = ButtonRole.plain,
  });

  double get boundedGap => gap.clamp(0, 64);
  double get boundedRadius => radius.clamp(0, 48);
  double get boundedBorder => borderWidth.clamp(0, 12);
  double get boundedIconSize => iconSize.clamp(12, 96);
  SideValues get paddings =>
      paddingSides ?? SideValues.all(padding.clamp(0, 64));

  CardRule copyWith({
    double? gap,
    double? padding,
    SideValues? paddingSides,
    bool clearPaddingSides = false,
    MarkdownInk? background,
    double? borderWidth,
    MarkdownInk? borderInk,
    double? radius,
    double? iconSize,
    MarkdownInk? iconInk,
    MarkdownInk? iconBackground,
    TextRule? title,
    TextRule? text,
    ButtonRole? button,
  }) =>
      CardRule(
        gap: gap ?? this.gap,
        padding: padding ?? this.padding,
        paddingSides:
            clearPaddingSides ? null : (paddingSides ?? this.paddingSides),
        background: background ?? this.background,
        borderWidth: borderWidth ?? this.borderWidth,
        borderInk: borderInk ?? this.borderInk,
        radius: radius ?? this.radius,
        iconSize: iconSize ?? this.iconSize,
        iconInk: iconInk ?? this.iconInk,
        iconBackground: iconBackground ?? this.iconBackground,
        title: title ?? this.title,
        text: text ?? this.text,
        button: button ?? this.button,
      );

  Map<String, Object?> toJson() => {
        "gap": gap,
        "padding": padding,
        if (paddingSides != null) "paddingSides": paddingSides!.toJson(),
        if (!background.isInherit) "background": background.toJson(),
        "borderWidth": borderWidth,
        if (!borderInk.isInherit) "borderInk": borderInk.toJson(),
        "radius": radius,
        "iconSize": iconSize,
        if (!iconInk.isInherit) "iconInk": iconInk.toJson(),
        if (!iconBackground.isInherit)
          "iconBackground": iconBackground.toJson(),
        "title": title.toJson(),
        "text": text.toJson(),
        if (button != ButtonRole.plain) "button": button.name,
      };

  static CardRule fromJson(Map<String, Object?> json) {
    TextRule rule(String key, TextRule fallback) {
      var v = json[key];
      return v is Map<String, Object?> ? TextRule.fromJson(v) : fallback;
    }

    return CardRule(
      gap: asDouble(json["gap"]) ?? 16,
      padding: asDouble(json["padding"]) ?? 16,
      paddingSides: SideValues.fromJson(json["paddingSides"]),
      background: json.containsKey("background")
          ? MarkdownInk.fromJson(json["background"])
          : const MarkdownInk.of(MarkdownRole.raised),
      borderWidth: asDouble(json["borderWidth"]) ?? 0,
      borderInk: json.containsKey("borderInk")
          ? MarkdownInk.fromJson(json["borderInk"])
          : const MarkdownInk.of(MarkdownRole.outline),
      radius: asDouble(json["radius"]) ?? 12,
      iconSize: asDouble(json["iconSize"]) ?? 28,
      iconInk: json.containsKey("iconInk")
          ? MarkdownInk.fromJson(json["iconInk"])
          : const MarkdownInk.of(MarkdownRole.accent),
      iconBackground: MarkdownInk.fromJson(json["iconBackground"]),
      title: rule("title", const TextRule(scale: 1.3, bold: true)),
      text:
          rule("text", const TextRule(ink: MarkdownInk.of(MarkdownRole.muted))),
      button: ButtonRole.values.firstWhere((r) => r.name == json["button"],
          orElse: () => ButtonRole.plain),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CardRule && other.toJson().toString() == toJson().toString();

  @override
  int get hashCode => toJson().toString().hashCode;
}
